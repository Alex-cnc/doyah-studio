import AppKit
import DoyahCore

/// 能带闭包的 `NSMenuItem`（AppKit 的标准做法：`target` 是自己、`action` 打到 `fire`）。
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, isDestructive: Bool = false, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: nil, keyEquivalent: "")
        target = self
        action = #selector(fire)
        // 破坏性项的红色走**主题令牌**（`Theme.nsColor(.danger)`），不用 `NSColor.systemRed`：
        // 后者与配色方案无关 —— 换主题时它一个人不变（设计令牌门禁 `check-design-tokens.py` 钉的就是这条）。
        if isDestructive { attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: Theme.nsColor(.danger)]) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}

/// 对象树右键菜单的 **AppKit 渲染路径**。
///
/// ## 为什么必须走 AppKit（2026-09-29 需求提出者实测：「我右键一个表，它弹出断开连接那个菜单」）
///
/// 树住在 `ConnectionListView` 的 sidebar `List` 里。AppKit 弹右键菜单的规则是：从**命中视图**起、
/// 沿 `superview` 链问 `menu(for:)`，**第一个返回非 nil 的胜出**。我们的行捕获器
/// （`RowRightClickCatcherView`）是命中视图，但它原先没实现 `menu(for:)` ⇒ 一路问到侧栏连接行那份
/// 「断开连接」菜单。SwiftUI 的 `.contextMenu` 在这里指望不上：它挂在行容器上，在 `List` 里会被
/// 提升/合并，AppKit 找不到"这一行"的那一份。
///
/// 所以：**命中视图自己给出菜单**。AppKit 一问就有，别人再也抢不走。
///
/// 菜单项的**可用性仍由 Core 的 `ObjectTreeActions.isAvailable` 决定**（与
/// `ObjectTreeContextMenu` 那份 SwiftUI 渲染同一个出处），本文件不另写一套类型判断；
/// 动作也仍走 `AppState.performTreeAction` / `selectTreeObject` 两个现成收口。
@MainActor
enum ObjectTreeAppKitMenu {

    static func build(
        object: DatabaseObject,
        appState: AppState,
        onEdit: ((ConnectionConfig) -> Void)?
    ) -> NSMenu {
        let menu = NSMenu()
        if object.kind == .server {
            appendServerItems(to: menu, appState: appState, onEdit: onEdit)
        } else {
            appendObjectItems(to: menu, object: object, appState: appState)
        }
        // 空菜单比没有菜单更让人困惑（与 SwiftUI 那份同一个口径）。
        if menu.items.isEmpty {
            menu.addItem(ClosureMenuItem(title: L(.treeMenuEmpty)) {})
        }
        return menu
    }

    // MARK: - 表 / 视图 / 列 / 函数 / 序列（FR-META-14）

