import Foundation

// MARK: - 主题（配色方案）：一组令牌值的容器（FR-EDIT-33 扩写 · 队列 L-80）
//
// 2026-09-29 需求提出者：「要增加一个 theme 主题选项」，并指出公司 Linux 版**早就有三个主题色自由选择**：
// **豆芽绿 / 玫瑰金 / 科技蓝**。口径见 `Docs/design/外观方案-v1.md` §9 ——
//
//   **一个主题 = 一组令牌值**（底色基调 + 强调色家族 + 语法着色），**不是**只换一个强调色。
//   三个主题共用同一套令牌名与同一套门槛（正文 ≥4.5 / 强对比 ≥7 / 图标线 ≥3，**深浅两态都要过**）。
//
// 为什么值表集中在这一个文件、而不是散在各枚举的 `switch` 里：令牌名（角色）与令牌值（一套配色）
// 是**两条轴**。角色写在 `DesignTokens.swift`（语义 + 用法规矩），值写在这里（按主题分组）。
// 这样「换配色」= 换一个表，而"哪个角色该长什么样"的规矩一处都没动 ——
// 也正是这一步让「样张与产品同源」这条接线（`Scripts/render-design-mock.sh`）自动跟着换。
//
// **值来源与「推导值」的纪律（照 §9.1 的约定，不许出现第四条路）**
//   · `科技蓝` = 外观方案 D 的完整值集（§8：需求提出者提供参考图、逐像素取色）—— 已给定；
//   · `豆芽绿` / `玫瑰金` = **推导草案**：Linux 侧已有实际色值，但**本侧三仓无记载**
//     （`Docs/发布计划.md` 的「待输入」表登记着这条缺口）⇒ 先按主题名推导（嫩芽绿系 / 暖粉金系），
//     **表里每个推导主题都整块标注**，收到实际色值后**以实际值替换、不留两套**。
//     推导不是随便挑的：每一组都过了同一套门槛，且由单测与 `Scripts/check-design-themes.py` 各自独立复算一遍。

/// 主题（配色方案）—— 用户可切的那三个候选（FR-EDIT-33）。
///
/// 持久化按 `id` 存（**不随界面语言变化**，也不随显示名变化）；未知 id **一律回退**而不是报错
/// （配置文件被手改、或将来删掉某个主题时，界面都必须照常起来）——与 `AccentTheme` 同口径。
public enum DesignTheme: String, CaseIterable, Identifiable, Sendable {

    /// 科技蓝：外观方案 D 的那一组值（§8，作为**默认主题**）。
    case techBlue = "tech-blue"
    /// 豆芽绿：嫩芽绿系（**推导草案**，等 Linux 侧实际色值）。
    case beanGreen = "bean-green"
    /// 玫瑰金：暖粉金系（**推导草案**，等 Linux 侧实际色值）。
    case roseGold = "rose-gold"

    public var id: String { rawValue }

    /// 显示名的文案键（中英各一条；`Core` 给键、App 用 `L(...)` 取文案 —— 与其它文案同一口径）。
    public var nameKey: LKey {
        switch self {
        case .techBlue: return .designThemeTechBlue
        case .beanGreen: return .designThemeBeanGreen
        case .roseGold: return .designThemeRoseGold
        }
    }

    /// 这一组值**是不是推导草案**（Linux 侧实际色值未到）。
    ///
    /// 为什么要能在代码里问这一句：界面要在「待值」的主题旁边如实标出来（不许把推导值当实际值卖），
    /// 门禁也要据此检查「待值登记还在、没被静默删掉」。
    public var isDerivedDraft: Bool { self != .techBlue }

    /// 该主题**配套的交互强调色**（选中行 / 主按钮 / 焦点环）。
    ///
    /// 口径（L-80 定案，一句话可推翻）：**主题自带配套强调色** —— 选中态与主按钮必须和主题同色相，
    /// 否则「豆芽绿主题」里会杵着一个鲸鱼蓝按钮，主题就只换了一半。
    /// 科技蓝的配套值 = **鲸鱼蓝**（与 App 图标 / dsh-tui 同源，也是改造前的默认值 ⇒ 现状零变化）。
    public var accent: AccentTheme {
        switch self {
        case .techBlue: return .whaleBlue
        case .beanGreen: return .beanGreen
        case .roseGold: return .roseGold
        }
    }

    /// 这一主题的完整值表。
    public var palette: ThemePalette { ThemePalette.of(self) }

    /// 用户可选的顺序 = 界面里的顺序（科技蓝在首位：它是默认值，也是 Linux 侧同名的那一个）。
    public static let all: [DesignTheme] = [.techBlue, .beanGreen, .roseGold]

    /// 默认与回退都是科技蓝（产品改造前的现状就是这一组值）。
    public static let fallback = DesignTheme.techBlue

