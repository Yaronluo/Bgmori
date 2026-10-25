import Foundation

struct SocialComment: Identifiable, Hashable, Sendable {
    let id: String
    let username: String
    let name: String
    let avatarURL: URL?
    let rating: Int?
    let state: String?
    let time: String
    let text: String
}

struct GroupSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let members: String
    let iconURL: URL?
}

struct TopicSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let groupName: String?
    let author: String?
    let replies: String?
    let lastReply: String?
}

struct GroupHome: Sendable {
    let groups: [GroupSummary]
    let topics: [TopicSummary]
}

struct GroupDetail: Sendable {
    let name: String
    let title: String
    let intro: String
    let iconURL: URL?
    let topics: [TopicSummary]
}

struct TopicPost: Identifiable, Hashable, Sendable {
    let id: String
    let floor: String
    let username: String
    let name: String
    let avatarURL: URL?
    let time: String
    let text: String
}

struct TopicDetail: Sendable {
    let id: Int
    let title: String
    let groupName: String?
    let posts: [TopicPost]
}

struct BlogSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let author: String?
    let summary: String
    let date: String?
    let coverURL: URL?
    let subjectName: String?
}

struct BlogDetail: Sendable {
    let id: Int
    let title: String
    let author: String?
    let date: String?
    let content: String
    let coverURL: URL?
}

struct TimelineItem: Identifiable, Hashable, Sendable {
    let id: String
    let action: String
    let subjectID: Int?
    let subjectTitle: String?
    let subjectOriginalTitle: String?
    let comment: String?
    let rating: Int?
    let time: String?
    let coverURL: URL?
}
