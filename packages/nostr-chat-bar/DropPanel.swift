import Cocoa

// MARK: - Drop-down panel
//
// Mimics noctalia's layer-shell card: borderless, floats above
// everything, pinned under the menubar of whichever screen the mouse
// is on, slides in/out. NSPanel + .nonactivatingPanel lets it grab key
// without stealing app focus from whatever's underneath — same UX as
// Spotlight.

final class DropPanel: NSPanel {
    // Borderless windows refuse key by default; override so the
    // TextView can actually receive typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onCancel: (() -> Void)?
    override func cancelOperation(_: Any?) { onCancel?() }  // Esc
}
