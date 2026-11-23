import SwiftUI

/// QQ App 直登：不生成二维码，直接拉起手机 QQ 的授权确认页。
/// QQ SDK 返回 access_token/openid 后，交给酷狗概念版 /v6/login_by_openplat 换 KuGoo。
struct QQAppLoginView: View {
    let onLogin: (String, Int, String?) -> Void
    let onFailure: (String) -> Void

    @State private var status = "正在打开 QQ…"
    @State private var hasStarted = false
    @State private var showDebug = false
    @State private var debugAvailable = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(ThirdPartyProvider.qq.tint.opacity(0.14))
                        .frame(width: 88, height: 88)
                    Text("QQ")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(ThirdPartyProvider.qq.tint)
                }

                Text("在 QQ 里确认登录")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.text)

                Text("不再扫码。点击下方按钮会直接打开手机 QQ，在 QQ 的授权页点“确认登录”，完成后自动回到 Sonora。")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 30)

                Button {
                    start()
                } label: {
                    Text("打开 QQ 授权")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(ThirdPartyProvider.qq.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 30)
                .disabled(status == "正在换登录态…")

                Text(status)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.tertiaryText)

                if debugAvailable {
                    Button("查看登录日志") { showDebug = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ThirdPartyProvider.qq.tint)
                }

                Spacer()
            }
            .padding(.vertical, 40)
        }
        .sheet(isPresented: $showDebug) { LoginDebugView() }
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            // 进入页面就拉起 QQ，减少一次无意义点击；用户取消后仍可用按钮重试。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if status == "正在打开 QQ…" { start() }
            }
        }
    }

    private func start() {
        status = "正在打开 QQ…"
        let watchdog = status
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            if status == watchdog {
                status = "QQ 没有响应。请确认已安装手机 QQ，再点一次重试"
            }
        }
        QQSDKLogin.shared().start { accessToken, openid, error in
            DispatchQueue.main.async {
                if let error, !error.isEmpty {
                    status = error
                    onFailure(error)
                    return
                }
                guard let accessToken, !accessToken.isEmpty,
                      let openid, !openid.isEmpty else {
                    let message = "QQ 没有返回 access_token 或 openid"
                    status = message
                    onFailure(message)
                    return
                }

                status = "正在换登录态…"
                Task {
                    do {
                        let result = try await KGLogin.loginByOpenPlat(accessToken: accessToken, openid: openid)
                        await MainActor.run {
                            onLogin(result.token, result.userid, result.vipToken)
                        }
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription ?? "QQ 登录失败"
                        LoginDebug.shared.add("exchange error: \(message)")
                        await MainActor.run {
                            status = message
                            debugAvailable = true
                            onFailure(message)
                        }
                    }
                }
            }
        }
    }
}
