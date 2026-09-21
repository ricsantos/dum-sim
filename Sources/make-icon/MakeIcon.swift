import AppKit
import DumSimIcon
import Foundation

/// Writes AppIcon.icns into the directory given on the command line.
///
/// With `--source <path>` it masks that artwork into the macOS icon shape.
/// Without it, or when the file is missing, it draws the steamer glyph instead.
/// With `--png` it also writes AppIcon-1024.png, for a README or a release page.
@main
enum MakeIcon {
    static func main() {
        guard CommandLine.arguments.count > 1 else {
            FileHandle.standardError.write(
                Data("usage: make-icon <output directory> [--source <png>] [--png]\n".utf8)
            )
            exit(1)
        }

        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        loadSource()
        let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset")

        do {
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

            // The sizes iconutil expects, each at one and two times.
            for points in [16, 32, 128, 256, 512] {
                try write(points: points, scale: 1, into: iconset)
                try write(points: points, scale: 2, into: iconset)
            }

            let icns = outputDirectory.appendingPathComponent("AppIcon.icns")
            let iconutil = Process()
            iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
            iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
            try iconutil.run()
            iconutil.waitUntilExit()
            guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

            try FileManager.default.removeItem(at: iconset)
            print("Wrote \(icns.path)")

            if CommandLine.arguments.contains("--png") {
                let png = outputDirectory.appendingPathComponent("AppIcon-1024.png")
                try writePNG(pixels: 1024, to: png)
                print("Wrote \(png.path)")
            }
        } catch {
            FileHandle.standardError.write(Data("make-icon: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func write(points: Int, scale: Int, into directory: URL) throws {
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(points)x\(points)\(suffix).png"
        try writePNG(pixels: points * scale, to: directory.appendingPathComponent(name))
    }

    private static nonisolated(unsafe) var source: NSImage?

    private static func loadSource() {
        guard let flag = CommandLine.arguments.firstIndex(of: "--source"),
              CommandLine.arguments.indices.contains(flag + 1)
        else { return }
        source = NSImage(contentsOfFile: CommandLine.arguments[flag + 1])
    }

    private static func writePNG(pixels: Int, to url: URL) throws {
        let size = CGFloat(pixels)
        let image = source.map { SteamerGlyph.appIcon(from: $0, size: size) }
            ?? SteamerGlyph.appIcon(size: size)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
