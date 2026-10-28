import Foundation

/// 对象树：某个节点**这一次没加载出来**之后，那一行要不要给「重试」入口、点了之后到底做哪几步。
///
/// ## 为什么要有它（`FR-STD-DB-META-006` ③）
///
/// 需求原文是「任意层级都可继续展开；空节点给明确文案；**加载失败在该节点给可读错误并可重试**」。
/// 此前只做到前一半：失败那一行下面画出那句人话（`ErrorPresenter` 的「人话 + 方向」），
/// **界面上没有任何入口**。用户唯一的办法是自己把它折起来再展开一次 —— 而这件事
/// 界面上一个字都没提，于是「这个库连不上」在用户眼里就是「这软件点不进去」。
///
/// ## 为什么判定要做成纯函数
///
/// 「要不要出这枚入口」与「点了做什么」若各写一份，就会长出本仓反复踩的那类缺陷：
/// 界面出一枚**点了没反应**的按钮（在途时又发一遍取数），或者重试之后那一行
/// **还挂着上一轮的红字**（用户以为没生效，然后再点一次）。所以判定只在这里：
/// 视图把这一行的四个事实喂进来，拿回一个结果；出不出入口与点了做什么出自同一份判定。
///
/// ## 四档「不出入口」，每档都对应一种「点了会更糟」
///
/// - `inFlight`：这一发还在途 —— 再点一次就是**第二次取数**，谁后落地谁说了算。
///   根节点刷新踩过同族的坑（三个入口各发一遍，见 `ObjectTreeRefreshGate` / 队列 `L-96`），
///   节点这一层此前没有闸门；
/// - `notExpanded`：入口画在展开后的那一行下面，收起时那一行根本没画出来；
/// - `noFailure`：没有失败就没有可重试的东西 —— 在空态（「该库下暂无表 / 视图」）旁边摆一枚
///   「重试」，用户会以为「是刚才出错了」，把正常状态读成故障；
/// - `alreadyLoaded`：子节点已经在缓存里（这一次是成功的），残留的错误不该换来一枚重试。
///
/// ## 重试两步的顺序也是口径
///
/// **先清旧错误、再取数**。反过来的话，从点击到结果落地之间那一行仍然写着上一轮的失败原因，
/// 而界面上没有任何「正在重试」的迹象 —— 用户能看见的唯一变化就是没有变化。
public enum ObjectTreeRetry {

    /// 这一行为什么**不**给重试入口。
    ///
    /// 做成带名字的档位（而不是一个 `Bool`）是为了让打点 / 判据能说清是**哪一条**没让过 ——
    /// 「按钮没出来」与「按钮出来了但点了没反应」是两种完全不同的缺陷。
    public enum Skip: String, Equatable, Sendable {
        /// 这一发还在途：再取一次就是两发抢着落地。
        case inFlight
        /// 节点是收起的：入口所在的那一行没有画出来。
        case notExpanded
        /// 没有失败（空态 / 正常态）：没有可重试的东西。
        case noFailure
        /// 子节点已经在缓存里：这一次是成功的。
        case alreadyLoaded
    }

    /// 点了「重试」要做的两步（**顺序即口径**：先清旧错误，再取数）。
    public enum Step: String, Equatable, Sendable {
        case clearError
        case loadChildren
    }

    /// 一次重试的计划：对哪个节点、做哪几步。
    ///
    /// `steps` 是数组而不是一个「开始」布尔值，正是为了让「先清错误再取数」这条口径
    /// 能被判据**逐字**读到（把顺序写反的实现拿不到这份计划）。
    public struct Plan: Equatable, Sendable {
        public let nodeID: String
        public let steps: [Step]

        public init(nodeID: String, steps: [Step]) {
            self.nodeID = nodeID
            self.steps = steps
        }
    }

    public enum Outcome: Equatable, Sendable {
        case retry(Plan)
        case skip(Skip)

        /// 要重试的那份计划（不出入口时为 `nil`）。
        public var plan: Plan? {
            if case let .retry(plan) = self { return plan }
            return nil
        }

        /// 这一行出不出「重试」入口 —— 与 `plan` 出自同一份判定，视图不必自己再判一次。
        public var affordsRetry: Bool { plan != nil }
    }

    /// 判定的**唯一入口**。
    ///
    /// - Parameters:
    ///   - nodeID: 节点标识（进计划，供调用方核对「点的是这一行」）。
    ///   - isExpanded: 这一行现在是展开的（入口只在展开后的那一行下面）。
    ///   - isLoading: 这个节点的子节点正在取。
    ///   - cachedCount: 子节点缓存（`nil` = 没加载过；`0` = 加载过但没有子节点 —— 两者不是一回事）。
    ///   - error: 这一行挂着的失败文案（`nil` / 空白 = 没有失败）。
    public static func evaluate(
        nodeID: String,
        isExpanded: Bool,
        isLoading: Bool,
        cachedCount: Int?,
        error: String?
    ) -> Outcome {
        // ① 在途优先于一切：无论别的状态如何，都不许再发第二次取数。
        if isLoading { return .skip(.inFlight) }
        // ② 收起时入口所在的这一行没有画出来。
        if !isExpanded { return .skip(.notExpanded) }
        // ③ 没有失败就不出（空白串也算没有：`ErrorPresenter` 不该给出空串，但界面不能因此摆一枚空按钮）。
        guard let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .skip(.noFailure)
        }
        // ④ 已经有了这一次的子节点 ⇒ 那是成功的，残留错误不该换来重试。
        if cachedCount != nil { return .skip(.alreadyLoaded) }

        return .retry(Plan(nodeID: nodeID, steps: [.clearError, .loadChildren]))
    }
}
