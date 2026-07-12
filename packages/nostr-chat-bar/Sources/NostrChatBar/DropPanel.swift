import Cocoa

// MARK: - Drop-down panel
//
// Mimics noctalia's layer-shell card: borderless, floats above
// everything, pinned under the menubar of whichever screen the mouse
// is on, slides in/out. NSPanel + .nonactivatingPanel lets it grab key
// without stealing app focus from whatever's underneath — same UX as
// Spotlight.

/// What the panel accepts from a file-manager drag: one local image.
/// The daemon validates again on send-file; this only keeps the drop
/// cursor honest.
enum ImageDropPolicy {
    static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    static func acceptable(_ url: URL) -> Bool {
        url.isFileURL && allowedExtensions.contains(url.pathExtension.lowercased())
    }
}

final class DropPanel: NSPanel {
    // Borderless windows refuse key by default; override so the
    // TextView can actually receive typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onCancel: (() -> Void)?
    override func cancelOperation(_: Any?) { onCancel?() }  // Esc
}

/// Content view that accepts image-file drags for the whole panel.
/// Lives on the view, not the window: NSWindow's dragging-destination
/// hooks are an informal protocol that cannot be overridden, while a
/// registered view receives them directly.
final class DropTargetView: NSView {
    /// Local image file dropped anywhere on the panel.
    var onFileDrop: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func droppedImageURL(_ sender: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options) as? [URL],
            let first = urls.first, ImageDropPolicy.acceptable(first)
        else { return nil }
        return first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedImageURL(sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedImageURL(sender) else { return false }
        onFileDrop?(url.path)
        return true
    }
}
