import SwiftUI
import DoyahCore

/// 对象树的右键菜单（FR-META-14 / FR-META-11）—— **内容**与**作用在哪一行**两件事的住处。
///
/// ## 为什么搬出 `ObjectTreeView.swift`（队列 `L-90` ㈡ 第 2 条 · 开发循环第 110 轮）
///
/// 清单里 `FR-META-14` 那一行的人话是「依次右键：表 / 视图 / 列 / 服务器 / 数据库 / schema / 函数 →
/// ① 每一行弹出来的都是**它自己**的菜单 ② 数据库 / schema 上有「新建表」③ 函数上有「查看 DDL」
/// ④ 列上有「复制列名」」—— 它的主体就是这里这份菜单内容加上 `menuTargetObject` 那个解析。
/// 原来两者都是 `ObjectTreeView` 里的 `private` ⇒ 只能靠人一步步点。
/// 搬出来之后这两件事都能机械判（见 `TestsUISnapshot/ObjectTreeContextMenuProbeTests.swift`）：
/// 菜单内容渲染一次就知道有哪些项、解析拿真行数组喂一次就知道作用在哪一行。
///
/// 生产路径只有一个调用者（`ObjectTreeView` 那一个 `.contextMenu`），**行为与搬出前逐字一致**。
/// 注意本文件**不取数**（不碰 `AppState` 的加载方法、不 import 驱动）：
/// 它只把「哪一行 / 有哪些项」算出来，真正的动作仍由 `AppState` 收口。

/// 右键菜单作用在**哪一行**上 —— 纯函数（无视图状态、无取数能力）。
/// 右键菜单作用在**鼠标底下那一行**上。
///
/// 为什么不是"每行各挂一个"（2026-09-24 实测缺陷）：为了让行距变紧，整棵树现在是**一个 `List` 行**
/// （见 `body` 里那个 `VStack` 的说明）。而 AppKit 的右键菜单是**按 List 行**解析的 ——
/// 一个行里挂若干 `.contextMenu` 时它只会用找到的第一个，于是右键点数据库弹出来的是
/// **服务器**那份菜单（需求提出者实测：「行距调整后，右键点击数据库菜单出错了，
/// 显示的是整个数据库服务器对象的右键菜单」）。
/// 现在整块只挂一个，内容由**悬停行**决定：鼠标在哪一行，菜单就是那一行的 ——
/// 与"每行自己挂"结果等价，但没有歧义。
///
///
/// 为什么需要这个兜底（2026-09-28 需求提出者实测：「点一下鼠标要等一下才能选择对象，
/// 否则马上点右键就会报『这一行没有可用的操作』」）：`onHover` 是**视图级**的悬停状态，
/// 而单击会改 `selectedTreeObject` ⇒ 整棵树重算、行视图被重建 ⇒ SwiftUI 补一个
/// **假的 mouseExited**（指针其实没动），悬停盒子被清空；指针既然没动，新的 mouseEntered
/// 也不会来 —— 盒子就一直是空的，直到用户真的挪一下鼠标。于是"手快"的人（点完立刻右键）
/// 看到的是那张空菜单。
///
/// 两条一起修：① 单击/双击时**顺手把悬停盒子写成被点的那一行**（点击本身就证明指针在它身上）；
/// ② 这里再加一道兜底 —— 盒子空时用「已选中那一行」，因为右键前必然是左键点过它。
/// 兜底只在盒子为空时生效：盒子有值时不抢（否则会退回老毛病「点数据库弹服务器菜单」）。
enum ObjectTreeMenuTarget {

    /// 菜单打开那一刻真正的目标行：**悬停行优先，悬停没命中就退回「刚点中的那一行」**。
    ///
    /// - Parameters:
    ///   - hoveredRowID: 悬停盒子里记的那一行 id（`nil` = 盒子空）。
    ///   - selected: 当前选中对象（兜底用）。
    ///   - rows: 这一次渲染的可见行（与视图用的是同一份摊平结果）。
    static func resolve(
        hoveredRowID: String?,
        selected: DatabaseObject?,
        rows: [ObjectTreeVisibleRow]
    ) -> DatabaseObject? {
        if let hoveredRowID,
           let row = rows.first(where: { $0.object.id == hoveredRowID }),
           !row.isGroupHeader,
           ObjectTreeActions.hasContextMenu(row.object.kind) {
            return row.object
        }
        guard let selected,
              let row = rows.first(where: { $0.object.id == selected.id }),
              !row.isGroupHeader,
              ObjectTreeActions.hasContextMenu(selected.kind) else { return nil }
        return selected
    }
}


