import Foundation

public enum SleepHelperConfiguration {
    public static let appIdentifier = "dev.codex.LockHold"
    public static let identifier = "dev.codex.LockHold.SleepHelper"
    public static let plistName = identifier + ".plist"
    public static let executableName = "LockHoldSleepHelper"
    public static let protocolVersion = 1
}

/// Deliberately exposes no command strings, executable paths, or arbitrary arguments.
@objc public protocol SleepHelperProtocol {
    func readState(reply: @escaping @Sendable (Bool, Int, String?) -> Void)
    func setSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (Bool, Int, String?) -> Void)
}

public struct SleepControlError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
