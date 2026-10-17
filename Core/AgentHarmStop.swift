import Foundation

/// **伤害性动作的及时刹停**（`FR-AI-34` · L0「忠」的机制面）。
///
/// L0 写的是："一旦识别到伤害性，我立刻停下并告诉你：不等指令、不打折扣、不给自己找'这次例外'。"
/// 这个文件把那句话变成**机械判据**，三条纪律：
/// 1. **前置**：在"白名单判定 / 审批队列"之前就判 —— 等于不是"排队等批"，而是**连单都不建**。
/// 2. **宁可误停**：命中的是"不可逆 / 外发 / 提权"这一类；停错了可以再来，做错了不能回滚。
/// 3. **留痕**：每次停手落一条记录（时间 · 类别 · 命中字面 · 命令原文截断）——
///    这就是"我没做过什么"能被查的证据（自我声明不算数）。
public enum AgentHarmCategory: String, Codable, Equatable, Sendable, CaseIterable {
    /// 递归强删（工作区内的临时清理很少需要 `-rf`；宁可停一次）。
    case destructiveDeletion
    /// 强推远端（`--force`）—— 会覆盖别人已经推上去的历史。
    case forcedRemoteWrite
    /// 往别的机器上跑东西 / 开反向 shell。
    case remoteShell
    /// 把数据传出本机（`scp` / `rsync` 到远端 / `curl --upload-file`）。
    case dataEgress
    /// 动磁盘 / 关机 / 重启（不可逆，且影响整机）。
    case diskOrSystem
    /// 提权（`sudo`）。
    case privilegeEscalation
}

public struct AgentHarmSignal: Equatable, Sendable {
    public var category: AgentHarmCategory
    /// 命中的**字面**（ASCII，便于审计与判据；不做本地化）。
    public var marker: String
    public var command: String

    public init(category: AgentHarmCategory, marker: String, command: String) {
        self.category = category
        self.marker = marker
        self.command = command
    }
}

public enum AgentHarmStop {

    /// 纯函数：命令进、结论出。**不执行、不排队、不写文件**（写记录是外面的事，方便判据）。
    ///
    /// 判定顺序 = 危害从重到轻：动磁盘 > 强删 > 强推 > 外发 > 远程执行 > 提权。
    public static func inspect(command: String) -> AgentHarmSignal? {
        let raw = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let lower = raw.lowercased()

        func hit(_ category: AgentHarmCategory, _ marker: String) -> AgentHarmSignal {
            AgentHarmSignal(category: category, marker: marker, command: raw)
        }

        // ① 动磁盘 / 关机（不可逆 + 影响整机）
        for marker in ["mkfs", "dd if=", "diskutil erase", "diskutil reformat", "shutdown ", "reboot"] {
            if lower.contains(marker) { return hit(.diskOrSystem, marker) }
        }

        // ② 递归强删：`rm` 同时带递归与强制
        if hasRMWithRecursiveForce(lower) { return hit(.destructiveDeletion, "rm -rf") }

        // ③ 强推（`--force-with-lease` 是安全变体，**不拦**）
        if lower.contains("git push") {
            if lower.contains("--force-with-lease") { /* 放行 */ }
            else if lower.contains("--force") { return hit(.forcedRemoteWrite, "git push --force") }
            else if containsStandaloneFlag(lower, "-f") { return hit(.forcedRemoteWrite, "git push -f") }
        }

        // ④ 数据外发
        if lower.hasPrefix("scp ") || lower.contains(" scp ") { return hit(.dataEgress, "scp") }
        if lower.contains("rsync ") && containsRemoteHost(lower) { return hit(.dataEgress, "rsync-to-remote") }
        if lower.contains("curl") && (lower.contains("--upload-file") || containsStandaloneFlag(lower, "-T")) {
            return hit(.dataEgress, "curl --upload-file")
        }

        // ⑤ 远程执行 / 反向 shell / 管道直灌解释器
        if lower.hasPrefix("ssh ") || lower.contains(" ssh ") { return hit(.remoteShell, "ssh") }
        if lower.contains("nc -e") || lower.contains("ncat -e") { return hit(.remoteShell, "nc -e") }
        if (lower.contains("curl") || lower.contains("wget")) && (lower.contains("| sh") || lower.contains("| bash")) {
            return hit(.remoteShell, "curl|sh")
        }

        // ⑥ 提权
        if lower.hasPrefix("sudo ") || lower.contains(" sudo ") { return hit(.privilegeEscalation, "sudo") }

        return nil
    }

