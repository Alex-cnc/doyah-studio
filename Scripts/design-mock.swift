import AppKit
import Foundation

// ============================================================================
// Doyah Studio 外观样张渲染器（离屏，不需要图形会话）
//
// 为什么要脚本渲染而不是改完再看：屏幕录制权限被系统拒绝，agent 截不了 App 的图。
// 但 CoreGraphics 离屏渲染是允许的（`Scripts/make-app-icon.swift` 同理）。
// 于是：**先把设计渲染成 PNG 给需求提出者定调，确认后再落到 SwiftUI**。
//
// 用法：`Scripts/render-design-mock.sh [输出目录]`（**不要**直接 `swift Scripts/design-mock.swift` ——
// 那样编不进 Core 的令牌，脚本会编译失败；这正是「样张必须接真令牌」的强制点）。
// 该入口做的事：把本文件当 `main.swift` + `Core/DesignTokens.swift`（+ `AccentTheme.swift` /
// `ColorContrast.swift` / `Localization.swift`）一起 `swiftc` 编译，再运行产出 PNG。
// ============================================================================

// MARK: - 令牌（唯一来源 = `Core/DesignTokens.swift`）
//
// 2026-09-29（队列 **L-79 ㈡**）：**这份脚本不再自带调色板**。
//
// 原先它自己写着一份十六进制表（第一行的注释还写着「未来会变成 Core/DesignTokens.swift 的真身」），
// 于是方案 D 换值之后，**样张与产品不再同源** —— 拿它出的图去定调、去逐屏复查，看的是另一套配色
// （中性灰底 + 旧强调色），而没有任何门禁会说话。现在改为**编译期直接接真令牌**：
// 本文件与 `Core/DesignTokens.swift`（+ `AccentTheme.swift` / `ColorContrast.swift` /
// `Localization.swift`）一起编译，入口 = `Scripts/render-design-mock.sh`。于是：
//   · 令牌换值，样张自动跟着换；样张里**不可能**出现产品没有的颜色；
//   · 门禁 `Scripts/check-design-mock-tokens.py` 钉住这件事：本文件里不许再出现色值字面量、
//     渲染入口必须真的把 `Core/DesignTokens.swift` 编进来、深色样张必须量得出方案 D 的蓝调。
//
// 间距 / 圆角 / 字号同样接 Core（`Spacing` / `Radius` / `Metrics` / `TypeScale`），
// 所以这份脚本里也找不到「同一件事在第二处各写一遍」。

/// `0xRRGGBB` → `NSColor`。**纯换算，不含任何色值**。
extension NSColor {
    convenience init(mockHex: UInt32) {
        self.init(
            srgbRed: CGFloat((mockHex >> 16) & 0xFF) / 255,
            green: CGFloat((mockHex >> 8) & 0xFF) / 255,
            blue: CGFloat(mockHex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// 名字对不上而已 —— 值全部来自 Core 的令牌（Core 的 `Metrics` 与本脚本旧名同字不同物，
/// 故旧名收进这个别名里，读代码时一眼能看出「这是 Core 的哪一格」）。
enum Mock {
    static let radiusControl = Radius.control
    static let radiusCard = Radius.card
    static let radiusPanel = Radius.panel
    static let sidebarRow = Metrics.rowHeight          // 侧栏行高与列表行高同档（26）
    static let statusHeight = Metrics.statusBarHeight
    static let activityWidth = Metrics.activityBarWidth
}

enum Typography {
    // 字号一律取自 `TypeScale`（Core 的级差表），不在这里新造数字。
    static let caption = NSFont.systemFont(ofSize: TypeScale.captionSize, weight: .medium)
    static let data = NSFont.monospacedDigitSystemFont(ofSize: TypeScale.dataSize, weight: .regular)
    static let body = NSFont.systemFont(ofSize: TypeScale.bodySize, weight: .regular)
    static let bodyStrong = NSFont.systemFont(ofSize: TypeScale.bodySize, weight: .semibold)
    static let title = NSFont.systemFont(ofSize: TypeScale.titleSize, weight: .semibold)
    static let mono = NSFont.monospacedSystemFont(ofSize: TypeScale.monoSize, weight: .regular)
    static let monoSmall = NSFont.monospacedSystemFont(ofSize: TypeScale.monoSmallSize, weight: .regular)
}

/// 主题 = **一组令牌值**（与 `Docs/design/外观方案-v1.md` §9 的「一个主题 = 一组值」同口径）。
///
/// 这里不存任何值，只按深浅两态去 Core 的令牌里取 —— 这就是「样张与产品同源」那句话的落地方式：
/// 换个配色 = 改 `Core/DesignTokens.swift`，样张下一次渲染自动跟着换。
struct Theme {
    let name: String
    let isDark: Bool

    private func color(_ c: ThemeColor) -> NSColor { NSColor(mockHex: c.hex(dark: isDark)) }

    var window: NSColor { color(Surface.window.color) }
    var sidebar: NSColor { color(Surface.sidebar.color) }
    var content: NSColor { color(Surface.content.color) }
    var panel: NSColor { color(Surface.panel.color) }
    var raised: NSColor { color(Surface.raised.color) }
    /// 发丝线：深色 = 白 `Hairline.darkAlpha` 叠加（在五个表面上都成立）/ 浅色 = 实色 `Hairline.lightHex`。
    var hairline: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(CGFloat(Hairline.darkAlpha))
            : NSColor(mockHex: Hairline.lightHex)
    }

    var textBright: NSColor { color(TextTone.bright.color) }
    var textPrimary: NSColor { color(TextTone.primary.color) }
    var textSecondary: NSColor { color(TextTone.secondary.color) }
    var textTertiary: NSColor { color(TextTone.tertiary.color) }

    var success: NSColor { color(StatusTone.success.color) }
    var warning: NSColor { color(StatusTone.warning.color) }
    var danger: NSColor { color(StatusTone.danger.color) }

    // 语法六档：**按角色挂到令牌家族**（外观方案 §8.4）—— 同样只转调，不写色值。
    var synKeyword: NSColor { color(SyntaxTone.keyword.color) }
    var synIdentifier: NSColor { color(SyntaxTone.identifier.color) }
    var synString: NSColor { color(SyntaxTone.string.color) }
    var synNumber: NSColor { color(SyntaxTone.number.color) }
    var synFunction: NSColor { color(SyntaxTone.function.color) }
    var synComment: NSColor { color(SyntaxTone.comment.color) }

    func accentFill(_ accent: NSColor, _ alpha: CGFloat) -> NSColor {
        accent.withAlphaComponent(alpha)
    }

    /// 方案 D · 科技蓝（当前唯一在用的方案；深 / 浅两态同色相派生）。
    static let dark = Theme(name: "深色 · 方案 D 科技蓝", isDark: true)
    static let light = Theme(name: "浅色 · 方案 D 科技蓝", isDark: false)
}

/// 侧栏当前显示哪个视图 —— 由最左侧活动栏切换（VS Code 的信息架构：
/// 「看哪个视图」与「视图里看什么」分开）。
enum SidebarMode {
    case database         // 连接 + 对象树（已有）
    case workspace        // 工作区 Explorer（已实现：用户自选目录，供 AI 开发）
    case workspaceEmpty   // 工作区尚未选择时的空状态（也是实现的一部分）
}

struct Accent {
    let name: String
    let color: NSColor
    let note: String

    /// 交互强调色的候选 = **产品里那一份**（`AccentTheme.all`）。旧版在这里又抄了三行十六进制，
    /// 于是产品换强调色、样张不知道；现在只转调，色值与显示名都从 Core / 语言表取。
    ///
    /// 分工提醒（见 `Core/DesignTokens.swift` 类头）：`AccentTheme` = 用户可切的**交互强调色**
    /// （选中条 / 主按钮 / 焦点环）；`AccentFamily` = 方案 D 的**基准家族**（链接 / 语法 / 度量值）。
    /// 两者是否合并成「主题」一件事，见队列 **L-80**。
    static let candidates: [Accent] = AccentTheme.all.map { preset in
        Accent(
            name: LocalizedStrings.text(preset.nameKey, language: .simplifiedChinese),
            color: NSColor(mockHex: preset.accentHex),
            note: "\(preset.id) · 实心按钮压白字走 fill \(String(format: "#%06X", preset.fillHex))"
        )
    }

    /// 产品当前实际用的那一个（= `AccentTheme.fallback`，与「默认 / 回退」同源）。
    static var current: Accent {
        guard let index = AccentTheme.all.firstIndex(where: { $0.id == AccentTheme.fallback.id }) else {
            return candidates[0]
        }
        return candidates[index]
    }
}

// MARK: - 画布

final class Canvas {
    let ctx: CGContext
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat, height: CGFloat, scale: CGFloat) {
        self.width = width
        self.height = height
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: width, height: height)
        self.rep = rep
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        context.shouldAntialias = true
        NSGraphicsContext.current = context
        self.ctx = context.cgContext
        // 翻转成"y 向下"，排版时省心
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
    }

    let rep: NSBitmapImageRep

    func finish() -> Data {
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func fill(_ rect: NSRect, _ color: NSColor) {
        color.setFill()
        rect.fill()
    }

    func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    func stroke(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor, width: CGFloat = 1) {
        color.setStroke()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
        path.lineWidth = width
        path.stroke()
    }

    /// 发丝线：水平或垂直的 1 像素线（0.5pt）。精致感一半在这里。
    func hairline(x: CGFloat, y: CGFloat, length: CGFloat, vertical: Bool, color: NSColor) {
        color.setFill()
        if vertical {
            NSRect(x: x, y: y, width: Metrics.hairline, height: length).fill()
        } else {
            NSRect(x: x, y: y, width: length, height: Metrics.hairline).fill()
        }
    }

    func text(_ string: String, at point: CGPoint, font: NSFont, color: NSColor) {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]).draw(at: point)
    }

