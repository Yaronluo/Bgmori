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
    var dailyReminder = false { didSet { save() } }
    var useSafariUserAgentForHTML = true { didSet { save() } }

    var oauthClientID: String = "" { didSet { save() } }
    var oauthClientSecret: String = "" { didSet { save() } }
    var oauthRedirectURI: String = "bgmori://oauth/callback" { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        preferChineseName = defaults.object(forKey: "preferChineseName") as? Bool ?? true
        hideSpoilers = defaults.object(forKey: "hideSpoilers") as? Bool ?? true
        showNSFW = defaults.object(forKey: "showNSFW") as? Bool ?? false
        dailyReminder = defaults.object(forKey: "dailyReminder") as? Bool ?? false
        useSafariUserAgentForHTML = defaults.object(forKey: "useSafariUserAgentForHTML") as? Bool ?? true

        oauthClientID = defaults.string(forKey: "oauthClientID")
            ?? Bundle.main.object(forInfoDictionaryKey: "BGMApiClientID") as? String
            ?? ""
        oauthClientSecret = defaults.string(forKey: "oauthClientSecret")
            ?? Bundle.main.object(forInfoDictionaryKey: "BGMApiClientSecret") as? String
            ?? ""
        oauthRedirectURI = defaults.string(forKey: "oauthRedirectURI")
            ?? (Bundle.main.object(forInfoDictionaryKey: "BGMOAuthRedirect") as? String)
            ?? "bgmori://oauth/callback"
    }

    var hasOAuthConfig: Bool {
        !oauthClientID.trimmed.isEmpty && !oauthClientSecret.trimmed.isEmpty
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    func save() {
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(preferChineseName, forKey: "preferChineseName")
        defaults.set(hideSpoilers, forKey: "hideSpoilers")
        defaults.set(showNSFW, forKey: "showNSFW")
        defaults.set(dailyReminder, forKey: "dailyReminder")
        defaults.set(useSafariUserAgentForHTML, forKey: "useSafariUserAgentForHTML")
        defaults.set(oauthClientID, forKey: "oauthClientID")
        defaults.set(oauthClientSecret, forKey: "oauthClientSecret")
        defaults.set(oauthRedirectURI, forKey: "oauthRedirectURI")
    }
}
