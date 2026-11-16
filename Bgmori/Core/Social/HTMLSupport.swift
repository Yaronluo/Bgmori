import Foundation

/// Compiling a pattern costs more than matching a small page, and social
/// parsing asks for the same handful of patterns dozens of times per page.
private final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()
    private let lock = NSLock()
    private var storage: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue)|\(pattern)"
        lock.lock()
        if let cached = storage[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        lock.lock()
        if storage.count >= 256 { storage.removeAll(keepingCapacity: true) }
        storage[key] = regex
        lock.unlock()
        return regex
    }
}

enum HTMLSupport {
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = RegexCache.shared.regex(pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
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

    /// Keep opening tags so callers can read attributes regardless of their order.
    static func blocks(_ html: String, matching pattern: String) -> [String] {
        guard let regex = RegexCache.shared.regex(pattern, options: .caseInsensitive) else { return [] }
        let source = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
        return matches.enumerated().map { index, match in
            let end = index + 1 < matches.count ? matches[index + 1].range.location : source.length
            return source.substring(with: NSRange(location: match.range.location, length: end - match.range.location))
        }
    }

    static func elementContents(class className: String, in html: String) -> String? {
        let name = NSRegularExpression.escapedPattern(for: className)
        return elementContents(openingPattern: "<([a-z][a-z0-9]*)\\b[^>]*\\bclass=[\"'][^\"']*\\b" + name + "\\b[^\"']*[\"'][^>]*>", in: html)
    }

    // Match the closing container by depth so nested quotes and spoilers retain their full text.
    static func elementContents(id: String, in html: String) -> String? {
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        let pattern = "<([a-z][a-z0-9]*)\\b[^>]*\\bid=[\"']" + escapedID + "[\"'][^>]*>"
        return elementContents(openingPattern: pattern, in: html)
    }

    private static func elementContents(openingPattern: String, in html: String) -> String? {
        guard let opening = RegexCache.shared.regex(openingPattern, options: .caseInsensitive) else { return nil }
        let source = html as NSString
        guard let match = opening.firstMatch(in: html, range: NSRange(location: 0, length: source.length)) else { return nil }
        let tag = source.substring(with: match.range(at: 1))
        let start = NSMaxRange(match.range)
        guard let tags = RegexCache.shared.regex("</?" + tag + "\\b[^>]*>", options: .caseInsensitive) else { return nil }
        var depth = 1
        for token in tags.matches(in: html, range: NSRange(location: start, length: source.length - start)) {
            let value = source.substring(with: token.range)
            if value.hasPrefix("</") { depth -= 1 }
            else if !value.hasSuffix("/>") { depth += 1 }
            if depth == 0 { return source.substring(with: NSRange(location: start, length: token.range.location - start)) }
        }
        return nil
    }

    static func text(_ html: String) -> String {
        var value = html.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
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

        guard let regex = RegexCache.shared.regex(#"&#(x?)([0-9A-Fa-f]+);"#, options: []) else { return value }
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
