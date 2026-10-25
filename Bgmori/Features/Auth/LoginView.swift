import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var manualToken = ""
    @State private var showManualToken = false
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        #if os(macOS)
        desktopLogin
        #else
        phoneLogin
        #endif
    }

    private var phoneLogin: some View {
        @Bindable var settings = app.settings
        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.91, green: 0.39, blue: 0.55), Color(red: 0.40, green: 0.29, blue: 0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 76)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                        Text("Bgmori")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("一个更轻、更快的 Bangumi 客户端")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("登录后可以同步收藏、评分、进度与吐槽；未登录也可以浏览放送表和条目。")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task {
                                isWorking = true
                                errorText = nil
                                await app.signIn()
                                isWorking = false
                                if app.auth.isLoggedIn { dismiss() }
                                else { errorText = app.auth.errorMessage }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.key")
                                Text("使用 Bangumi 登录")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                if isWorking { ProgressView().tint(.brandPink) }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.white)
                        .foregroundStyle(Color.brandPink)
                        .disabled(isWorking)

                        if !settings.hasOAuthConfig {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("还没有配置 OAuth 应用", systemImage: "info.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("在 bgm.tv/dev/app 创建一个应用，回调地址填 bgmori://oauth/callback，然后把 Client ID / Secret 填到下面。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)

                                TextField("Client ID", text: $settings.oauthClientID)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                SecureField("Client Secret", text: $settings.oauthClientSecret)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                TextField("回调地址", text: $settings.oauthRedirectURI)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .padding(12)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        DisclosureGroup(isExpanded: $showManualToken) {
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField("粘贴 Access Token", text: $manualToken)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("使用这个 Token") {
                                    Task {
                                        isWorking = true
                                        await app.signInWithToken(manualToken)
                                        isWorking = false
                                        if app.auth.isLoggedIn { dismiss() }
                                        else { errorText = app.auth.errorMessage }
                                    }
                                }
                                .buttonStyle(.glass)
                                .disabled(manualToken.trimmed.isEmpty || isWorking)
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("已有 Access Token")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .tint(.white)
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                    Button("先逛逛") { dismiss() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.bottom, 20)

                    Text("非官方客户端 · 数据来自 Bangumi")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
    #if os(macOS)
    private var desktopLogin: some View {
        @Bindable var settings = app.settings
        return VStack(spacing: 0) {
            HStack {
                Text("账户").font(.headline)
                Spacer()
                Button("完成", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("关闭")
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                            .resizable().frame(width: 64, height: 64)
                        Text("登录 Bgmori").font(.title.bold())
                        Text("同步你的收藏、评分与观看进度")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 0)
                    Group {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("OAuth 应用").font(.headline)
                                Spacer()
                                Link("创建应用 ↗", destination: URL(string: "https://bgm.tv/dev/app")!)
                                    .font(.caption)
                            }
                            Text("填入你在 Bangumi 创建的应用信息，即可继续登录。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                                GridRow {
                                    Text("Client ID").foregroundStyle(.secondary)
                                    TextField("Client ID", text: $settings.oauthClientID)
                                }
                                GridRow {
                                    Text("Client Secret").foregroundStyle(.secondary)
                                    SecureField("Client Secret", text: $settings.oauthClientSecret)
                                }
                                GridRow {
                                    Text("回调地址").foregroundStyle(.secondary)
                                    TextField("回调地址", text: $settings.oauthRedirectURI)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            Text("回调地址需与 Bangumi 开发者后台一致。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        Task {
                            isWorking = true
                            errorText = nil
                            await app.signIn()
                            isWorking = false
                            if app.auth.isLoggedIn { dismiss() }
                            else { errorText = app.auth.errorMessage }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isWorking { ProgressView().controlSize(.small) }
                            Text(isWorking ? "正在登录…" : "使用 Bangumi 登录")
                        }
                        .frame(width: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isWorking || !settings.hasOAuthConfig)
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DisclosureGroup("已有 Access Token", isExpanded: $showManualToken) {
                        HStack {
                            SecureField("粘贴 Access Token", text: $manualToken)
                                .textFieldStyle(.roundedBorder)
                            Button("登录") {
                                Task {
                                    isWorking = true
                                    errorText = nil
                                    await app.signInWithToken(manualToken)
                                    isWorking = false
                                    if app.auth.isLoggedIn { dismiss() }
                                    else { errorText = app.auth.errorMessage }
                                }
                            }
                            .disabled(manualToken.trimmed.isEmpty || isWorking)
                        }
                        .padding(.top, 10)
                    }
                    .font(.subheadline)
                    Text("无需登录，也可以浏览作品与每日放送。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("非官方客户端 · 数据来自 Bangumi")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("先逛逛") { dismiss() }
            }
            .padding(20)
        }
        .frame(width: 540, height: 660)
        .background(Color.bgmBackground)
    }
    #endif

}
