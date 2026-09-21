import Foundation

/// One file's outcome.
public struct ImportResult: Sendable {
    public let source: URL
    public let destination: Destination
    /// Where the file landed on the host filesystem. Photos imports have no stable path.
    public let placedAt: URL?
    /// Set when the router aimed at Photos and `addmedia` refused the file.
    public let fellBackToFiles: Bool

    public init(source: URL, destination: Destination, placedAt: URL?, fellBackToFiles: Bool = false) {
        self.source = source
        self.destination = destination
        self.placedAt = placedAt
        self.fellBackToFiles = fellBackToFiles
    }
}

public struct ImportFailure: Sendable {
    public let source: URL
    public let message: String
}

public struct ImportReport: Sendable {
    public var results: [ImportResult] = []
    public var failures: [ImportFailure] = []

    public var isEmpty: Bool { results.isEmpty && failures.isEmpty }
}

public enum Importer {
    public enum Failure: LocalizedError {
        case missingFile(URL)

        public var errorDescription: String? {
            switch self {
            case .missingFile(let url): return "No file at \(url.path)."
            }
        }
    }

    /// Copies `urls` into `device`. A `nil` destination lets the router decide per file.
    public static func `import`(
        _ urls: [URL],
        into device: Simulator,
        destination forced: Destination? = nil
    ) -> ImportReport {
        var report = ImportReport()

        var missing: [URL] = []
        var present: [URL] = []
        for url in urls {
            FileManager.default.fileExists(atPath: url.path) ? present.append(url) : missing.append(url)
        }
        for url in missing {
            report.failures.append(
                ImportFailure(source: url, message: Failure.missingFile(url).localizedDescription)
            )
        }

        var grouped: [Int: (Destination, [URL])] = [:]
        var order: [Int] = []
        for url in present {
            let destination = forced ?? Router.destination(for: url)
            let key = destinationKey(destination)
            if grouped[key] == nil {
                grouped[key] = (destination, [])
                order.append(key)
            }
            grouped[key]?.1.append(url)
        }

        for key in order {
            guard let (destination, batch) = grouped[key] else { continue }
            switch destination {
            case .photos:
                importPhotos(batch, into: device, report: &report)
            case .files:
                let target = resolveFilesDirectory(device: device, report: &report, sources: batch)
                guard let target else { continue }
                copy(batch, into: target, destination: .files, report: &report)
            case .app(let bundleID, let subpath):
                do {
                    let container = try Containers.appContainer(device: device, bundleID: bundleID)
                    let target = subpath.isEmpty
                        ? container
                        : container.appendingPathComponent(subpath, isDirectory: true)
                    copy(batch, into: target, destination: destination, report: &report)
                } catch {
                    for url in batch {
                        report.failures.append(
                            ImportFailure(source: url, message: error.localizedDescription)
                        )
                    }
                }
            }
        }

        return report
    }

    /// Brings the destination app to the front so the import is visible.
    public static func open(_ destination: Destination, on device: Simulator) throws {
        try Simctl.run(["launch", device.udid, destination.hostBundleID])
    }

    // MARK: - Photos

    private static func importPhotos(
        _ urls: [URL],
        into device: Simulator,
        report: inout ImportReport
    ) {
        // One call keeps live photo pairs together.
        do {
            try Simctl.run(["addmedia", device.udid] + urls.map(\.path))
            for url in urls {
                report.results.append(
                    ImportResult(source: url, destination: .photos, placedAt: nil)
                )
            }
            return
        } catch {
            // Fall through: retry one at a time so a single bad file does not sink the batch.
        }

        var rejected: [URL] = []
        for url in urls {
            do {
                try Simctl.run(["addmedia", device.udid, url.path])
                report.results.append(
                    ImportResult(source: url, destination: .photos, placedAt: nil)
                )
            } catch {
                rejected.append(url)
            }
        }

        guard !rejected.isEmpty else { return }
        guard let target = resolveFilesDirectory(device: device, report: &report, sources: rejected) else {
            return
        }
        copy(rejected, into: target, destination: .files, report: &report, fellBackToFiles: true)
    }

    // MARK: - Filesystem

    private static func resolveFilesDirectory(
        device: Simulator,
        report: inout ImportReport,
        sources: [URL]
    ) -> URL? {
        do {
            return try Containers.filesLocalStorage(device: device)
        } catch {
            for url in sources {
                report.failures.append(
                    ImportFailure(source: url, message: error.localizedDescription)
                )
            }
            return nil
        }
    }

    private static func copy(
        _ urls: [URL],
        into directory: URL,
        destination: Destination,
        report: inout ImportReport,
        fellBackToFiles: Bool = false
    ) {
        for url in urls {
            do {
                let placed = try copyAtomically(from: url, into: directory)
                report.results.append(
                    ImportResult(
                        source: url,
                        destination: destination,
                        placedAt: placed,
                        fellBackToFiles: fellBackToFiles
                    )
                )
            } catch {
                report.failures.append(
                    ImportFailure(source: url, message: error.localizedDescription)
                )
            }
        }
    }

    /// Copies to a hidden temporary name, then renames into place.
    ///
    /// The Files app's file provider watches "File Provider Storage" and can truncate a file
    /// that appears mid-write, which is why a plain `cp` sometimes leaves a zero byte file.
    /// A rename is atomic, so the provider only ever sees the finished file.
    static func copyAtomically(from source: URL, into directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let final = uniqueURL(for: source.lastPathComponent, in: directory)
        let temporary = directory.appendingPathComponent(".dum-sim-\(UUID().uuidString)")

        do {
            try fileManager.copyItem(at: source, to: temporary)
            try fileManager.moveItem(at: temporary, to: final)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        return final
    }

    /// "photo.png" -> "photo 2.png" when the name is taken.
    static func uniqueURL(for name: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        repeat {
            let next = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(next)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func destinationKey(_ destination: Destination) -> Int {
        var hasher = Hasher()
        switch destination {
        case .photos: hasher.combine(0)
        case .files: hasher.combine(1)
        case .app(let bundleID, let subpath):
            hasher.combine(2)
            hasher.combine(bundleID)
            hasher.combine(subpath)
        }
        return hasher.finalize()
    }
}
