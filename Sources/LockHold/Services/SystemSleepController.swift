import Foundation
import LockHoldCore

@MainActor
final class SystemSleepController {
    private let reader: any SleepSettingReading
    private let writer: any SleepSettingWriting
    private let helper: any SleepHelperManaging
    private let now: @MainActor () -> ContinuousClock.Instant
    private var pendingValue: Bool?
    private var isReading = false
    private var revision = 0
    private var lastHelperStatusRead: ContinuousClock.Instant?

    private(set) var sleepDisabled: Bool?
    private(set) var helperStatus: SleepHelperStatus = .notRegistered
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    var onChange: (() -> Void)?

    var isAwaitingApproval: Bool { pendingValue != nil }

    @discardableResult
    private func readHelperStatus(force: Bool = true) -> SleepHelperStatus {
        let currentTime = now()
        if !force, let lastHelperStatusRead,
            lastHelperStatusRead.duration(to: currentTime) < .seconds(1)
        {
            return helperStatus
        }
        let status = helper.status
        helperStatus = status
        lastHelperStatusRead = currentTime
        return status
    }

    init(
        reader: any SleepSettingReading = LocalSleepSettingReader(),
        writer: any SleepSettingWriting = SleepHelperClient(),
        helper: any SleepHelperManaging = SleepHelperManager(),
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock().now }
    ) {
        self.reader = reader
        self.writer = writer
        self.helper = helper
        self.now = now
    }

    func refresh() async {
        guard !isBusy, !isReading else { return }
        isReading = true
        readHelperStatus(force: false)
        let readRevision = revision
        defer { isReading = false; onChange?() }
        do {
            let value = try await reader.readSleepDisabled()
            // A more recent write must not be overwritten by a read started earlier.
            if !isBusy && readRevision == revision { sleepDisabled = value }
        } catch {
            if !isBusy && readRevision == revision { sleepDisabled = nil }
        }
    }

    func setSleepDisabled(_ desired: Bool) async {
        guard !isBusy, pendingValue == nil else { return }
        revision += 1
        isBusy = true
        errorMessage = nil
        onChange?()
        defer { isBusy = false; onChange?() }
        do {
            let current = try await reader.readSleepDisabled()
            sleepDisabled = current
            guard current != desired else { return }
            if readHelperStatus() != .enabled {
                try helper.register()
                if readHelperStatus() != .enabled {
                    pendingValue = desired
                    helper.openSettings()
                    return
                }
            }
            sleepDisabled = try await writer.setSleepDisabled(desired)
        } catch {
            readHelperStatus()
            errorMessage = error.localizedDescription
            sleepDisabled = try? await reader.readSleepDisabled()
        }
    }

    func resumeAfterApproval() async {
        guard let desired = pendingValue, !isBusy else { return }
        guard readHelperStatus() == .enabled else { return }
        revision += 1
        pendingValue = nil
        isBusy = true
        errorMessage = nil
        onChange?()
        defer { isBusy = false; onChange?() }
        do {
            sleepDisabled = try await reader.readSleepDisabled()
            if sleepDisabled != desired {
                sleepDisabled = try await writer.setSleepDisabled(desired)
            }
        } catch {
            readHelperStatus()
            errorMessage = error.localizedDescription
            sleepDisabled = try? await reader.readSleepDisabled()
        }
    }

    func cancelPendingRequest() {
        pendingValue = nil
        onChange?()
    }

    func openHelperSettings() {
        helper.openSettings()
    }

    func clearError() {
        errorMessage = nil
    }

    /// The UI explicitly explains that removal first restores normal system sleep.
    func removeHelper() async {
        guard !isBusy else { return }
        revision += 1
        cancelPendingRequest()
        isBusy = true
        errorMessage = nil
        onChange?()
        defer { isBusy = false; onChange?() }
        do {
            let current = try await reader.readSleepDisabled()
            sleepDisabled = current
            if current {
                sleepDisabled = try await writer.setSleepDisabled(false)
            }
            try await helper.unregister()
            readHelperStatus()
        } catch {
            readHelperStatus()
            errorMessage = error.localizedDescription
            sleepDisabled = try? await reader.readSleepDisabled()
        }
    }
}
