import XCTest
@testable import DoyahCore

/// 编码与换行（`FR-STD-WS-EDIT-023`）：按真实形态打开、按原样写回、切换是显式的。
///
/// ## 为什么每一条都盯住"字节"
/// 这条需求的失败形态**不会崩溃、也不会报错**：一个 CRLF 文件被存成 LF，文件照样能打开，
/// 只是 `git diff` 里整篇都变了；一个 GB18030 文件被存成 UTF-8，中文照样看得见，
/// 只是在 Windows 上双击就变成乱码。所以判据一律比较**字节**，而不是比较字符串。
final class TextFileFormatTests: XCTestCase {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: ① CRLF 打开 → 内部 LF → 保存仍是 CRLF

    func testCRLFFileIsNormalizedForEditingAndSavedBackAsCRLF() throws {
        let original = data("let a = 1\r\nlet b = 2\r\n")
        let opened = try TextFileFormat.decode(original)

        // 内部只有一个口径：LF。否则行号 / 折叠 / 缩进每条路都要各自剥一次 `\r`。
        XCTAssertEqual(opened.text, "let a = 1\nlet b = 2\n")
        XCTAssertEqual(opened.format.lineEnding, .crlf)
        XCTAssertEqual(opened.format.encoding, .utf8)

        // 保存：逐字节还回去（这条是需求 ② 的正面）。
        XCTAssertEqual(opened.format.bytes(for: opened.text), original)
    }

    // MARK: ② LF 文件不许被"顺手统一"成 CRLF

    func testLFFileRoundTripsByteForByte() throws {
        let original = data("a\nb\nc")
        let opened = try TextFileFormat.decode(original)
        XCTAssertEqual(opened.format.lineEnding, .lf)
        XCTAssertEqual(opened.format.bytes(for: opened.text), original)
    }

    // MARK: ③ 混排是第三种事实：不猜、原样写回

    func testMixedEndingsAreReportedAndWrittenBackVerbatim() throws {
        let original = data("a\r\nb\nc\r\n")
        let opened = try TextFileFormat.decode(original)

        XCTAssertEqual(opened.format.lineEnding, .mixed, "两种换行都在 ⇒ 如实说混排，不挑一种冒充")
        XCTAssertEqual(opened.text, "a\r\nb\nc\r\n", "混排不归一：归一就等于替用户统一了")
        XCTAssertEqual(opened.format.bytes(for: opened.text), original)
    }

    // MARK: ④ GB18030 文件：中文不乱码、保存仍写 GB18030

    func testGB18030ChineseDecodesAndSavesBackInGB18030() throws {
        let encoding = try XCTUnwrap(ResultExportEncoding.gb18030.foundationEncoding,
                                     "本平台没有 GB18030 编码器，这条判据无从验证")
        let original = try XCTUnwrap("中文\r\n内容\r\n".data(using: encoding))
        // 前提：这份字节**不是**合法 UTF-8（否则这条判据在测另一件事）。
        XCTAssertNil(String(data: original, encoding: .utf8))

        let opened = try TextFileFormat.decode(original)
        XCTAssertEqual(opened.text, "中文\n内容\n")
        XCTAssertEqual(opened.format.encoding, .gb18030)
        XCTAssertEqual(opened.format.lineEnding, .crlf)

        let saved = try XCTUnwrap(opened.format.bytes(for: opened.text))
        XCTAssertEqual(String(data: saved, encoding: encoding), "中文\r\n内容\r\n",
                       "保存必须还写 GB18030 —— 写 UTF-8 会让原工具链读成乱码")
        XCTAssertNil(String(data: saved, encoding: .utf8), "写回的不是 UTF-8，这一点也要钉住")
    }

    // MARK: ⑤ BOM：有的保留、没有的不许凭空加

    func testByteOrderMarkIsKeptWhenPresentAndNeverInvented() throws {
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + data("hi\n")
        let opened = try TextFileFormat.decode(withBOM)
        XCTAssertTrue(opened.format.hadByteOrderMark)
        XCTAssertEqual(opened.text, "hi\n", "BOM 是字节层的东西，不许当正文里的一个字符")
        XCTAssertEqual(opened.format.bytes(for: opened.text), withBOM)

        let withoutBOM = data("hi\n")
        let plain = try TextFileFormat.decode(withoutBOM)
        XCTAssertFalse(plain.format.hadByteOrderMark)
        XCTAssertEqual(plain.format.bytes(for: plain.text), withoutBOM, "不许给没 BOM 的文件加一个")
    }

    // MARK: ⑥ 切换：编码只改口径、换行要落地

