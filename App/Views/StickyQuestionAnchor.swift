import AppKit
import SwiftUI

import DoyahCore

/// **当前轮那条提问**的标记视图（详设 §3.34）。
///
/// 它自己不报任何数：只作为「这一行是当前轮提问」的记号挂在那一行的背景上，
/// 让 `StickyQuestionSpy` 在文档视图里找得到它、量得到它的顶边。
///
/// 为什么不让这个视图**自己**往回写状态：那一行会被 `LazyVStack` 回收（长输出把它顶远），
/// 回收后回调就断了；更要命的是「从被回收那一行的闭包里写宿主 `@State`」在 SwiftUI 里会踩
/// 「Modifying state during view update」（本轮实测：`AgentChatView.swift: Modifying state
/// during view update, this will cause undefined behavior`）—— 写进去的值会被丢掉，
/// 条永远不出现。所以读数与缓存都只放在**长命**的那一件上（`StickyQuestionSpy`，
/// 挂在滚动内容根上、内容多长它都在）。
final class StickyQuestionRowMarker: NSView {
    /// **轮钥**（= 当前轮那条提问消息的 id）：换轮就换钥。
    ///
    /// 为什么标记要带钥而不是只靠「实例是不是同一个」：`LazyVStack` 会重建行，
    /// 同一轮的行重建会造出新实例 —— 那样「换轮」与「行重建」就分不开，重定位会误触发。
    var turnKey: UUID?
}

/// 把标记挂到当前轮那一行上（零行为，只提供身份与坐标）。
struct StickyQuestionRowAnchor: NSViewRepresentable {
    /// 轮钥（= 这条提问消息的 id）。读数器拿它判「是不是换了一轮」。
    let turnKey: UUID

    func makeNSView(context: Context) -> StickyQuestionRowMarker {
        let view = StickyQuestionRowMarker()
        view.turnKey = turnKey
        return view
    }

    func updateNSView(_ view: StickyQuestionRowMarker, context: Context) {
        view.turnKey = turnKey
    }
}

/// **内容末尾**的记号（详设 §3.39 判据⑤）：一个 1pt 的 `NSView`，量得到「正文最后一行的底边」。
///
/// 为什么需要它：入口要证明「不遮正文」，就得有一个**可机械取的正文端点**。文档高是
/// 「内容 + padding + 预留带」的合计，减出来的差值要靠推算 —— 那就成了同一份布局的第二个答案。
/// 这个记号挂在内容根里最后一项，位置由布局给，判据只读它。
final class AgentTranscriptTailMarker: NSView {}

struct AgentTranscriptTailAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AgentTranscriptTailMarker { AgentTranscriptTailMarker() }
    func updateNSView(_ view: AgentTranscriptTailMarker, context: Context) {}
}

/// 点吸顶条时用的**滚动命令**（详设 §3.34 契约③）。
///
/// 为什么不用 `ScrollViewProxy.scrollTo(message.id, anchor: .top)`：那一行的 id 同时是
/// `ForEach` 的条目身份，`scrollTo` 解析到的是**条目容器**（它前面还有一条轮次分隔线
/// `12 + 0.5 + 12` 与 4pt 块间距）—— 实测落点比行顶低 **28.5pt**，正是这三段之和。
/// 契约③ 要的是「定位到**该消息**顶部」，所以落点直接按内容坐标给：
/// `NSClipView.scroll(to:)` 到「提问顶边」那个偏移，再按刷新后的真值补一次
/// （`LazyVStack` 对未物化行只有估值，第一次落定后坐标可能变）。
final class StickyQuestionScroller {

    weak var spy: StickyQuestionSpy.SpyView?

    /// 把视口顶滚到「当前轮提问的顶边」。没量到那一行（还没渲染过）就什么都不做。
    func scrollQuestionToTop() {
        spy?.scrollQuestionToTop()
    }

    /// 把视口滚到**内容底边**（贴底跟随的唯一落点，§3.33.3 契约①）—— **先问状态机**。
    ///
    /// 为什么落点判定在读数器里而不是宿主：宿主那份「贴不贴底」是**异步回写**的副本，
    /// 读数在路上时副本就是旧的 —— 人往上翻之后它还会是 `true`，于是下一次内容长高又把人
    /// 拽回底部（「上翻被抢回」），反过来副本卡在 `false` 时新一轮再也不跟（「停在第一轮」）。
    /// 两副本 = 必漂移；所以只留这一份：宿主只发「想跟」的意图，**跟不跟由状态机答**。
    func scrollToBottomIfPinned() {
        spy?.scrollToBottomIfPinned()
    }

