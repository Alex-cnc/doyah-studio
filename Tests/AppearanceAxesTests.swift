import XCTest
@testable import DoyahCore

/// 外观的**两条轴**（队列 L-85）：深浅轴（`AppearancePreference`：跟随系统 / 总是深色 / 总是浅色）
/// × 配色轴（`DesignTheme`：科技蓝 / 豆芽绿 / 玫瑰金）。
///
/// 这一族守的不是「哪套值更好看」，而是**两条轴正交**这件事本身 —— 需求提出者 2026-09-29 的口径是
/// 「只是要你具备主题可选的功能框架，你可以先实现随系统主题」：
///
///   ① **深浅轴**三态与真值表（3 态 × 系统当前态 = 6 组）逐组对上；
///   ② **正交**：深浅判定**只读深浅轴**（换主题不改深浅）、配色**只读配色轴**（换深浅不改配色）——
///      两轴一旦互相读，就会出现「切了主题，深浅档被顺手重置」这类没人能解释的行为；
///   ③ **可组合**：两轴的笛卡尔积（3 态 × 2 系统态 × 3 主题 = 18 组）逐组可达、不重不漏，
///      且「跟随系统」这一档在系统深浅**两态**下都拿到该主题对应那一档的值、**都过门槛**
///      （正文 ≥4.5 / 强对比 ≥7 / 图标线 ≥3）；
///   ④ 两轴的**持久化键分开**（切一轴不许把另一轴写回默认）。
///
/// 为什么单测之外还要 `Scripts/check-design-themes.py` 的判据 H：判据与被判对象同源是这里的缝
/// （两边都用 `ColorContrast` 算对比度），而且「键有没有被另一轴写」「界面上看不看得见当前档位」
/// 都不在单测视野里 —— 同族第 77/78 轮两次栽在「单测绿、事实不成立」。
final class AppearanceAxesTests: XCTestCase {

    private let thresholds = ColorContrast.Threshold.self

    /// 两轴组合的**一次性枚举**（判据 D/E 的公共入口）：18 组，顺序固定便于逐组定位。
    /// 放在测试里而不是生产代码里：生产侧两轴本来就是分开取的（`AppearancePreference` 管深浅、
    /// `DesignThemeManager` 管配色），**没有**一个「组合对象」；这里要的只是把组合逐个走一遍。
    private struct Combination: Hashable {
        let appearance: AppearancePreference
        let systemIsDark: Bool
        let theme: DesignTheme

        /// 深浅轴的结论：**只**由前两项决定。
        var isDark: Bool { appearance.resolvesToDark(systemIsDark: systemIsDark) }

        /// 配色：**只**由第三项决定。
        var palette: ThemePalette { theme.palette }

        /// 该组合下真正生效的五档表面 / 文本值（深浅由 `isDark` 选）。
        func value(_ light: UInt32, _ dark: UInt32) -> UInt32 { isDark ? dark : light }
    }

    private static let systemStates: [Bool] = [false, true]

    private static let matrix: [Combination] = AppearancePreference.allCases.flatMap { appearance in
        systemStates.flatMap { systemIsDark in
            DesignTheme.all.map { theme in
                Combination(appearance: appearance, systemIsDark: systemIsDark, theme: theme)
            }
        }
    }

    // MARK: - ① 深浅轴：三态与真值表

    /// 三态齐全、顺序稳定、**默认与未知值都回落「跟随系统」**。
    func testAppearanceAxisHasExactlyThreeStatesAndFallsBackToFollowSystem() {
        XCTAssertEqual(
            AppearancePreference.allCases,
            [.followSystem, .alwaysDark, .alwaysLight],
            "深浅轴必须是三态（跟随系统 / 总是深色 / 总是浅色），顺序也是界面里的顺序"
        )
        XCTAssertEqual(AppearancePreference.resolve(rawValue: nil), .followSystem)
        XCTAssertEqual(AppearancePreference.resolve(rawValue: ""), .followSystem)
        XCTAssertEqual(AppearancePreference.resolve(rawValue: "no-such-mode"), .followSystem)
        // 落盘用的 rawValue 是契约：改了等于让老用户的偏好失效
        XCTAssertEqual(AppearancePreference.followSystem.rawValue, "followSystem")
        XCTAssertEqual(AppearancePreference.alwaysDark.rawValue, "alwaysDark")
        XCTAssertEqual(AppearancePreference.alwaysLight.rawValue, "alwaysLight")
    }

