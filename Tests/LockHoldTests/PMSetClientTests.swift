import Foundation
import LockHoldCore
import Security
import Testing

struct PMSetClientTests {
    @Test(arguments: ["0", "1"])
    func parsesActualSystemFlag(value: String) throws {
        #expect(
            try PMSetClient.parseSleepDisabled(
                "System-wide power settings:\n SleepDisabled\t\t\(value)\n") == (value == "1"))
    }

    @Test func unsetPreferenceUsesMacOSDefault() throws {
        #expect(try !PMSetClient.parseSleepDisabled("Currently in use:\n sleep 1\n"))
    }

    @Test(arguments: [
        "", "permission denied", "SleepDisabled 2", "SleepDisabled 1 extra",
        "SleepDisabled 0\nSleepDisabled 1",
    ])
    func rejectsUnknownOrAmbiguousReports(report: String) {
        #expect(throws: SleepControlError.self) { try PMSetClient.parseSleepDisabled(report) }
    }

    @Test func sendsOnlyFixedCommandAndVerifiesIt() throws {
        let runner = FakePMSetRunner(results: [
            PMSetResult(status: 0, output: ""),
            PMSetResult(status: 0, output: "SleepDisabled 1"),
        ])
        #expect(try PMSetClient(runner: runner).setSleepDisabled(true))
        #expect(runner.arguments == [["-a", "disablesleep", "1"], ["-g"]])
    }

    @Test func successfulExitWithoutChangedStateIsAFailure() {
        let runner = FakePMSetRunner(results: [
            PMSetResult(status: 0, output: "must be run as root"),
            PMSetResult(status: 0, output: "SleepDisabled 0"),
        ])
        #expect(throws: SleepControlError.self) {
            try PMSetClient(runner: runner).setSleepDisabled(true)
        }
    }

    @Test func failedWriteDoesNotReportSuccess() {
        let runner = FakePMSetRunner(results: [PMSetResult(status: 1, output: "permission denied")])
        #expect(throws: SleepControlError.self) {
            try PMSetClient(runner: runner).setSleepDisabled(false)
        }
        #expect(runner.arguments == [["-a", "disablesleep", "0"]])
    }

    @Test func signingRequirementsAreValidAndPinBothPeers() throws {
        for identifier in [
            SleepHelperConfiguration.appIdentifier, SleepHelperConfiguration.identifier,
        ] {
            let requirement = try CodeSigningIdentity.requirement(
                identifier: identifier, teamIdentifier: "ABCDE12345")
            var parsed: SecRequirement?
            #expect(
                SecRequirementCreateWithString(requirement as CFString, [], &parsed)
                    == errSecSuccess)
            #expect(parsed != nil)
            #expect(requirement.contains("anchor apple generic"))
            #expect(requirement.contains(identifier))
            #expect(requirement.contains("ABCDE12345"))
        }
    }

    @Test func rejectsUntrustedRequirementInputs() {
        #expect(throws: SleepControlError.self) {
            try CodeSigningIdentity.requirement(identifier: "any.app", teamIdentifier: "ABCDE12345")
        }
        #expect(throws: SleepControlError.self) {
            try CodeSigningIdentity.requirement(
                identifier: SleepHelperConfiguration.appIdentifier, teamIdentifier: "\" or true")
        }
    }
}

private final class FakePMSetRunner: PMSetRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [PMSetResult]
    private(set) var arguments: [[String]] = []

    init(results: [PMSetResult]) { self.results = results }

    func run(arguments: [String]) throws -> PMSetResult {
        lock.lock()
        defer { lock.unlock() }
        self.arguments.append(arguments)
        guard !results.isEmpty else { throw SleepControlError("Unexpected command") }
        return results.removeFirst()
    }
}
