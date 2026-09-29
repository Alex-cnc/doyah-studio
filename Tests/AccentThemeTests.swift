import XCTest
@testable import DoyahCore

/// 强调色主题的单测（FR-EDIT-33）。
///
/// 这里守的主要是**可访问性**与**回退**：三个候选都能选、都能持久化，
/// 且"白字压在实心按钮上"必须过 WCAG AA —— 这是肉眼很难判断、但一测就露的事。
final class AccentThemeTests: XCTestCase {

    // MARK: 候选集合

    /// 2026-09-29（L-80 ㈠）：候选从 3 个变 5 个 —— 新增的两个是**主题配套**的强调色
    /// （豆芽绿 / 玫瑰金）。`all` 现在的用途有两处（见 `AccentTheme.all` 的注释）：
    /// 解析旧配置 + 给"彼此可分辨"这类判据提供全集。
    func testFiveCandidatesWithStableUniqueIdentifiers() {
        XCTAssertEqual(AccentTheme.all.count, 5)
        XCTAssertEqual(Set(AccentTheme.all.map(\.id)).count, 5)
        // id 是持久化用的，写死在这里防止有人顺手改名把用户的选择弄丢
        XCTAssertEqual(
            AccentTheme.all.map(\.id),
            ["whale-blue", "deep-teal", "whale-magenta", "bean-green", "rose-gold"]
        )
    }

    func testEachCandidateHasItsOwnNameKey() {
        XCTAssertEqual(Set(AccentTheme.all.map(\.nameKey)).count, 5)
        XCTAssertEqual(AccentTheme.whaleBlue.nameKey, .accentWhaleBlue)
        XCTAssertEqual(AccentTheme.deepTeal.nameKey, .accentDeepTeal)
        XCTAssertEqual(AccentTheme.whaleMagenta.nameKey, .accentWhaleMagenta)
        XCTAssertEqual(AccentTheme.beanGreen.nameKey, .accentBeanGreen)
        XCTAssertEqual(AccentTheme.roseGold.nameKey, .accentRoseGold)
    }

    /// 两个候选取自 dsh-tui 鲸鱼自身的调色板：品牌同源的证据写进测试，免得日后被"优化"掉。
    func testWhaleColoursComeFromTheTuiPalette() {
        XCTAssertEqual(AccentTheme.whaleBlue.accentHex, 0x4E6FFF)      // B[78,111,255]
        XCTAssertEqual(AccentTheme.whaleMagenta.accentHex, 0xCC3399)   // 心形 H[204,51,153]
    }

    // MARK: 解析与回退

    func testResolveReturnsRequestedTheme() {
        XCTAssertEqual(AccentTheme.resolve(id: "deep-teal"), AccentTheme.deepTeal)
        XCTAssertEqual(AccentTheme.resolve(id: "whale-magenta"), AccentTheme.whaleMagenta)
    }

    /// 没存过 / 存了空串 / 存了未知 id / 存了将来被删掉的 id —— 都必须回退，不能报错也不能崩。
    func testResolveFallsBackInsteadOfFailing() {
        XCTAssertEqual(AccentTheme.resolve(id: nil), AccentTheme.fallback)
        XCTAssertEqual(AccentTheme.resolve(id: ""), AccentTheme.fallback)
        XCTAssertEqual(AccentTheme.resolve(id: "no-such-theme"), AccentTheme.fallback)
        XCTAssertEqual(AccentTheme.fallback, AccentTheme.whaleBlue)
    }

    func testStorageKeyIsNamespacedLikeOtherUIPreferences() {
        XCTAssertEqual(AccentTheme.Storage.key, "ui.accentTheme")
        XCTAssertTrue(AccentTheme.Storage.key.hasPrefix("ui."))
    }

    // MARK: 色值合法性

    func testEveryHexIsAValidOpaqueColour() {
        for theme in AccentTheme.all {
            for hex in [theme.accentHex, theme.fillHex] {
                XCTAssertLessThanOrEqual(hex, 0xFFFFFF, "\(theme.id) 的色值超出 0xRRGGBB")
            }
            let (red, green, blue) = AccentTheme.components(theme.accentHex)
            for component in [red, green, blue] {
                XCTAssertTrue((0...1).contains(component), "\(theme.id) 分量越界")
            }
        }
    }

    func testContrastRatioBasics() {
        // 黑白比为 21，同色比为 1 —— 先确认公式本身没错
        XCTAssertEqual(AccentTheme.contrastRatio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(AccentTheme.contrastRatio(0x4E6FFF, 0x4E6FFF), 1, accuracy: 0.001)
    }

    // MARK: 可访问性（这条是本次真正要守的）

    /// 实心按钮上压白字：**必须 ≥ 4.5**（WCAG AA 正文）。
    ///
    /// 实测背景：直接拿主色当填充时，鲸鱼蓝只有 4.17、深海青只有 3.12 —— 都不够，
    /// 所以才有了 `fillHex` 这一档压暗色。若有人日后把 fill 改回主色，这条会立刻红。
    func testWhiteTextOnSolidFillPassesAA() {
        for theme in AccentTheme.all {
            let ratio = AccentTheme.contrastRatio(0xFFFFFF, theme.fillHex)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "\(theme.id) 的实心填充放白字只有 \(String(format: "%.2f", ratio))，达不到 4.5"
            )
        }
    }

    /// 强调色作为 UI 组件（选中条 / 焦点环 / 图标）与两种表面比：**≥ 3.0** 即可（WCAG 对非文本）。
    ///
    /// 底色取自令牌，不写死十六进制 —— 否则换了配色（方案 D）这里还拿旧底色算，
    /// 判据看着是绿的、其实量的是另一个界面。L-80 ㈠ 起 `Surface` 的取色要带主题，
    /// 这里对**每个主题**都用**它自己的**内容底算一遍（配套强调色必须在自己主题上看得清）。
    func testAccentIsVisibleOnBothSurfacesInEveryTheme() {
        for theme in DesignTheme.all {
            let darkContent = Surface.content.color(in: theme).dark
            let lightContent = Surface.content.color(in: theme).light
            for accent in AccentTheme.all {
                let onDark = AccentTheme.contrastRatio(accent.accentHex, darkContent)
                let onLight = AccentTheme.contrastRatio(accent.accentHex, lightContent)
                XCTAssertGreaterThanOrEqual(onDark, 3.0, "\(accent.id) 在 \(theme.id) 深色底上只有 \(String(format: "%.2f", onDark))")
                XCTAssertGreaterThanOrEqual(onLight, 3.0, "\(accent.id) 在 \(theme.id) 浅色底上只有 \(String(format: "%.2f", onLight))")
            }
        }
    }

    /// 三个候选必须**彼此可分辨**，否则"看样张再定"这件事就没有意义。
    func testCandidatesAreDistinguishableFromEachOther() {
        let themes = AccentTheme.all
        for i in 0..<themes.count {
            for j in (i + 1)..<themes.count {
                let a = AccentTheme.components(themes[i].accentHex)
                let b = AccentTheme.components(themes[j].accentHex)
                let distance = sqrt(
                    pow(a.red - b.red, 2) + pow(a.green - b.green, 2) + pow(a.blue - b.blue, 2)
                )
                XCTAssertGreaterThan(distance, 0.3, "\(themes[i].id) 与 \(themes[j].id) 太接近")
            }
        }
    }
}
