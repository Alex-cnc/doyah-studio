import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// `FR-STD-DB-META-006` · **连不上的库**：对象树失败之后**不许自己接着刷**。
///
/// ## 为什么要有这一格（2026-11-03 人类主人真机点验）
///
/// 原话：「连一个连不上的地址（如 `127.0.0.1:1`）后，对象树不停地自己刷新，像在无限重试」。
///
/// 根因不是"重试写多了"，而是**根刷新被同一次失败反复触发**：
/// `ObjectTreeView.body` 的根是 `Group`（第 60 行），刷新挂在它的 `.task(id:)`（第 162 行）上，
/// 而 `Group` 会把修饰符**分发到每个分支子视图**（本文件 `hoverBox` 那段注释里早写着这条）。
/// 于是「加载中」分支 ↔ 「加载失败」分支一换，就等于是**一个新视图出现** ⇒ 同一个 id 再跑一次
/// `reloadRoot()` ⇒ 再失败一次 ⇒ 再换分支 …… 死循环。对 `127.0.0.1:1`（连接被立刻拒绝）
/// 这个循环快得就像"界面自己在抖"。
///
/// ## 判什么
///
/// ① **取数发数有上限**：一个连不上的地址，自动路径最多「首连 + 一次自动重试」= 2 发；
///    泵 5 秒之后 `loadStats.started` 必须是 2，**不是几十**。
/// ② **失败停在树上**：泵完之后画面里读得到失败文案（不是"正在加载"那种还会变的样子）。
/// ③ **用户点一下还能再来一发**：手动重试入口在场（`NSButton`），触发之后 `started` 必须 +1 ——
///    "停在那儿、我点它再试"是需求原文，不能靠"把重试关掉"交差。
///
/// ## 边界（如实登记）
///
/// · 不判「自动重试的间隔是不是 2 秒」：那一段由 `Tests/ObjectTreeLoadRetryTests` 在**策略**这一层
///   判（纯函数，不靠墙钟）。
/// · 行内红字读得到文字、读不到颜色（SwiftUI `Text` 的颜色不落在可读载体上），
///   所以「红字」这一条只判文案在场 + 代码里走的是 `Theme.status(.danger)`（结构判据见
///   `Tests/ObjectTreeFailureStopsTests`）。
final class ObjectTreeDeadConnectionProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "死地址探针要真渲染：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    /// 一个**必然连不上**的连接（本机 1 号端口没有服务 ⇒ 立刻 connection refused）。
    private func deadConfig() -> ConnectionConfig {
        ConnectionConfig(
            name: "死地址探针",
            dbType: .postgresql,
            host: "127.0.0.1",
            port: 1,
            database: "doyah_probe_unreachable",
            username: "postgres",
            sslMode: .disable,
            timeout: 2
        )
    }

    @MainActor
    private func makeAppState() async -> AppState {
        let state = AppState()
        await state.startupChain?.value
        let cfg = deadConfig()
        state.connections = [cfg]
        state.selectedConnectionID = cfg.id
        return state
    }

    /// 画面里读得到的文字（`NSButton` 标题 + `NSTextField` / `NSTextView`）——
    /// 失败文案在 `Text` 里读不到，所以这一条只当**辅助**证据用（真判据是取数发数）。
    @MainActor
    private func visibleTexts<V: View>(_ host: UISnapshot.LiveHost<V>) -> [String] {
        let fields = host.textFields.map(\.stringValue)
        let views = UISnapshot.LiveHost<V>.findViews(ofType: NSTextView.self, in: host.hosting)
            .map(\.string)
        let buttons = UISnapshot.LiveHost<V>.findViews(ofType: NSButton.self, in: host.hosting)
            .map(\.title)
        return (fields + views + buttons).filter { !$0.isEmpty }
    }

    private func writeEvidence(_ name: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = name
        let data = try JSONSerialization.data(
            withJSONObject: enriched,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("object-tree-dead-connection-\(name).json"),
            options: .atomic
        )
    }

    @MainActor
    func testDeadConnectionStopsRefreshing() async throws {
        let state = await makeAppState()
        let host = UISnapshot.LiveHost(
            ObjectTreeView(onEdit: nil).environmentObject(state),
            size: CGSize(width: 360, height: 600)
        )
        // 一次连不上要等驱动的连接超时（本机实测 **20 秒**），所以这里要泵得比它长：
        // 45 秒 = 首连失败（~20s）+ 2 秒后的那次自动重试失败（~42s）之后还剩几秒观察。
        // 修之前同一段时间里自动取数是 1 → 2 → 3 一路涨（`started >= 3`）。
        await host.pumpAsync(seconds: 45)

        let started = state.objectTreeRefreshGate.loadStats.started
        let texts = visibleTexts(host)
        let buttons = UISnapshot.LiveHost<ObjectTreeView>.findViews(
            ofType: NSButton.self,
            in: host.hosting
        )
        let retryTitle = L(.commonRetry)
        let retryButtons = buttons.filter {
            $0.title == retryTitle || $0.accessibilityLabel() == retryTitle
        }

        try writeEvidence("stopsRefreshing", [
            "gateStarted": started,
            "gateJoined": state.objectTreeRefreshGate.loadStats.joined,
            "inFlight": state.objectTreeRefreshGate.inFlightCount,
            "visibleTexts": texts,
            "buttonCount": buttons.count,
            "retryButtonCount": retryButtons.count,
        ])

        XCTAssertLessThanOrEqual(
            started, 2,
            "连不上的地址上对象树自动取了 \(started) 发数 —— 失败之后还在自己刷（要求：首连 + 至多一次自动重试）"
        )
        XCTAssertGreaterThanOrEqual(
            started, 1,
            "一发都没取过 —— 这条判据没生效（连接根本没试过，别当成通过）"
        )
        XCTAssertEqual(
            state.objectTreeRefreshGate.inFlightCount, 0,
            "收尾之后还有键留在在途表里 —— 这一把键从此刷不出来"
        )
        XCTAssertEqual(
            retryButtons.count, 1,
            "失败态里应有且只有一枚「\(retryTitle)」入口（需求：它停在那儿，我点重试它再试）"
        )

        // ③ **点一下真的还能再试一发**：不是"把重试关掉"就算修好了。
        let before = started
        retryButtons.first?.performClick(nil)
        await host.pumpAsync(seconds: 25)
        let after = state.objectTreeRefreshGate.loadStats.started
        try writeEvidence("manualRetry", [
            "startedBeforeClick": before,
            "startedAfterClick": after,
        ])
        XCTAssertEqual(
            after, before + 1,
            "点了「\(retryTitle)」之后取数发数 \(before) → \(after) —— 用户手点这一下必须真的再来一发"
        )

        await state.disconnectObjectTree()
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
