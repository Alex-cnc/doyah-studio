import XCTest
@testable import DoyahCore

/// 主题（配色方案）的单测 —— FR-EDIT-33 扩写 · 队列 L-80 ㈠。
///
/// 这里守三件事：
///   ① **主题集本身**（有几个、id / 显示名稳不稳、未知 id 怎么回退、哪个是默认）；
///   ② **每套值表的门槛**（`DesignTokensTests` 已逐角色守过对比度，这里守"三套表都真的在、
///      都互不相同、推导状态标注正确"这类结构性问题）；
///   ③ **主题与配套强调色的绑定**（选中态 / 主按钮 / 焦点环必须与主题同色相，
///      而且要在**这一主题自己的**表面与填充上过关）。
final class DesignThemeTests: XCTestCase {

    private let thresholds = ColorContrast.Threshold.self

    // MARK: 主题集

    func testFourThemesWithStableUniqueIdentifiers() {
        XCTAssertEqual(DesignTheme.all.count, 4)
        XCTAssertEqual(Set(DesignTheme.all.map(\.id)).count, 4)
        // id 是持久化用的（`ui.designTheme`），写死在这里防止有人顺手改名把用户的选择弄丢
        XCTAssertEqual(DesignTheme.all.map(\.id), ["tech-blue", "stardust", "bean-green", "rose-gold"])
        // 与 Linux 侧同名的三个主题（需求提出者给的名：科技蓝 / 豆芽绿 / 玫瑰金）
        XCTAssertEqual(DesignTheme.all[0], .techBlue, "科技蓝是默认值，排在第一个")
        XCTAssertEqual(DesignTheme.fallback, .techBlue)
    }

    func testEachThemeHasItsOwnNameKey() {
        XCTAssertEqual(Set(DesignTheme.all.map(\.nameKey)).count, 4)
        XCTAssertEqual(DesignTheme.techBlue.nameKey, .designThemeTechBlue)
        XCTAssertEqual(DesignTheme.beanGreen.nameKey, .designThemeBeanGreen)
        XCTAssertEqual(DesignTheme.roseGold.nameKey, .designThemeRoseGold)
        XCTAssertEqual(DesignTheme.stardust.nameKey, .designThemeStardust)
        // 名字必须是**双语都在**的（缺一条就会出现英文界面上露出中文主题名）
        for theme in DesignTheme.all {
            let table = LocalizedStrings.table[theme.nameKey]
            XCTAssertNotNil(table?[.simplifiedChinese], "\(theme.id) 缺中文名")
            XCTAssertNotNil(table?[.english], "\(theme.id) 缺英文名")
        }
    }

    /// 没存过 / 存了空串 / 存了未知 id / 存了将来被删掉的主题 —— 都必须回退，不能报错也不能崩。
    func testResolveFallsBackInsteadOfFailing() {
        XCTAssertEqual(DesignTheme.resolve(id: "bean-green"), DesignTheme.beanGreen)
        XCTAssertEqual(DesignTheme.resolve(id: "rose-gold"), DesignTheme.roseGold)
        XCTAssertEqual(DesignTheme.resolve(id: nil), DesignTheme.fallback)
        XCTAssertEqual(DesignTheme.resolve(id: ""), DesignTheme.fallback)
        XCTAssertEqual(DesignTheme.resolve(id: "no-such-theme"), DesignTheme.fallback)
    }

    func testStorageKeyIsNamespacedLikeOtherUIPreferences() {
        XCTAssertEqual(DesignTheme.Storage.key, "ui.designTheme")
        XCTAssertTrue(DesignTheme.Storage.key.hasPrefix("ui."))
    }

    /// **待值是待值**：Linux 侧实际色值未到的两个主题必须如实标出来（界面据此显示「待值」）。
    /// 收到实际值后这条测试连同标注一起改 —— 不许把推导值当实际值卖。
    func testDerivationStatusIsHonest() {
        XCTAssertFalse(DesignTheme.techBlue.isDerivedDraft, "科技蓝 = 外观方案 D 的实际值")
        XCTAssertTrue(DesignTheme.beanGreen.isDerivedDraft)
        XCTAssertTrue(DesignTheme.roseGold.isDerivedDraft)
        // 星空紫 = 需求提出者给的观感（NASA 韦伯「宇宙悬崖」取色）⇒ **是实际值**，不是推导草案
        XCTAssertFalse(DesignTheme.stardust.isDerivedDraft,
                       "星空紫的值来自需求提出者给的观感，在界面上标「推导草案」就是说假话")
    }

    // MARK: 四套值表

    /// 四套表都要真的存在、id 对得上，且**互不相同**（防"复制一份改了名字"）。
    func testEveryThemeHasItsOwnPalette() {
        var seen: Set<String> = []
        for theme in DesignTheme.all {
            let palette = theme.palette
            XCTAssertEqual(palette.id, theme, "\(theme.id) 的值表 id 对不上")
            let signature = [
                palette.window.dark, palette.content.dark, palette.textPrimary.dark, palette.accent.dark
            ].map { String($0, radix: 16) }.joined(separator: "-")
            XCTAssertFalse(seen.contains(signature), "\(theme.id) 的值表与另一个主题逐值相同")
            seen.insert(signature)
        }
    }

