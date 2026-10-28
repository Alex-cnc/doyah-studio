import Foundation
import DoyahCore

/// 从工作区根目录读一次仓库状态（`FR-AGT-KNOW-CTX-001` 的取数半）。
///
/// 解析全在 `AgentGitFacts.parse(porcelain:)`（Core，纯函数、可单测）；这里只负责**跑一次 git**。
/// 三条边界：
/// - 机器上没装 git / 不是仓库 / 超时 ⇒ 返回 `nil`，**不编**一个空分支；
/// - 只读命令（`status --porcelain`），不碰工作树；
/// - 超时 1.5 秒：一个巨型仓库不该把对话卡住（拿不到就当没有，界面照常）。
enum GitStatusProbe {

    static func facts(root: String?) -> AgentGitFacts? {
        guard let root, !root.isEmpty else { return nil }
        // 进程与超时那一套只在 `GitWorktreeProbe.run` 里写一遍（本片同批收口）：
        // 两处各写一份 `Process` + 轮询，迟早一处超时 1.5 秒一处 3 秒，同样的仓库两个面板说法不同。
        switch GitWorktreeProbe.run(["status", "--porcelain=v1", "--branch"], root: root, timeout: 1.5) {
        case .finished(let code, let output):
            guard code == 0 else { return nil }
            return AgentGitFacts.parse(porcelain: output)
        case .timeout, .unavailable:
            return nil
        }
    }
}
