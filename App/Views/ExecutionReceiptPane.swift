import SwiftUI
import DoyahCore

/// 下方面板的「回执」页（`FR-STD-DB-TASK-003`）：本查询页签上每一跑的**执行回执**。
///
/// ## 与「输出」的分工（口径写在这里，免得下一个人把它并进输出）
///
/// · **输出**是**过程流水**：每次执行清空重来（2026-09-27 需求提出者的原话），回答「刚才那一跑
///   中间发生了什么」；
/// · **回执**是**审计读数**：成功 / 失败 / 被拦下 / 取消各留一条，不随后一跑消失，回答
///   「这一跑动了什么、多久、哪里错了」。需求写着「挂在会话上可作为审计依据」，所以它跟着
///   页签走（关页签即随之消失），长期留档那条路是查询归档（按天一个 `.sql`）。
///
/// ## 视图里只做三件事
///
/// ① 取数：读 `tab.receiptLog`（**唯一出处**，视图不自己攒一份）；
/// ② 渲染：每条的正文由 `ExecutionReceipt.render(labels:)` 出 —— 排版与字段次序在 Core 里，
///    这里只管摆位置（同一份回执在剪贴板、导出文件、界面上是同一段文本）；
/// ③ 动作：复制 / 导出 / 清空三枚，全部落到 `AppState` 的方法上（空数据时给一句理由，
///    处置登记在 `Scripts/empty-action-button-dispositions.json`）。
struct ExecutionReceiptPane: View {

    @EnvironmentObject private var appState: AppState
    let tab: QueryTab?

    /// 新的在前（最近一跑最容易被找）。
    private var receipts: [ExecutionReceipt] {
        tab?.receiptLog.newestFirst ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if receipts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(receipts) { receipt in
                            block(receipt)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: 工具条

    private var toolbar: some View {
        HStack(spacing: Spacing.hair) {
            Text(L(.lowerPaneReceipts))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))

            Spacer(minLength: Spacing.s)

            // 三枚动作**常驻**（空数据时可点并给一句理由 —— 与「外发日志」那一档同一处置；
            // 藏起来会让「为什么这里没有复制」多一次提问）。图标 + 提示（`NFR-UI-01`）。
            //
            // 是**真 `NSButton`**（`PanelIconButton`，不是 SwiftUI `Button`）：这三枚是验收要点里
            // 写着要点的动作，而 SwiftUI `Button` 在离屏宿主里不落成 `NSButton`、无障碍树也不构建
            // ⇒ 探针一次都点不到、只能靠人点（口径与 `ResultFilterPopup` / `TitleBarSearchBox` 同源）。
            PanelIconButton(systemName: "doc.on.doc", help: L(.receiptCopyAll), label: L(.receiptCopyAll)) {
                if let tab { appState.copyReceipts(for: tab.id) }
            }

            PanelIconButton(
                systemName: "square.and.arrow.down",
                help: L(.receiptExport),
                label: L(.receiptExport)
            ) {
                if let tab { _ = appState.exportReceipts(for: tab.id) }
            }

            PanelIconButton(systemName: "trash", help: L(.receiptClear), label: L(.receiptClear)) {
                if let tab { appState.clearReceipts(for: tab.id) }
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: 一条回执

    /// 一条回执 = 一段**可选中复制**的等宽文本（正文由 Core 渲染，视图不另排一套字段）。
    /// 左边一道细色条按结局取色：一眼能看出「这一跑成了没有」。
    private func block(_ receipt: ExecutionReceipt) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(tone(for: receipt.outcome))
                .frame(width: Spacing.hair)

            Text(receipt.render(labels: appState.receiptLabels))
                .font(Theme.font(.caption).monospaced())
                .foregroundStyle(Theme.text(.secondary))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
        }
    }

    /// 结局 → 色：成功绿 / 失败红 / 取消灰 / 未发出告警色（它与失败不是一回事，颜色也不该一样）。
    private func tone(for outcome: ExecutionOutcome) -> Color {
        switch outcome {
        case .succeeded: return Theme.status(.success)
        case .failed: return Theme.status(.danger)
        case .cancelled: return Theme.text(.tertiary)
        case .refused: return Theme.status(.warning)
        }
    }

    // MARK: 空态

    private var emptyState: some View {
        VStack(spacing: Spacing.s) {
            Spacer(minLength: 12)
            Image(systemName: "doc.text.magnifyingglass")
                .font(Theme.font(.title))
                .foregroundStyle(Theme.text(.tertiary))
            Text(L(.receiptEmpty))
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.secondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.m)
    }
}
