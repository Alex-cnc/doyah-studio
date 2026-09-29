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
    var onRightClick: ((NSEvent) -> Void)?
    /// 取证用（只在 `DOYAH_TREE_RIGHTCLICK_DEBUG=1` 时写日志）。
    var debugTag: String = "?"

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 只接右键；其余一律放行（返回 nil ⇒ AppKit 继续在下面的兄弟视图里找）。
        NSApp.currentEvent?.type == .rightMouseDown ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        // 取证：距上一次右键，这一批行一共重算了几次 `body`
        // （优化前 ≈ 行数（几十次）；优化后 ≈ 真的变了的那一两行）。
        let evaluations = ObjectTreeRowContent.bodyEvaluations
        ObjectTreeRowContent.bodyEvaluations = 0
        ObjectTreeRightClickLog.append("catcher 命中 tag=\(debugTag)｜距上次右键，行 body 重算 \(evaluations) 次")
        onRightClick?(event)
        // 沿视图链往上找菜单：SwiftUI 的 `.contextMenu` 挂在"这一行"上 ⇒ 菜单必然对得上这一行。
        super.rightMouseDown(with: event)
    }
}

/// 挂在**每一行**上的右键捕获器（`overlay`，且只在右键时参与命中）。
struct RowRightClickCatcher: NSViewRepresentable {
    let tag: String
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> RowRightClickCatcherView {
        let view = RowRightClickCatcherView()
        view.debugTag = tag
        view.onRightClick = { _ in onRightClick() }
        return view
    }

    func updateNSView(_ nsView: RowRightClickCatcherView, context: Context) {
        nsView.debugTag = tag
        nsView.onRightClick = { _ in onRightClick() }
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
