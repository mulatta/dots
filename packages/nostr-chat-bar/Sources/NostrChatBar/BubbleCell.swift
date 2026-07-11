import Cocoa

// MARK: - Bubble cell

final class BubbleCell: NSTableCellView {
    private let bubble = NSView()
    private let markdown = MarkdownBubbleView()
    private let meta = NSTextField(labelWithString: "")
    private let quote = NSTextField(labelWithString: "")
    private let img = NSImageView()
    private let reply = NSButton()
    private let copy = NSButton()
    var onReply: (() -> Void)?
    var onCopy: (() -> Void)?
    private var lead: NSLayoutConstraint!
    private var trail: NSLayoutConstraint!
    private var replyLead: NSLayoutConstraint!
    private var replyTrail: NSLayoutConstraint!
    private var copyLead: NSLayoutConstraint!
    private var copyTrail: NSLayoutConstraint!

    override init(frame f: NSRect) { super.init(frame: f); build() }
    required init?(coder: NSCoder) { fatalError() }

    private let stack = NSStackView()

    private func build() {
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 12
        meta.font = .systemFont(ofSize: 9)
        meta.textColor = .tertiaryLabelColor
        quote.font = .systemFont(ofSize: 11)
        quote.lineBreakMode = .byTruncatingTail
        quote.isHidden = true
        for button in [reply, copy] {
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.contentTintColor = .secondaryLabelColor
            button.alphaValue = 0
            button.translatesAutoresizingMaskIntoConstraints = false
            button.imageScaling = .scaleProportionallyDown
        }
        reply.target = self
        reply.action = #selector(replyClicked)
        copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "copy message")
        copy.target = self
        copy.action = #selector(copyClicked)
        img.imageScaling = .scaleProportionallyUpOrDown
        img.wantsLayer = true
        img.layer?.cornerRadius = 8
        img.layer?.masksToBounds = true

        for v in [quote, img, markdown, meta] { stack.addArrangedSubview(v) }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(stack)
        addSubview(bubble)
        addSubview(reply)
        addSubview(copy)
        // Hover-reveal in the gutter beside the bubble — same UX as the
        // QML version. NSTrackingArea on the row toggles alpha.
        let track = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(track)

        lead = bubble.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        trail = bubble.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        replyLead = reply.leadingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: 6)
        replyTrail = reply.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -6)
        copyLead = copy.leadingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: 6)
        copyTrail = copy.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -6)
        // Padding via explicit constants instead of stack.edgeInsets:
        // NSStackView only honours edgeInsets along its own axis; the
        // perpendicular alignment guide it pins children to is the
        // stack's raw edge, so the right inset silently collapsed to 0
        // on .trailing-aligned ("mine") bubbles.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.78),
            img.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            img.heightAnchor.constraint(lessThanOrEqualToConstant: 240),
            reply.centerYAnchor.constraint(equalTo: bubble.centerYAnchor, constant: -11),
            reply.widthAnchor.constraint(equalToConstant: 20),
            copy.centerYAnchor.constraint(equalTo: bubble.centerYAnchor, constant: 11),
            copy.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    @objc private func replyClicked() { onReply?() }
    @objc private func copyClicked() { onCopy?() }
    override func mouseEntered(with _: NSEvent) {
        reply.animator().alphaValue = 1
        copy.animator().alphaValue = 1
    }
    override func mouseExited(with _: NSEvent) {
        reply.animator().alphaValue = 0
        copy.animator().alphaValue = 0
    }

    func configure(_ r: Row, ago: String, quoted: String?,
                   searchHit: Bool = false, searchCurrent: Bool = false) {
        bubble.layer?.borderWidth = searchHit ? 2 : 0
        bubble.layer?.borderColor = (searchCurrent
            ? NSColor.systemYellow : NSColor.systemOrange).cgColor
        // Deactivate both first — flipping one before the other can
        // briefly leave lead+trail active on a reused cell, which
        // AppKit logs as an unsatisfiable-constraint storm.
        lead.isActive = false; trail.isActive = false
        replyLead.isActive = false; replyTrail.isActive = false
        copyLead.isActive = false; copyTrail.isActive = false
        lead.isActive = !r.mine; trail.isActive = r.mine
        replyLead.isActive = !r.mine; replyTrail.isActive = r.mine
        copyLead.isActive = !r.mine; copyTrail.isActive = r.mine
        // Arrow points toward the bubble it sits beside, so mirror for
        // own messages (button is in the left gutter → point right).
        reply.image = NSImage(
            systemSymbolName: r.mine ? "arrowshape.turn.up.right"
                                     : "arrowshape.turn.up.left",
            accessibilityDescription: "reply")
        stack.alignment = r.mine ? .trailing : .leading
        quote.isHidden = quoted == nil && r.replyTo.isEmpty
        quote.textColor = r.mine
            ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor
        quote.stringValue = "↳ " + (quoted.map {
            $0.count > 60 ? String($0.prefix(59)) + "…" : $0
        } ?? "…")
        let incomingBubble = NSColor(calibratedWhite: 1.0, alpha: 0.78)
        let incomingText = NSColor(calibratedWhite: 0.05, alpha: 1.0)
        let incomingMeta = NSColor(calibratedWhite: 0.25, alpha: 0.7)
        bubble.layer?.backgroundColor = (r.mine
            ? NSColor.controlAccentColor
            : incomingBubble).cgColor
        let bodyText = r.mine ? NSColor.white : incomingText
        markdown.configure(text: r.text, mine: r.mine, textColor: bodyText)
        meta.textColor = r.mine
            ? NSColor.white.withAlphaComponent(0.7) : incomingMeta
        var m = ago
        if r.mine {
            if r.tries > 0 { m += "  ⚠" }
            else if r.state == "pending" { m += "  …" }
            else if !r.ack.isEmpty { m += "  \(r.ack)" }
        }
        meta.stringValue = m
        if !r.image.isEmpty, let i = NSImage(contentsOfFile: r.image) {
            img.image = i; img.isHidden = false
        } else { img.image = nil; img.isHidden = true }
    }
}
