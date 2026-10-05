import AppKit
import Combine
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **工作区 Markdown 预览的界面面不变量** —— 队列 `L-137` 第三片。
///
/// ## 判的是三件界面层能机器量的事
///
/// ① **只读**：预览里不许有可编辑文本视图。需求已拍板「Markdown 是唯一真相」，
///    预览要是能改字，就立刻多出一个"哪边为准"的问题 —— 而这类问题**编译照过**。
///    判据不只报"没找到"：同一族里带**对照**（真的插一个可编辑 `NSTextView` 进去，
///    量法必须看得见它），否则"零命中"可能只是这套遍历根本看不见东西。
/// ② **跟随滚动落点**：光标行 → 顶层块下标，必须与契约层 `anchor(forSourceLine:)`
///    同解（界面层不许自己数行）。
/// ③ **如实报数**：截断时才有计数，且与 `report` 逐字段相等；没截断就一行不多。
/// ④ **预览全过程统一外发日志零写入**（判据 ②）：远端图 / 链接 / 内联 HTML 这些
///    最容易「顺手做成一发出网」的内容，喂进全过程之后统一外发日志的条数必须**一条不增**；
///    同一族带两条对照（数条数的量法写得出来就读得到 / `shared` 就是应用默认那一份），
///    外加渲染侧不许自带**直连网络 API** 的源码判据。
///
/// ## 边界（如实登记）
///
/// · 不验观感（字号 / 间距好不好看）—— 那是快照 + 读图那一族；
/// · `.task(id:)` 在离屏宿主里不会自己转 run loop，所以本轮用一个**有上限的自旋**
///   放它跑完（`settle`）；高度断言留了余量，不拿像素级相等当判据；
/// · **链接可点**（剩余③，2026-10-01）量的是**链接属性**与**接管 `openURL` 那一句**
///   （`OpenURLAction.Result` 不是 `Equatable`，运行期比不了「回的是哪一支」）；
///   「点一下真的开在浏览器页签里」是 GUI 行为 ⇒ 归人工点验（内测清单）。
final class MarkdownPreviewProbeTests: XCTestCase {

    // MARK: 取样文档

    /// 覆盖 GFM 的主要块型（标题 / 段落 / 嵌套列表 / 表格 / 围栏 / 引用 / 分隔线）。
    private let sample = """
    # 标题

    第一段 **粗体** 与 `代码`。

    - 甲
    - 乙
      - 乙一

    | 列 | 值 |
    | --- | ---: |
    | a | 1 |

    ```swift
    let x = 1
    ```

    > 引用

    ---
    """

    // MARK: 装配（全程离屏：不需要窗口、不渲染位图、不需要人在场）

