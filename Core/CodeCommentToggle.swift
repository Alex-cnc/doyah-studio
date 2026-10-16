import Foundation

/// 一次「注释切换」编辑动作的落法（与 `CodePairingPlan` / `MarkdownEditPlan` 同口径：UTF-16 坐标）。
///
/// 与那两个 plan 的区别只有一个：**替换范围是整段行**（可能要动好几行的行首），
/// 所以 `replacement` 是整块文本 —— 宿主一次 `replaceCharacters` 落下去，⌘Z 一步回得去。
public struct CodeCommentPlan: Equatable, Sendable {
    /// 要替换的范围（UTF-16）—— **整块行**（含行尾换行符之外的全部内容）。
    public let range: NSRange
    /// 替换成什么（整块新文本）。
    public let replacement: String
    /// 替换完成后的选区起点（UTF-16）。
    public let caret: Int
    /// 替换完成后的选区长度（0 = 只有光标）。
    public let selectionLength: Int

    public init(range: NSRange, replacement: String, caret: Int, selectionLength: Int = 0) {
        self.range = range
        self.replacement = replacement
        self.caret = caret
        self.selectionLength = selectionLength
    }
}

/// 注释切换（`FR-EDIT-51`）：⌘/ 按**当前语言的注释符**给选区（或光标所在行）加 / 取消行注释。
///
/// ## 为什么是纯逻辑、纯函数
///
/// 判据天然是「给『文本 + 选区 + 语言』要『期望文本 + 期望选区』」。这族最容易错的是
/// **多行选区里空行的处置**与**取消注释时空格的去留**（`//  x` 去掉注释后该是 `x` 还是 ` x`）——
/// 两者都只在界面上"看着别扭"，没有判据就会长期歪着。
///
/// ## 口径（每一条都有判据）
///
/// · **注释符只从语言表来**：`CodeSyntax.comments` 里第一个行注释（`isLine`）。本文件**不出现任何**
///   具体语言的注释符 —— 语言知识只有一处（`Core/CodeLanguageDefinitions.swift` 的纪律），
///   新增语言因此**不改核心代码**；
/// · **没有行注释符 ⇒ 交还系统**（返回 `nil`）：只登记了块注释的语言（HTML / CSS / JSON）不在本片范围内，
///   宁可什么都不做，也不硬编一个 `<!--` 出来；
/// · **影响范围 = 选区覆盖的整行**（无选区 ⇒ 光标那一行）；选区终点落在行首 ⇒ **不算进那一行**（与主流一致）；
/// · **空行不参与判定、也不动**：整块全是空行 ⇒ `nil`；混着空行时，空行保持原样（不写 `// ` 上去）；
/// · **全注释 ⇒ 取消**；否则**一律加**（一行有一行没有也算"加"，不做混合态特判）；
/// · **取消时连我们加的那个空格一起去掉**（`// x` → `x`）：不然来回切一次会一点点往右挪；
/// · **缩进保持**：注释符插在缩进之后，不是在绝对行首。
public enum CodeCommentToggling {

    /// ⌘/ 该怎么落。返回 `nil` = **交还系统**（不是失败，是"这门语言本片不管"或"没什么可动的"）。
    public static func plan(in text: String, selection: NSRange, syntax: CodeSyntax) -> CodeCommentPlan? {
        guard let token = syntax.comments.first(where: { $0.isLine })?.open, !token.isEmpty else { return nil }

        let ns = text as NSString
        let length = ns.length
        guard length > 0 else { return nil }

        // 行范围：行数学全部走 `CodeLines`（行号列 / 跳转行 / 高亮都是同一份实现），这里不另数 `\n`。
        let starts = CodeLines.lineStarts(in: text)
        let selStart = min(max(0, selection.location), length)
        let selEnd = min(max(selStart, selStart + selection.length), length)
        let firstLine = CodeLines.lineNumber(at: selStart, lineStarts: starts)
        let lastProbe = (selEnd > selStart) ? max(selStart, selEnd - 1) : selStart
        let lastLine = CodeLines.lineNumber(at: lastProbe, lineStarts: starts)
        guard let firstRange = CodeLines.range(ofLine: firstLine, lineStarts: starts, length: length),
              let lastRange = CodeLines.range(ofLine: lastLine, lineStarts: starts, length: length),
              NSMaxRange(lastRange) >= firstRange.location else { return nil }
        let blockRange = NSRange(location: firstRange.location,
                                 length: NSMaxRange(lastRange) - firstRange.location)

        // 块内按 `\n` 切；行终止符带来的那个"末尾空串"不算一行（`CodeLines` 同族口径）。
        var block = ns.substring(with: blockRange)
        var hadTrailingNewline = false
        if block.hasSuffix("\n") { block.removeLast(); hadTrailingNewline = true }
        let parts = block.components(separatedBy: "\n")

        func indentAndRest(_ line: String) -> (indent: String, rest: String) {
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            return (indent, String(line.dropFirst(indent.count)))
        }

        let hasContent = parts.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard hasContent else { return nil }

        let commented = parts.allSatisfy {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix(token)
        }

        var newParts: [String] = []
        // 逐行的"改动落点"（原块内的偏移）与增量 —— 用它把选区平移过去。
        var edits: [(at: Int, delta: Int)] = []
        var cursor = 0
        for part in parts {
            let (indent, rest) = indentAndRest(part)
            let blank = rest.trimmingCharacters(in: .whitespaces).isEmpty
            if blank {
                newParts.append(part)
            } else if commented {
                var body = rest
                body.removeFirst(token.count)
                if body.hasPrefix(" ") { body.removeFirst() }   // 连我们自己加的那一个空格一起去掉
                let line = indent + body
                newParts.append(line)
                edits.append((at: cursor + indent.count, delta: line.count - part.count))
            } else {
                let line = indent + token + " " + rest
                newParts.append(line)
                edits.append((at: cursor + indent.count, delta: line.count - part.count))
            }
            cursor += part.count + 1                                  // +1 = 被切掉的那个 `\n`
        }

        var replacement = newParts.joined(separator: "\n")
        if hadTrailingNewline { replacement += "\n" }
        guard replacement != block else { return nil }                 // 一个字符都没变 ⇒ 别白改一次（撤销栈也是资源）

        /// 把原块内的偏移映射到新块内：落在某个改动点之后的，累加该点的增量。
        func map(_ offsetInBlock: Int) -> Int {
            var value = offsetInBlock
            for edit in edits where offsetInBlock >= edit.at { value += edit.delta }
            return max(0, value)
        }

        let startInBlock = max(0, selStart - blockRange.location)
        let endInBlock = max(0, selEnd - blockRange.location)
        let newStart = blockRange.location + map(startInBlock)
        let newEnd = blockRange.location + map(endInBlock)
        return CodeCommentPlan(range: blockRange,
                               replacement: replacement,
                               caret: newStart,
                               selectionLength: max(0, newEnd - newStart))
    }
}
