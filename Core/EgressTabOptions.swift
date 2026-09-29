import Foundation

/// 外发日志里「按浏览器页签筛」那台下拉的**选项推导**（FR-EDIT-34）。
///
/// 为什么单独一层：它原先写在 `EgressLogSheet` 的 `private var tabOptions` 里 —— 于是
/// 「日志里出现过的页签」这件事**只有渲染出来才看得见**，判据只能去读界面控件；
/// 而 2026-09-29 实测本机 SwiftUI 的 `Picker` **不落到 AppKit 控件**
/// （把 `EgressLogSheet` 渲染进离屏宿主后，视图树里找不到任何 `NSPopUpButton`，
/// 只有 `NSHostingView` / `HostingScrollView` 那几层）⇒ 搬成纯函数之后，判据可以拿
/// **盘上读回来的真记录**直接判它（见 `TestsUISnapshot/BrowserTabDownloadProbeTests.swift`）。
/// 与第 96 / 101 轮抽 `LowerPaneTabStrip` / `ObjectTreeRows` 同一个理由：**能单独断言**。
///
/// 口径（与从前逐字一致，只是换了个位置）：
///   · 选项从**日志本身**派生，不是从「当前开着的页签」派生 —— 关掉页签后那些记录仍要能被筛出来；
///   · 只收带页签身份的记录（`tabID != nil`），非浏览器来源不占选项；
///   · 顺序 = 日志里**首次出现的顺序**（日志本身新的在前）；
///   · 标签取该页签的标题，缺标题时退回 id 前 8 位；当前标签**短于 12 字**时允许被后来的标题替换
///     （标题可能先是地址、后来才成真标题）。
public enum EgressTabOptions {

    /// 一台下拉里的一个选项（页签 id + 显示名）。
    public struct TabOption: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let label: String

        public init(id: UUID, label: String) {
            self.id = id
            self.label = label
        }
    }

    /// 允许被「后来的标题」替换的标签长度上限 —— **唯一来源**，界面与判据共用，不各写一个。
    public static let replaceableLabelLength = 12

    public static func options(from entries: [EgressEntry]) -> [TabOption] {
        var seen: [UUID: String] = [:]
        var order: [UUID] = []
        for entry in entries {
            guard let tabID = entry.tabID else { continue }
            if seen[tabID] == nil {
                order.append(tabID)
                seen[tabID] = entry.tabTitle ?? String(tabID.uuidString.prefix(8))
            } else if seen[tabID]?.count ?? 0 < replaceableLabelLength,
                      let title = entry.tabTitle, !title.isEmpty {
                seen[tabID] = title
            }
        }
        return order.map { TabOption(id: $0, label: seen[$0] ?? String($0.uuidString.prefix(8))) }
    }
}