enum ObjectTreeContextMenu {

    /// 菜单内容。**生产路径与判据读的是同一个入口**：`ObjectTreeView` 把它交给 `.contextMenu { … }`，
    /// 探针把它装进一个 `VStack` 渲染成图 —— 两边拿到的项**同一份代码算出来**。
    ///
    /// 为什么是「静态 `@ViewBuilder` + 显式 `appState`」而不是一个 `View` 结构体（第 110 轮实测踩到）：
    /// `.contextMenu` 要的是**若干兄弟节点**（Button / Divider），不是一个装好的容器 ——
    /// 把整份内容包成 `VStack` 交给 `.contextMenu`，菜单里就只剩一个空条目。
    /// 所以这里保持「返回兄弟节点」的形状（与搬出 `ObjectTreeView` 之前逐字同形）；
    /// **快照那一侧**才是容器问题：`VStack` / `.padding` 由探针自己加，不写进这里。
    /// 副作用：进入渲染的那块内容里**不再有 `@EnvironmentObject`**，`appState` 由调用方传进来 ——
    /// 判据那边因此不必挂环境对象，也就不存在「判的是另一份状态」。
    @MainActor
    @ViewBuilder
    static func items(
        object: DatabaseObject?,
        appState: AppState,
        onEdit: ((ConnectionConfig) -> Void)? = nil
    ) -> some View {
        menuItems(for: object, appState: appState, onEdit: onEdit)
    }

    /// 右键菜单的内容：作用在**鼠标底下那一行**上；没有可作用对象时给一条说明，
    /// 而不是弹一个空菜单（空菜单比没有菜单更让人困惑）。
    @MainActor
    @ViewBuilder
    private static func menuItems(
        for object: DatabaseObject?,
        appState: AppState,
        onEdit: ((ConnectionConfig) -> Void)?
    ) -> some View {
        if let object {
            if object.kind == .server {
                serverContextMenu(appState: appState, onEdit: onEdit)
            } else {
                objectContextMenu(for: object, appState: appState)
            }
        } else {
            Text(L(.treeMenuEmpty))
        }
    }

    /// 表 / 视图 / 列节点的右键菜单（FR-META-14）。
    ///
    /// 菜单项是否呈现**由 Core 的 `ObjectTreeActions.isAvailable` 决定**，
    /// 不在视图里再写一份类型判断 —— 否则两处规则迟早不一致。
    @MainActor
    @ViewBuilder
    private static func objectContextMenu(for object: DatabaseObject, appState: AppState) -> some View {
        // 「新建表」（FR-DDL-03）：入口挂在**数据库 / schema** 节点上。
        // 它原来嵌在下面"表相关动作"那一块里，而那一块整体被 `truncateTable` 的可用性挡着
        // （只对 `.table` 为真）—— 于是这个按钮**从来没出现过**（2026-09-24 排查右键菜单时抓到）。
        if object.kind == .database || object.kind == .schema {
            Button(L(.tableDesignTitle)) {
                appState.createTableTarget = object
            }

            Divider()
        }

        if ObjectTreeActions.isAvailable(.browseRows, for: object.kind) {
            Button(L(.treeActionBrowseRows, ObjectTreeActions.defaultBrowseLimit)) {
                runTreeAction(.browseRows, on: object, appState: appState)
            }

            Divider()

            Button(L(.treeActionSelectTemplate)) {
                runTreeAction(.selectTemplate, on: object, appState: appState)
            }
        }

        if ObjectTreeActions.isAvailable(.insertTemplate, for: object.kind) {
            Button(L(.treeActionInsertTemplate)) {
                runTreeAction(.insertTemplate, on: object, appState: appState)
            }
        }

        if ObjectTreeActions.isAvailable(.copyQualifiedName, for: object.kind) {
            Button(L(.treeActionCopyQualifiedName)) {
                runTreeAction(.copyQualifiedName, on: object, appState: appState)
            }
        }

        if ObjectTreeActions.isAvailable(.copyColumnName, for: object.kind) {
            Button(L(.treeActionCopyColumnName)) {
                runTreeAction(.copyColumnName, on: object, appState: appState)
            }
        }

        if ObjectTreeActions.isAvailable(.browseRows, for: object.kind) {
            Button(L(.treeActionBrowseWithCondition)) {
                // 先记下目标（面板读的就是它），再开面板 —— 与 ⌘K 那条命令同一个入口。
                appState.selectTreeObject(object)
                appState.isBrowseRowsCommandPresented = true
            }
        }

        // 合成数据（FR-AI-07）：只对表提供 —— 视图不可写，序列没有列。
        if object.kind == .table {
            Button(L(.syntheticGenerate) + "…") {
                appState.selectTreeObject(object)
                appState.isSyntheticCommandPresented = true
            }
        }

        if ObjectTreeActions.isAvailable(.viewDDL, for: object.kind) {
            Divider()

            Button(L(.treeActionViewDDL)) {
                runTreeAction(.viewDDL, on: object, appState: appState)
            }
        }

        if ObjectTreeActions.isAvailable(.truncateTable, for: object.kind) {
            Divider()

            if object.kind == .table {
                Divider()
                Button(L(.tableDesignAlterTitle)) {
                    appState.alterTableTarget = object
                }
            }

            Button(L(.treeActionTruncate), role: .destructive) {
                runTreeAction(.truncateTable, on: object, appState: appState)
            }
        }

        if ObjectTreeActions.isAvailable(.dropTable, for: object.kind) {
            Button(L(.treeActionDrop), role: .destructive) {
                runTreeAction(.dropTable, on: object, appState: appState)
            }
        }
    }

