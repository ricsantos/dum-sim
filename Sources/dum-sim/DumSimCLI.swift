import DumSimKit
import Foundation

@main
struct DumSimCLI {
    static let usage = """
    dum-sim — drop files onto an iOS simulator from the command line.

    USAGE
      dum-sim [options] <file>...      Copy files into a simulator.
      dum-sim devices                  List available simulators.
      dum-sim --help                   Show this text.

    OPTIONS
      -d, --device <name|udid>   Target simulator. Default: the booted one.
      -t, --to <where>           Force a destination: photos, files, or app.
          --app <bundle-id>      App container to copy into. Implies --to app.
          --path <subpath>       Subpath inside the app container. Default: Documents.
      -o, --open                 Launch the destination app after the copy.
      -q, --quiet                Print nothing on success.

    ROUTING
      Images, videos and vCards go to Photos through `simctl addmedia`.
      Everything else goes to "On My iPhone" in the Files app.
      A file that addmedia refuses falls back to Files.

    EXAMPLES
      dum-sim ~/Pictures/*.png
      dum-sim --to files backup.sqlite
      dum-sim --app com.example.MyApp --path Documents seed.json
      dum-sim -d "iPhone 18 Pro" -o photo.heic
    """

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.isEmpty {
            print(usage)
            exit(1)
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            exit(0)
        }
        if arguments.first == "devices" {
            listDevices()
        }

        importFiles(arguments)
    }

    // MARK: - Commands

    static func listDevices() -> Never {
        do {
            let devices = try Simulator.all().sorted {
                if $0.isBooted != $1.isBooted { return $0.isBooted }
                return ($0.runtime, $0.name) < ($1.runtime, $1.name)
            }
            guard !devices.isEmpty else {
                print("No simulators available.")
                exit(0)
            }
            let width = devices.map(\.displayName.count).max() ?? 0
            for device in devices {
                let marker = device.isBooted ? "●" : " "
                let name = device.displayName.padding(toLength: width, withPad: " ", startingAt: 0)
                print("\(marker) \(name)  \(device.udid)  \(device.state)")
            }
            exit(0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func importFiles(_ arguments: [String]) -> Never {
        var deviceQuery: String?
        var forcedDestination: String?
        var appBundleID: String?
        var appSubpath = "Documents"
        var shouldOpen = false
        var quiet = false
        var paths: [String] = []

        var index = 0
        func nextValue(_ flag: String) -> String {
            let next = index + 1
            guard next < arguments.count else { fail("\(flag) needs a value.") }
            index = next
            return arguments[next]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-d", "--device": deviceQuery = nextValue(argument)
            case "-t", "--to": forcedDestination = nextValue(argument).lowercased()
            case "--app": appBundleID = nextValue(argument)
            case "--path": appSubpath = nextValue(argument)
            case "-o", "--open": shouldOpen = true
            case "-q", "--quiet": quiet = true
            default:
                if argument.hasPrefix("-") && argument.count > 1 {
                    fail("Unknown option \(argument). Run `dum-sim --help`.")
                }
                paths.append(argument)
            }
            index += 1
        }

        guard !paths.isEmpty else { fail("Give at least one file. Run `dum-sim --help`.") }

        let destination: Destination?
        switch forcedDestination {
        case nil:
            destination = appBundleID.map { .app(bundleID: $0, subpath: appSubpath) }
        case "photos", "photo":
            destination = .photos
        case "files", "file":
            destination = .files
        case "app":
            guard let appBundleID else { fail("--to app needs --app <bundle-id>.") }
            destination = .app(bundleID: appBundleID, subpath: appSubpath)
        default:
            fail("Unknown destination \"\(forcedDestination ?? "")\". Use photos, files or app.")
        }

        let device: Simulator
        do {
            device = try Simulator.resolve(deviceQuery)
        } catch {
            fail(error.localizedDescription)
        }

        let urls = paths.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL
        }
        let report = Importer.import(urls, into: device, destination: destination)

        if !quiet {
            for result in report.results {
                let note = result.fellBackToFiles ? " (Photos refused it)" : ""
                let placed = result.placedAt.map { " -> \($0.path)" } ?? ""
                print("\(result.source.lastPathComponent) -> \(result.destination.label)\(note)\(placed)")
            }
            if !report.results.isEmpty {
                print("\(report.results.count) file(s) copied to \(device.displayName).")
            }
        }

        for failure in report.failures {
            FileHandle.standardError.write(
                Data("dum-sim: \(failure.source.lastPathComponent): \(failure.message)\n".utf8)
            )
        }

        if shouldOpen, let first = report.results.first {
            try? Importer.open(first.destination, on: device)
        }

        exit(report.failures.isEmpty ? 0 : 1)
    }

    // MARK: - Helpers

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("dum-sim: \(message)\n".utf8))
        exit(1)
    }
}
