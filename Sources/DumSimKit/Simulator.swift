import Foundation

/// One simulated device reported by `simctl list devices`.
public struct Simulator: Sendable, Hashable, Identifiable {
    public let udid: String
    public let name: String
    public let runtime: String
    public let state: String

    public var id: String { udid }
    public var isBooted: Bool { state == "Booted" }

    public var displayName: String { "\(name) (\(runtime))" }

    public init(udid: String, name: String, runtime: String, state: String) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
        self.state = state
    }
}

extension Simulator {
    public enum LookupError: LocalizedError {
        case noBootedDevice
        case notFound(String)
        case ambiguous(String, [Simulator])

        public var errorDescription: String? {
            switch self {
            case .noBootedDevice:
                return "No simulator is booted. Boot one in Device Hub, or pass --device <name or UDID>."
            case .notFound(let query):
                return "No simulator matches \"\(query)\". Run `dum-sim devices` to see the list."
            case .ambiguous(let query, let matches):
                let list = matches.map { "  \($0.displayName)  \($0.udid)" }.joined(separator: "\n")
                return "\"\(query)\" matches more than one simulator:\n\(list)\nPass the UDID instead."
            }
        }
    }

    /// Every device known to CoreSimulator, newest runtime first.
    public static func all() throws -> [Simulator] {
        let json = try Simctl.run(["list", "devices", "--json"])
        guard let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = root["devices"] as? [String: [[String: Any]]]
        else {
            return []
        }

        var result: [Simulator] = []
        for (runtimeIdentifier, entries) in devices {
            let runtime = prettyRuntime(runtimeIdentifier)
            for entry in entries {
                guard entry["isAvailable"] as? Bool ?? true,
                      let udid = entry["udid"] as? String,
                      let name = entry["name"] as? String
                else { continue }
                result.append(
                    Simulator(
                        udid: udid,
                        name: name,
                        runtime: runtime,
                        state: entry["state"] as? String ?? "Unknown"
                    )
                )
            }
        }
        return result.sorted { ($0.runtime, $0.name) > ($1.runtime, $1.name) }
    }

    public static func booted() throws -> [Simulator] {
        try all().filter(\.isBooted)
    }

    /// Resolves a user-supplied device query. `nil` or "booted" picks the booted device.
    public static func resolve(_ query: String?) throws -> Simulator {
        let devices = try all()

        guard let query, query.lowercased() != "booted" else {
            let booted = devices.filter(\.isBooted)
            guard let first = booted.first else { throw LookupError.noBootedDevice }
            if booted.count > 1 { throw LookupError.ambiguous("booted", booted) }
            return first
        }

        if let exact = devices.first(where: { $0.udid.caseInsensitiveCompare(query) == .orderedSame }) {
            return exact
        }

        let byName = devices.filter { $0.name.caseInsensitiveCompare(query) == .orderedSame }
        let matches = byName.isEmpty
            ? devices.filter { $0.name.localizedCaseInsensitiveContains(query) }
            : byName

        // A booted match beats a shut down one of the same name.
        let booted = matches.filter(\.isBooted)
        let candidates = booted.isEmpty ? matches : booted

        switch candidates.count {
        case 0: throw LookupError.notFound(query)
        case 1: return candidates[0]
        default: throw LookupError.ambiguous(query, candidates)
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-0" -> "iOS 27.0"
    static func prettyRuntime(_ identifier: String) -> String {
        let tail = identifier.components(separatedBy: "SimRuntime.").last ?? identifier
        let parts = tail.components(separatedBy: "-")
        guard parts.count > 1 else { return tail }
        return "\(parts[0]) \(parts.dropFirst().joined(separator: "."))"
    }
}
