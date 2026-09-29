import AppKit
import SwiftUI

/// **每一行自己接右键**：不碰任何坐标系 —— AppKit 把事件交给哪一行，那一行就是被点的行。
///
/// 为什么不再用「指针坐标 ↔ 行框」换算（2026-09-29 两轮取证 → 放弃）：
/// ① 第一版把 AppKit 的左下原点当成 SwiftUI 的左上原点 ⇒ 命中永远不成立、且静静地不报错；
/// ② 第二版按屏幕坐标换算能命中了，但**每行都差一行**（需求提出者原话：「每次都选到下面的对象去了」）。
/// 坐标是最容易错、最难自证的中间层 —— 能不要就不要。行的归属本来就该由 AppKit 自己判。
///
/// 两个关键点：
/// - `hitTest` **只认右键**（看 `NSApp.currentEvent`）：左键单击 / 双击 / 拖拽 / 展开箭头一律返回 nil
///   放行给下面的 SwiftUI 视图 —— 现有手势一行都不用改，也不会被挡。
/// - `rightMouseDown` 里先选中本行，再 `super.rightMouseDown(with:)`：AppKit 沿视图链往上找
///   `menu(for:)`，找到的就是**这一行**的 `.contextMenu`（绝对对得上，不用猜）。
final class RowRightClickCatcherView: NSView {
    /// 取证用（只在 `DOYAH_TREE_RIGHTCLICK_DEBUG=1` 时写日志）。
    var debugTag: String = "?"
    /// 右键即选中本行（菜单动作作用于选中项）。
    var onSelect: (() -> Void)?
    /// **本行自己的菜单**（由 SwiftUI 侧注入 `ObjectTreeAppKitMenu.build`）。
    var makeMenu: (() -> NSMenu)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 只接右键；其余一律放行（返回 nil ⇒ AppKit 继续在下面的兄弟视图里找）。
        NSApp.currentEvent?.type == .rightMouseDown ? self : nil
    }

    /// **命中视图自己给出菜单**（2026-09-29 修「右键一个表却弹出断开连接那个菜单」）。
    ///
    /// AppKit 弹右键菜单的规则：从命中视图起沿 `superview` 链问 `menu(for:)`，
    /// **第一个返回非 nil 的胜出**。我们是命中视图 ⇒ 只要这里返回本行的菜单，别人就抢不走
    /// （原先这里没实现 ⇒ 返回 nil ⇒ 一路问到侧栏连接行那份「断开连接」）。
    /// 顺带把"右键即选中"也放在这里 —— 它天然发生在菜单弹出**之前**，菜单动作因此作用于本行。
    override func menu(for event: NSEvent) -> NSMenu? {
        let evaluations = ObjectTreeRowContent.bodyEvaluations
        ObjectTreeRowContent.bodyEvaluations = 0
        ObjectTreeRightClickLog.append("catcher 命中 tag=\(debugTag)｜距上次右键，行 body 重算 \(evaluations) 次")
        onSelect?()
        return makeMenu?()
    }
}

/// 挂在**每一行**上的右键捕获器（`overlay`，且只在右键时参与命中）。
struct RowRightClickCatcher: NSViewRepresentable {
    let tag: String
    let onSelect: () -> Void
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> RowRightClickCatcherView {
        let view = RowRightClickCatcherView()
        view.debugTag = tag
        view.onSelect = onSelect
        view.makeMenu = makeMenu
        return view
    }

    func updateNSView(_ nsView: RowRightClickCatcherView, context: Context) {
        nsView.debugTag = tag
        nsView.onSelect = onSelect
        nsView.makeMenu = makeMenu
    }
}

/// 取证日志：本机没有截图与模拟点击授权，这是唯一能在无界面权限下取证的路径。
enum ObjectTreeRightClickLog {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DOYAH_TREE_RIGHTCLICK_DEBUG"] == "1"
    }

    static func append(_ message: String) {
        guard isEnabled else { return }
        let line = "\(Date()) \(message)\n"
        let path = "/tmp/doyah-tree-rightclick.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