    // MARK: - 判定小工具

    private static func hasRMWithRecursiveForce(_ lower: String) -> Bool {
        // 逐段看（`rm a && rm -rf b` 里前面那段不算）
        for segment in lower.split(separator: "&").flatMap({ $0.split(separator: ";") }) {
            let tokens = segment.split(separator: " ").map(String.init)
            guard let rmIndex = tokens.firstIndex(where: { $0 == "rm" || $0.hasSuffix("/rm") }) else { continue }
            let flags = tokens.dropFirst(rmIndex + 1).filter { $0.hasPrefix("-") }
            let joined = flags.joined()
            let recursive = flags.contains { $0.contains("r") || $0.contains("R") }
            let forced = flags.contains { $0.contains("f") }
            if (joined.contains("rf") || joined.contains("fr") || joined.contains("Rf") || joined.contains("fR"))
                || (recursive && forced) {
                return true
            }
        }
        return false
    }

    private static func containsStandaloneFlag(_ lower: String, _ flag: String) -> Bool {
        lower.split(separator: " ").contains { $0 == Substring(flag) }
    }

    /// `rsync a/ host:path` 这种带远端冒号的形态（本地 `rsync a/ b/` 不算）。
    private static func containsRemoteHost(_ lower: String) -> Bool {
        lower.split(separator: " ").contains { token in
            guard token.contains(":") else { return false }
            // 排除 `./a:b` 这种本地奇怪文件名：冒号前必须像主机名（字母数字点横线）
            let host = token.split(separator: ":").first.map(String.init) ?? ""
            return !host.isEmpty && host != "." && host.rangeOfCharacter(from: CharacterSet(charactersIn: "/")) == nil
        }
    }
}

/// 停手记录（`FR-AI-34`：**忠不靠誓言，靠记录**）。
///
/// 每次刹停落一条 JSONL（时间 / 类别 / 命中字面 / 命令原文截断 / 会话）。
/// 与「既有外发日志」「既有审计日志」并列但**不合并** —— 它是**安全事件**，口径不同，混在一起会淹掉。
///（注：此处刻意不写那两个日志的文件名 —— 仓里有判据按字面扫「审计写入口只许一处」，写名字会被当成第二套通道。）
public struct AgentHarmStopLog: Sendable {

    public static let fileName = "agent-harm-stops.jsonl"
    /// 命令原文只留前这么多个字符（避免把长命令/可能的敏感参数整段落盘）。
    public static let commandPreviewLimit = 200

    public var directory: URL

    public init(directory: URL) { self.directory = directory }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DoyahStudio", isDirectory: true)
    }

    public static var `default`: AgentHarmStopLog { AgentHarmStopLog(directory: defaultDirectory) }

    public struct Entry: Codable, Equatable, Sendable {
        public var timestamp: Date
        public var category: String
        public var marker: String
        public var command: String
        public var session: String?
    }

    public func fileURL() -> URL { directory.appendingPathComponent(Self.fileName) }

    /// 落一条。写不进去**不抛**（刹停本身绝不能因为日志失败而放行）—— 但也不静默：返回 `false` 让调用方知道。
    @discardableResult
    public func record(_ signal: AgentHarmSignal, session: String? = nil, at: Date = Date()) -> Bool {
        let entry = Entry(timestamp: at,
                          category: signal.category.rawValue,
                          marker: signal.marker,
                          command: String(signal.command.prefix(Self.commandPreviewLimit)),
                          session: session)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = fileURL()
            var line = data
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url)
            }
            return true
        } catch {
            return false
        }
    }

    public func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL()),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(Entry.self, from: Data(line.utf8))
        }
    }
}
