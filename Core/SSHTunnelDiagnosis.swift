import Foundation

/// 查询失败时的**归因**：这次失败该不该说成「隧道问题」（FR-CONN-18 判据 ②）。
///
/// **为什么必须有这一层**：隧道断掉之后，驱动看到的是一个普通的 socket 关闭 ——
/// 报出来的话是「连接已断开」「Broken pipe」。用户拿这句话去查，查的是数据库为什么拒绝，
/// 而真因在他的跳板机上。判据 ② 要的正是「断开时指明是隧道问题而非库问题」。
///
/// **反过来也要守住**：没配隧道、或隧道好好活着的时候，**一个字都不许加** ——
/// 把数据库自己的错误说成「隧道问题」同样是误导，而且是更难发现的那种。
///
/// 纯函数：只吃「隧道配置 + 隧道的当前状态 + 原始错误文案」，不读进程、不读磁盘 ⇒ 逐条可测。
public enum SSHTunnelDiagnosis {

    /// 把原始错误文案按隧道状态改写；不需要改写时**原样返回**（同一字符串）。
    ///
    /// - Parameters:
    ///   - tunnel: 连接上的隧道配置（`nil` = 直连）。
    ///   - state: 隧道的当前状态；`nil` = 这一跳根本没起过隧道。
    public static func annotate(
        message: String,
        tunnel: SSHTunnelConfig?,
        state: SSHTunnelProcess.State?,
        language: AppLanguage
    ) -> String {
        guard let tunnel, tunnel.isEnabled, let state else { return message }

        switch state {
        case .ready, .starting, .idle:
            // 隧道在（或在建）：失败就是数据库/语句自己的失败，别抢它的话。
            return message
        case .stopped:
            return LocalizedStrings.format(
                .sshTunnelDroppedDuringQuery,
                language: language,
                LocalizedStrings.text(.sshTunnelStoppedWithoutReason, language: language),
                message
            )
        case .failed(let reason):
            return LocalizedStrings.format(.sshTunnelDroppedDuringQuery, language: language, reason, message)
        }
    }

    /// 这一跳**该不该**因为隧道而作废旧连接（`true` = 隧道已死，下一次执行要重建隧道）。
    ///
    /// 与 `annotate` 分开，是因为两件事的判据不同：文案只在「失败归因」时用，
    /// 而作废连接在**任何一次读到隧道已死**时都该发生（否则下一次复用一个已经断开的连接，
    /// 报出来的又是一句看不懂的连接错误）。
    public static func shouldRebuild(state: SSHTunnelProcess.State?, tunnel: SSHTunnelConfig?) -> Bool {
        guard let tunnel, tunnel.isEnabled, let state else { return false }
        switch state {
        case .failed, .stopped: return true
        case .ready, .starting, .idle: return false
        }
    }
}
