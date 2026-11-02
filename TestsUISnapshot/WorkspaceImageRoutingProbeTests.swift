import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **图片按各自的视图打开**（`FR-STD-WS-FS-008` ①的接线半边）。
///
/// ## 由头
///
/// 台账那一格原写着「① 的另一半『图片等按各自视图』盘上没有实现 —— 图片走 `openAsText`
/// 会被当二进制拒绝」。Core 侧的登记（`.image` 这一档）与页签种类由
/// `Tests/WorkspaceImageOpenTests` 判；这里判**真正那一步**：双击一张图之后，
/// 工作区里到底多出了什么样的页签、有没有被塞进编辑器、⌘S 会不会把图写坏。
///
/// ## 判据方向
///
/// ① 图片文件 ⇒ 页签是**图片页**（`kind == .image`）、没有正文、不脏、不留错误；
/// ② 同一张图点两次 ⇒ 只有一页（与文本文件同一条去重纪律）；
/// ③ 文本文件仍进编辑器（加了图片这一档不许把别人的路挤掉）；
/// ④ 打不开的三种形状（不存在 / 不是能显示的图 / 超过图片上限）各给**可读原因**且不留空页签；
/// ⑤ ⌘S 不许碰图片文件（拿空正文写回 = 把用户的图写成 0 字节）。
///
/// ## 边界（如实登记）
///
/// · 不验像素：图真的画出来要真窗口 + 人眼（`WorkspaceImageView` 的观感归人工点验）；
/// · 不写用户数据：临时目录里造图，跑完删；
/// · 不挂 `DOYAH_UI_SNAPSHOT` ⇒ 与 `WorkspaceFileOpenGuardProbeTests` 同一档，随每轮门禁第 1 项天天跑。
final class WorkspaceImageRoutingProbeTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("workspace-image-routing-probe", isDirectory: true)
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

    /// 1×1 的 PNG（真实字节：ImageIO 真能解出 1 × 1）。
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    private func writeImage(_ name: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Self.onePixelPNG.write(to: url)
        return url
    }

    // MARK: - ① 图片进自己的视图

    @MainActor
    func testImageFileOpensInItsOwnView() throws {
        let image = try writeImage("shot.png")

        let model = makeModel()
        model.openFile(at: image)

        XCTAssertNil(model.errorText, "一张好好的 PNG 不该报错：\(model.errorText ?? "-")")
        XCTAssertEqual(model.tabs.count, 2, "Home + 这张图")
        let tab = try XCTUnwrap(model.selectedTab)
        XCTAssertTrue(tab.isImage, "选中的必须是图片页（不是空文本页）")
        XCTAssertEqual(tab.kind, .image)
        XCTAssertEqual(tab.path, image.path)
        XCTAssertEqual(tab.title, "shot.png")
        XCTAssertTrue(tab.content.isEmpty, "图片没有正文 —— 不许把二进制塞进 content")
        XCTAssertFalse(tab.isDirty, "刚打开的图片页不是脏的（关了不该问「要不要保存」）")
    }

    /// ② 同一张图点两次 ⇒ 一页（去重纪律与文本文件同一条）。
    @MainActor
    func testOpeningTheSameImageTwiceReusesTheTab() throws {
        let image = try writeImage("same.png")
        let model = makeModel()

        model.openFile(at: image)
        let first = try XCTUnwrap(model.selectedTab?.id)
        model.openFile(at: image)

        XCTAssertEqual(model.tabs.count, 2, "同一张图只许一页")
        XCTAssertEqual(model.selectedTab?.id, first)
    }

    /// ③ 加图片这一档**不许挤掉文本那一条路**。
    @MainActor
    func testTextFileStillOpensInTheEditor() throws {
        let file = scratch.appendingPathComponent("notes.md")
        try "# 说明\n".write(to: file, atomically: true, encoding: .utf8)

        let model = makeModel()
        model.openFile(at: file)

        let tab = try XCTUnwrap(model.selectedTab)
        XCTAssertFalse(tab.isImage, "文本文件仍然进编辑器")
        XCTAssertEqual(tab.kind, .file)
        XCTAssertEqual(tab.content, "# 说明\n", "正文要真的读进来")
    }

    // MARK: - ④ 三种打不开都说得清（且不留空页签）

    @MainActor
    func testMissingImageGivesAReadableReason() {
        let model = makeModel()
        let gone = scratch.appendingPathComponent("gone.png")

        model.openFile(at: gone)

        let problem = model.errorText ?? ""
        XCTAssertTrue(problem.contains("gone.png"), "原因要点名是哪个文件：\(problem)")
        XCTAssertEqual(model.tabs.count, 1, "打不开的文件不许留下半开的页签")
    }

    @MainActor
    func testCorruptImageIsRefusedWithAReadableReason() throws {
        let broken = scratch.appendingPathComponent("broken.png")
        try Data("这不是一张图".utf8).write(to: broken)

        let model = makeModel()
        model.openFile(at: broken)

        let problem = model.errorText ?? ""
        XCTAssertTrue(problem.contains("broken.png"), "原因要点名是哪个文件：\(problem)")
        XCTAssertEqual(model.tabs.count, 1, "解不出宽高的图不留空页签")
    }

    @MainActor
    func testOversizeImageIsRefusedWithBothNumbers() throws {
        let huge = scratch.appendingPathComponent("huge.png")
        FileManager.default.createFile(atPath: huge.path, contents: Self.onePixelPNG)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(WorkspaceTabsModel.maximumImageFileSize + 1024))
        try handle.close()

        let model = makeModel()
        model.openFile(at: huge)

        let problem = model.errorText ?? ""
        XCTAssertTrue(problem.contains("huge.png"), "原因要点名文件：\(problem)")
        XCTAssertTrue(problem.contains("MB"), "原因要给出尺寸读数：\(problem)")
        XCTAssertEqual(model.tabs.count, 1)
    }

    // MARK: - ⑤ ⌘S 不碰图片

    /// 这条是这一片最贵的坑：图片页没有正文，`save` 若照旧走文本那条路，
    /// 一次 ⌘S 就会把图写成 0 字节 —— 文件还在，内容没了。
    @MainActor
    func testSavingAnImageTabNeverTouchesTheFile() throws {
        let image = try writeImage("keep.png")
        let before = try Data(contentsOf: image)

        let model = makeModel()
        model.openFile(at: image)
        let id = try XCTUnwrap(model.selectedTab?.id)
        let saved = model.save(id)

        XCTAssertFalse(saved, "图片页没有「保存」这回事")
        XCTAssertEqual(try Data(contentsOf: image), before, "盘上字节必须一个都不变")
        XCTAssertNil(model.errorText, "不该报错 —— 只是这一页没有可保存的东西")
    }
}
