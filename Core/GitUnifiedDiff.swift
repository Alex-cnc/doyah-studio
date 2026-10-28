import Foundation

// `FR-STD-WS-VCS-001`（Git 只读与差异）的**差异投影**：`git diff` 的统一格式原文 ⇒ 可画的逐行结构。
//
// 为什么不直接 `AgentTextDiff.lines(before:after:)`：那是**两份文本之间**的差异（Agent 改文件前后用），
// 而这里要读的是 **git 自己算好的差异**（含 `@@` 分段、行号、二进制、改名、新文件 / 删文件）。
// 两者的输入不同源，硬并成一份会让「界面显示的差异」与「git 认为的差异」变成两件事。
//
// 四条硬口径：
//   ① **分段由 `@@` 的计数驱动**，不是靠「遇到 `diff --git` 就翻页」——
//      在 hunk 正文里，一行 `+++ b/x` 的真实含义是**新增一行以 `++ b/x` 开头的正文**；
//      按前缀认头就会把一个内容行当成文件头，随后整段差异错位（本仓栽过同族事故）。
//   ② **行号来自两个游标**（旧文 / 新文各一个），逐行推进；`\ No newline at end of file` 只写标记、
//      **不推进游标**（它描述的是上一行，不是一行内容）。
//   ③ **认不出的头忽略**（`index` / `similarity index` / `old mode`…）：它们是元数据，
//      画不到屏幕上；但**文件本身不许丢** —— 只要出现过 `diff --git` 就有一条。
//   ④ **有上限**：一个巨型文件不整份塞进视图（`maxLinesPerFile`），超了就 `truncated = true`
//      并在界面上如实说「只显示前 N 行」。

/// 差异里的一行。
public struct GitDiffLine: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable {
        case context
        case added
        case removed
    }

    public var kind: Kind
    /// 行正文（**不含** 前导的 `+` / `-` / 空格）。
    public var text: String
    /// 旧文行号（新增行没有）。
    public var oldNumber: Int?
    /// 新文行号（删除行没有）。
    public var newNumber: Int?
    /// 这一行原本是文件最后一行且原文件末尾没有换行（`\ No newline at end of file`）。
    public var noNewlineAtEnd: Bool

    public init(kind: Kind, text: String, oldNumber: Int?, newNumber: Int?,
                noNewlineAtEnd: Bool = false) {
        self.kind = kind
        self.text = text
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.noNewlineAtEnd = noNewlineAtEnd
    }
}

/// 一个 `@@` 分段。
public struct GitDiffHunk: Equatable, Sendable {
    /// 原样的头（`@@ -12,7 +12,9 @@ func foo()`），证据面用。
    public var header: String
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    /// 头里 `@@` 之后那段（git 给的作用域提示），没有就是空串。
    public var section: String
    public var lines: [GitDiffLine]

    public init(header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int,
                section: String = "", lines: [GitDiffLine] = []) {
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.section = section
        self.lines = lines
    }
}

/// 一个文件的差异。
public struct GitDiffFile: Equatable, Sendable {

    /// 旧路径（`---` 那一行；`/dev/null` ⇒ 空串）。
    public var oldPath: String
    /// 新路径（`+++` 那一行；`/dev/null` ⇒ 空串）。
    public var newPath: String
    public var isBinary: Bool
    public var isNew: Bool
    public var isDeleted: Bool
    public var hunks: [GitDiffHunk]
    /// 因为行数上限被截断（界面上要如实说）。
    public var truncated: Bool

    public init(oldPath: String, newPath: String, isBinary: Bool = false, isNew: Bool = false,
                isDeleted: Bool = false, hunks: [GitDiffHunk] = [], truncated: Bool = false) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.isBinary = isBinary
        self.isNew = isNew
        self.isDeleted = isDeleted
        self.hunks = hunks
        self.truncated = truncated
    }

    /// 列表上显示哪个路径：删掉的文件只有旧路径，其余以新路径为准。
    public var displayPath: String {
        if isDeleted { return oldPath.isEmpty ? newPath : oldPath }
        return newPath.isEmpty ? oldPath : newPath
    }

    /// 这个文件加了几行 / 删了几行。
    public var addedCount: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count } }
    public var removedCount: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count } }

    /// 这个文件有没有可画的正文（二进制 / 只有模式变化都没有）。
    public var hasBody: Bool { hunks.contains { !$0.lines.isEmpty } }
}

/// 一次 `git diff` 的完整投影。
public struct GitDiffDocument: Equatable, Sendable {

    public var files: [GitDiffFile]

    public init(files: [GitDiffFile] = []) {
        self.files = files
    }

    public var isEmpty: Bool { files.isEmpty }
    public var addedTotal: Int { files.reduce(0) { $0 + $1.addedCount } }
    public var removedTotal: Int { files.reduce(0) { $0 + $1.removedCount } }
    public var isTruncated: Bool { files.contains(where: \.truncated) }
    public var hasBinary: Bool { files.contains(where: \.isBinary) }
    public var hasBody: Bool { files.contains(where: \.hasBody) }
}

