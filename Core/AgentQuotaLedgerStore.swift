import Foundation

/// 配额账本的**跨重启**那一面（`NFR-ALL-GATE-AI-004` 判据 ③）。
///
/// 需求原文：「跨调用累计，重启后计数不重置」。在此之前账本只活在 `AppState` 的内存里
/// （注释里写着「按需求口径它是单次会话，所以退出应用即清零」）—— 那句话与判据 ③ 直接相反：
/// 关一次应用就等于把「调用次数 / 累计 token」两个上限**清零**，上限只对连续不关机的长跑有效。
///
/// 三条口径与 `AgentDailyUsageLedger`（日配额）一致，不另造一套：
/// ① **一个文件两个键**（次数 / token），与其余本机数据同目录，不新开文件体系；
/// ② **读不出来 ⇒ 按 0 计但如实标 `degraded`**（不让界面把「账本坏了」说成「一次都没用过」）；
/// ③ **写失败不炸主流程**（记账是旁路），但返回值如实说没记上。
public struct AgentQuotaLedgerStore: Sendable {

    /// 一次读盘结论。
    public struct Reading: Equatable, Sendable {
        public var ledger: AgentQuotaLedger
        /// 账本文件存在但读不出 / 解析不了（按 0 计，界面照实说一句）。
        public var degraded: Bool

        public init(ledger: AgentQuotaLedger = .empty, degraded: Bool = false) {
            self.ledger = ledger
            self.degraded = degraded
        }

        public static let fresh = Reading()
    }

    /// 盘上形状：只这两个键（与 `AgentQuotaLedger` 一一对应）。
    private struct Payload: Codable, Equatable {
        var requestCount: Int
        var totalTokens: Int
    }

    /// 文件名（同目录的其余账本都没前缀乱起，这里跟着来）。
    public static let fileName = "agent-quota-ledger.json"

    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(Self.fileName)
    }

    /// 读回账本。文件不在 = 全新的账本（不是降级）。
    public func load() -> Reading {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .fresh }
        guard let data = try? Data(contentsOf: fileURL) else {
            return Reading(degraded: true)
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Reading(degraded: true)
        }
        return Reading(ledger: AgentQuotaLedger(requestCount: max(0, payload.requestCount),
                                                totalTokens: max(0, payload.totalTokens)))
    }

    /// 记账落盘。返回 `true` = 真的写进去了。
    @discardableResult
    public func save(_ ledger: AgentQuotaLedger) -> Bool {
        let payload = Payload(requestCount: max(0, ledger.requestCount),
                              totalTokens: max(0, ledger.totalTokens))
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            try JSONEncoder().encode(payload).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 清零（真删文件 —— 不是写一份 0 进去，免得「删了」与「没写过」两件事在盘上分不开）。
    @discardableResult
    public func reset() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }
}
