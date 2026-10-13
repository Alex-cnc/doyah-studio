import Foundation

/// 本机存储里**日期怎么落盘** —— 只有这一处口径。
///
/// **为什么不是 `.iso8601` / `.secondsSince1970`**：两条路都**丢了低位**（实测抓过两次：
/// `Date()` 建的头一行存了再读**不再相等**，「重启后读回同一条」那条判据当场判红）。
///
/// 真因不是 JSON 数字格式化，而是 **`Date` 内部以 2001 基准存**：`timeIntervalSince1970`
/// 要走一次「加 978307200 再减回来」，这一下就丢了低位。所以落盘存 **`timeIntervalSinceReferenceDate`**
/// （Date 的原生基准，**不平移**）的最短可往返字符串 —— 解析回来**逐位一致**。
///
/// 解析不出来 ⇒ 当作坏行抛（与「坏行跳过并计数」同一条纪律）。
/// **注意分工**：这是**盘上存储**的表示；给人读的**导出**仍走 ISO8601（见 `AgentSessionStore.export`），
/// 回放顺序不靠导出的字符串精度，靠排序后的数组次序 + 同一时刻保持写入序。
enum AgentStoredDate {

    static var encoding: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(String(date.timeIntervalSinceReferenceDate))
        }
    }

    static var decoding: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let seconds = Double(text), seconds.isFinite else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "stored timestamp is not a finite number")
                )
            }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
    }
}
