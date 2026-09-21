import AppKit

/// Sits on top of the status item button and catches files dropped on the icon.
final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onHighlight: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // AppKit finds a drop target with hitTest, so this view must accept hits.
    // It forwards every mouse event to the status button underneath instead.
    override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { superview?.mouseUp(with: event) }
    override func mouseDragged(with event: NSEvent) { superview?.mouseDragged(with: event) }
    override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }
    override func rightMouseUp(with event: NSEvent) { superview?.rightMouseUp(with: event) }
    override func otherMouseDown(with event: NSEvent) { superview?.otherMouseDown(with: event) }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: sender).isEmpty else { return [] }
        onHighlight?(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onHighlight?(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onHighlight?(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !urls(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let dropped = urls(from: sender)
        guard !dropped.isEmpty else { return false }
        onHighlight?(false)
        onDrop?(dropped)
        return true
    }

    private func urls(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        )
        return (objects as? [URL]) ?? []
    }
}
