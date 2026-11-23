import SwiftUI
import UIKit
import Combine

/// 底栏播放封面圆盘在屏幕坐标系中的真实矩形。
/// 播放页展开时用它作为 `PlayerPanelFrame` 的起点，不再用固定 15% 位移。
struct MiniPlayerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

enum Theme {
    static let background = Color("Background")
    // 半透明卡片让全局专辑色透出来，但正文只用黑/白两级。
    static let card = Color("Card").opacity(0.88)
    // 强调色也只使用黑/白：暗色主题白，浅色主题黑。
    static let accent = Color("TextPrimary")
    static let onAccent = Color("Background")
    static let text = Color("TextPrimary")
    static let secondaryText = Color("TextPrimary").opacity(0.72)
    static let tertiaryText = Color("TextPrimary").opacity(0.46)
    static let chip = Color("Chip").opacity(0.84)
    static let separator = Color("TextPrimary").opacity(0.16)
    static let border = Color("TextPrimary").opacity(0.12)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.96), accent.opacity(0.68)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// 全局背景：只保留底色，不再做全站专辑色染色；唯一的色彩来自播放页的封面磨砂玻璃。
struct AppBackground: View {
    var body: some View {
        AppBackgroundGradient()
    }
}

/// iOS 原生 UIVisualEffectView 磨砂玻璃。播放页背景用这个，不额外叠任何颜色遮罩。
struct NativeFrostedGlass: UIViewRepresentable {
    let style: UIBlurEffect.Style

    final class Coordinator {
        var style: UIBlurEffect.Style?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.style = style
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        // 播放进度每 0.25 秒会刷新 SwiftUI 树；重复赋同一个 blur 会触发
        // UIVisualEffectView 重建，拖动时就会持续掉帧。只在样式变化时更新。
        guard context.coordinator.style != style else { return }
        context.coordinator.style = style
        uiView.effect = UIBlurEffect(style: style)
    }
}

/// 内容层统一使用实色卡片 + 一条 hairline；只有需要抬升的浮层才给很轻的接触阴影。
struct AppSurface: ViewModifier {
    var cornerRadius: CGFloat = 12
    var elevated: Bool = false
    var fill: Color = Theme.card

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
            .shadow(
                color: elevated ? Color.black.opacity(0.06) : Color.clear,
                radius: elevated ? 8 : 0,
                x: 0,
                y: elevated ? 3 : 0
            )
    }
}

struct AppChipSurface: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.chip)
        )
    }
}

extension View {
    func appSurface(cornerRadius: CGFloat = 12, elevated: Bool = false) -> some View {
        modifier(AppSurface(cornerRadius: cornerRadius, elevated: elevated))
    }

    func appChip(cornerRadius: CGFloat = 10) -> some View {
        modifier(AppChipSurface(cornerRadius: cornerRadius))
    }

    func appPanel(cornerRadius: CGFloat = 12) -> some View {
        modifier(AppSurface(cornerRadius: cornerRadius))
    }

    /// 系统搜索框的实色底：中性填充，不再逐块叠系统 blur。
    func appSearchField(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }
}

/// 列表行使用真正的整行卡片底色；圆角和分隔交给系统 List。
struct GlassRowBackground: View {
    var body: some View {
        Rectangle().fill(Theme.card)
    }
}

/// 全局按压反馈：轻微缩小 + 变淡，用短弹簧回弹，避免生硬的线性缩放。
struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.82),
                       value: configuration.isPressed)
    }
}

private final class CoverCache {
    static let shared = CoverCache()
    let cache = NSCache<NSString, UIImage>()
}

struct CoverImage: View {
    let url: URL?
    var size: CGFloat = 44
    var radius: CGFloat = 8
    var showsBorder: Bool = true
    var onLoad: ((URL?, UIImage?) -> Void)? = nil

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .task(id: url?.absoluteString) {
            guard let url = url else {
                withAnimation(.easeInOut(duration: 0.24)) { image = nil }
                onLoad?(nil, nil)
                return
            }
            let key = url.absoluteString as NSString
            if let cached = CoverCache.shared.cache.object(forKey: key) {
                withAnimation(.easeInOut(duration: 0.24)) { image = cached }
                onLoad?(url, cached)
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let decoded = UIImage(data: data) else { return }
            CoverCache.shared.cache.setObject(decoded, forKey: key)
            withAnimation(.easeInOut(duration: 0.26)) { image = decoded }
            onLoad?(url, decoded)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.chip
            Image(systemName: "music.note")
                .font(.system(size: size * 0.32, weight: .medium))
                .foregroundColor(Theme.tertiaryText)
        }
    }
}


struct SongActionsSheet: View {
    let song: Song
    @EnvironmentObject private var player: PlayerEngine
    @ObservedObject private var library = LibraryStore.shared
    @Environment(\.dismiss) private var dismiss

