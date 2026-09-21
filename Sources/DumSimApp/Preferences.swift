import DumSimKit
import Foundation

/// What the menu remembers between launches.
final class Preferences {
    private enum Key {
        static let deviceUDID = "targetDeviceUDID"
        static let destination = "destinationOverride"
        static let openAfterDrop = "openAfterDrop"
        static let showDropWindow = "showDropWindow"
        static let autoShowWhileDragging = "autoShowWhileDragging"
        static let hasCustomPosition = "hasCustomPosition"
    }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [Key.autoShowWhileDragging: true])
    }

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

    /// Keeps the floating panel on screen between launches.
    var showDropWindow: Bool {
        get { defaults.bool(forKey: Key.showDropWindow) }
        set { defaults.set(newValue, forKey: Key.showDropWindow) }
    }

    /// Shows the panel by itself while a file drag is in progress.
    var autoShowWhileDragging: Bool {
        get { defaults.bool(forKey: Key.autoShowWhileDragging) }
        set { defaults.set(newValue, forKey: Key.autoShowWhileDragging) }
    }

    /// True once the user drags the panel somewhere. The panel then stays put.
    var hasCustomPosition: Bool {
        get { defaults.bool(forKey: Key.hasCustomPosition) }
        set { defaults.set(newValue, forKey: Key.hasCustomPosition) }
    }

    var forcedDestination: Destination? {
        switch destinationChoice {
        case "photos": return .photos
        case "files": return .files
        default: return nil
        }
    }
}
