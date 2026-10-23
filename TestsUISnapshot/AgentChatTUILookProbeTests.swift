import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 对话面板**观感探针**：把真视图树离屏渲染成 PNG，用来判「像不像 Hermes -tui」。
///
/// 为什么要有它：人类主人已经两次说「界面像不了 TUI」，而**系统截屏权限拿不到**（`screencapture`
/// 恒为黑图），等于我一直在盲改 —— 改了间距、改了字形，自己一次也没看见过结果。
/// 这个探针把「人眼验收」变成可复跑产物：同一份种子数据 → 同一张图 → 我自己读图判定。
///
/// 口径：
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）；它是取证工具，不进每轮门禁；
/// · 数据**全部合成**：不连库、不读用户会话、不发请求；
/// · 拍两张：满屏对话（有工具卡、代码块、事件行）与空会话空态。
final class AgentChatTUILookProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "界面快照要显式打开：DOYAH_UI_SNAPSHOT=1（它是取证工具，不进每轮门禁）"
        )
    }

    @MainActor
    private func seededModel() -> AgentChatModel {
        let messages: [AgentChatMessage] = [
            .init(role: .user, text: "把当前库的表结构列出来，重点看订单相关的几张。"),
            .init(role: .assistant, text: "先看一眼有哪些表。"),
            .init(role: .tool, text: "list_tables · 23 个表"),
            .init(role: .assistant, text: """
            有 5 张和订单相关。`orders` 是主表，`order_items` 是明细，其余三张是字典表。

            ```sql
            select table_name, (select count(*) from information_schema.columns c
                                where c.table_name = t.table_name) as cols
            from information_schema.tables t
            where table_schema = 'public' and table_name like 'order%';
            ```
            """),
            .init(role: .tool, text: "sql_query · 5 行 · 34ms"),
            .init(role: .assistant, text: "明细表 `order_items` 没有外键索引，1,200 万行下按 `order_id` 查会全表扫。"),
            .init(role: .notice, text: "◈ 已切到只读连接")
        ]
        let cards: [AgentToolCard] = [
            .init(name: "list_tables", arguments: "schema: public", outcome: .executed("23 个表")),
            .init(name: "sql_query", arguments: "select … from order_items", outcome: .executed("5 行 · 34ms"))
        ]
        let state = AgentChatState(messages: messages, cards: cards,
                                   endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"))
        return AgentChatModel(sessionID: "snapshot", state: state)
    }

    /// 满屏对话：工具卡、代码块、事件行同屏。
    @MainActor
    func testTranscriptLooksLikeTUI() throws {
        let state = AppState()
        state.connections = []
        let model = seededModel()
        _ = try UISnapshot.write("agent-chat-tui-dark", size: CGSize(width: 920, height: 640),
                                 scheme: .dark) {
            AgentChatView(model: model)
                .environmentObject(state)
                .environmentObject(WorkspaceTabsModel())
        }
    }

    /// 空会话空态（A1 的观感）。
    @MainActor
    func testEmptyStateLooksLikeTUI() throws {
        let state = AppState()
        state.connections = []
        let model = AgentChatModel(sessionID: "snapshot-empty")
        _ = try UISnapshot.write("agent-chat-tui-empty-dark", size: CGSize(width: 920, height: 480),
                                 scheme: .dark) {
            AgentChatView(model: model)
                .environmentObject(state)
                .environmentObject(WorkspaceTabsModel())
        }
    }
}
