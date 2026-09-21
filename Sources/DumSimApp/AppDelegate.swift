import AppKit
import DumSimKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var dropView: DropView!
    private let feedback = FeedbackPopover()
    private let preferences = Preferences()
    private let dropWindow = DropWindowController()
    private let dragWatcher = DragWatcher()
    private var devices: [Simulator] = []
    private var isBusy = false
    /// True while the panel is on screen only because a drag is in progress.
    private var windowShownForDrag = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        configureDropWindow()
    }

    private func configureDropWindow() {
        dropWindow.onDrop = { [weak self] urls in self?.handleDrop(urls) }
        dropWindow.onUserMove = { [weak self] in self?.preferences.hasCustomPosition = true }
        dropWindow.keepVisible = { [weak self] in self?.preferences.showDropWindow ?? false }
        updateWindowSubtitle()

        // The status item reports a usable frame only once the menu bar lays it
        // out, so place the panel later and then before every appearance.
        Task { @MainActor in
            for _ in 0 ..< 60 {
                if DropWindowController.isUsableAnchor(self.statusItem.button?.window?.frame ?? .zero) {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            self.placeUnderIconIfDefault()
        }

        dragWatcher.onFileDragBegan = { [weak self] in self?.showWindowForDrag() }
        dragWatcher.onFileDragEnded = { [weak self] in self?.hideWindowAfterDrag() }

        if preferences.showDropWindow {
            dropWindow.show()
        }
        if preferences.autoShowWhileDragging {
            dragWatcher.start()
        }
    }

    // MARK: - Floating panel

    /// Keeps the panel under the icon until the user drags it somewhere else.
    private func placeUnderIconIfDefault() {
        guard !preferences.hasCustomPosition else { return }
        dropWindow.moveUnder(statusItem.button)
    }

    private func showWindowForDrag() {
        guard !dropWindow.isVisible else { return }
        windowShownForDrag = true
        updateWindowSubtitle()
        placeUnderIconIfDefault()
        dropWindow.show()
    }

    private func hideWindowAfterDrag() {
        guard windowShownForDrag else { return }
        windowShownForDrag = false
        // A short delay lets a drop that landed on the panel finish first.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !self.preferences.showDropWindow, !self.isBusy else { return }
            self.dropWindow.hide()
        }
    }

    private func updateWindowSubtitle() {
        let device = targetDescription()
        let destination: String
        switch preferences.destinationChoice {
        case "photos": destination = "Photos"
        case "files": destination = "Files"
        default: destination = "Auto"
        }
        dropWindow.updateSubtitle("\(device)\n\(destination)")
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.statusImage()
        button.image?.isTemplate = true
        button.toolTip = "Drop files here to copy them to a simulator."

        let drop = DropView(frame: button.bounds)
        drop.translatesAutoresizingMaskIntoConstraints = false
        drop.onDrop = { [weak self] urls in self?.handleDrop(urls) }
        drop.onHighlight = { [weak self] on in self?.statusItem.button?.highlight(on) }
        button.addSubview(drop)
        NSLayoutConstraint.activate([
            drop.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            drop.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            drop.topAnchor.constraint(equalTo: button.topAnchor),
            drop.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
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

        let window = NSMenuItem(
            title: "Keep Drop Window On Screen",
            action: #selector(toggleDropWindow),
            keyEquivalent: ""
        )
        window.target = self
        window.state = preferences.showDropWindow ? .on : .off
        menu.addItem(window)

        let auto = NSMenuItem(
            title: "Show Drop Window While Dragging",
            action: #selector(toggleAutoShow),
            keyEquivalent: ""
        )
        auto.target = self
        auto.state = preferences.autoShowWhileDragging ? .on : .off
        menu.addItem(auto)

        let reset = NSMenuItem(
            title: "Move Drop Window Under Icon",
            action: #selector(resetWindowPosition),
            keyEquivalent: ""
        )
        reset.target = self
        menu.addItem(reset)

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
        "Target: \(targetDescription())"
    }

    /// Names the target, or says how many simulators are competing for it.
    private func targetDescription() -> String {
        do {
            return try Simulator.resolve(preferences.deviceUDID).displayName
        } catch let error as Simulator.LookupError {
            if case .ambiguous(_, let matches) = error {
                return "\(matches.count) simulators booted"
            }
            return "No simulator booted"
        } catch {
            return "No simulator booted"
        }
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
        updateWindowSubtitle()
    }

    @objc private func selectDestination(_ sender: NSMenuItem) {
        preferences.destinationChoice = (sender.representedObject as? String) ?? "auto"
        updateWindowSubtitle()
    }

    @objc private func toggleDropWindow() {
        preferences.showDropWindow.toggle()
        windowShownForDrag = false
        updateWindowSubtitle()
        if preferences.showDropWindow {
            placeUnderIconIfDefault()
            dropWindow.show()
        } else {
            dropWindow.hide()
        }
    }

    @objc private func resetWindowPosition() {
        preferences.hasCustomPosition = false
        dropWindow.moveUnder(statusItem.button)
        dropWindow.show()
        preferences.showDropWindow = true
    }

    @objc private func toggleAutoShow() {
        preferences.autoShowWhileDragging.toggle()
        preferences.autoShowWhileDragging ? dragWatcher.start() : dragWatcher.stop()
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

    private func handleDrop(_ urls: [URL]) {
        guard !isBusy else { return }
        isBusy = true
        statusItem.button?.appearsDisabled = true

        let query = preferences.deviceUDID

        Task {
            let resolution = await Task.detached(priority: .userInitiated) { () -> Resolution in
                do {
                    return .device(try Simulator.resolve(query))
                } catch let error as Simulator.LookupError {
                    if case .ambiguous(_, let matches) = error { return .choose(matches) }
                    return .failed(error.localizedDescription)
                } catch {
                    return .failed(error.localizedDescription)
                }
            }.value

            switch resolution {
            case .device(let device):
                await runImport(urls, on: device)

            case .choose(let matches):
                // The drop panel itself grows into the picker.
                placeUnderIconIfDefault()
                dropWindow.show()
                dropWindow.showChooser(for: matches) { [weak self] device, remember in
                    guard let self else { return }
                    guard let device else {
                        self.finishDrop()
                        return
                    }
                    if remember { self.preferences.deviceUDID = device.udid }
                    Task { await self.runImport(urls, on: device) }
                }

            case .failed(let message):
                present(.failed(message: message))
                finishDrop()
            }
        }
    }

    private func runImport(_ urls: [URL], on device: Simulator) async {
        let destination = preferences.forcedDestination
        let shouldOpen = preferences.openAfterDrop

        let report = await Task.detached(priority: .userInitiated) { () -> ImportReport in
            let report = Importer.import(urls, into: device, destination: destination)
            if shouldOpen, let first = report.results.first {
                try? Importer.open(first.destination, on: device)
            }
            return report
        }.value

        present(.finished(device: device, report: report))
        finishDrop()
    }

    private func finishDrop() {
        isBusy = false
        statusItem.button?.appearsDisabled = false
        if !preferences.showDropWindow {
            dropWindow.hide()
        }
        updateWindowSubtitle()
    }

    private enum Resolution: Sendable {
        case device(Simulator)
        case choose([Simulator])
        case failed(String)
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
