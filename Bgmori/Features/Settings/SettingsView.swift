import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var cacheSize = "计算中…"
    @State private var isClearing = false
    @State private var showConnections = false
    @State private var showReminders = false

    var body: some View {
        @Bindable var settings = app.settings

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                accountHeader

                settingsSection("外观") {
                    themeRow(settings)
                }

                settingsSection("网络") {
                    networkRow
                }

                settingsSection("内容") {
                    settingRow(
                        icon: "chart.bar.xaxis",
                        tint: .brandPink,
                        title: "显示观看进度",
                        subtitle: "在发现和我的页显示已看话数与进度条"
                    ) {
                        Toggle("显示观看进度", isOn: $settings.showWatchingProgress)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.brandPink)
                            .accessibilityIdentifier("settings-watching-progress")
                    }

                    rowDivider

                    settingRow(
                        icon: "character.book.closed.fill",
                        tint: .collectionTint(1),
                        title: "优先显示中文名",
                        subtitle: "标题优先使用中文名"
                    ) {
                        Toggle("优先显示中文名", isOn: $settings.preferChineseName)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.brandPink)
                    }

                    rowDivider

                    settingRow(
                        icon: "eye.slash.fill",
                        tint: .collectionTint(4),
                        title: "默认隐藏剧透",
                        subtitle: "简介与吐槽先折叠敏感内容"
                    ) {
                        Toggle("默认隐藏剧透", isOn: $settings.hideSpoilers)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.brandPink)
                    }

                    rowDivider

                    settingRow(
                        icon: "exclamationmark.triangle.fill",
                        tint: .collectionTint(2),
                        title: "显示 NSFW 内容",
                        subtitle: "搜索与条目详情中显示成人内容"
                    ) {
                        Toggle("显示 NSFW 内容", isOn: $settings.showNSFW)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.brandPink)
                    }
                }

                settingsSection("通知") {
                    Button { showReminders = true } label: {
                        settingRow(icon: "bell.badge.fill", tint: .brandPink, title: "追番提醒",
                                   subtitle: settings.dailyReminder ? "每日汇总、单番提醒与通知预览" : "未开启 · 仅提醒在看作品") {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reminder-settings")
                }

                settingsSection("存储") {
                    settingRow(
                        icon: "internaldrive.fill",
                        tint: Color(red: 0.50, green: 0.55, blue: 0.62),
                        title: "本地缓存",
                        subtitle: cacheSize
                    ) {
                        Button(isClearing ? "清理中…" : "清理") {
                            Task {
                                isClearing = true
                                await app.clearCaches()
                                cacheSize = await app.cacheSizeText()
                                isClearing = false
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.brandPink)
                        .disabled(isClearing)
                        .accessibilityIdentifier("settings-clear-cache")
                    }
                }

                aboutSection(settings)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 36)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color.bgmBackground)
        .navigationTitle("设置")
        .navigationDestination(isPresented: $showConnections) {
            ConnectionSettingsView()
                .environment(app)
        }
        .navigationDestination(isPresented: $showReminders) { ReminderSettingsView().environment(app) }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BGMORI_ROUTE"] == "reminders" { showReminders = true }
            #endif
            cacheSize = await app.cacheSizeText()
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        #endif
    }

    // MARK: - Account

    private var accountHeader: some View {
        HStack(spacing: 14) {
            AvatarView(url: app.auth.user?.avatarURL, size: 58)
                .overlay {
                    Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.auth.user?.displayName ?? "游客模式")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                if let username = app.auth.user?.username {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("登录后同步收藏与观看进度")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if app.auth.user != nil {
                Button("退出登录", role: .destructive) {
                    app.signOut()
                    dismiss()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .frame(minHeight: 36)
            } else {
                Button {
                    dismiss()
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        app.showLogin = true
                    }
                } label: {
                    Text("登录")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.bgmCanvas)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 30)
                        .background(Color.brandPink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-login")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Rows

    private func themeRow(_ settings: AppSettings) -> some View {
        settingRow(
            icon: "circle.lefthalf.filled",
            tint: .collectionTint(3),
            title: "主题",
            subtitle: nil
        ) {
            Menu {
                ForEach(AppAppearance.allCases) { appearance in
                    Button {
                        settings.appearance = appearance
                    } label: {
                        HStack {
                            Text(appearance.title)
                            if settings.appearance == appearance {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(settings.appearance.title)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .tint(.secondary)
            .accessibilityIdentifier("settings-appearance")
        }
    }

    private var networkRow: some View {
        Button {
            showConnections = true
        } label: {
            settingRow(
                icon: "network",
                tint: .collectionTint(1),
                title: "网络与连接",
                subtitle: "API、图片与网页线路"
            ) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("connection-settings")
    }

    private func settingRow<Trailing: View>(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            trailing()
        }
        #if os(macOS)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        #else
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        #endif
        .contentShape(Rectangle())
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 42)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
        }
    }

    // MARK: - About

    private func aboutSection(_ settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于软件")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            settingRow(
                icon: "info.circle.fill",
                tint: .collectionTint(5),
                title: "版本",
                subtitle: nil
            ) {
                Text(settings.appVersion)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            rowDivider

            Link(destination: URL(string: "https://bgm.tv")!) {
                settingRow(
                    icon: "link",
                    tint: .collectionTint(1),
                    title: "Bangumi",
                    subtitle: nil
                ) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            rowDivider

            Link(destination: URL(string: "https://bangumi.wiki")!) {
                settingRow(
                    icon: "server.rack",
                    tint: .collectionTint(2),
                    title: "镜像服务",
                    subtitle: "自动获取镜像地址"
                ) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("Bgmori 是非官方第三方客户端，与 Bangumi 官方无关联。所有条目、评分、评论版权归 Bangumi 及原作者所有。")
                Text("播放时刻由 bgmlist 提供，数据来自 bangumi-data（CC BY 4.0）。")
                Text("镜像仅用于数据、图片和网页访问；登录与收藏凭证只发送到官方或明确配置的自定义服务。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
            .padding(.horizontal, 4)
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
                         ? "有系统代理时优先通过代理连接官网；无代理时优先使用 ECH。连接失败后尝试其他可用线路，账号凭证只发往官网。"
                         : (draft.mode == .encrypted
                            ? "强制使用 ECH 并绑定实际网络接口，不经过 HTTP 代理或社区镜像。无法建立加密握手时直接报错。"
                            : "仅使用官方服务，有系统代理时优先使用代理，也支持 ECH 加密直连。"))
                        .font(.caption)
                        .foregroundStyle(Color.bgmMuted)
                }
                Toggle("加密 DNS（实验）", isOn: $draft.encryptedDNS)
                    .accessibilityIdentifier("connection-encrypted-dns")
                Text("此开关仅影响普通连接。ECH 直连会独立获取加密握手配置，不依赖服务域名的系统 DNS 解析。")
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
                    Text("只有服务器接受 ECH 并通过域名证书验证后才会显示已验证。账号登录也使用应用内官方直连，不需要打开浏览器。")
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
