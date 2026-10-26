import DoyahCore
import SwiftUI

/// 过程行 → 版式语汇里的**工具条目**（详设 `§5.3.8.1` ②）。
///
/// ## 这不是第二套解析
/// 解析的对象是**本进程自己写出来的那一行文本**：格式由 `Core/AgentChat.swift` 三处定死 ——
/// `appendProgressLine`（`▸ <名> · <摘要>`）、`closeProgressLine`（尾部追加 `"  " + <标记>`）、
/// `durationSuffix`（` · 0.5s`）。它的唯一用途是把
/// `▸ read_file · Core/x.swift  ✓ · 0.5s` 摆成 `├─ ⏺ read_file("Core/x.swift") (0.5s)`。
///
/// **与 Markdown 无关**：正文的块级 / 行内解析仍只走 `MarkdownDocument` 那一处
/// （`AgentMarkdownBody`），这里一个 Markdown 标记都不认。
///
/// **认不出就 `nil`**：界面把原行原样画出来（宁可见旧格式，也不猜、不吞字）。
struct AgentToolLine: Equatable {

    enum Outcome: Equatable {
        /// 发起但还没收尾（没有标记）。
        case running
        case success
        /// 被拒 / 失败（`reason` = 机器码，界面按需翻）。
        case failure(String)
    }

    var name: String
    /// 参数摘要（Core 写的 `summary`，可能是路径 / 命令 / 语句）。
    var summary: String
    /// 耗时原文（`0.5s`）；`nil` = 没真跑（**不编一个 0.0s**）。
    var elapsed: String?
    var outcome: Outcome
}

enum AgentToolLines {

    /// `Core/AgentChat.swift` 的 `progressBullet`。
    static let bullet = "▸ "
    /// 名字与摘要之间的分隔（Core 的 `" · "`）。
    static let nameSeparator = " · "
    /// 收尾标记与正文之间的分隔（Core 的 `closeProgressLine` 用**两个空格**）。
    static let markGap = "  "
    /// 参数摘要的截断长度（§5.3.8.1 ②：超 60 字截断加 `…`）。
    static let maxSummaryLength = 60
    /// 耗时前面的分隔（Core 的 `durationSuffix`）。
    static let elapsedSeparator = " · "

    /// 一整块过程文本 → 条目数组（认不出的行**丢掉**，由界面按原文兜底画）。
    static func rows(_ text: String) -> [AgentToolLine] {
        text.components(separatedBy: "\n").compactMap(parse)
    }

    /// 一行 → 条目；格式不符（不是本进程写的那种行）⇒ `nil`。
    static func parse(_ raw: String) -> AgentToolLine? {
        guard raw.hasPrefix(bullet) else { return nil }
        var head = String(raw.dropFirst(bullet.count))
        var outcome = AgentToolLine.Outcome.running
        var elapsed: String?

        // 尾部标记：`  ✓[ · 0.5s]` / `  ✗ <原因>[ · 0.5s]`。
        // 从**最后一个**两个空格处切：摘要里可能出现两个空格，标记那一段一定以 ✓ / ✗ 开头。
        if let gap = head.range(of: markGap, options: .backwards) {
            let tail = String(head[gap.upperBound...])
            if tail.hasPrefix("✓") || tail.hasPrefix("✗") {
                head = String(head[..<gap.lowerBound])
                var rest = String(tail.dropFirst())
                // 先摘耗时（` · 0.5s` 在最后），剩下的才是拒因 —— 顺序反了会把 ` · ` 一起吃掉。
                if let split = rest.range(of: elapsedSeparator, options: .backwards) {
                    let candidate = String(rest[split.upperBound...])
                    if isElapsed(candidate) {
                        elapsed = candidate
                        rest = String(rest[..<split.lowerBound])
                    }
                }
                // 标记与拒因之间的那一个空格不算内容。
                rest = String(rest.drop(while: { $0 == " " }))
                outcome = tail.hasPrefix("✓") ? .success : .failure(rest)
            }
        }
        return AgentToolLine(name: name(from: head), summary: summary(from: head),
                             elapsed: elapsed, outcome: outcome)
    }

