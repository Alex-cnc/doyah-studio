import Foundation

/// **被拒之后要告诉它怎么办**（`FR-AI-20` ④ / `FR-AI-31` ①）。
///
/// 2026-11-11 真机查到的打转根源（一轮 56 跳、279 条审计）：
/// 拒因回灌给模型的是 `run_command => commandNotAllowed` —— **机器码 + 一个被丢掉的 detail**，
/// 没有一句「改成什么写法才行」。于是模型只能猜，把同一个意图换个拼法再试：
/// 同一轮里 **37 次被拒**（`;` `>` `&` `bash`、`./Scripts/verify-all.sh`），
/// 再加 **8 次 exit 124 超时**，56 跳里大约 45 跳是白烧的。
///
/// 这个文件只做一件事：把「为什么被拒」翻成**下一步能照做的一句**。
/// 纯函数、不读状态；同一条被连拒多次的升级由调用方计数（见 `escalation`）。
public enum AgentRefusalGuidance {

    /// 给模型看的改法（中文：模型的思考语言与判据行都是中文，别在这里切英文）。
    ///
    /// - Parameters:
    ///   - detail: 策略给出的细节码，形如 `control-character:;`、`executable-is-a-path:./x.sh`、
    ///     `too-many-arguments:40`，或直接是**不在白名单的可执行名**。
    ///   - allowed: 白名单里的可执行名（拼进提示，别让它继续瞎猜）。
    public static func message(detail: String, allowed: [String] = []) -> String {
        if let character = suffix(of: detail, after: "control-character:") {
            return message(forControlCharacter: character)
        }
        if let executable = suffix(of: detail, after: "executable-is-a-path:") {
            return "可执行名不能带路径（`\(executable)` 被拒）：用裸名字，脚本改走解释器，"
                + "例如 `python3 Scripts/xxx.py`、`node scripts/xxx.js`、`make target`。"
        }
        if let count = suffix(of: detail, after: "too-many-arguments:") {
            return "参数太多了（\(count) 个）：拆成几次调用，或把筛选交给 `grep` / `find` 自己的参数。"
        }
        if detail.hasPrefix("control-character") {
            return message(forControlCharacter: "")
        }
        if !detail.isEmpty {
            // 剩下的最常见形态：detail 就是那个不在白名单里的可执行名。
            let hint = allowed.isEmpty ? "" : "白名单里能用的只有：\(allowed.joined(separator: " / "))。"
            return "`\(detail)` 不在命令白名单里。\(hint)"
                + " 如果只是想读文件、找内容、看目录，用 read_file / search_files / list_dir 更直接。"
        }
        return "这条命令被策略拒绝了：换一种只读写法，或改用文件类工具。"
    }

    /// 控制字符各自的改法（**逐字符给不同出路**，别一句「不许用特殊字符」了事）。
    public static func message(forControlCharacter character: String) -> String {
        switch character {
        case ";", "&":
            return "一次只跑**一条**命令，不许用 `\(character)` 串起来：拆成多次工具调用（每次一条）。"
        case ">", ">>":
            return "不许用重定向 `\(character)`：要写文件用 `write_file` 工具，不要借 shell 落盘。"
        case "<":
            return "不许用输入重定向 `<`：要读文件用 `read_file` 工具。"
        case "|":
            return "不许用管道 `|`：把筛选交给 `grep` / `find` 自己的参数，或先取回内容再判断。"
        case "$", "`":
            return "不许用变量展开 `\(character)`：把要用的值直接写进命令。"
        case "'", "\"", "\\":
            return "不许用引号/转义 `\(character)`：参数里别带需要转义的字符，改用不带空格的写法。"
        case "\n", "\r":
            return "一次只跑一条命令，不要把多条用换行拼在一起。"
        default:
            return "命令里不许出现 shell 控制字符：去掉它，或拆成多次工具调用。"
        }
    }

    /// 同一条（同工具同写法）**被连拒第 N 次**时追加的警告。
    ///
    /// 为什么要升级：只给改法还不够 —— 观察到的行为是「看完改法又试同一句」。
    /// 第 2 次换一句话提醒，第 3 次起明说「再试这条我就跳过它」，让它去换路子而不是硬磕。
    public static func escalation(streak: Int) -> String? {
        switch streak {
        case 0, 1:
            return nil
        case 2:
            return "注意：这是**第二次**因为同一写法被拒，别再试同一个写法了。"
        default:
            return "第 \(streak) 次因同一写法被拒：这条**不要再试**，换工具或换思路（还不行就如实说做不到）。"
        }
    }

    private static func suffix(of detail: String, after prefix: String) -> String? {
        guard detail.hasPrefix(prefix) else { return nil }
        let rest = String(detail.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
    }
}
