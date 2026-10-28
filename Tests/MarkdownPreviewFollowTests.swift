import XCTest
@testable import DoyahCore

/// `FR-STD-WS-WEB-002`：工作区 Markdown 预览的**跟随滚动会话面** —— 行号按页签记。
///
/// 判的是 `Core/MarkdownPreviewFollow.swift`。此前这条需求只做到「一个标量行号 + 光标行 → 块下标」，
/// 「换页签会不会串行号」「切回来位置还在不在」**没有任何东西在管**：从长文档切到另一篇时，
/// 预览拿着上一份文档的行号去找落点，够长就跳到一个跟当下操作无关的块。
///
/// 每一条都成对：反例（改坏一处）在证据文件 `.agent/evidence/2026-10-29-FR-STD-WS-WEB-002.md` 里
/// 逐段跑过判红，然后逐字节还原。
final class MarkdownPreviewFollowTests: XCTestCase {

    private let a = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let b = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    // MARK: - 起点

    /// 还没有活跃页签：行是 1；此时报来的行**记账但不发布** ——
    /// 报数带页签身份，记得住（编辑器第一帧可能早于激活），但当前跟哪一份文档还没定，
    /// 一旦激活那个页签就该拿到它自己记的值。
    func testReportsBeforeActivationAreRecordedButNotPublished() {
        var follow = MarkdownPreviewFollow()
        XCTAssertNil(follow.activeTab)
        XCTAssertEqual(follow.line, MarkdownPreviewFollow.firstLine)

        XCTAssertFalse(follow.report(line: 42, tab: a), "没有活跃页签时不发布")
        XCTAssertEqual(follow.line, MarkdownPreviewFollow.firstLine, "不发布就不许改当前行")
        XCTAssertNil(follow.activeTab, "报数不许反过来造出一个活跃页签")

        XCTAssertEqual(follow.activate(a), 42, "激活之后要拿到它自己那次报数")
    }

    /// 激活一个从没见过的页签 ⇒ 从第 1 行开始。
    func testActivatingFreshTabStartsAtFirstLine() {
        var follow = MarkdownPreviewFollow()
        XCTAssertEqual(follow.activate(a), 1)
        XCTAssertEqual(follow.activeTab, a)
        XCTAssertEqual(follow.line, 1)
    }

    // MARK: - 按页签记（这一族是「换页签不串行号」的本体）

    /// 两个页签各记各的：切到 B 不继承 A 的行，切回 A 拿回 A 自己的行。
    func testEachTabKeepsItsOwnLine() {
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        XCTAssertTrue(follow.report(line: 800, tab: a))

        XCTAssertEqual(follow.activate(b), 1, "切到 B 不许继承 A 的第 800 行")
        XCTAssertEqual(follow.line, 1)
        XCTAssertTrue(follow.report(line: 7, tab: b))

        XCTAssertEqual(follow.activate(a), 800, "切回 A 必须回到 A 自己的位置")
        XCTAssertEqual(follow.line, 800)
    }

    /// **拆掉的旧编辑器还会报一次**：非活跃页签的报数记在它自己名下，
    /// 但绝不许拿它去改当前预览（否则切换那一瞬间就跳到另一份文档的块上）。
    func testReportFromInactiveTabIsRecordedButNotPublished() {
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        follow.report(line: 40, tab: a)
        follow.activate(b)
        follow.report(line: 5, tab: b)

        XCTAssertFalse(follow.report(line: 999, tab: a), "非活跃页签的报数不许发布")
        XCTAssertEqual(follow.line, 5, "当前预览仍跟 B 的那一行")

        XCTAssertEqual(follow.activate(a), 999, "它自己名下的记录要跟上（回到 A 时位置是对的）")
    }

    /// 同一页签重复激活是幂等的（返回现价、不改状态）——
    /// 视图会在「首次出现」与「选中页签变化」两条路上各调一次，重复调用不许把位置打回起点。
    func testActivatingSameTabTwiceIsIdempotent() {
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        follow.report(line: 120, tab: a)
        XCTAssertEqual(follow.activate(a), 120)
        XCTAssertEqual(follow.activate(a), 120)
        XCTAssertEqual(follow.line, 120)
    }