    private var isFavorite: Bool {
        library.isFavorite(song)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CoverImage(url: song.coverURL, size: 52, radius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.SongName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(16)

            Divider().background(Theme.separator)

            actionRow(title: "下一首播放", icon: "arrow.up.forward") {
                player.playNext(song)
                dismiss()
            }
            actionRow(title: isFavorite ? "取消我喜欢" : "我喜欢", icon: isFavorite ? "heart.fill" : "heart") {
                dismiss()
                Task {
                    let added = await library.toggleFavorite(song)
                    if let added = added {
                        player.showToast(added ? "已加入我喜欢" : "已从我喜欢移除")
                    } else {
                        player.showToast(library.favoritesMessage)
                    }
                }
            }
            actionRow(title: "加入播放列表末尾", icon: "text.badge.plus") {
                player.appendToQueue(song)
                dismiss()
            }

            Button("取消") { dismiss() }
                .font(.system(size: 15))
                .foregroundColor(Theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.chip)
                .cornerRadius(12)
                .padding(16)

            Spacer(minLength: 0)
        }
        .background(AppBackground())
    }

    private func actionRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}

/// 歌曲右侧三个点的可点菜单；用于歌单/我喜欢等自定义行，避免点三个点变成播放。
struct SongMoreMenu: View {
    let song: Song
    @EnvironmentObject private var player: PlayerEngine
    @ObservedObject private var library = LibraryStore.shared

    private var isFavorite: Bool {
        library.isFavorite(song)
    }

    var body: some View {
        Menu {
            Button {
                player.playNext(song)
            } label: {
                Label("下一首播放", systemImage: "arrow.up.forward")
            }
            Button {
                player.appendToQueue(song)
            } label: {
                Label("加入播放列表", systemImage: "text.badge.plus")
            }
            Button {
                Task {
                    let added = await library.toggleFavorite(song)
                    if let added = added {
                        player.showToast(added ? "已加入我喜欢" : "已从我喜欢移除")
                    } else {
                        player.showToast(library.favoritesMessage)
                    }
                }
            } label: {
                Label(isFavorite ? "取消我喜欢" : "我喜欢",
                      systemImage: isFavorite ? "heart.fill" : "heart")
            }
            Button {
                UIPasteboard.general.string = "\(song.SongName) - \(song.artist)"
                player.showToast("已复制歌曲信息")
            } label: {
                Label("复制歌名和歌手", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.tertiaryText)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}

/// 统一的“整行播放 + 右侧独立菜单”行，避免三个点被整行按钮吞掉。
struct SongRowWithMenu: View {
    let song: Song
    var index: Int? = nil
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    if let index = index {
                        Text("\(index)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .frame(width: 22, alignment: .leading)
                    }
                    SongRow(song: song, showsMore: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
            SongMoreMenu(song: song)
        }
    }
}

/// 悬浮底栏：单层系统材质 + hairline + 克制阴影，保留通透感但不做液态玻璃高光。
struct FloatingTabBar: View {
    @Binding var tab: Int
    let onOpenPlayer: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabSelection

    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "发现", icon: "sparkles", tag: 0, iconSize: 29)

            Spacer(minLength: 0)

            FloatingAlbumButton(onOpenPlayer: onOpenPlayer)

            Spacer(minLength: 0)

            tabButton(title: "我的", icon: "person.crop.circle", tag: 1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: 280)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.085 : 0.24),
                            Color.white.opacity(colorScheme == .dark ? 0.035 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
                .allowsHitTesting(false)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10),
            radius: 18,
            x: 0,
            y: 8
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .animation(.interpolatingSpring(stiffness: 240, damping: 26), value: tab)
    }

    private func tabButton(title: String, icon: String, tag: Int, iconSize: CGFloat = 32) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.interpolatingSpring(stiffness: 240, damping: 26)) {
                tab = tag
            }
        } label: {
            ZStack {
                if tab == tag {
                    Circle()
                        .fill(Theme.accent.opacity(colorScheme == .dark ? 0.18 : 0.11))
                        .overlay(
                            Circle().stroke(Theme.accent.opacity(colorScheme == .dark ? 0.20 : 0.14),
                                            lineWidth: 0.8)
                        )
                        .matchedGeometryEffect(id: "selected-tab", in: tabSelection)
                        .frame(width: 45, height: 45)
                }

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: tab == tag ? .semibold : .regular))
                    .foregroundColor(tab == tag ? Theme.accent : Theme.secondaryText)
            }
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(title)
    }

}

private struct FloatingAlbumButton: View {
    @EnvironmentObject private var player: PlayerEngine
    let onOpenPlayer: () -> Void

