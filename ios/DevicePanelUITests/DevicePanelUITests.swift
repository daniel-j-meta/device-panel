import XCTest

final class DevicePanelUITests: XCTestCase {
    private var server: LocalDevicePanelServer!

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = LocalDevicePanelServer()
        try server.start()
    }

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    @MainActor
    func testCompleteControlFlowUsesOnlyLoopbackAndRollsBackFailures() {
        let app = makeApp()
        defer { app.terminate() }
        launchAndSignIn(app)

        let power = app.buttons["powerControl"]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        XCTAssertEqual(power.value as? String, "Off")

        power.tap()
        waitForValue("On", element: power)
        server.waitForRoom { $0.on }

        let brightness75 = app.buttons["brightness75"]
        brightness75.tap()
        waitForValue("Selected", element: brightness75)
        server.waitForRoom { $0.brightness == 75 }

        let red = app.buttons["colorRed"]
        red.tap()
        waitForValue("Selected", element: red)
        server.waitForRoom { $0.colorMode == "red" }

        let temperature = app.sliders["temperatureSlider"]
        temperature.adjust(toNormalizedSliderPosition: 0.25)
        server.waitForRoom {
            abs($0.colorTemperaturePct - 25) <= 2 && $0.colorMode == "temperature"
        }

        server.failNextCommandRequest()
        power.tap()
        XCTAssertTrue(app.otherElements["errorBanner"].waitForExistence(timeout: 5))
        waitForValue("On", element: power)

        app.buttons["Retry Command"].tap()
        waitForValue("Off", element: power)
        server.waitForRoom { !$0.on }

        server.setRoom {
            $0.on = true
            $0.brightness = 10
            $0.colorTemperaturePct = 80
        }
        app.swipeDown()
        waitForValue("On", element: power)
        waitForValue("Selected", element: app.buttons["brightness10"])

        XCTAssertFalse(server.requestedPaths.isEmpty)
        XCTAssertTrue(server.requestedPaths.allSatisfy { $0.hasPrefix("/api/v1/") })
    }

    @MainActor
    func testExpiredSessionReturnsToSignIn() {
        let app = makeApp()
        defer { app.terminate() }
        launchAndSignIn(app)
        server.expireNextAuthenticatedRequest()

        app.swipeDown()

        XCTAssertTrue(app.textFields["serverURLField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your session has expired. Sign in again."].exists)
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        return app
    }

    @MainActor
    private func launchAndSignIn(_ app: XCUIApplication) {
        app.launch()

        let serverField = app.textFields["serverURLField"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 5))
        serverField.tap()
        serverField.typeText(server.baseURL)

        let password = app.secureTextFields["passwordField"]
        password.tap()
        password.typeText("test-pass")
        app.buttons["signInButton"].tap()

        XCTAssertTrue(app.navigationBars["Living Room"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["connectionStatus"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForValue(
        _ value: String,
        element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Expected \(element) to have value \(value)",
            file: file,
            line: line
        )
    }
}
