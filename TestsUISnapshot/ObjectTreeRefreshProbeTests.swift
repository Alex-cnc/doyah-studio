import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 队列 `L-96`：**同一次刷新被连唤两次 / `reloadRoot` 重入** —— 两条判据。
///
/// ## 这一格原来为什么没有判据（第 101 轮如实登记的那条「做不到」）
///
/// 第 101 轮试过「整棵真 `ObjectTreeView` + 真库 + 真点击」，结论是「做不到」：真对象树在离屏宿主里
/// **始终停在加载分支**（画面近空白、工具条不在视图树里），于是那一格被登记成「没有机器判据」。
///
/// 第 106 轮把它**定到了根上**：不是树渲染不了，是**泵循环**的问题 —— 当时用的
/// `RunLoop.current.run(until:)` 泵着的期间，「从别的线程跳回主 actor」的续体落不了地，
/// 真库**首连**（`ensureService`）就卡在那里不返回（临时诊断逐行日志：`reloadRoot 进入` →
/// `权限探测 开始` → `探测①ensureService 开始` → **8 秒没有下一行**；而同一份 `AppState`、
/// 同一个方法在测试自己的 `async` 上下文里直调，同一秒就回来了）。
/// 换成 `UISnapshot.LiveHost.pumpAsync`（`Task.sleep` 让出主 actor）之后，整棵树在活宿主里
/// **正常加载出来** —— 所以这一格现在判得了（`pumpAsync` 的注释里也记着这条）。
///
/// ## 判什么
///
/// ① **整棵树在活宿主里真加载出来**（真库 + 真渲染）：
///    · 数据分支**在场** —— 那台「层级视图 / 按类型分组」开关**只在「已加载」那一支里**画得出来；
///    · 加载分支**退场** —— 「正在加载对象…」不许还在画面上；
///    · 画面里**真有那棵树** —— 与**同一条连接指向一个不存在的库**（快速失败、停在失败分支）
///      那个对照宿主比，**视图树节点数必须多出一大截**（失败态只有一行提示 + 一个重试按钮）。
/// ② **同一把刷新键下的重入**：让子树在**上一发还在途**时消失再出现（同一连接、同一元数据版本
///    ⇒ 刷新键一字不变）⇒ ① 结论必须**照样成立**（树不许留在加载态、不许掉成空树），
///    且闸门收尾之后 `inFlightCount == 0`（没有把键漏在在途表里）。
///
/// ## 边界（如实登记）
///
/// · **行内文字读不出来**：SwiftUI 的行 `Text` **不落在** `NSTextField` / `NSTextView` / `NSButton`
///   这些可读载体上（实测：这台宿主里只读得到分段选择器的两档标签「Hierarchy / Group by type」）
///   ⇒ 本批判到「树进了已加载那一支、画面里真有东西」这一层，**判不到**「某个表名出现在第几行」；
///   要判到名字，得走辅助功能（AX）或快照像素比对 —— 本轮没做（不假装判过）。
/// · **「同键两发真并发时，服务端只收到一轮查询」判不到**：本机档首连太快（实测 <150 ms），
///   凑不出稳定的重叠窗口；那一条由 `Tests/ObjectTreeRefreshGateTests` 在**闸门语义**这一层判
///   （数的是测试自己给的取数闭包被调了几次）。
final class ObjectTreeRefreshProbeTests: XCTestCase {

