import AppKit
import DoyahCore
import SwiftUI

/// **让窗口自带的系统材质在壁纸生效时让路**（只动材质，不动布局；关掉壁纸逐像素还原）。
///
/// ## 为什么需要这一件
///
/// 壁纸照片是画在**窗口内容**里的（`MainWindow` 的 `.background(WallpaperBackground())`），
/// 而 `NavigationSplitView` 的侧栏在外面又铺了一层**系统材质**（`NSVisualEffectView`）——
/// 那层混的是「窗口背后」的东西（桌面 / 窗口底色），**画在它下面**的照片永远透不上来。
/// 实测症状（人类主人 2026-10-16 实机点验原话：「左侧栏背景怎么是不透明的呢？」）：
/// 内容区照片看得见，侧栏是一块平的灰。
///
/// ## 为什么走 AppKit
///
/// SwiftUI 在 **macOS 上没有** `containerBackground(for: .navigationSplitView)`（那条只给 iOS；
/// 本件落地前用 `swiftc -typecheck` 对 macOS 14 SDK 实探过：`'navigationSplitView' is unavailable in macOS`）。
/// 也**不用**「往侧栏里再铺一层自己的照片」这种绕法 —— 那会让侧栏与内容区出现**接缝**
/// （同一张照片被两个视口各裁一次），观感是"两个窗口"而不是"一整张照片"。
///
/// ## 怎么让路（并保证可逆）
///
/// 从本视图**沿祖先链**找出所有 `NSVisualEffectView`，壁纸开着时把材质的 `state` 置为
/// `.inactive`、`material` 换 `.clear`（= 看得见后面的东西）；关掉壁纸时**把原来的三件
/// （material / state / blendingMode）逐字还回去** —— 不做"猜一个默认值还原"，
/// 免得把系统材质永久改坏（这类"关掉之后再也回不去"是本项目一贯最忌的事。
///
/// ## 边界（如实登记）
///
/// ① 只看**祖先链**：若某个系统版本把侧栏材质放成**兄弟**视图而不是祖先，这条就不生效（不会崩，
///    只是那一栏仍是不透明的灰）—— 真机点验是唯一判据；
/// ② 只碰材质三件，**不碰** frame / 布局 / 圆角 / 分割线；
/// ③ 终端等**自带 vibrancy** 的视图不在祖先链上（它们是内容区里的兄弟），不会被动到。
struct WindowMaterialRelief: NSViewRepresentable {

    /// 主题 / 开关都从 `DesignThemeManager` 现取（与令牌取色同一个理由：缓存会读到旧值）。
    @ObservedObject private var themeManager = DesignThemeManager.shared

    /// 壁纸是否生效 —— 只问 Core 那**一个**函数（主题声明 ∧ 开关开）。
    private var isActive: Bool {
        WallpaperSkinPreference.paintsWallpaper(theme: themeManager.theme, in: .standard)
    }

    func makeNSView(context: Context) -> NSView { ReliefView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReliefView)?.apply(isActive: isActive)
    }

    final class ReliefView: NSView {

        /// 原来的材质三件（按视图身份存；同一个视图只记第一次的样子）。
        private static var originals: [ObjectIdentifier: (material: NSVisualEffectView.Material,
                                                          state: NSVisualEffectView.State,
                                                          blending: NSVisualEffectView.BlendingMode)] = [:]
        private var applied: Bool?

        func apply(isActive: Bool) {
            guard applied != isActive else { return }
            applied = isActive
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var effects: [NSVisualEffectView] = []
                var node: NSView? = self.superview
                while let current = node {
                    if let effect = current as? NSVisualEffectView { effects.append(effect) }
                    node = current.superview
                }
                for effect in effects {
                    let key = ObjectIdentifier(effect)
                    if isActive {
                        if Self.originals[key] == nil {
                            Self.originals[key] = (effect.material, effect.state, effect.blendingMode)
                        }
                        // **踩过的坑**：第一版写 `effect.material = .clear` —— macOS 的
                        // `NSVisualEffectView.Material` **没有** `.clear` 这个成员，编译就红
                        // （而当时打包脚本把失败吞了、拿旧二进制出包，于是"看似修好了"）。
                        // 正解是换**混合目标**：默认的 `.behindWindow` 取的是"窗口背后"（桌面）⇒
                        // 照片（画在窗口内容里）永远进不来；改成 `.withinWindow` 之后这层材质
                        // 取的是**窗口自己内容**里的像素 —— 照片就在底下，于是那一栏跟着照片走。
                        effect.blendingMode = .withinWindow
                    } else if let original = Self.originals[key] {
                        effect.material = original.material
                        effect.state = original.state
                        effect.blendingMode = original.blending
                        Self.originals[key] = nil
                    }
                }
            }
        }
    }
}
