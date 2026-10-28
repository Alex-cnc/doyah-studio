import XCTest

/// `FR-STD-WS-EDIT-023` 的**源树判据**：形态必须真的接到打开 / 保存 / 状态栏三条路上。
///
/// ## 为什么这条必须有
/// `TextFileFormat` 全绿只说明"算得对"。真正会出事的是接线断在半路：
/// · 打开时按编码解了、保存却仍写死 UTF-8 ⇒ 用户改一次 GB18030 文件就被悄悄换了编码；
/// · 状态栏画了一格、菜单没接 ⇒ 需求 ③「可手动切换」是空的；
/// · 会话恢复不带形态 ⇒ 重启后第一次 ⌘S 就改掉盘上的编码。
/// 这三种都不会让 Core 判据变红，所以另立一条打在**源码锚点**上的判据。
///
/// 反过来的那一半同样要钉：保存这条路里**不许**再出现写死编码的写盘调用
/// （`write(toFile:atomically:encoding: .utf8)`）—— 它一旦回来，上面写的全白写。
final class TextFileFormatSourceTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let body = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        XCTAssertGreaterThan(body.count, 4000, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    /// 打开：走 `TextFileFormat.decode`（编码 + 换行一起判），并把形态交给页签。
    func testOpenPathDecodesFormatAndHandsItToTheTab() throws {
        let body = try text("App/WorkspaceTabsModel.swift")
        for anchor in [
            "let decoded = try TextFileFormat.decode(data)",
            "format: decoded.format)",
            "noticeText = notes.joined(separator: \" \")"
        ] {
            XCTAssertTrue(body.contains(anchor), "打开那条路缺少锚点：\(anchor)")
        }
        // 反向：不许再绕过形态直接解字节（那会把"换行怎么算"和"编码怎么算"分成两处）。
        XCTAssertFalse(body.contains("TextFileDecoder.decode(data)"),
                       "打开那条路不许再直接调解码器：形态要一次判全")
    }

    /// 保存：按这一页的形态编字节；编不出来**不写**。
    func testSaveWritesWithTheTabsOwnFormat() throws {
        let body = try text("App/WorkspaceTabsModel.swift")
        for anchor in [
            "let format = tabs[index].format",
            "guard let data = format.bytes(for: tabs[index].content) else {",
            "try data.write(to: URL(fileURLWithPath: path), options: .atomic)"
        ] {
            XCTAssertTrue(body.contains(anchor), "保存那条路缺少锚点：\(anchor)")
        }
        // 反向：写死编码的写盘调用不许回来。
        XCTAssertFalse(body.contains("write(toFile: path, atomically: true, encoding: .utf8)"),
                       "保存不许再写死 UTF-8")
    }

    /// 状态栏：一格显示 + 菜单三入口（编码 / 换行 / 重新判定），都走模型那一个入口。
    func testStatusBarMenuExposesTheThreeEntryPoints() throws {
        let body = try text("App/Views/WorkspaceAreaView.swift")
        for anchor in [
            "formatMenu(tab: tab)",
            "Text(formatLabel(tab.format))",
            "tabs.chooseEncoding(tabID: tab.id, encoding: encoding)",
            "tabs.chooseLineEnding(tabID: tab.id, lineEnding: ending)",
            "tabs.redetectFormat(tabID: tab.id)",
            "if tab.hasPendingFormatChange {"
        ] {
            XCTAssertTrue(body.contains(anchor), "状态栏那一格缺少锚点：\(anchor)")
        }
    }
}
