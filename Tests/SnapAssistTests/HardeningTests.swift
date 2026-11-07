import AppKit
import XCTest
@testable import SnapAssist

final class HardeningTests: XCTestCase {
    func testNormalFullScreenDockCanvasDoesNotSuppressSuggestions() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let canvas = SystemWindow(pid: 777, layer: 20, frame: screen.frame)
        XCTAssertFalse(WindowList.isSystemOverlay(windows: [canvas], dockPid: 777,
                                                  screens: [screen], windowManagerPid: 888))
    }

    func testLegacyAndCurrentMissionControlSurfacesSuppressSuggestions() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        for surface in [SystemWindow(pid: 777, layer: 18, frame: screen.frame),
                        SystemWindow(pid: 888, layer: 19, frame: screen.frame)] {
            XCTAssertTrue(WindowList.isSystemOverlay(windows: [surface], dockPid: 777,
                                                     screens: [screen], windowManagerPid: 888))
        }
        let unrelated = SystemWindow(pid: 999, layer: 19, frame: screen.frame)
        XCTAssertFalse(WindowList.isSystemOverlay(windows: [unrelated], dockPid: 777,
                                                  screens: [screen], windowManagerPid: 888))
    }

    func testCenteringMonitorFollowsLifecycleAndOffSetting() {
        var installs = 0
        var removals = 0
        let token = NSObject()
        let controller = CenterWindowController(installMonitor: { mask, _ in
            XCTAssertTrue(mask.contains(.flagsChanged))
            installs += 1
            return token
        }, removeMonitor: { value in
            XCTAssertTrue((value as AnyObject) === token)
            removals += 1
        })
        controller.start()
        XCTAssertEqual(installs, 0, "Off must not subscribe to global input")
        controller.isEnabled = true
        controller.start()
        XCTAssertEqual(installs, 1, "Repeated start must not duplicate monitors")
        controller.isEnabled = false
        XCTAssertEqual(removals, 1, "Off removes monitoring immediately")
        controller.isEnabled = true
        XCTAssertEqual(installs, 2)
        controller.stop()
        XCTAssertEqual(removals, 2)
        controller.isEnabled = false
        controller.isEnabled = true
        XCTAssertEqual(installs, 2, "A stopped controller must stay stopped")
    }

    func testRestartPassesLiteralPathsAsSeparateArguments() {
        for path in ["/Applications/Snap Assist.app", "/Applications/Owner's Snap.app",
                     "/Applications/$(touch ignored);`ignored`.app"] {
            var captured: [String]?
            let result = AppRestart.waitAndOpen(parent: 123, bundle: URL(fileURLWithPath: path),
                parentExited: { _ in true }, launch: { captured = $0 })
            XCTAssertEqual(result, 0)
            XCTAssertEqual(captured, ["--", path])
        }
    }

    func testRestartTimesOutWithoutLaunchingAnotherInstance() {
        var now: TimeInterval = 0
        var launched = false
        let result = AppRestart.waitAndOpen(parent: 123, bundle: URL(fileURLWithPath: "/Applications/Test.app"),
            timeout: 10, parentExited: { _ in false }, uptime: { now }, pause: { now += 1 },
            launch: { _ in launched = true })
        XCTAssertEqual(result, 1)
        XCTAssertFalse(launched)
        XCTAssertEqual(now, 10)
    }

    func testRestartWaitsForExitAndReportsLaunchFailure() {
        var checks = 0
        var pauses = 0
        let result = AppRestart.waitAndOpen(parent: 123, bundle: URL(fileURLWithPath: "/Applications/Test.app"),
            parentExited: { _ in checks += 1; return checks == 3 }, pause: { pauses += 1 },
            launch: { _ in throw NSError(domain: "fixture", code: 1) })
        XCTAssertEqual(pauses, 2)
        XCTAssertEqual(result, 1)
    }
}
