import Foundation

actor SocialService {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func subjectComments(subjectID: Int, page: Int = 1) async throws -> [SocialComment] {
        let url = URL(string: "https://bgm.tv/subject/\(subjectID)/comments?page=\(page)")!
        let html = try await api.rawHTML(url, cacheKey: "social-comments-\(subjectID)-\(page)", ttl: 3_600)
        return parseSubjectComments(html, subjectID: subjectID, page: page)
    }

    func episodeComments(episodeID: Int) async throws -> [SocialComment] {
        let url = URL(string: "https://bgm.tv/ep/\(episodeID)")!
        let html = try await api.rawHTML(url, cacheKey: "social-episode-\(episodeID)", ttl: 3_600)
        return parseEpisodeComments(html, episodeID: episodeID)
    }

    func groupHome() async throws -> GroupHome {
        let url = URL(string: "https://bgm.tv/group")!
        let html = try await api.rawHTML(url, cacheKey: "social-groups", ttl: 1_800)
        return parseGroupHome(html)
    }

    func groupDetail(name: String) async throws -> GroupDetail {
        let url = URL(string: "https://bgm.tv/group/\(name)")!
        let html = try await api.rawHTML(url, cacheKey: "social-group-\(name)", ttl: 1_800)
        return parseGroupDetail(html, name: name)
    }

    func topic(id: Int) async throws -> TopicDetail {
        let url = URL(string: "https://bgm.tv/group/topic/\(id)")!
        let html = try await api.rawHTML(url, cacheKey: "social-topic-\(id)", ttl: 1_800)
        return parseTopic(html, id: id)
    }

    func blogList() async throws -> [BlogSummary] {
        let url = URL(string: "https://bgm.tv/blog")!
        let html = try await api.rawHTML(url, cacheKey: "social-blogs", ttl: 1_800)
        return parseBlogList(html)
    }

    func blogDetail(id: Int) async throws -> BlogDetail {
        let url = URL(string: "https://bgm.tv/blog/\(id)")!
        let html = try await api.rawHTML(url, cacheKey: "social-blog-\(id)", ttl: 3_600)
        return try parseBlogDetail(html, id: id)
    }

    func timeline(username: String) async throws -> [TimelineItem] {
        let url = URL(string: "https://bgm.tv/user/\(username)/timeline")!
        let html = try await api.rawHTML(url, cacheKey: "social-timeline-\(username)", ttl: 600)
        return parseTimeline(html)
    }

    // MARK: - Subject comments

    private func parseSubjectComments(_ html: String, subjectID: Int, page: Int) -> [SocialComment] {
        let blocks = HTMLSupport.blocks(html, separator: #"<div class="item clearit""#)
        return blocks.enumerated().compactMap { index, block in
            let username = HTMLSupport.first(#"href="/user/([^"]+)" class="l""#, in: block) ?? "unknown"
            let name = HTMLSupport.first(#"class="l">([^<]+)</a>"#, in: block) ?? username
            let avatar = HTMLSupport.first(#"background-image:url\('([^']+)'\)"#, in: block)
            let rating = HTMLSupport.first(#"starlight stars(\d+)"#, in: block).flatMap(Int.init)
            let state = HTMLSupport.first(#"<small class="grey">\s*([^<@]+?)\s*</small>"#, in: block)?.trimmed
            let time = HTMLSupport.first(#"<small class="grey">\s*@\s*([^<]+)</small>"#, in: block)?.trimmed ?? ""
            let text = HTMLSupport.first(#"<p class="comment">(.*?)</p>"#, in: block).map(HTMLSupport.text) ?? ""
            guard !text.isEmpty else { return nil }
            return SocialComment(
                id: "\(subjectID)-\(page)-\(index)-\(username)",
                username: username,
                name: name,
                avatarURL: Images.normalized(avatar),
                rating: rating,
                state: state,
                time: time,
                text: text
            )
        }
    }

    private func parseEpisodeComments(_ html: String, episodeID: Int) -> [SocialComment] {
        let blocks = HTMLSupport.blocks(html, separator: #"<div id="post_"#)
        return blocks.enumerated().compactMap { index, block in
            let postID = HTMLSupport.first(#"^(\d+)"#, in: block) ?? "\(index)"
            let username = HTMLSupport.first(#"data-item-user="([^"]*)""#, in: block) ?? "unknown"
            let name = HTMLSupport.first(#"class="l post_author[^"]*">([^<]+)</a>"#, in: block)
                ?? HTMLSupport.first(#"class="l">([^<]+)</a>"#, in: block)
                ?? username
            let avatar = HTMLSupport.first(#"background-image:url\('([^']+)'\)"#, in: block)
            let time = HTMLSupport.first(#"</a>\s*-\s*([^<]+)</small>"#, in: block)?.trimmed ?? ""
            let content = HTMLSupport.first(#"class="reply_content">(.*?)<div class="likes_grid"#, in: block)
                ?? HTMLSupport.first(#"class="reply_content">(.*?)</div>\s*</div>"#, in: block)
                ?? ""
            let text = HTMLSupport.text(content)
            guard !text.isEmpty else { return nil }
            return SocialComment(
                id: "ep\(episodeID)-\(postID)",
                username: username,
                name: name,
                avatarURL: Images.normalized(avatar),
                rating: nil,
                state: nil,
                time: time,
                text: text
            )
        }
    }

    // MARK: - Groups

    private func parseGroupHome(_ html: String) -> GroupHome {
        let groupBlock = HTMLSupport.first(#"<ul class="groupsLarge">(.*?)</ul>"#, in: html) ?? html
        let groupMatches = HTMLSupport.matches(#"<a href="/group/([^"/]+)" title="([^"]*)">.*?<img src="([^"]*)".*?<small class="feed">([^<]+)</small>"#, in: groupBlock)
        let groups = groupMatches.compactMap { match -> GroupSummary? in
            guard match.count >= 5 else { return nil }
            let id = match[1]
            let title = match[2].isEmpty ? id : match[2]
            return GroupSummary(id: id, title: title, members: HTMLSupport.text(match[4]), iconURL: Images.normalized(match[3]))
        }

        let rows = HTMLSupport.matches(#"<tr[^>]*class="topic[^"]*".*?</tr>"#, in: html)
        var topics: [TopicSummary] = []
        for row in rows {
            let rowHTML = row[0]
            guard let idString = HTMLSupport.first(#"href="/group/topic/(\d+)""#, in: rowHTML),
                  let id = Int(idString),
                  let title = HTMLSupport.first(#"href="/group/topic/\d+"[^>]*class="l">([^<]+)</a>"#, in: rowHTML) else { continue }
            let groupName = HTMLSupport.first(#"<td class="odd"><a href="/group/[^"]+">([^<]+)</a></td>"#, in: rowHTML)
            let author = HTMLSupport.first(#"<td class="odd"><a href="/user/[^"]+">([^<]+)</a></td>"#, in: rowHTML)
            let replies = HTMLSupport.first(#"<td class="posts">(\d+)</td>"#, in: rowHTML)
            let last = HTMLSupport.first(#"<small class="grey">([^<]+)</small>"#, in: rowHTML)
            topics.append(TopicSummary(id: id, title: title, groupName: groupName, author: author, replies: replies, lastReply: last))
        }

        return GroupHome(groups: groups, topics: topics)
    }

    private func parseGroupDetail(_ html: String, name: String) -> GroupDetail {
        let title = HTMLSupport.first(#"<title>([^<]+)</title>"#, in: html) ?? name
        let introBlock = HTMLSupport.first(#"class="grp_box">(.*?)<div class="clear">"#, in: html) ?? ""
        let icon = HTMLSupport.first(#"<img src="([^"]*)" class="port[^"]*""#, in: html)
        let intro = HTMLSupport.text(introBlock)

        let topicRows = HTMLSupport.matches(#"<tr[^>]*class="topic[^"]*".*?</tr>"#, in: html)
        let topics: [TopicSummary] = topicRows.compactMap { row in
            let rowHTML = row[0]
            guard let idString = HTMLSupport.first(#"href="/group/topic/(\d+)""#, in: rowHTML),
                  let id = Int(idString),
                  let title = HTMLSupport.first(#"href="/group/topic/\d+"[^>]*class="l">([^<]+)</a>"#, in: rowHTML) else { return nil }
            let author = HTMLSupport.first(#"<td class="author"><a href="/user/[^"]+" class="l">([^<]+)</a></td>"#, in: rowHTML)
            let replies = HTMLSupport.first(#"<td class="posts">(\d+)</td>"#, in: rowHTML)
            let last = HTMLSupport.first(#"<small class="grey">([^<]+)</small>"#, in: rowHTML)
            return TopicSummary(id: id, title: title, groupName: name, author: author, replies: replies, lastReply: last)
        }

        return GroupDetail(name: name, title: title, intro: intro, iconURL: Images.normalized(icon), topics: topics)
    }

    private func parseTopic(_ html: String, id: Int) -> TopicDetail {
        let title = HTMLSupport.first(#"<title>([^<]+)</title>"#, in: html) ?? "话题"
        let groupName = HTMLSupport.first(#"<h1>.*?<a href="/group/[^"]+"[^>]*>([^<]+)</a>"#, in: html)
        let blocks = HTMLSupport.blocks(html, separator: #"<div id="post_"#)

        let posts = blocks.enumerated().compactMap { index, block -> TopicPost? in
            let postID = HTMLSupport.first(#"^(\d+)"#, in: block) ?? "\(index)"
            let floor = HTMLSupport.first(#"floor-anchor">#(\d+)</a>"#, in: block) ?? "#\(index + 1)"
            let username = HTMLSupport.first(#"data-item-user="([^"]*)""#, in: block) ?? "unknown"
            let name = HTMLSupport.first(#"class="l post_author[^"]*">([^<]+)</a>"#, in: block)
                ?? HTMLSupport.first(#"class="l">([^<]+)</a>"#, in: block)
                ?? username
            let avatar = HTMLSupport.first(#"background-image:url\('([^']+)'\)"#, in: block)
            let time = HTMLSupport.first(#"</a>\s*-\s*([^<]+)</small>"#, in: block)?.trimmed ?? ""
            let content = HTMLSupport.first(#"class="topic_content">(.*?)</div>"#, in: block)
                ?? HTMLSupport.first(#"class="reply_content">(.*?)<div class="likes_grid"#, in: block)
                ?? HTMLSupport.first(#"class="reply_content">(.*?)</div>"#, in: block)
                ?? ""
            let text = HTMLSupport.text(content)
            guard !text.isEmpty else { return nil }
            return TopicPost(
                id: postID,
                floor: floor,
                username: username,
                name: name,
                avatarURL: Images.normalized(avatar),
                time: time,
                text: text
            )
        }

        return TopicDetail(id: id, title: title, groupName: groupName, posts: posts)
    }

    // MARK: - Blogs

    private func parseBlogList(_ html: String) -> [BlogSummary] {
        let blocks = HTMLSupport.blocks(html, separator: #"<div class="item clearit""#)
        return blocks.compactMap { block in
            guard let idString = HTMLSupport.first(#"href="/blog/(\d+)""#, in: block),
                  let id = Int(idString) else { return nil }
            let title = HTMLSupport.first(#"class="title"><a[^>]*>(.*?)</a>"#, in: block).map(HTMLSupport.text) ?? "日志 #\(id)"
            let summary = HTMLSupport.first(#"class="content">(.*?)</div>"#, in: block).map(HTMLSupport.text) ?? ""
            let author = HTMLSupport.first(#"href="/user/[^"]+" class="l">([^<]+)</a>"#, in: block)
            let cover = HTMLSupport.first(#"<img src="([^"]*)""#, in: block)
            let subject = HTMLSupport.first(#"评论\s*<a href="/subject/\d+" class="l">([^<]+)</a>"#, in: block)
            let date = HTMLSupport.first(#"([0-9]{4}-[0-9]{1,2}-[0-9]{1,2})"#, in: block)
            return BlogSummary(
                id: id,
                title: title,
                author: author,
                summary: summary,
                date: date,
                coverURL: Images.normalized(cover),
                subjectName: subject
            )
        }
    }

    private func parseBlogDetail(_ html: String, id: Int) throws -> BlogDetail {
        guard let content = HTMLSupport.elementContents(id: "entry_content", in: html),
              !HTMLSupport.text(content).isEmpty else {
            throw APIError.message("无法读取日志，可从右上角菜单打开网页。")
        }
        let title = HTMLSupport.first(#"<h1[^>]*class="title"[^>]*>(.*?)</h1>"#, in: html).map(HTMLSupport.text)
            ?? HTMLSupport.first(#"<title>([^<]+)</title>"#, in: html).map(HTMLSupport.text)
            ?? "日志"
        let authorBlock = HTMLSupport.first(#"class="author user-card"[^>]*>(.*?)<div class="header""#, in: html) ?? ""
        let author = HTMLSupport.first(#"<a[^>]*href="/user/[^"/]+"[^>]*>([^<]+)</a>"#, in: authorBlock).map(HTMLSupport.text)
        let date = HTMLSupport.first(#"([0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:\s+[0-9:]+)?)"#, in: html)
        let cover = HTMLSupport.first(#"<div class="cover">.*?<img src="([^"]*)""#, in: html)
        return BlogDetail(
            id: id,
            title: title,
            author: author,
            date: date,
            content: HTMLSupport.text(content),
            coverURL: Images.normalized(cover)
        )
    }

    // MARK: - Timeline

    private func parseTimeline(_ html: String) -> [TimelineItem] {
        let blocks = HTMLSupport.blocks(html, separator: #"class="clearit tml_item""#)
        return blocks.compactMap { block in
            let id = HTMLSupport.first(#"id="tml_(\d+)""#, in: block) ?? UUID().uuidString
            let action = HTMLSupport.first(#"class="info_full clearit">\s*([^<]+)"#, in: block)?.trimmed ?? ""
            let subjectID = HTMLSupport.first(#"data-subject-id="(\d+)""#, in: block).flatMap(Int.init)
            let subjectTitle = HTMLSupport.first(#"data-subject-name-cn="([^"]*)""#, in: block)
                ?? HTMLSupport.first(#"data-subject-name="([^"]*)""#, in: block)
            let subjectOriginal = HTMLSupport.first(#"data-subject-name="([^"]*)""#, in: block)
            let comment = HTMLSupport.first(#"class="comment">(.*?)</div>"#, in: block)
                .map { HTMLSupport.text($0) }
            let rating = HTMLSupport.first(#"starlight stars(\d+)"#, in: block).flatMap(Int.init)
            let time = HTMLSupport.first(#"<span title="([^"]*)" class="titleTip""#, in: block)
            let cover = HTMLSupport.first(#"<span class="cover"><img src="([^"]*)""#, in: block)
            return TimelineItem(
                id: id,
                action: action,
                subjectID: subjectID,
                subjectTitle: subjectTitle,
                subjectOriginalTitle: subjectOriginal,
                comment: comment,
                rating: rating,
                time: time,
                coverURL: Images.normalized(cover)
            )
        }
    }
}
