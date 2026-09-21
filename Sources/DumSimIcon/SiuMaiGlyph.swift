import AppKit

/// The siu mai that gives dum-sim its name.
///
/// The glyph is drawn rather than stored, so the menu bar template stays sharp at
/// every size. Every stroke and fill is opaque, because a template image carries
/// only alpha and macOS supplies the colour.
public enum SiuMaiGlyph {
    /// The design grid. Every coordinate below is in these units.
    public static let grid: CGFloat = 18

    // The dumpling sits low on the grid to leave room for the steam above it.
    private static let rimY: CGFloat = 9.0
    private static let leftX: CGFloat = 3.0
    private static let rightX: CGFloat = 15.0
    private static let bottomY: CGFloat = 2.0

    /// Draws the dumpling into the current context, on an 18 by 18 grid.
    public static func draw(lineWidth: CGFloat = 1.35) {
        // The filling is a mass, not an arc. An outlined dome reads as a handle.
        filledMound().fill()

        let wrapper = cupPath(closed: false)
        wrapper.lineWidth = lineWidth
        wrapper.lineCapStyle = .round
        wrapper.lineJoinStyle = .round
        wrapper.stroke()

        steam(lineWidth: lineWidth)
    }

    /// Three upright dashes, the middle one tallest. Curved wisps read as
    /// antennae at this size, and fanned ones read as a sparkle.
    private static func steam(lineWidth: CGFloat) {
        for (x, top, length) in [(6.5, 15.5, 1.5), (9.0, 16.6, 1.9), (11.5, 15.5, 1.5)] {
            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: x, y: top - length))
            dash.line(to: NSPoint(x: x, y: top))
            dash.lineWidth = lineWidth * 0.7
            dash.lineCapStyle = .round
            dash.stroke()
        }
    }

    /// The wavy top edge of the wrapper, left to right.
    private static func wave(into path: NSBezierPath, humps: Int = 5, amplitude: CGFloat = 0.5) {
        let width = (rightX - leftX) / CGFloat(humps)
        for index in 0 ..< humps {
            let start = leftX + CGFloat(index) * width
            let end = start + width
            path.curve(
                to: NSPoint(x: end, y: rimY),
                controlPoint1: NSPoint(x: start + width * 0.24, y: rimY + amplitude),
                controlPoint2: NSPoint(x: end - width * 0.24, y: rimY + amplitude)
            )
        }
    }

    /// The pleated wrapper: a wavy rim over a barrel that narrows to the base.
    private static func cupPath(closed: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: leftX, y: rimY))
        wave(into: path)
        path.curve(
            to: NSPoint(x: 13.2, y: bottomY),
            controlPoint1: NSPoint(x: 15.5, y: rimY - 3.2),
            controlPoint2: NSPoint(x: 14.8, y: bottomY + 1.1)
        )
        path.line(to: NSPoint(x: 4.8, y: bottomY))
        path.curve(
            to: NSPoint(x: leftX, y: rimY),
            controlPoint1: NSPoint(x: 3.2, y: bottomY + 1.1),
            controlPoint2: NSPoint(x: 2.5, y: rimY - 3.2)
        )
        if closed { path.close() }
        return path
    }

    /// A low broad mound, the filling sitting just proud of the wrapper.
    private static func filledMound() -> NSBezierPath {
        let base = rimY + 0.25
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3.9, y: base))
        path.curve(
            to: NSPoint(x: 14.1, y: base),
            controlPoint1: NSPoint(x: 5.0, y: 14.1),
            controlPoint2: NSPoint(x: 13.0, y: 14.1)
        )
        path.close()
        return path
    }

    /// A monochrome template for the menu bar. macOS recolours it.
    public static func statusImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let transform = NSAffineTransform()
            transform.scale(by: size / grid)
            transform.concat()
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Masks supplied artwork into the macOS icon shape.
    ///
    /// A square source fills the plate. Anything outside the squircle is clipped,
    /// so a picture with its own background still gets rounded corners.
    public static func appIcon(from source: NSImage, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let plate = plateRect(in: size)
            NSBezierPath(
                roundedRect: plate,
                xRadius: plate.width * 0.2237,
                yRadius: plate.width * 0.2237
            ).addClip()
            source.draw(in: plate, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    /// The fallback bundle icon: a warm plate with the glyph knocked out in white.
    public static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let plate = plateRect(in: size)
            let squircle = NSBezierPath(
                roundedRect: plate,
                xRadius: plate.width * 0.2237,
                yRadius: plate.width * 0.2237
            )
            let gradient = NSGradient(
                starting: NSColor(srgbRed: 0.97, green: 0.71, blue: 0.35, alpha: 1),
                ending: NSColor(srgbRed: 0.82, green: 0.44, blue: 0.16, alpha: 1)
            )
            gradient?.draw(in: squircle, angle: -90)

            NSGraphicsContext.saveGraphicsState()
            let glyph = plate.width * 0.62
            let origin = (size - glyph) / 2
            let move = NSAffineTransform()
            move.translateX(by: origin, yBy: origin)
            move.scale(by: glyph / grid)
            move.concat()
            NSColor.white.setStroke()
            NSColor.white.setFill()
            draw()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    /// macOS icons leave a margin around the artwork.
    private static func plateRect(in size: CGFloat) -> NSRect {
        let inset = size * 0.09
        return NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    }
}
