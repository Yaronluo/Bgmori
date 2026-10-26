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
    var metaTags: [String] = []
    var platform: String?
}

struct CategoryFilterOption: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let metaTags: [String]
    var platform: String?
}

struct CategoryFilterGroup: Hashable, Sendable, Identifiable {
    let title: String
    let options: [CategoryFilterOption]
    var id: String { title }
}

enum CategoryCatalog {
    static func parse(_ html: String, type: SubjectType) throws -> [CategoryFilterGroup] {
        guard let sidebar = HTMLSupport.elementContents(id: "columnSubjectBrowserB", in: html) else {
            throw APIError.decoding("官网分类解析失败，请重试或在浏览器中查看。")
        }
        let sections = HTMLSupport.matches(#"<h2\b[^>]*>(.*?)</h2>\s*<ul\b[^>]*>(.*?)</ul>"#, in: sidebar)
        var groups: [CategoryFilterGroup] = []
        for section in sections {
            let title = HTMLSupport.text(section[1])
            guard !["时间", "拼音筛选", "标签"].contains(title), !title.isEmpty else { continue }
            var seen: Set<String> = []
            let options = HTMLSupport.matches(#"<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#, in: section[2]).compactMap { link -> CategoryFilterOption? in
                guard let url = HTMLSupport.absoluteURL(HTMLSupport.decodeEntities(link[1])), url.host == "bgm.tv" else { return nil }
                let parts = url.path.split(separator: "/").map(String.init)
                guard parts.count == 3, parts[0] == type.browserSection, parts[1] == "browser" else { return nil }
                let value = parts[2]
                let label = HTMLSupport.text(link[2])
                guard !label.isEmpty, seen.insert(value).inserted else { return nil }
                var tags = [title == "分类" || title == "系列" ? label : value]
                if title == "分类", type == .real {
                    switch value {
                    case "jp": tags = ["电视剧", "日本"]
                    case "en": tags = ["电视剧", "欧美"]
                    case "cn": tags = ["电视剧", "华语"]
                    default: break
                    }
                }
                var platform: String?
                if title == "分类", value == "misc" {
                    // "Other" has no public tag: exclude named formats and verify the API platform.
                    switch type {
                    case .anime: tags = ["-TV", "-WEB", "-OVA", "-剧场版", "-动态漫画"]
                    case .book: tags = ["-漫画", "-小说", "-画集", "-绘本", "-公式书", "-写真"]
                    case .game: tags = ["-游戏", "-扩展包", "-软件", "-桌游"]
                    case .real: tags = ["-电视剧", "-电影", "-演出", "-综艺"]
                    case .music: tags = []
                    }
                    platform = label
                }
                return CategoryFilterOption(id: value, title: label, metaTags: tags, platform: platform)
            }
            if !options.isEmpty, !groups.contains(where: { $0.id == title }) {
                groups.append(CategoryFilterGroup(title: title, options: options))
            }
        }
        guard groups.contains(where: { ["类型", "题材"].contains($0.title) && $0.options.count > 1 }) else {
            throw APIError.decoding("官网分类解析失败，请重试或在浏览器中查看。")
        }
        return groups
    }
}

extension SubjectType {
    static let browsingTypes: [SubjectType] = [.anime, .book, .music, .game, .real]

    var browserSection: String {
        switch self {
        case .anime: "anime"
        case .book: "book"
        case .music: "music"
        case .game: "game"
        case .real: "real"
        }
    }

    var browserURL: URL { URL(string: "https://bgm.tv/\(browserSection)/browser")! }
}
