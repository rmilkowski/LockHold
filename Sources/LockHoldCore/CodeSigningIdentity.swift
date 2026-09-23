import Foundation
import Security

public enum CodeSigningIdentity {
    public static func currentTeamIdentifier() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let information = information as? [String: Any],
            let team = information[kSecCodeInfoTeamIdentifier as String] as? String,
            isValidTeamIdentifier(team)
        else {
            throw SleepControlError(
                "Sleep control requires a signed build of LockHold. Build and install it with an Apple Development or Developer ID signing identity."
            )
        }
        return team
    }

    public static func requirement(identifier: String, teamIdentifier: String) throws -> String {
        guard isValidTeamIdentifier(teamIdentifier),
            identifier == SleepHelperConfiguration.appIdentifier
                || identifier == SleepHelperConfiguration.identifier
        else {
            throw SleepControlError("Invalid sleep-helper signing identity.")
        }
        // Both peers are pinned to the same Apple-issued team and their exact identifier.
        // Ad-hoc signatures and an identifier alone are not an authorization boundary.
        return "anchor apple generic and identifier \"\(identifier)\" "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\" "
            + "and !(entitlement[\"com.apple.security.get-task-allow\"] exists)"
    }

    private static func isValidTeamIdentifier(_ value: String) -> Bool {
        value.count == 10
            && value.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }
}
