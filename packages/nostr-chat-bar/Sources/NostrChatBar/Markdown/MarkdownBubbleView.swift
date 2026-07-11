import Cocoa
import Foundation
import WebKit

// MARK: - Markdown bubble rendering

final class MarkdownBubbleView: NSView {
    private let stack = NSStackView()

    override var intrinsicContentSize: NSSize { stack.intrinsicContentSize }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(text: String, mine: Bool, textColor: NSColor) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let linkTint: NSColor = mine ? .white.withAlphaComponent(0.95) : .linkColor
        for block in MarkdownBubbleBlocks.parse(text) {
            switch block {
            case let .markdown(markdown):
                guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let textView = MarkdownTextView(frame: .zero)
                configureTextView(textView)
                textView.textStorage?.setAttributedString(MarkdownDocumentRenderer.attributedText(
                    from: markdown,
                    mine: mine,
                    textColor: textColor,
                    linkTint: linkTint))
                stack.addArrangedSubview(textView)
            case let .mermaid(source):
                stack.addArrangedSubview(MermaidDiagramView(source: source, mine: mine))
            case let .math(source):
                stack.addArrangedSubview(MathBlockView(source: source, mine: mine))
            }
        }
        invalidateIntrinsicContentSize()
    }

    private func configureTextView(_ textView: MarkdownTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.translatesAutoresizingMaskIntoConstraints = false
    }
}

private enum MarkdownBubbleBlock {
    case markdown(String)
    case mermaid(String)
    case math(String)
}

private enum MarkdownBubbleBlocks {
    static func parse(_ text: String) -> [MarkdownBubbleBlock] {
        var blocks: [MarkdownBubbleBlock] = []
        var markdown: [String] = []
        var special: [String] = []
        var specialKind: MarkdownBubbleBlockKind?

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let kind = specialKind {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if kind.closes(trimmed) {
                    blocks.append(kind.block(source: special.joined(separator: "\n")))
                    special.removeAll()
                    specialKind = nil
                } else {
                    special.append(line)
                }
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 {
                if !markdown.isEmpty {
                    blocks.append(.markdown(markdown.joined(separator: "\n")))
                    markdown.removeAll()
                }
                let body = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.math(body))
            } else if let kind = MarkdownBubbleBlockKind(opening: trimmed) {
                if !markdown.isEmpty {
                    blocks.append(.markdown(markdown.joined(separator: "\n")))
                    markdown.removeAll()
                }
                specialKind = kind
            } else {
                markdown.append(line)
            }
        }

        if let kind = specialKind {
            markdown.append(kind.openingFence)
            markdown.append(contentsOf: special)
        }
        if !markdown.isEmpty { blocks.append(.markdown(markdown.joined(separator: "\n"))) }
        return blocks
    }
}

private enum MarkdownBubbleBlockKind {
    case mermaid
    case math

    init?(opening: String) {
        switch opening {
        case "```mermaid", "~~~mermaid": self = .mermaid
        case "```math", "~~~math", "```latex", "~~~latex", "$$": self = .math
        default: return nil
        }
    }

    var openingFence: String {
        switch self {
        case .mermaid: "```mermaid"
        case .math: "$$"
        }
    }

    func closes(_ line: String) -> Bool {
        switch self {
        case .mermaid: line.hasPrefix("```") || line.hasPrefix("~~~")
        case .math: line == "$$" || line.hasPrefix("```") || line.hasPrefix("~~~")
        }
    }

    func block(source: String) -> MarkdownBubbleBlock {
        switch self {
        case .mermaid: .mermaid(source)
        case .math: .math(source)
        }
    }
}

private final class MermaidDiagramView: NSView {
    private static let maxContentWidth: CGFloat = 460
    private let webView: WKWebView

    override var intrinsicContentSize: NSSize { NSSize(width: Self.maxContentWidth, height: 280) }

    init(source: String, mine: Bool) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        configureWebView(height: 280)
        webView.loadHTMLString(Self.html(source: source, mine: mine), baseURL: ResourceLoader.baseURL())
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configureWebView(height: CGFloat) {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.maxContentWidth),
            heightAnchor.constraint(equalToConstant: height),
        ])
        webView.setValue(false, forKey: "drawsBackground")
    }

    private static func html(source: String, mine: Bool) -> String {
        let theme = mine ? "dark" : "default"
        let background = mine ? "transparent" : "rgba(255,255,255,0.0)"
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body { margin: 0; padding: 0; background: \(background); overflow: auto; }
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            .mermaid { padding: 8px; }
            svg { max-width: 100%; height: auto; }
          </style>
        </head>
        <body>
          <pre class="mermaid">\(escapeHTML(source))</pre>
          <script>
            \(ResourceLoader.script(named: "mermaid.min"))
            mermaid.initialize({ startOnLoad: true, theme: '\(theme)', securityLevel: 'strict' });
          </script>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class MathBlockView: NSView {
    private static let maxContentWidth: CGFloat = 460
    private let webView: WKWebView

    override var intrinsicContentSize: NSSize { NSSize(width: Self.maxContentWidth, height: 120) }

    init(source: String, mine: Bool) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.maxContentWidth),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html(source: source, mine: mine), baseURL: ResourceLoader.baseURL())
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func html(source: String, mine: Bool) -> String {
        let color = mine ? "#ffffff" : "#111111"
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            \(ResourceLoader.css(named: "katex.min"))
            html, body { margin: 0; padding: 0; background: transparent; color: \(color); overflow: auto; }
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 8px; }
            #math { font-size: 16px; }
          </style>
        </head>
        <body>
          <div id="math"></div>
          <script>
            \(ResourceLoader.script(named: "katex.min"))
            katex.render(\(jsonString(source)), document.getElementById('math'), { displayMode: true, throwOnError: false, trust: false });
          </script>
        </body>
        </html>
        """
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }
}

private enum ResourceLoader {
    static func script(named name: String) -> String {
        guard let source = resource(named: name, extension: "js") else {
            return "console.warn('\(name) unavailable');"
        }
        return source.replacingOccurrences(of: "</script", with: "<\\/script")
    }

    static func css(named name: String) -> String {
        resource(named: name, extension: "css") ?? ""
    }

    static func baseURL() -> URL? {
        if let resourceURL = Bundle.main.resourceURL { return resourceURL }
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("../share/nostr-chat-bar/")
            .standardizedFileURL
    }

    private static func resource(named name: String, extension ext: String) -> String? {
        let filename = "\(name).\(ext)"
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.resourceURL?.appendingPathComponent(filename),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("../share/nostr-chat-bar/\(filename)"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/\(filename)"),
        ].compactMap { $0 }
        for url in candidates {
            if let source = try? String(contentsOf: url.standardizedFileURL, encoding: .utf8) {
                return source
            }
        }
        return nil
    }
}

private final class MarkdownTextView: NSTextView {
    private static let minContentWidth: CGFloat = 220
    private static let maxContentWidth: CGFloat = 460

    override var intrinsicContentSize: NSSize {
        guard let manager = layoutManager, let container = textContainer else {
            return super.intrinsicContentSize
        }
        // Measure at the desired maximum width instead of the current bounds.
        // Reused table cells can arrive here with a stale, narrow bounds value;
        // using it feeds Auto Layout a tiny intrinsic width and turns Hangul
        // messages into vertical columns.
        container.containerSize = NSSize(width: Self.maxContentWidth,
                                         height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let naturalWidth = min(Self.maxContentWidth,
                               max(Self.minContentWidth, ceil(used.width + textContainerInset.width * 2)))
        return NSSize(width: naturalWidth,
                      height: ceil(used.height + textContainerInset.height * 2))
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }
}