    /// 由持久化的 id 解析；未知 id 回退（理由见类型注释）。
    public static func resolve(id: String?) -> DesignTheme {
        guard let id, !id.isEmpty else { return fallback }
        return all.first { $0.id == id } ?? fallback
    }

    /// 偏好设置里的存储键（与工程内其它 UI 偏好同一套 `ui.` 前缀）。
    public enum Storage {
        public static let key = "ui.designTheme"
    }
}

/// 一个主题的**完整令牌值表**：21 个角色 + 发丝线两个参数。
///
/// 为什么是显式字段而不是字典：缺一个角色在字典里是「查不到」，在这里是**编译不过**。
/// 「查不到就回退到默认值」正是配色类改动的经典假绿 —— 某屏少拿一个角色，界面照常起来，
/// 只是那一块用着别的主题的颜色，谁都不会说话。
public struct ThemePalette: Equatable, Sendable {

    public let id: DesignTheme

    // 表面五档（层次由暗到亮：window → sidebar → content → panel → raised）
    public let window: ThemeColor
    public let sidebar: ThemeColor
    public let content: ThemeColor
    public let panel: ThemeColor
    public let raised: ThemeColor

    // 文本五档
    public let textBright: ThemeColor
    public let textPrimary: ThemeColor
    public let textSecondary: ThemeColor
    public let textTertiary: ThemeColor
    public let textDisabled: ThemeColor

    // 状态三档
    public let success: ThemeColor
    public let warning: ThemeColor
    public let danger: ThemeColor

    // 强调色家族五档（基准值，用于装饰性 / 语义性着色；用户可切的**交互**强调色见 `DesignTheme.accent`）
    public let accent: ThemeColor
    public let accentGlow: ThemeColor
    public let accentSoft: ThemeColor
    public let accentTeal: ThemeColor
    public let accentWarm: ThemeColor

    // 发丝线：深色 = 白 `hairlineDarkAlpha` 叠加；浅色 = 实色 `hairlineLight`（见 `Hairline` 的注释）
    public let hairlineLight: UInt32
    public let hairlineDarkAlpha: Double

    public static func of(_ theme: DesignTheme) -> ThemePalette {
        switch theme {
        case .techBlue: return .techBlue
        case .beanGreen: return .beanGreen
        case .roseGold: return .roseGold
        }
    }

    // MARK: 科技蓝（外观方案 D · §8 原值，逐像素取色 —— 不是推导值）
    //
    // 这一组里 §8 没给值、由本侧推定的两处（**推导值，一句话可推翻**）：
    //   · 浅色 `raised` = 白：沿用既有规矩（浅色下 raised 与 content 同为白，浮层靠发丝线 / 阴影区分）；
    //     §8.5 没给 raised，改了反而会造出"浅色下浮层比内容还亮"的走样。
    //   · 浅色 `window` = `#F1F5FA`：**对 §8.5 的一处显式偏离** —— §8.5 写它与 content 同为白，
    //     但既有判据要求"window 必须与 content 可区分"（距离 ≥0.02），两白相等会当场判红。
    //     取比 sidebar 再低一档的同色相浅蓝（比 content 暗、距离 0.041），观感与白无异。

    public static let techBlue = ThemePalette(
        id: .techBlue,
        window: ThemeColor(light: 0xF1F5FA, dark: 0x02070A),
        sidebar: ThemeColor(light: 0xF4F7FB, dark: 0x081420),
        content: ThemeColor(light: 0xFFFFFF, dark: 0x0B1A2A),
        panel: ThemeColor(light: 0xF4F7FB, dark: 0x15263A),
        raised: ThemeColor(light: 0xFFFFFF, dark: 0x1D3350),
        textBright: ThemeColor(light: 0x061426, dark: 0xEFF8FA),
        textPrimary: ThemeColor(light: 0x10243D, dark: 0xCAD0DC),
        textSecondary: ThemeColor(light: 0x45607F, dark: 0x8594B1),
        textTertiary: ThemeColor(light: 0x5C7CA6, dark: 0x5C7CA6),
        textDisabled: ThemeColor(light: 0xA9B7CC, dark: 0x415F86),
        success: ThemeColor(light: 0x16704A, dark: 0x4ADE80),
        warning: ThemeColor(light: 0x92600B, dark: 0xFBBF24),
        danger: ThemeColor(light: 0xC2321F, dark: 0xF87171),
        accent: ThemeColor(light: 0x2E6FA8, dark: 0x6EA8D0),
        accentGlow: ThemeColor(light: 0x1C63C4, dark: 0x7AB0FA),
        accentSoft: ThemeColor(light: 0x4C6C9B, dark: 0x4C6C9B),
        accentTeal: ThemeColor(light: 0x0E7490, dark: 0x94E2F8),
        accentWarm: ThemeColor(light: 0x8A6A3B, dark: 0xC7AF95),
        hairlineLight: 0xD3DCE8,
        hairlineDarkAlpha: 0.10
    )

