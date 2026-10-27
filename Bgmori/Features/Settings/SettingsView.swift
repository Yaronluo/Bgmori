import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var cacheSize = "计算中…"
    @State private var isClearing = false
    @State private var showConnections = false

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

            Section("网络") {
                Button("网络与连接", systemImage: "network") { showConnections = true }
                    .accessibilityIdentifier("connection-settings")
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
                Text("通过 bangumi.wiki 自动获取镜像地址，用于数据、图片和网页访问。公开浏览失败时可自动回退。登录与收藏凭证仅发送到官方或明确配置的自定义服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .navigationDestination(isPresented: $showConnections) {
            ConnectionSettingsView()
                .environment(app)
        }
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


struct ConnectionSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MirrorRouting.shared.settings
    @State private var applied = MirrorRouting.shared.settings
    @State private var events: [ConnectionEvent] = []
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                Picker("连接方式", selection: $draft.mode) {
                    ForEach(ConnectionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("connection-mode")
                if draft.mode == .custom {
                    TextField("反代根域名，如 mirror.example.com", text: $draft.customRoot)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .accessibilityIdentifier("connection-custom-root")
                    Text("填写你信任的通配反代根域名，API、图片和网页会使用对应子域名。账号请求也会经过此服务。")
                        .font(.caption)
                        .foregroundStyle(Color.bgmMuted)
                } else {
                    Text(draft.mode == .automatic
                         ? "优先通过 ECH 加密直连官网，失败后尝试普通官网连接及镜像。账号凭证只发往官网。"
                         : (draft.mode == .encrypted
                            ? "强制使用 ECH 并绑定实际网络接口，不经过 HTTP 代理或社区镜像。无法建立加密握手时直接报错。"
                            : "仅使用 Bangumi 官方服务，可使用 ECH 加密直连或系统普通连接。"))
                        .font(.caption)
                        .foregroundStyle(Color.bgmMuted)
                }
                Toggle("加密 DNS（实验）", isOn: $draft.encryptedDNS)
                    .accessibilityIdentifier("connection-encrypted-dns")
                Text("此开关仅影响普通连接。ECH 直连会独立获取加密握手配置，不依赖 Bangumi 的系统 DNS 解析。")
                    .font(.caption)
                    .foregroundStyle(Color.bgmMuted)
                Button(isSaving ? "正在保存…" : "保存连接设置") {
                    Task {
                        isSaving = true
                        errorText = nil
                        do {
                            try await app.applyConnectionSettings(draft)
                            applied = MirrorRouting.shared.settings
                            draft = applied
                            events = MirrorRouting.shared.diagnostics
                        } catch {
                            errorText = "请填写有效的 HTTPS 根域名，不包含路径、端口或账号信息。"
                        }
                        isSaving = false
                    }
                }
                .disabled(isSaving || app.isCheckingConnections || draft == applied)
                .accessibilityIdentifier("connection-save")
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(Color.brandPink)
                }
            } header: { Text("连接方式") }

            Section("当前连接") {
                ForEach(ConnectionService.allCases, id: \.self) { service in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(service.title)
                            Spacer()
                            Text(events.first { $0.service == service }?.result ?? "尚未连接")
                                .foregroundStyle(Color.bgmMuted)
                        }
                        if let event = events.first(where: { $0.service == service }) {
                            Text("\(event.host) · \(event.milliseconds) ms")
                                .font(.caption)
                                .foregroundStyle(Color.bgmMuted)
                                .textSelection(.enabled)
                        }
                    }
                    .accessibilityIdentifier("connection-status-\(service.rawValue)")
                }
                Button {
                    Task {
                        await app.checkConnections()
                        events = MirrorRouting.shared.diagnostics
                    }
                } label: {
                    HStack {
                        Text(app.isCheckingConnections ? "正在检测…" : "重新检测")
                        if app.isCheckingConnections { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(app.isCheckingConnections || isSaving || draft != applied)
                .accessibilityIdentifier("connection-recheck")
                if let summary = app.connectionCheckSummary {
                    Text(summary).font(.caption).foregroundStyle(Color.bgmMuted)
                        .accessibilityIdentifier("connection-check-summary")
                }
                if draft != applied {
                    Text("保存设置后可重新检测。")
                        .font(.caption).foregroundStyle(Color.bgmMuted)
                }
            }

            Section("连接诊断") {
                DisclosureGroup("最近的连接记录") {
                    if events.isEmpty {
                        Text("还没有连接记录，缓存命中时不会产生新请求。")
                            .foregroundStyle(Color.bgmMuted)
                    }
                    ForEach(Array(events.prefix(12))) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(event.service.title) · \(event.host)")
                                .lineLimit(2)
                            HStack {
                                Text(event.result)
                                Spacer()
                                Text("\(event.milliseconds) ms")
                                Text(event.date, style: .time)
                            }
                            .font(.caption)
                            .foregroundStyle(Color.bgmMuted)
                        }
                    }
                }
                Text("仅记录服务域名、结果与耗时，不记录完整访问地址或登录凭证。")
                    .font(.caption).foregroundStyle(Color.bgmMuted)
                DisclosureGroup("ECH 加密直连状态") {
                    #if BGMORI_ECH
                    if let info = ECHTransport.info {
                        LabeledContent("已验证握手", value: "\(info.acceptedConnections) 次")
                        LabeledContent("直连接口", value: info.directInterface.isEmpty ? "尚未连接" : info.directInterface)
                        LabeledContent("ECH 配置", value: info.configReady ? "已取得" : "首次连接时获取")
                    }
                    Text("只有服务器接受 ECH 并通过域名证书验证后才会显示已验证。外部浏览器的授权网页使用浏览器自己的网络；无法打开时可使用已有 Access Token 登录。")
                        .font(.caption).foregroundStyle(Color.bgmMuted)
                    #else
                    Text("此构建没有包含 ECH 连接库。")
                        .font(.caption).foregroundStyle(Color.bgmMuted)
                    #endif
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("网络与连接")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .task {
            while !Task.isCancelled {
                events = MirrorRouting.shared.diagnostics
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }
}