public enum GitUnifiedDiff {

    /// 单个文件最多画多少行（超了 `truncated`，界面上说明「只显示前 N 行」）。
    public static let defaultMaxLinesPerFile = 4_000

    /// 解析 `git diff`（`--no-color`、统一格式）的原文。
    public static func parse(_ text: String,
                             maxLinesPerFile: Int = defaultMaxLinesPerFile) -> GitDiffDocument {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var files: [GitDiffFile] = []
        var file: FileBuilder?
        var remainingOld = 0
        var remainingNew = 0

        /// 收口当前文件（把 builder 变成不可变结构）。
        func closeFile() {
            guard let builder = file else { return }
            files.append(builder.finish())
            file = nil
        }

        for raw in lines {
            // 在 hunk 正文里（**判据是 `@@` 的剩余计数，不是这一行长什么样**）：
            // 只要这两个计数还没走完，任何一行都是正文 —— 包括以 `diff --git` / `---` / `+++`
            // 开头的那些（它们在正文里就是内容；按前缀认头会把文件切成两半、行号全错）。
            if let builder = file, let hunk = builder.current,
               remainingOld > 0 || remainingNew > 0,
               let first = raw.first {
                if first == "\\" {
                    // `\ No newline at end of file`：描述**上一行**，本身不是一行内容。
                    builder.markLastStoredLineNoNewline()
                    continue
                }
                let body = String(raw.dropFirst())
                switch first {
                case " ":
                    builder.appendLine(kind: .context, text: body, hunk: hunk,
                                       oldNumber: hunk.oldCursor, newNumber: hunk.newCursor,
                                       maxLines: maxLinesPerFile)
                    hunk.oldCursor += 1
                    hunk.newCursor += 1
                    remainingOld -= 1
                    remainingNew -= 1
                case "-":
                    builder.appendLine(kind: .removed, text: body, hunk: hunk,
                                       oldNumber: hunk.oldCursor, newNumber: nil,
                                       maxLines: maxLinesPerFile)
                    hunk.oldCursor += 1
                    remainingOld -= 1
                case "+":
                    builder.appendLine(kind: .added, text: body, hunk: hunk,
                                       oldNumber: nil, newNumber: hunk.newCursor,
                                       maxLines: maxLinesPerFile)
                    hunk.newCursor += 1
                    remainingNew -= 1
                default:
                    // 真 git 不会产出这种行（正文永远带前缀）。但**计数还没走完**说明我们仍在
                    // 这一段里 ⇒ 整行当上下文收下，**不许**把它当文件头去切段（那样会把后面
                    // 的正文全归到另一个文件上）。
                    builder.appendLine(kind: .context, text: raw, hunk: hunk,
                                       oldNumber: hunk.oldCursor, newNumber: hunk.newCursor,
                                       maxLines: maxLinesPerFile)
                    hunk.oldCursor += 1
                    hunk.newCursor += 1
                    remainingOld -= 1
                    remainingNew -= 1
                }
                if remainingOld <= 0 && remainingNew <= 0 { builder.current = nil }
                continue
            }

            // 文件头 / 分段头 / 元数据。
            if raw.hasPrefix("diff --git ") {
                closeFile()
                let builder = FileBuilder()
                let rest = String(raw.dropFirst("diff -- ".count))
                if let split = rest.range(of: " b/") {
                    builder.oldPath = stripPrefix(String(rest[rest.startIndex..<split.lowerBound]))
                    builder.newPath = stripPrefix(String(rest[split.upperBound...]))
                }
                file = builder
                continue
            }
            guard let builder = file else { continue }

            // 真实 git 里这条标记常常出现在**一段的最后一行之后**（那一刻计数已经走完、
            // `current` 已被清掉），所以它必须挂在「这个文件最后存下来的那行」上，
            // 而不是挂 `current` 上 —— 否则末尾无换行这件事永远标不上。
            if raw.hasPrefix("\\") {
                builder.markLastStoredLineNoNewline()
                continue
            }

            if raw.hasPrefix("--- ") {
                let path = stripPrefix(String(raw.dropFirst(4)))
                builder.oldPath = path
                if path.isEmpty { builder.isNew = true }
            } else if raw.hasPrefix("+++ ") {
                let path = stripPrefix(String(raw.dropFirst(4)))
                builder.newPath = path
                if path.isEmpty { builder.isDeleted = true }
            } else if raw.hasPrefix("new file mode") {
                builder.isNew = true
            } else if raw.hasPrefix("deleted file mode") {
                builder.isDeleted = true
            } else if raw.hasPrefix("rename from ") {
                builder.oldPath = GitWorktreeStatus.unquote(String(raw.dropFirst("rename from ".count)))
            } else if raw.hasPrefix("rename to ") {
                builder.newPath = GitWorktreeStatus.unquote(String(raw.dropFirst("rename to ".count)))
            } else if raw.hasPrefix("Binary files ") || raw.hasPrefix("GIT binary patch") {
                builder.isBinary = true
            } else if raw.hasPrefix("@@") {
                if let hunk = HunkBuilder(line: raw) {
                    builder.open(hunk)
                    remainingOld = hunk.oldCount
                    remainingNew = hunk.newCount
                }
            }
            // 其余（`index …` / `similarity index` / `old mode` / `\ No newline…`）忽略。
        }
        closeFile()
        return GitDiffDocument(files: files)
    }

