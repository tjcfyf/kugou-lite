import UIKit
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var code: KugouQRCode?
    @State private var status = "正在生成二维码…"
    @State private var pollTask: Task<Void, Never>?
    @State private var vipText = "正在查询会员状态…"
    @State private var probeText = ""
    @State private var probing = false

    var body: some View {
        NavigationView {
            VStack(spacing: 22) {
                if auth.isLoggedIn {
                    loggedInContent
                } else {
                    qrContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("酷狗账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if !auth.isLoggedIn { loadQR() }
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    // MARK: - Logged in

    private var loggedInContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 62))
                .foregroundColor(Theme.accent)
            Text("已登录")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text("UID \(auth.userid)")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
            Text(vipText)
                .font(.system(size: 13))
                .foregroundColor(Theme.accent)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    Task { vipText = await KGUser.vipText() ?? "未登录" }
                } label: {
                    Text("刷新会员状态")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }

                Button {
                    guard !probing else { return }
                    probing = true
                    Task {
                        probeText = await KGVIP.probeReport()
                        probing = false
                    }
                } label: {
                    Text(probing ? "诊断中…" : "诊断领取")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .padding(.top, 2)

            if !probeText.isEmpty {
                Text(probeText)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Theme.card)
                    .cornerRadius(8)
            }

            Button {
                auth.signOut()
                player.showToast("已退出登录")
                loadQR()
            } label: {
                Text("退出登录")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
            }
            .padding(.top, 8)
        }
        .task(id: auth.userid) {
            if auth.isLoggedIn {
                vipText = await KGUser.vipText() ?? "未获取到会员信息"
            }
        }
    }

    // MARK: - QR

    private var qrContent: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 232, height: 232)

                if let image = code?.image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 208, height: 208)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                }
            }

            Text(status)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("打开酷狗 App → 我的 → 扫一扫\n扫码后手机上确认登录")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                loadQR()
            } label: {
                Text("刷新二维码")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
            }
        }
        .padding(.horizontal, 28)
    }

    private func loadQR() {
        pollTask?.cancel()
        code = nil
        status = "正在生成二维码…"

        Task {
            do {
                let value = try await KGLogin.createQR()
                code = value
                status = "请用酷狗 App 扫码"
                startPolling(value.key)
            } catch {
                status = (error as? LocalizedError)?.errorDescription ?? "二维码生成失败，点下方刷新"
            }
        }
    }

    private func startPolling(_ key: String) {
        pollTask = Task {
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }

                guard let result = try? await KGLogin.check(key) else { continue }
                switch result.status {
                case 0:
                    status = "二维码已过期，请点刷新"
                    return
                case 2:
                    status = "已扫码，请在手机上确认"
                case 4:
                    if let token = result.token, let userid = result.userid {
                        auth.signIn(token: token, userid: userid, vipToken: result.vipToken)
                        status = "登录成功"
                        player.showToast("登录成功，正在注册设备…")
                        let deviceReply = await KGDevice.registerIfNeeded()
                        player.showToast(deviceReply)
                        player.showToast("正在领取今日会员…")

                        // 登录完成后立刻走一次概念版领会员。
                        let claim = await KGVIP.claimIfNeeded()
                        if claim == .claimed {
                            player.showToast("已自动领取今日会员")
                        } else if claim == .failed {
                            player.showToast("今日会员领取失败，下次播放会再试")
                        }
                        vipText = await KGUser.vipText() ?? "未获取到会员信息"

                        try? await Task.sleep(nanoseconds: 900_000_000)
                        dismiss()
                    }
                    return
                default:
                    break
                }
            }
            status = "二维码已过期，请点刷新"
        }
    }
}
