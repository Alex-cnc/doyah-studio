import AppKit
import SwiftUI
import DoyahCore

/// **过程块**（详设 §3.33「对话区展示优先级」）：工具调用块与过程独白。
///
/// ## 为什么单拎成两个视图
///
/// 这一族要的判据是**几何读数**：折叠态几 pt、展开态几 pt、多少条之后还一样高。
/// 挂在 `AgentChatView` 的私有方法里就只能靠人眼，而且展开态是 `@State`，
/// 离屏宿主点不动（`DialogActionRowProbeTests` 那条已登记的边界）。做成「输入 →
/// 视图」的独立件之后，探针能把 `expanded: .constant(true)` 真挂起来量，
/// 生产路径与判据读的是**同一份**渲染代码，不是照着画一遍。
///
/// ## 两条硬口径（2026-11-07 真机复验）
///
/// · **工具调用默认折成一行摘要**（`▸ 56 次工具调用 · 8.2s · 展开`）：改前默认展开，
///   一轮 56 次调用就是 56 行，把结论挤出屏幕；
/// · **过程独白默认折成一行**（`▸ 过程独白 · 12 行 · 展开`）：模型写在正文里的
///   「我先读一下……再……」属于过程信息，不许当正文铺。
struct AgentToolBlockView: View {

    /// 过程文本（Core 写的那一块：每行 `▸ 名 · 摘要  ✓ · 0.5s`）。
    let text: String
    /// 展开态由宿主给（默认 `false` = 一行摘要）。
    let expanded: Bool
    let highlight: String?
    let language: AppLanguage
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// 折叠态高度：**一行**（表头那一行 = `Metrics.listRowHeight`）。
    static let collapsedHeight: CGFloat = Metrics.listRowHeight

    /// 展开态行体的上限（≈ 10 行条目，超了在内部滚）。
    static let bodyMaxHeight: CGFloat = 216

    /// 展开态整块上限：表头 + 发丝 + 行体 = **238pt**（判据要求 ≤ 240pt）。
    static var expandedMaxHeight: CGFloat {
        collapsedHeight + Spacing.hair + bodyMaxHeight
    }

    private static let font = Theme.font(.mono)

    var body: some View {
        let rows = AgentToolLines.rows(text)
        let rawLines = text.components(separatedBy: "\n")
        let count = rows.isEmpty ? rawLines.count : rows.count

        VStack(alignment: .leading, spacing: Spacing.hair) {
            Button(action: onToggle) {
                HStack(spacing: Spacing.s) {
                    Text(expanded ? "└─ ▾" : "└─ ▸")
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.secondary))
                    // 一行摘要：`56 次工具调用 · 8.2s · 展开`（§3.33）。
                    Text(AgentToolBlockSummary.text(count: count,
                                                    elapsedSeconds: AgentToolBlockSummary.elapsedSeconds(rows),
                                                    expanded: expanded,
                                                    language: language))
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? LocalizedStrings.text(.agentChatCollapse, language: language)
                  : LocalizedStrings.text(.agentChatExpand, language: language))

            if expanded {
                // 行体高度 = **min(行数 × 行高, 上限)**（§3.37）：两条调用就两行高，
                // 不再先占满 216pt 再留一块空白；超过上限才在内部滚（300 次调用不会把
                // 这一块撑成 6000pt）。行数是整数 ⇒ 天然只在整行边界变化，不会抖。
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Spacing.hair) {
                        if rows.isEmpty {
                            // 认不出的过程行：**原样**逐行画（Core 换了格式时，这里既不吞字也不猜）。
                            ForEach(Array(rawLines.enumerated()), id: \.offset) { _, line in
                                Text(TranscriptHighlight.apply(highlight, to: AttributedString(line)))
                                    .font(Self.font)
                                    .foregroundStyle(Theme.text(.secondary))
                                    .textSelection(.enabled)
                                    .padding(.leading, Metrics.listIndent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                toolEntryRow(row, isLast: index == rows.count - 1)
                            }
                        }
                    }
                }
                .frame(height: AgentProcessBody.height(rows: count,
                                                       spacing: Spacing.hair,
                                                       cap: Self.bodyMaxHeight))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 折叠态**钉成一行**（20pt）：这一块的高度是常量，探针拿它当判据。
        .frame(height: expanded ? nil : Self.collapsedHeight, alignment: .topLeading)
        // **判据⑤的计数点**（§3.33.4）：工具块按调用 / 步骤各自成块 —— 收的是动作，
        // 不是思考，所以思考区合并成一轮一个之后，这里一个都不能少、一行都不能变。
        .background(AgentToolBlockAnchor())
    }