    /// 把视口滚到**内容底边**（不看状态机；探针 / 显式定位用）。
    func scrollToBottom() {
        spy?.scrollToBottom()
    }

    /// **回到消息底部**（详设 §3.39）：滚到内容底边 **且把跟随恢复成「贴着底」**。
    ///
    /// 与 `scrollToBottom()` 的区别只有一个、但很关键：那条只是「这一次滚到底」，
    /// 状态机仍是「人上翻」，下一次追加**不再跟** —— 而入口点的语义是「我要回到跟随」。
    /// 所以这里重置状态机（并撤掉本轮落点），之后 `report()` 见「贴底 + 距底 > 4pt」
    /// 就自己补跟，无需宿主再发指令。
    func jumpToBottomRestoringFollow() {
        spy?.jumpToBottomRestoringFollow()
    }

    /// 新轮开口：重置贴底状态机并定位到本轮开始处（§3.33.3 契约④）。
    func repinToBottom() {
        spy?.repinToBottom()
    }
}

/// 对话区滚动读数的**唯一出口**（详设 §3.34；贴底跟随沿用 §3.33.2 ③）：一次滚动，三个读数。
///
/// · `offsetFromTop`：视口顶在内容坐标里的位置（吸顶判定的一半）；
/// · `isStuck`：当前轮那条提问是否已经**滚出视口顶**（= `AgentStickyQuestion.shouldStick`）；
/// · `distanceToBottom`：距底距离（贴底跟随）。
///
/// ## 为什么三样都从这一处出
///
/// 判定的两个量必须在**同一次读数**里取：`clip.bounds.origin` 一次只变一个新值，分开订阅
/// 就会在「滚动刚到、布局还没跟」的那一拍拼出互相矛盾的组合（一边新一边旧）⇒ 条闪。
///
/// ## 为什么由它去找那一行、而不是那一行来找它
///
/// 「当前轮提问顶边在内容里的位置」只在那一行**还活着**时量得到；长输出会把它顶到很远，
/// `LazyVStack` 会把它回收。所以缓存必须留在**不会死的对象**上（这个 Spy 挂在滚动内容根），
/// 并且按「标记视图的实例身份」判断缓存是否还有效：
///
/// · 找到标记 ⇒ 记下它的顶边；换了实例（新的一轮 / 行被重建）⇒ 重记；
/// · 找不到（行被回收）⇒ **沿用上一份**。清掉就等于「滚远了反而不吸顶」，正是要修的现象。
///
/// 三样读数都只在**真的滚动**时算（`clip.boundsDidChange`）：内容长高不改它们 ——
/// 否则「贴着底 + 新内容刚到、还没跟」这一瞬会被误判成「用户往上翻」（§3.33.2 的同一条教训）。
struct StickyQuestionSpy: NSViewRepresentable {

    struct Reading: Equatable {
        /// 视口顶在内容坐标里的位置（pt，≥ 0）。
        var offsetFromTop: CGFloat
        /// 距底距离（pt，≥ 0）。
        var distanceToBottom: CGFloat
        /// 当前轮提问是否已经滚出视口顶（条该出现）。
        var isStuck: Bool
        /// 外层对话区是不是**贴着底**（唯一判定：`AgentScrollFollow` 的状态机，住在读数器里）。
        var isPinned: Bool = true
        /// 内容总高 / 视口高（pt）：只给判据读数用，判定不读它们。
        var contentHeight: CGFloat = 0
        var viewportHeight: CGFloat = 0
    }

    /// 点条时的滚动命令（`nil` = 不需要 / 探针自己滚）。
    var scroller: StickyQuestionScroller?
    /// **当前轮的轮钥**（= 本轮那条提问消息的 id；`nil` = 还没有提问）。
    ///
    /// 为什么要从外面喂进来、而不是靠 `.onChange(of: currentTurnKey)` 通知：
    /// 换轮的重定位**不许**依赖那个钩子的时机（beta1.0.9 真机实测它一次都没触发 ⇒
    /// 「多轮后停在第一轮」）。`updateNSView` 是布局驱动的，视图一更新它就被调 ——
    /// 轮钥一变就在这里重置状态机并定位，与 `onChange` 无关。
    var turnKey: UUID?
    let onReading: (Reading) -> Void

