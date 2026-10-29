import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    var appearance: AppAppearance = .system { didSet { save() } }
    var preferChineseName = true { didSet { save() } }
    var hideSpoilers = true { didSet { save() } }
    var showNSFW = false { didSet { save() } }
    var showWatchingProgress = false { didSet { save() } }
    var dailyReminder = false { didSet { save() } }
    var useSafariUserAgentForHTML = true { didSet { save() } }

    private let defaults = UserDefaults.standard
    /// @Observable 会把存储属性改写成计算属性，init 里的赋值同样会触发 didSet。
    /// 加载完成前禁止回写，否则第一行赋值就会用默认值覆盖磁盘上已有的设置。
    @ObservationIgnored private var isLoaded = false

    init() {
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        preferChineseName = defaults.object(forKey: "preferChineseName") as? Bool ?? true
        hideSpoilers = defaults.object(forKey: "hideSpoilers") as? Bool ?? true
        showNSFW = defaults.object(forKey: "showNSFW") as? Bool ?? false
        showWatchingProgress = defaults.object(forKey: "showWatchingProgress") as? Bool ?? false
        dailyReminder = defaults.object(forKey: "dailyReminder") as? Bool ?? false
        useSafariUserAgentForHTML = defaults.object(forKey: "useSafariUserAgentForHTML") as? Bool ?? true

        // Account/password login no longer needs a locally configured OAuth application.
        for key in ["oauthClientID", "oauthClientSecret", "oauthRedirectURI"] {
            defaults.removeObject(forKey: key)
        }

        isLoaded = true
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    func save() {
        guard isLoaded else { return }
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(preferChineseName, forKey: "preferChineseName")
        defaults.set(hideSpoilers, forKey: "hideSpoilers")
        defaults.set(showNSFW, forKey: "showNSFW")
        defaults.set(showWatchingProgress, forKey: "showWatchingProgress")
        defaults.set(dailyReminder, forKey: "dailyReminder")
        defaults.set(useSafariUserAgentForHTML, forKey: "useSafariUserAgentForHTML")
    }
}
