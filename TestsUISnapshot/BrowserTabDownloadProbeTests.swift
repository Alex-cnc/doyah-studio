import AppKit
import SwiftUI
import XCTest

import DoyahCore
import DoyahPlatform
@testable import DoyahStudioApp

/// 「待人工验收清单」B 类第 9 条：**浏览器页签与下载**那一行 —— 队列 `L-89` ㈡ 第 9 条（第 103 轮）。
///
/// ## 清单里那三句人话（`FR-EDIT-34`）
///
///   ① 新建页签 → 打开一个站点 → **关掉重开应用，看是否恢复地址**；
///   ② 看外发日志：**按页签筛一次**（下拉里应出现你刚浏览的那个页签）；
///   ③ 找一个下载链接点一下（或直接访问一个 `.zip` / `.pdf`）→ 过 = 提示条「已下载到 <路径>」、
///      文件**真的在那个目录里**、同名文件**不会被覆盖**（自动加 `-1`）。
///
/// ## 本批最要紧的实测结论：② 在真机上**从来没生效过**（两处真缺陷，本批修掉）
///
/// 判据不是照着清单去点一遍，而是**按清单那条链的每一环去查**，于是查出：
///
///   · **落盘那一步把页签身份抹掉了**：`EgressLog.append` 的脱敏是**重建**一个 `EgressEntry`，
///     那次重建漏了 `tabID` / `tabTitle` ⇒ 内存里那条带着页签身份，**盘上那份没有**。
///     而界面读的是盘上那份（`refreshEgressLog()`）⇒ 页签下拉永远是空的、还灰着。
///   · **地址栏那条路没带页签身份**：`WebKitBrowserEngine.navigate(to:)`（地址栏 / 后退 / 前进 / 刷新
///     都走它）记日志时漏了 `tabID`；只有「页面内点击」那条（`decidePolicyFor`）带着 ⇒
///     同一件事两条路记出来的记录**形状不一致**，而清单原文正是「打开一个站点」这条路。
///
/// 两处都属于「看起来像功能、其实从来没生效」：单测当初用**内存里现造的** `EgressEntry` 判筛选，
/// 走不到落盘路径；静态判据只管「代码里有没有这段接线」。所以本批的判据**从盘上读**、**从界面上读**。
///
/// ## 判据的三条（各自独立）
///
///   ① **恢复**：真 `AppState` + 真页签库文件（`DOYAH_BROWSER_TABS_DIR`，临时目录）——
///      一条真导航之后重开应用，地址回来了，而且**没被加载**（`isBrowserPagePristine`）；
///      再把真视图渲染出来，**地址栏控件里的文本就是那个地址**。
///   ② **按页签筛**：真 `AppState` + 真外发日志文件（`DOYAH_EGRESS_LOG_DIR`）——
///      两个页签、只有一个发过请求；从**盘上**读回来的记录必须带着各自己的页签身份；
///      `EgressFilter(tabID:)` 只留那一个；再把**真 `EgressLogSheet`** 渲染出来，
///      页签那台下拉里恰好一个页签、且**可点**（反向对照：日志清空后它是灰的 ——
///      那条断言不是恒真的）。
///   ③ **下载**：真授权目录（walk 的是产品自己的 `BrowserDownload.destination` + 真 `FileManager`）——
///      文件真的落在那个目录、同名再来一次得到 `-1` 而**原来那份一个字节没动**；
///      走真 `AppState.handleBrowserDownload(_:page:)` ⇒ 提示条就是「已下载到 <路径>」，
///      外发日志里那条 `allowed` 也带着页签身份。
///
/// ## 边界（如实写在前面）
///
/// · **WebKit 的字节搬运那一步没有被驱动**：`WKDownload` 的回调要有一次真的下载
///   （要起本机 HTTP 服务 + 真 `WKWebView`），本批不假装验过 —— 判的是**引擎之后**的每一环
///   （落盘命名 / 覆盖规避 / 提示条 / 留痕），它们全是产品代码，且都喂真文件、真目录。
/// · **不走公网**：导航打在 `127.0.0.1:9`（discard 口，连不上就失败）—— 既覆盖「地址栏这条路」，
///   又不让探针自己产生真实外发。
/// · 标题是**数据**（引擎回报的），探针直接给一个可区分的标题；它不影响本批任何一条判据
///   （判的是**页签身份**与「筛得出来」）。
/// · 证据 JSON 落在 `DOYAH_SNAPSHOT_DIR`，由 `Scripts/run-manual-verification-probes.sh` 核对
///   —— **跳过 ≠ 通过**（探针没跑时文件不存在，脚本判红）。
final class BrowserTabDownloadProbeTests: XCTestCase {

