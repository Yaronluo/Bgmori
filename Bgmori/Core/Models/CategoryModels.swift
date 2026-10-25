import Foundation

enum CategorySort: String, CaseIterable, Identifiable, Sendable {
    case heat
    case rank
    case score

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heat: "热门优先"
        case .rank: "口碑排行"
        case .score: "评分优先"
        }
    }
}

struct CategoryQuery: Hashable, Sendable {
    var type: SubjectType = .anime
    var sort: CategorySort = .heat
    var year: Int?
    var tag: String?
    var includeNSFW = false
}

extension SubjectType {
    static let browsingTypes: [SubjectType] = [.anime, .book, .music, .game, .real]

    var browsingTags: [String] {
        switch self {
        case .anime: ["科幻", "奇幻", "恋爱", "日常", "悬疑", "战斗", "治愈", "搞笑"]
        case .book: ["漫画", "小说", "轻小说", "绘本", "画集"]
        case .music: ["原声集", "主题歌", "角色歌", "同人", "古典"]
        case .game: ["RPG", "冒险", "视觉小说", "动作", "策略", "独立游戏"]
        case .real: ["日剧", "美剧", "电影", "特摄", "纪录片", "综艺"]
        }
    }
}
