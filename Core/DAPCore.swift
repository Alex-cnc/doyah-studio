import Foundation

/// 调试器接入的**协议层与口径层**（`FR-STD-WS-TOOL-003`）。
///
/// 需求一句：**经 DAP 接既有调试器，支持断点、单步、变量查看，不自研调试协议。**
/// 判据三条（这三条都不是「能不能调试」，而是**出错时说真话**）：
///
/// ① 断点被外部挪动时，说清「原位置已不存在」；
/// ② 调试期改文件，提示「代码与运行体不一致」；
/// ③ 调试器不可用**不影响普通编辑**。
///
/// 所以本文件先落三块「不依赖真实调试器」的口径：
/// 分帧（DAP 只有 `Content-Length` 头这一种形制）、断点复验、可用性与一致性判断。
/// 真正的 stdio 传输与 UI 接线在下一片；先让判据能被机械核，再接进程。

// MARK: - 分帧

/// DAP 的线上形制：`Content-Length: <n>\r\n\r\n<n 个字节的 JSON>`。
///
/// 只在**字节**层切，不解析 JSON —— 解析归调用方（`JSONDecoder` 对 DAP 的 `seq`/`command`
/// 各有各的模型，混在分帧里迟早把「半包」当成「格式错误」）。
public enum DAPFrame {

    /// 把一条消息体包成线上字节。
    public static func encode(body: Data) -> Data {
        var out = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        out.append(body)
        return out
    }

