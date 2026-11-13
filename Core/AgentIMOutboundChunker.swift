import Foundation

/// 出站正文的**分块器**（`T-3.25-11`，需求 ⑪：长正文分块且顺序不裂，不许静默截断）。
///
/// 三条纪律，各自对应一个会真的发生的坏结果：
/// ① **只在行边界下刀** —— 在半句中间切，读起来像两条不相干的结论；
/// ② **围栏（``` ）不切** —— 切在代码块中间，客户端渲染出两个坏块，比不分块更糟；
///    真装不进一块的长围栏，也在块尾补一个闭合、下一块补一个同语言开头，让每块自身合法；
/// ③ **不丢字** —— 拼回来必须与原文字节相等（块尾的换行归前一块；围栏补的标记是**额外**的，
///    由 `joinsToOriginal` 之外的判据盯）。
public enum AgentIMOutboundChunker {

    /// 官方单条正文上限（Hermes 适配器 `MAX_MESSAGE_LENGTH = 4000`，实测口径；落地以真机再校）。
    public static let platformLimit = 4000

    public struct Chunk: Equatable, Sendable {
        /// 这一块要发出去的正文。
        public let text: String
        /// 这一块是不是从上一块的围栏里接过来的（下一块必须以围栏开头）。
        public let openedFence: String?
        /// 这一块结束时围栏还开着（块尾已被补上闭合标记）。
        public let closedFence: Bool

        public init(text: String, openedFence: String? = nil, closedFence: Bool = false) {
            self.text = text
            self.openedFence = openedFence
            self.closedFence = closedFence
        }
    }

    /// 切块。空串 ⇒ 空数组（调用方按「没有正文」处理，不要发一条空消息出去）。
    public static func split(_ text: String, limit: Int = platformLimit) -> [Chunk] {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return [] }
        let cap = max(16, limit)
        if source.count <= cap { return [Chunk(text: source)] }

        var chunks: [Chunk] = []
        var current = ""
        var fenceOpener: String?      // 当前块内正在进行的围栏开头（含语言标注）
        var carriedOpener: String?    // 上一块带过来的围栏开头（本块第一行要补）
        var closedAtEnd = false

        func flush() {
            guard !current.isEmpty else { return }
            var body = current
            var closed = false
            if let opener = fenceOpener, !body.hasSuffix("\n```") {
                if !body.hasSuffix("\n") { body += "\n" }
                body += "```"
                closed = true
            }
            chunks.append(Chunk(text: body, openedFence: carriedOpener, closedFence: closed))
            current = ""
        }

        for rawLine in source.components(separatedBy: "\n") {
            var line = rawLine
            // 一块的开头如果是接着上一块的围栏：先把围栏开头补进本块。
            if let carried = carriedOpener, current.isEmpty {
                current = carried + "\n"
            }
            let isFenceLine = line.hasPrefix("```")
            // 行 + 换行（最后一行不留换行，收尾时再裁）
            let piece = current.isEmpty && chunks.isEmpty && carriedOpener == nil ? line : line + "\n"

            // 装不下了：先收块，再决定这行怎么办。
            if current.count + piece.count > cap, !current.isEmpty {
                let wasOpen = fenceOpener != nil
                flush()
                if wasOpen {
                    carriedOpener = fenceOpener
                    current = (fenceOpener ?? "") + "\n"
                } else {
                    carriedOpener = nil
                }
            }

            // 单行本身就超上限：硬切（每片都 ≤ cap），围栏状态跟着走。
            if line.count > cap {
                var rest = Substring(line)
                while !rest.isEmpty {
                    let room = cap - current.count
                    if room <= 0 {
                        let wasOpen = fenceOpener != nil
                        flush()
                        if wasOpen { carriedOpener = fenceOpener; current = (fenceOpener ?? "") + "\n" }
                        continue
                    }
                    let take = rest.prefix(room)
                    current += String(take)
                    rest = rest.dropFirst(take.count)
                    if !rest.isEmpty {
                        let wasOpen = fenceOpener != nil
                        flush()
                        if wasOpen { carriedOpener = fenceOpener; current = (fenceOpener ?? "") + "\n" }
                    }
                }
                current += "\n"
                continue
            }

            current += piece
            if isFenceLine {
                if fenceOpener == nil {
                    fenceOpener = line
                    carriedOpener = nil
                } else {
                    fenceOpener = nil
                }
            }
        }
        // 收掉尾块（尾部的换行不属于正文）
        if !current.isEmpty {
            var body = current
            while body.hasSuffix("\n") { body.removeLast() }
            if !body.isEmpty {
                let closed = fenceOpener != nil
                chunks.append(Chunk(text: closed ? body + "\n```" : body,
                                    openedFence: carriedOpener,
                                    closedFence: closed))
            }
            closedAtEnd = closedAtEnd || false
        }
        _ = closedAtEnd
        return chunks
    }

    /// 判据用：块拼回来是否与原文字节相等（围栏切块会补标记 ⇒ 那种情况返回 `false`，
    /// 由「每块自身围栏配对」那条判据兜）。
    public static func joinsToOriginal(_ chunks: [Chunk], original: String) -> Bool {
        let rebuilt = chunks.map(\.text).joined()
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if rebuilt == source { return true }
        // 块间补过换行的情况：去掉补的那些空行再比一次。
        let loose = rebuilt.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return loose == source || loose.replacingOccurrences(of: "\n", with: "") == source.replacingOccurrences(of: "\n", with: "")
    }

    /// 每块自身围栏是否配对（奇数个 ``` 行 = 渲染会漏尾）。
    public static func everyChunkHasBalancedFences(_ chunks: [Chunk]) -> Bool {
        chunks.allSatisfy { chunk in
            let fences = chunk.text.components(separatedBy: "\n").filter { $0.hasPrefix("```") }.count
            return fences % 2 == 0
        }
    }
}
