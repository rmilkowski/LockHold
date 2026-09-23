import AppKit

if CommandLine.arguments.dropFirst() == ["--probe-sleep-helper"] {
    Task { @MainActor in
        do {
            let disabled = try await SleepHelperClient().readSleepDisabled()
            print(
                "Verified signed root helper. SleepDisabled=\(disabled ? 1 : 0). No settings changed."
            )
            exit(EXIT_SUCCESS)
        } catch {
            print("Sleep helper probe failed: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
    }
    dispatchMain()
}

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.run()