    private static func appendObjectItems(to menu: NSMenu, object: DatabaseObject, appState: AppState) {
        let kind = object.kind

        // 「新建表」（FR-DDL-03）：入口挂在**数据库 / schema** 节点上。
        if kind == .database || kind == .schema {
            menu.addItem(ClosureMenuItem(title: L(.tableDesignTitle)) {
                appState.createTableTarget = object
            })
            menu.addItem(.separator())
        }

        if ObjectTreeActions.isAvailable(.browseRows, for: kind) {
            menu.addItem(ClosureMenuItem(title: L(.treeActionBrowseRows, ObjectTreeActions.defaultBrowseLimit)) {
                run(.browseRows, on: object, appState: appState)
            })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: L(.treeActionSelectTemplate)) {
                run(.selectTemplate, on: object, appState: appState)
            })
        }

        if ObjectTreeActions.isAvailable(.insertTemplate, for: kind) {
            menu.addItem(ClosureMenuItem(title: L(.treeActionInsertTemplate)) {
                run(.insertTemplate, on: object, appState: appState)
            })
        }

        if ObjectTreeActions.isAvailable(.copyQualifiedName, for: kind) {
            menu.addItem(ClosureMenuItem(title: L(.treeActionCopyQualifiedName)) {
                run(.copyQualifiedName, on: object, appState: appState)
            })
        }

        if ObjectTreeActions.isAvailable(.copyColumnName, for: kind) {
            menu.addItem(ClosureMenuItem(title: L(.treeActionCopyColumnName)) {
                run(.copyColumnName, on: object, appState: appState)
            })
        }

        if ObjectTreeActions.isAvailable(.browseRows, for: kind) {
            menu.addItem(ClosureMenuItem(title: L(.treeActionBrowseWithCondition)) {
                appState.selectTreeObject(object)
                appState.isBrowseRowsCommandPresented = true
            })
        }

        // 合成数据（FR-AI-07）：只对表提供 —— 视图不可写、序列没有列。
        if kind == .table {
            menu.addItem(ClosureMenuItem(title: L(.syntheticGenerate) + "…") {
                appState.selectTreeObject(object)
                appState.isSyntheticCommandPresented = true
            })
        }

        if ObjectTreeActions.isAvailable(.viewDDL, for: kind) {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: L(.treeActionViewDDL)) {
                run(.viewDDL, on: object, appState: appState)
            })
        }

        if ObjectTreeActions.isAvailable(.truncateTable, for: kind) {
            menu.addItem(.separator())
            if kind == .table {
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem(title: L(.tableDesignAlterTitle)) {
                    appState.alterTableTarget = object
                })
            }
            menu.addItem(ClosureMenuItem(title: L(.treeActionTruncate), isDestructive: true) {
                run(.truncateTable, on: object, appState: appState)
            })
        }

        if ObjectTreeActions.isAvailable(.dropTable, for: kind) {
            menu.addItem(ClosureMenuItem(title: L(.treeActionDrop), isDestructive: true) {
                run(.dropTable, on: object, appState: appState)
            })
        }
    }

    // MARK: - 服务器节点（FR-META-11）

    private static func appendServerItems(
        to menu: NSMenu,
        appState: AppState,
        onEdit: ((ConnectionConfig) -> Void)?
    ) {
        let isConnected = appState.isObjectTreeConnected

        let connect = ClosureMenuItem(title: L(.objectTreeMenuConnect)) {
            Task { await appState.connectObjectTree() }
        }
        connect.isEnabled = !isConnected
        menu.addItem(connect)

        let disconnect = ClosureMenuItem(title: L(.objectTreeMenuDisconnect)) {
            Task { await appState.disconnectObjectTree() }
        }
        disconnect.isEnabled = isConnected
        menu.addItem(disconnect)

        menu.addItem(.separator())

        let edit = ClosureMenuItem(title: L(.objectTreeMenuEditConnection)) {
            if let configuration = appState.selectedConnection { onEdit?(configuration) }
        }
        edit.isEnabled = appState.selectedConnection != nil
        menu.addItem(edit)

        menu.addItem(.separator())

        // 库级管理（FR-SESS-05）：目标是「当前正在用的库」。
        let properties = ClosureMenuItem(title: L(.objectTreeMenuDatabaseProperties)) {
            appState.isPropertiesPresented = true
        }
        properties.isEnabled = appState.adminTargetDatabase != nil
        menu.addItem(properties)

        let dropDatabase = ClosureMenuItem(title: L(.objectTreeMenuDropDatabase)) {
            appState.isDropDatabasePresented = true
        }
        dropDatabase.isEnabled = appState.adminTargetDatabase != nil
        menu.addItem(dropDatabase)

        menu.addItem(.separator())

        // 诊断与权限面板（FR-SESS-04 / FR-DIAG-05）；未连接时查询必然失败，故禁用。
        let privileges = ClosureMenuItem(title: L(.objectTreeMenuPrivileges)) {
            appState.isPrivilegePanelPresented = true
        }
        privileges.isEnabled = isConnected
        menu.addItem(privileges)

        let locks = ClosureMenuItem(title: L(.objectTreeMenuLocks)) {
            appState.isLockCommandPresented = true
        }
        locks.isEnabled = isConnected
        menu.addItem(locks)

        // 服务器会话（FR-SESS-01 / 02）。
        let session = ClosureMenuItem(title: L(.sessionTitle) + "…") {
            appState.isSessionCommandPresented = true
        }
        session.isEnabled = isConnected
        menu.addItem(session)

        menu.addItem(.separator())

        // 权限未知（nil）或明确无权限（false）时不呈现入口。
        if appState.canCreateDatabase == true {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: L(.objectTreeMenuCreateDatabase)) {
                appState.isCreateDatabasePresented = true
            })
        }
    }

    private static func run(_ action: ObjectTreeAction, on object: DatabaseObject, appState: AppState) {
        Task { await appState.performTreeAction(action, on: object) }
    }
}
