import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(assertionController: AutoLockAssertionController())
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.prepareForTermination()
    }
}
