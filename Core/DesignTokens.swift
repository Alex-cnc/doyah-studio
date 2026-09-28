import Foundation

// MARK: - 设计令牌（FR-EDIT-33 的落地底座）
//
// 这一层存在的理由，是量出来的：改造前 App/ 里
//   · 显式字号只有 3 个（14 / 15 / 9），其余全靠默认 `.body` → 没有排版级差；
//   · padding 值里 `2` 出现 139 次，还混着 1 / 3 / 6 / 10 / 12 / 20 / 150 → 没有刻度；
//   · 颜色是零散的系统色 + 裸 `Color.orange/.red/.blue` → 同一种"警告橙"在不同面板里不是同一个橙。
//
// 所以令牌层做三件事：**刻度化、语义化、可校验**。
// 它只放纯数据（十六进制 + 数值），平台绑定（NSColor / Font / Color）在 App/AppTheme.swift ——
// 这样 Core 不 import AppKit，而全部数值都能单测（`DesignTokensTests`）。
//
// **用法规矩（很重要，写在这里免得日后走样）**
//   1. 间距只用 `Spacing` 里的值；确需 1pt 像素微调时用 `Metrics.hairline`，不要新造数字。
//   2. 表面层次靠**明度差 + 发丝线**，不靠描边：`window < sidebar/content/panel < raised`（深色由暗到亮）。
//   3. 浅色主题下 `raised` 与 `content` 同为白色，**浮层必须靠外加发丝线或阴影**才能看出来；
//      因此"页签条 / 分段控件的轨道"要用 `panel`，选中块才用 `raised` ——
//      两者都铺在 `content` 上时，选中块是看不见的（这是浅色界面最常见的一处走样）。
//   4. 强调色**不在这一层**：交互强调色（选中态 / 主按钮 / 焦点环）由用户配置（`AccentTheme`），
//      这里只放**方案 D 的强调色家族**（`AccentFamily`）—— 它是**基准值**，用于装饰性 / 语义性着色
//      （链接、语法、度量值、次级描边），不参与"用户换强调色"那条路。两条路各有单测把守。
//
// **色值来源（2026-09-29 起）= 外观方案 D · 科技蓝**：需求提出者提供参考图、逐像素统计取色，
// 全量值与门槛见 `Docs/design/外观方案-v1.md` §8（契约登记：`Docs/概要设计.md` §3.9 / v2.74）。
// 本文件里的每个色值都能在 §8 找到出处；§8 未给值的少数角色（浅色 `raised` / `disabled` /
// `textBright` / `accentSoft` / 浅色 `window`）在各自位置逐条写明"为什么取这个值"，并如实登记
// 为**推导值**（一句话可推翻）—— 不许出现第四条路：悄悄换掉一个没人记得的值。

/// 间距刻度（4 / 8 网格；`hair` 是唯一的例外，用于图标与文字之间的紧贴）。
public enum Spacing {
    public static let hair: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32

    /// 允许出现的全部取值 —— 校验脚本按它判断"裸数字"。
    public static let scale: [CGFloat] = [hair, xs, s, m, l, xl, xxl]

    public static func isOnScale(_ value: CGFloat) -> Bool {
        scale.contains(value)
    }
}

/// 圆角刻度。
public enum Radius {
    /// 发丝级圆角：给 2pt 强调条这类"线"用（线的圆角只能是线宽的一半）。
    public static let hairline: CGFloat = 1
    public static let badge: CGFloat = 4
    public static let control: CGFloat = 6
    public static let card: CGFloat = 8
    public static let panel: CGFloat = 10

    public static let scale: [CGFloat] = [hairline, badge, control, card, panel]
}

