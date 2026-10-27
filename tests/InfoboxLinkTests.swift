import Foundation

@main
struct InfoboxLinkTests {
    static func main() async throws {
        func links(_ key: String, _ value: InfoboxValue) -> [String] {
            InfoboxItem(key: key, value: value).linkedText.runs.compactMap { $0.link?.absoluteString }
        }
        precondition(links("个人博客", .text("http://ameblo.jp/taka8rie/")) == ["http://ameblo.jp/taka8rie/"])
        precondition(links("Twitter", .text("@taka8rie")) == ["https://twitter.com/taka8rie"])
        precondition(links("X", .text(" taka8rie ")) == ["https://twitter.com/taka8rie"])
        precondition(links("别名", .text("@taka8rie")).isEmpty)
        precondition(links("Twitter", .text("https://x.com/taka8rie")) == ["https://x.com/taka8rie"])
        precondition(links("Twitter", .text("@bad/name")).isEmpty)
        precondition(links("Twitter", .list(["@taka8rie", "@test_2"])) == ["https://twitter.com/taka8rie", "https://twitter.com/test_2"])
        precondition(links("网站", .text("https://bgm.tv.ech.invalid/person/17491")).isEmpty)
        precondition(links("网站", .text("javascript:alert(1)")).isEmpty)
        precondition(links("邮箱", .text("hello@example.com")).isEmpty)
        let mixed = InfoboxItem(key: "官方网站", value: .list(["日本語 https://taka8rie.com/", "https://example.com/a?q=1&b=2"]))
        precondition(String(mixed.linkedText.characters) == mixed.value.display)
        precondition(links(mixed.key, mixed.value) == ["https://taka8rie.com/", "https://example.com/a?q=1&b=2"])
        precondition(links("官网", .text("www.example.com")) == ["http://www.example.com"])
        print("PASS: web links, handles, lists, Unicode, plain text and internal/unsafe URL exclusion")

        if CommandLine.arguments.contains("--live") {
            var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/persons/17491")!)
            request.setValue("Yaronluo/Bgmori (infobox verification)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            precondition((response as? HTTPURLResponse)?.statusCode == 200)
            let person = try JSONDecoder().decode(PersonDetail.self, from: data)
            let blog = person.infobox.first { $0.key == "个人博客" }!
            let twitter = person.infobox.first { $0.key == "Twitter" }!
            precondition(links(blog.key, blog.value) == ["http://ameblo.jp/taka8rie/"])
            precondition(links(twitter.key, twitter.value) == ["https://twitter.com/taka8rie"])
            print("PASS: live person 17491 blog and Twitter destinations")
        }
    }
}
