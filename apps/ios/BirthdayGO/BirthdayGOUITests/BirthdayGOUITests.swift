import XCTest

final class BirthdayGOUITests: XCTestCase {
    func testOnboardingAppearsBeforeExplore() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-onboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Rocco's Quest"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Let's Go"].exists)
        XCTAssertFalse(app.tabBars.buttons["Quest"].exists)
        app.buttons["Let's Go"].tap()
        XCTAssertTrue(app.staticTexts["Play the Quest"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Back"].exists)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Rocco's Quest"].waitForExistence(timeout: 3))
    }

    func testInvitationScreenIsAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-invite"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Birthday GO"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start the adventure"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Start the adventure"].isEnabled)
        XCTAssertTrue(app.buttons["I have a private code"].exists)
    }

    func testReadyTabsExposeMapCollectionMemoriesAndFinale() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-ready"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Quest"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Explore"].exists)
        XCTAssertTrue(app.staticTexts["Marathon Madness"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.buttons["FriendDex"].exists)
        XCTAssertFalse(app.tabBars.buttons["Cookies"].exists)
        app.tabBars.buttons["Birthday Dex"].tap()
        let remaining = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'left to unlock'")).firstMatch
        XCTAssertTrue(remaining.waitForExistence(timeout: 3))
        app.tabBars.buttons["Messages"].tap()
        XCTAssertTrue(app.staticTexts["Birthday Messages"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sharon"].exists)
        XCTAssertTrue(app.staticTexts["Mary"].exists)
        XCTAssertFalse(app.staticTexts["Anya"].exists)
        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.staticTexts["Happy Birthday Rocco"].waitForExistence(timeout: 3))
        let running = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Running'")).firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["96"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["How to Play"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Final surprise"].exists)
        XCTAssertFalse(app.staticTexts["NYC Memory Passport"].exists)
    }

    func testQuestIsHomeAndTheMapIsGone() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-ready"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Quest"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Explore"].exists)
        XCTAssertFalse(app.maps.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Marathon Madness"].waitForExistence(timeout: 3))
        app.staticTexts["Marathon Madness"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3))
        app.buttons["Back to quest"].tap()
        XCTAssertTrue(app.staticTexts["Marathon Madness"].waitForExistence(timeout: 3))
    }
}