    func makeNSView(context: Context) -> SpyView {
        let view = SpyView()
        view.onReading = onReading
        view.setTurnKey(turnKey)
        scroller?.spy = view
        return view
    }

    func updateNSView(_ view: SpyView, context: Context) {
        view.onReading = onReading
        view.setTurnKey(turnKey)
        scroller?.spy = view
        view.attachIfNeeded()
    }

    final class SpyView: NSView {

        var onReading: ((Reading) -> Void)?

        /// **贴底判定唯一的状态机**（§3.33.3）。
        ///
        /// 为什么住在读数器里而不是宿主的 `@State` 里：它要记住「上一次的偏移」才能分清
        /// 「人往上滚了」与「内容长高了」。放进 `@State` 结构体，就得每次读数都写一次状态
        /// ⇒ 每一个滚动帧都重算一屏（那正是 §3.33.2 要消掉的「闪」）。这里只是一块内存，
        /// 宿主只在**判定翻转**时被通知一次。
        private var follow = AgentScrollFollow()

        private var observer: NSObjectProtocol?
        /// 内容高变化的那一路（新内容 / 折展都会改它）。
        private var frameObserver: NSObjectProtocol?
        /// 视口高变化的那一路（吸顶条进出 / 窗口改宽高）。
        private var clipFrameObserver: NSObjectProtocol?
        /// 正在由**我们自己**滚（防止「补跟 → 读数 → 再补跟」在同一个调用栈里递归）。
        private var isScrolling = false
        /// **订阅时那一个 clip**：读数永远只从它来（子滚动区 —— 比如内层思考视口 —— 的
        /// `boundsDidChange` 通知 object 不是它，因此进不来）。
        private weak var attachedClip: NSClipView?

        /// 当前轮提问顶边在内容坐标里的位置，以及它是从哪个标记实例量来的。
        private var questionTop: CGFloat?
        private weak var questionMarker: StickyQuestionRowMarker?

        /// **当前轮的轮钥**（= 当前轮那条提问消息的 id）。
        ///
        /// 换钥 = 新一轮开始了 ⇒ 状态机整个重置、视口回到本轮开始处再贴回来（§3.33.3 契约④）。
        /// 为什么这件事在这里做，而不是在宿主的 `.onChange(of: currentTurnKey)` 里：
        /// 那个钩子在本视图里**不保证触发**（beta1.0.9 真机「多轮后停在第一轮、要手工拖」
        /// 就是这么来的 —— 实测 `repins = 0`，视图侧那些 `onChange` 一次都没跑）。
        /// 换轮是**几何事实**：新的提问行出现 ⇒ 文档里换了一个带不同轮钥的标记 ⇒
        /// 这条路只依赖「内容变了」，而内容变化是这个读数器本来就在订阅的东西。
        private var turnKey: UUID?

        /// **本轮的落点**（`nil` = 用户已经上手，控制权交还给他）。
        ///
        /// 为什么不是「滚一次就完」：换轮那一拍的几何还是旧的，我们把视口滚到位之后，
        /// 紧接着这次布局可能又按旧锚点把它摆回去（实测：滚到 2611.5pt，下一拍读数变回 0.0pt）。
        /// 所以落点要**整轮有效**：每次读数发现「不在落点上」就再落一次 —— 这也正是
        /// 「当前轮一直贴着最新内容」的意思。用户一上手（滚轮 / 拖滚动条）就撤掉，交还控制权。
        private var turnTarget: CGFloat?
        /// 本轮已经落了几次（封顶：不许无限追 —— 40 次 ≈ 一轮流式的读数数量级）。
        private var turnTargetApplies = 0

        /// **换轮重定位的计数点**（判据用：换轮有没有真的触发一次重置）。
        /// 为什么要这个：离屏宿主在换轮重排那一拍会把滚动视口约束丢掉（实测视口高读成 3526pt），
        /// 落点几何量不到；「有没有换轮、往哪落」这两个读数在任何宿主里都读得到。
        static private(set) var turnResetCount = 0
        static private(set) var lastTurnTarget: CGFloat = -1
        /// **轮钥变了 ⇒ 新一轮开始**（§3.33.3 契约④）：状态机重置、视口回到本轮开始处。
        ///
        /// 走下一拍再滚：`updateNSView` 发生在 SwiftUI 的一次布局里，当场 `clip.scroll`
        /// 会在「布局进行中改几何」这条路上抖动（与 `onReading` 拖一拍同一个理由）。

