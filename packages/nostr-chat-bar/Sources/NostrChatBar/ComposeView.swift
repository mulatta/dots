import Cocoa

final class ComposeView: NSTextView {
    var onImagePaste: ((String) -> Void)?

    var onSend: (() -> Void)?

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