    /// 页签库 / 外发日志 / 下载目录所在的**临时**目录（脚本注入）—— 探针绝不碰真实数据家。
    private var tabsDirectory: URL!
    private var egressDirectory: URL!
    private var scratch: URL!

    private var tabsFile: URL { tabsDirectory.appendingPathComponent("browser-tabs.json") }
    private var egressFile: URL { egressDirectory.appendingPathComponent("egress-log.jsonl") }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "浏览器页签探针要真落盘 + 真渲染：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
        let env = ProcessInfo.processInfo.environment
        guard let tabs = env["DOYAH_BROWSER_TABS_DIR"], !tabs.isEmpty,
              let egress = env["DOYAH_EGRESS_LOG_DIR"], !egress.isEmpty else {
            throw XCTSkip(
                "本探针要往页签库与外发日志里写夹具 ⇒ 必须在临时目录里跑："
                    + "请走 Scripts/run-manual-verification-probes.sh（它注入这两个目录）"
                    + " —— 跳过不算通过，脚本会核对证据文件"
            )
        }
        tabsDirectory = URL(fileURLWithPath: tabs, isDirectory: true)
        egressDirectory = URL(fileURLWithPath: egress, isDirectory: true)
        scratch = tabsDirectory.appendingPathComponent("downloads", isDirectory: true)
        try resetStores()
    }

    override func tearDownWithError() throws {
        // 收场也清一遍：同一次跑里所有用例共用一份目录，**上个用例晚到的写**不该落到下个用例头上。
        //
        // 但 setUp 被**跳过**时（门禁里没注入那两个目录）这几个字段还是 `nil`：这里既不能清场、
        // 也不能隐式解包 —— 第 103 轮实测：XCTest 跳过用例之后**仍会调 tearDown**，
        // 于是 `tabsDirectory!` 把「跳过」变成了**整个测试包崩掉**（门禁第 1 项当场红，signal 5）。
        guard tabsDirectory != nil, egressDirectory != nil, scratch != nil else { return }
        try? resetStores()
    }

    /// 清干净两个库文件 + 下载目录（同一次跑里所有用例共用一份目录 ⇒ 用例自己清场）。
    private func resetStores() throws {
        for url in [tabsFile, egressFile] {
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: scratch)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    /// 真 `AppState`（与界面同一条路）+ **等启动链落地**（链上会恢复页签、读许可证）。
    @MainActor
    private func makeState() async -> AppState {
        let state = AppState()
        await state.startupChain?.value
        return state
    }

    /// 等到条件成立 —— **异步**等，不是泵运行循环。
    ///
    /// 本批要等的三件事都是 `Task {}` 起的**主 actor** 上的工作（页签落盘 `persistBrowserTabs()` /
    /// 外发留痕 `handleBrowserDownload` 里那条 / `refreshEgressLog()`）。第 103 轮实测的坑：
    /// **同步** `RunLoop.run` 泵**等不到**它们（同一段代码泵满 8 秒盘上还是空的，测试方法返回之后才落地），
    /// 而 `Task.sleep` 会让出主 actor、把排队的作业放进来跑 ⇒ 改成异步等。
    /// 与此同族的教训：`await` 才是让主 actor 处理排队作业的地方（第 99/101 轮的「发出去就不管的异步」）。
    @MainActor
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return condition()
    }

    /// 证据文件落在快照目录（`DOYAH_SNAPSHOT_DIR`）；**脚本会核对它** —— 跳过 ≠ 通过。
    private func writeEvidence(_ caseName: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = caseName
        enriched["tabsDirectory"] = tabsDirectory.path
        enriched["egressDirectory"] = egressDirectory.path
        let data = try JSONSerialization.data(
            withJSONObject: enriched,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("browser-tab-evidence-\(caseName).json"),
            options: .atomic
        )
    }

    // MARK: - ① 恢复：重开应用地址回来了，而且没被加载

    @MainActor
    func testRestoredTabShowsAddressWithoutLoading() async throws {
        let address = "http://127.0.0.1:9/docs"
        let first = await makeState()
        let tabID = first.openBrowserTab()
        first.navigateBrowserTab(tabID, input: address)
        let reachedModel = await waitUntil { first.browserPages.first(where: { $0.id == tabID })?.url != nil }
        XCTAssertTrue(reachedModel, "地址栏导航没把地址写进页模型")
        let landed = await waitUntil { FileManager.default.fileExists(atPath: self.tabsFile.path) }
        XCTAssertTrue(landed, "页签没有落盘 —— 重开应用就没得恢复")

        // 重开：**新的** AppState 走真恢复路径（页签库文件是同一份）
        let second = await makeState()
        let page = try XCTUnwrap(
            second.browserPages.first(where: { $0.id == tabID }),
            "重开之后页签没回来（恢复路径断了）"
        )
        XCTAssertEqual(page.url?.absoluteString, address, "恢复出来的地址不是上次那个")
        XCTAssertTrue(
            second.isBrowserPagePristine(tabID),
            "恢复出来的页签被当成已加载 —— 打开应用就出网了（契约：恢复不自动请求）"
        )

        // 界面上看得见：真视图 + 真宿主，读**地址栏控件里的文本**
        let language = LocalizationManager.shared.effectiveLanguage
        let scope = LocalizationManager.beginHostLanguage(language)
        defer { LocalizationManager.endHostLanguage() }
        let host = UISnapshot.LiveHost(
            BrowserTabView(page: page).environmentObject(second),
            size: CGSize(width: 720, height: 360)
        )
        host.settle()
        let fields = host.textFields.map(\.stringValue)
        XCTAssertTrue(fields.contains(address), "地址栏里没有那个地址：\(fields)")
        let restoredTitle = LocalizedStrings.text(.browserRestoredTitle, language: language)
        XCTAssertTrue(
            scope.observed.contains(restoredTitle),
            "恢复出来的页签应当写明「\(restoredTitle)」，实际渲染到的文案：\(scope.observed.sorted())"
        )
        let shot = try host.capture(
            name: "browser-tab-restored",
            language: language,
            observed: scope.observed
        )
        try writeEvidence("restoredTab", [
            "address": address,
            "restoredAddress": page.url?.absoluteString ?? "",
            "pristineAfterRestart": second.isBrowserPagePristine(tabID),
            "addressFieldValues": fields,
            "restoredTitle": restoredTitle,
            "screenshot": shot.file,
        ])
    }

    // MARK: - ② 外发日志按页签筛（「下拉里应出现你刚浏览的那个页签」）

    /// 页签 A 发过请求（一次下载回报 + 一次**地址栏导航**）；页签 B 什么都没发。
    ///
    /// 判的是**盘上那份日志**（`refreshEgressLog()` 读的就是它）与**真界面上的那台下拉** ——
    /// 这两处都读不到内存里手造的 `EgressEntry`，所以两处真缺陷在这里原形毕露。
    @MainActor
    func testEgressLogCanBeFilteredByTab() async throws {
        let state = await makeState()
        let tabA = state.openBrowserTab()
        let tabB = state.openBrowserTab()
        XCTAssertNotEqual(tabA, tabB)

        // 标题 ≥12 字：页签下拉的标签取值规则（「短标签会被后来的长标题替换」）与记录先后无关
        let titleA = "文档站（探针 · 127.0.0.1:9）"
        let pageA = BrowserPage(
            id: tabA,
            url: URL(string: "http://127.0.0.1:9/a")!,
            title: titleA
        )
        state.applyBrowserUpdate(pageA)
        state.handleBrowserDownload(
            .finished(filename: "report.zip", url: scratch.appendingPathComponent("report.zip")),
            page: pageA
        )
        // 地址栏导航：真引擎 → 真策略 → 真日志；打在 discard 口（连不上就失败，也不会真出网）
        state.navigateBrowserTab(tabA, input: "http://127.0.0.1:9/a")
        let recorded = await waitUntil { self.egressLineCount() == 2 }
        XCTAssertTrue(recorded, "两条记录没落盘（实际 \(egressLineCount()) 行）—— 日志是异步写的，先等它")
        await state.refreshEgressLog()

        let entries = state.egressEntries
        XCTAssertEqual(
            entries.count, 2,
            "外发日志里应当恰好两条（下载回报 + 地址栏导航）：\(entries.map(\.origin))"
        )
        for entry in entries {
            XCTAssertEqual(
                entry.tabID, tabA,
                "这条记录从盘上读回来没有页签身份：\(entry.origin) / \(entry.detail ?? "-")"
            )
        }
        XCTAssertEqual(entries.filter { $0.tabID == tabB }.count, 0, "没发过请求的页签不该出现在日志里")

        let navigation = try XCTUnwrap(entries.first { $0.origin == "浏览器 · 页签" }, "地址栏那条没记进日志")
        XCTAssertEqual(navigation.tabID, tabA, "地址栏导航那条没带页签身份（只有页面内点击那条带）")
        XCTAssertEqual(navigation.target, "http://127.0.0.1:9/a")

        let download = try XCTUnwrap(entries.first { $0.origin == "浏览器 · 下载" }, "下载那条没记进日志")
        XCTAssertEqual(download.outcome, .allowed)
        XCTAssertEqual(download.tabTitle, titleA, "下载那条的页签标题不对")

        XCTAssertEqual(EgressFilter(tabID: tabA).apply(to: entries).count, 2, "按 A 筛不出它自己的两条")
        XCTAssertEqual(EgressFilter(tabID: tabB).apply(to: entries).count, 0, "按 B 筛出了不是它的记录")

        // 界面那一侧：日志面板真画出来了，而「页签」那台下拉的选项推导就是上面那份记录
        //
        // 为什么不去读控件：本机 SwiftUI 的 `Picker` **不落到 AppKit 控件**（第 103 轮实测：
        // 把 `EgressLogSheet` 渲染进离屏宿主，视图树里一个 `NSPopUpButton` 都没有）⇒
        // 推导搬成 Core 的纯函数 `EgressTabOptions`（与第 101 轮 `ObjectTreeRows` 同一个做法），
        // 「视图用的就是它」由探针脚本第十批的**源锚点**判。
        let language = LocalizationManager.shared.effectiveLanguage
        let allTabs = LocalizedStrings.text(.egressFilterAllTabs, language: language)
        let filled = try renderSheet(state: state, language: language, name: "browser-egress-tab-filter")
        XCTAssertTrue(
            filled.observed.contains(allTabs),
            "外发日志面板上没渲染出「页签」那台下拉（它那档「\(allTabs)」没出现）：\(filled.observed.sorted())"
        )
        // 如实记一条**工具事实**：本机 SwiftUI 的 `Picker` **不落到 AppKit 控件**
        // （视图树里一个 `NSPopUpButton` 都没有）⇒ 判据不能指着「点那台下拉」写，只能判推导本身。
        // 哪天系统版本变了，这条会翻红，提醒后来人「现在可以点它了」。
        XCTAssertTrue(
            filled.pickers.isEmpty,
            "视图树里出现了 NSPopUpButton（\(filled.pickers.count) 个）—— 请改走真点击那条路并把这条注记改掉"
        )
        let options = EgressTabOptions.options(from: entries)
        XCTAssertEqual(options.map(\.id), [tabA], "下拉里出现的页签不是恰好那一个（没发过请求的页签混进来了？）")
        XCTAssertEqual(options.map(\.label), [titleA], "下拉里那个页签的显示名不对")

        // 反向对照：日志清空 ⇒ 选项为空（面板上那台下拉因此是灰的：`.disabled(tabOptions.isEmpty)`）
        await state.clearEgressLog()
        XCTAssertTrue(state.egressEntries.isEmpty, "清空后内存里还有记录")
        XCTAssertTrue(
            EgressTabOptions.options(from: state.egressEntries).isEmpty,
            "日志空着时还有页签选项 —— 「可点」那条断言恒真了"
        )
        let cleared = try renderSheet(
            state: state,
            language: language,
            name: "browser-egress-tab-filter-empty"
        )
        XCTAssertTrue(cleared.observed.contains(allTabs), "清空后那台下拉不在面板上了")

        try writeEvidence("egressByTab", [
            "tabA": tabA.uuidString,
            "tabB": tabB.uuidString,
            "tabATitle": titleA,
            "entryOrigins": entries.map(\.origin),
            "entryTabIDs": entries.map { $0.tabID?.uuidString ?? "nil" },
            "navigationEntryTarget": navigation.target,
            "downloadEntryOutcome": download.outcome.rawValue,
            "filterCountForTabA": EgressFilter(tabID: tabA).apply(to: entries).count,
            "filterCountForTabB": EgressFilter(tabID: tabB).apply(to: entries).count,
            "tabPickerLabels": options.map(\.label),
            "tabPickerIDs": options.map(\.id.uuidString),
            "tabPickerLabelsWhenEmpty": EgressTabOptions.options(from: state.egressEntries).map(\.label),
            "sheetRenderedAllTabs": filled.observed.contains(allTabs),
            "screenshot": filled.shot.file,
            "emptyScreenshot": cleared.shot.file,
        ])
    }

    // MARK: - ③ 下载：文件真落在授权目录、同名不覆盖、提示条与留痕

    /// 「找一个下载链接点一下 → 提示条「已下载到 <路径>」、文件真的在那个目录里、
    /// 同名文件不会被覆盖（自动加 `-1`）」这条人话里**引擎之后**的每一环。
    ///
    /// 授权的获取走产品自己的书签机制（`MacDirectoryAccess.makeBookmark` → `DirectoryBookmark`
    /// → `AppState.authorizedDownloadDirectory()`），不塞假对象；落盘命名走产品自己的
    /// `BrowserDownload.destination` + **真 `FileManager`**；回报走产品自己的
    /// `AppState.handleBrowserDownload(_:page:)`（引擎的下载回调调的就是它）。
    @MainActor
    func testDownloadLandsInAuthorizedDirectoryWithoutOverwriting() async throws {
        let state = await makeState()
        let tabID = state.openBrowserTab()
        let title = "文档站（探针 · 下载）"
        let page = BrowserPage(id: tabID, url: URL(string: "http://127.0.0.1:9/a")!, title: title)
        state.applyBrowserUpdate(page)

        let bookmark = try MacDirectoryAccess.makeBookmark(for: scratch, displayName: "下载探针")
        state.storedDirectoryBookmarks = [bookmark]
        let directory = try XCTUnwrap(
            state.authorizedDownloadDirectory(),
            "授权目录没解析出来（探针进程里书签不通？）—— 没有它引擎会拒绝这次下载"
        )
        XCTAssertEqual(
            directory.resolvingSymlinksInPath().path,
            scratch.resolvingSymlinksInPath().path,
            "解析出来的授权目录不是探针那个临时目录"
        )

        func destination() throws -> URL {
            let outcome = BrowserDownload.destination(
                suggestedFilename: "report.zip",
                directory: directory,
                fileExists: { FileManager.default.fileExists(atPath: $0.path) }
            )
            return try XCTUnwrap(outcome.url, "没拿到落盘目标：\(outcome)")
        }

        let first = try destination()
        XCTAssertEqual(first.lastPathComponent, "report.zip")
        let payload = Data("探针写下的第一份内容".utf8)
        try payload.write(to: first)

        let second = try destination()
        XCTAssertEqual(second.lastPathComponent, "report-1.zip", "同名文件会被覆盖 —— 应当自动加 -1")
        try Data("第二份".utf8).write(to: second)
        XCTAssertEqual(try Data(contentsOf: first), payload, "第二份把第一份写坏了")

        // 回报：引擎下载结束走的就是这条（提示条 + 外发留痕）
        state.handleBrowserDownload(.finished(filename: "report.zip", url: second), page: page)
        let notice = L(.browserDownloadFinished, second.path)
        XCTAssertEqual(
            state.browserPages.first(where: { $0.id == tabID })?.notice,
            notice,
            "页上那条提示不是「已下载到 <路径>」"
        )
        let recorded = await waitUntil { self.egressLineCount() == 1 }
        XCTAssertTrue(recorded, "下载那条没落进外发日志")
        await state.refreshEgressLog()
        let entry = try XCTUnwrap(state.egressEntries.first, "外发日志里没有下载那条")
        XCTAssertEqual(entry.outcome, .allowed)
        XCTAssertEqual(entry.tabID, tabID, "下载那条从盘上读回来没有页签身份")
        XCTAssertEqual(entry.detail, BrowserDownload.logDetail(filename: "report.zip", outcome: "完成"))

        // 提示条真的画上去了：同一份视图两次渲染**逐字节相同**（无噪声），
        // 去掉提示条那一份必须**不同**（否则判据是空的）
        let reported = try XCTUnwrap(
            state.browserPages.first(where: { $0.id == tabID }),
            "页签不在模型里"
        )
        let withNotice = try renderTabHost(page: reported, state: state)
        XCTAssertEqual(
            withNotice,
            try renderTabHost(page: reported, state: state),
            "同一份视图两次渲染不一样 —— 像素判据有噪声"
        )
        var bare = reported
        bare.clearNotice()
        XCTAssertNotEqual(
            withNotice,
            try renderTabHost(page: bare, state: state),
            "去掉提示条之后画面一模一样 —— 那条提示根本没画上去"
        )

        try writeEvidence("downloadLanding", [
            "tabID": tabID.uuidString,
            "authorizedDirectory": directory.path,
            "firstFile": first.lastPathComponent,
            "secondFile": second.lastPathComponent,
            "firstBytes": payload.count,
            "firstUnchanged": try Data(contentsOf: first) == payload,
            "filesOnDisk": (try? FileManager.default.contentsOfDirectory(atPath: directory.path)
                .sorted()) ?? [],
            "notice": notice,
            "egressOutcome": entry.outcome.rawValue,
            "egressTabID": entry.tabID?.uuidString ?? "nil",
            "egressDetail": entry.detail ?? "",
        ])
    }

    // MARK: - 夹具与渲染

    /// 盘上那份外发日志的行数（**不是**内存里的 `egressEntries`）—— 判据要看落盘事实。
    private func egressLineCount() -> Int {
        guard let text = try? String(contentsOf: egressFile, encoding: .utf8) else { return 0 }
        return text
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    /// 把**真 `EgressLogSheet`** 渲染一遍，取回这一遍渲染出来的文案与那张图。
    ///
    /// 面板的 `.task` 会去刷新日志 —— 离屏宿主会泵运行循环（第 11 轮实测：`.task` 会跑完），
    /// 所以先 `pump` 一下再看画面。
    @MainActor
    private func renderSheet(
        state: AppState,
        language: AppLanguage,
        name: String
    ) throws -> (observed: Set<String>, pickers: [NSPopUpButton], shot: UISnapshot.Record) {
        let scope = LocalizationManager.beginHostLanguage(language)
        defer { LocalizationManager.endHostLanguage() }
        let host = UISnapshot.LiveHost(
            EgressLogSheet().environmentObject(state),
            size: CGSize(width: 900, height: 620)
        )
        host.pump(0.8)
        let shot = try host.capture(name: name, language: language, observed: scope.observed)
        return (scope.observed, host.popUpButtons, shot)
    }

    /// 把**真 `BrowserTabView`** 渲染一遍，返回这一帧的画面指纹
    /// （用于「提示条在不在」的对照：同一份视图两次必须相同、去掉提示条必须不同）。
    @MainActor
    private func renderTabHost(page: BrowserPage, state: AppState) throws -> String {
        let host = UISnapshot.LiveHost(
            BrowserTabView(page: page).environmentObject(state),
            size: CGSize(width: 720, height: 300)
        )
        host.settle()
        return try host.signature()
    }
}