        func setTurnKey(_ key: UUID?) {
            let previous = turnKey
            guard key != turnKey else { return }
            turnKey = key
            // 只有「从另一个轮换过来」才算新一轮。**首次挂上**（`nil → 本轮`）不重定位：
            // 打开会话时的初始位置不归这里抢（抢了就会和用户/系统的初始滚动打架）。
            if previous != nil { repinToBottom() }
        }


        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
            // SwiftUI 有时先把视图插进层级、下一拍才插进 `NSScrollView` 的文档视图。
            DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
        }

        func attachIfNeeded() {
            guard observer == nil, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let clip = scroll.contentView
            attachedClip = clip
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            // **内容高变化也要报一次**（§3.33.3 契约①）：流式逐段、新步骤、思考区折/展、
            // 吸顶条进出都只改**内容高**而不改偏移 —— 等 `boundsDidChange` 就等于永远等不到。
            document.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: document,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            // **视口高变化也要报一次**：吸顶条进出（§3.34）让视口少/多 20pt，内容高一点没变、
            // 偏移也一点没动 —— 只有「视口变矮」这一件事把距底撑开 20pt（实测 T-① 第 6 次）。
            clip.postsFrameChangedNotifications = true
            clipFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            // 首报走下一拍：`attachIfNeeded` 常在视图更新中途被调，同步回写状态会踩
            // 「在更新中修改状态」（见文件头的实测记录）。
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        private func report() {
            // **只读我们自己订阅的那一个 clip**：视图被挪进子滚动区时这条守卫会挡住
            // 「内层滚动当外层读数」（§3.33.3 契约②）。
            guard let clip = attachedClip, clip.window != nil,
                  let scroll = clip.enclosingScrollView, let document = scroll.documentView
            else { return }
            let contentHeight = document.bounds.height
            let viewportHeight = clip.bounds.height
            let maxOffset = max(0, contentHeight - viewportHeight)
            // 文档视图是翻转坐标（origin.y = 0 在顶）；非翻转时换算一次。
            let flipped = document.isFlipped
            let offsetFromTop = flipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)

            let newTurn = refreshQuestionTopIfNeeded(in: document, flipped: flipped)
            // **换轮 ⇒ 先重置状态机、回到本轮开始处，再贴回来**（§3.33.3 契约④）。
            //
            // 重置在前（上一轮「人上翻」的意图当场作废），定位在后（`applyScroll` 会夹到
            // `maxOffset`：新轮内容不足一屏时落点就是底部）。这里只置待办，落点在下面那段
            // 「跟着内容变化重试」里执行 —— 换轮那一拍的几何还是旧的，当场滚会被这次布局摆回去。
            if newTurn { beginTurnReset() }

            if settleTurnTarget(contentHeight: contentHeight, offsetFromTop: offsetFromTop) {
                // 已经滚过去了：由 `applyScroll` 内部那次 `report()` 送读数，本拍不再用旧偏移判一次。
                return
            }

            // 贴底判定：一次完整读数进状态机（分得清「人上翻」与「内容长高」）。
            follow.update(contentHeight: contentHeight,
                          viewportHeight: viewportHeight,
                          offsetFromTop: offsetFromTop)

            let distance = AgentScrollFollow.distanceToBottom(contentHeight: contentHeight,
                                                              viewportHeight: viewportHeight,
                                                              offsetFromTop: offsetFromTop)

            // **贴底态的自愈**（§3.33.3 契约①）：内容刚长高、偏移还没跟上 ⇒ 当场补跟，
            // 不等「通知 → 下一拍回写 → 再重排」那条链（少两帧，实测会漏出 20pt）。
            // 只在**贴底**时做：人往上翻之后 `follow` 已经是假，这里一次都不会触发。
            if follow.isPinnedToBottom, distance > AgentScrollFollow.bottomTolerance, !isScrolling {
                scrollToBottom()
                return
            }

            let stuck = questionTop.map {
                AgentStickyQuestion.shouldStick(viewportTop: offsetFromTop, questionTop: $0)
            } ?? false
            let reading = Reading(offsetFromTop: offsetFromTop,
                                  distanceToBottom: distance,
                                  isStuck: stuck,
                                  isPinned: follow.isPinnedToBottom,
                                  contentHeight: contentHeight,
                                  viewportHeight: viewportHeight)
            // 回写走**下一拍**：`boundsDidChange` 可能就发生在 SwiftUI 的一次布局 / 更新里，
            // 当场写宿主 `@State` 会踩「Modifying state during view update」
            // （本轮实测原话：`AgentChatView.swift:197: Modifying state during view update`）。
            DispatchQueue.main.async { [weak self] in self?.onReading?(reading) }
        }

