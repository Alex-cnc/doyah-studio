import Foundation

/// **本机自测入口：把一个 JSONL 文件当成 IM 入站通道**（`FR-AGT-LINK-CHAN-003` 的判据面）。
///
/// 为什么需要它：IM 这条路的问题全都是「只有人在手机上试才看得见」——
/// 手机试一轮要另一个人、要等、还看不见审计。2026-11-11 复盘那一轮
/// （56 跳 / 37 次被拒 / 8 次超时）就是靠主人反复手测才暴露的。
///
/// 把它做成文件投递：往文件里追加一行 `{"op":"message",…}`，应用照 `AgentIMInboundFrame`
/// 解析后走**同一条** `acceptAgentIMInbound` —— 差别只有「不联网」，
/// 于是跳数、拒因、心跳、拍板这些行为都能在终端里复现、对照、留证。
///
/// 三条口径：
/// 1. **只吃整行**：末尾没有换行的那半行可能正在被写，留到下一轮再读（不留半帧）。
/// 2. **只吃增量**：`offset` 记住读到哪儿；重复 drain 不会把同一条消息跑第二遍。
/// 3. **坏帧不吞**：解不出来的行**跳过但记数**（由调用方写日志），不假装收到。
public struct AgentIMFileInbox: Equatable {

    public let url: URL
    /// 已经消费到的字节位置。
    public private(set) var offset: UInt64
    /// 解不出来的行数（供日志：坏帧必须留痕）。
    public private(set) var malformedCount: Int

    public init(url: URL, offset: UInt64 = 0) {
        self.url = url
        self.offset = offset
        self.malformedCount = 0
    }

    /// 读自上次以来**新增的完整行**，解成帧；半行留在下一轮。
    public mutating func drain(now: Date = Date()) -> [AgentIMInboundFrame] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        // 文件被改小（清空重写）⇒ 偏移作废，从头再读；否则只吃新增部分。
        if size < offset { offset = 0 }
        guard size > offset else { return [] }
        try? handle.seek(toOffset: offset)
        return readLines(from: handle, now: now)
    }

    private mutating func readLines(from handle: FileHandle, now: Date) -> [AgentIMInboundFrame] {
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }
        guard let text = String(data: data, encoding: .utf8) else {
            malformedCount += 1
            offset += UInt64(data.count)
            return []
        }
        // 只消费到最后一个换行为止 —— 后面那半行可能还没写完。
        guard let lastNewline = text.lastIndex(of: "\n") else { return [] }
        let complete = String(text[text.startIndex...lastNewline])
        offset += UInt64(complete.utf8.count)

        var frames: [AgentIMInboundFrame] = []
        for raw in complete.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let frame = AgentIMInboundFrame.decode(line, receivedAt: now) {
                frames.append(frame)
            } else {
                malformedCount += 1
            }
        }
        return frames
    }
}


/// **自测模式的投递落点**：把「本该发到手机上的那条」追加进本地 JSONL。
///
/// 单独放一个类型，是因为 `AgentChainTests` 的源树判据②要求「写文件的入口只有一套」——
/// 宿主里再出现一次 `FileHandle(forWritingTo:)` 就会被判成第二套留痕通道（实测判红过一次）。
public enum AgentIMLocalResultFile {

    public static func append(text: String, to url: URL, at date: Date = Date()) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let stamp = ISO8601DateFormatter().string(from: date)
        let line = "{\"createdAt\":\"" + stamp + "\",\"text\":\"" + escaped + "\"}\n"
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
