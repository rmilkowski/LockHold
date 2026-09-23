import Darwin
import Foundation

public struct PMSetResult: Sendable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public protocol PMSetRunning: Sendable {
    func run(arguments: [String]) throws -> PMSetResult
}

/// The only executable this boundary can launch is Apple's pmset.
public struct PMSetRunner: PMSetRunning {
    public init() {}

    public func run(arguments: [String]) throws -> PMSetResult {
        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        // These fixed pmset operations produce only a small settings/error report.
        // Bound execution so a failed system tool cannot strand an XPC request.
        if finished.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            throw SleepControlError("macOS did not finish the sleep-setting request. Try again.")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return PMSetResult(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }
}

public struct PMSetClient: Sendable {
    private let runner: any PMSetRunning

    public init(runner: any PMSetRunning = PMSetRunner()) {
        self.runner = runner
    }

    public func readSleepDisabled() throws -> Bool {
        let result = try runner.run(arguments: ["-g"])
        guard result.status == 0 else {
            throw SleepControlError("Could not read the macOS sleep setting. \(result.output)")
        }
        return try Self.parseSleepDisabled(result.output)
    }

    public func setSleepDisabled(_ disabled: Bool) throws -> Bool {
        let result = try runner.run(arguments: ["-a", "disablesleep", disabled ? "1" : "0"])
        guard result.status == 0 else {
            throw SleepControlError("Could not change the macOS sleep setting. \(result.output)")
        }
        // pmset can report some failures in its output without a nonzero exit status.
        let actual = try readSleepDisabled()
        guard actual == disabled else {
            throw SleepControlError("macOS did not apply the requested sleep setting. Try again.")
        }
        return actual
    }

    public static func parseSleepDisabled(_ output: String) throws -> Bool {
        var values: [Bool] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            if words.first == "SleepDisabled" {
                guard words.count == 2, words[1] == "0" || words[1] == "1" else {
                    throw SleepControlError("macOS returned an unrecognised sleep-setting value.")
                }
                values.append(words[1] == "1")
            }
        }
        if values.count == 1, let disabled = values.first {
            return disabled
        }
        // An unset system preference is omitted by pmset and means normal sleep.
        // Require a recognisable report before interpreting that absence as a default.
        if values.isEmpty,
            output.contains("System-wide power settings:") || output.contains("Currently in use:")
        {
            return false
        }
        throw SleepControlError("Could not determine the macOS sleep setting.")
    }
}
