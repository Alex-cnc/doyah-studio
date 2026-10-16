import Foundation

/// 「壁纸皮肤」—— 把一张照片铺成窗口背景，面板按**定值不透明度**压在它上面。
///
/// ## 这件东西是什么（与「星云皮肤」「主题」的分工）
///
/// - **主题**（`DesignTheme`）= 一组令牌值（纯色 + 强调色 + 语法色）；
/// - **星云皮肤**（`NebulaSkinPreference`）= 在表面**之上**叠一层程序化云气与星点；
/// - **壁纸皮肤**（本件）= 在表面**之下**垫一张**照片**，再让表面**半透明**透出它。
///
/// 三条互不代偿：主题决定「用什么色」，星云决定「表面之上再加什么」，壁纸决定「表面之下透出什么」。
///
/// ## 两张在册（人类主人 2026-10-16 亲自命名）
///
/// | 壁纸 | 归哪个主题 | 为什么是它 |
/// |---|---|---|
/// | **城市之湖 City Lake**（`wallpaper-city-lake`） | 科技蓝 | 这张湖景照本来就是人类主人给的**科技蓝参照图**（原话「我预期的科技蓝主题是这种风格和效果」） |
/// | **宇宙悬崖 Cosmic Cliff**（`wallpaper-cosmic-cliff`） | 深空苍穹 | 名字相称（星云 = 深空；原话「城市之湖显然不是深空苍穹啊，宇宙悬崖叫深空苍穹还差不多」）+ 规范页观感来源就是这张 |
///
/// **配对口径 = 名字相称 ∧ 取色来源一致** —— 钉在 `Tests/WallpaperSkinTests.swift` 里，两张对调即红。
/// 界面上的选择是**记在偏好里的**，所以 `stardust` 不铺照片也不影响别的主题（它有自己的程序化星云）。
///
/// ## 三档可调（人类主人 2026-10-16 原话「这个档位是可以调节的吧」）
///
/// 每张壁纸带**三档**：**稳 / 中 / 震撼**（1 / 2 / 3）。
/// - 档越大 = 面板越透 = 照片越明显；
/// - **缺省档 = 人类主人在效果图上挑的那一档**（城市之湖 = 震撼，宇宙悬崖 = 中）；
/// - 选择按主题存（`ui.wallpaperStrength.<主题 id>`），切主题不会把另一张的档位带过去；
/// - 三档的**每一档**都要过同一套下限（蒙版最松 ≥ 0.24、表面 ≥ 0.28、次序合理）——
///   「可调」不等于「可以调到字看不清」，这是判据拦的事，不是靠自觉。
///
/// ## 为什么每档的两层数字都必须是「定值」
///
/// 照片当背景之后，「文字压在什么颜色上」取决于照片的像素 —— 这是整条令牌链路里**第一次**
/// 出现「表面不是一个定值颜色」。要让它仍然可判、可复算，做法只有一条：**蒙版与逐表面不透明度
/// 都写死（每一档各一组）并由主题声明**，于是有效底色可复算、判据有得可对。
///
/// ## 出处
///
/// · 城市之湖 = 人类主人拍摄（湖景照，1864×4096 竖拍 → **中段横裁** 16:10）；
/// · 宇宙悬崖 = NASA/ESA/CSA/STScI，JWST「Cosmic Cliffs」（NGC 3324，船底座星云），公共领域。
public enum WallpaperSkin {

    /// 资源名（`App/Resources/<这个名字>.jpg`；进包由 `project.yml` 的 `App` 源目录带出）。
    ///
    /// 命名跟随主题：一个主题一张照片 —— 想做第二张壁纸，是**给那个主题加一份值表**，不是在这里加分支。
    public static func assetName(for theme: DesignTheme) -> String? { theme.wallpaper?.assetName }
}

/// 蒙版的一个停靠点：`location` 是纵向位置（0 = 顶，1 = 底），`alpha` 是这一点的遮罩浓度。
///
/// 遮罩颜色**不在这里** —— 它是主题的 `window` 值（`rgba(windowColor, alpha)`）：
/// 蒙版要用「这个主题自己的底」去压，「深空苍穹」的底是 `#05070D`，不是随便一个黑。
public struct WallpaperMaskStop: Equatable, Sendable {

