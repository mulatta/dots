import Cocoa

final class ComposeView: NSTextView {
    var onImagePaste: ((String) -> Void)?

    var onSend: (() -> Void)?

    // NSTextView has no placeholder API; draw one while empty. The
    // controller keeps it in sync with connection state and peer name.
    var placeholder: String = "" { didSet { needsDisplay = true } }

    override var string: String {
        get { super.string }
        set {
            super.string = newValue
            needsDisplay = true
        }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? .systemFont(ofSize: 13),
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: attributes)
    }

    // Handle Return here, before key-binding resolution —
    // StandardKeyBinding.dict has no Shift+Return entry, so by the
    // time doCommandBy fires the modifier is already lost. Any
    // modifier means "newline", bare Return means "send".
    override func keyDown(with e: NSEvent) {
        guard e.keyCode == 36 || e.keyCode == 76 else {  // Return / Enter
            super.keyDown(with: e); return
        }
        if e.modifierFlags.isDisjoint(with: [.shift, .option, .control]) {
            onSend?()
        } else {
            insertNewlineIgnoringFieldEditor(nil)
        }
    }
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) != nil { super.paste(sender); return }
        guard let img = NSImage(pasteboard: pb),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        let f = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("nostr-chat-paste-\(Int(Date().timeIntervalSince1970)).png")
        try? png.write(to: URL(fileURLWithPath: f))
        onImagePaste?(f)
    }
}
