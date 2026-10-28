#if DEBUG
import SwiftUI

/// Deterministic UI regression surfaces; no account or collection writes are involved.
struct DebugLayoutPreview: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BGMORI_PREVIEW_PAGINATION"] == "1"
            || ProcessInfo.processInfo.environment["BGMORI_PREVIEW_YEAR_PICKER"] == "1"
    }
    @State private var completedPages = 0
    @State private var isLoading = false
    @State private var year: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if ProcessInfo.processInfo.environment["BGMORI_PREVIEW_YEAR_PICKER"] == "1" {
                    YearPickerButton(selection: $year) { Text(year.map(String.init) ?? "年份") }
                } else {
                    Text("\(completedPages)").accessibilityIdentifier("pagination-preview-count")
                    if completedPages < 3 {
                        PaginationFooter(offset: completedPages, isLoading: isLoading, error: nil) {
                            guard !isLoading else { return }
                            isLoading = true
                            defer { isLoading = false }
                            try? await Task.sleep(for: .milliseconds(150))
                            guard !Task.isCancelled else { return }
                            completedPages += 1
                            // Offset becomes visible before snapshot persistence finishes.
                            try? await Task.sleep(for: .milliseconds(400))
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgmCanvas)
    }
}
enum DebugCollectionFixtures {
    static let collections: [UserSubjectCollection] = {
        let json = #"""
[
{"subject_id":328609,"subject_type":2,"type":1,"rate":0,"ep_status":0,"comment":"","subject":{"id":328609,"type":2,"name":"ぼっち・ざ・ろっく！","name_cn":"孤独摇滚！","images":{"large":"https://lain.bgm.tv/pic/cover/l/e2/e7/328609_2EHLJ.jpg"},"eps":12}},
{"subject_id":27364,"subject_type":2,"type":1,"rate":0,"ep_status":0,"comment":"","subject":{"id":27364,"type":2,"name":"氷菓","name_cn":"冰菓","images":{"large":"https://lain.bgm.tv/pic/cover/l/cd/38/27364_1ZFmr.jpg"},"eps":22}},
{"subject_id":1424,"subject_type":2,"type":3,"rate":0,"ep_status":3,"comment":"","subject":{"id":1424,"type":2,"name":"けいおん！","name_cn":"轻音少女","images":{"large":"https://lain.bgm.tv/pic/cover/l/48/9d/1424_q8FMQ.jpg"},"eps":14}},
{"subject_id":160209,"subject_type":2,"type":2,"rate":10,"ep_status":0,"comment":"很喜欢。","subject":{"id":160209,"type":2,"name":"君の名は。","name_cn":"你的名字。","images":{"large":"https://lain.bgm.tv/pic/cover/l/20/15/160209_2UzU8.jpg"},"eps":1}},
{"subject_id":876,"subject_type":2,"type":2,"rate":9,"ep_status":0,"comment":"用来检查长短评论是否撑高网格。这里的内容应当只占一行，完整文字仍然可以在列表或详情阅读。","subject":{"id":876,"type":2,"name":"CLANNAD 〜AFTER STORY〜","name_cn":"","images":{"large":"https://lain.bgm.tv/pic/cover/l/67/d1/876_dCfrd.jpg"},"eps":24}},
{"subject_id":464376,"subject_type":2,"type":4,"rate":7,"ep_status":0,"comment":"","subject":{"id":464376,"type":2,"name":"負けヒロインが多すぎる！","name_cn":"败犬女主太多了！","images":{"large":"https://lain.bgm.tv/pic/cover/l/e4/dc/464376_NsZRw.jpg"},"eps":12}},
{"subject_id":51,"subject_type":2,"type":1,"rate":0,"ep_status":0,"comment":"","subject":{"id":51,"type":2,"name":"CLANNAD -クラナド-","name_cn":"CLANNAD","images":{"large":"https://lain.bgm.tv/pic/cover/l/28/38/51_6PN42.jpg"},"eps":23}},
{"subject_id":428735,"subject_type":2,"type":1,"rate":0,"ep_status":0,"comment":"","subject":{"id":428735,"type":2,"name":"BanG Dream! It's MyGO!!!!!","name_cn":"","images":{"large":"https://lain.bgm.tv/pic/cover/l/e7/a7/428735_1v11n.jpg"},"eps":13}},
{"subject_id":9912,"subject_type":2,"type":3,"rate":0,"ep_status":3,"comment":"","subject":{"id":9912,"type":2,"name":"日常","name_cn":"日常","images":{"large":"https://lain.bgm.tv/pic/cover/l/0e/14/9912_vHEd6.jpg"},"eps":26}},
{"subject_id":909,"subject_type":2,"type":2,"rate":10,"ep_status":0,"comment":"很喜欢。","subject":{"id":909,"type":2,"name":"とらドラ！","name_cn":"龙与虎","images":{"large":"https://lain.bgm.tv/pic/cover/l/a4/30/909_e5zhk.jpg"},"eps":25}},
{"subject_id":248175,"subject_type":2,"type":2,"rate":9,"ep_status":0,"comment":"用来检查长短评论是否撑高网格。这里的内容应当只占一行，完整文字仍然可以在列表或详情阅读。","subject":{"id":248175,"type":2,"name":"かぐや様は告らせたい～天才たちの恋愛頭脳戦～","name_cn":"辉夜大小姐想让我告白～天才们的恋爱头脑战～","images":{"large":"https://lain.bgm.tv/pic/cover/l/2a/f7/248175_2w4zT.jpg"},"eps":12}},
{"subject_id":29648,"subject_type":2,"type":4,"rate":7,"ep_status":0,"comment":"","subject":{"id":29648,"type":2,"name":"中二病でも恋がしたい！","name_cn":"中二病也要谈恋爱！","images":{"large":"https://lain.bgm.tv/pic/cover/l/3d/fd/29648_LOcOx.jpg"},"eps":13}}
]
"""#
        return (try? JSONDecoder().decode([UserSubjectCollection].self, from: Data(json.utf8))) ?? []
    }()
}
#endif
