import Foundation
import DoyahCore

/// 工作区**路径表**的缓存（供行内灰字的路径候选用，`FR-EDIT-57` 的最后一块）。
///
/// ## 为什么要有这一层
///
/// 路径候选要的是"工作区里所有能当路径写的条目"（`PathGhostCompletion.index`），那是**递归读盘**的活。
/// 若在击键那一拍现算，每敲一个字都要扫一遍目录 —— 那就是 `NFR-PERF-05` 那类卡顿，
/// 而且会随着工作区变大越来越慢。所以：
///
///   · **根一变就在后台搭一次**（不阻塞界面，也不占主线程的击键预算）；
///   · 编辑器**立刻拿当前那一份**（第一次可能还是空的 —— 空的只会让"写路径时先不出灰字"，
///     绝不会瞎猜，见 `PathGhostOutcome` 的分工）；
///   · 搭好之后发一条通知，编辑器收到就刷新灰字（灰字是画出来的，晚一拍出现没有任何副作用）。
///
/// ## 为什么带 30 秒过期
///
/// 工作区里的文件是会变的（新建 / 改名 / 别的工具生成）。没有过期就没有新鲜度：用户新加一个文件，
/// 灰字要等他重开工作区才认得。过期后**下一次请求**在后台重搭，期间仍用旧表（旧表最多少几条，
/// 不会给出不存在的路径 —— 那条由 `PathGhostCompletion.candidates` 保证）。
///
/// 口径与 `WorkspaceSearch` / `WorkspaceTree` 一致：忽略构建产物与版本库目录、不跟随符号链接、
/// 深度与条数有界（`PathGhostCompletion.defaultMaxDepth` / `defaultIndexLimit`）。
final class WorkspacePathIndex {

    /// 全工程一份（每个页签各搭一张表是白付的：它们看的是同一个工作区）。
    static let shared = WorkspacePathIndex()

    /// 表更新完成的广播（**主线程**投递）。
    static let didChange = Notification.Name("studio.workspace.pathIndexDidChange")

    /// 过期时间：过了就允许重搭（见类型注释）。
    private let ttl: TimeInterval = 30

    private let queue = DispatchQueue(label: "studio.doyah.workspace.path-index", qos: .utility)

    /// 当前表对应的根（`nil` = 没有工作区）。
    private var root: URL?

    /// 当前可用的表（老的那一份也留着 —— 见类型注释）。
    private(set) var candidates: [WorkspacePathCandidate] = []

    /// 下一代：用来丢弃"赶不上趟"的搭表结果（根连着换了两次时，先完成的那份不能覆盖后一份）。
    private var generation = 0

    /// 下一次允许重搭的时刻。
    private var refreshAfter: Date = .distantFuture

    private init() {}

    /// 每条编辑器刷新前调一次：根变了 / 表过期了就**后台**重搭，本方法立刻返回。
    func ensure(root: URL?) {
        let now = Date()
        guard root != self.root || now >= refreshAfter else { return }
        self.root = root
        generation += 1
        let generation = self.generation
        refreshAfter = now.addingTimeInterval(ttl)

        guard let root else {
            candidates = []
            return
        }
        queue.async { [weak self] in
            let index = PathGhostCompletion.index(in: root)
            // 丢掉过期的结果：根又换了，或者已经搭过更新的一份。
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.candidates = index.candidates
                NotificationCenter.default.post(name: Self.didChange, object: nil)
            }
        }
    }
}
