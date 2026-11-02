import XCTest
@testable import DoyahCore

/// `FR-STD-ALL-LIC-002` / `-003` / `FR-STD-WS-LIC-001` 的**呈现面**判据。
///
/// 这三条判的都是「授权怎么露在界面上」，而它们最容易退化的方式是**接线断掉**：
/// 活动栏改成画 `allCases`、Home 与帮助各写一句状态、到期判定被搬进数据路径、
/// 笔记插件开始读许可证 —— 这些都不是单测能「跑出来」的，只能扫源树钉住。
///
/// **覆盖边界（如实）**：静态扫描判得住「有人改了这几个接线点」，判不住「界面画出来好不好看」；
/// 真鼠标点验记未覆盖（证据文件里单列）。
final class LicensePresentationScopeTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: - 002：按授权呈现入口（不是灰掉）

    /// Standard 下工作区 / 数据库**不出现**（不是出现后灰掉）。
    func testStandardHidesWorkspaceAndDatabaseInsteadOfGreyingThem() {
        let items = LicensePresentation.activityItems(for: .notesOnly)
        XCTAssertTrue(items.contains(.notes))
        XCTAssertFalse(items.contains(.workspace), "未授权的工作区必须不出现")
        XCTAssertFalse(items.contains(.database), "未授权的数据库必须不出现")
        // 周报（Retro）不挂授权 ⇒ 全档可见（`M7` 判据 ①），所以它在结果里是**对的**
        XCTAssertTrue(items.contains(.retro))
    }

    func testUltraShowsAllAreas() {
        let items = LicensePresentation.activityItems(for: .all)
        XCTAssertTrue(items.contains(.workspace) && items.contains(.database) && items.contains(.notes))
        XCTAssertEqual(
            items,
            ActivityBarItem.allCases.filter { items.contains($0) },
            "Ultra 下除挂点过滤外一项都不该少（顺序沿用 allCases）"
        )
    }

    /// 活动栏只画「该出现的那几项」，并且**没有**一条把未授权项灰掉的路径。
    func testActivityBarDrawsOnlyTheVisibleItemsAndNeverGreysOutHiddenOnes() throws {
        let view = try source("App/Views/ActivityBarView.swift")
        XCTAssertTrue(
            view.contains("ForEach(appState.visibleActivityItems)"),
            "活动栏必须画 visibleActivityItems（许可 + 挂点的唯一出口）"
        )
        XCTAssertFalse(view.contains("ActivityBarItem.allCases"), "不许绕开许可自己画全量")
        XCTAssertFalse(view.contains(".disabled("), "未授权的项是**不出现**，不是灰掉诱导")
    }

    /// 「版本与许可证」页有真入口（应用菜单里、紧挨系统「关于」），不是只有代码里能打开。
    func testAboutLicensePageHasAMenuEntry() throws {
        let commands = try source("App/DoyahStudioCommands.swift")
        XCTAssertTrue(commands.contains(".menuAboutLicense"), "菜单项文案键必须在")
        XCTAssertTrue(
            commands.contains("appState.isAboutLicensePresented = true"),
            "菜单项必须真打开那一页"
        )
        let sheet = try source("App/Views/AboutLicenseSheet.swift")
        XCTAssertTrue(sheet.contains("licAboutEdition"), "页上要说清「我现在是什么版」")
        XCTAssertTrue(sheet.contains("license-status"), "页上要说清「为什么是这一版」")
        XCTAssertTrue(sheet.contains("licAboutUpgradeTitle"), "页上要逐条列出别的版能做什么")
    }

    // MARK: - 003：到期只降呈现，不锁数据

    func testExpiredLicenseSaysWhyAndKeepsTheNotesCapability() {
        let expired = License(issuedTo: "alex", capabilities: .all, expiresAt: Date(timeIntervalSince1970: 1_000))
        let entitlements = LicenseGate.evaluate(
            expired,
            payload: Data("p".utf8),
            signature: Data("s".utf8),
            verifier: AlwaysValid(),
            now: Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertEqual(entitlements.edition, .standard)
        guard case .expired = entitlements.basis else {
            return XCTFail("到期必须给出 expired 这个依据，实际：\(entitlements.basis)")
        }
        XCTAssertEqual(
            entitlements.capabilities, .notesOnly,
            "到期退到 Standard：**笔记那一块还开着**（数据不锁）"
        )
    }

    /// 到期判定只许出现在许可证这条链路上。
    ///
    /// 只要有人把 `license.isExpired` 写进文件树 / 编辑器 / 导出 / 笔记存储，这一条就红 ——
    /// 「到期把数据锁住」正是从这种地方长出来的。
    func testExpiryIsConsultedOnlyByTheLicenseChain() throws {
        var offenders: [String] = []
        for path in try Self.swiftSources(under: ["Core", "App", "CLI", "Plugins", "Tools"]) {
            guard !path.hasSuffix("Core/License.swift"),
                  !path.hasSuffix("Core/LicenseLoader.swift"),
                  !path.hasSuffix("Tools/LicenseTool/main.swift") else { continue }
            let text = try source(path)
            if text.contains("license.isExpired") || text.contains("licenseLoad.license?.isExpired") {
                offenders.append(path)
            }
        }
        XCTAssertEqual(
            offenders, [],
            "到期只降呈现：判定不许溜进数据路径（文件树 / 编辑器 / 导出 / 笔记存储）⇒ \(offenders)"
        )
    }

    /// 笔记数据面（`Plugins/Notes`）**一个许可证符号都没有** —— 「不锁数据」的结构性证据：
    /// 存储与导出那条路径根本不知道许可证存在，到期与未授权都改不了它的行为。
    func testNotesDataSurfaceDoesNotKnowAboutLicenses() throws {
        var offenders: [String] = []
        for path in try Self.swiftSources(under: ["Plugins/Notes/Sources"]) {
            let text = try source(path).lowercased()
            if text.contains("license") || text.contains("licence") || text.contains("entitlement") {
                offenders.append(path)
            }
        }
        XCTAssertEqual(offenders, [], "笔记数据面不该读许可证（否则到期就能锁数据）⇒ \(offenders)")
    }

    // MARK: - WS-LIC-001：Home 与帮助里能查到版本与授权状态

    func testStatusLineCarriesVersionEditionAndReasonInBothLanguages() {
        let load = LicenseLoader.LoadResult(
            entitlements: LicenseEntitlements(
                edition: .ultra, capabilities: .all, basis: .licensed, note: ""
            ),
            license: License(issuedTo: "alex", capabilities: .all),
            source: .missing
        )
        let zh = LicenseStatusLine.text(version: "0.6.0", load: load, language: .simplifiedChinese)
        XCTAssertTrue(zh.contains("Doyah Studio 0.6.0"), "版本号要在这一行里：\(zh)")
        XCTAssertTrue(zh.contains("Ultra"), "档位要在这一行里：\(zh)")
        XCTAssertTrue(zh.contains("没有许可证") || zh.contains("许可证"), "依据要在这一行里：\(zh)")

        let en = LicenseStatusLine.text(version: "0.6.0", load: load, language: .english)
        XCTAssertTrue(en.contains("Doyah Studio 0.6.0"))
        XCTAssertTrue(en.contains("Ultra"))
        XCTAssertFalse(
            en.contains("许可证"),
            "英文界面上这一行不许漏中文（语言由调用方给）：\(en)"
        )
    }

    /// Home 与帮助**调的是同一个函数**，并且各自都带了自己的无障碍标识（点验的抓手）。
    func testHomeAndHelpShareOneStatusLine() throws {
        let home = try source("App/Views/WorkspaceAreaView.swift")
        XCTAssertTrue(home.contains("LicenseStatusLine.text("), "Home 那一行必须走 LicenseStatusLine")
        XCTAssertTrue(home.contains("home-license-status"), "Home 那一行要有可点验的标识")

        let help = try source("App/Views/QueryToolbar.swift")
        XCTAssertTrue(help.contains("LicenseStatusLine.text("), "帮助面板那一行必须走同一个函数")
        XCTAssertTrue(help.contains("help-license-status"), "帮助面板那一行要有可点验的标识")
    }

    // MARK: - 辅助

    private struct AlwaysValid: LicenseSignatureVerifying {
        func isValid(payload: Data, signature: Data) -> Bool { true }
    }

    /// 递归列出若干目录下的 `.swift`（相对仓库根），跳过 `.build` / `Vendor`。
    private static func swiftSources(under roots: [String]) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        var results: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            guard relative.hasSuffix(".swift") else { continue }
            guard roots.contains(where: { relative.hasPrefix($0 + "/") }) else { continue }
            results.append(relative)
        }
        return results.sorted()
    }
}
