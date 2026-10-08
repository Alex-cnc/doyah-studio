import Foundation

/// 待办日历月视图**每格副条**要用的那两样东西：**农历日**（队列 `L-100` 的界面半第三片）
/// 与**当日节气**。
///
/// 为什么这一整块落在 Core（与 `TodoCalendar` 同一条理由）：
///  ① 「这一天是农历几月几号 / 是不是节气」是**换算**，把它画出来才是界面 —— 换算各端各写
///     一遍就会出现「同一份数据在两个端上落在不同的日子」，而这种差异**单端永远自洽**；
///  ② 与对侧同族：农历 / 二十四节气（`FR-NOTE-40` / `FR-NOTE-41`）是**共享层能力**，
///     不属任何一端的界面片（`Docs/概要设计.md` 第 186 轮那条边界就是这么登记的）。
///
/// 三条口径（与 `TodoCalendar` 头部那四条同源）：
///  ① **不读系统时钟**：参照时刻（`Date`）与日历（`Calendar`）一律由调用方传 —— 本文件
///     一个 `Date()` / `Calendar.current` 都没有；
///  ② **语言不进 Core**：这里只出「哪个键」（`LKey`）与「哪个档」（枚举），句子在语言表里，
///     拼装（`L(...)`）在界面那一层 —— 与 `TodoCalendar.weekdayHeaderKeys` 同一条纪律；
///  ③ **脏值不抛错**：表覆盖范围之外（1900 年之前 / 2100 年之后 / 越界钟点）回 `nil`，
///     界面收到 `nil` 就不画副条，不崩、不猜。
public enum LunarCalendar {

    // MARK: - 覆盖范围

    /// 农历换算表覆盖的**农历年**（含）：农历数据表按年编，只有这一个区间的答案有出处。
    /// 农历年在表外的日期 `lunarDate(of:calendar:)` 回 `nil`（界面不画副条）——
    /// 注意**公历 2101 年初的那几天仍属农历 2100 年**，它们**在**范围内（表边界跟着农历年走）。
    public static let lunarYearRange = 1900...2100

    /// 节气计算能覆盖的公历年：天文公式在 1000~3000 年都有意义（1900~2100 是常用区间）。
    public static let solarTermYearRange = 1000...3000

    // MARK: - 对外入口

    /// **某一天的副条**：农历日 +（有则）当日节气。表外回 `nil`。
    ///
    /// 只有一个入口 —— 界面不该自己先取农历、再单独问一次节气（两处各问一次，
    /// 就会出现「同一天农历取自一个日历、节气取自另一个」，那种差异只在跨时区时看得见）。
    public static func dayInfo(for date: Date, calendar: Calendar) -> LunarDayInfo? {
        guard let lunar = lunarDate(of: date, calendar: calendar) else { return nil }
        return LunarDayInfo(lunar: lunar, term: solarTerm(on: date, calendar: calendar))
    }

    /// **公历某天 → 农历**（`FR-NOTE-40`）。表外回 `nil`。
    ///
    /// 「哪一天」按**调用方给的日历**（含它的时区）算：农历是**中国标准时间**意义上的日历，
    /// 界面传本地日历时与传中国时区日历结果一致（本机就是 CST）；判据里一律显式传
    /// `Asia/Shanghai` —— 跨零点那类用例只能靠固定时区钉住（与 `TodoCalendarTests` 同做法）。
    public static func lunarDate(of date: Date, calendar: Calendar) -> LunarDate? {
        let day = calendar.startOfDay(for: date)
        guard let base = calendar.date(from: DateComponents(year: 1900, month: 1, day: 31)) else {
            return nil
        }
        // 「差几天」只借 `Calendar` 加减（不自己减一个日长：夏令时那两天两套答案会差一小时）。
        guard let offset = calendar.dateComponents([.day], from: base, to: day).day else { return nil }
        return lunarDate(daysAfterBase: offset)
    }

    /// **某一天的节气**（`FR-NOTE-41`）：这一天正好是某个节气交节的那一天 ⇒ 回那一枚；否则 `nil`。
    ///
    /// 一个公历月恰好两枚节气（`2k` / `2k+1`），所以只在「这一天所在月的那两枚」里找 ——
    /// 遍历 24 枚的写法会多问 22 次，且「哪个月有哪两枚」这条换算就会在各处各写一遍。
    public static func solarTerm(on date: Date, calendar: Calendar) -> SolarTerm? {
        let month = calendar.component(.month, from: date)
        guard (1...12).contains(month) else { return nil }
        let year = calendar.component(.year, from: date)
        for raw in [(month - 1) * 2, (month - 1) * 2 + 1] {
            guard let term = SolarTerm(rawValue: raw),
                  let instant = instant(of: term, year: year, calendar: calendar) else { continue }
            // 「交节那天」= 交节时刻与这一天在**同一个日界内**（日界由调用方的日历给）。
            if calendar.isDate(instant, inSameDayAs: date) { return term }
        }
        return nil
    }