    // MARK: 豆芽绿（**推导草案** —— Linux 侧实际色值到位后整表替换，不留两套）
    //
    // 推导口径（照科技蓝的结构等比走一遍，不是另起一套）：深色底 = 极暗的绿基调（window 最暗、
    // 五档明度严格递增）、浅色 = 带绿调的白（content 纯白最亮）；文本四档同色相往深 / 往亮走；
    // 状态三色（成功 / 警告 / 危险）**沿用方案 D**：语义色的色相不该随主题漂移（红还是红）。
    // 强调家族按绿的色相铺开，语法六档仍按角色挂家族（§8.4 的角色表）。

    public static let beanGreen = ThemePalette(
        id: .beanGreen,
        window: ThemeColor(light: 0xF2F8F3, dark: 0x04120A),
        sidebar: ThemeColor(light: 0xF4F9F5, dark: 0x0A1D12),
        content: ThemeColor(light: 0xFFFFFF, dark: 0x0F2418),
        panel: ThemeColor(light: 0xF4F9F5, dark: 0x16301F),
        raised: ThemeColor(light: 0xFFFFFF, dark: 0x1E3D28),
        textBright: ThemeColor(light: 0x06180D, dark: 0xF0FBF3),
        textPrimary: ThemeColor(light: 0x12301E, dark: 0xC6D9CB),
        textSecondary: ThemeColor(light: 0x48664F, dark: 0x8AA791),
        textTertiary: ThemeColor(light: 0x5E8A6E, dark: 0x6E9E7C),
        textDisabled: ThemeColor(light: 0xA9C3B1, dark: 0x3E6B4E),
        success: ThemeColor(light: 0x16704A, dark: 0x4ADE80),
        warning: ThemeColor(light: 0x92600B, dark: 0xFBBF24),
        danger: ThemeColor(light: 0xC2321F, dark: 0xF87171),
        accent: ThemeColor(light: 0x2F7D52, dark: 0x86C79C),
        accentGlow: ThemeColor(light: 0x1B7A4A, dark: 0xA8E6BB),
        accentSoft: ThemeColor(light: 0x4C7B5F, dark: 0x56795F),
        accentTeal: ThemeColor(light: 0x0F7F7A, dark: 0x7FD8C4),
        accentWarm: ThemeColor(light: 0x8A6A3B, dark: 0xC9B27A),
        hairlineLight: 0xD5E3D9,
        hairlineDarkAlpha: 0.10
    )

    // MARK: 玫瑰金（**推导草案** —— 同上，整表待替换）
    //
    // 暖粉金基调：深色底是极暗的暖褐（带一点红），浅色是带粉调的白；
    // 强调家族取暖粉金（`accent` / `accentGlow` / `accentSoft` / `accentWarm`），
    // `accentTeal` 保留一个**冷色对位**（配色里全暖会糊成一片，青是这套表里唯一的冷锚点）。

    public static let roseGold = ThemePalette(
        id: .roseGold,
        window: ThemeColor(light: 0xFBF3F1, dark: 0x14080B),
        sidebar: ThemeColor(light: 0xF8F0EE, dark: 0x1F0F13),
        content: ThemeColor(light: 0xFFFFFF, dark: 0x26141A),
        panel: ThemeColor(light: 0xF8F0EE, dark: 0x341C23),
        raised: ThemeColor(light: 0xFFFFFF, dark: 0x42262E),
        textBright: ThemeColor(light: 0x1E0A0C, dark: 0xFDF3F4),
        textPrimary: ThemeColor(light: 0x33161A, dark: 0xDCC8CD),
        textSecondary: ThemeColor(light: 0x6B484E, dark: 0xA9909A),
        textTertiary: ThemeColor(light: 0x8A6A6E, dark: 0xA97F86),
        textDisabled: ThemeColor(light: 0xC3AEB1, dark: 0x6E4A53),
        success: ThemeColor(light: 0x16704A, dark: 0x4ADE80),
        warning: ThemeColor(light: 0x92600B, dark: 0xFBBF24),
        danger: ThemeColor(light: 0xC2321F, dark: 0xF87171),
        accent: ThemeColor(light: 0xA65B55, dark: 0xE0A6A2),
        accentGlow: ThemeColor(light: 0xB04A3C, dark: 0xF5C0AE),
        accentSoft: ThemeColor(light: 0x8A6A6B, dark: 0x9C6F6F),
        accentTeal: ThemeColor(light: 0x0F7F7A, dark: 0x9BD3C8),
        accentWarm: ThemeColor(light: 0x8A6A3B, dark: 0xE0B57E),
        hairlineLight: 0xF0D9D5,
        hairlineDarkAlpha: 0.10
    )
}
