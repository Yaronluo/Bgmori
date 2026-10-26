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

        if CommandLine.arguments.contains("--live") {
            let api = APIClient(cache: DiskCache(namespace: "BgmoriSocialVerification-\(UUID())"))
            let social = SocialService(api: api)
            let blogs = try await social.blogList()
            precondition(!blogs.isEmpty)
            for blog in blogs.prefix(3) {
                let detail = try await social.blogDetail(id: blog.id)
                precondition(!detail.content.isEmpty)
                precondition(!detail.title.isEmpty)
                print("PASS: live blog \(detail.id), \(detail.content.count) characters")
            }
        }
    }
}
