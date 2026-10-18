import Foundation

/// 一条可作路径候选的工作区条目（相对工作区根、`/` 分隔）。
///
/// 为什么要一个自己的值类型、而不是直接用 `WorkspaceEntry`：那条树上还带着"是不是符号链接""能不能展开"
/// 这些**树渲染才需要**的东西；灰字只要两件事 —— **写进正文的路径**与**补完要不要加 `/`**。
/// 少带字段就少一处漂移（将来树改了契约，灰字不该被牵着动）。
public struct WorkspacePathCandidate: Equatable, Sendable {

    /// 相对工作区根的路径（磁盘上的**规范写法**，大小写照原样）。
    public let relativePath: String

    /// 目录 ⇒ 接受后补一个 `/`（用户还要继续往里写）；文件 ⇒ 补到文件名为止。
    public let isDirectory: Bool

    public init(relativePath: String, isDirectory: Bool) {
        self.relativePath = relativePath
        self.isDirectory = isDirectory
    }
}

/// 路径那一路的一次判定结果。
///
/// 为什么要三种、而不是继续用 `nil`：`inline` 的 `nil` 只有"不出灰字"一种意思，
/// 但路径这里必须分清两种 `nil` ——
///   · `notPath`：这一刻**不是**在写路径（比如敲的是 `ret`）⇒ 交给词法候选，别抢；
///   · `nothing`：**确实**在写路径，但没有可补的（`@` 后面空着、或 `Docs/zzz` 不存在）
///     ⇒ 一条都不出，**也不许退化成词补全**（在路径位置上补出个标识符比不补更糟）。
/// 这两种混成一个 `nil` 的话，`Docs/zz` 会被词法候选接过去，用户看到的是"路径写着写着冒出个变量名"。
public enum PathGhostOutcome: Equatable, Sendable {

    /// 不是在写路径 ⇒ 调用方可以继续走词法候选。
    case notPath

    /// 在写路径，但这一格没有可补的 ⇒ 什么都不出。
    case nothing

    /// 该画的那一条。
    case suggestion(InlineGhostSuggestion)
}

/// 工作区**路径候选**（`FR-EDIT-57` 最后一块：`@` / 相对路径提示）。
///
/// ## 为什么要有这一片
///
/// 需求提出者 2026-10-15 的原话是「工作区的代码编辑器也要下功夫做到好用，编程助手的基本能力都要有」。
/// 写 Markdown 时最常打断人的动作是**引一个工作区里的文件**：`![图](Docs/img/…`、`[见](../Docs/…)`。
/// 这条路此前要么手打全路径、要么切到文件树里翻 —— 编程助手的基本能力里，路径补全是和词补全同一档的。
///
/// ## 六条口径（每条都是刻意的取舍，`Tests/InlineGhostPathTests.swift` 逐条守着）
///
/// 1. **只在"像路径"时才给**：片段里有 `/`、以 `~` 起、或前面带 `@` 标记。
///    **裸词一律不猜路径** —— 否则代码里敲 `ret` 会被补成 `retry.swift`，那是替用户改代码。
/// 2. **只补最后一段**：已写出来的目录部分必须**逐段对上**（大小写不敏感 —— macOS 文件系统本来就不敏感），
///    但写进正文的是**磁盘上的规范写法**（敲 `docs/des` 得到 `Docs/design/`，不是把小写留在文件里）。
/// 3. **目录补完带 `/`、文件不带**：目录后面用户总要继续写，少打一个 `/` 是最常见的手误。
/// 4. **排序可判**：短路径优先 → 目录优先 → 字典序。理由：路径越短越可能是用户想指的那个，
///    同长时目录优先（它能继续往下走），最后一档只为让结果**确定**（同一个索引永远同一个建议）。
/// 5. **长度上限 120**（`maximumPathGhostLength`）：词那一路的 24 对路径太紧
///    （`Docs/design/开发循环-每轮卡.md` 一个就 30 多）；上限只是为了拦住几百字符的病态路径。
///    画不下时由界面截断加省略号（`GhostTextOverlay`），**接受后落进正文的仍是完整路径**。
/// 6. **前三道门与词那一路共用**（`InlineGhostCompletion.gate`）：有选区 / 组字期间 / 字符串或注释里一律不出。
///
/// ## 已知边界（如实登记）
///
/// · **不转义空格**：文件名里有空格时插进去的是原名（Markdown 里没问题，Shell 里要自己加引号）；
/// · 索引是**有界快照**：深度 6 / 4,000 条 / 跳过构建产物与版本库目录（与 `WorkspaceSearch` 同一套），
///   超出上限的深目录里的文件补不到 —— 这是刻意的，不能让一次击键去扫整个家目录；
/// · 符号链接不跟随（可能指向工作区外），所以在灰字里也补不到。
public enum PathGhostCompletion {

