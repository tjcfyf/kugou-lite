import UIKit
import SwiftUI

private enum LoginMethod: String, CaseIterable, Identifiable, Equatable {
    case phone
    case qr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: return "手机号登录"
        case .qr: return "扫码登录"
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var method: LoginMethod = .phone
    @State private var code: KugouQRCode?
    @State private var status = "正在生成二维码…"
    @State private var pollTask: Task<Void, Never>?
    @State private var vipText = "正在查询会员状态…"
    @State private var probeText = ""
    @State private var probing = false

    // 手机号登录
    @State private var phone = ""
    @State private var verifyCode = ""
    @State private var countdown = 0
    @State private var sendingCode = false
    @State private var loggingIn = false
    @State private var loginError = ""
    @State private var smsNotice = ""
    @State private var thirdParty: ThirdPartyProvider?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case phone
        case code
    }

    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    if auth.isLoggedIn {
                        loggedInContent
                    } else {
                        loginHeader
                        methodPicker

                        if method == .phone {
                            phoneContent
                        } else {
                            qrContent
                        }
                        thirdPartySection
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
            .navigationTitle("酷狗概念版")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Theme.text)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focus = nil }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if !auth.isLoggedIn, method == .qr, code == nil {
                loadQR()
            }
        }
        .onDisappear {
            pollTask?.cancel()
        }
        .onChange(of: method) { value in
            loginError = ""
            if value == .qr {
                focus = nil
                if code == nil { loadQR() }
            } else {
                pollTask?.cancel()
            }
        }
        .onChange(of: phone) { value in
            let digits = String(value.filter { $0.isNumber }.prefix(11))
            if digits != value { phone = digits }
            smsNotice = ""
            loginError = ""
        }
        .onChange(of: verifyCode) { value in
            let digits = String(value.filter { $0.isNumber }.prefix(6))
            if digits != value { verifyCode = digits }
            loginError = ""
        }
        .onReceive(countdownTimer) { _ in
            if countdown > 0 { countdown -= 1 }
        }
        .sheet(item: $thirdParty) { provider in
            ThirdPartyLoginView(provider: provider) { token, userid, vipToken in
                thirdParty = nil
                Task {
                    await completeLogin(token: token, userid: userid, vipToken: vipToken)
                }
            }
        }
    }

    // MARK: - Header

    private var loginHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.card)
                    .frame(width: 66, height: 66)
                    .overlay(
                        Circle().stroke(Theme.border, lineWidth: 0.5)
                    )
                Text("K")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
            }

            Text("酷狗概念版")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.text)

            Text("登录后同步账号、会员权益与收藏")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
        }
        .padding(.top, 4)
    }

    private var methodPicker: some View {
        HStack(spacing: 4) {
            ForEach(LoginMethod.allCases) { item in
                Button {
                    guard method != item else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        method = item
                    }
                } label: {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(method == item ? Theme.onAccent : Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(method == item ? Theme.accent : Color.clear)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.chip)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
    }

    // MARK: - Phone

    private var phoneContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                fieldTitle("手机号")
                HStack(spacing: 10) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 18)

                    TextField("请输入 11 位手机号", text: $phone)
                        .font(.system(size: 16))
                        .foregroundColor(Theme.text)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .phone)
                        .submitLabel(.next)
                        .onSubmit { focus = .code }

                    if !phone.isEmpty {
                        Button {
                            phone = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(focus == .phone ? Theme.accent.opacity(0.55) : Theme.border,
                                lineWidth: focus == .phone ? 1 : 0.5)
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                fieldTitle("短信验证码")
                HStack(spacing: 10) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 18)

                    TextField("请输入验证码", text: $verifyCode)
                        .font(.system(size: 16))
                        .foregroundColor(Theme.text)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .code)
                        .submitLabel(.done)
                        .onSubmit { loginWithPhone() }

                    Button {
                        sendCode()
                    } label: {
                        HStack(spacing: 6) {
                            if sendingCode {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                                    .scaleEffect(0.72)
                            }
                            Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Theme.chip)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendCode || sendingCode || countdown > 0)
                    .opacity((canSendCode || countdown > 0 || sendingCode) ? 1 : 0.42)
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(focus == .code ? Theme.accent.opacity(0.55) : Theme.border,
                                lineWidth: focus == .code ? 1 : 0.5)
                )
            }

            if !smsNotice.isEmpty {
                Label(smsNotice, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .transition(.opacity)
            }

            if !loginError.isEmpty {
                Label(loginError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color.red.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Button {
                loginWithPhone()
            } label: {
                HStack(spacing: 8) {
                    if loggingIn {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.onAccent))
                            .scaleEffect(0.78)
                    }
                    Text(loggingIn ? "登录中…" : "登录")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canLogin || loggingIn)
            .opacity(canLogin ? 1 : 0.42)
            .padding(.top, 2)

            Text("未注册的手机号验证通过后会自动创建酷狗账号，验证码由酷狗官方发送")
                .font(.system(size: 11))
                .foregroundColor(Theme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    private var validPhone: Bool {
        phone.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil
    }

    private var thirdPartySection: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 0.5)
                Text("其他登录方式")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiaryText)
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 0.5)
            }

            HStack(spacing: 11) {
                ForEach(ThirdPartyProvider.allCases) { provider in
                    Button {
                        thirdParty = provider
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(provider.tint.opacity(0.13))
                                    .frame(width: 30, height: 30)
                                if provider == .qq {
                                    Text("QQ")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(provider.tint)
                                } else {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(provider.tint)
                                }
                            }

                            Text(provider.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.text)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 6)
    }

    private var canSendCode: Bool {
        validPhone && !sendingCode && countdown == 0
    }

    private var canLogin: Bool {
        validPhone && verifyCode.count >= 4
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.secondaryText)
            .padding(.leading, 4)
    }

    private func sendCode() {
        guard canSendCode else { return }
        focus = nil
        sendingCode = true
        loginError = ""
        smsNotice = ""

        Task {
            do {
                try await KGLogin.sendSMSCode(phone: phone)
                countdown = 60
                smsNotice = "验证码已发送，请查看短信"
                sendingCode = false
                focus = .code
            } catch {
                sendingCode = false
                loginError = (error as? LocalizedError)?.errorDescription ?? "验证码发送失败"
            }
        }
    }

    private func loginWithPhone() {
        guard canLogin, !loggingIn else { return }
        focus = nil
        loggingIn = true
        loginError = ""

        Task {
            do {
                let result = try await KGLogin.loginByPhone(phone: phone, code: verifyCode)
                loggingIn = false
                await completeLogin(token: result.token, userid: result.userid, vipToken: result.vipToken)
            } catch {
                loggingIn = false
                loginError = (error as? LocalizedError)?.errorDescription ?? "登录失败，请稍后再试"
            }
        }
    }

    // MARK: - QR

    private var qrContent: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 232, height: 232)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

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
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)

            Text("打开酷狗概念版 → 我的 → 扫一扫\n扫码后请在手机上确认登录")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                loadQR()
            } label: {
                Text("刷新二维码")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.top, 2)
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
                        await completeLogin(token: token, userid: userid, vipToken: result.vipToken)
                    }
                    return
                default:
                    break
                }
            }
            status = "二维码已过期，请点刷新"
        }
    }

    private func completeLogin(token: String, userid: Int, vipToken: String?) async {
        pollTask?.cancel()
        auth.signIn(token: token, userid: userid, vipToken: vipToken)
        status = "登录成功"
        player.showToast("登录成功，正在注册设备…")

        let deviceReply = await KGDevice.registerIfNeeded()
        player.showToast(deviceReply)
        player.showToast("正在领取畅听权益…")

        let claim = await KGVIP.claimIfNeeded()
        if claim == .claimed {
            player.showToast(KGVIP.lastMessage.isEmpty ? "已领取畅听权益" : KGVIP.lastMessage)
        } else if claim == .alreadyClaimed {
            if !KGVIP.lastMessage.isEmpty { player.showToast(KGVIP.lastMessage) }
        } else if claim == .failed {
            player.showToast(KGVIP.lastMessage.isEmpty ? "畅听权益领取失败，下次播放会再试" : KGVIP.lastMessage)
        } else {
            player.showToast("登录已失效，请重新登录")
        }
        vipText = await KGUser.vipText() ?? "未获取到会员信息"

        try? await Task.sleep(nanoseconds: 900_000_000)
        dismiss()
    }

    // MARK: - Logged in

    private var loggedInContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 62))
                .foregroundColor(Theme.accent)
                .padding(.top, 16)

            Text("已登录")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.text)

            Text("UID \(auth.userid)")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)

            Text(vipText)
                .font(.system(size: 13))
                .foregroundColor(Theme.accent)
                .multilineTextAlignment(.center)

            Text("会员状态说明：酷狗概念版的畅听权益按天发放，不走豪华 VIP 的到期字段，所以日期显示旧记录是正常的")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

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
                    .appSurface(cornerRadius: 20)
            }

            Button {
                auth.signOut()
                player.showToast("已退出登录")
                if method == .qr { loadQR() } else { code = nil }
            } label: {
                Text("退出登录")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .task(id: auth.userid) {
            if auth.isLoggedIn {
                vipText = await KGUser.vipText() ?? "未获取到会员信息"
            }
        }
    }
}
