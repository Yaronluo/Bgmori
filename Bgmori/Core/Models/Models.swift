import Foundation

// MARK: - Enums

enum SubjectType: Int, CaseIterable, Identifiable, Sendable {
    case book = 1
    case anime = 2
    case music = 3
    case game = 4
    case real = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .book: "书籍"
        case .anime: "动画"
        case .music: "音乐"
        case .game: "游戏"
        case .real: "三次元"
        }
    }

    var icon: String {
        switch self {
        case .book: "book.closed"
        case .anime: "play.tv"
        case .music: "music.note"
        case .game: "gamecontroller"
        case .real: "film"
        }
    }

    static func title(for raw: Int) -> String {
        SubjectType(rawValue: raw)?.title ?? "其他"
    }
}

enum CollectionType: Int, CaseIterable, Identifiable, Sendable {
    case wish = 1
    case done = 2
    case doing = 3
    case onHold = 4
    case dropped = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .wish: "想看"
        case .done: "看过"
        case .doing: "在看"
        case .onHold: "搁置"
        case .dropped: "抛弃"
        }
    }

    var icon: String {
        switch self {
        case .wish: "bookmark"
        case .done: "checkmark.circle.fill"
        case .doing: "play.circle.fill"
        case .onHold: "pause.circle"
        case .dropped: "xmark.circle"
        }
    }
}

enum EpisodeCollectionType: Int, Sendable {
    case none = 0
    case wish = 1
    case done = 2
    case dropped = 3
}

// MARK: - Shared value types

struct Images: Decodable, Hashable, Sendable {
    let small: String?
    let grid: String?
    let large: String?
    let medium: String?
    let common: String?

    enum CodingKeys: String, CodingKey {
        case small, grid, large, medium, common
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        small = try? c.decode(String.self, forKey: .small)
        grid = try? c.decode(String.self, forKey: .grid)
        large = try? c.decode(String.self, forKey: .large)
        medium = try? c.decode(String.self, forKey: .medium)
        common = try? c.decode(String.self, forKey: .common)
    }

    init(small: String? = nil, grid: String? = nil, large: String? = nil, medium: String? = nil, common: String? = nil) {
        self.small = small
        self.grid = grid
        self.large = large
        self.medium = medium
        self.common = common
    }

    static func normalized(_ string: String?) -> URL? {
        guard var value = string, !value.isEmpty else { return nil }
        if value.hasPrefix("//") { value = "https:" + value }
        if value.hasPrefix("http://") { value = value.replacingOccurrences(of: "http://", with: "https://") }
        return URL(string: value)
    }

    // Poster cards need the large source on Retina displays; common/medium are thumbnails.
    var gridURL: URL? {
        [large, common, medium, small, grid].compactMap(Self.normalized).first
    }
    var thumbURL: URL? { Self.normalized(small ?? grid ?? common ?? medium ?? large) }
    var heroURL: URL? { Self.normalized(large ?? medium ?? common ?? small ?? grid) }
    var fullURL: URL? { Self.normalized(medium ?? large ?? common ?? small ?? grid) }
}

struct Tag: Decodable, Hashable, Sendable, Identifiable {
    let name: String
    let count: Int
    let totalCount: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, count, totalCount = "total_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        count = (try? c.decode(Int.self, forKey: .count)) ?? 0
        totalCount = (try? c.decode(Int.self, forKey: .totalCount)) ?? count
    }
}

struct Rating: Decodable, Hashable, Sendable {
    let rank: Int?
    let total: Int
    let count: [String: Int]
    let score: Double

    enum CodingKeys: String, CodingKey { case rank, total, count, score }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try? c.decode(Int.self, forKey: .rank)
        total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        count = (try? c.decode([String: Int].self, forKey: .count)) ?? [:]
        score = (try? c.decode(Double.self, forKey: .score)) ?? 0
    }

    var distribution: [(score: Int, count: Int)] {
        (1...10).map { value in
            (value, count[String(value)] ?? 0)
        }
    }

    var scoreText: String { String(format: "%.1f", score) }
}

