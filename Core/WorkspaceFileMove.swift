import Foundation

/// 工作区树上的**拖拽移动**（`FR-STD-WS-FS-003` 的「拖拽移动」那一条）。
///
/// 为什么单独一个类型：拖拽这件事有两半 ——
///   ① **界面先问「这一行接不接」**（拖到一半就要给反馈，不能等落地失败再说）；
///   ② **落到盘上时要真搬**（`WorkspaceFileOperations.move`）。
/// 两半必须用**同一份判定**，否则会出现「显示可以放、松手报错」或「明明能放、界面不接」。
/// 所以几何判定只写在这里一次：`placement` 是**纯路径算术**（不碰盘、不看内容），
/// 界面拿它决定接不接，`WorkspaceFileOperations.move` 拿它决定搬不搬。
///
/// 三条不许含糊的口径：
///   ① **工作区根不能搬**（它不是树上的一个条目，是被搬进去的那个容器）；
///   ② **不能搬进自己里面**（把 `src` 拖到 `src/dist`：搬完 `src` 就没了，盘上的东西会跟着一起消失）；
///   ③ **落在同一层 = 什么都不做**（不是失败，也不是复制一份 —— 拖回原位是手滑，不是意图）。
public enum WorkspaceFileMove {

    /// 拒绝的两档（界面按这一档说一句话，句子在语言表里）。
    public enum Refusal: Equatable, Sendable {
        /// 工作区根不能搬。
        case rootNotMovable
        /// 落点在源条目自己里面（含落在自己身上）。
        case intoOwnSubtree
    }

    /// 一次拖拽的结论。
    public enum Placement: Equatable, Sendable {
        /// 该搬到这个相对路径（`/` 分隔、相对工作区根）。
        case move(to: String)
        /// 同一层：不用动。
        case noop
        /// 不许搬，理由在这一档。
        case refused(Refusal)
    }

    /// 相对路径 ⇒ 路径分量（空 / `nil` / 全是 `..` 都当空：那是根）。
    static func components(_ raw: String) -> [String] {
        guard let normalized = WorkspaceTree.normalizedRelativePath(raw) else { return [] }
        return normalized.split(separator: "/").map(String.init)
    }

    /// 拖拽落点判定（**纯逻辑**，判据只钉它）。
    ///
    /// - Parameters:
    ///   - source: 被拖的那一条的相对路径（`""` = 工作区根）。
    ///   - directory: 松手处那个目录的相对路径（`""` = 工作区根）。
    public static func placement(source: String, into directory: String) -> Placement {
        let sourceComponents = components(source)
        let directoryComponents = components(directory)
        // ① 根不是条目：谁拖它都不接。
        guard let name = sourceComponents.last else { return .refused(.rootNotMovable) }
        // ② 落点 = 自己，或在自己子树里 ⇒ 拒（按**路径分量**比，不按字符串前缀：
        //    `a` 与 `ab` 在字符串前缀下会被判成一家人）。
        if directoryComponents.count >= sourceComponents.count,
           Array(directoryComponents.prefix(sourceComponents.count)) == sourceComponents {
            return .refused(.intoOwnSubtree)
        }
        // ③ 同一层 ⇒ 不用动。
        if directoryComponents.count == sourceComponents.count - 1,
           Array(sourceComponents.prefix(directoryComponents.count)) == directoryComponents {
            return .noop
        }
        return .move(to: (directoryComponents + [name]).joined(separator: "/"))
    }
}
