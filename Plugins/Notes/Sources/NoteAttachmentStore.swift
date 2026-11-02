import Foundation

/// **附件落盘**（`FR-NTS-NOTE-ATTACH-001`）—— 二进制留在文件系统，库里只存路径。
///
/// 判据要的三件事，逐条对应到这一层的形状：
///   · ① 「图片可缩放但不改写原文件」：这里只有**一次字节拷贝**（`FileManager.copyItem`），
///     **没有**解码 / 重编码 / 缩图 —— 拷贝之后源文件与目标文件逐字节相同（判据用 sha256 对）；
///     界面上的缩放只是显示层的 frame，读的仍是这份原文件。
///   · ② 「附件缺失时明确提示『文件不在了』」：`isMissing(_:)` 是**唯一**的判定处，
///     界面按它把那一行画成缺失态并给一句人话（不静默跳过、不假装有）。
///   · ③ 「删除笔记不会静默删掉附件」：删笔记这一层**一个文件都不删**（`NoteLibrary.delete` 只落墓碑 +
///     删索引行，见那边注释）；要删文件必须**另行**调 `deleteFiles(_:)`—— 那一条路由界面上的第二次确认
///     触发（`AppState.confirmNoteRemoval()` 收尾那一段）。
///
/// 为什么按 `noteID` 分目录：一条笔记的附件自成一组，删文件 / 清空一条笔记时不至于把别人的文件卷进来
/// （`L-50` 那一族教训：范围说不清的动作早晚删错东西）。文件名前加 `uuid-` 前缀是为了同名文件并存时
/// 不互相覆盖 —— 覆盖一次就等于**静默丢掉**一张原图。
public struct NoteAttachmentStore: Sendable {

    /// 落盘失败（机器可读；界面文案由语言表按类别组织，这一层不产文案）。
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// 源文件不在了（拖进来的临时文件被系统清掉、外接盘拔了）。
        case sourceMissing(String)
        /// 拷贝之后字节数对不上 —— 宁可报失败，不留半份文件。
        case copyMismatch(expected: Int64, copied: Int64)
        /// 目标目录建不出来（权限 / 磁盘满）。
        case destinationUnavailable(String)

        public var description: String {
            switch self {
            case .sourceMissing(let path): return "attachment source missing: \(path)"
            case .copyMismatch(let expected, let copied): return "attachment copy mismatch: \(copied) != \(expected)"
            case .destinationUnavailable(let reason): return "attachment destination unavailable: \(reason)"
            }
        }
    }

    /// 附件根目录（`<笔记数据家>/attachments`）。
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 默认根目录：与库文件**同一个数据家**（`NoteDatabase.defaultDirectory`）——
    /// 备份 / 迁移 / 卸载清理只需要认一个目录。
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(root: NoteDatabase.defaultDirectory(environment: environment)
            .appendingPathComponent("attachments", isDirectory: true))
    }

    /// 一条笔记的附件目录。
    public func directory(for noteID: UUID) -> URL {
        root.appendingPathComponent(noteID.uuidString, isDirectory: true)
    }

    /// 目标路径（文件名 = `<附件 uuid>-<原文件名>`；原文件名只取最后一段，不带路径）。
    public func destination(for noteID: UUID, fileName: String, id: UUID) -> URL {
        let safeName = (fileName as NSString).lastPathComponent
        let name = safeName.isEmpty ? "attachment" : safeName
        return directory(for: noteID).appendingPathComponent("\(id.uuidString)-\(name)", isDirectory: false)
    }

    /// **把一份文件收进来**（字节拷贝，不改内容）。
    ///
    /// - Returns: 索引行要的那一条（路径是**绝对路径**；相对路径在换机器 / 换数据家之后会指错地方）。
    /// - Throws: `sourceMissing` / `copyMismatch` / `destinationUnavailable`。
    public func importFile(
        at source: URL,
        noteID: UUID,
        id: UUID = UUID(),
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> NoteAttachment {
        guard fileManager.fileExists(atPath: source.path) else {
            throw Failure.sourceMissing(source.path)
        }
        let target = destination(for: noteID, fileName: source.lastPathComponent, id: id)
        do {
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            throw Failure.destinationUnavailable(String(describing: error))
        }
        // 目标已存在 ⇒ **不覆盖**（同一个附件 id 重复导入是程序错误，不是「顺手覆盖」的理由）。
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        do {
            try fileManager.copyItem(at: source, to: target)
        } catch {
            throw Failure.destinationUnavailable(String(describing: error))
        }
        let expected = byteCount(of: source, fileManager: fileManager)
        let copied = byteCount(of: target, fileManager: fileManager)
        guard expected == copied else {
            try? fileManager.removeItem(at: target)
            throw Failure.copyMismatch(expected: expected, copied: copied)
        }
        return NoteAttachment(id: id, path: target.path, byteCount: copied, addedAt: now)
    }

    /// 文件还在不在（判据②的**唯一判定处**）。
    public func isMissing(_ attachment: NoteAttachment, fileManager: FileManager = .default) -> Bool {
        !fileManager.fileExists(atPath: attachment.path)
    }

    /// 一组附件里已经不在的那些（界面按这个数说「N 个文件不在了」）。
    public func missing(
        in attachments: [NoteAttachment], fileManager: FileManager = .default
    ) -> [NoteAttachment] {
        attachments.filter { isMissing($0, fileManager: fileManager) }
    }

    /// **真的删文件**（判据③：只有人另行确认之后才走这一条）。
    ///
    /// - Returns: 真的删掉了几个文件（不在了的**不算删掉**—— 如实报数，不把「本来就没有」算成「删了」）。
    @discardableResult
    public func deleteFiles(
        _ attachments: [NoteAttachment], fileManager: FileManager = .default
    ) throws -> Int {
        var removed = 0
        for attachment in attachments where fileManager.fileExists(atPath: attachment.path) {
            try fileManager.removeItem(at: URL(fileURLWithPath: attachment.path))
            removed += 1
            // 目录空了就顺手收掉（`<noteID>/` 是这条笔记自己的分组，不删会留一堆空壳目录）。
            let directory = URL(fileURLWithPath: attachment.path).deletingLastPathComponent()
            if let rest = try? fileManager.contentsOfDirectory(atPath: directory.path), rest.isEmpty {
                try? fileManager.removeItem(at: directory)
            }
        }
        return removed
    }

    private func byteCount(of url: URL, fileManager: FileManager) -> Int64 {
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }
}
