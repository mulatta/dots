import Cocoa
import WebKit

/// Persistent WebKit viewport for the bundled message renderer.
final class ChatHistoryView: NSView, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private let readyGate = RendererReadyGate()
    private var started = false
    private var searchQuery = ""

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
        let messageHandler = WeakScriptMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(messageHandler, name: "bridge")
        if let root = Self.rendererRoot() {
            configuration.setURLSchemeHandler(
                RendererSchemeHandler(root: root), forURLScheme: RendererSchemeHandler.scheme)
        }
        configuration.setURLSchemeHandler(mediaHandler, forURLScheme: MediaSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)

        messageHandler.delegate = self
        readyGate.onReady = { [weak self] in self?.pushSnapshot() }
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
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: renderer loading

    /// Finds the Vite bundle in development, app, or bare-package layouts.
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

    func start() {
        guard !started else { return }
        started = true
        loadRenderer()
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

    func upsert(_ row: Row) {
        readyGate.run { call("upsertMessage", ["message": row.webPayload]) }
    }

    func patch(id: String, fields: [String: Any]) {
        readyGate.run { call("patchMessage", ["id": id, "patch": fields]) }
    }

    func remove(id: String) {
        readyGate.run { call("removeMessage", ["id": id]) }
    }

    func setSearch(query: String) {
        searchQuery = query
        readyGate.run { call("setSearch", ["query": query]) }
    }

    func stepSearch(_ direction: Int) {
        readyGate.run { call("stepSearch", ["direction": direction]) }
    }

    func closeSearch() {
        searchQuery = ""
        readyGate.run { call("closeSearch", [:]) }
    }

    private func pushSnapshot() {
        if let snapshot = snapshotProvider?() {
            call("replaceMessages", ["messages": snapshot])
        }
        if !searchQuery.isEmpty {
            call("setSearch", ["query": searchQuery])
        }
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
        readyGate.reset()
        loadRenderer()
    }
}