    @MainActor
    private static func runTreeAction(
        _ action: ObjectTreeAction,
        on object: DatabaseObject,
        appState: AppState
    ) {
        Task { await appState.performTreeAction(action, on: object) }
    }

    /// 服务器节点的右键菜单（FR-META-11）。
    ///
    /// 本期只实现「服务器」节点：连接 / 断开 / 编辑连接，以及**依据登录用户权限**
    /// 决定是否呈现「新建数据库」。数据库 / schema / 表等节点的菜单留待后续需求。
    @MainActor
    @ViewBuilder
    private static func serverContextMenu(
        appState: AppState,
        onEdit: ((ConnectionConfig) -> Void)?
    ) -> some View {
        let isConnected = appState.isObjectTreeConnected

        Button(L(.objectTreeMenuConnect)) {
            Task { await appState.connectObjectTree() }
        }
        .disabled(isConnected)

        Button(L(.objectTreeMenuDisconnect)) {
            Task { await appState.disconnectObjectTree() }
        }
        .disabled(!isConnected)

        Divider()

        Button(L(.objectTreeMenuEditConnection)) {
            if let configuration = appState.selectedConnection {
                onEdit?(configuration)
            }
        }
        .disabled(appState.selectedConnection == nil)

        Divider()

        // 库级管理（FR-SESS-05）：目标是「当前正在用的库」，没连库时不呈现入口。
        Button(L(.objectTreeMenuDatabaseProperties)) {
            appState.isPropertiesPresented = true
        }
        .disabled(appState.adminTargetDatabase == nil)

        Button(L(.objectTreeMenuDropDatabase)) {
            appState.isDropDatabasePresented = true
        }
        .disabled(appState.adminTargetDatabase == nil)

        Divider()

        // 诊断与权限面板（FR-SESS-04 / FR-DIAG-05）；未连接时查询必然失败，故禁用。
        Button(L(.objectTreeMenuPrivileges)) {
            appState.isPrivilegePanelPresented = true
        }
        .disabled(!isConnected)

        Button(L(.objectTreeMenuLocks)) {
            appState.isLockCommandPresented = true
        }
        .disabled(!isConnected)

        // 服务器会话（FR-SESS-01 / 02）。这个 builder 本来就是**服务器节点专用菜单**，
        // 所以不需要再判节点类型 —— 会话是整个实例的概念（本轮我先多写了一次判断，编译才发现）。
        Button(L(.sessionTitle) + "…") {
            appState.isSessionCommandPresented = true
        }
        .disabled(!isConnected)

        Divider()

        // 权限未知（nil）或明确无权限（false）时不呈现入口，避免给出必然失败的按钮。
        if appState.canCreateDatabase == true {
            Divider()

            Button(L(.objectTreeMenuCreateDatabase)) {
                appState.isCreateDatabasePresented = true
            }
        }
    }
}

// MARK: - 菜单目标的写入口

extension AppState {
    /// 记下「这次操作针对谁」——**唯一写入口**。
    ///
    /// 右键菜单入口与 ⌘K 命令面板读的是**同一个**字段（`selectedTreeObject`），
    /// 这样「面板开了、对象却是上一个」这种漂移不可能发生。
    /// 树上的单击 / 双击与菜单里那两条入口（按条件浏览 / 合成数据）都走这里 ——
    /// 收口是 `L-90` ㈡ 第 2 条把菜单搬出视图时顺手做的（原来视图里私有 `select` 与菜单各写一份）。
    func selectTreeObject(_ object: DatabaseObject) {
        selectedTreeObject = object
    }
}
