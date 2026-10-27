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
        #if DEBUG
        // UI verification can browse public pages without accessing the user's keychain.
        if ProcessInfo.processInfo.environment["BGMORI_GUEST_MODE"] == "1" { return }
        #endif
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
            let authorizationURL = await api.browserURL(URL(string: "https://bgm.tv/oauth/authorize")!)
            var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
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

        defer { webSession = nil }

        return try await withCheckedThrowingContinuation { continuation in
            let result = AuthContinuation(continuation)

            // ASWebAuthenticationSession 不保证在主线程回调：macOS 上它从
            // SafariLaunchAgent 的 XPC 队列返回。闭包必须显式标成 @Sendable，
            // 否则会继承 MainActor 隔离，被系统线程调用时触发
            // “Block was expected to execute on queue [com.apple.main-thread]” 崩溃。
            let completion: @Sendable (URL?, (any Error)?) -> Void = { callback, error in
                if let error {
                    result.resume(throwing: error)
                } else if let callback {
                    result.resume(returning: callback)
                } else {
                    result.resume(throwing: APIError.message("授权已取消"))
                }
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme,
                completionHandler: completion
            )
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            webSession = session

            guard session.start() else {
                result.resume(throwing: APIError.message("无法打开登录页面，请稍后重试"))
                return
            }
        }
    }
}

/// 保证登录回调只恢复一次 continuation，避免 start 失败与系统回调同时发生时的重复恢复崩溃。
private final class AuthContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?

    init(_ continuation: CheckedContinuation<URL, any Error>) {
        self.continuation = continuation
    }

    func resume(returning url: URL) {
        take()?.resume(returning: url)
    }

    func resume(throwing error: any Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<URL, any Error>? {
        lock.lock()
        defer { lock.unlock() }
        let pending = continuation
        continuation = nil
        return pending
    }
}
