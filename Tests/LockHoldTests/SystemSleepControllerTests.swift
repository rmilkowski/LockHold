import LockHoldCore
import Testing

@testable import LockHold

@MainActor
struct SystemSleepControllerTests {
    @Test(arguments: [false, true])
    func alreadyApprovedHelperChangesSettingWithoutRegistering(desired: Bool) async {
        let client = FakeSleepClient(disabled: !desired)
        let manager = FakeSleepManager(status: .enabled)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.setSleepDisabled(desired)
        #expect(controller.sleepDisabled == desired)
        #expect(manager.registerCalls == 0)
        #expect(await client.writes == [desired])
    }

    @Test(arguments: [false, true])
    func approvalDefersWriteThenResumesOnce(desired: Bool) async {
        let client = FakeSleepClient(disabled: !desired)
        let manager = FakeSleepManager(status: .notRegistered)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.setSleepDisabled(desired)
        #expect(controller.isAwaitingApproval)
        #expect(manager.settingsOpened)
        #expect(await client.writes.isEmpty)
        manager.status = .enabled
        await controller.resumeAfterApproval()
        await controller.resumeAfterApproval()
        #expect(controller.sleepDisabled == desired)
        #expect(!controller.isAwaitingApproval)
        #expect(await client.writes == [desired])
    }

    @Test func cancellationPreventsLaterApprovalFromChangingSettings() async {
        let client = FakeSleepClient()
        let manager = FakeSleepManager(status: .notRegistered)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.setSleepDisabled(true)
        controller.cancelPendingRequest()
        manager.status = .enabled
        await controller.resumeAfterApproval()
        #expect(await client.writes.isEmpty)
    }

    @Test func readsTerminalChangesAndDoesNotResetOnLaunch() async {
        let client = FakeSleepClient(disabled: true)
        let manager = FakeSleepManager(status: .notRegistered)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.refresh()
        #expect(controller.sleepDisabled == true)
        #expect(await client.writes.isEmpty)
        await client.setActualValue(false)
        await controller.refresh()
        #expect(controller.sleepDisabled == false)
    }

    @Test func failedWriteRefreshesActualStateAndAllowsRetry() async {
        let client = FakeSleepClient(failWrites: true)
        let controller = SystemSleepController(
            reader: client, writer: client, helper: FakeSleepManager(status: .enabled))
        await controller.setSleepDisabled(true)
        #expect(controller.sleepDisabled == false)
        #expect(controller.errorMessage != nil)
        #expect(!controller.isBusy)
        await client.allowWrites()
        await controller.setSleepDisabled(true)
        #expect(controller.sleepDisabled == true)
        #expect(controller.errorMessage == nil)
    }

    @Test func removalRestoresSleepBeforeUnregistering() async {
        let client = FakeSleepClient(disabled: true)
        let manager = FakeSleepManager(status: .enabled)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.removeHelper()
        #expect(await client.writes == [false])
        #expect(manager.unregisterCalls == 1)
        #expect(controller.sleepDisabled == false)
    }

    @Test func failedRestoreKeepsHelperAvailableForRecovery() async {
        let client = FakeSleepClient(disabled: true, failWrites: true)
        let manager = FakeSleepManager(status: .enabled)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.removeHelper()
        #expect(manager.unregisterCalls == 0)
        #expect(controller.sleepDisabled == true)
        #expect(controller.errorMessage != nil)
    }

    @Test func removalRefreshesASettingAlreadyRestoredInTerminal() async {
        let client = FakeSleepClient(disabled: true)
        let manager = FakeSleepManager(status: .enabled)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.refresh()
        #expect(controller.sleepDisabled == true)
        await client.setActualValue(false)
        await controller.removeHelper()
        #expect(controller.sleepDisabled == false)
        #expect(await client.writes.isEmpty)
        #expect(manager.unregisterCalls == 1)
    }

    @Test(arguments: [false, true])
    func externalChangeDoesNotReverseTheSelectedAction(desired: Bool) async {
        let client = FakeSleepClient(disabled: !desired)
        let manager = FakeSleepManager(status: .notRegistered)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.refresh()
        #expect(controller.sleepDisabled == !desired)

        // The user selects the displayed action after another app has already applied it.
        await client.setActualValue(desired)
        await controller.setSleepDisabled(desired)

        #expect(controller.sleepDisabled == desired)
        #expect(await client.writes.isEmpty)
        #expect(manager.registerCalls == 0)
        #expect(!manager.settingsOpened)
        #expect(!controller.isBusy)
    }

    @Test(arguments: [false, true])
    func approvalSkipsAChangeAlreadyAppliedInTerminal(desired: Bool) async {
        let client = FakeSleepClient(disabled: !desired)
        let manager = FakeSleepManager(status: .notRegistered)
        let controller = SystemSleepController(reader: client, writer: client, helper: manager)
        await controller.setSleepDisabled(desired)
        #expect(controller.isAwaitingApproval)

        await client.setActualValue(desired)
        manager.status = .enabled
        await controller.resumeAfterApproval()

        #expect(controller.sleepDisabled == desired)
        #expect(await client.writes.isEmpty)
        #expect(!controller.isAwaitingApproval)
        #expect(!controller.isBusy)
    }
}

private actor FakeSleepClient: SleepSettingReading, SleepSettingWriting {
    var disabled: Bool
    var failWrites: Bool
    var writes: [Bool] = []

    init(disabled: Bool = false, failWrites: Bool = false) {
        self.disabled = disabled
        self.failWrites = failWrites
    }

    func readSleepDisabled() async throws -> Bool { disabled }

    func setSleepDisabled(_ disabled: Bool) async throws -> Bool {
        writes.append(disabled)
        if failWrites { throw SleepControlError("Simulated write failure") }
        self.disabled = disabled
        return disabled
    }

    func setActualValue(_ disabled: Bool) { self.disabled = disabled }
    func allowWrites() { failWrites = false }
}

@MainActor
private final class FakeSleepManager: SleepHelperManaging {
    var status: SleepHelperStatus
    var registerCalls = 0
    var unregisterCalls = 0
    var settingsOpened = false

    init(status: SleepHelperStatus) { self.status = status }
    func register() throws { registerCalls += 1; status = .requiresApproval }
    func unregister() async throws { unregisterCalls += 1; status = .notRegistered }
    func openSettings() { settingsOpened = true }
}
