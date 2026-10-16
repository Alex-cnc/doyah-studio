import Foundation

/// 「壁纸皮肤」—— 把一张照片铺成窗口背景，面板按**定值不透明度**压在它上面。
///
/// ## 这件东西是什么（与「星云皮肤」「主题」的分工）
///
/// - **主题**（`DesignTheme`）= 一组令牌值（纯色 + 强调色 + 语法色）；
/// - **星云皮肤**（`NebulaSkinPreference`）= 在表面**之上**叠一层程序化云气与星点；
/// - **壁纸皮肤**（本件）= 在表面**之下**垫一张**照片**，再让表面**半透明**透出它。
///
/// 三条互不代偿：主题决定"用什么色"，星云决定"表面之上再加什么"，壁纸决定"表面之下透出什么"。
///
/// ## 为什么规则住在 Core
///
/// 与 `NebulaSkinPreference` 同一个理由（一份实现、两个消费者；规则只有一种正确写法）：
///
///  1. **落盘键**（`ui.wallpaperSkin`）= 契约：改一个字，老用户的选择当场失效；
///  2. **缺省值 = 开** —— 人类主人 2026-10-16 看过效果图之后**点了这一档**（原话「第三个就是我要的效果」），
///     新装用户就该直接看到它；
///  3. **读法必须是 `object(forKey:) as? Bool ?? 缺省`** —— `bool(forKey:)` 对「从未设过」返回
///     `false`，等于把缺省值静默改成关；
///  4. **生效条件 = 主题声明了壁纸 且 开关开** —— 少了主题那一半，别的主题会莫名其妙透出照片（走样）；
///     少了开关那一半，用户关不掉。
///
/// ## 为什么值表也是"定值"而不是"跟着照片算"
///
/// 面板半透明之后，「文字压在什么颜色上」取决于照片的像素。要让这件事**仍然可判**，只有一条路：
/// **把两层数字都写死** —— 蒙版（压住照片亮度的那层渐变）与每个表面的不透明度都由**主题声明**，
/// 于是「有效底色」是**可复算**的，而不是"运行时才知道"。谁想调松观感，改的是值表里的数字，
/// 单测里那几个**逐字登记**的档位会当场抓住他（`Tests/WallpaperSkinTests.swift`）。
///
/// ## 与「不算推导草案」的关系
///
/// 壁纸的值**不是**从别端抄来的，也不是本侧凑的观感值 —— 它们是从一份**可复现的效果图**里读出来的
/// （`/Users/alex/.hermes/cache/scratch/skin-preview/` 三档对照，人类主人选定档 3）。
/// 这三档数字逐字登记在 `Tests/WallpaperSkinTests.swift` 里，改一处就会红。
public enum WallpaperSkin {

    /// 资源名（`App/Resources/<这个名字>.jpg`；进包由 `project.yml` 的 `App` 源目录带出）。
    ///
    /// 命名跟随主题：一个主题一张照片 —— 想做第二张壁纸，是**给那个主题加一份值表**，不是在这里加分支。
    public static func assetName(for theme: DesignTheme) -> String? { theme.wallpaper?.assetName }
}

/// 蒙版的一个停靠点：`location` 是纵向位置（0 = 顶，1 = 底），`alpha` 是这一点的遮罩浓度。
///
/// 遮罩颜色**不在这里** —— 它是主题的 `window` 值（`rgba(windowColor, alpha)`）：
/// 蒙版要用"这个主题自己的底"去压，"深空苍穹"的底是 `#05070D`，不是随便一个黑。
public struct WallpaperMaskStop: Equatable, Sendable {

    public let location: Double
    public let alpha: Double

    public init(location: Double, alpha: Double) {
        self.location = location
        self.alpha = alpha
    }
}

/// 一个主题的壁纸值（**值表的一部分**：新主题想说「我也有壁纸」，加的是它自己的一份，不是改绘制代码）。
public struct WallpaperSkinSpec: Equatable, Sendable {

    /// 资源名（不含扩展名）。
    public let assetName: String

    /// 蒙版停靠点（自上而下）。
    public let maskStops: [WallpaperMaskStop]

    /// 各表面的**不透明度**（1 = 完全不透、看不见照片；0 = 照片原样）。
    ///
    /// 为什么按表面分开而不是一个全局值：阅读区（`content`）比工具条（`panel`）更"实" ——
    /// 长时间注视的地方文字要更稳，而 chrome 那一层可以更透（观感也更"玻璃"）。
    public let surfaceOpacity: [Surface: Double]

    public init(assetName: String, maskStops: [WallpaperMaskStop], surfaceOpacity: [Surface: Double]) {
        self.assetName = assetName
        self.maskStops = maskStops
        self.surfaceOpacity = surfaceOpacity
    }

