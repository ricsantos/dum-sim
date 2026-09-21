import AppKit
import DumSimKit

/// A small floating panel you can drop files on.
///
/// The menu bar icon sits under the menu bar, and macOS reads a drag to the top
/// edge as a Spaces gesture. This panel gives the drag a target that is easy to hit.
/// A borderless panel refuses key status by default, which stops its buttons
/// from responding. The picker needs clicks, so this one accepts it.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class DropWindowController {
    private let panel: FloatingPanel
    private let zone: DropZoneView
    private let chooser = ChooserView()
    private let effect = NSVisualEffectView()
    private var isShowingChooser = false

    var onDrop: (([URL]) -> Void)?
    /// Fires when the user drags the panel somewhere else.
    var onUserMove: (() -> Void)?
    /// Answers whether the panel stays on screen once the picker closes.
    var keepVisible: (() -> Bool)?

    private var isMovingProgrammatically = false

    var isVisible: Bool { panel.isVisible }

    private static let contentRect = NSRect(x: 0, y: 0, width: 200, height: 150)
    private static let autosaveName = NSWindow.FrameAutosaveName("DumSimDropWindow")

    init() {
        zone = DropZoneView(frame: Self.contentRect)

        panel = FloatingPanel(
            contentRect: Self.contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // .statusBar keeps the panel above a full screen app.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // The frame must be set before the view gains a child, or autoresizing
        // computes the child's frame against a zero sized superview.
        effect.frame = Self.contentRect
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        // A behind-window blur is composited by the window server, so a layer
        // corner radius does not clip it. A mask image does.
        effect.maskImage = Self.roundedMask(radius: 16)
        effect.autoresizingMask = [.width, .height]

        effect.addSubview(zone)
        zone.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            zone.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            zone.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            zone.topAnchor.constraint(equalTo: effect.topAnchor),
            zone.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        chooser.translatesAutoresizingMaskIntoConstraints = false
        chooser.alphaValue = 0
        chooser.isHidden = true
        effect.addSubview(chooser)
        NSLayoutConstraint.activate([
            chooser.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            chooser.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            chooser.topAnchor.constraint(equalTo: effect.topAnchor),
            chooser.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.contentView = effect
        zone.onDrop = { [weak self] urls in self?.onDrop?(urls) }

        _ = panel.setFrameUsingName(Self.autosaveName)
        panel.setFrameAutosaveName(Self.autosaveName)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isMovingProgrammatically else { return }
                self.onUserMove?()
            }
        }
    }

    /// True when the status item reports a frame that lies on a real screen.
    /// A hidden or overflowed item reports one that does not.
    static func isUsableAnchor(_ frame: NSRect) -> Bool {
        frame.width > 1 && frame.height > 1
            && NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    /// A resizable rounded rectangle that shapes the panel.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Centres the panel below the status item, clamped to the screen.
    ///
    /// An unusable anchor falls back to the top right of the menu bar display.
    func moveUnder(_ button: NSStatusBarButton?) {
        let anchor = button?.window?.frame ?? .zero
        // A hidden or overflowed status item reports a frame outside every screen.
        let anchorScreen = NSScreen.screens.first { $0.frame.intersects(anchor) }
        let hasAnchor = anchor.width > 1 && anchor.height > 1 && anchorScreen != nil

        // NSScreen.screens.first is the display that carries the menu bar.
        let screen = anchorScreen ?? NSScreen.screens.first ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        let top = visible.maxY - size.height - 8

        var x = hasAnchor ? anchor.midX - size.width / 2 : visible.maxX - size.width - 24
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)

        var y = hasAnchor ? anchor.minY - size.height - 8 : top
        if y < visible.minY + 8 { y = top }

        let origin = NSPoint(x: x, y: y)
        isMovingProgrammatically = true
        panel.setFrameOrigin(origin)
        isMovingProgrammatically = false
        panel.saveFrame(usingName: Self.autosaveName)
        logPlacement(anchor: anchor, hasAnchor: hasAnchor, visible: visible, origin: origin)
    }

    private func logPlacement(anchor: NSRect, hasAnchor: Bool, visible: NSRect, origin: NSPoint) {
        if ProcessInfo.processInfo.environment["DUMSIM_DEBUG"] != nil {
            let line = "place anchor=\(anchor) hasAnchor=\(hasAnchor) visible=\(visible) origin=\(origin)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    func show() {
        if !isShowingChooser { enforceDropSize() }
        panel.orderFrontRegardless()
    }

    /// Grows the panel into the picker, keeping its top edge in place.
    func showChooser(
        for devices: [Simulator],
        completion: @escaping (Simulator?, Bool) -> Void
    ) {
        chooser.present(devices) { [weak self] device, remember in
            guard let self else { return }
            // Order the panel out before the reset, or the drop target shows
            // for the length of the copy that follows.
            NSApp.deactivate()
            if self.keepVisible?() != true {
                self.panel.orderOut(nil)
            }
            self.resetToDropSize()
            completion(device, remember)
        }

        chooser.isHidden = false
        chooser.layoutSubtreeIfNeeded()
        let size = NSSize(
            width: max(Self.contentRect.width, chooser.fittingSize.width),
            height: max(Self.contentRect.height, chooser.fittingSize.height)
        )

        isShowingChooser = true
        panel.orderFrontRegardless()
        grow(to: size)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func resetToDropSize() {
        isShowingChooser = false
        chooser.isHidden = true
        chooser.alphaValue = 0
        zone.isHidden = false
        zone.alphaValue = 1
        enforceDropSize()
    }

    /// Snaps the panel back to the drop size, keeping its centre and top edge.
    private func enforceDropSize() {
        let size = Self.contentRect.size
        guard panel.frame.size != size else { return }

        let current = panel.frame
        var frame = NSRect(
            x: current.midX - size.width / 2,
            y: current.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - size.width - 8)
            frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - size.height - 8)
        }

        isMovingProgrammatically = true
        panel.setFrame(frame, display: true)
        isMovingProgrammatically = false
        // Persist the small frame, never the picker's.
        panel.saveFrame(usingName: Self.autosaveName)
    }

    /// Animates the panel out to the picker size, keeping its top edge in place.
    private func grow(to size: NSSize) {
        let current = panel.frame
        var frame = NSRect(
            x: current.midX - size.width / 2,
            y: current.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - size.width - 8)
            frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - size.height - 8)
        }

        // A programmatic resize moves the window, which must not count as the
        // user choosing a position.
        isMovingProgrammatically = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            zone.animator().alphaValue = 0
            chooser.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.isMovingProgrammatically = false
            guard self.isShowingChooser else { return }
            self.zone.isHidden = true
        }
    }

    func hide() {
        resetToDropSize()
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func updateSubtitle(_ text: String) {
        zone.subtitle = text
    }
}
