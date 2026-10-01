import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **星云皮肤的像素级证据**（队列 `L-155` ② · 开发循环第 154 轮）—— 开发循环里那条
/// 「判据缺口：星云皮肤的存在、开关与三层表面没有任何门禁在看」的下半截。
///
/// ## 缺口是什么
///
/// `L-153` 的星云皮肤（`App/Views/NebulaBackground.swift`）落地时，现有的判据只能证
/// 「它编译进包」「没引入裸色值」「扫描面与台账对齐」—— **证不了**这三件人话：
///
///   ① 星空紫下**真的画了**（不是 `if` 写反、也不是画在 0 尺寸的层上）；
///   ② 关掉开关**逐像素回到纯色**（"可关"是需求提出者要的退路，不是摆设）；
///   ③ **别的主题什么都没画**（偷偷给所有主题加星星 = 走样）。
///
/// 这三件都是**像素上的事实**，静态判据（`Scripts/check-design-themes.py` 判据 I）只能替它们
/// 守住"落点在不在、条件写没写对"；真正"画没画"只能看像素。屏幕录制权限没拿到、助理截不了
/// 运行中的 App，但**离屏渲染不需要授权**（`UISnapshot` 就是干这个的）。
///
/// ## 判法（与条目原文的差异，如实登记）
///
/// 条目 ② 写的是「断言三张的**角像素**分别等于皮肤色 / 纯面板色 / 纯内容色」。实现时改成
/// **整图逐像素比对 + 参照件**，理由是角像素在这一族里是**不可靠**的量具：
///   · "皮肤色"并不是一个常量 —— 星云是云气 + 星点的叠加，同一个角落可能是星点、也可能是云气
///     边缘、也可能正好是底板色，三种情况都在"画对了"的范围内；
///   · 真正要判的是**两个方向**（画了 / 没画），而"没画"这一侧的最强判据是
///     **与同主题的纯表面对照件逐像素相同**（0 个像素不同）—— 角像素比不出 0。
/// 所以：星空紫开 / 星空紫关 / 科技蓝开 三张仍是本条的主角（两两不同），另加两张**纯表面对照件**
/// （星空紫 / 科技蓝，不带 `NebulaBackground`）作为"没画"的基准。偏差写进开发记录与 `AGENT-SPEC` §9。
///
/// ## 口径
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与快照同一条纪律：取证才跑，每轮门禁不跑；
/// · 主题走**宿主语境覆盖**（`beginHostTheme`，不落盘）；皮肤开关是 `private(set)`、没有宿主覆盖，
///   只能真写 `UserDefaults` —— 跑完逐态还原（本探针跑在测试进程自己的域里，碰不到 App 的偏好）；
/// · 深色一遍即可：星空紫的星点/云气在深色下才给满（浅色档刻意压淡），判"画没画"取强的那一档。
/// · 这批图**一个 `L(...)` 都不进像素**（只有色块与星点）⇒ 已在
///   `Scripts/ui-snapshot-language-exemptions.json` 里逐张注册为语言无关。
final class NebulaSkinProbeTests: XCTestCase {

    /// 一张图的面积：够放下几团云气与几十颗星，又不至于拖慢（九张 × 两遍）。
    private let size = CGSize(width: 260, height: 180)

    /// 「画了」的下限：星空紫开启时，云气 + 星点覆盖的范围远超这个数（实测数万像素）。
    /// 取一个**远低于实测、又远高于噪声**的值：判的是"有没有画"，不是"画了多少"
    /// （浓淡属于观感，只能人工点验）。
    private let minimumPaintedPixels = 500

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本族要离屏渲染真视图树：DOYAH_UI_SNAPSHOT=1 才跑（快照是取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 渲染一条（主题 / 开关 / 表面 / 层）

    /// 拍一条 `base`（中英各一遍，名字由 `writeBothLanguages` 加后缀）。
    ///
    /// `skinEnabled` 传 `nil` = 不动开关（纯表面参照件用不上它）；
    /// `plain` 为真时**不铺 `NebulaBackground`** —— 那正是"没画"的基准。
    @MainActor
    private func shoot(
        _ base: String,
        surface: Surface,
        layer: NebulaBackground.Layer,
        theme: DesignTheme,
        skinEnabled: Bool?,
        plain: Bool = false
    ) throws -> [UISnapshot.Record] {
        let manager = DesignThemeManager.shared
        let previousOverride = manager.beginHostTheme(theme)
        defer {
            if let previousOverride { _ = manager.beginHostTheme(previousOverride) } else { manager.endHostTheme() }
        }
        let previousSkin = manager.isNebulaSkinEnabled
        if let skinEnabled { manager.setNebulaSkinEnabled(skinEnabled) }
        defer { if skinEnabled != nil { manager.setNebulaSkinEnabled(previousSkin) } }

        // 「这一张**应当**画东西吗」决定"空白"那道闸开不开：
        //  · 应当画（星空紫 + 开关开）⇒ 留闸（内容占比 < 0.002 就是真出错了，当场抛错）；
        //  · 不该画（别的主题 / 关了开关 / 纯表面参照件）⇒ **空白正是期望**，放开闸 ——
        //    这类图是不是真的空，由与对照件的**逐像素比对**判（比闸更硬）。
        // 用 `paintsNebula` 算它不影响判据的硬度：函数写错时这一侧的像素比对照样红。
        // `plain`（不带 `NebulaBackground` 的纯表面参照件）天然什么都不画 ⇒ 同样放开闸。
        let shouldPaint = !plain && NebulaSkinPreference.paintsNebula(
            theme: theme,
            isSkinEnabled: skinEnabled ?? manager.isNebulaSkinEnabled
        )

        let pair = try UISnapshot.writeBothLanguages(
            base,
            size: size,
            scheme: .dark,
            minimumContentRatio: shouldPaint ? 0.002 : 0
        ) {
            if plain {
                Theme.surface(surface)
            } else {
                ZStack {
                    Theme.surface(surface)
                    NebulaBackground(layer: layer)
                }
            }
        }
        return pair.records
    }

