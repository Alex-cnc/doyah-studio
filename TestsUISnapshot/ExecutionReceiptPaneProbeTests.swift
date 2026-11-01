import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「执行回执」的 **App 侧探针**（`FR-STD-DB-TASK-003`）—— B1 批次第一片。
///
/// ## 这一行为什么停在 🟡（台账备注原文「差人工点一次」）
///
/// 核盘之后要分开说三件事：
///   · `Core/ExecutionReceipt` 的**结构与渲染**早有 25 + 4 例判据（结局四档 / 影响行数 `nil` /
///     结果集读数 / 四类形状脱敏 / 确定性 JSON / 册子容量）；
///   · 但那是「把一条回执拼成文本」，**没有一处碰过剪贴板、也没有一处量过界面上那三枚按钮**；
///   · 真正交付给用户的是「下方面板 → 回执页 → 点复制 / 导出 / 清空之后发生了什么」。
///     这一段此前**一次都没人量过**：按钮可以不接线、可以接错 tab、剪贴板可以不动 ——
///     上面 29 例照样全绿。
///
/// ## 这条探针怎么量（不靠人点，也不靠「看着对」）
///
/// 挂**真** `ExecutionReceiptPane` 进离屏真窗口 → 从视图树里取出**真 `NSButton`**
/// （本片把三枚动作从 SwiftUI `Button` 换成 `PanelIconButton`：SwiftUI 按钮在离屏宿主里
/// 不落 `NSButton`、无障碍树也不构建 ⇒ 只能靠人点，见 `DialogActionRowProbeTests` 文件头实测）
/// → `performClick(nil)`（用户点它走的就是这条 action 路径）→ 读 `NSPasteboard.general`
/// 里真实的字符串、读 `tab.receiptLog` 与状态栏那句话。判据是**字节与条数**，不是截图。
///
/// ## 判据六条
///
/// ① 三枚动作都**真的在**、且各自带着自己那句提示（少了哪一枚 / 提示挂了别人的话都算红）；
/// ② **复制**：剪贴板里是整本回执（新的在前）、逐字节等于 Core 渲染的那一份、
///    口令已被抹成 `***` 而原文一个字都不在；
/// ③ **空态**：没有回执时点复制 / 清空都**不动剪贴板**，只给一句理由（「空数据按钮」的处置口径）；
/// ④ **清空**：点一下回执册真的空了、面板回空态、状态栏说清「已清空」，且此后再点复制不动剪贴板；
/// ⑤ **导出**：`writeReceipts(_:to:)`（面板之后那一半，与按钮同一条出口）写出的文件
///    与 `exportData()` 逐字节相同、能解回两条、原文口令不在里面；
/// ⑥ **画的是每一条**：三条回执的画面墨迹比一条明显多（证明不是只画了一条 / 只画了个空壳）。
///
/// ## 边界（如实登记，别把这条读成「全点过了」）
///
/// · **导出按钮后面那个保存面板没点**：`NSSavePanel.runModal()` 是模态的，无人值守的机器上
///   不该弹窗，探针也不该去点它。所以「面板弹出来、用户选路径」这一跳由人承担；
///   面板**之后**的落盘那一半（也就是本行验收要点里唯一能出错的逻辑）由 ⑤ 判住。
/// · **回执正文读不出来**：SwiftUI `Text`（`.textSelection(.enabled)`）在这台宿主里不落
///   `NSTextField` / `NSTextView` ⇒ 「界面上逐字写着哪几个字段」判不到；那一面由
///   `Tests/ExecutionReceiptTests` 判 Core 渲染，本文件只判「点了之后剪贴板 / 台账里是什么」。
/// · **真鼠标拖选正文**：输入设备行为，与 `FR-STD-DB-RES-006` 同一类边界，不在本行验收要点里。
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与其它端上探针同一条纪律：取证才跑，每轮门禁不跑。
final class ExecutionReceiptPaneProbeTests: XCTestCase {

