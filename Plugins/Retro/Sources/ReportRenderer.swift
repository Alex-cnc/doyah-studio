import Foundation

// `report.md` ⇒ 块序列的**纯函数渲染**（Retro macOS · M0 第 2 片）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-08`（右区按 `report.md` 渲染，标题层级 / 表格 /
// 引用 / 列表与源文一致）+ §6.5 `IR-05` 不变量 3（媒体按**相对路径**引用，不用绝对路径、不内嵌
// base64）+ `Docs/概要设计.md` §3.5 不变量 1（**渲染是纯函数** ⇒ 同一份输入逐字节相同的产物）。
//
// 三条硬口径：
//   ① **纯函数**：输出只由 `(markdown, 包目录)` 决定 —— 不读时钟、不读环境、不用随机 / 无序容器；
//      同一份 `report.md` 连续两次渲染 ⇒ `RenderedReport` 逐字节相同（判据 ⑤ 的机械形式）。
//   ② **只读**：本层**没有任何写盘入口**（不开文件写、不建目录、不改包）—— `FR-R-13-08` 判据 ③。
//   ③ **逐条报告且不崩**：取不到的图原位占位 + 一条 `ReportRenderIssue`，**不 throw、不中断**
//      （与 `FR-R-12-04` ③ / `FR-R-13-09` 判据 ④ 同口径）。
//
// **图片引用的三条去向**（判据 ④）：
//   · `![](assets/x.png)` 且文件在盘上 ⇒ `.inPackage(包内绝对路径)`；
//   · 文件不在盘上 ⇒ `.placeholder(fileMissing)` + 报告一条；
//   · 含 `..` 的越界路径 ⇒ `.placeholder(pathOutOfPackage)` + 报告一条；
//   · 绝对路径 / `data:` base64 / 带 scheme 的外链 ⇒ `.placeholder(referenceNotRelative)` + 报告一条。
// 最后一条不是「顺手也处理一下」：`IR-05` 不变量 3 明令不用绝对路径、不内嵌 base64 ⇒ 本渲染器
// **不设**这两类取图分支，它们只能落进「拒绝 + 报告」。

public enum ReportRenderer {

    // MARK: - 入口

    /// 直接把一期的包渲染成块序列（R-01 的 `ReportPackage` 直接喂进来）。
    public static func render(package: ReportPackage) -> RenderedReport {
        render(markdown: package.reportMarkdown, packageDirectory: package.directoryURL)
    }

    /// 渲染 `report.md` 正文。
    ///
    /// - Parameters:
    ///   - markdown: `report.md` 的正文（已按 `IR-05` 不变量 6 校验过 UTF-8 无 BOM）。
    ///   - packageDirectory: **这一期的包目录**（`index.json` / `report.md` / `assets/` 所在的那一层）。
    ///     图片相对路径一律**锚在这个目录上**解析。
    public static func render(markdown: String, packageDirectory: URL) -> RenderedReport {
        let lines = normalizedLines(markdown)
        var blocks: [MarkdownBlock] = []
        var issues: [ReportRenderIssue] = []

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // 代码块围栏（``` 开 / ``` 闭）：未闭合就吃到文末（不崩、不吞错）。
            if let info = codeFenceInfo(trimmed) {
                var body: [String] = []
                var cursor = index + 1
                while cursor < lines.count, codeFenceInfo(lines[cursor].trimmingCharacters(in: .whitespaces)) == nil {
                    body.append(lines[cursor])
                    cursor += 1
                }
                blocks.append(.codeBlock(language: info.isEmpty ? nil : info, text: body.joined(separator: "\n")))
                index = cursor < lines.count ? cursor + 1 : cursor
                continue
            }

            if let heading = headingBlock(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // 表格：本行是表头（≥2 列）且下一行是分隔行 ⇒ 成表；数据行吃到「空行 / 不含 |」为止。
            if isTableHeader(at: index, in: lines) {
                let header = splitTableRow(line)
                var rows: [[String]] = []
                var cursor = index + 2
                while cursor < lines.count {
                    let candidate = lines[cursor]
                    let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                    if candidateTrimmed.isEmpty || !candidateTrimmed.contains("|") { break }
                    rows.append(splitTableRow(candidate))
                    cursor += 1
                }
                blocks.append(.table(header: header, rows: rows))
                index = cursor
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                var cursor = index
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoted.append(quoteBody(candidate))
                    cursor += 1
                }
                blocks.append(.quote(text: quoted.joined(separator: "\n")))
                index = cursor
                continue
            }

            if let item = unorderedListItem(trimmed) {
                var items = [item]
                var cursor = index + 1
                while cursor < lines.count,
                      let next = unorderedListItem(lines[cursor].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    cursor += 1
                }
                blocks.append(.unorderedList(items: items))
                index = cursor
                continue
            }

            if let item = orderedListItem(trimmed) {
                var items = [item]
                var cursor = index + 1
                while cursor < lines.count,
                      let next = orderedListItem(lines[cursor].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    cursor += 1
                }
                blocks.append(.orderedList(items: items))
                index = cursor
                continue
            }

            if let reference = imageReference(trimmed) {
                blocks.append(resolveImage(alt: reference.alt,
                                           reference: reference.reference,
                                           line: index + 1,
                                           packageDirectory: packageDirectory,
                                           issues: &issues))
                index += 1
                continue
            }

            // 段落：吃到空行或「下一个块的起点」。
            var paragraph: [String] = []
            var cursor = index
            while cursor < lines.count {
                let candidate = lines[cursor]
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if isBlockStart(at: cursor, in: lines) { break }
                paragraph.append(candidate)
                cursor += 1
            }
            if paragraph.isEmpty {          // 防守：任何情况下都要前进，绝不空转
                paragraph.append(line)
                cursor = index + 1
            }
            blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
            index = cursor
        }

