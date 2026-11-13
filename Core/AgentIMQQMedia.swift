import Foundation

/// **原生媒体出站**（`T-3.25-12`，需求 ⑫：图 / 文件 / 语音走原生媒体，先上传换句柄再发）。
///
/// 三段口径，都是踩过的坑：
/// ① **只收本机文件**：`http(s)` 一律拒绝并说明「不代下载」—— 拿链接当附件发，平台回的是
///    一张 404 的占位图，用户以为发出去了；
/// ② **先上传换 `file_info` 再发消息**：直接把字节塞进消息体是自建中继那套写法，官方 REST 不认；
/// ③ **失败三分**（配额 / 瞬时 / 其余）：`40093002` 当日配额用尽不可重试、`40093001` 可重试一次、
///    连接层抛错算网络 —— 混成一档，人只能看到「发了但没动静」。
public enum AgentIMMediaKind: String, Codable, Equatable, Sendable, CaseIterable {
    case image
    case video
    case voice
    case file

    /// 官方 `file_type`（1 图 / 2 视频 / 3 语音 / 4 文件）。
    public var fileType: Int {
        switch self {
        case .image: return 1
        case .video: return 2
        case .voice: return 3
        case .file: return 4
        }
    }

    /// 按扩展名猜档（猜不出按文件发 —— 猜错成「语音」会被客户端当坏文件）。
    public static func inferred(fromPath path: String) -> AgentIMMediaKind {
        switch (path as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic": return .image
        case "mp4", "mov", "m4v", "webm": return .video
        case "mp3", "wav", "m4a", "ogg", "amr", "silk", "flac", "aac": return .voice
        default: return .file
        }
    }
}

/// 待发的媒体（**只有本机文件**这一种形态）。
public enum AgentIMMediaSource: Equatable, Sendable {

    case localFile(URL)

    public enum Problem: Error, Equatable, Sendable {
        case empty
        /// 链接：不代下载。
        case linkNotAllowed
        case notAFile
        case unreadable
    }

    public static func validated(path: String) throws -> AgentIMMediaSource {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Problem.empty }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("file://") {
            throw Problem.linkNotAllowed
        }
        let url = URL(fileURLWithPath: trimmed).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw Problem.unreadable
        }
        guard !isDirectory.boolValue else { throw Problem.notAFile }
        return .localFile(url)
    }

    public var url: URL? {
        if case .localFile(let url) = self { return url }
        return nil
    }
}

/// 媒体链路要的两件 HTTP 能力（分片上传 + 普通 JSON 发送）。
public protocol AgentIMMediaHTTPClient: Sendable {
    func postMultipart(_ url: URL, body: Data, contentType: String, headers: [String: String]) async throws -> AgentIMHTTPResponse
    func post(_ url: URL, payload: String, headers: [String: String]) async throws -> AgentIMHTTPResponse
}

/// 官方文件上传端点（**只有这一处拼路径**）。
public enum AgentIMQQMediaEndpoint {

    public static func uploadPath(for target: AgentIMOutboundTarget) -> String {
        let segment = target.kind == .c2c ? "users" : "groups"
        return "/v2/\(segment)/\(target.openID)/files"
    }

    public static func uploadURL(for target: AgentIMOutboundTarget,
                                 environment: AgentIMQQEnvironment) -> URL? {
        guard let valid = try? target.validated() else { return nil }
        return URL(string: uploadPath(for: valid), relativeTo: environment.apiBase)?.absoluteURL
    }
}

/// 上传结果（`file_info` 就是后面发消息时要塞进 `media` 的那个句柄）。
public enum AgentIMMediaUploadResult: Equatable, Sendable {
    case uploaded(fileInfo: String, kind: AgentIMMediaKind)
    case failed(AgentIMDeliveryFailure)
}

/// 媒体消息的正文形状（`msg_type=7` + `media.file_info`）。
public struct AgentIMQQMediaBody: Equatable, Sendable {

    public static let mediaMessageType = 7

    public var fileInfo: String
    public var messageID: String?
    public var sequence: Int?

    public init(fileInfo: String, messageID: String? = nil, sequence: Int? = nil) {
        self.fileInfo = fileInfo
        self.messageID = messageID
        self.sequence = sequence
    }

