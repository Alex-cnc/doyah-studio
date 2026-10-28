import Foundation
import Security

import DoyahCore

/// macOS 侧的 IM 通道密钥存储：系统钥匙串（`FR-AGT-LINK-CHAN-003` 的凭据落点）。
///
/// 与 `KeychainAgentKeyStore` 同一个理由放在平台模块：`import Security` 不是跨平台的。
/// 契约（两侧一致）：**Secret 不落配置文件**、可被明确清除、不进日志与审计。
/// 条目名按通道分（`agent-im-qq`），不与模型 API Key（`agent.api-key`）共用一条记录 ——
/// 换模型不该把通道凭据一起覆盖掉。
public struct KeychainAgentIMSecretStore: AgentIMSecretStore {

    private let service: String

    public init(service: String = DoyahIdentity.keychainServiceName) {
        self.service = service
    }

    public func setSecret(_ secret: String, for kind: AgentIMChannelCredentialKind) throws {
        let query = baseQuery(for: kind)
        let data = Data(secret.utf8)

        let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existingStatus == errSecSuccess {
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AppError.credentialStore(code: updateStatus)
            }
            return
        }
        guard existingStatus == errSecItemNotFound else {
            throw AppError.credentialStore(code: existingStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppError.credentialStore(code: addStatus)
        }
    }

    public func secret(for kind: AgentIMChannelCredentialKind) throws -> String? {
        var query = baseQuery(for: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AppError.credentialStore(code: status)
        }
        guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
            throw AppError.credentialStore(code: errSecInternalError)
        }
        return text
    }

    public func deleteSecret(for kind: AgentIMChannelCredentialKind) throws {
        let status = SecItemDelete(baseQuery(for: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.credentialStore(code: status)
        }
    }

    private func baseQuery(for kind: AgentIMChannelCredentialKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.secretAccount
        ]
    }
}
