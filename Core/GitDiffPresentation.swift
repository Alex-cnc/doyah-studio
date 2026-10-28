import Foundation

/// 差异里真正画到屏幕上的一行。
public enum GitDiffRow: Equatable, Sendable {
    /// 分段头（`@@ -12,7 +12,9 @@ …`）。
    case hunkHeader(String)
    /// 正文一行。
    case line(GitDiffLine)
    /// 被折起来的一段未变行（点一下展开）。
    case fold(GitDiffFold)
    /// 按需渲染：这一页之后还有 `hidden` 行没生成。
    case more(hidden: Int)
}

/// 一段可以折起来的上下文。
public struct GitDiffFold: Equatable, Sendable {

    /// 折叠锚。**按内容记，不按序号**：`首行号 + 条数`。
    /// 同一份差异重取两次锚逐字相同（折起来的还是那一段）；这一段的长短变了锚就变
    /// （那时「折着的还是那一段」已经不成立了，宁可让它展开）。
    public var id: String
    public var firstOldNumber: Int?
    public var firstNewNumber: Int?
    /// 被折起来（没画出来）的行数。
    public var hiddenCount: Int

    public init(id: String, firstOldNumber: Int?, firstNewNumber: Int?, hiddenCount: Int) {
        self.id = id
        self.firstOldNumber = firstOldNumber
        self.firstNewNumber = firstNewNumber
        self.hiddenCount = hiddenCount
    }
}

/// 呈现的两个旋钮（谁在折 / 一页多少行）。
public struct GitDiffDisplayOptions: Equatable, Sendable {

    /// 折叠时**每端**留几行（0 = 整段折掉）。
    public var keepContext: Int
    /// 一次最多生成多少行；余下折成一行「还有 N 行」（点一次多一页）。
    public var pageLimit: Int
    /// 已经点开的那些折（存的是锚 `GitDiffFold.id`）。
    public var expandedFolds: Set<String>

    public init(keepContext: Int = 3,
                pageLimit: Int = GitDiffPresentation.defaultPageLimit,
                expandedFolds: Set<String> = []) {
        self.keepContext = max(0, keepContext)
        self.pageLimit = max(1, pageLimit)
        self.expandedFolds = expandedFolds
    }
}

/// 一个文件画出来的样子。
public struct GitDiffFilePresentation: Equatable, Sendable {
    public var rows: [GitDiffRow]
    /// 因按需渲染还没生成的行数（0 = 全都在这儿了）。
    public var hiddenRows: Int
    /// 折叠之后、按需渲染之前的总行数（界面上「还有 N 行」用它推）。
    public var totalRows: Int
    /// 折起来几段 / 一共折了几行。
    public var foldCount: Int
    public var foldedLineCount: Int
}

/// `FR-STD-WS-VCS-002` 的**呈现面**：一份解析好的差异 ⇒ 真的画到屏幕上的那些行。
///
/// 三件事都在这里做（纯函数，判据能机械跑）：
///   ① **可折叠的上下文**：一段连续未改的行，超过「两端各留 `keepContext`」的部分折成一行
///      （「⋯ N 行未变」）。**改动的行永远不折** —— 把 `+` / `-` 折起来等于把差异本身藏起来；
///   ② **按需渲染**（万行级）：一页只生成 `pageLimit` 行，余下折成一行「还有 N 行」。
///      慢的是视图里的行数，不是解析 —— 一次塞一万个 `Text` 会让整块面板卡住，
///      而用户通常只看最前面那几十行；
///   ③ **折叠与分页互不吞并**：`foldCount` / `hiddenRows` 各自记账，界面上能分别说清
///      「有几段被折起来了」与「还有多少行没生成」—— 两个数说的不是一件事。
///
/// 为什么不在视图里按需算：视图会在每次 body 求值时重算，而折叠状态与分页状态都在模型里
/// （视图树重建会丢 `@State`，本仓在侧栏折叠状态上栽过一次）；把「算什么」放 Core，
/// 视图只负责画。
public enum GitDiffPresentation {

    /// 一页多少行。
    public static let defaultPageLimit = 400
    /// 少于这么多行不值得单占一行「⋯ N 行未变」（折起来反而更长）。
    static let minimumFoldLines = 2

    public static func make(for file: GitDiffFile,
                            options: GitDiffDisplayOptions = GitDiffDisplayOptions())
        -> GitDiffFilePresentation {

        var rows: [GitDiffRow] = []
        var foldCount = 0
        var foldedLineCount = 0

        for hunk in file.hunks {
            guard !hunk.lines.isEmpty else { continue }
            rows.append(.hunkHeader(hunk.header))
            var index = 0
            while index < hunk.lines.count {
                let line = hunk.lines[index]
                guard line.kind == .context else {
                    rows.append(.line(line))
                    index += 1
                    continue
                }
                // 一段连续的上下文。
                var end = index
                while end < hunk.lines.count, hunk.lines[end].kind == .context { end += 1 }
                let run = Array(hunk.lines[index..<end])
                let keep = min(options.keepContext, run.count / 2)
                let hidden = run.count - keep * 2
                let foldable = hidden >= minimumFoldLines
                let fold = foldable ? fold(for: run, keep: keep) : nil

                if let fold, !options.expandedFolds.contains(fold.id) {
                    rows.append(contentsOf: run.prefix(keep).map { GitDiffRow.line($0) })
                    rows.append(.fold(fold))
                    rows.append(contentsOf: run.suffix(keep).map { GitDiffRow.line($0) })
                    foldCount += 1
                    foldedLineCount += fold.hiddenCount
                } else {
                    rows.append(contentsOf: run.map { GitDiffRow.line($0) })
                }
                index = end
            }
        }

        let total = rows.count
        let limit = max(1, options.pageLimit)
        if total > limit {
            let visible = Array(rows.prefix(limit)) + [.more(hidden: total - limit)]
            return GitDiffFilePresentation(rows: visible, hiddenRows: total - limit, totalRows: total,
                                           foldCount: foldCount, foldedLineCount: foldedLineCount)
        }
        return GitDiffFilePresentation(rows: rows, hiddenRows: 0, totalRows: total,
                                       foldCount: foldCount, foldedLineCount: foldedLineCount)
    }

    /// 折起来那段的锚：首行号 + 条数（见 `GitDiffFold.id`）。
    static func fold(for run: [GitDiffLine], keep: Int) -> GitDiffFold {
        let hiddenLines = Array(run.dropFirst(keep).dropLast(keep))
        let first = hiddenLines.first
        let old = first?.oldNumber.map(String.init) ?? "-"
        let new = first?.newNumber.map(String.init) ?? "-"
        return GitDiffFold(id: "\(old)|\(new)|\(hiddenLines.count)",
                           firstOldNumber: first?.oldNumber,
                           firstNewNumber: first?.newNumber,
                           hiddenCount: hiddenLines.count)
    }
}
