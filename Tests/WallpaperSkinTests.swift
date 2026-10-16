import XCTest
@testable import DoyahCore

/// 「壁纸皮肤」的**值表与规则单测**（人类主人 2026-10-16：两张壁纸由他命名 **城市之湖** / **宇宙悬崖**，
/// 档位由他在效果图上各挑一档，随后问「这个档位是可以调节的吧」⇒ 三档可调）。
///
/// ## 为什么这层必须机器判
///
/// 照片当背景之后，「文字压在什么颜色上」取决于照片的像素 —— 这是**整条令牌链路里第一次**
/// 出现「表面不是一个定值颜色」的情况。要让它仍然可判、可复算，做法只有一条：
/// **每一档的两层数字都写死**（蒙版浓度 + 每个表面的不透明度），并且**逐字钉在判据里**。
///
/// ## 三条被钉住的口径
///
/// 1. **配对 = 名字相称 ∧ 取色来源一致** —— 城市之湖归科技蓝（这张湖景照就是他给的科技蓝参照图），
///    宇宙悬崖归深空苍穹（原话「城市之湖显然不是深空苍穹啊，宇宙悬崖叫深空苍穹还差不多」）；
/// 2. **缺省档 = 他挑的那一档** —— 城市之湖 = 3（震撼）、宇宙悬崖 = 2（中）；
/// 3. **「可调」不等于「能调到看不清」** —— 三档的**每一档**都要过同一套下限
///    （蒙版最松 ≥ 0.24、表面 ≥ 0.28、阅读区比 chrome 实、浮层最实）。
///
/// ## 判什么 / 不判什么（边界如实登记）
///
/// - **判**：配对与资源名与显示名 / 三档的档数与逐档合法性 / 缺省档 / 档位的存与取与夹回 /
///   开关 / 生效条件（主题声明 ∧ 开关）；
/// - **不判**（下一片，如实登记）：① 资源文件**真的在包里** —— 归静态判据；
///   ② **像素级**的有效底色（拿资源实测最亮处 × 蒙版 × 面板不透明度 ⇒ 对比度是否守住文字门槛）——
///   归离屏探针 / 脚本。本族只钉住「输入的那些数字」。
final class WallpaperSkinTests: XCTestCase {

    /// 单独的 suite：测试进程自己的域，与 App 的偏好无关。
    private let suiteName = "studio.doyah.tests.wallpaper-skin"
    private var defaults: UserDefaults!

    /// 在册的两张壁纸（主题 → 值）。
    private var registered: [(theme: DesignTheme, spec: WallpaperSkinSpec)] {
        DesignTheme.allCases.compactMap { theme in theme.wallpaper.map { (theme, $0) } }
    }

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - ① 谁有壁纸 · 配对 · 命名

    func testOnlyThemesThatDeclareAWallpaperHaveOne() {
        for theme in DesignTheme.allCases {
            switch theme {
            case .techBlue, .deepSpace:
                XCTAssertNotNil(theme.wallpaper, "\(theme.rawValue) 必须声明壁纸（人类主人 2026-10-16 命名）")
            case .beanGreen, .roseGold, .stardust:
                XCTAssertNil(theme.wallpaper, "\(theme.rawValue) 没声明壁纸 ⇒ 不许透出照片")
            }
        }
        XCTAssertEqual(registered.count, 2, "在册壁纸就是两张：城市之湖（科技蓝）+ 宇宙悬崖（深空苍穹）")
    }

    /// 配对规则：名字相称 ∧ 取色来源一致 —— 两张对调即红。
    func testWallpaperPairingFollowsNameAndSource() {
        XCTAssertEqual(WallpaperSkin.assetName(for: .techBlue), "wallpaper-city-lake",
                       "城市之湖归科技蓝：这张湖景照本来就是人类主人给的科技蓝参照图")
        XCTAssertEqual(WallpaperSkin.assetName(for: .deepSpace), "wallpaper-cosmic-cliff",
                       "宇宙悬崖归深空苍穹：名字相称，且规范页的观感来源就是这张星云图")
        XCTAssertEqual(DesignTheme.techBlue.wallpaper?.nameKey, .wallpaperCityLake)
        XCTAssertEqual(DesignTheme.deepSpace.wallpaper?.nameKey, .wallpaperCosmicCliff)
        XCTAssertNil(WallpaperSkin.assetName(for: .stardust), "星空紫有自己的程序化星云，不铺照片")
        XCTAssertNil(WallpaperSkin.assetName(for: .beanGreen))
    }