        return RenderedReport(blocks: blocks, issues: issues)
    }

    // MARK: - 图片解析（`IR-05` 不变量 3）

    /// 把一条图片引用解析成「包内绝对路径」或「占位 + 一条报告」。
    private static func resolveImage(
        alt: String,
        reference: String,
        line: Int,
        packageDirectory: URL,
        issues: inout [ReportRenderIssue]
    ) -> MarkdownBlock {
        func placeholder(_ reason: ImagePlaceholderReason, _ issue: ReportRenderIssue.Kind) -> MarkdownBlock {
            issues.append(ReportRenderIssue(line: line, kind: issue))
            return .image(MarkdownImage(alt: alt, reference: reference, resolution: .placeholder(reason: reason)))
        }

        // 空引用按「不是相对路径」处理（取不到图，也不该当合法路径去碰盘）。
        guard !reference.isEmpty else {
            return placeholder(.referenceNotRelative, .imageReferenceNotRelative(reference: reference))
        }

        // 非相对形态：绝对路径 / 带 scheme（`data:` base64、`http(s)://` 外链…）/ 残留 base64 载荷。
        // 本渲染器**不解析**这几种 —— 一律拒绝（`IR-05` 不变量 3 的硬口径）。
        if reference.hasPrefix("/") || hasScheme(reference) || reference.contains(";base64,") {
            return placeholder(.referenceNotRelative, .imageReferenceNotRelative(reference: reference))
        }

        // 越界（任何一段是 `..`）⇒ 拒绝，不做「先拼再判断能不能绕回来」的花活。
        if reference.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
            return placeholder(.pathOutOfPackage, .imagePathOutOfPackage(reference: reference))
        }

        // 锚在包目录上解析，并做一次词法标准化后的**包内**复核（双保险）。
        let base = packageDirectory.standardizedFileURL
        let resolved = URL(fileURLWithPath: reference, isDirectory: false, relativeTo: base).standardizedFileURL
        let basePath = base.path.hasSuffix("/") ? String(base.path.dropLast()) : base.path
        guard resolved.path == basePath || resolved.path.hasPrefix(basePath + "/") else {
            return placeholder(.pathOutOfPackage, .imagePathOutOfPackage(reference: reference))
        }

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return placeholder(.fileMissing, .imageFileMissing(reference: reference))
        }

        return .image(MarkdownImage(alt: alt, reference: reference, resolution: .inPackage(resolved)))
    }

    // MARK: - 行级判定

    /// `\n` 切行；顺手吃掉 CRLF 里残留的 `\r`（`IR-05` 不变量 6 要求 LF，但读到 CRLF 不该崩）。
    private static func normalizedLines(_ markdown: String) -> [String] {
        markdown.components(separatedBy: "\n").map { line in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }
    }

    /// ``` 围栏行 ⇒ 返回信息串（无信息串返回 `""`）；不是围栏行 ⇒ `nil`。
    private static func codeFenceInfo(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    /// `#` ~ `######` + 空格 + 文本。多于 6 个 `#` 不成标题（段落）。
    private static func headingBlock(_ trimmed: String) -> (level: Int, text: String)? {
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        return (hashes.count, rest.trimmingCharacters(in: .whitespaces))
    }

    /// `---` / `***` / `___`（≥3 个同种字符，允许夹杂空格）。
    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\t", with: "")
        guard compact.count >= 3, let kind = compact.first, "-*_".contains(kind) else { return false }
        return compact.allSatisfy { $0 == kind }
    }

    /// 无序项 ⇒ 返回项文本；否则 `nil`。`-` / `*` / `+` 后须跟空白（避免把 `-5%` 当列表）。
    private static func unorderedListItem(_ trimmed: String) -> String? {
        guard let marker = trimmed.first, "-*+".contains(marker) else { return nil }
        let rest = trimmed.dropFirst()
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// 有序项 ⇒ 返回项文本；否则 `nil`。`1.` / `2.` … 后须跟空白（避免把 `1.2 亿` 当列表）。
    private static func orderedListItem(_ trimmed: String) -> String? {
        let digits = trimmed.prefix { $0 >= "0" && $0 <= "9" }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(".") else { return nil }
        let afterDot = rest.dropFirst()
        guard afterDot.isEmpty || afterDot.first == " " || afterDot.first == "\t" else { return nil }
        return afterDot.trimmingCharacters(in: .whitespaces)
    }

    /// 一行**恰为** `![alt](reference)` ⇒ 拆出两半；否则 `nil`（行进混排的图片留在段落原文里）。
    private static func imageReference(_ trimmed: String) -> (alt: String, reference: String)? {
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")") else { return nil }
        guard let separator = trimmed.range(of: "](", options: [], range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex) else {
            return nil
        }
        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<separator.lowerBound])
        let reference = String(trimmed[separator.upperBound..<trimmed.index(before: trimmed.endIndex)])
        return (alt, reference.trimmingCharacters(in: .whitespaces))
    }

    /// 引用是否带 URL scheme（`data:` / `http:` / `file:` …）—— 带 scheme 的一律**不**当包内相对路径。
    private static func hasScheme(_ reference: String) -> Bool {
        guard let first = reference.first, first.isLetter else { return false }
        for character in reference.dropFirst() {
            if character == ":" { return true }
            if character == "/" { return false }
            if !(character.isLetter || character.isNumber || character == "+" || character == "-" || character == ".") {
                return false
            }
        }
        return false
    }

    /// 引用行里首个 `>` 之后的内容（`> 引用` ⇒ `引用`；`>引用` ⇒ `引用`）。
    private static func quoteBody(_ trimmed: String) -> String {
        var body = trimmed.dropFirst()
        if body.hasPrefix(" ") { body = body.dropFirst() }
        return String(body)
    }

    // MARK: - 表格

    /// `index` 处是不是「表头 + 分隔行」的成表起点（表头至少 2 列）。
    private static func isTableHeader(at index: Int, in lines: [String]) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        guard header.contains("|"), splitTableRow(header).count >= 2 else { return false }
        return isTableDelimiterRow(lines[index + 1])
    }

    /// `| --- | :--: |` 这类分隔行：每一格都是 `-`（可带两侧对齐冒号）。
    private static func isTableDelimiterRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            var body = cell.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return false }
            if body.hasPrefix(":") { body.removeFirst() }
            if body.hasSuffix(":") { body.removeLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    /// `| a | b |` ⇒ `["a", "b"]`：剥掉首尾竖线、按**未转义**的 `|` 切、逐格去空白（`\|` 是转义竖线）。
    private static func splitTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))

        // 外围竖线切出的首个 / 末个空串只可能来自「首 / 尾的 |」，去掉。
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("|"), cells.first == "" { cells.removeFirst() }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("|"), cells.last == "" { cells.removeLast() }
        return cells
    }

    // MARK: - 段落边界

    /// 某一行是不是「块的起点」（段落收集靠它停住）。与主循环里的判定**同一套**。
    private static func isBlockStart(at index: Int, in lines: [String]) -> Bool {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if codeFenceInfo(trimmed) != nil { return true }
        if headingBlock(trimmed) != nil { return true }
        if isHorizontalRule(trimmed) { return true }
        if isTableHeader(at: index, in: lines) { return true }
        if trimmed.hasPrefix(">") { return true }
        if unorderedListItem(trimmed) != nil { return true }
        if orderedListItem(trimmed) != nil { return true }
        if imageReference(trimmed) != nil { return true }
        return false
    }
}
