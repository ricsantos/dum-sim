import AppKit

/// The bamboo steamer that gives dum-sim its name.
///
/// The glyph is drawn rather than stored, so the menu bar template and the app
/// icon come from one description and stay sharp at every size.
public enum SteamerGlyph {
    /// The design grid. Every coordinate below is in these units.
    public static let grid: CGFloat = 18

    /// Strokes the steamer into the current context, on an 18 by 18 grid.
    public static func draw(lineWidth: CGFloat = 1.35) {
        // Steam: three dashes, the middle one tallest.
        for (x, top, length) in [(6.3, 16.0, 1.7), (9.0, 16.9, 2.1), (11.7, 16.0, 1.7)] {
            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: x, y: top - length))
            dash.line(to: NSPoint(x: x, y: top))
            dash.lineWidth = lineWidth * 0.7
            dash.lineCapStyle = .round
            dash.stroke()
        }

        // Lid: a low dome on an overhanging rim.
        let dome = NSBezierPath()
        dome.move(to: NSPoint(x: 3.6, y: 11.6))
        dome.curve(
            to: NSPoint(x: 14.4, y: 11.6),
            controlPoint1: NSPoint(x: 4.8, y: 13.6),
            controlPoint2: NSPoint(x: 13.2, y: 13.6)
        )
        dome.lineWidth = lineWidth
        dome.lineCapStyle = .round
        dome.stroke()

        let rim = NSBezierPath()
        rim.move(to: NSPoint(x: 2.0, y: 11.3))
        rim.line(to: NSPoint(x: 16.0, y: 11.3))
        rim.lineWidth = lineWidth
        rim.lineCapStyle = .round
        rim.stroke()

        // Body: nearly straight sided, like a real bamboo basket.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 3.3, y: 10.7))
        body.line(to: NSPoint(x: 4.1, y: 2.4))
        body.line(to: NSPoint(x: 13.9, y: 2.4))
        body.line(to: NSPoint(x: 14.7, y: 10.7))
        body.lineWidth = lineWidth
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.stroke()

        for (y, inset) in [(8.0, 0.25), (5.2, 0.52)] {
            let slat = NSBezierPath()
            slat.move(to: NSPoint(x: 3.3 + inset, y: y))
            slat.line(to: NSPoint(x: 14.7 - inset, y: y))
            slat.lineWidth = lineWidth * 0.7
            slat.lineCapStyle = .round
            slat.stroke()
        }
    }

    /// A monochrome template for the menu bar. macOS recolours it.
    public static func statusImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSColor.black.setStroke()
            scaleToGrid(size)
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The bundle icon: a warm bamboo square with the glyph knocked out in white.
    public static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            // macOS icons leave a margin, and the corner radius is about 22%.
            let inset = size * 0.09
            let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
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
            draw()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    private static func scaleToGrid(_ size: CGFloat) {
        let transform = NSAffineTransform()
        transform.scale(by: size / grid)
        transform.concat()
    }
}
