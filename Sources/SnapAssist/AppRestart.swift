import AppKit
import Darwin

/// Relaunches this bundle after the old instance exits, without shell parsing.
enum AppRestart {
    static let helperArgument = "--relaunch-after"

    static func openArguments(for bundle: URL) -> [String] {
        ["--", bundle.path]
    }

    static func restart() {
        guard let executable = Bundle.main.executableURL else { return }
        let helper = Process()
        helper.executableURL = executable
        helper.arguments = [helperArgument, String(getpid())]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }

    /// Internal CLI path: called before NSApplication is initialized.
    static func runHelper(arguments: [String]) -> Int32 {
        guard arguments.count == 3,
              let parent = pid_t(arguments[2]), parent > 1, parent != getpid(),
              Bundle.main.bundleURL.pathExtension == "app" else { return 2 }
        return waitAndOpen(parent: parent, bundle: Bundle.main.bundleURL)
    }

    static func waitAndOpen(
        parent: pid_t, bundle: URL,
        timeout: TimeInterval = 10,
        parentExited: (pid_t) -> Bool = { kill($0, 0) == -1 && errno == ESRCH },
        uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        pause: () -> Void = { Thread.sleep(forTimeInterval: 0.05) },
        launch: ([String]) throws -> Void = { arguments in
            let opener = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = arguments
            try opener.run()
            opener.waitUntilExit()
            if opener.terminationStatus != 0 {
                throw NSError(domain: "SnapAssist.Restart", code: Int(opener.terminationStatus))
            }
        }
    ) -> Int32 {
        let deadline = uptime() + timeout
        while !parentExited(parent) {
            guard uptime() < deadline else { return 1 }
            pause()
        }
        do {
            try launch(openArguments(for: bundle))
            return 0
        } catch {
            return 1
        }
    }
}
