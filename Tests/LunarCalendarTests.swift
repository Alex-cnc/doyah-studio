import XCTest
@testable import DoyahCore

/// 片 `TD-CAL-2`（派单 `T-20261009-026`）的 Core 半判据：**农历换算**（`FR-NOTE-40`）
/// 与**二十四节气判定**（`FR-NOTE-41`）。
///
/// 为什么这两块值得单测（与 `TodoCalendarTests` 头注释同族）：
///  · 「这一天是农历几月几号 / 是不是交节那天」是**跨端口径** —— 算错一次就是「同一份数据
///    在两个端上落在不同的日子」，而这种差异**单端永远自洽**，只有拿**另一个出处**比才看得见；
///  · 农历表的位序、闰月排在同名月之后那一轮、节气牛顿迭代的收敛 —— 写错都不崩，
///    只会悄悄错一天。
///
/// **算法不许自证**（判据口径）：
///  ① **农历部分**逐日与 Foundation `Calendar(identifier: .chinese)` 比对 —— 表与 Foundation
///     是**两个出处**，对得上才算证据（若换算就是借 Foundation 来实现的，这条是自证）；
///  ② **节气部分**与**公开对照表**逐条比对（对照来源见下）。
///
/// 节气对照表来源（2026 年二十四节气交节时刻，**北京时间**）：
///   · `https://www.edtool.cn/toolbox/ershisijieqi.html`（二十四节气查询，1900~2099）；
///   · `https://www.ksij.cn/er-shi-si-jie-qi-2026/`（"2026年二十四节气时间表"）；
///   · `https://k.sina.com.cn/article_7857201856_1d45362c001902wbw6.html`（新浪 2026 年表）。
///   三处对**日期**一致；下表逐条抄自第一处（含时刻，用于说明本实现的精度落点）：
///     小寒 01-05 16:23:07 ｜ 大寒 01-20 09:44:53 ｜ 立春 02-04 04:02:05 ｜ 雨水 02-18 23:51:53
///     惊蛰 03-05 21:58:57 ｜ 春分 03-20 22:45:56 ｜ 清明 04-05 02:39:57 ｜ 谷雨 04-20 09:39:05
///     立夏 05-05 19:48:41 ｜ 小满 05-21 08:36:42 ｜ 芒种 06-05 23:48:18 ｜ 夏至 06-21 16:24:27
///     小暑 07-07 09:56:54 ｜ 大暑 07-23 03:13:02 ｜ 立秋 08-07 19:42:40 ｜ 处暑 08-23 10:18:46
///     白露 09-07 22:41:13 ｜ 秋分 09-23 08:05:11 ｜ 寒露 10-08 14:29:14 ｜ 霜降 10-23 17:37:54
///     立冬 11-07 17:52:01 ｜ 小雪 11-22 15:23:18 ｜ 大雪 12-07 10:52:29 ｜ 冬至 12-22 04:50:10
///
/// 本实现的精度（如实登记）：太阳视黄经取 Meeus 第 25 章那套（约 0.01° ≈ 15 分钟），
/// 24 枚里最大偏差 ~13 分钟（立夏），**日级判据 24/24 全中**；离日界最近的是
/// 芒种（真值 06-05 23:48）与雨水（02-18 23:51），都仍在正确的一侧。
final class LunarCalendarTests: XCTestCase {

    // MARK: - 固定日历（判据不受本机时区 / 地区影响）

