import Foundation

enum HTMLSupport {
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
        }
    }

    static func first(_ pattern: String, in text: String) -> String? {
        guard let match = matches(pattern, in: text).first, match.count > 1 else { return nil }
        let value = match[1]
        return value.isEmpty ? nil : value
    }

    static func all(_ pattern: String, in text: String) -> [String] {
        matches(pattern, in: text).compactMap { $0.count > 1 ? $0[1] : nil }
    }

    static func blocks(_ html: String, separator: String) -> [String] {
        html.components(separatedBy: separator).dropFirst().map { String($0) }
    }

    static func text(_ html: String) -> String {
        var value = html
        value = value.replacingOccurrences(of: #"<script.*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"<style.*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"<img[^>]*alt="([^"]*)"[^>]*>"#, with: "$1", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"</(p|div|li|h[1-6])>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        value = decodeEntities(value)
        value = value.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        let map: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
            "&apos;": "'", "&nbsp;": " ", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–",
            "&middot;": "·", "&laquo;": "«", "&raquo;": "»", "&copy;": "©", "&times;": "×"
        ]
        var value = text
        for (key, replacement) in map {
            value = value.replacingOccurrences(of: key, with: replacement)
        }

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9A-Fa-f]+);"#) else { return value }
        let ns = NSMutableString(string: value)
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let isHex = ns.substring(with: match.range(at: 1)).lowercased() == "x"
            let number = ns.substring(with: match.range(at: 2))
            guard let code = UInt32(number, radix: isHex ? 16 : 10), let scalar = UnicodeScalar(code) else { continue }
            ns.replaceCharacters(in: match.range, with: String(scalar))
        }
        return ns as String
    }

    static func absoluteURL(_ raw: String?, base: String = "https://bgm.tv") -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") { return URL(string: base + raw) }
        return URL(string: raw)
    }

    static func firstParagraph(_ html: String) -> String {
        text(html)
    }
}

enum BBCode {
    static func plain(_ input: String, hideSpoilers: Bool = true) -> String {
        var value = input
        value = value.replacingOccurrences(of: #"\[img\].*?\[/img\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\[url=[^\]]*\](.*?)\[/url\]"#, with: "$1", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\[url\](.*?)\[/url\]"#, with: "$1", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\[mask\](.*?)\[/mask\]"#, with: hideSpoilers ? "▮▮▮" : "$1", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\[(b|i|u|s|quote|code|center|left|right|size=[^\]]*|color=[^\]]*)\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\[/(b|i|u|s|quote|code|center|left|right|size|color)\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\[[^\]]{1,20}\]"#, with: "", options: .regularExpression)
        return HTMLSupport.decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