    /// 从缓冲区**尽量**切出完整消息体；切不完整就把剩余留在 buffer 里等下一批字节。
    ///
    /// 半包是常态（stdio 一次 read 可能只有半个头、或头齐了体还没齐），
    /// 因此这里不做「解不出来就抛错」，只做「还没齐就返回空」——
    /// 把半包当错误处理，会在慢一点的调试器上把整场调试判死。
    public static func decode(_ buffer: inout Data) -> [Data] {
        var bodies: [Data] = []
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])  // \r\n\r\n
        while true {
            guard let headerEnd = buffer.range(of: separator) else { return bodies }
            let headerBytes = buffer[buffer.startIndex..<headerEnd.lowerBound]
            guard let header = String(data: headerBytes, encoding: .utf8),
                  let length = contentLength(in: header) else {
                // 头都读不懂（没有 Content-Length）⇒ 这段字节没法再对齐，
                // 丢掉到第一个分隔符为止，免得死循环。
                buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)
                continue
            }
            let bodyStart = headerEnd.upperBound
            let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
            guard available >= length else { return bodies }  // 体还没齐，等下一批
            let bodyEnd = buffer.index(bodyStart, offsetBy: length)
            bodies.append(Data(buffer[bodyStart..<bodyEnd]))
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        }
    }

    /// 头里取 `Content-Length`；大小写不敏感（规范写 `Content-Length`，实测有实现给小写）。
    static func contentLength(in header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
            else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

// MARK: - 断点

/// 一条断点。`line` 是**1 起**的行号（编辑器里看到的就是这个数，别再换口径）。
public struct DebugBreakpoint: Equatable, Sendable {
    /// 用户下断点时那一行的行号。
    public let line: Int
    /// 下断点时那一行的原文（去掉首尾空白）—— 复验时靠它认「人还在不在原处」。
    public let anchor: String
    /// 是否已被调试器确认可停（`setBreakpoints` 回来的 `verified`）。
    public var verified: Bool

    public init(line: Int, anchor: String, verified: Bool = false) {
        self.line = line
        self.anchor = anchor
        self.verified = verified
    }
}

/// 文件被外部改动之后，一条断点的去向。
public enum BreakpointRecheck: Equatable, Sendable {
    /// 原位还在（行号与内容都没变）。
    case unchanged(DebugBreakpoint)
    /// 内容被挪到了别的行 —— **必须说清「原位置已不存在」**，不能悄悄跟着走。
    case moved(to: Int, message: String)
    /// 找不到（内容没了，或出现多处无法判断该跟哪一处）。
    case removed(message: String)
}

public enum DebugBreakpoints {

    /// 判据 ①：断点被外部挪动 / 删掉时，给人一句能读懂的话。
    ///
    /// 规则：先看**原行内容**是否还在原行；不在就在全文里找唯一一处相同内容 ⇒ 移到那儿；
    /// 找不到或多处命中 ⇒ 移除（多处命中**不许猜**，猜错会停在意想不到的地方）。
    public static func recheck(_ breakpoint: DebugBreakpoint, against newText: String) -> BreakpointRecheck {
        let lines = newText.components(separatedBy: .newlines)
        let anchor = breakpoint.anchor

        if breakpoint.line >= 1, breakpoint.line <= lines.count,
           lines[breakpoint.line - 1].trimmingCharacters(in: .whitespaces) == anchor {
            return .unchanged(breakpoint)
        }

        let hits = lines.enumerated()
            .filter { $0.element.trimmingCharacters(in: .whitespaces) == anchor && !anchor.isEmpty }
            .map { $0.offset + 1 }

        if hits.count == 1, let only = hits.first {
            return .moved(
                to: only,
                message: "断点原位置已不存在（第 \(breakpoint.line) 行的内容变了），已移到第 \(only) 行"
            )
        }
        if hits.count > 1 {
            return .removed(
                message: "断点原位置已不存在，且这段内容出现在 \(hits.count) 处，无法判断该跟哪一处 ⇒ 断点已移除"
            )
        }
        return .removed(message: "断点原位置已不存在（第 \(breakpoint.line) 行的内容找不到了）⇒ 断点已移除")
    }
}

// MARK: - 可调试状态与「不挡编辑」

/// 调试器拿不到的原因（每一种都要能说成一句人话，不许把协议错误码丢给用户）。
public enum DebugUnavailableReason: Equatable, Sendable {
    /// 本机没装这个语言的调试适配器。
    case adapterNotFound(name: String)
    /// 适配器起来了但立刻退出（常见：路径写错、缺运行时）。
    case adapterExited(code: Int32)
    /// 握手超时（适配器起来但不说 DAP）。
    case handshakeTimeout(seconds: Int)
    /// 用户主动停掉。
    case stoppedByUser

    /// 一句话（判据 ③ 的一部分：不可用时**说清为什么**，而不是让按钮灰着不解释）。
    public var sentence: String {
        switch self {
        case .adapterNotFound(let name):
            return "没找到 \(name) 的调试适配器，调试入口先关着；装好之后重开工作区即可"
        case .adapterExited(let code):
            return "调试适配器启动后立刻退出（退出码 \(code)），调试入口先关着；编辑不受影响"
        case .handshakeTimeout(let seconds):
            return "调试适配器 \(seconds) 秒内没有按 DAP 应答，调试入口先关着；编辑不受影响"
        case .stoppedByUser:
            return "调试已停止"
        }
    }
}

/// 调试面板该显示什么、编辑器还能不能改。
public struct DebugAvailability: Equatable, Sendable {
    /// 调试入口是否可点。
    public let canStart: Bool
    /// 给用户看的一句话（不可用时 = 为什么）。
    public let sentence: String

    /// 判据 ③：**无论调试器是什么状态，普通编辑一律可用**。
    /// 这条不做成「配置项」—— 调试接不上就把编辑器锁住，是这一族最容易犯的错。
    public var canEdit: Bool { true }

    public static func whenUnavailable(_ reason: DebugUnavailableReason) -> DebugAvailability {
        DebugAvailability(canStart: false, sentence: reason.sentence)
    }

    public static let ready = DebugAvailability(canStart: true, sentence: "调试器已就绪")
}

// MARK: - 调试期改了文件

/// 调试会话状态（只留判断「代码与运行体是否一致」需要的三档）。
public enum DebugSessionState: Equatable, Sendable {
    /// 没在跑。
    case idle
    /// 适配器已启动、程序在跑（`launch` / `attach` 之后、`terminated` 之前）。
    case running
    /// 已结束（正常结束 / 被停 / 崩溃）。
    case terminated(reason: String)

    public var isRunning: Bool { self == .running }
}

/// 判据 ②：调试期改文件 ⇒ 提示「代码与运行体不一致」。
public enum DebugConsistency {

    /// 返回要显示的提示；`nil` = 不用提示（没在调试，或文件没动）。
    ///
    /// 只在**运行中**提示：没在调试时改文件是日常，弹这句话等于噪音。
    /// 提示语里带上**改了哪几个文件**，人才知道停下来的到底是哪份代码。
    public static func warning(
        state: DebugSessionState,
        changedFiles: [String]
    ) -> String? {
        guard state.isRunning, !changedFiles.isEmpty else { return nil }
        let names = changedFiles.prefix(3).joined(separator: "、")
        let more = changedFiles.count > 3 ? " 等 \(changedFiles.count) 个文件" : ""
        return "调试进行中改了 \(names)\(more)：代码与运行体不一致，断点位置与变量可能对不上当前文件 —— "
            + "要按新代码调试请先停止再重新启动"
    }
}
