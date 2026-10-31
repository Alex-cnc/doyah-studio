import Foundation

/// Agent 那条 shell 的**回收协议**（纯函数，可单测）。
///
/// ## 为什么单独抽出来
///
/// 这段协议过去写在 `App/AgentShellSession.swift` 里，App 目标进不了单测 ⇒ 每次改协议只能靠
/// 「打包 → 手点 → 看日志」，一轮几分钟。协议本身（怎么拼脚本、怎么认哨兵、怎么剔回显）
/// 全是纯字符串逻辑，抽到 Core 就能拿单测钉死，App 只负责「把字节写进 PTY、把输出喂回来」。
///
/// ## 协议长什么样
///
/// ```
/// ESC[200~                     ← 括号粘贴开始（zle 把中间内容当「粘贴」处理，不逐字解释）
///   <用户那条命令>
///   __doyah_ec=$?
///   printf '__DOYAH_AGENT_DONE_xxx:%d\n' $__doyah_ec
/// ESC[201~                     ← 括号粘贴结束
/// \r                           ← 粘贴外的一次回车：真正提交
/// ```
///
/// **为什么必须括号粘贴**：2026-10-31 实测，把多行脚本原样丢给交互式 zsh 时，PTY 会把它
/// 分块送进 zle；某一块的引号还没送到，shell 就进了 `quote>` 续行态，后面的命令**全被当成
/// 字符串吞掉** —— 表现是「第一条 pwd 成功、第二条 pwd 卡满 60 秒」。包进粘贴标记之后
/// 连续四条命令（含管道）全部一次到底，日志里再没出现过 `quote>`。
///
/// **为什么每次都先发 Ctrl-C**：上一条若是被打断 / 超时 / 留下未闭合的引号，下一次写进去
/// 就会接着上一段的残局。Ctrl-C 在提示符下无害，在续行态里正好把它掐断。
public enum AgentShellProtocol {

    /// 每次写命令前先发的字节：Ctrl-C（掐断上一段的残局）+ Ctrl-U（清掉行缓冲）。
    public static let reset = "\u{03}\u{15}"

    /// 粘贴开始 / 结束标记（xterm 括号粘贴）。
    static let pasteBegin = "\u{1B}[200~"
    static let pasteEnd = "\u{1B}[201~"

    /// 拼一段可提交的脚本。
    ///
    /// - 三行各以 `\n` 分隔（粘贴内部按行切；**不要**用 `\r`，粘贴里的 CR 会被 zle 当控制字符）。
    /// - 格式串用**单引号**包住、退出码变量不加引号：少一层引号就少一处「引号没闭合进 quote>」的机会。
    /// - 结尾的 `\r` 在粘贴标记**外面**：那才是真正的那次回车。
    public static func script(command: String, sentinel: String) -> String {
        let body = command
            + "\n__doyah_ec=$?\n"
            + "printf '\(sentinel):%d\\n' $__doyah_ec\n"
        return pasteBegin + body + pasteEnd + "\r"
    }

    /// 从缓冲里认「这一条跑完了」。
    ///
    /// 只认 `<哨兵>:` 后面**紧跟纯数字** —— 回显里出现的那行是 `printf '…:%d\n'`，
    /// 冒号后面是 `%`，自然过不了这一关（2026-10-31：没这层判断时，第一条命令被自己写进去的
    /// 那行判成「已完成」，退出码解析成 -1）。
    public static func completion(in buffer: String, sentinel: String) -> (body: String, exitCode: Int32)? {
        let needle = sentinel + ":"
        // **要把所有出现都看一遍，不能只看第一处**：回显里那行 `printf '…:%d\n'` 也含哨兵字面量，
        // 而它排在真正的结果行**前面**；只看第一处就会一直卡在「冒号后面是 %」上
        // （2026-10-31 现场：缓冲里明明有 `…CAF0:0`，程序却说「未命中」，卡满 60 秒）。
        var searchStart = buffer.startIndex
        while let range = buffer.range(of: needle, range: searchStart..<buffer.endIndex) {
            let after = buffer[range.upperBound...]
            // 按 Unicode 标量扫行，不按 Character：Swift 把 `\r\n` 当成**一个**字素簇，
            // `$0 != "\r"` 对 CRLF 永远为真 —— 一行都切不开。
            var line = ""
            for scalar in after.unicodeScalars {
                if scalar == "\r" || scalar == "\n" { break }
                line.unicodeScalars.append(scalar)
            }
            let digits = line.trimmingCharacters(in: .whitespaces)
            if !digits.isEmpty, digits.allSatisfy({ $0.isNumber }), let code = Int32(digits) {
                return (String(buffer[..<range.lowerBound]), code)
            }
            searchStart = range.upperBound
        }
        return nil
    }