    /// 真值表：3 态 × 系统当前态 = 6 组，**逐组**写出来（不是拿一个表达式算两遍）。
    func testAppearanceTruthTableOverEveryStateAndSystemValue() {
        XCTAssertFalse(AppearancePreference.followSystem.resolvesToDark(systemIsDark: false))
        XCTAssertTrue(AppearancePreference.followSystem.resolvesToDark(systemIsDark: true))
        XCTAssertTrue(AppearancePreference.alwaysDark.resolvesToDark(systemIsDark: false))
        XCTAssertTrue(AppearancePreference.alwaysDark.resolvesToDark(systemIsDark: true))
        XCTAssertFalse(AppearancePreference.alwaysLight.resolvesToDark(systemIsDark: false))
        XCTAssertFalse(AppearancePreference.alwaysLight.resolvesToDark(systemIsDark: true))
    }

    /// 两处出口**必须同一个答案**：`forcedDark`（交给 SwiftUI 的 `.preferredColorScheme`）
    /// 与 `resolvesToDark`（终端色板 / 快照用）。分叉就会出现「界面跟随系统、终端不跟随」。
    func testForcedDarkAgreesWithResolvedDark() {
        for appearance in AppearancePreference.allCases {
            for systemIsDark in Self.systemStates {
                let forced = appearance.forcedDark
                if appearance == .followSystem {
                    XCTAssertNil(forced, "跟随系统必须交给系统（`nil`）—— 写死 true/false 等于锁死外观")
                } else {
                    XCTAssertNotNil(forced)
                    XCTAssertEqual(forced, appearance.resolvesToDark(systemIsDark: systemIsDark),
                                   "\(appearance.rawValue) 的两处出口给出不同答案")
                }
            }
        }
    }

    // MARK: - ② 正交：两轴互不读取

    /// **换主题不改深浅判定**：同一个（深浅档 × 系统态）下，三个主题给出的深浅结论必须一致。
    func testDarkResolutionIsIndependentOfTheme() {
        for appearance in AppearancePreference.allCases {
            for systemIsDark in Self.systemStates {
                let answers = DesignTheme.all.map { theme in
                    Combination(appearance: appearance, systemIsDark: systemIsDark, theme: theme).isDark
                }
                XCTAssertEqual(Set(answers).count, 1,
                               "\(appearance.rawValue)/系统\(systemIsDark ? "深" : "浅") 下"
                               + "不同主题给出不同的深浅结论 —— 配色轴串进了深浅轴")
            }
        }
    }

    /// **换深浅档不改配色**：同一个主题在 3 态 × 2 系统态下的值表必须是**同一份**。
    func testPaletteSelectionIsIndependentOfAppearanceAxis() {
        for theme in DesignTheme.all {
            let palettes = Self.matrix.filter { $0.theme == theme }.map { $0.palette }
            XCTAssertEqual(Set(palettes.map(\.id)).count, 1, "\(theme.id) 的配色随深浅档变了")
            for palette in palettes {
                XCTAssertEqual(palette, theme.palette, "\(theme.id) 的取到的值表不是它自己那份")
            }
        }
    }

    /// 两轴的**持久化键分开**且各自带命名空间 —— 分开才谈得上「切一轴不重置另一轴」。
    func testStorageKeysAreSeparateAndNamespaced() {
        let appearanceKey = AppearancePreference.Storage.appKey
        let themeKey = DesignTheme.Storage.key
        XCTAssertEqual(appearanceKey, "appearance.mode")
        XCTAssertEqual(themeKey, "ui.designTheme")
        XCTAssertNotEqual(appearanceKey, themeKey, "两轴共用一个键 ⇒ 切一轴必然重置另一轴")
        XCTAssertFalse(appearanceKey.isEmpty)
        XCTAssertFalse(themeKey.isEmpty)
        // 终端配色是**第三个**键（终端的深浅档允许单独覆盖界面）
        XCTAssertNotEqual(AppearancePreference.Storage.terminalKey, appearanceKey)
        XCTAssertNotEqual(AppearancePreference.Storage.terminalKey, themeKey)
    }

    // MARK: - ③ 可组合：笛卡尔积逐个走一遍

