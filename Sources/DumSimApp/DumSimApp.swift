import AppKit

@main
enum DumSimApp {
    // NSApplication holds its delegate weakly, so the app keeps its own reference.
    @MainActor static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
