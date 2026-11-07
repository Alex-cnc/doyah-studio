import Combine
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **思考区流式上屏的四条判据**（详设 §3.33.2 ① / ③ / ④ 的纯函数与状态层部分）。
///
/// ## 由头（人类主人 2026-11-07 真机 beta1.0.4）
///
/// > 「思考过程中，流式输出让滚动条很闪，不像 hermes 的输出这么丝滑」
///
/// 根因是**上屏频率**：一条 token 级回调就改一次 `@Published state` ⇒ SwiftUI 重算一帧
/// ⇒ 思考区 `ScrollView` 内容尺寸变一次、指示器按新尺寸重算一次。
///
/// ## 判据（每条都带反例读数，反例证明判据有牙齿）
///
/// ① **合并率**：200 条增量（每条间隔 2ms）⇒ 上屏 **≤ 1/3**（实测 9 次 = 4.5%）；
///    关节流（`interval = 0`）⇒ **200 次** ⇒ 同一套判据判红；
/// ③ **跟随只在贴底态**（`AgentScrollFollow`）：`distanceToBottom > 容差` ⇒ `shouldFollow == false`；
/// ④ **两档高度**：`AgentThinkingViewport.height(expanded:)` 只返回 200 / 20，没有中间值。
final class AgentThinkingStreamTests: XCTestCase {

    /// 端点最密的一档：token 间隔 2ms（500 增量/秒）。
    private static let deltaInterval: TimeInterval = 0.002
    private static let deltaCount = 200

    private static func piece(_ index: Int) -> AgentLoopEvent {
        .reasoningDelta("想\(index)；")
    }

    // MARK: - ① 合并率（纯 Core）

    /// 判据本体：**上屏次数 ≤ 增量条数的 1/3**。
    private func coalescingViolations(ingested: Int, flushes: Int) -> [String] {
        guard ingested > 0 else { return ["一条增量都没进来 ⇒ 判据没量到东西"] }
        let limit = ingested / 3
        guard flushes > limit else { return [] }
        return ["上屏 \(flushes) 次 / 增量 \(ingested) 条（\(ratio(flushes, ingested))）> 上限 \(limit) 次 ⇒ 没有合并"]
    }

    private func ratio(_ flushes: Int, _ ingested: Int) -> String {
        String(format: "%.1f%%", Double(flushes) / Double(ingested) * 100)
    }

