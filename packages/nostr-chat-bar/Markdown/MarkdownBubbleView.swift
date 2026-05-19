import Cocoa
import Foundation

// MARK: - Markdown bubble rendering

final class MarkdownBubbleView: NSView {
    private let textView = MarkdownTextView(frame: .zero)

    override var intrinsicContentSize: NSSize { textView.intrinsicContentSize }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
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
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(text: String, mine: Bool, textColor: NSColor) {
        let linkTint: NSColor = mine ? .white.withAlphaComponent(0.95) : .linkColor
        textView.textStorage?.setAttributedString(MarkdownDocumentRenderer.attributedText(
            from: text,
            mine: mine,
            textColor: textColor,
            linkTint: linkTint))
        textView.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
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
