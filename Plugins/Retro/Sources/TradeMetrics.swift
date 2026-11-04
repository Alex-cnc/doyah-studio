import Foundation

// `FR-RTR-REV-ATTR-001` / `FR-RTR-REV-ATTR-002` 的**定义式单点 + 恒等式**
// （执行契约 §16.9：「七件套定义式单点」「恒等式对不上即判红」「合计闭合」）。
//
// 契约出处（概要设计 §3.5 公共口径 C + §3.5.9 ①②③）：
//   · 胜率 = 盈利笔数 ÷ 已平仓笔数；零交易 ⇒ **不适用**（不是 0）；
//   · 盈亏比 = 平均盈利额 ÷ |平均亏损额|；无亏损笔 ⇒ 不适用并报「无亏损笔」；
//   · 盈利因子 = 总盈利额 ÷ |总亏损额|；
//   · 期望值 = 净盈亏合计 ÷ 已平仓笔数（元/笔）；
//   · **恒等式**：盈利因子 = 盈亏比 × 胜率 ÷ (1 − 胜率) —— 分母口径差一处，等式立刻破；
//   · 数字写法：金额以最小货币单位整数累计；比率输出 **6 位小数、逢半进位**（不用银行家舍入）；
//     **中间计算不截断，只在输出处舍入一次**。
//
// 本片只做定义式与恒等式：不读库、不读盘、不接行情。`MetricValue` 用「值 / 不适用（带原因）」
// 两态表达公共口径 D 的「缺失三分」中的前两分（零是真实值，不适用是口径上不存在）。

/// 指标输出两态：**有值** / **不适用（带原因）** —— 不许用 0 或 nil 冒充「不适用」。
public enum MetricValue: Equatable, CustomStringConvertible {
    case value(Decimal)
    case notApplicable(reason: String)

    public var description: String {
        switch self {
        case let .value(value): return "\(value)"
        case let .notApplicable(reason): return "不适用（\(reason)）"
        }
    }
}

/// 一笔已平仓成交（只保留算指标需要的字段）。
public struct ClosedTrade: Equatable {
    /// 净盈亏（最小货币单位，已按 §16.9 ③ 扣完费用）。
    public let netProfit: Decimal

    public init(netProfit: Decimal) {
        self.netProfit = netProfit
    }
}

/// 归因七件套里可纯函数化的四件 + 恒等式（`FR-RTR-REV-ATTR-001`）。
public struct TradeMetrics: Equatable {
    /// 比率输出的位数（公共口径 C：6 位，逢半进位）。
    public static let ratioScale = 6

    public let paidTrades: Int
    public let winningTrades: Int
    public let losingTrades: Int
    /// 零盈亏笔（既非盈也非亏）。
    ///
    /// **必须单列**：恒等式 `PF = 盈亏比 × 胜率 ÷ (1 − 胜率)` 只在「胜率的分母 = 盈 + 亏」时成立；
    /// 把零盈亏笔算进分母，等式必然破 —— 这不是实现瑕疵，是契约里两句话的口径张力，
    /// 已在执行契约 §16.9 如实登记（Agent 遇到按「分母 = 盈 + 亏」实现，并把零盈亏笔单列报数）。
    public var flatTrades: Int { paidTrades - winningTrades - losingTrades }
    /// 参与胜率分母的笔数 = 盈 + 亏。
    public var directionalTrades: Int { winningTrades + losingTrades }
    public let grossProfit: Decimal
    public let grossLoss: Decimal

    public init(trades: [ClosedTrade]) {
        let profits = trades.map(\.netProfit)
        paidTrades = trades.count
        winningTrades = profits.filter { $0 > 0 }.count
        losingTrades = profits.filter { $0 < 0 }.count
        grossProfit = profits.filter { $0 > 0 }.reduce(0, +)
        grossLoss = profits.filter { $0 < 0 }.reduce(0) { $0 + abs($1) }
    }

    /// 胜率 = 盈利笔数 ÷（盈 + 亏）笔数（零交易或全是零盈亏 ⇒ 不适用，不是 0）。
    ///
    /// 分母**不含零盈亏笔**：含了就与恒等式冲突（见 `flatTrades`）。
    public var winRate: MetricValue {
        guard directionalTrades > 0 else { return .notApplicable(reason: "零交易") }
        return .value(Decimal(winningTrades) / Decimal(directionalTrades))
    }

    /// 盈亏比 = 平均盈利额 ÷ |平均亏损额|（无亏损笔 ⇒ 不适用）。
    public var payoffRatio: MetricValue {
        guard losingTrades > 0 else { return .notApplicable(reason: "无亏损笔") }
        guard winningTrades > 0 else { return .notApplicable(reason: "无盈利笔") }
        let averageWin = grossProfit / Decimal(winningTrades)
        let averageLoss = grossLoss / Decimal(losingTrades)
        return .value(averageWin / averageLoss)
    }

    /// 盈利因子 = 总盈利额 ÷ |总亏损额|（无亏损笔 ⇒ 不适用）。
    public var profitFactor: MetricValue {
        guard losingTrades > 0 else { return .notApplicable(reason: "无亏损笔") }
        return .value(grossProfit / grossLoss)
    }

    /// 期望值 = 净盈亏合计 ÷ 已平仓笔数（零交易 ⇒ 不适用）。
    public var expectancy: MetricValue {
        guard paidTrades > 0 else { return .notApplicable(reason: "零交易") }
        return .value((grossProfit - grossLoss) / Decimal(paidTrades))
    }

    /// 恒等式残差：`盈利因子 − 盈亏比 × 胜率 ÷ (1 − 胜率)`。
    ///
    /// **必须在未舍入值上算**（公共口径 C：中间不截断）—— 拿界面显示的 6 位小数回代，
    /// 残差会被舍入噪声喂大，判据就变成「看运气」。任一指标不适用 ⇒ `nil`（无法判，不是通过）。
    public var identityResidual: Decimal? {
        guard case let .value(profitFactor) = profitFactor,
              case let .value(payoffRatio) = payoffRatio,
              case let .value(winRate) = winRate,
              winRate != 1
        else { return nil }
        return profitFactor - payoffRatio * winRate / (1 - winRate)
    }

    /// 判据：恒等式残差绝对值 ≤ 容差（默认 1e-9；容差必须写进口径，不许临时放宽）。
    public func identityHolds(tolerance: Decimal = Decimal(string: "1e-9")!) -> Bool {
        guard let residual = identityResidual else { return false }
        return abs(residual) <= tolerance
    }
}

/// 公共口径 C 的输出舍入：**6 位小数、逢半进位**（不是银行家舍入），只在输出处调一次。
public enum RatioOutput {
    /// 按 `scale` 位小数做「逢半进位」舍入。
    public static func halfUp(_ value: Decimal, scale: Int = TradeMetrics.ratioScale) -> Decimal {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, scale, .plain)
        return rounded
    }

    /// 输出成定长字符串（判据比的是字符串，避免 Decimal 归一化差异）。
    public static func string(_ value: Decimal, scale: Int = TradeMetrics.ratioScale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = scale
        formatter.maximumFractionDigits = scale
        formatter.roundingMode = .halfUp
        return formatter.string(from: halfUp(value, scale: scale) as NSDecimalNumber) ?? "\(halfUp(value, scale: scale))"
    }
}
