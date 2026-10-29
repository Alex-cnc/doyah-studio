import Foundation

/// QQ 扫码接入的**协议层**（`FR-AGT-LINK-CHAN-003`）。
///
/// 分工：
/// - 桥进程（`Scripts/qq-qr-bridge.mjs`）只会吐**逐行 JSON**，它不做判断；
/// - 判断全在这里：一行算什么事件、事件之后界面处于哪一档、能不能点「重新生成」；
/// - 界面只负责画二维码与状态字 —— 这样「扫码这条到底成没成」有机械判据，不必靠肉眼。
///
/// 一行一个对象（其它输出一律忽略，桥可能被 npm 之类的噪声污染）：
/// `{"event":"qr","url":"…"}` · `{"event":"expired"}` · `{"event":"success","appId":"…","appSecret":"…","openId":"…"}` · `{"event":"failed","error":"…"}`
public enum AgentIMQREvent: Equatable, Sendable {
    case qr(url: String)
    case expired
    case succeeded(appID: String, appSecret: String, ownerOpenID: String?)
    case failed(reason: String)
}

/// 界面上的四档状态（**只有这四档**，不许界面自己再加一档「进行中但没二维码」）。
public enum AgentIMQRLoginState: Equatable, Sendable {
    /// 还没点。
    case idle
    /// 已出码，等人扫。
    case showing(qr: String)
    /// 码过期了：保留上一张（界面提示「已过期，正在刷新」），等桥给新码。
    case expired(lastQR: String?)
    /// 扫码成功：拿到 AppID / AppSecret，可以落库了。
    case succeeded(appID: String, appSecret: String, ownerOpenID: String?)
    /// 失败：给可读原因（桥不可用、缺少 AppID、二维码生成不出来…）。
    case failed(reason: String)

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed: return true
        case .idle, .showing, .expired: return false
        }
    }

    /// 现在能不能再点一次「用 QQ 扫码接入」（成功与失败都可以重来；出码中不重复起进程）。
    public var allowsRestart: Bool {
        switch self {
        case .succeeded, .failed, .idle, .expired: return true
        case .showing: return false
        }
    }
}

public enum AgentIMQRLogin {

    /// 把桥的一行输出解析成事件；不是这四个之一（空行 / 噪声 / 字段缺失）一律 `nil`。
    public static func parse(line: String) -> AgentIMQREvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return nil }

        switch event {
        case "qr":
            guard let url = (object["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else { return nil }
            return .qr(url: url)
        case "expired":
            return .expired
        case "success":
            let appID = string(object["appId"])
            let secret = string(object["appSecret"])
            // **缺一个就算没成**：宁可报失败，也不许把半套凭据落库（落进去只会连不上）。
            guard !appID.isEmpty, !secret.isEmpty else {
                return .failed(reason: "QQ 授权结果缺少 AppID 或 AppSecret")
            }
            let openID = string(object["openId"])
            return .succeeded(appID: appID, appSecret: secret, ownerOpenID: openID.isEmpty ? nil : openID)
        case "failed":
            let reason = string(object["error"])
            return .failed(reason: reason.isEmpty ? "扫码服务不可用" : reason)
        default:
            return nil
        }
    }

    /// 状态推进（纯函数）。
    public static func next(_ state: AgentIMQRLoginState, event: AgentIMQREvent) -> AgentIMQRLoginState {
        switch event {
        case .qr(let url):
            // 收到新码：任何非终态都进「出码中」；已经成功的**不许被新码打回**（成功即定稿）。
            if case .succeeded = state { return state }
            return .showing(qr: url)
        case .expired:
            // 过期只记住上一张码，界面照旧等人扫下一张；成功后过期通知一律忽略。
            switch state {
            case .succeeded, .failed: return state
            case .showing(let qr): return .expired(lastQR: qr)
            case .expired(let last): return .expired(lastQR: last)
            case .idle: return .expired(lastQR: nil)
            }
        case .succeeded(let appID, let secret, let openID):
            return .succeeded(appID: appID, appSecret: secret, ownerOpenID: openID)
        case .failed(let reason):
            return .failed(reason: reason)
        }
    }

    /// 桥脚本相对仓库的固定位置（判据与界面共用一处，免得两处各写一条路径）。
    public static let bridgeRelativePath = "Scripts/qq-qr-bridge.mjs"

    /// 起桥用的命令（纯函数：只给 node + 脚本路径，不带任何参数注入面）。
    public static func launchArguments(bridgePath: String) -> [String] {
        [bridgePath]
    }

    /// 起桥用的环境变量：连接器入口可由宿主显式指定（不指定时桥自己按 DSH 档案顺序找）。
    public static func environment(connectorEntry: String?, inherited: [String: String]) -> [String: String] {
        var env = inherited
        if let entry = connectorEntry, !entry.isEmpty {
            env["DOYAH_QQ_CONNECTOR_ENTRY"] = entry
        }
        return env
    }

    /// 成功后要落库的两样（`appSecret` 进钥匙串，`appID` 进配置；openid 只作展示与主人绑定）。
    public static func credentials(from state: AgentIMQRLoginState) -> (appID: String, appSecret: String, ownerOpenID: String?)? {
        guard case .succeeded(let appID, let secret, let openID) = state else { return nil }
        return (appID, secret, openID)
    }

    private static func string(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
