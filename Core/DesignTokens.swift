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
// **色值来源（2026-09-29 起）= 主题集**：默认主题「科技蓝」= 外观方案 D，需求提出者提供参考图、
// 逐像素统计取色；另有两个主题（豆芽绿 / 玫瑰金）的推导草案。**值表在 `Core/DesignTheme.swift`**
// （按主题分组，每个角色一份），本文件只留**角色与用法规矩**——「哪个角色长什么样」是另一条轴。
// 全量值与门槛见 `Docs/design/外观方案-v1.md` §8 / §9（契约登记：`Docs/概要设计.md` §3.9）。
// **取色必须带主题**：`Surface.panel.color(in: theme)` —— 去掉无参的 `color` 是有意的，
// 让「这一屏跟的是哪个主题」在每一处调用点都写出来（编译器替我们守这条）。
// §8 未给值的少数角色（浅色 `raised` / `disabled` / `textBright` / `accentSoft` / 浅色 `window`）
// 在值表里各自写明「为什么取这个值」，并如实登记为**推导值**（一句话可推翻）——
// 不许出现第四条路：悄悄换掉一个没人记得的值。

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
    /// 侧栏宽度（对象树 / 工作区 / 笔记面**共用一值**）。
    ///
    /// 这个值是侧栏宽度的**唯一出处** —— 视图层不许再写 `240 / 280 / 380` 这种字面量。
    /// 由头 = 2026-10-06 人类主人实机点验第 1 条「左栏太宽」的定因：它曾是**死常量**
    /// （`App/` 零命中），真正生效的是 `App/Views/MainWindow.swift` 里写死的那三档
    /// ⇒ 想调宽度只能改视图，没有单点旋钮。现在那一处（全 App 仅一处侧栏列宽规格）**三档一并读它**，
    /// 数据库 / 工作区 / 笔记三面共用，不按语境区分（派单 `T-20261006-078` §1；语境化宽度未批）。
    /// 出处 = `Docs/design/外观方案-v1.md`（侧栏宽 248）。
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
/// 这样换配色只改值表，也不会出现"表头用了三个不同的灰"。
///
/// 2026-09-29（L-79 ㈠）：深色由**中性灰**换成方案 D 的**深海军蓝**（§8.1），浅色按同一套色相派生（§8.5）；
/// 2026-09-29（L-80 ㈠）：值表按**主题**分组（`Core/DesignTheme.swift`），本枚举只留角色语义。
/// 深色五档的明度**严格递增**（这是不变式，对**每个主题**都成立，有单测守着）。
public enum Surface: String, CaseIterable, Sendable {
    case window
    case sidebar
    case content
    case panel
    case raised

    /// 这一角色在**指定主题**下的取值。没有无参版本是有意的（见文件头）。
    public func color(in theme: DesignTheme) -> ThemeColor {
        let palette = theme.palette
        switch self {
        case .window: return palette.window
        case .sidebar: return palette.sidebar
        case .content: return palette.content
        case .panel: return palette.panel
        case .raised: return palette.raised
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

    /// 这一档文本在**指定主题**下的取值。
    ///
    /// 角色级规矩（对每个主题都成立）：
    ///   · `tertiary` 是"辅助信息"那一档，**深浅同值**（它不是"两套色"，而是参考图里的中间调）；
    ///   · `disabled` 比 `tertiary` 更淡（有单测守着顺序与下限）；
    ///   · `bright` 是"强对比"档（≥7），只给标题与关键数值用。
    public func color(in theme: DesignTheme) -> ThemeColor {
        let palette = theme.palette
        switch self {
        case .bright: return palette.textBright
        case .primary: return palette.textPrimary
        case .secondary: return palette.textSecondary
        case .tertiary: return palette.textTertiary
        case .disabled: return palette.textDisabled
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

    /// 这一档状态色在**指定主题**下的取值。
    ///
    /// 角色级规矩：状态三色的**色相不随主题漂移**（成功是绿、警告是黄、危险是红）——
    /// 语义色的任务是"一眼认出这是哪一类状态"，跟着主题换色相会把它变成装饰。
    /// 三个主题目前共用同一组值（值表里逐主题写着）。
    public func color(in theme: DesignTheme) -> ThemeColor {
        let palette = theme.palette
        switch self {
        case .success: return palette.success
        case .warning: return palette.warning
        case .danger: return palette.danger
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
/// **方案 D 未给分类色**（§8 只给了表面 / 文本 / 强调家族 / 语义 / 语法）：**三个主题都不动它**，
/// 实测这四色在 D 的 content（#0B1A2A）与 panel（#15263A）上仍 ≥3.0（深浅两态都够），
/// 且彼此可分辨。要按主题色相重排是另一件事（会改用户"认引擎"的颜色），一行话可开条。
///
/// 取色**不带主题**是有意的（唯一的例外）：身份色表达的是"这是哪个引擎"，与用户选的配色无关 ——
/// 跟着主题换会让"PostgreSQL 是蓝的"这件事不再成立。这条例外由单测钉住（它必须与主题无关）。
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

    public func color(in theme: DesignTheme) -> ThemeColor {
        let palette = theme.palette
        switch self {
        case .accent: return palette.accent
        case .accentGlow: return palette.accentGlow
        case .accentSoft: return palette.accentSoft
        case .teal: return palette.accentTeal
        case .warm: return palette.accentWarm
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

    public func color(in theme: DesignTheme) -> ThemeColor {
        switch self {
        case .keyword: return AccentFamily.accentGlow.color(in: theme)
        case .identifier: return TextTone.primary.color(in: theme)
        case .string: return AccentFamily.warm.color(in: theme)
        case .number: return AccentFamily.teal.color(in: theme)
        case .function: return AccentFamily.accent.color(in: theme)
        case .comment: return TextTone.tertiary.color(in: theme)
        }
    }
}

/// 发丝线颜色：不是固定的灰，而是"当前表面上的 1px 亮/暗线"。
///
/// 深色 = 白 `darkAlpha` 叠加（§8.1 的值，三个主题共用 10%）；浅色 = 各主题自己的**实色**
/// （科技蓝 `#D3DCE8` / 豆芽绿 `#D5E3D9` / 玫瑰金 `#F0D9D5`）。
/// 为什么浅色不用透明度：§8.5 给的是一个**带色相的实色**，用黑色透明度反算的话
/// （黑 17% 叠在白上 ≈ #D3D3D3）会丢掉那点色相（G/B 通道差 5~9/255），
/// 而每个主题的浅色整套都是同色相的 —— 为省一个分支把色调丢掉不值。深色侧仍是叠加：
/// 深色五个表面跨度大（最暗 #02070A → 最亮 #42262E），白色低透明度是唯一在五面上都成立的写法。
public enum Hairline {
    /// 浅色档的实色（随主题；见 `ThemePalette.hairlineLight`）。
    public static func lightHex(in theme: DesignTheme) -> UInt32 {
        theme.palette.hairlineLight
    }

    /// 深色档的白色透明度（§8.1：白 10%；三个主题共用）。
    public static func darkAlpha(in theme: DesignTheme) -> Double {
        theme.palette.hairlineDarkAlpha
    }
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
