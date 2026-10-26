import Foundation

/// 会话生命周期（`FR-AGT-UX-SESS-001`）：新建 / 归档 / 恢复 / 删除 / 导出 / 重新导入。
///
/// 口径三条（逐条对 SRS 验收要点）：
/// · ① **归档可恢复**：归档 = 挪进 `archive/` 子目录，不是打标记 —— 这样「活跃列表」与
///   「归档列表」各读一处，不会出现「列表里还在、但点进去是归档态」那种半吊子状态；
///   恢复 = 挪回来，**跳数与顺序逐条一致**（判据对拍）。
/// · ② **删除即真删**：活跃文件、归档副本、以及**续跑旁挂件**（`resume-<号>.json`，见
///   `AgentTurnResumeStore`）一并删掉；返回「删了几个文件」而不是布尔 —— 少删一个能被读数看见。
///   别人的工作区的会话**拒删**（不是「删了但你看不到」）。
/// · ③ **导出可重新导入**：导出面已经是 JSON（`export(_:)`），这里补反方向；
///   导入**落到调用方指定的工作区**（导出文件可以带走、换工作区用），
///   同一个会话号已在盘上时**默认拒收**，要覆盖式重名得显式选 `assignNewID`。
public enum AgentSessionLifecycleError: Error, Equatable, Sendable {
    /// 活跃面与归档面都没有这条会话。
    case sessionNotFound
    /// 会话属于别的工作区 —— 不许动（不是「看不到」，是「不许操作」）。
    case workspaceMismatch
    /// 恢复时目标文件名已被占（同一会话号在活跃面已有一份）。
    case conflictingSessionExists(sessionID: String)
    /// 导入载荷不是本产品导出的形状。
    case malformedPayload(reason: String)

    /// 机器码（日志 / 判据用；ASCII，展示层再翻人话）。
    public var code: String {
        switch self {
        case .sessionNotFound: return "sessionNotFound"
        case .workspaceMismatch: return "workspaceMismatch"
        case .conflictingSessionExists(let id): return "conflictingSessionExists:\(id)"
        case .malformedPayload(let reason): return "malformedPayload:\(reason)"
        }
    }
}

/// 导入时同名会话号的处置：默认拒收（不静默覆盖别人的数据）。
public enum AgentSessionIDConflictPolicy: String, Sendable {
    /// 已存在同级会话号 ⇒ 抛 `conflictingSessionExists`。
    case reject
    /// 已存在 ⇒ 换一个新会话号，旧的不动。
    case assignNewID
}

public extension AgentSessionStore {

    /// 归档子目录（与活跃文件同一个父目录，便于整目录备份）。
    var archiveDirectory: URL {
        directory.appendingPathComponent("archive", isDirectory: true)
    }

    func archivedFileURL(sessionID: String) -> URL {
        archiveDirectory.appendingPathComponent(fileURL(sessionID: sessionID).lastPathComponent)
    }

    // MARK: - 归档 / 恢复

    /// 归档一条会话。返回 `true` = 这一下真的挪了；`false` = 本来就在归档态（幂等）。
    @discardableResult
    func archive(sessionID: String, workspace: String) throws -> Bool {
        let loaded = load(sessionID: sessionID, workspace: workspace)
        if loaded.workspaceMismatch { throw AgentSessionLifecycleError.workspaceMismatch }
        guard let session = loaded.session else {
            // 活跃面没有 ⇒ 再看归档面：已在归档态就如实回 false（重复点不该报错）
            if let archived = archivedHeader(sessionID: sessionID) {
                if archived.workspace != workspace { throw AgentSessionLifecycleError.workspaceMismatch }
                return false
            }
            throw AgentSessionLifecycleError.sessionNotFound
        }
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let from = fileURL(sessionID: session.header.id)
        let to = archivedFileURL(sessionID: session.header.id)
        if FileManager.default.fileExists(atPath: to.path) {
            // 归档面已有一份同名（理论上不该有）：不覆盖，报冲突让人看一眼
            throw AgentSessionLifecycleError.conflictingSessionExists(sessionID: session.header.id)
        }
        try FileManager.default.moveItem(at: from, to: to)
        return true
    }

    /// 从归档面恢复。返回 `true` = 真的挪回来了；`false` = 本来就在活跃面。
    @discardableResult
    func restore(sessionID: String, workspace: String) throws -> Bool {
        guard let archived = archivedHeader(sessionID: sessionID) else {
            // 归档面没有 ⇒ 活跃面有就是「本来就在」，否则是真没有
            let active = load(sessionID: sessionID, workspace: workspace)
            if active.workspaceMismatch { throw AgentSessionLifecycleError.workspaceMismatch }
            if active.session != nil { return false }
            throw AgentSessionLifecycleError.sessionNotFound
        }
        if archived.workspace != workspace { throw AgentSessionLifecycleError.workspaceMismatch }
        let to = fileURL(sessionID: archived.id)
        guard !FileManager.default.fileExists(atPath: to.path) else {
            throw AgentSessionLifecycleError.conflictingSessionExists(sessionID: archived.id)
        }
        try FileManager.default.moveItem(at: archivedFileURL(sessionID: archived.id), to: to)
        return true
    }

