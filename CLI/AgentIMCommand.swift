import Foundation

import DoyahCore
import DoyahPlatform

/// `agent im` —— IM 通道凭据的**配置面**（`FR-AGT-LINK-CHAN-003`）。
///
/// 为什么要有 CLI：AppID / Secret 是**不能走聊天通道**的东西（会留在聊天记录与网关日志里），
/// 而没有界面时（服务器上、SSH 里、第一次装配前）总得有个「落在哪儿」的入口。
/// 所以这一条命令只做三件事：写进去、看状态、清掉 —— **不联网**，传输层还没实现。
///
/// 密钥口径（与 `secret` 命令同一条）：
/// · **只从 stdin 或文件读**，不收 `--secret <值>`（值会进 argv、进 shell 历史、进 `ps`）；
/// · 打出来的永远只有「长度 + 尾 4」，不回显本体；
/// · 本体只进系统凭据存储，配置文件里只有 AppID。
func runAgentIMCommand(arguments: [String]) -> Int32 {
    let usage = """
    用法：
      DoyahCLI agent im set --app-id <AppID> [--secret-stdin | --secret-file <路径>]
      DoyahCLI agent im status
      DoyahCLI agent im clear
    说明：只落凭据，不联网（传输层尚未实现）。Secret 只从 stdin / 文件读，不接受 --secret <值>。
    """

    func value(of flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    let store = AgentIMCredentialStore(secretStore: KeychainAgentIMSecretStore())

    func fail(_ text: String) -> Int32 {
        FileHandle.standardError.write(Data("\(text)\n".utf8))
        return 2
    }

    func statusLine(_ status: AgentIMCredentialStatus) -> String {
        let appID = status.appID.map { "…\($0.suffix(4))（长度 \($0.count)）" } ?? "未配置"
        let secret: String
        if let length = status.secretLength, let tail = status.secretTail {
            secret = "已配置（长度 \(length) · 尾 \(tail)）"
        } else {
            secret = "未配置"
        }
        return """
        AppID：\(appID)
        Secret：\(secret)
        配置文件：\(status.configFileURL.path)
        传输层：未实现（这一格只存凭据，不联网）
        """
    }

    guard let action = arguments.first else { return fail(usage) }

    do {
        switch action {
        case "set":
            guard let appID = value(of: "--app-id") else {
                return fail("缺少 --app-id\n\(usage)")
            }
            if arguments.contains("--secret") {
                return fail("不接受 --secret <值>：值会进 argv、shell 历史与 ps。请用 --secret-stdin 或 --secret-file。")
            }

            let secretPath = value(of: "--secret-file")
            var secret: String?
            if arguments.contains("--secret-stdin") {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8) else {
                    return fail("stdin 不是 UTF-8")
                }
                secret = text
            } else if let secretPath {
                guard let text = try? String(contentsOfFile: secretPath, encoding: .utf8) else {
                    return fail("读不到 --secret-file：\(secretPath)")
                }
                secret = text
            }

            let status = try store.save(appID: appID, secret: secret, for: .qq)
            print(statusLine(status))
            if secret == nil {
                print("注：本次只写 AppID，Secret 未改动。")
            }
            return 0

        case "status":
            print(statusLine(try store.status(for: .qq)))
            return 0

        case "clear":
            try store.clear(for: .qq)
            print(LocalizedStrings.text(.agentIMCleared, language: .simplifiedChinese))
            return 0

        default:
            return fail("未知动作：\(action)\n\(usage)")
        }
    } catch let problem as AgentIMCredentialProblem {
        FileHandle.standardError.write(Data(
            (AgentIMCredentialRejectionText.line(for: problem, language: .simplifiedChinese) + "\n").utf8))
        return 2
    } catch {
        FileHandle.standardError.write(Data("\(CLIFailureText.oneLine(error))\n".utf8))
        return 1
    }
}