    /// 一条工具条目：`├─ ⏺ <名>("<参数摘要>") (<耗时>s)`（末条用 `└─`）。
    private func toolEntryRow(_ row: AgentToolLine, isLast: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(isLast ? "└─ ⏺" : "├─ ⏺")
                .font(Self.font)
                .foregroundStyle(Theme.text(.tertiary))
            // **调用的那一行走淡蓝**（§5.3.8.4：蓝 = 机器动作）；跑着的调暗一档表示「还没回来」。
            Text(TranscriptHighlight.apply(highlight,
                                           to: AttributedString(AgentToolLines.callText(row))))
                .font(Self.font)
                .foregroundStyle(row.outcome == .running
                                 ? Theme.chat(.command, colorScheme).opacity(0.7)
                                 : Theme.chat(.command, colorScheme))
                .textSelection(.enabled)
            // **失败逐条标在自己这一行上**（六态「部分失败」：不许整轮报失败、也不许丢失败条目）。
            if case let .failure(reason) = row.outcome {
                Text("✗ " + refusalCode(reason))
                    .font(Self.font)
                    .foregroundStyle(Theme.status(.danger))
                    .help(refusalHelp(reason) ?? "")
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metrics.listRowHeight)
        .padding(.leading, Metrics.listIndent)
    }

    /// 拒因里的 `denied:` 前缀（`Core` 的 `toolFinished` 事件把它拼在机器码前面）。
    private static let deniedPrefix = "denied:"

    /// 行内那个**短码**：剥掉 `denied:` 包装词，其余原样（宁可见码，也不编一句像解释的话）。
    private func refusalCode(_ raw: String) -> String {
        raw.hasPrefix(Self.deniedPrefix) ? String(raw.dropFirst(Self.deniedPrefix.count)) : raw
    }

    /// 短码 → 整句解释（只翻能确定的那两种；其余返回 `nil`，不挂提示）。
    private func refusalHelp(_ raw: String) -> String? {
        switch refusalCode(raw) {
        case "writeConflict": return LocalizedStrings.text(.agentChatWriteBusy, language: language)
        case "staleTarget": return LocalizedStrings.text(.agentChatWriteStale, language: language)
        default: return nil
        }
    }
}

/// **思考区**（详设 §3.33「思考区三态」/ §3.33.4「一轮一个思考区」）：过程独白（以及打开的思考段）只住在这里。
///
/// ## 一轮一个区（§3.33.4，beta1.0.7 主人原话）
///
/// > 「多个步骤的思考应该是合一起的啊，现在是分成了一块一块的」
///
/// 改前这个视图是**按 step 实例化**的（`AgentChatView` 在逐条消息的 `ForEach` 里调它），
/// 五步就是五块 200pt 的折叠块。现在它收的是**整轮**的段（`segments`）：
/// · 只有一个抬头 ⇒ 折 / 展**一次作用于整轮**；
/// · 步骤边界退成**区内轻分隔**（一行发丝 + 极小字「第 N 步」），不是二级折叠头；
/// · 整块高度 = **min(内容实测高, 200)**（§3.37）：内容少就贴着字收，超上限才在内部滚。
///
/// ## 三态（人类主人 2026-11-07 拍的产品决策）
///
/// 1. **运行中（本轮未结束）** ⇒ 默认**展开**，可流式增量显示，高度按 §3.37 自适应
///    （≤ `expandedMaxHeight` = 200pt，超了内部滚动）；用户可手动收起。
/// 2. **任一终态**（完成 / 失败 / 取消）⇒ **自动折成一行**摘要：
///    `思考过程 · 12 步 · 18.4s · 展开`（`collapsedHeight` = 一行）。
/// 3. **用户手动展开后** ⇒ 本轮内保持（sticky），**不许**每帧 / 每个新事件又折回去；
///    新轮开始才回到「按阶段默认」—— sticky 与轮次作用域都在 Core
///    （`AgentThinkingFold` / `AgentThinkingManualState`），视图只读结论。
///
/// 「哪一段算独白」「哪几条消息凑成这一轮」也**不在这里**判：`AgentTurnThinking` 给，视图只画。
///
/// ## 流式期间的四条（详设 §3.33.2 / §3.37，beta1.0.4「滚动条很闪」+ beta1.0.8「固定高度」）
///
/// · **高度 = min(内容, 上限) 且按整行量化**（§3.37）：一行的思考就一行高，超 178pt 才卡在上限；
///   量化保证高度只在**跨过行高倍数**时变 —— 既没有空白，也不会退回「一个 token 抖一次」；
/// · **条件跟随**：只有用户贴着底时才跟着新内容走，往上翻就停手（`AgentScrollFollow`）；
/// · **运行中不画滚动指示器**：内容每 50ms 长一截，滑块尺寸每次重算就是闪的来源；
///   终态手动展开是静态内容，交回系统默认。
struct AgentThinkingZone: View {