    /// 拍照与宿主共用的尺寸（一处定义，夹具与判据不各写一份）。
    static let paneSize = CGSize(width: 720, height: 420)

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1",
            "回执页探针要真 AppKit 按钮与真系统剪贴板：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    /// 一条回执（`sql` 里刻意带一句口令，用来判脱敏有没有在这条路上失效）。
    private func receipt(
        outcome: ExecutionOutcome,
        database: String,
        seconds: Double,
        affectedRows: Int? = nil,
        sql: String = "select 1",
        errorText: String? = nil
    ) -> ExecutionReceipt {
        ExecutionReceipt(
            executedAt: Date(timeIntervalSince1970: 1_760_000_000 + seconds),
            duration: seconds,
            connectionName: "本机测试库",
            database: database,
            scopeTitle: "整篇",
            statementCount: 1,
            outcome: outcome,
            affectedRows: affectedRows,
            results: ExecutionReceipt.ResultReading(
                resultSetCount: outcome == .succeeded ? 1 : 0,
                rowCount: outcome == .succeeded ? 12 : 0,
                columnCount: outcome == .succeeded ? 3 : 0
            ),
            sql: sql,
            errorText: errorText
        )
    }

    /// 三条：成功 / 失败（带口令与错误原文）/ 未发出。旧 → 新按这个顺序进册子。
    private func threeReceipts() -> [ExecutionReceipt] {
        [
            receipt(outcome: .succeeded, database: "shop", seconds: 0.4, affectedRows: 3, sql: "update orders set note = 'x'"),
            receipt(
                outcome: .failed,
                database: "shop",
                seconds: 1.5,
                sql: "alter user app with password 'S3cretPass!'",
                errorText: "permission denied for table orders"
            ),
            receipt(outcome: .refused, database: "shop", seconds: 0, sql: "drop table orders"),
        ]
    }

    @MainActor
    private struct Host {
        let state: AppState
        let tabID: UUID
        let live: UISnapshot.LiveHost<AnyView>

        var buttons: [NSButton] {
            UISnapshot.LiveHost<AnyView>.findViews(ofType: NSButton.self, in: live.hosting)
        }

        var log: ExecutionReceiptLog {
            state.tabs.first(where: { $0.id == tabID })?.receiptLog ?? ExecutionReceiptLog()
        }

        /// 按提示语认出那一枚（提示是产品自己给的那句话，不写死字面量）。
        func button(_ help: String) -> NSButton? {
            buttons.first(where: { $0.toolTip == help })
        }

        func tearDown() {
            live.window.contentView = nil
        }
    }

    /// 把**真** `ExecutionReceiptPane` 挂进离屏窗口（不上屏：无人值守的机器不该闪一下）。
    @MainActor
    private func mount(_ receipts: [ExecutionReceipt]) throws -> Host {
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        state.newQueryTab()
        let tabID = try XCTUnwrap(state.tabs.last?.id, "建不出查询页签 —— 夹具坏了")
        if let index = state.tabs.firstIndex(where: { $0.id == tabID }) {
            for item in receipts {
                state.tabs[index].receiptLog.append(item)
            }
        }

        // 生产里这块面板拿到的是**当帧**的那个 `QueryTab`（`MainWindow` 每次重算都从 `appState.tabs`
        // 取）；夹具照抄这一点 —— 直接传一份值快照的话，清空之后面板读的还是旧册子
        // （那是夹具的错，不是产品的错，会把「面板没跟着变」判成缺陷）。
        let live = UISnapshot.LiveHost(
            AnyView(PaneHarness().environmentObject(state)),
            size: Self.paneSize
        )
        live.settle()

        let host = Host(state: state, tabID: tabID, live: live)
        XCTAssertFalse(host.buttons.isEmpty, "回执页一枚真 `NSButton` 都没取到 —— 三枚动作没落成 AppKit 控件")
        return host
    }

    // MARK: - ① 三枚动作都在，且各带各的提示