/// 度量：尺寸类常量。
public enum Metrics {
    /// 发丝线（1 物理像素 @2x）。
    public static let hairline: CGFloat = 0.5
    /// 标签 / 列表 / 表格行高 —— "紧凑但留白严格"的具体含义。
    public static let rowHeight: CGFloat = 26
    /// 树 / 列表行的**内容高度**（对象树、工作区文件树共用）。
    ///
    /// 2026-09-24 由 26 收到 **20**（两步：先 26 → 22 修"太松散"，再按需求提出者点名的目标值收到 20）。
    /// 起因：「层级行与行的间隔太大了，显得很松散，表稍微多一点就要向下拉滚动条」。
    /// 实测当时的**行距是 34pt 而内容只有 26pt** —— 多出来的是 `List` 给的行距，
    /// 而且 `listRowInsets` / 负内边距 / `defaultMinListRowHeight` 对它**全都无效**（都试过）。
    /// 所以真正的修法是**把整棵树放进一个 `List` 行**（`ObjectTreeView` 里的 `VStack(spacing: 0)`），
    /// 行距从此等于这个令牌。20pt 仍放得下 caption 字与 12pt 图标（实测行距 = 20pt）。
    public static let listRowHeight: CGFloat = 20

    public static let tabHeight: CGFloat = 30
    public static let toolbarHeight: CGFloat = 44
    public static let statusBarHeight: CGFloat = 24
    public static let controlHeight: CGFloat = 26
    /// 侧栏宽度（对象树 / 工作区）。
    public static let sidebarWidth: CGFloat = 248
    /// 最左侧活动栏宽度（FR-EDIT-32）。
    public static let activityBarWidth: CGFloat = 46
    /// 活动栏图标边长。
    public static let activityIconSize: CGFloat = 20
    /// 列表 / 树的层级缩进步长（对象树、工作区文件树共用）。
    public static let listIndent: CGFloat = 14

    // MARK: 面板尺寸（按内容算出来的那些）

    /// 「执行计划」面板（FR-DIAG-01）的宽度 —— **高度不写死**，由内容决定。
    ///
    /// 2026-09-27 人工点验反馈：「Explain text 弹出对话框布局有问题，窗口特别高，
    /// 上下两块很大的空白区域」。根因是这里原先把面板高写死 620、计划树 220、原始输出 110：
    /// 内容只有几行时，两个框就是两大片空白，窗口再高也跟内容无关。
    /// 现在两块区的高度一律**按行数算**（`行数 × 行高`，夹在 [min, max] 内），
    /// 超过上限才滚动 —— 内容少时面板自然变矮。
    public static let planPanelWidth: CGFloat = 720
    /// 面板高度的下限（空态/报错时也留一点体面，但不再是 620 那种空高度）。
    public static let planPanelMinHeight: CGFloat = 160
    /// 计划树区：上下限 + 每行高度（与 `listRowHeight` 一致，树里就是列表行）。
    public static let planTreeMinHeight: CGFloat = 56
    public static let planTreeMaxHeight: CGFloat = 320
    /// 原始输出区：上下限 + 每行高度（等宽小字）。
    public static let planRawMinHeight: CGFloat = 48
    public static let planRawMaxHeight: CGFloat = 260
    public static let planRawLineHeight: CGFloat = 15
    /// 工具条上的图标按钮尺寸（28 × 22）。
    public static let toolbarButtonWidth: CGFloat = 28
    public static let toolbarButtonHeight: CGFloat = 22
    /// 结果表列的宽度上下限（估算出来的宽度会被夹在这个区间里）。
    public static let minColumnWidth: CGFloat = 40
    public static let maxColumnWidth: CGFloat = 420
    /// 列宽估算时采样多少行（再多也不影响判断，白花时间）。
    public static let columnWidthSampleRows: Int = 100
}

/// 叠加层的透明度：**选中态与斑马纹的深浅只在这里定义一次**。
///
/// 原先它们散在视图里当魔法数字（`0.14` / `0.02`…），改了主题色也不会跟着动；
/// 而且"选中态该多重"是个需要统一的口径 —— 活动栏、侧栏、结果表必须是同一个值，
/// 否则同样的"选中"在三处看起来深浅不一。`DesignTokensTests` 会守住合理区间，
/// 防止手滑写成 0.4 那种一眼就"糊"了的程度。
public enum Overlay {
    public enum Selection {
        public static let darkAlpha: Double = 0.14
        public static let lightAlpha: Double = 0.10
    }