    @MainActor
    private func host<V: View>(_ view: V, width: CGFloat = 720) -> NSHostingController<V> {
        let controller = NSHostingController(rootView: view)
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    /// 放 SwiftUI 的 `.task(id:)` 跑完：离屏宿主不会自己转 run loop。
    @MainActor
    private func settle(_ controller: NSHostingController<some View>, seconds: TimeInterval = 0.4) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            controller.view.layoutSubtreeIfNeeded()
        }
    }

    /// 递归收集整棵树里的文本视图（对照用例证明它**看得见**真插进去的 `NSTextView`）。
    @MainActor
    private func textViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView { found.append(textView) }
        for subview in view.subviews {
            found.append(contentsOf: textViews(in: subview))
        }
        return found
    }

    @MainActor
    private func preview(_ text: String) -> MarkdownPreviewView {
        MarkdownPreviewView(text: text, language: .markdown, cursor: MarkdownPreviewCursorModel())
    }

    // MARK: ① 只读

    @MainActor
    func testPreviewHasNoEditableTextSurface() {
        let controller = host(preview(sample))
        settle(controller)
        let editors = textViews(in: controller.view)
        XCTAssertTrue(
            editors.isEmpty,
            "预览里不该有文本视图（只读 = 不引 NSTextView）：实测 \(editors.count) 个，"
                + "可编辑 \(editors.filter(\.isEditable).count) 个"
        )
        XCTAssertEqual(textViews(in: controller.view).filter { $0 is CodeTextView }.count, 0)
    }

    /// **对照（判据必须能判红）**：同一套遍历，插一个真可编辑的 `NSTextView` 进去就得看得见。
    @MainActor
    func testProbeSeesAnEditableTextSurface() {
        let host = host(EditableProbeRepresentable())
        host.view.layoutSubtreeIfNeeded()
        let editors = textViews(in: host.view)
        XCTAssertFalse(editors.isEmpty, "量法看不见真插进去的 NSTextView ⇒ 上面那条的\"零命中\"不算数")
        XCTAssertTrue(editors.contains(where: \.isEditable))
    }

    // MARK: ② 跟随滚动的落点

    func testScrollTargetFollowsTheContractAnchor() {
        let document = MarkdownDocument.parse(sample)
        for line in 1...max(1, document.lineCount) {
            XCTAssertEqual(
                MarkdownPreviewContent.scrollTarget(forSourceLine: line, in: document),
                document.anchor(forSourceLine: line)?.blockIndex,
                "第 \(line) 行：界面层的落点必须与契约层锚点同解（界面不许自己数行）"
            )
        }
        XCTAssertNil(MarkdownPreviewContent.scrollTarget(forSourceLine: 0, in: document))
        XCTAssertNil(MarkdownPreviewContent.scrollTarget(forSourceLine: document.lineCount + 1, in: document))
    }

    // MARK: ③ 如实报数

    func testTruncationCountsOnlyWhenTheReportSaysSo() {
        let clean = MarkdownDocument.parse(sample)
        XCTAssertNil(MarkdownPreviewContent.truncationCounts(clean.report))

        let truncated = MarkdownDocument.parse(
            "# 标题\n\n正文\n更多正文\n",
            limits: MarkdownParseLimits(maxLines: 1, maxBlocks: 1)
        )
        let counts = MarkdownPreviewContent.truncationCounts(truncated.report)
        XCTAssertNotNil(counts, "真截断了就必须报出来（不许静默少画）")
        XCTAssertEqual(counts?.skipped, truncated.report.skippedLineCount)
        XCTAssertEqual(counts?.unparsed, truncated.report.unparsedLineCount)
    }

    // MARK: 光标行（同一行重复上报不许反复发布）

    @MainActor
    func testCursorModelPublishesOnlyOnChange() {
        let model = MarkdownPreviewCursorModel()
        var published: [Int] = []
        let token = model.$line.dropFirst().sink { published.append($0) }
        defer { token.cancel() }

        model.report(line: 1)
        model.report(line: 3)
        model.report(line: 3)
        model.report(line: 0)
        model.report(line: -2)

        XCTAssertEqual(model.line, 3, "越界值必须丢掉（宁可不动，也不猜一个位置）")
        XCTAssertEqual(published, [3], "同一行重复上报不许发布：实测 \(published)")
    }

    // MARK: 内容决定高度（证明真的画出来了，不是一张空底）

    /// 量的**是预览真渲染的那一份**（`MarkdownBlocksView`）——
    /// 预览自身外面套着 `ScrollView`，它按提议高度撑满，量不出内容差异
    /// （第一版判据就是这么判红的：10000.0 不比 10000.0 高）。
    @MainActor
    func testBlocksRenderTallerWithMoreContent() {
        let longDocument = MarkdownDocument.parse(sample + "\n" + sample + "\n" + sample)
        let shortDocument = MarkdownDocument.parse("短")

        let long = host(MarkdownBlocksView(blocks: longDocument.blocks, language: .markdown))
        let short = host(MarkdownBlocksView(blocks: shortDocument.blocks, language: .markdown))
        let longHeight = long.sizeThatFits(in: NSSize(width: 720, height: 10_000)).height
        let shortHeight = short.sizeThatFits(in: NSSize(width: 720, height: 10_000)).height

        XCTAssertGreaterThan(shortHeight, 0)
        XCTAssertGreaterThan(
            longHeight,
            shortHeight,
            "内容多了高度不变 ⇒ 这些块没真画（空底也能过的假绿）：\(shortHeight) → \(longHeight)"
        )
    }

    /// 空文件也画得出来、且**没有编辑面**（空态那一句人话由语言表的键在位保证，
    /// 本判据不做文案断言 —— 文案不是这一层的事）。
    @MainActor
    func testEmptyDocumentStillHosts() {
        let controller = host(preview(""))
        settle(controller)
        XCTAssertTrue(textViews(in: controller.view).isEmpty)
    }

    // MARK: ④ 预览全过程：统一外发日志零写入（判据 ②）

    /// **诱饵**：这几种内容最容易被「顺手做成一次出网」—— 远端图片、链接、内联 HTML、
    /// 引用里的地址。预览哪天开始拉远端图，「默认零外发」这条对外承诺就**悄悄**不成立了，
    /// 而编译照过、快照照绿、读图也读不出来。
    private let egressBait = """
    # 远端图与链接

    ![远端图](https://example.com/pixel.png)

    [链接](https://example.com/page)

    ![本机图](file:///tmp/not-authorized.png)

    > 引用里的地址 https://example.com/quote
    """

    /// 读统一外发日志现在有几条（**只读**，不写）。
    private func egressCount() async throws -> Int {
        try await EgressLog.shared.entries().count
    }

    /// 量具目录：优先用脚本注入的那个（`run-manual-verification-probes.sh` 会注入本仓
    /// `.build/` 下的临时目录）；没有注入就自己在本仓 `.build/` 下开一个。
    ///
    /// **为什么非要本仓内**：测试进程跑在**沙箱**里，写不进 `~/Library/Application Support`
    /// （实测：往那儿写会留下一个 0 字节的 `egress-log.jsonl.sb-*` 临时文件，日志永远数不出东西）
    /// ⇒ 拿一个写不进去的目录判「零写入」，是**假绿**（连真写入都落不了盘）。
    private func egressProbeDirectory() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let injected = environment["DOYAH_EGRESS_LOG_DIR"], !injected.isEmpty {
            return URL(fileURLWithPath: injected, isDirectory: true)
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let fallback = root.appendingPathComponent(".build/ui-probe-egress", isDirectory: true)
        // 在**第一次碰 `EgressLog.shared` 之前**把它指到可写目录（没注入时才这么做，
        // 绝不覆盖脚本注入的值）。
        setenv("DOYAH_EGRESS_LOG_DIR", fallback.path, 1)
        return fallback
    }

    /// **判据 ②**：全过程（解析正常 / 截断 / 超大 + 离屏渲染 + 跟随滚动扫全篇 + 空文档）
    /// 跑完，统一外发日志的条数**一条不增**。
    @MainActor
    func testPreviewProcessWritesNothingToTheUnifiedEgressLog() async throws {
        // 空跑防护：诱饵里必须真有「会诱发出网」的内容，否则这条判的是空文档。
        XCTAssertTrue(egressBait.contains("https://"), "诱饵里没有远端地址 ⇒ 这条判的是空跑")

        // ① 量具就是**应用那一份**，且它得**写得进去** —— 两件都不成立就明确跳过
        //    （跳过 ≠ 通过；探针脚本会核对证据，不让人拿「跳过」冒充「判过」）。
        let directory = egressProbeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let meter = await EgressLog.shared.fileLocation()
        guard meter.deletingLastPathComponent().path == directory.path else {
            throw XCTSkip("共享外发日志已被绑到别处（\(meter.path)）⇒ 这一条量不了，跳过（不算通过）")
        }
        let probe = EgressLog(directoryURL: directory)
        await probe.record(kind: .externalProgram, target: "probe-control", origin: "对照", outcome: .denied)
        let controlCount = try await probe.entries().count
        guard controlCount == 1 else {
            throw XCTSkip("\(directory.path) 写不进去（沙箱）⇒ 「零写入」判不出来，跳过（不算通过）")
        }
        // 对照那一条落盘 = 写得进、数得出；清掉它，回到干净基线。
        try? FileManager.default.removeItem(at: meter)

        let before = try await egressCount()
        XCTAssertEqual(before, 0, "清场后该是 0 条 —— 实测 \(before) 条")

        let cursor = MarkdownPreviewCursorModel()
        let controller = host(MarkdownPreviewView(text: egressBait, language: .markdown, cursor: cursor))
        settle(controller)

        // 渲染必须真的发生了（空底也能「零外发」—— 那不算数）。
        let blocks = MarkdownDocument.parse(egressBait)
        let tall = host(MarkdownBlocksView(blocks: blocks.blocks, language: .markdown))
        XCTAssertGreaterThan(
            tall.sizeThatFits(in: NSSize(width: 720, height: 10_000)).height, 0,
            "预览没画出任何高度 ⇒ 这一轮什么都没渲染，「零外发」不作数"
        )

        // 跟随滚动扫全篇（光标行 → 锚点 → 滚动），截断那一档（报数条会被画出来），空文档。
        for line in 0...(blocks.lineCount + 2) { cursor.report(line: line) }
        let truncated = MarkdownDocument.parse(
            egressBait + "\n更多正文\n", limits: MarkdownParseLimits(maxLines: 3, maxBlocks: 2)
        )
        XCTAssertNotNil(
            MarkdownPreviewContent.truncationCounts(truncated.report),
            "截断那一条没生效 ⇒ 报数条这一路没被走到"
        )
        settle(host(MarkdownBlocksView(blocks: truncated.blocks, language: .markdown)))
        settle(host(preview("")))

        // 真出网那条路多半是**异步**的（URLSession 回调、后台任务）：给它一个让出的窗口再读一次 ——
        // 免得「晚到的写」被当成「没写」。`Task.sleep` 会把主 actor 让出去，别的任务这期间能跑。
        try? await Task.sleep(nanoseconds: 300_000_000)

        let after = try await egressCount()
        XCTAssertEqual(
            after, before,
            "预览全过程往统一外发日志写了 \(after - before) 条 —— 「默认零外发」这条承诺当场作废"
        )
        try? FileManager.default.removeItem(at: meter)   // 清场：别把夹具留给后面的用例
    }

    /// **对照之一（判据必须能判红）**：同一套「数条数」的量法，真写一条必须数得到 ——
    /// 否则上面那条「0 条」可能只是这个量法根本读不出东西（假绿）。
    /// 用临时目录里的**另一份**日志来写：不去污染应用那一份（探针只管读）。
    func testEgressCountMethodSeesAWrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPreviewEgressProbe-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = EgressLog(directoryURL: directory)
        let before = try await log.entries().count
        XCTAssertEqual(before, 0, "临时目录是新的，这一步该是 0 条")

        await log.record(
            kind: .browser, target: "https://example.com/probe",
            origin: "对照", outcome: .allowed
        )
        let after = try await log.entries().count
        XCTAssertEqual(after, before + 1, "写了一条却数不出来 ⇒ 上面那条「零写入」不作数")
    }

    /// **对照之二**：上面量的是 `EgressLog.shared` —— 它必须就是**应用默认拿到的那一份**
    /// （没人注入目录时 `EgressLog()` 与 `shared` 解到同一个文件）。否则那条判据量的是
    /// 一个「没人往里写」的空壳，绿得毫无意义。
    func testSharedEgressLogIsTheDefaultInstance() async {
        let shared = await EgressLog.shared.fileLocation()
        let fresh = await EgressLog().fileLocation()
        XCTAssertEqual(
            shared.path, fresh.path,
            "`shared` 与默认构造解不到同一个文件 ⇒ 用量 `shared` 的那条判据量错了对象"
        )
    }

    // MARK: ⑤ 渲染侧不许自带直连网络的能力（同一条判据的另一条腿）

    /// 判据 ② 量的是**统一外发日志**；万一有人加了一处**绕过日志的直连**，那条量法看不见
    /// （日志里当然也没有）。所以再钉一条源码判据：预览渲染那一份里不许出现**直连网络的 API**。
    ///
    /// **边界（如实登记）**：只禁**直连 API**（`URLSession` / `WKWebView` / `import Network` /
    /// `NWConnection`），**不禁 URL 字符串** —— 链接默认开在已内嵌的浏览器页签（`L-137` 剩余③）
    /// 落地时那一侧本来就要拿地址；出网与否归浏览器那条通道（它自己写外发日志）。
    func testPreviewRenderSourceHasNoDirectNetworkAPI() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("App/Views/MarkdownPreviewView.swift"), encoding: .utf8
        )

        // 空跑防护：扫的那一份必须在位、形状对得上（改名 / 掏空 ⇒ 红）。
        XCTAssertGreaterThan(source.count, 4_000, "渲染侧源文件只有 \(source.count) 字节 ⇒ 这条判的是空跑")
        XCTAssertTrue(source.contains("struct MarkdownPreviewView"), "渲染侧源文件的形状对不上")

        let tokens = ["URLSession", "WKWebView", "import Network", "NWConnection"]
        let hits = tokens.filter { source.contains($0) }
        XCTAssertTrue(hits.isEmpty, "预览渲染侧出现了直连网络的 API：\(hits) —— 出网只能走统一外发日志那条通道")

        // 对照（判据必须能判红）：同一套扫法在**真的直连网络**的文件上必须命中。
        let control = try String(
            contentsOf: root.appendingPathComponent("Platform/macOS/WebKitBrowserEngine.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            tokens.filter { control.contains($0) }.isEmpty,
            "同一套扫法在浏览器引擎上都命中不了 ⇒ 上面那条「零命中」不作数"
        )
    }

    // MARK: ⑥ 链接可点（队列 `L-137` 剩余③，2026-10-01）

    /// 一份带链接的文档（链接在**段落里**，与 `egressBait` 那份同样的形状）。
    private let linkSample = "见 [文档](https://example.com/a?b=1) 与 [相对](docs/x.md) 完"

    /// **链接属性真的挂上了**：块里的行内 span 经渲染侧那一份组装之后，
    /// 「文档」那一段必须带着 `https://example.com/a?b=1`，其余各段**一个都没有**。
    ///
    /// 量的就是真渲染用的那一份（`MarkdownInline.attributed`）—— 不是测试里另拼一套。
    func testLinkRunsCarryTheLinkAttribute() throws {
        let document = MarkdownDocument.parse(linkSample)
        guard case let .paragraph(spans) = document.blocks[0].kind else {
            return XCTFail("应当是段落")
        }
        let attributed = MarkdownInline.attributed(spans)
        let links = links(in: attributed)

        XCTAssertEqual(links.count, 2, "带链接的段数与目标对不上：\(links)")
        XCTAssertEqual(links["文档"], "https://example.com/a?b=1")
        XCTAssertEqual(links["相对"], "docs/x.md")
        XCTAssertNil(links["见 "], "没链接的那几段不许被安上链接属性")
        XCTAssertNil(links[" 与 "])
        XCTAssertNil(links[" 完"])
    }

    /// **对照（判据必须能判红）**：同一套取值法在**没有链接**的文档上必须一条都取不到 ——
    /// 否则上面那条「两条都对」可能只是这套遍历见了谁都报链接。
    func testLinkAttributeProbeSeesNothingWithoutLinks() {
        let document = MarkdownDocument.parse("普通 **粗体** 与 `代码`")
        guard case let .paragraph(spans) = document.blocks[0].kind else {
            return XCTFail("应当是段落")
        }
        XCTAssertTrue(links(in: MarkdownInline.attributed(spans)).isEmpty)
    }

    /// **连不出来 URL 的目标按普通文本画**（不猜、不改写、**不假装可点**）：
    /// 点了什么都不发生的"链接"比纯文本更坏。
    func testUnparseableTargetIsDrawnAsPlainText() {
        let spans = [
            NoteSpan(text: "尖括号", link: "https://a<b.com/"),
            NoteSpan(text: "空目标", link: ""),
        ]
        XCTAssertTrue(links(in: MarkdownInline.attributed(spans)).isEmpty)
        XCTAssertNil(MarkdownPreviewContent.linkURL(for: "https://a<b.com/"))
        XCTAssertNil(MarkdownPreviewContent.linkURL(for: ""))
        // 边界（如实登记）：**空格与非 ASCII 不是"解析不出来"** —— `URL(string:)` 自己给它们
        // 百分号编码（实测 `"…/a b"` → `"…/a%20b"`）⇒ 这类目标照画成链接，
        // 只是交回入口时是**编码形态**（下一条往返用例钉着这一点）。
        XCTAssertEqual(
            MarkdownPreviewContent.linkURL(for: "https://example.com/a b")?.absoluteString,
            "https://example.com/a%20b"
        )
        // 相对路径照画（能不能加载由浏览器那条入口判）
        XCTAssertNotNil(MarkdownPreviewContent.linkURL(for: "docs/x.md"))
    }

    /// **交回浏览器那条入口的目标文本**：绝对地址与相对路径都必须**原样往返**
    /// （链接属性只装得下 `URL`，中间那一次还原不许改写目标）。
    func testLinkTargetRoundTripsIntoTheBrowserEntry() throws {
        for target in ["https://example.com/a?b=1", "docs/x.md", "file:///tmp/a.html"] {
            let url = try XCTUnwrap(MarkdownPreviewContent.linkURL(for: target))
            XCTAssertEqual(MarkdownPreviewContent.linkTarget(for: url), target)
        }
        // **边界（如实登记）**：需要编码的目标（空格 / 非 ASCII）交回时是**编码形态** ——
        // 那是 `URL(string:)` 做的事，本层不自己编解码（浏览器那条入口两种形态都认）。
        let spaced = try XCTUnwrap(MarkdownPreviewContent.linkURL(for: "https://example.com/a b"))
        XCTAssertEqual(MarkdownPreviewContent.linkTarget(for: spaced), "https://example.com/a%20b")
    }

    /// **源码判据（点击不弹系统浏览器）**：预览必须**自己接管** `openURL`，并且**代码里
    /// 不许出现系统默认动作** —— 没接线也得丢弃（契约明写「默认在已内嵌的浏览器页签里打开，
    /// 不弹系统浏览器」）。
    ///
    /// 为什么用源码判据：`OpenURLAction.Result` **不是 `Equatable`**，运行期没法比较
    /// 「回的是哪一支」；而"有没有接管"这件事在源码上是**确定的**（少写这一句 = 系统拿默认浏览器打开）。
    /// **剥注释后再判**：契约那句话本身就要写出这个标识符 —— 判的是代码，不是散文。
    func testPreviewTakesOverOpenURLActionAndNeverFallsBackToTheSystem() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("App/Views/MarkdownPreviewView.swift"), encoding: .utf8
        )
        // 空跑防护：扫的那一份必须在位、形状对得上
        XCTAssertTrue(source.contains("struct MarkdownPreviewView"), "渲染侧源文件的形状对不上")
        XCTAssertTrue(source.contains(".environment(\\.openURL,"), "预览没有接管 openURL ⇒ 点击会落到系统默认浏览器")

        let code = strippingComments(source)
        XCTAssertFalse(code.contains("systemAction"), "代码里出现系统默认动作 ⇒ 没接线时会退回系统浏览器")
        XCTAssertTrue(code.contains("openLink("), "接管了却没有交给宿主那个入口 —— 点击等于没地方去")
        XCTAssertTrue(code.contains(".discarded"), "没接线时的处置必须是「明确丢弃」，不是系统默认动作")
        // 对照：同一套扫法在一个**不接管**的视图上必须扫不到（证明这条判据不是恒真）
        let control = try String(
            contentsOf: root.appendingPathComponent("App/Views/WorkspaceTabStrip.swift"), encoding: .utf8
        )
        XCTAssertFalse(control.contains(".environment(\\.openURL,"))
    }

    /// 剥掉注释（块注释整体去掉、行注释从 `//` 起去掉）；双引号里的 `//`（`"https://…"`）不算注释 ——
    /// 只做这一档朴素判断，够这个渲染侧源文件用。
    private func strippingComments(_ source: String) -> String {
        var out = ""
        var inBlock = false
        var inString = false
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            if inBlock {
                if character == "*", next < source.endIndex, source[next] == "/" {
                    inBlock = false
                    index = source.index(after: next)
                    continue
                }
                index = next
                continue
            }
            if inString {
                out.append(character)
                if character == "\"" { inString = false }
                index = next
                continue
            }
            if character == "\"" {
                inString = true
                out.append(character)
                index = next
                continue
            }
            if character == "/", next < source.endIndex, source[next] == "/" {
                while index < source.endIndex, source[index] != "\n" { index = source.index(after: index) }
                continue
            }
            if character == "/", next < source.endIndex, source[next] == "*" {
                inBlock = true
                index = source.index(after: next)
                continue
            }
            out.append(character)
            index = next
        }
        return out
    }

    /// 取 `AttributedString` 里带链接属性的那几段（文字 → 目标）。
    private func links(in attributed: AttributedString) -> [String: String] {
        var found: [String: String] = [:]
        for run in attributed.runs {
            guard let link = run.attributes.link else { continue }
            found[String(attributed[run.range].characters)] = link.absoluteString
        }
        return found
    }
}

/// 对照用：把**真的可编辑** `NSTextView` 插进 SwiftUI 树里（判据的"能判红"那一半）。
private struct EditableProbeRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        textView.isEditable = true
        textView.string = "对照"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