    // MARK: - 农历换算（表驱动 · 1900~2100）

    /// **表驱动**的农历换算：1900-01-31 是农历 1900 年正月初一，按年表逐月扣天数。
    ///
    /// 为什么用表而不是**跟 Foundation 借**（`Calendar(identifier: .chinese)`）：
    /// 判据要求「农历部分与 Foundation 逐日比对」—— 换算若就是 Foundation 自己，
    /// 那份比对是**自证**（同一处实现比同一处实现，永远绿）。表与 Foundation 是**两个出处**，
    /// 对得上才是证据。表的来源与逐位校验见 `Tests/LunarCalendarTests.swift` 头注释。
    static func lunarDate(daysAfterBase offsetDays: Int) -> LunarDate? {
        guard offsetDays >= 0 else { return nil }
        var offset = offsetDays
        var year = 1900
        var length = 0
        while year < 2101, offset > 0 {
            length = daysInLunarYear(year)
            offset -= length
            year += 1
        }
        if offset < 0 {
            offset += length
            year -= 1
        }
        guard lunarYearRange.contains(year) else { return nil }

        let leap = leapMonth(ofLunarYear: year)
        var isLeap = false
        var month = 1
        while month < 13, offset > 0 {
            // 闰月排在**同名的那个月之后**：`month == leap + 1` 那一轮先扣闰月，
            // 再扣正牌的那个月（方言与 `lunarInfo` 的位序一致，改一处就会整体错位）。
            if leap > 0, month == leap + 1, !isLeap {
                month -= 1
                isLeap = true
                length = leapMonthDays(ofLunarYear: year)
            } else {
                length = monthDays(ofLunarYear: year, month: month)
            }
            if isLeap, month == leap + 1 { isLeap = false }
            offset -= length
            month += 1
        }
        if offset == 0, leap > 0, month == leap + 1 {
            if isLeap {
                isLeap = false
            } else {
                isLeap = true
                month -= 1
            }
        }
        if offset < 0 {
            offset += length
            month -= 1
        }
        guard (1...12).contains(month), (1...30).contains(offset + 1) else { return nil }
        return LunarDate(year: year, month: month, day: offset + 1, isLeapMonth: isLeap)
    }

    /// 某农历年的闰月（**0 = 没有闰月**）。
    static func leapMonth(ofLunarYear year: Int) -> Int {
        guard lunarYearRange.contains(year) else { return 0 }
        return lunarInfo[year - 1900] & 0xf
    }

    /// 某农历年闰月的天数（没有闰月回 0）。
    static func leapMonthDays(ofLunarYear year: Int) -> Int {
        guard leapMonth(ofLunarYear: year) > 0 else { return 0 }
        return (lunarInfo[year - 1900] & 0x10000) != 0 ? 30 : 29
    }

    /// 某农历年**某个月**（1~12，指正牌的那个月）的天数：大月 30、小月 29。
    static func monthDays(ofLunarYear year: Int, month: Int) -> Int {
        guard lunarYearRange.contains(year), (1...12).contains(month) else { return 0 }
        return (lunarInfo[year - 1900] & (0x10000 >> month)) != 0 ? 30 : 29
    }

    /// 某农历年的总天数（12 个月 + 闰月）。
    static func daysInLunarYear(_ year: Int) -> Int {
        guard lunarYearRange.contains(year) else { return 0 }
        var sum = 348
        var bit = 0x8000
        while bit > 0x8 {
            if (lunarInfo[year - 1900] & bit) != 0 { sum += 1 }
            bit >>= 1
        }
        return sum + leapMonthDays(ofLunarYear: year)
    }

