import Foundation

// `FR-AI-30` ①（回边：模型调用的失败分级与重试 / 退避）—— 提案 `0009` B 片。
//
// 为什么单独一个文件：`Core/LLMClient.swift` 的语义是「发一次请求，非 2xx 直接抛」，
// 本文件**不改它**，只在其外面加一层可断言的装饰器 —— 通道仍是一条，重试是回边。
//
// 三条口径（提案 `0009` B 片）：
//  ① 哪些失败值得再试：`transport` / `httpStatus(408 / 429 / 5xx)`；
//     其余（`disabled` / `forbidden` / `quotaExceeded` / 420 之外的 4xx / `malformedResponse` / `emptyCompletion`）**一次都不重试**。
//  ② 等待间隔取**固定表**（默认 `[0.5, 2]` 秒），**不引入随机源** ⇒ 判据可以逐项断言。
//  ③ 上限触达**如实停**：抛出的错误报明「重试 N 次后仍失败 + 最后一次原因」，**不返回半成品**（`R-63` ②）。

/// 重试策略表。全部取值都是参数（可配区间），判据只断言「落在表里 / 落在区间里」。
public struct LLMRetryPolicy: Equatable, Sendable {
    /// 重试次数上限（默认 3 ⇒ 总尝试 = 1 初 + 3 重 = 4 次）。
    public var maxAttempts: Int
    /// 每次重试之前要等的秒数（固定表，超出表长就用表尾）。
    public var delays: [TimeInterval]
    /// 累计等待上限（秒）：`nil` = 不限。触达即按「如实停」处理。
    public var maxTotalSeconds: TimeInterval?

    public init(maxAttempts: Int = 3, delays: [TimeInterval] = [0.5, 2], maxTotalSeconds: TimeInterval? = nil) {
        self.maxAttempts = maxAttempts
        self.delays = delays
        self.maxTotalSeconds = maxTotalSeconds
    }

    /// 失败分级：这一档值得再试吗。
    public func isRetryable(_ error: LLMError) -> Bool {
        switch error {
        case .transport:
            return true
        case .httpStatus(let code, _):
            return code == 408 || code == 429 || (500...599).contains(code)
        case .disabled, .forbidden, .quotaExceeded, .malformedResponse, .emptyCompletion:
            return false
        }
    }

    /// 第 `retry` 次重试（1 起）之前要等的秒数 —— **固定表**，超出表长用表尾。
    public func delayBeforeRetry(_ retry: Int) -> TimeInterval {
        guard !delays.isEmpty else { return 0 }
        return delays[min(max(retry - 1, 0), delays.count - 1)]
    }
}

/// 一次尝试的结局 —— 审计与单测共用这一处读数（序号 / 分类 / 等待间隔）。
public enum LLMRetryOutcome: Equatable, Sendable {
    /// 这一跳拿到了响应。
    case succeeded
    /// 这一跳失败、且策略说值得再试，已按 `after` 秒等待。
    case willRetry(after: TimeInterval)
    /// 这一跳失败、且策略说**不值得再试**（一次都不重试）。
    case notRetryable
    /// 这一跳失败、且次数 / 时长上限触达 ⇒ 如实停。
    case exhausted
}

/// 单次尝试的读数。
public struct LLMRetryAttempt: Equatable, Sendable {
    /// 第几次尝试（1 = 初次）。
    public var attempt: Int
    public var outcome: LLMRetryOutcome
    /// 到这一次尝试为止**累计**等待的秒数。
    public var waitedBefore: TimeInterval
    /// 这一跳的错误（成功时为 `nil`）。
    public var error: LLMError?

    public init(attempt: Int, outcome: LLMRetryOutcome, waitedBefore: TimeInterval, error: LLMError? = nil) {
        self.attempt = attempt
        self.outcome = outcome
        self.waitedBefore = waitedBefore
        self.error = error
    }
}

/// 上限触达时的**如实停**：说清重试了几次、最后一次为什么失败 —— 不带任何「半成品」响应。
public struct LLMRetryExhausted: Error, Equatable, LocalizedError {
    /// 实际尝试次数（含初次）。
    public var attempts: Int
    /// 实际重试次数（= `attempts - 1`）。
    public var retries: Int
    /// 最后一次失败的原因（**原样**，不吞）。
    public var lastError: LLMError
    /// 累计等待秒数。
    public var totalWaited: TimeInterval

    public init(attempts: Int, retries: Int, lastError: LLMError, totalWaited: TimeInterval) {
        self.attempts = attempts
        self.retries = retries
        self.lastError = lastError
        self.totalWaited = totalWaited
    }

    public var errorDescription: String? {
        let reason = lastError.errorDescription ?? "未分类失败"
        return "重试 \(retries) 次后仍失败（共尝试 \(attempts) 次）：\(reason)"
    }
}

/// 装饰既有 `LLMClient` 的重试层。**不改** `OpenAICompatibleClient` 的语义，也不改请求内容 ——
/// 因此「本地端点免 key」这类口径（重试请求同样不带 `Authorization`）天然不受影响。
public struct RetryingLLMClient: LLMClient {
    public let base: any LLMClient
    public let policy: LLMRetryPolicy
    private let sleeper: @Sendable (TimeInterval) async -> Void
    private let onAttempt: (@Sendable (LLMRetryAttempt) -> Void)?

    /// - Parameters:
    ///   - sleeper: 休眠器。**注入**是为了单测不读时钟、不真等（默认实现才真的 `Task.sleep`）。
    ///   - onAttempt: 每次尝试的回调（审计接这里；单测也用它取证）。
    public init(
        base: any LLMClient,
        policy: LLMRetryPolicy = LLMRetryPolicy(),
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            guard seconds > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        onAttempt: (@Sendable (LLMRetryAttempt) -> Void)? = nil
    ) {
        self.base = base
        self.policy = policy
        self.sleeper = sleeper
        self.onAttempt = onAttempt
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var retries = 0
        var waited: TimeInterval = 0

        while true {
            let attemptNumber = retries + 1
            do {
                let response = try await base.complete(request)
                onAttempt?(LLMRetryAttempt(attempt: attemptNumber, outcome: .succeeded, waitedBefore: waited))
                return response
            } catch let error as LLMError {
                guard policy.isRetryable(error) else {
                    onAttempt?(LLMRetryAttempt(attempt: attemptNumber, outcome: .notRetryable,
                                               waitedBefore: waited, error: error))
                    throw error
                }
                let nextRetry = retries + 1
                let delay = policy.delayBeforeRetry(nextRetry)
                let overCount = nextRetry > policy.maxAttempts
                let overTime = policy.maxTotalSeconds.map { waited + delay > $0 } ?? false
                if overCount || overTime {
                    onAttempt?(LLMRetryAttempt(attempt: attemptNumber, outcome: .exhausted,
                                               waitedBefore: waited, error: error))
                    throw LLMRetryExhausted(attempts: attemptNumber, retries: retries,
                                            lastError: error, totalWaited: waited)
                }
                onAttempt?(LLMRetryAttempt(attempt: attemptNumber, outcome: .willRetry(after: delay),
                                           waitedBefore: waited, error: error))
                waited += delay
                retries = nextRetry
                await sleeper(delay)
            }
        }
    }
}