    public let location: Double
    public let alpha: Double

    public init(location: Double, alpha: Double) {
        self.location = location
        self.alpha = alpha
    }
}

/// **一档**壁纸的观感：蒙版四段 + 逐表面不透明度。
public struct WallpaperSkinLevel: Equatable, Sendable {

    /// 这一档的显示名（稳 / 中 / 震撼）。
    public let nameKey: LKey

    /// 蒙版停靠点（自上而下）。
    public let maskStops: [WallpaperMaskStop]

    /// 各表面的**不透明度**（1 = 完全不透、看不见照片；0 = 照片原样）。
    ///
    /// 为什么按表面分开而不是一个全局值：阅读区（`content`）比工具条（`panel`）更「实」——
    /// 长时间注视的地方文字要更稳，而 chrome 那一层可以更透（观感也更「玻璃」）。
    public let surfaceOpacity: [Surface: Double]

    public init(nameKey: LKey, maskStops: [WallpaperMaskStop], surfaceOpacity: [Surface: Double]) {
        self.nameKey = nameKey
        self.maskStops = maskStops
        self.surfaceOpacity = surfaceOpacity
    }

    /// 这一表面在本档下的不透明度（没登记的按**最实**处理：宁可看不见照片，也不让文字发飘）。
    public func opacity(of surface: Surface) -> Double { surfaceOpacity[surface] ?? 1 }

    /// 蒙版**最松**的那一档（判据用：照片最亮处压在它下面时，文字的对比度就是这里决定的）。
    public var weakestMaskAlpha: Double { maskStops.map(\.alpha).min() ?? 1 }
}

/// 一个主题的壁纸值（**值表的一部分**：新主题想说「我也有壁纸」，加的是它自己的一份，不是改绘制代码）。
public struct WallpaperSkinSpec: Equatable, Sendable {

    /// 资源名（不含扩展名）。
    public let assetName: String

    /// 这张壁纸的**显示名**（界面用：外观面板里写明「现在铺的是哪一张」）。
    public let nameKey: LKey

    /// 三档（稳 / 中 / 震撼），下标 0 起。
    public let levels: [WallpaperSkinLevel]

    /// **缺省档**（1 起）= 人类主人在效果图上挑的那一档。
    public let defaultLevel: Int

    public init(assetName: String, nameKey: LKey, levels: [WallpaperSkinLevel], defaultLevel: Int) {
        self.assetName = assetName
        self.nameKey = nameKey
        self.levels = levels
        self.defaultLevel = defaultLevel
    }

    /// 取某一档（**越界一律夹回合法范围**：坏值只可能落回缺省那一档，不会落成「没有壁纸」或「全透」）。
    public func level(_ strength: Int) -> WallpaperSkinLevel {
        let index = min(max(strength, 1), max(levels.count, 1)) - 1
        return levels.indices.contains(index) ? levels[index] : levels[0]
    }

    /// 缺省那一档。
    public var defaultLevelSpec: WallpaperSkinLevel { level(defaultLevel) }

    /// 档位数（界面按它摆选择器）。
    public var levelCount: Int { levels.count }
}

// MARK: - 值表（两张 · 各三档）

public extension WallpaperSkinSpec {

