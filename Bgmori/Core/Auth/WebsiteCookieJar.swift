import Foundation

/// One website cookie, in a form that can live in the Keychain between launches.
/// Values are credentials: never print, log or send them to a mirror.
struct WebsiteCookie: Codable, Sendable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresAt: Date?
    var isSecure: Bool
    var hostOnly: Bool
    var origin: String
}

struct WebsiteSessionSnapshot: Codable, Sendable {
    var cookies: [WebsiteCookie]

    var isEmpty: Bool { cookies.isEmpty }

    /// Only the main website cookies are needed to remove a collection.
    /// Dropping the API and token-page cookies keeps the persisted snapshot small.
    var mainSiteOnly: WebsiteSessionSnapshot {
        WebsiteSessionSnapshot(cookies: cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain == "bgm.tv" || domain.hasSuffix(".bgm.tv")
                || domain == "bangumi.tv" || domain.hasSuffix(".bangumi.tv")
        })
    }
}

/// Cookie absorption and header construction shared by the login session and
/// the persistent collection-removal session.
struct WebsiteCookieJar: Sendable {
    private(set) var cookies: [WebsiteCookie]

    init(cookies: [WebsiteCookie] = []) {
        self.cookies = Array(cookies.filter(Self.isSane).suffix(64))
    }

    var snapshot: WebsiteSessionSnapshot {
        WebsiteSessionSnapshot(cookies: cookies).mainSiteOnly
    }

    func cookieHeader(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            let hostMatches = cookie.hostOnly
                ? host == cookie.origin.lowercased()
                : host == domain || host.hasSuffix("." + domain)
            let path = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/")
            let fresh = cookie.expiresAt.map { $0 > Date() } ?? true
            return hostMatches && pathMatches && fresh && (!cookie.isSecure || url.scheme == "https")
        }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    mutating func absorb(_ result: WebLoginHTTPResult, from url: URL) {
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
                        $0.name == cookie.name
                            && $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == domain
                            && $0.path == cookie.path
                    }
                    let maxAge = line.range(of: #";\s*max-age\s*=\s*(?:0|-\d+)\s*(?:;|$)"#,
                                            options: [.regularExpression, .caseInsensitive])
                    if cookie.value != "deleted", maxAge == nil, cookie.expiresDate.map({ $0 > Date() }) ?? true {
                        cookies.append(WebsiteCookie(
                            name: cookie.name,
                            value: cookie.value,
                            domain: domain,
                            path: cookie.path.isEmpty ? "/" : cookie.path,
                            expiresAt: cookie.expiresDate,
                            isSecure: cookie.isSecure,
                            hostOnly: hostOnly,
                            origin: url.host ?? ""
                        ))
                    }
                }
            }
        }
        cookies = Array(cookies.filter(Self.isSane).suffix(64))
    }

    private static func isSane(_ cookie: WebsiteCookie) -> Bool {
        !cookie.name.isEmpty && cookie.name.utf8.count <= 128
            && !cookie.value.isEmpty && cookie.value.utf8.count <= 4_096
            && !cookie.domain.isEmpty && cookie.domain.utf8.count <= 253
            && cookie.path.utf8.count <= 256
    }
}

/// Parses the logged-in subject page for the website's own remove action.
/// Normal subjects use `/remove`; the doujin section uses `/erase_collect`.
/// Both are tried because the page can change, and the API verifies the result.
enum SubjectRemovalHTML {
    static func removalURLs(in html: String, subjectID: Int) -> [URL] {
        if isSignInPage(html) { return [] }
        let id = String(subjectID)
        let patterns = [
            #"href\s*=\s*[\"']([^\"']*/subject/"# + id + #"/(?:erase_collect|remove)[^\"']*)[\"']"#,
            #"[\"'](/subject/"# + id + #"/(?:erase_collect|remove)[^\"']*)[\"']"#
        ]
        var found: [URL] = []
        for pattern in patterns {
            for raw in captures(pattern, in: html) {
                if let url = canonicalRemovalURL(raw, subjectID: subjectID) {
                    found.append(url)
                }
            }
        }

        var hash: String?
        for url in found {
            if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "gh" })?.value, !value.isEmpty {
                hash = value
                break
            }
        }
        if hash == nil {
            hash = BangumiWebLogin.formhash(in: html)
                ?? capture(#"eraseSubjectCollect\(\s*[\"']?"# + id + #"[\"']?\s*,\s*[\"']([A-Za-z0-9]+)[\"']\s*\)"#, in: html)
                ?? capture(#"/logout/([A-Za-z0-9]+)"#, in: html)
        }
        if let hash, hash.count <= 256,
           hash.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil {
            for path in ["remove", "erase_collect"] {
                if let url = URL(string: "https://bgm.tv/subject/\(subjectID)/\(path)?gh=\(hash)") {
                    found.append(url)
                }
            }
        }

        var seen = Set<String>()
        let unique = found.filter { seen.insert($0.absoluteString).inserted }
        // Prefer the normal-subject endpoint before the doujin alias.
        return unique.filter { $0.path.hasSuffix("/remove") }
            + unique.filter { !$0.path.hasSuffix("/remove") }
    }

    static func removalURL(in html: String, subjectID: Int) -> URL? {
        removalURLs(in: html, subjectID: subjectID).first
    }

    static func isSignedIn(_ html: String) -> Bool {
        isAuthenticatedPage(html)
            || html.range(of: #"/subject/\d+/(?:erase_collect|remove)"#, options: .regularExpression) != nil
    }

    /// The page's own account menu is the signal that the stored cookies were
    /// actually accepted. A removal-looking template on the anonymous page is
    /// not enough.
    static func isAuthenticatedPage(_ html: String) -> Bool {
        html.range(of: #"/logout/[A-Za-z0-9]+"#, options: .regularExpression) != nil
            || html.range(of: #"id\s*=\s*[\"']headerUser[\"']"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isSignInPage(_ html: String) -> Bool {
        html.contains("/FollowTheRabbit")
            || html.range(of: #"id\s*=\s*[\"']loginForm[\"']"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func canonicalRemovalURL(_ raw: String, subjectID: Int) -> URL? {
        let decoded = decodeEntities(raw)
        guard var components = URLComponents(string: decoded) else { return nil }
        if components.host == nil {
            components = URLComponents(string: "https://bgm.tv"
                + (decoded.hasPrefix("/") ? decoded : "/" + decoded)) ?? URLComponents()
        }
        if let host = components.host?.lowercased(),
           ["bangumi.tv", "www.bangumi.tv", "www.bgm.tv", "chii.in", "www.chii.in"].contains(host) {
            components.host = "bgm.tv"
        }
        components.scheme = "https"
        components.fragment = nil
        components.queryItems = components.queryItems?.filter { item in
            item.name == "gh" || (item.name == "ajax" && item.value == "1")
        }
        guard components.queryItems?.contains(where: { $0.name == "gh" && !($0.value ?? "").isEmpty }) == true,
              components.host == "bgm.tv",
              let url = components.url,
              url.path.range(of: #"^/subject/"# + String(subjectID) + #"/(?:erase_collect|remove)$"#,
                             options: .regularExpression) != nil else { return nil }
        return url
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&#x26;", with: "&")
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text).first
    }
}