    public func jsonString() -> String {
        var object: [String: Any] = ["content": "", "msg_type": Self.mediaMessageType,
                                     "media": ["file_info": fileInfo]]
        if let messageID, !messageID.isEmpty { object["msg_id"] = messageID }
        if let sequence, messageID != nil { object["msg_seq"] = sequence }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// 发一条本机媒体：**上传 → 拿 `file_info` → 发 `msg_type=7`**。
public struct AgentIMQQMediaSender: Sendable {

    public var client: any AgentIMMediaHTTPClient
    public var environment: AgentIMQQEnvironment
    public var sequences: AgentIMReplySeqLedger
    public var token: @Sendable () async throws -> AgentIMQQToken
    /// 瞬时失败是否重试一次（默认是：`40093001` 本来就写着「可重试」）。
    public var retriesTransient: Bool
    /// 重试前的等待（秒）。测试传 0，真机 1。
    public var retryDelay: TimeInterval

    public init(client: any AgentIMMediaHTTPClient,
                environment: AgentIMQQEnvironment,
                sequences: AgentIMReplySeqLedger,
                token: @escaping @Sendable () async throws -> AgentIMQQToken,
                retriesTransient: Bool = true,
                retryDelay: TimeInterval = 1) {
        self.client = client
        self.environment = environment
        self.sequences = sequences
        self.token = token
        self.retriesTransient = retriesTransient
        self.retryDelay = retryDelay
    }

    public func send(path: String,
                     kind: AgentIMMediaKind? = nil,
                     target: AgentIMOutboundTarget,
                     entryID: String,
                     replyTo messageID: String?,
                     at: Date = Date()) async -> AgentIMSendOutcome {
        let source: AgentIMMediaSource
        do {
            source = try AgentIMMediaSource.validated(path: path)
        } catch AgentIMMediaSource.Problem.linkNotAllowed {
            return .notReady(code: "linkNotAllowed")
        } catch {
            return .notReady(code: "mediaUnreadable")
        }
        guard let fileURL = source.url else { return .notReady(code: "mediaUnreadable") }
        guard let valid = try? target.validated(),
              let uploadURL = AgentIMQQMediaEndpoint.uploadURL(for: valid, environment: environment),
              let sendURL = AgentIMQQMessageEndpoint.url(for: valid, environment: environment) else {
            return .notReady(code: "badTarget")
        }
        let mediaKind = kind ?? AgentIMMediaKind.inferred(fromPath: fileURL.path)

        let tokenValue: AgentIMQQToken
        do {
            tokenValue = try await token()
        } catch let problem as AgentIMQQProvisionProblem {
            return AgentIMOutboundSender.outcome(for: problem)
        } catch {
            return .notReady(code: "tokenUnavailable")
        }

        let upload = await upload(url: uploadURL, fileURL: fileURL, kind: mediaKind,
                                  headers: tokenValue.authorizationHeaders)
        let fileInfo: String
        switch upload {
        case .uploaded(let info, _): fileInfo = info
        case .failed(let failure):
            return Self.outcome(for: failure)
        }

        let replyTo = (messageID?.isEmpty == false) ? messageID : nil
        let body = AgentIMQQMediaBody(fileInfo: fileInfo,
                                      messageID: replyTo,
                                      sequence: sequences.sequence(forEntry: entryID,
                                                                   replyTo: replyTo,
                                                                   at: at))
        do {
            let response = try await client.post(sendURL, payload: body.jsonString(),
                                                 headers: tokenValue.authorizationHeaders)
            return AgentIMOutboundSender.outcome(for: response)
        } catch {
            return .networkFailed
        }
    }

    /// 上传一次（瞬时失败按 `retriesTransient` 重试一次；配额一次都不重试）。
    func upload(url: URL, fileURL: URL, kind: AgentIMMediaKind,
                headers: [String: String]) async -> AgentIMMediaUploadResult {
        var attempt = 0
        while true {
            attempt += 1
            let boundary = "doyah-\(UUID().uuidString)"
            guard let body = Self.multipartBody(fileURL: fileURL, kind: kind, boundary: boundary) else {
                return .failed(.other(code: "mediaUnreadable"))
            }
            let response: AgentIMHTTPResponse
            do {
                response = try await client.postMultipart(url, body: body,
                                                          contentType: "multipart/form-data; boundary=\(boundary)",
                                                          headers: headers)
            } catch {
                return .failed(.network)
            }
            if response.isSuccess {
                if let info = ProvisionerSupport.jsonObject(response.body)?["file_info"] as? String,
                   !info.isEmpty {
                    return .uploaded(fileInfo: info, kind: kind)
                }
                return .failed(.other(code: "noFileInfo"))
            }
            let code = AgentIMQQProvisioner.errorCode(in: response.body)
            let failure = AgentIMDeliveryFailure.classify(status: response.status, code: code)
            if failure.shouldRetry, retriesTransient, attempt < 2 {
                if retryDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000)) }
                continue
            }
            return .failed(failure)
        }
    }

    /// `multipart/form-data` 正文（字段名按官方：`file_image` 图 / `file` 其余，`file_type`，`srv_send_msg=false`）。
    static func multipartBody(fileURL: URL, kind: AgentIMMediaKind, boundary: String) -> Data? {
        guard let bytes = try? Data(contentsOf: fileURL) else { return nil }
        let filename = fileURL.lastPathComponent
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("file_type", "\(kind.fileType)")
        field("srv_send_msg", "false")
        let fileField = kind == .image ? "file_image" : "file"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(bytes)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    static func outcome(for failure: AgentIMDeliveryFailure) -> AgentIMSendOutcome {
        switch failure {
        case .quota: return .rateLimited
        case .transient: return .serverFailed
        case .network: return .networkFailed
        case .other(let code): return .notReady(code: code)
        }
    }
}
