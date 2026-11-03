import Foundation

/// **磁盘改动 → 界面两处落地**（`FR-STD-WS-FS-009` 的唯一接线点）。
///
/// ## 为什么单独一个类型
///
/// 监听那一半（`AppState.startWorkspaceWatching` + `WorkspaceFileWatcher`）只回答一件事：
/// **哪些路径变了**。变了之后有两个消费者，而**两个都不是 `AppState` 自己的东西**：
///
///   · 左侧文件树 —— `WorkspaceStore`（只重列被改目录，`reloadDirectories`）；
///   · 编辑器里的文件页签 —— `WorkspaceTabsModel`（干净页签按盘上重载，脏页签只记标记）。
///
/// 2026-11-03 之前这两句写在 `AppState.handleDiskChanges` 里，而那时候：
///   · 刷树那句直接打 `WorkspaceStore.shared` —— **藏起来的全局**，判据给不了它根目录，
///     于是「FSEvents ⇒ 树重列」这条链路从来没有一条判据真的走过；
///   · 页签那句遍历的是 `AppState.tabs` —— 那是**数据库的 SQL 页签**（只有 `QueryWorkspaceView`
///     渲染它）。工作区编辑器渲染的是 `WorkspaceTabsModel`，它压根不在那条路上，
///     而且它自己**根本没有「按盘上重载」这个方法**。真机上看到的就是：
///     外部改了文件，编辑器正文一动不动，连脏页签的提示都没有。
///
/// 收成「一个函数 + 两个注入参数」之后：生产宿主（`DoyahStudioApp`）在这里接一次；
/// 判据（`TestsUISnapshot/WorkspaceExternalChangeProbeTests`）用临时工作区把**同一条链路**
/// 跑通 —— 不再需要碰主人的书签，也不再有一句 `WorkspaceStore.shared` 藏在 AppState 里。
///
/// ## 边界（如实登记）
///
/// 只接「工作区根之内」的路径 —— 根之外的单文件监听（`watch(file:)`）走同一条回调，
/// 树那边 `WorkspaceChangeScope` 会把根外的路径筛掉，页签那边本来就按绝对路径比，不冲突。
@MainActor
enum WorkspaceDiskChangeWiring {

    /// 把一个监听接到「树 + 文件页签」上。
    ///
    /// 幂等：重复调用只是换了一份闭包，不会多挂一条 FSEvents 流（流归 `AppState`）。
    static func attach(
        appState: AppState,
        store: WorkspaceStore,
        tabs: WorkspaceTabsModel
    ) {
        appState.onWorkspaceDiskChanges = { [weak store, weak tabs] paths in
            // 树：只重列被改目录（不整树重来 —— 整树会清掉展开状态，树会塌）。
            store?.reloadDirectories(forChangedPaths: paths)
            // 页签：干净的重载，脏的只记标记（`WorkspaceTabsModel.reloadFromDisk`）。
            tabs?.reloadFromDisk(changedPaths: paths)
        }
    }
}