    /// **城市之湖**（科技蓝）= 人类主人 2026-10-16 在效果图上选定**第 3 档（震撼）**。
    ///
    /// 三档（同一张照片、同一套壳的对照图，逐档看过）：
    /// 档 1 · 稳（阅读区 72%）· 档 2 · 中（58%）· **档 3 · 震撼（44%）**。
    static let cityLake = WallpaperSkinSpec(
        assetName: "wallpaper-city-lake",
        nameKey: .wallpaperCityLake,
        levels: [
            WallpaperSkinLevel(
                nameKey: .wallpaperLevelSteady,
                maskStops: [
                    WallpaperMaskStop(location: 0.00, alpha: 0.84),
                    WallpaperMaskStop(location: 0.42, alpha: 0.52),
                    WallpaperMaskStop(location: 0.74, alpha: 0.64),
                    WallpaperMaskStop(location: 1.00, alpha: 0.80),
                ],
                surfaceOpacity: [.window: 0.68, .sidebar: 0.68, .content: 0.72, .panel: 0.52, .raised: 0.86]
            ),
            WallpaperSkinLevel(
                nameKey: .wallpaperLevelBalanced,
                maskStops: [
                    WallpaperMaskStop(location: 0.00, alpha: 0.74),
                    WallpaperMaskStop(location: 0.42, alpha: 0.38),
                    WallpaperMaskStop(location: 0.74, alpha: 0.50),
                    WallpaperMaskStop(location: 1.00, alpha: 0.68),
                ],
                surfaceOpacity: [.window: 0.54, .sidebar: 0.54, .content: 0.58, .panel: 0.38, .raised: 0.74]
            ),
            WallpaperSkinLevel(
                nameKey: .wallpaperLevelVivid,
                // 上暗 → 中亮 → 下略暗：最亮的一档（0.24）落在「天际线与塔楼」那一条。
                maskStops: [
                    WallpaperMaskStop(location: 0.00, alpha: 0.64),
                    WallpaperMaskStop(location: 0.42, alpha: 0.24),
                    WallpaperMaskStop(location: 0.74, alpha: 0.36),
                    WallpaperMaskStop(location: 1.00, alpha: 0.54),
                ],
                surfaceOpacity: [.window: 0.40, .sidebar: 0.40, .content: 0.44, .panel: 0.30, .raised: 0.62]
            ),
        ],
        defaultLevel: 3
    )

    /// **宇宙悬崖**（深空苍穹）= 人类主人 2026-10-16 在效果图上选定**第 2 档（中）**。
    ///
    /// 三档：档 1 · 稳（阅读区 60%）· **档 2 · 中（52%）**· 档 3 · 震撼（44%）。
    ///
    /// **为什么这张整体比湖景"实"一档**：韦伯这张图**亮得多**（橙棕悬崖 + 白星星场），
    /// 第一版照湖景那组数（阅读区 34%）试出来**表格压在橙色亮部会化掉** ⇒ 三档整体往「更狠」挪，
    /// 人类主人看完对照图挑了**中**这一档 —— 观感仍在（山脊 + 星场 + 橙棕崖壁都看得见），表格最稳。
    static let cosmicCliff = WallpaperSkinSpec(
        assetName: "wallpaper-cosmic-cliff",
        nameKey: .wallpaperCosmicCliff,
        levels: [
            WallpaperSkinLevel(
                nameKey: .wallpaperLevelSteady,
                maskStops: [
                    WallpaperMaskStop(location: 0.00, alpha: 0.88),
                    WallpaperMaskStop(location: 0.42, alpha: 0.60),
                    WallpaperMaskStop(location: 0.74, alpha: 0.70),
                    WallpaperMaskStop(location: 1.00, alpha: 0.82),
                ],
                surfaceOpacity: [.window: 0.54, .sidebar: 0.54, .content: 0.60, .panel: 0.46, .raised: 0.74]
            ),
            WallpaperSkinLevel(
                nameKey: .wallpaperLevelBalanced,
                // 上四分之一是全图最亮处（星场 + 云脊发光）⇒ 顶段压最狠；
                // 下三分之一是橙棕崖壁（表格压在这里）⇒ 再压回去。
                maskStops: [
                    WallpaperMaskStop(location: 0.00, alpha: 0.82),
                    WallpaperMaskStop(location: 0.42, alpha: 0.48),
                    WallpaperMaskStop(location: 0.74, alpha: 0.62),
                    WallpaperMaskStop(location: 1.00, alpha: 0.76),
                ],
                surfaceOpacity: [.window: 0.46, .sidebar: 0.46, .content: 0.52, .panel: 0.36, .raised: 0.66]
            ),
            WallpaperSkinLevel(
                nameKey: .wallpaperLevelVivid,
                maskStops: [
                    WallpaperMaskStop(location: 0.00, alpha: 0.74),
                    WallpaperMaskStop(location: 0.42, alpha: 0.38),
                    WallpaperMaskStop(location: 0.74, alpha: 0.52),
                    WallpaperMaskStop(location: 1.00, alpha: 0.70),
                ],
                surfaceOpacity: [.window: 0.38, .sidebar: 0.38, .content: 0.44, .panel: 0.28, .raised: 0.58]
            ),
        ],
        defaultLevel: 2
    )
}