    /// 这一轮的段（顺序即发生顺序；详设 §3.33.4）。
    let segments: [AgentThinkingSegment]
    let phase: AgentThinkingPhase
    /// `nil` = 用户没动过（按阶段默认）。
    let manual: Bool?
    let steps: Int
    let elapsedSeconds: Double?
    /// 本轮思考的 token 合计（§3.33.4 第一行）；`nil` = 调用方没有读数（探针 / 单段路径）
    /// ⇒ 抬头退回「思考过程 · N 步 · 18.4s · 展开」。
    let tokens: Int?
    let highlight: String?
    let language: AppLanguage
    let onToggle: (Bool) -> Void

    /// 单段形态（探针 / 只有一个调用点的简短路径）：等价于只有第 1 段的一轮。
    init(text: String,
         phase: AgentThinkingPhase,
         manual: Bool?,
         steps: Int,
         elapsedSeconds: Double?,
         tokens: Int? = nil,
         highlight: String?,
         language: AppLanguage,
         onToggle: @escaping (Bool) -> Void) {
        self.init(segments: [AgentThinkingSegment(step: 1, text: text)],
                  phase: phase,
                  manual: manual,
                  steps: steps,
                  elapsedSeconds: elapsedSeconds,
                  tokens: tokens,
                  highlight: highlight,
                  language: language,
                  onToggle: onToggle)
    }

    init(segments: [AgentThinkingSegment],
         phase: AgentThinkingPhase,
         manual: Bool?,
         steps: Int,
         elapsedSeconds: Double?,
         tokens: Int? = nil,
         highlight: String?,
         language: AppLanguage,
         onToggle: @escaping (Bool) -> Void) {
        self.segments = segments
        self.phase = phase
        self.manual = manual
        self.steps = steps
        self.elapsedSeconds = elapsedSeconds
        self.tokens = tokens
        self.highlight = highlight
        self.language = language
        self.onToggle = onToggle
    }

    @Environment(\.colorScheme) private var colorScheme

    /// 折叠态高度：**一行摘要**（= 一行等宽字）。
    static let collapsedHeight: CGFloat = AgentThinkingViewport.collapsedHeight

    /// 展开态**内容视口的上限**（178pt = 200 − 20 − 2）；不够就只占实测那么多（§3.37）。
    static let contentMaxHeight: CGFloat = AgentThinkingViewport.viewportHeight

    /// 展开态整块**上限**（200pt；`expandedMaxHeight` 这个名字留给既有判据当上限用）。
    static var expandedMaxHeight: CGFloat { AgentThinkingViewport.totalHeight }

    /// 内容**实测高**（已按整行量化，§3.37）。
    ///
    /// 只存量化后的值：写一次 `@State` 就是一次重排，而量化值只在**跨过行高倍数**时变 ——
    /// 这就是「高度不随每个 token 抖」的落点（判据④）。实测由 `ContentHeightSpy` 报回。
    @State private var measuredContentHeight: CGFloat = 0

    private static let font = Theme.font(.mono)

    /// 内容末尾那个 1pt 哨兵的 id（自动跟随的锚）。
    private static let bottomAnchor = "agentThinkingBottom"