    /// 1900~2100 年的农历年表：`0x___1_2___` —— 低 4 位 = 闰月月份（0 = 不闰），
    /// 位 `0x10000` = 闰月大小（1 = 30 天），位 `0x8000`~`0x10` 从正月起逐月记大小
    /// （1 = 30 天，0 = 29 天）。
    ///
    /// 来源：这份表是**公开的**农历数据（1900~2100，中国标准时间），广泛用于
    /// 「公历 ↔ 农历」的公开实现（例如 `calendar.js` 一系的实现，含 2049 年那处
    /// 修正）。本片**不自己编表**：逐位与 Foundation `Calendar(identifier: .chinese)`
    /// 逐年逐日比对（见 `Tests/LunarCalendarTests.swift`），对不上即判红。
    static let lunarInfo: [Int] = [
        0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, // 1900-1909
        0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, // 1910-1919
        0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, // 1920-1929
        0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, // 1930-1939
        0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, // 1940-1949
        0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, // 1950-1959
        0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, // 1960-1969
        0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, // 1970-1979
        0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, // 1980-1989
        0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0, // 1990-1999
        0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, // 2000-2009
        0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, // 2010-2019
        0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, // 2020-2029
        0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, // 2030-2039
        0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, // 2040-2049
        0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0, // 2050-2059
        0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4, // 2060-2069
        0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, // 2070-2079
        0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, // 2080-2089
        0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252, // 2090-2099
        0x0d520                                                                                    // 2100
    ]

    // MARK: - 节气（太阳视黄经 = 15° 的整数倍那一刻）

    /// **某一枚节气在某年的交节时刻**（那一刻是绝对时刻，落在哪一天由调用方的日历判）。
    ///
    /// 做法 = 求 `太阳视黄经 == 节气黄经` 的时刻，用**牛顿迭代**（黄经对时间几乎线性，
    /// 每天约 0.9856°，把它当导数，几步就收敛）。口径与「不读系统时钟」一致：
    /// 初值由**调用方的日历**在那一年的那个月里取一个近似日（上半月 6 号 / 下半月 21 号），
    /// 不碰任何全局状态。
    ///
    /// 精度与出处：太阳视黄经用 Meeus《Astronomical Algorithms》第 25 章那套
    /// （几何平均黄经 + 中心差 + 章动与光行差修正），1900~2100 年误差约 0.01°
    /// （≈ 15 分钟）；`ΔT` 用 Espenak & Meeus 的分段多项式。判据是**日级**：
    /// 2026 年 24 枚与公开对照表逐日一致（见 `Tests/LunarCalendarTests.swift` 头注释）。
    static func instant(of term: SolarTerm, year: Int, calendar: Calendar) -> Date? {
        guard solarTermYearRange.contains(year) else { return nil }
        var seed = DateComponents()
        seed.year = year
        seed.month = term.month
        // 一月两枚：靠月头的那枚（小寒 / 立春 / …）在 6 号附近，靠月尾的那枚在 21 号附近。
        seed.day = term.rawValue % 2 == 0 ? 6 : 21
        seed.hour = 12
        guard let start = calendar.date(from: seed) else { return nil }

        var julianDay = julianDay(from: start)
        for _ in 0..<80 {
            let longitude = apparentSolarLongitude(julianDayTT: julianDay)
            let delta = normalizedSignedDegrees(term.longitude - longitude)
            if abs(delta) < 1e-8 { break }
            julianDay += delta / solarLongitudeRatePerDay
        }
        // 迭代在**力学时**（TT）里做；交节时刻是**世界时**（UT）⇒ 减掉 ΔT。
        let julianDayUT = julianDay - deltaTSeconds(forYear: year) / 86_400
        return Date(timeIntervalSince1970: (julianDayUT - 2_440_587.5) * 86_400)
    }

    /// 太阳视黄经每天走的度数（节气的牛顿迭代用它当导数）。
    static let solarLongitudeRatePerDay = 0.9856473

    /// **太阳视黄经**（度，0~360，含章动与光行差）：Meeus《Astronomical Algorithms》
    /// 第二版第 25 章 25.2~25.10 三式 —— 几何平均黄经 `L0`、中心差 `C`，再补
    /// 光行差（`-0.00569°`）与黄经章动里主项（`-0.00478° · sin Ω`）。
    /// 参数是**力学时**的儒略日（TT）。
    static func apparentSolarLongitude(julianDayTT julianDay: Double) -> Double {
        let t = (julianDay - 2_451_545) / 36_525
        let meanLongitude = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let meanAnomaly = 357.52911 + 35_999.05029 * t - 0.0001537 * t * t
        let anomaly = meanAnomaly * .pi / 180
        let center = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(anomaly)
            + (0.019993 - 0.000101 * t) * sin(2 * anomaly)
            + 0.000289 * sin(3 * anomaly)
        let node = (125.04 - 1934.136 * t) * .pi / 180
        return normalizedDegrees(meanLongitude + center - 0.00569 - 0.00478 * sin(node))
    }

