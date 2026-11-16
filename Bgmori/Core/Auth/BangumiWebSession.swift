import Foundation

/// Uses the website session saved at login to call the same remove action the
/// website itself uses. API v0 has no subject-collection delete endpoint.
actor BangumiWebSession: SubjectCollectionRemoving {
    private let api: APIClient
    private var snapshot: WebsiteSessionSnapshot?
    private var generation = UUID()

    init(api: APIClient, snapshot: WebsiteSessionSnapshot? = nil) {
        self.api = api
        #if DEBUG
        // UI tests and previews must never read the user's stored cookies.
        if ProcessInfo.processInfo.environment["BGMORI_GUEST_MODE"] == "1" {
            self.snapshot = nil
            return
        }
        #endif
        self.snapshot = snapshot ?? WebsiteSessionStore.load()
    }

    func adopt(_ snapshot: WebsiteSessionSnapshot) {
        generation = UUID()
        self.snapshot = snapshot
        WebsiteSessionStore.save(snapshot)
    }

    func clear() {
        generation = UUID()
        snapshot = nil
        WebsiteSessionStore.clear()
    }

    func removeCollection(subjectID: Int) async throws {
        let generation = self.generation
        guard let snapshot, !snapshot.isEmpty else { throw BangumiWebSessionError.signInRequired }
        guard let route = await api.webLoginRoutes().first else { throw BangumiWebSessionError.signInRequired }

        var jar = WebsiteCookieJar(cookies: snapshot.cookies)
        let subjectURL = URL(string: "https://bgm.tv/subject/\(subjectID)")!
        let page: WebLoginHTTPResult
        do {
            page = try await api.webSessionRequest(subjectURL, route: route,
                                                   cookie: jar.cookieHeader(for: subjectURL))
        } catch APIError.unauthorized {
            throw expired()
        } catch APIError.forbidden {
            throw expired()
        }
        guard generation == self.generation else { throw APIError.cancelled }
        jar.absorb(page, from: subjectURL)
        save(jar, generation: generation)

        let html = String(decoding: page.data, as: UTF8.self)
        guard SubjectRemovalHTML.isAuthenticatedPage(html) else { throw expired() }
        let removalURLs = SubjectRemovalHTML.removalURLs(in: html, subjectID: subjectID)
        #if DEBUG
        note("subject=\(subjectID) page=\(page.response.statusCode) auth=true candidates=\(removalURLs.map(\.path).joined(separator: ","))")
        #endif
        guard !removalURLs.isEmpty else {
            throw SubjectRemovalHTML.isSignedIn(html)
                ? BangumiWebSessionError.websiteChanged
                : expired()
        }

        var sawAccepted = false
        var lastStatus: Int?
        for removalURL in removalURLs {
            guard generation == self.generation else { throw APIError.cancelled }
            #if DEBUG
            note("try path=\(removalURL.path)")
            #endif
            let result: WebLoginHTTPResult
            do {
                result = try await api.webSessionRequest(
                    removalURL, route: route,
                    cookie: jar.cookieHeader(for: removalURL),
                    referer: subjectURL
                )
            } catch APIError.unauthorized {
                throw expired()
            } catch APIError.forbidden {
                throw expired()
            }
            guard generation == self.generation else { throw APIError.cancelled }
            jar.absorb(result, from: removalURL)
            save(jar, generation: generation)

            if result.response.statusCode == 401 || result.response.statusCode == 403 {
                throw expired()
            }
            guard (200..<400).contains(result.response.statusCode) else {
                lastStatus = result.response.statusCode
                continue
            }
            let responseHTML = String(decoding: result.data.prefix(262_144), as: UTF8.self)
            if SubjectRemovalHTML.isSignInPage(responseHTML) {
                throw expired()
            }
            sawAccepted = true
            #if DEBUG
            note("response path=\(removalURL.path) status=\(result.response.statusCode)")
            #endif

            // The web action can answer 200/302 without doing anything (for
            // example the doujin endpoint against a normal subject). Confirm
            // against the API before accepting it, then try the other endpoint.
            let confirmed = await removalConfirmed(subjectID: subjectID)
            #if DEBUG
            note("verify subject=\(subjectID) result=\(confirmed.map(String.init) ?? "unknown")")
            #endif
            switch confirmed {
            case true:
                return
            case false:
                // The API can trail the website by a moment. Re-check once
                // before declaring this endpoint ineffective.
                try? await Task.sleep(for: .milliseconds(350))
                switch await removalConfirmed(subjectID: subjectID) {
                case true: return
                case nil: return
                case false: continue
                }
            case nil:
                // The API cannot confirm right now. Keep the optimistic local
                // result and let LibraryStore reconcile instead of rolling
                // back a possibly successful removal.
                return
            }
        }

        if sawAccepted {
            throw BangumiWebSessionError.notRemoved
        }
        throw BangumiWebSessionError.http(lastStatus ?? 0)
    }

    private func removalConfirmed(subjectID: Int) async -> Bool? {
        do {
            _ = try await api.userCollection("-", subjectID: subjectID, force: true, storeInCache: false)
            return false
        } catch APIError.notFound {
            return true
        } catch {
            return nil
        }
    }

    #if DEBUG
    /// Sanitized diagnostics: paths, statuses and booleans only — never cookies,
    /// `gh` values or response bodies.
    private func note(_ message: String) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bgmori", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("RemovalDiagnostics.log")
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file, options: .atomic)
        }
    }
    #endif

    private func expired() -> BangumiWebSessionError {
        generation = UUID()
        snapshot = nil
        WebsiteSessionStore.clear()
        return .sessionExpired
    }

    private func save(_ jar: WebsiteCookieJar, generation: UUID) {
        guard generation == self.generation else { return }
        let snapshot = jar.snapshot
        guard !snapshot.isEmpty else { return }
        self.snapshot = snapshot
        WebsiteSessionStore.save(snapshot)
    }
}
