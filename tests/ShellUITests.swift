import XCTest
#if os(macOS)
import AppKit
#endif

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
    func testDirectLoginLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["BGMORI_ROUTE"] = "login"
            app.launchEnvironment["BGMORI_GUEST_MODE"] = "1"
            app.launchEnvironment["BGMORI_ECH_ONLY"] = "1"
            app.launchArguments = ["-appearance", appearance]
            app.launch()
            XCTAssertTrue(app.textFields["login-email"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.secureTextFields["login-password"].exists)
            XCTAssertTrue(app.textFields["login-captcha"].exists)
            let captcha = app.buttons["login-captcha-image"]
            let loaded = NSPredicate(format: "label == %@ AND enabled == true", "更换验证码")
            expectation(for: loaded, evaluatedWith: captcha)
            waitForExpectations(timeout: 45)
            XCTAssertFalse(app.buttons["login-submit"].isEnabled)
            XCTAssertFalse(app.staticTexts["OAuth 应用"].exists)
            XCTAssertFalse(app.staticTexts["已有 Access Token"].exists)
            XCTAssertFalse(app.staticTexts["login-error"].exists)
            snapshot("direct-login-\(appearance)", app: app)
            #if os(macOS)
            app.activate()
            captcha.click()
            #else
            captcha.tap()
            #endif
            expectation(for: loaded, evaluatedWith: captcha)
            waitForExpectations(timeout: 45)
            XCTAssertFalse(app.staticTexts["login-error"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testECHOnlyConnectionsLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["BGMORI_ROUTE"] = "settings"
            app.launchEnvironment["BGMORI_GUEST_MODE"] = "1"
            app.launchEnvironment["BGMORI_ECH_ONLY"] = "1"
            app.launchArguments = ["-appearance", appearance]
            app.launch()
            let settings = app.buttons["connection-settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 20))
            #if os(macOS)
            app.activate()
            settings.click()
            #else
            if !settings.isHittable { app.swipeUp() }
            settings.tap()
            #endif
            let recheck = app.buttons["connection-recheck"]
            XCTAssertTrue(recheck.waitForExistence(timeout: 10))
            #if os(macOS)
            recheck.click()
            #else
            recheck.tap()
            #endif
            XCTAssertTrue(app.staticTexts["connection-check-summary"].waitForExistence(timeout: 60))
            XCTAssertGreaterThanOrEqual(app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "ECH 已验证", "ECH 已验证")).count, 3,
                                       "Every service must complete verified ECH; plain HTTP and mirrors cannot satisfy this test")
            snapshot("ech-only-\(appearance)", app: app)
            app.terminate()
        }
    }

    @MainActor
    func testConnectionsLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("settings", appearance: appearance)
            let settings = app.buttons["connection-settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 20))
            if !settings.isHittable {
                #if os(iOS)
                app.swipeUp()
                #else
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -250)
                #endif
            }
            #if os(macOS)
            app.activate()
            settings.click()
            #else
            settings.tap()
            #endif
            let recheck = app.buttons["connection-recheck"]
            XCTAssertTrue(recheck.waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["connection-encrypted-dns"].exists)
            #if os(macOS)
            recheck.click()
            #else
            recheck.tap()
            #endif
            XCTAssertTrue(app.staticTexts["connection-check-summary"].waitForExistence(timeout: 50))
            XCTAssertTrue(app.descendants(matching: .any)["connection-status-api"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["connection-status-images"].exists)
            snapshot("connections-\(appearance)", app: app)
            app.terminate()
        }
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
    func testInfoLinksAndFiltersLightAndDark() {
        for appearance in ["light", "dark"] {
            let person = launch("person:17491", appearance: appearance)
            let twitter = person.descendants(matching: .any)["infobox-value-Twitter"].firstMatch
            XCTAssertTrue(twitter.waitForExistence(timeout: 40))
            for _ in 0..<5 {
                #if os(iOS)
                if twitter.isHittable && twitter.frame.maxY < person.frame.maxY - 150 && twitter.frame.minY > 150 { break }
                let start = person.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.65))
                let end = person.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: twitter.frame.minY < 150 ? 0.8 : 0.5))
                start.press(forDuration: 0.1, thenDragTo: end)
                #else
                if twitter.isHittable { break }
                person.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -250)
                #endif
            }
            XCTAssertTrue(twitter.isHittable)
            snapshot("infobox-links-\(appearance)", app: person)
            #if os(macOS)
            let browserURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://twitter.com/taka8rie")!)!
            let browser = XCUIApplication(bundleIdentifier: Bundle(url: browserURL)!.bundleIdentifier!)
            twitter.click()
            #else
            let browser = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
            twitter.tap()
            #endif
            XCTAssertTrue(browser.wait(for: .runningForeground, timeout: 15), "Tapping the handle must open the browser")
            person.terminate()

            let comments = launch("comments:317613", appearance: appearance)
            let sort = comments.descendants(matching: .any)["comments-sort-filter"].firstMatch
            XCTAssertTrue(sort.waitForExistence(timeout: 40))
            snapshot("comment-filters-\(appearance)", app: comments)
            #if os(macOS)
            sort.click()
            let newest = comments.menuItems["最新"]
            XCTAssertTrue(newest.waitForExistence(timeout: 5))
            newest.click()
            #else
            sort.tap()
            let newest = comments.buttons["最新"]
            XCTAssertTrue(newest.waitForExistence(timeout: 5))
            newest.tap()
            #endif
            XCTAssertTrue(comments.buttons["comments-filter-reset"].waitForExistence(timeout: 5))
            snapshot("comment-filters-active-\(appearance)", app: comments)
            comments.terminate()
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
