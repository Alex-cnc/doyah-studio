import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 格式化入口**真的能跑到页签上**（内测 `#2` 第二轮打回，原话：「**格式化菜单有了，但并不具备格式化能力**，
/// 我把一个 json 文件打乱了，点击格式没反应。快捷键貌似也没反应——之前有」）。
///
/// 这条链上任何一处断掉，用户看到的都是同一句「点了没反应」，所以三处缝各一条判据：
///   ① **页签语言判定**：`.json` 路径必须判成 `TextLanguage.json`（判成 fallback ⇒ 只会得到一句拒绝）；
///   ② **模型那条路**：乱掉的 JSON 走 `formatSelected()` 必须真的**投递**重排后的文本；
///   ③ **菜单项**：主菜单「编辑」里那一项必须带**可执行的 action / target**，并真调用一次
///      （`NSApp.sendAction`）—— 「菜单里有、点下去没人接」正是这一轮的报障形态。
///
/// 边界（如实）：③ 判的是「菜单项本身能不能触发」；它落到哪个页签取决于当时选中的页签，
/// 探针不替需求提出者点界面（真正的「点下去画面变了」仍要人在场看一眼）。
@MainActor
final class FormatMenuWiringProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "格式化入口探针要真调用产品接口：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    private func makeScrambledJSON() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("format-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("scrambled.json")
        try "{\"a\":1,\"b\":{\"c\":[1,2,3]},\"d\":\"x\"}".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// ① + ②：语言判定与投递。
    func testScrambledJSONThroughTheModelPath() async throws {
        let file = try makeScrambledJSON()
        let tabs = WorkspaceTabsModel()
        tabs.openFile(at: file)
        guard let tab = tabs.tabs.first(where: { !$0.isHome }) else {
            return XCTFail("JSON 没开成页签")
        }
        XCTAssertEqual(tab.language, .json, "页签语言判定错了 ⇒ 格式化只会得到一句拒绝")
        tabs.select(tab.id)
        tabs.formatSelected()
        for _ in 0..<200 {
            if tabs.formatDelivery != nil || tabs.errorText != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(tabs.errorText, "格式化被拒绝了：\(tabs.errorText ?? "")")
        guard let delivery = tabs.formatDelivery else {
            return XCTFail("格式化**没有投递**（notice=\(tabs.noticeText ?? "nil")）⇒ 界面上就是「点了没反应」")
        }
        XCTAssertNotEqual(delivery.text, tab.content, "投递的文本与原文一模一样 ⇒ 等于没格式化")
        XCTAssertNotNil(tabs.noticeText, "没有给用户一句「做了什么」")
    }

    /// ③：主菜单「编辑」里那一项**真的能触发**。
    func testEditMenuFormatItemCarriesAnAction() throws {
        // 这个宿主**不是**真 App 进程：`NSApp` 是 nil、菜单树根本不存在 ⇒ 菜单那一面交给
        // `DOYAH_MENU_DUMP=<文件> ./dist/DoyahStudio-alpha2.0.app/Contents/MacOS/DoyahStudio`
        // （实测该口子会打印每项的 selector/target ⇒ 能判「菜单里有、点下去没人接」）。
        guard let mainMenu = NSApplication.shared.mainMenu else {
            throw XCTSkip("本宿主没有真菜单树（菜单要在真 App 进程里才建）⇒ 见 DOYAH_MENU_DUMP")
        }
        var found: NSMenuItem?
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if item.title.contains("格式化代码") || item.title.contains("Format Code") { found = item }
                if let submenu = item.submenu { walk(submenu) }
            }
        }
        walk(mainMenu)
        guard let item = found else {
            return XCTFail("主菜单里找不到那一项（内测 `#2` 的入口又没了）")
        }
        XCTAssertNotNil(item.action, "菜单项没有 action ⇒ 点下去没人接（这一轮的报障形态）")
        XCTAssertNotNil(item.target, "菜单项没有 target ⇒ 点下去没人接")
        guard let action = item.action else { return }
        XCTAssertTrue(
            NSApp.sendAction(action, to: item.target, from: item),
            "菜单项的 action 送不到（`NSApp.sendAction` 没接住）"
        )
    }
    // MARK: - ④ 投递**落到编辑器里**（这一条才是「点了没反应」的那一面）

    /// 只判「模型投递了」不够：投递之后**视图有没有真的换上去**才是用户看到的。
    /// 这一段把真 `CodeEditorView` 放进活宿主、读真 `CodeTextView` 里的文本 ——
    /// 与 `MultiCursorProbeTests` 同一条路线（自己点自己、零权限）。
    @MainActor
    func testDeliveryActuallyLandsInTheRealEditor() throws {
        let file = try makeScrambledJSON()
        let tabs = WorkspaceTabsModel()
        tabs.openFile(at: file)
        guard let tab = tabs.tabs.first(where: { !$0.isHome }) else { return XCTFail("JSON 没开成页签") }
        tabs.select(tab.id)

        let host = UISnapshot.LiveHost(Harness(tabs: tabs, tabID: tab.id), size: CGSize(width: 720, height: 320))
        host.pump(0.4)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里 —— 判据的入口没了"
        )
        XCTAssertEqual(textView.string, tab.content, "编辑器里应当是那个被打乱的 JSON")

        tabs.formatSelected()
        host.pump(0.8)
        XCTAssertNotEqual(
            textView.string, "{\"a\":1,\"b\":{\"c\":[1,2,3]},\"d\":\"x\"}",
            "格式化之后编辑器里**还是原来那段** ⇒ 用户看到的就是「点了没反应」"
        )
        XCTAssertTrue(
            textView.string.contains("\n  ") || textView.string.contains("\n    "),
            "格式化之后的文本应当有缩进换行，实际是：\(textView.string.prefix(60))"
        )
    }

    /// 活宿主里只放一个真编辑器，数据源是真模型（与工作区那棵树同形）。
    private struct Harness: View {
        @ObservedObject var tabs: WorkspaceTabsModel
        let tabID: UUID

        var body: some View {
            CodeEditorView(
                tabID: tabID,
                text: tabs.tabs.first(where: { $0.id == tabID })?.content ?? "",
                language: tabs.tabs.first(where: { $0.id == tabID })?.language ?? .plainText,
                pendingFormat: tabs.formatDelivery,
                pendingReveal: nil,
                onTextChange: { tabs.updateContent($0, for: tabID) },
                onSave: {},
                onFormat: { tabs.formatSelected() },
                onCursorLine: { _ in }
            )
        }
    }
}
