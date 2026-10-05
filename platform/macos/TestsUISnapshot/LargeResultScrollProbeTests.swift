import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 大结果集滚动的 **App 侧探针**（队列 `L-89` ㈡ ④ · 清单 §4 `FR-RES-07`）—— 第 97 轮。
///
/// ## 这一行原来为什么"只能人点"
/// 清单原文：「查 1 万行 × 20 列，上下滚十几秒 ⇒ 不卡（掉帧可感知但不"卡死"）；内存不飙」，
/// 状态格写着「需人工（属 `NFR-PERF-02` 同一阻塞）」。其中**能变成机器判据的那部分**：
///   · 「不卡死」→ 单帧成本有来源上界；滚动时**每一帧的画面都真的在变**
///     （位置变了而画面没变 = 卡死的机器形态）；
///   · 「结果变大不会更慢」→ 同一屏的帧成本在 1 万行与 10 万行结果上必须**同量级**
///     （比值判据，机器无关：不写死毫秒，只要求"别随总行数放大"）；
///   · 「内存不飙」→ **同一轮操作重复做不再增长**（第一遍之后取基线，再看后几遍的增量）；
///   · 「虚拟化」→ 物化出来的行视图数只跟可见区域有关，与总行数无关。
///
/// ## 阈值从哪来（纪律：容差必须有来源）
/// 全部读 `Scripts/result-scroll-baseline.json`（本机实测基线 + 倍数 + 理由），本文件不写魔数；
/// 那份台账由 `Scripts/check-result-scroll-ledger.py` 看着（字段齐备 / 基线是正数 /
/// 上限对基线至少有 3 倍余量 / 理由非空 / 探针真的挂在取证脚本上）。
///
/// ## 边界（如实登记）
/// · 证得住：单帧成本有界、帧在变、重复操作不涨内存、物化行视图不随总行数增长；
///   **证不住**「观感顺不顺」（掉帧可不可感知是人的判断），也不含**上屏合成**路径 ——
///   这里是离屏 `cacheDisplay`，走同一套绘制代码但不上屏；真机 GPU 合成仍归人工点验；
/// · **不连任何数据库**：数据是本文件造的合成结果（1 万 / 10 万行 × 20 列）；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与快照同一条纪律：取证才跑，每轮门禁不跑。
final class LargeResultScrollProbeTests: XCTestCase {

    // MARK: - 阈值台账（唯一来源）

    private struct Ledger: Decodable {
        struct Frame: Decodable {
            let floorMs: Double
            let p50MsLimit: Double
            let rasterMsLimit: Double
            let scaleRatioLimit: Double
        }
        struct Memory: Decodable {
            let residentLimitMB: Double
        }
        let smallRows: Int
        let largeRows: Int
        let columns: Int
        let scrollSteps: Int
        let frame: Frame
        let memory: Memory
    }

    private func ledger() throws -> Ledger {
        // 仓根由 `#filePath` 往上两级得到（`TestsUISnapshot/x.swift` → 仓根）：
        // 不依赖工作目录 —— `swift test` 与 `run-manual-verification-probes.sh` 的 cwd 不是同一处。
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Scripts/result-scroll-baseline.json"))
        return try JSONDecoder().decode(Ledger.self, from: data)
    }

