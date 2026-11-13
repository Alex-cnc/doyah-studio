import Foundation

/// **入站附件**（`T-3.25-13`，需求 ⑫：入站附件必须解析并回执，不许当没看见）。
///
/// 三条纪律：
/// ① **只跟 http(s) 取**：平台给的 `url` 是外部输入 —— `file://` / 其它 scheme 一律不取
///    （否则一条消息就能让产品去读本机任意文件并回执出去）；
/// ② **落到会话目录、0600**：文件名要洗（去掉路径分隔符与 `..`），落盘权限只给本人；
/// ③ **取不到也要说**：`localPath == nil` + `note` ⇒ 回执里写「（没取到）」，
///    静默丢弃是最坏的形态 —— 用户以为助手看见了图，其实什么都没拿到。
public struct AgentIMInboundAttachment: Codable, Equatable, Sendable {

    public var contentType: String?
    public var filename: String
    public var byteCount: Int?
    public var remoteURL: URL?
    /// 落到本机的路径（取不到就是 `nil`）。
    public var localPath: String?
    /// 取不到的原因（机器码，人话由回执翻）。
    public var note: String?

    public init(contentType: String? = nil, filename: String, byteCount: Int? = nil,
                remoteURL: URL? = nil, localPath: String? = nil, note: String? = nil) {
        self.contentType = contentType
        self.filename = filename
        self.byteCount = byteCount
        self.remoteURL = remoteURL
        self.localPath = localPath
        self.note = note
    }
}

public enum AgentIMInboundAttachmentParser {

    /// 从入站帧的 `d` 里解 `attachments`（官方形状：`{content_type, filename, size, url, width, height}`）。
    public static func parse(_ data: [String: Any]) -> [AgentIMInboundAttachment] {
        guard let raw = data["attachments"] as? [[String: Any]], !raw.isEmpty else { return [] }
        return raw.map { item in
            let filename = sanitizedFilename(item["filename"] as? String)
            let size = (item["size"] as? NSNumber)?.intValue
            let urlText = (item["url"] as? String) ?? ""
            let url = URL(string: urlText)
            var note: String?
            if let url {
                let scheme = url.scheme?.lowercased() ?? ""
                if scheme != "http" && scheme != "https" { note = "unsupportedScheme" }
            } else {
                note = "badURL"
            }
            return AgentIMInboundAttachment(contentType: item["content_type"] as? String,
                                            filename: filename,
                                            byteCount: size,
                                            remoteURL: note == nil ? url : nil,
                                            localPath: nil,
                                            note: note)
        }
    }

    /// 洗文件名：只留最后一段、去 `..`、空的给个占位。
    static func sanitizedFilename(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "attachment" }
        var name = (trimmed as NSString).lastPathComponent
        name = name.replacingOccurrences(of: "..", with: "_")
        name = name.replacingOccurrences(of: "/", with: "_")
        name = name.replacingOccurrences(of: "\\", with: "_")
        return name.isEmpty ? "attachment" : name
    }
}

/// 把附件取到本机（注入 `download` 便于测：判据里不联网）。
public struct AgentIMInboundAttachmentStore: Sendable {

    public var directory: URL
    /// 上限：超过就不取（一条消息不该把磁盘塞满）。
    public var maxBytes: Int
    public var download: @Sendable (URL) async throws -> Data

    public init(directory: URL,
                maxBytes: Int = 20 * 1024 * 1024,
                download: @escaping @Sendable (URL) async throws -> Data) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.download = download
    }

    public func store(_ attachments: [AgentIMInboundAttachment]) async -> [AgentIMInboundAttachment] {
        var stored: [AgentIMInboundAttachment] = []
        for var attachment in attachments {
            guard attachment.remoteURL != nil, attachment.note == nil else {
                stored.append(attachment)
                continue
            }
            if let size = attachment.byteCount, size > maxBytes {
                attachment.note = "tooLarge"
                stored.append(attachment)
                continue
            }
            do {
                let data = try await download(attachment.remoteURL!)
                guard data.count <= maxBytes else {
                    attachment.note = "tooLarge"
                    stored.append(attachment)
                    continue
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appendingPathComponent(uniqueName(attachment.filename))
                try data.write(to: target, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                       ofItemAtPath: target.path)
                attachment.localPath = target.path
                attachment.byteCount = data.count
            } catch {
                attachment.note = "downloadFailed"
            }
            stored.append(attachment)
        }
        return stored
    }

    private func uniqueName(_ name: String) -> String {
        let stamp = UUID().uuidString.prefix(8)
        return "\(stamp)-\(name)"
    }
}

/// 回执那一句（`N 个附件：a.png（12.3 KB）、b.pdf（没取到）`）。
public enum AgentIMAttachmentReceipt {

    public static func line(for attachments: [AgentIMInboundAttachment],
                            language: AppLanguage) -> String? {
        guard !attachments.isEmpty else { return nil }
        let missing = LocalizedStrings.text(.agentIMAttachmentMissing, language: language)
        let items = attachments.map { attachment -> String in
            let size = attachment.byteCount.map { Self.humanSize($0) } ?? "—"
            if attachment.localPath == nil { return "\(attachment.filename)（\(missing)）" }
            return "\(attachment.filename)（\(size)）"
        }
        return LocalizedStrings.format(.agentIMAttachmentReceipt, language: language,
                                       Int64(attachments.count), items.joined(separator: "、"))
    }

    static func humanSize(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
        if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        return "\(bytes) B"
    }
}
