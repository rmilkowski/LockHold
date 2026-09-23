import Foundation
import LockHoldCore
import OSLog
import SystemConfiguration

private let logger = Logger(
    subsystem: SleepHelperConfiguration.appIdentifier, category: "SleepHelper")

/// All clients share one queue so writes and their verification cannot overlap.
private let operationQueue = DispatchQueue(label: "dev.codex.LockHold.SleepHelper.operations")

private final class SleepHelperSession: NSObject, SleepHelperProtocol, @unchecked Sendable {
    let userID: uid_t
    private let client = PMSetClient()

    init(userID: uid_t) {
        self.userID = userID
    }

    func readState(reply: @escaping @Sendable (Bool, Int, String?) -> Void) {
        perform(reply: reply) { try self.client.readSleepDisabled() }
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (Bool, Int, String?) -> Void)
    {
        perform(reply: reply) { try self.client.setSleepDisabled(disabled) }
    }

    private func perform(
        reply: @escaping @Sendable (Bool, Int, String?) -> Void,
        operation: @escaping @Sendable () throws -> Bool
    ) {
        operationQueue.async {
            do {
                var consoleUser: uid_t = 0
                guard SCDynamicStoreCopyConsoleUser(nil, &consoleUser, nil) != nil,
                    consoleUser != 0, consoleUser == self.userID
                else {
                    throw SleepControlError(
                        "Sleep settings can only be changed from the active Mac login.")
                }
                reply(try operation(), SleepHelperConfiguration.protocolVersion, nil)
            } catch {
                logger.error(
                    "Sleep request failed: \(error.localizedDescription, privacy: .public)")
                reply(false, SleepHelperConfiguration.protocolVersion, error.localizedDescription)
            }
        }
    }
}

private final class SleepHelperListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var connections = 0
    private var generation = 0

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        lock.lock()
        connections += 1
        generation += 1
        lock.unlock()
        connection.exportedInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.exportedObject = SleepHelperSession(userID: connection.effectiveUserIdentifier)
        connection.invalidationHandler = { [self] in
            lock.lock()
            connections -= 1
            generation += 1
            lock.unlock()
            scheduleIdleExit()
        }
        connection.resume()
        return true
    }

    func scheduleIdleExit() {
        lock.lock()
        let expectedGeneration = generation
        lock.unlock()
        // Exit when idle; launchd starts the bundled helper on the next request.
        // This also covers clients rejected before the delegate is called, so an
        // old helper executable cannot remain running across app upgrades.
        operationQueue.asyncAfter(deadline: .now() + 1) { [self] in
            lock.lock()
            let shouldExit = connections == 0 && generation == expectedGeneration
            if shouldExit { exit(EXIT_SUCCESS) }
            lock.unlock()
        }
    }
}

do {
    guard geteuid() == 0 else {
        throw SleepControlError(
            "The sleep helper must be started by macOS after administrator approval.")
    }
    let team = try CodeSigningIdentity.currentTeamIdentifier()
    let listener = NSXPCListener(machServiceName: SleepHelperConfiguration.identifier)
    let delegate = SleepHelperListener()
    listener.setConnectionCodeSigningRequirement(
        try CodeSigningIdentity.requirement(
            identifier: SleepHelperConfiguration.appIdentifier, teamIdentifier: team
        )
    )
    listener.delegate = delegate
    listener.resume()
    delegate.scheduleIdleExit()
    logger.info("Sleep helper ready")
    withExtendedLifetime((listener, delegate)) { dispatchMain() }
} catch {
    logger.error("Sleep helper could not start: \(error.localizedDescription, privacy: .public)")
    exit(EXIT_FAILURE)
}
