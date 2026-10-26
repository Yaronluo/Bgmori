import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var cacheSize = "计算中…"
    @State private var isClearing = false

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section("账户") {
                if let user = app.auth.user {
                    HStack(spacing: 12) {
                        AvatarView(url: user.avatarURL, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.displayName)
                                .font(.headline)
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("退出登录", role: .destructive) {
                        app.signOut()
                        dismiss()
                    }
                } else {
                    Button("登录 Bangumi") {
                        dismiss()
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            app.showLogin = true
                        }
                    }
                }
            }

            Section("OAuth 应用") {
                TextField("Client ID", text: $settings.oauthClientID)
                    .textContentType(.username)
                SecureField("Client Secret", text: $settings.oauthClientSecret)
                TextField("回调地址", text: $settings.oauthRedirectURI)
                Link("打开 Bangumi 开发者平台", destination: URL(string: "https://bgm.tv/dev/app")!)
                    .font(.system(size: 13))
                Text("回调地址需要与开发者后台一致；默认使用 bgmori://oauth/callback。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.hasOAuthConfig {
                    Label("配置已就绪", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("外观") {
                Picker("主题", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("内容") {
                Toggle("优先显示中文名", isOn: $settings.preferChineseName)
                Toggle("默认隐藏剧透", isOn: $settings.hideSpoilers)
                Toggle("显示 NSFW 内容", isOn: $settings.showNSFW)
            }

            Section("通知") {
                Toggle("每日放送提醒", isOn: Binding(
                    get: { settings.dailyReminder },
                    set: { newValue in
                        Task {
                            if newValue {
                                _ = await app.enableDailyReminder()
                            } else {
                                settings.dailyReminder = false
                                await app.updateDailyReminder()
                            }
                        }
                    }
                ))
                Text("每天 20:00 提醒在看作品。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("缓存") {
                HStack {
                    Text("本地缓存")
                    Spacer()
                    Text(cacheSize)
                        .foregroundStyle(.secondary)
                }
                Button(isClearing ? "清理中…" : "清理缓存") {
                    Task {
                        isClearing = true
                        await app.clearCaches()
                        cacheSize = await app.cacheSizeText()
                        isClearing = false
                    }
                }
                .disabled(isClearing)
            }

            Section("关于软件") {
                LabeledContent("版本", value: settings.appVersion)
                Link("Bangumi", destination: URL(string: "https://bgm.tv")!)
                Text("Bgmori 是非官方第三方客户端，与 Bangumi 官方无关联。所有条目、评分、评论版权归 Bangumi 及原作者所有。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("镜像服务", destination: URL(string: "https://bangumi.wiki")!)
                Text("通过 bangumi.wiki 自动获取镜像地址，用于数据、图片和网页访问。登录及收藏请求也会经过所用镜像。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .task {
            cacheSize = await app.cacheSizeText()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
            }
        }
    }
}
