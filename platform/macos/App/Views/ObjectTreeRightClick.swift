import AppKit
import SwiftUI

/// **每一行自己接鼠标**（右键给菜单、左键给零等待的选中/展开）：不碰任何坐标系 —— AppKit 把事件交给哪一行，那一行就是被点的行。
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
final class RowMouseCatcherView: NSView {
    /// 取证用（只在 `DOYAH_TREE_RIGHTCLICK_DEBUG=1` 时写日志）。
    var debugTag: String = "?"
    /// 单击（以及双击的第一次）→ 选中本行。
    var onSelect: (() -> Void)?
    /// 双击 → 展开本行。
    var onDoubleClick: (() -> Void)?
    /// **本行自己的菜单**（由 SwiftUI 侧注入 `ObjectTreeAppKitMenu.build`）。
    var makeMenu: (() -> NSMenu)?
    /// 行首 chevron 的横向范围（相对行左边）：左键落在这一段里**不拦**
    /// —— 让 SwiftUI 那个按钮自己处理，展开箭头照旧能用。
    var chevronZone: ClosedRange<CGFloat> = 0 ... 0

    /// - 右键：拦下来自己给菜单（见 `menu(for:)`）。
    /// - 左键：**拦下来自己处理单击 / 双击** —— 这是"左键比右键慢"的根因修法：
    ///   SwiftUI 同一行同时挂单击与双击手势时，单击必须等双击判定窗口（~250–300ms）过期才触发；
    ///   AppKit 的 `clickCount` 是原生给的、**零等待**。行首箭头那一段除外（留给 SwiftUI 的按钮）。
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown:
            return self
        case .leftMouseDown where !chevronZone.contains(point.x):
            return self
        default:
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 {
            ObjectTreeRightClickLog.append("左键单击 tag=\(debugTag)｜clickCount=1")
            onSelect?()
        } else if event.clickCount == 2 {
            ObjectTreeRightClickLog.append("左键双击 tag=\(debugTag)｜clickCount=2")
            onDoubleClick?()
        }
    }

    /// **命中视图自己给出菜单**（2026-09-29 修「右键一个表却弹出断开连接那个菜单」）。
    ///
    /// AppKit 弹右键菜单的规则：从命中视图起沿 `superview` 链问 `menu(for:)`，
    /// **第一个返回非 nil 的胜出**。我们是命中视图 ⇒ 只要这里返回本行的菜单，别人就抢不走。
    override func menu(for event: NSEvent) -> NSMenu? {
        let evaluations = ObjectTreeRowContent.bodyEvaluations
        ObjectTreeRowContent.bodyEvaluations = 0
        ObjectTreeRightClickLog.append("右键 tag=\(debugTag)｜距上次右键，行 body 重算 \(evaluations) 次")
        onSelect?()
        return makeMenu?()
    }
}

/// 挂在**每一行**上的鼠标捕获器（`overlay`）：右键给菜单、左键给"零等待"的选中与展开。
struct RowMouseCatcher: NSViewRepresentable {
    let tag: String
    /// 行首 chevron 的横向范围（左键落在这里放行给 SwiftUI 的按钮）。
    let chevronZone: ClosedRange<CGFloat>
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> RowMouseCatcherView {
        let view = RowMouseCatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: RowMouseCatcherView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: RowMouseCatcherView) {
        view.debugTag = tag
        view.chevronZone = chevronZone
        view.onSelect = onSelect
        view.onDoubleClick = onDoubleClick
        view.makeMenu = makeMenu
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
