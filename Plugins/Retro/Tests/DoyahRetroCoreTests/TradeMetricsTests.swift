import XCTest
@testable import DoyahRetroCore

// `FR-RTR-REV-ATTR-001` / `FR-RTR-REV-ATTR-002` 的机械证据
// （执行契约 §16.9：定义式单点 · 恒等式 · 不适用 ≠ 0 · 输出 6 位逢半进位）。
//
// 纪律：
//   ① **不适用不是 0**：零交易、无亏损笔都必须是 `.notApplicable(带原因)`；
//   ② **恒等式必须真能破**：造一组「分母口径不同」的数，判据必须判红 —— 只会永远为真的判据等于没写；
//   ③ **舍入只在输出处**：中间不截断，判据在未舍入值上算；舍入用逢半进位（不用银行家舍入）。

final class TradeMetricsTests: XCTestCase {

    private func trades(_ values: [Int]) -> TradeMetrics {
        TradeMetrics(trades: values.map { ClosedTrade(netProfit: Decimal($0)) })
    }

    /// 零交易 ⇒ 胜率与期望值「不适用」，不是 0。
    func testZeroTradesIsNotApplicable() {
        let metrics = trades([])
        XCTAssertEqual(metrics.winRate, .notApplicable(reason: "零交易"))
        XCTAssertEqual(metrics.expectancy, .notApplicable(reason: "零交易"))
        XCTAssertNil(metrics.identityResidual, "指标不适用时恒等式无法判，不许当成通过")
    }

    /// 无亏损笔 ⇒ 盈亏比与盈利因子「不适用」（不是无穷大、不是 0）。
    func testNoLosingTradesIsNotApplicable() {
        let metrics = trades([100, 200])
        XCTAssertEqual(metrics.payoffRatio, .notApplicable(reason: "无亏损笔"))
        XCTAssertEqual(metrics.profitFactor, .notApplicable(reason: "无亏损笔"))
        XCTAssertEqual(metrics.winRate, .value(1))
    }

    /// 恒等式在正常样本上成立：PF = 盈亏比 × 胜率 ÷ (1 − 胜率)。
    func testIdentityHoldsOnMixedSample() {
        let metrics = trades([100, 200, 300, -150, -250])
        XCTAssertTrue(metrics.identityHolds(), "残差 \(String(describing: metrics.identityResidual))")
        XCTAssertEqual(metrics.winRate, .value(Decimal(3) / Decimal(5)))
        XCTAssertEqual(metrics.profitFactor, .value(Decimal(600) / Decimal(400)))
    }

    /// 零盈亏笔单列，**不进胜率分母** —— 进了恒等式必然破（这是契约里两句话的口径张力）。
    func testFlatTradesAreExcludedFromWinRateDenominator() {
        let metrics = trades([100, 200, 300, -150, -250, 0])
        XCTAssertEqual(metrics.flatTrades, 1)
        XCTAssertEqual(metrics.directionalTrades, 5)
        XCTAssertEqual(metrics.winRate, .value(Decimal(3) / Decimal(5)))
        XCTAssertTrue(metrics.identityHolds(), "零盈亏笔进分母会把恒等式打破")
    }

    /// 判据必须能破：口径错配（胜率分母多算一笔）⇒ 残差超容差。
    func testIdentityBreaksWhenDenominatorDiffers() {
        let metrics = trades([100, 200, 300, -150, -250, 0])
        guard case let .value(profitFactor) = metrics.profitFactor,
              case let .value(winRate) = metrics.winRate,
              case let .value(payoffRatio) = metrics.payoffRatio
        else { return XCTFail("样本应给出三个值") }
        let wrongWinRate = Decimal(3) / Decimal(6)                   // 把零盈亏笔算进分母
        let residual = profitFactor - payoffRatio * wrongWinRate / (1 - wrongWinRate)
        XCTAssertGreaterThan(abs(residual), Decimal(string: "1e-9")!, "错配口径的残差必须超容差")
        XCTAssertEqual(winRate, Decimal(3) / Decimal(5), "正确口径是 盈 + 亏 做分母")
    }

    /// 输出舍入：6 位小数、逢半进位（银行家舍入在这里会给 0.000000）。
    func testRatioOutputRoundsHalfUpNotBankers() {
        let half = Decimal(string: "0.0000005")!
        XCTAssertEqual(RatioOutput.string(half), "0.000001", "逢半进位")
        let halfDown = Decimal(string: "0.0000004")!
        XCTAssertEqual(RatioOutput.string(halfDown), "0.000000")
        XCTAssertEqual(RatioOutput.string(Decimal(1) / Decimal(3)), "0.333333")
        XCTAssertEqual(RatioOutput.string(Decimal(2) / Decimal(3)), "0.666667")
    }

    /// 中间不截断：把显示值（6 位）回代算恒等式，残差比未舍入值大 —— 证明判据必须吃未舍入值。
    func testIdentityMustUseUnroundedValues() {
        // 样本刻意选成循环小数：3/7 与 60/220 都不是有限小数，舍入才会露出差异
        let metrics = trades([10, 20, 30, -40, -50, -60, -70])
        guard let precise = metrics.identityResidual else { return XCTFail("样本应可判") }
        XCTAssertLessThanOrEqual(abs(precise), Decimal(string: "1e-9")!)

        guard case let .value(pf) = metrics.profitFactor,
              case let .value(wr) = metrics.winRate,
              case let .value(pr) = metrics.payoffRatio
        else { return XCTFail("样本应给出三个值") }
        let roundedPF = RatioOutput.halfUp(pf)
        let roundedWR = RatioOutput.halfUp(wr)
        let roundedPR = RatioOutput.halfUp(pr)
        let roundedResidual = roundedPF - roundedPR * roundedWR / (1 - roundedWR)
        XCTAssertGreaterThan(abs(roundedResidual), abs(precise))
    }

    /// 合计闭合：盈利因子 = 总盈利 ÷ 总亏损（不是平均值的比）。
    func testProfitFactorIsTotalsNotAverages() {
        let metrics = trades([100, 100, 100, -50, -50])
        XCTAssertEqual(metrics.profitFactor, .value(Decimal(300) / Decimal(100)))
        XCTAssertEqual(metrics.expectancy, .value(Decimal(200) / Decimal(5)))
    }
}
