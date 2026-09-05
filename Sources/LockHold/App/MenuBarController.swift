import AppKit
import OSLog

@MainActor
final class MenuBarController: NSObject {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LockHold",
        category: "AutoLock"
    )
    private let assertionController: AutoLockAssertionController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem()

    init(assertionController: AutoLockAssertionController) {
        self.assertionController = assertionController
        super.init()

        configureMenu()
        configureStatusItem()
        refreshState()
    }

    func prepareForTermination() {
        do {
            try assertionController.disableAutoLockOverride()
        } catch {
            // Termination must continue: macOS cleans up process-owned assertions on exit.
            logger.error(
                "Assertion cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func configureStatusItem() {
        statusItem.menu = menu

        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
    }

    private func configureMenu() {
        toggleItem.target = self
        toggleItem.action = #selector(toggleAutoLockOverride)
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let exitItem = NSMenuItem(title: "Exit", action: #selector(exitApp), keyEquivalent: "q")
        exitItem.target = self
        menu.addItem(exitItem)
    }

    private func refreshState() {
        let overrideIsActive = assertionController.isPreventingAutoLock

        toggleItem.title = overrideIsActive ? "Enable Auto-Lock" : "Disable Auto-Lock"
        statusItem.button?.image = StatusIcon.image(overrideIsActive: overrideIsActive)
        statusItem.button?.contentTintColor = nil
        let status =
            overrideIsActive ? "Auto-lock override active" : "Auto-lock follows macOS settings"
        statusItem.button?.toolTip = "LockHold: \(status)"
        statusItem.button?.setAccessibilityLabel("LockHold: \(status)")
    }

    @objc private func toggleAutoLockOverride() {
        do {
            try assertionController.toggleAutoLockOverride()
            logger.info(
                "Auto-lock override active: \(self.assertionController.isPreventingAutoLock)")
        } catch {
            logger.error("Assertion toggle failed: \(error.localizedDescription, privacy: .public)")
            presentError(error)
        }

        refreshState()
    }

    @objc private func exitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Auto-Lock Toggle Failed"
        alert.informativeText = error.localizedDescription
        if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
            alert.informativeText += "\n\n\(suggestion)"
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
