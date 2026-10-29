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
    func testSidebarWindowRestoreLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("home", appearance: appearance)
            XCTAssertTrue(app.buttons["home-hot-dot-0"].waitForExistence(timeout: 60))
            #if os(macOS)
            let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
            app.activate()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
            let iconRegions = sidebarIconRegions(app: app)
            snapshot("sidebar-before-\(appearance)", app: app)
            assertSidebarIcons(app: app, regions: iconRegions)
            for iteration in 0..<3 {
                finder.activate()
                XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
                app.activate()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
                XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
                snapshot("sidebar-restored-\(appearance)-\(iteration)", app: app)
                assertSidebarIcons(app: app, regions: iconRegions)
            }
            #else
            XCTAssertEqual(app.tabBars.buttons.count, 5)
            snapshot("sidebar-phone-\(appearance)", app: app)
            #endif
            app.terminate()
        }
    }

    #if os(macOS)
    @MainActor
    private func sidebarIconRegions(app: XCUIApplication) -> [String: CGRect] {
        let windowFrame = app.windows.firstMatch.frame
        let outlineFrame = app.outlines.firstMatch.frame
        var regions: [String: CGRect] = [:]
        for title in ["发现", "分类", "放送", "收藏", "搜索", "我的"] {
            let label = app.outlines.staticTexts[title].firstMatch
            XCTAssertTrue(label.waitForExistence(timeout: 5), "Missing sidebar row: \(title)")
            let rowFrame = label.frame
            regions[title] = CGRect(x: outlineFrame.minX + 6 - windowFrame.minX,
                                    y: rowFrame.midY - 12 - windowFrame.minY,
                                    width: 28, height: 24)
        }
        return regions
    }

    @MainActor
    private func assertSidebarIcons(app: XCUIApplication, regions: [String: CGRect]) {
        let window = app.windows.firstMatch
        let image = window.screenshot()
        guard let bitmap = NSBitmapImageRep(data: image.pngRepresentation) else {
            XCTFail("Cannot inspect the sidebar screenshot")
            return
        }
        let scale = CGFloat(bitmap.pixelsWide) / window.frame.width
        // Sample fixed window-relative regions established before switching.
        // Stage Manager may temporarily invalidate the accessibility snapshot
        // while the rendered window is already restored.
        for (title, box) in regions {
            var coloredPixels = 0
            for y in Int(box.minY * scale)..<Int(box.maxY * scale) {
                for x in Int(box.minX * scale)..<Int(box.maxX * scale) {
                    guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh,
                          let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent - color.greenComponent > 0.12,
                       color.redComponent - color.blueComponent > 0.08 {
                        coloredPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(coloredPixels, 25, "Sidebar icon disappeared after window restore: \(title)")
        }
    }
    #endif

    @MainActor
    func testSilentHomeRefreshLightAndDark() {
        for appearance in ["light", "dark"] {
            // First obtain a real home snapshot, then exercise the cached launch.
            let initial = launch("home", appearance: appearance)
            XCTAssertTrue(initial.buttons["home-hot-dot-0"].waitForExistence(timeout: 60))
            initial.terminate()

            let app = launch("home", appearance: appearance)
            let firstPage = app.buttons["home-hot-dot-0"]
            XCTAssertTrue(firstPage.waitForExistence(timeout: 5), "Cached home must be available without waiting for the network")
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "正在显示缓存")).firstMatch.exists)
            XCTAssertFalse(app.staticTexts["正在读取缓存…"].exists)
            XCTAssertFalse(app.otherElements["startup-screen"].exists)

            let secondPage = app.buttons["home-hot-dot-1"]
            XCTAssertTrue(secondPage.exists)
            #if os(macOS)
            app.activate()
            secondPage.click()
            #else
            XCTAssertEqual(app.tabBars.buttons.count, 5)
            secondPage.tap()
            #endif
            let selected = NSPredicate(format: "selected == true")
            expectation(for: selected, evaluatedWith: secondPage)
            waitForExpectations(timeout: 3)
            #if os(macOS)
            firstPage.click()
            #else
            firstPage.tap()
            #endif
            expectation(for: selected, evaluatedWith: firstPage)
            waitForExpectations(timeout: 3)
            snapshot("silent-home-\(appearance)", app: app)
            app.terminate()
        }
    }

    @MainActor
    func testPeoplePortraitsLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("people:yaron", appearance: appearance)
            XCTAssertTrue(app.buttons["people-character-466"].waitForExistence(timeout: 40))
            XCTAssertTrue(app.buttons["people-person-17491"].exists)
            XCTAssertTrue(app.buttons["people-person-5001"].exists)
            // Allow the real image requests to complete before capturing.
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "portrait loading")], timeout: 4)
            snapshot("people-large-portraits-\(appearance)", app: app)
            app.terminate()
        }
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
    func testSearchAndLibraryHeadersLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("search", appearance: appearance)
            let field = app.textFields["search-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 30))
            let scope = app.buttons["角色"].firstMatch
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            #if os(iOS)
            XCTAssertLessThanOrEqual(field.frame.maxY, scope.frame.minY)
            #endif
            snapshot("search-header-\(appearance)", app: app)
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<3 {
                #if os(macOS)
                scroll.scroll(byDeltaX: 0, deltaY: -300)
                #else
                scroll.swipeUp()
                #endif
                XCTAssertTrue(field.isHittable)
                XCTAssertTrue(scope.isHittable)
            }
            snapshot("search-header-scrolled-\(appearance)", app: app)
            app.terminate()

            // Exercise layout and input without needing a real account or credentials.
            let library = XCUIApplication()
            library.launchEnvironment["BGMORI_ROUTE"] = "library"
            library.launchEnvironment["BGMORI_GUEST_MODE"] = "1"
            library.launchEnvironment["BGMORI_PREVIEW_LIBRARY_FILTERS"] = "1"
            library.launchArguments = ["-appearance", appearance]
            library.launch()
            let search = library.textFields.firstMatch
            let types = library.buttons["library-type-all"]
            let summary = library.staticTexts["library-summary"]
            XCTAssertTrue(search.waitForExistence(timeout: 30))
            XCTAssertTrue(types.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(search.frame.maxY, types.frame.minY)
            XCTAssertLessThanOrEqual(types.frame.maxY, summary.frame.minY)
            snapshot("library-header-\(appearance)", app: library)
            #if os(macOS)
            search.click()
            #else
            search.tap()
            #endif
            search.typeText("test")
            XCTAssertEqual(search.value as? String, "test")
            snapshot("library-header-editing-\(appearance)", app: library)
            library.terminate()
        }
    }

    @MainActor
    func testStationaryPaginationDoesNotStall() {
        let app = XCUIApplication()
        app.launchEnvironment["BGMORI_GUEST_MODE"] = "1"
        app.launchEnvironment["BGMORI_PREVIEW_PAGINATION"] = "1"
        app.launch()
        let count = app.staticTexts["pagination-preview-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 30))
        // No scroll gestures: each completion must trigger the next visible page.
        expectation(for: NSPredicate(format: "label == %@ OR value == %@", "3", "3"), evaluatedWith: count)
        waitForExpectations(timeout: 15)
        app.terminate()
    }

    @MainActor
    func testCompactLayoutsLightAndDark() {
        for appearance in ["light", "dark"] {
            let search = launch("search", appearance: appearance)
            let category = search.buttons["浏览动画分类"]
            XCTAssertTrue(category.waitForExistence(timeout: 30))
            let idea = search.buttons["搜索 CLANNAD，动画"]
            XCTAssertTrue(idea.waitForExistence(timeout: 10))
            snapshot("compact-search-\(appearance)", app: search)
            search.terminate()

            let profile = launch("profile", appearance: appearance)
            let visibleGroups = profile.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "小组与讨论")).firstMatch
            XCTAssertTrue(visibleGroups.waitForExistence(timeout: 30))
            snapshot("compact-profile-\(appearance)", app: profile)
            profile.terminate()

            let library = XCUIApplication()
            library.launchEnvironment["BGMORI_ROUTE"] = "library"
            library.launchEnvironment["BGMORI_GUEST_MODE"] = "1"
            library.launchEnvironment["BGMORI_PREVIEW_LIBRARY_GRID"] = "1"
            library.launchArguments = ["-appearance", appearance]
            library.launch()
            let cards = library.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-grid-"))
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 30))
            XCTAssertFalse(library.staticTexts["未评分"].exists)
            // SwiftUI can expose both a container and its label with the same ID.
            let first = cards.matching(identifier: "library-grid-328609").firstMatch
            let second = cards.matching(identifier: "library-grid-27364").firstMatch
            XCTAssertTrue(first.exists && second.exists)
            snapshot("compact-library-grid-\(appearance)", app: library)
            XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 1)
            XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
            library.terminate()

            #if os(macOS)
            // Exercise the actual category toolbar on Mac; its popover anchor
            // must remain clickable in the normal split-view hierarchy.
            let years = launch("categories", appearance: appearance)
            #else
            let years = XCUIApplication()
            years.launchEnvironment["BGMORI_GUEST_MODE"] = "1"
            years.launchEnvironment["BGMORI_PREVIEW_YEAR_PICKER"] = "1"
            years.launchArguments = ["-appearance", appearance]
            years.launch()
            #endif
            let picker = years.buttons["year-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 30))
            #if os(macOS)
            picker.click()
            #else
            picker.tap()
            #endif
            let current = Calendar.current.component(.year, from: Date())
            let firstYear = years.buttons["year-option-\(current)"]
            let secondYear = years.buttons["year-option-\(current - 1)"]
            XCTAssertTrue(firstYear.waitForExistence(timeout: 5))
            #if os(macOS)
            XCTAssertLessThanOrEqual(secondYear.frame.minY - firstYear.frame.minY, 28)
            #else
            XCTAssertLessThanOrEqual(secondYear.frame.minY - firstYear.frame.minY, 40)
            #endif
            snapshot("compact-years-\(appearance)", app: years)
            years.terminate()
        }
    }

    @MainActor
    func testTagPaginationLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("tag:校园", appearance: appearance)
            let grid = app.descendants(matching: .any)["tag-results"].firstMatch
            XCTAssertTrue(grid.waitForExistence(timeout: 60))
            let scroll = app.scrollViews.containing(.any, identifier: "tag-results").firstMatch
            let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "tag-subject-"))
            var seen: Set<String> = []
            snapshot("tag-first-page-\(appearance)", app: app)
            for _ in 0..<18 {
                seen.formUnion(cards.allElementsBoundByIndex.map(\.identifier))
                if seen.count > 20 { break }
                #if os(macOS)
                scroll.scroll(byDeltaX: 0, deltaY: -300)
                #else
                scroll.swipeUp(velocity: .slow)
                #endif
            }
            let appended = NSPredicate { _, _ in
                seen.formUnion(cards.allElementsBoundByIndex.map(\.identifier))
                return seen.count > 20
            }
            expectation(for: appended, evaluatedWith: app)
            waitForExpectations(timeout: 60)
            snapshot("tag-paginated-\(appearance)", app: app)
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "仅显示前")).firstMatch.exists)
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "已加载")).firstMatch.exists)
            app.terminate()
        }
    }

    @MainActor
    func testCategoryPaginationLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("categories", appearance: appearance)
            let grid = app.descendants(matching: .any)["category-results"].firstMatch
            XCTAssertTrue(grid.waitForExistence(timeout: 60))
            let scroll = app.scrollViews.containing(.any, identifier: "category-results").firstMatch
            let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "category-subject-"))
            var seenSubjects: Set<String> = []
            // A first server page contains at most 24 subjects. Scroll through
            // actual content until another page is appended to the same grid.
            for _ in 0..<18 {
                seenSubjects.formUnion(cards.allElementsBoundByIndex.map(\.identifier))
                if seenSubjects.count > 24 { break }
                #if os(macOS)
                scroll.scroll(byDeltaX: 0, deltaY: -300)
                #else
                scroll.swipeUp(velocity: .slow)
                #endif
            }
            let appended = NSPredicate { _, _ in
                seenSubjects.formUnion(cards.allElementsBoundByIndex.map(\.identifier))
                return seenSubjects.count > 24
            }
            expectation(for: appended, evaluatedWith: app)
            waitForExpectations(timeout: 60)
            snapshot("category-pagination-\(appearance)", app: app)
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
    func testCalendarAiringTimesLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("calendar", appearance: appearance)
            let wednesday = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "星期三，")).firstMatch
            XCTAssertTrue(wednesday.waitForExistence(timeout: 60))
            #if os(macOS)
            wednesday.click()
            #else
            wednesday.tap()
            #endif
            let detective = app.buttons["calendar-row-393010"].firstMatch
            let clock = NSPredicate(format: "label CONTAINS %@", "21:30 播出")
            expectation(for: clock, evaluatedWith: detective)
            waitForExpectations(timeout: 40)
            XCTAssertTrue(app.staticTexts["北京时间 ·"].exists)
            XCTAssertTrue(detective.label.contains("10月7日开播"), "Keep the premiere date alongside the clock")
            XCTAssertFalse(app.buttons["calendar-row-975"].firstMatch.label.contains("播出"),
                           "An unmatched catalogue entry must not receive an invented clock")
            snapshot("calendar-airing-times-\(appearance)", app: app)
            app.terminate()
        }
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
    func testSubjectSectionPreviewsLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch("subject:8", appearance: appearance)
            let episodes = app.buttons["episode-section-toggle"]
            let characters = app.buttons["character-section-toggle"]
            let episodeLinks = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "episode-link-")
            )
            let characterLinks = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "character-link-")
            )
            XCTAssertTrue(app.staticTexts["简介"].waitForExistence(timeout: 60))
            revealSubjectSection(episodes, app: app)
            XCTAssertEqual(episodes.value as? String, "已收起")
            XCTAssertEqual(episodeLinks.count, 3)
            XCTAssertTrue(episodeLinks.firstMatch.exists)
            XCTAssertTrue(episodes.label.contains("查看其余"))
            XCTAssertGreaterThanOrEqual(episodes.frame.minY, episodeLinks.element(boundBy: 2).frame.maxY)
            snapshot("subject-episodes-preview-\(appearance)", app: app)

            toggleSubjectSection(episodes, app: app)
            XCTAssertTrue(episodeLinks.element(boundBy: 3).waitForExistence(timeout: 5))
            XCTAssertEqual(episodes.value as? String, "已展开")
            XCTAssertEqual(characters.value as? String, "已收起")
            snapshot("subject-episodes-expanded-\(appearance)", app: app)
            toggleSubjectSection(episodes, app: app)
            XCTAssertEqual(episodeLinks.count, 3)

            revealSubjectSection(characters, app: app)
            XCTAssertTrue(characterLinks.firstMatch.waitForExistence(timeout: 10))
            let previewCount = characterLinks.count
            XCTAssertGreaterThan(previewCount, 0)
            XCTAssertTrue(characters.label.contains("位角色"))
            XCTAssertGreaterThanOrEqual(characters.frame.minY, characterLinks.element(boundBy: previewCount - 1).frame.maxY)
            #if os(iOS)
            XCTAssertEqual(previewCount, 3)
            #endif
            let firstRowTop = characterLinks.firstMatch.frame.minY
            for index in 0..<previewCount {
                XCTAssertEqual(characterLinks.element(boundBy: index).frame.minY, firstRowTop, accuracy: 1)
            }
            snapshot("subject-sections-preview-\(appearance)", app: app)
            toggleSubjectSection(characters, app: app)
            let extraCharacter = characterLinks.element(boundBy: previewCount)
            revealSubjectSection(extraCharacter, app: app)
            XCTAssertTrue(extraCharacter.exists)
            XCTAssertEqual(characters.value as? String, "已展开")
            XCTAssertEqual(episodes.value as? String, "已收起")
            snapshot("subject-characters-expanded-\(appearance)", app: app)
            toggleSubjectSection(characters, app: app)
            XCTAssertEqual(characterLinks.count, previewCount)
            XCTAssertEqual(episodeLinks.count, 3)
            snapshot("subject-sections-preview-restored-\(appearance)", app: app)

            for (section, prefix) in [("staff", "staff-link-"), ("relation", "relation-link-")] {
                let toggle = app.buttons["\(section)-section-toggle"]
                let links = app.descendants(matching: .any).matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", prefix)
                )
                revealSubjectSection(toggle, app: app)
                XCTAssertTrue(toggle.label.contains("查看其余"))
                let visibleCount = links.count
                XCTAssertGreaterThan(visibleCount, 0)
                XCTAssertGreaterThanOrEqual(toggle.frame.minY, links.element(boundBy: visibleCount - 1).frame.maxY)
                snapshot("subject-\(section)-preview-\(appearance)", app: app)
                toggleSubjectSection(toggle, app: app)
                let extra = links.element(boundBy: visibleCount)
                revealSubjectSection(extra, app: app)
                XCTAssertTrue(extra.exists)
                snapshot("subject-\(section)-expanded-\(appearance)", app: app)
                toggleSubjectSection(toggle, app: app)
                XCTAssertEqual(links.count, visibleCount)
            }
            app.terminate()
        }
    }

    @MainActor
    func testPersonWorksPreviewLightAndDark() {
        for appearance in ["light", "dark"] {
            let person = launch("person:17491", appearance: appearance)
            let works = person.buttons["person-related-toggle"]
            let workLinks = person.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "person-related-[0-9]+"))
            XCTAssertTrue(person.staticTexts["参与作品"].waitForExistence(timeout: 60))
            revealSubjectSection(works, app: person)
            let workPreviewCount = workLinks.count
            XCTAssertGreaterThan(workPreviewCount, 0)
            XCTAssertTrue(works.label.contains("部作品"))
            XCTAssertGreaterThanOrEqual(works.frame.minY, workLinks.element(boundBy: workPreviewCount - 1).frame.maxY)
            let workRowTop = workLinks.firstMatch.frame.minY
            for index in 0..<workPreviewCount {
                XCTAssertEqual(workLinks.element(boundBy: index).frame.minY, workRowTop, accuracy: 1)
            }
            snapshot("person-works-preview-\(appearance)", app: person)
            toggleSubjectSection(works, app: person)
            let extraWork = workLinks.element(boundBy: workPreviewCount)
            revealSubjectSection(extraWork, app: person)
            XCTAssertTrue(extraWork.exists)
            snapshot("person-works-expanded-\(appearance)", app: person)
            toggleSubjectSection(works, app: person)
            XCTAssertEqual(workLinks.count, workPreviewCount)
            person.terminate()
        }
    }

    @MainActor
    private func revealSubjectSection(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<20 {
            #if os(iOS)
            // isHittable can include a header covered by the floating bottom bar.
            let bottomEdge = app.tabBars.firstMatch.exists
                ? app.tabBars.firstMatch.frame.minY : app.frame.maxY - 140
            if element.exists, element.isHittable,
               element.frame.minY > 130, element.frame.maxY <= bottomEdge { return }
            let needsEarlierContent = element.exists && element.frame.minY <= 130
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: needsEarlierContent ? 0.4 : 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: needsEarlierContent ? 0.65 : 0.45))
            start.press(forDuration: 0.1, thenDragTo: end)
            #else
            if element.isHittable { return }
            let needsEarlierContent = element.exists && element.frame.minY < app.windows.firstMatch.frame.minY + 80
            app.scrollViews.element(boundBy: 1).scroll(byDeltaX: 0, deltaY: needsEarlierContent ? 250 : -350)
            #endif
        }
        snapshot("unreachable-\(element.identifier)", app: app)
        XCTFail("Subject section did not become visible: \(element.identifier)")
    }

    @MainActor
    private func toggleSubjectSection(_ element: XCUIElement, app: XCUIApplication) {
        let collapse = app.buttons["\(element.identifier)-collapse"]
        let target = collapse.exists ? collapse : element
        revealSubjectSection(target, app: app)
        #if os(macOS)
        target.click()
        #else
        target.tap()
        #endif
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