    public enum Zebra {
        public static let darkAlpha: Double = 0.02
        public static let lightAlpha: Double = 0.015
    }
}

// MARK: - 颜色语义

/// 一个颜色在两套主题下的取值（十六进制）。
public struct ThemeColor: Equatable, Sendable {
    public let light: UInt32
    public let dark: UInt32

    public init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    public func hex(dark isDark: Bool) -> UInt32 { isDark ? dark : light }
}

/// 表面（层次由暗到亮：window → sidebar → content → panel → raised）。
///
/// 语义而不是色值：视图里写 `Surface.panel` 而不是 `#15263A`，
/// 这样换配色只改这一处，也不会出现"表头用了三个不同的灰"。
///
/// 2026-09-29（L-79 ㈠）：深色由**中性灰**换成方案 D 的**深海军蓝**（§8.1），
/// 浅色按同一套色相派生（§8.5）。深色五档的明度**严格递增**（这是不变式，有单测守着）。
public enum Surface: String, CaseIterable, Sendable {
    case window
    case sidebar
    case content
    case panel
    case raised

    public var color: ThemeColor {
        switch self {
        // 深色五档 = §8.1 原值（逐像素统计取色）。
        // 浅色档：
        //   · sidebar / panel / content = §8.5 原值（content 白、sidebar 与 panel 同 #F4F7FB）；
        //   · raised = #FFFFFF：**沿用既有规矩 3**（浅色下 raised 与 content 同为白，浮层靠发丝线 / 阴影
        //     区分）；§8.5 没给 raised，改了反而会造出"浅色下浮层比内容还亮"的走样。
        //   · window = #F1F5FA：**推导值，且是对 §8.5 的一处显式偏离** —— §8.5 写 window 与 content 同为
        //     #FFFFFF，但既有判据要求"window 必须与 content 可区分"（距离 ≥0.02，见 §3.9 跨平台不变量），
        //     两白相等会当场判红。取比 sidebar 再低一档的同色相浅蓝（距离 content 0.041、比 content 暗），
        //     实际观感与白无异（window 在 chrome 铺满时本来就看不见）。一句话可推翻。
        case .window: return ThemeColor(light: 0xF1F5FA, dark: 0x02070A)
        case .sidebar: return ThemeColor(light: 0xF4F7FB, dark: 0x081420)
        case .content: return ThemeColor(light: 0xFFFFFF, dark: 0x0B1A2A)
        case .panel: return ThemeColor(light: 0xF4F7FB, dark: 0x15263A)
        case .raised: return ThemeColor(light: 0xFFFFFF, dark: 0x1D3350)
        }
    }
}

/// 文本层级。
public enum TextTone: String, CaseIterable, Sendable {
    /// 最高对比（方案 D 新增，令牌名 `textBright`）：窗口 / 面板标题、关键数值。
    /// 深色 #EFF8FA 是对 window 的 18.78（≥7 的"强对比"档）；浅色一律往深里走（同色相）。
    case bright
    case primary
    case secondary
    case tertiary
    /// 禁用态：比三级更淡。WCAG 对"非活动控件"不做对比度要求，
    /// 但它**必须仍能看出"这里有个东西、只是现在不能用"**，所以有下限（见单测）。
    case disabled

    public var color: ThemeColor {
        switch self {
        // 深色档全部 = §8.2 原值（含"参考图直接取到的 #415F86 只有 3.09、不够正文故上提"那条）。
        // 浅色档 = §8.5 原值 **除** 两处推导值（逐条写在下面）。
        case .bright: return ThemeColor(light: 0x061426, dark: 0xEFF8FA)
        case .primary: return ThemeColor(light: 0x10243D, dark: 0xCAD0DC)
        case .secondary: return ThemeColor(light: 0x45607F, dark: 0x8594B1)
        // 辅助信息（表头 / 行号 / 状态栏）：**深浅同值** #5C7CA6 —— 它不是"两套色"，而是
        // 参考图里那个中间调（§8.2 明写 `#415F86` 不够、上提到 #5C7CA6 的那一档）。
        // 同一个中间调在白底上是 4.30、在深蓝底上是 4.09，两态都过 3.0 的辅助门槛，
        // 故不再另造一个浅色值（§8.5 未给 textTertiary）。
        case .tertiary: return ThemeColor(light: 0x5C7CA6, dark: 0x5C7CA6)
        // 深色 = 参考图里**采样到的**中间调 #415F86（§8.2 提到它不够做正文，做"禁用"正合适：
        // 2.68 > 1.5 的下限、且比三级文本淡）；
        // 浅色 = 推导值 #A9B7CC（同色相的浅蓝灰：2.03，仍满足"比三级淡、又不至于看不见"）。
        case .disabled: return ThemeColor(light: 0xA9B7CC, dark: 0x415F86)
        }
    }
}

