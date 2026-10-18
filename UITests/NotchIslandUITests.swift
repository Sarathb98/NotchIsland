import XCTest

final class NotchIslandUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExpandedIslandTimerCanStartAndPause() {
        let app = launchIsland()
        defer { app.terminate() }
        selectModule("Timer", in: app)
        XCTAssertTrue(element("widget.timer", in: app).waitForExistence(timeout: 5))
        let start = app.buttons["Start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        clickVisibleTimerControl(start, in: app)
        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 3), "Running timers expose the native Pause control.")
        clickVisibleTimerControl(pause, in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 3), "Pausing restores the Start control.")
        XCTAssertTrue(app.buttons["Reset"].firstMatch.exists)
    }

    @MainActor
    func testModulePickerOpensNotesAndKeepsClipboardOff() {
        let app = launchIsland()
        defer { app.terminate() }
        selectModule("Notes", in: app)
        XCTAssertTrue(app.buttons["New note"].firstMatch.waitForExistence(timeout: 3), "Notes exposes an accessible creation control.")
        selectModule("Clipboard", in: app)
        let clipboard = app.switches["clipboard.history"].firstMatch
        XCTAssertTrue(clipboard.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["Search clipboard"].firstMatch.exists,
                       "Clipboard history remains opt-in during an isolated test launch.")
        XCTAssertTrue(app.staticTexts["Clipboard history is off"].firstMatch.exists,
                      "The visible status must explicitly confirm that history is off.")
    }

    @MainActor
    func testEscapeCollapsesTheAccessibleIsland() {
        let app = launchIsland()
        defer { app.terminate() }
        selectModule("Timer", in: app)
        // A native button gives the nonactivating panel keyboard focus.
        let reset = app.buttons["Reset"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        let surface = element("island.surface", in: app)
        let expandedFrame = surface.frame
        clickVisibleTimerControl(reset, in: app)
        app.typeKey(.escape, modifierFlags: [])
        // macOS XCTest omits the SwiftUI group's AXValue. Check the actual
        // dismissal and shrinking surface instead of that unavailable attribute.
        let dismissed = NSPredicate(format: "exists == false")
        expectation(for: dismissed, evaluatedWith: element("module.picker", in: app))
        waitForExpectations(timeout: 3)
        XCTAssertFalse(element("module.picker", in: app).exists, "Collapsed islands hide expanded controls.")
        XCTAssertTrue(surface.exists, "The island remains discoverable to accessibility clients.")
        XCTAssertGreaterThan(surface.frame.height, 0)
        XCTAssertLessThan(surface.frame.height, expandedFrame.height / 2,
                          "Escape must shrink the surface back to the notch cap.")
        XCTAssertEqual(surface.frame.minY, expandedFrame.minY, accuracy: 1,
                       "The island remains anchored to the screen's top edge.")
    }

    @MainActor
    func testDashboardAndTrayNavigation() {
        let app = launchIsland()
        defer { app.terminate() }
        XCTAssertTrue(element("dashboard.media", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("dashboard.mirror", in: app).exists,
                      "The dashboard exposes its camera mirror card.")
        XCTAssertTrue(element("dashboard.calendar", in: app).exists)
        XCTAssertTrue(element("dashboard.notes", in: app).exists)
        XCTAssertTrue(element("dashboard.timer", in: app).exists)
        XCTAssertTrue(element("dashboard.tasks", in: app).exists,
                      "The dashboard exposes its task list card, even when it extends beyond the visible horizontal area.")
        let surface = element("island.surface", in: app)
        let dashboardFrame = surface.frame
        let dashboardImage = XCTAttachment(screenshot: surface.screenshot())
        dashboardImage.name = "Notch Island dashboard"
        dashboardImage.lifetime = .keepAlways
        add(dashboardImage)
        let tray = app.buttons["island.tab.tray"].firstMatch
        XCTAssertTrue(tray.exists)
        tray.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(element("island.tray", in: app).waitForExistence(timeout: 3))
        XCTAssertLessThan(surface.frame.height, dashboardFrame.height)
        XCTAssertEqual(surface.frame.width, dashboardFrame.width, accuracy: 1)
        let trayImage = XCTAttachment(screenshot: surface.screenshot())
        trayImage.name = "Notch Island tray"
        trayImage.lifetime = .keepAlways
        add(trayImage)
        let dashboard = app.buttons["island.tab.dashboard"].firstMatch
        dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(element("dashboard.media", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("dashboard.mirror", in: app).exists)
        XCTAssertTrue(element("dashboard.tasks", in: app).exists)
    }

    @MainActor
    func testCameraMirrorHasExplicitStartControl() {
        let app = launchIsland()
        defer { app.terminate() }
        XCTAssertTrue(element("dashboard.mirror", in: app).waitForExistence(timeout: 3))
        // The horizontal dashboard may clip this card on smaller displays.
        // Open its focused module to inspect the control without scrolling.
        selectModule("Mirror", in: app)
        XCTAssertTrue(element("dashboard.mirror", in: app).waitForExistence(timeout: 3))
        let start = app.buttons["mirror.toggle"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertEqual(start.label, "Start Mirror",
                       "Camera access must require an explicit Start action.")
        XCTAssertFalse(app.buttons["Stop Mirror"].firstMatch.exists)
    }

    @MainActor
    func testTasksCanBeCreatedCompletedAndDeleted() {
        let app = launchIsland()
        defer { app.terminate() }
        selectModule("Tasks", in: app)
        XCTAssertTrue(element("dashboard.tasks", in: app).waitForExistence(timeout: 3))

        let input = app.textFields["tasks.new"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.click()
        input.typeText("Call mom\n")

        let complete = app.buttons["Mark Call mom complete"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 3),
                      "Return in the task field creates a row.")
        clickVisibleTaskControl(complete, in: app)
        let incomplete = app.buttons["Mark Call mom incomplete"].firstMatch
        XCTAssertTrue(incomplete.waitForExistence(timeout: 3),
                      "Completing a task updates its accessible state.")

        let remove = app.buttons["Delete Call mom"].firstMatch
        XCTAssertTrue(remove.exists)
        clickVisibleTaskControl(remove, in: app)
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: incomplete)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(app.staticTexts["Call mom"].firstMatch.exists)
    }

    @MainActor
    private func launchIsland() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.notchisland.app")
        app.launchArguments = ["--ui-testing", "--expanded", "--skip-onboarding",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(element("module.picker", in: app).waitForExistence(timeout: 10),
                      "An isolated expanded launch must show the module picker.")
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func clickVisibleTimerControl(_ control: XCUIElement, in app: XCUIApplication) {
        let frame = control.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertFalse(frame.isEmpty, "The timer control must have a visible frame.")
        XCTAssertTrue(element("island.surface", in: app).frame.contains(center))
        XCTAssertTrue(element("widget.timer", in: app).frame.contains(center),
                      "The control must be inside the timer's visible scroll area.")
        // Element.click() can attempt to scroll an already visible control using
        // a stale SwiftUI ScrollView snapshot. Click its verified visible center.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor
    private func clickVisibleTaskControl(_ control: XCUIElement, in app: XCUIApplication) {
        let frame = control.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertFalse(frame.isEmpty, "The task control must have a visible frame.")
        XCTAssertTrue(element("island.surface", in: app).frame.contains(center))
        XCTAssertTrue(element("dashboard.tasks", in: app).frame.contains(center))
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor
    private func selectModule(_ title: String, in app: XCUIApplication) {
        let picker = element("module.picker", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.click()
        let item = app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "The module menu contains \(title).")
        item.click()
    }
}