// MARK: - 主题声明

public extension DesignTheme {

    /// 这一主题铺哪张壁纸（没声明 = 不铺照片）。
    ///
    /// 与「哪个主题画星云」同一条纪律：**由主题自己声明** —— 新主题要壁纸，加的是它的值，
    /// 不动 `Theme.surface` / `WallpaperBackground` 的绘制代码（规范页 §三 点名禁止的事）。
    ///
    /// 配对口径 = **名字相称 ∧ 取色来源一致**（人类主人 2026-10-16 校正）。
    var wallpaper: WallpaperSkinSpec? {
        switch self {
        case .techBlue: return .cityLake
        case .deepSpace: return .cosmicCliff
        case .beanGreen, .roseGold, .stardust: return nil
        }
    }
}

// MARK: - 开关与档位规则

/// 壁纸皮肤的**开关与档位规则**（键、缺省值、读法、生效条件）—— 与 `NebulaSkinPreference` 同形。
public enum WallpaperSkinPreference {

    /// 开关的落盘键。
    public static let key = "ui.wallpaperSkin"

    /// 档位的落盘键前缀（按主题分开存：切主题不会把另一张的档位带过去）。
    public static let strengthKeyPrefix = "ui.wallpaperStrength."

    /// 开关缺省值：**开**（人类主人 2026-10-16 点名要这两张）。
    public static let defaultEnabled = true

    /// 某一主题的档位键。
    public static func strengthKey(for theme: DesignTheme) -> String { strengthKeyPrefix + theme.rawValue }

    /// 从偏好里读回开关。**读法就是规格**：先问「有没有设过」，再退回缺省值。
    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultEnabled
    }

    /// 写入开关（唯一写入口）。
    public static func setEnabled(_ isEnabled: Bool, in defaults: UserDefaults) {
        defaults.set(isEnabled, forKey: key)
    }

    /// 某一主题当前的档位（1 起）。
    ///
    /// 缺省 = 这张壁纸的 `defaultLevel`（人类主人挑的那一档）；存了坏值（0 / 99 / 非数字）
    /// **夹回合法范围**，绝不落成「没有壁纸」。
    public static func strength(for theme: DesignTheme, in defaults: UserDefaults) -> Int {
        guard let spec = theme.wallpaper else { return 1 }
        guard let stored = defaults.object(forKey: strengthKey(for: theme)) as? Int else {
            return spec.defaultLevel
        }
        return min(max(stored, 1), max(spec.levelCount, 1))
    }

    /// 写入某一主题的档位（唯一写入口）。
    public static func setStrength(_ strength: Int, for theme: DesignTheme, in defaults: UserDefaults) {
        guard let spec = theme.wallpaper else { return }
        defaults.set(min(max(strength, 1), max(spec.levelCount, 1)), forKey: strengthKey(for: theme))
    }

    /// **生效条件**：主题声明了壁纸 且 开关开 —— 两半缺一不可。
    public static func paintsWallpaper(theme: DesignTheme, in defaults: UserDefaults) -> Bool {
        theme.wallpaper != nil && isEnabled(in: defaults)
    }

    /// 当前生效的**那一档**（不生效时为 `nil`；绘制侧与取色侧都只问这一句，免得两处各判一次）。
    public static func activeLevel(theme: DesignTheme, in defaults: UserDefaults) -> WallpaperSkinLevel? {
        guard let spec = theme.wallpaper, isEnabled(in: defaults) else { return nil }
        return spec.level(strength(for: theme, in: defaults))
    }

    /// 当前生效的壁纸（含显示名；界面用）。
    public static func activeSpec(theme: DesignTheme, in defaults: UserDefaults) -> WallpaperSkinSpec? {
        paintsWallpaper(theme: theme, in: defaults) ? theme.wallpaper : nil
    }
}
