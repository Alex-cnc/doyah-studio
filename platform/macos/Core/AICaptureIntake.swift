import Foundation

/// **AI 产物 → 笔记**的**入库判定**（队列 `L-134`；需求依据 = `Q14=A` / DoyahNotes `DR-07`）。
///
/// 为什么单列一层：这条口径从前**散在每个调用点上** —— 界面一处
/// （`AppState.saveDiagnosisNote`）、命令行一处（`doyah diagnose --save-note`），
/// 两处各自算一次「同指纹存过没有」，算完却**都照样存第二份**，只把提示语换个说法。
/// 于是「同一份产物只存一条」这句话在代码里**谁也不负责**：口径要改就得改两遍，
/// 漏一处就变成两种行为（而这正是 `Q14` 收口时查出来的形状）。
///
/// 三条口径（都在本文件里，调用方不再自己判一次）：
///   ① **同指纹默认不重复存**（`Q14=A`）：命中已有那条 ⇒ **不写库**，把**已有那条**交回去，
///      由调用方指给用户看（界面上给一个「打开那条」的入口，命令行打印它的标题）；
///   ② **要副本必须显式**（`--force-new` / 界面上单独一颗按钮）：显式要才存第二份；
///   ③ **没有指纹就没有判重**（如实）：`source.fingerprint == nil` 时按现状存新的一条 ——
///      判重的依据是指纹本身；靠正文相似度去猜「看起来是同一份」比重复存更糟
///      （用户写的两条不同笔记被并成一条是不可逆的）。
public enum AICaptureIntake {

    /// 这一次「存进笔记」到底做了什么。取值是**机器可读的**（命令行 `--json` 直接打它），
    /// 不再靠一句人话文案去反推行为。
    public enum Outcome: String, Equatable, Sendable {
        /// 没有同指纹的旧笔记 ⇒ 新建了一条。
        case saved
        /// 有同指纹、但调用方显式要副本 ⇒ 仍存了一条新的。
        case savedCopy
        /// 有同指纹、也没要副本 ⇒ **一个字节都没写**，交回的是已有那条。
        case reusedExisting
    }

    /// 判定结果（**一次算清**：结论与「指回哪一条」出自同一次计算，不可能互相矛盾）。
    public struct Decision: Equatable, Sendable {
        public let outcome: Outcome
        /// `reusedExisting` 时 = 已有那条（指回它）；其余情况为 `nil`。
        public let existingNote: Note?

        public var didWrite: Bool { outcome != .reusedExisting }
    }

    /// 一次「存进笔记」**实际落在哪一条上**（`receive` 的出口形状）。
    public struct Result: Equatable, Sendable {
        public let note: Note
        public let outcome: Outcome
    }

    /// **判定（纯函数）**：只吃草稿、现有笔记与开关，不碰磁盘、不读时钟 ——
    /// 于是「同指纹两次保存只留一条」可以被直接断言，不必去凑时序。
    ///
    /// - Parameters:
    ///   - draft: 待落库的草稿（判重看 `draft.source.fingerprint`）。
    ///   - existing: 当前库里的全部笔记（调用方刚读出来的那一份）。
    ///   - forceNew: 显式要副本（命令行 `--force-new` / 界面的「再存一份」）。
    public static func decide(draft: NoteDraft, existing: [Note], forceNew: Bool) -> Decision {
        guard let fingerprint = draft.source.fingerprint else {
            // 没有指纹 ⇒ 没有判重依据（口径③）。
            return Decision(outcome: .saved, existingNote: nil)
        }
        guard let reused = earliest(fingerprint: fingerprint, in: existing) else {
            return Decision(outcome: .saved, existingNote: nil)
        }
        return forceNew
            ? Decision(outcome: .savedCopy, existingNote: nil)
            : Decision(outcome: .reusedExisting, existingNote: reused)
    }

    /// 同指纹里**最早**的那条笔记。
    ///
    /// 为什么定「最早」而不是随手挑一条：提示上写「之前存过」却不说是哪一条时，
    /// 用户是按标题去找的 —— 有三条同指纹时指到最后一条，会让人以为第一条被换掉了。
    /// 排序键带上 `id` 是为了**同一份库两次运行给出同一个答案**（创建时间相同时也不漂）。
    public static func earliest(fingerprint: String, in existing: [Note]) -> Note? {
        existing
            .filter { note in note.source.fingerprint == fingerprint }
            .min { left, right in
                if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
                return left.id.uuidString < right.id.uuidString
            }
    }

    /// **落库**（判定 + 写库一起）：AI 产物入笔记**只该走这一个入口**。
    ///
    /// 之所以把「读现有笔记 → 判定 → 写」放在一次调用里，而不是把 `decide` 交给调用方自己拼：
    /// 调用方自己拼就又回到「每个调用点各判一次」的老路上去了 —— 判定与写库之间多一步，
    /// 就多一个漏判的机会（而这一轮修的正是「算了判重、却照样存」）。
    ///
    /// 返回的 `Result` 里那条笔记 = **这次调用真正落在哪一条上**：
    /// `saved` / `savedCopy` 是刚存下的那条，`reusedExisting` 是**已经在那儿**的那条
    /// （调用方据此指给用户看；`note.id` 可以直接拿去跳转）。
    public static func receive(
        _ draft: NoteDraft,
        into library: NoteLibrary,
        forceNew: Bool = false
    ) async throws -> Result {
        let existing = try await library.load()
        let decision = decide(draft: draft, existing: existing, forceNew: forceNew)
        if let reused = decision.existingNote {
            return Result(note: reused, outcome: .reusedExisting)
        }
        let saved = try await library.upsert(draft)
        return Result(note: saved, outcome: decision.outcome)
    }
}