    @MainActor
    func testTheThreeActionsAreRealButtonsWithTheirOwnHints() throws {
        let host = try mount(threeReceipts())
        defer { host.tearDown() }

        let copyHint = L(.receiptCopyAll)
        let exportHint = L(.receiptExport)
        let clearHint = L(.receiptClear)

        XCTAssertEqual(host.buttons.count, 3, "回执页应当正好三枚动作（复制 / 导出 / 清空），实际 \(host.buttons.count) 枚")
        for hint in [copyHint, exportHint, clearHint] {
            let button = try XCTUnwrap(host.button(hint), "没有一枚按钮带「\(hint)」这句提示 —— 入口没有落到真控件上")
            XCTAssertFalse(button.isHidden, "「\(hint)」那枚藏起来了（空数据时也要常驻：藏起来会多一次「为什么这里没有」的提问）")
            XCTAssertGreaterThan(button.frame.width, 4, "「\(hint)」那枚宽度近 0（画了但点不到）")
            XCTAssertEqual(button.accessibilityLabel(), hint, "「\(hint)」那枚的读屏标签与提示不一致（图标按钮没有文字，标签就是它唯一的说法）")
            XCTAssertNotNil(button.image, "「\(hint)」那枚没有图标（只剩一个没有面积的空按钮）")
        }
        // 三枚的提示**互不相同**：同一个提示挂两次的话，上面按提示认按钮会认错。
        XCTAssertEqual(Set(host.buttons.compactMap(\.toolTip)).count, 3, "三枚里有两枚的提示一样 ⇒ 用户分不清哪枚是哪件")
        print("🧪 三枚动作：\(host.buttons.compactMap(\.toolTip))")
    }

    // MARK: - ② 复制：整本回执（新的在前）逐字节进系统剪贴板

    @MainActor
    func testCopyReachesTheSystemPasteboardWithEveryReceiptNewestFirst() throws {
        let receipts = threeReceipts()
        let host = try mount(receipts)
        defer { host.tearDown() }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("SENTINEL-BEFORE-CLICK", forType: .string)

        let copy = try XCTUnwrap(host.button(L(.receiptCopyAll)))
        copy.performClick(nil)

        let pasted = try XCTUnwrap(NSPasteboard.general.string(forType: .string), "点完复制剪贴板里没有字符串")
        let expected = host.log.exportText(labels: host.state.receiptLabels)
        XCTAssertEqual(pasted, expected, "剪贴板内容与 Core 渲染的整本回执不一致（复制走的不是同一条渲染）")

        // 新的在前：界面上先看最近一跑，剪贴板那本按时间读（旧 → 新）。
        let failedRange = try XCTUnwrap(pasted.range(of: "permission denied"), "失败那条的错误原文没进剪贴板")
        let refusedRange = try XCTUnwrap(pasted.range(of: "drop table orders"), "最后那条（未发出）没进剪贴板")
        XCTAssertLessThan(failedRange.lowerBound, refusedRange.lowerBound, "回执不是按旧 → 新的次序排的")

        // 四条读数（结局 / 影响行数 / 耗时 / 结果集）与执行时刻都在。
        for needle in [L(.receiptOutcome), L(.receiptAffectedRows), L(.receiptDuration), L(.receiptExecutedAt)] {
            XCTAssertTrue(pasted.contains(needle), "剪贴板里少了「\(needle)」这一项 —— 复制出去的缺字段")
        }
        XCTAssertEqual(host.state.statusMessage, L(.receiptCopied, 3), "复制之后状态栏没有说清复制了几条")
        print("🧪 复制读数：\(pasted.count) 字 / 状态栏「\(host.state.statusMessage)」")
    }

