import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「待人工验收清单」**B 类**（快照 / 探针可代劳）条目的机器判据 —— 队列 `L-89` ㈡ 第 2 条：
/// 清单 §2 `FR-EDIT-26`（主题与字体）的 **③ 手输已装等宽族 ⇒ 生效且「当前使用」拼写正确** /
/// **④ 输非等宽 ⇒ 明确提示它不是等宽（不是静默回落）** / **⑤ SQL 预览的字形随之变化**。
///
/// ## 为什么需要它
///
/// 这三条现在写在「什么算过」里，靠人点：在外观面板的手输框里打一个族名、按「应用」、
/// 再打一个非等宽的、最后瞄一眼预览。而**「不是等宽」与「这个族不存在」是两句不同的话**
/// （`Core/FontPreferences.swift` 刻意分了三档：`resolved` / `unknownFamily` / `notMonospaced`
/// —— 混成一句，用户会一直以为自己选对了），这正是 `2026-09-23` 那批「编译过、单测过、
/// 判据全绿但人一点就发现不对」的同一族问题。
///
/// ## 造态：宿主语境覆盖（不落盘）
///
/// 面板读的是 `FontManager.shared`（编辑器 / 终端 / 预览共用这一个入口），而**改用户的字体偏好
/// 是 `select(family:)` 那条落盘的路** —— 拍一张图不该改它。所以造态走
/// `FontManager.beginHostPreference(_:)`（与 `DesignThemeManager.beginHostTheme` /
/// `LocalizationManager.beginHostLanguage` 同构：**只覆盖、不落盘**），`defer` 里退出。
///
/// ## ⑤ 的判据形状（像素）
///
/// 面板里吃这个字体的**不止** SQL 预览一处（终端预览同样吃它），所以「两张图不一样」证明不了
/// 「预览的字形变了」。判据比的是**一条受控的取样带**（`UISnapshot.band`）：SQL 预览那一行
/// 距图底的位置**只由它下面的固定高度内容决定**（面板用 `.defaultScrollAnchor(.bottom)` 渲染 ⇒
/// 上方文案增删不会挪动它），于是三个方向都能机械判：
///   · 换族（Menlo → Courier New）⇒ 这一带**必须**变；
///   · 同一族渲染两遍 ⇒ 这一带**必须逐像素相同**；
///   · 上方**多出一行提示**（系统等宽 → 不存在的族）或**回落到系统等宽**（Helvetica）⇒
///     这一带**必须相同**（对照：否则它只是「随便一段变得很多的区域」）。
final class AppearanceFontProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针要渲染真视图树：DOYAH_UI_SNAPSHOT=1 才跑（与快照同一条纪律：取证才跑，门禁不跑）"
        )
    }

    /// 与 `UISnapshotPanelsTests.testDesignThemeSwitcher` 同一块面板、同一个视口 —— 便于互相对照。
    private let panelSize = CGSize(width: 560, height: 700)

    /// SQL 预览那一行在快照里的位置（**距图底**，单位 px，2× 缩放）。
    ///
    /// 来源 = **实测**（第 93 轮标定）：渲染「Menlo / Courier New」两遍逐行比较，差异只落在
    /// y 530…552（图高 1400，即距图底 848…870）—— 那正是预览那一行的字形墨迹；
    /// 取 840 / 高 36 的带把它整行框住，并把上方文本框下沿与下方分隔线让出去。
    /// 位置**不靠自觉维护**：下面两条对照（同一族两遍逐像素相同、上方多一行提示时这一带不变）
    /// 会在面板布局被改动时先红。
    private let previewBandFromBottom = 840
    private let previewBandHeight = 36

    /// 预览那一行字面量有 **46 个字符**（面板里那句 `select id, name from orders where total > 100;`）
    /// —— 2× 渲染下每个字符至少亮 1 个像素，所以带的墨迹下限取 46（实测远高于此，打印在输出里）。
    private let minimumPreviewInk = 46

    // MARK: - 宿主

    @MainActor
    private func makeHost() -> (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    ) {
        let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        return (
            state,
            WorkspaceStore.shared,
            WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("appearance-font-\(UUID().uuidString).json")
                )
            ),
            TerminalModel()
        )
    }

    // MARK: - 渲染一个字体偏好下的外观面板

    /// 在**宿主语境**下渲染一遍外观面板：`family` 为 `nil` = 系统等宽。
    ///
    /// 两件事同时钉住：① 造态**没落盘**（`FontManager.shared.preference` 一字未动）；
    /// ② 渲染后（离屏宿主会泵运行循环）覆盖仍在 —— 否则下面断言的是「另一遍的界面」。
    @MainActor
    private func render(
        _ name: String,
        family: String?,
        size: Int = MonospaceFontSize.default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UISnapshot.LanguagePair {
        let host = makeHost()
        let preference = MonospaceFontPreference(family: family, size: size)
        let diskBefore = FontManager.shared.preference

        FontManager.shared.beginHostPreference(preference)
        defer { FontManager.shared.endHostPreference() }

        let pair = try UISnapshot.writeBothLanguages(name, size: panelSize) {
            AppearanceSheet(initialScrollAnchor: .bottom).snapshotEnvironment(
                state: host.state,
                workspace: host.workspace,
                tabs: host.tabs,
                terminal: host.terminal
            )
        }

        XCTAssertEqual(
            FontManager.shared.effectivePreference, preference,
            "\(name)：渲染完之后宿主覆盖不在了 —— 这一遍量的不是注入的那个偏好",
            file: file, line: line
        )
        XCTAssertEqual(
            FontManager.shared.preference, diskBefore,
            "\(name)：造态改了落盘的字体偏好 —— 宿主语境只该覆盖、不该落盘",
            file: file, line: line
        )
        return pair
    }

    /// 这一遍渲染里，`key` 按它的语言应当长成什么样（与渲染**同一条取值路径**）。
    @MainActor
    private func text(_ language: AppLanguage, _ key: LKey, _ arguments: CVarArg...) -> String {
        UISnapshot.localizedText(language) { L(key, arguments) }
    }

    /// 「这句文案在**这一遍**（中 / 英各一）里该 / 不该出现」。
    ///
    /// `arguments` 按**语言**给：有些参数本身也是界面文案（例如选项名「系统等宽」中英不同），
    /// 拿中文那遍取到的值去比英文那遍，比的是两样东西（第 93 轮实测踩到过）。
    @MainActor
    private func assertPresence(
        _ pair: UISnapshot.LanguagePair,
        side: String,
        key: LKey,
        arguments: @escaping (AppLanguage) -> [CVarArg],
        shouldAppear: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for record in pair.records {
            let language = AppLanguage(rawValue: record.language) ?? .simplifiedChinese
            let expected = text(language, key, arguments(language))
            let found = record.localizedStrings.contains(expected)
            XCTAssertEqual(
                found,
                shouldAppear,
                "\(side)·\(language.rawValue)：文案「\(expected)」\(shouldAppear ? "应当出现" : "不该出现")，"
                    + "实际\(found ? "出现了" : "没出现")（快照 \(record.name)）",
                file: file, line: line
            )
        }
    }

    // MARK: - ③④ FR-EDIT-26：手输字体族之后界面说的话

    @MainActor
    func testFontFamilySentencesReachTheInterface() throws {
        // 前置：本机得真有这两个族，否则这条判据判的是别的东西。
        XCTAssertTrue(
            FontManager.availableMonospacedFamilies.contains("Menlo"),
            "本机没有 Menlo（系统自带等宽族）—— 先确认字体环境，再来判这条"
        )
        XCTAssertTrue(
            FontManager.availableAllFamilies.contains("Helvetica"),
            "本机没有 Helvetica（系统自带**比例**字体）—— 先确认字体环境，再来判这条"
        )
        /// 各语言下「系统等宽」这个**选项名**（它本身也是界面文案）。
        let systemMono: (AppLanguage) -> [CVarArg] = { [unowned self] language in
            [self.text(language, .appearanceMonoSystem)]
        }

        // ① 手输**小写** `menlo`：生效，且「当前使用」给的是系统里的**正确拼写**。
        let resolved = try render("manual-check-font-family-resolved", family: "menlo")
        assertPresence(resolved, side: "已装等宽", key: .appearanceMonoEffective,
                       arguments: { _ in ["Menlo"] }, shouldAppear: true)
        assertPresence(resolved, side: "已装等宽", key: .appearanceMonoNotMonospaced,
                       arguments: { _ in ["Menlo"] }, shouldAppear: false)
        assertPresence(resolved, side: "已装等宽", key: .appearanceMonoFallback,
                       arguments: { _ in ["Menlo"] }, shouldAppear: false)

        // ② 手输**非等宽** `Helvetica`：必须明确说「存在但不是等宽」，**不是**静默回落。
        let notMonospaced = try render("manual-check-font-family-not-monospaced", family: "Helvetica")
        assertPresence(notMonospaced, side: "非等宽", key: .appearanceMonoNotMonospaced,
                       arguments: { _ in ["Helvetica"] }, shouldAppear: true)
        assertPresence(notMonospaced, side: "非等宽", key: .appearanceMonoFallback,
                       arguments: { _ in ["Helvetica"] }, shouldAppear: false)
        assertPresence(notMonospaced, side: "非等宽", key: .appearanceMonoEffective,
                       arguments: systemMono, shouldAppear: true)

        // ③ 手输一个**不存在**的族：说的是另一句（「不可用 / 已回落」），不许与非等宽混成一句。
        let unknown = try render("manual-check-font-family-unknown", family: "NoSuchFamilyXYZ")
        assertPresence(unknown, side: "不存在的族", key: .appearanceMonoFallback,
                       arguments: { _ in ["NoSuchFamilyXYZ"] }, shouldAppear: true)
        assertPresence(unknown, side: "不存在的族", key: .appearanceMonoNotMonospaced,
                       arguments: { _ in ["NoSuchFamilyXYZ"] }, shouldAppear: false)

        // ④ 没选族（系统等宽）：两句提示**都不该出现**（别无事生非）。
        let systemDefault = try render("manual-check-font-family-system", family: nil)
        assertPresence(systemDefault, side: "系统等宽", key: .appearanceMonoNotMonospaced,
                       arguments: systemMono, shouldAppear: false)
        assertPresence(systemDefault, side: "系统等宽", key: .appearanceMonoFallback,
                       arguments: systemMono, shouldAppear: false)
        assertPresence(systemDefault, side: "系统等宽", key: .appearanceMonoEffective,
                       arguments: systemMono, shouldAppear: true)

        // ⑤ 两句文案**本身**就不是一句（防「两档共用一个键」这种退化）—— 拿同一族名代进去比。
        let notMonospacedSentence = text(.simplifiedChinese, .appearanceMonoNotMonospaced, "X")
        let fallbackSentence = text(.simplifiedChinese, .appearanceMonoFallback, "X")
        XCTAssertNotEqual(
            notMonospacedSentence, fallbackSentence,
            "「存在但不是等宽」与「系统里没有这个族」必须是**两句不同的话** —— 混成一句，用户会一直以为自己选对了"
        )

        // ⑥ 四态的文案集两两不同（否则上面比的是同一张图）。
        let sets = [resolved, notMonospaced, unknown, systemDefault].map { Set($0.records[0].localizedStrings) }
        for (lhs, rhs) in [(0, 1), (0, 2), (1, 2), (1, 3), (2, 3)] {
            XCTAssertNotEqual(
                sets[lhs], sets[rhs],
                "两态的文案集相同 ⇒ 界面根本没把这两个偏好区分开"
            )
        }

        // ⑦ ② 的交付面：编辑器 / 终端 / 预览共用的那一个入口，交出的就是注入的那个族与字号。
        FontManager.shared.beginHostPreference(MonospaceFontPreference(family: "Menlo", size: 15))
        defer { FontManager.shared.endHostPreference() }
        XCTAssertEqual(
            FontManager.shared.monospaceNSFont().familyName, "Menlo",
            "`Theme.font(.mono)`（编辑器 / 终端 / SQL 预览共用）交出的不是注入的族"
        )
        XCTAssertEqual(
            FontManager.shared.monospaceNSFont().pointSize, 15,
            "字号没跟着走（同一个入口）"
        )
    }

    // MARK: - ⑤ FR-EDIT-26：SQL 预览的字形跟着字体走

    @MainActor
    func testPreviewGlyphsFollowTheFamily() throws {
        XCTAssertTrue(
            FontManager.availableMonospacedFamilies.contains("Menlo")
                && FontManager.availableMonospacedFamilies.contains("Courier New"),
            "本机缺 Menlo / Courier New（两个系统自带等宽族）—— 先确认字体环境，再来判这条"
        )

        let menlo = try render("manual-check-font-preview-menlo", family: "Menlo")
        let courier = try render("manual-check-font-preview-courier-new", family: "Courier New")
        let menloAgain = try render("manual-check-font-preview-menlo-again", family: "Menlo")
        let systemDefault = try render("manual-check-font-preview-system", family: nil)
        let unknown = try render("manual-check-font-preview-unknown", family: "NoSuchFamilyXYZ")
        let notMonospaced = try render("manual-check-font-preview-not-monospaced", family: "Helvetica")

        func band(_ pair: UISnapshot.LanguagePair, _ name: String) throws -> UISnapshot.Band {
            let record = try XCTUnwrap(pair.records.first, "\(name)：这一遍没有产物")
            let band = try XCTUnwrap(
                UISnapshot.band(ofPNGAt: record.file, fromBottom: previewBandFromBottom, height: previewBandHeight),
                "\(name)：取不出取样带（图没落盘？）"
            )
            XCTAssertGreaterThanOrEqual(
                band.ink, minimumPreviewInk,
                "\(name)：取样带里只有 \(band.ink) 个非背景像素 —— 那一带没画上预览（取样带位置或面板布局变了？）"
            )
            print("🎯 \(name)：取样带 \(band.width)×\(band.height)px，墨迹 \(band.ink) 像素（下限 \(minimumPreviewInk)）")
            return band
        }

        let menloBand = try band(menlo, "Menlo")
        let courierBand = try band(courier, "Courier New")
        let menloAgainBand = try band(menloAgain, "Menlo（第二遍）")
        let systemBand = try band(systemDefault, "系统等宽")
        let unknownBand = try band(unknown, "不存在的族")
        let notMonospacedBand = try band(notMonospaced, "非等宽（Helvetica）")

        func difference(_ lhs: UISnapshot.Band, _ rhs: UISnapshot.Band, _ label: String) throws -> Int {
            try XCTUnwrap(UISnapshot.differingPixels(lhs, rhs), "\(label)：两带尺寸不一致，比不了")
        }

        // ① 换族 ⇒ 这一带必须变（Menlo 是无衬线、Courier New 是打字机衬线，字形差别肉眼可见）。
        let changed = try difference(menloBand, courierBand, "Menlo vs Courier New")
        XCTAssertGreaterThan(
            changed, 0,
            "换成另一个等宽族之后，SQL 预览那一行**逐像素完全相同** —— 预览是张不跟字体走的假样张？"
        )

        // ② 同一族渲染两遍 ⇒ 这一带必须逐像素相同（判据自己不能抖）。
        let stable = try difference(menloBand, menloAgainBand, "Menlo 两遍")
        XCTAssertEqual(stable, 0, "同一个字体渲染两遍，取样带却差了 \(stable) 个像素 —— 先把抖动查清再谈别的")

        // ③ 对照一：上方**多出一行提示**（系统等宽 → 不存在的族）时这一带不许动 ——
        //     生效族没变（都回落系统等宽），变的只是上面那句提示。
        let warningOnly = try difference(systemBand, unknownBand, "系统等宽 vs 不存在的族")
        XCTAssertEqual(
            warningOnly, 0,
            "上方多了一句提示、生效字体没变，取样带却差了 \(warningOnly) 个像素 —— 取样带取的不是预览那一行"
        )

        // ④ 对照二：非等宽（Helvetica）回落系统等宽 ⇒ 预览字形也不该变。
        let fallbackOnly = try difference(systemBand, notMonospacedBand, "系统等宽 vs 非等宽回落")
        XCTAssertEqual(
            fallbackOnly, 0,
            "回落到系统等宽之后预览字形却变了 \(fallbackOnly) 个像素 —— 回落那条路没走对"
        )

        print("✅ 换族差异 \(changed) 像素 / 同族重跑 \(stable) / 只多提示 \(warningOnly) / 非等宽回落 \(fallbackOnly)")
    }

    override class func tearDown() {
        UISnapshot.finishManifestIfEnabled()
        super.tearDown()
    }
}
