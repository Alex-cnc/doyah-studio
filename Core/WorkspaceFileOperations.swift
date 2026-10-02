import Foundation

/// 工作区里的**文件操作**（`FR-EDIT-41` / 队列 `L-114`）：新建文件 / 新建文件夹 / 重命名 / 删除。
///
/// 四条纪律（形态由需求提出者 2026-09-30 定；2026-10-02 追加「这几个问题都是 alpha2 版本冻结的，
/// 必须在 alpha2 中有」）：
///   ① **只许工作区内** —— 目标路径与「重命名后的路径」都要过 `WorkspaceTree.isContained`，
///      而且**先解符号链接再判**（`isContained` 比的是字符串路径，跟着链接走出去那一步它拦不住）；
///   ② **失败如实报** —— 名字非法 / 撞名 / 越界 / 系统错误四类都给结构化原因，界面照它说话，不静默；
///   ③ **删除走废纸篓**（`trashItem`）—— 「可撤销」这一条唯一的真保障，不做 `removeItem`；
///   ④ **展示文案不进 Core** —— 默认名（中文「未命名」/ 英文 `Untitled`）由调用方从语言表给，
///      这里只管「取一个不撞名的」。
public enum WorkspaceFileOperations {

    /// 失败的四类。每一条都对应界面上**不同的一句话**（Core 只给结构，句子在语言表里）。
    public enum Failure: Error, Equatable {
        /// 越界：不在工作区内（含符号链接指到工作区外）。
        case notContained
        /// 名字是空的（或只有空白）。
        case emptyName
        /// 名字非法：含 `/` 或 `:`（macOS 上 `:` 是路径分隔符的另一种写法）、是 `.` / `..`、
        /// 或首尾带空白（不替用户猜要不要去掉）。
        case illegalName(String)
        /// 已经有一个同名的东西了。
        case alreadyExists(String)
        /// 要往里建东西的那个路径不是目录。
        case notADirectory(String)
        /// 工作区根自己不能删（结构上挡一层）。
        case rootNotDeletable
        /// 系统给的真实原因（权限 / 文件系统 / 只读卷…）。
        case system(String)
    }

    /// 删除前那句「将删几项」的读数。
    ///
    /// `truncated = true` 表示数到上限就停了 —— 界面照实写「N 项以上」，
    /// 而不是为了说一句话去把十万条目录递归读完。
    public struct DeletionSummary: Equatable {
        public let items: Int
        public let truncated: Bool

        public init(items: Int, truncated: Bool) {
            self.items = items
            self.truncated = truncated
        }
    }

    /// 数到多少就停（含目录自身）。
    public static let deletionCountLimit = 500

    // MARK: - 名字

