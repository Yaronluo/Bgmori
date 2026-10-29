import Foundation

enum CategorySort: String, Codable, CaseIterable, Identifiable, Sendable {
    case rank
    case heat = "trends"
    case collects
    case date
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rank: "排名"
        case .heat: "热度"
        case .collects: "收藏"
        case .date: "日期"
        case .title: "名称"
        }
    }

    // The public search API calls collection count "heat"; website trends are distinct.
    var searchSort: String? {
        switch self {
        case .rank: "rank"
        case .collects: "heat"
        case .heat, .date, .title: nil
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

    var browserURL: URL {
        var url = type.browserURL
        if let tag { url.appendPathComponent(tag) }
        else if let tag = metaTags.first(where: { !$0.hasPrefix("-") }) { url.appendPathComponent(tag) }
        if let year {
            url.appendPathComponent("airtime")
            url.appendPathComponent(String(year))
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "sort", value: sort.rawValue)]
        return components.url!
    }

    /// Stable, source-independent key for the complete query. Account data is
    /// not part of this key because category results are public.
    var cacheKey: String {
        let fields = [String(type.rawValue), sort.rawValue, year.map(String.init) ?? "-",
                      tag ?? "-", includeNSFW ? "1" : "0",
                      metaTags.sorted().joined(separator: "\u{1f}"), platform ?? "-"]
        return fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }

    func matches(_ subject: Subject) -> Bool {
        guard subject.type == type.rawValue, includeNSFW || !subject.nsfw,
              platform == nil || subject.platform == platform else { return false }
        guard sort.searchSort == nil else { return true } // Search already applies these filters.
        if let year, subject.date?.hasPrefix("\(year)-") != true { return false }
        let tags = Set(subject.metaTags.map { $0.lowercased() })
        return metaTags.allSatisfy { tag in
            tag.hasPrefix("-") ? !tags.contains(String(tag.dropFirst()).lowercased()) : tags.contains(tag.lowercased())
        }
    }
}

enum CategoryBrowserPage {
    static let size = 24

    static func parse(_ html: String, page: Int) throws -> (ids: [Int], total: Int) {
        guard let list = HTMLSupport.elementContents(id: "browserItemList", in: html) else {
            throw APIError.decoding("官网排序解析失败，请重试或在浏览器中查看。")
        }
        let rows = HTMLSupport.all(#"<li\b[^>]*\bid=["']item_(\d+)["']"#, in: list)
        let ids = rows.compactMap(Int.init)
        guard ids.count == HTMLSupport.matches(#"<li\b"#, in: list).count, Set(ids).count == ids.count,
              !ids.isEmpty || ["没有找到", "暂无条目", "没有相关", "无结果"].contains(where: list.contains) else {
            throw APIError.decoding("官网排序解析失败，请重试或在浏览器中查看。")
        }
        let links = HTMLSupport.all(#"href=["'][^"']*[?&](?:amp;)?page=(\d+)[^"']*["']"#, in: html).compactMap(Int.init)
        let lastPage = max(page, links.max() ?? page)
        let total = lastPage == page ? (page - 1) * size + ids.count : lastPage * size
        return (ids, total)
    }
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
                guard let rawURL = HTMLSupport.absoluteURL(HTMLSupport.decodeEntities(link[1])) else { return nil }
                let url = MirrorRouting.shared.canonicalURL(for: rawURL)
                guard url.host == "bgm.tv" else { return nil }
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
