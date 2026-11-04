import Foundation

// `FR-RTR-MKT-HEALTH-001` 的**缺口四处同源**（执行契约 §16.6⑤：「图上断点、表上空槽 + 原因、
// 导出空单元格、统计分母剔除并报 n/N；四处必须同一份缺口清单」）。
//
// 契约出处（概要设计 §3.5 公共口径 D + §3.5.6 ⑤）：
//   · 缺口 = 相对交易日历**该有却没有**的行；停牌 / 退市 / 尚未上市属**已知豁免**，
//     豁免须命中规则并留痕，且**只标记不删数据**；
//   · 缺口**不改写成连续**：不插值、不前值填充；
//   · 同一份数据在四处（图 / 表 / 导出 / 统计）各算一遍缺口 ⇒ 迟早四处不一样，
//     所以本片只产出**一份清单**，四处是它的**投影**（不是四份各自的计算）。
//
// 本片不含交易日历本身（接入层给），只吃「应有日期序列」与「实际行日期」。

/// 缺口条目：一处缺口 = 一个交易日 + 一个原因类别。
public struct GapEntry: Equatable, Hashable {
    /// 原因类别（判据比的是类别，不是文案）。
    public enum Reason: String, Equatable, Hashable {
        /// 该有却没有（相对交易日历缺行）。
        case missingBar = "缺行情"
        /// 已知豁免：停牌。
        case suspended = "停牌"
        /// 已知豁免：退市。
        case delisted = "退市"
        /// 已知豁免：尚未上市。
        case notListed = "尚未上市"
    }

    public let tradingDay: String
    public let reason: Reason

    public init(tradingDay: String, reason: Reason) {
        self.tradingDay = tradingDay
        self.reason = reason
    }

    /// 是否计入「真缺口」（豁免只标记，不进分母剔除的分子）。
    public var isRealGap: Bool { reason == .missingBar }
}

/// 缺口清单：**唯一**一份，四处投影都从它取。
public struct GapLedger: Equatable {
    /// 全序：交易日升序，同日按原因排序（判据要求「两次运行逐行一致」）。
    public let entries: [GapEntry]

    /// 由「应有交易日」与「实际行日期」+ 豁免规则产出清单。
    ///
    /// - Parameters:
    ///   - expectedDays: 交易日历给的应有日期（`YYYY-MM-DD`）
    ///   - actualDays: 库里实际存在的行日期
    ///   - exemptions: 已知豁免（日期 ⇒ 原因），命中即按豁免记，不算「真缺口」
    public init(expectedDays: [String], actualDays: [String], exemptions: [String: GapEntry.Reason] = [:]) {
        let actual = Set(actualDays)
        let entries = Set(expectedDays)
            .subtracting(actual)
            .map { day in
                GapEntry(tradingDay: day, reason: exemptions[day] ?? .missingBar)
            }
            .sorted { lhs, rhs in
                if lhs.tradingDay != rhs.tradingDay { return lhs.tradingDay < rhs.tradingDay }
                return lhs.reason.rawValue < rhs.reason.rawValue
            }
        self.entries = entries
    }

    /// 真缺口（缺行情）的交易日集合。
    public var realGapDays: [String] { entries.filter(\.isRealGap).map(\.tradingDay) }

    // MARK: - 四处投影（同一份 entries，四种形状）

    /// ① 图表：断点。缺口处**不连线**（两点各自断开），且给出缺口计数。
    /// 返回可绘制点（连续段内相邻）+ 段数，缺口把序列切成 `段数 = 缺口数 + 1`。
    public func chartProjection(points: [String]) -> (drawableSegments: Int, gapCount: Int) {
        let gaps = realGapDays.filter { $0 >= (points.first ?? "") && $0 <= (points.last ?? "") }
        return (drawableSegments: points.isEmpty ? 0 : gaps.count + 1, gapCount: gaps.count)
    }

    /// ② 表格 / ③ 导出：空单元格 + 原因（**不填 0、不前值填充**）。
    public func tableProjection() -> [(tradingDay: String, cell: String, reason: String)] {
        entries.map { (tradingDay: $0.tradingDay, cell: "", reason: $0.reason.rawValue) }
    }

    /// ④ 统计：报「可用样本 n/N」。
    ///
    /// 口径（**唯一一处**）：**分母 = 应有交易日 − 豁免日**（停牌 / 退市 / 未上市在口径上就不该有行情，
    /// 留在分母里等于把「本来就不该有」记成「缺了」）；**分子 = 分母 − 真缺口**。
    public func statsProjection(expectedDays: [String]) -> (available: Int, total: Int) {
        let exempt = Set(entries.filter { !$0.isRealGap }.map(\.tradingDay))
        let total = expectedDays.filter { !exempt.contains($0) }.count
        let missing = realGapDays.filter { expectedDays.contains($0) }.count
        return (available: total - missing, total: total)
    }

    /// 判据本体：四处投影里的缺口交易日集合必须**完全相同**（少一处即判红）。
    public func projectionsAgree(expectedDays: [String]) -> Bool {
        let truth = Set(realGapDays)
        let table = Set(tableProjection().filter { $0.reason == GapEntry.Reason.missingBar.rawValue }.map(\.tradingDay))
        let chart = Set(realGapDays)
        let stats = Set(realGapDays.filter { expectedDays.contains($0) })
        return truth == table && truth == chart && stats.isSubset(of: truth)
    }
}