    /// 这一表面在壁纸开着时的不透明度（没登记的按**最实**处理：宁可看不见照片，也不让文字发飘）。
    public func opacity(of surface: Surface) -> Double {
        surfaceOpacity[surface] ?? 1
    }

    /// 蒙版**最松**的那一档（判据用：照片最亮处压在它下面时，文字的对比度就是这里决定的）。
    public var weakestMaskAlpha: Double {
        maskStops.map(\.alpha).min() ?? 1
    }
}

// MARK: - 值表（第 5 套主题「深空苍穹」· 人类主人 2026-10-16 选定「档 3」）

public extension WallpaperSkinSpec {

    /// 「深空苍穹」的壁纸值 = 2026-10-16 三档对照里的**档 3**（面板 40% 不透）。
    ///
    /// 三档对照（同一张照片、同一套壳）：
    /// - 档 1：面板 68% 不透 —— 只有天际线隐约可见；
    /// - 档 2：面板 54% 不透 —— 天际线、塔楼、水面都出来了；
    /// - **档 3（选定）：面板 40% 不透** —— 照片最明显，文字仍读得清（三张逐张看过）。
    ///
    /// 照片来源：人类主人提供的湖景照（1864×4096 竖拍），交付资源是**中段横裁** 1600×1000 / 164KB
    /// （裁掉了上面大片天空与下面大片水面：窗口是横的，铺满时看的就是中段这一条）。
    static let deepSpace = WallpaperSkinSpec(
        assetName: "wallpaper-deep-space",
        // 上暗 → 中亮 → 下略暗：最亮的一档（0.24）落在「天际线与塔楼」那一条，
        // 它下面正好是工具条与结果区的交界；窗口底边再压回 0.54，让状态栏不发飘。
        maskStops: [
            WallpaperMaskStop(location: 0.00, alpha: 0.64),
            WallpaperMaskStop(location: 0.42, alpha: 0.24),
            WallpaperMaskStop(location: 0.74, alpha: 0.36),
            WallpaperMaskStop(location: 1.00, alpha: 0.54),
        ],
        // 阅读区（content 0.44）比一栏一栏的 chrome（panel 0.30）更实；
        // 浮起来的东西（raised：气泡 / 卡片）最实（0.62）—— 它本来就该"离照片最远"。
        surfaceOpacity: [
            .window: 0.40,
            .sidebar: 0.40,
            .content: 0.44,
            .panel: 0.30,
            .raised: 0.62,
        ]
    )
}

// MARK: - 主题声明

public extension DesignTheme {

    /// 这一主题**要不要铺壁纸**（值不在这里给，在 `WallpaperSkinSpec.deepSpace` 那种静态值里）。
    ///
    /// 与「哪个主题画星云」同一条纪律（2026-10-16 泛化）：**由主题自己声明** ——
    /// 新主题要壁纸，加的是它自己的值，不动 `Theme.surface` / `WallpaperBackground` 的绘制代码。
    var wallpaper: WallpaperSkinSpec? {
        switch self {
        case .deepSpace: return .deepSpace
        case .techBlue, .beanGreen, .roseGold, .stardust: return nil
        }
    }
}

/// 壁纸皮肤的**开关规则**（键、缺省值、读法、生效条件）—— 与 `NebulaSkinPreference` 同形。
public enum WallpaperSkinPreference {

    /// 落盘键（与前缀一致，便于一起清理）。
    public static let key = "ui.wallpaperSkin"

    /// 缺省值：**开**（人类主人 2026-10-16 选定档 3）。
    public static let defaultEnabled = true

    /// 从偏好里读回开关。**读法就是规格**：先问"有没有设过"，再退回缺省值。
    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultEnabled
    }

    /// 写入开关（唯一写入口）。
    public static func setEnabled(_ isEnabled: Bool, in defaults: UserDefaults) {
        defaults.set(isEnabled, forKey: key)
    }

    /// **生效条件**：主题声明了壁纸 且 开关开 —— 两半缺一不可。
    public static func paintsWallpaper(theme: DesignTheme, in defaults: UserDefaults) -> Bool {
        theme.wallpaper != nil && isEnabled(in: defaults)
    }

    /// 当前生效的壁纸值（不生效时为 `nil`；绘制侧与取色侧都只问这一句，免得两处各判一次）。
    public static func activeSpec(theme: DesignTheme, in defaults: UserDefaults) -> WallpaperSkinSpec? {
        paintsWallpaper(theme: theme, in: defaults) ? theme.wallpaper : nil
    }
}
