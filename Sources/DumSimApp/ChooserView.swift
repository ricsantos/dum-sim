import AppKit
import DumSimKit

/// The picker the drop panel grows into when more than one simulator is booted.
@MainActor
final class ChooserView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Copy to which simulator?")
    private let rememberBox = NSButton(
        checkboxWithTitle: "Remember", target: nil, action: nil
    )
    private let cardStack = NSStackView()

    private var devices: [Simulator] = []
    private var completion: ((Simulator?, Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        cardStack.orientation = .horizontal
        cardStack.alignment = .top
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        rememberBox.font = .systemFont(ofSize: 11)
        rememberBox.target = self
        rememberBox.action = #selector(ignore)
        rememberBox.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .small
        cancel.keyEquivalent = "\u{1b}"
        cancel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(cardStack)
        addSubview(rememberBox)
        addSubview(cancel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            cardStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            cardStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
            cardStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

            rememberBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rememberBox.topAnchor.constraint(equalTo: cardStack.bottomAnchor, constant: 12),
            rememberBox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            cancel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            cancel.centerYAnchor.constraint(equalTo: rememberBox.centerYAnchor),
            cancel.leadingAnchor.constraint(greaterThanOrEqualTo: rememberBox.trailingAnchor, constant: 10),
        ])
    }

    /// Fills the picker and starts loading a screenshot for each device.
    func present(_ devices: [Simulator], completion: @escaping (Simulator?, Bool) -> Void) {
        self.devices = devices
        self.completion = completion
        rememberBox.state = .off

        for view in cardStack.arrangedSubviews {
            cardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        var cards: [DeviceCard] = []
        for (index, device) in devices.enumerated() {
            let card = DeviceCard(device: device, tag: index)
            card.target = self
            card.action = #selector(pick(_:))
            cardStack.addArrangedSubview(card)
            cards.append(card)
        }

        layoutSubtreeIfNeeded()
        loadThumbnails(cards)
    }

    private func loadThumbnails(_ cards: [DeviceCard]) {
        for card in cards {
            let device = card.device
            Task {
                let data = await Task.detached(priority: .userInitiated) {
                    try? Simctl.screenshot(device: device)
                }.value
                guard let data, let image = NSImage(data: data) else { return }
                card.setThumbnail(image)
            }
        }
    }

    @objc private func pick(_ sender: NSButton) {
        guard devices.indices.contains(sender.tag) else { return }
        finish(devices[sender.tag])
    }

    @objc private func cancel() {
        finish(nil)
    }

    @objc private func ignore() {}

    private func finish(_ device: Simulator?) {
        let remember = rememberBox.state == .on
        let callback = completion
        completion = nil
        callback?(device, remember)
    }
}

/// One tappable simulator, with a live screenshot once it arrives.
private final class DeviceCard: NSButton {
    static let thumbnailHeight: CGFloat = 200

    let device: Simulator

    private let thumbnail = NSImageView()
    private var thumbnailWidth: NSLayoutConstraint!

    init(device: Simulator, tag: Int) {
        self.device = device
        super.init(frame: .zero)

        self.tag = tag
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = device.udid

        thumbnail.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: device.name)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.contentTintColor = .tertiaryLabelColor
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 10
        thumbnail.layer?.masksToBounds = true
        thumbnail.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: device.name)
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail

        let runtimeLabel = NSTextField(labelWithString: device.runtime)
        runtimeLabel.font = .systemFont(ofSize: 10)
        runtimeLabel.textColor = .secondaryLabelColor
        runtimeLabel.alignment = .center

        let column = NSStackView(views: [thumbnail, nameLabel, runtimeLabel])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 5
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        thumbnailWidth = thumbnail.widthAnchor.constraint(equalToConstant: 96)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnail.heightAnchor.constraint(equalToConstant: Self.thumbnailHeight),
            thumbnailWidth,
            widthAnchor.constraint(equalToConstant: 118),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The view is sized to the screenshot, so the rounded corners clip the image
    /// itself rather than a letterboxed frame.
    func setThumbnail(_ image: NSImage) {
        thumbnail.image = image
        thumbnail.contentTintColor = nil

        let size = image.size
        guard size.height > 0 else { return }
        let width = Self.thumbnailHeight * (size.width / size.height)
        thumbnailWidth.constant = min(max(width, 40), 110)
        thumbnail.layer?.borderWidth = 1
        thumbnail.layer?.borderColor = NSColor.separatorColor.cgColor
    }
}
