import Foundation

// `FR-RTR-MKT-FEED-002` 的**幂等落库**（执行契约 §16.4：「幂等键 = 标的 + 周期 + 交易日 + 复权方式，
// 同键覆盖不追加」）。
//
// 契约出处（概要设计 §3.5 公共口径 A + §3.5.4 ①）：
//   · 幂等键 = 标的 + 周期 + 交易日 + 复权方式；同键重跑 **覆盖不追加**；
//   · 写入按**单标的事务**，失败不落半截行（半个标的比没有更坏：它会被当成「已有数据」）；
//   · 每条价格带**来源**与**复权标记**（复权价能用复权因子复算，相对差 ≤ 1e-6）。
//
// 本片是**内存版**落库语义（真正的事务在存储层）：它的作用是把「覆盖不追加」这条判据
// 变成可执行的东西 —— 谁要写盘，先过这一层的键与事务边界。
// 单标事务：`commit(symbol:)` 之前，任何 `stage` 都不可见；失败即丢弃该标的的全部待写行。

/// 幂等键（`FR-RTR-MKT-FEED-002`）：四要素齐全才成键，缺一不允许落库。
public struct BarKey: Hashable, CustomStringConvertible {
    public let symbol: String
    public let period: String
    public let tradingDay: String   // YYYY-MM-DD
    public let adjustment: String   // 复权方式：不复权 / 前复权 / 后复权

    public init(symbol: String, period: String, tradingDay: String, adjustment: String) {
        self.symbol = symbol
        self.period = period
        self.tradingDay = tradingDay
        self.adjustment = adjustment
    }

    public var description: String { "\(symbol)|\(period)|\(tradingDay)|\(adjustment)" }
}

/// 一行价格（只留判据需要的字段）。
public struct BarRow: Equatable {
    public let key: BarKey
    public let open: Decimal
    public let high: Decimal
    public let low: Decimal
    public let close: Decimal
    /// 成交量：缺列 = **缺失**（`nil`），不是 0（公共口径 D）。
    public let volume: Decimal?
    /// 来源（换源不改上层，但来源必须随行）。
    public let source: String

    public init(key: BarKey, open: Decimal, high: Decimal, low: Decimal, close: Decimal, volume: Decimal?, source: String) {
        self.key = key
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.source = source
    }
}

/// 内存版幂等落库（覆盖不追加 + 单标事务）。
public struct IdempotentBarStore {
    /// 已提交行（键 ⇒ 行）。同键只可能有一行 —— 这就是「覆盖不追加」的形状。
    private var committed: [BarKey: BarRow] = [:]
    /// 待写行（按标的暂存；`commit(symbol:)` 前不可见）。
    private var staged: [String: [BarKey: BarRow]] = [:]

    public init() {}

    /// 已提交行数（判据：同键重跑后不增长）。
    public var count: Int { committed.count }

    /// 按标的取已提交行（全序：交易日升序、并列按键字符串升序）。
    public func rows(symbol: String) -> [BarRow] {
        committed.values
            .filter { $0.key.symbol == symbol }
            .sorted { lhs, rhs in
                if lhs.key.tradingDay != rhs.key.tradingDay { return lhs.key.tradingDay < rhs.key.tradingDay }
                return lhs.key.description < rhs.key.description
            }
    }

    /// 暂存一行：同键在暂存区里**覆盖**（不追加）。
    public mutating func stage(_ row: BarRow) {
        var bucket = staged[row.key.symbol] ?? [:]
        bucket[row.key] = row
        staged[row.key.symbol] = bucket
    }

    /// 提交某标的的全部暂存行（单标事务）：之后才对读方可见。
    public mutating func commit(symbol: String) {
        guard let bucket = staged.removeValue(forKey: symbol) else { return }
        for (key, row) in bucket { committed[key] = row }
    }

    /// 回滚某标的的全部暂存行（失败不落半截行）。
    public mutating func rollback(symbol: String) {
        staged.removeValue(forKey: symbol)
    }

    /// 便捷路径：一行即一标的事务（导入单条时用）。
    public mutating func upsert(_ row: BarRow) {
        stage(row)
        commit(symbol: row.key.symbol)
    }
}
