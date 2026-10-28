import Foundation

@MainActor
@Observable
final class AuthManager {
    private let api: APIClient
    private let website: BangumiWebLogin
    private var loginID = UUID()
    private var issuedTokenName: String?

    private(set) var token: String?
    private(set) var expiresAt: Date?
    private(set) var user: User?
    private(set) var captchaData: Data?
    private(set) var isLoadingCaptcha = false
    private(set) var isSigningIn = false
    private(set) var isCompletingLogin = false
    var isRestoring = false
    var errorMessage: String?

    init(api: APIClient) {
        self.api = api
        website = BangumiWebLogin(api: api)
        #if DEBUG
        if ProcessInfo.processInfo.environment["BGMORI_GUEST_MODE"] == "1" { return }
        #endif
        token = Keychain.read("accessToken")
        issuedTokenName = UserDefaults.standard.string(forKey: "issuedTokenName")
        if let interval = UserDefaults.standard.object(forKey: "tokenExpiresAt") as? Double {
            expiresAt = Date(timeIntervalSince1970: interval)
        }
    }

    var isLoggedIn: Bool { token?.isEmpty == false }
    var displayName: String { user?.displayName ?? "用户" }
    var username: String? { user?.username }

    func restore() async {
        guard let token, !token.isEmpty else { return }
        guard expiresAt.map({ $0 > Date() }) ?? true else {
            signOut()
            errorMessage = "登录已过期，请重新登录"
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        await api.setToken(token)
        do { user = try await api.me() }
        catch APIError.unauthorized {
            signOut()
            errorMessage = "登录已失效，请重新登录"
        } catch { errorMessage = "暂时无法连接服务，已保留登录状态" }
    }

    func prepareLogin() async {
        guard !isLoadingCaptcha, !isSigningIn else { return }
        let id = loginID
        isLoadingCaptcha = true
        isCompletingLogin = false
        captchaData = nil
        errorMessage = nil
        defer { if id == loginID { isLoadingCaptcha = false } }
        do {
            let data = try await website.start(id: id)
            try Task.checkCancellation()
            if id == loginID { captchaData = data }
        } catch {
            if id == loginID, !Task.isCancelled { errorMessage = Self.message(for: error) }
        }
    }

    func signIn(email: String, password: String, captcha: String) async {
        guard !isSigningIn, !isLoadingCaptcha, captchaData != nil else { return }
        let id = loginID
        isSigningIn = true
        errorMessage = nil
        defer { if id == loginID { isSigningIn = false } }
        do {
            let credential = try await website.submit(id: id, email: email.trimmed, password: password, captcha: captcha.trimmed)
            try Task.checkCancellation()
            guard id == loginID else { return }
            try Keychain.store(credential.token, for: "accessToken")
            Keychain.delete("refreshToken")
            token = credential.token
            user = credential.user
            expiresAt = credential.expiresAt
            issuedTokenName = credential.name
            UserDefaults.standard.set(credential.name, forKey: "issuedTokenName")
            UserDefaults.standard.set(credential.expiresAt.timeIntervalSince1970, forKey: "tokenExpiresAt")
            await api.setToken(credential.token)
            await website.cancel(id: id)
            captchaData = nil
            isCompletingLogin = false
        } catch {
            guard id == loginID, !Task.isCancelled else { return }
            let message = Self.message(for: error)
            let signedIn = await website.hasWebsiteLogin(id: id)
            guard id == loginID, !Task.isCancelled else { return }
            isCompletingLogin = signedIn
            if !signedIn {
                // Captchas are single-use. Never retry a password POST automatically.
                captchaData = nil
                do {
                    let data = try await website.start(id: id)
                    if id == loginID, !Task.isCancelled { captchaData = data }
                } catch { /* The explicit reload button remains available. */ }
            }
            if id == loginID { errorMessage = message }
        }
    }

    func cancelLogin() {
        let id = loginID
        loginID = UUID()
        captchaData = nil
        isLoadingCaptcha = false
        isSigningIn = false
        isCompletingLogin = false
        errorMessage = nil
        Task { await website.cancel(id: id) }
    }

    func refreshIfNeeded() async {
        if isLoggedIn, let expiresAt, expiresAt <= Date() {
            signOut()
            errorMessage = "登录已过期，请重新登录"
        }
    }

    func signOut() {
        let previousToken = token
        let previousName = issuedTokenName
        token = nil
        user = nil
        expiresAt = nil
        issuedTokenName = nil
        cancelLogin()
        Keychain.delete("accessToken")
        Keychain.delete("refreshToken")
        UserDefaults.standard.removeObject(forKey: "tokenExpiresAt")
        UserDefaults.standard.removeObject(forKey: "issuedTokenName")
        Task {
            await api.setToken(nil)
            await api.clearCache()
            if let previousToken, let previousName { await website.revoke(token: previousToken, name: previousName) }
        }
    }

    private static func message(for error: Error) -> String {
        if let login = error as? BangumiLoginError { return login.localizedDescription }
        if let api = error as? APIError {
            switch api {
            case .rateLimited: return "请求过于频繁，请稍后重试"
            case .verificationRequired: return "官网需要额外验证，请稍后重试或查看官网"
            case .message(let message): return message
            default: break
            }
        }
        return "暂时无法完成登录，请检查网络后重试"
    }
}


extension AuthManager: LibraryAccountProviding {}