    /// 口令必须**在这条路上也没了**（结构里已抹过，但复制可以绕过 render —— 那次事故的回归钉）。
    @MainActor
    func testCopyNeverCarriesThePasswordLiteral() throws {
        let host = try mount(threeReceipts())
        defer { host.tearDown() }

        let copy = try XCTUnwrap(host.button(L(.receiptCopyAll)))
        copy.performClick(nil)

        let pasted = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertFalse(pasted.contains("S3cretPass!"), "剪贴板里出现了口令原文 —— 复制没有走渲染后的那一份")
        XCTAssertTrue(pasted.contains("***"), "剪贴板里没有脱敏标记（口令位置既不是原文也没有抹痕，用户读不出「这里有一句被抹了」）")
        XCTAssertTrue(
            host.log.receipts.contains { $0.redaction.total > 0 },
            "夹具里那条带口令的语句没有被记成「脱敏过」—— 判据量到的会是假绿"
        )
    }

    // MARK: - ③ 空态：点得动、给理由、不动剪贴板

    @MainActor
    func testEmptyPaneExplainsItselfAndLeavesThePasteboardAlone() throws {
        let host = try mount([])
        defer { host.tearDown() }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("SENTINEL-EMPTY", forType: .string)

        let copy = try XCTUnwrap(host.button(L(.receiptCopyAll)))
        copy.performClick(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "SENTINEL-EMPTY", "空数据时点复制改动了剪贴板")
        XCTAssertEqual(host.state.statusMessage, L(.receiptCopyEmpty), "空数据时点复制没有给理由（静默无反应 = 用户以为按钮坏了）")

        let clear = try XCTUnwrap(host.button(L(.receiptClear)))
        clear.performClick(nil)
        XCTAssertEqual(host.state.statusMessage, L(.receiptClearEmpty), "空数据时点清空没有给理由")

        // 空态**真的画了东西**（不是一片空白）：空态文案与图标都是内容。
        let record = try host.live.capture(name: "FR-STD-DB-TASK-003-receipts-empty", observed: [L(.receiptEmpty)])
        XCTAssertGreaterThan(record.contentRatio, 0.002, "空态画面几乎没有内容 —— 这一页在用户眼里会像坏了")
        print("🧪 空态内容占比 \(String(format: "%.3f", record.contentRatio))")
    }

    // MARK: - ④ 清空：册子真空了、面板回空态、此后再复制不动剪贴板

    @MainActor
    func testClearEmptiesTheLogAndThePaneFallsBackToItsEmptyState() throws {
        let host = try mount(Array(threeReceipts().prefix(2)))
        defer { host.tearDown() }

        XCTAssertEqual(host.log.count, 2, "夹具没把两条回执装进册子")
        let filled = try host.live.capture(name: "FR-STD-DB-TASK-003-receipts-two")
        XCTAssertGreaterThan(filled.contentRatio, 0.002, "有回执时画面几乎没有内容 —— 回执没被画出来")

        let clear = try XCTUnwrap(host.button(L(.receiptClear)))
        clear.performClick(nil)
        host.live.pump(0.2)

        XCTAssertTrue(host.log.isEmpty, "点了清空，回执册里还有 \(host.log.count) 条")
        XCTAssertEqual(host.state.statusMessage, L(.receiptCleared), "清空之后状态栏没有说清发生了什么")

        let emptied = try host.live.capture(name: "FR-STD-DB-TASK-003-receipts-emptied")
        XCTAssertGreaterThan(emptied.contentRatio, 0.002, "清空之后画面整个空了 —— 空态没画出来")
        XCTAssertNotEqual(
            filled.contentRatio, emptied.contentRatio,
            "清空前后两张图的内容占比一模一样 ⇒ 面板没有跟着台账变（用户会以为点空了）"
        )

        // 清空之后点复制：一句理由，不动剪贴板。
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("SENTINEL-AFTER-CLEAR", forType: .string)
        host.button(L(.receiptCopyAll))?.performClick(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "SENTINEL-AFTER-CLEAR", "清空之后再点复制改动了剪贴板")
        print("🧪 清空读数：占比 \(String(format: "%.3f", filled.contentRatio)) → \(String(format: "%.3f", emptied.contentRatio))")
    }

    // MARK: - ⑤ 导出：面板之后那一半写出的字节

