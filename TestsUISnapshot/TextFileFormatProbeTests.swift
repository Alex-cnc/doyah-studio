import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **打开 / 保存时的编码与换行**（`FR-STD-WS-EDIT-023`）—— 需求 F 的 App 内行为探针。
///
/// ## 判的是「真文件上的真行为」，不是判定函数的返回值
///
/// `Core/TextFileFormat.swift` 的判定（`TextFileFormat.decode` / `LineEnding.detecting`）已经由
/// `Tests/` 的纯逻辑判据钉过。那条路全绿仍然拦不住下面这几件事，而它们都是**用户能看见**的：
///
///   ① **打开那一步没把形态带上页签** ⇒ 状态栏显示缺省值，一次保存就把整个文件改成 LF；
///   ② **保存那一刻没按页签的形态写** ⇒ 二进制上「全文都变」了，git 里一次提交覆盖整份文件；
///   ③ **切编码不带未保存标记** ⇒ 用户以为已经生效，关页签时那个选择静默消失。
///
/// 所以本文件的每一档都走**真的 `WorkspaceTabsModel`**（双击 / 右键「以源码打开」/ 状态栏菜单
/// 都是它）+ **临时目录里的真文件**，并在**字节层**断言落盘结果（再解回来对一遍：
/// 「在别的工具里仍是该编码」这句话只有字节说了算）。
///
/// ## 边界（如实登记）
///
/// · 状态栏那一格（`WorkspaceAreaView.formatMenu`）画的是 `TextFileFormat.displayName`，
///   本探针判的是**那一格的取值**（模型里同一格数据）；「那一行字真的画在屏幕上」属于观感/像素那一族，
///   本轮不重复（既有 `WorkspaceChromeHeightProbeTests` 一族已覆盖 chrome 的渲染面）。
/// · 切换只判到「模型口径 + 落盘字节」：菜单本身的点击（SwiftUI `Menu` 的条目）在离屏宿主里
///   落不到 `NSMenuItem`（同族实测见 `NotesEditorSaveProbeTests` 文件头），所以入口判到
///   `chooseEncoding` / `chooseLineEnding` 这一层 —— 状态栏那份菜单的每个条目直接调的就是它们。
final class TextFileFormatProbeTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextFileFormatProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 装配

    /// 真页签模型，历史 / 现场两份存储都指向临时目录（绝不碰真实数据家）。
    @MainActor
    private func makeTabs() -> WorkspaceTabsModel {
        WorkspaceTabsModel(
            store: WorkspaceHistoryStore.standard(applicationSupport: root),
            sessionStore: WorkspaceSessionStore.standard(applicationSupport: root)
        )
    }

    private func write(_ name: String, bytes: Data) throws -> URL {
        let url = root.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    /// GB18030 编码器（夹具用：与产品判定同一个系统编码；测试里自己造字节，不借产品代码）。
    private var gb18030: String.Encoding? {
        let cfEncoding = CFStringEncodings.GB_18030_2000
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
        guard nsEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: nsEncoding)
    }

    @MainActor
    private func tab(_ tabs: WorkspaceTabsModel, at url: URL) throws -> WorkspaceTab {
        try XCTUnwrap(
            tabs.tabs.first { $0.path == url.path },
            "打开之后页签集合里没有 \(url.lastPathComponent) —— 打开这条路没走通"
        )
    }

    /// 一段字节里 `\r\n` 的个数与「不属于 CRLF 的孤立 `\n`」的个数（标量级扫，别按 Character）。
    private func counts(of data: Data) -> (crlf: Int, loneLF: Int, loneCR: Int) {
        let scalars = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
        var crlf = 0
        var loneLF = 0
        var loneCR = 0
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\r" {
                if index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    crlf += 1
                    index += 2
                    continue
                }
                loneCR += 1
            } else if scalars[index] == "\n" {
                loneLF += 1
            }
            index += 1
        }
        return (crlf, loneLF, loneCR)
    }

    // MARK: - ① CRLF 文件：按 CRLF 打开，保存回去还是 CRLF

    @MainActor
    func testCRLFFileOpensAsCRLFAndSavesBackAsCRLF() throws {
        let url = try write("crlf.txt", bytes: Data("第一行\r\n第二行\r\n".utf8))

        let tabs = makeTabs()
        tabs.openFile(at: url)
        let opened = try tab(tabs, at: url)

        XCTAssertEqual(
            opened.format.lineEnding, .crlf,
            "这份文件盘上是 CRLF，页签却记成 \(opened.format.lineEnding.shortName) —— "
                + "状态栏会说错，保存会把它改成 LF"
        )
        XCTAssertEqual(opened.format.displayName, "UTF-8 · CRLF", "状态栏那一格说的形态不对")
        XCTAssertFalse(opened.isDirty, "刚打开就脏 ⇒ 形态这一半被算成了未保存改动")
        // 编辑器内部一律 LF（否则每一行末尾都多一个看不见的 `\r`）。
        XCTAssertFalse(
            opened.content.unicodeScalars.contains("\r"),
            "编辑器缓冲里还留着 `\\r` —— 每行末尾会多一个不可见字符"
        )

        tabs.updateContent(opened.content + "第三行\n", for: opened.id)
        XCTAssertTrue(tabs.save(opened.id), "保存失败（临时目录里不该失败）")

        let bytes = try Data(contentsOf: url)
        let counts = counts(of: bytes)
        XCTAssertEqual(counts.crlf, 3, "保存后 CRLF 行数不对 ⇒ 换行被悄悄改了：\(counts)")
        XCTAssertEqual(counts.loneLF, 0, "保存后出现了裸 LF 行 ⇒ 换行被悄悄改成 LF：\(counts)")
        XCTAssertEqual(counts.loneCR, 0, "保存后出现了孤立 CR：\(counts)")
        XCTAssertEqual(
            String(decoding: bytes, as: UTF8.self), "第一行\r\n第二行\r\n第三行\r\n",
            "落盘内容与用户敲的不一致"
        )
        XCTAssertFalse(try tab(tabs, at: url).isDirty, "保存之后那一页还是脏的")
    }

    // MARK: - ② GB18030 文件：按它的编码打开，保存回去仍是 GB18030

    @MainActor
    func testGB18030FileOpensWithItsEncodingAndSavesBackInIt() throws {
        let encoding = try XCTUnwrap(gb18030, "这台机器没有 GB18030 编码器 ⇒ 这一档无从判起")
        let original = "中文内容\n第二行\n"
        let url = try write("gb.txt", bytes: try XCTUnwrap(original.data(using: encoding)))

        let tabs = makeTabs()
        tabs.openFile(at: url)
        let opened = try tab(tabs, at: url)

        XCTAssertEqual(
            opened.format.encoding, .gb18030,
            "盘上是 GB18030，页签却记成 \(opened.format.encoding.shortName) —— "
                + "保存时会把中文写成 UTF-8，别的工具打开就是乱码"
        )
        XCTAssertEqual(opened.content, original, "按 GB18030 解出来的正文与夹具不一致")
        XCTAssertFalse(opened.isDirty, "刚打开就脏 ⇒ 编码这一半被算成了未保存改动")

        tabs.updateContent(original + "第三行\n", for: opened.id)
        XCTAssertTrue(tabs.save(opened.id), "保存失败（GB18030 编码器本该编得出来）")

        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(
            String(data: bytes, encoding: encoding), original + "第三行\n",
            "保存之后按 GB18030 解不回原文 ⇒ 编码被悄悄改了"
        )
        // 反向：当成 UTF-8 读**读不出**这段中文（否则「仍是 GB18030」这句话没法判）。
        XCTAssertNotEqual(
            String(data: bytes, encoding: .utf8), original + "第三行\n",
            "这份字节居然能按 UTF-8 读出同样的文字 ⇒ 这条判据判不出编码有没有被换掉"
        )
        XCTAssertEqual(
            try TextFileFormat.detect(contentsOf: url).encoding, .gb18030,
            "重新按字节判定时编码变了"
        )
    }

    // MARK: - ③ 状态栏切编码：出现未保存标记，保存后文件真的是新编码

    @MainActor
    func testSwitchingEncodingMarksTheTabDirtyAndLandsOnDisk() throws {
        let encoding = try XCTUnwrap(gb18030, "这台机器没有 GB18030 编码器 ⇒ 这一档无从判起")
        let url = try write("switch.txt", bytes: Data("纯文本\n".utf8))

        let tabs = makeTabs()
        tabs.openFile(at: url)
        let opened = try tab(tabs, at: url)
        XCTAssertEqual(opened.format.encoding, .utf8, "起手该是 UTF-8")
        XCTAssertFalse(opened.isDirty, "起手不该是脏的")

        // 状态栏那一格 → 菜单里「GB18030」这一项打到的就是它。
        tabs.chooseEncoding(tabID: opened.id, encoding: .gb18030)
        let switched = try tab(tabs, at: url)
        XCTAssertEqual(
            tabs.format(for: opened.id)?.encoding, .gb18030,
            "切了编码，状态栏那一格读到的还是旧值"
        )
        XCTAssertEqual(
            switched.content, "纯文本\n",
            "切编码不该动正文（编码只在写盘那一刻起作用）"
        )
        XCTAssertTrue(
            switched.isDirty,
            "切了编码却没有未保存标记 ⇒ 用户以为已经生效，关页签时这个选择会静默消失"
        )

        XCTAssertTrue(tabs.save(opened.id), "保存失败（GB18030 编得出来）")
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(
            String(data: bytes, encoding: encoding), "纯文本\n",
            "保存之后文件不是 GB18030 —— 状态栏说的与盘上的不是一件事"
        )
        XCTAssertNotEqual(
            String(data: bytes, encoding: .utf8), "纯文本\n",
            "保存出来的字节仍能按 UTF-8 读成原文 ⇒ 编码切换没落地"
        )
        XCTAssertFalse(try tab(tabs, at: url).isDirty, "保存之后那一页还是脏的（形态没对齐）")
    }

    // MARK: - ④ 状态栏切换行：显式改口径，保存后就是那一档

    @MainActor
    func testSwitchingLineEndingConvertsOnSave() throws {
        let url = try write("ending.txt", bytes: Data("甲\n乙\n".utf8))

        let tabs = makeTabs()
        tabs.openFile(at: url)
        let opened = try tab(tabs, at: url)
        XCTAssertEqual(opened.format.lineEnding, .lf, "起手该是 LF")

        tabs.chooseLineEnding(tabID: opened.id, lineEnding: .crlf)
        XCTAssertTrue(
            try tab(tabs, at: url).isDirty,
            "切了换行却没有未保存标记 ⇒ 这个选择会随页签一起消失"
        )
        XCTAssertTrue(tabs.save(opened.id))

        let bytes = try Data(contentsOf: url)
        let counts = counts(of: bytes)
        XCTAssertEqual(counts.crlf, 2, "切到 CRLF 之后保存出来不是 CRLF：\(counts)")
        XCTAssertEqual(counts.loneLF, 0, "还有裸 LF 行：\(counts)")
        XCTAssertEqual(
            try TextFileFormat.detect(contentsOf: url).lineEnding, .crlf,
            "重新按字节判定时换行形态没变"
        )
    }

    // MARK: - ⑤ 对照（判据必须能判红）：同一套字节量法看得见「换行被改掉」

    /// 上面几条断言的都是「盘上的字节」。若这套量法对 CRLF / LF 根本不敏感，那几条绿得毫无意义。
    /// 这里拿**同一个 `counts`** 去量两种手写夹具 —— 必须量出差别。
    func testByteScanSeesTheDifferenceBetweenCRLFAndLF() throws {
        let crlf = counts(of: Data("a\r\nb\r\n".utf8))
        let lf = counts(of: Data("a\nb\n".utf8))
        XCTAssertEqual(crlf.crlf, 2)
        XCTAssertEqual(crlf.loneLF, 0)
        XCTAssertEqual(lf.crlf, 0)
        XCTAssertEqual(lf.loneLF, 2)
        XCTAssertNotEqual(crlf.crlf, lf.crlf, "这套量法分不出 CRLF 与 LF ⇒ 上面几条判据不算数")
    }
}