    /// 名字校验（纯函数，判据只钉它）。
    public static func validate(name raw: String) -> Failure? {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyName }
        if raw == "." || raw == ".." { return .illegalName(raw) }
        if raw.hasPrefix(" ") || raw.hasSuffix(" ") || raw.hasPrefix("\t") || raw.hasSuffix("\t") {
            return .illegalName(raw)
        }
        if raw.contains("/") || raw.contains(":") { return .illegalName(raw) }
        return nil
    }

    /// 「取一个不撞名的」：`base` / `base 2` / `base 3` …（带扩展名时 = `base.txt` / `base 2.txt`）。
    public static func uniqueName(base: String, fileExtension: String?, in directoryURL: URL) -> String {
        func composed(_ index: Int) -> String {
            let stem = index <= 1 ? base : "\(base) \(index)"
            guard let fileExtension, !fileExtension.isEmpty else { return stem }
            return "\(stem).\(fileExtension)"
        }
        var index = 1
        while index <= 10_000 {
            let candidate = composed(index)
            if !FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(candidate).path) {
                return candidate
            }
            index += 1
        }
        return composed(index)
    }

    // MARK: - 建

    /// 新建空文件（**不覆盖**同名文件 —— 唯一名由 `uniqueName` 给，写的时候再用 `.withoutOverwriting` 兜一层）。
    @discardableResult
    public static func createFile(
        baseName: String,
        fileExtension: String?,
        in directoryURL: URL,
        workspaceURL: URL
    ) throws -> URL {
        try requireDirectory(directoryURL, in: workspaceURL)
        let name = uniqueName(base: baseName, fileExtension: fileExtension, in: directoryURL)
        let target = directoryURL.appendingPathComponent(name)
        try requireContained(target, in: workspaceURL)
        do {
            try Data().write(to: target, options: .withoutOverwriting)
        } catch {
            throw Failure.system(error.localizedDescription)
        }
        return target
    }

    /// 新建文件夹。
    @discardableResult
    public static func createDirectory(
        baseName: String,
        in directoryURL: URL,
        workspaceURL: URL
    ) throws -> URL {
        try requireDirectory(directoryURL, in: workspaceURL)
        let name = uniqueName(base: baseName, fileExtension: nil, in: directoryURL)
        let target = directoryURL.appendingPathComponent(name)
        try requireContained(target, in: workspaceURL)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        } catch {
            throw Failure.system(error.localizedDescription)
        }
        return target
    }

    // MARK: - 改名

    /// 重命名。**同名不改**（返回原 URL，不算失败）—— 那是「点开改名又什么都没改」的正常结局。
    @discardableResult
    public static func rename(_ url: URL, to newName: String, in workspaceURL: URL) throws -> URL {
        try requireContained(url, in: workspaceURL)
        if let failure = validate(name: newName) { throw failure }

        let parent = url.deletingLastPathComponent()
        let target = parent.appendingPathComponent(newName)
        try requireContained(target, in: workspaceURL)
        if target.standardizedFileURL == url.standardizedFileURL { return url }
        if FileManager.default.fileExists(atPath: target.path) { throw Failure.alreadyExists(newName) }

        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            throw Failure.system(error.localizedDescription)
        }
        return target
    }

    // MARK: - 删

    /// 移到废纸篓，返回**废纸篓里那个位置**（判据靠它把测试留下的东西清掉）。
    @discardableResult
    public static func delete(_ url: URL, in workspaceURL: URL) throws -> URL? {
        try requireContained(url, in: workspaceURL)
        if url.standardizedFileURL == workspaceURL.standardizedFileURL { throw Failure.rootNotDeletable }

        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            throw Failure.system(error.localizedDescription)
        }
        return resulting as URL?
    }

    /// 「将删几项」：目录 = 自身 + 递归内容（数到 `deletionCountLimit` 就停并标截断）；文件 = 1。
    public static func deletionSummary(at url: URL) -> DeletionSummary {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return DeletionSummary(items: 0, truncated: false)
        }
        guard isDirectory.boolValue else { return DeletionSummary(items: 1, truncated: false) }

        var items = 1
        if let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case _? in enumerator {
                items += 1
                if items >= deletionCountLimit { return DeletionSummary(items: items, truncated: true) }
            }
        }
        return DeletionSummary(items: items, truncated: false)
    }

    // MARK: - 内部：边界

    /// 只许工作区内：**两遍都要过** —— 字符串路径（挡 `..`）与解开符号链接后的真实路径（挡链接逃逸）。
    private static func requireContained(_ url: URL, in workspaceURL: URL) throws {
        let resolvedTarget = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = workspaceURL.resolvingSymlinksInPath().standardizedFileURL
        guard WorkspaceTree.isContained(resolvedTarget.path, in: resolvedRoot.path),
              WorkspaceTree.isContained(url.standardizedFileURL.path, in: workspaceURL.standardizedFileURL.path)
        else { throw Failure.notContained }
    }

    private static func requireDirectory(_ url: URL, in workspaceURL: URL) throws {
        try requireContained(url, in: workspaceURL)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { throw Failure.notADirectory(url.lastPathComponent) }
    }
}
