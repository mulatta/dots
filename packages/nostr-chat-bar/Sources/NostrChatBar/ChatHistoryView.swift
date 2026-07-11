import Cocoa
import WebKit

/// The message-history viewport: one persistent WKWebView hosting the
/// bundled Vue renderer. Swift stays authoritative — this view only
/// mirrors the canonical `rows` into the page and relays user intent
/// back out as validated `WebAction`s.
final class ChatHistoryView: NSView, WKScriptMessageHandler, WKNavigationDelegate {
    // Internal (not private) so harnesses and tests can observe the
    // rendered document; production code outside this file must not
    // touch it.
    let webView: WKWebView
    private var readyGate: RendererReadyGate!

    /// Validated renderer actions, minus `ready` which is handled here.
    var onAction: ((WebAction) -> Void)?
    /// Full canonical snapshot; called on every renderer `ready`.
    var snapshotProvider: (() -> [[String: Any]])?
    /// Message ID → local attachment path, resolved from canonical rows.
    var mediaPathResolver: ((String) -> String?)? {
        get { mediaHandler.resolvePath }
        set { mediaHandler.resolvePath = newValue }
    }

    private let mediaHandler = MediaSchemeHandler()

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let root = Self.rendererRoot() {
            configuration.setURLSchemeHandler(
                RendererSchemeHandler(root: root), forURLScheme: RendererSchemeHandler.scheme)
        }
        configuration.setURLSchemeHandler(mediaHandler, forURLScheme: MediaSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)

        readyGate = RendererReadyGate { [weak self] in self?.pushSnapshot() }
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self), name: "bridge")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
            webView.isInspectable = true
        #endif

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        loadRenderer()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: renderer loading

    /// The built Vite bundle: `web/` inside the .app resources, with the
    /// share/ layout as fallback for running the bare binary and an env
    /// override for development and harnesses.
    static func rendererRoot() -> URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["NOSTR_CHAT_BAR_WEB_ROOT"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("web"))
        }
        candidates.append(
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("../share/nostr-chat-bar/web").standardizedFileURL)
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path)
        }
    }

    private func loadRenderer() {
        guard Self.rendererRoot() != nil else {
            FileHandle.standardError.write(
                Data("nostr-chat-bar: web renderer assets not found\n".utf8))
            return
        }
        webView.load(URLRequest(url: RendererSchemeHandler.pageURL))
    }

    // MARK: native → renderer

    func replaceMessages(_ rows: [Row]) {
        readyGate.run { call("replaceMessages", ["messages": rows.map(\.webPayload)]) }
    }

    func upsert(_ row: Row) {
        readyGate.run { call("upsertMessage", ["message": row.webPayload]) }
    }

    func patch(id: String, fields: [String: Any]) {
        readyGate.run { call("patchMessage", ["id": id, "patch": fields]) }
    }

    func remove(id: String) {
        readyGate.run { call("removeMessage", ["id": id]) }
    }

    func setConnection(streaming: Bool, up: Int, total: Int) {
        readyGate.run {
            call(
                "setConnection",
                [
                    "status": [
                        "streaming": streaming, "relaysUp": up, "relaysTotal": total,
                    ] as [String: Any]
                ])
        }
    }

    func setSearch(query: String) {
        readyGate.run { call("setSearch", ["query": query]) }
    }

    func stepSearch(_ direction: Int) {
        readyGate.run { call("stepSearch", ["direction": direction]) }
    }

    func closeSearch() {
        readyGate.run { call("closeSearch", [:]) }
    }

    private func pushSnapshot() {
        guard let snapshot = snapshotProvider?() else { return }
        call("replaceMessages", ["messages": snapshot])
    }

    /// Structured arguments only — daemon-derived content must never be
    /// interpolated into JavaScript source.
    private func call(_ method: String, _ arguments: [String: Any]) {
        let keys = arguments.keys.sorted().joined(separator: ", ")
        webView.callAsyncJavaScript(
            "return window.nostrChat.\(method)(\(keys));",
            arguments: arguments,
            in: nil,
            in: .page
        ) { result in
            if case let .failure(error) = result {
                FileHandle.standardError.write(
                    Data("nostr-chat-bar: bridge \(method) failed: \(error)\n".utf8))
            }
        }
    }

    // MARK: renderer → native

    func userContentController(
        _: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.name == "bridge", let action = WebActionDecoder.decode(message.body)
        else { return }
        if case .ready = action {
            readyGate.becomeReady()
            return
        }
        onAction?(action)
    }

    // MARK: navigation policy

    /// The page never navigates: only the bundled index.html loads.
    /// Anchor clicks inside sanitized message HTML surface as
    /// `open-link` bridge actions, not navigations, but any WebKit-
    /// initiated navigation attempt is still refused here as defense in
    /// depth.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.request.url == RendererSchemeHandler.pageURL else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        // Swift state survives WebKit; a fresh load replays it through
        // the ready → snapshot path.
        readyGate.reset()
        loadRenderer()
    }
}
