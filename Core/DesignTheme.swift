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
    /// 星空紫：深空靛紫系（2026-10-01 新增 —— 需求提出者要的「比科技蓝更梦幻」那一档，星际猎人的星云感）。
    case stardust = "stardust"
    /// 深空苍穹：近黑四层景深 + 等离子青（2026-10-16 新增 —— 交付件 `Docs/design/theme-deepspace-spec.html`
    /// 的实现规范；人类主人令「做一个深空苍穹主题」）。
    ///
    /// 与星空紫的分工：星空紫是**靛紫**（紫罗兰色相 + 星云铺得满），深空苍穹是**近黑 + 冷光点缀**
    /// （规范页原话：科幻感来自「黑 + 微光」，不来自彩色铺底）。
    case deepSpace = "deep-space"

    public var id: String { rawValue }

    /// 显示名的文案键（中英各一条；`Core` 给键、App 用 `L(...)` 取文案 —— 与其它文案同一口径）。
    public var nameKey: LKey {
        switch self {
        case .techBlue: return .designThemeTechBlue
        case .beanGreen: return .designThemeBeanGreen
        case .roseGold: return .designThemeRoseGold
        case .stardust: return .designThemeStardust
        case .deepSpace: return .designThemeDeepSpace
        }
    }

    /// 这一组值**是不是推导草案**（Linux 侧实际色值未到）。
    ///
    /// 为什么要能在代码里问这一句：界面要在「待值」的主题旁边如实标出来（不许把推导值当实际值卖），
    /// 门禁也要据此检查「待值登记还在、没被静默删掉」。
    ///
    /// 2026-10-01（T-20261001-031）：原先写成「不是科技蓝就算推导」—— 星空紫的值来自需求提出者
    /// 给的观感（NASA 韦伯「宇宙悬崖」NGC 3324 取色），是**实际值**；按旧写法它会被界面标成
    /// 「推导草案」，那就是在界面上说假话。改成逐主题点名，新增主题必须显式决定自己算不算推导。
    ///
    /// 2026-10-16：**深空苍穹也不算推导草案** —— 深色侧的每个值都来自交付件
    /// `Docs/design/theme-deepspace-spec.html` 的令牌表（给定值，不是本侧凑的）；只有**浅色侧**
    /// 一整套是本侧按同一套门槛推导的，那半边在值表注释与《外观方案》§9 里**逐条标着「推导」**
    /// （它不属「等 Linux 侧实际色值」这件事 —— 深空苍穹是本侧新增主题，Linux 侧无对应）。
    public var isDerivedDraft: Bool { self == .beanGreen || self == .roseGold }

    /// 这一主题**要不要画「星云皮肤」**（2026-10-16 泛化）。
    ///
    /// 从前这件事写死在 `NebulaSkinPreference.paintsNebula` 里（`theme == .stardust`），
    /// 于是「哪些主题有星云」这一条**只能有一个答案**：新主题想画云气就得改那个函数
    /// （规范页 §三 点名禁止的「为某个主题单写分支」）。
    /// 现在反过来：**由主题自己声明**，`NebulaSkinPreference` 只负责「声明 ∧ 开关」这个组合。
    ///
    /// 为什么两个主题都画：星空紫的星云是「云气 + 星点」（紫罗兰），深空苍穹的是「角落星云」
    /// （规范页 §二② 的紫 / 青 / 品红三色，只走边角）。两者共用同一套绘制（`NebulaBackground`），
    /// 只是强度与色调跟着主题走。
    public var paintsNebula: Bool {
        switch self {
        case .stardust, .deepSpace: return true
        case .techBlue, .beanGreen, .roseGold: return false
        }
    }

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
        case .stardust: return .stardust
        // 深空苍穹：**自带配套强调色「深空蓝」**（`AccentTheme.deepSpace` = `#007CE8`）。
        // 为什么不是 `#5EEAD4`（规范页的主强调）：交互强调色要过「白底 ≥3.0」那一档，
        // 而 `#5EEAD4` 白底实测只有 **1.48** —— 它只适合当深底上的**发光 / 文字**（值表里的
        // `accent` 就是它），当选中条 / 主按钮 / 焦点环的填充色不达标。
        // 为什么不是复用「深海青」`#17A2A2`：它白底只剩 3.12，而本主题的浅色面板（`#F1F4F8`）
        // 会把它压到 **2.83** ⇒ `DesignThemeTests.testEachThemeHasAMatchingAccentVisibleOnItsOwnSurfaces`
        // 当场判红；把它压暗又会被判「与既有六个候选太像」（`testCandidatesAreDistinguishableFromEachOther`）。
        // 三条约束（白底 / 每个主题的深色底 / 与既有候选 ≥0.3）一交，青族里可用的只剩**偏蓝的深青蓝**：
        // `#007CE8`（色相 208°，正是规范页 `accent.alt #60A5FA` 那一族的深版）——
        // 白底 4.17 / 自身浅色面板 3.77 / 自身深色底 4.62 / 与最近候选距离 0.323，四条全过。
        case .deepSpace: return .deepSpace
        }
    }

    /// 这一主题的完整值表。
    public var palette: ThemePalette { ThemePalette.of(self) }

    /// 用户可选的顺序 = 界面里的顺序（科技蓝在首位：它是默认值，也是 Linux 侧同名的那一个）。
    /// 2026-10-16：深空苍穹排在星空紫之后（两个「深」主题相邻，再往后是两组浅底主题）。
    public static let all: [DesignTheme] = [.techBlue, .stardust, .deepSpace, .beanGreen, .roseGold]

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
        case .stardust: return .stardust
        case .deepSpace: return .deepSpace
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
        accentTeal: ThemeColor(light: 0x0F7F7A, dark: 0x86D8E8),
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

    // MARK: 星空紫（2026-10-01 新增 · 需求提出者定「比科技蓝更梦幻」的那一档）
    //
    // 设计意图（三条输入信号）：
    //   · **科技派** —— 不能甜腻、不能粉嫩，要冷冽的科技感；
    //   · **星际猎人** —— 宇宙 / 星云 / 扫描 / 能量，深空 + 荧光；
    //   · **比科技蓝更梦幻** —— 不是「更亮的蓝」，要有质变。
    //
    // 三个手法：
    //   ① **色相左移**：蓝 `#4E6FFF` → 紫罗兰 —— 紫在光谱上紧邻蓝，**邻近不突兀**，但自带星云 / 极光 / 深海荧光的联想；
    //   ② **深底偏靛**：深色不是「黑蓝」而是**靛紫**（`content = #241356`），像深空而不像夜色；
    //   ③ **辉光层**：`accentGlow` 取更亮的紫罗兰，模拟星云发光 —— 语法 `keyword` 挂它，代码高亮自带光感。
    //
    // **为什么紫色比蓝色难做**（实测记录，留给后来者）：WCAG 相对亮度的通道权重是
    // `R 0.2126 / G 0.7152 / B 0.0722` —— 紫色主要靠 **B 通道**提亮，而 B 的权重**最低**，
    // 所以「紫调表面」的亮度天然上不去、五档容易挤成一团。
    // 本组因此**刻意把 B 的绝对值放大**（`window #0A0618` → `raised #4723A0`，B 通道跨 24 → 160），
    // 靠 B 的大跨度换取「表面距离 ≥0.02」与「亮度严格递增」同时成立。
    // （另注：判据 `check-design-themes.py` 的表面距离是 **RGB 欧氏距离**，不是亮度差 ——
    //   按亮度差去调参会得出「科技蓝自己都过不了」的错误结论，已踩过。）

    public static let stardust = ThemePalette(
        id: .stardust,
        window: ThemeColor(light: 0xE4E7ED, dark: 0x0C1018),
        sidebar: ThemeColor(light: 0xE7E9ED, dark: 0x141B2A),
        content: ThemeColor(light: 0xFFFFFF, dark: 0x1B2436),
        panel: ThemeColor(light: 0xE7E9ED, dark: 0x25314A),
        raised: ThemeColor(light: 0xFFFFFF, dark: 0x333F5E),
        textBright: ThemeColor(light: 0x0A0F1C, dark: 0xF0F3FA),
        textPrimary: ThemeColor(light: 0x1A2334, dark: 0xC8D2E8),
        textSecondary: ThemeColor(light: 0x4E5C78, dark: 0x8E9CB8),
        textTertiary: ThemeColor(light: 0x6A7A96, dark: 0x6B7A96),
        textDisabled: ThemeColor(light: 0xAFB8CC, dark: 0x49556B),
        success: ThemeColor(light: 0x16704A, dark: 0x4ADE80),
        warning: ThemeColor(light: 0x92600B, dark: 0xFBBF24),
        danger: ThemeColor(light: 0xC2321F, dark: 0xF87171),
        accent: ThemeColor(light: 0x4F5FD8, dark: 0x8FA6FF),
        accentGlow: ThemeColor(light: 0x4053CC, dark: 0xB8C4FF),
        accentSoft: ThemeColor(light: 0x5A6485, dark: 0x5D6C8C),
        accentTeal: ThemeColor(light: 0x0F7F7A, dark: 0x7FD8C4),
        accentWarm: ThemeColor(light: 0x8A6A3B, dark: 0xC9B27A),
        hairlineLight: 0xCFD4DE,
        hairlineDarkAlpha: 0.10
    )

    // MARK: 深空苍穹（2026-10-16 · 交付件 `Docs/design/theme-deepspace-spec.html`）
    //
    // **深色侧 = 规范页的给定值**（逐条对得上，不是本侧凑的）：
    //   · 四层底 `bg.base #05070D` → `window`｜`bg.panel #0A0F1A` → `sidebar`｜
    //     `bg.card #111827` → `content`；机制要**五档**表面，规范只给四层 ⇒ 由后两层之间
    //     再推 `panel #18202F` / `raised #1F2940`（每档只挪一点点明度，保持「近黑」的观感）；
    //   · `border.subtle #1B2436` → 折成既有的「白 × 透明度」口径（`hairlineDarkAlpha` 0.10，
    //     与另外四个主题同值 —— 这一档是**机制口径**，不是某一主题的审美）；
    //   · 文字：`text.primary #E6EDF7` → `textPrimary`｜`text.secondary #94A3B8` → `textSecondary`｜
    //     `text.disabled #64748B` → `textDisabled`；机制要五档 ⇒ `textBright` 提亮到 `#F2F6FC`
    //     （强对比 ≥7 那一档）、`textTertiary` 取 `#7C8CA3`（辅助 ≥3.0 那一档）。
    //   · 强调：`accent.primary #5EEAD4` → `accent`（等离子青）｜`accent.alt #60A5FA` → `accentGlow`；
    //     `accentTeal` / `accentWarm` / `accentSoft` 是**语法六档与分类色要用的角色**（规范页没给）
    //     ⇒ 本侧按「同一族色相铺开」推：`#2DD4BF`（更沉的青，给数字）· `#D9B48F`（暖砂，给字符串）·
    //     `#5A6B85`（低饱和青灰，只做装饰）。
    //
    // **浅色侧 = 本侧推导**（规范页只给了深色；按同一套门槛与同一套结构推一遍）：
    //   · 表面 = 冷灰蓝四级（`content` 纯白最亮，浅色不变式）；文字四档往深走；
    //   · 强调家族下压到白底可读（`accentGlow #1D4ED8` / `accentTeal #0F766E` / `accent #0E7490`）。
    //   · 表面四档与另外几套同构（`content` 白 → `panel`/`sidebar` 冷灰蓝 → `window` 再低一档）——
    //     **不自创「近白面板」那种偏门档**：面板与内容之间的距离（`ColorContrast.distance` 口径）
    //     必须 ≥0.02，把面板压到近白就只剩 0.0134（实测被 `DesignTokensTests` 当场判红）。
    //
    // **与规范页的一处显式偏离（如实登记）**：规范 §二⑤ 的深色语义色给的是 `#34D399`，
    //   本表用**全部主题共用的** `#4ADE80`（成功）/ `#FBBF24`（警告）/ `#F87171`（危险）——
    //   仓内有一条更硬的纪律「语义色的色相不随主题漂移」（`DesignThemeTests.testStatusHuesDoNotDriftAcrossThemes`
    //   逐值对账），且语义色本来就不该成为某一主题的装饰。色相同为绿 / 黄 / 红，观感一致。
    public static let deepSpace = ThemePalette(
        id: .deepSpace,
        window: ThemeColor(light: 0xEAEEF4, dark: 0x05070D),
        sidebar: ThemeColor(light: 0xF1F4F8, dark: 0x0A0F1A),
        content: ThemeColor(light: 0xFFFFFF, dark: 0x111827),
        panel: ThemeColor(light: 0xF1F4F8, dark: 0x18202F),
        raised: ThemeColor(light: 0xFFFFFF, dark: 0x1F2940),
        textBright: ThemeColor(light: 0x0B111C, dark: 0xF2F6FC),
        textPrimary: ThemeColor(light: 0x1C2534, dark: 0xE6EDF7),
        textSecondary: ThemeColor(light: 0x46536B, dark: 0x94A3B8),
        textTertiary: ThemeColor(light: 0x5D6B85, dark: 0x7C8CA3),
        textDisabled: ThemeColor(light: 0xA6B0C2, dark: 0x64748B),
        success: ThemeColor(light: 0x16704A, dark: 0x4ADE80),
        warning: ThemeColor(light: 0x92600B, dark: 0xFBBF24),
        danger: ThemeColor(light: 0xC2321F, dark: 0xF87171),
        accent: ThemeColor(light: 0x0E7490, dark: 0x5EEAD4),
        accentGlow: ThemeColor(light: 0x1D4ED8, dark: 0x60A5FA),
        accentSoft: ThemeColor(light: 0x54657F, dark: 0x5A6B85),
        accentTeal: ThemeColor(light: 0x0F766E, dark: 0x2DD4BF),
        accentWarm: ThemeColor(light: 0x8A6A3B, dark: 0xD9B48F),
        hairlineLight: 0xC9D6E5,
        hairlineDarkAlpha: 0.10
    )
}

