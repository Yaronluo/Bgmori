import Foundation
import ImageIO

enum BangumiLoginError: LocalizedError {
    case websiteChanged, rejected(String), tokenCreation, accountCheck
    var errorDescription: String? {
        switch self {
        case .websiteChanged: "Bangumi 登录页面暂时无法识别，请稍后重试或查看官网"
        case .rejected(let message): message
        case .tokenCreation: "已登录官网，但生成登录凭证未完成，请重试"
        case .accountCheck: "登录凭证暂时无法验证，请重试"
        }
    }
}

struct WebsiteCredential: Sendable {
    let token: String
    let name: String
    let user: User
    let expiresAt: Date
}

/// An isolated website session, exclusively for account login and token creation.
/// Passwords never enter storage; cookies remain in memory until completion or cancellation.
actor BangumiWebLogin {
    private final class Session {
        let id: UUID
        let route: WebLoginRoute
        let name: String
        var formhash = ""
        var cookies: [StoredCookie] = []
        var signedIn = false
        var pendingToken: String?
        var tokenCreatedAt: Date?

        init(id: UUID, route: WebLoginRoute) {
            self.id = id
            self.route = route
            #if os(macOS)
            name = "Bgmori Mac " + UUID().uuidString
            #else
            name = "Bgmori iPhone " + UUID().uuidString
            #endif
        }

        func absorb(_ result: WebLoginHTTPResult, from url: URL) {
            for header in result.setCookies {
                // Foundation may combine repeated headers; Expires contains commas too.
                let lines = header.replacingOccurrences(of: #",(?=\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+=)"#,
                                                       with: "\n", options: .regularExpression).components(separatedBy: "\n")
                for line in lines {
                    let hostOnly = line.range(of: #";\s*domain\s*="#, options: [.regularExpression, .caseInsensitive]) == nil
                    for cookie in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": line], for: url) {
                        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                        guard ["bgm.tv", "next.bgm.tv", "api.bgm.tv"].contains(domain),
                              url.host == domain || url.host?.hasSuffix("." + domain) == true else { continue }
                        cookies.removeAll {
                            $0.cookie.name == cookie.name && $0.cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == domain && $0.cookie.path == cookie.path
                        }
                        let maxAge = line.range(of: #";\s*max-age\s*=\s*(?:0|-\d+)\s*(?:;|$)"#, options: [.regularExpression, .caseInsensitive])
                        if cookie.value != "deleted", maxAge == nil, cookie.expiresDate.map({ $0 > Date() }) ?? true {
                            cookies.append(StoredCookie(cookie: cookie, hostOnly: hostOnly, origin: url.host ?? ""))
                        }
                    }
                }
            }
        }

        func cookieHeader(for url: URL) -> String? {
            let matching = cookies.filter { stored in
                let cookie = stored.cookie
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                let hostMatches = stored.hostOnly ? url.host == stored.origin : url.host == domain || url.host?.hasSuffix("." + domain) == true
                let path = cookie.path.isEmpty ? "/" : cookie.path
                return hostMatches && (url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/"))
                    && (cookie.expiresDate.map { $0 > Date() } ?? true) && (!cookie.isSecure || url.scheme == "https")
            }.map(\.cookie)
            return matching.isEmpty ? nil : HTTPCookie.requestHeaderFields(with: matching)["Cookie"]
        }
    }

    private struct StoredCookie {
        let cookie: HTTPCookie
        let hostOnly: Bool
        let origin: String
    }
    private let api: APIClient
    private var session: Session?
    private var startingID: UUID?
    private var operation = UUID()

    init(api: APIClient) { self.api = api }

    func start(id: UUID) async throws -> Data {
        let operationID = UUID()
        operation = operationID
        startingID = id
        session = nil
        let routes = await api.webLoginRoutes()
        var lastError: Error = APIError.network("无法连接 Bangumi 登录服务，请检查网络后重试")
        for route in routes {
            let candidate = Session(id: id, route: route)
            do {
                let url = URL(string: "https://bgm.tv/login")!
                let result = try await api.webLoginRequest(url, route: route)
                try Task.checkCancellation()
                guard operation == operationID else { throw APIError.cancelled }
                guard result.response.statusCode == 200,
                      let hash = Self.formhash(in: String(decoding: result.data, as: UTF8.self)) else {
                    throw BangumiLoginError.websiteChanged
                }
                candidate.formhash = hash
                candidate.absorb(result, from: url)
                let captchaURL = URL(string: "https://bgm.tv/signup/captcha?\(UInt64.random(in: 1_000_000_000_000...9_999_999_999_999))")!
                let captcha = try await api.webLoginRequest(captchaURL, route: route, cookie: candidate.cookieHeader(for: captchaURL))
                try Task.checkCancellation()
                guard operation == operationID else { throw APIError.cancelled }
                guard captcha.response.statusCode == 200, captcha.data.count <= 1_048_576,
                      let source = CGImageSourceCreateWithData(captcha.data as CFData, nil),
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                    throw APIError.message("验证码加载失败，请重试")
                }
                candidate.absorb(captcha, from: captchaURL)
                session = candidate
                startingID = nil
                return captcha.data
            } catch {
                if Task.isCancelled || operation != operationID { throw APIError.cancelled }
                lastError = error
            }
        }
        startingID = nil
        throw lastError
    }

    func submit(id: UUID, email: String, password: String, captcha: String) async throws -> WebsiteCredential {
        guard let current = session, current.id == id else { throw APIError.message("请重新获取验证码") }
        if !current.signedIn {
            let url = URL(string: "https://bgm.tv/FollowTheRabbit")!
            let form = ["formhash": current.formhash, "referer": "", "dreferer": "", "email": email,
                        "password": password, "captcha_challenge_field": captcha, "loginsubmit": "登录"]
            let response = try await api.webLoginRequest(url, method: "POST", route: current.route,
                cookie: current.cookieHeader(for: url), body: Self.formBody(form), contentType: "application/x-www-form-urlencoded")
            try ensureCurrent(current)
            current.absorb(response, from: url)
            guard (200...399).contains(response.response.statusCode),
                  current.cookies.contains(where: { $0.cookie.name == "chii_auth" && !$0.cookie.value.isEmpty }) else {
                throw BangumiLoginError.rejected(Self.rejectionMessage(String(decoding: response.data, as: UTF8.self)))
            }
            current.signedIn = true
        }
        if current.pendingToken == nil {
            let url = URL(string: "https://next.bgm.tv/demo/access-tokens")!
            let body = try JSONSerialization.data(withJSONObject: ["name": current.name, "days": 365])
            let response = try await api.webLoginRequest(url, method: "POST", route: current.route,
                cookie: current.cookieHeader(for: url), body: body, contentType: "application/json")
            try ensureCurrent(current)
            guard (200...299).contains(response.response.statusCode),
                  let token = try? JSONDecoder().decode(String.self, from: response.data),
                  !token.isEmpty, token.count <= 1024,
                  token.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
                throw BangumiLoginError.tokenCreation
            }
            current.pendingToken = token
            current.tokenCreatedAt = Date()
        }
        guard let token = current.pendingToken else { throw BangumiLoginError.tokenCreation }
        let checked = try await api.webLoginRequest(URL(string: "https://api.bgm.tv/v0/me")!, route: current.route, bearer: token)
        try ensureCurrent(current)
        guard checked.response.statusCode == 200, let user = try? JSONDecoder().decode(User.self, from: checked.data),
              user.id > 0, !user.username.isEmpty else {
            throw BangumiLoginError.accountCheck
        }
        return WebsiteCredential(token: token, name: current.name, user: user,
                                 expiresAt: (current.tokenCreatedAt ?? Date()).addingTimeInterval(365 * 86_400))
    }

    func hasWebsiteLogin(id: UUID) -> Bool { session?.id == id && session?.signedIn == true }

    func cancel(id: UUID) {
        if session?.id == id || startingID == id {
            operation = UUID()
            session = nil
            startingID = nil
        }
    }

    /// Only revoke the unique name issued by this login, never another application's token.
    func revoke(token: String, name: String) async {
        guard name.hasPrefix("Bgmori ") else { return }
        for route in await api.webLoginRoutes() {
            do {
                let page = try await api.webLoginRequest(URL(string: "https://next.bgm.tv/demo/access-token")!, route: route, bearer: token)
                guard page.response.statusCode == 200 else { continue }
                for id in Self.tokenIDs(named: name, html: String(decoding: page.data, as: UTF8.self)) {
                    let body = try JSONSerialization.data(withJSONObject: ["id": id])
                    _ = try await api.webLoginRequest(URL(string: "https://next.bgm.tv/demo/access-tokens")!, method: "DELETE",
                                                     route: route, bearer: token, body: body, contentType: "application/json")
                }
                return
            } catch { if Task.isCancelled { return } }
        }
    }

    private func ensureCurrent(_ current: Session) throws {
        try Task.checkCancellation()
        guard session === current else { throw APIError.cancelled }
    }

    static func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }.map {
            ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "="
                + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").utf8)
    }

    static func formhash(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<input\b[^>]*>"#, options: .caseInsensitive) else { return nil }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let input = String(html[range])
            if capture(#"\bname\s*=\s*["']formhash["']"#, in: input, group: 0) != nil,
               let value = capture(#"\bvalue\s*=\s*["']([^"']+)["']"#, in: input), value.count <= 256 { return value }
        }
        return nil
    }

    static func rejectionMessage(_ html: String) -> String {
        let text = capture(#"<p\b[^>]*class=["'][^"']*\btext\b[^"']*["'][^>]*>(.*?)</p>"#, in: html) ?? ""
        if text.contains("验证码") { return "验证码不正确或已失效，请重新输入" }
        if text.contains("锁") || text.contains("次数") || text.contains("频繁") { return "登录尝试过于频繁，请稍后重试" }
        if text.contains("密码") || text.contains("用户") || text.contains("邮箱") { return "邮箱或密码不正确，请检查后重试" }
        return "登录未成功，请检查邮箱、密码和验证码后重试"
    }

    static func tokenIDs(named name: String, html: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"\bid=["']token-(\d+)["']"#) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        return matches.enumerated().compactMap { index, match in
            let end = index + 1 < matches.count ? matches[index + 1].range.location : (html as NSString).length
            let block = (html as NSString).substring(with: NSRange(location: match.range.location, length: end - match.range.location))
            guard let tokenName = capture(#"class=["'][^"']*\bfw-bold\b[^"']*["'][^>]*>([^<]*)<"#, in: block),
                  tokenName.trimmingCharacters(in: .whitespacesAndNewlines) == name,
                  let idRange = Range(match.range(at: 1), in: html) else { return nil }
            return Int(html[idRange])
        }
    }

    private static func capture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
}