    func testSwitchingEncodingKeepsTextAndSwitchingLineEndingRewritesIt() {
        let format = TextFileFormat(encoding: .utf8, lineEnding: .lf, hadByteOrderMark: true)

        let gb = format.choosing(encoding: .gb18030)
        XCTAssertEqual(gb.encoding, .gb18030)
        XCTAssertFalse(gb.hadByteOrderMark, "GB18030 没有 BOM 的概念：留着它会把首格写成乱码字符")

        let outcome = TextFileFormat(encoding: .utf8, lineEnding: .lf)
            .choosing(lineEnding: .crlf, in: "a\nb\n")
        XCTAssertEqual(outcome.format.lineEnding, .crlf)
        XCTAssertEqual(outcome.text, "a\r\nb\r\n", "点 CRLF 的意思就是内容以后用 CRLF，必须落地")
    }

    // MARK: ⑦ GB18030 是全 Unicode 变换格式：编完解回来必须逐字相等（写成问号就是丢字）

    func testGB18030EncodingIsLosslessForCharactersOutsideTheChineseBlock() throws {
        let encoding = try XCTUnwrap(ResultExportEncoding.gb18030.foundationEncoding,
                                     "本平台没有 GB18030 编码器，这条判据无从验证")
        let format = TextFileFormat(encoding: .gb18030, lineEnding: .lf)
        let original = "emoji 😀 与生僻字 𠀀\n"

        let data = try XCTUnwrap(format.bytes(for: original),
                                 "GB18030 覆盖全部 Unicode，编不出来说明这条实现坏了")
        XCTAssertEqual(String(data: data, encoding: encoding), original,
                       "编完解回来必须逐字相等 —— 被换成问号就是静默丢字")
        XCTAssertNotEqual(data, Data(original.utf8), "写出去的必须真是 GB18030 字节，不是 UTF-8")
    }

    // MARK: ⑧ 页签：只改形态也算脏

    func testTabIsDirtyWhenOnlyTheFormatChangesAndCleanAfterSaving() {
        var tab = WorkspaceTab.file(path: "/tmp/a.txt", content: "a\nb\n",
                                    format: TextFileFormat(encoding: .utf8, lineEnding: .lf))
        XCTAssertFalse(tab.isDirty)
        XCTAssertFalse(tab.hasPendingFormatChange)

        tab.format = TextFileFormat(encoding: .gb18030, lineEnding: .lf)
        XCTAssertTrue(tab.isDirty, "只切了编码也必须算脏 —— 否则关页签时这个改动悄悄消失")
        XCTAssertTrue(tab.hasPendingFormatChange)

        tab.markSaved()
        XCTAssertFalse(tab.isDirty)
        XCTAssertFalse(tab.hasPendingFormatChange)
        XCTAssertEqual(tab.savedFormat.encoding, .gb18030)
    }

    // MARK: ⑨ 会话恢复：形态跟着回来，不回来就等于第一次保存时悄悄改掉

    func testSnapshotRemembersFormatSoRestoreDoesNotSilentlyRewriteTheFile() throws {
        let tab = WorkspaceTab.file(path: "/tmp/win.txt", content: "a\nb\n",
                                    format: TextFileFormat(encoding: .gb18030, lineEnding: .crlf))
        let snapshot = WorkspaceSessionSnapshot(tabs: [.init(tab)])
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: encoded)

        let restored = WorkspaceSessionSnapshot.restore(from: decoded) { _ in "a\nb\n" }
        let restoredTab = try XCTUnwrap(restored.tabs.first)
        XCTAssertEqual(restoredTab.format.encoding, .gb18030)
        XCTAssertEqual(restoredTab.format.lineEnding, .crlf)
        XCTAssertFalse(restoredTab.isDirty, "内容与形态都与盘上一致 ⇒ 回来是干净的")
    }

    // MARK: ⑩ 老快照没有形态栏：按盘上字节重判，并按形态归一内容

    func testOldSnapshotWithoutFormatAsksTheDiskInsteadOfDefaultingToUTF8LF() throws {
        let old = WorkspaceSessionSnapshot(tabs: [
            .init(path: "/tmp/old.txt", title: "old.txt", language: TextLanguage.plainText.rawValue)
        ])
        let restored = WorkspaceSessionSnapshot.restore(
            from: old,
            readFile: { _ in "a\r\nb\r\n" },
            formatFor: { _ in TextFileFormat(encoding: .gb18030, lineEnding: .crlf) }
        )
        let tab = try XCTUnwrap(restored.tabs.first)
        XCTAssertEqual(tab.format.encoding, .gb18030, "老快照要问盘，不许直接落缺省 UTF-8")
        XCTAssertEqual(tab.format.lineEnding, .crlf)
        XCTAssertEqual(tab.content, "a\nb\n", "盘上文本也要归一到 LF，与打开那条路同源")
        XCTAssertEqual(tab.savedContent, "a\nb\n")
        XCTAssertFalse(tab.isDirty)
    }
}
