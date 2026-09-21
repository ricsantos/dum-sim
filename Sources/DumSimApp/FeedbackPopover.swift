import AppKit

/// A short message under the status item. It closes itself.
@MainActor
final class FeedbackPopover {
    private let popover = NSPopover()
    private let label = NSTextField(labelWithString: "")
    private var dismissTask: Task<Void, Never>?

    init() {
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 8
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])

        let controller = NSViewController()
        controller.view = container
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
    }

    func show(_ message: String, isError: Bool, relativeTo view: NSView, for seconds: Double = 3) {
        dismissTask?.cancel()

        label.stringValue = message
        label.textColor = isError ? .systemRed : .labelColor
        popover.contentSize = fittingSize()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.popover.performClose(nil)
        }
    }

    private func fittingSize() -> NSSize {
        let width = min(max(label.intrinsicContentSize.width, 180), 320)
        label.preferredMaxLayoutWidth = width
        let height = label.intrinsicContentSize.height
        return NSSize(width: width + 28, height: height + 24)
    }
}
