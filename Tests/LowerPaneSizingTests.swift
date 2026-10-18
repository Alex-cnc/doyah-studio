import XCTest
@testable import DoyahCore

/// 下方面板在折叠 / 展开两态下的**高度提示**（队列 `L-121`，需求提出者 2026-09-30 实测缺陷）。
///
/// 判据的本质是一条**不许**：**折叠态不许给面板留最小高度**。
/// 原因写在 `LowerPaneSizing` 的文档里 —— 外层留了 `minHeight`，内层又把自己收成标题栏一行，
/// 多出来的高度由外层框填（外层框没有面板的底色），于是底部出现一条「比标题栏宽的空白带」，
/// 透出来的是工作区背景。这三条断言就是那个缺陷的看门人。
final class LowerPaneSizingTests: XCTestCase {

    /// 缺陷本体：折叠态**必须**是「不设最小高度」。
    func testCollapsedHasNoMinimumHeight() {
        XCTAssertNil(
            LowerPaneSizing.minHeight(collapsed: true),
            "折叠态给了最小高度 ⇒ 底部会留下一条比标题栏宽的空白带（L-121 就是这个缺陷）"
        )
    }

    /// 折叠态也不设理想高度：让面板按标题栏一行自量（字号 / 语言变了会自己跟着变）。
    func testCollapsedHasNoIdealHeight() {
        XCTAssertNil(LowerPaneSizing.idealHeight(collapsed: true))
    }

    /// 展开态保留原有两条口径（L-84 ㈠「下方面板默认占两成」的下限与落位高度）。
    func testExpandedKeepsContract() {
        XCTAssertEqual(LowerPaneSizing.minHeight(collapsed: false), 90)
        XCTAssertEqual(LowerPaneSizing.idealHeight(collapsed: false), 200)
    }

    /// 两态必须是**真的不一样**：同值就等于没分态（折叠后照样留白）。
    func testTwoStatesDiffer() {
        XCTAssertNotEqual(
            LowerPaneSizing.minHeight(collapsed: true),
            LowerPaneSizing.minHeight(collapsed: false)
        )
        XCTAssertGreaterThan(
            LowerPaneSizing.idealHeight(collapsed: false) ?? 0,
            LowerPaneSizing.idealHeight(collapsed: true) ?? 0,
            "展开态的理想高度要大于折叠态（后者为 nil ⇒ 按内容自量）"
        )
    }

    // MARK: L-181：拖出来的高度

    /// 拖出来的高度要**夹在合法范围**：下限＝展开态下限，上限＝可用高度的 75%（矮窗口不许把编辑区挤没）。
    func testDraggedHeightIsClamped() {
        XCTAssertEqual(LowerPaneSizing.clamped(height: 10, available: 900), LowerPaneSizing.draggableMinHeight)
        XCTAssertEqual(LowerPaneSizing.clamped(height: 10_000, available: 900), 675)
        XCTAssertEqual(LowerPaneSizing.clamped(height: 400, available: 900), 400)
    }

    /// 拿不到可用高度（`nil`）或由它算出的上限低于下限时都要兜底 —— 结果不许随可用高度反向跑。
    func testDraggedHeightFallsBackSafely() {
        XCTAssertEqual(LowerPaneSizing.clamped(height: 10_000, available: nil), LowerPaneSizing.fallbackMaxHeight)
        XCTAssertEqual(LowerPaneSizing.clamped(height: 10, available: 0), LowerPaneSizing.draggableMinHeight)
        XCTAssertEqual(LowerPaneSizing.clamped(height: 400, available: 100), LowerPaneSizing.draggableMinHeight)
    }

    // MARK: FR-EDIT-29 人工点验不过：面板高度拖不动（2026-10-18）

    /// **拖拽前后高度读数成对**：上拖变高、下拖变矮，一一对应（这是「拖得动」的判据本体）。
    func testDragYieldsPairedHeights() {
        guard case let .resize(up) = LowerPaneResize.outcome(startHeight: 300, translation: -50, available: 900) else {
            return XCTFail("上拖应当是 resize")
        }
        guard case let .resize(down) = LowerPaneResize.outcome(startHeight: up, translation: 50, available: 900) else {
            return XCTFail("下拖应当是 resize")
        }
        XCTAssertEqual(up, 350, "往上拖 50pt ⇒ 面板高 50pt")
        XCTAssertEqual(down, 300, "再往下拖 50pt ⇒ 回到 300（成对读数，无累积漂移）")
    }

    /// 夹取：上限 = 可用高度的 75%（矮窗口不许把编辑区挤没）。
    func testDragClampsAtMax() {
        XCTAssertEqual(
            LowerPaneResize.outcome(startHeight: 200, translation: -10_000, available: 900),
            .resize(675)
        )
        XCTAssertEqual(
            LowerPaneResize.outcome(startHeight: 200, translation: -10_000, available: nil),
            .resize(LowerPaneSizing.fallbackMaxHeight)
        )
    }

    /// 下限 = **折叠**而不是「夹到最小」：继续往下拖要有反馈，否则看不出「再往下就收起」。
    func testDragBelowMinimumCollapses() {
        XCTAssertEqual(
            LowerPaneResize.outcome(startHeight: 120, translation: 100, available: 900),
            .collapse,
            "拖到最小高度（90）以下 ⇒ 折叠"
        )
        if case .collapse = LowerPaneResize.outcome(startHeight: 100, translation: 9, available: 900) {
            XCTFail("刚好停在最小高度（90）应当是 resize，不是折叠")
        }
    }

    /// **折叠后恢复原高度**：折叠态不设高度（L-121 口径不变），且存着的高度值没被折叠写坏。
    func testCollapseKeepsLastExpandedHeight() {
        XCTAssertNil(
            LowerPaneResize.panelHeight(dragged: 320, collapsed: true, available: 900),
            "折叠态必须是「不设约束」，否则又回到 L-121 那条空白带"
        )
        XCTAssertEqual(
            LowerPaneResize.panelHeight(dragged: 320, collapsed: false, available: 900),
            320,
            "展开后原高度 320 原样回来"
        )
    }

    /// 展开态给的是**确定值**（`CGFloat?` 里的真数字），不是 `nil` 那种「愿望」——
    /// 第一版就栽在「只有 idealHeight 提示、没有确定高度」上。
    func testExpandedHeightIsDefinite() {
        let h = LowerPaneResize.panelHeight(dragged: 260, collapsed: false, available: 900)
        XCTAssertNotNil(h)
        XCTAssertEqual(h!, 260, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(h!, LowerPaneSizing.draggableMinHeight)
        XCTAssertEqual(
            LowerPaneResize.panelHeight(dragged: 10, collapsed: false, available: 900),
            LowerPaneSizing.draggableMinHeight,
            "存盘值坏了（比如被写成 10）也夹回下限，不许面板消失"
        )
    }
}
