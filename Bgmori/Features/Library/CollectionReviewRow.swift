import SwiftUI

struct CollectionReviewRow: View {
    @Environment(\.displayScale) private var displayScale
    let item: UserSubjectCollection

    private var coverWidth: CGFloat {
        #if os(macOS)
        108
        #else
        76
        #endif
    }

    private var metadata: String {
        var parts = [SubjectType.title(for: item.subjectType)]
        if let subject = item.subject {
            if item.subjectType == SubjectType.book.rawValue, subject.volumes > 0 {
                parts.append("\(subject.volumes) 卷")
            } else if subject.eps > 0 {
                parts.append("\(subject.eps) 话")
            }
            if let date = subject.date, !date.isEmpty { parts.append(date) }
        }
        return parts.joined(separator: " · ")
    }

    private var updatedDate: Date? {
        guard let raw = item.updatedAt else { return nil }
        return (try? Date(raw, strategy: .iso8601))
            ?? (try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CachedAsyncImage(url: item.coverURL, maxPixel: Int(ceil(coverWidth * 1.42 * displayScale)),
                             placeholderTint: .subjectTint(item.subjectType))
                .frame(width: coverWidth, height: coverWidth * 1.42)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                #if os(macOS)
                HStack(alignment: .top, spacing: 16) {
                    titles
                    Spacer(minLength: 0)
                    CollectionBadge(type: item.collectionType)
                }
                #else
                titles
                #endif

                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        CollectionPersonalRating(rate: item.rate)
                        dateLabel
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        CollectionPersonalRating(rate: item.rate)
                        dateLabel
                    }
                }

                #if os(iOS)
                HStack(spacing: 8) {
                    CollectionBadge(type: item.collectionType)
                    progressLabel
                }
                #else
                progressLabel
                #endif

                if let review = item.reviewText {
                    CollectionReviewText(text: review)
                        .accessibilityIdentifier("library-review-\(item.subjectId)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            if let original = item.subject?.name, !original.isEmpty, original != item.title {
                Text(original)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var dateLabel: some View {
        if let date = updatedDate {
            Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("收藏更新于 \(date.formatted(date: .abbreviated, time: .omitted))")
        }
    }

    @ViewBuilder
    private var progressLabel: some View {
        if item.collectionType == .doing, !item.progressText.isEmpty {
            Text("进度 \(item.progressText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CollectionPersonalRating: View {
    let rate: Int

    var body: some View {
        HStack(spacing: 6) {
            if rate > 0 {
                RatingStars(score: Double(min(rate, 10)), size: 11)
                Text("\(min(rate, 10)) 分")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("未评分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rate > 0 ? "我的评分 \(min(rate, 10)) 分，满分 10 分" : "未评分")
    }
}

struct CollectionReviewText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bgmMuted.opacity(0.14)))
    }
}