    /// 路径候选最长多少字符（见口径 5）。
    public static let maximumPathGhostLength = 120

    /// 索引的默认深度上限（工作区根算第 0 层）。
    public static let defaultMaxDepth = 6

    /// 索引的默认条数上限。
    public static let defaultIndexLimit = 4_000

    /// `@` 标记：写在这个字符后面的片段按路径补（`@Docs/de`）。
    public static let mentionMarker: Character = "@"

    /// 工作区路径表（有界快照）。
    public struct Index: Equatable, Sendable {

        public let candidates: [WorkspacePathCandidate]

        /// 是否因为条数 / 深度上限而提前停（**如实登记**：界面不显示，但代码里能查到）。
        public let isTruncated: Bool

        public init(candidates: [WorkspacePathCandidate], isTruncated: Bool = false) {
            self.candidates = candidates
            self.isTruncated = isTruncated
        }
    }

    // MARK: - 索引

    /// 广播式搭一张路径表（**有界**：深度、条数、忽略名单）。
    ///
    /// 与 `WorkspaceSearch` 的差别只在用途：那边按名字找**文件**，这边要的是"所有能当路径写的条目"
    /// （目录也算，因为目录是路径中间那几段）。忽略名单、不跟随符号链接、有界遍历这三条**共用同一套口径**。
    public static func index(
        in root: URL,
        maxDepth: Int = defaultMaxDepth,
        limit: Int = defaultIndexLimit,
        ignored: Set<String> = WorkspaceTree.searchIgnored,
        fileManager: FileManager = .default
    ) -> Index {
        guard limit > 0, maxDepth >= 0 else { return Index(candidates: [], isTruncated: false) }
        var collected: [WorkspacePathCandidate] = []
        var truncated = false
        var queue: [(url: URL, depth: Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (directory, depth) = queue.removeFirst()
            guard depth < maxDepth else { continue }
            guard let children = try? WorkspaceTree.children(
                of: directory,
                relativeTo: root,
                showHidden: false,
                ignored: ignored,
                fileManager: fileManager
            ) else { continue }

            for entry in children {
                switch entry.kind {
                case .symlink:
                    continue                       // 不跟随：它可能指向工作区外
                case .directory:
                    if collected.count >= limit { truncated = true; return Index(candidates: collected, isTruncated: true) }
                    collected.append(WorkspacePathCandidate(relativePath: entry.relativePath, isDirectory: true))
                    queue.append((directory.appendingPathComponent(entry.name), depth + 1))
                case .file:
                    if collected.count >= limit { truncated = true; return Index(candidates: collected, isTruncated: true) }
                    collected.append(WorkspacePathCandidate(relativePath: entry.relativePath, isDirectory: false))
                }
            }
        }

        return Index(candidates: collected, isTruncated: truncated)
    }

    // MARK: - 候选

    /// 给定用户已敲出来的片段（含 `@` 标记），算**该写进正文的**整串（含 `@`、目录带结尾 `/`），已排序。
    ///
    /// 返回空数组 = 这是路径形态但没有可补的。**不是**路径形态的判断不在这里（见 `pathSuggestion`）。
    public static func candidates(typed: String, in index: [WorkspacePathCandidate]) -> [String] {
        let hasMarker = typed.first == mentionMarker
        let body = hasMarker ? String(typed.dropFirst()) : typed
        let marker = hasMarker ? String(mentionMarker) : ""

        // 拆最后一段：前面的目录部分必须逐段对上，只补 leaf。
        let slash = body.lastIndex(of: "/")
        let directoryPart = slash.map { String(body[...$0]) } ?? ""
        let leaf = slash.map { String(body[body.index(after: $0)...]) } ?? body

        let directoryLower = directoryPart.lowercased()
        let leafLower = leaf.lowercased()

        var matched: [String] = []
        for candidate in index {
            let path = candidate.relativePath
            guard !path.isEmpty else { continue }

            if directoryPart.isEmpty {
                // 没有目录部分 ⇒ 只看根那一层（`@Doc` 得到 `Docs/`，不跨层猜）。
                guard !path.contains("/") else { continue }
                guard path.lowercased().hasPrefix(leafLower) else { continue }
            } else {
                // 目录部分要**真的**对上（不是子串）：`Doc/` 不能match `Docs/…`。
                guard path.count > directoryPart.count,
                      String(path.prefix(directoryPart.count)).lowercased() == directoryLower else { continue }
                let rest = String(path.dropFirst(directoryPart.count))
                let segment = rest.firstIndex(of: "/").map { String(rest[..<$0]) } ?? rest
                guard segment.lowercased().hasPrefix(leafLower) else { continue }
            }
            // 已经打全了 ⇒ 没得补（灰字为空没法画）。目录多一个结尾 `/`，所以目录在这里仍然算"有得补"。
            let insertText = marker + path + (candidate.isDirectory ? "/" : "")
            guard insertText.count > typed.count else { continue }
            matched.append(insertText)
        }

        return matched.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            let lhsIsDirectory = lhs.hasSuffix("/")
            let rhsIsDirectory = rhs.hasSuffix("/")
            if lhsIsDirectory != rhsIsDirectory { return lhsIsDirectory }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    /// 算一条**路径**灰字。
    ///
    /// 只有"像路径"的片段才会进候选（口径 1）；不像的话返回 `.notPath`，让调用方走词法候选。
    public static func pathSuggestion(
        in text: String,
        selection: NSRange,
        language: TextLanguage,
        index: [WorkspacePathCandidate],
        enabled: Bool = true
    ) -> PathGhostOutcome {
        // 前三道门与词那一路**同一份**（`InlineGhostCompletion.gate`）：开关 / 单空选区 / 字符串注释里不出。
        guard let gate = InlineGhostCompletion.gate(
            in: text,
            selection: selection,
            language: language,
            enabled: enabled
        ) else { return .nothing }
        let ns = gate.ns
        let caret = gate.caret

        // 往前扫到这段路径的开头。`@` 是**标记**（不是路径体）：只认紧贴片段前面的那一个。
        var start = caret
        while start > 0, isPathBody(ns.character(at: start - 1)) { start -= 1 }
        var hasMarker = false
        if start > 0, ns.character(at: start - 1) == unicharFor(mentionMarker) {
            start -= 1
            hasMarker = true
        }
        let range = NSRange(location: start, length: caret - start)
        guard range.length > 0 else { return .notPath }
        let typed = ns.substring(with: range)
        let body = hasMarker ? String(typed.dropFirst()) : typed

        // 口径 1：只在"像路径"时给。裸词交给词法候选 —— 敲 `ret` 不许被补成 `retry.swift`。
        let looksLikePath = hasMarker || body.contains("/") || body.hasPrefix("~") || body.hasPrefix("./")
            || body.hasPrefix("../")
        guard looksLikePath else { return .notPath }

        // 光标右边还是路径体 ⇒ 用户在路径中间改东西，不是在等补全（也不许退化成词补全）。
        if caret < ns.length, isPathBody(ns.character(at: caret)) { return .nothing }

        // `@` 后面空着、或整段只有一个字符 ⇒ 还没有可猜的东西（与词那一路 `minimumPrefixLength` 同一取舍）。
        guard body.count >= 1, typed.count >= 2 else { return .nothing }

        for insertText in candidates(typed: typed, in: index) {
            // 写进正文的是**规范写法**，所以只能比"整串前缀"，不能再按用户敲的大小写逐字相等。
            guard insertText.count > typed.count,
                  insertText.lowercased().hasPrefix(typed.lowercased()) else { continue }
            let ghost = String(insertText.dropFirst(typed.count))
            guard !ghost.isEmpty,
                  !ghost.contains("\n"), !ghost.contains("\r"),
                  ghost.count <= maximumPathGhostLength else { continue }
            return .suggestion(
                InlineGhostSuggestion(
                    range: range,
                    insertText: insertText,
                    ghost: ghost,
                    // 路径候选与文档词同一档淡法：都是"你这篇 / 这个工作区里已经有的东西"，不是语言知识。
                    kind: .word,
                    caretOffset: range.location + (insertText as NSString).length
                )
            )
        }
        return .nothing
    }

    // MARK: - 词法边界

    /// 路径体的终止符：空白、引号、括号、逗号分号、赋值与管道…
    ///
    /// 为什么是"黑名单"而不是"白名单"：文件名可以合法地含中文、emoji、`&`、`+`、`%` 这些，
    /// 白名单会静默把它们切成两半；而这些符号恰恰是**代码语法**里用来分隔 token 的，黑名单更准。
    static let pathStopScalars: Set<Unicode.Scalar> = [
        "\"", "'", "`", "(", ")", "[", "]", "{", "}", "<", ">",
        ",", ";", ":", "=", "|", "\\", "*", "?", "#", "@"
    ]

    static func isPathBody(_ codeUnit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(codeUnit) else { return false }
        if scalar.properties.isWhitespace { return false }
        if pathStopScalars.contains(scalar) { return false }
        return !CharacterSet.controlCharacters.contains(scalar)
    }

    private static func unicharFor(_ character: Character) -> unichar {
        unichar(String(character).utf16.first ?? 0)
    }
}