struct CollectionStats: Decodable, Hashable, Sendable {
    let wish: Int
    let collect: Int
    let doing: Int
    let onHold: Int
    let dropped: Int

    enum CodingKeys: String, CodingKey {
        case wish, collect, doing, dropped
        case onHold = "on_hold"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wish = (try? c.decode(Int.self, forKey: .wish)) ?? 0
        collect = (try? c.decode(Int.self, forKey: .collect)) ?? 0
        doing = (try? c.decode(Int.self, forKey: .doing)) ?? 0
        onHold = (try? c.decode(Int.self, forKey: .onHold)) ?? 0
        dropped = (try? c.decode(Int.self, forKey: .dropped)) ?? 0
    }
}

struct InfoboxEntry: Decodable, Hashable, Sendable {
    let v: String
}

enum InfoboxValue: Decodable, Hashable, Sendable {
    case text(String)
    case list([String])

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            self = .text(value)
            return
        }
        if let entries = try? decoder.singleValueContainer().decode([InfoboxEntry].self) {
            self = .list(entries.map(\.v))
            return
        }
        self = .text("")
    }

    var display: String {
        switch self {
        case .text(let value): value
        case .list(let values): values.joined(separator: " / ")
        }
    }
}

struct InfoboxItem: Decodable, Hashable, Sendable, Identifiable {
    let key: String
    let value: InfoboxValue

    var id: String { key }
}

struct ErrorDetail: Decodable, Sendable {
    let title: String?
    let description: String?
    let details: String?
}

// MARK: - Subject

struct Subject: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let type: Int
    let name: String
    let nameCn: String
    let summary: String
    let date: String?
    let platform: String?
    let images: Images?
    let infobox: [InfoboxItem]
    let rating: Rating?
    let totalEpisodes: Int
    let eps: Int
    let volumes: Int
    let collection: CollectionStats?
    let tags: [Tag]
    let nsfw: Bool
    let locked: Bool
    let series: Bool
    let metaTags: [String]

    enum CodingKeys: String, CodingKey {
        case id, type, name, summary, date, platform, images, infobox, rating, eps, volumes, collection, tags, nsfw, locked, series
        case nameCn = "name_cn"
        case totalEpisodes = "total_episodes"
        case metaTags = "meta_tags"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        nameCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        date = try? c.decode(String.self, forKey: .date)
        platform = try? c.decode(String.self, forKey: .platform)
        images = try? c.decode(Images.self, forKey: .images)
        infobox = (try? c.decode([InfoboxItem].self, forKey: .infobox)) ?? []
        rating = try? c.decode(Rating.self, forKey: .rating)
        totalEpisodes = (try? c.decode(Int.self, forKey: .totalEpisodes)) ?? 0
        eps = (try? c.decode(Int.self, forKey: .eps)) ?? 0
        volumes = (try? c.decode(Int.self, forKey: .volumes)) ?? 0
        collection = try? c.decode(CollectionStats.self, forKey: .collection)
        tags = (try? c.decode([Tag].self, forKey: .tags)) ?? []
        nsfw = (try? c.decode(Bool.self, forKey: .nsfw)) ?? false
        locked = (try? c.decode(Bool.self, forKey: .locked)) ?? false
        series = (try? c.decode(Bool.self, forKey: .series)) ?? false
        metaTags = (try? c.decode([String].self, forKey: .metaTags)) ?? []
    }

    static func == (lhs: Subject, rhs: Subject) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayTitle: String { nameCn.isEmpty ? name : nameCn }
    var originalTitle: String { nameCn.isEmpty ? "" : name }
    var coverURL: URL? { images?.gridURL }
    var heroURL: URL? { images?.heroURL }
    var typeName: String { SubjectType.title(for: type) }
    var episodeCountText: String {
        let count = totalEpisodes > 0 ? totalEpisodes : eps
        return count > 0 ? "\(count) 话" : (platform ?? typeName)
    }
    var ratingText: String { rating?.scoreText ?? "—" }
    var rankText: String {
        guard let rank = rating?.rank else { return "—" }
        return "#\(rank)"
    }
    var url: URL? { URL(string: "https://bgm.tv/subject/\(id)") }
}

