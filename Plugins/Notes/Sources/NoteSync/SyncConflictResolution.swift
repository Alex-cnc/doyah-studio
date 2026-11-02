import Foundation

// `FR-NTS-NOTE-SYNC-002`：**记录级 LWW 之后，落败那一版怎么被人看见、被人用掉**。
//
// 决胜规则（`SyncCore` 的 `SyncResolution`）回答的是「谁是这一版」；「冲突留两版」回答的是
// 「判负的那版落在哪里」（`CloudConflictCopy`）。**这一条需求剩下的那一半**是：
// 落败版**能打开**、**能另存**、两版都**标来源设备与时间**、合并结果**是新版本可回退**、
// 而「以我这版为准」**必须是人按的**。
//
// 五条判据逐条落在哪里（写在这里，免得下一个人只看见其中三条）：
//   ① 后写者按 `rev` 定为准 —— `SyncResolution.decide`；被覆盖的那版**可打开**（`text(ofPayload:)` /
//      `presentation(of:)`）、**可另存**（`newNotePayload(from:)` → 一条新笔记）；
//   ② 两版都标来源设备与时间 —— `SyncVersionStamp`（`rev` / `updatedAt` / `deviceId`），
//      胜者那一版由 `CloudConflictCopy.winner` 带着（旧状态文件没有 ⇒ 如实 `nil`，不编设备名）；
//   ③ 合并结果是新版本、可回退 —— `keepLosingVersionAsHumanChoice` 产出 `rev = max(胜者, 判负) + 1`
//      的一条**新记录**（不是把旧 `rev` 重发一次，那会与原胜版同 `rev`、又成一个冲突、按一辈子也收敛不了）；
//      它写回库时走 `NoteLibrary.save` ⇒ 自动记一版（`NoteVersion`），回滚走 `NoteLibrary.rollback`；
//   ④ 「以我这版为准」**是人按的** —— 本文件只提供 `…AsHumanChoice` 这一个入口，**自动路径零引用**
//      （`push` / `flush` / 增量下拉只 `recordConflict`，从不裁决、从不销账）；这一点由
//      `Tests/NoteSyncConflictResolutionTests` 的源树判据钉住，不靠注释承诺；
//   ⑤ 删除作墓碑且 `rev` 严格递增、不许被高 `rev` 副本按 LWW 覆盖回来 ——
//      `SyncResolution.tombstone(of:at:)` + `decide` 里的墓碑闸。
//
// 边界（**不在本条范围**）：段落级并集 / CRDT 自动合并不做（能力书 5.1.9 的边界）。

/// 一版的来源与时刻（判据② 要「两版都标」）。
///
/// 为什么是独立类型而不是把 `SyncRecord` 直接扔给界面：界面只需要「哪台设备、什么时候、第几版」，
/// 不需要也不该拿到那版正文的整条记录（正文走 `losingText`，一次只给一份）。
public struct SyncVersionStamp: Equatable, Sendable {
    /// 第几版（`IR-16` 的 `rev`）。
    public var rev: Int
    /// 这一版的时刻。
    public var updatedAt: Date
    /// 出端标识（`IR-16` 的 `device_id`）。`nil` = 这一版没带出端（旧状态文件 / 未装配），**不编**。
    public var deviceId: String?
    /// 这一版是不是墓碑（删除）。
    public var isTombstone: Bool

    public init(rev: Int, updatedAt: Date, deviceId: String?, isTombstone: Bool) {
        self.rev = rev
        self.updatedAt = updatedAt
        self.deviceId = deviceId
        self.isTombstone = isTombstone
    }

    public init(record: SyncRecord) {
        self.init(
            rev: record.rev,
            updatedAt: record.updatedAt,
            deviceId: record.deviceId,
            isTombstone: record.isTombstone
        )
    }

    /// 来源设备**确实知道**吗（`false` 时界面应说「来源不明」，不许拿本机名顶上去）。
    public var hasKnownDevice: Bool {
        guard let deviceId else { return false }
        return !deviceId.isEmpty
    }
}

/// 一条冲突在界面上长什么样（两版并排 + 落败版正文）。
public struct SyncConflictPresentation: Equatable, Sendable {
    /// 笔记的跨端身份。
    public var uid: String
    /// 标题：由落败版正文首行推出（与快速捕获同一条口径），推不出来用调用方给的兜底文案。
    public var title: String
    /// 判负的那一版（留底的这一版）。
    public var losing: SyncVersionStamp
    /// 胜者那一版。`nil` = 旧状态文件里没记胜者整条（界面如实说「来源不明」）。
    public var winner: SyncVersionStamp?
    /// 这条冲突是什么时候记下的。
    public var recordedAt: Date
    /// 落败版原文（**逐字投影**：`NoteBody` 解得出来就解，解不出来原样给）。
    public var losingText: String
    /// 落败版原始快照（另存时按它整份写回去，不经投影 —— 逐字保留）。
    public var losingPayload: String

    public init(
        uid: String,
        title: String,
        losing: SyncVersionStamp,
        winner: SyncVersionStamp?,
        recordedAt: Date,
        losingText: String,
        losingPayload: String
    ) {
        self.uid = uid
        self.title = title
        self.losing = losing
        self.winner = winner
        self.recordedAt = recordedAt
        self.losingText = losingText
        self.losingPayload = losingPayload
    }

    /// 能不能「以我这版为准 / 另存」：判负版是墓碑时没有正文可用（只能看一条删除记录）。
    public var canRestoreLosingVersion: Bool { !losing.isTombstone }

    /// 胜者那一版的 `rev`（读数与界面都用它说「这一版压过了 rev N」）。
    public var winnerRev: Int? { winner?.rev }
}

