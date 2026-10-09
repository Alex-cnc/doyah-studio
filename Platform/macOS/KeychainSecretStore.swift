import Foundation
import Security

import DoyahCore

/// macOS 侧的凭据存储实现：系统钥匙串（Keychain）。
///
/// **为什么它在平台模块而不是 Core**：`import Security` 只有 Apple 平台有，
/// 放进 Core 会让 Core 在 Linux 上直接编译不过 —— 而 Core 是要两个平台共用的
/// （需求书 §10.9 P-02、概要设计 §3 平台适配层契约）。Core 只留 `SecretStore` 协议。
///
/// Linux 侧需要一个等价实现（Secret Service / 文件 + 0600 权限），
/// 但**行为契约必须一致**：密码不落配置文件、重启后可恢复、可被明确清除、不进错误信息与日志。
public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = DoyahIdentity.keychainServiceName) {
        self.service = service
    }

    public func setPassword(_ password: String, for connectionID: UUID) throws {
        let query = baseQuery(connectionID: connectionID)
        let data = Data(password.utf8)

        let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existingStatus == errSecSuccess {
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
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

    public func password(for connectionID: UUID) throws -> String? {
        var query = baseQuery(connectionID: connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppError.credentialStore(code: status)
        }
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw AppError.credentialStore(code: errSecInternalError)
        }
        return password
    }

    public func deletePassword(for connectionID: UUID) throws {
        let status = SecItemDelete(baseQuery(connectionID: connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.credentialStore(code: status)
        }
    }

    private func baseQuery(connectionID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString
        ]
    }
}

/// macOS 侧的**账号会话令牌**存储实现（片 `云C` · `IR-18`：**令牌存 Keychain，不落明文文件**）。
///
/// 与同文件的 `KeychainSecretStore` 共用同一套 Security 查询（同一个 service、同样是
/// `kSecClassGenericPassword`），只是键换成固定的账号名、载荷换成**会话 JSON**
/// —— **接线复用**，不另起一套（契约：令牌不落配置文件、可被明确清除、不进日志）。
///
/// 为什么是「一个固定账号名」而不是按 `uid` 分条：一台机器上只有一个活动账号 ——
/// 换账号先登出（`CloudAuthClient.signOut` 收尾必清本地会话），所以不存在两条会话并存。
public struct KeychainNoteSyncTokenStore: NoteSyncTokenStore {
    /// 固定账号名（钥匙串里这条记录的 `kSecAttrAccount`）。
    public static let defaultAccount = "notesync.session"

    private let service: String
    private let account: String

    public init(
        service: String = DoyahIdentity.keychainServiceName,
        account: String = KeychainNoteSyncTokenStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    public func setSession(_ session: NoteSyncSession) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw AppError.persistence("会话令牌编码失败")
        }

        let query = baseQuery()
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

    public func session() throws -> NoteSyncSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppError.credentialStore(code: status)
        }
        guard let data = result as? Data else {
            throw AppError.credentialStore(code: errSecInternalError)
        }
        do {
            return try JSONDecoder().decode(NoteSyncSession.self, from: data)
        } catch {
            throw AppError.persistence("会话令牌解码失败")
        }
    }

    public func deleteSession() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.credentialStore(code: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
