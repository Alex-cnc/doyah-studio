import AppKit
import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-AGT-UX-CONV-008` 的**Dock 角标判据**。
///
/// 2026-11-03 真机点验的缺陷原话：「任务跑完 `⌘H` 隐藏，Dock 图标没有任何角标」。
/// 根因不是权限也不是签名 —— 置角标那句原来写在 `AgentNotificationPoster.post()` 里，
/// 而 `post()` 只在 `plan.system != nil` 时才被调用，那一格被 `paneIsVisible`
/// （= `NSApp.isActive`）挡住 ⇒ **App 在前台跑完时一次都不走到**。
///
/// 所以这里判的是那条容易做错的组合：
/// ① 前台跑完（`paneIsVisible == true`）⇒ `notifySink` **一次都不该被调**（旧行为到这里就断了）；
/// ② 可 **Dock 角标必须已经置上** —— 它跟着收尾回调走，与弹不弹通知无关；
/// ③ 后台跑完（失败那一轮）⇒ 通知照发，角标同样要有；
/// ④ 回到前台（`didBecomeActive` 那条路调的就是 `clearDockBadge`）能清掉。
///
/// 反例（改回去就红）：删掉 `taskFinishedSink?()`、或把置角标挪回 `post()` ⇒ ①② 红（角标始终 nil）。
final class AgentNotificationBadgeTests: XCTestCase {

    // 角标是**进程级**状态 ⇒ 每条用例自己做收尾（`tearDown` 不是主线程隔离的，
    // 在那边调 `clearDockBadge()` 会撞上 actor 隔离 —— 实测编译不过）。

    /// 前台跑完：通知不弹（这是对的），但**角标要有**（这就是缺陷）。
    @MainActor
    func testFinishingInTheForegroundStillSetsTheDockBadge() async {
        AgentNotificationPoster.clearDockBadge()
        XCTAssertNil(NSApplication.shared.dockTile.badgeLabel, "起点必须是干净的")

        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        model.refreshEndpoint()
        // **缺陷现场**：人正看着这一页（App 在前台）。
        model.paneIsVisible = { true }
        var posted = 0
        model.notifySink = { _ in posted += 1 }
        model.taskFinishedSink = { AgentNotificationPoster.markTaskFinished() }
        model.makeLoop = { _, _, _ in
            (loop: AgentLoop(client: AnsweringClient(), dispatcher: QuietDispatcher()),
             context: AgentLoopContext(systemPrompt: "你是助手。",
                                       userPrompt: "跑一下",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:9/v1")!,
                                                               model: "fake",
                                                               systemPrompt: "",
                                                               userPrompt: ""),
                                       sessionID: "s-badge",
                                       workspace: "ws-badge"))
        }
        model.input = "跑一下"
        await model.send()
        await waitForBadge()

        XCTAssertEqual(posted, 0, "人在看着这一页 ⇒ 系统通知不弹（这条行为不变）")
        XCTAssertEqual(NSApplication.shared.dockTile.badgeLabel, "1",
                       "前台跑完也必须置角标 —— 角标走的是收尾回调，不是「弹通知」那条被前台挡住的闸")
    }

    /// 人不在看（后台跑完）：通知照发，角标同样要有（两处出口互不替代）。
    ///
    /// 用**失败**那一轮：`failed` 不受「长任务 30 秒」门槛限制，判定是确定的
    /// （完成那一轮在测试里只跑了几毫秒，按口径本来就该安静）。
    @MainActor
    func testFinishingInTheBackgroundSetsBothTheNotificationAndTheBadge() async {
        AgentNotificationPoster.clearDockBadge()
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        model.refreshEndpoint()
        model.paneIsVisible = { false }
        var posted = 0
        model.notifySink = { _ in posted += 1 }
        model.taskFinishedSink = { AgentNotificationPoster.markTaskFinished() }
        model.makeLoop = { _, _, _ in
            (loop: AgentLoop(client: FailingClient(), dispatcher: QuietDispatcher()),
             context: AgentLoopContext(systemPrompt: "你是助手。",
                                       userPrompt: "跑一下",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:9/v1")!,
                                                               model: "fake",
                                                               systemPrompt: "",
                                                               userPrompt: ""),
                                       sessionID: "s-badge-bg",
                                       workspace: "ws-badge"))
        }
        model.input = "跑一下"
        await model.send()
        await waitForBadge()

        XCTAssertEqual(NSApplication.shared.dockTile.badgeLabel, "1", "后台跑完同样要置角标")
        XCTAssertGreaterThan(posted, 0, "人不在看 ⇒ 系统通知那一格还要走（角标不是它的替代品）")
    }

    /// 兜底两格自身：置上 / 清掉（`applicationDidBecomeActive` 那条路调的就是 `clearDockBadge`）。
    @MainActor
    func testBadgeCanBeSetAndCleared() {
        AgentNotificationPoster.markTaskFinished()
        XCTAssertEqual(NSApplication.shared.dockTile.badgeLabel, "1")
        AgentNotificationPoster.clearDockBadge()
        XCTAssertNil(NSApplication.shared.dockTile.badgeLabel, "回到前台要能清掉，否则角标会一直挂着")
    }

    /// 收尾可能落在一个 `Task` 里 ⇒ 给一点时间，别把「还没来得及置」读成「没置」。
    /// （门是 10 秒；这条路径是本地假客户端，正常一两帧就到。）
    @MainActor
    private func waitForBadge(timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while NSApplication.shared.dockTile.badgeLabel != "1", Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

// MARK: - 测试用假件（一跳就收尾 / 一跳就失败 / 不碰盘的工具分发）

private final class AnsweringClient: LLMStreamingClient, @unchecked Sendable {
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("看过了。"))
            continuation.yield(.finished(reason: "stop"))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

private final class FailingClient: LLMStreamingClient, @unchecked Sendable {
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        throw LLMError.transport("连不上：测试用假客户端")
    }
}

private final class QuietDispatcher: AgentToolDispatcher, @unchecked Sendable {
    func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
        .file(AgentToolFileOutput(path: "a.txt", text: "", truncated: false, totalBytes: 0))
    }
}
