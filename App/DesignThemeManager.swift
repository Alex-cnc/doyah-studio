import AppKit
import Combine
import DoyahCore
import SwiftUI

/// 主题（配色方案）的运行时状态（FR-EDIT-33 扩写 · 队列 L-80）。
///
/// 与 `AccentManager` / `FontManager` / `LocalizationManager` 同构：
/// 单例 `ObservableObject` + `UserDefaults` 持久化，视图不必逐个订阅。
///
/// **为什么主题要比强调色更"宽"**：一个主题 = 一组令牌值（表面 / 文本 / 状态 / 强调家族 / 语法 +
/// 配套的交互强调色）。所以这个对象管两件事：
///   ① 当前主题（`ui.designTheme`）—— 令牌取色时逐个调用点都要求它（`Surface.panel.color(in: theme)`）；
///   ② **把配套强调色同步给 `AccentManager`** —— 选中态 / 主按钮 / 焦点环的颜色仍由 `AccentManager`
///      下发（它们是**系统控件**的颜色，走根视图 `.tint`），主题只管"该用哪一个"。
///
/// 为什么不在 `Theme` 里缓存主题：与强调色同一个理由 —— 缓存下来就会出现
/// "换了主题但结果表的选中条还是旧的"。
final class DesignThemeManager: ObservableObject {

    static let shared = DesignThemeManager()

    /// 用户选的主题（**落盘的那一个**）。改动只经由 `select(_:)`，
    /// 避免出现"界面变了但没落盘"的状态。
    @Published private(set) var selected: DesignTheme

    /// **宿主语境覆盖**（不落盘，与 `LocalizationManager.beginHostLanguage` 同构）。
    ///
    /// 为什么需要它：离屏快照要拍「每个主题各自长什么样」（三张图同一块面板、选择不同），
    /// 而**拍一张图不该改用户的偏好** —— 语言那条路已经踩过这个坑并定下了口径
    /// （宿主参数只覆盖、不落盘）。主题照抄，不另起一套。
    @Published private(set) var hostOverride: DesignTheme?

    /// 当前**生效**的主题：视图 / 令牌一律看它（宿主覆盖优先）。
    var theme: DesignTheme { hostOverride ?? selected }

    private init() {
        // **不在这里回头写强调色**：老用户可能存过一个「深海青」，若启动时被主题覆盖，
        // 就成了"打开一次就悄悄改了偏好"。主题只在**用户选了它**的那一刻同步配套强调色。
        selected = DesignTheme.resolve(id: UserDefaults.standard.string(forKey: DesignTheme.Storage.key))
    }

    /// 进入宿主语境（快照用）：返回进入前的那一个，调用方负责还原。
    /// **刻意不写 `UserDefaults`** —— 它只能影响这一段渲染。
    @discardableResult
    func beginHostTheme(_ theme: DesignTheme) -> DesignTheme? {
        let previous = hostOverride
        hostOverride = theme
        return previous
    }

    /// 退出宿主语境。
    func endHostTheme() {
        hostOverride = nil
    }

    /// 选择主题（落盘 + 通知界面 + 把配套强调色同步给 `AccentManager`）。
    func select(_ theme: DesignTheme) {
        guard theme != selected else { return }
        selected = theme
        UserDefaults.standard.set(theme.id, forKey: DesignTheme.Storage.key)
        // 配套强调色：主题自带的那一个（见 `DesignTheme.accent`）。
        AccentManager.shared.select(theme.accent)
    }

    /// 当前主题的值表（渲染 / 自绘视图现取，别缓存）。
    var palette: ThemePalette { theme.palette }
}
