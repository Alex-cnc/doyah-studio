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
        // 皮肤开关：**缺省开**（用户明确要它）。用 `object(forKey:)` 而不是 `bool(forKey:)` ——
        // 后者对"从未设过"也返回 false，会让默认值变成关（这正是"新装看不到皮肤"的经典坑）。
        isNebulaSkinEnabled = UserDefaults.standard.object(forKey: NebulaSkinStorage.key) as? Bool ?? true
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

    // MARK: 星云皮肤开关 （星空紫「星云皮肤」· 2026-10-01 需求提出者要的「皮肤」质感；派单 `T-20261001-031`／`T-20261001-037`；队列 `L-153`）

    /// 是否启用「星云皮肤」（星云云气 + 星点）。
    ///
    /// **默认开**：需求提出者 2026-10-01 明确要这层质感（原话「我说的可能是皮肤更准确」），
    /// 新装用户直接看到它；但**必须可关** —— 一是"我就想安静用"的退路，二是故障兜底。
    ///
    /// **只对星空紫生效**：别的主题没有"星云"语义，偷偷加星星是走样（见 `NebulaBackground`）。
    @Published private(set) var isNebulaSkinEnabled: Bool

    /// 皮肤开关的持久化键（与 `DesignTheme.Storage.key` 同一前缀，便于一起清理）。
    enum NebulaSkinStorage {
        static let key = "ui.nebulaSkin"
    }

    /// 开关皮肤。**只在星空紫下才有视觉差别**，但开关本身对所有主题都记住 ——
    /// 这样"切到星空紫 → 切走 → 再切回来"能回到用户上次的选择。
    func setNebulaSkinEnabled(_ enabled: Bool) {
        guard enabled != isNebulaSkinEnabled else { return }
        isNebulaSkinEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: NebulaSkinStorage.key)
    }
}
