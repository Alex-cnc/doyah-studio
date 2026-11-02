import Foundation

/// 智能体外发封条（`AC-ALL-GATE-AI-001` / `AC-AI-01` / `NFR-AI-02`）。
///
/// **一句话契约**：总开关关着时，网络层一个请求都不许发出去 —— 不是「发了再报错」。
///
/// 为什么要有这一层（而不是只靠 `AgentGate`）：
///   · `AgentGate.decide` 是**判定**，它只对**问过它的人**生效。2026-11-02 实测：
///     聊天循环、编辑区辅助、连接测试、网页工具这几条路都是直接造 `LLMRequest` 就发，
///     问闸门的是「自然语言生成 SQL」「数据任务规格」「连接测试」三处；漏问一处，
///     「总开关关闭 ⇒ 零外发」这句话当场不成立，而界面上一片安静（没人会发现）。
///   · 所以真正的保证必须落在**唯一的那层运输**上：`URLSessionTransport` 与
///     `URLSessionStreamingTransport` 是 Core 里仅有的两个真实 HTTP 出口（另外只有
///     平台层 IM socket 与笔记云同步各自一份，见 `Tests/AgentEgressSealTests` 的清单判据）。
///     封条在它们**发请求之前**就拦住 ⇒ 新加的调用点即使忘了问闸门，也发不出去。
///
/// 默认值刻意是**关**：装好软件、配置还没读回来那段时间里，进程不知道该不该发 ——
/// 这时候「不发」是唯一安全的答案（安全默认，`NFR-SEC-05`）。
///
/// 同步点只有「配置落盘 / 读回」这一类**真值变化**（`AgentConfigurationStore.load/save`、
/// `AppState.loadAgentConfiguration`、CLI 自建配置）。**不**跟着界面草稿走：设置面板里
/// 拨一下开关还没保存，不该改变本进程此刻能不能外发。
public final class AgentEgressSeal: @unchecked Sendable {

    public static let shared = AgentEgressSeal()

    private let lock = NSLock()
    private var open: Bool

    /// - Parameter initiallyOpen: 单测要能造一个「已经开着」的封条；产品里只走 `.shared`。
    public init(initiallyOpen: Bool = false) {
        self.open = initiallyOpen
    }

    /// 当前是否允许外发。默认 `false`（关）。
    public var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return open
    }

    public func setOpen(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        open = value
    }

    /// 按一份**已保存的**配置同步封条（唯一语义：`isEnabled`）。
    public func apply(_ configuration: AgentConfiguration) {
        setOpen(configuration.isEnabled)
    }

    /// 被拦下时抛的错误。与闸门同一句话，界面不必另写一套文案。
    public var refusal: LLMError { .disabled }
}
