import Foundation
import IOKit.pwr_mgt

/// The small IOKit boundary, replaceable in tests without changing system sleep state.
protocol PowerAssertionClient {
    func createDisplaySleepAssertion() throws -> IOPMAssertionID
    func releaseAssertion(_ assertionID: IOPMAssertionID) throws
}

struct IOKitPowerAssertionClient: PowerAssertionClient {
    func createDisplaySleepAssertion() throws -> IOPMAssertionID {
        var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "LockHold is preventing idle display sleep" as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.creationFailed(result)
        }

        return assertionID
    }

    func releaseAssertion(_ assertionID: IOPMAssertionID) throws {
        let result = IOPMAssertionRelease(assertionID)

        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.releaseFailed(result)
        }
    }
}

enum PowerAssertionError: LocalizedError, Equatable {
    case creationFailed(IOReturn)
    case releaseFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .creationFailed(let result):
            return "Could not disable auto-lock. IOKit returned \(result)."
        case .releaseFailed(let result):
            return "Could not release the auto-lock override. IOKit returned \(result)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .creationFailed:
            return "Try again. Your macOS sleep settings are still in control."
        case .releaseFailed:
            return "Try again, or quit LockHold to release the override."
        }
    }
}