/// 状态色（成功 / 警告 / 危险）。
///
/// 2026-09-29（方案 D）：深色 #4ADE80 / #FBBF24 / #F87171，浅色 #16704A / #92600B / #C2321F
/// —— 两态都是 §8.3 / §8.5 原值（对 window / 白底 7.32 ~ 12.13，均过门槛）。
public enum StatusTone: String, CaseIterable, Sendable {
    case success
    case warning
    case danger

    public var color: ThemeColor {
        switch self {
        case .success: return ThemeColor(light: 0x16704A, dark: 0x4ADE80)
        case .warning: return ThemeColor(light: 0x92600B, dark: 0xFBBF24)
        case .danger: return ThemeColor(light: 0xC2321F, dark: 0xF87171)
        }
    }
}

/// **分类色**：用于标识**身份**（数据库引擎徽标、标签），不是状态。
///
/// 与状态色分开是有意的：把 GBase 的橙当成"警告"会让状态色失去含义 ——
/// 用户看到橙色分不清"这是这个引擎的颜色"还是"这里有问题"。
/// 分类色（身份色，不是状态色）。
///
/// `Codable` 是 FR-CONN-16 需要：连接的**自选颜色**按**名字**存（`"teal"`），
/// 不存具体色值 —— 色值随主题演化，存了它就要为"颜色改了、旧配置怎么办"再写一次迁移。
///
/// **方案 D 未给分类色**（§8 只给了表面 / 文本 / 强调家族 / 语义 / 语法）：本轮**不动**，
/// 实测这四色在 D 的 content（#0B1A2A）与 panel（#15263A）上仍 ≥3.0（深浅两态都够），
/// 且彼此可分辨。要按 D 的色相重排是另一件事（会改用户"认引擎"的颜色），一行话可开条。
public enum CategoricalTone: String, CaseIterable, Codable, Sendable {
    case blue
    case teal
    case magenta
    case amber

    public var color: ThemeColor {
        switch self {
        case .blue: return ThemeColor(light: 0x3B57E0, dark: 0x6E8BFF)
        case .teal: return ThemeColor(light: 0x0F7F7F, dark: 0x4FBDBD)
        case .magenta: return ThemeColor(light: 0xB02A83, dark: 0xD46FB0)
        case .amber: return ThemeColor(light: 0xB9791B, dark: 0xD9A343)
        }
    }
}

/// **强调色家族**（方案 D 新增令牌：`accent` / `accentGlow` / `accentSoft` / `teal` / `warm`）。
///
/// 与 `AccentTheme` 的分工写在类头上：这里是**基准值**（装饰性 / 语义性着色 ——
/// 活动页签下划线、链接、语法关键字、度量值、次级描边），用户可换的**交互强调色**
/// （选中态 / 主按钮 / 焦点环）仍走 `AccentTheme`。§8.3 的克制规则不变：强调色只在三处出现。
///
/// 浅色档：§8.5 给了 `accent` #2E6FA8 / 链接（= `accentGlow`）#1C63C4 / `teal` #0E7490 /
/// `warm` #8A6A3B；`accentSoft` §8.5 未给，取**深浅同值** #4C6C9B —— 它在白底上是 5.35、
/// 在 window 上是 3.78，两态都过"图标线 ≥3"的门槛（§8.3 明写它"只够图标线，不得用于正文"）。
public enum AccentFamily: String, CaseIterable, Sendable {
    case accent
    case accentGlow
    case accentSoft
    case teal
    case warm

