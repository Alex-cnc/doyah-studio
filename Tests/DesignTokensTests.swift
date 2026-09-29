import XCTest
@testable import DoyahCore

/// 设计令牌的单测。
///
/// 这一层的价值不在"存了几个数字"，而在**它把品味变成了可校验的约束**：
/// 间距必须在刻度上、表面之间必须能被看出来是两块、文字必须够对比度。
/// 这些都是肉眼容易放过、但一旦放过就会累积成"看着不精致"的东西。
///
/// 2026-09-29（L-80 ㈠）：令牌值按**主题**分组（`Core/DesignTheme.swift`）⇒
/// **每一条不变式都对 `DesignTheme.all` 里的每个主题跑一遍**，而不是只看默认主题。
/// 这是"三选一"这件事真正要守的地方：新增一个主题只要有一档不过门槛，这里当场红。
final class DesignTokensTests: XCTestCase {

    private let thresholds = ColorContrast.Threshold.self

    // MARK: 刻度

    func testSpacingIsOnTheFourEightGrid() {
        XCTAssertEqual(Spacing.scale, [2, 4, 8, 12, 16, 24, 32])
        // 除了 hair（图标与文字紧贴），其余都必须是 4 的倍数
        for value in Spacing.scale where value != Spacing.hair {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) 不在 4 的倍数上")
        }
        XCTAssertTrue(Spacing.isOnScale(Spacing.l))
        XCTAssertFalse(Spacing.isOnScale(150), "曾经出现过 150 这种裸数字")
        XCTAssertFalse(Spacing.isOnScale(3), "曾经出现过 3 这种裸数字")
    }

    func testRadiusScaleIsFixed() {
        XCTAssertEqual(Radius.scale, [1, 4, 6, 8, 10])
    }

    func testTypeScaleHasRealHierarchy() {
        XCTAssertEqual(TypeScale.scale, [11, 12, 13, 15, 17])
        // 级差必须单调递增，否则不叫"级差"
        let sorted = TypeScale.scale.sorted()
        XCTAssertEqual(TypeScale.scale, sorted)
        XCTAssertFalse(TypeScale.isOnScale(14), "14 不属于任何一级（改造前出现过）")
        // 每个命名常量都必须在刻度上（否则刻度形同虚设）
        for named in [TypeScale.captionSize, TypeScale.dataSize, TypeScale.monoSize,
                      TypeScale.monoSmallSize, TypeScale.bodySize, TypeScale.titleSize, TypeScale.displaySize] {
            XCTAssertTrue(TypeScale.isOnScale(named), "\(named) 不在字号刻度上")
        }
    }

    /// 度量值被**钉住**：改这些数字是设计决策，必须连同测试一起改，不能顺手漂移。
    func testMetricsArePinned() {
        XCTAssertEqual(Metrics.hairline, 0.5)
        XCTAssertEqual(Metrics.rowHeight, 26)          // 紧凑但留白严格
        XCTAssertEqual(Metrics.toolbarHeight, 44)
        XCTAssertEqual(Metrics.statusBarHeight, 24)
        XCTAssertEqual(Metrics.activityBarWidth, 46)   // FR-EDIT-32
        XCTAssertEqual(Metrics.sidebarWidth, 248)
    }

    // MARK: 表面层次（改造中修掉过两次真缺陷，这里守住）

    /// 内容区与侧栏必须能被看出来是两块 —— 第一版只差 3/255，等于没有层次。
    func testContentAndSidebarAreDistinguishableInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let content = Surface.content.color(in: theme).hex(dark: isDark)
                let sidebar = Surface.sidebar.color(in: theme).hex(dark: isDark)
                let distance = ColorContrast.distance(content, sidebar)
                XCTAssertGreaterThanOrEqual(
                    distance, thresholds.surfaceSeparation,
                    "\(theme.id) 的\(isDark ? "深色" : "浅色")态里内容区与侧栏太接近（距离 \(String(format: "%.3f", distance))）"
                )
            }
        }
    }

    func testPanelAndWindowAreDistinguishableFromContentInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let content = Surface.content.color(in: theme).hex(dark: isDark)
                for surface in [Surface.panel, .window] {
                    let distance = ColorContrast.distance(content, surface.color(in: theme).hex(dark: isDark))
                    XCTAssertGreaterThanOrEqual(
                        distance, thresholds.surfaceSeparation,
                        "\(theme.id) 的\(isDark ? "深色" : "浅色")态里 \(surface.rawValue) 与内容区太接近"
                    )
                }
            }
        }
    }

    /// 深色主题靠**明度递增**表达层次：window < sidebar < content < panel < raised。
    func testDarkSurfacesRiseInLightnessInEveryTheme() {
        let order: [Surface] = [.window, .sidebar, .content, .panel, .raised]
        for theme in DesignTheme.all {
            let luminances = order.map { ColorContrast.relativeLuminance($0.color(in: theme).dark) }
            for index in 1..<luminances.count {
                XCTAssertGreaterThan(
                    luminances[index], luminances[index - 1],
                    "\(theme.id) 的深色态里 \(order[index].rawValue) 不比 \(order[index - 1].rawValue) 亮"
                )
            }
        }
    }

    /// 浅色主题的不变式不同：**内容区是最亮的**（面板与浮层靠描边 / 阴影区分，不靠更亮）。
    func testLightContentIsTheBrightestSurfaceInEveryTheme() {
        for theme in DesignTheme.all {
            let content = ColorContrast.relativeLuminance(Surface.content.color(in: theme).light)
            for surface in Surface.allCases where surface != .content {
                XCTAssertLessThanOrEqual(
                    ColorContrast.relativeLuminance(surface.color(in: theme).light), content,
                    "\(theme.id) 的浅色态里 \(surface.rawValue) 比内容区还亮"
                )
            }
        }
    }

    // MARK: 对比度（这一层真正要守的）

    /// 正文与次要信息：WCAG AA 4.5。
    func testBodyAndSecondaryTextPassAAOnContentInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let background = Surface.content.color(in: theme).hex(dark: isDark)
                for tone in [TextTone.primary, .secondary] {
                    let ratio = ColorContrast.ratio(tone.color(in: theme).hex(dark: isDark), background)
                    XCTAssertGreaterThanOrEqual(
                        ratio, thresholds.bodyText,
                        "\(theme.id) 的\(isDark ? "深色" : "浅色")态里 \(tone.rawValue) 只有 \(String(format: "%.2f", ratio))"
                    )
                }
            }
        }
    }

    /// 辅助信息（表头 / 行号）：按**非文本组件**的 3.0 守 —— 它刻意比正文轻，
    /// 但要能看清。
    func testTertiaryTextStaysReadableInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let background = Surface.content.color(in: theme).hex(dark: isDark)
                let ratio = ColorContrast.ratio(TextTone.tertiary.color(in: theme).hex(dark: isDark), background)
                XCTAssertGreaterThanOrEqual(
                    ratio, thresholds.largeText,
                    "\(theme.id) 的\(isDark ? "深色" : "浅色")态里辅助文字只有 \(String(format: "%.2f", ratio))"
                )
            }
        }
    }

    /// 禁用态：WCAG 不要求它达 AA（非活动控件），但**不能淡到看不见**，
    /// 且必须比三级文本更淡 —— 这条顺序反了就会出现"能用的按钮看起来是禁用的"。
    func testDisabledTextIsDimmerThanTertiaryButStillVisibleInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let background = Surface.content.color(in: theme).hex(dark: isDark)
                let disabled = ColorContrast.ratio(TextTone.disabled.color(in: theme).hex(dark: isDark), background)
                let tertiary = ColorContrast.ratio(TextTone.tertiary.color(in: theme).hex(dark: isDark), background)
                XCTAssertLessThan(disabled, tertiary, "\(theme.id) 的\(isDark ? "深色" : "浅色")态：禁用态应比三级文本淡")
                XCTAssertGreaterThanOrEqual(disabled, 1.5, "\(theme.id) 的\(isDark ? "深色" : "浅色")态：禁用态淡到看不见了")
            }
        }
    }

    /// 状态色主要用作状态点（非文本组件）→ 3.0。
    func testStatusColoursAreVisibleOnBothSurfacesInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                for background in [Surface.content, .panel] {
                    let hex = background.color(in: theme).hex(dark: isDark)
                    for tone in StatusTone.allCases {
                        let ratio = ColorContrast.ratio(tone.color(in: theme).hex(dark: isDark), hex)
                        XCTAssertGreaterThanOrEqual(
                            ratio, thresholds.component,
                            "\(theme.id) 的\(isDark ? "深色" : "浅色")态里 \(tone.rawValue) 在 \(background.rawValue) 上只有 \(String(format: "%.2f", ratio))"
                        )
                    }
                }
            }
        }
    }

    /// 代码要在编辑器里读得下去：除注释外都按正文 4.5 守。
    func testSyntaxColoursAreReadableOnContentInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let background = Surface.content.color(in: theme).hex(dark: isDark)
                for tone in SyntaxTone.allCases {
                    let ratio = ColorContrast.ratio(tone.color(in: theme).hex(dark: isDark), background)
                    let required = tone == .comment ? thresholds.largeText : thresholds.bodyText
                    XCTAssertGreaterThanOrEqual(
                        ratio, required,
                        "\(theme.id) 的\(isDark ? "深色" : "浅色")态里 \(tone.rawValue) 只有 \(String(format: "%.2f", ratio))（需 ≥ \(required)）"
                    )
                }
            }
        }
    }

    /// 关键词与字符串、数字与函数之间必须分得开 —— 语法着色"糊成一片"就等于没有。
    func testSyntaxColoursAreDistinctFromEachOtherInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let tones = SyntaxTone.allCases
                for i in 0..<tones.count {
                    for j in (i + 1)..<tones.count {
                        // identifier 就是正文色，与其它色当然不同；这里只要求"不完全相同"
                        let a = tones[i].color(in: theme).hex(dark: isDark)
                        let b = tones[j].color(in: theme).hex(dark: isDark)
                        XCTAssertNotEqual(a, b, "\(theme.id)：\(tones[i].rawValue) 与 \(tones[j].rawValue) 用了同一个颜色")
                    }
                }
            }
        }
    }

    // MARK: 与强调色的边界

    /// 选中态与斑马纹的透明度必须在一个"看得出但不糊"的区间里。
    ///
    /// 这条守的是手滑：写成 0.4 会让选中行糊成一块，写成 0.02 又完全看不出，
    /// 而这两种都不会有任何编译错误或崩溃 —— 只能靠断言。
    func testOverlayAlphasAreInASaneRange() {
        for alpha in [Overlay.Selection.darkAlpha, Overlay.Selection.lightAlpha] {
            XCTAssertGreaterThanOrEqual(alpha, 0.06, "选中淡填充太淡，看不出来")
            XCTAssertLessThanOrEqual(alpha, 0.20, "选中淡填充太重，会糊成一块")
        }
        // 浅色底的对比本来就弱，浅色档的透明度应当**不高于**深色档
        XCTAssertLessThanOrEqual(Overlay.Selection.lightAlpha, Overlay.Selection.darkAlpha)
        for alpha in [Overlay.Zebra.darkAlpha, Overlay.Zebra.lightAlpha] {
            XCTAssertGreaterThan(alpha, 0, "斑马纹不能为 0（等于没有）")
            XCTAssertLessThanOrEqual(alpha, 0.06, "斑马纹太重会像表格有底色")
        }
    }

    func testResultColumnWidthBoundsAreSane() {
        XCTAssertLessThan(Metrics.minColumnWidth, Metrics.maxColumnWidth)
        XCTAssertGreaterThanOrEqual(Metrics.minColumnWidth, 24, "太窄会把列头截没")
        XCTAssertGreaterThan(Metrics.columnWidthSampleRows, 0)
    }

    /// 分类色必须**彼此可分辨**（徽标的任务就是一眼区分引擎），
    /// 且引擎映射是稳定的数据（改它等于改用户认引擎的方式）。
    ///
    /// L-80 ㈠ 补一条：分类色**不随主题变**（它是身份色，见 `CategoricalTone` 的注释）——
    /// 这条断言是"有人顺手把它挂到主题上"的当场报红。
    func testCategoricalTonesAreDistinctAndMapped() {
        for isDark in [true, false] {
            let hexes = CategoricalTone.allCases.map { $0.color.hex(dark: isDark) }
            XCTAssertEqual(Set(hexes).count, hexes.count, "分类色有重复")
            for i in 0..<hexes.count {
                for j in (i + 1)..<hexes.count {
                    XCTAssertGreaterThan(
                        ColorContrast.distance(hexes[i], hexes[j]), 0.05,
                        "\(CategoricalTone.allCases[i]) 与 \(CategoricalTone.allCases[j]) 太接近"
                    )
                }
            }
        }
        XCTAssertEqual(DatabaseType.postgresql.identityTone, .blue)
        XCTAssertEqual(DatabaseType.gbase8a.identityTone, .amber)
        XCTAssertNotEqual(DatabaseType.postgresql.identityTone, DatabaseType.gbase8a.identityTone)
    }

    /// 强调色**不属于**令牌层：它由用户配置（`AccentTheme`）。
    /// 这条测试是防"有人图省事把强调色写死进 DesignTokens"。
    ///
    /// L-80 ㈠ 起要**逐主题**判：三套表都不能藏着某个强调色的值。
    func testAccentIsNotHardCodedInTokens() {
        for theme in DesignTheme.all {
            let tokenHexes = Set(
                Surface.allCases.map { $0.color(in: theme).light }
                    + Surface.allCases.map { $0.color(in: theme).dark }
                    + TextTone.allCases.map { $0.color(in: theme).light }
                    + TextTone.allCases.map { $0.color(in: theme).dark }
            )
            for accent in AccentTheme.all {
                XCTAssertFalse(
                    tokenHexes.contains(accent.accentHex),
                    "\(accent.id) 被写死进了 \(theme.id) 的令牌层"
                )
            }
        }
    }

    // MARK: 外观方案 D · 科技蓝（2026-09-29 登记，落地 = L-79；L-80 起是**默认主题**）

    /// 方案 D 的**关键值**先钉住几处（全量值见 `Docs/design/外观方案-v1.md` §8，那是文档侧的出处；
    /// 这里只钉"改了要说一声"的几处，理由同 `testMetricsArePinned`）。
    ///
    /// 为什么只钉几处：令牌层的值是**唯一来源**，逐条抄一遍进测试等于把同一份数字写两遍
    /// （L-55 的纪律）；钉住的是**身份值**（深色底、强调色、青绿 / 暖色点缀）——
    /// 它们一改就是"换了一个方案"，不是微调。
    func testTechBlueIdentityValuesArePinned() {
        let techBlue = DesignTheme.techBlue
        XCTAssertEqual(Surface.window.color(in: techBlue).dark, 0x02070A, "方案 D 的窗口底（§8.1）")
        XCTAssertEqual(Surface.content.color(in: techBlue).dark, 0x0B1A2A, "方案 D 的内容底（§8.1）")
        XCTAssertEqual(TextTone.primary.color(in: techBlue).dark, 0xCAD0DC, "方案 D 的正文（§8.2）")
        XCTAssertEqual(AccentFamily.accent.color(in: techBlue).dark, 0x6EA8D0, "方案 D 的强调色（§8.3）")
        XCTAssertEqual(AccentFamily.teal.color(in: techBlue).dark, 0x94E2F8, "方案 D 的青绿点缀（§8.3）")
        XCTAssertEqual(AccentFamily.warm.color(in: techBlue).dark, 0xC7AF95, "方案 D 的暖色点缀（§8.3）")
        XCTAssertEqual(TextTone.primary.color(in: techBlue).light, 0x10243D, "方案 D 的浅色正文（§8.5）")
    }

    /// §8.6 的门槛是**产品要求**：正文 ≥4.5 / **强对比 ≥7** / 图标线 ≥3，**深浅两态都要过**。
    /// L-80 ㈠ 起这条对**每个主题**都成立（"三选一"不能有一个选项偷偷不过门槛）。
    func testStrongContrastTierHoldsInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let content = Surface.content.color(in: theme).hex(dark: isDark)
                let bright = TextTone.bright.color(in: theme).hex(dark: isDark)
                let ratio = ColorContrast.ratio(bright, content)
                XCTAssertGreaterThanOrEqual(
                    ratio, thresholds.strongText,
                    "\(theme.id) 的\(isDark ? "深色" : "浅色")态里标题 / 关键数值只有 \(String(format: "%.2f", ratio))（需 ≥ \(thresholds.strongText)）"
                )
                // 标题比正文更强 —— 否则"bright"这个名字没有意义
                XCTAssertGreaterThan(
                    ratio,
                    ColorContrast.ratio(TextTone.primary.color(in: theme).hex(dark: isDark), content)
                )
            }
        }
    }

    /// 强调色家族按 §8.3 写明**各自的用途**分别守：
    /// `accentGlow` / `teal` / `warm` 会落到文字与链接上（≥4.5）；`accent` / `accentSoft`
    /// 是非文本组件（≥3.0，且 §8.3 明写 `accentSoft`"只够图标线，不得用于正文"）。
    func testAccentFamilyMeetsItsDocumentedRolesInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                // §8.2 / §8.5 的对比度基准：深色对 `window`、浅色对白底
                let base = isDark ? Surface.window.color(in: theme).dark : 0xFFFFFF
                for tone in [AccentFamily.accentGlow, .teal, .warm] {
                    let ratio = ColorContrast.ratio(tone.color(in: theme).hex(dark: isDark), base)
                    XCTAssertGreaterThanOrEqual(
                        ratio, thresholds.bodyText,
                        "\(theme.id) 的\(isDark ? "深色" : "浅色")态里 \(tone.rawValue) 做文字 / 链接只有 \(String(format: "%.2f", ratio))"
                    )
                }
                for tone in [AccentFamily.accent, .accentSoft] {
                    let ratio = ColorContrast.ratio(tone.color(in: theme).hex(dark: isDark), base)
                    XCTAssertGreaterThanOrEqual(
                        ratio, thresholds.component,
                        "\(theme.id) 的\(isDark ? "深色" : "浅色")态里 \(tone.rawValue) 做图标线只有 \(String(format: "%.2f", ratio))"
                    )
                }
            }
        }
    }

    /// 语法色六档**按角色**挂在令牌家族上（§8.4 的六档就是 §8.1~8.3 的角色表）。
    /// 这条是防回潮：谁把某个语法色改回硬编码的十六进制，六档就会与家族脱钩 —— 当场报红。
    func testSyntaxTonesAreBoundToAccentFamilyRolesInEveryTheme() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                func hex(_ color: ThemeColor) -> UInt32 { color.hex(dark: isDark) }
                XCTAssertEqual(hex(SyntaxTone.keyword.color(in: theme)), hex(AccentFamily.accentGlow.color(in: theme)))
                XCTAssertEqual(hex(SyntaxTone.string.color(in: theme)), hex(AccentFamily.warm.color(in: theme)))
                XCTAssertEqual(hex(SyntaxTone.number.color(in: theme)), hex(AccentFamily.teal.color(in: theme)))
                XCTAssertEqual(hex(SyntaxTone.function.color(in: theme)), hex(AccentFamily.accent.color(in: theme)))
                XCTAssertEqual(hex(SyntaxTone.identifier.color(in: theme)), hex(TextTone.primary.color(in: theme)))
                XCTAssertEqual(hex(SyntaxTone.comment.color(in: theme)), hex(TextTone.tertiary.color(in: theme)))
            }
        }
    }

    /// 发丝线：深色 = 白 10%（§8.1），浅色 = 各主题自己的实色。
    /// 浅色这一处是**唯一**不用"透明度叠加"的发丝线，故把值钉住并写明出处。
    func testHairlineFollowsTheTheme() {
        XCTAssertEqual(Hairline.darkAlpha(in: .techBlue), 0.10, "方案 D §8.1：白 10%")
        XCTAssertEqual(Hairline.lightHex(in: .techBlue), 0xD3DCE8, "方案 D §8.5：浅色实色")
        for theme in DesignTheme.all {
            // 浅色实色必须比它要分隔的 content 暗 —— 亮的线在白底上等于没有
            XCTAssertLessThan(
                ColorContrast.relativeLuminance(Hairline.lightHex(in: theme)),
                ColorContrast.relativeLuminance(Surface.content.color(in: theme).light),
                "\(theme.id) 的浅色发丝线不比 content 暗"
            )
            // 深色透明度必须在一个"看得见但不刺眼"的区间里
            let alpha = Hairline.darkAlpha(in: theme)
            XCTAssertGreaterThanOrEqual(alpha, 0.05, "\(theme.id) 的深色发丝线太淡")
            XCTAssertLessThanOrEqual(alpha, 0.20, "\(theme.id) 的深色发丝线太重")
        }
    }
}