    private static func isElapsed(_ text: String) -> Bool {
        text.hasSuffix("s") && text.dropLast().allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func name(from head: String) -> String {
        guard let range = head.range(of: nameSeparator) else { return head }
        return String(head[..<range.lowerBound])
    }

    private static func summary(from head: String) -> String {
        guard let range = head.range(of: nameSeparator) else { return "" }
        return String(head[range.upperBound...])
    }

    /// 参数摘要的显示形态：超长截断加 `…`（§5.3.8.1 ②）。
    static func displaySummary(_ summary: String) -> String {
        summary.count <= maxSummaryLength ? summary : String(summary.prefix(maxSummaryLength)) + "…"
    }

    /// 条目那一行的正文段：`<名>("<参数摘要>") (<耗时>)`（不含行首栏字形）。
    ///
    /// 耗时**必须写**（对照图里每条都带 `(0.5s)`）；没真跑过就没有这一格，也不编一个
    /// `0.0s` —— 编出来的耗时会在复盘时把人带偏。
    static func callText(_ line: AgentToolLine) -> String {
        let args = displaySummary(line.summary)
        let call = args.isEmpty ? line.name + "()" : line.name + "(\"" + args + "\")"
        guard let elapsed = line.elapsed else { return call }
        return call + " (" + elapsed + ")"
    }
}

/// 状态行里的进度条（§5.3.8.1 ④：`[████░░] 42%`）。
///
/// 纯函数，格子数固定：终端里的方括号进度条就是这个样子，宽度不能随窗口伸缩
/// （一伸缩就会在状态行里跳）。
enum AgentChatProgressBar {

    /// 总格数（对照图里是 6 格）。
    static let cells = 6

    /// `[████░░]`（**不含百分比**）。
    static func bar(percent: Int) -> String {
        let clamped = max(0, min(100, percent))
        // 四舍五入到格：半格以上算一格（不然 99% 会显示成 5 格，看着像没跑满）。
        let filled = min(cells, Int((Double(clamped) / 100.0 * Double(cells)).rounded()))
        return "[" + String(repeating: "█", count: filled)
            + String(repeating: "░", count: cells - filled) + "]"
    }
}

/// 底部状态行的**字段顺序**（§5.3.8.1 ④，顺序写死在这一处）。
///
/// 只收「有读数就出、没读数整段不出」的输入：传 `nil` 的字段连分隔符都不留
/// （不写 `0`、不写 `n/a`）。
struct AgentChatStatusInput {
    var isRunning: Bool
    /// 状态指示字形（`FR-AGT-UX-CONV-012` 的「状态指示字形」开关）：
    /// 就绪 / 运行中两态由它画在状态词前面；空串 = 这一态不给字形（不硬凑一个）。
    var stateGlyph: String = ""
    /// 跑着时的已跑时长（秒，已格式化成 `1.2s`）；`nil` = 没读数。
    var elapsed: String?
    var model: String?
    /// 上下文已用 / 窗口（两格都有才出）。
    var contextUsed: Int?
    var contextWindow: Int?
    var contextPercent: Double?
    var cachePercent: Double?
    var tokensPerSecond: Double?
}

enum AgentChatStatusLine {

    /// 组装状态行的字段序列（**顺序 = 契约顺序**，界面只加 `|` 分隔）。
    ///
    /// 额外读数（压缩 / 续跑 / 完成判据 / 长跑监控）**跟在固定七格之后**：
    /// 它们是别的条款要求「不许静默」的读数，不能因为版式重排就消失；
    /// 跟在后面也不打乱固定七格的相对顺序。
    static func fields(_ input: AgentChatStatusInput, extras: [String]) -> [String] {
        var fields: [String] = []
        let prefix = input.stateGlyph.isEmpty ? "" : input.stateGlyph + " "
        if input.isRunning {
            fields.append(prefix + L(.agentStatusComputing) + (input.elapsed.map { " " + $0 } ?? ""))
        } else {
            fields.append(prefix + L(.agentStatusReady))
        }
        if let model = input.model, !model.isEmpty { fields.append(model) }
        if let used = input.contextUsed, let window = input.contextWindow {
            fields.append(AgentTokenShort.text(used) + "/" + AgentTokenShort.text(window))
        } else if let used = input.contextUsed {
            fields.append(L(.agentStatusContextWindowUnknown, AgentTokenShort.text(used)))
        }
        if let percent = input.contextPercent {
            fields.append(AgentChatProgressBar.bar(percent: Int(percent.rounded()))
                          + " " + AgentModelReadings.percentText(percent))
        }
        if let cache = input.cachePercent {
            fields.append("⊙ " + AgentModelReadings.percentText(cache))
        }
        if let rate = input.tokensPerSecond {
            fields.append("↑ " + String(format: "%.0f", rate) + " t/s")
        }
        // `voice off`：本端没有语音输入，这一格如实写「关」（不是灰掉、也不是省略 ——
        // 省略会让人以为这一格不存在）。
        fields.append(L(.agentStatusVoiceOff))
        fields.append(contentsOf: extras.filter { !$0.isEmpty })
        return fields
    }
}
