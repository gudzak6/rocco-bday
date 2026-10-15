import XCTest

final class BirthdayGOUITests: XCTestCase {
    func testOnboardingAppearsBeforeExplore() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-onboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A Birthday Adventure Awaits!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Your Gift"].exists)
        XCTAssertFalse(app.tabBars.buttons["Explore"].exists)
        app.buttons["Open Your Gift"].tap()
        XCTAssertTrue(app.staticTexts["Explore Your City"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Back"].exists)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["A Birthday Adventure Awaits!"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Birthday Dex"].tap()
        XCTAssertTrue(app.staticTexts["Undiscovered"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Memories"].tap()
        XCTAssertTrue(app.staticTexts["Birthday Messages"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sharon"].exists)
        XCTAssertTrue(app.staticTexts["Anya"].exists)
        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.staticTexts["You did it"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Replay anytime."].exists)
    }

    func testNearbyListIsReachableWithoutGrantingLocation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-ready"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 5))
        app.buttons["Nearby list"].tap()
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 3))
    }

    func testMemoryStopDiscCollectsOnceAndReturnsToTheMap() {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Location") { alert in
            let allow = alert.buttons["Allow While Using App"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        app.launchArguments = ["-ui-testing-ready"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 8))
        if app.buttons["Allow While Using App"].waitForExistence(timeout: 3) {
            app.buttons["Allow While Using App"].tap()
            app.tap()
        }
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.swipeLeft()
        map.pinch(withScale: 1.4, velocity: 1)
        XCTAssertTrue(app.buttons["Recenter map"].exists)
        app.buttons["Nearby list"].tap()
        let grandCentral = app.staticTexts["Grand Central Terminal"]
        for _ in 0..<10 where !grandCentral.exists {
            app.swipeUp()
        }
        XCTAssertTrue(grandCentral.waitForExistence(timeout: 3))
        grandCentral.tap()
        let disc = app.images["Grand Central Terminal photo disc"]
        XCTAssertTrue(disc.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Meet me under the clock"].exists == false)
        XCTAssertTrue(app.staticTexts["If we can find each other in Grand Central, we can find anything. Happy birthday — the next train is yours."].exists)
        XCTAssertTrue(app.staticTexts["Swipe across the disc to collect this memory."].waitForExistence(timeout: 4))
        let discShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        discShot.name = "memory-stop-disc"
        discShot.lifetime = .keepAlways
        add(discShot)
        let start = disc.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = disc.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Memory Collected"].waitForExistence(timeout: 6))
        let again = disc.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let back = disc.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        again.press(forDuration: 0.05, thenDragTo: back)
        XCTAssertTrue(app.staticTexts["Memory Collected"].exists)
        app.buttons["Back to map"].tap()
        XCTAssertTrue(app.buttons["Recenter map"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["150 XP"].waitForExistence(timeout: 4))
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "memory-stop-map"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Nearby list"].tap()
        XCTAssertTrue(app.staticTexts["Grand Central Terminal"].waitForExistence(timeout: 5))
        app.staticTexts["Grand Central Terminal"].tap()
        XCTAssertTrue(app.staticTexts["Already collected. Swipe the disc to spin it again."].waitForExistence(timeout: 5))
        app.buttons["Back to map"].tap()
        XCTAssertTrue(app.staticTexts["150 XP"].waitForExistence(timeout: 4))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 8))
        app.buttons["Nearby list"].tap()
        XCTAssertTrue(app.staticTexts["Grand Central Terminal"].waitForExistence(timeout: 5))
        app.staticTexts["Grand Central Terminal"].tap()
        XCTAssertTrue(app.staticTexts["Already collected. Swipe the disc to spin it again."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Memory Collected"].exists)
    }

    func testCatchOpensAccessibleThrowControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-ready"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 5))
        app.buttons["Nearby list"].tap()
        XCTAssertTrue(app.staticTexts["Cupcake Sprite"].waitForExistence(timeout: 3))
        app.staticTexts["Cupcake Sprite"].tap()
        let camera = app.buttons["Open camera to catch"]
        XCTAssertTrue(camera.waitForExistence(timeout: 3))
        camera.tap()
        XCTAssertTrue(app.buttons["Tap to catch instead"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close catch"].exists)
        XCTAssertTrue(app.staticTexts["Cupcake Sprite, capture target"].waitForExistence(timeout: 3))
        let orb = app.otherElements["Capture orb"]
        XCTAssertTrue(orb.waitForExistence(timeout: 3))
        XCTAssertEqual(orb.value as? String, "Ready")
        let resting = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resting.name = "catch-ready"
        resting.lifetime = .keepAlways
        add(resting)
        let start = orb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 12, dy: -8)))
        XCTAssertFalse(app.staticTexts["Caught!"].exists)
        XCTAssertTrue(app.buttons["Tap to catch instead"].exists)
        XCTAssertEqual(orb.value as? String, "Ready")
    }
}
