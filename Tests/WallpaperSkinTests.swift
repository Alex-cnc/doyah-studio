import XCTest
@testable import DoyahCore

/// 「壁纸皮肤」的**值表与规则单测**（第 5 套主题「深空苍穹」落地件 · 人类主人 2026-10-16 选定档 3）。
///
/// ## 为什么这层必须机器判
///
/// 照片当背景之后，「文字压在什么颜色上」取决于照片的像素 —— 这是**整条令牌链路里第一次**
/// 出现"表面不是一个定值颜色"的情况。要让它仍然可判、可复算，做法只有一条：
/// **两层数字都写死**（蒙版浓度 + 每个表面的不透明度），并且**逐字钉在判据里**。
/// 于是：谁想调松观感（把面板调到 0.2、把蒙版最松那档调到 0.1），改值表的那一刻这几条就红，
/// 而不是等用户在某台机器上发现"白天的天空把字冲没了"。
///
/// ## 判什么 / 不判什么（边界如实登记）
///
/// - **判**：哪几个主题有壁纸 / 蒙版四段的位置与浓度 / 每个表面的不透明度与它们之间的次序 /
///   开关的键与缺省值 / 「关掉之后重开还是关」/ 生效条件（主题声明 ∧ 开关）；
/// - **不判**（下一片，如实登记）：① 资源文件**真的在包里**（`App/Resources/*.jpg` ↔ 值表里的名字）
///   —— 归静态判据；② **像素级**的有效底色（拿资源实测最亮处 × 蒙版 × 面板不透明度，
///   算出的对比度是否守住文字门槛）—— 归离屏探针 / 脚本。本族只钉住"输入的那两个数字"。
final class WallpaperSkinTests: XCTestCase {

    /// 单独的 suite：测试进程自己的域，与 App 的偏好无关。
    private let suiteName = "studio.doyah.tests.wallpaper-skin"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - ① 谁有壁纸：由主题声明，不是写死在绘制侧

    func testOnlyThemesThatDeclareAWallpaperHaveOne() {
        for theme in DesignTheme.allCases {
            switch theme {
            case .deepSpace:
                XCTAssertNotNil(theme.wallpaper, "深空苍穹必须声明壁纸（人类主人 2026-10-16 选定档 3）")
            case .techBlue, .beanGreen, .roseGold, .stardust:
                XCTAssertNil(theme.wallpaper, "\(theme.rawValue) 没声明壁纸 ⇒ 不许透出照片")
            }
        }
    }

    /// 资源名跟随主题：一个主题一张照片。想做第二张，是给那个主题加一份值表，不是在这里加分支。
    func testAssetNameFollowsTheTheme() {
        XCTAssertEqual(WallpaperSkin.assetName(for: .deepSpace), "wallpaper-deep-space")
        XCTAssertNil(WallpaperSkin.assetName(for: .techBlue))
    }

    // MARK: - ② 蒙版：四段、位置递增、首尾就是 0 与 1