    /// `a/x` / `b/x` ⇒ `x`；`/dev/null` ⇒ 空串。
    static func stripPrefix(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        // 非 git 的 diff 会在路径后跟一个制表符再跟时间戳。
        if let tab = text.firstIndex(of: "\t") { text = String(text[text.startIndex..<tab]) }
        text = GitWorktreeStatus.unquote(text)
        if text == "/dev/null" { return "" }
        if text.hasPrefix("a/") || text.hasPrefix("b/") { return String(text.dropFirst(2)) }
        return text
    }
}

// MARK: - 解析期的可变壳

/// 文件级的可变壳（`GitDiffFile` 是不变结构，便于比较与缓存）。
///
/// **分段只存可变壳、`finish()` 时才拍快照**：早先这里是「存快照 + 追加时同步回快照」，
/// 于是「末尾无换行」那种**事后打标**写在快照副本上、下一次追加又被可变壳的旧内容覆盖回去
/// （实测：标记了、下一秒就没了）。一份正文只能有一个住处。
private final class FileBuilder {
    var oldPath = ""
    var newPath = ""
    var isBinary = false
    var isNew = false
    var isDeleted = false
    var hunkBuilders: [HunkBuilder] = []
    var current: HunkBuilder?
    var truncated = false
    private var storedLines = 0

    func open(_ hunk: HunkBuilder) {
        hunkBuilders.append(hunk)
        current = hunk
    }

    /// 把一行放进当前分段（`hunk` 由调用方传进来，免得再去取一次 `current`）。
    func appendLine(kind: GitDiffLine.Kind, text: String, hunk: HunkBuilder,
                    oldNumber: Int?, newNumber: Int?, maxLines: Int) {
        guard storedLines < maxLines else {
            truncated = true
            return
        }
        storedLines += 1
        hunk.lines.append(GitDiffLine(kind: kind, text: text,
                                      oldNumber: oldNumber, newNumber: newNumber))
    }

    /// 把「末尾无换行」标到**最后一条已存下来的行**上。
    ///
    /// 真实 git 里这条标记常常出现在**一段的最后一行之后**（那一刻计数已经走完、`current`
    /// 已被清掉），所以它挂的是「这个文件最后存下来的那行」，而不是 `current` 那一段的行。
    func markLastStoredLineNoNewline() {
        guard let hunk = hunkBuilders.last, var line = hunk.lines.last else { return }
        line.noNewlineAtEnd = true
        hunk.lines[hunk.lines.count - 1] = line
    }

    func finish() -> GitDiffFile {
        GitDiffFile(oldPath: oldPath, newPath: newPath, isBinary: isBinary,
                    isNew: isNew, isDeleted: isDeleted,
                    hunks: hunkBuilders.map { $0.snapshot() }, truncated: truncated)
    }
}

/// 分段级的可变壳。
private final class HunkBuilder {
    var header: String
    var oldStart = 0
    var oldCount = 0
    var newStart = 0
    var newCount = 0
    var section = ""
    var lines: [GitDiffLine] = []
    var oldCursor = 0
    var newCursor = 0

    init?(line: String) {
        // `@@ -12,7 +12,9 @@ func foo()`
        guard line.hasPrefix("@@") else { return nil }
        let body = String(line.dropFirst(2))
        guard let closeRange = body.range(of: " @@") else { return nil }
        let ranges = body[body.startIndex..<closeRange.lowerBound]
            .split(separator: " ").map(String.init)
        guard ranges.count >= 2,
              let old = Self.range(ranges[0]), let new = Self.range(ranges[1]) else { return nil }
        header = line
        oldStart = old.start
        oldCount = old.count
        newStart = new.start
        newCount = new.count
        oldCursor = old.start
        newCursor = new.start
        section = String(body[closeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// `-12,7` ⇒ (12, 7)；`-12` ⇒ (12, 1)。
    private static func range(_ token: String) -> (start: Int, count: Int)? {
        guard token.hasPrefix("-") || token.hasPrefix("+") else { return nil }
        let parts = token.dropFirst().split(separator: ",")
        guard let start = Int(parts[0]) else { return nil }
        let count = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        return (start, count)
    }

    func snapshot() -> GitDiffHunk {
        GitDiffHunk(header: header, oldStart: oldStart, oldCount: oldCount,
                    newStart: newStart, newCount: newCount, section: section, lines: lines)
    }
}
