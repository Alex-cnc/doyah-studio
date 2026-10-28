import AppKit
import DoyahCore

/// **行号列的绘制件（全工程唯一一份）** —— 工作区代码编辑器与数据库 SQL 编辑器共用。
///
/// ## 为什么要抽出一件（2026-09-30 第 121 轮，队列 `L-111`）
///
/// 数据库侧 SQL 编辑器此前**没有行号列**，而工作区编辑器有（第 45 轮 `L-64` 落地）。
/// 补这一格时只有两条路：**再画一套**，或者**把绘画法抽出来共用**。选后者，理由是
/// 「一个文件在两个编辑器里行号不一致」这种缺陷几乎必然发生 —— 一处改了口径、另一处忘了跟：
/// · **口径**（一个逻辑行一个号 / 末尾终止符多一个空行 / 位置单位 UTF-16）在 Core
///   （`Core/CodeLines`，15 项单测，契约见概要设计 §3.17 不变量 10）；
/// · **画法**（列宽怎么量、数字怎么对齐、画哪几行）收在这一件里；
/// · 两个编辑器只负责「把它挂上」（`reload` + `draw`）。
///
/// ## 挂法（三步，两处一模一样）
///
/// ① `reload(_:)` —— 文本进去/换掉、字体变了、内容改了之后各调一次；
///   它顺带把 `textContainerInset.width` 定成列宽（**列是「正文左边那条空档」**，
///   所以必须在文本进去之后算，否则会先按空文档算成 1 位）。
/// ② `draw(in:of:)` —— 在 `NSTextView.draw(_:)` 里 `super.draw` **之后**调；
///   ⚠️ `super.draw` 前后必须 `saveGraphicsState()` / `restoreGraphicsState()`：
///  `NSTextView` 会把裁剪区收窄到文本容器（把 `textContainerInset` 那条空档整条裁掉）且不还回来
///   —— 不还原的话行号画不出来，症状是「整条列只剩右侧一个像素」（第 45 轮实测，AGENT-SPEC §9 第 21 条）。
/// ③ 只画**可见**的那几行（从可见区顶部那一行往后画到出界为止）—— 几千行的文档里
///   每帧硬扫全文会让滚动发涩。
final class LineNumberGutter {

    /// 已经算好的行起点（UTF-16 偏移）；由 `reload(_:)` 重算。
    private(set) var lineStarts: [Int] = [0]

    /// 列宽；`0` 表示还没算过（此时不画）。
    private(set) var width: CGFloat = 0

    /// 折叠标记（`FR-STD-WS-EDIT-017` ②）：行号 → 这一行的块折着没有。
    ///
    /// 空表 = 这份文档没有可折的块 ⇒ **列宽不多占那一格**（否则纯文本 / HTML 的行号列
    /// 会无端宽出一截，和 SQL 编辑器那一份也不一致）。
    private(set) var foldMarkers: [Int: Bool] = [:]

    /// 标记列宽（一枚三角 + 两侧留白）。只在有标记时占位。
    static let markerWidth: CGFloat = 11
    /// 三角的半边长（画出来的实际大小）。
    static let markerRadius: CGFloat = 3.5

    /// 逻辑行数（行起点个数）—— 判据读它，与「画」无关。
    var lineCount: Int { lineStarts.count }

    /// 列宽要留几位数（`digits(9) = 1` / `digits(10) = 2`）。
    var digits: Int { CodeLines.digits(of: lineStarts.count) }

    /// 数字用**当前等宽字体**的小号（FR-EDIT-26 里用户可换字体族 / 字号 ⇒ 跟着变）。
    static var font: NSFont {
        FontManager.shared.monospaceNSFont(size: TypeScale.monoSmallSize)
    }

    static let paddingLeft = Spacing.xs
    static let paddingRight = Spacing.s
    /// 上下留白（两个编辑器同一档：`Spacing.s`）。
    static let verticalInset = Spacing.s

