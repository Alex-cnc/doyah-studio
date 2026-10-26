import Foundation
import AVFoundation
import DoyahCore

/// 语音出（`FR-AGT-TOOL-MEDIA-002` 的 macOS 落点）：把一段文本读出来，**可中断**。
///
/// 契约在 Core（`AgentSpeechRequest.validated`）；这一层只管发声与中断，
/// 并把「说到哪了」用回调交回界面（转写原文本身留在会话里，可回看）。
///
/// 如实：语音**进的**那一半（麦克风）本端未接（人类主人 2026-10-26：「除了麦克风其他都可以做的」）。
@MainActor
final class SpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var finishContinuation: CheckedContinuation<Bool, Never>?
    private(set) var isSpeaking = false
    /// 每读完一句回调（界面用来滚动 / 高亮）。
    var onSpokenRange: ((NSRange) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 朗读一段文本；`completion(true)` = 正常读完，`false` = 被打断或合成失败。
    @discardableResult
    func speak(_ request: AgentSpeechRequest) async -> Bool {
        guard let validated = try? request.validated() else { return false }
        stop()
        let utterance = AVSpeechUtterance(string: validated.text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
            synthesizer.speak(utterance)
        }
    }

    /// 中断：立刻停，回调记为「被打断」。
    func stop() {
        guard isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        finishContinuation?.resume(returning: false)
        finishContinuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        finishContinuation?.resume(returning: true)
        finishContinuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        finishContinuation?.resume(returning: false)
        finishContinuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        onSpokenRange?(characterRange)
    }
}
