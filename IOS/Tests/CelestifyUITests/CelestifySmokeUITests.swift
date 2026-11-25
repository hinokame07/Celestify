//
//  CelestifySmokeUITests.swift
//  CelestifyUITests
//
//  UI smoke tests verifying onboarding launch & accessibility identifiers.
//

import XCTest

final class CelestifySmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesIntoCelestialOnboardingWhenSignedOut() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Celestify"].waitForExistence(timeout: 5.0))
        XCTAssertTrue(app.buttons["Continue with Spotify"].exists)
    }
}