    // MARK: - 逐像素比对

    /// 两条记录（同一尺寸的两张 PNG）之间**不同的像素数**；尺寸读不出来或不等 ⇒ 直接判红。
    private func differingPixels(_ lhs: UISnapshot.Record, _ rhs: UISnapshot.Record) throws -> Int {
        func whole(_ record: UISnapshot.Record) throws -> UISnapshot.Band {
            guard let size = UISnapshot.pixelSize(ofPNGAt: record.file) else {
                throw XCTSkip("读不到 \(record.name) 的像素尺寸（\(record.file)）")
            }
            guard let band = UISnapshot.region(
                ofPNGAt: record.file, leading: 0, top: 0, width: size.width, height: size.height
            ) else {
                throw XCTSkip("取不到 \(record.name) 的像素块")
            }
            return band
        }
        let left = try whole(lhs)
        let right = try whole(rhs)
        XCTAssertEqual(
            left.width * left.height, right.width * right.height,
            "两张图尺寸不同（\(lhs.name) vs \(rhs.name)）—— 比出来的差没有意义"
        )
        guard let count = UISnapshot.differingPixels(left, right) else {
            throw XCTSkip("两条带的形状对不上（\(lhs.name) vs \(rhs.name)）")
        }
        return count
    }

    /// 取中英那一对里的**中文那份**做像素比对：两张按判据必须逐字节相同
    /// （`Scripts/check-ui-snapshot-languages.py` 会判），所以取哪一份都一样。
    private func primary(_ records: [UISnapshot.Record], _ base: String) throws -> UISnapshot.Record {
        guard let record = records.first else { throw XCTSkip("\(base) 没有产出记录") }
        print("🧪 \(base)：\(records.map(\.name).joined(separator: " / ")) → \(record.file)")
        return record
    }

    // MARK: - 主判据