    private var host = "127.0.0.1"
    private var port = 55433
    private var user = "postgres"
    private var database = ""
    private var markerTables: [String] = []
    /// 对照宿主用的**不存在**的库名（同一条连接、只换库名 ⇒ 快速失败）。
    private let missingDatabase = "doyah_probe_l96_missing"
    private static let selectedConnectionDefaultsKey = "settings.selectedConnectionID"
    private var savedSelectedConnection: String?

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "刷新重入探针要真库 + 真渲染：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
        let env = ProcessInfo.processInfo.environment
        guard let scratchDatabase = env["DOYAH_PROBE_PGGROUP"] else {
            throw XCTSkip(
                "刷新重入探针要真集群：请走 Scripts/run-manual-verification-probes.sh"
                    + "（它起本机档并注入 DOYAH_PROBE_PG*）—— 跳过不算通过，脚本会核对证据文件"
            )
        }
        database = scratchDatabase
        markerTables = [env["DOYAH_PROBE_PGTABLE_A"], env["DOYAH_PROBE_PGTABLE_B"]].compactMap { $0 }
        host = env["DOYAH_PROBE_PGHOST"] ?? host
        port = Int(env["DOYAH_PROBE_PGPORT"] ?? "") ?? port
        user = env["DOYAH_PROBE_PGUSER"] ?? user
        savedSelectedConnection = UserDefaults.standard.string(forKey: Self.selectedConnectionDefaultsKey)
    }

    override func tearDownWithError() throws {
        if let saved = savedSelectedConnection {
            UserDefaults.standard.set(saved, forKey: Self.selectedConnectionDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedConnectionDefaultsKey)
        }
    }

    // MARK: - 宿主与真库

    /// 让被测子树**先消失、再出现**（同一连接、同一元数据版本 ⇒ 刷新键一字不变）。
    private final class FlipBox: ObservableObject {
        @Published var visible = true
    }

    private struct FlipHarness: View {
        @ObservedObject var box: FlipBox
        var body: some View {
            if box.visible {
                ObjectTreeView(onEdit: nil)
            } else {
                Color.clear.frame(width: 10, height: 10)
            }
        }
    }

    private func config(database name: String? = nil) -> ConnectionConfig {
        ConnectionConfig(
            name: "刷新重入探针",
            dbType: .postgresql,
            host: host,
            port: port,
            database: name ?? database,
            username: user,
            sslMode: .disable,
            timeout: 5
        )
    }

    @MainActor
    private func makeAppState(database name: String? = nil) async -> AppState {
        let state = AppState()
        await state.startupChain?.value
        let cfg = config(database: name)
        state.connections = [cfg]
        state.selectedConnectionID = cfg.id
        return state
    }

    /// 断开并等它落地（`AppState` 里的「断开」是发出去就不管的异步；不等会踩 PostgresNIO 的 deinit 断言）。
    @MainActor
    private func disconnectAndSettle(_ state: AppState) async {
        await state.disconnectObjectTree()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// 视图树里的节点数（`NSHostingView` 自己也算一个）。
    ///
    /// 为什么要它：行内文字读不出来（见文件头「边界」），于是「画面里真有那棵树」这件事
    /// 只能拿**结构量**判 —— 与失败态（一行提示 + 一个重试按钮）比，节点数差一个量级。
    @MainActor
    private func nodeCount<V: View>(_ host: UISnapshot.LiveHost<V>) -> Int {
        func walk(_ view: NSView) -> Int {
            1 + view.subviews.reduce(0) { $0 + walk($1) }
        }
        return walk(host.hosting)
    }

    /// 画面上读得到的字 —— **从视图树里读**，不是从模型里推（本轮实测只读得到分段选择器的两档标签）。
    @MainActor
    private func visibleTexts<V: View>(_ host: UISnapshot.LiveHost<V>) -> [String] {
        let fields = host.textFields.map(\.stringValue)
        let views = UISnapshot.LiveHost<V>.findViews(ofType: NSTextView.self, in: host.hosting)
            .map(\.string)
        let buttons = UISnapshot.LiveHost<V>.findViews(ofType: NSButton.self, in: host.hosting)
            .map(\.title)
        let segments = UISnapshot.LiveHost<V>.findViews(ofType: NSSegmentedControl.self, in: host.hosting)
            .flatMap { control in
                (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" }
            }
        return (fields + views + buttons + segments).filter { !$0.isEmpty }
    }

    private func writeEvidence(_ caseName: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = caseName
        enriched["database"] = database
        enriched["controlDatabase"] = missingDatabase
        enriched["markerTables"] = markerTables
        enriched["host"] = "\(host):\(port)"
        let data = try JSONSerialization.data(
            withJSONObject: enriched,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("object-tree-refresh-evidence-\(caseName).json"),
            options: .atomic
        )
    }

    // MARK: - ① 整棵树在活宿主里真加载出来

    @MainActor
    func testWholeTreeLoadsInLiveHost() async throws {
        let isLoadingText = L(.treeLoadingObjects)

        // ---- 对照：同一条连接、换成一个不存在的库 ⇒ 停在「加载失败」那一支 ----
        let controlState = await makeAppState(database: missingDatabase)
        let controlHost = UISnapshot.LiveHost(
            ObjectTreeView(onEdit: nil).environmentObject(controlState),
            size: CGSize(width: 360, height: 600)
        )
        await controlHost.pumpAsync(seconds: 8)
        let controlNodes = nodeCount(controlHost)
        let controlToolbar = controlHost.firstSegmentedControl
        await disconnectAndSettle(controlState)

        XCTAssertNil(
            controlToolbar,
            "对照宿主（不存在的库）里也有那台开关 —— 说明「开关在场」这个信号认不出加载态/失败态"
        )

        // ---- 被测：真库 ----
        let state = await makeAppState()
        defer { UserDefaults.standard.removeObject(forKey: Self.selectedConnectionDefaultsKey) }
        let host = UISnapshot.LiveHost(
            ObjectTreeView(onEdit: nil).environmentObject(state),
            size: CGSize(width: 360, height: 600)
        )
        await host.pumpAsync(seconds: 8)

        let texts = visibleTexts(host)
        let toolbar = host.firstSegmentedControl
        let nodes = nodeCount(host)

        XCTAssertNotNil(
            toolbar,
            "整棵树 8 秒之后还没进到「已加载」那一支（工具条不在视图树里）—— 真库那条路没走通"
        )
        XCTAssertFalse(
            texts.contains(isLoadingText),
            "树已经加载出来了却还挂着「\(isLoadingText)」—— 加载态没收干净"
        )
        XCTAssertGreaterThan(
            nodes, controlNodes,
            "真库那棵树（\(nodes) 个视图）不比失败态（\(controlNodes) 个视图）多 —— 画面里其实没那棵树"
        )
        XCTAssertEqual(state.objectTreeRefreshGate.inFlightCount, 0, "加载收尾之后还有键留在在途表里")

        try writeEvidence("wholeTree", [
            "toolbarPresent": toolbar != nil,
            "controlToolbarPresent": controlToolbar != nil,
            "loadingTextPresent": texts.contains(isLoadingText),
            "visibleTexts": texts,
            "nodesLoaded": nodes,
            "nodesControl": controlNodes,
            "gateStarted": state.objectTreeRefreshGate.loadStats.started,
            "gateJoined": state.objectTreeRefreshGate.loadStats.joined,
            "inFlightAfterSettle": state.objectTreeRefreshGate.inFlightCount,
        ])

        await disconnectAndSettle(state)
    }

    // MARK: - ② 同一把刷新键下重入（上一发还在途时子树消失再出现）

    @MainActor
    func testReentryWhileInFlightKeepsTreeLoaded() async throws {
        let state = await makeAppState()
        defer { UserDefaults.standard.removeObject(forKey: Self.selectedConnectionDefaultsKey) }
        let box = FlipBox()

        let host = UISnapshot.LiveHost(
            FlipHarness(box: box).environmentObject(state),
            size: CGSize(width: 360, height: 600)
        )
        // 只等 0.15 秒：第一次刷新**必然还在途**（首连 + 建库权限探测 + 根节点往返）
        await host.pumpAsync(seconds: 0.15)
        box.visible = false                       // 子树消失（`.task` 会取消上一发）
        await host.pumpAsync(seconds: 0.05)
        box.visible = true                        // 重新出现：同一连接、同一版本 ⇒ 刷新键一字不变
        await host.pumpAsync(seconds: 8)

        let isLoadingText = L(.treeLoadingObjects)
        let texts = visibleTexts(host)
        let toolbar = host.firstSegmentedControl

        XCTAssertNotNil(
            toolbar,
            "重入之后树没回到「已加载」那一支 —— 同一次刷新的第二发把树留在加载态了"
        )
        XCTAssertFalse(texts.contains(isLoadingText), "重入之后加载态没收干净")
        XCTAssertEqual(
            state.objectTreeRefreshGate.inFlightCount, 0,
            "重入之后还有键留在在途表里 —— 这一把键从此刷不出来"
        )

        try writeEvidence("reentry", [
            "toolbarAfterReentry": toolbar != nil,
            "loadingTextAfterReentry": texts.contains(isLoadingText),
            "visibleTextsAfterReentry": texts,
            "nodesAfterReentry": nodeCount(host),
            "gateStarted": state.objectTreeRefreshGate.loadStats.started,
            "gateJoined": state.objectTreeRefreshGate.loadStats.joined,
            "inFlightAfterSettle": state.objectTreeRefreshGate.inFlightCount,
        ])

        await disconnectAndSettle(state)
    }
}