    // MARK: - ② 三档：档数 / 逐档合法性 / 缺省档

    func testEveryWallpaperHasThreeLevels() {
        for (theme, spec) in registered {
            XCTAssertEqual(spec.levelCount, 3, "\(theme.rawValue)：交付的是三档（稳 / 中 / 震撼）")
            XCTAssertTrue((1...spec.levelCount).contains(spec.defaultLevel),
                          "\(theme.rawValue)：缺省档必须落在合法范围内（现在 \(spec.defaultLevel)）")
        }
    }

    /// 缺省档 = 人类主人在效果图上挑的那一档（改它 = 改他挑的观感，要红）。
    func testDefaultLevelIsTheOneTheOwnerPicked() {
        XCTAssertEqual(DesignTheme.techBlue.wallpaper?.defaultLevel, 3, "城市之湖：他挑的是第 3 档（震撼）")
        XCTAssertEqual(DesignTheme.deepSpace.wallpaper?.defaultLevel, 2, "宇宙悬崖：他挑的是第 2 档（中）")
    }

    func testEveryLevelMaskIsOrderedAndInRange() {
        for (theme, spec) in registered {
            for strength in 1...spec.levelCount {
                let level = spec.level(strength)
                let stops = level.maskStops
                XCTAssertEqual(stops.count, 4, "\(theme.rawValue)/第 \(strength) 档：四段蒙版（上 / 中上 / 中下 / 下）")
                XCTAssertEqual(stops.first?.location ?? -1, 0, accuracy: 0.0001,
                               "\(theme.rawValue)/第 \(strength) 档：第一段必须贴住窗口顶边")
                XCTAssertEqual(stops.last?.location ?? -1, 1, accuracy: 0.0001,
                               "\(theme.rawValue)/第 \(strength) 档：最后一段必须贴住窗口底边")
                for (previous, next) in zip(stops, stops.dropFirst()) {
                    XCTAssertLessThan(previous.location, next.location,
                                      "\(theme.rawValue)/第 \(strength) 档：位置必须严格递增")
                }
                for stop in stops {
                    XCTAssertTrue((0...1).contains(stop.location), "\(theme.rawValue)/第 \(strength) 档：位置越界")
                    XCTAssertTrue((0...1).contains(stop.alpha), "\(theme.rawValue)/第 \(strength) 档：浓度越界")
                }
            }
        }
    }

    /// **「可调」不等于「能调到看不清」**：三档里**每一档**都要过下限。
    ///
    /// 0.24 这个蒙版下限的来历：城市之湖第 3 档就是这么定的（人类主人选的效果图），
    /// 再松一档（0.16）在天际线那一条上已经开始吃掉正文对比度。宇宙悬崖更亮 ⇒ 各档自然更高。
    func testEveryLevelKeepsTheFloors() {
        for (theme, spec) in registered {
            for strength in 1...spec.levelCount {
                let level = spec.level(strength)
                XCTAssertGreaterThanOrEqual(level.weakestMaskAlpha, 0.24,
                                            "\(theme.rawValue)/第 \(strength) 档：蒙版最松那档低于下限 ⇒ 亮处会顶穿文字")
                for surface in Surface.allCases {
                    XCTAssertGreaterThanOrEqual(level.opacity(of: surface), 0.28,
                                                "\(theme.rawValue)/第 \(strength) 档/\(surface.rawValue) 低于下限 ⇒ 文字发飘")
                    XCTAssertLessThanOrEqual(level.opacity(of: surface), 1,
                                             "\(theme.rawValue)/第 \(strength) 档/\(surface.rawValue) 超过 1")
                }
                XCTAssertGreaterThan(level.opacity(of: .content), level.opacity(of: .panel),
                                     "\(theme.rawValue)/第 \(strength) 档：阅读区必须比工具条实")
                XCTAssertGreaterThan(level.opacity(of: .raised), level.opacity(of: .content),
                                     "\(theme.rawValue)/第 \(strength) 档：浮层必须比阅读区更实")
                XCTAssertGreaterThanOrEqual(level.opacity(of: .sidebar), level.opacity(of: .panel),
                                            "\(theme.rawValue)/第 \(strength) 档：侧栏不能比工具条更透")
            }
        }
    }

