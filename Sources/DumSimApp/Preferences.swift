import DumSimKit
import Foundation

/// What the menu remembers between launches.
final class Preferences {
    private enum Key {
        static let deviceUDID = "targetDeviceUDID"
        static let destination = "destinationOverride"
        static let openAfterDrop = "openAfterDrop"
    }

    private let defaults = UserDefaults.standard

    /// `nil` means "whichever simulator is booted".
    var deviceUDID: String? {
        get { defaults.string(forKey: Key.deviceUDID) }
        set { defaults.set(newValue, forKey: Key.deviceUDID) }
    }

    /// "auto", "photos" or "files".
    var destinationChoice: String {
        get { defaults.string(forKey: Key.destination) ?? "auto" }
        set { defaults.set(newValue, forKey: Key.destination) }
    }

    var openAfterDrop: Bool {
        get { defaults.bool(forKey: Key.openAfterDrop) }
        set { defaults.set(newValue, forKey: Key.openAfterDrop) }
    }

    var forcedDestination: Destination? {
        switch destinationChoice {
        case "photos": return .photos
        case "files": return .files
        default: return nil
        }
    }
}