    func testCoalescerBatchesTwoHundredDeltas() {
        var coalescer = AgentStreamCoalescer()
        var batchSizes: [Int] = []
        for index in 0..<Self.deltaCount {
            let now = Double(index) * Self.deltaInterval
            if let batch = coalescer.ingest(Self.piece(index), at: now) {
                batchSizes.append(batch.count)
            }
        }
        // 收尾强刷（轮结束 / 结构边界都会走到它）：最后半句不许留在 buffer 里。
        let tail = coalescer.takeAll(at: Double(Self.deltaCount) * Self.deltaInterval)
        let trailing = tail?.count ?? 0
        let flushes = coalescer.flushCount
        let total = batchSizes.reduce(0, +) + trailing

        print("🧪 ① 合并：增量 \(coalescer.ingestedCount) 条（间隔 2ms）⇒ 上屏 \(flushes) 次"
              + "（\(ratio(flushes, coalescer.ingestedCount))），每批 \(batchSizes) + 尾批 \(trailing)")
        XCTAssertEqual(coalescer.ingestedCount, Self.deltaCount, "夹具没把 200 条都喂进去")
        XCTAssertEqual(total, Self.deltaCount, "有增量没上屏（批次条数加起来 \(total) ≠ 200）⇒ 丢字")
        XCTAssertTrue(coalescingViolations(ingested: coalescer.ingestedCount, flushes: flushes).isEmpty,
                      coalescingViolations(ingested: coalescer.ingestedCount, flushes: flushes).joined())
        XCTAssertGreaterThanOrEqual(flushes, 2, "上屏 \(flushes) 次 ⇒ 只上了头一条，后面的字一直憋着")

        // 反例：**关节流**（`interval = 0` = 改前形态，一条增量一次上屏）⇒ 同一套判据必须报红。
        var unthrottled = AgentStreamCoalescer(interval: 0)
        for index in 0..<Self.deltaCount {
            _ = unthrottled.ingest(Self.piece(index), at: Double(index) * Self.deltaInterval)
        }
        let red = coalescingViolations(ingested: unthrottled.ingestedCount, flushes: unthrottled.flushCount)
        print("🧪 反例①（关节流）：上屏 \(unthrottled.flushCount) 次 / 增量 \(unthrottled.ingestedCount) 条 ⇒ "
              + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red.isEmpty, "关节流（\(unthrottled.flushCount) 次上屏）判据仍然绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ① 真状态层：`@Published` 只发「窗口」那么多次

    /// 走**生产路径**（`AgentChatModel.observe`）量「SwiftUI 会重算几帧」：
    /// 每次 `state` 变更发一次 `objectWillChange`，那就是一帧。
    @MainActor
    func testModelPublishesOncePerWindowNotPerDelta() async {
        let model = AgentChatModel(sessionID: "thinking-stream-probe")
        var virtualNow: TimeInterval = 0
        model.streamClock = { virtualNow }
        var publishes = 0
        let token = model.objectWillChange.sink { publishes += 1 }
        defer { token.cancel() }

        for index in 0..<Self.deltaCount {
            virtualNow = Double(index) * Self.deltaInterval
            await model.observe(Self.piece(index))
        }
        let beforeFlush = publishes
        // 结构边界（工具开跑）⇒ 强刷最后一批。
        await model.observe(.toolStarted(name: "read_file", summary: "Core/AgentChat.swift"))
        let afterFlush = publishes

        let text = model.state.messages.first(where: { $0.role == .assistant })?.thinking ?? ""
        print("🧪 ① 真状态层：200 条增量 ⇒ `@Published` 发 \(beforeFlush) 次（结构边界强刷后 \(afterFlush) 次）"
              + " / 上屏 \(model.streamFlushCount) 次 / 拼出 \(text.count) 字")

        XCTAssertEqual(model.streamIngestedCount, Self.deltaCount)
        let expectedText = (0..<Self.deltaCount).map { "想\($0)；" }.joined()
        XCTAssertEqual(text.count, expectedText.count,
                       "思考段没拼全（\(text.count) 字 ≠ \(expectedText.count) 字）⇒ 合并丢了字")
        XCTAssertEqual(text, expectedText, "合并后的字与逐条追加**不是同一份**（顺序 / 内容变了）")
        XCTAssertTrue(text.hasPrefix("想0；"), "顺序错了：开头是「\(text.prefix(6))」")
        XCTAssertLessThanOrEqual(beforeFlush, Self.deltaCount / 3,
                                 "200 条增量发了 \(beforeFlush) 次变更 ⇒ 一 token 一帧（没有合并）")
        // 一次批 = 一次状态变更：增量那条路上变更次数不许比上屏次数多（多了说明批里又逐条改了）。
        // 结构边界（`.toolStarted`）自己另发一次 —— 那是它自己的变更，不算在增量头上。
        XCTAssertEqual(afterFlush, model.streamFlushCount + 1,
                       "状态变更 \(afterFlush) 次 ≠ 上屏 \(model.streamFlushCount) 次 + 结构事件 1 次"
                       + " ⇒ 一批里逐条上屏了")
    }

    /// 两条通道（思考段 / 正文）各自合并，**字一个不少**。
    @MainActor
    func testBothChannelsSurviveCoalescing() async {
        let model = AgentChatModel(sessionID: "thinking-stream-channels")
        var virtualNow: TimeInterval = 0
        model.streamClock = { virtualNow }

        for index in 0..<60 {
            virtualNow = Double(index) * Self.deltaInterval
            await model.observe(.reasoningDelta("思\(index)"))
        }
        for index in 0..<60 {
            virtualNow = Double(60 + index) * Self.deltaInterval
            await model.observe(.delta("答\(index)"))
        }
        await model.observe(.toolFinished(name: "read_file", outcome: "executed", millis: 12))

        let message = model.state.messages.first(where: { $0.role == .assistant })
        let thinking = message?.thinking ?? ""
        let body = message?.text ?? ""
        print("🧪 ① 双通道：思考段 \(thinking.count) 字 / 正文 \(body.count) 字 / 上屏 \(model.streamFlushCount) 次")
        XCTAssertEqual(thinking, (0..<60).map { "思\($0)" }.joined(),
                       "思考段被合并吃掉或串了：\(thinking.prefix(20))…")
        XCTAssertEqual(body, (0..<60).map { "答\($0)" }.joined(),
                       "正文被合并吃掉或串了：\(body.prefix(20))…")
    }

    /// **结构边界强刷**：过程行到场前把积压的字先上屏 —— 否则过程行跑到正文前面。
    @MainActor
    func testStructuralEventFlushesBeforeItApplies() async {
        let model = AgentChatModel(sessionID: "thinking-stream-order")
        var virtualNow: TimeInterval = 0
        model.streamClock = { virtualNow }
        await model.observe(.hopStarted(index: 0))

        for index in 0..<20 {
            virtualNow = Double(index) * Self.deltaInterval
            await model.observe(.delta("字\(index)"))
        }
        await model.observe(.toolStarted(name: "read_file", summary: "Core/AgentChat.swift"))

        let roles = model.state.messages.map(\.role)
        let body = model.state.messages.first(where: { $0.role == .assistant })?.text ?? ""
        print("🧪 ① 顺序：消息角色 \(roles) / 正文 \(body.count) 字")
        XCTAssertEqual(body, (0..<20).map { "字\($0)" }.joined(),
                       "结构事件之前没强刷 ⇒ 正文只有 \(body.count) 字")
        XCTAssertEqual(roles.last, .tool, "过程行没落在正文之后：\(roles)")
    }

    // MARK: - ③ 条件跟随（纯函数）

    func testFollowOnlyWhilePinnedToBottom() {
        var follow = AgentScrollFollow()
        XCTAssertTrue(follow.shouldFollow, "初值必须是「贴底」—— 第一次出内容要能跟上")

        follow.update(distanceToBottom: 0)
        XCTAssertTrue(follow.shouldFollow, "贴着底却不跟")
        follow.update(distanceToBottom: AgentScrollFollow.bottomTolerance)
        XCTAssertTrue(follow.shouldFollow, "容差之内算贴底")

        // 用户往上滚 120pt ⇒ 停手（内容再涨也不跟）。
        follow.update(distanceToBottom: 120)
        XCTAssertFalse(follow.shouldFollow, "用户往上翻了还在跟 ⇒ 抢控制权")
        print("🧪 ③ 跟随：贴底（0pt）跟 / 容差（4pt）跟 / 上翻（120pt）不跟")

        // 滚回底部 ⇒ 恢复跟随。
        follow.update(distanceToBottom: 0.5)
        XCTAssertTrue(follow.shouldFollow, "回到贴底没恢复跟随")

        // 距底换算：内容 1000 / 视口 178，偏移 822 ⇒ 贴底；偏移 800 ⇒ 距底 22。
        let atBottom = AgentScrollFollow.distanceToBottom(contentHeight: 1000, viewportHeight: 178,
                                                          offsetFromTop: 822)
        let scrolledUp = AgentScrollFollow.distanceToBottom(contentHeight: 1000, viewportHeight: 178,
                                                            offsetFromTop: 800)
        print("🧪 ③ 距底换算：偏移 822 ⇒ \(atBottom)pt / 偏移 800 ⇒ \(scrolledUp)pt")
        XCTAssertEqual(atBottom, 0, accuracy: 0.01)
        XCTAssertEqual(scrolledUp, 22, accuracy: 0.01)
    }

    // MARK: - ③b 贴底判定：分得清「人上翻」与「内容长高」（§3.33.3 契约②/③）

    /// 由头（人类主人 2026-11-07 真机 beta1.0.6）：
    /// > 「每 Step 里的思考过程是可以滚动，但整个界面却不滚动了，要手工去拖动」
    ///
    /// 旧判定只看「距底多少」：**内容长高**与**人往上滚**都表现为「距底变大」，
    /// 于是「贴底 + 新内容刚到、还没跟」这一瞬被判成「人上翻」⇒ 跟随当场断掉。
    /// 新口径看**偏移的变化方向**：内容长高 / 视口变矮时偏移不动 ⇒ 保持跟。
    func testFollowSeparatesContentGrowthFromUserScroll() {
        var follow = AgentScrollFollow()
        let viewport: CGFloat = 400

        // ① 贴底起步：内容 1000 ⇒ 最大偏移 600、距底 0。
        follow.update(contentHeight: 1000, viewportHeight: viewport, offsetFromTop: 600)
        XCTAssertTrue(follow.shouldFollow)

        // ② **内容长高 200pt**（偏移一动不动）⇒ 距底 200，但这不是人翻的 ⇒ 仍跟。
        follow.update(contentHeight: 1200, viewportHeight: viewport, offsetFromTop: 600)
        XCTAssertTrue(follow.shouldFollow,
                      "内容长高 200pt 就被判成「人上翻」⇒ 流式一跟就停（beta1.0.6 的现象）")

        // ③ **吸顶条出现**（视口矮 20pt）：内容高与偏移都不变 ⇒ 仍跟。
        follow.update(contentHeight: 1200, viewportHeight: 380, offsetFromTop: 600)
        XCTAssertTrue(follow.shouldFollow, "视口变矮 20pt 就被判成「人上翻」⇒ 条一出现跟随就断")

        // ④ 人真的往上滚 100pt ⇒ 停跟。
        follow.update(contentHeight: 1200, viewportHeight: 380, offsetFromTop: 500)
        XCTAssertFalse(follow.shouldFollow, "偏移小了 100pt 还跟 ⇒ 抢用户控制权")

        // ⑤ 停跟之后内容再长 ⇒ 保持停跟（不回弹）。
        follow.update(contentHeight: 1600, viewportHeight: 380, offsetFromTop: 500)
        XCTAssertFalse(follow.shouldFollow, "用户上翻之后内容一长又被拽回底部")

        // ⑥ 人往上滚的时候偏移反向变大（往下滚回）但还没到底 ⇒ 仍停跟。
        follow.update(contentHeight: 1600, viewportHeight: 380, offsetFromTop: 700)
        XCTAssertFalse(follow.shouldFollow, "只是往下滚了一段（距底 520）就恢复跟随")

        // ⑦ 滚回距底 3pt（容差内）⇒ 恢复跟随。
        follow.update(contentHeight: 1600, viewportHeight: 380, offsetFromTop: 1217)
        XCTAssertTrue(follow.shouldFollow, "回到容差内没恢复跟随")

        // ⑧ 整像素抖动（< 0.5pt）不算人上翻。
        var jitter = AgentScrollFollow()
        jitter.update(contentHeight: 1000, viewportHeight: viewport, offsetFromTop: 600)
        jitter.update(contentHeight: 1000, viewportHeight: viewport, offsetFromTop: 599.8)
        XCTAssertTrue(jitter.shouldFollow, "0.2pt 的舍入抖动被判成「人上翻」")

        print("🧪 ③b 贴底状态机：内容长高(200pt) 跟 / 视口变矮(20pt) 跟 / 上翻(100pt) 不跟"
              + " / 上翻后长高 不跟 / 回底(3pt) 跟 / 抖动(0.2pt) 跟")

        // **反例读数**：同一串读数喂给「只看距底」的旧口径 ⇒ 第 ② 步就判红（不再跟）。
        var legacy = AgentScrollFollow()
        for (content, viewportHeight, offset) in [(CGFloat(1000), viewport, CGFloat(600)),
                                                  (1200, viewport, 600)] {
            legacy.update(distanceToBottom: AgentScrollFollow.distanceToBottom(contentHeight: content,
                                                                              viewportHeight: viewportHeight,
                                                                              offsetFromTop: offset))
        }
        print("🧪 反例③b（旧口径只看距底）：内容长高 200pt 后 shouldFollow = \(legacy.shouldFollow)"
              + (legacy.shouldFollow ? " ⇒ 假绿 ❌" : " ⇒ 判红 ✅（正是 beta1.0.6 断跟的机制）"))
        XCTAssertFalse(legacy.shouldFollow, "旧口径在同一串读数上也判「跟」⇒ 新判据没有牙齿")
    }

    // MARK: - ④ 两档高度（没有中间值）

    func testTriStateHeightsAreOnlyTwoValues() {
        let running = AgentThinkingViewport.height(expanded: true)
        let collapsed = AgentThinkingViewport.height(expanded: false)
        print("🧪 ④ 两档高度：展开 \(running)pt / 折叠 \(collapsed)pt / 视口 \(AgentThinkingViewport.viewportHeight)pt")
        XCTAssertEqual(running, 200, accuracy: 0.001, "展开态整块不是 200pt")
        XCTAssertEqual(collapsed, 20, accuracy: 0.001, "折叠态不是一行 20pt")
        XCTAssertEqual(AgentThinkingViewport.viewportHeight, 178, accuracy: 0.001,
                       "视口不是 178pt（200 − 抬头 20 − 发丝 2）")
        // 视图侧常量与 Core 常量必须是**同一个数**（两处各写一份就会漂）。
        XCTAssertEqual(AgentThinkingZone.expandedMaxHeight, running, accuracy: 0.001)
        XCTAssertEqual(AgentThinkingZone.collapsedHeight, collapsed, accuracy: 0.001)
        XCTAssertEqual(AgentThinkingZone.contentMaxHeight, AgentThinkingViewport.viewportHeight,
                       accuracy: 0.001)
    }
}
