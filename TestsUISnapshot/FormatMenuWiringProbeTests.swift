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

    /// ③：主菜单「编辑」里那一项**真的接在同一条路上**。
    ///
    /// 原来这一条是「读真 `NSApp.mainMenu`，本宿主没有菜单树就 `XCTSkip`」—— **跳过不算通过**，
    /// 于是它在门禁里等于零证据（`verify-ui-interactions` 的收尾核对把 skipped 直接判红）。
    /// 改成两段，**永远跑第一段**：
    ///   · 源锚点（本进程可判）：命令组 `CommandGroup(after: .pasteboard)` 里那一项、菜单键
    ///     `L(.menuFormat)`、动作打的是**唯一入口** `tabs.formatSelected()`、⇧⌘F 全 App 只注册一处；
    ///   · 有真菜单树时再加判：`action` / `target` 非空且 `NSApp.sendAction` 接得住
    ///     （真 App 进程那条路由由 `DOYAH_MENU_DUMP=<文件>` 取，读数见证据文件）。
    func testEditMenuFormatItemIsWiredToTheSameEntry() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let commands = try String(
            contentsOf: root.appendingPathComponent("App/DoyahStudioCommands.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(commands.contains("CommandGroup(after: .pasteboard)"),
                      "主菜单「编辑」那一组里没有条目 —— 用户找的就是那儿")
        XCTAssertTrue(commands.contains("L(.menuFormat)"), "「编辑」里那一项没有用无占位符的菜单键")
        XCTAssertTrue(commands.contains("workspaceTabs.formatSelected()"),
                      "「编辑」里的格式化没有打到工作区页签上（菜单与快捷键必须同一个入口）")

        // ⇧⌘F 只许注册一处：同一快捷键挂两个菜单项时 AppKit 只认一个，另一项就是摆设。
        let appRoot = root.appendingPathComponent("App")
        var registrations: [(String, Int)] = []
        for file in try FileManager.default.subpathsOfDirectory(atPath: appRoot.path)
        where file.hasSuffix(".swift") {
            let text = try String(contentsOf: appRoot.appendingPathComponent(file), encoding: .utf8)
            let count = text.components(separatedBy: "keyboardShortcut(AppShortcut.formatCode").count - 1
            if count > 0 { registrations.append((file, count)) }
        }
        XCTAssertEqual(registrations.reduce(0) { $0 + $1.1 }, 1,
                       "⇧⌘F 注册了 \(registrations.reduce(0) { $0 + $1.1 }) 处：\(registrations) —— 只许一处")

        // 快捷键本身：⌘ + ⇧ + `f`（源码里这两档分开写在 `key` / `modifiers` 两个 switch 里）。
        let shortcuts = try String(
            contentsOf: root.appendingPathComponent("App/ShortcutCatalog.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(shortcuts.contains("case .formatCode: return \"f\""), "格式化快捷键不再是 ⌘⇧F")
        XCTAssertTrue(
            shortcuts.contains(".history, .clearEditor, .format, .formatCode,"),
            "`formatCode` 不在「⌘ + ⇧」那一档里"
        )

        // 真 App 进程里再判一层（本宿主没有菜单树时**不跳过、也不假绿**：上一段已经把
        //「菜单项存在且打到同一入口」判掉了，这一层只是趁有树时把 AppKit 的连线也读完）。
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        var found: NSMenuItem?
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if item.title.contains("格式化代码") || item.title.contains("Format Code") { found = item }
                if let submenu = item.submenu { walk(submenu) }
            }
        }
        walk(mainMenu)
        guard let item = found else {
            return XCTFail("真菜单树里有，但没有那一项（内测 `#2` 的入口又没了）")
        }
        XCTAssertNotNil(item.action, "菜单项没有 action ⇒ 点下去没人接")
        XCTAssertNotNil(item.target, "菜单项没有 target ⇒ 点下去没人接")
        guard let action = item.action else { return }
        XCTAssertTrue(
            NSApp.sendAction(action, to: item.target, from: item),
            "菜单项的 action 送不到（`NSApp.sendAction` 没接住）"
        )
    }

    /// ②：**撤销后与格式化前逐字一致**（需求原文），而且模型里的正文也回到原文。
    ///
    /// 为什么这一条必须动真格：投递走的是 `content` 直改的话，界面上「看起来格式化了」，
    /// 而 ⌘Z 拿不回来 —— 那正是 `FormatDelivery` 存在的理由。判据三件：
    /// 格式化之后编辑器里真的变了 → 一次撤销 → **逐字**等于原文（视图与模型都算）。
    @MainActor
    func testFormatIsUndoableBackToTheExactOriginal() throws {
        let file = try makeScrambledJSON()
        let original = try String(contentsOf: file, encoding: .utf8)
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
        XCTAssertEqual(textView.string, original, "开局应当就是那个被打乱的 JSON")

        tabs.formatSelected()
        host.pump(0.8)
        XCTAssertNotEqual(textView.string, original, "格式化之后编辑器里还是原文 ⇒ 等于没格式化")
        guard let undoManager = textView.undoManager else {
            return XCTFail("编辑器没有撤销管理器 ⇒ 「可撤销」这条判据无从成立（不是通过）")
        }
        XCTAssertTrue(undoManager.canUndo, "格式化这一步没有进撤销栈 ⇒ ⌘Z 拿不回来")

        undoManager.undo()
        host.pump(0.3)
        XCTAssertEqual(textView.string, original, "撤销之后与格式化前不逐字一致")
        XCTAssertEqual(tabs.tabs.first(where: { $0.id == tab.id })?.content, original,
                       "模型里的正文没有跟着撤销回来（下一次保存会把格式化结果写回磁盘）")
    }

    /// ⑤：**该语言没有内置档时明说未支持** —— 不静默、不改内容、不说「没反应」。
    ///
    /// 收口在两处：模型给出的那句拒绝（`errorText` 有话说、投递为空、正文一字未动），
    /// 以及语言表里那句拒绝文案本身不许再提「外部工具没装」（定案「只用内置」之后，
    /// 那句话在事实上是假的 —— 这条路根本不去探外部工具）。
    @MainActor
    func testLanguageWithoutABuiltinSaysSoAndLeavesTheTextAlone() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("format-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("notes.txt")
        let text = "a:  1\nb:  2\n"
        try text.write(to: file, atomically: true, encoding: .utf8)

        let tabs = WorkspaceTabsModel()
        tabs.openFile(at: file)
        guard let tab = tabs.tabs.first(where: { !$0.isHome }) else { return XCTFail(".txt 没开成页签") }
        XCTAssertEqual(tab.language, .plainText, "`.txt` 应当落在纯文本（认不出语言那一档）")
        tabs.select(tab.id)

        tabs.formatSelected()
        // 格式化是**异步**的（`nonisolated` 那段搬去协作线程池）：拒绝那句话要等它落回主线程。
        for _ in 0..<200 {
            if tabs.errorText != nil || tabs.formatDelivery != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(tabs.formatDelivery, "没有内置档却投递了文本 —— 这是「静默改了」")
        XCTAssertEqual(tabs.tabs.first(where: { $0.id == tab.id })?.content, text, "拒绝时正文一个字都不该动")
        XCTAssertEqual(tabs.errorText, L(.workspaceFormatRefusedUnknown), "认不出语言时那一句没说清")

        // 没有内置档那一档（今天没有语言走到它，但话术必须与定案一致）：
        for language in [AppLanguage.simplifiedChinese, .english] {
            let message = LocalizedStrings.text(.workspaceFormatRefusedNoFormatter, language: language)
            XCTAssertTrue(message.contains("%@"), "\(language) 那一句丢了语言名占位符")
            for stale in ["外部工具", "external tool", "PATH"] {
                XCTAssertFalse(message.contains(stale),
                               "\(language) 的拒绝文案还在提 \(stale) —— 定案是「只用内置」，这说法不成立")
            }
        }
        XCTAssertTrue(
            LocalizedStrings.text(.workspaceFormatRefusedNoFormatter, language: .simplifiedChinese)
                .contains("内置"),
            "简体中文那句没有说明「没有内置档」"
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