// MARK: - 星云皮肤的配色（值表的一部分：新主题想说「我也有云气」，不必改绘制代码）

/// 一团云气的**配色**（色值 + 基础透明度）。
///
/// **位置 / 半径 / 层倍率不在这里** —— 那是绘制侧的形状（`App/Views/NebulaBackground.swift`）；
/// 归到值表的是「这个主题的云气是什么颜色、多浓」，与令牌值同一条纪律：
/// **换主题 = 换一组值**，不为某个主题改代码。
public struct NebulaCloud: Equatable, Sendable {
    public var hex: UInt32
    /// 基础透明度（绘制侧再乘该层的强度倍率：阅读区更克制）。
    public var alpha: Double

    public init(hex: UInt32, alpha: Double) {
        self.hex = hex
        self.alpha = alpha
    }
}

/// 一个主题的星云皮肤配色。
public struct NebulaSkinTones: Equatable, Sendable {
    /// 深色态逐团云气（顺序对应绘制侧的形状表；多了会被忽略，少了就是没铺满）。
    public var cloudsDark: [NebulaCloud]
    /// 浅色态逐团云气（浅色下云气更淡）。
    public var cloudsLight: [NebulaCloud]
    /// 星点三档色（最亮 / 中 / 暗）。
    public var starTints: [UInt32]
    /// 亮星的星芒色。
    public var brightStarTint: UInt32