struct SubjectSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let type: Int
    let name: String
    let nameCn: String
    let date: String?
    let images: Images?
    let score: Double?
    let rank: Int?
    let eps: Int
    let volumes: Int
    let collectionTotal: Int
    let tags: [Tag]

    enum CodingKeys: String, CodingKey {
        case id, type, name, date, images, score, rank, eps, volumes, tags
        case nameCn = "name_cn"
        case collectionTotal = "collection_total"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        nameCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        date = try? c.decode(String.self, forKey: .date)
        images = try? c.decode(Images.self, forKey: .images)
        score = try? c.decode(Double.self, forKey: .score)
        rank = try? c.decode(Int.self, forKey: .rank)
        eps = (try? c.decode(Int.self, forKey: .eps)) ?? 0
        volumes = (try? c.decode(Int.self, forKey: .volumes)) ?? 0
        collectionTotal = (try? c.decode(Int.self, forKey: .collectionTotal)) ?? 0
        tags = (try? c.decode([Tag].self, forKey: .tags)) ?? []
    }

    init(subject: Subject) {
        self.id = subject.id
        self.type = subject.type
        self.name = subject.name
        self.nameCn = subject.nameCn
        self.date = subject.date
        self.images = subject.images
        self.score = subject.rating?.score
        self.rank = subject.rating?.rank
        self.eps = subject.eps
        self.volumes = subject.volumes
        self.collectionTotal = subject.collection?.collect ?? 0
        self.tags = subject.tags
    }

    init(id: Int, type: Int, name: String, nameCn: String, date: String?, images: Images?, score: Double?, rank: Int?, eps: Int, volumes: Int, collectionTotal: Int, tags: [Tag]) {
        self.id = id
        self.type = type
        self.name = name
        self.nameCn = nameCn
        self.date = date
        self.images = images
        self.score = score
        self.rank = rank
        self.eps = eps
        self.volumes = volumes
        self.collectionTotal = collectionTotal
        self.tags = tags
    }

    static func == (lhs: SubjectSummary, rhs: SubjectSummary) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayTitle: String { nameCn.isEmpty ? name : nameCn }
    var coverURL: URL? { images?.gridURL }
    var ratingText: String { score.map { String(format: "%.1f", $0) } ?? "—" }
}

// MARK: - Episode

struct Episode: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let type: Int
    let name: String
    let nameCn: String
    let sort: Double
    let ep: Double?
    let airdate: String?
    let comment: Int
    let duration: String?
    let desc: String?
    let disc: Int
    let subjectId: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, name, sort, ep, airdate, comment, duration, desc, disc
        case nameCn = "name_cn"
        case subjectId = "subject_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        nameCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        sort = (try? c.decode(Double.self, forKey: .sort)) ?? 0
        ep = try? c.decode(Double.self, forKey: .ep)
        airdate = try? c.decode(String.self, forKey: .airdate)
        comment = (try? c.decode(Int.self, forKey: .comment)) ?? 0
        duration = try? c.decode(String.self, forKey: .duration)
        desc = try? c.decode(String.self, forKey: .desc)
        disc = (try? c.decode(Int.self, forKey: .disc)) ?? 0
        subjectId = try? c.decode(Int.self, forKey: .subjectId)
    }

    static func == (lhs: Episode, rhs: Episode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayTitle: String { nameCn.isEmpty ? name : nameCn }
    var originalTitle: String { nameCn.isEmpty ? "" : name }
    var numberText: String {
        if let ep, ep > 0 { return "第 \(Int(ep)) 话" }
        if sort > 0 { return String(format: "%.1f", sort) }
        return "SP"
    }
    var typeName: String {
        switch type {
        case 0: "本篇"
        case 1: "SP"
        case 2: "OP"
        case 3: "ED"
        default: "其他"
        }
    }
}

struct EpisodeCollection: Decodable, Sendable {
    let episode: Episode?
    let type: Int
    let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case episode, type
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        episode = try? c.decode(Episode.self, forKey: .episode)
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        updatedAt = (try? c.decode(Int.self, forKey: .updatedAt)) ?? 0
    }
}

