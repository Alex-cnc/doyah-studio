import XCTest
@testable import DoyahCore

/// 星空紫「星云皮肤」的**偏好规则单测**（队列 `L-155` ③ · 开发循环第 154 轮）。
///
/// ## 为什么这段规则要有单测
///
/// 它是 2026-10-01 需求提出者实测反馈（派单 `T-20261001-031`／`T-20261001-037`）落下来的那一层
/// 「皮肤」里**唯一能用机器钉住的那一半**：云气浓淡、星点密度、滚动流畅度只能人工点验，
/// 但"开关的键是什么 / 缺省开还是关 / 关掉之后读回来还是不是关 / 皮肤跑到别的主题上没有"
/// 这四件事**必须**是机器判的。此前它们全在 `App/DesignThemeManager` 的初始化里，
/// 而那个位置有个天然的不可测性：单例在**进程第一次被碰到**时就定型了，
/// 「默认开」「重开仍关」这两态在 App 侧的单测里**做不到**（要重启进程）。
/// 规则搬进 Core（`NebulaSkinPreference`）之后就做得到了：注入一个 `UserDefaults(suiteName:)`，
/// 「新装」= 键不存在，「重开」= 用同一个 suite 再取一次。
///
/// ## 边界（如实登记）
///
/// 本族判的是**规则**，不是观感：不判"画出来好不好看"，也不判"三层表面上真的画了" ——
/// 后者由 `TestsUISnapshot/NebulaSkinProbeTests.swift` 的离屏渲染（像素级）与
/// `Scripts/check-design-themes.py` 判据 I（静态落点）分工。
final class NebulaSkinPreferenceTests: XCTestCase {

    /// 单独的 suite：测试进程自己的域，与 App 的偏好（`studio.doyah.DoyahStudio`）无关。
    private let suiteName = "studio.doyah.tests.nebula-skin"

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - ① 键名是契约

    /// 落盘键是**用户已存偏好的地址**：改一个字，老用户的选择当场失效，
    /// 而界面上看起来只是"皮肤又自己打开了"（没有任何症状提示这是 bug）。
    func testStorageKeyIsTheContractLiteral() {
        XCTAssertEqual(
            NebulaSkinPreference.key, "ui.nebulaSkin",
            "皮肤开关的落盘键是契约：改了它 = 所有老用户的开关选择静默失效"
        )
    }

    /// 键与主题键同前缀（清偏好时能一起被找到），且**不与主题键相等**（相等就是互相覆盖）。
    func testKeyIsNamespacedAndDistinctFromTheThemeKey() {
        XCTAssertTrue(
            NebulaSkinPreference.key.hasPrefix("ui."),
            "与 `DesignTheme.Storage.key`（ui.designTheme）同一前缀，便于一起清理"
        )
        XCTAssertNotEqual(NebulaSkinPreference.key, DesignTheme.Storage.key)
    }

    // MARK: - ② 缺省值 = 开（"新装用户直接看到皮肤"）

    /// 从未设过 ⇒ 开。这一条是需求提出者 2026-10-01 的原话（「我说的可能是皮肤更准确」）落成的缺省。
    func testNeverSetMeansEnabled() {
        let defaults = freshDefaults()
        XCTAssertNil(defaults.object(forKey: NebulaSkinPreference.key), "夹具前提：键必须不存在")
        XCTAssertTrue(NebulaSkinPreference.isEnabled(in: defaults), "从未设过应当读成「开」")
    }

    /// **读法就是规格**：`bool(forKey:)` 对"从未设过"返回 `false` ⇒ 缺省值会被静默改成关。
    /// 这一条把两种读法的差别钉在测试里 —— 谁把实现换成 `bool(forKey:)`，这里当场红。
    func testReadRuleDiffersFromBoolForKeyOnAFreshStore() {
        let defaults = freshDefaults()
        XCTAssertFalse(defaults.bool(forKey: NebulaSkinPreference.key), "夹具前提：bool(forKey:) 这一态是 false")
        XCTAssertNotEqual(
            NebulaSkinPreference.isEnabled(in: defaults), defaults.bool(forKey: NebulaSkinPreference.key),
            "读法必须是 object(forKey:) as? Bool ?? 缺省 —— 用 bool(forKey:) 会把缺省从「开」改成「关」"
        )
    }