    /// 行号列宽 = 左留白 + 位数 × 数字宽 + 右留白（+ 有折叠标记时再留一格标记列）。
    ///
    /// 数字宽按**当前字体实量**而不是写死：列宽写死的话，用户把字号调大（或换个更宽的等宽字体）
    /// 之后数字会被裁掉，而 99 → 100 行这种「多一位」同样会挤（`CodeLines.digits`）。
    static func width(digits: Int, hasMarkers: Bool = false) -> CGFloat {
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        return paddingLeft + CGFloat(max(1, digits)) * digitWidth + paddingRight
            + (hasMarkers ? markerWidth : 0)
    }

    /// 重算行起点与列宽，并把列宽交给 `textContainerInset`（正文从列的右边开始）。
    ///
    /// 返回「列宽变没变」—— 调用方据此判断要不要重排（字号 / 位数变了会变）。
    @discardableResult
    func reload(_ textView: NSTextView) -> Bool {
        lineStarts = CodeLines.lineStarts(in: textView.string)
        let newWidth = Self.width(digits: digits, hasMarkers: !foldMarkers.isEmpty)
        let changed = width == 0 || abs(newWidth - width) > 0.5
        if changed {
            width = newWidth
            // `textContainerInset.width` 左右同时生效 ⇒ 右边也留同一宽度。接受它：
            // 两个编辑器都是「无横滚 + 自动换行」，代价只是换行位置提前一点，
            // 换来的形态最简单（没有第二套滚动同步）。
            textView.textContainerInset = NSSize(width: newWidth, height: Self.verticalInset)
        }
        textView.needsDisplay = true
        return changed
    }

    /// 换上这一份折叠标记（行号 → 折没折），并按「标记列占不占位」重算列宽。
    ///
    /// 标记数一变（0 → N 或 N → 0）列宽就变，正文的可用宽度也跟着变 ⇒ 必须重排，
    /// 否则会出现「行号列宽了、正文却还按旧宽度换行」的错位。
    @discardableResult
    func applyFoldMarkers(_ markers: [Int: Bool], to textView: NSTextView) -> Bool {
        guard markers != foldMarkers else { return false }
        foldMarkers = markers
        return reload(textView)
    }

    /// 先让 `NSTextView` 画底色与正文，再把行号画上去（顺序反了会被底色盖掉 ——
    /// `drawsBackground = true` 时它填的是整个 `bounds`）。
    func draw(in dirtyRect: NSRect, of textView: NSTextView) {
        guard width > 0, let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let gutter = NSRect(x: 0, y: dirtyRect.minY, width: width, height: dirtyRect.height)
        Theme.nsColor(Surface.panel).setFill()
        gutter.fill()
        Theme.hairlineNSColor.setFill()
        NSRect(
            x: width - Metrics.hairline,
            y: dirtyRect.minY,
            width: Metrics.hairline,
            height: dirtyRect.height
        ).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: Theme.nsColor(TextTone.tertiary),
        ]
        let origin = textView.textContainerOrigin
        let length = (textView.string as NSString).length

        // 只画看得见的那几行：先问「可见区顶部落在哪个字符上」，再从那一行往后画到出界为止。
        let probeY = max(0, dirtyRect.minY - origin.y)
        let probeCharacter = layoutManager.characterIndex(
            for: NSPoint(x: 0, y: probeY),
            in: container,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        var index = max(0, CodeLines.lineNumber(at: probeCharacter, lineStarts: lineStarts) - 1)
        // 与**正文基线**对齐：数字比正文小一号，按顶边对齐会看起来高一档。
        // 正文的升部取自**编辑器自己的字体**（两处的 baseFont 都是同一族等宽字体 ⇒ 与「取 baseFont」等价）。
        let bodyAscender = (textView.font ?? Theme.nsFont(.mono)).ascender

        while index < lineStarts.count {
            let top = origin.y
                + fragmentTop(
                    forLineStartingAt: lineStarts[index],
                    layoutManager: layoutManager,
                    container: container,
                    length: length
                )
            if top > dirtyRect.maxY { break }

            let label = "\(index + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let x = width - Self.paddingRight - size.width
                - (foldMarkers.isEmpty ? 0 : Self.markerWidth)
            let y = top + (bodyAscender - Self.font.ascender)
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            // 折叠标记（`FR-STD-WS-EDIT-017` ②）：只给「有块可折」的那几行画。
            if let folded = foldMarkers[index + 1] {
                drawFoldMarker(isFolded: folded, top: top, lineHeight: bodyAscender + 2)
            }
            index += 1
        }
    }

