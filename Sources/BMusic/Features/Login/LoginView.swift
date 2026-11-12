#if os(macOS)
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var state: AppState

    @State private var ticket: QRLoginTicket?
    @State private var status: QRLoginStatus = .waiting
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var pollTask: Task<Void, Never>?
    @StateObject private var captchaFlow = GeeTestFlow()
    @State private var method: LoginMethod = .qr

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.account == nil ? "登录 B 站账号" : "账号")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    state.showLogin = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().opacity(0.5)

            if let account = state.account {
                loggedIn(account)
            } else {
                methodContent
            }
        }
        .frame(width: 410, height: 530)
        .background {
            ZStack {
                VisualEffectView(material: .popover, blending: .behindWindow)
                Theme.pageGradient
            }
            .ignoresSafeArea()
        }
        .overlay {
            GeeTestOverlay(flow: captchaFlow)
        }
        .onAppear {
            if state.account == nil { startLogin() }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
            captchaFlow.cancel()
        }
        .onChange(of: method) { _, newValue in
            if newValue == .qr {
                startLogin()
            } else {
                pollTask?.cancel()
                pollTask = nil
                ticket = nil
            }
        }
    }

    @ViewBuilder
    private var methodContent: some View {
        VStack(spacing: 0) {
            Picker("登录方式", selection: $method) {
                ForEach(LoginMethod.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 2)

            switch method {
            case .qr: qrContent
            case .sms:
                ScrollView(showsIndicators: false) {
                    SMSLoginForm(api: state.api, flow: captchaFlow) {
                        finishLogin()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            case .password:
                ScrollView(showsIndicators: false) {
                    PasswordLoginForm(api: state.api, flow: captchaFlow) {
                        finishLogin()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func finishLogin() {
        errorText = nil
        Task { @MainActor in
            await state.refreshAccount()
            if state.account != nil {
                ToastCenter.shared.success("登录成功")
                state.showLogin = false
            } else {
                ToastCenter.shared.show("登录 Cookie 已保存，但获取账号信息失败，请稍后重试")
            }
        }
    }

    // MARK: - QR

    private var qrContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Text("使用哔哩哔哩 App 扫码")
                    .font(.system(size: 14, weight: .semibold))
                Text("打开 App，点击右上角「扫一扫」")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white)
                    .frame(width: 228, height: 228)
                    .shadow(color: .black.opacity(0.10), radius: 14, y: 6)

                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                } else if let ticket {
                    QRCodeView(text: ticket.url)
                        .frame(width: 196, height: 196)
                        .opacity(status == .expired ? 0.16 : 1)
                        .blur(radius: status == .expired ? 2 : 0)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("二维码加载失败")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if status == .expired {
                    VStack(spacing: 9) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 22, weight: .medium))
                        Text("二维码已过期")
                            .font(.system(size: 11, weight: .medium))
                        Button("刷新二维码") { startLogin() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                } else if status == .scanned {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(Theme.mint)
                        Text("已扫码，请在手机上确认")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .frame(width: 228, height: 228)
            .padding(.top, 4)

            statusLine

            if let errorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(hex: 0xFF6B6B))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            VStack(alignment: .leading, spacing: 7) {
                Label("不会读取你的密码，也不使用钥匙串", systemImage: "lock.shield")
                Label("登录状态只保存在这台 Mac 的应用数据中", systemImage: "internaldrive")
                Label("随时可以在设置中退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
    }

    private var statusLine: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(status == .scanned ? Theme.mint : Theme.accent)
                .frame(width: 5, height: 5)
            Text(status == .scanned ? "等待手机确认…" : "等待扫码…")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Logged in

    private func loggedIn(_ account: Account) -> some View {
        VStack(spacing: 16) {
            CachedAsyncImage(url: account.avatarURL)
                .frame(width: 78, height: 78)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                .padding(.top, 28)

            VStack(spacing: 3) {
                Text(account.name)
                    .font(.system(size: 17, weight: .semibold))
                Text("Lv.\(account.level) · \(account.vipLabel.isEmpty ? "普通会员" : account.vipLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !account.sign.isEmpty {
                Text(account.sign)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            HStack(spacing: 30) {
                stat("关注", "\(account.following)")
                stat("粉丝", "\(account.follower)")
                stat("硬币", String(format: "%.1f", account.coins))
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .panelBackground(cornerRadius: 12)
            .padding(.horizontal, 24)

            Text("收藏夹已同步，可在音乐库中查看。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Spacer()

            HStack(spacing: 10) {
                Button("关闭") { state.showLogin = false }
                    .buttonStyle(SecondaryButtonStyle())
                Button("退出登录") {
                    state.logout()
                    state.showLogin = false
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.bottom, 22)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
    }

    // MARK: - Login flow

    private func startLogin() {
        pollTask?.cancel()
        isLoading = true
        errorText = nil
        status = .waiting
        ticket = nil

        pollTask = Task {
            do {
                let newTicket = try await state.api.qrGenerate()
                guard !Task.isCancelled else { return }
                ticket = newTicket
                isLoading = false
                await poll(newTicket)
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                errorText = error.localizedDescription
            }
        }
    }

    private func poll(_ ticket: QRLoginTicket) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            do {
                let result = try await state.api.qrPoll(key: ticket.key)
                guard !Task.isCancelled else { return }
                status = result.status
                switch result.status {
                case .success:
                    await state.refreshAccount()
                    ToastCenter.shared.success("登录成功")
                    state.showLogin = false
                    return
                case .expired:
                    return
                case .waiting, .scanned, .unknown:
                    continue
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = makeImage() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.black)
        }
    }

    private func makeImage() -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
#endif
