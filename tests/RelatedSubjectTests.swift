import Foundation

@main
struct RelatedSubjectTests {
    static func main() throws {
        let decoder = JSONDecoder()

        // /v0/characters/{id}/subjects and /v0/persons/{id}/subjects use
        // "image" + "staff" instead of the "images" + "relation" shape.
        let creditJSON = """
        [{
            "staff": "主角",
            "eps": "",
            "name": "けいおん!",
            "name_cn": "轻音少女",
            "image": "http://lain.bgm.tv/pic/cover/l/ab/cd/1_abc.jpg",
            "type": 2,
            "id": 1
        }]
        """
        let credits = try decoder.decode([RelatedSubject].self, from: Data(creditJSON.utf8))
        precondition(credits.count == 1)
        let credit = credits[0]
        precondition(credit.relation == "主角", "Character/person credits must read the staff field")
        precondition(credit.displayTitle == "轻音少女")
        precondition(credit.coverURL?.absoluteString == "https://lain.bgm.tv/pic/cover/l/ab/cd/1_abc.jpg",
                     "Credits must fall back to the single image URL and upgrade it to HTTPS")

        // /v0/subjects/{id}/subjects keeps the images object and relation field.
        let relationJSON = """
        [{
            "images": {
                "small": "https://lain.bgm.tv/r/200/pic/cover/l/ef/gh/2.jpg",
                "grid": "https://lain.bgm.tv/r/100/pic/cover/l/ef/gh/2.jpg",
                "large": "https://lain.bgm.tv/pic/cover/l/ef/gh/2.jpg",
                "medium": "https://lain.bgm.tv/r/800/pic/cover/l/ef/gh/2.jpg",
                "common": "https://lain.bgm.tv/r/400/pic/cover/l/ef/gh/2.jpg"
            },
            "name": "CLANNAD",
            "name_cn": "",
            "relation": "游戏",
            "type": 4,
            "id": 2
        }]
        """
        let relations = try decoder.decode([RelatedSubject].self, from: Data(relationJSON.utf8))
        precondition(relations[0].relation == "游戏")
        precondition(relations[0].coverURL?.absoluteString == "https://lain.bgm.tv/pic/cover/l/ef/gh/2.jpg",
                     "Subject relations must keep the images object")
        precondition(relations[0].displayTitle == "CLANNAD")

        print("PASS: character/person credits decode staff + image, subject relations keep relation + images")
    }
}