    /// **条件跟随**（§3.33.2 ③）：只在贴着底时跟；用户往上滚就停手。
    ///
    /// 只在「是不是贴底」**真的翻转**时写它 —— 每像素滚一下都写 `@State` 就等于
    /// 把「不闪」拆掉一半（每次写都重算这一格）。
    @State private var follow = AgentScrollFollow()

    /// 有内容的段（空白段丢掉：段还在，只是不占一行）。
    private var drawn: [AgentThinkingSegment] {
        segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 整区文本：跟随判定与「内容变了要不要跟」都看它（一段变了整区就变了）。
    private var combinedText: String { drawn.map(\.text).joined(separator: "\n\n") }

    var body: some View {
        let drawn = self.drawn
        if !drawn.isEmpty {
            let expanded = AgentThinkingFold.isExpanded(phase: phase, manual: manual)
            VStack(alignment: .leading, spacing: AgentThinkingViewport.hairGap) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(expanded ? "▾" : "▸")
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.tertiary))
                    // 抬头（§3.33.4 第一行）：有 token 读数就照主人给的形制
                    // `Thinking  ~308 tokens`；没有读数（探针 / 无用量）退回旧摘要。
                    Text(tokens.map { AgentTurnUsageLines.thinking(tokens: $0, estimated: true) }
                         ?? AgentThinkingSummary.text(steps: steps,
                                                      elapsedSeconds: elapsedSeconds,
                                                      expanded: expanded,
                                                      language: language))
                        .font(Self.font)
                        .foregroundStyle(Theme.chat(.thinking, colorScheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(height: Self.collapsedHeight)
                .contentShape(Rectangle())
                .onTapGesture { onToggle(!expanded) }
                .accessibilityAddTraits(.isButton)
                // 步数 / 耗时 / 折展提示仍要读得到 —— 抬头只剩 token 数之后，它们进 tooltip。
                .help(AgentThinkingSummary.text(steps: steps,
                                                elapsedSeconds: elapsedSeconds,
                                                expanded: expanded,
                                                language: language))

                if expanded {
                    viewport(drawn)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // **高度 = min(内容实测高, 上限)**（§3.37）：折叠态一行；展开态贴着内容收，
            // 到 200pt 才停。两档之间**不加 `withAnimation`**（动画逐帧插值 = 又一档闪）。
            .frame(height: expanded
                   ? AgentThinkingViewport.expandedHeight(contentHeight: measuredContentHeight)
                   : Self.collapsedHeight,
                   alignment: .topLeading)
            // **判据①的计数点**（§3.33.4）：一个思考区一个锚 —— 折叠态也在，
            // 所以「页面上几个思考区」是可数的机械读数，不是靠数折叠头看出来的。
            // `tokens` 带上抬头那个数：判据② 拿它跟「合并后的区」对账（±0）。
            .background(AgentThinkingZoneAnchor(tokens: tokens ?? -1))
        }
    }

    /// 内容视口：**高度 = min(内容实测高, 178pt)**，超了才内部滚动（§3.37）。
    ///
    /// 段与段之间是**轻分隔**（§3.33.4）：一行发丝 + 极小字「第 N 步」。
    /// 它不是折叠头（点不动、不占一行抬头高度）—— 折展只有整区那一个口。
    private func viewport(_ segments: [AgentThinkingSegment]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(segments) { segment in
                        if segment.step > 1 {
                            stepDivider(segment.step)
                        }
                        AgentTranscriptText(text: segment.text, font: Self.font, highlight: highlight)
                            .foregroundStyle(Theme.chat(.thinking, colorScheme).opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // **判据③的计数点**：段锚带步号，探针按文档坐标排序核对 1→N。
                            .background(AgentThinkingSegmentAnchor(step: segment.step))
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                // **宽度必须吃满视口**：不给它，文档视图会按「理想宽」缩成一列字
                // （实测每字一行、文档高 14 万 pt），滚动位置与跟随读数就都失真了。
                .frame(maxWidth: .infinity, alignment: .leading)
                // **内容实测高**（§3.37）：挂在内容根上，读的是这一块**自然高**。
                // 只在量化值跨过一整行时才写 `@State`（写一次 = 一次重排）——
                // 「高度随每个 token 抖」与「内容短时留一大块空白」在同一个口径下都关掉。
                .background(ContentHeightSpy { raw in
                    let quantized = AgentThinkingViewport.quantizedContentHeight(raw)
                    guard quantized != measuredContentHeight else { return }
                    measuredContentHeight = quantized
                })
                // 跟随状态只被**人真的滚了**改写（内容长高不改它）：
                // 内容长高就刷新，「刚长高还没跟」会被误判成用户往上翻。
                //
                // 挂在**内容根**上而不是底部哨兵上：哨兵在滚出视口后会被回收，
                // 回收了就再也收不到滚动通知 ⇒ 跟随状态冻在「贴底」，人往上翻照样被拽回来。
                .background(ScrollOffsetSpy { distance in
                    let pinned = distance <= AgentScrollFollow.bottomTolerance
                    if pinned != follow.isPinnedToBottom {
                        follow.update(distanceToBottom: distance)
                    }
                })
            }
            // **视口高 = min(实测内容高, 178)**（§3.37）：内容少就只占内容那么多（不空一块），
            // 内容多就卡在 178 由内部滚动接手。**按整行量化**，所以不会一个 token 变一次。
            .frame(height: AgentThinkingViewport.expandedViewportHeight(
                contentHeight: measuredContentHeight))
            // **滚动条策略**（§3.33.2 ⑤）：运行中**隐藏** —— 内容每 50ms 长一截，指示器
            // 每次都得按新内容高重算滑块尺寸，那正是「闪」的来源；视口只有 178pt，
            // 一屏之内不需要位置指示。终态手动展开是**静态内容**，交回系统默认（可见）。
            .scrollIndicators(phase == .running ? .hidden : .visible)
            .onChange(of: combinedText) { _, _ in
                // 只在贴着底时跟；**不带动画**（动画版每个增量都重启一次巡航，永远跑不完）。
                guard follow.shouldFollow else { return }
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
            .onAppear {
                follow.update(distanceToBottom: 0)
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    /// 步骤边界：**一行发丝 + 极小字「第 N 步」**（§3.33.4 契约②：轻分隔，不是多级折叠头）。
    ///
    /// 字取 `monoSmall`（比正文小一档）+ 三级文字色：读的时候是「翻页记号」，
    /// 不是又一个可点的标题 —— 台阶感在，块的割裂感不在。
    private func stepDivider(_ step: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Rectangle()
                .fill(Theme.hairline(colorScheme))
                .frame(height: Metrics.hairline)
            Text(LocalizedStrings.format(.agentChatThinkingStepLabel, language: language, step))
                .font(Theme.font(.monoSmall))
                .foregroundStyle(Theme.text(.tertiary))
                .fixedSize()
        }
        .padding(.vertical, Spacing.s)
    }
}

// MARK: - 探针锚（详设 §3.33.4 判据①③⑤）

/// 一个**思考区实例**的记号（零行为、零尺寸语义）。
///
/// 为什么要它：判据① 要的是「页面上有几个思考区」这个**数**。折叠态没有滚动容器、
/// `Text` 也不落成 `NSTextField`（本仓已登记的边界）—— 靠在文档树里找一个**专门的类型**
/// 才是机械读数：一个区一个锚，按 step 实例化的话它就跟着变成 N 个。
///
/// `tokens` = 抬头**实际画出来**的那个数（判据② 拿它跟合并后的区对账，不是另算一遍）。
final class AgentThinkingZoneMarker: NSView {
    var tokens: Int = -1
}

struct AgentThinkingZoneAnchor: NSViewRepresentable {
    var tokens: Int = -1

    func makeNSView(context: Context) -> AgentThinkingZoneMarker {
        let view = AgentThinkingZoneMarker()
        view.tokens = tokens
        return view
    }

    func updateNSView(_ view: AgentThinkingZoneMarker, context: Context) {
        view.tokens = tokens
    }
}

/// 一个**段**的记号：带步号，探针按文档坐标排序核对「1→N」的顺序保真（判据③）。
final class AgentThinkingSegmentMarker: NSView {
    var step: Int = 0
}

struct AgentThinkingSegmentAnchor: NSViewRepresentable {
    let step: Int

    func makeNSView(context: Context) -> AgentThinkingSegmentMarker {
        let view = AgentThinkingSegmentMarker()
        view.step = step
        return view
    }

    func updateNSView(_ view: AgentThinkingSegmentMarker, context: Context) {
        view.step = step
    }
}

/// 一个**工具块实例**的记号（判据⑤：合并思考区之后工具的个数与行高都不许变）。
final class AgentToolBlockMarker: NSView {}

/// **结论正文**的记号（判据：汇总区与结论之间的间距 —— §3.37 契约⑩）。
///
/// 判据要的那条距离是「Σ 行底边 → 结论首行顶边」，两端各要一个可机械取的几何点：
/// Σ 行有 `AgentTurnUsageRowMarker`（`.total`），结论这一侧就是它。
final class AgentAnswerStartMarker: NSView {}

struct AgentAnswerStartAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AgentAnswerStartMarker { AgentAnswerStartMarker() }
    func updateNSView(_ view: AgentAnswerStartMarker, context: Context) {}
}

struct AgentToolBlockAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AgentToolBlockMarker { AgentToolBlockMarker() }
    func updateNSView(_ view: AgentToolBlockMarker, context: Context) {}
}


// MARK: - 一轮的三行汇总（详设 §3.33.4 契约六~八）

/// **「Tool calls (N)  ~M tokens」那一行**（§3.33.4 契约七）：默认折成一行；
/// 展开后**逐个调用各一行 20pt**（§3.33 的口径不变：一次调用 = 一行摘要）。
///
/// 为什么工具要收进这一行、而不是继续按消息各占一行：一轮 56 次调用就是 56 行，
/// 结论被顶出屏幕（§3.33.1 ④ 的老问题）。收成一行之后**次数与 token**还在一眼可见的位置，
/// 明细点开就有 —— 且明细仍是每调用一行，不是一坨文本。
struct AgentToolCallsSummaryRow: View {

    /// 本轮工具**调用次数**（读数，不是行数）。
    let count: Int
    /// 这些调用的 token 合计。
    let tokens: Int
    /// 本轮每条工具消息的原文（一次调用一条）。
    let texts: [String]
    let expanded: Bool
    let highlight: String?
    let language: AppLanguage
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// 折叠态 = 一行（与工具块、思考区同一档）。
    static let collapsedHeight: CGFloat = Metrics.listRowHeight
    /// 展开后明细的上限（超了在内部滚，不把结论顶走）。
    static let bodyMaxHeight: CGFloat = AgentToolBlockView.bodyMaxHeight

    private static let font = Theme.font(.mono)

    /// 展开后的**总行数**：一行一次调用（解析不出的那条按 1 行算，因为
    /// `AgentToolCallRow` 认不出时就是原样一行）。§3.37 的行体高度直接吃这个数。
    private var bodyRowCount: Int {
        texts.reduce(0) { $0 + max(1, AgentToolLines.rows($1).count) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            Button(action: onToggle) {
                HStack(spacing: Spacing.s) {
                    Text(expanded ? "▾" : "▸")
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.tertiary))
                    Text(AgentTurnUsageLines.toolCalls(count: count, tokens: tokens, estimated: true))
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: Self.collapsedHeight)
            .help(expanded ? LocalizedStrings.text(.agentChatCollapse, language: language)
                  : LocalizedStrings.text(.agentChatExpand, language: language))

            if expanded {
                // 行体高 = **min(总行数 × 行高, 216pt)**（§3.37）：一次调用就一行高，
                // 56 次调用才到上限并在内部滚。行数由文本现算（一行一次调用），不抖。
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Spacing.hair) {
                        ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                            AgentToolCallRow(text: text,
                                             highlight: highlight,
                                             language: language)
                        }
                    }
                }
                .frame(height: AgentProcessBody.height(rows: bodyRowCount,
                                                       spacing: Spacing.hair,
                                                       cap: Self.bodyMaxHeight))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **判据计数点**（§3.33.4 判据 A）：一眼能数「页面上几个 Tool calls 行」。
        .background(AgentTurnUsageRowAnchor(kind: .toolCalls, tokens: tokens))
    }
}

/// **一次工具调用 = 一行 20pt**（§3.33.4：Tool calls 展开后的内部行，§3.33 口径不变）。
struct AgentToolCallRow: View {

