import Foundation

// 私密保护（需求 `FR-NTS-NOTE-PRIVACY-001`）· **不进搜索 / 不同步 / 不外发 / 看内容要二次验证**。
//
// 需求书 §3.5 该行三条判据（逐条对应到本文件）：
//   ① 私密笔记不出现在检索结果 —— `NotePrivacy.isSearchable` + `NoteDatabase.search` 的 SQL 过滤；
//   ② 私密笔记不外发到 Agent / IM / 导出 —— `canSync` / `canExport` / `canSendToAgent`（三处调用点各判一次）；
//   ③ 取消私密需二次确认 —— `unprivateRequiresConfirmation` + `NotePrivacyChangeOutcome.confirmationRequired`。
//
// 边界（如实写清，不假装覆盖）：**这不是整机加密** —— 它防的是「别人拿到你解锁着的设备随手翻」，
// 防不住能读你磁盘的人（库里正文仍是明文，加密库是另一条更大的活）。需求原文的「不是」列就写着这一条。
public enum NotePrivacy {

    /// 检索（库内 FTS + 子串兜底两条路都算）能不能看见这条。
    public static func isSearchable(_ note: Note) -> Bool { !note.isPrivate }

    /// 能不能上行到云端（「不同步」）。删除墓碑也走这一条：**私密笔记的墓碑同样不上行**
    /// （否则云端会凭墓碑知道「这台机器上曾有这么一条」——那本身就是泄漏）。
    public static func canSync(_ note: Note) -> Bool { !note.isPrivate }

    /// 能不能导出（HTML / Markdown / 备份交付）。
    public static func canExport(_ note: Note) -> Bool { !note.isPrivate }

    /// 能不能发给 Agent / IM（「不外发」的另一半）。
    public static func canSendToAgent(_ note: Note) -> Bool { !note.isPrivate }

    /// **取消私密必须二次确认**（判据③）：标私密是一次普通操作，撤私密不是 ——
    /// 撤错了等于把一条本该藏住的东西放到搜索 / 同步 / 外发的面上，而它不会再自己回来。
    public static let unprivateRequiresConfirmation = true
}

/// 一次私密挡位变更的结果（**机器可读**，文案在界面那一层组织）。
public enum NotePrivacyChangeOutcome: Equatable, Sendable {
    /// 真的改了几行（`0` = 认不出的 id）。
    case changed(Int)
    /// 取消私密但没带二次确认 ⇒ **拒绝执行**（判据③）。
    case confirmationRequired
}

/// 二次验证的口子（真机上走 `LocalAuthentication`；判据里注入一个桩，于是「必须先验证才拿得到内容」
/// 这件事可以被机器证明，而不是靠人点一遍）。
///
/// 为什么要协议而不是闭包：调用点（界面）只认「能不能拿到内容」，
/// 而**内容只有这一条路能拿到** —— 把授权做成参数，任何绕过授权直接 `notes()` 的写法都拿不到私密条目。
public protocol NotePrivacyAuthorizing: Sendable {
    /// 返回 `true` = 验证通过（人按了指纹 / 输了系统密码）。
    func authorize(reason: String) async -> Bool
}

/// 永远拒绝的授权器（**默认值**）：没有注入真授权器时，私密笔记一律打不开。
///
/// 为什么默认是「拒绝」而不是「放行」：这是保护挡位，忘了接线时的安全失败方向必须是「看不见」。
public struct DenyingNotePrivacyAuthorizer: NotePrivacyAuthorizing {
    public init() {}
    public func authorize(reason: String) async -> Bool { false }
}

/// 已经验证过的一条私密笔记（**带内容**）。类型本身就是凭据：拿到它 = 已经过二次验证。
public struct RevealedPrivateNote: Equatable, Sendable {
    public var note: Note
    public var versions: [NoteVersionEntry]

    public init(note: Note, versions: [NoteVersionEntry] = []) {
        self.note = note
        self.versions = versions
    }
}