    /// 档越大 = 越透（照片越明显）—— 这条是「可调」这个功能的**定义**，反了就是功能错了。
    func testLevelsGetMoreTransparentAsTheNumberGrows() {
        for (theme, spec) in registered {
            for (lower, higher) in zip(1..<spec.levelCount, 2...spec.levelCount) {
                XCTAssertGreaterThanOrEqual(spec.level(lower).weakestMaskAlpha,
                                            spec.level(higher).weakestMaskAlpha,
                                            "\(theme.rawValue)：第 \(lower) 档的蒙版不能比第 \(higher) 档松")
                XCTAssertGreaterThanOrEqual(spec.level(lower).opacity(of: .content),
                                            spec.level(higher).opacity(of: .content),
                                            "\(theme.rawValue)：第 \(lower) 档的阅读区不能比第 \(higher) 档透")
            }
        }
    }

    /// 越界档位**夹回合法范围**（坏值只可能落回合法档，不会落成「没有壁纸」或「全透」）。
    func testOutOfRangeStrengthClampsIntoRange() throws {
        for (theme, spec) in registered {
            XCTAssertEqual(spec.level(0).nameKey, spec.level(1).nameKey, "\(theme.rawValue)：0 → 第 1 档")
            XCTAssertEqual(spec.level(-5).nameKey, spec.level(1).nameKey, "\(theme.rawValue)：负数 → 第 1 档")
            XCTAssertEqual(spec.level(99).nameKey, spec.level(spec.levelCount).nameKey,
                           "\(theme.rawValue)：过大 → 最后一档")
        }
    }

    // MARK: - ③ 两张缺省档的数字**逐字登记**

