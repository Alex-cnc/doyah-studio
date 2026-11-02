import Foundation
@testable import DoyahCore

/// 测试用的外发日志：**永远写临时目录**，绝不碰 `.shared`。
///
/// 为什么需要它：`EgressLog.shared` 落在用户的真审计日志里
/// （`~/Library/Application Support/<产品名>/egress-log.jsonl`）。单测会起假 `ssh`、
/// 假 `pg_dump`，若这些测试直接写 `.shared`，用户那份「出网必留痕」的账本里就会混进
/// 一堆**从没发生过的出网** —— 审计日志一旦掺假，「默认零外发」这句话就没法再用来举证了。
/// 所以凡是要驱动真实出网装饰器的用例，一律注入这里的实例。
enum EgressTestSupport {

    static func temporaryLog(_ label: String = "egress") -> EgressLog {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return EgressLog(directoryURL: directory)
    }

    /// 读完就删（用例尾部调用；删不掉也不该让用例红）。
    static func remove(_ log: EgressLog) async {
        let url = await log.fileLocation().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: url)
    }
}
