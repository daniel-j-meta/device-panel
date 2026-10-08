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
        waitForPower(on: false, app: app)

        power.tap()
        server.waitForRoom { $0.on }
        waitForPower(on: true, app: app)

        let brightness75 = app.buttons["brightness75"]
        brightness75.tap()
        server.waitForRoom { $0.brightness == 75 }
        waitForValue("Selected", element: brightness75)

        let red = app.buttons["colorRed"]
        red.tap()
        server.waitForRoom { $0.colorMode == "red" }
        waitForValue("Selected", element: red)

        let temperature = app.sliders["temperatureSlider"]
        temperature.adjust(toNormalizedSliderPosition: 0.25)
        server.waitForRoom {
            abs($0.colorTemperaturePct - 25) <= 2 && $0.colorMode == "temperature"
        }

        server.failNextCommandRequest()
        power.tap()
        XCTAssertTrue(app.descendants(matching: .any)["errorBanner"].waitForExistence(timeout: 5))
        waitForPower(on: true, app: app)

        let retry = app.buttons["Retry Command"]
        if !retry.isHittable { app.swipeUp() }
        retry.tap()
        server.waitForRoom { !$0.on }
        waitForPower(on: false, app: app)

        server.setRoom {
            $0.on = true
            $0.brightness = 10
            $0.colorTemperaturePct = 80
        }
        app.buttons["refreshButton"].tap()
        waitForPower(on: true, app: app)
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

        app.buttons["refreshButton"].tap()

        XCTAssertTrue(app.textFields["serverURLField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your session has expired. Sign in again."].exists)
    }

    @MainActor
    func testIncorrectPasswordStaysSignedOut() {
        let app = makeApp()
        defer { app.terminate() }
        app.launch()

        let serverField = app.textFields["serverURLField"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 5))
        serverField.tap()
        serverField.typeText(server.baseURL)
        let password = app.secureTextFields["passwordField"]
        password.tap()
        password.typeText("wrong-password")
        app.buttons["signInButton"].tap()

        XCTAssertTrue(app.staticTexts["Incorrect password."].waitForExistence(timeout: 5))
        XCTAssertTrue(server.requestedPaths.contains("/api/v1/sessions"))
        XCTAssertFalse(app.navigationBars["Living Room"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["connectionStatus"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForPower(on: Bool, app: XCUIApplication) {
        let label = on ? "Living Room is on" : "Living Room is off"
        XCTAssertTrue(
            app.staticTexts[label].waitForExistence(timeout: 5),
            "Expected \(label); server=\(server.snapshot), paths=\(server.requestedPaths)"
        )
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
            "Expected \(element) to have value \(value); server=\(server.snapshot), paths=\(server.requestedPaths)",
            file: file,
            line: line
        )
    }
}
