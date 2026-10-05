import AppKit
import Foundation

// ============================================================================
// App Store 式「展示图」（Demo 图）渲染器 —— T-20261001-031 ②
//
// 与 `Scripts/design-mock.swift`（**样张** = 工程证据）**分工明确**：
//   · 样张：必须与产品**逐像素同源** —— 由 `Scripts/check-design-mock-tokens.py` 钉住
//     （脚本里不许有色值字面量、入口必须编译真令牌、深色底必须带蓝调）；那条链路本件**不碰**。
//   · 本件：**营销物料**。图上有产品里没有的像素（底 / 大标题 / 卖点标注 / 圆角容器 / 阴影）
//     ⇒ 混进样张链路会破坏上面那条判据。**营销物料与工程证据应分开。**
//
// 但「营销」不等于「自己编一套配色」：本件同样**编译期接真令牌**（入口 `Scripts/render-store-shot.sh`
// 把 `platform/macos/Core/DesignTokens.swift` / `platform/macos/Core/DesignTheme.swift` 等一起编进来），底 / 字 / 强调色一律取
// `ThemePalette.of(.stardust)`；产品窗口那一块**直接贴渲染入口刚产出的真样张**（不重画）。
// ⇒ 展示图里不可能出现产品没有的颜色。
//
// 用法：`Scripts/render-store-shot.sh [输出目录]`
//   参数：① 深色样张 PNG ② 浅色样张 PNG ③ 输出目录（前两个由入口脚本渲染后传进来）
// ============================================================================

