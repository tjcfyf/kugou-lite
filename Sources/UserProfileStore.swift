import Foundation
import Combine
import SwiftUI

/// 全局酷狗资料缓存：主页右上角头像、资料库账号卡共用同一份数据。
/// token/userid 变化时自动刷新，登录成功或退出会立刻反映到界面。
final class UserProfileStore: ObservableObject {
    static let shared = UserProfileStore()

    @Published private(set) var profile: KugouProfile?

    private var loading = false
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = Publishers.CombineLatest(
            AuthStore.shared.$token,
            AuthStore.shared.$userid
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] pair in
            guard let self else { return }
            let token = pair.0
            let userid = pair.1
            if token == nil || userid == 0 {
                self.profile = nil
                return
            }
            Task { await self.refresh() }
        }
    }

    @MainActor
    func refresh(force: Bool = false) async {
        guard AuthStore.shared.isLoggedIn else {
            profile = nil
            return
        }
        if loading && !force { return }
        loading = true
        defer { loading = false }

        guard let updated = await KGUser.profile() else { return }
        profile = updated
    }
}

/// 圆形用户头像。未登录或加载失败时显示系统占位图，不闪白块。
struct UserAvatarView: View {
    let url: URL?
    var size: CGFloat = 30
    var borderWidth: CGFloat = 0.7

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(Theme.text.opacity(0.14), lineWidth: borderWidth)
        )
        .contentShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Theme.chip)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.64, weight: .semibold))
                .foregroundColor(Theme.accent.opacity(0.82))
        }
    }
}
