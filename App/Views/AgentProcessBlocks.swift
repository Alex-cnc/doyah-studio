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
                // 行体**在内部滚动、有上限**：300 次调用不会把这一块撑成 6000pt。
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
                .frame(maxHeight: Self.bodyMaxHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 折叠态**钉成一行**（20pt）：这一块的高度是常量，探针拿它当判据。
        .frame(height: expanded ? nil : Self.collapsedHeight, alignment: .topLeading)
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

/// **思考区**（详设 §3.33「思考区三态」）：过程独白（以及打开的思考段）只住在这里。
///
/// ## 三态（人类主人 2026-11-07 拍的产品决策）
///
/// 1. **运行中（本轮未结束）** ⇒ 默认**展开**，可流式增量显示，限高 `contentMaxHeight`
///    （整块 ≤ `expandedMaxHeight` = 200pt）且内部滚动；用户可手动收起。
/// 2. **任一终态**（完成 / 失败 / 取消）⇒ **自动折成一行**摘要：
///    `思考过程 · 12 步 · 18.4s · 展开`（`collapsedHeight` = 一行）。
/// 3. **用户手动展开后** ⇒ 本轮内保持（sticky），**不许**每帧 / 每个新事件又折回去；
///    新轮开始才回到「按阶段默认」—— sticky 与轮次作用域都在 Core
///    （`AgentThinkingFold` / `AgentThinkingManualState`），视图只读结论。
///
/// 「哪一段算独白」也**不在这里**判：`AgentAnswerClassifier` 给，视图只画。
///
/// ## 流式期间的三条（详设 §3.33.2，beta1.0.4 真机「滚动条很闪」）
///
/// · **固定视口**：展开态整块**恒 200pt**（抬头 20 + 发丝 2 + 视口 178），内容只在视口里滚；
/// · **条件跟随**：只有用户贴着底时才跟着新内容走，往上翻就停手（`AgentScrollFollow`）；
/// · **运行中不画滚动指示器**：内容每 50ms 长一截，滑块尺寸每次重算就是闪的来源；
///   终态手动展开是静态内容，交回系统默认。
struct AgentThinkingZone: View {

    /// 这一格的内容：过程独白（必先是它）+ 思考段（开关打开时才有）。
    let text: String
    let phase: AgentThinkingPhase
    /// `nil` = 用户没动过（按阶段默认）。
    let manual: Bool?
    let steps: Int
    let elapsedSeconds: Double?
    let highlight: String?
    let language: AppLanguage
    let onToggle: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// 折叠态高度：**一行摘要**（= 一行等宽字）。
    static let collapsedHeight: CGFloat = AgentThinkingViewport.collapsedHeight

    /// 展开态**内容视口**的高度（定值，不跟内容长）：200 − 20 − 2 = **178pt**。
    static let contentMaxHeight: CGFloat = AgentThinkingViewport.viewportHeight

    /// 展开态整块高度（恒为 200pt；`maxHeight` 的旧名保留给既有判据）。
    static var expandedMaxHeight: CGFloat { AgentThinkingViewport.totalHeight }

    private static let font = Theme.font(.mono)

    /// 内容末尾那个 1pt 哨兵的 id（自动跟随的锚）。
    private static let bottomAnchor = "agentThinkingBottom"

    /// **条件跟随**（§3.33.2 ③）：只在贴着底时跟；用户往上滚就停手。
    ///
    /// 只在「是不是贴底」**真的翻转**时写它 —— 每像素滚一下都写 `@State` 就等于
    /// 把「不闪」拆掉一半（每次写都重算这一格）。
    @State private var follow = AgentScrollFollow()

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = AgentThinkingFold.isExpanded(phase: phase, manual: manual)
            VStack(alignment: .leading, spacing: AgentThinkingViewport.hairGap) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(expanded ? "▾" : "▸")
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.tertiary))
                    Text(AgentThinkingSummary.text(steps: steps,
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
                .help(expanded ? LocalizedStrings.text(.agentChatCollapse, language: language)
                      : LocalizedStrings.text(.agentChatExpand, language: language))

                if expanded {
                    viewport(trimmed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // **两档定高**（§3.33.2 ④）：20pt / 200pt，中间没有第三个数 ——
            // 折叠与展开是**直接切档**，不加 `withAnimation` 改高度（动画期间尺寸逐帧插值，
            // 看着就是又一档闪）。
            .frame(height: AgentThinkingViewport.height(expanded: expanded), alignment: .topLeading)
        }
    }

    /// 内容视口：**定高 178pt + 内部滚动**（不跟内容长 —— 整块对外恒 200pt）。
    private func viewport(_ text: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    AgentTranscriptText(text: text, font: Self.font, highlight: highlight)
                        .foregroundStyle(Theme.chat(.thinking, colorScheme).opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                        // 跟随状态只被**人真的滚了**改写（内容长高不改它）：
                        // 内容长高就刷新，「刚长高还没跟」会被误判成用户往上翻。
                        .background(ScrollOffsetSpy { distance in
                            let pinned = distance <= AgentScrollFollow.bottomTolerance
                            if pinned != follow.isPinnedToBottom {
                                follow.update(distanceToBottom: distance)
                            }
                        })
                }
                // **宽度必须吃满视口**：不给它，文档视图会按「理想宽」缩成一列字
                // （实测每字一行、文档高 14 万 pt），滚动位置与跟随读数就都失真了。
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // **命门：定高而不是上限**。改前是 `maxHeight`，内容短时 `ScrollView`
            // 会缩到内容高 ⇒ 每来一段增量整块高度就变一次、下面的正文被推一次。
            .frame(height: Self.contentMaxHeight)
            // **滚动条策略**（§3.33.2 ⑤）：运行中**隐藏** —— 内容每 50ms 长一截，指示器
            // 每次都得按新内容高重算滑块尺寸，那正是「闪」的来源；视口只有 178pt，
            // 一屏之内不需要位置指示。终态手动展开是**静态内容**，交回系统默认（可见）。
            .scrollIndicators(phase == .running ? .hidden : .visible)
            .onChange(of: text) { _, _ in
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
}
