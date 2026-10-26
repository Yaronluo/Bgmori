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

    #if os(iOS)
    private var phoneLogin: some View {
        @Bindable var settings = app.settings
        return NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image("BrandIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08))
                            }
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                            .accessibilityHidden(true)

                        Text("登录 Bgmori")
                            .font(.title2.bold())
                        Text("同步你的收藏、评分与观看进度")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                Section {
                    credentialField("Client ID", text: $settings.oauthClientID)
                    credentialField("Client Secret", text: $settings.oauthClientSecret, secure: true)
                    credentialField("回调地址", text: $settings.oauthRedirectURI)
                    Link("创建 OAuth 应用 ↗", destination: URL(string: "https://bgm.tv/dev/app")!)
                        .font(.subheadline)
                } header: {
                    Text("OAuth 应用")
                } footer: {
                    Text("填入你在 Bangumi 创建的应用信息，即可继续登录。回调地址需与开发者后台一致。")
                }

                Section {
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
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.brandPink)
                    .disabled(isWorking || !settings.hasOAuthConfig)

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showManualToken) {
                        SecureField("粘贴 Access Token", text: $manualToken)
                            .font(.system(.body, design: .monospaced))
                        Button("使用这个 Token") {
                            Task {
                                isWorking = true
                                await app.signInWithToken(manualToken)
                                isWorking = false
                                if app.auth.isLoggedIn { dismiss() }
                                else { errorText = app.auth.errorMessage }
                            }
                        }
                        .disabled(manualToken.trimmed.isEmpty || isWorking)
                    } label: {
                        Label("已有 Access Token", systemImage: "key")
                    }
                }

                Section {
                    Button("先逛逛") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle("账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgmBackground)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func credentialField(_ title: String, text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField("必填", text: text)
                        .accessibilityLabel(title)
                } else {
                    TextField("必填", text: text)
                        .accessibilityLabel(title)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(.body, design: .monospaced))
        }
    }
    #endif

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
                    .buttonStyle(.glassProminent)
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
                }
                .padding(24)
            }
            Divider()
            HStack {
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
