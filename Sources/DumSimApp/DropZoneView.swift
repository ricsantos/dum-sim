import AppKit

/// The content of the floating window. It draws a dashed target and accepts files.
final class DropZoneView: NSView {
    var onDrop: (([URL]) -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Drop Files")
    private let subtitleLabel = NSTextField(labelWithString: "")

    private var isTargeted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        buildSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var subtitle: String {
        get { subtitleLabel.stringValue }
        set { subtitleLabel.stringValue = newValue }
    }

    // MARK: - Layout

    private func buildSubviews() {
        iconView.image = NSImage(
            systemSymbolName: "arrow.down.doc",
            accessibilityDescription: "Drop files"
        )
        iconView.symbolConfiguration = .init(pointSize: 26, weight: .regular)
        iconView.contentTintColor = .secondaryLabelColor

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .center

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [iconView, titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 10, dy: 10)
        let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)
        path.lineWidth = isTargeted ? 2.5 : 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        (isTargeted ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.stroke()

        if isTargeted {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
        }
    }

    // MARK: - Dragging

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: sender).isEmpty else { return [] }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isTargeted = false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        isTargeted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let dropped = urls(from: sender)
        guard !dropped.isEmpty else { return false }
        isTargeted = false
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