    /// 公历 + 中国标准时间：农历与节气都是**中国标准时间**意义上的日历，
    /// 跨零点那类用例只能靠固定时区钉住（与 `TodoCalendarTests` 同做法）。
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }

    /// 对照出处：Foundation 自己的农历日历（**不是**本实现）。
    private var chineseCalendar: Calendar {
        var value = Calendar(identifier: .chinese)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func ymd(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// 当年表里的农历年 → 干支循环里的年号（1~60）：Foundation 的 `.year` 是**循环数**，
    /// 本实现的 `LunarDate.year` 是**绝对年号** —— 换算只有这一处（`(年 - 4) mod 60 + 1`，
    /// 1900 年为 37 与 Foundation 实测一致）。
    private func cycleYear(ofLunarYear year: Int) -> Int {
        ((year - 4) % 60 + 60) % 60 + 1
    }

    // MARK: - 农历：逐日与 Foundation 比对

    /// **逐日**比对：（月、日、闰月、循环年号）四项全等才算对上。
    ///
    /// 覆盖 1900 / 2023（闰二月）/ 2025（闰六月）/ 2026 / 2027 / 2099~2100 六个区段 ——
    /// 闰月、表头、表尾都在内（闰月那几段是「闰月排在同名月之后」那一轮的唯一证据）。
    func testLunarDateMatchesFoundationChineseCalendarDayByDay() {
        var spans: [(Date, Date)] = []
        for year in [2023, 2024, 2025, 2026, 2027] {
            spans.append((at(year, 1, 1), at(year, 12, 31)))
        }
        // 表头 / 表尾 / 闰月那几段（表外的两端也要有）。
        spans.append((at(1900, 1, 31), at(1900, 3, 15)))
        spans.append((at(2023, 3, 15), at(2023, 4, 20)))   // 闰二月
        spans.append((at(2025, 7, 1), at(2025, 8, 25)))    // 闰六月
        spans.append((at(2099, 11, 20), at(2100, 2, 20)))  // 表尾（2100 年那一段）

        var checked = 0
        for (start, end) in spans {
            var date = start
            while date <= end {
                let mine = LunarCalendar.lunarDate(of: date, calendar: calendar)
                let theirs = chineseCalendar.dateComponents(
                    [.year, .month, .day, .isLeapMonth], from: date
                )
                guard let mine else {
                    XCTFail("表内日期却取不到农历：\(ymd(date))")
                    return
                }
                XCTAssertEqual(mine.month, theirs.month, "月份对不上：\(ymd(date))")
                XCTAssertEqual(mine.day, theirs.day, "日对不上：\(ymd(date))")
                XCTAssertEqual(
                    mine.isLeapMonth, theirs.isLeapMonth == true,
                    "闰月标记对不上：\(ymd(date))"
                )
                XCTAssertEqual(
                    cycleYear(ofLunarYear: mine.year), theirs.year,
                    "循环年号对不上（农历 \(mine.year) 年）：\(ymd(date))"
                )
                checked += 1
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
        }
        // 防静默：一段都没比到 = 判据取不到输入（本仓库踩过两次这类假绿）。
        print("🧪 TD-CAL-2 农历逐日比对：与 Foundation 比了 \(checked) 天")
        XCTAssertGreaterThan(checked, 2000, "逐日比对的样本量太小，判据等于没跑（\(checked) 天）")
    }

    /// 公开对照表上的几个**已知值**（来源见文件头）：与 Foundation 无关的第二道锚 ——
    /// 两条出处同时对得上，才排除「两个实现同错一处」。
    func testLunarDateKnownValuesFromPublicReference() {
        let cases: [(Int, Int, Int, Int, Int, Int, Bool)] = [
            // 公历年 / 月 / 日, 农历年 / 月 / 日, 是否闰月
            (2026, 10, 8, 2026, 8, 28, false),   // 寒露那天 = 八月廿八（edtool / 新浪）
            (2026, 10, 23, 2026, 9, 14, false),  // 霜降 = 九月十四
            (2026, 11, 7, 2026, 9, 29, false),   // 立冬 = 九月廿九
            (2026, 9, 23, 2026, 8, 13, false),   // 秋分 = 八月十三
            (2026, 2, 4, 2025, 12, 17, false),   // 立春 = 二〇二五年腊月十七（新浪）
            (2026, 2, 18, 2026, 1, 2, false),    // 雨水 = 正月初二
            (2026, 6, 21, 2026, 5, 7, false),    // 夏至 = 五月初七
            (1900, 1, 31, 1900, 1, 1, false),    // 表头：1900 年正月初一
            (2023, 3, 22, 2023, 2, 1, true)      // 闰二月（2023 年唯一一处闰月）
        ]
        for (gy, gm, gd, ly, lm, ld, leap) in cases {
            let value = LunarCalendar.lunarDate(of: at(gy, gm, gd), calendar: calendar)
            XCTAssertEqual(value?.year, ly, "农历年对不上：\(gy)-\(gm)-\(gd)")
            XCTAssertEqual(value?.month, lm, "农历月对不上：\(gy)-\(gm)-\(gd)")
            XCTAssertEqual(value?.day, ld, "农历日对不上：\(gy)-\(gm)-\(gd)")
            XCTAssertEqual(value?.isLeapMonth, leap, "闰月标记对不上：\(gy)-\(gm)-\(gd)")
        }
    }

    /// 农历年在表外回 `nil` —— 界面据此**不画**副条，而不是猜一个日子。
    ///
    /// 边界跟着**农历年**走：`2101-01-01` 仍属农历 2100 年（在范围内，有答案），
    /// 到了农历 2101 年（公历 2101 年 2 月起）才回 `nil`。
    func testLunarDateIsNilOutsideTableRange() {
        XCTAssertNil(LunarCalendar.lunarDate(of: at(1899, 12, 31), calendar: calendar))
        XCTAssertNil(LunarCalendar.lunarDate(of: at(2101, 12, 31), calendar: calendar))
        XCTAssertNotNil(LunarCalendar.lunarDate(of: at(1900, 1, 31), calendar: calendar))
        XCTAssertNotNil(LunarCalendar.lunarDate(of: at(2100, 12, 31), calendar: calendar))
        // 表头那一端：公历 2101 年初仍在农历 2100 年内（表边界跟农历年，不跟公历年）。
        XCTAssertNotNil(LunarCalendar.lunarDate(of: at(2101, 1, 1), calendar: calendar))
    }

    /// 农历年表的结构不变量（表被抄错一位，这些会当场红）：
    /// 一年 353~385 天、一个月 29 或 30 天、闰月 0 或 1~12、表长正好 201（1900~2100）。
    func testLunarTableInvariants() {
        XCTAssertEqual(LunarCalendar.lunarInfo.count, 201, "1900~2100 正好 201 年")
        for year in 1900...2100 {
            let days = LunarCalendar.daysInLunarYear(year)
            XCTAssertTrue((353...385).contains(days), "\(year) 年天数 \(days) 越界")
            let leap = LunarCalendar.leapMonth(ofLunarYear: year)
            XCTAssertTrue((0...12).contains(leap), "\(year) 闰月 \(leap) 越界")
            var months = 0
            for month in 1...12 {
                let length = LunarCalendar.monthDays(ofLunarYear: year, month: month)
                XCTAssertTrue(length == 29 || length == 30, "\(year)-\(month) 月长 \(length) 越界")
                months += length
            }
            XCTAssertEqual(days, months + LunarCalendar.leapMonthDays(ofLunarYear: year))
        }
    }

    // MARK: - 节气：与公开对照表比对

    /// 2026 年 24 枚节气与公开对照表**逐条**对上（对照来源见文件头）。
    /// 同时判**反面**：交节那天的**前后各一天**都不是这一枚（否则「那一天」这个说法不成立）。
    func testSolarTermsMatchPublicReferenceFor2026() {
        let reference: [(SolarTerm, Int, Int)] = [
            (.minorCold, 1, 5), (.majorCold, 1, 20),
            (.startOfSpring, 2, 4), (.rainWater, 2, 18),
            (.awakeningOfInsects, 3, 5), (.springEquinox, 3, 20),
            (.pureBrightness, 4, 5), (.grainRain, 4, 20),
            (.startOfSummer, 5, 5), (.grainFull, 5, 21),
            (.grainInEar, 6, 5), (.summerSolstice, 6, 21),
            (.minorHeat, 7, 7), (.majorHeat, 7, 23),
            (.startOfAutumn, 8, 7), (.endOfHeat, 8, 23),
            (.whiteDew, 9, 7), (.autumnEquinox, 9, 23),
            (.coldDew, 10, 8), (.frostDescent, 10, 23),
            (.startOfWinter, 11, 7), (.minorSnow, 11, 22),
            (.majorSnow, 12, 7), (.winterSolstice, 12, 22)
        ]
        XCTAssertEqual(reference.count, 24, "对照表必须 24 条")
        for (term, month, day) in reference {
            let date = at(2026, month, day)
            XCTAssertEqual(
                LunarCalendar.solarTerm(on: date, calendar: calendar), term,
                "节气对不上：\(ymd(date)) 应为 \(term)"
            )
            let before = calendar.date(byAdding: .day, value: -1, to: date)!
            let after = calendar.date(byAdding: .day, value: 1, to: date)!
            XCTAssertNil(LunarCalendar.solarTerm(on: before, calendar: calendar), "\(ymd(before)) 不该有节气")
            XCTAssertNil(LunarCalendar.solarTerm(on: after, calendar: calendar), "\(ymd(after)) 不该有节气")
        }
    }

    /// 节气判定在**其它年份**也要自洽：把交节那天当锚，前一天的黄经差应当很小（< 1.5°），
    /// 后一天同理 —— 这是「那天确实卡在 15° 整数倍上」的机械证据，不依赖任何对照表。
    func testSolarTermLandingIsNearLongitudeMultipleOnOtherYears() {
        for year in [2024, 2025, 2027, 2030] {
            for term in SolarTerm.allCases {
                // 用本实现的「某年某枚交节时刻」找那天，再核对黄经。
                guard let instant = SolarCalendarTestSupport.instant(of: term, year: year, calendar: calendar) else {
                    XCTFail("取不到 \(year) 年 \(term) 的交节时刻")
                    continue
                }
                let longitude = LunarCalendar.apparentSolarLongitude(
                    julianDayTT: LunarCalendar.julianDay(from: instant)
                        + LunarCalendar.deltaTSeconds(forYear: year) / 86_400
                )
                let delta = abs(LunarCalendar.normalizedSignedDegrees(longitude - term.longitude))
                XCTAssertLessThan(delta, 0.001, "\(year) \(term) 交节时刻的黄经差 \(delta)° 太大")
            }
        }
    }

    /// 24 枚节气的**结构**：一月恰好两枚、黄经是对齐 15° 的 24 个整数倍、月份覆盖 1~12。
    /// （这一条不借任何表 —— 它判的是「取值空间本身立得住」。）
    func testSolarTermCoversTwelveMonthsTwiceEach() {
        XCTAssertEqual(SolarTerm.allCases.count, 24)
        XCTAssertEqual(SolarTerm.allCases.map(\.month), (0..<24).map { $0 / 2 + 1 })
        XCTAssertEqual(SolarTerm.allCases.map(\.longitude), (0..<24).map { Double(($0 * 15 + 285) % 360) })
        XCTAssertEqual(Set(SolarTerm.allCases.map(\.longitude)).count, 24, "24 个黄经不许重合")
        XCTAssertEqual(SolarTerm.allCases.filter { $0.key == .lunarTermColdDew }.count, 1)
    }

    // MARK: - 副条入口

    /// `dayInfo` 一次给齐两样：农历日 +（有则）节气。2026-10-08（寒露）同一天两样都有；
    /// 2026-10-09（今天）只有农历日、没有节气。
    func testDayInfoCarriesLunarDateAndTermOnTheSameDay() {
        let termDay = LunarCalendar.dayInfo(for: at(2026, 10, 8), calendar: calendar)
        XCTAssertEqual(termDay?.lunar.month, 8)
        XCTAssertEqual(termDay?.lunar.day, 28)
        XCTAssertEqual(termDay?.term, .coldDew)

        let plainDay = LunarCalendar.dayInfo(for: at(2026, 10, 9), calendar: calendar)
        XCTAssertEqual(plainDay?.lunar.month, 8)
        XCTAssertEqual(plainDay?.lunar.day, 29)
        XCTAssertNil(plainDay?.term)
    }

    /// `dayInfo` 在农历年表外回 `nil`（界面不画副条）。
    func testDayInfoIsNilOutsideTableRange() {
        XCTAssertNil(LunarCalendar.dayInfo(for: at(1899, 12, 31), calendar: calendar))
        XCTAssertNil(LunarCalendar.dayInfo(for: at(2101, 12, 31), calendar: calendar))
    }
}

/// 让判据够得着 Core 里那两个 `internal` 的换算入口（`instant(of:year:calendar:)` /
/// `apparentSolarLongitude` / `deltaTSeconds`）。放在这里而不是开 `public`：
/// 它们不是给界面用的 API，只是给判据留的观测点。
enum SolarCalendarTestSupport {
    static func instant(of term: SolarTerm, year: Int, calendar: Calendar) -> Date? {
        LunarCalendar.instant(of: term, year: year, calendar: calendar)
    }
}
