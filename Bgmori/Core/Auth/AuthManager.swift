import AuthenticationServices
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first {
            return window
        }
        return UIWindow(windowScene: scenes.first!)
        #endif
    }
}

@MainActor
@Observable
final class AuthManager {
    private let api: APIClient
    private let settings: AppSettings
    private let presenter = WebAuthPresenter()
    private var webSession: ASWebAuthenticationSession?

    private(set) var token: String?
    private(set) var refreshToken: String?
    private(set) var expiresAt: Date?
    private(set) var user: User?

    var isRestoring = false
    var isSigningIn = false
    var errorMessage: String?

    init(api: APIClient, settings: AppSettings) {
        self.api = api
        self.settings = settings
        token = Keychain.read("accessToken")
        refreshToken = Keychain.read("refreshToken")
        if let interval = UserDefaults.standard.object(forKey: "tokenExpiresAt") as? Double {
            expiresAt = Date(timeIntervalSince1970: interval)
        }
    }

    var isLoggedIn: Bool { token?.isEmpty == false }
    var displayName: String { user?.displayName ?? "Bangumi 用户" }
    var username: String? { user?.username }

    func restore() async {
        guard let token, !token.isEmpty else { return }
        isRestoring = true
        defer { isRestoring = false }
        await api.setToken(token)

        do {
            user = try await api.me()
        } catch APIError.unauthorized {
            if await refresh() {
                user = try? await api.me()
            } else {
                signOut()
            }
        } catch {
            // Keep the token for offline use; the UI can still browse.
            errorMessage = (error as? LocalizedError)?.errorDescription
        }
    }

    func signIn() async {
        guard settings.hasOAuthConfig else {
            errorMessage = APIError.missingConfiguration.localizedDescription
            return
        }
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let state = UUID().uuidString
            var components = URLComponents(string: "https://bgm.tv/oauth/authorize")!
            components.queryItems = [
                .init(name: "client_id", value: settings.oauthClientID.trimmed),
                .init(name: "response_type", value: "code"),
                .init(name: "redirect_uri", value: settings.oauthRedirectURI),
                .init(name: "state", value: state)
            ]
            guard let url = components.url else { throw APIError.invalidURL }

            let callback = try await authenticate(url: url)
            guard let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                  let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value,
                  let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
                  returnedState == state else {
                throw APIError.message("授权回调校验失败，请重试")
            }

            let response = try await api.oauthToken(form: [
                "grant_type": "authorization_code",
                "client_id": settings.oauthClientID.trimmed,
                "client_secret": settings.oauthClientSecret.trimmed,
                "code": code,
                "redirect_uri": settings.oauthRedirectURI
            ])
            try await apply(response)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signInWithToken(_ raw: String) async {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            token = trimmed
            Keychain.save(trimmed, for: "accessToken")
            await api.setToken(trimmed)
            user = try await api.me()
            expiresAt = nil
            UserDefaults.standard.removeObject(forKey: "tokenExpiresAt")
        } catch {
            token = nil
            Keychain.delete("accessToken")
            await api.setToken(nil)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        guard let refreshToken, !refreshToken.isEmpty, settings.hasOAuthConfig else { return false }
        do {
            let response = try await api.oauthToken(form: [
                "grant_type": "refresh_token",
                "client_id": settings.oauthClientID.trimmed,
                "client_secret": settings.oauthClientSecret.trimmed,
                "refresh_token": refreshToken,
                "redirect_uri": settings.oauthRedirectURI
            ])
            try await apply(response)
            return true
        } catch {
            return false
        }
    }

    func refreshIfNeeded() async {
        guard isLoggedIn else { return }
        if let expiresAt, expiresAt.timeIntervalSinceNow > 86_400 { return }
        _ = await refresh()
    }

    func signOut() {
        token = nil
        refreshToken = nil
        expiresAt = nil
        user = nil
        errorMessage = nil
        Keychain.delete("accessToken")
        Keychain.delete("refreshToken")
        UserDefaults.standard.removeObject(forKey: "tokenExpiresAt")
        Task {
            await api.setToken(nil)
            await api.clearCache()
        }
    }

    private func apply(_ response: TokenResponse) async throws {
        token = response.accessToken
        refreshToken = response.refreshToken ?? refreshToken
        expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))

        Keychain.save(response.accessToken, for: "accessToken")
        if let refreshToken = response.refreshToken {
            Keychain.save(refreshToken, for: "refreshToken")
        }
        UserDefaults.standard.set(expiresAt?.timeIntervalSince1970, forKey: "tokenExpiresAt")

        await api.setToken(response.accessToken)
        user = try? await api.me()
    }

    private func authenticate(url: URL) async throws -> URL {
        let scheme = settings.oauthRedirectURI
            .split(separator: ":")
            .first
            .map(String.init) ?? "bgmori"

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: APIError.message("授权已取消"))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            session.start()
        }
    }
}