    /// 每个主题的**表面五档 + 文本五档**必须同色相（这里用"色相不能跨太大"的粗判：
    /// 深色表面的蓝分量与绿分量不该反着来 —— 科技蓝 B>G、豆芽绿 G>B、玫瑰金 R>G）。
    /// 这条守的是"把某一档从别的主题复制过来"这种手滑。
    func testEachThemeKeepsItsOwnHueOnDarkSurfaces() {
        let darkContent = DesignTheme.techBlue.palette.content.dark
        let beanContent = DesignTheme.beanGreen.palette.content.dark
        let roseContent = DesignTheme.roseGold.palette.content.dark
        // 科技蓝：蓝最重
        XCTAssertGreaterThan(darkContent & 0xFF, (darkContent >> 8) & 0xFF, "科技蓝的深色底应当偏蓝")
        // 豆芽绿：绿最重
        XCTAssertGreaterThan((beanContent >> 8) & 0xFF, (beanContent >> 16) & 0xFF, "豆芽绿的深色底应当偏绿")
        XCTAssertGreaterThan((beanContent >> 8) & 0xFF, beanContent & 0xFF, "豆芽绿的深色底应当偏绿")
        // 玫瑰金：红最重（暖）
        XCTAssertGreaterThan((roseContent >> 16) & 0xFF, roseContent & 0xFF, "玫瑰金的深色底应当偏暖")
    }

    /// 状态色的**色相不随主题漂移**（成功是绿、警告是黄、危险是红）——
    /// 语义色跟着主题换色相会把它变成装饰，用户就认不出"这是哪一类状态"了。
    func testStatusHuesDoNotDriftAcrossThemes() {
        for tone in StatusTone.allCases {
            let reference = tone.color(in: .techBlue)
            for theme in DesignTheme.all {
                XCTAssertEqual(
                    tone.color(in: theme).light, reference.light,
                    "\(theme.id) 的 \(tone.rawValue) 浅色档脱离了其它主题"
                )
                XCTAssertEqual(
                    tone.color(in: theme).dark, reference.dark,
                    "\(theme.id) 的 \(tone.rawValue) 深色档脱离了其它主题"
                )
            }
        }
    }

    /// 三套表的**每个角色**都必须过同一套门槛 —— 这是"三选一"能成立的前提。
    /// （`DesignTokensTests` 逐条守对比度；这里补一条汇总性的：每主题每态里，
    /// **所有前景角色**在内容底上都不得低于 1.5 的"看得见"下限。）
    ///
    /// 表面五档不在这条判据里：浅色态下 `content` 与 `raised` **同为白**是**有意的**
    /// （浮层靠发丝线 / 阴影区分，见 `Surface` 的注释）⇒ 拿表面跟内容底比对比度是量错了东西。
    /// 表面之间的"可分辨"由 `DesignTokensTests` 的距离判据（≥0.02）单独守。
    func testEveryForegroundRoleInEveryThemeClearsTheVisibilityFloor() {
        for theme in DesignTheme.all {
            for isDark in [true, false] {
                let surface = Surface.content.color(in: theme).hex(dark: isDark)
                var roles: [ThemeColor] = TextTone.allCases.map { $0.color(in: theme) }
                roles += StatusTone.allCases.map { $0.color(in: theme) }
                roles += AccentFamily.allCases.map { $0.color(in: theme) }
                roles += SyntaxTone.allCases.map { $0.color(in: theme) }
                for role in roles {
                    let ratio = ColorContrast.ratio(role.hex(dark: isDark), surface)
                    XCTAssertGreaterThanOrEqual(
                        ratio, 1.5,
                        "\(theme.id) 的\(isDark ? "深色" : "浅色")态里有个前景角色在内容底上几乎看不见（\(String(format: "%.2f", ratio))）"
                    )
                }
            }
        }
    }

    // MARK: 与配套强调色的绑定

    /// 每个主题都配一个**同色相**的交互强调色，且这个强调色在这一主题自己的两态表面上
    /// 都过"非文本组件 ≥3.0"的门槛 —— 否则"豆芽绿主题"的选中条会在它自己的底上看不清。
    func testEachThemeHasAMatchingAccentVisibleOnItsOwnSurfaces() {
        for theme in DesignTheme.all {
            let accent = theme.accent
            for isDark in [true, false] {
                for surface in [Surface.content, .panel] {
                    let ratio = ColorContrast.ratio(accent.accentHex, surface.color(in: theme).hex(dark: isDark))
                    XCTAssertGreaterThanOrEqual(
                        ratio, thresholds.component,
                        "\(theme.id) 的配套强调色 \(accent.id) 在它自己的 \(surface.rawValue)（\(isDark ? "深色" : "浅色")）上只有 \(String(format: "%.2f", ratio))"
                    )
                }
            }
        }
    }

    /// 主题配套强调色就是 `AccentTheme` 里那几个同名候选（不是另造一份色值）——
    /// 这样「外观」面板里选主题 = 选中态 / 主按钮 / 焦点环一起换，两条轴不会各说各话。
    func testThemeAccentIsOneOfTheAccentCandidates() {
        for theme in DesignTheme.all {
            XCTAssertTrue(
                AccentTheme.all.contains(where: { $0.id == theme.accent.id }),
                "\(theme.id) 的配套强调色 \(theme.accent.id) 不在候选里"
            )
        }
        XCTAssertEqual(DesignTheme.techBlue.accent.id, "whale-blue", "科技蓝的配套值 = 鲸鱼蓝（与 App 图标同源，现状零变化）")
        XCTAssertEqual(DesignTheme.beanGreen.accent.id, "bean-green")
        XCTAssertEqual(DesignTheme.roseGold.accent.id, "rose-gold")
    }
}
