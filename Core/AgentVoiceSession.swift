import Foundation

/// **媒体工具**（`FR-AGT-TOOL-MEDIA-001/002` / 本端计划 P4-媒体）：
/// 语音进 / 语音出，**转写原文可回看、可中断**。
///
/// 状态机刻意小：`idle → recording → transcribing → ready`，中途 `cancel` 后
/// **已产生的转写片段仍可回看**（中断不等于丢结果）。
public enum AgentVoiceState: String, Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case ready
    case cancelled
}

public enum AgentVoiceError: Error, Equatable, Sendable {
    case invalidTransition(from: AgentVoiceState, to: AgentVoiceState)
    case emptyTranscript
}

public struct AgentVoiceSession: Equatable, Sendable {
    public private(set) var state: AgentVoiceState = .idle
    /// 逐段转写（长录音边录边转时会有多段）。
    public private(set) var transcriptSegments: [String] = []
    public private(set) var interrupted: Bool = false

    public init() {}

    public var transcript: String { transcriptSegments.joined(separator: "\n") }
    public var isReady: Bool { state == .ready }

    public mutating func startRecording() throws {
        guard state == .idle || state == .ready || state == .cancelled else {
            throw AgentVoiceError.invalidTransition(from: state, to: .recording)
        }
        state = .recording
        interrupted = false
    }

    public mutating func appendTranscript(_ text: String) throws {
        guard state == .recording || state == .transcribing else {
            throw AgentVoiceError.invalidTransition(from: state, to: .transcribing)
        }
        guard !text.isEmpty else { return }
        transcriptSegments.append(text)
        state = .transcribing
    }

    public mutating func finish() throws -> String {
        guard state == .recording || state == .transcribing else {
            throw AgentVoiceError.invalidTransition(from: state, to: .ready)
        }
        guard !transcript.isEmpty else { throw AgentVoiceError.emptyTranscript }
        state = .ready
        return transcript
    }

    /// 中断：停止收音/转写，但**保留已产生的片段**（可回看）。
    public mutating func cancel() {
        interrupted = true
        state = .cancelled
    }

    public mutating func reset() {
        state = .idle
        transcriptSegments = []
        interrupted = false
    }
}

/// 语音出（TTS）请求：文本 + 是否流式；实际合成在平台层，这里只给契约与校验。
public struct AgentSpeechRequest: Equatable, Sendable {
    public var text: String
    public var streaming: Bool

    public init(text: String, streaming: Bool = true) {
        self.text = text
        self.streaming = streaming
    }

    public enum Validation: Error, Equatable, Sendable {
        case emptyText
        case tooLong(characters: Int, limit: Int)
    }

    public func validated(limit: Int = 4_000) throws -> AgentSpeechRequest {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Validation.emptyText }
        guard trimmed.count <= limit else { throw Validation.tooLong(characters: trimmed.count, limit: limit) }
        return AgentSpeechRequest(text: trimmed, streaming: streaming)
    }
}
