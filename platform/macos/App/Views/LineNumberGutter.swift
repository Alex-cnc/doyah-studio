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

    /// 行号列宽 = 左留白 + 位数 × 数字宽 + 右留白。
    ///
    /// 数字宽按**当前字体实量**而不是写死：列宽写死的话，用户把字号调大（或换个更宽的等宽字体）
    /// 之后数字会被裁掉，而 99 → 100 行这种「多一位」同样会挤（`CodeLines.digits`）。
    static func width(digits: Int) -> CGFloat {
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        return paddingLeft + CGFloat(max(1, digits)) * digitWidth + paddingRight
    }

    /// 重算行起点与列宽，并把列宽交给 `textContainerInset`（正文从列的右边开始）。
    ///
    /// 返回「列宽变没变」—— 调用方据此判断要不要重排（字号 / 位数变了会变）。
    @discardableResult
    func reload(_ textView: NSTextView) -> Bool {
        lineStarts = CodeLines.lineStarts(in: textView.string)
        let newWidth = Self.width(digits: digits)
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
            let y = top + (bodyAscender - Self.font.ascender)
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            index += 1
        }
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