    public init(cloudsDark: [NebulaCloud], cloudsLight: [NebulaCloud],
                starTints: [UInt32], brightStarTint: UInt32) {
        self.cloudsDark = cloudsDark
        self.cloudsLight = cloudsLight
        self.starTints = starTints
        self.brightStarTint = brightStarTint
    }
}

public extension DesignTheme {

    /// 这一主题的星云配色（只有 `paintsNebula` 为真的主题才有内容）。
    ///
    /// 星空紫 = NASA「宇宙悬崖」的法（靛蓝为主、边缘透紫）；
    /// 深空苍穹 = 规范页 §二② 的法（紫 `#7C5CFF` / 青 `#38BDF8` / 品红 `#F472B6`，
    /// **只走边角**，所以基础透明度整体比星空紫更低一档）。
    var nebulaTones: NebulaSkinTones {
        switch self {
        case .stardust:
            return NebulaSkinTones(
                cloudsDark: [NebulaCloud(hex: 0x1E3A6E, alpha: 0.50),
                             NebulaCloud(hex: 0x2A4A82, alpha: 0.34),
                             NebulaCloud(hex: 0x3A2F6B, alpha: 0.30),
                             NebulaCloud(hex: 0x16264A, alpha: 0.44),
                             NebulaCloud(hex: 0x4A3D7A, alpha: 0.22)],
                cloudsLight: [NebulaCloud(hex: 0xD8E0F5, alpha: 0.55),
                              NebulaCloud(hex: 0xC8D4F0, alpha: 0.38),
                              NebulaCloud(hex: 0xE0D8F0, alpha: 0.32),
                              NebulaCloud(hex: 0xE8EDF8, alpha: 0.42)],
                starTints: [0xE4D7F8, 0xD8E0FA, 0xC0CCE8],
                brightStarTint: 0xE4D7F8
            )

        case .deepSpace:
            return NebulaSkinTones(
                cloudsDark: [NebulaCloud(hex: 0x7C5CFF, alpha: 0.30),
                             NebulaCloud(hex: 0x38BDF8, alpha: 0.26),
                             NebulaCloud(hex: 0xF472B6, alpha: 0.16),
                             NebulaCloud(hex: 0x35507F, alpha: 0.34)],
                cloudsLight: [NebulaCloud(hex: 0xDCE6F5, alpha: 0.52),
                              NebulaCloud(hex: 0xE4EEFA, alpha: 0.36),
                              NebulaCloud(hex: 0xE8E4F6, alpha: 0.26),
                              NebulaCloud(hex: 0xF0F4FA, alpha: 0.40)],
                starTints: [0xE6F6FF, 0xD8E8FA, 0xC2D4E8],
                brightStarTint: 0xE6F6FF
            )

        // 其余三个主题不画星云（`paintsNebula == false`）—— 值仍然给一份「中性空表」，
        // 免得将来有人误以为「空数组」是漏写（绘制侧根本不会走到这里）。
        case .techBlue, .beanGreen, .roseGold:
            return NebulaSkinTones(cloudsDark: [], cloudsLight: [], starTints: [], brightStarTint: 0xFFFFFF)
        }
    }
}