    var body: some View {
        Button {
            guard player.current != nil else {
                player.showToast("先选一首歌")
                return
            }
            onOpenPlayer()
        } label: {
            BottomArtwork()
                .frame(width: 56, height: 56)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MiniPlayerFramePreferenceKey.self,
                            value: proxy.frame(in: .global)
                        )
                    }
                )
                .scaleEffect(player.isPlaying ? 1.0 : 0.985)
                .contentShape(Circle())
                .animation(Motion.quick, value: player.isPlaying)
                .animation(Motion.standard, value: player.current?.id)
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel("当前播放")
    }
}

/// 只让底栏中心封面自己刷新旋转，不带着整条玻璃底栏每帧重绘。
private struct BottomArtwork: View {
    @EnvironmentObject private var player: PlayerEngine
    @State private var angle: Double = 0
    private let rotationTimer = Timer.publish(every: 0.10, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let song = player.current, let url = song.coverURL {
                CoverImage(url: url, size: 43, radius: 21.5)
            } else {
                RotatingAlbumPlaceholder(size: 43)
            }
        }
        .transition(.opacity)
        .rotationEffect(.degrees(angle))
        .onReceive(rotationTimer) { _ in
            guard player.isPlaying else { return }
            angle += 4.5
            if angle >= 360 { angle -= 360 }
        }
    }
}

/// 没有歌曲封面时的通用圆形封面；播放时由底栏统一驱动旋转。
struct RotatingAlbumPlaceholder: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.chip)
            Circle()
                .stroke(Theme.border, lineWidth: 0.5)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.82))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct SongRow: View {
    let song: Song
    var showsMore: Bool = false
    @EnvironmentObject private var player: PlayerEngine
    @ObservedObject private var library = LibraryStore.shared

    private var isFavorite: Bool {
        library.isFavorite(song)
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: song.coverURL, size: 56, radius: 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(song.SongName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    if song.needsPurchase {
                        Text("VIP")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.55), lineWidth: 0.5)
                            )
                    }
                }
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            if showsMore {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
                    .frame(width: 24, height: 30)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .animation(Motion.quick, value: isFavorite)
        .contextMenu {
            Button {
                player.playNext(song)
            } label: {
                Label("下一首播放", systemImage: "arrow.up.forward")
            }
            Button {
                player.appendToQueue(song)
            } label: {
                Label("加入播放列表", systemImage: "text.badge.plus")
            }
            Button {
                Task {
                    let added = await library.toggleFavorite(song)
                    if let added = added {
                        player.showToast(added ? "已加入我喜欢" : "已从我喜欢移除")
                    } else {
                        player.showToast(library.favoritesMessage)
                    }
                }
            } label: {
                Label(isFavorite ? "取消我喜欢" : "我喜欢",
                      systemImage: isFavorite ? "heart.fill" : "heart")
            }
            Button {
                UIPasteboard.general.string = "\(song.SongName) - \(song.artist)"
                player.showToast("已复制歌曲信息")
            } label: {
                Label("复制歌名和歌手", systemImage: "doc.on.doc")
            }
        }
    }
}


/// 只圆上面两角的形状，用于底部半屏面板。
struct TopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

/// iOS 15 没有 presentationDetents，用 SwiftUI 原生 Material 搭半屏玻璃。
/// 只做位移，不做缩放/透明度动画，避免磨砂层每帧重绘导致掉帧。
struct GlassHalfSheet<Content: View>: View {
    @Binding var isPresented: Bool
    var heightRatio: CGFloat
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(isPresented: Binding<Bool>,
         heightRatio: CGFloat = 0.52,
         @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.heightRatio = heightRatio
        self.content = content()
    }

    var body: some View {
        let screen = UIScreen.main.bounds
        let panelHeight = min(max(screen.height * heightRatio, 300), screen.height - 64)

        ZStack(alignment: .bottom) {
            Color.black.opacity(isPresented ? 0.18 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .animation(isPresented ? M3Motion.panelExpand : M3Motion.panelCollapse,
                           value: isPresented)

            VStack(spacing: 0) {
                Button(action: close) {
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(Theme.text.opacity(0.24))
                            .frame(width: 40, height: 5)
                        Text("点击关闭")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Theme.tertiaryText)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 3)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                content
            }
            .frame(width: screen.width, height: panelHeight, alignment: .top)
            .background(
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Theme.background.opacity(colorScheme == .dark ? 0.10 : 0.05)
                }
            )
            .clipShape(TopRoundedRectangle(radius: 26))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.text.opacity(0.10))
                    .frame(height: 0.5)
            }
            // 不再给磨砂面板加大半径阴影：`UIVisualEffectView + radius 20 shadow`
            // 在 iOS 15 上每帧都要离屏合成，是半屏面板关闭掉帧的主要来源。
            // 顶部 0.5pt 分隔线已经足够把面板与背景分开。
            .offset(y: isPresented ? 0 : panelHeight + 20)
            .animation(isPresented ? M3Motion.panelExpand : M3Motion.panelCollapse,
                       value: isPresented)
        }
        .ignoresSafeArea()
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
    }

    private func close() {
        isPresented = false
    }
}
