import Foundation

/// **内联审批按钮**（需求 ⑧「平台支持时改为内联按钮，码保留为兜底」）。
///
/// 三件事，缺一件这个功能就是坏的：
/// ① **按钮上带的那串数据由我们自己定**（`approve:<码>` / `reject:<码>`）：它是平台回传的
///    唯一凭据，解析必须窄 —— 认不出的数据一律不当作放行；
/// ② **点完必须及时 ACK**（`PUT /interactions/{id}` + `{"code":0}`）：不 ACK，用户那边看到的是
///    一个错误标记，还以为自己点失败了，于是再点一遍；
/// ③ **按钮不放宽审批**：它和「批准 <码>」走**同一条**票据判定（一码一票、一次性、过期作废），
///    这里只负责把按钮变成同一句决定。
public enum AgentIMQQButtonData {

    public static let approvePrefix = "approve:"
    public static let rejectPrefix = "reject:"

    public static func approve(code: String) -> String { approvePrefix + code.lowercased() }
    public static func reject(code: String) -> String { rejectPrefix + code.lowercased() }

    /// 按钮数据 → 决定（复用「批准 <码>」那套解析：形状与语义只此一处）。
    public static func decision(from raw: String) -> AgentIMApprovalCommand.Decision? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix(approvePrefix) {
            let code = String(trimmed.dropFirst(approvePrefix.count))
            return AgentIMApprovalCommand.isHexCode(code)
                ? .init(approve: true, code: code) : nil
        }
        if trimmed.hasPrefix(rejectPrefix) {
            let code = String(trimmed.dropFirst(rejectPrefix.count))
            return AgentIMApprovalCommand.isHexCode(code)
                ? .init(approve: false, code: code) : nil
        }
        return nil
    }
}

/// 按钮面板的 JSON（官方 `keyboard.content.rows[].buttons[]`）。
public enum AgentIMQQKeyboard {

    /// 审批两个按钮（批准 / 拒绝）。`code` 就是票据上的那一小段。
    public static func approval(code: String, language: AppLanguage) -> String {
        let approveLabel = LocalizedStrings.text(.agentIMButtonApprove, language: language)
        let rejectLabel = LocalizedStrings.text(.agentIMButtonReject, language: language)
        let payload: [String: Any] = [
            "content": [
                "rows": [
                    ["buttons": [
                        button(id: "approve", label: approveLabel, visited: approveLabel,
                               data: AgentIMQQButtonData.approve(code: code), style: 1),
                        button(id: "reject", label: rejectLabel, visited: rejectLabel,
                               data: AgentIMQQButtonData.reject(code: code), style: 0)
                    ]]
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func button(id: String, label: String, visited: String,
                               data: String, style: Int) -> [String: Any] {
        [
            "id": id,
            "render_data": ["label": label, "visited_label": visited, "style": style],
            // **action.type = 1 才是回调**（平台推 `INTERACTION_CREATE` 的唯一取值）；
            // `2` 是链接跳转 —— 带 data 也不推事件，真机表现为「点了没反应、日志零事件」。
            // permission.type = 2（所有人可点，具体到谁能放行由票据判）。
            "action": ["type": 1, "permission": ["type": 2], "data": data, "enter": true]
        ]
    }
}

/// 平台推回来的那一次点击（`INTERACTION_CREATE`）。
public struct AgentIMInteraction: Equatable, Sendable {
    public var interactionID: String
    public var buttonData: String
    public var chatID: String
    public var userID: String
    public var chatKind: AgentIMChatKind

    public init(interactionID: String, buttonData: String, chatID: String,
                userID: String, chatKind: AgentIMChatKind) {
        self.interactionID = interactionID
        self.buttonData = buttonData
        self.chatID = chatID
        self.userID = userID
        self.chatKind = chatKind
    }
}

public enum AgentIMQQInteractionParser {

    /// 解 `INTERACTION_CREATE` 的 `d`。解不出关键字段 ⇒ `nil`（**不许猜**）。
    public static func parse(_ data: [String: Any]) -> AgentIMInteraction? {
        guard let interactionID = data["id"] as? String, !interactionID.isEmpty else { return nil }
        let payload = data["data"] as? [String: Any]
        let resolved = payload?["resolved"] as? [String: Any]
        let buttonData = (resolved?["button_data"] as? String)
            ?? (payload?["button_data"] as? String)
            ?? ""
        guard !buttonData.isEmpty else { return nil }
        let chatType = (data["chat_type"] as? NSNumber)?.intValue ?? 0
        let groupID = data["group_openid"] as? String
        let userID = (data["user_openid"] as? String) ?? ""
        let chatID = groupID ?? userID
        guard !chatID.isEmpty else { return nil }
        let kind: AgentIMChatKind = chatType == 2 || groupID != nil ? .group : .c2c
        return AgentIMInteraction(interactionID: interactionID, buttonData: buttonData,
                                  chatID: chatID, userID: userID, chatKind: kind)
    }
}

/// ACK 用的 HTTP 能力（`PUT`）。
public protocol AgentIMInteractionHTTPClient: Sendable {
    func put(_ url: URL, payload: String, headers: [String: String]) async throws -> AgentIMHTTPResponse
}

public enum AgentIMQQInteractionEndpoint {

    public static func ackPath(interactionID: String) -> String {
        "/interactions/\(interactionID)"
    }

    public static func ackURL(interactionID: String,
                              environment: AgentIMQQEnvironment) -> URL? {
        // interaction id 是外部输入：只放行字母数字与短横线（它要被拼进路径）。
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !interactionID.isEmpty,
              interactionID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return URL(string: ackPath(interactionID: interactionID), relativeTo: environment.apiBase)?.absoluteURL
    }
}

/// 点完就 ACK（`{"code":0}` 表示「收到，按钮状态可以落定」）。
public struct AgentIMQQInteractionAcker: Sendable {

    public var client: any AgentIMInteractionHTTPClient
    public var environment: AgentIMQQEnvironment
    public var token: @Sendable () async throws -> AgentIMQQToken

    public init(client: any AgentIMInteractionHTTPClient,
                environment: AgentIMQQEnvironment,
                token: @escaping @Sendable () async throws -> AgentIMQQToken) {
        self.client = client
        self.environment = environment
        self.token = token
    }

    public func ack(_ interaction: AgentIMInteraction) async -> AgentIMSendOutcome {
        guard let url = AgentIMQQInteractionEndpoint.ackURL(interactionID: interaction.interactionID,
                                                            environment: environment) else {
            return .notReady(code: "badInteractionID")
        }
        let tokenValue: AgentIMQQToken
        do {
            tokenValue = try await token()
        } catch let problem as AgentIMQQProvisionProblem {
            return AgentIMOutboundSender.outcome(for: problem)
        } catch {
            return .notReady(code: "tokenUnavailable")
        }
        do {
            let response = try await client.put(url, payload: #"{"code":0}"#,
                                                headers: tokenValue.authorizationHeaders)
            // ACK 的回执是**空体 `{}`**（没有 `id`）：不能拿「外发那条」的判定（它要求 `id`，
            // 空体会被判成 `responseNotJSON` —— 2026-11-14 真机就报这个，看着像失败其实平台已收下）。
            // 官方文档：`PUT /interactions/{id}` 成功回 `{}`。2xx 即算 ACK 成功。
            if response.isSuccess { return .delivered(messageID: nil) }
            return AgentIMOutboundSender.outcome(for: response)
        } catch {
            return .networkFailed
        }
    }
}
