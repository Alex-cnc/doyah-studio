import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「模型档位」那一节的真控件（`FR-AI-32` 配置面）—— 增 / 复制 / 删 / 逐档测试四枚动作与档名输入格。
///
/// ## 为什么量真控件
///
/// 这一节的四个动作在 `AppState` 里都有单测（`AgentProfileManagementTests` 判数据与请求），
/// 但「界面上到底有没有这四枚、点得到还是灰的」只有装真视图才看得见 —— 配置层的多档
/// 在 beta1.1 就是「功能在、面板只暴露一档」，那正是这类判据要拦的坏法。
///
/// ## 判据（都能判红）
///
/// ① 三档时：下拉里就是这三条（不是一条），当前档是选中那条；
/// ② 四枚动作都落成真 `NSButton`，`performClick` 各派发一次；
/// ③ **只剩一档**时「删除」置灰（删到空 = 没有可用配置），三档时可点；
/// ④ 测试在途时「测试此档」置灰（同一档不许并发压两次），且有档名输入格。
///
/// 边界：SwiftUI 的 `Text` 在 macOS 上不落 `NSView` ⇒ 「结论那一行写的什么」判在
/// `AgentConnectionProbeTests`（文案由 `AgentConnectionOutcome.line` 出，同一处）；
/// 本文件只判控件与指派。
final class AgentProfileEditorProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主：DOYAH_UI_SNAPSHOT=1 才跑（取证工具，不进每轮门禁）"
        )
    }

    private final class Box {
        var adds = 0
        var duplicates = 0
        var deletes = 0
        var tests = 0
    }

    /// 档的端点**取自契约层**（`AgentProviderCatalog`），不在探针里写死地址 ——
    /// 预设目录是端点的唯一出处，探针也不该另开一份。
    private func profile(id: String, name: String, preset: String, model: String) -> AgentProfile {
        AgentProfile(id: id, name: name, presetID: preset,
                     endpoint: AgentProviderCatalog.preset(id: preset)?.endpoint ?? "",
                     model: model)
    }

    private func profiles() -> [AgentProfile] {
        [
            profile(id: "p1", name: "便宜本机", preset: "ollama", model: "qwen2.5:7b"),
            profile(id: "p2", name: "云端写作", preset: "deepseek", model: "deepseek-v4.1-flash"),
            profile(id: "p3", name: "代码", preset: "openai", model: "gpt-4.1"),
        ]
    }

    private func editor(
        profiles: [AgentProfile],
        canDelete: Bool,
        isTesting: Bool,
        box: Box,
        name: Binding<String> = .constant("云端写作")
    ) -> some View {
        VStack(alignment: .leading) {
            AgentProfileEditor(
                profiles: profiles,
                selectedProfileID: .constant(profiles.first?.id),
                name: name,
                canAdd: true,
                canDelete: canDelete,
                line: L(.agentProfileLastOne),
                testLine: nil,
                isTesting: isTesting,
                onAdd: { box.adds += 1 },
                onDuplicate: { box.duplicates += 1 },
                onDelete: { box.deletes += 1 },
                onTest: { box.tests += 1 }
            )
        }
        .frame(width: 640)
    }

    @MainActor
    private func host(_ view: some View) -> UISnapshot.LiveHost<AnyView> {
        let live = UISnapshot.LiveHost(AnyView(view), size: CGSize(width: 660, height: 420))
        live.pump(0.5)
        return live
    }

    // MARK: - ① 三档都在下拉里

    @MainActor
    func testThePickerListsEveryProfile() throws {
        let box = Box()
        let live = host(editor(profiles: profiles(), canDelete: true, isTesting: false, box: box))
        let popUps = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSPopUpButton.self, in: live.hosting)
        let titles = popUps.flatMap(\.itemTitles)
        for expected in ["便宜本机", "云端写作", "代码"] {
            XCTAssertTrue(titles.contains(expected),
                          "下拉里没有「\(expected)」，实际：\(titles)")
        }
        XCTAssertEqual(titles.filter { ["便宜本机", "云端写作", "代码"].contains($0) }.count, 3,
                       "同一个档出现了不止一条：\(titles)")
        print("🧪 判据①读数：下拉 = \(titles)")
    }

    // MARK: - ② 四枚动作各派发一次

    @MainActor
    func testTheFourActionsAreRealButtonsAndDispatch() throws {
        let box = Box()
        let live = host(editor(profiles: profiles(), canDelete: true, isTesting: false, box: box))
        let buttons = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSButton.self, in: live.hosting)
        let titles = buttons.map(\.title)
        for expected in [L(.agentProfileAdd), L(.agentProfileDuplicate),
                         L(.agentProfileDelete), L(.agentProfileTest)] {
            XCTAssertTrue(titles.contains(expected), "少了一枚「\(expected)」，实际：\(titles)")
        }
        func click(_ title: String) throws {
            let button = try XCTUnwrap(buttons.first { $0.title == title }, "找不到「\(title)」那一枚：\(titles)")
            XCTAssertTrue(button.isEnabled, "「\(title)」在可点状态下是灰的")
            button.performClick(nil)
        }
        try click(L(.agentProfileAdd))
        try click(L(.agentProfileDuplicate))
        try click(L(.agentProfileDelete))
        try click(L(.agentProfileTest))
        XCTAssertEqual(box.adds, 1, "点「新增档」没派发")
        XCTAssertEqual(box.duplicates, 1, "点「复制此档」没派发")
        XCTAssertEqual(box.deletes, 1, "点「删除此档」没派发")
        XCTAssertEqual(box.tests, 1, "点「测试此档」没派发")
        print("🧪 判据②读数：四枚动作各派发一次（新增 \(box.adds) / 复制 \(box.duplicates) / 删除 \(box.deletes) / 测试 \(box.tests)）")
    }

    // MARK: - ③ 只剩一档 ⇒ 删除置灰

    @MainActor
    func testDeleteIsGreyedOutWhenOnlyOneProfileIsLeft() throws {
        let box = Box()
        let live = host(editor(profiles: [profiles()[0]], canDelete: false, isTesting: false, box: box))
        let buttons = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSButton.self, in: live.hosting)
        let deleteButton = try XCTUnwrap(buttons.first { $0.title == L(.agentProfileDelete) },
                                         "没有「删除此档」那一枚：\(buttons.map(\.title))")
        XCTAssertFalse(deleteButton.isEnabled, "只剩一档还能点删除（判红）")
        deleteButton.performClick(nil)
        XCTAssertEqual(box.deletes, 0, "灰着的删除按钮仍然派发了")
        let addButton = try XCTUnwrap(buttons.first { $0.title == L(.agentProfileAdd) })
        XCTAssertTrue(addButton.isEnabled, "一档时「新增档」不该灰")
        print("🧪 判据③读数：一档时删除 isEnabled=\(deleteButton.isEnabled)")
    }

    // MARK: - ④ 测试在途 ⇒ 按钮置灰 + 档名格在

    @MainActor
    func testTestButtonGoesGreyWhileTestingAndTheNameFieldExists() throws {
        let box = Box()
        let live = host(editor(profiles: profiles(), canDelete: true, isTesting: true, box: box))
        let buttons = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSButton.self, in: live.hosting)
        let testButton = try XCTUnwrap(buttons.first { $0.title == L(.agentProfileTest) },
                                       "没有「测试此档」那一枚：\(buttons.map(\.title))")
        XCTAssertFalse(testButton.isEnabled, "测试在途还能再点一次（判红）")

        let fields = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSTextField.self, in: live.hosting)
        XCTAssertTrue(fields.contains { $0.stringValue == "云端写作" },
                      "没有档名输入格（或没回填当前档名），实际：\(fields.map(\.stringValue))")
        print("🧪 判据④读数：在途时测试 isEnabled=\(testButton.isEnabled) / 输入格 = \(fields.map(\.stringValue))")
    }
}
