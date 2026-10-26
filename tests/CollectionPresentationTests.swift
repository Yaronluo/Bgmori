import Foundation

@main
struct CollectionPresentationTests {
    static func main() throws {
        let decoder = JSONDecoder()
        let base: [String: Any] = [
            "subject_id": 333158, "subject_type": 2, "rate": 7, "type": 2,
            "subject": ["id": 333158, "type": 2, "name": "ぼっち・ざ・ろっく！", "name_cn": "孤独摇滚！", "score": 9.8]
        ]
        for comment in [NSNull(), "", " \n\t\r "] as [Any] {
            var payload = base
            payload["comment"] = comment
            let item = try decoder.decode(UserSubjectCollection.self, from: JSONSerialization.data(withJSONObject: payload))
            precondition(item.reviewText == nil, "Null, empty and whitespace-only comments must hide the review")
        }
        var payload = base
        payload["comment"] = " \n喜欢舞台演出的细节。\n人物也很可爱。 \n"
        let item = try decoder.decode(UserSubjectCollection.self, from: JSONSerialization.data(withJSONObject: payload))
        precondition(item.reviewText == "喜欢舞台演出的细节。\n人物也很可爱。")
        precondition(item.rate == 7 && item.subject?.score == 9.8, "Personal and community ratings must remain distinct")
        precondition(item.applying(CollectionPatch(comment: "")).reviewText == nil, "Clearing a comment must remove its display block")
        precondition(item.applying(CollectionPatch(rate: 0)).rate == 0, "Unrated collections must stay unrated")
        print("PASS: absent/empty/whitespace comments, multiline reviews, clearing reviews and personal ratings")
    }
}
