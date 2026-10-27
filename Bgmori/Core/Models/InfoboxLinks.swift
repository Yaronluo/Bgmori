import Foundation

extension InfoboxItem {
    /// Preserve the original text while making web addresses and social handles actionable.
    var linkedText: AttributedString {
        var result = AttributedString(value.display)
        let text = value.display
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in Self.webLinkDetector.matches(in: text, range: fullRange) {
            guard let url = match.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host?.lowercased(),
                  host != "ech.invalid", !host.hasSuffix(".ech.invalid"),
                  let range = Range(match.range, in: text),
                  let attributedRange = Range(range, in: result) else { continue }
            result[attributedRange].link = url
        }

        let field = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if field.contains("twitter") || field.contains("推特") || field == "x" {
            // A bare handle is only meaningful in a Twitter/X field. Other @ text stays literal.
            let values: [String]
            switch value {
            case .text(let text): values = [text]
            case .list(let list): values = list
            }
            var offset = 0
            for entry in values {
                let handle = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                if handle.range(of: #"^@?[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil,
                   let range = Range(NSRange(location: offset, length: (entry as NSString).length), in: text),
                   let attributedRange = Range(range, in: result) {
                    let username = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
                    result[attributedRange].link = URL(string: "https://twitter.com/\(username)")
                }
                offset += (entry as NSString).length + 3 // InfoboxValue.display joins with " / ".
            }
        }
        return result
    }

    private static let webLinkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}
