import Foundation
import Combine
import DoyahCore

/// 「变更」页（`FR-STD-WS-VCS-001`）的状态所有者。
///
/// 为什么状态住在这里而不是视图里：这块面板挂在**段一级**的下方面板里，
/// 切活动栏 / 折叠 / 最大化都会重建视图树（本仓在侧边栏折叠状态上栽过一次，
/// 见 `AGENT-SPEC.md` §9 第 35 条）。刷新一次要跑两次 git（status + diff），
/// 让它在 `@State` 里随视图重建丢一次，用户看到的就是「每次切回来都在转圈」。
///
/// 三条口径：
///   ① **只读**：这里没有任何会改变工作树 / 暂存区 / 历史的方法；
///   ② **不静默**：读失败留着失败档（`failure`），界面上说清是哪一档，不把它当「干净」；
///   ③ **一次只认最后一次请求**（`token`）：git 慢时连点两下刷新，先回来的那次不许覆盖后发的。
final class GitChangesModel: ObservableObject {

    /// 状态读取的三态（外加上一次失败的档）。
    enum LoadState: Equatable {
        case idle
        case loading
        case ready(GitWorktreeStatus)
        case failed(GitProbeFailure)
    }

    @Published private(set) var state: LoadState = .idle
    /// 当前在右边看的那个文件（nil = 还没选）。
    @Published private(set) var selection: GitWorktreeEntry?
    @Published private(set) var diff: GitDiffDocument?
    @Published private(set) var diffFailure: GitProbeFailure?
    /// 右侧看的是暂存区那一侧还是工作区那一侧（同一个文件两侧都有改动时，用户要看得出区别）。
    @Published private(set) var diffIsStaged = false
    @Published private(set) var isRefreshing = false

    /// 请求序号（状态 / 差异各一个）：只有各自最后一次请求的结果落地。
    /// **不能共用一个**——共用时切一次文件就会把还在路上的状态刷新结果丢掉，面板卡在 loading。
    private var statusToken = 0
    private var diffToken = 0
    /// 记下最近一次的根目录（选文件时不必再由视图传一遍）。
    private var rootPath: String?

    /// 换工作区 / 点刷新 / 页签出现时都走它。
    func refresh(root: String?) {
        rootPath = root
        statusToken += 1
        let current = statusToken
        isRefreshing = true
        state = .loading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = GitWorktreeProbe.loadStatus(root: root)
            DispatchQueue.main.async {
                guard let self, current == self.statusToken else { return }
                self.isRefreshing = false
                switch result {
                case .success(let status):
                    self.state = .ready(status)
                    // 选中的文件如果已经不在改动清单里（被提交 / 被还原）⇒ 撤掉右侧，
                    // 否则会一直画着一份「盘上已经不存在的差异」。
                    if let selection = self.selection,
                       !status.entries.contains(where: { $0.id == selection.id }) {
                        self.selection = nil
                        self.diff = nil
                        self.diffFailure = nil
                    } else if let selection = self.selection {
                        self.loadDiff(entry: selection, staged: self.diffIsStaged)
                    }
                case .failure(let failure):
                    self.state = .failed(failure)
                    self.selection = nil
                    self.diff = nil
                    self.diffFailure = nil
                }
            }
        }
    }

    /// 选一个文件（同一个文件再点一次 = 不做事，不重新跑 git）。
    func select(_ entry: GitWorktreeEntry?) {
        guard entry?.id != selection?.id else { return }
        selection = entry
        diff = nil
        diffFailure = nil
        guard let entry else { return }
        // 两侧都有改动时**先给工作区那一侧**：用户刚改完的东西通常还没暂存。
        let staged = entry.isUnstaged ? false : true
        loadDiff(entry: entry, staged: staged)
    }

    /// 重读右侧（切「暂存 / 未暂存」也走它 —— 两档是同一个文件的两种看法）。
    func loadDiff(entry: GitWorktreeEntry, staged: Bool) {
        guard let root = rootPath else { return }
        diffToken += 1
        let current = diffToken
        diffIsStaged = staged
        diff = nil
        diffFailure = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = GitWorktreeProbe.loadDiff(root: root, entry: entry, staged: staged)
            DispatchQueue.main.async {
                guard let self, current == self.diffToken else { return }
                switch result {
                case .success(let document):
                    self.diff = document
                case .failure(let failure):
                    self.diffFailure = failure
                }
            }
        }
    }
}