    func testMaskStopsAreOrderedAndInRange() throws {
        let stops = try XCTUnwrap(DesignTheme.deepSpace.wallpaper).maskStops
        XCTAssertEqual(stops.count, 4, "交付的是四段蒙版（上 / 中上 / 中下 / 下）")
        XCTAssertEqual(try XCTUnwrap(stops.first).location, 0, accuracy: 0.0001, "第一段必须贴住窗口顶边")
        XCTAssertEqual(try XCTUnwrap(stops.last).location, 1, accuracy: 0.0001, "最后一段必须贴住窗口底边")
        for (previous, next) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThan(previous.location, next.location, "位置必须严格递增：\(previous.location) → \(next.location)")
        }
        for stop in stops {
            XCTAssertTrue((0...1).contains(stop.location), "位置越界：\(stop.location)")
            XCTAssertTrue((0...1).contains(stop.alpha), "浓度越界：\(stop.alpha)")
        }
    }

    /// 蒙版**最松**的那一档不许低于下限 —— 「照片最亮处压在它下面时，字还要能读」的机械代理。
    ///
    /// 0.24 这个下限的来历：档 3 就是这么定的（人类主人选的效果图），再松一档（0.16）在
    /// 天际线那一条上已经开始吃掉正文对比度。真要往下松，得同时改这一条并说明为什么。
    func testWeakestMaskStopKeepsAFloor() throws {
        let spec = try XCTUnwrap(DesignTheme.deepSpace.wallpaper)
        XCTAssertGreaterThanOrEqual(spec.weakestMaskAlpha, 0.24,
                                   "蒙版最松那档低于下限 ⇒ 照片最亮处会顶穿文字")
    }

    // MARK: - ③ 表面不透明度：每个角色都有定值、有下限、次序合理

    func testEverySurfaceHasAFixedOpacityAboveTheFloor() throws {
        let spec = try XCTUnwrap(DesignTheme.deepSpace.wallpaper)
        for surface in Surface.allCases {
            let opacity = spec.opacity(of: surface)
            XCTAssertGreaterThanOrEqual(opacity, 0.28,
                                       "\(surface.rawValue) 的不透明度低于下限 ⇒ 文字发飘")
            XCTAssertLessThanOrEqual(opacity, 1, "\(surface.rawValue) 的不透明度不许超过 1")
        }
    }

    /// 次序：阅读区（content）**比 chrome（panel）实**；浮起来的东西（raised）最实 ——
    /// 长注视的地方要稳，一栏一栏的壳可以更"玻璃"，浮层离照片最远。
    func testReadingSurfacesAreMoreSolidThanChrome() throws {
        let spec = try XCTUnwrap(DesignTheme.deepSpace.wallpaper)
        XCTAssertGreaterThan(spec.opacity(of: .content), spec.opacity(of: .panel),
                             "阅读区必须比工具条那一层实")
        XCTAssertGreaterThan(spec.opacity(of: .raised), spec.opacity(of: .content),
                             "浮层（气泡 / 卡片）必须比阅读区更实")
        XCTAssertGreaterThanOrEqual(spec.opacity(of: .sidebar), spec.opacity(of: .panel),
                                   "侧栏至少不能比工具条更透")
    }

    /// **档 3 逐字登记**（人类主人选定的那一档）：这四条数字是"这个观感"的定义，
    /// 改一个就会红 —— 想改观感，请连同这条判据与值表注释一起改，并在提交信息里说明。
    func testDeliveredValuesAreRegisteredVerbatim() throws {
        let spec = try XCTUnwrap(DesignTheme.deepSpace.wallpaper)
        XCTAssertEqual(spec.maskStops, [
            WallpaperMaskStop(location: 0.00, alpha: 0.64),
            WallpaperMaskStop(location: 0.42, alpha: 0.24),
            WallpaperMaskStop(location: 0.74, alpha: 0.36),
            WallpaperMaskStop(location: 1.00, alpha: 0.54),
        ])
        XCTAssertEqual(spec.opacity(of: .window), 0.40, accuracy: 0.0001)
        XCTAssertEqual(spec.opacity(of: .sidebar), 0.40, accuracy: 0.0001)
        XCTAssertEqual(spec.opacity(of: .content), 0.44, accuracy: 0.0001)
        XCTAssertEqual(spec.opacity(of: .panel), 0.30, accuracy: 0.0001)
        XCTAssertEqual(spec.opacity(of: .raised), 0.62, accuracy: 0.0001)
    }

    /// 没登记的表面按**最实**处理：漏登记只会"看不见照片"，不会"文字发飘"。
    func testUnregisteredSurfaceFallsBackToOpaque() {
        let spec = WallpaperSkinSpec(assetName: "x", maskStops: [], surfaceOpacity: [:])
        for surface in Surface.allCases {
            XCTAssertEqual(spec.opacity(of: surface), 1)
        }
    }

    // MARK: - ④ 开关规则（键 / 缺省 / 读法 / 重开）

    func testSwitchDefaultsToOn() {
        XCTAssertNil(defaults.object(forKey: WallpaperSkinPreference.key), "前提：这个 suite 是干净的")
        XCTAssertTrue(WallpaperSkinPreference.isEnabled(in: defaults),
                      "缺省值必须是开 —— 人类主人看过效果图之后点的这一档")
    }

    /// 「关掉之后重开还是关」：用同一个 suite 再读一次 = 模拟重开进程。
    func testTurningItOffSticksAcrossRestart() {
        WallpaperSkinPreference.setEnabled(false, in: defaults)
        XCTAssertFalse(WallpaperSkinPreference.isEnabled(in: defaults))
        // 「重开」= 同一个 suite 重新读（`object(forKey:)` 的读法就是为了这一态）
        XCTAssertEqual(defaults.object(forKey: WallpaperSkinPreference.key) as? Bool, false)
    }

    func testKeyIsTheContract() {
        XCTAssertEqual(WallpaperSkinPreference.key, "ui.wallpaperSkin",
                       "键名就是契约：改一个字，老用户的选择当场失效")
    }

    // MARK: - ⑤ 生效条件 = 主题声明 ∧ 开关开（真值表）

    func testActivationIsThemeDeclarationAndSwitch() throws {
        let spec = try XCTUnwrap(DesignTheme.deepSpace.wallpaper)
        for theme in DesignTheme.allCases {
            for enabled in [true, false] {
                WallpaperSkinPreference.setEnabled(enabled, in: defaults)
                let active = WallpaperSkinPreference.activeSpec(theme: theme, in: defaults)
                let expected = (theme == .deepSpace) && enabled
                XCTAssertEqual(active != nil, expected,
                               "\(theme.rawValue) / 开关 \(enabled) ⇒ 生效应为 \(expected)")
                if expected { XCTAssertEqual(active, spec) }
            }
        }
        // 收尾：别把开关留在测试改过的状态上（同一个 suite 后续用例还要用）
        defaults.removePersistentDomain(forName: suiteName)
    }
}
