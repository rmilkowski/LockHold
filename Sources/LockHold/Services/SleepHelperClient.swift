import Foundation
import LockHoldCore

protocol SleepSettingReading: Sendable {
    func readSleepDisabled() async throws -> Bool
}

protocol SleepSettingWriting: Sendable {
    func setSleepDisabled(_ disabled: Bool) async throws -> Bool
}

struct LocalSleepSettingReader: SleepSettingReading {
    func readSleepDisabled() async throws -> Bool {
        try await Task.detached(priority: .utility) {
            try PMSetClient().readSleepDisabled()
        }.value
    }
}

struct SleepHelperClient: SleepSettingWriting {
    func setSleepDisabled(_ disabled: Bool) async throws -> Bool {
        try await request(disabled: disabled)
    }

    /// Also used by the read-only integration probe; it verifies the peer is root.
    func readSleepDisabled() async throws -> Bool {
        try await request(disabled: nil)
    }

    private func request(disabled: Bool?) async throws -> Bool {
        let team = try CodeSigningIdentity.currentTeamIdentifier()
        let requirement = try CodeSigningIdentity.requirement(
            identifier: SleepHelperConfiguration.identifier, teamIdentifier: team
        )
        return try await withCheckedThrowingContinuation { continuation in
            SleepHelperRequest(continuation: continuation, requirement: requirement).start(
                disabled: disabled)
        }
    }
}

/// Owns one connection and completes its continuation exactly once, including on timeout.
private final class SleepHelperRequest: @unchecked Sendable {
    private let connection = NSXPCConnection(
        machServiceName: SleepHelperConfiguration.identifier, options: .privileged
    )
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, any Error>?

    init(continuation: CheckedContinuation<Bool, any Error>, requirement: String) {
        self.continuation = continuation
        connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.setCodeSigningRequirement(requirement)
    }

    func start(disabled: Bool?) {
        connection.interruptionHandler = { [self] in
            finish(.failure(SleepControlError("The sleep helper disconnected. Try again.")))
        }
        connection.invalidationHandler = { [self] in
            finish(
                .failure(
                    SleepControlError(
                        "The sleep helper is unavailable. Check its approval in System Settings.")))
        }
        connection.resume()
        // A write and its verification each have their own bounded pmset execution.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [self] in
            finish(
                .failure(
                    SleepControlError(
                        "The sleep helper did not respond. Check its approval in System Settings and try again."
                    )))
        }
        let proxy = connection.remoteObjectProxyWithErrorHandler { [self] error in
            finish(
                .failure(
                    SleepControlError(
                        "Could not contact the sleep helper. \(error.localizedDescription)")))
        }
        guard let helper = proxy as? SleepHelperProtocol else {
            finish(.failure(SleepControlError("The sleep helper returned an invalid connection.")))
            return
        }
        let reply: @Sendable (Bool, Int, String?) -> Void = { [self] value, version, message in
            guard connection.effectiveUserIdentifier == 0,
                version == SleepHelperConfiguration.protocolVersion
            else {
                finish(
                    .failure(
                        SleepControlError(
                            "The sleep helper's identity or version did not match. Reinstall LockHold."
                        )))
                return
            }
            if let message {
                finish(.failure(SleepControlError(message)))
            } else {
                finish(.success(value))
            }
        }
        if let disabled {
            helper.setSleepDisabled(disabled, reply: reply)
        } else {
            helper.readState(reply: reply)
        }
    }

    private func finish(_ result: Result<Bool, any Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        connection.invalidate()
        pending.resume(with: result)
    }
}
