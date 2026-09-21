import AppKit

/// A small floating panel you can drop files on.
///
/// The menu bar icon sits under the menu bar, and macOS reads a drag to the top
/// edge as a Spaces gesture. This panel gives the drag a target that is easy to hit.
@MainActor
final class DropWindowController {
    private let panel: NSPanel
    private let zone: DropZoneView
    private let effect = NSVisualEffectView()

    var onDrop: (([URL]) -> Void)?
    /// Fires when the user drags the panel somewhere else.
    var onUserMove: (() -> Void)?

    private var isMovingProgrammatically = false

    var isVisible: Bool { panel.isVisible }

    private static let contentRect = NSRect(x: 0, y: 0, width: 200, height: 150)
    private static let autosaveName = NSWindow.FrameAutosaveName("DumSimDropWindow")

    init() {
        zone = DropZoneView(frame: Self.contentRect)

        panel = NSPanel(
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
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func updateSubtitle(_ text: String) {
        zone.subtitle = text
    }
}
