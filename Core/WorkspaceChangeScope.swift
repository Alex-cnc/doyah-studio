import Foundation

/// 工作区外部改动 → **该重列哪些目录**（2026-10-27 人类主人拍板：
/// 「只用加载被修的节点就行」）。
///
/// 为什么单独抽出来：这是「懒加载文件树 + FSEvents」之间唯一需要判断的地方，
/// 写在视图/Store 里就没法用纯逻辑判据盯住。规则只有三条：
/// 1. **只认工作区根之内的路径**（根之外的正文件另有单点监听）；
/// 2. 一个变化的文件 → 只重列它的**父目录**（文件本身不需要「加载」）；
/// 3. 父目录**没被展开就不必取**（看不见的东西，取了也没人画）——
///    根目录（相对路径 `""`）永远算可见。
///
/// 反例（都不许）：整树 `adopt` 重来（展开状态会被清空、树会塌）、
/// 把变化路径本身当目录去列（拿到的是文件的内容列表，错的）、
/// 因为 `.git/` 里的一次写入就把整棵树重列。
public enum WorkspaceChangeScope {

    /// FSEvents 里不值得触发文件树重列的目录名（编译产物与版本库内部状态）。
    /// 说明：这些目录里的写入几乎每次编译/提交都会发生，重列也看不到任何用户可读的变化。
    public static let ignoredDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", ".build", ".build-cache", "node_modules", "dist", ".swiftpm"
    ]

    /// 给定一批变化路径，返回**需要重列的目录**（相对工作区根；根目录是空串）。
    ///
    /// - Parameters:
    ///   - changedPaths: FSEvents 报上来的绝对路径（可能含目录本身、也可能含根之外的路径）。
    ///   - rootPath: 工作区根的绝对路径。
    ///   - expandedPaths: 当前展开的目录（相对路径集合）。
    ///   - ignoredNames: 忽略的目录名；路径里**任何一层**命中即忽略。
    /// - Returns: 去重后的相对目录路径，稳定排序（便于判据与日志）。
    public static func directoriesToReload(
        changedPaths: [String],
        rootPath: String,
        expandedPaths: Set<String>,
        ignoredNames: Set<String> = ignoredDirectoryNames
    ) -> [String] {
        let root = normalize(rootPath)
        guard !root.isEmpty else { return [] }
        let prefix = root + "/"

        var relatives = Set<String>()
        for raw in changedPaths {
            let path = normalize(raw)
            guard path == root || path.hasPrefix(prefix) else { continue }

            // 相对路径的组成部分：变化路径本身是不是被忽略的目录（如 xxx/.git/index）
            let relative = path == root ? "" : String(path.dropFirst(prefix.count))
            let components = relative.split(separator: "/").map(String.init)
            if components.contains(where: { ignoredNames.contains($0) }) { continue }

            // 变化的若是目录本身，重列它的**父**（它的内容会随父级列表一起变）；
            // 若是文件，父目录就是目录。两种情况同一个算法：去掉最后一段。
            let parent = components.dropLast().joined(separator: "/")
            // 根的直接子项（含根自身的变化）⇒ 父目录 = 根 ""
            if parent.isEmpty {
                relatives.insert("")
            } else if expandedPaths.contains(parent) {
                relatives.insert(parent)
            }
            // 没展开的父目录 ⇒ 不取（看不见，懒加载的应有之义）
        }
        return relatives.sorted()
    }

    /// 去掉重复斜杠与结尾斜杠，其余原样（不做符号链接解析：FSEvents 给的就是解析后的路径）。
    private static func normalize(_ path: String) -> String {
        var value = path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