/// 另存出来的一份正文（标题 + 正文 + 权威源快照）。
public struct SyncConflictNotePayload: Sendable {
    public var title: String
    public var body: String
    /// 落败版原样快照（`NoteBody` JSON）。`nil` = 那一版存的本来就是纯文本。
    public var spans: String?

    public init(title: String, body: String, spans: String?) {
        self.title = title
        self.body = body
        self.spans = spans
    }
}

public enum SyncConflictResolver {

    /// 解析一版快照的**正文投影**（判据① 的「可打开」）。
    ///
    /// 三条口径：
    ///   · `NoteBody` 解得出来 ⇒ 走官方的 `body` 投影（与库里 `note.body` 同一份，不另起一套解析）；
    ///   · 解不出来（纯文本快照 / 别的端存的形状）⇒ **原样返回**，不当成空正文；
    ///   · `payload` 是空串 ⇒ 空串（如实：那一版本来就是空的）。
    public static func text(ofPayload payload: String) -> String {
        guard !payload.isEmpty else { return "" }
        guard let data = payload.data(using: .utf8),
              let body = try? JSONDecoder().decode(NoteBody.self, from: data) else {
            return payload
        }
        return body.body
    }

    /// 标题：正文首个非空行（去首尾空白、压连续空白、超 80 字截断）。
    /// 推不出来（整段空白）⇒ 调用方给的兜底（语言表给「未命名」，Core 不写文案）。
    public static func title(fromText text: String, fallback: String) -> String {
        let line = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .first { !$0.isEmpty } ?? ""
        if line.isEmpty { return fallback }
        return line.count > 80 ? String(line.prefix(80)) : line
    }

    /// 一条冲突的界面面（判据①②）。
    public static func presentation(of copy: CloudConflictCopy, untitledFallback: String) -> SyncConflictPresentation {
        let text = text(ofPayload: copy.losing.payload)
        return SyncConflictPresentation(
            uid: copy.uid,
            title: title(fromText: text, fallback: untitledFallback),
            losing: SyncVersionStamp(record: copy.losing),
            winner: copy.winner.map(SyncVersionStamp.init(record:)),
            recordedAt: copy.at,
            losingText: text,
            losingPayload: copy.losing.payload
        )
    }

    /// **「以我这版为准」——人按的动作**（判据③④）。
    ///
    /// 产出的是一条**新记录**：`rev` 严格大于已知的两版（胜利那版的 `rev`、判负版的 `rev`、
    /// 以及调用方现取的 `currentRevision`），`updatedAt` = 按下这一刻，`deviceId` = 按下的这台。
    /// 于是它不是「把旧 `rev` 再发一次」（那会与原胜版同 `rev` ⇒ 又判一次冲突，两端永远收敛不了），
    /// 而是「我把这一版定为下一版」。
    ///
    /// 为什么名字里带 `AsHumanChoice`：这是判据④ 的机械抓手 —— 自动路径里出现这个名字就是错的，
    /// 源树判据（测试）会点出来。
    ///
    /// - Parameters:
    ///   - copy: 那条冲突副本（判负版原文 + 胜者那一版）。
    ///   - currentRevision: 调用方现取的「这条笔记已经上行到的 `rev`」（库/状态可能比副本记的更新）。
    ///   - deviceId: 按下这一下的设备标识。
    ///   - at: 按下这一刻。
    public static func keepLosingVersionAsHumanChoice(
        _ copy: CloudConflictCopy,
        currentRevision: Int? = nil,
        deviceId: String,
        at: Date
    ) -> SyncRecord {
        let highest = max(copy.winnerRev, max(copy.losing.rev, currentRevision ?? 0))
        let newRev = highest + 1
        // 判负版本身是墓碑（另一端删了、这一版还是旧的活版本）⇒ 保留「删」这个事实，
        // 只把它的 `rev` 抬上去；否则按「以我这版为准」恢复成活版本。
        let deletedAt = copy.losing.isTombstone ? at : nil
        return SyncRecord(
            uid: copy.uid,
            rev: newRev,
            updatedAt: at,
            deletedAt: deletedAt,
            deviceId: deviceId,
            payload: copy.losing.payload
        )
    }

    /// **另存**（判据①）：把落败版原样写成一份新的正文（新笔记由调用方按 `NoteLibrary.save` 落库）。
    ///
    /// `spans` 只在原快照**确实**是 `NoteBody` 时给 —— 给的是一份**原样快照**（不是重新投影的产物），
    /// 于是另存出来的笔记与落败那版逐字相同；不是 `NoteBody` 的（纯文本）就退回正文，不伪造富文本。
    public static func newNotePayload(from copy: CloudConflictCopy, untitledFallback: String) -> SyncConflictNotePayload {
        let payload = copy.losing.payload
        var spans: String?
        if let data = payload.data(using: .utf8),
           (try? JSONDecoder().decode(NoteBody.self, from: data)) != nil {
            spans = payload
        }
        let text = text(ofPayload: payload)
        return SyncConflictNotePayload(
            title: title(fromText: text, fallback: untitledFallback),
            body: text,
            spans: spans
        )
    }

    /// 另存时的来源（判据① 的「这条是怎么来的」）：来源种类 = 冲突副本，
    /// 指纹 = 原笔记的 `uid`（半年后能回答「它是从哪条笔记的哪一版另存出来的」）。
    public static func source(for copy: CloudConflictCopy) -> NoteSource {
        NoteSource(kind: .conflictCopy, fingerprint: copy.uid, capturedAt: copy.at)
    }
}