    /// 儒略日（世界时口径）← 绝对时刻。
    static func julianDay(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    /// `ΔT = TT - UT`（秒）：Espenak & Meeus 的分段多项式（NASA 日食网站那套，
    /// 1900~2150 分段）。精度对**日级**判据绰绰有余（本世纪量级 ~70 s）；
    /// 表外用 2150 年那一段外推（界面上不过是一格副条，不值得为它再补几段）。
    static func deltaTSeconds(forYear year: Int) -> Double {
        let y = Double(year)
        switch year {
        case ..<1920:
            let t = y - 1900
            return -2.79 + 1.494119 * t - 0.0598939 * t * t + 0.0061966 * t * t * t
                - 0.000197 * t * t * t * t
        case 1920..<1941:
            let t = y - 1920
            return 21.20 + 0.84493 * t - 0.076100 * t * t + 0.0020936 * t * t * t
        case 1941..<1961:
            let t = y - 1950
            return 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2547
        case 1961..<1986:
            let t = y - 1975
            return 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718
        case 1986..<2005:
            let t = y - 2000
            return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * t * t * t
                + 0.000651814 * t * t * t * t + 0.00002373599 * t * t * t * t * t
        case 2005..<2050:
            let t = y - 2000
            return 62.92 + 0.32217 * t + 0.005589 * t * t
        default:
            let u = (y - 1820) / 100
            return -20 + 32 * u * u - 0.5628 * (2150 - y)
        }
    }

    // MARK: - 角度归一（各一处出处）

    /// 把角度归一到 `[0, 360)`（黄经、时角都用它 —— 两处各写一遍就会出现两个「360 算不算 0」）。
    static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// 把角度差归一到 `(-180, 180]`（牛顿迭代里「还差几度」必须走这一段，否则会绕一整圈）。
    static func normalizedSignedDegrees(_ degrees: Double) -> Double {
        let value = normalizedDegrees(degrees)
        return value > 180 ? value - 360 : value
    }
}

/// **二十四节气**（`FR-NOTE-41` 的那 24 个太阳黄经节点）。
///
/// 取值空间只落这一处：界面遍历 `allCases` 或按「某月两枚」取。枚举顺序**就是**公历一年里的
/// 先后（`rawValue` 0 = 小寒 … 23 = 冬至）—— 于是「某月的那两枚 = `2k` / `2k+1`」这条换算
/// 只有一处（`LunarCalendar.solarTerm(on:calendar:)`），界面不自己排一遍。
public enum SolarTerm: Int, CaseIterable, Sendable {

    case minorCold = 0           // 小寒 285°
    case majorCold = 1           // 大寒 300°
    case startOfSpring = 2       // 立春 315°
    case rainWater = 3           // 雨水 330°
    case awakeningOfInsects = 4  // 惊蛰 345°
    case springEquinox = 5       // 春分 0°
    case pureBrightness = 6      // 清明 15°
    case grainRain = 7           // 谷雨 30°
    case startOfSummer = 8       // 立夏 45°
    case grainFull = 9           // 小满 60°
    case grainInEar = 10         // 芒种 75°
    case summerSolstice = 11     // 夏至 90°
    case minorHeat = 12          // 小暑 105°
    case majorHeat = 13          // 大暑 120°
    case startOfAutumn = 14      // 立秋 135°
    case endOfHeat = 15          // 处暑 150°
    case whiteDew = 16           // 白露 165°
    case autumnEquinox = 17      // 秋分 180°
    case coldDew = 18            // 寒露 195°
    case frostDescent = 19       // 霜降 210°
    case startOfWinter = 20      // 立冬 225°
    case minorSnow = 21          // 小雪 240°
    case majorSnow = 22          // 大雪 255°
    case winterSolstice = 23     // 冬至 270°

    /// 这一节气落在**公历的哪个月**（1~12）：小寒 / 大寒在一月 …… 冬至在十二月。
    public var month: Int { rawValue / 2 + 1 }

    /// 这一节气的**太阳视黄经**（度）：小寒 285°、立春 315°、春分 0° …… 冬至 270°。
    public var longitude: Double { Double((rawValue * 15 + 285) % 360) }

