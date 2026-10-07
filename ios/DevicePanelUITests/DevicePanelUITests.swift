import XCTest

final class DevicePanelUITests: XCTestCase {
    func testFreshLaunchShowsAccessibleSignInForm() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Device Panel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["serverURLField"].exists)
        XCTAssertTrue(app.secureTextFields["passwordField"].exists)
        XCTAssertTrue(app.buttons["signInButton"].exists)
        XCTAssertFalse(app.buttons["signInButton"].isEnabled)

        app.textFields["serverURLField"].tap()
        app.textFields["serverURLField"].typeText("https://panel.example")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("test-password")

        XCTAssertTrue(app.buttons["signInButton"].isEnabled)
    }
}
