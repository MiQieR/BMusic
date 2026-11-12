import SwiftUI
import WebKit

/// 极验人机验证流程：拉取 challenge → WebView 弹窗验证 → 结果回传登录接口。
@MainActor
final class GeeTestFlow: ObservableObject {
    @Published private(set) var challenge: GeeTestChallenge?
    @Published private(set) var message: String?
    private var continuation: ((Result<GeeTestResult, Error>) -> Void)?

    var isActive: Bool { challenge != nil }

    /// 请求一次人机验证；结果（含 token）通过 completion 返回。
    func verify(api: BiliAPI, _ completion: @escaping (Result<GeeTestResult, Error>) -> Void) {
        cancel()
        message = nil
        Task {
            do {
                let challenge = try await api.loginCaptcha()
                continuation = completion
                self.challenge = challenge
            } catch {
                completion(.failure(error))
            }
        }
    }

    func finish(_ result: GeeTestResult) {
        challenge = nil
        let handler = continuation
        continuation = nil
        handler?(.success(result))
    }

    func fail(_ text: String) {
        challenge = nil
        message = text
        let handler = continuation
        continuation = nil
        handler?(.failure(BiliError.unavailable(text)))
    }

    func cancel() {
        guard challenge != nil || continuation != nil else {
            message = nil
            return
        }
        challenge = nil
        let handler = continuation
        continuation = nil
        handler?(.failure(BiliError.cancelled))
    }
}

/// WebView 承载的极验验证（gt.js v3，bind 形态）。macOS / iOS 共用。
struct GeeTestOverlay: View {
    @ObservedObject var flow: GeeTestFlow

    var body: some View {
        Group {
            if let challenge = flow.challenge {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("安全验证")
                                .font(.system(size: 14, weight: .semibold))
                            Text("完成验证后继续登录")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("取消") { flow.cancel() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    GeeTestWebView(challenge: challenge) { result in
                        flow.finish(result)
                    } onError: { text in
                        flow.fail(text)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 348, height: 470)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 26, y: 12)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: flow.challenge)
    }
}

#if os(macOS)
private struct GeeTestWebView: NSViewRepresentable {
    let challenge: GeeTestChallenge
    let onSuccess: (GeeTestResult) -> Void
    let onError: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.configuration.userContentController.add(context.coordinator, name: "geetest")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        let identity = "\(challenge.gt)#\(challenge.challenge)"
        if context.coordinator.loaded != identity {
            context.coordinator.loaded = identity
            view.loadHTMLString(Self.html(challenge), baseURL: URL(string: "https://www.bilibili.com"))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: GeeTestWebView
        var loaded = ""

        init(_ parent: GeeTestWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "geetest", let body = message.body as? [String: Any] else { return }
            let validate = body.string("validate")
            let error = body.string("error")
            if !validate.isEmpty {
                parent.onSuccess(GeeTestResult(
                    token: parent.challenge.token,
                    challenge: body.string("challenge").isEmpty ? parent.challenge.challenge : body.string("challenge"),
                    validate: validate,
                    seccode: body.string("seccode")
                ))
            } else if !error.isEmpty {
                parent.onError(error)
            }
        }
    }

    static func html(_ challenge: GeeTestChallenge) -> String {
        let gt = challenge.gt
        let id = challenge.challenge
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
        <style>body{margin:0;padding:0;background:transparent;font-family:-apple-system,'PingFang SC',sans-serif;display:flex;align-items:center;justify-content:center;height:100vh}</style>
        <script src="https://static.geetest.com/static/js/gt.js"></script></head>
        <body><div id="cap"></div><script>
        var gt = "\(gt)", challenge = "\(id)";
        initGeetest({gt: gt, challenge: challenge, offline: false, new_captcha: true, product: "bind", protocol: "https"}, function (cap) {
          cap.onReady(function () { cap.verify(); });
          cap.onSuccess(function () {
            var r = cap.getValidate();
            if (r) { window.webkit.messageHandlers.geetest.postMessage({challenge: r.geetest_challenge, validate: r.geetest_validate, seccode: r.geetest_seccode}); }
          });
          cap.onError(function (e) { window.webkit.messageHandlers.geetest.postMessage({error: (e && e.msg) ? e.msg : "人机验证组件加载失败，请重试"}); });
          cap.onClose(function () { window.webkit.messageHandlers.geetest.postMessage({error: "人机验证已关闭，请重试"}); });
        });
        </script></body></html>
        """
    }
}
#else
private struct GeeTestWebView: UIViewRepresentable {
    let challenge: GeeTestChallenge
    let onSuccess: (GeeTestResult) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.configuration.userContentController.add(context.coordinator, name: "geetest")
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        let identity = "\(challenge.gt)#\(challenge.challenge)"
        if context.coordinator.loaded != identity {
            context.coordinator.loaded = identity
            view.loadHTMLString(Self.html(challenge), baseURL: URL(string: "https://www.bilibili.com"))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: GeeTestWebView
        var loaded = ""

        init(_ parent: GeeTestWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "geetest", let body = message.body as? [String: Any] else { return }
            let validate = body.string("validate")
            let error = body.string("error")
            if !validate.isEmpty {
                parent.onSuccess(GeeTestResult(
                    token: parent.challenge.token,
                    challenge: body.string("challenge").isEmpty ? parent.challenge.challenge : body.string("challenge"),
                    validate: validate,
                    seccode: body.string("seccode")
                ))
            } else if !error.isEmpty {
                parent.onError(error)
            }
        }
    }

    static func html(_ challenge: GeeTestChallenge) -> String {
        let gt = challenge.gt
        let id = challenge.challenge
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
        <style>body{margin:0;padding:0;background:transparent;font-family:-apple-system,'PingFang SC',sans-serif;display:flex;align-items:center;justify-content:center;height:100vh}</style>
        <script src="https://static.geetest.com/static/js/gt.js"></script></head>
        <body><div id="cap"></div><script>
        var gt = "\(gt)", challenge = "\(id)";
        initGeetest({gt: gt, challenge: challenge, offline: false, new_captcha: true, product: "bind", protocol: "https"}, function (cap) {
          cap.onReady(function () { cap.verify(); });
          cap.onSuccess(function () {
            var r = cap.getValidate();
            if (r) { window.webkit.messageHandlers.geetest.postMessage({challenge: r.geetest_challenge, validate: r.geetest_validate, seccode: r.geetest_seccode}); }
          });
          cap.onError(function (e) { window.webkit.messageHandlers.geetest.postMessage({error: (e && e.msg) ? e.msg : "人机验证组件加载失败，请重试"}); });
          cap.onClose(function () { window.webkit.messageHandlers.geetest.postMessage({error: "人机验证已关闭，请重试"}); });
        });
        </script></body></html>
        """
    }
}
#endif
