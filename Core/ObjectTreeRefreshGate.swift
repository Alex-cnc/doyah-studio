import Foundation

/// 对象树刷新的**键**：连接 + 元数据版本（`ObjectTreeView` 的 `.task(id:)` 用的就是这两项）。
///
/// 单独抽出来是因为它现在有**两个**用处：视图拿它决定「什么时候重新加载」，
/// 闸门（`ObjectTreeRefreshGate`）拿它判定「这两次算不算同一次刷新」——
/// 两处各写一份（一边 `Hashable` 结构体、一边拼字符串）迟早对不上。
public struct ObjectTreeRefreshKey: Hashable, Sendable {
    public let connectionID: UUID?
    public let revision: Int

    public init(connectionID: UUID?, revision: Int) {
        self.connectionID = connectionID
        self.revision = revision
    }
}

/// 「**同一次刷新只许有一次在途**」——同一把键之下，第二发不再各自取一次数，而是**并到第一发上**。
///
/// ## 为什么要有它（队列 `L-96`）
///
/// 对象树的根节点刷新有**三个**入口：`.task(id:)`（连接变化 / 元数据版本变化 / **视图重新出现**）、
/// 工具条上的刷新按钮、失败态里的重试按钮。它们之间原先**没有任何约束**：谁先到谁先取数，
/// 两个入口几乎同时到就是**两次取数**（两次建库权限探测 + 两次根节点查询），
/// 而两次的结果谁后落地谁说了算 —— 界面上看到的是哪一份要碰运气。
///
/// 实测（2026-09-29 第 106 轮，真库 + 活宿主）：让子树**消失再出现**（同一连接、同一 revision，
/// 键一字不变），`.task(id:)` 会**再跑一遍**、再取一次数 —— 同一把键下的重入是**真实存在**的。
///
/// ## 语义
///
/// · 第一发：照常取数，但**跑在这一发自己的任务里**（不是调用方的任务里）——
///   视图被销毁重建时 `.task` 会取消上一发，而已经发出去的那一发对**眼前这份数据仍然有用**
///   （正是它要给并上来的那个新实例用）；调用方随后靠 `Task.isCancelled` 自己判断要不要写状态；
/// · 第二发（同键、第一发还在途）：**挂起等第一发的结果**，不再取数；
/// · 第一发结束（成功 / 失败）⇒ 等着的都拿到同一份结果 / 同一个错，闸门**当场释放**；
/// · 不同键互不影响（换连接之后那一发不被上一发挡住）；
/// · 释放之后同一把键可以再来（**不许**把一次刷新变成永久封印）。
///
/// 计数（`loadStats`）只给判据用：它数的是「真的取了几次数 / 并了几次」，不是业务状态。
@MainActor
public final class ObjectTreeRefreshGate {

    /// 在途键 → 这一发的任务（谁在等都拿它）。
    private var inFlight: [ObjectTreeRefreshKey: Task<[DatabaseObject], Error>] = [:]
    private var started = 0
    private var joined = 0

    public init() {}

    /// 取根节点：同键在途就并上去，否则自己取一发。
    ///
    /// `load` 由调用方给（生产路径 = `AppState.loadMetadataRoot()`）—— 闸门不认识数据库，
    /// 也就不会在判据里变成第二份「取数口径」。
    public func roots(
        for key: ObjectTreeRefreshKey,
        load: @escaping () async throws -> [DatabaseObject]
    ) async throws -> [DatabaseObject] {
        if let existing = inFlight[key] {
            joined += 1
            return try await existing.value
        }

        // 第一发：登记「这一键在途」，再发出去。
        // `Task { }` 在这里**继承主 actor**（闸门是 `@MainActor`）⇒ 里面的 `load()` 仍在主 actor 上跑，
        // 视图状态不会被别的 executor 碰。
        started += 1
        let task = Task { try await load() }
        inFlight[key] = task
        // 收尾**挂在这一发自己身上**：第一发的调用方被取消 / 提前退出，都不影响这里把键摘掉。
        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// 还在途的键数（判据用；正常情况下收尾之后必须是 0）。
    public var inFlightCount: Int { inFlight.count }

    /// 真的取了几发数 / 并了几次（判据用）。
    public var loadStats: (started: Int, joined: Int) { (started, joined) }
}
