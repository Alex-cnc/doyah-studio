import AppKit
import DoyahCore
import SwiftUI

/// 工具栏「任务」菜单的 **AppKit 渲染路径**（`FR-STD-DB-TASK-001` 的交付面）。
///
/// ## 为什么不继续用 SwiftUI `Menu`
///
/// 与 `PanelIconButton` / `ObjectTreeAppKitMenu` 同一条实测理由：离屏宿主里 SwiftUI `Menu`
/// 只是画出来的一枚标签，**不落** `NSButton` / `NSPopUpButton`，无障碍树也不构建 ⇒
/// 「菜单里有哪几项、点下去发生什么」在自动化里**一次都量不到**，只能靠人点。
/// 而这条需求剩下的那一格恰恰就是「点没点过」。
///
/// 换成真 `NSButton` + 真 `NSMenu` 之后，探针拿到的就是**用户点开的那一份菜单**：
/// `menu.items` 是铺出来的行，`performActionForItem(at:)` 走的是行自己的 `target/action`
/// （不是另开一个入口，也不是把实现里的闭包自己调一遍）。
///
/// ## 菜单内容不许在这里另判一遍
///
/// 有哪些行、每行文案、哪一项能不能点 —— 全部来自 `Core/SQLTaskMenuPlan`。
/// 本文件只做「一份值 → 一份 `NSMenu`」的搬运工；在这里再写一遍 `if tasks.isEmpty`
/// 就是第二个真相，迟早和 Core 那份说不到一块。
@MainActor
enum SQLTaskAppKitMenu {

    /// 「保存」那一项点下去要做什么 —— 由调用方给（工具栏里是「把 sheet 立起来」）。
    /// 呈现方式不进 Core：Core 不知道有没有窗口，也不该知道。
    struct Actions {
        let save: () -> Void
        let load: (SQLTaskMenuPlan.Row) -> Void
        let delete: (SQLTaskMenuPlan.Row) -> Void
        let unbind: () -> Void
    }

    /// 生产那一套动作接线（**工具栏与探针共用这一处**）。
    ///
    /// 「点载入之后切连接 / 切库 / 绑上」「点删掉之后册子里那条真的没了」「点解绑之后页签不再绑着」——
    /// 这三件事此前只写在工具栏视图的闭包里。搬到这里之后，探针点的是同一份动作，
    /// 而工具栏那边只剩一句「保存这一项要把 sheet 立起来」（那是唯一与窗口有关的动作）。
    static func actions(
        appState: AppState,
        tabID: UUID,
        onSave: @escaping () -> Void
    ) -> Actions {
        Actions(
            save: onSave,
            load: { row in
                guard let task = appState.sqlTasks.first(where: { $0.id == row.id }) else { return }
                appState.loadSQLTask(task, into: tabID)
            },
            delete: { row in
                guard let task = appState.sqlTasks.first(where: { $0.id == row.id }) else { return }
                Task { await appState.deleteSQLTask(task) }
            },
            unbind: { appState.unbindSQLTask(from: tabID) }
        )
    }

    static func build(plan: SQLTaskMenuPlan, actions: Actions) -> NSMenu {
        let menu = NSMenu()
        // 菜单要跟着语言走：每次铺之前重设，不靠 `NSMenu` 自己缓存的那份。
        menu.autoenablesItems = false

        let readOnlyText = L(.sqlTaskModeReadOnly)
        let writableText = L(.sqlTaskModeWritable)

        let saveItem = ClosureMenuItem(title: L(.sqlTaskSaveAction)) { actions.save() }
        saveItem.isEnabled = plan.saveEnabled
        menu.addItem(saveItem)

        menu.addItem(.separator())

        if plan.isEmpty {
            // 空态：一句人话，点不动（`isEnabled = false`）—— 灰着的一行比一条空菜单更少让人误会。
            let empty = ClosureMenuItem(title: L(.sqlTaskListEmpty)) {}
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for row in plan.rows {
                menu.addItem(ClosureMenuItem(title: row.label(readOnlyText: readOnlyText, writableText: writableText)) {
                    actions.load(row)
                })
            }

            menu.addItem(.separator())

            let deleteGroup = NSMenu()
            for row in plan.rows {
                deleteGroup.addItem(ClosureMenuItem(title: row.name, isDestructive: true) {
                    actions.delete(row)
                })
            }
            let deleteItem = NSMenuItem(title: L(.commonDelete), action: nil, keyEquivalent: "")
            deleteItem.submenu = deleteGroup
            menu.addItem(deleteItem)
        }

        if let bound = plan.bound {
            menu.addItem(.separator())
            let boundItem = ClosureMenuItem(title: L(.sqlTaskBoundTo, bound.name)) {}
            boundItem.isEnabled = false
            menu.addItem(boundItem)
            menu.addItem(ClosureMenuItem(title: L(.sqlTaskUnbind)) { actions.unbind() })
        }

        return menu
    }
}

/// 工具栏上那枚「任务」按钮 —— 真 `NSButton`，点一下弹出**同一份** AppKit 菜单。
///
/// 图标沿用原先 SwiftUI 那一版的 `checklist`，无边框、次要色、只画图标（与
/// `PanelIconButton` 同一套外观口径）；提示同时挂 `toolTip` 与无障碍标签。
///
/// 菜单在**点击时**铺（`menuProvider`），不是初始化时 —— 菜单内容跟着 `AppState` 变
/// （存一条、删一条、绑一条），初始化时铺好的那份点开就是旧账。
struct SQLTaskMenuButton: NSViewRepresentable {

    var pointSize: CGFloat = 11
    let help: String
    let menuProvider: () -> NSMenu

    func makeCoordinator() -> Coordinator {
        Coordinator(menuProvider: menuProvider)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.popMenu)
        button.setAccessibilityRole(.button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.menuProvider = menuProvider
        button.image = NSImage(
            systemSymbolName: "checklist",
            accessibilityDescription: help
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        button.toolTip = help
        button.setAccessibilityLabel(help)
    }

    final class Coordinator: NSObject {
        var menuProvider: () -> NSMenu

        init(menuProvider: @escaping () -> NSMenu) {
            self.menuProvider = menuProvider
        }

        /// 用户点一下：菜单贴着按钮下沿弹出来（与 SwiftUI `Menu` 同一落点）。
        @objc func popMenu(_ sender: NSButton) {
            let menu = menuProvider()
            let origin = NSPoint(x: 0, y: sender.bounds.height + 2)
            menu.popUp(positioning: nil, at: origin, in: sender)
        }

        /// 探针用：拿到**这一下会弹出来的那份菜单**，不必真弹（弹出是模态的，
        /// 无人值守的机器上不该弹窗 —— 与执行回执那枚导出按钮同一条边界）。
        func currentMenu() -> NSMenu {
            menuProvider()
        }
    }
}