// MARK: - User & collection

struct User: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let username: String
    let nickname: String
    let avatar: Images?
    let sign: String
    let userGroup: Int

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, avatar, sign
        case userGroup = "user_group"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        nickname = (try? c.decode(String.self, forKey: .nickname)) ?? ""
        avatar = try? c.decode(Images.self, forKey: .avatar)
        sign = (try? c.decode(String.self, forKey: .sign)) ?? ""
        userGroup = (try? c.decode(Int.self, forKey: .userGroup)) ?? 0
    }

    static func == (lhs: User, rhs: User) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayName: String { nickname.isEmpty ? username : nickname }
    var avatarURL: URL? { avatar?.heroURL }
    var profileURL: URL? { URL(string: "https://bgm.tv/user/\(username)") }
}

struct UserSubjectCollection: Decodable, Identifiable, Sendable {
    let subjectId: Int
    let subjectType: Int
    let rate: Int
    let type: Int
    let comment: String?
    let tags: [String]
    let epStatus: Int
    let volStatus: Int
    let updatedAt: String?
    let isPrivate: Bool
    let subject: SubjectSummary?

    var id: Int { subjectId }

    enum CodingKeys: String, CodingKey {
        case subjectId = "subject_id"
        case subjectType = "subject_type"
        case rate, type, comment, tags, subject
        case epStatus = "ep_status"
        case volStatus = "vol_status"
        case updatedAt = "updated_at"
        case isPrivate = "private"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subjectId = (try? c.decode(Int.self, forKey: .subjectId)) ?? 0
        subjectType = (try? c.decode(Int.self, forKey: .subjectType)) ?? 0
        rate = (try? c.decode(Int.self, forKey: .rate)) ?? 0
        type = (try? c.decode(Int.self, forKey: .type)) ?? 1
        comment = try? c.decode(String.self, forKey: .comment)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        epStatus = (try? c.decode(Int.self, forKey: .epStatus)) ?? 0
        volStatus = (try? c.decode(Int.self, forKey: .volStatus)) ?? 0
        updatedAt = try? c.decode(String.self, forKey: .updatedAt)
        isPrivate = (try? c.decode(Bool.self, forKey: .isPrivate)) ?? false
        subject = try? c.decode(SubjectSummary.self, forKey: .subject)
    }

    init(subjectId: Int, subjectType: Int, rate: Int, type: Int, comment: String?, tags: [String], epStatus: Int, volStatus: Int, updatedAt: String?, isPrivate: Bool, subject: SubjectSummary?) {
        self.subjectId = subjectId
        self.subjectType = subjectType
        self.rate = rate
        self.type = type
        self.comment = comment
        self.tags = tags
        self.epStatus = epStatus
        self.volStatus = volStatus
        self.updatedAt = updatedAt
        self.isPrivate = isPrivate
        self.subject = subject
    }

    func applying(_ patch: CollectionPatch) -> UserSubjectCollection {
        UserSubjectCollection(
            subjectId: subjectId,
            subjectType: subjectType,
            rate: patch.rate ?? rate,
            type: patch.type ?? type,
            comment: patch.comment ?? comment,
            tags: patch.tags ?? tags,
            epStatus: patch.epStatus ?? epStatus,
            volStatus: patch.volStatus ?? volStatus,
            updatedAt: updatedAt,
            isPrivate: patch.isPrivate ?? isPrivate,
            subject: subject
        )
    }

    var collectionType: CollectionType { CollectionType(rawValue: type) ?? .wish }
    var title: String { subject?.displayTitle ?? "条目 #\(subjectId)" }
    var coverURL: URL? { subject?.coverURL }
    var reviewText: String? {
        guard let text = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    var progressText: String {
        let total = subject?.eps ?? 0
        if total > 0 { return "\(epStatus)/\(total)" }
        return epStatus > 0 ? "\(epStatus)" : ""
    }
    var progressFraction: Double {
        guard let total = subject?.eps, total > 0 else { return 0 }
        return min(1, max(0, Double(epStatus) / Double(total)))
    }
}

struct CollectionPatch: Encodable, Sendable {
    var type: Int?
    var rate: Int?
    var epStatus: Int?
    var volStatus: Int?
    var comment: String?
    var isPrivate: Bool?
    var tags: [String]?

