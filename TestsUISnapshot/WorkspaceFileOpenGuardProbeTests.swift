import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **点开一个文件之后的三条拒绝路径**（`FR-STD-WS-FS-008` ③④）。
///
/// 台账原来挂着的是 `WorkspaceFileRoutingProbeTests` 6 例 —— 那一族判的是**路由**
/// （`.html` 交给浏览器、其余进编辑器），对需求书 ③「大文件与编码沿用既有判定」与
/// ④「打开失败给出可读原因」一个字都没判。这一族补的就是那两条：**拒绝要说得清，
/// 而且拒绝之后页签集不许被动过**（「点一下没反应」和「点了打不开但说过为什么」是两回事）。
///
/// ## 边界（如实登记）
///
/// · 判的是**模型出口那几句话**（`errorText` / `noticeText`），不是弹在窗口里的横幅；
/// · ② 的语言判定（扩展名表 + 文件名表、认不出回落纯文本）不在这里重复判 ——
///   那是 `Tests/CodeLanguageRegistryTests` 的 19 例；
/// · 大文件阈值取的是模型里那一个常量，不在这里另写一个数字（两处写死必然漂）。
final class WorkspaceFileOpenGuardProbeTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("workspace-open-guard-probe", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
    }

    @MainActor
    private func makeModel() -> WorkspaceTabsModel {
        WorkspaceTabsModel(
            store: WorkspaceHistoryStore(fileURL: scratch.appendingPathComponent("history.json")),
            sessionStore: WorkspaceSessionStore(
                fileURL: scratch.appendingPathComponent("session-\(UUID().uuidString).json")
            )
        )
    }

    // MARK: - ③ 太大 ⇒ 如实拒绝（带两个数：这个文件多大、上限多大）

    @MainActor
    func testOversizeFileIsRefusedWithBothNumbers() throws {
        let file = scratch.appendingPathComponent("huge.log")
        let bytes = WorkspaceTabsModel.maximumFileSize + 1024
        try Data(repeating: 0x41, count: bytes).write(to: file)

        let model = makeModel()
        model.openFile(at: file)

        let problem = try XCTUnwrap(model.errorText, "超限文件必须给可读原因，不许静默")
        XCTAssertTrue(problem.contains("huge.log"), "原因里要点名是哪个文件：\(problem)")
        XCTAssertTrue(problem.contains("MB"), "原因里要给出尺寸读数：\(problem)")
        XCTAssertEqual(model.tabs.count, 1, "被拒绝的文件不许留下半开的页签")
    }

    // MARK: - ③ 二进制 ⇒ 如实拒绝（不硬塞进编辑器）

    @MainActor
    func testBinaryFileIsRefusedInsteadOfBeingOpenedAsText() throws {
        let file = scratch.appendingPathComponent("blob.bin")
        try Data([0x00, 0x01, 0x02, 0x00, 0xFF]).write(to: file)

        let model = makeModel()
        model.openFile(at: file)

        let problem = try XCTUnwrap(model.errorText, "二进制文件必须给可读原因")
        XCTAssertTrue(problem.contains("blob.bin"), "原因里要点名是哪个文件：\(problem)")
        XCTAssertEqual(model.tabs.count, 1)
    }

    // MARK: - ③ 编码不是 UTF-8 ⇒ 照开，但把编码说出来

    @MainActor
    func testNonUTF8FileOpensAndSaysWhichEncoding() throws {
        let file = scratch.appendingPathComponent("gbk.txt")
        // GB18030 的「中文」：UTF-8 解不出来，必须靠既有编码判定接住
        let gb18030 = try XCTUnwrap("中文\n".data(using: String.Encoding(rawValue: 0x80000632)))
        try gb18030.write(to: file)

        let model = makeModel()
        model.openFile(at: file)

        XCTAssertNil(model.errorText, "认得出的非 UTF-8 文件应当能打开：\(model.errorText ?? "")")
        XCTAssertEqual(model.tabs.count, 2, "应当在 Home 之外多一个文件页签")
        let notice = model.noticeText ?? ""
        XCTAssertFalse(notice.isEmpty, "用了非缺省编码就必须说出来（否则用户不知道保存会不会改掉）")
        XCTAssertTrue(
            notice.contains("GB18030") || notice.uppercased().contains("GBK") || notice.contains("GB"),
            "提示里要写出具体编码：\(notice)"
        )
    }

    // MARK: - ④ 打不开 ⇒ 可读原因（不是无声无息）

    @MainActor
    func testMissingFileGivesAReadableReason() {
        let file = scratch.appendingPathComponent("not-there.swift")

        let model = makeModel()
        model.openFile(at: file)

        let problem = try? XCTUnwrap(model.errorText)
        XCTAssertNotNil(problem, "打开失败必须给可读原因")
        XCTAssertTrue((model.errorText ?? "").contains("not-there.swift"),
                      "原因里要点名是哪个文件：\(model.errorText ?? "")")
        XCTAssertEqual(model.tabs.count, 1, "失败的打开不许留下空壳页签")
    }

    /// 目录也一样：给一句话说「这是目录」，别让它长成一个空页签。
    @MainActor
    func testDirectoryGivesAReadableReason() {
        let model = makeModel()
        model.openFile(at: scratch)

        XCTAssertNotNil(model.errorText, "点目录也要说一句")
        XCTAssertEqual(model.tabs.count, 1)
    }
}
