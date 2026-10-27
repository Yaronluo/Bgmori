import Foundation

@main
struct SocialTests {
    static func main() async throws {
        let html = #"<div id="entry_content" class="content">开头<div class="quote">引用<div>嵌套</div>尾部</div><p>最后一段</p></div><div>不应包含</div>"#
        let content = HTMLSupport.elementContents(id: "entry_content", in: html)
        precondition(content != nil)
        let text = HTMLSupport.text(content!)
        precondition(text.contains("最后一段"), "Nested containers must not truncate the blog")
        precondition(!text.contains("不应包含"), "Blog extraction must stop at its closing container")
        precondition(HTMLSupport.elementContents(id: "missing", in: html) == nil)
        precondition(HTMLSupport.elementContents(id: "entry_content", in: "<div id='entry_content'>unfinished") == nil)
        precondition(HTMLSupport.elementContents(id: "entry_content", in: "<DIV class='content' id='entry_content'>正文</DIV>") == "正文")
        precondition(HTMLSupport.text("第一段<br />\r\n<br />\r\n<br />第二段") == "第一段\n\n第二段")
        print("PASS: nested blog content, boundary, malformed containers and paragraph spacing")

        let subjectHTML = #"""
        <div id="comment_box"><div data-item-user="sai" class="item clearit">
        <a href="/user/sai" class="l">Sai</a><p class="comment">第一行<br />第二行</p></div></div>
        """#
        let comments = try SocialService.parseSubjectComments(subjectHTML, subjectID: 8, page: 1)
        precondition(comments.count == 1 && comments[0].text == "第一行\n第二行")
        let episodeHTML = #"""
        <div id="comment_list"><div class="row" id="post_1" data-item-user="sai">
        <a class="l">Sai</a><div class="reply_content"><div class="message clearit">正文<div>尾段</div></div>
        <div class="likes_grid">不应包含</div><div id="post_2" data-item-user="other">
        <div class="cmt_sub_content"><div class="quote">引用</div>回复尾段</div></div></div></div></div>
        """#
        let posts = try SocialService.parseEpisodeComments(episodeHTML, episodeID: 1027)
        precondition(posts.count == 2 && posts[0].text == "正文尾段" && posts[1].text.contains("回复尾段"))
        precondition(!posts[0].text.contains("不应包含") && !posts[0].text.contains("回复尾段"))
        let emptySubject = try SocialService.parseSubjectComments("<div id='comment_box'></div>", subjectID: 8, page: 1)
        let emptyEpisode = try SocialService.parseEpisodeComments("<div id='comment_list'></div>", episodeID: 1027)
        precondition(emptySubject.isEmpty && emptyEpisode.isEmpty)
        for invalid in ["<html>需要登录</html>", "<div id='comment_box'><div class='item clearit'>格式已变化</div></div>"] {
            do {
                _ = try SocialService.parseSubjectComments(invalid, subjectID: 8, page: 1)
                preconditionFailure("Unreadable pages must not become empty comments")
            } catch APIError.message { }
        }
        print("PASS: comment containers, nested messages/replies, genuine empty states and explicit parse failures")

        if CommandLine.arguments.contains("--live") {
            let api = APIClient(cache: DiskCache(namespace: "BgmoriSocialVerification-\(UUID())"))
            let social = SocialService(api: api)
            let subjectComments = try await social.subjectComments(subjectID: 317613, force: true)
            let episodeComments = try await social.episodeComments(episodeID: 1027, force: true)
            precondition(subjectComments.count == 20 && !episodeComments.isEmpty)
            precondition(episodeComments.contains { $0.id == "ep1027-242518" }, "Nested episode replies must load")
            print("PASS: live subject 317613 (\(subjectComments.count) comments), episode 1027 (\(episodeComments.count) posts)")
            let blogs = try await social.blogList()
            precondition(!blogs.isEmpty)
            var verified = 0
            for blog in blogs.prefix(8) {
                let detail: BlogDetail
                do {
                    detail = try await social.blogDetail(id: blog.id)
                } catch APIError.notFound {
                    print("SKIP: live blog \(blog.id) was removed after entering the list")
                    continue
                }
                precondition(!detail.content.isEmpty)
                precondition(!detail.title.isEmpty)
                print("PASS: live blog \(detail.id), \(detail.content.count) characters")
                verified += 1
                if verified == 3 { break }
            }
            precondition(verified == 3, "Verify three existing live blog bodies")
        }
    }
}