        /// 把视口滚到**内容底边**（贴底跟随的唯一落点，§3.33.3 契约①）。
        ///
        /// 为什么不走 `ScrollViewProxy.scrollTo(底部哨兵, anchor: .bottom)`：那个落点对齐的是
        /// **哨兵**的底边，而内容末尾还有 12pt 的 `.padding(.vertical)`（`Spacing.m`）——
        /// 实测（beta1.0.6 真机 / 探针）贴底后距底**恒为 12.0pt**，超过 4pt 容差 ⇒
        /// 每跟一次就立刻被判成「用户上翻」⇒ 整段流式再也不跟。落点必须**同一个分母**。
        func scrollToBottom() {
            applyScroll(offsetFromTop: .greatestFiniteMagnitude)
        }

        /// 只有**状态机说贴着底**时才滚到底（宿主的跟随意图走这条口，§3.33.3 契约①）。
        func scrollToBottomIfPinned() {
            guard follow.isPinnedToBottom else { return }
            scrollToBottom()
        }

        /// **回到消息底部并恢复跟随**（详设 §3.39）：人点入口，等于「我要重新贴上」。
        ///
        /// 三件事，顺序不能反：
        /// ① **撤掉本轮落点**（`turnTarget`）—— 点一下之后控制权在「贴底跟随」这边，
        ///   若落点还在，下一次读数会把视口又摆回本轮开始处（入口当场又出现）；
        /// ② **重置状态机**为贴底（`AgentScrollFollow()` 的缺省就是贴底），
        ///    这样下一拍 `report()` 里的「贴底态自愈」就会跟着新内容走；
        /// ③ **滚到内容底边**（与跟随同一个落点，距底 0pt）。
        ///
        /// 为什么不是「滚到底 + 等一个滚动事件把 pinned 改回来」：程序滚没有用户事件，
        /// 状态机不会自己从「上翻」翻回「贴底」—— 只有距底 ≤ 4pt 这一条能翻，而那条
        /// 恰好要等我们把视口滚过去才成立（先有鸡）。所以这里显式重置，不是抄近路。
        func jumpToBottomRestoringFollow() {
            turnTarget = nil
            follow = AgentScrollFollow()
            scrollToBottom()
        }

        /// **新轮开口**：状态机整个重置，视口回到**本轮开始处**（§3.33.3 契约④）。
        ///
        /// 为什么要重置而不只是「贴底一次」：人刚发了消息就该看见这一轮的回答 —— 哪怕他上一轮
        /// 翻到半路停着。重置状态机是刻意的：那一刻的「上翻」意图已经失效了（只在本轮内有效）。
        ///
        /// 落点 = **本轮提问行的顶边**（`questionTop`），由 `applyScroll` 夹到 `maxOffset`：
        /// 新一轮刚开口时内容还没有一屏 ⇒ 夹到的就是底部（两条规则同解，不会互相打架）。
        func repinToBottom() {
            beginTurnReset()
            _ = settleTurnTarget(contentHeight: -1, offsetFromTop: -1)
        }

        /// 起一次「本轮落点」（状态机当场重置 —— 上一轮的上翻意图立刻作废）。
        private func beginTurnReset() {
            follow = AgentScrollFollow()
            // 缓存的提问顶边若属于上一轮（新行还没物化），它在这一轮毫无意义 ⇒ 落点取底部：
            // 新一轮刚开口时内容不足一屏，「本轮开始处」本来就夹到底部（两条规则同解）。
            turnTarget = questionTop ?? .greatestFiniteMagnitude
            turnTargetApplies = 0
            Self.turnResetCount += 1
            Self.lastTurnTarget = turnTarget ?? -1
        }

