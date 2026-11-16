import Foundation
import ImageIO

private final class LoginServer: @unchecked Sendable {
    static let shared = LoginServer()
    let lock = NSLock()
    var password = UUID().uuidString + "+&=中文"
    var token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    var cookie = UUID().uuidString
    var tokenName = ""
    var attempts = 0
    var issued = 0
    var checked = 0
    var removed: [Int] = []
    var reject = false
    var hang = false
    var broken = false
    var captchaCookies: [String] = []
    var userAgent: String?

    struct Reply { let status: Int; var body: Data = Data(); var headers: [String: String] = [:]; var hang = false }
    func reply(_ request: URLRequest) -> Reply {
        lock.withLock {
            let url = request.url!
            let cookies = request.value(forHTTPHeaderField: "Cookie") ?? ""
            precondition(["bgm.tv", "next.bgm.tv", "api.bgm.tv"].contains(url.host), "Login escaped official hosts")
            if url.path == "/login" {
                precondition(cookies.isEmpty, "An old web session leaked into a new login")
                userAgent = request.value(forHTTPHeaderField: "User-Agent")
                return Reply(status: 200, body: Data((broken ? "<html>Changed</html>" : "<input value='login-hash' type='hidden' name='formhash'>").utf8),
                             headers: ["Set-Cookie": "sid=\(cookie); Domain=.bgm.tv; Path=/; Secure, hostonly=value; Path=/; Secure, expired=value; Max-Age=0; Path=/"], hang: hang)
            }
            precondition(request.value(forHTTPHeaderField: "User-Agent") == userAgent, "Website login must preserve User-Agent")
            if url.path == "/subject/8" {
                precondition(cookies.contains("chii_auth=test"))
                return Reply(status: 200, body: Data(
                    #"<a href="/subject/8/erase_collect?gh=abc123">取消收藏</a>"#.utf8
                ))
            }
            if url.path == "/subject/8/erase_collect" {
                precondition(cookies.contains("chii_auth=test"))
                precondition(url.query == "gh=abc123")
                precondition(request.value(forHTTPHeaderField: "Referer") == "https://bgm.tv/subject/8")
                return Reply(status: 302, headers: ["Location": "https://bgm.tv/subject/8"])
            }
            if url.path == "/signup/captcha" {
                precondition(cookies.contains("sid=" + cookie))
                precondition(!cookies.contains("expired="))
                captchaCookies.append(cookies)
                return Reply(status: 200, body: Self.image())
            }
            if url.path == "/FollowTheRabbit" {
                attempts += 1
                let body = Self.body(request)
                let components = URLComponents(string: "https://test.invalid/?" + String(decoding: body, as: UTF8.self))!
                let values = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
                precondition(values["password"] == password && values["formhash"] == "login-hash")
                precondition(cookies.contains("sid=" + cookie))
                if reject { return Reply(status: 200, body: Data("<p class='text'>验证码错误，请返回重试。</p>".utf8)) }
                return Reply(status: 302, headers: ["Set-Cookie": "chii_auth=\(cookie); Domain=.bgm.tv; Path=/; Secure; Expires=Wed, 01 Jan 2099 00:00:00 GMT", "Location": "https://untrusted.invalid/"])
            }
            if url.path == "/demo/access-tokens", request.httpMethod == "POST" {
                issued += 1
                precondition(cookies.contains("chii_auth=") && cookies.contains("sid=" + cookie))
                precondition(!cookies.contains("hostonly="), "A host-only cookie escaped to next.bgm.tv")
                let json = try! JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
                precondition(json["days"] as? Int == 365)
                tokenName = json["name"] as! String
                return Reply(status: 200, body: try! JSONEncoder().encode(token))
            }
            if url.path == "/v0/me" {
                checked += 1
                precondition(cookies.isEmpty && request.value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
                if checked == 1 { return Reply(status: 503) }
                if checked == 2 { return Reply(status: 200, body: Data("{}".utf8)) }
                return Reply(status: 200, body: Data(#"{"id":1,"username":"local-fixture","nickname":"Fixture"}"#.utf8))
            }
            if url.path == "/demo/access-token" {
                return Reply(status: 200, body: Data("<div id='token-21'><span class='fw-bold'>Other app</span></div><div id=\"token-22\"><span class=\"name fw-bold\">\(tokenName)</span></div>".utf8))
            }
            if url.path == "/demo/access-tokens", request.httpMethod == "DELETE" {
                let json = try! JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
                removed.append(json["id"] as! Int)
                return Reply(status: 204)
            }
            return Reply(status: 404)
        }
    }

    static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
    static func image() -> Data {
        let context = CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 128,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class LoginProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = LoginServer.shared.reply(request)
        if reply.hang { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct WebLoginTests {
    static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            precondition(MirrorRouting.echAvailable)
            let routing = MirrorRouting()
            try routing.configure(ConnectionSettings(mode: .encrypted), persistChanges: false)
            let api = APIClient(routing: routing, discoverMirrors: false)
            let service = BangumiWebLogin(api: api)
            let id = UUID()
            let data = try await service.start(id: id)
            precondition(!data.isEmpty)
            let routes = await api.webLoginRoutes()
            let tokenPage = try await api.webLoginRequest(URL(string: "https://next.bgm.tv/demo/access-token")!, route: routes[0])
            precondition([200, 302, 303].contains(tokenPage.response.statusCode), "The token-management host must also be reachable over ECH")
            await service.cancel(id: id)
            #if BGMORI_ECH
            let info = ECHTransport.info!
            precondition(info.acceptedConnections > 0 && !info.directInterface.isEmpty && info.proxyDisabled)
            print("PASS live: official login form, isolated cookie, decoded captcha and token-management host over verified ECH; interface=\(info.directInterface)")
            #endif
            return
        }
        precondition(!MirrorRouting.echAvailable, "Protocol fixtures must never send test credentials to real ECH hosts")
        precondition(BangumiWebLogin.formhash(in: "<input value='reordered' NAME='formhash'>") == "reordered")
        precondition(BangumiWebLogin.formhash(in: "<input name='other' value='bad'>") == nil)
        precondition(BangumiWebLogin.rejectionMessage("<p class='text'>验证码错误</p>").contains("验证码"))

        let liveRemoval = #"<a class="l" href="/subject/8/erase_collect?gh=abc123">取消收藏</a>"#
        let liveRemovalURLs = SubjectRemovalHTML.removalURLs(in: liveRemoval, subjectID: 8)
        precondition(liveRemovalURLs.first?.absoluteString == "https://bgm.tv/subject/8/remove?gh=abc123")
        precondition(liveRemovalURLs.contains {
            $0.absoluteString == "https://bgm.tv/subject/8/erase_collect?gh=abc123"
        })
        let encodedRemoval = #"<a href="https://bangumi.tv/subject/8/remove?gh=abc123&amp;ajax=1">取消收藏</a>"#
        precondition(SubjectRemovalHTML.removalURL(in: encodedRemoval, subjectID: 8)?.absoluteString
                     == "https://bgm.tv/subject/8/remove?gh=abc123&ajax=1")
        let bothRemovals = #"<a href="/subject/8/erase_collect?gh=old">x</a><a href="/subject/8/remove?gh=new">y</a>"#
        precondition(SubjectRemovalHTML.removalURLs(in: bothRemovals, subjectID: 8).first?.absoluteString
                     == "https://bgm.tv/subject/8/remove?gh=new")
        let hashFallback = #"<a href="/logout/def456">退出</a>"#
        precondition(SubjectRemovalHTML.removalURL(in: hashFallback, subjectID: 8)?.absoluteString
                     == "https://bgm.tv/subject/8/remove?gh=def456")
        let javascriptRemoval = #"<a href="javascript:void(0)" onclick="eraseSubjectCollect(8,'js789')">取消收藏</a>"#
        precondition(SubjectRemovalHTML.removalURL(in: javascriptRemoval, subjectID: 8)?.absoluteString
                     == "https://bgm.tv/subject/8/remove?gh=js789")
        precondition(SubjectRemovalHTML.removalURL(in: "<html>登录</html>", subjectID: 8) == nil)
        precondition(!SubjectRemovalHTML.isSignedIn("<html>登录</html>"))
        precondition(SubjectRemovalHTML.isSignInPage(#"<form id="loginForm"></form>"#))
        print("PASS: normal-subject remove is preferred, erase_collect remains a fallback, formhash fallback and signed-out detection")

        let cookieResponse = HTTPURLResponse(url: URL(string: "https://bgm.tv/login")!, statusCode: 200,
                                             httpVersion: nil, headerFields: nil)!
        var jar = WebsiteCookieJar()
        jar.absorb(WebLoginHTTPResult(
            data: Data(),
            response: cookieResponse,
            setCookies: [
                "chii_auth=auth-value; Domain=.bgm.tv; Path=/; Secure",
                "sid=host-value; Path=/; Secure"
            ]
        ), from: URL(string: "https://bgm.tv/login")!)
        let subjectCookie = jar.cookieHeader(for: URL(string: "https://bgm.tv/subject/8")!) ?? ""
        precondition(subjectCookie.contains("chii_auth=auth-value") && subjectCookie.contains("sid=host-value"))
        precondition(jar.cookieHeader(for: URL(string: "https://next.bgm.tv/demo/access-token")!)?.contains("sid=host-value") == false)
        precondition(jar.snapshot.cookies.allSatisfy { $0.domain == "bgm.tv" })
        let encodedSnapshot = try JSONEncoder().encode(jar.snapshot)
        let decodedSnapshot = try JSONDecoder().decode(WebsiteSessionSnapshot.self, from: encodedSnapshot)
        precondition(decodedSnapshot.cookies == jar.snapshot.cookies)
        print("PASS: website cookies keep domain/path/host-only scope, persist only main-site values and round-trip through JSON")
        let routing = MirrorRouting()
        try routing.configure(ConnectionSettings(mode: .custom, customRoot: "custom.example.com"), persistChanges: false)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginProtocol.self]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = APIClient(session: session, routing: routing, discoverMirrors: false)
        let routes = await api.webLoginRoutes()
        precondition(routes.count == 1 && !routes[0].encrypted, "Custom services must never receive website passwords")
        let service = BangumiWebLogin(api: api)
        let id = UUID()
        _ = try await service.start(id: id)
        do {
            _ = try await service.submit(id: id, email: "fixture@example.invalid", password: LoginServer.shared.password, captcha: "fixture")
            preconditionFailure("An unverified account must not be accepted")
        } catch BangumiLoginError.accountCheck { }
        let installedToken = await api.hasToken()
        precondition(!installedToken)
        do {
            _ = try await service.submit(id: id, email: "", password: "", captcha: "")
            preconditionFailure("A malformed 200 response must not create a logged-in account")
        } catch BangumiLoginError.accountCheck { }
        let credential = try await service.submit(id: id, email: "", password: "", captcha: "")
        precondition(credential.user.id == 1 && credential.expiresAt.timeIntervalSinceNow > 364 * 86_400)
        precondition(LoginServer.shared.attempts == 1 && LoginServer.shared.issued == 1, "Retrying account verification must never replay login/token creation")
        let snapshot = await service.snapshot(id: id)
        precondition(snapshot?.cookies.contains(where: { $0.name == "chii_auth" && !$0.value.isEmpty }) == true,
                     "A completed login must expose the main-site session for in-app collection removal")
        precondition(snapshot?.cookies.contains(where: { $0.name == "sid" }) == true)
        await service.cancel(id: id)
        let afterCancel = await service.snapshot(id: id)
        precondition(afterCancel == nil, "Cancelling login must discard the website session")
        do { _ = try await service.submit(id: id, email: "", password: "", captcha: ""); preconditionFailure() }
        catch APIError.message { }
        await service.revoke(token: credential.token, name: credential.name)
        precondition(LoginServer.shared.removed == [22], "Logout must only revoke this login's token")
        let sessionRoute = await api.webLoginRoutes()[0]
        let subjectPage = try await api.webSessionRequest(
            URL(string: "https://bgm.tv/subject/8")!, route: sessionRoute, cookie: "chii_auth=test"
        )
        precondition(subjectPage.response.statusCode == 200)
        let removalPage = try await api.webSessionRequest(
            URL(string: "https://bgm.tv/subject/8/erase_collect?gh=abc123")!,
            route: sessionRoute, cookie: "chii_auth=test",
            referer: URL(string: "https://bgm.tv/subject/8")!
        )
        precondition(removalPage.response.statusCode == 302)
        do {
            _ = try await api.webSessionRequest(URL(string: "https://bgm.tv/user/sai")!,
                                                route: sessionRoute, cookie: "chii_auth=test")
            preconditionFailure("The stored website session must not authorize other pages")
        } catch APIError.invalidURL { }
        print("PASS: website session requests are limited to the subject page and its remove action")
        print("PASS: form encoding, cookie domains/expiry/host-only scope, pinned official routes, verified account and own-token revocation")

        LoginServer.shared.reject = true
        let rejectedID = UUID()
        _ = try await service.start(id: rejectedID)
        do {
            _ = try await service.submit(id: rejectedID, email: "fixture@example.invalid", password: LoginServer.shared.password, captcha: "fixture")
            preconditionFailure()
        } catch BangumiLoginError.rejected(let message) { precondition(message.contains("验证码")) }
        precondition(LoginServer.shared.attempts == 2 && LoginServer.shared.issued == 1)
        try routing.configure(ConnectionSettings(mode: .official), persistChanges: false)
        do {
            _ = try await service.submit(id: rejectedID, email: "", password: "", captcha: "")
            preconditionFailure()
        } catch APIError.message { }
        precondition(LoginServer.shared.attempts == 2, "A changed route must invalidate the old website session")
        await service.cancel(id: rejectedID)
        print("PASS: rejected captcha never generates a token; route changes and cancellation invalidate sessions")

        let delegate = WebLoginRedirectDelegate()
        let url = URL(string: "https://bgm.tv/FollowTheRabbit")!
        let redirect: URLRequest? = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: session.dataTask(with: url), willPerformHTTPRedirection: HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: URL(string: "https://untrusted.invalid/")!)) { continuation.resume(returning: $0) }
        }
        precondition(redirect == nil)
        print("PASS: credential-bearing website requests never follow redirects")

        LoginServer.shared.broken = true
        do { _ = try await service.start(id: UUID()); preconditionFailure() }
        catch BangumiLoginError.websiteChanged { }
        LoginServer.shared.broken = false
        LoginServer.shared.hang = true
        let pendingID = UUID()
        let pending = Task { try await service.start(id: pendingID) }
        try await Task.sleep(for: .milliseconds(50))
        pending.cancel()
        do { _ = try await pending.value; preconditionFailure() }
        catch APIError.cancelled { }
        await service.cancel(id: pendingID)
        print("PASS: website changes surface an explicit error; stalled login reads cancel cleanly")
    }
}
