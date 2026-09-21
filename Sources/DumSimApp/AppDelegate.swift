import AppKit
import DumSimKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var dropView: DropView!
    private let feedback = FeedbackPopover()
    private let preferences = Preferences()
    private var devices: [Simulator] = []
    private var isBusy = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.statusImage()
        button.image?.isTemplate = true
        button.toolTip = "Drop files here to copy them to a simulator."

        let drop = DropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onDrop = { [weak self] urls in self?.handleDrop(urls) }
        drop.onHighlight = { [weak self] on in self?.statusItem.button?.highlight(on) }
        button.addSubview(drop)
        dropView = drop
    }

    private static func statusImage() -> NSImage? {
        let candidates = [
            "iphone.and.arrow.forward",
            "square.and.arrow.down.on.square",
            "arrow.down.to.line",
            "iphone",
        ]
        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "dum-sim") {
                return image
            }
        }
        return NSImage(named: NSImage.applicationIconName)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        devices = (try? Simulator.all()) ?? []
        menu.removeAllItems()

        let target = NSMenuItem(title: targetSummary(), action: nil, keyEquivalent: "")
        target.isEnabled = false
        menu.addItem(target)
        menu.addItem(.separator())

        menu.addItem(submenuItem(title: "Target Simulator", submenu: deviceMenu()))
        menu.addItem(submenuItem(title: "Destination", submenu: destinationMenu()))

        let open = NSMenuItem(
            title: "Open Destination After Drop",
            action: #selector(toggleOpenAfterDrop),
            keyEquivalent: ""
        )
        open.target = self
        open.state = preferences.openAfterDrop ? .on : .off
        menu.addItem(open)

        menu.addItem(.separator())

        let choose = NSMenuItem(title: "Copy Files…", action: #selector(chooseFiles), keyEquivalent: "o")
        choose.target = self
        menu.addItem(choose)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit dum-sim", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func submenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func targetSummary() -> String {
        guard let device = try? resolvedDevice() else {
            return "No simulator booted"
        }
        return "Target: \(device.displayName)"
    }

    private func deviceMenu() -> NSMenu {
        let menu = NSMenu()

        let auto = NSMenuItem(title: "Booted Simulator", action: #selector(selectDevice(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = nil as String?
        auto.state = preferences.deviceUDID == nil ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())

        let sorted = devices.sorted {
            if $0.isBooted != $1.isBooted { return $0.isBooted }
            return ($0.runtime, $0.name) < ($1.runtime, $1.name)
        }

        for device in sorted.prefix(40) {
            let title = device.isBooted ? "\(device.displayName) — booted" : device.displayName
            let item = NSMenuItem(title: title, action: #selector(selectDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.udid
            item.state = preferences.deviceUDID == device.udid ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func destinationMenu() -> NSMenu {
        let menu = NSMenu()
        let choices = [
            ("auto", "Automatic"),
            ("photos", "Always Photos"),
            ("files", "Always Files"),
        ]
        for (key, title) in choices {
            let item = NSMenuItem(title: title, action: #selector(selectDestination(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = preferences.destinationChoice == key ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Actions

    @objc private func selectDevice(_ sender: NSMenuItem) {
        preferences.deviceUDID = sender.representedObject as? String
    }

    @objc private func selectDestination(_ sender: NSMenuItem) {
        preferences.destinationChoice = (sender.representedObject as? String) ?? "auto"
    }

    @objc private func toggleOpenAfterDrop() {
        preferences.openAfterDrop.toggle()
    }

    @objc private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Copy to Simulator"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        handleDrop(panel.urls)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Import

    private func resolvedDevice() throws -> Simulator {
        try Simulator.resolve(preferences.deviceUDID)
    }

    private func handleDrop(_ urls: [URL]) {
        guard !isBusy else { return }
        isBusy = true
        statusItem.button?.appearsDisabled = true

        let destination = preferences.forcedDestination
        let query = preferences.deviceUDID
        let shouldOpen = preferences.openAfterDrop

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Outcome in
                do {
                    let device = try Simulator.resolve(query)
                    let report = Importer.import(urls, into: device, destination: destination)
                    if shouldOpen, let first = report.results.first {
                        try? Importer.open(first.destination, on: device)
                    }
                    return .finished(device: device, report: report)
                } catch {
                    return .failed(message: error.localizedDescription)
                }
            }.value

            present(outcome)
            isBusy = false
            statusItem.button?.appearsDisabled = false
        }
    }

    private enum Outcome: Sendable {
        case finished(device: Simulator, report: ImportReport)
        case failed(message: String)
    }

    private func present(_ outcome: Outcome) {
        guard let button = statusItem.button else { return }

        switch outcome {
        case .failed(let message):
            feedback.show(message, isError: true, relativeTo: button, for: 5)

        case .finished(let device, let report):
            var lines: [String] = []
            let grouped = Dictionary(grouping: report.results) { $0.destination.label }
            for (label, results) in grouped.sorted(by: { $0.key < $1.key }) {
                lines.append("\(results.count) \(results.count == 1 ? "file" : "files") → \(label)")
            }
            for failure in report.failures.prefix(4) {
                lines.append("✗ \(failure.source.lastPathComponent): \(failure.message)")
            }
            if report.failures.count > 4 {
                lines.append("✗ and \(report.failures.count - 4) more")
            }
            if lines.isEmpty {
                lines.append("Nothing copied.")
            }
            lines.append(device.displayName)

            feedback.show(
                lines.joined(separator: "\n"),
                isError: !report.failures.isEmpty,
                relativeTo: button,
                for: report.failures.isEmpty ? 3 : 6
            )
        }
    }
}