    func textRight(_ string: String, rightEdge: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
        let size = (string as NSString).size(withAttributes: [.font: font, .foregroundColor: color])
        text(string, at: CGPoint(x: rightEdge - size.width, y: y), font: font, color: color)
    }

    func textCenter(_ string: String, centerX: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
        let size = (string as NSString).size(withAttributes: [.font: font, .foregroundColor: color])
        text(string, at: CGPoint(x: centerX - size.width / 2, y: y), font: font, color: color)
    }

    func symbol(_ name: String, in rect: NSRect, color: NSColor, pointSize: CGFloat = 12) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        image.draw(in: imageRect)
        imageRect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: rect)
    }
}

// MARK: - 活动栏 与 工作区 Explorer

/// 最左侧窄边栏：上排视图切换，最底下是设置 / 账户。
/// 选中项用「左侧 2pt 强调条 + 图标提亮」，不铺整块背景 —— 窄条上铺背景会很脏。
func drawActivityBar(_ c: Canvas, theme: Theme, accent: Accent, top: CGFloat, height: CGFloat, mode: SidebarMode) {
    let width = Mock.activityWidth
    c.fill(NSRect(x: 0, y: top, width: width, height: height), theme.window)

    let items: [(String, SidebarMode?, String)] = [
        ("cylinder.split.1x2", .database, "数据库"),
        ("folder", .workspace, "工作区")
    ]
    var y = top + 8
    for (symbolName, itemMode, _) in items {
        let active = itemMode != nil && itemMode == mode
        if active {
            c.rounded(NSRect(x: 0, y: y + 8, width: 2, height: 28), 1, accent.color)
        }
        c.symbol(symbolName, in: NSRect(x: (width - 20) / 2, y: y + 12, width: 20, height: 20),
                 color: active ? theme.textPrimary : theme.textTertiary, pointSize: 17)
        y += 44
    }

    // 底部：设置 / 账户
    var bottomY = top + height - 8 - 44
    for symbolName in ["person.crop.circle", "gearshape"] {
        c.symbol(symbolName, in: NSRect(x: (width - 20) / 2, y: bottomY + 12, width: 20, height: 20),
                 color: theme.textTertiary, pointSize: 17)
        bottomY -= 44
    }
    c.hairline(x: 8, y: bottomY + 52, length: width - 16, vertical: false, color: theme.hairline)
}

