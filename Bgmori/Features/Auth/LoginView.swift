import ImageIO
import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var captcha = ""
    @State private var action: Task<Void, Never>?
    @FocusState private var focus: Field?
    private enum Field { case email, password, captcha }

    private var busy: Bool { app.auth.isSigningIn || app.auth.isLoadingCaptcha }
    private var canSubmit: Bool {
        !busy && app.auth.captchaData != nil
            && (app.auth.isCompletingLogin || !email.trimmed.isEmpty && !password.isEmpty && !captcha.trimmed.isEmpty)
    }
    private var captchaImage: CGImage? {
        guard let data = app.auth.captchaData,
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 14) {
                        Image("BrandIcon")
                            .resizable().scaledToFit().frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("登录").font(.title2.bold())
                            Text("同步你的收藏、评分与观看进度")
                                .font(.subheadline).foregroundStyle(Color.bgmMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("邮箱")
                                TextField("Bangumi 邮箱", text: $email)
                                    .textContentType(.username)
                                    .focused($focus, equals: .email)
                                    .accessibilityIdentifier("login-email")
                                    #if os(iOS)
                                        .keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                    #endif
                                    .autocorrectionDisabled()
                            }
                            .padding(16)
                            Divider().padding(.horizontal, 16)
                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("密码")
                                SecureField("输入密码", text: $password)
                                    .textContentType(.password)
                                    .focused($focus, equals: .password)
                                    .accessibilityIdentifier("login-password")
                            }
                            .padding(16)
                            Divider().padding(.horizontal, 16)
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    fieldLabel("验证码")
                                    TextField("输入图片中的字符", text: $captcha)
                                        .focused($focus, equals: .captcha)
                                        .accessibilityIdentifier("login-captcha")
                                        #if os(iOS)
                                            .textInputAutocapitalization(.never)
                                        #endif
                                        .autocorrectionDisabled()
                                }
                                Button(action: reloadCaptcha) {
                                    Group {
                                        if let image = captchaImage {
                                            Image(decorative: image, scale: 1).resizable().scaledToFit()
                                        } else if app.auth.isLoadingCaptcha {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Label("重新获取", systemImage: "arrow.clockwise").font(.caption)
                                        }
                                    }
                                    .frame(width: 124, height: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(app.auth.captchaData == nil ? "获取验证码" : "更换验证码")
                                .accessibilityIdentifier("login-captcha-image")
                                .disabled(busy)
                            }
                            .padding(16)
                            .accessibilityElement(children: .contain)
                        }
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.leading)
                        .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bgmSecondary, lineWidth: 1)
                        }
                        .disabled(app.auth.isSigningIn || app.auth.isCompletingLogin)
                        Text("点击图片更换验证码。邮箱和密码仅用于本次登录，不会保存。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    if let error = app.auth.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("login-error")
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if app.auth.isSigningIn { ProgressView().controlSize(.small) }
                            Text(app.auth.isSigningIn ? "正在登录…" : app.auth.isCompletingLogin ? "重试登录" : "登录并同步")
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .controlSize(.large)
                    .tint(.brandPink)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("login-submit")
                    #if os(macOS)
                        .keyboardShortcut(.defaultAction)
                    #endif
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bgmBackground)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("账户")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { close() }
                        .accessibilityIdentifier("login-close")
                }
            }
            .onSubmit {
                switch focus {
                case .email: focus = .password
                case .password: focus = .captcha
                default: if canSubmit { submit() }
                }
            }
            .task { await app.auth.prepareLogin() }
            .onDisappear {
                action?.cancel()
                password = ""
                captcha = ""
                app.auth.cancelLogin()
            }
        }
        #if os(macOS)
            .frame(width: 480, height: 580)
        #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
    }

    private func reloadCaptcha() {
        guard !busy else { return }
        captcha = ""
        action = Task { await app.auth.prepareLogin() }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        action = Task {
            await app.signIn(email: email, password: password, captcha: captcha)
            guard !Task.isCancelled else { return }
            captcha = ""
            if app.auth.isCompletingLogin { password = "" }
            if app.auth.isLoggedIn {
                password = ""
                dismiss()
            }
        }
    }

    private func close() {
        action?.cancel()
        password = ""
        captcha = ""
        dismiss()
    }
}
