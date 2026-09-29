import Foundation

/// 强调色主题（FR-EDIT-33）。
///
/// 放在 Core 而不是 App：这是**纯数据 + 纯函数**（解析、回退、色值换算、对比度），
/// 不打开图形界面就能单测；`NSColor` / `Color` 的绑定留在 App 层（与 `Localization` 同构）。
///
/// **为什么每个强调色有两个色值**（这不是冗余，是实测出来的）：
/// - `accent` 用于「选中行淡填充 / 左侧强调条 / 图标 / 焦点环」——它是跟**表面**比，
///   门槛是 WCAG 对 UI 组件的 3.0；
/// - `fill` 用于**实心按钮**，上面压白字 —— 门槛是正文的 4.5。
///
/// 同一个亮度做不到两件事都合格：实测 `#4E6FFF` 上白字只有 **4.17**、`#17A2A2` 只有 **3.12**
/// （都不够 4.5），所以 `fill` 是压暗过的那一档。这条由 `AccentThemeTests` 守着。
public struct AccentTheme: Equatable, Sendable, Identifiable {

    /// 持久化用的稳定标识 —— **不随界面语言变化**（否则切一次语言就把用户的选择丢了）。
    public let id: String
    /// 显示名的文案键。
    public let nameKey: LKey
    /// 主色：选中条 / 图标 / 焦点环 / 淡填充底色。
    public let accentHex: UInt32
    /// 实心填充（压白字，必须过 WCAG AA 4.5）。
    public let fillHex: UInt32

    public init(id: String, nameKey: LKey, accentHex: UInt32, fillHex: UInt32) {
        self.id = id
        self.nameKey = nameKey
        self.accentHex = accentHex
        self.fillHex = fillHex
    }

    // MARK: 三个候选
    //
    // 其中两个取自 dsh-tui 鲸鱼自身的调色板（在其源码里量到的 B 与心形 H）：
    // 这样"品牌色"与用户每天看到的那个 TUI 是同源的，而不是我另外挑的。

    /// 鲸鱼蓝（`B[78,111,255]`）。
    public static let whaleBlue = AccentTheme(
        id: "whale-blue",
        nameKey: .accentWhaleBlue,
        accentHex: 0x4E6FFF,
        fillHex: 0x3B57E0
    )

    /// 深海青 —— 与红 / 橙告警区分度最大。
    public static let deepTeal = AccentTheme(
        id: "deep-teal",
        nameKey: .accentDeepTeal,
        accentHex: 0x17A2A2,
        fillHex: 0x0F7F7F
    )

    /// 鲸心品红（心形 `H[204,51,153]`）。
    public static let whaleMagenta = AccentTheme(
        id: "whale-magenta",
        nameKey: .accentWhaleMagenta,
        accentHex: 0xCC3399,
        fillHex: 0xB02A83
    )

    // MARK: 主题配套的两个（L-80 ㈠，**推导草案**）
    //
    // 主题「豆芽绿」「玫瑰金」各自要一个**同色相**的交互强调色（否则换主题只换了一半：
    // 豆芽绿的界面里杵着一个鲸鱼蓝按钮）。Linux 侧的实际色值未到 ⇒ 这两个值也是推导值，
    // 与那两个主题的值表**一起替换**。两者都过了"白字压填充 ≥4.5"与"在自身两态表面上 ≥3.0"。

    /// 豆芽绿的配套强调色（嫩芽绿系，**推导值**）。
    public static let beanGreen = AccentTheme(
        id: "bean-green",
        nameKey: .accentBeanGreen,
        accentHex: 0x468C33,
        fillHex: 0x347A28
    )

    /// 玫瑰金的配套强调色（暖粉金系，**推导值**）。
    public static let roseGold = AccentTheme(
        id: "rose-gold",
        nameKey: .accentRoseGold,
        accentHex: 0xBE6A62,
        fillHex: 0x9C4A42
    )

    /// 全部候选。
    ///
    /// 界面不再逐条列强调色（「外观」面板的强调色列表**升格为主题下拉**，每个主题自带配套值，
    /// 见 `DesignTheme.accent`）；这一份集合仍然要有两个用途：
    ///   ① **解析旧配置** —— 用户以前挑过的 `deep-teal` / `whale-magenta` 得继续认得出来；
    ///   ② 给「几个强调色彼此可分辨」「配套值不是随便挑的」这类判据提供全集。
    public static let all: [AccentTheme] = [whaleBlue, deepTeal, whaleMagenta, beanGreen, roseGold]

    /// 默认与回退都是鲸鱼蓝（与 App 图标同系）。
    public static let fallback = AccentTheme.whaleBlue

    /// 由持久化的 id 解析；**未知 id 一律回退而不是报错** ——
    /// 配置文件被手改、或将来删掉某个候选时，界面都必须照常起来。
    public static func resolve(id: String?) -> AccentTheme {
        guard let id, !id.isEmpty else { return fallback }
        return all.first { $0.id == id } ?? fallback
    }

    /// 偏好设置里的存储键（与工程内其它 UI 偏好同一套 `ui.` 前缀）。
    public enum Storage {
        public static let key = "ui.accentTheme"
    }

    // MARK: 色值与对比度
    //
    // 计算本身收在 `ColorContrast`（全工程唯一一份），这里只做转调 ——
    // 避免"强调色"和"设计令牌"各算一套对比度、两套阈值。

    /// 把 `0xRRGGBB` 拆成 0...1 的分量。
    public static func components(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        ColorContrast.components(hex)
    }

    /// WCAG 相对亮度。
    public static func relativeLuminance(_ hex: UInt32) -> Double {
        ColorContrast.relativeLuminance(hex)
    }

    /// WCAG 对比度（1...21）。
    public static func contrastRatio(_ lhs: UInt32, _ rhs: UInt32) -> Double {
        ColorContrast.ratio(lhs, rhs)
    }
}
