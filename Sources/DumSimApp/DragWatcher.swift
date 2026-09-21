import AppKit

/// Notices when a file drag starts anywhere on the Mac, so the panel can appear
/// under the pointer without a click first.
///
/// This reads the drag pasteboard, never the keyboard, so it needs no permission.
/// If macOS withholds the events, the menu toggle still shows the panel.
@MainActor
final class DragWatcher {
    var onFileDragBegan: (() -> Void)?
    var onFileDragEnded: (() -> Void)?

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var isDragging = false
    private var handledChangeCount = -1

    var isRunning: Bool { dragMonitor != nil }

    func start() {
        guard dragMonitor == nil else { return }

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { _ in
            MainActor.assumeIsolated { [weak self] in self?.checkForFileDrag() }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
            MainActor.assumeIsolated { [weak self] in self?.finishDrag() }
        }
    }

    func stop() {
        [dragMonitor, upMonitor].forEach { monitor in
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        dragMonitor = nil
        upMonitor = nil
        finishDrag()
    }

    private func checkForFileDrag() {
        guard !isDragging else { return }

        let pasteboard = NSPasteboard(name: .drag)
        // A stale pasteboard keeps its types after a drag, so compare the change count.
        guard pasteboard.changeCount != handledChangeCount else { return }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard pasteboard.canReadObject(forClasses: [NSURL.self], options: options) else { return }

        isDragging = true
        onFileDragBegan?()
    }

    private func finishDrag() {
        guard isDragging else { return }
        isDragging = false
        handledChangeCount = NSPasteboard(name: .drag).changeCount
        onFileDragEnded?()
    }
}