    /// 归档面里这个工作区有哪些会话（与活跃面同一套「坏文件跳过并计数」口径）。
    func archivedSessions(workspace: String) -> AgentSessionListResult {
        let contents = (try? FileManager.default.contentsOfDirectory(at: archiveDirectory,
                                                                    includingPropertiesForKeys: nil)) ?? []
        var headers: [AgentSessionHeader] = []
        var skippedFiles = 0
        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard url.pathExtension == "jsonl" else { continue }
            guard let header = headerOf(url: url) else { skippedFiles += 1; continue }
            guard header.workspace == workspace else { continue }
            headers.append(header)
        }
        return AgentSessionListResult(headers: headers.sorted { $0.createdAt < $1.createdAt },
                                     skippedFiles: skippedFiles)
    }

    // MARK: - 删除（真删）

    /// 真删：活跃文件 + 归档副本 + 续跑旁挂件一起删。返回删掉的文件数。
    ///
    /// `sidecarDirectories` = 旁挂件所在的目录（`AgentTurnResumeStore.directory` 一类）；
    /// 不传就只删会话本体的两个面 —— 那样「删除后磁盘上不再有该会话数据」这条就**不成立**，
    /// 所以调用方（接界面时）必须把续跑目录一起传进来。
    @discardableResult
    func delete(sessionID: String, workspace: String, sidecarDirectories: [URL] = []) throws -> Int {
        let active = load(sessionID: sessionID, workspace: workspace)
        if active.workspaceMismatch { throw AgentSessionLifecycleError.workspaceMismatch }
        let archived = archivedHeader(sessionID: sessionID)
        if let archived, archived.workspace != workspace { throw AgentSessionLifecycleError.workspaceMismatch }
        guard active.session != nil || archived != nil else {
            throw AgentSessionLifecycleError.sessionNotFound
        }
        var removed = 0
        var targets = [fileURL(sessionID: sessionID), archivedFileURL(sessionID: sessionID)]
        for directory in sidecarDirectories {
            targets.append(directory.appendingPathComponent(AgentTurnResumeStore.sidecarFileName(sessionID: sessionID)))
        }
        for url in targets where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    // MARK: - 导入（导出的反方向）

    /// 把 `export(_:)` 出来的数据重新装成一条会话。
    ///
    /// 三条口径：① **落到调用方指定的工作区**（导出可带走，换工作区照常用）；
    /// ② 会话号已在盘上按 `conflict` 处置（默认拒收，不静默覆盖）；
    /// ③ 形状不对 ⇒ `malformedPayload`，**不落半个文件**（先整份解析完再写）。
    @discardableResult
    func importSession(from data: Data,
                       workspace: String,
                       conflict: AgentSessionIDConflictPolicy = .reject,
                       sessionID: String? = nil) throws -> AgentSessionHeader {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AgentSessionLifecycleError.malformedPayload(reason: "notJSONObject")
        }
        guard let title = root["title"] as? String, !title.isEmpty else {
            throw AgentSessionLifecycleError.malformedPayload(reason: "noTitle")
        }
        guard let rawTurns = root["turns"] as? [[String: Any]] else {
            throw AgentSessionLifecycleError.malformedPayload(reason: "noTurns")
        }

        var turns: [AgentSessionTurn] = []
        var claimedID = sessionID ?? (root["id"] as? String) ?? UUID().uuidString
        for raw in rawTurns {
            guard let kindRaw = raw["kind"] as? String, let kind = AgentSessionTurn.Kind(rawValue: kindRaw),
                  let role = raw["role"] as? String, let text = raw["text"] as? String else {
                throw AgentSessionLifecycleError.malformedPayload(reason: "badTurn")
            }
            let at = (raw["at"] as? String).flatMap(Self.parseISO8601) ?? Date(timeIntervalSince1970: 0)
            turns.append(AgentSessionTurn(sessionID: claimedID, workspace: workspace, kind: kind, role: role,
                                          text: text, toolName: raw["toolName"] as? String,
                                          toolCallID: raw["toolCallID"] as? String,
                                          approval: raw["approval"] as? String, at: at))
        }

        let exists = FileManager.default.fileExists(atPath: fileURL(sessionID: claimedID).path)
            || archivedHeader(sessionID: claimedID) != nil
        if exists {
            switch conflict {
            case .reject:
                throw AgentSessionLifecycleError.conflictingSessionExists(sessionID: claimedID)
            case .assignNewID:
                let fresh = UUID().uuidString
                turns = turns.map { turn in
                    var copy = turn
                    copy.sessionID = fresh
                    return copy
                }
                claimedID = fresh
            }
        }

        let createdAt = (root["createdAt"] as? String).flatMap(Self.parseISO8601) ?? Date()
        let header = AgentSessionHeader(id: claimedID, workspace: workspace, title: title, createdAt: createdAt)
        // 整份解析完才落盘：头一行 + 逐跳
        try ensureDirectoryExists()
        var payload = try Self.encoder.encode(header)
        payload.append(0x0A)
        for turn in turns {
            payload.append(try Self.encoder.encode(turn))
            payload.append(0x0A)
        }
        try payload.write(to: fileURL(sessionID: claimedID), options: .atomic)
        return header
    }

    // MARK: - 内部

    /// 归档面里这条会话的头一行（没有 / 坏掉都回 `nil` —— 调用方按「不在归档态」处理）。
    func archivedHeader(sessionID: String) -> AgentSessionHeader? {
        headerOf(url: archivedFileURL(sessionID: sessionID))
    }

    func headerOf(url: URL) -> AgentSessionHeader? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let data = line.data(using: .utf8),
               let header = try? Self.decoder.decode(AgentSessionHeader.self, from: data) {
                return header
            }
        }
        return nil
    }

    static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