/// 工作区视图：用户自选一个目录（沙箱下走「选择文件夹」授权），供 AI 开发与终端使用。
func drawWorkspaceExplorer(_ c: Canvas, theme: Theme, accent: Accent, x: CGFloat, top: CGFloat, height: CGFloat) {
    let width = Metrics.sidebarWidth
    c.fill(NSRect(x: x, y: top, width: width, height: height), theme.sidebar)
    c.hairline(x: x + width - Metrics.hairline, y: top, length: height, vertical: true, color: theme.hairline)

    var y = top + 14
    c.text("工作区", at: CGPoint(x: x + 16, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 18

    // 当前工作区 + 切换入口
    let headerRect = NSRect(x: x + 8, y: y, width: width - 16, height: Mock.sidebarRow)
    c.rounded(headerRect, Mock.radiusControl, theme.raised)
    c.symbol("folder.fill", in: NSRect(x: x + 18, y: y + 7, width: 13, height: 13), color: accent.color, pointSize: 11)
    c.text("DoyahStudio", at: CGPoint(x: x + 36, y: y + 5), font: Typography.bodyStrong, color: theme.textPrimary)
    c.symbol("chevron.up.chevron.down", in: NSRect(x: x + width - 32, y: y + 8, width: 12, height: 12), color: theme.textTertiary, pointSize: 10)
    y += Mock.sidebarRow + 4

    // 路径（三级省略，只有中间省略在 SwiftUI 里才不会把根目录吃掉）
    c.text("~/…/projects/DoyahStudio", at: CGPoint(x: x + 18, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 22

    let tree: [(Int, String, String, Bool)] = [
        (0, "folder", ".dsh", false),
        (0, "folder", "App", false),
        (0, "folder", "Core", false),
        (1, "swift", "AgentSQLGenerator.swift", false),
        (1, "swift", "DesignTokens.swift", false),
        (1, "swift", "TerminalScreen.swift", true),
        (0, "folder", "Docs", false),
        (0, "folder", "Scripts", false),
        (0, "folder", "Tests", false),
        (0, "doc.text", "AGENTS.md", false),
        (0, "doc.plaintext", "Package.swift", false),
        (0, "doc.text", "README.md", false)
    ]
    for (depth, symbolName, name, selected) in tree {
        let indent = x + 16 + CGFloat(depth) * 14
        if selected {
            c.rounded(NSRect(x: x + 8, y: y, width: width - 16, height: Mock.sidebarRow), Mock.radiusControl, accent.color.withAlphaComponent(theme.isDark ? 0.14 : 0.10))
            c.rounded(NSRect(x: x + 8, y: y + 5, width: 3, height: Mock.sidebarRow - 10), 1.5, accent.color)
        }
        c.symbol(symbolName, in: NSRect(x: indent, y: y + 7, width: 13, height: 13),
                 color: selected ? accent.color : theme.textTertiary, pointSize: 11)
        c.text(name, at: CGPoint(x: indent + 20, y: y + 5), font: Typography.body,
               color: selected ? theme.textPrimary : theme.textSecondary)
        y += Mock.sidebarRow
    }

    // 底部：沙箱授权状态（这是工作区在 macOS 上的真实约束，必须给用户看见）
    let footerY = top + height - 30
    c.hairline(x: x, y: footerY, length: width, vertical: false, color: theme.hairline)
    c.fill(NSRect(x: x + 16, y: footerY + 12, width: 6, height: 6), theme.success)
    c.text(
        "已授权读写：/Users/me/Documents/Doyah 工作区",
        at: CGPoint(x: x + 28, y: footerY + 8),
        font: Typography.caption,
        color: theme.textTertiary
    )
}

/// 空状态：还没有选工作区时右侧面板长什么样（实现里就是这个）。
func drawWorkspaceEmptyState(_ c: Canvas, theme: Theme, accent: Accent, x: CGFloat, top: CGFloat, height: CGFloat) {
    let width = Metrics.sidebarWidth
    c.fill(NSRect(x: x, y: top, width: width, height: height), theme.sidebar)
    c.hairline(x: x + width - Metrics.hairline, y: top, length: height, vertical: true, color: theme.hairline)

    var y = top + 14
    c.text("工作区", at: CGPoint(x: x + 16, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 24

    c.text("还没有选择工作区", at: CGPoint(x: x + 16, y: y), font: Typography.bodyStrong, color: theme.textPrimary)
    y += 20
    for line in ["选一个本地目录作为工作区：", "终端会在那里启动，查询归档与", "智能体的文件读写也都以它为准。"] {
        c.text(line, at: CGPoint(x: x + 16, y: y), font: Typography.caption, color: theme.textSecondary)
        y += 16
    }
    y += 10
    // 主按钮用实心强调色（整个界面里唯一一处）
    let button = NSRect(x: x + 16, y: y, width: 108, height: 26)
    c.rounded(button, Mock.radiusControl, accent.color)
    c.textCenter("选择文件夹…", centerX: button.midX, y: button.minY + 6, font: Typography.body, color: .white)

    // 底部同样常显授权状态
    let footerY = top + height - 30
    c.hairline(x: x, y: footerY, length: width, vertical: false, color: theme.hairline)
    c.fill(NSRect(x: x + 16, y: footerY + 12, width: 6, height: 6), theme.textTertiary)
    c.text("尚未授权目录", at: CGPoint(x: x + 28, y: footerY + 8), font: Typography.caption, color: theme.textTertiary)
}

// MARK: - 窗口样张

/// 一行结果数据
struct Row {
    let id: String
    let channel: String
    let orders: String
    let gmv: String
    let created: String
    let status: String
    let statusColor: (Theme) -> NSColor
}

let sampleRows: [Row] = [
    Row(id: "10241", channel: "微信小程序", orders: "1,204", gmv: "318,420.55", created: "2026-09-23 09:14:02", status: "paid") { $0.success },
    Row(id: "10240", channel: "App Store", orders: "986", gmv: "265,731.00", created: "2026-09-23 09:12:47", status: "paid") { $0.success },
    Row(id: "10239", channel: "抖音小店", orders: "742", gmv: "198,004.20", created: "2026-09-23 09:11:15", status: "refund") { $0.warning },
    Row(id: "10238", channel: "微信小程序", orders: "655", gmv: "171,288.90", created: "2026-09-23 09:08:33", status: "paid") { $0.success },
    Row(id: "10237", channel: "官网直销", orders: "431", gmv: "120,776.00", created: "2026-09-23 09:05:02", status: "paid") { $0.success },
    Row(id: "10236", channel: "天猫旗舰店", orders: "388", gmv: "99,120.40", created: "2026-09-23 09:03:41", status: "failed") { $0.danger },
    Row(id: "10235", channel: "抖音小店", orders: "204", gmv: "51,308.75", created: "2026-09-23 09:01:09", status: "paid") { $0.success },
    Row(id: "10234", channel: "App Store", orders: "147", gmv: "38,442.10", created: "2026-09-23 08:58:52", status: "paid") { $0.success }
]

func renderWindow(theme: Theme, accent: Accent, mode: SidebarMode = .database) -> Data {
    let W: CGFloat = 1440
    let H: CGFloat = 900
    let canvas = Canvas(width: W, height: H, scale: 2)
    let c = canvas

    // ---- 窗口底 ----
    c.fill(NSRect(x: 0, y: 0, width: W, height: H), theme.window)

    // ---- 标题栏（与工具栏合一，macOS 现代做法）----
    let titlebarHeight: CGFloat = 52
    c.fill(NSRect(x: 0, y: 0, width: W, height: titlebarHeight), theme.sidebar)
    c.hairline(x: 0, y: titlebarHeight - Metrics.hairline, length: W, vertical: false, color: theme.hairline)

    // 红黄绿
    let lights: [(CGFloat, UInt32)] = [(20, 0xFF5F57), (40, 0xFEBC2E), (60, 0x28C840)]
    for (x, hex) in lights {
        c.rounded(NSRect(x: x, y: 19, width: 12, height: 12), 6, NSColor(mockHex: hex))
    }

    // 左：连接选择器
    var x: CGFloat = Metrics.sidebarWidth + 20
    c.rounded(NSRect(x: x, y: 13, width: 196, height: 26), Mock.radiusControl, theme.raised)
    c.fill(NSRect(x: x + 10, y: 24, width: 6, height: 6), theme.success)
    c.text("生产库 · PostgreSQL 16", at: CGPoint(x: x + 24, y: 18), font: Typography.body, color: theme.textPrimary)
    c.symbol("chevron.down", in: NSRect(x: x + 172, y: 19, width: 14, height: 14), color: theme.textTertiary, pointSize: 10)

    // 中：分段控件
    x += 216
    let segWidth: CGFloat = 246
    c.rounded(NSRect(x: x, y: 13, width: segWidth, height: 26), Mock.radiusControl, theme.content)
    let segs = ["查询", "表结构", "数据"]
    for (index, label) in segs.enumerated() {
        let segRect = NSRect(x: x + CGFloat(index) * segWidth / 3 + 2, y: 15, width: segWidth / 3 - 4, height: 22)
        if index == 0 {
            c.rounded(segRect, 5, theme.raised)
        }
        c.textCenter(label, centerX: segRect.midX, y: segRect.minY + 3, font: Typography.body,
                     color: index == 0 ? theme.textPrimary : theme.textSecondary)
    }

    // 右：搜索 + 图标按钮
    var rightX = W - 20
    for symbolName in ["gearshape", "sparkles", "square.split.2x1"] {
        c.symbol(symbolName, in: NSRect(x: rightX - 18, y: 19, width: 16, height: 16), color: theme.textSecondary, pointSize: 13)
        rightX -= 30
    }
    c.rounded(NSRect(x: rightX - 168, y: 13, width: 168, height: 26), Mock.radiusControl, theme.content)
    c.symbol("magnifyingglass", in: NSRect(x: rightX - 156, y: 20, width: 13, height: 13), color: theme.textTertiary, pointSize: 11)
    c.text("搜索对象 / 命令", at: CGPoint(x: rightX - 136, y: 18), font: Typography.body, color: theme.textTertiary)

    // ---- 侧栏 ----
    let bodyTop = titlebarHeight
    let statusHeight = Mock.statusHeight
    let bodyHeight = H - titlebarHeight - statusHeight
    drawActivityBar(c, theme: theme, accent: accent, top: bodyTop, height: bodyHeight, mode: mode)

    let sidebarX = Mock.activityWidth
    c.fill(NSRect(x: sidebarX, y: bodyTop, width: Metrics.sidebarWidth, height: bodyHeight), theme.sidebar)
    c.hairline(x: sidebarX + Metrics.sidebarWidth - Metrics.hairline, y: bodyTop, length: bodyHeight, vertical: true, color: theme.hairline)
    c.ctx.saveGState()
    c.ctx.translateBy(x: sidebarX, y: 0)

    var y = bodyTop + 14
    c.text("连接", at: CGPoint(x: 16, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 18

    let connections: [(String, String, NSColor, Bool)] = [
        ("生产库", "PostgreSQL 16", theme.success, true),
        ("报表库（只读）", "PostgreSQL 16", theme.success, false),
        ("分析集群", "GBase 8a", theme.warning, false),
        ("本地开发", "PostgreSQL 18", theme.textTertiary, false)
    ]
    for (name, engine, dot, selected) in connections {
        let rowRect = NSRect(x: 8, y: y, width: Metrics.sidebarWidth - 16, height: Mock.sidebarRow)
        if selected {
            c.rounded(rowRect, Mock.radiusControl, theme.accentFill(accent.color, 0.14))
            // 左侧 3pt 强调条：只在选中行出现，这是"克制地使用强调色"
            c.rounded(NSRect(x: 8, y: y + 5, width: 3, height: Mock.sidebarRow - 10), 1.5, accent.color)
        }
        c.fill(NSRect(x: 20, y: y + 11, width: 6, height: 6), dot)
        c.text(name, at: CGPoint(x: 34, y: y + 5), font: Typography.body,
               color: selected ? theme.textPrimary : theme.textSecondary)
        c.textRight(engine, rightEdge: Metrics.sidebarWidth - 18, y: y + 6, font: Typography.caption, color: theme.textTertiary)
        y += Mock.sidebarRow
    }

    y += 14
    c.text("对象", at: CGPoint(x: 16, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 18

    let objects: [(Int, String, String, Bool)] = [
        (0, "folder", "orders", false),
        (1, "tablecells", "orders", false),
        (1, "tablecells", "order_items", false),
        (1, "tablecells", "channels", false),
        (0, "folder", "analytics", false),
        (1, "tablecells", "dw_sales_daily", true),
        (1, "square.stack.3d.up", "v_channel_gmv", false),
        (0, "folder", "public", false),
        (1, "tablecells", "customers", false)
    ]
    for (depth, symbolName, name, selected) in objects {
        let indent = 16 + CGFloat(depth) * 14
        let rowRect = NSRect(x: 8, y: y, width: Metrics.sidebarWidth - 16, height: Mock.sidebarRow)
        if selected {
            c.rounded(rowRect, Mock.radiusControl, theme.accentFill(accent.color, 0.14))
            c.rounded(NSRect(x: 8, y: y + 5, width: 3, height: Mock.sidebarRow - 10), 1.5, accent.color)
        }
        c.symbol(symbolName, in: NSRect(x: indent, y: y + 7, width: 13, height: 13),
                 color: selected ? accent.color : theme.textTertiary, pointSize: 11)
        c.text(name, at: CGPoint(x: indent + 20, y: y + 5), font: Typography.body,
               color: selected ? theme.textPrimary : theme.textSecondary)
        y += Mock.sidebarRow
    }

    c.ctx.restoreGState()

    if mode == .workspace {
        drawWorkspaceExplorer(c, theme: theme, accent: accent, x: sidebarX, top: bodyTop, height: bodyHeight)
    } else if mode == .workspaceEmpty {
        drawWorkspaceEmptyState(c, theme: theme, accent: accent, x: sidebarX, top: bodyTop, height: bodyHeight)
    }

    // ---- 主区 ----
    let mainX = Mock.activityWidth + Metrics.sidebarWidth
    let mainWidth = W - mainX
    c.fill(NSRect(x: mainX, y: bodyTop, width: mainWidth, height: bodyHeight), theme.content)

    // 页签条
    var ty = bodyTop
    c.fill(NSRect(x: mainX, y: ty, width: mainWidth, height: Metrics.tabHeight), theme.content)
    var tx = mainX + 8
    let pageTabs: [(String, Bool)] = [("渠道 GMV 日报", true), ("未命名查询 2", false), ("orders", false)]
    for (title, active) in pageTabs {
        let tabWidth: CGFloat = 26 + (title as NSString).size(withAttributes: [.font: Typography.body]).width + 22
        if active {
            c.rounded(NSRect(x: tx, y: ty + 3, width: tabWidth, height: Metrics.tabHeight - 6), Mock.radiusControl, theme.panel)
            c.text(title, at: CGPoint(x: tx + 12, y: ty + 8), font: Typography.bodyStrong, color: theme.textPrimary)
            c.symbol("xmark", in: NSRect(x: tx + tabWidth - 18, y: ty + 11, width: 9, height: 9), color: theme.textTertiary, pointSize: 9)
        } else {
            c.text(title, at: CGPoint(x: tx + 12, y: ty + 8), font: Typography.body, color: theme.textSecondary)
            c.symbol("xmark", in: NSRect(x: tx + tabWidth - 18, y: ty + 11, width: 9, height: 9), color: theme.textTertiary.withAlphaComponent(0.6), pointSize: 9)
        }
        tx += tabWidth + 2
    }
    c.symbol("plus", in: NSRect(x: tx + 8, y: ty + 11, width: 11, height: 11), color: theme.textTertiary, pointSize: 11)
    ty += Metrics.tabHeight
    c.hairline(x: mainX, y: ty, length: mainWidth, vertical: false, color: theme.hairline)

    // 查询工具条
    c.fill(NSRect(x: mainX, y: ty, width: mainWidth, height: 38), theme.content)
    var bx = mainX + 12
    // 主按钮：整个界面里唯一使用实心强调色的地方
    let runRect = NSRect(x: bx, y: ty + 6, width: 78, height: 26)
    c.rounded(runRect, Mock.radiusControl, accent.color)
    c.symbol("play.fill", in: NSRect(x: bx + 12, y: ty + 12, width: 10, height: 10), color: .white, pointSize: 9)
    c.text("执行", at: CGPoint(x: bx + 28, y: ty + 11), font: Typography.bodyStrong, color: .white)
    bx += 86
    for (symbolName, label) in [("stop.fill", "停止"), ("doc.text.magnifyingglass", "解释计划"), ("arrow.triangle.2.circlepath", "事务")] {
        c.symbol(symbolName, in: NSRect(x: bx, y: ty + 12, width: 12, height: 12), color: theme.textSecondary, pointSize: 11)
        c.text(label, at: CGPoint(x: bx + 18, y: ty + 11), font: Typography.body, color: theme.textSecondary)
        bx += 18 + (label as NSString).size(withAttributes: [.font: Typography.body]).width + 18
    }
    c.hairline(x: mainX + 12, y: ty + 38 - Metrics.hairline, length: mainWidth - 24, vertical: false, color: theme.hairline)
    ty += 38

    // 编辑器
    let editorHeight: CGFloat = 214
    let gutterWidth: CGFloat = 46
    c.fill(NSRect(x: mainX, y: ty, width: mainWidth, height: editorHeight), theme.content)
    c.fill(NSRect(x: mainX, y: ty, width: gutterWidth, height: editorHeight), theme.content)
    c.hairline(x: mainX + gutterWidth, y: ty, length: editorHeight, vertical: true, color: theme.hairline)

    let sqlLines: [(String, [(String, NSColor)])] = [
        ("-- 近 7 天各渠道订单量与 GMV", [("-- 近 7 天各渠道订单量与 GMV", theme.synComment)]),
        ("SELECT c.channel_name,", [("SELECT ", theme.synKeyword), ("c.channel_name", theme.synIdentifier), (",", theme.synIdentifier)]),
        ("       count(*)              AS order_cnt,", [("       ", theme.synIdentifier), ("count", theme.synFunction), ("(*)", theme.synIdentifier), ("              AS ", theme.synKeyword), ("order_cnt", theme.synIdentifier), (",", theme.synIdentifier)]),
        ("       sum(o.amount)         AS gmv", [("       ", theme.synIdentifier), ("sum", theme.synFunction), ("(o.amount)", theme.synIdentifier), ("         AS ", theme.synKeyword), ("gmv", theme.synIdentifier)]),
        ("  FROM orders o", [("  FROM ", theme.synKeyword), ("orders", theme.synIdentifier), (" o", theme.synIdentifier)]),
        ("  JOIN channels c ON c.id = o.channel_id", [("  JOIN ", theme.synKeyword), ("channels", theme.synIdentifier), (" c ", theme.synIdentifier), ("ON ", theme.synKeyword), ("c.id = o.channel_id", theme.synIdentifier)]),
        (" WHERE o.created_at >= now() - interval '7 days'", [(" WHERE ", theme.synKeyword), ("o.created_at >= ", theme.synIdentifier), ("now", theme.synFunction), ("() - ", theme.synIdentifier), ("interval ", theme.synKeyword), ("'7 days'", theme.synString)]),
        ("   AND o.status <> 'cancelled'", [("   AND ", theme.synKeyword), ("o.status <> ", theme.synIdentifier), ("'cancelled'", theme.synString)]),
        (" GROUP BY 1", [(" GROUP BY ", theme.synKeyword), ("1", theme.synNumber)]),
        (" ORDER BY gmv DESC", [(" ORDER BY ", theme.synKeyword), ("gmv ", theme.synIdentifier), ("DESC", theme.synKeyword)]),
        (" LIMIT 50;", [(" LIMIT ", theme.synKeyword), ("50", theme.synNumber), (";", theme.synIdentifier)])
    ]
    let lineHeight: CGFloat = 19
    var ly = ty + 10
    for (index, line) in sqlLines.enumerated() {
        let isCurrent = index == 6
        if isCurrent {
            c.fill(NSRect(x: mainX, y: ly - 2, width: mainWidth, height: lineHeight), theme.accentFill(accent.color, theme.isDark ? 0.09 : 0.06))
        }
        c.textRight("\(index + 1)", rightEdge: mainX + gutterWidth - 12, y: ly + 2, font: Typography.monoSmall, color: isCurrent ? theme.textSecondary : theme.textTertiary)
        var lx = mainX + gutterWidth + 12
        for (fragment, color) in line.1 {
            let font = Typography.mono
            c.text(fragment, at: CGPoint(x: lx, y: ly + 1), font: font, color: color)
            lx += (fragment as NSString).size(withAttributes: [.font: font]).width
        }
        ly += lineHeight
    }
    // 光标
    c.fill(NSRect(x: mainX + gutterWidth + 12 + 28, y: ty + 10 + 6 * lineHeight + 2, width: 1.5, height: 15), accent.color)
    ty += editorHeight

    // 结果表
    let gridHeight = bodyHeight - (ty - bodyTop) - 190
    c.fill(NSRect(x: mainX, y: ty, width: mainWidth, height: gridHeight), theme.content)

    // 表头
    let headerHeight: CGFloat = 28
    c.fill(NSRect(x: mainX, y: ty, width: mainWidth, height: headerHeight), theme.panel)
    c.hairline(x: mainX, y: ty + headerHeight - Metrics.hairline, length: mainWidth, vertical: false, color: theme.hairline)

    let columns: [(String, CGFloat, Bool, Bool)] = [   // 标题 / 宽度 / 数值列 / 可排序
        ("id", 110, true, false),
        ("channel_name", 200, false, true),
        ("order_cnt", 130, true, true),
        ("gmv", 160, true, true),
        ("created_at", 200, false, false),
        ("status", 120, false, false)
    ]
    var columnsX = mainX
    for (title, columnWidth, numeric, sortable) in columns {
        let label = numeric ? "\(title)  " : title
        c.text(label, at: CGPoint(x: columnsX + 12, y: ty + 7), font: Typography.caption,
               color: sortable ? theme.textSecondary : theme.textTertiary)
        if title == "gmv" {
            // 排序指示只用一个小箭头 + 强调色，不用整列高亮
            c.symbol("arrow.down", in: NSRect(x: columnsX + columnWidth - 26, y: ty + 8, width: 9, height: 9), color: accent.color, pointSize: 9)
        }
        columnsX += columnWidth
        c.hairline(x: columnsX - Metrics.hairline, y: ty + 5, length: headerHeight - 10, vertical: true, color: theme.hairline)
    }

    var ry = ty + headerHeight
    for (index, row) in sampleRows.enumerated() {
        let selected = index == 2
        if selected {
            c.fill(NSRect(x: mainX, y: ry, width: mainWidth, height: Metrics.rowHeight), theme.accentFill(accent.color, theme.isDark ? 0.13 : 0.08))
            c.fill(NSRect(x: mainX, y: ry, width: 2, height: Metrics.rowHeight), accent.color)
        } else if index % 2 == 1 {
            // 极淡的斑马纹（深色 2%、浅色 1.5%）—— 只在长表里帮助横向追行
            c.fill(NSRect(x: mainX, y: ry, width: mainWidth, height: Metrics.rowHeight),
                   theme.textPrimary.withAlphaComponent(theme.isDark ? 0.02 : 0.015))
        }
        let values: [(String, Bool)] = [
            (row.id, true), (row.channel, false), (row.orders, true), (row.gmv, true), (row.created, false), (row.status, false)
        ]
        var cx = mainX
        for (columnIndex, entry) in values.enumerated() {
            let (value, isNumeric) = entry
            let columnWidth = columns[columnIndex].1
            if columnIndex == 5 {
                // 状态列用"圆点 + 文本"，不是彩色徽章铺满
                let dotColor = row.statusColor(theme)
                c.fill(NSRect(x: cx + 12, y: ry + 10, width: 6, height: 6), dotColor)
                c.text(value, at: CGPoint(x: cx + 24, y: ry + 6), font: Typography.body, color: theme.textSecondary)
            } else if isNumeric {
                c.textRight(value, rightEdge: cx + columnWidth - 12, y: ry + 6, font: Typography.data,
                            color: selected ? theme.textPrimary : theme.textSecondary)
            } else {
                c.text(value, at: CGPoint(x: cx + 12, y: ry + 6), font: Typography.body,
                       color: selected ? theme.textPrimary : theme.textSecondary)
            }
            cx += columnWidth
        }
        ry += Metrics.rowHeight
        c.hairline(x: mainX, y: ry - Metrics.hairline, length: mainWidth, vertical: false, color: theme.hairline.withAlphaComponent(0.6))
    }
    // 结果表页脚
    c.hairline(x: mainX, y: ry, length: mainWidth, vertical: false, color: theme.hairline)
    c.text("1,204 行 × 6 列", at: CGPoint(x: mainX + 12, y: ry + 6), font: Typography.caption, color: theme.textTertiary)
    c.text("0.043 s", at: CGPoint(x: mainX + 116, y: ry + 6), font: Typography.caption, color: theme.textTertiary)
    c.textRight("结果 1 / 1", rightEdge: W - 16, y: ry + 6, font: Typography.caption, color: theme.textTertiary)
    ty = ry + 26

    // ---- 下方面板 ----
    let paneHeight = bodyHeight - (ty - bodyTop)
    c.fill(NSRect(x: mainX, y: ty, width: mainWidth, height: paneHeight), theme.panel)
    c.hairline(x: mainX, y: ty, length: mainWidth, vertical: false, color: theme.hairline)
    var px = mainX + 10
    let paneTabs: [(String, Bool, Int)] = [("问题", false, 1), ("输出", false, 0), ("终端", true, 0), ("调试控制台", false, 0)]
    for (title, active, badge) in paneTabs {
        let titleWidth = (title as NSString).size(withAttributes: [.font: Typography.caption]).width
        if active {
            c.rounded(NSRect(x: px - 8, y: ty + 5, width: titleWidth + 16, height: 20), 5, theme.raised)
        }
        c.text(title, at: CGPoint(x: px, y: ty + 8), font: Typography.caption,
               color: active ? theme.textPrimary : theme.textTertiary)
        if badge > 0 {
            c.rounded(NSRect(x: px + titleWidth + 5, y: ty + 9, width: 13, height: 13), 6.5, theme.danger.withAlphaComponent(0.85))
            c.textCenter("\(badge)", centerX: px + titleWidth + 11.5, y: ty + 10, font: NSFont.systemFont(ofSize: 9, weight: .bold), color: .white)
        }
        px += titleWidth + 16 + 12
    }
    // 右侧动作
    var rx = W - 18
    for symbolName in ["arrow.down.right.and.arrow.up.left", "xmark.circle", "arrow.clockwise"] {
        c.symbol(symbolName, in: NSRect(x: rx - 14, y: ty + 8, width: 13, height: 13), color: theme.textTertiary, pointSize: 11)
        rx -= 24
    }
    // 回滚提示（反映刚做的功能）
    rx -= 40
    c.textRight("↑ 214/2000", rightEdge: rx, y: ty + 8, font: Typography.caption, color: theme.textTertiary)

    let terminalTop = ty + 30
    c.hairline(x: mainX, y: terminalTop - Metrics.hairline, length: mainWidth, vertical: false, color: theme.hairline)
    let terminalLines: [(String, NSColor)] = [
        ("gbase@dev  ~/.dsh/projects/DoyahStudio", theme.textTertiary),
        ("❯ dsh-tui", theme.textPrimary),
        ("  ✓ 已连接 生产库 · PostgreSQL 16.2 · UTF-8", theme.success),
        ("  正在执行  近 7 天各渠道订单量与 GMV …", theme.textSecondary),
        ("❯ 把上面那条查询存成「渠道 GMV 日报」，以后每天 09:00 跑", theme.textPrimary),
        ("  已写入 queries/2026-09-23.sql，并按连接与库分开记账", theme.textSecondary)
    ]
    var tly = terminalTop + 8
    for (line, color) in terminalLines {
        c.text(line, at: CGPoint(x: mainX + 14, y: tly), font: Typography.mono, color: color)
        tly += 18
    }

    // ---- 状态栏 ----
    let sy = H - statusHeight
    c.fill(NSRect(x: 0, y: sy, width: W, height: statusHeight), theme.sidebar)
    c.hairline(x: 0, y: sy, length: W, vertical: false, color: theme.hairline)
    c.fill(NSRect(x: 16, y: sy + 9, width: 6, height: 6), theme.success)
    c.text("生产库 · orders · 已连接", at: CGPoint(x: 28, y: sy + 5), font: Typography.caption, color: theme.textSecondary)
    var sx: CGFloat = 190
    for item in ["PostgreSQL 16.2", "UTF-8", "autocommit 关"] {
        c.hairline(x: sx, y: sy + 6, length: statusHeight - 12, vertical: true, color: theme.hairline)
        c.text(item, at: CGPoint(x: sx + 10, y: sy + 5), font: Typography.caption, color: theme.textTertiary)
        sx += 10 + (item as NSString).size(withAttributes: [.font: Typography.caption]).width + 10
    }
    c.textRight("上次执行 0.043 s · 影响 1,204 行", rightEdge: W - 16, y: sy + 5, font: Typography.caption, color: theme.textTertiary)

    return c.finish()
}

// MARK: - 令牌样张

func renderTokenSheet(theme: Theme) -> Data {
    let W: CGFloat = 1100
    let H: CGFloat = 660
    let c = Canvas(width: W, height: H, scale: 2)
    c.fill(NSRect(x: 0, y: 0, width: W, height: H), theme.content)

    c.text("Doyah Studio · 设计令牌", at: CGPoint(x: 28, y: 24), font: NSFont.systemFont(ofSize: 20, weight: .semibold), color: theme.textPrimary)
    c.text("间距 / 圆角 / 字号 / 色板 —— 一处定义、处处引用，并用脚本防回潮", at: CGPoint(x: 28, y: 52), font: Typography.body, color: theme.textSecondary)

    // 字号级差
    var y: CGFloat = 100
    c.text("排版级差", at: CGPoint(x: 28, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 22
    let samples: [(String, NSFont, NSColor)] = [
        ("窗口标题 17 / semibold", NSFont.systemFont(ofSize: 17, weight: .semibold), theme.textPrimary),
        ("区块标题 15 / semibold", NSFont.systemFont(ofSize: 15, weight: .semibold), theme.textPrimary),
        ("正文 13 / regular", Typography.body, theme.textPrimary),
        ("数据 12 / monospacedDigit", Typography.data, theme.textPrimary),
        ("代码 12 / SF Mono", Typography.mono, theme.textPrimary),
        ("辅助 11 / medium", Typography.caption, theme.textSecondary),
        ("三级 11 / tertiary", Typography.caption, theme.textTertiary)
    ]
    for (label, font, color) in samples {
        c.text(label, at: CGPoint(x: 28, y: y), font: font, color: color)
        c.text("1,204,318.55  ·  渠道 GMV  ·  SELECT", at: CGPoint(x: 320, y: y), font: font, color: theme.textSecondary)
        y += 26
    }

    // 间距刻度
    y += 10
    c.text("间距刻度（4 / 8）", at: CGPoint(x: 28, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 20
    var rulerX: CGFloat = 28
    for value in [2, 4, 8, 12, 16, 24, 32] as [CGFloat] {
        c.rounded(NSRect(x: rulerX, y: y, width: value, height: 10), 2, theme.accentFill(Accent.candidates[0].color, 0.75))
        c.text("\(Int(value))", at: CGPoint(x: rulerX, y: y + 14), font: Typography.caption, color: theme.textTertiary)
        rulerX += value + 26
    }
    y += 46
    c.text("圆角 4 / 6 / 8 / 10  ·  发丝线 0.5pt  ·  行高 26  ·  工具栏 44  ·  状态栏 24",
           at: CGPoint(x: 28, y: y), font: Typography.body, color: theme.textSecondary)

    // 色板
    y += 34
    c.text("色板", at: CGPoint(x: 28, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 16
    let swatches: [(String, NSColor)] = [
        ("window", theme.window), ("sidebar", theme.sidebar), ("content", theme.content),
        ("panel", theme.panel), ("raised", theme.raised), ("text", theme.textPrimary),
        ("secondary", theme.textSecondary), ("success", theme.success), ("warning", theme.warning), ("danger", theme.danger)
    ]
    var swatchX: CGFloat = 28
    for (name, color) in swatches {
        c.rounded(NSRect(x: swatchX, y: y, width: 72, height: 44), Mock.radiusCard, color)
        c.stroke(NSRect(x: swatchX, y: y, width: 72, height: 44), Mock.radiusCard, theme.hairline, width: 1)
        c.text(name, at: CGPoint(x: swatchX, y: y + 50), font: Typography.caption, color: theme.textTertiary)
        swatchX += 82
    }
    y += 78

    // 三个强调色候选：把"选中态"真的画出来，而不是只给色块
    c.text("强调色候选（下图为真实选中态 / 焦点态）", at: CGPoint(x: 28, y: y), font: Typography.caption, color: theme.textTertiary)
    y += 18
    var accentX: CGFloat = 28
    for candidate in Accent.candidates {
        let cardWidth: CGFloat = 336
        c.rounded(NSRect(x: accentX, y: y, width: cardWidth, height: 132), Mock.radiusPanel, theme.panel)
        c.stroke(NSRect(x: accentX, y: y, width: cardWidth, height: 132), Mock.radiusPanel, theme.hairline, width: 1)

        // 选中行：淡填充 + 左侧强调条
        c.rounded(NSRect(x: accentX + 12, y: y + 12, width: cardWidth - 24, height: 26), Mock.radiusControl, candidate.color.withAlphaComponent(theme.isDark ? 0.16 : 0.10))
        c.rounded(NSRect(x: accentX + 12, y: y + 17, width: 3, height: 16), 1.5, candidate.color)
        c.text("选中的连接行", at: CGPoint(x: accentX + 26, y: y + 17), font: Typography.body, color: theme.textPrimary)

        // 主按钮 + 焦点环
        c.rounded(NSRect(x: accentX + 12, y: y + 48, width: 78, height: 26), Mock.radiusControl, candidate.color)
        c.text("执行", at: CGPoint(x: accentX + 42, y: y + 53), font: Typography.bodyStrong, color: .white)
        c.stroke(NSRect(x: accentX + 100, y: y + 48, width: 78, height: 26), Mock.radiusControl, candidate.color, width: 1.5)
        c.text("焦点输入框", at: CGPoint(x: accentX + 112, y: y + 53), font: Typography.body, color: theme.textSecondary)

        // 语法高亮里的关键字也用强调色家族（保持一致）
        c.text("SELECT c.channel_name  -- 关键字随强调色走", at: CGPoint(x: accentX + 12, y: y + 84),
               font: Typography.monoSmall, color: theme.synKeyword)

        c.text(candidate.name, at: CGPoint(x: accentX + 12, y: y + 106), font: Typography.bodyStrong, color: theme.textPrimary)
        c.text(candidate.note, at: CGPoint(x: accentX + 76, y: y + 108), font: Typography.caption, color: theme.textTertiary)
        accentX += cardWidth + 16
    }

    return c.finish()
}

// MARK: - 自检
//
// 样张是"给人看的"，但渲染脚本必须先证明**真的画出东西了**（空白图也是合法 PNG）。
// 注意：位图是 deviceRGB，写进去的 sRGB 值会被当前显示器 profile 转换一次
// （实测 #16181D 读回是 #21242C），所以这里**不做逐字节比对**，而是：
//   · 结构关系（层次明度差、强调色落在正确位置）；
//   · 强调色**分类**（在按钮处取样，判断它离哪个候选最近，必须等于本次用的那个）；
//   · 三个候选之间必须彼此可区分；
//   · 文本 / 图标是否真的画上去了（非背景像素占比）。
// 这些才是"这张图有没有画出设计"的真正判据。

struct Check {
    var ok: Bool
    var note: String
}

extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "?" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
    /// 与另一个颜色的归一化距离（0 = 相同）。
    func distance(to other: NSColor) -> CGFloat {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return 1 }
        let dr = a.redComponent - b.redComponent
        let dg = a.greenComponent - b.greenComponent
        let db = a.blueComponent - b.blueComponent
        return sqrt(dr * dr + dg * dg + db * db) / sqrt(3)
    }
}

func close(_ lhs: NSColor, _ rhs: NSColor, tolerance: CGFloat = 0.10) -> Bool {
    lhs.distance(to: rhs) < tolerance
}

/// 某块区域里"非背景"像素的占比（证明文字 / 图标确实画上了）。
func inkRatio(_ rep: NSBitmapImageRep, rect: NSRect, background: NSColor, scale: CGFloat, step: Int = 3) -> Double {
    var total = 0
    var ink = 0
    var y = Int(rect.minY * scale)
    while y < Int(rect.maxY * scale) {
        var x = Int(rect.minX * scale)
        while x < Int(rect.maxX * scale) {
            if let color = rep.colorAt(x: x, y: y) {
                total += 1
                if !close(color, background, tolerance: 0.06) { ink += 1 }
            }
            x += step
        }
        y += step
    }
    return total == 0 ? 0 : Double(ink) / Double(total)
}

/// 一张窗口样张的全部取样点（供跨候选比较）。
struct WindowSamples {
    var accentButton: NSColor?
    var selectionBar: NSColor?
    var checks: [Check]
}

func verifyWindow(
    _ data: Data,
    theme: Theme,
    accent: Accent,
    label: String,
    barPoint: CGPoint = CGPoint(x: 55, y: 95),      // 侧栏里那一行选中的强调条
    buttonPoint: CGPoint = CGPoint(x: 345, y: 100)  // 查询工具条上的主按钮
) -> WindowSamples {
    guard let rep = NSBitmapImageRep(data: data) else {
        return WindowSamples(accentButton: nil, selectionBar: nil, checks: [Check(ok: false, note: "\(label): PNG 解不开")])
    }
    let scale: CGFloat = 2
    var checks: [Check] = []
    func sample(_ x: CGFloat, _ y: CGFloat) -> NSColor? { rep.colorAt(x: Int(x * scale), y: Int(y * scale)) }

    let window = sample(5, 5)   // 仅报告用：标题栏铺满，窗口底通常看不到
    let titlebar = sample(700, 10)
    let sidebar = sample(120, 500)
    let content = sample(1400, 585)   // 网格末行与下方面板之间的空白，避开当前行高亮与面板
    let header = sample(1400, 348)
    let button = sample(buttonPoint.x, buttonPoint.y)
    let bar = sample(barPoint.x, barPoint.y)

    print("  取样 \(label): 底 \(window?.hexString ?? "-") 标题栏 \(titlebar?.hexString ?? "-") 侧栏 \(sidebar?.hexString ?? "-") 内容 \(content?.hexString ?? "-") 表头 \(header?.hexString ?? "-") 按钮 \(button?.hexString ?? "-") 强调条 \(bar?.hexString ?? "-")")

    // 1）层次：深色主题里侧栏/标题栏必须**比内容暗**，浅色主题里反之。
    // 不变式（深浅两套都成立，Finder / Xcode / Linear 都是这个规律）：
    // **内容区是明度最高的表面**，chrome（标题栏 / 侧栏 / 面板）比它暗。
    if let titlebar, let content {
        checks.append(Check(ok: titlebar.luminance < content.luminance,
                            note: String(format: "内容区应是明度最高的表面（chrome %.3f 应 < 内容 %.3f）", titlebar.luminance, content.luminance)))
    }
    // 2）侧栏与内容必须拉得开（第一版只差 3/255，肉眼等于同一个色）
    if let sidebar, let content {
        let d = sidebar.distance(to: content)
        checks.append(Check(ok: d > 0.02, note: String(format: "侧栏与内容需可区分（距离 %.3f，需 > 0.02）", d)))
    }
    // 3）表头比内容略亮/略暗，形成分组感
    if let header, let content {
        checks.append(Check(ok: header.distance(to: content) > 0.01, note: "表头必须与内容区可区分"))
    }
    // 4）强调色分类：按钮处取到的颜色应最接近本次使用的候选
    if let button {
        let nearest = Accent.candidates.min { button.distance(to: $0.color) < button.distance(to: $1.color) }
        checks.append(Check(ok: nearest?.name == accent.name,
                            note: "执行按钮应使用强调色「\(accent.name)」，最近候选是「\(nearest?.name ?? "-")」"))
    } else {
        checks.append(Check(ok: false, note: "按钮取样失败"))
    }
    // 5）选中行强调条也用同一个强调色
    if let bar, let button {
        checks.append(Check(ok: bar.distance(to: button) < 0.12, note: "选中行强调条应与按钮同色"))
    }
    // 6）真的画出内容了
    func ink(_ name: String, _ rect: NSRect, _ background: NSColor, _ threshold: Double) {
        let value = inkRatio(rep, rect: rect, background: background, scale: scale)
        checks.append(Check(ok: value > threshold, note: String(format: "%@ 非背景像素 %.2f%%（需 > %.1f%%）", name, value * 100, threshold * 100)))
    }
    ink("编辑区（代码）", NSRect(x: 300, y: 122, width: 1100, height: 208), theme.content, 0.015)
    ink("结果网格", NSRect(x: 260, y: 362, width: 1160, height: 200), theme.content, 0.03)
    ink("侧栏（连接与对象）", NSRect(x: 8, y: 60, width: 232, height: 420), theme.sidebar, 0.02)
    ink("终端区", NSRect(x: 260, y: 700, width: 1100, height: 140), theme.panel, 0.01)

    let failures = checks.filter { !$0.ok }
    print("  自检 \(label)：\(checks.count - failures.count)/\(checks.count) 通过")
    for check in failures { print("    ! \(check.note)") }
    return WindowSamples(accentButton: button, selectionBar: bar, checks: checks)
}

// MARK: - 主流程

let outDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Docs/design"
try? FileManager.default.createDirectory(atPath: outDirectory, withIntermediateDirectories: true)

var allChecks: [Check] = []
var darkButtons: [NSColor] = []

func write(_ data: Data, _ name: String) {
    let url = URL(fileURLWithPath: outDirectory).appendingPathComponent(name)
    try? data.write(to: url)
    let size = (try? Data(contentsOf: url).count) ?? 0
    print("写出 \(url.lastPathComponent)（\(size / 1024) KB）")
}

// 0）先自证「接在真令牌上」——**不写死任何色值**（本文件里一个十六进制颜色都不许有，
//    `Scripts/check-design-mock-tokens.py` 会把这条变成机械判据），只用令牌自身能推出的关系：
//    ① 深色五档严格递增（window < sidebar < content < panel < raised）—— 外观方案 §8.1 的不变式，
//       旧的「中性灰」那套也是递增的，所以单靠它不够，得配②；
//    ② 深色表面**带蓝调**（B > R）—— 方案 D 的深海军蓝 vs 旧的中性灰（B ≈ R），这是"换了值但
//       某屏漏改"最省事的一刀；
//    ③ 语法六档各自等于某个令牌家族的值（没有孤立的旧语法色）。
print("渲染器：令牌唯一来源 = Core/DesignTokens.swift（当前 = 方案 D · 科技蓝，深 / 浅两态）")

let darkLuminance = Surface.allCases.map { ColorContrast.relativeLuminance($0.color.dark) }
allChecks.append(Check(
    ok: zip(darkLuminance, darkLuminance.dropFirst()).allSatisfy { $0 < $1 },
    note: "深色五档必须严格递增（window < sidebar < content < panel < raised）"
))
let familyValues = AccentFamily.allCases.map(\.color) + TextTone.allCases.map(\.color)
allChecks.append(Check(
    ok: SyntaxTone.allCases.allSatisfy { familyValues.contains($0.color) },
    note: "语法六档必须各自等于某个令牌家族的值（否则就是留了一个孤立的旧语法色）"
))

let dark = Theme.dark
let light = Theme.light
/// 产品当前实际在用的交互强调色（= `AccentTheme.fallback`）。
let currentAccent = Accent.current

// 1）主样张：方案 D 深 / 浅两态，交互强调色用产品当前那一个。
let darkData = renderWindow(theme: dark, accent: currentAccent)
allChecks += verifyWindow(darkData, theme: dark, accent: currentAccent, label: "深色-D-科技蓝").checks
write(darkData, "样张-深色-D-科技蓝.png")

let lightData = renderWindow(theme: light, accent: currentAccent)
allChecks += verifyWindow(lightData, theme: light, accent: currentAccent, label: "浅色-D-科技蓝").checks
write(lightData, "样张-浅色-D-科技蓝.png")

// 2）**蓝调判据**（方案 D 的「这组值真的落地了吗」）：深色表面必须带蓝调（B > R）。
//    旧的深色是**中性灰**（B ≈ R）—— 所以这一条能机械地把「换了值、但样张还是旧配色」抓出来；
//    它与上面那条令牌身份判据一起，构成「样张 = 产品」的可复跑证据。
for (name, background) in [("content", dark.content), ("sidebar", dark.sidebar), ("panel", dark.panel)] {
    let components = background.usingColorSpace(.sRGB)!
    let blue = components.blueComponent - components.redComponent
    allChecks.append(Check(ok: blue > 8.0 / 255.0,
                           note: String(format: "方案 D 的深色 %@ 必须带蓝调（B−R = %.1f/255，需 > 8/255）", name, blue * 255)))
}

// 3）交互强调色的三个候选（方案 D 的表面 + 各自真实的选中态 / 主按钮 / 焦点环）。
for candidate in Accent.candidates {
    let data = renderWindow(theme: dark, accent: candidate)
    let result = verifyWindow(data, theme: dark, accent: candidate, label: "深色-D-\(candidate.name)")
    allChecks += result.checks
    if let button = result.accentButton { darkButtons.append(button) }
    write(data, "样张-深色-D-强调色-\(candidate.name).png")
}

// 三个候选必须真的长得不一样（否则「看样张再定」就没意义）
if darkButtons.count == Accent.candidates.count {
    for i in 0..<darkButtons.count {
        for j in (i + 1)..<darkButtons.count {
            let d = darkButtons[i].distance(to: darkButtons[j])
            allChecks.append(Check(ok: d > 0.15, note: String(format: "候选 %d 与 %d 的按钮色必须可区分（距离 %.3f）", i + 1, j + 1, d)))
        }
    }
}

// 4）「已实现」三屏（工作区视图 / 空工作区 / 浅色工作区）—— 与产品里已交付的界面同一套令牌。
let lightWorkspaceData = renderWindow(theme: light, accent: currentAccent, mode: .workspace)
allChecks += verifyWindow(lightWorkspaceData, theme: light, accent: currentAccent, label: "浅色-D-工作区视图",
                          barPoint: CGPoint(x: 55, y: 271)).checks
write(lightWorkspaceData, "样张-已实现-浅色-工作区.png")

let emptyData = renderWindow(theme: dark, accent: currentAccent, mode: .workspaceEmpty)
write(emptyData, "样张-已实现-深色-空工作区.png")

let workspaceData = renderWindow(theme: dark, accent: currentAccent, mode: .workspace)
allChecks += verifyWindow(workspaceData, theme: dark, accent: currentAccent, label: "深色-D-工作区视图",
                          barPoint: CGPoint(x: 55, y: 271)).checks   // 工作区视图里选中的是第 6 行文件
write(workspaceData, "样张-已实现-深色-工作区.png")

// 5）令牌页（深浅两态）
for (theme, name) in [(dark, "深色"), (light, "浅色")] {
    let data = renderTokenSheet(theme: theme)
    if let rep = NSBitmapImageRep(data: data) {
        let value = inkRatio(rep, rect: NSRect(x: 20, y: 20, width: 1060, height: 620), background: theme.content, scale: 2)
        allChecks.append(Check(ok: value > 0.05, note: String(format: "令牌样张-%@ 非背景像素 %.2f%%", name, value * 100)))
    } else {
        allChecks.append(Check(ok: false, note: "令牌样张-\(name): PNG 解不开"))
    }
    write(data, "样张-令牌-\(name).png")
}

let failed = allChecks.filter { !$0.ok }
print(failed.isEmpty ? "全部样张自检通过（\(allChecks.count) 项）" : "\(failed.count)/\(allChecks.count) 项自检未过")
exit(failed.isEmpty ? 0 : 1)