    /// 画一枚折叠标记：**折着 = 向右的三角**（`▸`，表示"展开看看里面"），
    /// **展开 = 向下的三角**（`▾`，表示"收起来"）。方向语义与系统里所有折叠控件一致。
    ///
    /// 颜色走令牌（深浅两套都在 `AccentFamily` / `TextTone` 里）：折着的那一枚用强调色，
    /// 一眼能看出「这几行是被折起来的，不是文件本来就短」。
    private func drawFoldMarker(isFolded: Bool, top: CGFloat, lineHeight: CGFloat) {
        let columnMinX = width - Self.markerWidth
        let centerX = columnMinX + Self.markerWidth / 2
        let centerY = top + lineHeight / 2
        let radius = Self.markerRadius
        let path = NSBezierPath()
        // 视图是 flipped 的（y 向下增长）⇒ 「下方」= `centerY + radius`。
        if isFolded {
            path.move(to: NSPoint(x: centerX - radius / 2, y: centerY - radius))
            path.line(to: NSPoint(x: centerX - radius / 2, y: centerY + radius))
            path.line(to: NSPoint(x: centerX + radius, y: centerY))
        } else {
            path.move(to: NSPoint(x: centerX - radius, y: centerY - radius / 2))
            path.line(to: NSPoint(x: centerX + radius, y: centerY - radius / 2))
            path.line(to: NSPoint(x: centerX, y: centerY + radius))
        }
        path.close()
        (isFolded
            ? Theme.nsColor(AccentFamily.accent.color(in: Theme.designTheme))
            : Theme.nsColor(TextTone.secondary)).setFill()
        path.fill()
    }

    // MARK: 命中（点标记 = 折 / 展）

    /// 这一点落在哪一行的折叠标记上（`nil` = 这一点不是标记 ⇒ 调用方交还默认点击行为）。
    ///
    /// 判定的是**标记列**（行号列最右边那一格）而整条行号列：行号本身还能点着选中整行
    /// （那条老行为不动），只有点在小三角上才折。
    func foldMarkerLine(at point: NSPoint, of textView: NSTextView) -> Int? {
        guard !foldMarkers.isEmpty, width > 0 else { return nil }
        let columnMinX = width - Self.markerWidth
        guard point.x >= columnMinX, point.x <= width else { return nil }
        guard let line = lineNumber(atY: point.y, of: textView) else { return nil }
        return foldMarkers[line] == nil ? nil : line
    }

    /// 纵坐标 → 行号（1 起）。口径与画行号那一侧同一个 `CodeLines`。
    private func lineNumber(atY y: CGFloat, of textView: NSTextView) -> Int? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let origin = textView.textContainerOrigin
        let probeY = max(0, y - origin.y)
        let character = layoutManager.characterIndex(
            for: NSPoint(x: 0, y: probeY),
            in: container,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        let length = (textView.string as NSString).length
        guard character <= length else { return nil }
        return CodeLines.lineNumber(at: character, lineStarts: lineStarts)
    }

    /// 某一行的**顶边**（文本容器坐标）。
    ///
    /// 两类位置要分开取：正常行按第一个字形的 line fragment（软换行的续行用同一个起点 ⇒ 一个逻辑行
    /// 只有一个号，这是对的）；而末尾那个空行**没有字形**，取 `NSTextView` 为它准备的 extra line fragment
    /// （口径 ② 在画这一侧的落点 —— 少了它，末尾空行就没有号）。
    private func fragmentTop(
        forLineStartingAt lineStart: Int,
        layoutManager: NSLayoutManager,
        container: NSTextContainer,
        length: Int
    ) -> CGFloat {
        guard lineStart < length else {
            if layoutManager.extraLineFragmentTextContainer != nil {
                return layoutManager.extraLineFragmentRect.minY
            }
            return layoutManager.usedRect(for: container).maxY
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: lineStart)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }
}