    /// 18 组：不重、不漏，且每轴每个取值都出现了正确的次数（3 主题各 6 组、3 态各 6 组、2 系统态各 9 组）。
    func testAxisMatrixCoversEveryCombinationExactlyOnce() {
        let combinations = Self.matrix
        XCTAssertEqual(combinations.count, 18, "3 态 × 2 系统态 × 3 主题 = 18")
        XCTAssertEqual(Set(combinations).count, 18, "组合有重复")
        for theme in DesignTheme.all {
            XCTAssertEqual(combinations.filter { $0.theme == theme }.count, 6)
        }
        for appearance in AppearancePreference.allCases {
            XCTAssertEqual(combinations.filter { $0.appearance == appearance }.count, 6)
        }
        for systemIsDark in Self.systemStates {
            XCTAssertEqual(combinations.filter { $0.systemIsDark == systemIsDark }.count, 9)
        }
    }

    /// **跟随系统这一档，在系统深浅两态下都要过门槛**（每个主题各算一遍；门槛与文档同值）。
    ///
    /// 这一条正是「随系统主题」的全部风险：只测一态时，另一态可能落在浅色白底上看不清的颜色上。
    /// 实现与 `Scripts/check-design-themes.py` 判据 C **各写一份**（判据与被判对象同源是那一族的缝）。
    func testFollowSystemBothStatesClearThresholdsInEveryTheme() {
        for theme in DesignTheme.all {
            for systemIsDark in Self.systemStates {
                let combination = Combination(
                    appearance: .followSystem, systemIsDark: systemIsDark, theme: theme
                )
                let state = systemIsDark ? "深色" : "浅色"
                let label = "\(theme.id)/跟随系统→\(state)"
                let palette = combination.palette

                let content = combination.value(palette.content.light, palette.content.dark)
                func ratio(_ light: UInt32, _ dark: UInt32) -> Double {
                    ColorContrast.ratio(combination.value(light, dark), content)
                }

                XCTAssertGreaterThanOrEqual(
                    ratio(palette.textPrimary.light, palette.textPrimary.dark), thresholds.bodyText,
                    "\(label)：正文（textPrimary）没到 4.5"
                )
                XCTAssertGreaterThanOrEqual(
                    ratio(palette.textSecondary.light, palette.textSecondary.dark), thresholds.bodyText,
                    "\(label)：正文（textSecondary）没到 4.5"
                )
                let bright = ratio(palette.textBright.light, palette.textBright.dark)
                XCTAssertGreaterThanOrEqual(bright, thresholds.strongText, "\(label)：强对比没到 7")
                XCTAssertGreaterThan(
                    bright, ratio(palette.textPrimary.light, palette.textPrimary.dark),
                    "\(label)：textBright 不比正文强，这个名字就没有意义"
                )
                XCTAssertGreaterThanOrEqual(
                    ratio(palette.textTertiary.light, palette.textTertiary.dark), thresholds.largeText,
                    "\(label)：辅助色没到 3.0"
                )

                // 图标线 / 焦点环：深色量对 `window`、浅色量对白（与判据 C 同一口径）
                let reference = combination.isDark ? palette.window.dark : 0xFFFFFF
                for (name, color) in [("accent", palette.accent), ("accentSoft", palette.accentSoft)] {
                    let value = combination.value(color.light, color.dark)
                    let valueRatio = ColorContrast.ratio(value, reference)
                    XCTAssertGreaterThanOrEqual(
                        valueRatio, thresholds.component,
                        "\(label)：图标线 \(name) 在基准底上只有 \(String(format: "%.2f", valueRatio))"
                    )
                }
            }
        }
    }

    /// 两轴组合下**每个组合都取得到值**，且深浅两态**确实是两套值**（不是同一个值被写了两遍）。
    func testEveryCombinationResolvesDistinctValuesPerState() {
        for theme in DesignTheme.all {
            let light = Combination(appearance: .alwaysLight, systemIsDark: true, theme: theme)
            let dark = Combination(appearance: .alwaysDark, systemIsDark: false, theme: theme)
            XCTAssertFalse(light.isDark)
            XCTAssertTrue(dark.isDark)
            let lightSurfaces = [light.palette.window, light.palette.sidebar, light.palette.content,
                                 light.palette.panel, light.palette.raised]
            let darkSurfaces = [dark.palette.window, dark.palette.sidebar, dark.palette.content,
                                dark.palette.panel, dark.palette.raised]
            for (lightColor, darkColor) in zip(lightSurfaces, darkSurfaces) {
                XCTAssertNotEqual(lightColor.light, lightColor.dark, "\(theme.id)：浅色档的两态值相同")
                XCTAssertNotEqual(darkColor.light, darkColor.dark, "\(theme.id)：深色档的两态值相同")
            }
        }
    }
}
