import Foundation

/// 对象树**根节点**加载失败之后，还要不要再自己试一次 —— 同一把刷新键下的自动取数预算。
///
/// ## 由头（`FR-STD-DB-META-006` · 2026-11-03 人类主人真机点验）
///
/// 原话：「连一个连不上的地址（如 `127.0.0.1:1`）后，**对象树不停地自己刷新**，像在无限重试」。
///
/// 根因不是"哪里写了重试"，而是**同一发刷新被反复触发**：`ObjectTreeView.body` 的根是 `Group`，
/// `.task(id:)` 挂在它上面；生产结构里这棵树住在 `ConnectionListView` 的
/// `List(selection:)` → `Section` 里，**行会随内容变化被重建**，于是「加载中」↔「加载失败」
/// 一次翻转就等于一次"重新出现"、`.task` 再跑一遍 `reloadRoot()` —— 键一个字没变，取数却重来。
/// 真机探针（`TestsUISnapshot/ObjectTreeDeadConnectionProbeTests`）实测：40 秒里
/// 自动取数发数 1 → 2 → 3 一路涨，不会停。
///
/// ## 口径
///
/// **同一把刷新键的自动取数有上限**：首连 + `backoff.count` 次重试。预算用完之后，
/// 自动路径一次都不许再发（`beginAutomatic` 恒 `false`）—— 树停在失败态，
/// 原因写在树上，**等用户手点「重试」**（`beginManual` 重新给一份预算）。
///
/// 为什么只自动重试 **一次**（`backoff = [2s]`）：连不上的地址每一次尝试要等驱动的
/// 连接超时（本机实测 **20 秒**），三次退避加起来是「用户盯着转圈一分钟」；
/// 能连上的情况首连就已经连上了，多试只对**瞬时抖动**有意义，而一次足够覆盖它。
///
/// 为什么预算按**发数**算、而不是「失败次数」算：同一把键的自动调用可能来自
/// `.task(id:)`、排队中的重试、以及 SwiftUI 的行重建 —— 数「失败」时分不清"这一次失败
/// 是不是同一发"，数「已经发过几发」永远分得清。这也是这条判据能一眼看懂的地方。
public struct ObjectTreeLoadRetry: Equatable, Sendable {

    /// 自动重试的退避间隔（第 n 次失败之后等 `backoff[n-1]`）。
    public static let backoff: [Duration] = [.seconds(2)]

    /// 同一把键允许的自动取数总发数 = 首连 + 重试。
    public static var automaticBudget: Int { 1 + backoff.count }

    /// 这份预算算的是哪把刷新键（换键 = 新的一轮，预算重来）。
    private var key: ObjectTreeRefreshKey?
    /// 这把键下已经发出去几发**自动**取数。
    private var automaticLoads = 0

    public init() {}

    /// 已经发出去的自动取数发数（判据与探针读它）。
    public var usedAutomaticLoads: Int { automaticLoads }

    /// 这一把键是不是已经**放弃自动重试**了（`true` ⇒ 自动路径一律空转、等用户手点）。
    public var hasGivenUp: Bool { automaticLoads >= Self.automaticBudget }

    /// 自动路径（`.task(id:)`、排队中的自动重试）现在能不能发这一发。
    ///
    /// 换键（换连接 / 元数据版本变了）会重置预算 —— 那是**另一件事**，不该被上一把键的失败锁住。
    public mutating func beginAutomatic(for key: ObjectTreeRefreshKey) -> Bool {
        if self.key != key {
            self.key = key
            automaticLoads = 0
        }
        guard automaticLoads < Self.automaticBudget else { return false }
        automaticLoads += 1
        return true
    }

    /// 用户手点（「重试」/工具条刷新）：**恰好发这一发**，之后自动路径继续停在原地。
    ///
    /// 为什么手动只给一发：需求原文是「它停在那儿，我点重试它再试」。点一下还跟一串自动重试，
    /// 等于把"停在那儿"又交回给定时器；而且判据里 `started` 到底该 +1 还是 +2 也说不清。
    /// 预算复位发生在**成功**（`recordSuccess`）之后 —— 连上了就回到「首连 + 一次重试」的常态。
    public mutating func beginManual(for key: ObjectTreeRefreshKey) {
        self.key = key
        automaticLoads = Self.automaticBudget
    }

    /// 这一发失败之后，要不要排队再自动试一次；`nil` = 就地停下（用户手动重试是唯一出路）。
    public func retryDelayAfterFailure() -> Duration? {
        guard automaticLoads >= 1, automaticLoads <= Self.backoff.count else { return nil }
        return Self.backoff[automaticLoads - 1]
    }

    /// 这一发成功了：预算复位（下一次再失败仍从首连 + 一次重试算起）。
    public mutating func recordSuccess() {
        automaticLoads = 0
    }
}
