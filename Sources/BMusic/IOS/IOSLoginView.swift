#if os(iOS)
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct IOSLoginView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var ticket: QRLoginTicket?
    @State private var qrImage: UIImage?
    @State private var status: QRLoginStatus = .waiting
    @State private var errorText: String?
    @State private var secondsLeft = 180
    @State private var pollTask: Task<Void, Never>?
    @State private var countdownTask: Task<Void, Never>?
    @StateObject private var captchaFlow = GeeTestFlow()
    @State private var method: LoginMethod = .qr

    var body: some View {
        NavigationStack {
            ZStack {
                IOSBackdrop()
                ScrollView {
                    VStack(spacing: 18) {
                        Picker("登录方式", selection: $method) {
                            ForEach(LoginMethod.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Theme.accent)
                        .padding(.top, 6)

                        switch method {
                        case .qr: qrContent
                        case .sms:
                            SMSLoginForm(api: state.api, flow: captchaFlow) {
                                finishLogin()
                            }
                        case .password:
                            PasswordLoginForm(api: state.api, flow: captchaFlow) {
                                finishLogin()
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay {
                GeeTestOverlay(flow: captchaFlow)
            }
            .task { await start() }
            .onDisappear {
                pollTask?.cancel()
                countdownTask?.cancel()
                captchaFlow.cancel()
            }
            .onChange(of: method) { _, newValue in
                if newValue == .qr {
                    restart()
                } else {
                    pollTask?.cancel()
                    countdownTask?.cancel()
                    ticket = nil
                    qrImage = nil
                }
            }
        }
    }

    @ViewBuilder
    private var qrContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Text("扫码登录")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("使用哔哩哔哩 App 扫描二维码")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            qrCard

            statusPill

            Button {
                restart()
            } label: {
                Label("刷新二维码", systemImage: "arrow.clockwise")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)

            VStack(alignment: .leading, spacing: 7) {
                Label("登录后可同步收藏夹、关注 UP 主与云端歌单", systemImage: "person.2")
                Label("仅保存登录 Cookie，不读取账号密码", systemImage: "lock.shield")
                Label("BMusic 为非官方客户端，与哔哩哔哩无隶属关系", systemImage: "info.circle")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private func finishLogin() {
        errorText = nil
        Task { @MainActor in
            await state.refreshAccount()
            if state.account != nil {
                ToastCenter.shared.success("登录成功")
                dismiss()
            } else {
                ToastCenter.shared.show("登录 Cookie 已保存，但获取账号信息失败，请稍后重试")
            }
        }
    }

    private var qrCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white)
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                    if status == .expired {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.black.opacity(0.62))
                        VStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 24, weight: .light))
                            Text("二维码已过期")
                                .font(.system(size: 13, weight: .semibold))
                            Button("点击刷新") { restart() }
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                        .foregroundStyle(.white)
                    }
                } else if errorText != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 24, weight: .light))
                        Text("二维码加载失败")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 236, height: 236)
            .shadow(color: .black.opacity(0.13), radius: 18, y: 8)

            Text(secondsLeft > 0 ? "二维码 \(secondsLeft) 秒后过期" : "二维码已过期")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(statusColor.opacity(0.10), in: Capsule())
        .foregroundStyle(statusColor)
    }

    private var statusText: String {
        if let errorText { return errorText }
        switch status {
        case .waiting: return "等待扫码"
        case .scanned: return "已扫码，请在手机确认"
        case .success: return "登录成功"
        case .expired: return "二维码已过期"
        case .unknown: return "等待确认"
        }
    }

    private var statusColor: Color {
        if errorText != nil { return .red }
        switch status {
        case .success: return Theme.mint
        case .scanned: return Theme.blue
        case .expired: return .orange
        default: return Theme.accent
        }
    }

    private func start() async {
        errorText = nil
        status = .waiting
        secondsLeft = 180
        do {
            let generated = try await state.api.qrGenerate()
            ticket = generated
            qrImage = Self.makeQRCode(generated.url)
            startCountdown()
            startPolling(key: generated.key)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func restart() {
        pollTask?.cancel()
        countdownTask?.cancel()
        ticket = nil
        qrImage = nil
        Task { await start() }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task {
            while !Task.isCancelled, secondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                secondsLeft = max(0, secondsLeft - 1)
                if secondsLeft == 0 {
                    status = .expired
                    pollTask?.cancel()
                    return
                }
            }
        }
    }

    private func startPolling(key: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                do {
                    let result = try await state.api.qrPoll(key: key)
                    status = result.status
                    if result.status == .success {
                        await state.refreshAccount()
                        ToastCenter.shared.success("登录成功")
                        dismiss()
                        return
                    }
                    if result.status == .expired {
                        return
                    }
                } catch {
                    errorText = error.localizedDescription
                    return
                }
            }
        }
    }

    private static func makeQRCode(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