    public var color: ThemeColor {
        switch self {
        case .accent: return ThemeColor(light: 0x2E6FA8, dark: 0x6EA8D0)
        case .accentGlow: return ThemeColor(light: 0x1C63C4, dark: 0x7AB0FA)
        case .accentSoft: return ThemeColor(light: 0x4C6C9B, dark: 0x4C6C9B)
        case .teal: return ThemeColor(light: 0x0E7490, dark: 0x94E2F8)
        case .warm: return ThemeColor(light: 0x8A6A3B, dark: 0xC7AF95)
        }
    }
}

/// 语法着色。
///
/// 2026-09-29（方案 D §8.4）：深色六档**按角色**映射到令牌 —— 关键字 = `accentGlow`、
/// 标识符 = `textPrimary`、字符串 = `warm`、数字 = `teal`、函数 = `accent`、注释 = `textTertiary`；
/// 浅色档按同一张角色表取 §8.5 的对应值（§8.5 只给了"角色 → 值"，没重复列语法表）。
/// 这就是"六档同步"的含义：换了令牌家族，语法色跟着走，不会留下孤立的旧色。
public enum SyntaxTone: String, CaseIterable, Sendable {
    case keyword
    case identifier
    case string
    case number
    case function
    case comment

    public var color: ThemeColor {
        switch self {
        case .keyword: return AccentFamily.accentGlow.color
        case .identifier: return TextTone.primary.color
        case .string: return AccentFamily.warm.color
        case .number: return AccentFamily.teal.color
        case .function: return AccentFamily.accent.color
        case .comment: return TextTone.tertiary.color
        }
    }
}

/// 发丝线颜色：不是固定的灰，而是"当前表面上的 1px 亮/暗线"。
///
/// 深色 = 白 10% 叠加（§8.1 的值）；浅色 = **实色 `#D3DCE8`**（§8.5 的值）。
/// 为什么浅色不用透明度：§8.5 给的是一个**带蓝调的实色**，用黑色透明度反算的话
/// （黑 17% 叠在白上 ≈ #D3D3D3）会丢掉那点蓝（G/B 通道差 5~9/255），
/// 而 方案 D 的浅色整套都是蓝调 —— 为省一个分支把色调丢掉不值。深色侧仍是叠加：
/// 深色五个表面跨度大（#02070A → #1D3350），白色低透明度是唯一在五面上都成立的写法。
public enum Hairline {
    /// 浅色档的实色（§8.5）。
    public static let lightHex: UInt32 = 0xD3DCE8
    /// 深色档的白色透明度（§8.1：白 10%）。
    public static let darkAlpha: Double = 0.10
}

// MARK: - 排版级差

/// 字号与字重。
///
/// 改造前全 App 只有 3 个显式字号 —— 标题、正文、表头、辅助信息长得一样，
/// 这是"简陋"最直接的来源。这里定 6 级，够用且不臃肿。
public enum TypeScale {
    /// 窗口 / 面板主标题。
    public static let displaySize: CGFloat = 17
    /// 区块标题。
    public static let titleSize: CGFloat = 15
    public static let bodySize: CGFloat = 13
    /// 数值列（配等宽数字，保证小数点对齐）。
    public static let dataSize: CGFloat = 12
    public static let monoSize: CGFloat = 12
    public static let monoSmallSize: CGFloat = 11
    public static let captionSize: CGFloat = 11

    /// 允许出现的字号（去重后的刻度）—— 校验脚本按它判断"裸字号"。
    ///
    /// 注意：`dataSize` 与 `monoSize` 是同一个字号（12）但语义不同（数值列 / 代码），
    /// 所以命名常量比刻度多 —— 由 `DesignTokensTests` 保证"每个命名常量都在刻度上"。
    public static let scale: [CGFloat] = [11, 12, 13, 15, 17]

    public static func isOnScale(_ size: CGFloat) -> Bool {
        scale.contains(size)
    }
}
