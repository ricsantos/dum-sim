import Foundation

/// Thin wrapper around `xcrun simctl`.
public enum Simctl {
    public struct CommandFailure: LocalizedError {
        public let arguments: [String]
        public let status: Int32
        public let output: String

        public var errorDescription: String? {
            let command = (["xcrun", "simctl"] + arguments).joined(separator: " ")
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "`\(command)` exited with status \(status)."
                : "`\(command)` exited with status \(status):\n\(detail)"
        }
    }

    /// Runs `xcrun simctl <arguments>` and returns stdout. Throws on a non-zero exit.
    @discardableResult
    public static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(decoding: outData, as: UTF8.self)
        let err = String(decoding: errData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw CommandFailure(
                arguments: arguments,
                status: process.terminationStatus,
                output: err.isEmpty ? out : err
            )
        }
        return out
    }
}

extension Simctl {
    /// A PNG of the device's screen. `simctl` only writes to a path, never stdout.
    public static func screenshot(device: Simulator) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dum-sim-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try run(["io", device.udid, "screenshot", "--type=png", url.path])
        return try Data(contentsOf: url)
    }
}