    /// 剔掉回显那一整段（PTY 有回显时，脚本会原样吐回来一遍）。
    public static func stripEcho(_ body: String, echo: String) -> String {
        // 先试整段精确匹配；对不上（PTY 把换行折成 CRLF）就按行剔 —— `echo` 为空时也照剔，
        // 因为「回收脚本那几行」本来就不该进结果（超时路径就传空串）。
        // ⚠️ 行切分前必须把 CRLF 折成 LF：Swift 把 `\r\n` 当一个字素簇，`split(separator: "\n")`
        // 切不开它（同 `completion` 那一处，是同一个坑）。
        let body = body.replacingOccurrences(of: "\r\n", with: "\n")
        if !echo.isEmpty, let range = body.range(of: echo) {
            return String(body[range.upperBound...])
        }
        // 换行被 PTY 重排过：按行剔掉「粘贴内容里的那三行」
        let markers = ["__doyah_ec=$?", "printf '"]
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var kept: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if markers.contains(where: { trimmed.hasPrefix($0) }) { continue }
            kept.append(String(line))
        }
        return kept.joined(separator: "\n")
    }

    /// 把一段原始输出洗成「人能读的正文」：去控制字符 → 去回显 → 去提示符行。
    ///
    /// 为什么一步不够：真机上 PTY 会把写进去的脚本用 zle **逐字重绘**一遍（每个字符之间夹着
    /// `ESC[27m`），整段精确匹配对不上；洗掉控制字符后它变成普通文本，才剔得掉。
    /// 剔剩的提示符行（`alex@Mac studio %`）对模型也是噪声，一并去掉。
    public static func cleanOutput(_ body: String, echo: String = "", command: String = "") -> String {
        var text = stripControl(body)
        text = stripEcho(text, echo: echo)
        var kept: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            // 提示符与回显常常挤在**同一行**（zle 重绘时不换行）：
            // `%      …      alex@Mac studio % python3 hello.py` ⇒ 只留 `%` 之后的那段。
            if let lastPercent = line.range(of: "% ", options: .backwards), line.contains("@") {
                line = String(line[lastPercent.upperBound...])
            }
            if !command.isEmpty, let range = line.range(of: command) {
                line = String(line[range.upperBound...])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: "  ", with: " ")
            if line.isEmpty { continue }
            if line == "__doyah_ec=$?" || line.hasPrefix("printf '") { continue }
            // zle 分块重绘剩下的残片（`p`、`python`）都是命令本身的前缀
            if !command.isEmpty, command.hasPrefix(line) { continue }
            if line.contains("__DOYAH_AGENT_DONE_") { continue }
            if line.count <= 2, line.allSatisfy({ "%$#>❯".contains($0) }) { continue }
            if line.hasSuffix("%") || line.hasSuffix("$"), line.contains("@") { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    /// 去掉 ANSI 转义序列与 `\r`（提示符配色、zle 重绘留下的残迹），留下人能读的正文。
    public static func stripControl(_ text: String) -> String {
        // CRLF 先折成 LF：Swift 的 Character 把 `\r\n` 当一个字素簇，下面按字素删 `\r` 删不掉它。
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
        var out = ""
        var iterator = Array(text)
        var index = 0
        while index < iterator.count {
            let ch = iterator[index]
            if ch == "\u{1B}" {
                index += 1
                if index < iterator.count, iterator[index] == "[" {
                    index += 1
                    while index < iterator.count, !(iterator[index].isLetter || iterator[index] == "m") {
                        index += 1
                    }
                }
                index += 1
                continue
            }
            if ch == "\u{08}" {   // 退格：zle 重绘的残留，直接丢
                index += 1
                continue
            }
            if ch == "\r" { index += 1; continue }
            out.append(ch)
            index += 1
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    }
}