    private func skipUnlessProbeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("大结果集滚动探针要真渲染 AppKit 表格：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）")
        }
    }

    // MARK: - 合成结果（20 列 × N 行）

    /// 造 N 行 × 20 列的合成结果。
    ///
    /// 取值刻意**短**（≤ 15 字节 ⇒ Swift 小字符串内联、几乎不占堆），只在最后一列放长一点的值：
    /// 这样「物化行视图 / 单帧成本」这两个判据量的是**绘制**，而不是被数据的堆分配淹掉量纲。
    private func makeResult(rows: Int, columns: Int) -> QueryResult {
        let metas: [ColumnMeta] = (0..<columns).map { index in
            ColumnMeta(id: index, name: index == 0 ? "id" : "c\(index)", typeName: index <= 1 ? "int8" : "text")
        }
        let body: [[String?]] = (0..<rows).map { row in
            (0..<columns).map { column -> String? in
                switch column {
                case 0: return String(row)
                case 1: return row % 7 == 0 ? nil : String(row % 1_000)
                case columns - 1: return row % 11 == 0 ? nil : "row \(row) / cell \(column)"
                default: return "r\(row % 1_000)c\(column)"
                }
            }
        }
        return QueryResult(columns: metas, rows: body, executionTime: 0.02)
    }

    // MARK: - 离屏宿主

    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<ResultGrid>
        let scroll: NSScrollView
        let table: NSTableView

        func tearDown() {
            window.contentView = nil
        }
    }

    /// 把**真** `ResultGrid` 挂进**离屏**窗口（不上屏：无人值守的机器不该闪一下）。
    ///
    /// 与快照同一条路（`UISnapshotKit.windowHostedImage`）：AppKit 自绘容器要有真窗口才会 tile，
    /// 没有窗口的宿主里 `cacheDisplay` 拿回来的是整幅背景（第 10 轮实测）。
    @MainActor
    private func mount(rows: [[String?]], result: QueryResult, size: CGSize) throws -> Host {
        let hosting = NSHostingView(rootView: ResultGrid(result: result, displayedRows: rows))
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let scroll = try XCTUnwrap(Self.firstScrollView(in: hosting), "离屏宿主里没有 NSScrollView —— 挂载路径坏了")
        let table = try XCTUnwrap(scroll.documentView as? NSTableView, "滚动视图的 documentView 不是 NSTableView")
        return Host(window: window, hosting: hosting, scroll: scroll, table: table)
    }

    @MainActor
    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }

    /// 物化出来的行视图数（`makeIfNecessary: false` ⇒ 只数**已经建出来**的，不催生新的）。
    ///
    /// 这是「虚拟化」的机器形态：`NSTableView` 复用行视图，物化数应当只跟**可见区域**有关。
    /// 100 万行的表如果把每一行都建出来，这个数会等于总行数 —— 内存与首帧都会炸。
    @MainActor
    private func materializedRowViews(_ table: NSTableView) -> Int {
        var count = 0
        for row in 0..<table.numberOfRows where table.rowView(atRow: row, makeIfNecessary: false) != nil {
            count += 1
        }
        return count
    }

    // MARK: - 一帧怎么量

    /// 渲染一帧（把当前滚动位置画进位图）并计时，同时给出**画面指纹**。
    ///
    /// 为什么用 `cacheDisplay` 而不是"上屏滚十几秒"：这是**同一套绘制代码**的离屏路径，
    /// 无人值守也能跑。代价是它不算 GPU 合成 —— 边界已写进文件头，不假装判住了上屏观感。
    @MainActor
    private func renderFrame(_ host: Host, offset: CGFloat, size: CGSize) throws
        -> (frameMs: Double, rasterMs: Double, digest: UInt64) {
        host.scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
        host.scroll.reflectScrolledClipView(host.scroll.contentView)
        host.hosting.layoutSubtreeIfNeeded()

        // 一帧 = 滚动之后**真正要重画的那一块**（`displayIfNeeded` 只画脏区，真机滚动也是这条路）。
        let started = CFAbsoluteTimeGetCurrent()
        host.hosting.displayIfNeeded()
        let frameMs = (CFAbsoluteTimeGetCurrent() - started) * 1_000

        // 整幅光栅化单独量、**不计进帧成本**：`cacheDisplay` 每次都重画整幅，比一帧贵一个量级，
        // 拿它当帧成本等于判据自带噪声。它的用途只有两个：画面指纹（判"位置动了画面没动"）
        // 与「整幅重画的上界」（拦数量级退化）。
        let rep = try XCTUnwrap(Self.bitmap(size: size), "位图分配失败")
        let rasterStarted = CFAbsoluteTimeGetCurrent()
        host.hosting.cacheDisplay(in: host.hosting.bounds, to: rep)
        let rasterMs = (CFAbsoluteTimeGetCurrent() - rasterStarted) * 1_000
        return (frameMs, rasterMs, Self.digest(of: rep))
    }

    /// 位图按 scale=1 建：量的是绘制成本，不是像素吞吐（像素断言由快照那一族承担）。
    private static func bitmap(size: CGSize) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width.rounded()),
            pixelsHigh: Int(size.height.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    }

    /// 画面指纹：按**跨步采样**把 RGB 累加成 64 位值（FNV-1a）。
    ///
    /// 为什么跨步而不是全量：这张图 900×420 有 150 万字节，每一步都全量累加会让**探针自己**的
    /// 开销盖过被判的绘制开销 —— 判据不能自带噪声。
    private static func digest(of rep: NSBitmapImageRep) -> UInt64 {
        guard let base = rep.bitmapData else { return 0 }
        let bytesPerRow = rep.bytesPerRow
        var hash: UInt64 = 1_469_598_103_934_665_603
        var y = 0
        while y < rep.pixelsHigh {
            var x = 0
            while x < rep.pixelsWide {
                let index = y * bytesPerRow + x * 4
                for channel in 0..<3 {
                    hash = (hash ^ UInt64(base[index + channel])) &* 1_099_511_628_211
                }
                x += 7
            }
            y += 7
        }
        return hash
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// 常驻内存（MB）。`task_info` 的 `resident_size` —— 与本机 `ps`/活动监视器同一族口径。
    private func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard status == KERN_SUCCESS else { return .nan }
        return Double(info.resident_size) / (1024 * 1024)
    }

    // MARK: - 判据 ①：虚拟化 —— 物化行视图不随总行数增长

    @MainActor
    func testMaterializedRowViewsFollowVisibleAreaNotTotalRows() throws {
        try skipUnlessProbeEnabled()
        let ledger = try ledger()
        let size = CGSize(width: 900, height: 420)

        var materialized: [Int: Int] = [:]
        var visible: [Int: Int] = [:]
        for rows in [ledger.smallRows, ledger.largeRows] {
            let result = makeResult(rows: rows, columns: ledger.columns)
            let host = try mount(rows: result.rows, result: result, size: size)
            defer { host.tearDown() }

            visible[rows] = host.table.rows(in: host.table.visibleRect).length
            materialized[rows] = materializedRowViews(host.table)
            print(
                "📊 \(rows) 行 × \(ledger.columns) 列：物化行视图 \(materialized[rows]!) 个"
                    + " / 可见 \(visible[rows]!) 行 / 表格总行数 \(host.table.numberOfRows)"
            )
        }

        let smallMaterialized = try XCTUnwrap(materialized[ledger.smallRows])
        let largeMaterialized = try XCTUnwrap(materialized[ledger.largeRows])
        let visibleRows = try XCTUnwrap(visible[ledger.smallRows])

        XCTAssertGreaterThan(visibleRows, 0, "可见行数是 0 ⇒ 离屏宿主没布局，后面的判据会变成空跑（假绿）")
        XCTAssertLessThanOrEqual(
            smallMaterialized, visibleRows + 2,
            "\(ledger.smallRows) 行时物化了 \(smallMaterialized) 个行视图，可见只有 \(visibleRows) 行 ⇒ 不是复用而是全建"
        )
        XCTAssertLessThanOrEqual(
            abs(largeMaterialized - smallMaterialized), 2,
            "总行数 \(ledger.smallRows) → \(ledger.largeRows)：物化行视图 \(smallMaterialized) → \(largeMaterialized)"
                + " ⇒ 绘制路径与总行数有关（虚拟化被破坏）"
        )
    }

    // MARK: - 判据 ②：滚动每一帧画面都在变 + 单帧成本有来源上界

    @MainActor
    func testScrollFramesKeepChangingAndStayWithinLedgerCost() throws {
        try skipUnlessProbeEnabled()
        let ledger = try ledger()
        let size = CGSize(width: 900, height: 420)
        let result = makeResult(rows: ledger.smallRows, columns: ledger.columns)
        let host = try mount(rows: result.rows, result: result, size: size)
        defer { host.tearDown() }

        // 从表头滚到接近底部。乘 0.98 是**故意不滚到最底**：到底那一帧的可见行更少，
        // 拿它当常态会把"边界态更便宜"误当成判据通过。
        let span = max(host.table.frame.height - size.height, 0)
        var digests: [UInt64] = []
        var times: [Double] = []
        var rasters: [Double] = []
        for step in 0..<ledger.scrollSteps {
            let fraction = CGFloat(step) / CGFloat(max(ledger.scrollSteps - 1, 1))
            let frame = try renderFrame(host, offset: span * fraction * 0.98, size: size)
            digests.append(frame.digest)
            times.append(frame.frameMs)
            rasters.append(frame.rasterMs)
        }

        let changed = zip(digests, digests.dropFirst()).filter { $0 != $1 }.count
        XCTAssertEqual(
            changed, digests.count - 1,
            "\(digests.count) 帧里有 \(digests.count - 1 - changed) 对相邻帧画面逐字节相同 ⇒ 位置动了、画面没动（卡死）"
        )
        XCTAssertNotEqual(digests.first, digests.last, "滚到底与开头是同一幅画面 ⇒ 内容根本没动")

        let p50 = median(times)
        let rasterP50 = median(rasters)
        print(
            String(
                format: "⏱️ %d 行 × %d 列：帧（脏区重画）p50 %.2f ms（最大 %.2f ms）/ 上界 %.2f ms；整幅重画 p50 %.1f ms / 上界 %.1f ms",
                ledger.smallRows, ledger.columns, p50, times.max() ?? 0, ledger.frame.p50MsLimit,
                rasterP50, ledger.frame.rasterMsLimit
            )
        )
        XCTAssertGreaterThan(p50, 0, "帧成本量成了 0 ⇒ 滚动根本没触发重画，这条判据成了空跑（假绿）")
        XCTAssertLessThanOrEqual(
            p50, ledger.frame.p50MsLimit,
            "单帧 p50 \(p50) ms 超过台账上界 \(ledger.frame.p50MsLimit) ms（来源 Scripts/result-scroll-baseline.json）"
        )
        XCTAssertLessThanOrEqual(
            rasterP50, ledger.frame.rasterMsLimit,
            "整幅重画 p50 \(rasterP50) ms 超过台账上界 \(ledger.frame.rasterMsLimit) ms"
        )
    }

    // MARK: - 判据 ③：单帧成本不随总行数放大（比值判据，机器无关）

    @MainActor
    private func p50FrameMs(rows: Int, columns: Int, steps: Int, size: CGSize) throws -> (frame: Double, raster: Double) {
        let result = makeResult(rows: rows, columns: columns)
        let host = try mount(rows: result.rows, result: result, size: size)
        defer { host.tearDown() }

        let span = max(host.table.frame.height - size.height, 0)
        var frames: [Double] = []
        var rasters: [Double] = []
        for step in 0..<steps {
            let fraction = CGFloat(step) / CGFloat(max(steps - 1, 1))
            let frame = try renderFrame(host, offset: span * fraction * 0.98, size: size)
            frames.append(frame.frameMs)
            rasters.append(frame.rasterMs)
        }
        return (median(frames), median(rasters))
    }

    @MainActor
    func testFrameCostDoesNotScaleWithTotalRows() throws {
        try skipUnlessProbeEnabled()
        let ledger = try ledger()
        let size = CGSize(width: 900, height: 420)

        // 先各跑两帧预热：首次接触的字体 / 复用池分配都算在预热身上，不进判据。
        _ = try p50FrameMs(rows: ledger.smallRows, columns: ledger.columns, steps: 2, size: size)
        _ = try p50FrameMs(rows: ledger.largeRows, columns: ledger.columns, steps: 2, size: size)

        let small = try p50FrameMs(rows: ledger.smallRows, columns: ledger.columns, steps: ledger.scrollSteps, size: size)
        let large = try p50FrameMs(rows: ledger.largeRows, columns: ledger.columns, steps: ledger.scrollSteps, size: size)

        // 分母兜底：小结果那一档可能快到微秒级，比值会失去意义 ⇒ 用台账里的 `floorMs` 当下限。
        let floor = max(small.raster, ledger.frame.floorMs)
        let limit = ledger.frame.scaleRatioLimit * floor
        print(
            String(
                format: "⚖️ 整幅重画 p50：%d 行 %.1f ms → %d 行 %.1f ms（%.2f×，上限 %.2f ms = %.1f×max(p50, %.1f ms)）；帧（脏区重画）%.2f ms → %.2f ms",
                ledger.smallRows, small.raster, ledger.largeRows, large.raster, large.raster / floor, limit,
                ledger.frame.scaleRatioLimit, ledger.frame.floorMs, small.frame, large.frame
            )
        )
        XCTAssertLessThanOrEqual(
            large.raster, limit,
            "总行数放大 \(ledger.largeRows / max(ledger.smallRows, 1)) 倍后整幅重画 p50 从 \(small.raster) ms 涨到 \(large.raster) ms"
                + "（允许 \(limit) ms）⇒ 绘制路径随总行数放大"
        )
        XCTAssertLessThanOrEqual(
            large.frame, ledger.frame.p50MsLimit,
            "10 万行时帧（脏区重画）p50 \(large.frame) ms 超过台账上界 \(ledger.frame.p50MsLimit) ms"
        )
    }

    // MARK: - 判据 ④：同一轮操作重复做，常驻内存不再增长

    @MainActor
    func testRepeatedPageTurnsAndScrollSweepsDoNotGrowMemory() throws {
        try skipUnlessProbeEnabled()
        let ledger = try ledger()
        let size = CGSize(width: 900, height: 420)
        let result = makeResult(rows: ledger.smallRows, columns: ledger.columns)

        // 分页档 = 每页 100 行 ⇒ 1 万行结果共 100 页，一遍就是"翻完整轮页"。
        let pageSize = 100
        let pageCount = (ledger.smallRows + pageSize - 1) / pageSize
        var state = ResultGridState(pageIndex: 0, pageSize: pageSize)

        func sweepPages() {
            for page in 0..<pageCount {
                state.adopt(pageIndex: page)
                let current = state.page(of: result.rows)
                XCTAssertEqual(current.pageIndex, page, "页号被夹取到别处了")
                XCTAssertEqual(current.rows.count, pageSize, "第 \(page) 页行数不对")
            }
        }

        // 末页在最后一次 adopt 之后 —— 顺手把「总行数 / 页数」这两个显示口径也钉住。
        sweepPages()
        let lastPage = state.page(of: result.rows)
        XCTAssertEqual(lastPage.totalRows, ledger.smallRows)
        XCTAssertEqual(lastPage.pageCount, pageCount)

        // 一轮完整操作 = 翻完一整轮页 + 全表滚一遍。
        //
        // 每轮都包在 `autoreleasepool` 里：主线程上没有运行循环时 autorelease 的对象不出池，
        // 不排池的话量到的是"这一轮做了多少事"而不是"攒下了什么" —— 那会是一条自带噪声的判据
        // （实测：不排池时两轮"增量" 83 MB，排池后同一份代码降到个位数）。
        func oneRound() throws {
            try autoreleasepool {
                sweepPages()
                try scrollSweep(rows: ledger.smallRows, columns: ledger.columns, steps: ledger.scrollSteps, size: size)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        try oneRound()   // 预热（含 AppKit 首次分配与字体 / 复用池）
        let baseline = residentMB()

        try oneRound()
        try oneRound()
        let delta = residentMB() - baseline

        print(
            String(
                format: "🧠 %d 行 × %d 列：翻 %d 页 + 全表滚 %d 帧 各重复 2 遍，常驻内存增量 %.1f MB（上限 %.1f MB）",
                ledger.smallRows, ledger.columns, pageCount, ledger.scrollSteps, delta, ledger.memory.residentLimitMB
            )
        )
        XCTAssertLessThanOrEqual(
            delta, ledger.memory.residentLimitMB,
            "重复同一轮操作后常驻内存涨了 \(delta) MB（上限 \(ledger.memory.residentLimitMB) MB）⇒ 每轮都在攒东西"
        )
    }

    /// 不分页档（整表入表）滚一遍 —— 与"每翻一页都攒一份副本"这一族失败同一条路。
    @MainActor
    private func scrollSweep(rows: Int, columns: Int, steps: Int, size: CGSize) throws {
        let result = makeResult(rows: rows, columns: columns)
        let host = try mount(rows: result.rows, result: result, size: size)
        defer { host.tearDown() }

        let span = max(host.table.frame.height - size.height, 0)
        for step in 0..<steps {
            let fraction = CGFloat(step) / CGFloat(max(steps - 1, 1))
            _ = try renderFrame(host, offset: span * fraction * 0.98, size: size)
        }
    }
}
