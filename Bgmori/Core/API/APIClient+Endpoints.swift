import Foundation

struct KeywordBody: Encodable, Sendable {
    let keyword: String
}

struct EpisodeTypeBody: Encodable, Sendable {
    let type: Int

    enum CodingKeys: String, CodingKey { case type }
}

struct EpisodeIDsBody: Encodable, Sendable {
    let episodeID: [Int]
    let type: Int

    enum CodingKeys: String, CodingKey {
        case episodeID = "episode_id"
        case type
    }
}

struct EmptyBody: Encodable, Sendable {}

extension APIClient {
    // MARK: - User

    func me() async throws -> User {
        try await get("/v0/me", as: User.self, auth: true)
    }

    func user(_ username: String) async throws -> User {
        try await get("/v0/users/\(username)", as: User.self, cacheKey: "user-\(username)", ttl: 86_400)
    }

    func userCollections(_ username: String, subjectType: Int? = nil, type: Int? = nil, limit: Int = 50, offset: Int = 0, auth: Bool = true, force: Bool = false) async throws -> Paged<UserSubjectCollection> {
        var query: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset))
        ]
        if let subjectType { query.append(.init(name: "subject_type", value: String(subjectType))) }
        if let type { query.append(.init(name: "type", value: String(type))) }
        let key = "collections-\(username)-\(subjectType ?? 0)-\(type ?? 0)-\(offset)"
        return try await get("/v0/users/\(username)/collections", query: query, as: Paged<UserSubjectCollection>.self, cacheKey: key, ttl: 600, auth: auth, force: force)
    }

    func userCollection(_ username: String, subjectID: Int) async throws -> UserSubjectCollection {
        try await get("/v0/users/\(username)/collections/\(subjectID)", as: UserSubjectCollection.self, cacheKey: "collection-\(username)-\(subjectID)", ttl: 60, auth: true)
    }

    func userCharacterCollections(_ username: String, limit: Int = 100, offset: Int = 0, auth: Bool = false, force: Bool = false) async throws -> Paged<UserCharacterCollection> {
        try await get(
            "/v0/users/\(username)/collections/-/characters",
            query: [
                .init(name: "limit", value: String(limit)),
                .init(name: "offset", value: String(offset))
            ],
            as: Paged<UserCharacterCollection>.self,
            cacheKey: "character-collections-\(username)-\(offset)-\(limit)",
            ttl: force ? 0 : 600,
            auth: auth
        )
    }

    func userPersonCollections(_ username: String, limit: Int = 100, offset: Int = 0, auth: Bool = false, force: Bool = false) async throws -> Paged<UserPersonCollection> {
        try await get(
            "/v0/users/\(username)/collections/-/persons",
            query: [
                .init(name: "limit", value: String(limit)),
                .init(name: "offset", value: String(offset))
            ],
            as: Paged<UserPersonCollection>.self,
            cacheKey: "person-collections-\(username)-\(offset)-\(limit)",
            ttl: force ? 0 : 600,
            auth: auth
        )
    }

    // MARK: - Subjects

    func subject(_ id: Int) async throws -> Subject {
        try await get("/v0/subjects/\(id)", as: Subject.self, cacheKey: "subject-\(id)", ttl: 86_400)
    }

    func browseSubjects(type: Int, sort: String, year: Int? = nil, month: Int? = nil, limit: Int = 12, offset: Int = 0, force: Bool = false) async throws -> Paged<Subject> {
        var query: [URLQueryItem] = [
            .init(name: "type", value: String(type)),
            .init(name: "sort", value: sort),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset))
        ]
        if let year { query.append(.init(name: "year", value: String(year))) }
        if let month { query.append(.init(name: "month", value: String(month))) }
        let key = "browse-\(type)-\(sort)-\(year ?? 0)-\(month ?? 0)-\(offset)-\(limit)"
        return try await get("/v0/subjects", query: query, as: Paged<Subject>.self, cacheKey: key, ttl: force ? 0 : 1_800)
    }

    func searchSubjects(
        keyword: String,
        sort: String = "match",
        filter: SubjectSearchFilter? = nil,
        limit: Int = 24,
        offset: Int = 0,
        cacheKey: String? = nil,
        ttl: TimeInterval = 0
    ) async throws -> Paged<Subject> {
        let body = SubjectSearchRequest(keyword: keyword, sort: sort, filter: filter)
        return try await post(
            "/v0/search/subjects",
            body: body,
            query: [
                .init(name: "limit", value: String(limit)),
                .init(name: "offset", value: String(offset))
            ],
            as: Paged<Subject>.self,
            auth: false,
            cacheKey: cacheKey,
            ttl: ttl
        )
    }

    func categorySubjects(query: CategoryQuery, limit: Int = 24, offset: Int = 0, force: Bool = false) async throws -> Paged<Subject> {
        if query.sort == .date {
            return try await categoryDateSubjects(query: query, limit: limit, offset: offset, force: force)
        }
        guard let sort = query.sort.searchSort else {
            return try await categoryBrowserSubjects(query: query, limit: limit, offset: offset, force: force)
        }
        var filter = SubjectSearchFilter()
        filter.type = [query.type.rawValue]
        filter.tag = query.tag.map { [$0] }
        filter.metaTags = query.metaTags.isEmpty ? nil : Array(Set(query.metaTags)).sorted()
        filter.nsfw = query.includeNSFW ? nil : false
        if let year = query.year {
            filter.airDate = [">=\(year)-01-01", "<\(year + 1)-01-01"]
        }
        if query.sort == .rank { filter.rank = [">0"] }
        let body = SubjectSearchRequest(keyword: "", sort: sort, filter: filter)
        let keyEncoder = JSONEncoder()
        keyEncoder.outputFormatting = .sortedKeys
        let cacheKey = "categories-v2-\(String(decoding: try keyEncoder.encode(body), as: UTF8.self))-\(limit)-\(offset)"
        return try await post(
            "/v0/search/subjects",
            body: body,
            query: [.init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))],
            as: Paged<Subject>.self,
            auth: false,
            cacheKey: cacheKey,
            ttl: force ? 0 : 1_800
        )
    }

    private func categoryDateSubjects(query: CategoryQuery, limit: Int, offset: Int, force: Bool) async throws -> Paged<Subject> {
        // The website's date view requires a cookie login; public browsing provides the same date order.
        let page = try await browseSubjects(type: query.type.rawValue, sort: "date", year: query.year,
                                            limit: limit, offset: offset, force: force)
        let candidates = page.data.filter { query.matches($0) }
        var subjects = candidates
        if let tag = query.tag {
            subjects = try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
                for (index, subject) in candidates.enumerated() {
                    group.addTask { (index, try await self.categorySubject(subject, hasTag: tag, force: force)) }
                }
                var matches: Set<Int> = []
                for try await (index, matched) in group where matched { matches.insert(index) }
                return candidates.enumerated().filter { matches.contains($0.offset) }.map(\.element)
            }
        }
        return Paged(data: subjects, total: page.total, limit: limit, offset: offset, nextOffset: page.nextOffset)
    }

    private func categorySubject(_ subject: Subject, hasTag tag: String, force: Bool) async throws -> Bool {
        // Detail responses contain only the top tags; verify a custom tag against the search index.
        var filter = SubjectSearchFilter()
        filter.type = [subject.type]
        filter.tag = [tag]
        filter.nsfw = subject.nsfw
        let body = SubjectSearchRequest(keyword: subject.name, sort: "match", filter: filter)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key = String(decoding: try encoder.encode(body), as: UTF8.self)
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await post("/v0/search/subjects", body: body,
                                      query: [.init(name: "limit", value: "50"), .init(name: "offset", value: String(offset))],
                                      as: Paged<Subject>.self, auth: false,
                                      cacheKey: "category-tag-\(key)-\(offset)", ttl: force ? 0 : 1_800)
            if page.data.contains(where: { $0.id == subject.id }) { return true }
            if page.data.isEmpty || page.nextOffset >= page.total { return false }
            offset = page.nextOffset
        }
    }

    private func categoryBrowserSubjects(query: CategoryQuery, limit: Int, offset: Int, force: Bool) async throws -> Paged<Subject> {
        var ids: [Int] = []
        var total = offset
        while ids.count < limit {
            try Task.checkCancellation()
            let position = offset + ids.count
            let page = position / CategoryBrowserPage.size + 1
            var components = URLComponents(url: query.browserURL, resolvingAgainstBaseURL: false)!
            components.queryItems = (components.queryItems ?? []) + [.init(name: "page", value: String(page))]
            let url = components.url!
            let html = try await rawHTML(url, cacheKey: "category-browser-\(url.absoluteString)", ttl: force ? 0 : 1_800)
            let parsed = try CategoryBrowserPage.parse(html, page: page)
            total = parsed.total
            let slice = parsed.ids.dropFirst(position % CategoryBrowserPage.size).prefix(limit - ids.count)
            ids.append(contentsOf: slice)
            if slice.isEmpty || offset + ids.count >= total { break }
        }
        // Hydrate official IDs in their original order, including NSFW and public-tag metadata.
        let subjects = try await withThrowingTaskGroup(of: (Int, Subject).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try await self.subject(id)) }
            }
            var rows: [(Int, Subject)] = []
            for try await row in group { rows.append(row) }
            return rows.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return Paged(data: subjects, total: total, limit: limit, offset: offset)
    }

    func categoryFilters(type: SubjectType, force: Bool = false) async throws -> [CategoryFilterGroup] {
        let html = try await rawHTML(type.browserURL, cacheKey: "category-filters-\(type.rawValue)", ttl: force ? 0 : 86_400)
        return try CategoryCatalog.parse(html, type: type)
    }

    func searchCharacters(keyword: String, limit: Int = 24, offset: Int = 0) async throws -> Paged<Character> {
        try await post(
            "/v0/search/characters",
            body: KeywordBody(keyword: keyword),
            query: [
                .init(name: "limit", value: String(limit)),
                .init(name: "offset", value: String(offset))
            ],
            as: Paged<Character>.self,
            auth: false
        )
    }

    func searchPersons(keyword: String, limit: Int = 24, offset: Int = 0) async throws -> Paged<Person> {
        try await post(
            "/v0/search/persons",
            body: KeywordBody(keyword: keyword),
            query: [
                .init(name: "limit", value: String(limit)),
                .init(name: "offset", value: String(offset))
            ],
            as: Paged<Person>.self,
            auth: false
        )
    }

    func subjectCharacters(_ id: Int) async throws -> [Character] {
        try await get("/v0/subjects/\(id)/characters", as: [Character].self, cacheKey: "chars-\(id)", ttl: 86_400)
    }

    func subjectPersons(_ id: Int) async throws -> [Person] {
        try await get("/v0/subjects/\(id)/persons", as: [Person].self, cacheKey: "persons-\(id)", ttl: 86_400)
    }

    func subjectRelations(_ id: Int) async throws -> [RelatedSubject] {
        try await get("/v0/subjects/\(id)/subjects", as: [RelatedSubject].self, cacheKey: "relations-\(id)", ttl: 86_400)
    }

    // MARK: - Episodes

    func episodes(subjectID: Int, offset: Int = 0, limit: Int = 200) async throws -> Paged<Episode> {
        try await get(
            "/v0/episodes",
            query: [
                .init(name: "subject_id", value: String(subjectID)),
                .init(name: "limit", value: String(limit)),
                .init(name: "offset", value: String(offset))
            ],
            as: Paged<Episode>.self,
            cacheKey: "episodes-\(subjectID)-\(offset)",
            ttl: 86_400
        )
    }

    func allEpisodes(subjectID: Int) async throws -> [Episode] {
        var result: [Episode] = []
        var offset = 0
        let limit = 200
        for _ in 0..<10 {
            let page = try await episodes(subjectID: subjectID, offset: offset, limit: limit)
            result.append(contentsOf: page.data)
            if page.data.count < limit { break }
            offset += limit
        }
        return result.sorted { lhs, rhs in
            if lhs.type != rhs.type { return lhs.type < rhs.type }
            return lhs.sort < rhs.sort
        }
    }

    func episode(_ id: Int) async throws -> Episode {
        try await get("/v0/episodes/\(id)", as: Episode.self, cacheKey: "episode-\(id)", ttl: 86_400)
    }

    func episodeCollections(subjectID: Int) async throws -> Paged<EpisodeCollection> {
        try await get(
            "/v0/users/-/collections/\(subjectID)/episodes",
            query: [.init(name: "limit", value: "1000")],
            as: Paged<EpisodeCollection>.self,
            cacheKey: "epcol-\(subjectID)",
            ttl: 300,
            auth: true
        )
    }

    // MARK: - Calendar

    func calendar() async throws -> [CalendarDay] {
        try await get("/calendar", as: [CalendarDay].self, cacheKey: "calendar", ttl: 21_600)
    }

    // MARK: - Collection mutations

    func createOrUpdateCollection(subjectID: Int, patch: CollectionPatch) async throws {
        try await postNoContent("/v0/users/-/collections/\(subjectID)", body: patch)
    }

    func patchCollection(subjectID: Int, patch: CollectionPatch) async throws {
        try await self.patch("/v0/users/-/collections/\(subjectID)", body: patch)
    }

    func updateEpisode(episodeID: Int, type: Int) async throws {
        try await put("/v0/users/-/collections/-/episodes/\(episodeID)", body: EpisodeTypeBody(type: type))
    }

    func batchUpdateEpisodes(subjectID: Int, episodeIDs: [Int], type: Int) async throws {
        guard !episodeIDs.isEmpty else { return }
        try await patch("/v0/users/-/collections/\(subjectID)/episodes", body: EpisodeIDsBody(episodeID: episodeIDs, type: type))
    }

    // MARK: - Character / person

    func character(_ id: Int) async throws -> Character {
        try await get("/v0/characters/\(id)", as: Character.self, cacheKey: "character-\(id)", ttl: 86_400)
    }

    func person(_ id: Int) async throws -> PersonDetail {
        try await get("/v0/persons/\(id)", as: PersonDetail.self, cacheKey: "person-\(id)", ttl: 86_400)
    }

    func characterSubjects(_ id: Int) async throws -> [RelatedSubject] {
        try await get("/v0/characters/\(id)/subjects", as: [RelatedSubject].self, cacheKey: "character-subjects-\(id)", ttl: 86_400)
    }

    func personSubjects(_ id: Int) async throws -> [RelatedSubject] {
        try await get("/v0/persons/\(id)/subjects", as: [RelatedSubject].self, cacheKey: "person-subjects-\(id)", ttl: 86_400)
    }

    func collectCharacter(_ id: Int, collected: Bool) async throws {
        if collected {
            try await postNoContent("/v0/characters/\(id)/collect", body: EmptyBody())
        } else {
            try await delete("/v0/characters/\(id)/collect")
        }
    }

    func collectPerson(_ id: Int, collected: Bool) async throws {
        if collected {
            try await postNoContent("/v0/persons/\(id)/collect", body: EmptyBody())
        } else {
            try await delete("/v0/persons/\(id)/collect")
        }
    }

    // MARK: - Index & revisions

    func index(_ id: Int) async throws -> IndexDetail {
        try await get("/v0/indices/\(id)", as: IndexDetail.self, cacheKey: "index-\(id)", ttl: 3_600)
    }

    func indexSubjects(_ id: Int) async throws -> Paged<IndexSubject> {
        try await get("/v0/indices/\(id)/subjects", as: Paged<IndexSubject>.self, cacheKey: "index-subjects-\(id)", ttl: 3_600)
    }

    func subjectRevisions(_ id: Int) async throws -> Paged<Revision> {
        try await get(
            "/v0/revisions/subjects",
            query: [
                .init(name: "subject_id", value: String(id)),
                .init(name: "limit", value: "50")
            ],
            as: Paged<Revision>.self,
            cacheKey: "revisions-\(id)",
            ttl: 3_600
        )
    }

    // MARK: - Cache

    func clearCache() async {
        await cache.clear()
    }

    func cacheSize() async -> Int64 {
        await cache.size()
    }
}
