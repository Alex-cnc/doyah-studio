import Foundation

// `FR-RTR-RSR-SCENARIO-001` / `FR-RTR-RSR-BACKTEST-001` 的**未来函数硬判据**
// （执行契约 §16.12 / §16.13 ①：「每次计算附「最大数据日」读数，> 游标日即失败」）。
//
// 契约出处（概要设计 §3.5 公共口径 A + §3.5.12 ① + §3.5.13 ①）：
//   · 暴露给图表 / 指标 / 规则的数据终点 = **游标日**；任何计算读取的行满足 **数据日 ≤ 游标日**；
//   · 「隐藏后续」是**真取不到**（数据入口按游标裁剪），不是视觉遮挡；
//   · 回退到某日再推进回同一日，全部读数逐值一致（**含中间序列**，不只末端）。
//
// 本片只做三件事，都是纯函数（不碰盘、不碰时钟、不碰 GUI）：
//   ① `maxDataDate` —— 一组行的最大数据日（未来函数判据的读数来源）；
//   ② `assertReadable` —— 越界即抛 `CursorViolation.futureData`（**不返回空、不静默裁剪**）；
//   ③ `readable` —— 按游标裁剪后的行（裁剪在**数据入口**做，下游拿不到未来行）。
//
// 交易日一律用 `YYYY-MM-DD` 字符串表达（字典序 = 时间序），不引入时区与日历：
// 契约层的判据是「日期比较」，不是「时刻比较」；跨时区换算属接入层。

/// 游标越界（`dataDate > cursor`）—— 判红，不接受「浮点噪声」式的解释。
public enum CursorViolation: Error, Equatable, CustomStringConvertible {
    /// 数据日晚于游标（未来函数）。
    case futureData(dataDate: String, cursor: String)

    public var description: String {
        switch self {
        case let .futureData(dataDate, cursor):
            return "数据日 \(dataDate) 晚于游标 \(cursor)：未来函数，拒绝计算"
        }
    }
}

/// 游标裁剪（`FR-RTR-RSR-SCENARIO-001`）。
public enum CursorGuard {
    /// 一组行的最大数据日；空集合 ⇒ `nil`（「无数据」与「数据日为 0」是两件事）。
    public static func maxDataDate<S: Sequence>(_ dataDates: S) -> String? where S.Element == String {
        dataDates.max()
    }

    /// 判据本体：最大数据日 > 游标日 ⇒ 抛错。
    ///
    /// **零容忍**：哪怕只多一天也抛 —— 契约说「出现即失败」，不说「多几天才失败」。
    public static func assertReadable<S: Sequence>(dataDates: S, cursor: String) throws where S.Element == String {
        guard let latest = maxDataDate(dataDates) else { return }
        guard latest <= cursor else {
            throw CursorViolation.futureData(dataDate: latest, cursor: cursor)
        }
    }

    /// 按游标裁剪：只留下 `数据日 ≤ 游标` 的行，保持输入顺序。
    ///
    /// 这是「真取不到」的实现点 —— 下游拿到的是裁剪后的数组，
    /// 不存在「拿到了但界面上遮住」这条路（遮住就还能被读到，等于没有游标）。
    public static func readable<T>(_ rows: [T], cursor: String, dataDate: (T) -> String) -> [T] {
        rows.filter { dataDate($0) <= cursor }
    }
}