    init(type: Int? = nil, rate: Int? = nil, epStatus: Int? = nil, volStatus: Int? = nil, comment: String? = nil, isPrivate: Bool? = nil, tags: [String]? = nil) {
        self.type = type
        self.rate = rate
        self.epStatus = epStatus
        self.volStatus = volStatus
        self.comment = comment
        self.isPrivate = isPrivate
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case type, rate, comment, tags
        case epStatus = "ep_status"
        case volStatus = "vol_status"
        case isPrivate = "private"
    }
}

// MARK: - Characters & people

struct Person: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let images: Images?
    let relation: String?
    let career: [String]
    let type: Int
    let eps: String?

    enum CodingKeys: String, CodingKey { case id, name, images, relation, career, type, eps }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        images = try? c.decode(Images.self, forKey: .images)
        relation = try? c.decode(String.self, forKey: .relation)
        career = (try? c.decode([String].self, forKey: .career)) ?? []
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        eps = try? c.decode(String.self, forKey: .eps)
    }

    static func == (lhs: Person, rhs: Person) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var coverURL: URL? { images?.thumbURL }
}

struct Character: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let images: Images?
    let summary: String
    let relation: String?
    let actors: [Person]
    let infobox: [InfoboxItem]

    enum CodingKeys: String, CodingKey { case id, name, images, summary, relation, actors, infobox }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        images = try? c.decode(Images.self, forKey: .images)
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        relation = try? c.decode(String.self, forKey: .relation)
        actors = (try? c.decode([Person].self, forKey: .actors)) ?? []
        infobox = (try? c.decode([InfoboxItem].self, forKey: .infobox)) ?? []
    }

    static func == (lhs: Character, rhs: Character) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var coverURL: URL? { images?.thumbURL }
}

struct PersonDetail: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let images: Images?
    let summary: String?
    let infobox: [InfoboxItem]
    let career: [String]
    let type: Int

    enum CodingKeys: String, CodingKey { case id, name, images, summary, infobox, career, type }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        images = try? c.decode(Images.self, forKey: .images)
        summary = try? c.decode(String.self, forKey: .summary)
        infobox = (try? c.decode([InfoboxItem].self, forKey: .infobox)) ?? []
        career = (try? c.decode([String].self, forKey: .career)) ?? []
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
    }

    var coverURL: URL? { images?.heroURL }
}

struct RelatedSubject: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let nameCn: String
    let images: Images?
    /// `/v0/characters/{id}/subjects` and `/v0/persons/{id}/subjects` return a
    /// single cover URL instead of the `images` object used by subject relations.
    let image: String?
    let relation: String
    let type: Int

    enum CodingKeys: String, CodingKey {
        case id, name, images, image, relation, staff, type
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        nameCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        images = try? c.decode(Images.self, forKey: .images)
        image = try? c.decode(String.self, forKey: .image)
        // Character/person credits call the relation "staff"; subject relations use "relation".
        relation = (try? c.decode(String.self, forKey: .relation))
            ?? (try? c.decode(String.self, forKey: .staff))
            ?? ""
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
    }

    static func == (lhs: RelatedSubject, rhs: RelatedSubject) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayTitle: String { nameCn.isEmpty ? name : nameCn }
    var coverURL: URL? { images?.gridURL ?? Images.normalized(image) }
}

// MARK: - Calendar

struct Weekday: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let en: String
    let cn: String
    let ja: String

    enum CodingKeys: String, CodingKey { case id, en, cn, ja }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        en = (try? c.decode(String.self, forKey: .en)) ?? ""
        cn = (try? c.decode(String.self, forKey: .cn)) ?? ""
        ja = (try? c.decode(String.self, forKey: .ja)) ?? ""
    }

    var shortName: String {
        let names = ["一", "二", "三", "四", "五", "六", "日"]
        let index = max(0, min(6, id - 1))
        return "周" + names[index]
    }
}

struct CalendarDay: Decodable, Identifiable, Sendable {
    let weekday: Weekday
    let items: [LegacySubject]

