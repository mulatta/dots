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
}

private enum MarkdownBubbleBlocks {
    static func parse(_ text: String) -> [MarkdownBubbleBlock] {
        var blocks: [MarkdownBubbleBlock] = []
        var markdown: [String] = []
        var mermaid: [String] = []
        var inMermaid = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if inMermaid {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.mermaid(mermaid.joined(separator: "\n")))
                    mermaid.removeAll()
                    inMermaid = false
                } else {
                    mermaid.append(line)
                }
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "```mermaid" || trimmed == "~~~mermaid" {
                if !markdown.isEmpty {
                    blocks.append(.markdown(markdown.joined(separator: "\n")))
                    markdown.removeAll()
                }
                inMermaid = true
            } else {
                markdown.append(line)
            }
        }

        if inMermaid {
            markdown.append("```mermaid")
            markdown.append(contentsOf: mermaid)
        }
        if !markdown.isEmpty { blocks.append(.markdown(markdown.joined(separator: "\n"))) }
        return blocks
    }
}

private final class MermaidDiagramView: NSView {
    private static let maxContentWidth: CGFloat = 460
    private let webView: WKWebView

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.maxContentWidth, height: 280)
    }

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
            heightAnchor.constraint(equalToConstant: 280),
        ])
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html(source: source, mine: mine), baseURL: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

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
            \(mermaidScript())
            mermaid.initialize({ startOnLoad: true, theme: '\(theme)', securityLevel: 'strict' });
          </script>
        </body>
        </html>
        """
    }

    private static func mermaidScript() -> String {
        guard let source = mermaidSource() else {
            return "window.mermaid = { initialize: () => {}, run: () => {} };"
        }
        return source.replacingOccurrences(of: "</script", with: "<\\/script")
    }

    private static func mermaidSource() -> String? {
        let candidates = [
            Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
            Bundle.main.resourceURL?.appendingPathComponent("mermaid.min.js"),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("../share/nostr-chat-bar/mermaid.min.js"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/mermaid.min.js"),
        ].compactMap { $0 }
        for url in candidates {
            if let source = try? String(contentsOf: url.standardizedFileURL, encoding: .utf8) {
                return source
            }
        }
        return nil
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
