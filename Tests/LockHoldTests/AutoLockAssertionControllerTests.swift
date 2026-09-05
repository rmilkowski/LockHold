import IOKit.pwr_mgt
import Testing

@testable import LockHold

struct AutoLockAssertionControllerTests {
    @Test func startsInactiveAndReleaseIsANoOp() throws {
        let client = TestPowerAssertionClient()
        let controller = AutoLockAssertionController(client: client)

        #expect(!controller.isPreventingAutoLock)
        try controller.disableAutoLockOverride()
        #expect(client.creationCount == 0)
        #expect(client.releasedIDs.isEmpty)
    }

    @Test func repeatedEnableOwnsOnlyOneAssertion() throws {
        let client = TestPowerAssertionClient()
        let controller = AutoLockAssertionController(client: client)

        try controller.enableAutoLockOverride()
        try controller.enableAutoLockOverride()

        #expect(controller.isPreventingAutoLock)
        #expect(client.creationCount == 1)
    }

    @Test func toggleReleasesTheOwnedAssertionAndCanStartAgain() throws {
        let client = TestPowerAssertionClient()
        let controller = AutoLockAssertionController(client: client)

        try controller.toggleAutoLockOverride()
        #expect(controller.isPreventingAutoLock)
        try controller.toggleAutoLockOverride()
        #expect(!controller.isPreventingAutoLock)
        #expect(client.releasedIDs == [42])

        client.creationResult = .success(43)
        try controller.toggleAutoLockOverride()
        try controller.toggleAutoLockOverride()
        #expect(client.creationCount == 2)
        #expect(client.releasedIDs == [42, 43])
    }

    @Test func failedCreationStaysInactiveAndAllowsRetry() throws {
        let client = TestPowerAssertionClient()
        client.creationResult = .failure(.creationFailed(kIOReturnError))
        let controller = AutoLockAssertionController(client: client)

        #expect(throws: PowerAssertionError.creationFailed(kIOReturnError)) {
            try controller.enableAutoLockOverride()
        }
        #expect(!controller.isPreventingAutoLock)
        try controller.disableAutoLockOverride()
        #expect(client.releasedIDs.isEmpty)

        client.creationResult = .success(42)
        try controller.enableAutoLockOverride()
        #expect(controller.isPreventingAutoLock)
        #expect(client.creationCount == 2)
    }

    @Test func failedReleasePreservesOwnershipAndAllowsRetry() throws {
        let client = TestPowerAssertionClient()
        let controller = AutoLockAssertionController(client: client)
        try controller.enableAutoLockOverride()
        client.releaseError = .releaseFailed(kIOReturnError)

        #expect(throws: PowerAssertionError.releaseFailed(kIOReturnError)) {
            try controller.toggleAutoLockOverride()
        }
        #expect(controller.isPreventingAutoLock)
        try controller.enableAutoLockOverride()
        #expect(client.creationCount == 1)

        client.releaseError = nil
        try controller.toggleAutoLockOverride()
        #expect(!controller.isPreventingAutoLock)
        #expect(client.releasedIDs == [42, 42])
    }

    @Test func deinitializationReleasesAnActiveAssertion() throws {
        let client = TestPowerAssertionClient()

        do {
            let controller = AutoLockAssertionController(client: client)
            try controller.enableAutoLockOverride()
        }

        #expect(client.releasedIDs == [42])
    }

    @Test func deinitializationRetriesAfterAReleaseFailure() throws {
        let client = TestPowerAssertionClient()

        do {
            let controller = AutoLockAssertionController(client: client)
            try controller.enableAutoLockOverride()
            client.releaseError = .releaseFailed(kIOReturnError)
            #expect(throws: PowerAssertionError.releaseFailed(kIOReturnError)) {
                try controller.disableAutoLockOverride()
            }
            client.releaseError = nil
        }

        #expect(client.releasedIDs == [42, 42])
    }

    @Test func successfulReleaseIsNotRepeatedAtDeinitialization() throws {
        let client = TestPowerAssertionClient()

        do {
            let controller = AutoLockAssertionController(client: client)
            try controller.enableAutoLockOverride()
            try controller.disableAutoLockOverride()
            try controller.disableAutoLockOverride()
        }

        #expect(client.releasedIDs == [42])
    }
}

private final class TestPowerAssertionClient: PowerAssertionClient {
    var creationResult: Result<IOPMAssertionID, PowerAssertionError> = .success(42)
    var releaseError: PowerAssertionError?
    private(set) var creationCount = 0
    private(set) var releasedIDs: [IOPMAssertionID] = []

    func createDisplaySleepAssertion() throws -> IOPMAssertionID {
        creationCount += 1
        return try creationResult.get()
    }

    func releaseAssertion(_ assertionID: IOPMAssertionID) throws {
        releasedIDs.append(assertionID)
        if let releaseError {
            throw releaseError
        }
    }
}
