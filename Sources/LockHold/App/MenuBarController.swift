import AppKit
import OSLog

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LockHold",
        category: "AutoLock"
    )
    private let assertionController: AutoLockAssertionController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem()
    private let sleepController = SystemSleepController()
    private let sleepItem = NSMenuItem()
    private let sleepStatusItem = NSMenuItem()
    private let helperSettingsItem = NSMenuItem()
    private let cancelSetupItem = NSMenuItem()
    private let removeHelperItem = NSMenuItem()
    private var approvalTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?

    init(assertionController: AutoLockAssertionController) {
        self.assertionController = assertionController
        super.init()

        configureMenu()
        configureStatusItem()
        sleepController.onChange = { [weak self] in self?.refreshState() }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sleepController.resumeAfterApproval()
                await self?.sleepController.refresh()
                self?.presentSleepError()
            }
        }
        refreshState()
        Task { await sleepController.refresh() }
    }

    func prepareForTermination() {
        approvalTask?.cancel()
        sleepController.cancelPendingRequest()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        appearanceObservation?.invalidate()
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
        // Mixed red/template-style indicators need a fresh image when the bar changes theme.
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshState() }
        }
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        toggleItem.target = self
        toggleItem.action = #selector(toggleAutoLockOverride)
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        sleepItem.target = self
        sleepItem.action = #selector(changeSystemSleep(_:))
        menu.addItem(sleepItem)
        let explanationItem = NSMenuItem(
            title: "Includes closing the lid", action: nil, keyEquivalent: "")
        explanationItem.isEnabled = false
        menu.addItem(explanationItem)
        sleepStatusItem.isEnabled = false
        menu.addItem(sleepStatusItem)

        helperSettingsItem.title = "Sleep Helper Settings…"
        helperSettingsItem.target = self
        helperSettingsItem.action = #selector(openHelperSettings)
        menu.addItem(helperSettingsItem)
        cancelSetupItem.title = "Cancel Pending Sleep Change"
        cancelSetupItem.target = self
        cancelSetupItem.action = #selector(cancelSleepSetup)
        menu.addItem(cancelSetupItem)
        removeHelperItem.title = "Remove Sleep Helper…"
        removeHelperItem.target = self
        removeHelperItem.action = #selector(removeSleepHelper)
        menu.addItem(removeHelperItem)

        menu.addItem(.separator())

        let exitItem = NSMenuItem(title: "Exit", action: #selector(exitApp), keyEquivalent: "q")
        exitItem.target = self
        menu.addItem(exitItem)
    }

    private func refreshState() {
        let overrideIsActive = assertionController.isPreventingAutoLock

        toggleItem.title = overrideIsActive ? "Enable Auto-Lock" : "Disable Auto-Lock"
        let sleepDisabled = sleepController.sleepDisabled == true
        statusItem.button?.image = StatusIcon.image(
            overrideIsActive: overrideIsActive, systemSleepDisabled: sleepDisabled
        )
        statusItem.button?.contentTintColor = nil
        let status =
            overrideIsActive ? "Auto-lock override active" : "Auto-lock follows macOS settings"
        let sleepStatus: String
        if sleepController.isAwaitingApproval {
            sleepStatus = "Waiting for helper approval in System Settings"
        } else if sleepController.isBusy {
            sleepStatus = "Changing system sleep…"
        } else if sleepController.sleepDisabled == nil {
            sleepStatus = "System sleep status unavailable"
        } else {
            sleepStatus =
                sleepDisabled ? "Sleep disabled until you turn it back on" : "Normal system sleep"
        }
        sleepItem.title = sleepDisabled ? "Enable System Sleep" : "Disable System Sleep"
        sleepItem.representedObject = !sleepDisabled
        if sleepController.helperStatus != .enabled { sleepItem.title += "…" }
        sleepItem.isEnabled = !sleepController.isBusy && !sleepController.isAwaitingApproval
        sleepStatusItem.title = sleepStatus
        sleepStatusItem.toolTip =
            "This system setting persists after quitting LockHold and restarting your Mac."
        helperSettingsItem.isHidden = sleepController.helperStatus == .notRegistered
        cancelSetupItem.isHidden = !sleepController.isAwaitingApproval
        removeHelperItem.isHidden = sleepController.helperStatus == .notRegistered
        removeHelperItem.isEnabled = !sleepController.isBusy
        statusItem.button?.toolTip = "LockHold: \(status); \(sleepStatus)"
        statusItem.button?.setAccessibilityLabel("LockHold: \(status); \(sleepStatus)")
        updateApprovalPolling()
    }

    func menuWillOpen(_ menu: NSMenu) {
        Task { await sleepController.refresh() }
    }

    private func updateApprovalPolling() {
        guard sleepController.isAwaitingApproval else {
            approvalTask?.cancel()
            approvalTask = nil
            return
        }
        guard approvalTask == nil else { return }
        approvalTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self else { return }
                await sleepController.resumeAfterApproval()
                presentSleepError()
            }
        }
    }

    @objc private func changeSystemSleep(_ sender: NSMenuItem) {
        // Capture the displayed action before asynchronous work can refresh the menu.
        guard let desired = sender.representedObject as? Bool else { return }
        Task {
            await sleepController.setSleepDisabled(desired)
            presentSleepError()
        }
    }

    @objc private func openHelperSettings() { sleepController.openHelperSettings() }

    @objc private func cancelSleepSetup() { sleepController.cancelPendingRequest() }

    @objc private func removeSleepHelper() {
        let alert = NSAlert()
        alert.messageText = "Remove Sleep Helper?"
        alert.informativeText =
            "This restores normal system sleep, including sleep when you close the lid, and removes LockHold's sleep helper. The Auto-Lock option remains available."
        alert.addButton(withTitle: "Remove Helper")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await sleepController.removeHelper()
            presentSleepError()
        }
    }

    private func presentSleepError() {
        guard let message = sleepController.errorMessage else { return }
        sleepController.clearError()
        let alert = NSAlert()
        alert.messageText = "System Sleep Change Failed"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
