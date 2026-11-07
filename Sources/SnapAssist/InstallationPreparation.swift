import AppKit

/// Bounded, graceful shutdown of the installed copy before replacing its bundle.
enum InstallationPreparation {
    static func run() -> Int32 {
        let destination = URL(fileURLWithPath: "/Applications/SnapAssist.app").standardizedFileURL
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.frank.snapassist")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.bundleURL?.standardizedFileURL == destination }
        for application in applications {
            if !application.terminate() { return 1 }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while applications.contains(where: { !$0.isTerminated }) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return 1 }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return 0
    }
}