    /// 存了一个**不是布尔的**值（偏好文件被手改 / 别的东西占了同一个键）⇒ 回落缺省，
    /// 不许崩、也不许把它当成真。
    func testNonBooleanValueFallsBackToDefault() {
        let defaults = freshDefaults()
        defaults.set("yes", forKey: NebulaSkinPreference.key)
        XCTAssertTrue(NebulaSkinPreference.isEnabled(in: defaults), "认不出的值应当回落缺省（开），不是当成真")
    }

    /// 读**不写盘**：读一次不许把缺省值写进用户偏好（否则"没设过"和"设成了开"就再也分不开）。
    func testReadingDoesNotWriteTheDefaultBack() {
        let defaults = freshDefaults()
        _ = NebulaSkinPreference.isEnabled(in: defaults)
        XCTAssertNil(defaults.object(forKey: NebulaSkinPreference.key), "读操作不许把缺省值落盘")
    }

    // MARK: - ③ 关掉之后：落盘 + 重开仍关

    /// 关 ⇒ 落盘 `false` ⇒ **重开**（同一个 suite 再取一次）读回来仍是关。
    /// 「重开」在这里就是"重新构造一个 `UserDefaults` 读同一个域"—— 与进程重启读的是同一份存储。
    func testOffIsPersistedAndSurvivesReopen() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: NebulaSkinPreference.key)
        XCTAssertFalse(NebulaSkinPreference.isEnabled(in: defaults), "关掉之后应当读成关")

        let reopened = UserDefaults(suiteName: suiteName) ?? .standard
        XCTAssertFalse(NebulaSkinPreference.isEnabled(in: reopened), "重开之后必须仍然是关（关不掉 = 开关是假的）")
    }

    /// 开 ⇒ 落盘 `true` ⇒ 重开仍是开（用户改了主意之后不许被缺省值盖回去）。
    func testOnIsPersistedAndSurvivesReopen() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: NebulaSkinPreference.key)
        let reopened = UserDefaults(suiteName: suiteName) ?? .standard
        XCTAssertTrue(NebulaSkinPreference.isEnabled(in: reopened))
    }

    // MARK: - ④ 生效条件：星空紫 且 开关开（唯一出处）

    /// 生效条件的**真值表**：四个主题 × 开关两态 = 8 组，只有「星空紫 + 开」这一组为真。
    func testPaintsNebulaTruthTableOverEveryThemeAndSwitchState() {
        var trueCount = 0
        for theme in DesignTheme.all {
            for enabled in [true, false] {
                let expected = (theme == .stardust) && enabled
                XCTAssertEqual(
                    NebulaSkinPreference.paintsNebula(theme: theme, isSkinEnabled: enabled),
                    expected,
                    "生效条件错：theme=\(theme.id) / 开关=\(enabled)"
                )
                if expected { trueCount += 1 }
            }
        }
        XCTAssertEqual(trueCount, 1, "8 组里**恰好**一组为真（星空紫 + 开）—— 多一组就是皮肤跑到别的主题上了")
        XCTAssertEqual(
            DesignTheme.all.count * 2, 8,
            "组合数是 4 主题 × 2 态：主题集变了这里要一起改（否则新主题默认没被判过）"
        )
    }

    /// 星空紫 + 关 = 不画（用户可以关掉它）；别的主题 + 开 = 也不画（不许偷偷给所有主题加星星）。
    func testOnlyStardustWithSwitchOnPaints() {
        XCTAssertTrue(NebulaSkinPreference.paintsNebula(theme: .stardust, isSkinEnabled: true))
        XCTAssertFalse(NebulaSkinPreference.paintsNebula(theme: .stardust, isSkinEnabled: false))
        for theme in DesignTheme.all where theme != .stardust {
            XCTAssertFalse(
                NebulaSkinPreference.paintsNebula(theme: theme, isSkinEnabled: true),
                "\(theme.id) 也画了星云 —— 那是走样（需求提出者要的是「星空紫这一档的皮肤」）"
            )
        }
    }
}
