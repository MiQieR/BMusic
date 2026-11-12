import SwiftUI

/// 登录页的三种方式：扫码、短信、账号密码。
enum LoginMethod: String, CaseIterable, Identifiable {
    case qr, sms, password

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qr: return "扫码登录"
        case .sms: return "短信登录"
        case .password: return "密码登录"
        }
    }
}

import SwiftUI

/// 短信验证码登录表单。获取验证码前先过一次极验人机验证。
struct SMSLoginForm: View {
    let api: BiliAPI
    @ObservedObject var flow: GeeTestFlow
    var onSuccess: () -> Void

    @State private var countries: [CountryRegion] = CountryRegion.fallback
    @State private var country: CountryRegion = CountryRegion.fallback[0]
    @State private var phone = ""
    @State private var code = ""
    @State private var captchaKey = ""
    @State private var busy = false
    @State private var countdown = 0
    @State private var errorText: String?
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("短信登录")
                    .font(.system(size: 14, weight: .semibold))
                Text("使用手机号接收验证码")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(countries) { item in
                    Button("\(item.name) +\(item.dialCode)") {
                        country = item
                    }
                }
            } label: {
                HStack {
                    Text("\(country.name) +\(country.dialCode)")
                        .font(.system(size: 12.5))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            #if os(macOS)
            .menuStyle(.button)
            .menuIndicator(.visible)
            #endif
            .tint(Theme.accent)

            LoginTextField("手机号", text: $phone)
            #if os(iOS)
                .keyboardType(.phonePad)
            #endif

            HStack(spacing: 8) {
                LoginTextField("验证码", text: $code)
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
                Button {
                    requestSMSCode()
                } label: {
                    Group {
                        if countdown > 0 {
                            Text("\(countdown) 秒后重发")
                        } else if captchaKey.isEmpty {
                            Text("获取验证码")
                        } else {
                            Text("重新发送")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(
                        Capsule().fill(Theme.accent.opacity(countdown > 0 || busy ? 0.10 : 0.14))
                    )
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(busy || countdown > 0 || phone.trimmingCharacters(in: .whitespaces).count < 5)
                .opacity(busy || countdown > 0 || phone.trimmingCharacters(in: .whitespaces).count < 5 ? 0.6 : 1)
            }

            Button {
                submit()
            } label: {
                Group {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("登录")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .disabled(busy || code.isEmpty || captchaKey.isEmpty)
            .opacity(code.isEmpty || captchaKey.isEmpty ? 0.6 : 1)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(hex: 0xFF6B6B))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Text("发送验证码时会弹出极验人机验证；登录 Cookie 仅保存在本机。")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            countries = await api.loginCountries()
            if let first = countries.first, country == CountryRegion.fallback[0] {
                country = first
            }
        }
        .onDisappear { countdownTask?.cancel() }
    }

    private func requestSMSCode() {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5 else {
            errorText = "请输入正确的手机号"
            return
        }
        busy = true
        errorText = nil
        flow.verify(api: api) { [api] result in
            Task { @MainActor in
                switch result {
                case .success(let captcha):
                    do {
                        let key = try await api.sendSMSCode(country: country, phone: trimmed, captcha: captcha)
                        captchaKey = key
                        errorText = nil
                        startCountdown()
                    } catch {
                        errorText = error.localizedDescription
                    }
                    busy = false
                case .failure(let error):
                    if !flow.isActive {
                        if case BiliError.cancelled = error {
                            errorText = nil
                        } else {
                            errorText = error.localizedDescription
                        }
                    }
                    busy = false
                }
            }
        }
    }

    private func submit() {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmedCode.isEmpty, !captchaKey.isEmpty else { return }
        busy = true
        errorText = nil
        Task { @MainActor in
            do {
                try await api.loginBySMS(
                    country: country,
                    phone: trimmed,
                    code: trimmedCode,
                    captchaKey: captchaKey
                )
                onSuccess()
            } catch {
                errorText = error.localizedDescription
                busy = false
            }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task {
            while !Task.isCancelled, countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                countdown = max(0, countdown - 1)
            }
        }
    }
}

/// 账号密码登录表单。密码经 RSA-PKCS1 加密后提交，不在本机留存。
struct PasswordLoginForm: View {
    let api: BiliAPI
    @ObservedObject var flow: GeeTestFlow
    var onSuccess: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("密码登录")
                    .font(.system(size: 14, weight: .semibold))
                Text("支持手机号或邮箱账号")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LoginTextField("手机号 / 邮箱", text: $username)

            LoginSecureField("密码", text: $password)

            Button {
                submit()
            } label: {
                Group {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("登录")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .disabled(busy || username.isEmpty || password.isEmpty)
            .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(hex: 0xFF6B6B))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Text("提交前需完成极验人机验证；若提示环境异常，请改用扫码或短信登录。密码加密后提交，BMusic 不保存它。")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func submit() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !password.isEmpty else { return }
        busy = true
        errorText = nil
        flow.verify(api: api) { [api] result in
            Task { @MainActor in
                switch result {
                case .success(let captcha):
                    do {
                        try await api.loginByPassword(username: name, password: password, captcha: captcha)
                        onSuccess()
                    } catch {
                        errorText = error.localizedDescription
                        busy = false
                    }
                case .failure(let error):
                    if !flow.isActive {
                        if case BiliError.cancelled = error {
                            errorText = nil
                        } else {
                            errorText = error.localizedDescription
                        }
                    }
                    busy = false
                }
            }
        }
    }
}

/// 共用的圆角输入框，macOS / iOS 样式一致。
struct LoginTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }
}

struct LoginSecureField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