    /// 城市之湖（科技蓝）缺省第 3 档：这几条数字是「这个观感」的定义，改一个就会红。
    func testCityLakeDefaultLevelIsRegisteredVerbatim() throws {
        let spec = try XCTUnwrap(DesignTheme.techBlue.wallpaper)
        XCTAssertEqual(spec.defaultLevelSpec.maskStops, [
            WallpaperMaskStop(location: 0.00, alpha: 0.64),
            WallpaperMaskStop(location: 0.42, alpha: 0.24),
            WallpaperMaskStop(location: 0.74, alpha: 0.36),
            WallpaperMaskStop(location: 1.00, alpha: 0.54),
        ])
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .window), 0.40, accuracy: 0.0001)
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .sidebar), 0.40, accuracy: 0.0001)
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .content), 0.44, accuracy: 0.0001)
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .panel), 0.30, accuracy: 0.0001)
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .raised), 0.62, accuracy: 0.0001)
    }

    /// 宇宙悬崖（深空苍穹）缺省第 2 档：同上，逐字登记。
    func testCosmicCliffDefaultLevelIsRegisteredVerbatim() throws {
        let spec = try XCTUnwrap(DesignTheme.deepSpace.wallpaper)
        XCTAssertEqual(spec.defaultLevelSpec.maskStops, [
            WallpaperMaskStop(location: 0.00, alpha: 0.82),
            WallpaperMaskStop(location: 0.42, alpha: 0.48),
            WallpaperMaskStop(location: 0.74, alpha: 0.62),
            WallpaperMaskStop(location: 1.00, alpha: 0.76),
        ])
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .window), 0.46, accuracy: 0.0001)
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .sidebar), 0.46, accuracy: 0.0001)
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .content), 0.52, accuracy: 0.0001)
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .panel), 0.36, accuracy: 0.0001)
        XCTAssertEqual(spec.defaultLevelSpec.opacity(of: .raised), 0.66, accuracy: 0.0001)
    }

    /// 没登记的表面按**最实**处理：漏登记只会「看不见照片」，不会「文字发飘」。
    func testUnregisteredSurfaceFallsBackToOpaque() {
        let level = WallpaperSkinLevel(nameKey: .wallpaperLevelSteady, maskStops: [], surfaceOpacity: [:])
        for surface in Surface.allCases {
            XCTAssertEqual(level.opacity(of: surface), 1)
        }
    }

    // MARK: - ④ 开关与档位（键 / 缺省 / 读法 / 重开 / 按主题分开）

    func testSwitchDefaultsToOn() {
        XCTAssertNil(defaults.object(forKey: WallpaperSkinPreference.key), "前提：这个 suite 是干净的")
        XCTAssertTrue(WallpaperSkinPreference.isEnabled(in: defaults),
                      "缺省值必须是开 —— 人类主人点名要这两张")
    }

    /// 「关掉之后重开还是关」：用同一个 suite 再读一次 = 模拟重开进程。
    func testTurningItOffSticksAcrossRestart() {
        WallpaperSkinPreference.setEnabled(false, in: defaults)
        XCTAssertFalse(WallpaperSkinPreference.isEnabled(in: defaults))
        XCTAssertEqual(defaults.object(forKey: WallpaperSkinPreference.key) as? Bool, false)
    }

    func testKeysAreTheContract() {
        XCTAssertEqual(WallpaperSkinPreference.key, "ui.wallpaperSkin",
                       "键名就是契约：改一个字，老用户的选择当场失效")
        XCTAssertEqual(WallpaperSkinPreference.strengthKey(for: .techBlue), "ui.wallpaperStrength.tech-blue")
    }

    /// 档位缺省 = 那张壁纸的缺省档；改完存得住；坏值夹回。
    func testStrengthDefaultsToThePickedLevelAndSticks() {
        XCTAssertEqual(WallpaperSkinPreference.strength(for: .techBlue, in: defaults), 3)
        XCTAssertEqual(WallpaperSkinPreference.strength(for: .deepSpace, in: defaults), 2)
        WallpaperSkinPreference.setStrength(1, for: .techBlue, in: defaults)
        XCTAssertEqual(WallpaperSkinPreference.strength(for: .techBlue, in: defaults), 1, "改完存得住")
        WallpaperSkinPreference.setStrength(99, for: .techBlue, in: defaults)
        XCTAssertEqual(WallpaperSkinPreference.strength(for: .techBlue, in: defaults), 3, "过大夹回最后一档")
        WallpaperSkinPreference.setStrength(0, for: .techBlue, in: defaults)
        XCTAssertEqual(WallpaperSkinPreference.strength(for: .techBlue, in: defaults), 1, "过小夹回第一档")
    }

    /// **按主题分开存**：改了城市之湖的档位，宇宙悬崖的档位不受影响。
    func testStrengthIsStoredPerTheme() {
        WallpaperSkinPreference.setStrength(1, for: .techBlue, in: defaults)
        XCTAssertEqual(WallpaperSkinPreference.strength(for: .deepSpace, in: defaults), 2,
                       "两个主题的档位互不干扰（切主题不会把另一张的档位带过去）")
    }

    // MARK: - ⑤ 生效条件 = 主题声明 ∧ 开关开（真值表）

    func testActivationIsThemeDeclarationAndSwitch() {
        for theme in DesignTheme.allCases {
            for enabled in [true, false] {
                WallpaperSkinPreference.setEnabled(enabled, in: defaults)
                let active = WallpaperSkinPreference.activeLevel(theme: theme, in: defaults)
                let declares = theme.wallpaper != nil
                XCTAssertEqual(active != nil, declares && enabled,
                               "\(theme.rawValue) / 开关 \(enabled) ⇒ 生效应为 \(declares && enabled)")
                if declares && enabled {
                    XCTAssertEqual(active, theme.wallpaper?.level(WallpaperSkinPreference.strength(for: theme, in: defaults)))
                }
            }
        }
        defaults.removePersistentDomain(forName: suiteName)
    }
}