    /// 这条工具消息的原文（一行一次调用；解析不出的行原样画）。
    let text: String
    let highlight: String?
    let language: AppLanguage

    @Environment(\.colorScheme) private var colorScheme

    private static let font = Theme.font(.mono)

    var body: some View {
        let rows = AgentToolLines.rows(text)
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                // 认不出的过程行：**原样**一行（既不吞字也不猜）。
                Text(TranscriptHighlight.apply(highlight, to: AttributedString(text)))
                    .font(Self.font)
                    .foregroundStyle(Theme.text(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: AgentToolBlockView.collapsedHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Spacing.s) {
                        Text("├─ ⏺")
                            .font(Self.font)
                            .foregroundStyle(Theme.text(.tertiary))
                        Text(TranscriptHighlight.apply(highlight,
                                                       to: AttributedString(AgentToolLines.callText(row))))
                            .font(Self.font)
                            .foregroundStyle(row.outcome == .running
                                             ? Theme.chat(.command, colorScheme).opacity(0.7)
                                             : Theme.chat(.command, colorScheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if case let .failure(reason) = row.outcome {
                            Text("✗ " + reason)
                                .font(Self.font)
                                .foregroundStyle(Theme.status(.danger))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: AgentToolBlockView.collapsedHeight)
                }
            }
        }
        // 判据⑤ 的计数点：一次调用一个 20pt 记号（工具个数与行高都不许被合并吞掉）。
        .background(AgentToolBlockAnchor())
    }
}

/// **「Σ ~324 total」那一行**（§3.33.4 契约八）：一轮 token 合计；展开看三项分项。
///
/// `Σ` 的口径写死在 `Core/AgentTurnUsage.totalTokens`（= thinking + tools + output），
/// tooltip 里再说一遍 —— 「合计是哪几项相加」不写在能被读到的地方，等于没写。
struct AgentTurnTotalRow: View {