    @MainActor
    func testExportWritesExactlyWhatTheStructureHoldsAndNoSecret() throws {
        let host = try mount(Array(threeReceipts().prefix(2)))
        defer { host.tearDown() }

        // 导出那枚必须**在**（提示、可点），否则「可导出」这条在界面上没有入口。
        let export = try XCTUnwrap(host.button(L(.receiptExport)), "没有「\(L(.receiptExport))」那枚按钮")
        XCTAssertEqual(export.accessibilityLabel(), L(.receiptExport))

        let directory = UISnapshot.outputDirectory.appendingPathComponent("receipt-export-probe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("execution-receipts.json")
        try? FileManager.default.removeItem(at: url)

        // 面板之后那一半（按钮点的也是这一条出口）：只把路径换成临时文件。
        XCTAssertTrue(host.state.writeReceipts(host.log, to: url), "写盘那一半返回了假（\(host.state.errorMessage ?? "无错误信息")）")

        let written = try Data(contentsOf: url)
        XCTAssertEqual(written, try host.log.exportData(), "写出去的字节与结构导出不一致（导出另拼了一份 JSON）")

        let decoded = try JSONDecoder.iso8601().decode([ExecutionReceipt].self, from: written)
        XCTAssertEqual(decoded.count, 2, "文件里不是两条回执")
        let text = try XCTUnwrap(String(data: written, encoding: .utf8))
        XCTAssertFalse(text.contains("S3cretPass!"), "导出文件里有口令原文")
        XCTAssertTrue(text.contains("permission denied"), "导出文件里没有那条错误原文（审计要看的东西丢了）")
        XCTAssertEqual(
            host.state.statusMessage,
            L(.receiptExported, 2, "execution-receipts.json"),
            "导出之后状态栏没有说清「几条 → 文件名」"
        )
        print("🧪 导出读数：\(written.count) 字节 / 2 条 / 状态栏「\(host.state.statusMessage)」")
    }

    // MARK: - ⑥ 画的是每一条，不是只画一条

    @MainActor
    func testMoreReceiptsPaintMoreOfThePane() throws {
        let one = try mount([threeReceipts()[0]])
        let oneShot = try one.live.capture(name: "FR-STD-DB-TASK-003-receipts-one")
        one.tearDown()

        let three = try mount(threeReceipts())
        let threeShot = try three.live.capture(name: "FR-STD-DB-TASK-003-receipts-three")
        three.tearDown()

        XCTAssertGreaterThan(
            threeShot.contentRatio, oneShot.contentRatio,
            "三条回执的画面内容占比（\(String(format: "%.3f", threeShot.contentRatio))）不比一条（\(String(format: "%.3f", oneShot.contentRatio))）多"
                + " ⇒ 只看得到一条，多出来的没画"
        )
        print("🧪 内容占比：一条 \(String(format: "%.3f", oneShot.contentRatio)) / 三条 \(String(format: "%.3f", threeShot.contentRatio))")
    }
}

private extension JSONDecoder {
    /// `ExecutionReceipt` 用 ISO8601 编码日期（与 `exportData()` 同一口径）。
    static func iso8601() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 回执页的宿主壳：**每次都从 `appState.tabs` 取当帧那份页签**（与生产那条取值路一致）。
///
/// 尺寸必须**钉住**：空态那一支（`Spacer` + 居中图标 + 一段文案）在「不限高」的宿主里会自己长到
/// 1983pt，画面就跑到拍照区外面去了（实测：清空之后快照内容占比 0.000，而同一份空态第一次挂载时是
/// 0.015）。生产里它是被下方面板的高度约束住的，夹具照抄这一点。
private struct PaneHarness: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        // 与生产同一条取值路（`MainWindow` 传的是 `appState.selectedTab`，不是「第一个页签」）。
        ExecutionReceiptPane(tab: appState.selectedTab)
            .frame(width: ExecutionReceiptPaneProbeTests.paneSize.width,
                   height: ExecutionReceiptPaneProbeTests.paneSize.height)
    }
}
