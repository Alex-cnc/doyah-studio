import AppKit
import DoyahCore
import SwiftUI

/// 「壁纸皮肤」的绘制层（第 5 套主题「深空苍穹」· 人类主人 2026-10-16 看过效果图之后选定 **档 3**）。
///
/// **这一层只做两件事**：把照片按「铺满窗口」画出来，再按值表里的**蒙版**压住它的亮度。
/// 资源名 / 四段蒙版 / 各表面不透明度**全部来自 `Core` 的值表**（`DesignTheme.wallpaper`），
/// 这里一个数字都不写死 —— 与 `NebulaBackground` 同一条纪律：**不为某个主题单写分支**。
///
/// **邻居的分工**（三层，互不代偿）：
/// - 照片在最底层（本层，挂在窗口根的 `.background` 上）；
/// - 表面在中间，按定值半透明（`Theme.surface` 一处收口）；
/// - 星云在表面**之上**（`NebulaBackground`，画在 `MainWindow` 的内容 ZStack 里）。
///
/// **为什么蒙版要用 `opaqueSurface(.window)`**：蒙版是"用来压照片的那层玻璃"，
/// 它自己必须满不透明 —— 若用半透明的表面色，蒙版会被透视规则**再乘一遍**，
/// 值表里那些定值当场失真（这条在 `Theme.opaqueSurface` 的注释里也写了一遍）。
///
/// **边界（如实登记）**：
/// ① `.sheet` / 弹出层另起一个窗口，那里的半透明表面底下**不是**这张照片（拿到的是弹层窗口自己的底）
///    ⇒ 弹层观感要另做一片（离屏快照取证），本片不假装已经处理好；
/// ② 本层不做像素级对比度自检 —— 值表是**定值**（蒙版最松 0.24 / 面板 ≥0.30），
///    「拿资源实测最亮处算有效底色」的闭环判据归下一片。
struct WallpaperBackground: View {

    /// 主题与开关都从 `DesignThemeManager` 现取（与令牌取色同一个理由：缓存会读到旧值）。
    @ObservedObject private var themeManager = DesignThemeManager.shared

    var body: some View {
        // 生效条件只问 Core 那**一个**函数（主题声明了壁纸 ∧ 开关开）——
        // 在这里再写一遍 `theme == .deepSpace && …` 只会让两处慢慢分叉。
        if let spec = WallpaperSkinPreference.activeSpec(theme: themeManager.theme, in: .standard) {
            photo(spec)
                .overlay(mask(spec))
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func photo(_ spec: WallpaperSkinSpec) -> some View {
        if let image = NSImage(named: spec.assetName) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            // 资源没进包：**不留白、不崩** —— 退回主题自己的窗口底色（等于这一层不存在），
            // 观感与关掉壁纸完全一致。宁可少一层，也不要露一块白板。
            Theme.opaqueSurface(.window)
        }
    }

    /// 蒙版：用**这个主题自己的窗口底色**去压（深空苍穹的底是 `#05070D`，不是随便一个黑）。
    private func mask(_ spec: WallpaperSkinSpec) -> some View {
        LinearGradient(
            stops: spec.maskStops.map {
                Gradient.Stop(color: Theme.opaqueSurface(.window).opacity($0.alpha), location: $0.location)
            },
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
