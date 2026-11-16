import Foundation

/// One page of the website's 提醒 feed, read from `next.bgm.tv/p1/notify`.
/// It authenticates with the account's existing token, so it never touches the
/// stored website cookie.
struct NoticePage: Decodable, Sendable {
    let data: [Notice]
    /// Total unread notices for the account, not the size of this page.
    let total: Int

    private enum CodingKeys: String, CodingKey { case data, total }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([Notice].self, forKey: .data) ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
    }
}

struct Notice: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let type: Int
    let sender: NoticeSender
    /// The thread title the notice belongs to; empty for friend requests.
    let title: String
    let mainID: Int
    let relatedID: Int
    let createdAt: Date
    var unread: Bool

    private enum CodingKeys: String, CodingKey {
        case id, type, sender, title, unread, mainID, relatedID, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decodeIfPresent(Int.self, forKey: .type) ?? 0
        sender = try container.decode(NoticeSender.self, forKey: .sender)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        mainID = try container.decodeIfPresent(Int.self, forKey: .mainID) ?? 0
        relatedID = try container.decodeIfPresent(Int.self, forKey: .relatedID) ?? 0
        unread = try container.decodeIfPresent(Bool.self, forKey: .unread) ?? false
        let stamp = try container.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        // P1 documents milliseconds; accept seconds too so a unit change cannot
        // push every row into 1970.
        createdAt = Date(timeIntervalSince1970: stamp > 10_000_000_000 ? stamp / 1000 : stamp)
    }
}

struct NoticeSender: Decodable, Hashable, Sendable {
    let id: Int
    let username: String
    let nickname: String
    let avatar: NoticeAvatar?

    var displayName: String { nickname.isEmpty ? username : nickname }
    var avatarURL: URL? { avatar?.url }
}

struct NoticeAvatar: Decodable, Hashable, Sendable {
    let small: String?
    let medium: String?
    let large: String?

    private enum CodingKeys: String, CodingKey { case small, medium, large }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let value = try? single.decode(String.self) {
            small = value
            medium = value
            large = value
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        small = try container.decodeIfPresent(String.self, forKey: .small)
        medium = try container.decodeIfPresent(String.self, forKey: .medium)
        large = try container.decodeIfPresent(String.self, forKey: .large)
    }

    var url: URL? { Images.normalized(large ?? medium ?? small) }
}

/// Where a notice happened. Used to decide between an in-app page and the
/// website fallback.
enum NoticePlace: Hashable, Sendable {
    case groupTopic(Int)
    case episode(Int)
    case blog(Int)
    case index(Int)
    case character(Int)
    case person(Int)
    case user(String)
    /// The app has no matching page (subject discussion, timeline, doujin
    /// sections, wiki patches); the row stays readable but is not tappable.
    case webOnly
}

extension Notice {
    var actionText: String { description.text }
    var place: NoticePlace { description.place }

    /// Mirrors the server's `lib/notify.ts` table: the type decides both the
    /// wording and the destination.
    private var description: (text: String, place: NoticePlace) {
        switch type {
        case 1, 2: ("在小组话题中回复了你", .groupTopic(mainID))
        case 3, 4: ("在条目讨论中回复了你", .webOnly)
        case 5, 6: ("在角色讨论中回复了你", .character(mainID))
        case 7, 8: ("在日志中回复了你", .blog(mainID))
        case 9, 10: ("在章节讨论中回复了你", .episode(mainID))
        case 11, 12: ("在目录中回复了你", .index(mainID))
        case 13: ("在人物讨论中回复了你", .person(mainID))
        case 14: ("请求加你为好友", .user(sender.username))
        case 15: ("通过了你的好友请求", .user(sender.username))
        case 17, 18: ("在同人小组中回复了你", .webOnly)
        case 19: ("在同人作品中回复了你", .webOnly)
        case 20, 21: ("在同人活动中回复了你", .webOnly)
        case 22: ("在时光机中回复了你", .webOnly)
        case 23: ("在小组话题中提到了你", .groupTopic(mainID))
        case 24: ("在条目讨论中提到了你", .webOnly)
        case 25: ("在角色讨论中提到了你", .character(mainID))
        case 26: ("在人物讨论中提到了你", .person(mainID))
        case 27: ("在目录中提到了你", .index(mainID))
        case 28: ("在时光机中提到了你", .webOnly)
        case 29: ("在日志中提到了你", .blog(mainID))
        case 30: ("在章节讨论中提到了你", .episode(mainID))
        case 31, 32, 33, 34: ("在同人社区中提到了你", .webOnly)
        case 35, 36, 41, 42: ("通过了你的编辑", .webOnly)
        case 37, 38, 43, 44: ("拒绝了你提交的编辑", .webOnly)
        case 39, 40, 45, 46: ("你提交的编辑已过期", .webOnly)
        case 47, 48, 49, 50: ("在编辑讨论中回复了你", .webOnly)
        default: ("有新提醒", .webOnly)
        }
    }
}