    /// 这一节气在语言表里的名字（唯一出处 —— 两处各写一遍迟早出现「同一节气两个名字」）。
    public var key: LKey {
        switch self {
        case .minorCold: return .lunarTermMinorCold
        case .majorCold: return .lunarTermMajorCold
        case .startOfSpring: return .lunarTermStartOfSpring
        case .rainWater: return .lunarTermRainWater
        case .awakeningOfInsects: return .lunarTermAwakeningOfInsects
        case .springEquinox: return .lunarTermSpringEquinox
        case .pureBrightness: return .lunarTermPureBrightness
        case .grainRain: return .lunarTermGrainRain
        case .startOfSummer: return .lunarTermStartOfSummer
        case .grainFull: return .lunarTermGrainFull
        case .grainInEar: return .lunarTermGrainInEar
        case .summerSolstice: return .lunarTermSummerSolstice
        case .minorHeat: return .lunarTermMinorHeat
        case .majorHeat: return .lunarTermMajorHeat
        case .startOfAutumn: return .lunarTermStartOfAutumn
        case .endOfHeat: return .lunarTermEndOfHeat
        case .whiteDew: return .lunarTermWhiteDew
        case .autumnEquinox: return .lunarTermAutumnEquinox
        case .coldDew: return .lunarTermColdDew
        case .frostDescent: return .lunarTermFrostDescent
        case .startOfWinter: return .lunarTermStartOfWinter
        case .minorSnow: return .lunarTermMinorSnow
        case .majorSnow: return .lunarTermMajorSnow
        case .winterSolstice: return .lunarTermWinterSolstice
        }
    }
}

/// **农历某一天**（`FR-NOTE-40`）：年 / 月 / 日 + 是不是闰月。
///
/// 只出**结构**（哪个键、几号），不出句子：月名 / 日名在语言表里，界面拿键去取
/// —— 与 `TodoCalendar.weekdayHeaderKeys` 同一条纪律（句子只在语言表里）。
public struct LunarDate: Equatable, Sendable {

    /// 农历年（绝对年号，如 2026）。**不是**干支纪年的 60 循环数。
    public let year: Int
    /// 农历月（1~12；闰月与同名月同为这个数，靠 `isLeapMonth` 分辨）。
    public let month: Int
    /// 农历日（1~30）。
    public let day: Int
    /// 是不是闰月（`true` ⇒ 界面上月名前要带「闰」）。
    public let isLeapMonth: Bool

    public init(year: Int, month: Int, day: Int, isLeapMonth: Bool) {
        self.year = year
        self.month = month
        self.day = day
        self.isLeapMonth = isLeapMonth
    }

    /// 月名的语言键：值是**月名前缀**（正 / 二 / … / 冬 / 腊；闰月再带「闰」），
    /// 「月」字由副条模板给 —— 这样中英两种语言可以各用各的拼法（中文挨着写、英文用 `/`）。
    public var monthNameKey: LKey {
        let index = min(max(month, 1), 12) - 1
        return isLeapMonth ? LunarDate.leapMonthKeys[index] : LunarDate.monthKeys[index]
    }

    /// 日名的语言键（初一 … 三十）。
    public var dayNameKey: LKey {
        LunarDate.dayKeys[min(max(day, 1), 30) - 1]
    }

    private static let monthKeys: [LKey] = [
        .lunarMonth1st, .lunarMonth2nd, .lunarMonth3rd, .lunarMonth4th, .lunarMonth5th, .lunarMonth6th,
        .lunarMonth7th, .lunarMonth8th, .lunarMonth9th, .lunarMonth10th, .lunarMonth11th, .lunarMonth12th
    ]

    private static let leapMonthKeys: [LKey] = [
        .lunarMonthLeap1st, .lunarMonthLeap2nd, .lunarMonthLeap3rd, .lunarMonthLeap4th,
        .lunarMonthLeap5th, .lunarMonthLeap6th, .lunarMonthLeap7th, .lunarMonthLeap8th,
        .lunarMonthLeap9th, .lunarMonthLeap10th, .lunarMonthLeap11th, .lunarMonthLeap12th
    ]

    private static let dayKeys: [LKey] = [
        .lunarDay1, .lunarDay2, .lunarDay3, .lunarDay4, .lunarDay5,
        .lunarDay6, .lunarDay7, .lunarDay8, .lunarDay9, .lunarDay10,
        .lunarDay11, .lunarDay12, .lunarDay13, .lunarDay14, .lunarDay15,
        .lunarDay16, .lunarDay17, .lunarDay18, .lunarDay19, .lunarDay20,
        .lunarDay21, .lunarDay22, .lunarDay23, .lunarDay24, .lunarDay25,
        .lunarDay26, .lunarDay27, .lunarDay28, .lunarDay29, .lunarDay30
    ]
}

/// **某一天的副条素材**：农历日 + 当日节气（无则 `nil`）。
public struct LunarDayInfo: Equatable, Sendable {

    /// 农历日。
    public let lunar: LunarDate
    /// 当日节气（这一天不是交节日 ⇒ `nil`，界面就不画那一行）。
    public let term: SolarTerm?

    public init(lunar: LunarDate, term: SolarTerm?) {
        self.lunar = lunar
        self.term = term
    }
}
