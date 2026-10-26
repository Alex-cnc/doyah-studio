import Foundation

/// 当日 token 用量账（`FR-AGT-OPS-OBS-002` 里「日配额」这一项的**生效面**）。
///
/// 为什么需要它：配置面板里的「日配额」如果只是个数字没人读，那条配置就是装饰 ——
/// 「改完立即生效」这句话要求有一个**真在看的消费者**。本类型就是那个消费者：
/// 每轮跑完记账、开跑前判定，配额用尽 ⇒ 如实拦住（并说清「要接着干就得先改上限」）。
///
/// 四条口径：
/// ① **按本地日切**（`Calendar.current` 的 `yyyy-MM-dd`）—— 跨日自动归零，不需要谁来清；
/// ② **只记不猜**：账本里只有「今天用了多少」，没有按会话 / 按任务的明细（那是审计面的事）；
/// ③ **账本读不出来 ⇒ 按 0 计但如实标 `degraded`**（不让界面把「读不出来」说成「今天没用过」）；
/// ④ **写失败不影响主流程**（记账是旁路，跑一轮不能因为账本写不进去就失败），但读数如实降级。
public struct AgentDailyUsageLedger: Sendable {

    public struct Reading: Equatable, Sendable {
        /// `yyyy-MM-dd`（本地日）。
        public var day: String
        public var tokens: Int
        /// 账本文件存在但读不出来（按 0 计，界面照实说一句）。
        public var degraded: Bool

        public init(day: String, tokens: Int, degraded: Bool = false) {
            self.day = day
            self.tokens = tokens
            self.degraded = degraded
        }
    }

    public enum Verdict: Equatable, Sendable {
        /// 还能跑，剩这么多。
        case allowed(remaining: Int)
        /// 今天的额度已经用完（`used >= quota`）。
        case exhausted(used: Int, quota: Int)

        public var isExhausted: Bool {
            if case .exhausted = self { return true }
            return false
        }
    }

    /// 盘上形状（只这两个键：一个日号、一个累计数）。
    private struct Payload: Codable, Equatable {
        var day: String
        var tokens: Int
    }

    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("agent-daily-tokens.json")
    }

    /// 本地日号（判据要能确定性对拍 ⇒ 日历与格式化器都可注入）。
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// 今天用了多少（跨日读回 0，而不是把昨天的数继续算）。
    public func reading(at date: Date = Date(), calendar: Calendar = .current) -> Reading {
        let today = Self.dayKey(for: date, calendar: calendar)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Reading(day: today, tokens: 0)
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return Reading(day: today, tokens: 0, degraded: true)
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Reading(day: today, tokens: 0, degraded: true)
        }
        guard payload.day == today else { return Reading(day: today, tokens: 0) }
        return Reading(day: today, tokens: max(0, payload.tokens))
    }

    /// 开跑前判定。`quota <= 0` 视为没配额可用（配置层已经拦过，这里再守一道）。
    public func verdict(quota: Int, at date: Date = Date(), calendar: Calendar = .current) -> Verdict {
        let used = reading(at: date, calendar: calendar).tokens
        guard quota > 0 else { return .exhausted(used: used, quota: quota) }
        if used >= quota { return .exhausted(used: used, quota: quota) }
        return .allowed(remaining: quota - used)
    }

    /// 记账（跨日先归零再累加）。返回记完之后的读数 —— 界面用它更新那一行，不再自己算一遍。
    @discardableResult
    public func record(tokens: Int, at date: Date = Date(), calendar: Calendar = .current) -> Reading {
        let today = Self.dayKey(for: date, calendar: calendar)
        let current = reading(at: date, calendar: calendar)
        let next = Payload(day: today, tokens: max(0, current.tokens + max(0, tokens)))
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            return Reading(day: today, tokens: next.tokens)
        } catch {
            // 写不进去：如实标降级，**不**假装记上了（读数会少算，界面照实说）。
            return Reading(day: today, tokens: next.tokens, degraded: true)
        }
    }
}
