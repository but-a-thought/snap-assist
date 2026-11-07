import AppKit

if CommandLine.arguments.dropFirst().first == AppRestart.helperArgument {
    exit(AppRestart.runHelper(arguments: CommandLine.arguments))
}
if CommandLine.arguments.dropFirst().first == "--prepare-install" {
    exit(InstallationPreparation.run())
}

// App di solo menu: nessuna finestra principale, nessuna icona nel Dock.
let application = NSApplication.shared

if CommandLine.arguments.contains("--check") {
    exit(SelfCheck.run())
}

if CommandLine.arguments.contains("--test") {
    let runner = TestRunner()
    application.delegate = runner
    application.setActivationPolicy(.accessory)
    application.run()
    exit(runner.exitCode)
}

if CommandLine.arguments.contains("--demo") {
    Demo.run()
    application.run()
    exit(0)
}

if CommandLine.arguments.contains("--demo-divider") {
    Demo.runDivider()
    application.run()
    exit(0)
}

if CommandLine.arguments.contains("--demo-snap") {
    Demo.runSnap()
    exit(0)
}

if CommandLine.arguments.contains("--screenshot") {
    ScreenshotDemo.run()
    application.run()
    exit(0)
}

if CommandLine.arguments.contains("--layout-editor") {
    let editor = LayoutEditorWindowController()
    editor.show()
    application.run()
    exit(0)
}

let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
