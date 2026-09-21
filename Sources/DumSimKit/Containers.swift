import Foundation

public enum Containers {
    public enum Failure: LocalizedError {
        case appNotInstalled(bundleID: String, device: Simulator)
        case groupMissing(group: String, bundleID: String)

        public var errorDescription: String? {
            switch self {
            case .appNotInstalled(let bundleID, let device):
                return "\(bundleID) is not installed on \(device.displayName)."
            case .groupMissing(let group, let bundleID):
                return "\(bundleID) does not publish the app group \(group) on this runtime."
            }
        }
    }

    /// The Files app group that backs "On My iPhone".
    public static let filesLocalStorageGroup = "group.com.apple.FileProvider.LocalStorage"
    public static let filesBundleID = "com.apple.DocumentsApp"

    /// `simctl get_app_container <device> <bundleID> <kind>`
    public static func appContainer(
        device: Simulator,
        bundleID: String,
        kind: String = "data"
    ) throws -> URL {
        let path: String
        do {
            path = try Simctl.run(["get_app_container", device.udid, bundleID, kind])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw Failure.appNotInstalled(bundleID: bundleID, device: device)
        }
        guard !path.isEmpty else {
            throw Failure.appNotInstalled(bundleID: bundleID, device: device)
        }
        return URL(fileURLWithPath: path)
    }

    /// Every app group container an app publishes, keyed by group identifier.
    public static func appGroups(device: Simulator, bundleID: String) throws -> [String: URL] {
        let output: String
        do {
            output = try Simctl.run(["get_app_container", device.udid, bundleID, "groups"])
        } catch {
            throw Failure.appNotInstalled(bundleID: bundleID, device: device)
        }

        var groups: [String: URL] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let identifier = parts[0].trimmingCharacters(in: .whitespaces)
            let path = parts[1].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            groups[identifier] = URL(fileURLWithPath: path)
        }
        return groups
    }

    /// The directory the Files app shows as "On My iPhone".
    public static func filesLocalStorage(device: Simulator) throws -> URL {
        let groups = try appGroups(device: device, bundleID: filesBundleID)
        guard let container = groups[filesLocalStorageGroup] else {
            throw Failure.groupMissing(group: filesLocalStorageGroup, bundleID: filesBundleID)
        }
        return container.appendingPathComponent("File Provider Storage", isDirectory: true)
    }
}