    // MARK: - 不发布的三档

    /// 同一行重复报数不发布（连按方向键不该让预览反复对齐同一块）。
    func testReportingSameLineDoesNotPublish() {
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        XCTAssertTrue(follow.report(line: 9, tab: a))
        XCTAssertFalse(follow.report(line: 9, tab: a))
        XCTAssertEqual(follow.line, 9)
        // 值没变，但记录仍是 9 —— 切走再切回仍然是 9，不是「因为没发布所以没记」。
        XCTAssertEqual(follow.activate(b), 1)
        XCTAssertEqual(follow.activate(a), 9)
    }

    /// 越界行（0 / 负数）丢弃，且**不污染**该页签的记录。
    func testOutOfRangeReportsAreDroppedWithoutPoisoningTheRecord() {
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        follow.report(line: 30, tab: a)

        XCTAssertFalse(follow.report(line: 0, tab: a))
        XCTAssertFalse(follow.report(line: -3, tab: a))
        XCTAssertEqual(follow.line, 30, "越界报数不许改当前行")

        XCTAssertEqual(follow.activate(b), 1)
        XCTAssertEqual(follow.activate(a), 30, "越界报数不许把该页签的记录写坏")
    }

    // MARK: - 收页签

    /// 关掉的页签记录丢掉：同一个文件再打开是**新的页签标识**，旧记录留着就会「复到上一份文档的位置」。
    func testRetainDropsClosedTabs() {
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        follow.report(line: 500, tab: a)
        follow.activate(b)

        follow.retain([b])
        XCTAssertEqual(follow.activeTab, b, "活跃页签还在集合里，不许被动掉")
        XCTAssertEqual(follow.line, 1)
        XCTAssertEqual(follow.activate(a), 1, "已关掉的页签再激活必须回到第 1 行")
    }

    /// 活跃页签自己被关掉 ⇒ 回到「没有活跃页签」：当前行打回 1，之后来的报数一律不发布。
    func testRetainActiveTabGoneResetsToNoActiveTab() {
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        follow.report(line: 77, tab: a)

        follow.retain([b])
        XCTAssertNil(follow.activeTab)
        XCTAssertEqual(follow.line, MarkdownPreviewFollow.firstLine)
        XCTAssertFalse(follow.report(line: 88, tab: b), "没有活跃页签 ⇒ 不发布")
        XCTAssertEqual(follow.line, MarkdownPreviewFollow.firstLine)
    }

    /// 集合里全都在 ⇒ 一个记录都不丢（收页签不许误伤还开着的页签）。
    func testRetainKeepsEverythingStillOpen() {
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        follow.report(line: 11, tab: a)
        follow.activate(b)
        follow.report(line: 22, tab: b)

        follow.retain([a, b])
        XCTAssertEqual(follow.activate(a), 11)
        XCTAssertEqual(follow.activate(b), 22)
    }

    // MARK: - 与滚动落点接得上

    /// 记下来的行就是喂给契约层查表的那个数：第 5 行必须落到「第二段」那一块（块下标 2），
    /// 会话面只负责记住行号，块下标仍由 `MarkdownDocument.anchor(forSourceLine:)` 给。
    func testRememberedLineFeedsTheSameAnchorAsTheDocument() {
        let text = """
        # 标题

        第一段。

        第二段。
        """
        let document = MarkdownDocument.parse(text)
        var follow = MarkdownPreviewFollow()
        follow.activate(a)
        follow.report(line: 5, tab: a)

        XCTAssertEqual(follow.line, 5)
        XCTAssertEqual(document.anchor(forSourceLine: 5)?.blockIndex, 2, "第 5 行（第二段）的顶层块下标")
        XCTAssertEqual(document.anchor(forSourceLine: follow.line)?.blockIndex, 2)
    }
}
