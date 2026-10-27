import XCTest

final class ShellUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(_ route: String, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BGMORI_ROUTE"] = route
        app.launchEnvironment["BGMORI_GUEST_MODE"] = "1"
        app.launchArguments = ["-appearance", appearance]
        app.launch()
        return app
    }

    private func tabTitle(_ tab: String) -> String {
        switch tab {
        case "home": "发现"
        case "categories": "分类"
        case "calendar": "每日放送"
        case "library": "收藏"
        default: "我的"
        }
    }

    @MainActor
    private func snapshot(_ name: String, app: XCUIApplication) {
        #if os(macOS)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: app.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTabNavigationRemainsVisible() {
        let app = launch("categories")
        #if os(iOS)
        XCTAssertTrue(app.buttons["category-filters"].waitForExistence(timeout: 20))
        for _ in 0..<3 {
            for tab in ["calendar", "library", "profile", "home", "categories"] {
                app.tabBars.buttons[tabTitle(tab)].tap()
                XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.tabBars.buttons[tabTitle(tab)].isHittable)
            }
            app.buttons["global-search"].tap()
            XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 5))
            app.tabBars.buttons["我的"].tap()
            app.tabBars.buttons["分类"].tap()
            XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 5), "Tab must preserve search history")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["category-filters"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.tabBars.buttons["分类"].isHittable)
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["category-filters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["分类"].isHittable)
        let card = app.descendants(matching: .any).matching(identifier: "cover-card-title").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        card.tap()
        XCTAssertTrue(app.buttons["记录进度"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.tabBars.buttons["分类"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["分类"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["category-filters"].exists)
        snapshot("iphone-navigation-return", app: app)
        #else
        XCTAssertTrue(app.buttons["category-filters"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "cover-card-title").firstMatch.waitForExistence(timeout: 30))
        snapshot("mac-categories-light", app: app)
        #endif
    }

    @MainActor
    func testCalendarTabLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("calendar", appearance: appearance)
            #if os(iOS)
            XCTAssertTrue(app.tabBars.buttons["每日放送"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.navigationBars["每日放送"].exists)
            XCTAssertTrue(app.tabBars.buttons["每日放送"].isSelected)
            XCTAssertEqual(app.tabBars.buttons.count, 5)
            #else
            XCTAssertTrue(app.buttons["只看在看"].waitForExistence(timeout: 15))
            #endif
            snapshot("calendar-tab-\(appearance)", app: app)
            app.terminate()
        }
    }

    @MainActor
    func testLiveCommentsLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("comments:317613", appearance: appearance)
            let comment = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "comment-text-317613-")).firstMatch
            XCTAssertTrue(comment.waitForExistence(timeout: 35), "The screenshot subject must display actual comments")
            #if os(iOS)
            XCTAssertTrue(app.tabBars.buttons["发现"].exists)
            #endif
            snapshot("comments-\(appearance)", app: app)
            app.terminate()
        }
    }

    @MainActor
    func testLiveEpisodeReplies() {
        let app = launch("episode:1027")
        #if os(iOS)
        let progress = app.buttons.matching(NSPredicate(format: "label IN %@", ["标记为看过", "已看过"])).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 35))
        app.swipeUp()
        #else
        XCTAssertTrue(app.staticTexts["吐槽"].waitForExistence(timeout: 35))
        app.scrollViews.element(boundBy: 1).scroll(byDeltaX: 0, deltaY: -300)
        #endif
        XCTAssertTrue(app.staticTexts["comment-text-ep1027-205402"].waitForExistence(timeout: 35))
        snapshot("episode-comments", app: app)
    }
    @MainActor
    func testSubjectCommentsPreview() {
        let app = launch("subject:317613")
        let comment = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "comment-text-317613-")).firstMatch
        XCTAssertTrue(comment.waitForExistence(timeout: 35))
        for _ in 0..<12 {
            if comment.isHittable { break }
            #if os(iOS)
            app.swipeUp()
            #else
            app.scrollViews.element(boundBy: 1).scroll(byDeltaX: 0, deltaY: -500)
            #endif
        }
        XCTAssertTrue(comment.isHittable)
        XCTAssertFalse(app.staticTexts["还没有吐槽，或正在加载。"].exists)
        snapshot("subject-comments-preview", app: app)
    }

}