        /// 落本轮落点：不在位就再落一次；用户上手就撤。
        ///
        /// 返回 `true` = 本拍刚滚过去（调用方直接返回，由 `applyScroll` 内部那次 `report()`
        /// 去送读数）。
        private func settleTurnTarget(contentHeight: CGFloat, offsetFromTop: CGFloat) -> Bool {
            // **用户上手（滚轮 / 拖滚动条）⇒ 交还控制权**：判定用真实事件，
            // 而不是「偏移变小了」——后者分不清「人上翻」与「布局把我们摆回去」，
            // 而后者恰恰是换轮那一拍必然发生的事。
            if Self.isUserScrollEvent() { turnTarget = nil }
            guard let target = turnTarget, !isScrolling,
                  let clip = attachedClip, let scroll = clip.enclosingScrollView,
                  let document = scroll.documentView else { return false }
            let maxOffset = max(0, document.bounds.height - clip.bounds.height)
            // 落点 = **本轮开始处**；它比底部更靠上（本轮下面还有内容）时就停在开始处，
            // 行还没物化（`questionTop == nil`）才退回底部。两个数都夹到 `maxOffset`。
            let resolved = min(target, questionTop ?? target)
            let goal = min(resolved, maxOffset)
            guard abs(offsetFromTop - goal) > 2, turnTargetApplies < 40 else { return false }
            turnTargetApplies += 1
            applyScroll(offsetFromTop: resolved)
            return true
        }

        /// 这一拍是不是**人**在滚（滚轮 / 拖滚动条）。程序滚（`applyScroll`）没有当前事件。
        private static func isUserScrollEvent() -> Bool {
            guard let type = NSApp.currentEvent?.type else { return false }
            return type == .scrollWheel || type == .leftMouseDragged
                || type == .rightMouseDragged || type == .otherMouseDragged
        }

        /// 把视口顶滚到「当前轮那一行提问的顶边」（§3.34 契约③）。
        ///
        /// 两次落点：第一次按当前的 content 坐标滚；落定后那一行就物化了，`LazyVStack`
        /// 对它的位置从「估值」变成真值 ⇒ 再按新值补一次（实测估值误差 28.5pt 量级）。
        func scrollQuestionToTop() {
            guard let top = questionTop else { return }
            applyScroll(offsetFromTop: top)
            DispatchQueue.main.async { [weak self] in
                guard let self, let refreshed = self.questionTop else { return }
                self.applyScroll(offsetFromTop: refreshed)
            }
        }

        private func applyScroll(offsetFromTop: CGFloat) {
            guard let clip = attachedClip ?? enclosingScrollView?.contentView,
                  let scroll = clip.enclosingScrollView,
                  let document = scroll.documentView
            else { return }
            isScrolling = true
            defer { isScrolling = false }
            let maxOffset = max(0, document.bounds.height - clip.bounds.height)
            let clamped = min(max(0, offsetFromTop), maxOffset)
            let y = document.isFlipped ? clamped : (maxOffset - clamped)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
            // 不必等 `boundsDidChange`：位置已经定了，当场重算一次读数（回写仍走下一拍）。
            report()
        }

        /// 找到那一行的标记就重记它的顶边；标记换了实例就作废重记；找不到就**留着**上一份。
        ///
        /// **换轮检测**（§3.33.3 契约④）也在这里：标记带轮钥，钥一变就是新一轮 ——
        /// 返回 `true`，由 `report()` 重置状态机并回到本轮开始处。
        private func refreshQuestionTopIfNeeded(in document: NSView, flipped: Bool) -> Bool {
            let markers = Self.findMarkers(in: document).filter { $0.window != nil && $0 !== self }
            guard let marker = markers.first else { return false }
            if marker !== questionMarker {
                questionMarker = marker
                questionTop = nil
            }
            // 轮钥（只有换了钥才算换轮；同一轮的行被重建不算）。
            let changed = marker.turnKey != turnKey
            if changed { turnKey = marker.turnKey }
            let rect = marker.convert(marker.bounds, to: document)
            let top = flipped ? rect.minY : (document.bounds.height - rect.maxY)
            if !changed, let last = questionTop, abs(last - top) <= 0.5 { return false }
            questionTop = top
            return changed
        }

        private static func findMarkers(in view: NSView) -> [StickyQuestionRowMarker] {
            var found: [StickyQuestionRowMarker] = []
            if let marker = view as? StickyQuestionRowMarker { found.append(marker) }
            for subview in view.subviews {
                found.append(contentsOf: findMarkers(in: subview))
            }
            return found
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            if let clipFrameObserver { NotificationCenter.default.removeObserver(clipFrameObserver) }
        }
    }
}
