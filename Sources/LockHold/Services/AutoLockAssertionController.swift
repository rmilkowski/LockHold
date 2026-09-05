import IOKit.pwr_mgt

/// Owns one temporary display-sleep assertion for the menu bar controller.
///
/// Instances stay with their owner and are not shared across actors.
final class AutoLockAssertionController {
    private let client: any PowerAssertionClient
    private var assertionID: IOPMAssertionID?

    init(client: any PowerAssertionClient = IOKitPowerAssertionClient()) {
        self.client = client
    }

    var isPreventingAutoLock: Bool {
        assertionID != nil
    }

    func enableAutoLockOverride() throws {
        guard assertionID == nil else {
            return
        }

        assertionID = try client.createDisplaySleepAssertion()
    }

    func disableAutoLockOverride() throws {
        guard let assertionID else {
            return
        }

        // Keep ownership on failure so the UI stays accurate and the user can retry.
        try client.releaseAssertion(assertionID)
        self.assertionID = nil
    }

    func toggleAutoLockOverride() throws {
        if isPreventingAutoLock {
            try disableAutoLockOverride()
        } else {
            try enableAutoLockOverride()
        }
    }

    deinit {
        // macOS also releases process-owned assertions when the process exits.
        try? disableAutoLockOverride()
    }
}
