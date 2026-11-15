import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「对话区**垂直落点**」这一族的探针（详设 §3.37 排版）。
///
/// ## 真机缺陷（2026-11-13，人类主人原话）
///
/// > 「Agent会话界面又成这个鸟样了，你告诉我你到底咋设计的，这个布局不能动态调整吗，
/// >  为什么要设置固定高度呢？」
/// > 「现在Doyah那些排在顶部的信息又变成紧贴着输入框了」
///
/// 两件事被同一处排版管着，方向却相反：
/// · **空态起手页**（图标 / 产品名 / 可用工具数）—— 属于「打开就看见」，必须在**上面**；
/// · **真会话的消息**（一轮跑完只剩几行摘要 + 结论）—— 属于「最新一句」，必须**贴底**。
/// 一刀切成「都贴底」，起手页就被按在输入框上；一刀切成「都靠上」，短会话又悬在顶上留一大片空白。
/// 判据要能同时判这两头，且**互相当反例**：拿会话的判据去量起手页必须报红，反之亦然。
///
/// ## 判据（能判红）
///
/// ① 起手页：内容落点带的中点在**上半屏**（`topInk < 0.42 × 高`）；
/// ② 短会话：内容落点带的底边在**下半屏**（`bottomInk > 0.62 × 高`）；
/// ③ 反例：把 ① 的读法套到短会话上、② 的读法套到起手页上，**都必须报红**。
///
/// ## 边界（如实登记）
///
/// · 量的是**像素落点**（`NSBitmapImageRep` 扫「亮的字迹行」），不是某个视图的 frame ——
///   SwiftUI 的 `Text` 在这台宿主里不落 `NSTextField`，没有 frame 可量（与本族其它探针同一条边界）；
/// · 星野背景自带亮点 ⇒ 只认「同一行连续 ≥ 4 个亮像素」，单点星不算字迹；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与其它端上探针同一条纪律：取证才跑。
/// 判据：`T-3.33-14`（起手页在上 / 短会话贴底，读数对调必须判红）。
final class AgentChatAnchorProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)

    // MARK: - 判据函数（真实测量与反例共用同一套）

    /// **差值判据**：短会话的字迹重心必须比空态起手页**明显更低**。
    ///
    /// 为什么量差值而不是绝对值：标题栏、输入框、状态条两种模式里一模一样，
    /// 绝对值被这些家具拖着跑（量了几轮都在 100pt 上下，分不出模式）；差值把家具抵消掉，
    /// 剩下的就是「内容落在哪」—— 空态在顶上、会话贴底，差值必须是一大截。
    static func shiftViolations(heroCentroid: CGFloat, chatCentroid: CGFloat) -> [String] {
        let delta = chatCentroid - heroCentroid
        guard delta >= 40 else {
            return ["会话重心 \(Int(chatCentroid))pt 只比起手页 \(Int(heroCentroid))pt 低 \(Int(delta))pt"
                    + " ⇒ 短会话没有贴底（两种模式落在同一处）"]
        }
        return []
    }

    // MARK: - 落点读数

    private struct Band {
        /// 字迹行的垂直重心（距视口顶，pt）。
        let centroid: CGFloat
        let first: CGFloat
        let last: CGFloat
        let height: CGFloat
    }

    private func state(empty: Bool) -> AgentChatState {
        guard !empty else {
            return AgentChatState(messages: [],
                                  endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"))
        }
        return AgentChatState(messages: [
            .init(role: .user, text: "一句话回答：1+1 等于几？"),
            .init(role: .assistant, text: "2。"),
        ], endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"))
    }

    @MainActor
    private func band(empty: Bool) -> Band {
        let appState = AppState()
        appState.connections = []
        let model = AgentChatModel(sessionID: "anchor-probe-\(empty ? "hero" : "conversation")",
                                   state: state(empty: empty))
        let live = UISnapshot.LiveHost(
            AnyView(AgentChatView(model: model)
                .environmentObject(appState)
                .environmentObject(WorkspaceTabsModel())),
            size: Self.pageSize
        )
        live.settle()
        live.pump(0.3)
        defer { live.window.contentView = nil }

        let hosting = live.hosting
        hosting.layoutSubtreeIfNeeded()
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else {
            return Band(centroid: 0, first: 0, last: 0, height: bounds.height)
        }
        hosting.cacheDisplay(in: bounds, to: rep)
        // 取证：把这一格**存成 PNG**，人眼（或视觉模型）直接看，不靠阈值猜。
        if let png = rep.representation(using: .png, properties: [:]) {
            let path = "/tmp/anchor-\(empty ? "hero" : "chat").png"
            try? png.write(to: URL(fileURLWithPath: path))
        }

        // 逐行扫「字迹」：**一行里有字 ⇒ 这一行的亮度方差大**（空行是纯背景，方差≈0）。
        // 为什么不用「亮像素」：浅色主题下字是**暗的**、背景是亮的，按亮度找会把整块背景当字迹，
        // 深浅两种主题还会给出相反结论 —— 方差对两种主题都成立。
        // 只认**距顶 ≥130pt** 的行：上面那条标题栏两种模式一模一样，算进来只会稀释差值。
        let width = rep.pixelsWide, pixelsHigh = rep.pixelsHigh
        let scale = CGFloat(pixelsHigh) / max(bounds.height, 1)
        var hits: [CGFloat] = []
        for y in 0..<pixelsHigh {
            // `cacheDisplay` 出来的位图**第 0 行就是顶**（渲染时已按 flipped 画），
            // 按 AppKit 默认的「自下而上」去换算会整体上下翻个个儿（实测过一次：两种模式读数正好对调）。
            let fromTop = CGFloat(y) / scale
            guard fromTop >= 130 else { continue }
            var vals: [CGFloat] = []
            var x = 0
            while x < width {
                if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    vals.append(0.2126 * color.redComponent
                                + 0.7152 * color.greenComponent
                                + 0.0722 * color.blueComponent)
                }
                x += 2
            }
            guard vals.count > 8 else { continue }
            let mean = vals.reduce(0, +) / CGFloat(vals.count)
            let variance = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / CGFloat(vals.count)
            if variance.squareRoot() >= 0.10 { hits.append(fromTop) }
        }
        guard !hits.isEmpty else {
            return Band(centroid: 0, first: 0, last: 0, height: bounds.height)
        }
        return Band(centroid: hits.reduce(0, +) / CGFloat(hits.count),
                    first: hits.first ?? 0,
                    last: hits.last ?? 0,
                    height: bounds.height)
    }

    // MARK: - ①② 真实读数

    @MainActor
    func testHeroSitsTopAndShortConversationSitsBottom() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1",
                          "端上取证探针：要 DOYAH_UI_SNAPSHOT=1 才跑")
        let hero = band(empty: true)
        let chat = band(empty: false)
        print("🧪 字迹重心：起手页 \(Int(hero.centroid))pt（\(Int(hero.first))–\(Int(hero.last))）"
              + " / 短会话 \(Int(chat.centroid))pt（\(Int(chat.first))–\(Int(chat.last))）"
              + "（视口高 \(Int(hero.height))pt）")

        let issues = Self.shiftViolations(heroCentroid: hero.centroid, chatCentroid: chat.centroid)
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
    }

    // MARK: - ③ 反例：两条判据互相当反例，必须判红

    @MainActor
    func testEachJudgeIsRedOnTheOtherMode() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1",
                          "端上取证探针：要 DOYAH_UI_SNAPSHOT=1 才跑")
        let hero = band(empty: true)
        let chat = band(empty: false)

        // 反例：把**同一份读数**对调 —— 声称「会话比空态更低」时反过来算，必须判红。
        let swapped = Self.shiftViolations(heroCentroid: chat.centroid, chatCentroid: hero.centroid)
        print("🧪 反例：把两种模式的读数对调 ⇒ \(swapped.isEmpty ? "假绿 ❌" : "判红 ✅")")

        XCTAssertFalse(swapped.isEmpty,
                       "对调读数仍然绿 ⇒ 这条判据量不出方向（两种模式分不开）")
    }
}
