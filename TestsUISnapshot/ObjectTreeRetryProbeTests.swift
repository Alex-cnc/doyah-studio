import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 对象树失败那一行的**「重试」入口**（`FR-STD-DB-META-006` ③）—— B1 批次第四片。
///
/// ## 这一格为什么停在「差人工点一次」
///
/// 判定（`Core/ObjectTreeRetry`，11 例）与接线（`Tests/ObjectTreeRetrySourceTests`，5 例）都在，
/// 缺的是**点一下**：那一枚「重试」是 SwiftUI `Button`，离屏宿主里不落 `NSButton`
/// （同 `PanelIconButton` 文件头的实测）⇒ 「点它到底重新取了一次数没有」只能靠人点。
/// 台账因此只能写「实现 🟡 · 界面已接线，差人工点一次」。
///
/// ## 这一片怎么量
///
/// ① 失败那一行收进 `App/Views/ObjectTreePlaceholderRow.swift`（行体 + 重试入口），
///    入口换成**真 `NSButton`**（`ObjectTreeRetryButton`）—— 探针能把这一行单独装进活宿主，
///    按下用户按的那一枚；
/// ② 两步执行（先清旧错误、再取数）收进 `Core/ObjectTreeRetry.apply`（顺序即口径），
///    探针把两个回调接成记账的假状态就能读出**顺序**；
/// ③ 判据读的是**按钮数 / 真的跑了几次 / 清与取的先后**，不是截图。
///
/// ## 边界（如实登记，别把这条读成「真库点过了」）
///
/// · **不是真数据库**：这一片量的是「入口在不在、点了做什么」，不量「连不上的库展开之后
///   真的报错了吗」—— 那一面要真集群（`ObjectTreeRefreshProbeTests` / `Scripts/run-manual-verification-probes.sh`
///   那条路，跳过不算通过）。
/// · **行内红字读不出来**：SwiftUI `Text` 不落 `NSTextField`（同 `DialogActionRowProbeTests` 文件头）
///   ⇒ 判不到「红字上写了什么」，只判「这一档画不画得出重试入口」。
/// · **真鼠标点按钮那一跳**（鼠标悬停高亮、按下态）不在本片。
final class ObjectTreeRetryProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主：DOYAH_UI_SNAPSHOT=1 才跑（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 夹具

    /// 记账盒（闭包捕获用）。
    private final class Box {
        var clicks = 0
        var order: [ObjectTreeRetry.Step] = []
        var error: String? = "连不上：数据库 doyah_probe 不存在"
        var loads = 0
        /// 取数那一刻还挂着哪句错误（判「先清、后取」用）。
        var errorWhenLoading: String?
        var isLoading = false
    }

    /// 把一行装进活宿主，取出里面所有真 `NSButton`。
    @MainActor
    private func buttons(in view: some View, size: CGSize = CGSize(width: 560, height: 44)) -> [NSButton] {
        let live = UISnapshot.LiveHost(AnyView(view), size: size)
        live.pump(0.4)
        return UISnapshot.LiveHost<AnyView>.findViews(ofType: NSButton.self, in: live.hosting)
    }

    /// 失败那一行（生产里由 `ObjectTreeView.placeholderRow` 交出同一份）。
    @MainActor
    private func failureRow(retry: (() -> Void)?) -> some View {
        ObjectTreePlaceholderRow(
            text: "连不上：数据库 doyah_probe 不存在",
            depth: 1,
            systemImage: "exclamationmark.triangle.fill",
            color: .orange,
            retry: retry
        )
    }

    // MARK: - ① 失败那一行有一枚真按钮，按下去真的跑一次

    @MainActor
    func testFailureRowDrawsARealRetryButtonAndClickingItRunsOnce() throws {
        let box = Box()
        let found = buttons(in: failureRow(retry: { box.clicks += 1 }))

        XCTAssertEqual(found.count, 1, "失败那一行落出 \(found.count) 枚真按钮 —— 重试入口不是 AppKit 控件（离屏点不到）")
        let button = try XCTUnwrap(found.first)
        XCTAssertEqual(button.title, L(.commonRetry), "按钮上是「\(button.title)」而不是「\(L(.commonRetry))」")
        XCTAssertEqual(button.toolTip, L(.commonRetry), "这一枚没有悬停提示（红字旁边一枚纯文字，读屏也念不出它是什么）")

        button.performClick(nil)
        XCTAssertEqual(box.clicks, 1, "点了「重试」没有真的跑一次（实测 \(box.clicks) 次）")
        button.performClick(nil)
        XCTAssertEqual(box.clicks, 2, "第二次点没派发 —— 入口只活一次（用户再点会以为界面卡住）")
        print("🧪 重试入口读数：按钮 \(found.count) 枚 / 标题「\(button.title)」/ 点两次跑了 \(box.clicks) 次")
    }

    // MARK: - ② 出不出入口由 Core 判：四档不出、一档出

    /// 四档「不出」逐档渲染一次：**一枚按钮都不许有**。
    ///
    /// 这四档不是随口写的：在途再点 = 第二次取数、收起时那一行没画出来、没有失败就没有可重试的、
    /// 已缓存说明这一次是成功的 —— 每一档都对应一种「点了会更糟」。
    @MainActor
    func testCoreJudgementDecidesWhetherTheEntryIsDrawn() throws {
        let facts: [(ObjectTreeRetry.Skip?, Bool, Bool, Int?, String?)] = [
            (.inFlight, true, true, nil, "连不上"),        // 在途
            (.notExpanded, false, false, nil, "连不上"),   // 收起
            (.noFailure, true, false, nil, nil),           // 没失败
            (.alreadyLoaded, true, false, 3, "连不上"),    // 已缓存
            (nil, true, false, nil, "连不上"),             // 该出
        ]

        for (expectedSkip, isExpanded, isLoading, cachedCount, error) in facts {
            let outcome = ObjectTreeRetry.evaluate(
                nodeID: "node-1",
                isExpanded: isExpanded,
                isLoading: isLoading,
                cachedCount: cachedCount,
                error: error
            )
            if let expectedSkip {
                XCTAssertEqual(outcome, .skip(expectedSkip), "这一档的判定变了（\(expectedSkip)）")
            } else {
                XCTAssertEqual(outcome.plan?.steps, [.clearError, .loadChildren],
                               "该出入口的那一档没给出「先清错误、再取数」两步")
            }

            // 视图那一侧只读判定结果：不出 ⇒ 传 nil ⇒ 画面上 0 枚按钮。
            let retry = outcome.affordsRetry ? { () -> Void in } : nil
            let drawn = buttons(in: failureRow(retry: retry))
            XCTAssertEqual(
                drawn.count, outcome.affordsRetry ? 1 : 0,
                "判定说 \(outcome.affordsRetry ? "出" : "不出")，画面上却有 \(drawn.count) 枚按钮"
            )
        }
        print("🧪 四档不出 / 一档出：逐档渲染的按钮数与 Core 判定一致")
    }

    // MARK: - ③ 点一下之后：先清旧错误、再取数

    @MainActor
    func testClickingRetryClearsTheErrorBeforeReloading() throws {
        let box = Box()
        let outcome = ObjectTreeRetry.evaluate(
            nodeID: "node-1", isExpanded: true, isLoading: false, cachedCount: nil, error: box.error
        )
        let plan = try XCTUnwrap(outcome.plan, "有失败却没给出重试计划 —— 这一行在界面上是死路")

        // 用户按下那枚按钮 ＝ 走这一条（视图的 `performRetry` 与探针读的是同一份 `apply`）。
        ObjectTreeRetry.apply(
            plan,
            clearError: { _ in
                box.order.append(.clearError)
                box.error = nil
            },
            loadChildren: { _ in
                box.order.append(.loadChildren)
                box.loads += 1
                box.errorWhenLoading = box.error
                box.isLoading = true
            }
        )

        XCTAssertEqual(box.order, [.clearError, .loadChildren], "两步的先后变了：实测 \(box.order)")
        XCTAssertNil(box.errorWhenLoading,
                     "取数那一刻旧错误还挂着（\" \(box.errorWhenLoading ?? "") \"）—— 从点击到结果落地，用户看到的是同一句旧红字")
        XCTAssertEqual(box.loads, 1, "点一次取了几次数：\(box.loads)")
        print("🧪 重试两步读数：顺序 \(box.order.map(\.rawValue)) / 取数时旧错误 \(box.errorWhenLoading ?? "已清") / 取数 \(box.loads) 次")
    }

    // MARK: - ④ 在途时入口从同一行上消失（端到端接起来判）

    @MainActor
    func testInFlightRowDrawsNoEntry() throws {
        let box = Box()
        let before = ObjectTreeRetry.evaluate(
            nodeID: "node-1", isExpanded: true, isLoading: false, cachedCount: nil, error: box.error
        )
        XCTAssertTrue(before.affordsRetry, "起点就不出入口 —— 后面那条「在途消失」判的是空跑")
        XCTAssertEqual(buttons(in: failureRow(retry: { box.clicks += 1 })).count, 1, "起点应该有一枚入口")

        // 点一下 → 进入在途（`loadChildren` 真的开始取数了）。
        box.isLoading = true
        let during = ObjectTreeRetry.evaluate(
            nodeID: "node-1", isExpanded: true, isLoading: box.isLoading, cachedCount: nil, error: box.error
        )
        XCTAssertEqual(during, .skip(.inFlight), "在途时判定没挡住（再点一次就是第二次取数，谁后落地谁说了算）")
        let drawn = buttons(in: failureRow(retry: during.affordsRetry ? { () -> Void in } : nil))
        XCTAssertEqual(drawn.count, 0, "在途时那一行还挂着重试入口 —— 用户能再发一遍取数")
        print("🧪 在途读数：判定 \(during) / 画面上按钮 \(drawn.count) 枚")
    }

    // MARK: - ⑤ 源锚点：树的失败分支用的就是这一行、判定只问 Core

    /// 盯三件事：① 失败分支把入口传给 `ObjectTreePlaceholderRow`；② 两步执行不再是视图里那段 for
    /// （唯一出口 = `ObjectTreeRetry.apply`）；③ 那一行里不再有 SwiftUI `Button(action: retry)`。
    func testObjectTreeUsesThatRowAndCoreJudgement() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent("App/Views/ObjectTreeView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(view.contains("ObjectTreePlaceholderRow("),
                      "树的占位行不再走 `ObjectTreePlaceholderRow` ⇒ 重试入口又回到离屏点不到的 SwiftUI 按钮")
        XCTAssertTrue(view.contains("retry: retryAction(for: row)"),
                      "失败分支没把入口传下去 —— 界面上仍然只有一个红字、没有出路")
        XCTAssertTrue(view.contains("ObjectTreeRetry.apply("),
                      "两步执行不再走 Core 的 `apply` ⇒ 「先清错误、再取数」又散回视图里自己 for 一遍")
        XCTAssertFalse(view.contains("Button(action: retry)"),
                       "视图里还留着那段 SwiftUI 重试按钮 —— 用户点不到的那一份又回来了")
        XCTAssertTrue(view.contains("ObjectTreeRetry.evaluate("),
                      "出不出入口不再问 Core（视图自己判 = 第二个判定源）")

        let row = try String(
            contentsOf: root.appendingPathComponent("App/Views/ObjectTreePlaceholderRow.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(row.contains("ObjectTreeRetryButton(title: L(.commonRetry)"),
                      "行里没有那一枚真按钮（重试入口又退回 SwiftUI）")
        XCTAssertTrue(row.contains("button.setAccessibilityLabel(title)"),
                      "真按钮没有读屏标签 —— 读屏只会念「按钮」")
    }
}