/// `0xRRGGBB` → `NSColor`。**纯换算，不含任何色值**。
extension NSColor {
    convenience init(storeHex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((storeHex >> 16) & 0xFF) / 255,
            green: CGFloat((storeHex >> 8) & 0xFF) / 255,
            blue: CGFloat(storeHex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// 展示图用的那一组值：**全部来自星空紫值表**（`ThemePalette.of(.stardust)`），本文件不写死颜色。
struct StoreSkin {
    let isDark: Bool
    let palette: ThemePalette

    func color(_ token: ThemeColor) -> NSColor { NSColor(storeHex: token.hex(dark: isDark)) }

    var window: NSColor { color(palette.window) }
    var panel: NSColor { color(palette.panel) }
    var raised: NSColor { color(palette.raised) }
    var textBright: NSColor { color(palette.textBright) }
    var textPrimary: NSColor { color(palette.textPrimary) }
    var textSecondary: NSColor { color(palette.textSecondary) }
    var textTertiary: NSColor { color(palette.textTertiary) }
    var accent: NSColor { color(palette.accent) }
    var accentGlow: NSColor { color(palette.accentGlow) }

    static func of(isDark: Bool) -> StoreSkin {
        StoreSkin(isDark: isDark, palette: ThemePalette.of(.stardust))
    }
}

/// 一条自检（本件自己的证据：色与图源同源、版式不重叠）。
struct StoreCheck {
    let ok: Bool
    let note: String
}

/// 画布：与样张同尺寸（2880×1800），离屏渲染（agent 没有屏幕录制权限，但 CoreGraphics 离屏可以）。
final class StoreCanvas {
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let ctx: CGContext
    let rep: NSBitmapImageRep

    init(width: CGFloat, height: CGFloat, scale: CGFloat = 1) {
        self.width = width
        self.height = height
        self.scale = scale
        let bitmap = NSBitmapImageRep(
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
        bitmap.size = NSSize(width: width, height: height)
        self.rep = bitmap
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        context.shouldAntialias = true
        NSGraphicsContext.current = context
        self.ctx = context.cgContext
        // 翻转成 y 向下（与 design-mock 同款：排版时 y 小 = 靠上）
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
    }

    func finish() -> Data {
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func sample(_ x: CGFloat, _ y: CGFloat) -> NSColor? {
        rep.colorAt(x: Int(x * scale), y: Int(y * scale))
    }

    func fill(_ rect: NSRect, _ color: NSColor) {
        color.setFill()
        rect.fill()
    }

    /// 星云辉光：星空紫的「光」—— NASA 原图的真相是「靛蓝为底、星光带紫」，
    /// 所以紫只出现在辉光里，不铺在白底上（底色一律是值表里的 window 值）。
    func glow(center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        if let gradient = NSGradient(colors: [color.withAlphaComponent(alpha),
                                              color.withAlphaComponent(0)]) {
            gradient.draw(fromCenter: center, radius: 0,
                          toCenter: center, radius: radius, options: [])
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    func dot(center: CGPoint, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2)).fill()
    }

    func text(_ string: String, at point: CGPoint, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if tracking != 0 { attributes[.kern] = tracking }
        NSAttributedString(string: string, attributes: attributes).draw(at: point)
    }

    func textWidth(_ string: String, font: NSFont, tracking: CGFloat = 0) -> CGFloat {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if tracking != 0 { attributes[.kern] = tracking }
        return (string as NSString).size(withAttributes: attributes).width
    }

    /// 贴一张**真样张**进圆角容器 —— 展示图里唯一的「产品像素」来源（不重画）。
    ///
    /// 翻转上下文的坑（2026-10-01 实测）：本画布是 y 向下的，`NSImage.draw(in:)` 在这里会把图
    /// **上下镜像**（自检「贴图区 ↔ 样张」当场量出 143/255 的差才发现）。所以这里改用 CG 画，
    /// 并把 CTM 先镜像回来一次 —— 两次镜像相抵 ⇒ 图正着贴。判据留在自检里，改动这一块必须先看它。
    @discardableResult
    func place(image path: String, in rect: NSRect, radius: CGFloat) -> Bool {
        guard let image = NSImage(contentsOfFile: path),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        // 阴影：先填一块圆角矩形（它会被贴图完全盖住，只用来投出阴影）
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 36
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()

        // 先把样张**在它自己的色彩空间里**重采样到目标像素尺寸，再 1:1 贴上去。
        // 为什么要这一步（实测踩出来的）：直接让 CG 把 2880 宽的样张缩进 1337 像素的框里，
        // 重采样在画布的色彩空间里做 ⇒ 深色区域整片偏紫（实测 #1A2335 → #261640，Δ≈13/255），
        // 「贴的是真样张」那条自检当场量出 33/255。**同一张图、缩放在哪儿做，颜色就不一样。**
        let pixelRect = NSRect(x: (rect.minX * scale).rounded(), y: (rect.minY * scale).rounded(),
                               width: (rect.width * scale).rounded(),
                               height: (rect.height * scale).rounded())
        let placed = NSRect(x: pixelRect.minX / scale, y: pixelRect.minY / scale,
                            width: pixelRect.width / scale, height: pixelRect.height / scale)
        let sameSize = Int(pixelRect.width) == cg.width && Int(pixelRect.height) == cg.height
        let resampled = sameSize ? cg
            : (resample(cg, width: Int(pixelRect.width), height: Int(pixelRect.height)) ?? cg)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: placed, xRadius: radius, yRadius: radius).addClip()
        ctx.saveGState()
        ctx.translateBy(x: 0, y: placed.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -placed.midY)
        ctx.interpolationQuality = .none
        ctx.draw(resampled, in: placed)
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return true
    }

    /// 在**源图自己的色彩空间**里重采样（不换空间 ⇒ 不偏色）。
    private func resample(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let space = image.colorSpace,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

// MARK: - 版式与文案（深 / 浅两张**同构**：同样的版式与文案，只换深浅两态）

enum StoreLayout {
    static let canvasW: CGFloat = 2880
    static let canvasH: CGFloat = 1800
    /// 出图像素 = 版式坐标 × 这个比例。版式按 2880×1800 写（与样张同一坐标系，改版式不用换算），
    /// 但封面图出到 2880×1800 单张 ~1.8 MB，而 GitHub README 上的显示宽度只有 ~900 px ⇒ 取
    /// 2048×1280（单张 ~0.9 MB，仍是显示宽度的 2 倍）。
    /// **缩放不改变色彩**：贴图那一步先在样张**自己的色彩空间里**重采样，再 1:1 贴上去
    /// （直接让 CG 缩进画布空间会整片偏紫，实测 #1A2335 → #261640）；自检「贴图区 ↔ 样张」
    /// 在两种比例下都量到 ≤2/255。
    static let renderScale: CGFloat = 2048.0 / 2880.0
    static let margin: CGFloat = 150
    /// 产品窗口那一块：右下，左侧留给标题与卖点。宽高比 = 2880:1800（与样张自身的比例一致）
    static let shotRect = NSRect(x: 900, y: 330, width: 1880, height: 1175)
    static let shotRadius: CGFloat = 14
    /// 左栏文字的右边界（越界就压到窗口上 ⇒ 由自检「版式不重叠」机械判住）
    static let columnLimit: CGFloat = 860
}

/// 文案：只说 README 里已经写着的事（不吹没做的）。
enum StoreCopy {
    static let eyebrow = "DOYAH STUDIO"
    static let headline = "原生数据库工作台"
    static let subhead = "无 JVM · 无 Electron · 中英双语即时切换"
    static let theme = "主题：星空紫 · Stardust"
    static let bullets = [
        "内嵌真实 PTY 终端与多语言代码编辑器",
        "智能体默认关闭，写操作逐次审批",
        "连库 / 查询 / 导出 / ER 图 / 诊断，一个窗口",
    ]
    static let footer = "macOS 14+ · PostgreSQL 一等公民"
}

/// 字号自适应：把一行文字压进给定宽度（两张图同构，因此不会一张挤到窗口上）。
func fitted(_ text: String, size: CGFloat, weight: NSFont.Weight,
            maxWidth: CGFloat, canvas: StoreCanvas, tracking: CGFloat = 0) -> CGFloat {
    var current = size
    while current > 18 {
        let font = NSFont.systemFont(ofSize: current, weight: weight)
        if canvas.textWidth(text, font: font, tracking: tracking) <= maxWidth { return current }
        current -= 2
    }
    return 18
}

// MARK: - 渲染一张展示图

func renderStoreShot(samplePath: String, isDark: Bool, label: String,
                     outputDirectory: String,
                     checks: inout [StoreCheck]) -> URL? {
    let skin = StoreSkin.of(isDark: isDark)
    let canvas = StoreCanvas(width: StoreLayout.canvasW, height: StoreLayout.canvasH,
                             scale: StoreLayout.renderScale)
    let margin = StoreLayout.margin
    let column = StoreLayout.columnLimit

    // ① 底 = 值表里的 window 值（角像素自检量的是它；「换主题就换底」在这一层也成立）
    canvas.fill(NSRect(x: 0, y: 0, width: StoreLayout.canvasW, height: StoreLayout.canvasH),
                skin.window)
    // ② 两团星云辉光：紫出现在**光**里，不铺在底色上（外观方案 §9 星空紫的设计要点）
    canvas.glow(center: CGPoint(x: 2560, y: 200), radius: 1150, color: skin.accentGlow,
                alpha: isDark ? 0.30 : 0.18)
    canvas.glow(center: CGPoint(x: 520, y: 1700), radius: 950, color: skin.accent,
                alpha: isDark ? 0.16 : 0.10)

    // ③ 左栏文字：每行都量宽度、并按需缩号，最后统一自检「没有越界」
    var measured: [(String, CGFloat, CGFloat)] = []
    func line(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, x: CGFloat, maxWidth: CGFloat, tracking: CGFloat = 0) {
        let chosen = fitted(text, size: size, weight: weight, maxWidth: maxWidth,
                            canvas: canvas, tracking: tracking)
        let font = NSFont.systemFont(ofSize: chosen, weight: weight)
        let width = canvas.textWidth(text, font: font, tracking: tracking)
        canvas.text(text, at: CGPoint(x: x, y: y), font: font, color: color, tracking: tracking)
        measured.append((text, width + (x - margin), chosen))
    }

    line(StoreCopy.eyebrow, y: 190, size: 40, weight: .semibold, color: skin.accentGlow,
         x: margin, maxWidth: column - margin, tracking: 7)
    line(StoreCopy.headline, y: 268, size: 96, weight: .bold, color: skin.textBright,
         x: margin, maxWidth: column - margin)
    line(StoreCopy.subhead, y: 432, size: 44, weight: .regular, color: skin.textPrimary,
         x: margin, maxWidth: column - margin)
    line(StoreCopy.theme, y: 546, size: 46, weight: .semibold, color: skin.accent,
         x: margin, maxWidth: column - margin)
    for (index, bullet) in StoreCopy.bullets.enumerated() {
        let y = 730 + CGFloat(index) * 86
        canvas.dot(center: CGPoint(x: margin + 10, y: y + 16), radius: 9, color: skin.accent)
        line(bullet, y: y, size: 40, weight: .regular, color: skin.textPrimary,
             x: margin + 46, maxWidth: column - margin - 46)
    }
    line(StoreCopy.footer, y: 1692, size: 32, weight: .regular, color: skin.textTertiary,
         x: margin, maxWidth: StoreLayout.shotRect.minX - 60 - margin)

    // ④ 贴**真样张**（唯一的「产品像素」来源）—— 不重画、不换色
    let pasted = canvas.place(image: samplePath, in: StoreLayout.shotRect,
                              radius: StoreLayout.shotRadius)
    checks.append(StoreCheck(ok: pasted,
                             note: "\(label)：产品窗口那一块要贴 \(samplePath)（贴不上就是空图）"))

    // ⑤ 版式不重叠：左栏每一行（含起笔偏移）都必须在 columnLimit 以内
    let overflow = measured.filter { $0.1 > column }
    checks.append(StoreCheck(ok: overflow.isEmpty,
                             note: "\(label)：左栏文字越界（右边界 \(column)）："
                                 + (overflow.isEmpty ? "无"
                                    : overflow.map { "\($0.0) 宽 \(Int($0.1))" }.joined(separator: " / "))))

    // ⑥ 强调色**真的画上去了**（网格采样：颜色出现 = 值表里的强调色确实用上了）
    var accentHits = 0
    var y: CGFloat = 4
    while y < StoreLayout.canvasH {
        var x: CGFloat = 4
        while x < StoreLayout.canvasW {
            if let c = canvas.sample(x, y) {
                let d = abs(c.redComponent - skin.accent.redComponent)
                    + abs(c.greenComponent - skin.accent.greenComponent)
                    + abs(c.blueComponent - skin.accent.blueComponent)
                if d * 255 <= 30 { accentHits += 1 }
            }
            x += 6
        }
        y += 6
    }
    checks.append(StoreCheck(ok: accentHits >= StoreMinimums.accentHits,
                             note: "\(label)：强调色命中 \(accentHits) 处（下限 \(StoreMinimums.accentHits)）"
                                 + " —— 命不中说明这一版其实没用主题的强调色"))

    // ⑦ 落盘
    let name = isDark ? "doyah-studio-stardust-dark.png" : "doyah-studio-stardust-light.png"
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)
    let data = canvas.finish()
    try? data.write(to: url)
    print("写出 \(name)（\(data.count / 1024) KB）")

    // ⑧ 读回：尺寸 + 角像素必须等于这一态的 `window` 值（容差 = PNG 往返实测值 8）
    if let back = NSBitmapImageRep(data: data) {
        let wantW = Int(StoreLayout.canvasW * StoreLayout.renderScale)
        let wantH = Int(StoreLayout.canvasH * StoreLayout.renderScale)
        checks.append(StoreCheck(ok: back.pixelsWide == wantW && back.pixelsHigh == wantH,
                                 note: "\(label)：尺寸 \(back.pixelsWide)×\(back.pixelsHigh)"
                                     + "（应为 \(wantW)×\(wantH)）"))
        let want = skin.window
        if let corner = back.colorAt(x: 2, y: 2) {
            let gap = abs(corner.redComponent - want.redComponent)
                + abs(corner.greenComponent - want.greenComponent)
                + abs(corner.blueComponent - want.blueComponent)
            checks.append(StoreCheck(ok: gap * 255 <= 8,
                                     note: "\(label)：角像素与星空紫 \(isDark ? "深色" : "浅色") window"
                                         + " 值相差 \(Int(gap * 255))/255（容差 8）"))
        }
        let paste = pastedPixelsMatch(store: back, samplePath: samplePath)
        checks.append(StoreCheck(ok: paste.ok,
                                 note: "\(label)：贴图区与样张的局部均值最大差 \(paste.worst)/255"
                                     + "（容差 \(StoreMinimums.pasteTolerance)）—— 差大了就是没贴那张真样张"))
    } else {
        checks.append(StoreCheck(ok: false, note: "\(label)：写出的 PNG 读不回来"))
    }
    return url
}

/// 空跑防护的门槛：**实测定的**（阈值拿实测定、不拿观感定 —— 与门禁同一条纪律）。
enum StoreMinimums {
    /// 强调色命中处数下限（网格采样；**实测定的**：2026-10-01 版式下深色 208 / 浅色 305 处）。
    static let accentHits = 150
    /// 贴图区 ↔ 样张局部均值的容差（三通道之和，5×5 邻域；2026-10-01 实测见渲染日志）。
    static let pasteTolerance = 12
    /// 取样点必须落在源样张的**平坦**区（各通道标准差之和 ≤ 此值，0-255 制）。
    static let flatSpread: Double = 10
    /// 平坦取样点的**下限**（不够就判红：取样点全落在文字上 = 判据失效）。
    static let minPastePoints = 4
}

/// 一个邻域的均值 + 起伏（各通道标准差的**和**，0-255 制）。
func blockStats(_ rep: NSBitmapImageRep, x: Int, y: Int,
                half: Int) -> (mean: (Double, Double, Double), spread: Double)? {
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0
    var r2 = 0.0, g2 = 0.0, b2 = 0.0
    for dy in -half...half {
        for dx in -half...half {
            let px = min(max(x + dx, 0), rep.pixelsWide - 1)
            let py = min(max(y + dy, 0), rep.pixelsHigh - 1)
            guard let c = rep.colorAt(x: px, y: py) else { return nil }
            r += c.redComponent; g += c.greenComponent; b += c.blueComponent
            r2 += c.redComponent * c.redComponent
            g2 += c.greenComponent * c.greenComponent
            b2 += c.blueComponent * c.blueComponent
            n += 1
        }
    }
    func sd(_ sum: Double, _ sum2: Double) -> Double {
        max(0, sum2 / n - (sum / n) * (sum / n)).squareRoot()
    }
    return ((r / n, g / n, b / n), (sd(r, r2) + sd(g, g2) + sd(b, b2)) * 255)
}

/// 贴图区与**源样张**必须对得上 —— 证明展示图里那一块就是那张真样张（不是重画的、也不是别的图）。
///
/// 三条纪律（都是实测踩出来的）：
///   · 比**局部均值**而不是单像素 —— 样张被缩到 0.65 倍，插值会让单像素在文字边缘差出几十/255，
///     那样判的就不是「贴的是哪张图」；
///   · 只在**平坦**区比（源样张那一块的起伏 ≤ `StoreMinimums.flatSpread`）—— 避开文字与分隔线；
///   · **平坦区不足就判红**（`StoreMinimums.minPastePoints`），否则「取样点全落在细节上」会假绿。
func pastedPixelsMatch(store: NSBitmapImageRep, samplePath: String) -> (ok: Bool, worst: Int, used: Int) {
    guard let sampleData = try? Data(contentsOf: URL(fileURLWithPath: samplePath)),
          let sample = NSBitmapImageRep(data: sampleData) else { return (false, 255, 0) }
    let rect = StoreLayout.shotRect
    let relatives: [(CGFloat, CGFloat)] = [
        (0.08, 0.10), (0.30, 0.06), (0.50, 0.06), (0.70, 0.06), (0.92, 0.35), (0.12, 0.40),
        (0.30, 0.55), (0.55, 0.62), (0.70, 0.78), (0.90, 0.70), (0.15, 0.95), (0.60, 0.95),
    ]
    var worst = 0
    var used = 0
    for (rx, ry) in relatives {
        let sx = min(Int(CGFloat(sample.pixelsWide) * rx), sample.pixelsWide - 1)
        let sy = min(Int(CGFloat(sample.pixelsHigh) * ry), sample.pixelsHigh - 1)
        guard let source = blockStats(sample, x: sx, y: sy, half: 5) else { return (false, 255, used) }
        guard source.spread <= StoreMinimums.flatSpread else { continue }
        // 出图是**像素 = 版式坐标 × renderScale**，取样点要换算到像素坐标（踩过一次：不换算时
        // 量的是别处的像素，判据变成噪声）。邻域半径按**贴图缩放比**折算 —— 两边的取样面积要相当，
        // 否则「源 11×11 / 出图 11×11」比的是 1.5 倍面积，边缘上必然差出几十/255（踩过）。
        let x = Int((rect.minX + rect.width * rx) * StoreLayout.renderScale)
        let y = Int((rect.minY + rect.height * ry) * StoreLayout.renderScale)
        let pasteScale = rect.width / CGFloat(sample.pixelsWide)
        let halfStore = max(1, Int((5 * pasteScale * StoreLayout.renderScale).rounded()))
        guard let pasted = blockStats(store, x: x, y: y, half: halfStore) else {
            return (false, 255, used)
        }
        let gap = (abs(pasted.mean.0 - source.mean.0) + abs(pasted.mean.1 - source.mean.1)
                   + abs(pasted.mean.2 - source.mean.2)) * 255
        used += 1
        worst = max(worst, Int(gap.rounded()))
    }
    return (used >= StoreMinimums.minPastePoints && worst <= StoreMinimums.pasteTolerance,
            worst, used)
}

// MARK: - 主流程

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    print("用法：store-shot <深色样张.png> <浅色样张.png> <输出目录>")
    exit(2)
}
let darkSample = arguments[1]
let lightSample = arguments[2]
let outDirectory = arguments[3]
try? FileManager.default.createDirectory(atPath: outDirectory, withIntermediateDirectories: true)

print("展示图渲染器：配色唯一来源 = platform/macos/Core/DesignTheme.swift 的 stardust 值表；产品窗口 = 真样张")

var checks: [StoreCheck] = []
let darkURL = renderStoreShot(samplePath: darkSample, isDark: true, label: "深色",
                              outputDirectory: outDirectory, checks: &checks)
let lightURL = renderStoreShot(samplePath: lightSample, isDark: false, label: "浅色",
                               outputDirectory: outDirectory, checks: &checks)

// ⑨ 深浅两张必须真的不一样（同构 ≠ 同一张）
func cornerGap(_ lhs: URL?, _ rhs: URL?) -> CGFloat? {
    guard let lhs, let rhs,
          let left = try? Data(contentsOf: lhs), let right = try? Data(contentsOf: rhs),
          let leftRep = NSBitmapImageRep(data: left), let rightRep = NSBitmapImageRep(data: right),
          let a = leftRep.colorAt(x: 2, y: 2), let b = rightRep.colorAt(x: 2, y: 2) else { return nil }
    return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
        + abs(a.blueComponent - b.blueComponent)
}
if let gap = cornerGap(darkURL, lightURL) {
    checks.append(StoreCheck(ok: gap * 255 > 40,
                             note: "深浅两态的角像素必须差得远（实测 \(Int(gap * 255))/255，门槛 40）"))
} else {
    checks.append(StoreCheck(ok: false, note: "深浅两态读不回来 —— 没法证明它们不是同一张"))
}

let failures = checks.filter { !$0.ok }
for check in checks { print("  \(check.ok ? "✓" : "✗") \(check.note)") }
print(failures.isEmpty ? "展示图自检通过（\(checks.count) 项）"
                       : "展示图自检失败（\(failures.count)/\(checks.count) 项）")
print("⚠️ 观感（构图 / 配文）须人工点验 —— 机械判据只能证明「色与图源同源」「版式不重叠」")
exit(failures.isEmpty ? 0 : 1)