    var id: Int { weekday.id }
}

struct LegacySubject: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let type: Int
    let name: String
    let nameCn: String
    let images: Images?
    let airDate: String?
    let airWeekday: Int
    let rating: Rating?

    enum CodingKeys: String, CodingKey {
        case id, type, name, images, rating
        case nameCn = "name_cn"
        case airDate = "air_date"
        case airWeekday = "air_weekday"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        nameCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        images = try? c.decode(Images.self, forKey: .images)
        airDate = try? c.decode(String.self, forKey: .airDate)
        airWeekday = (try? c.decode(Int.self, forKey: .airWeekday)) ?? 0
        rating = try? c.decode(Rating.self, forKey: .rating)
    }

    static func == (lhs: LegacySubject, rhs: LegacySubject) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayTitle: String { nameCn.isEmpty ? name : nameCn }
    var coverURL: URL? { images?.gridURL }
}

// MARK: - Paging & search

struct Paged<T: Decodable & Sendable>: Decodable, Sendable {
    let data: [T]
    let total: Int
    let limit: Int
    let offset: Int
    // Locally filtered pages still advance past every row returned by the source.
    let nextOffset: Int

    enum CodingKeys: String, CodingKey { case data, total, limit, offset }

    init(data: [T], total: Int, limit: Int, offset: Int, nextOffset: Int? = nil) {
        self.data = data
        self.total = total
        self.limit = limit
        self.offset = offset
        self.nextOffset = nextOffset ?? offset + data.count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = (try? c.decode([T].self, forKey: .data)) ?? []
        total = (try? c.decode(Int.self, forKey: .total)) ?? data.count
        limit = (try? c.decode(Int.self, forKey: .limit)) ?? data.count
        offset = (try? c.decode(Int.self, forKey: .offset)) ?? 0
        nextOffset = offset + data.count
    }
}

struct SubjectSearchFilter: Encodable, Sendable {
    var type: [Int]?
    var tag: [String]?
    var metaTags: [String]?
    var airDate: [String]?
    var rating: [String]?
    var ratingCount: [String]?
    var rank: [String]?
    var nsfw: Bool?

    enum CodingKeys: String, CodingKey {
        case type, tag, rating, rank, nsfw
        case metaTags = "meta_tags"
        case airDate = "air_date"
        case ratingCount = "rating_count"
    }
}

struct SubjectSearchRequest: Encodable, Sendable {
    var keyword: String
    var sort: String
    var filter: SubjectSearchFilter?
}

// MARK: - Index & revisions

struct IndexDetail: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let desc: String?
    let images: Images?
    let subjects: [IndexSubject]?

    enum CodingKeys: String, CodingKey { case id, title, desc, images, subjects }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        desc = try? c.decode(String.self, forKey: .desc)
        images = try? c.decode(Images.self, forKey: .images)
        subjects = try? c.decode([IndexSubject].self, forKey: .subjects)
    }
}

struct IndexSubject: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let nameCn: String
    let images: Images?
    let type: Int
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case id, name, images, type, comment
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        nameCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        images = try? c.decode(Images.self, forKey: .images)
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        comment = try? c.decode(String.self, forKey: .comment)
    }

    static func == (lhs: IndexSubject, rhs: IndexSubject) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayTitle: String { nameCn.isEmpty ? name : nameCn }
    var coverURL: URL? { images?.gridURL }
}

struct Revision: Decodable, Identifiable, Sendable {
    let id: Int
    let summary: String?
    let creator: User?
    let createdAt: String?
    let type: Int?

    enum CodingKeys: String, CodingKey {
        case id, summary, creator, type
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        summary = try? c.decode(String.self, forKey: .summary)
        creator = try? c.decode(User.self, forKey: .creator)
        createdAt = try? c.decode(String.self, forKey: .createdAt)
        type = try? c.decode(Int.self, forKey: .type)
    }
}

// MARK: - Auth

struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let refreshToken: String?
    let userId: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case userId = "user_id"
    }
}

struct OAuthErrorResponse: Decodable, Sendable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Helpers

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}
