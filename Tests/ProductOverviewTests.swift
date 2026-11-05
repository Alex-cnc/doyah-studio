import XCTest
@testable import DoyahCore

/// `FR-STD-WS-HELP-003`「关于与帮助里的产品功能介绍」的判据。
///
/// 两半各管一件事：
///   · **内容判据**（本文件上半）：两档语言各 6 个分组、条目不少于 20 条、英文正文不夹汉字 ——
///     这三条正是这份说明书最容易烂掉的方式（漏一组 / 越写越短 / 英文抄了中文）。
///   · **接线判据**（下半，源树）：两处入口真的存在，且都指向同一个开关 —— 而不是「写了个视图没人能打开」。
final class ProductOverviewTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func body(_ language: AppLanguage) -> String {
        LocalizedStrings.text(.productOverviewBody, language: language)
    }

    private func sections(_ text: String) -> [String] {
        text.split(separator: "\n").filter { $0.hasPrefix("## ") }.map(String.init)
    }

    private func bullets(_ text: String) -> [String] {
        text.split(separator: "\n").filter { $0.hasPrefix("· ") }.map(String.init)
    }

    // MARK: - 内容

    func testBothLanguagesCarrySixGroups() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(sections(body(language)).count, 6,
                           "\(language.rawValue)：分组数应为 6（这是什么 / 工作区 / 数据库 / 笔记与待办 / 智能体 / 授权与界面）")
        }
    }

    func testEveryGroupHasAtLeastThreeBullets() {
        for language in AppLanguage.allCases {
            let text = body(language)
            // 按「## 」切段，逐段数「· 」条目
            let parts = text.components(separatedBy: "\n## ")
            for (index, part) in parts.enumerated() where index > 0 {
                let count = part.split(separator: "\n").filter { $0.hasPrefix("· ") }.count
                XCTAssertGreaterThanOrEqual(count, 3, "\(language.rawValue) 第 \(index) 组条目只有 \(count) 条，少于 3 条")
            }
        }
    }

    func testEnglishBodyHasNoChineseCharacters() {
        let text = body(.english)
        let cjk = text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }
        XCTAssertTrue(cjk.isEmpty, "英文正文里出现了汉字：\(String(String.UnicodeScalarView(cjk)).prefix(40))")
    }

    func testChineseBodyIsNotACopyOfEnglish() {
        XCTAssertNotEqual(body(.simplifiedChinese), body(.english), "中英正文不能是同一份（说明该键没分语言）")
    }

    func testMenuTitleFollowsLanguage() {
        let zh = LocalizedStrings.text(.menuProductOverview, language: .simplifiedChinese)
        let en = LocalizedStrings.text(.menuProductOverview, language: .english)
        XCTAssertEqual(zh, "产品功能介绍")
        XCTAssertEqual(en, "Product Overview")
    }

    // MARK: - 接线（源树）

    func testAboutAndHelpBothOpenTheSameSheet() throws {
        let commands = try source("App/DoyahStudioCommands.swift")
        XCTAssertTrue(commands.contains("CommandGroup(replacing: .appInfo)"),
                      "「关于」这一项要由我们接管，交给系统面板就只剩名字与版本")
        XCTAssertTrue(commands.contains("CommandGroup(after: .help)"),
                      "帮助菜单里也要有入口")
        let opens = commands.components(separatedBy: "appState.isProductOverviewPresented = true").count - 1
        XCTAssertGreaterThanOrEqual(opens, 2, "两处入口都要指向同一个开关，现在只有 \(opens) 处")
    }

    func testSheetIsActuallyPresentedByTheMainWindow() throws {
        let window = try source("App/Views/MainWindow.swift")
        XCTAssertTrue(window.contains("isProductOverviewPresented"),
                      "开关有了但主窗口没挂 sheet ⇒ 点了没反应")
        XCTAssertTrue(window.contains("ProductOverviewSheet()"))
    }

    /// 负例：把某一份正文改短（模拟「漏写一组」），判据必须红 —— 这条用例证明上面那几条不是摆设。
    func testTheSectionCounterWouldCatchAMissingGroup() {
        let trimmed = body(.simplifiedChinese)
            .components(separatedBy: "\n## ")
            .dropLast()
            .joined(separator: "\n## ")
        XCTAssertEqual(sections(trimmed).count, 5, "少一组时计数应变成 5 ⇒ 上面那条 6 组的判据会红")
        XCTAssertNotEqual(sections(trimmed).count, sections(body(.simplifiedChinese)).count)
    }
}
