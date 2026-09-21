import Foundation

/// Where a file lands inside the simulator.
public enum Destination: Sendable, Equatable {
    /// The Photos library, by way of `simctl addmedia`.
    case photos
    /// "On My iPhone" in the Files app.
    case files
    /// An installed app's own container, under `subpath` (default "Documents").
    case app(bundleID: String, subpath: String)

    public var label: String {
        switch self {
        case .photos: return "Photos"
        case .files: return "Files"
        case .app(let bundleID, let subpath): return "\(bundleID)/\(subpath)"
        }
    }

    /// The app to bring to the front after an import.
    public var hostBundleID: String {
        switch self {
        case .photos: return "com.apple.mobileslideshow"
        case .files: return "com.apple.DocumentsApp"
        case .app(let bundleID, _): return bundleID
        }
    }
}

public enum Router {
    /// Extensions `simctl addmedia` accepts as photos or live photos.
    public static let photoExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "apng", "avci", "dng",
    ]

    /// Extensions `simctl addmedia` accepts as videos.
    public static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// Extensions `simctl addmedia` accepts as contacts.
    public static let contactExtensions: Set<String> = ["vcf", "vcard"]

    public static var mediaExtensions: Set<String> {
        photoExtensions.union(videoExtensions).union(contactExtensions)
    }

    /// Picks Photos for media that `addmedia` understands, and Files for everything else.
    public static func destination(for url: URL) -> Destination {
        let ext = url.pathExtension.lowercased()
        return mediaExtensions.contains(ext) ? .photos : .files
    }
}