    let usage: AgentTurnUsage
    let expanded: Bool
    let language: AppLanguage
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    static let rowHeight: CGFloat = Metrics.listRowHeight
    private static let font = Theme.font(.mono)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: Spacing.s) {
                    Text(expanded ? "▾" : "▸")
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.tertiary))
                    Text(AgentTurnUsageLines.total(tokens: usage.totalTokens, estimated: usage.isEstimated))
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: Self.rowHeight)
            .help(AgentTurnUsageLines.totalHelp(usage, language: language))

            if expanded {
                ForEach(Array(AgentTurnUsageLines.breakdown(usage).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: Spacing.s) {
                        Text(item.label)
                            .font(Self.font)
                            .foregroundStyle(Theme.text(.tertiary))
                            .frame(width: Self.labelWidth, alignment: .leading)
                        Text(item.value)
                            .font(Self.font)
                            .foregroundStyle(Theme.text(.secondary))
                        Spacer(minLength: 0)
                    }
                    .frame(height: Self.rowHeight)
                    .padding(.leading, Metrics.listIndent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AgentTurnUsageRowAnchor(kind: .total, tokens: usage.totalTokens))
    }

    /// `thinking` / `output` 两档标签的固定列宽（三档对齐，读数不跳）。
    private static let labelWidth: CGFloat = Spacing.l * 4
}

/// 三行汇总里「几行」的**计数点**（§3.33.4 判据 A）：一行一个记号。
///
/// 为什么不复用折叠头去数：`Button` 在离屏宿主里落成 `NSButton`、文字不落 `NSTextField`，
/// 数行只能靠显式记号；思考那一行用 `AgentThinkingZoneMarker`（它就是区本身）。
final class AgentTurnUsageRowMarker: NSView {
    /// `toolCalls` / `total`（思考行由思考区自己的锚计）。
    enum Kind: String { case toolCalls, total }
    var kind: Kind = .toolCalls
    /// 这一行**实际画出来**的 token 数（判据：Σ 行 == thinking + tools + output）。
    var tokens: Int = -1
}

struct AgentTurnUsageRowAnchor: NSViewRepresentable {
    let kind: AgentTurnUsageRowMarker.Kind
    var tokens: Int = -1

    func makeNSView(context: Context) -> AgentTurnUsageRowMarker {
        let view = AgentTurnUsageRowMarker()
        view.kind = kind
        view.tokens = tokens
        return view
    }

    func updateNSView(_ view: AgentTurnUsageRowMarker, context: Context) {
        view.kind = kind
        view.tokens = tokens
    }
}