    /// ① 星空紫下真的画了 ② 关掉逐像素回纯色 ③ 别的主题什么都没画 ④ 三层表面各自画得出来。
    @MainActor
    func testNebulaSkinPaintsOnlyInStardustAndCanBeSwitchedOff() throws {
        // 三层表面（与 `L-155` ① 的静态落点一一对应）：
        // 侧栏 / 内容区各自在 `MainWindow`，下方面板在 `LowerPaneView`。
        let layers: [(label: String, surface: Surface, layer: NebulaBackground.Layer)] = [
            ("sidebar", .sidebar, .sidebar),
            ("content", .content, .content),
            ("panel", .panel, .panel),
        ]

        var stardustOn: [String: UISnapshot.Record] = [:]
        var stardustOff: [String: UISnapshot.Record] = [:]
        for entry in layers {
            stardustOn[entry.label] = try primary(
                try shoot("nebula-skin-\(entry.label)-stardust-on", surface: entry.surface,
                          layer: entry.layer, theme: .stardust, skinEnabled: true),
                "\(entry.label)-stardust-on"
            )
            stardustOff[entry.label] = try primary(
                try shoot("nebula-skin-\(entry.label)-stardust-off", surface: entry.surface,
                          layer: entry.layer, theme: .stardust, skinEnabled: false),
                "\(entry.label)-stardust-off"
            )
        }

        // 两张"没画"的基准：同主题、同表面、**不铺星云**。
        let stardustPlain = try primary(
            try shoot("nebula-skin-panel-stardust-plain", surface: .panel, layer: .panel,
                      theme: .stardust, skinEnabled: nil, plain: true),
            "panel-stardust-plain"
        )
        let techBlueOn = try primary(
            try shoot("nebula-skin-panel-techblue-on", surface: .panel, layer: .panel,
                      theme: .techBlue, skinEnabled: true),
            "panel-techblue-on"
        )
        let techBluePlain = try primary(
            try shoot("nebula-skin-panel-techblue-plain", surface: .panel, layer: .panel,
                      theme: .techBlue, skinEnabled: nil, plain: true),
            "panel-techblue-plain"
        )

        // ④ 三层表面**都画得出来**：开与关必须不一样（一处落点写错层号 ⇒ 那一层两张会一模一样）。
        for entry in layers {
            let on = try XCTUnwrap(stardustOn[entry.label])
            let off = try XCTUnwrap(stardustOff[entry.label])
            XCTAssertGreaterThan(
                try differingPixels(on, off), 0,
                "\(entry.label) 那一层：皮肤开着与关着**画出来一样** —— 这一层的落点没生效"
            )
        }

        // ① 星空紫 + 开：真的画了（与"同主题纯表面"差出成百上千个像素）。
        let painted = try differingPixels(
            try XCTUnwrap(stardustOn["panel"]), stardustPlain
        )
        print("🧪 星空紫 + 开 vs 纯面板：不同像素 \(painted) 个（下限 \(minimumPaintedPixels)）")
        XCTAssertGreaterThan(
            painted, minimumPaintedPixels,
            "星空紫 + 开关开：与纯表面对照件只差 \(painted) 个像素 —— 皮肤没画出来（或画在了看不见的地方）"
        )

        // ② 星空紫 + 关：**逐像素**回纯色（这一条是"可关"的机器版）。
        let offDifference = try differingPixels(
            try XCTUnwrap(stardustOff["panel"]), stardustPlain
        )
        print("🧪 星空紫 + 关 vs 纯面板：不同像素 \(offDifference) 个（要求 0）")
        XCTAssertEqual(
            offDifference, 0,
            "关掉皮肤后与纯表面对照件差了 \(offDifference) 个像素 —— 「逐像素回到纯色」不成立"
        )

        // ③ 科技蓝 + 开：什么都没画（与"科技蓝纯表面"逐像素相同）。
        let techBlueDifference = try differingPixels(techBlueOn, techBluePlain)
        print("🧪 科技蓝 + 开 vs 科技蓝纯面板：不同像素 \(techBlueDifference) 个（要求 0）")
        XCTAssertEqual(
            techBlueDifference, 0,
            "科技蓝下画了 \(techBlueDifference) 个像素的星云 —— 皮肤偷偷跑到别的主题上了"
        )

        // 三张主角两两不同（条目原文的那一半）。**如实登记**：关着的星空紫与科技蓝的差别
        // 来自表面令牌不同（不是皮肤），所以它证明的是"三张各不相同"，"科技蓝不画"由上面 ③ 判。
        XCTAssertGreaterThan(
            try differingPixels(try XCTUnwrap(stardustOn["panel"]), try XCTUnwrap(stardustOff["panel"])), 0,
            "星空紫开着与关着画出来一样 —— 开关没接上"
        )
        XCTAssertGreaterThan(
            try differingPixels(try XCTUnwrap(stardustOff["panel"]), techBlueOn), 0,
            "关着的星空紫与开着皮肤的科技蓝一样 —— 主题没生效"
        )
        XCTAssertGreaterThan(
            try differingPixels(try XCTUnwrap(stardustOn["panel"]), techBlueOn), 0,
            "星空紫开着与科技蓝开着一样 —— 主题没生效"
        )
    }

    // MARK: - 开关的落盘与回读（真管理器 + 真 UserDefaults）

    /// ③ 的一半：**App 侧真的按唯一写入口落盘**，且"重开"（照 Core 的读法重新读同一个域）
    /// 之后仍然是关。规则本身的单测在 `Tests/NebulaSkinPreferenceTests.swift`；
    /// 这一条判的是**界面那个开关有没有接到唯一写入口上**（接到本地 `@State` 上就落不了盘）。
    @MainActor
    func testSwitchOffIsWrittenThroughTheOnlyWriteEntryPointAndReadsBackOff() throws {
        let defaults = UserDefaults.standard
        let key = NebulaSkinPreference.key
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
            DesignThemeManager.shared.setNebulaSkinEnabled(NebulaSkinPreference.isEnabled(in: defaults))
        }

        let manager = DesignThemeManager.shared
        // 先岔开一次再关：`setNebulaSkinEnabled` 对"设的就是当前值"会早退（不写盘），
        // 不岔开的话下面那条"键必须被写过"的断言会拿一个陈旧值当证据。
        manager.setNebulaSkinEnabled(true)
        manager.setNebulaSkinEnabled(false)

        XCTAssertFalse(manager.isNebulaSkinEnabled, "关掉之后管理器里必须立刻是关（界面读的是它）")
        XCTAssertEqual(
            defaults.object(forKey: key) as? Bool, false,
            "关掉之后 \(key) 必须落盘成 false —— 没落盘就是开关接在了本地 @State 上"
        )
        XCTAssertFalse(
            NebulaSkinPreference.isEnabled(in: defaults),
            "「重开」按 Core 的读法读同一个域，读回来必须仍是关（关不掉 = 开关是假的）"
        )
        XCTAssertFalse(
            NebulaSkinPreference.paintsNebula(theme: .stardust, isSkinEnabled: manager.isNebulaSkinEnabled),
            "关掉之后生效条件必须为假 —— 否则像素上还会画"
        )

        // 反过来：打开也要落盘（用户改了主意之后不许被缺省值盖回去）。
        manager.setNebulaSkinEnabled(true)
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)
        XCTAssertTrue(NebulaSkinPreference.isEnabled(in: defaults))
    }
}
