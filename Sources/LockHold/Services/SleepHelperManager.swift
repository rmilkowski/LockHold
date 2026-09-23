import Foundation
import LockHoldCore
import ServiceManagement

enum SleepHelperStatus {
    case notRegistered
    case requiresApproval
    case enabled
}

@MainActor
protocol SleepHelperManaging {
    var status: SleepHelperStatus { get }
    func register() throws
    func unregister() async throws
    func openSettings()
}

@MainActor
final class SleepHelperManager: SleepHelperManaging {
    private let service = SMAppService.daemon(plistName: SleepHelperConfiguration.plistName)

    var status: SleepHelperStatus {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .notRegistered
        }
    }

    func register() throws {
        _ = try CodeSigningIdentity.currentTeamIdentifier()
        guard Bundle.main.bundleIdentifier == SleepHelperConfiguration.appIdentifier,
            Bundle.main.bundleURL.pathExtension == "app",
            Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications"
        else {
            throw SleepControlError(
                "Install LockHold in Applications before setting up sleep control.")
        }
        if service.status == .enabled || service.status == .requiresApproval { return }
        do {
            try service.register()
        } catch {
            // macOS can report registration as an error while the approval is pending.
            guard service.status == .requiresApproval else { throw error }
        }
    }

    func unregister() async throws {
        try await service.unregister()
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
