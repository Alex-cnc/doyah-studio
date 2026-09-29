import SwiftUI
import DoyahCore

/// 连接表单里那两段「跟着方言走」的控件：**数据库类型那一台**（换方言时把端口与 SSL 收敛过来）
/// 与 **SSL 模式那一行**（按方言列模式 + 收窄说明）。
///
/// ## 为什么抽出来（唯一理由 —— 与第 96 轮 `LowerPaneTabStrip` / 第 101 轮 `ObjectTreeToolbar` 同款）
///
/// 在 `Form(.grouped)` 里，macOS 27 的 SwiftUI 把 `Picker` **自己画**：2026-09-29 第 105 轮实测，
/// 整棵宿主视图树里**没有**一个 `NSPopUpButton`（只有一堆 `_NSGraphicsView`）⇒ 离屏宿主里
/// 既找不到那台控件、也就点不动它，而「换一下方言，端口那一格当场变成 3306」这件事
/// **只有真点一下**才判得动（常量 `defaultPort == 3306` 的单测判不出联动）。
/// 抽成独立视图之后，判据的做法是：把**产品这两个视图**接到一个夹具上、从绑定那一侧推状态变化
/// （等于在界面里换方言），再断言 ① 绑定侧 ② **界面上那一格真 `NSTextField` 的正文**。
/// **「那台下拉点不动」这件事本身也是本轮的实测结论**，写进文件头与判据（探针里装了哨兵：
/// 哪天 SwiftUI 换回真控件，哨兵先红，提醒把「点一下」升级成真点击）。
///
/// **行为逐字不变**：两段代码原样搬过来，`ConnectionFormView` 用同一批绑定把它们放回原位 ——
/// 端口那一格与 host / database 一起仍留在表单里，位置与顺序都不动。
/// 换方言时表单要跟着变的那几件事 —— **唯一出处**（界面与判据共用同一份）。
///
/// ## 为什么要有它（而不是让 `.onChange` 里现算）
///
/// 本机 SwiftUI 的 `Picker` **不落到 AppKit 控件**（2026-09-29 第 105 轮实测：整棵宿主视图树里
/// 没有 `NSPopUpButton`，Picker 由 SwiftUI 自绘）⇒ 判据既**点不到**那台下拉、也**读不到**它的条目。
/// `EgressLogSheet` 当年遇到同一个问题，处置是「把它搬成能直接断言的东西」（`EgressTabOptions`）；
/// 这里照做：端口 / SSL 默认值 / SSL 清单三件事**只在这一处算**，界面读它、判据也读它。
/// 「界面真的读了它」由探针脚本的**源锚点**守（第 101 轮的教训：判据与界面脱钩就白判）。
enum ConnectionDialectLinkage {

    struct Adjustments: Equatable {
        /// 端口那一格要变成的正文。
        var port: String
        /// SSL 要落到的模式（方言默认值）。
        var sslMode: SSLMode
        /// 换方言 ⇒ 上一次那条「被收敛过」的黄字说明失效，必须清掉（R-53）。
        var adjusted: SSLMode?
        /// SSL 那一台的条目（**按方言列**；显示名也按方言取，`verify-full` 在 MySQL 下叫 `Verify Identity`）。
        var sslModes: [SSLMode]

        /// 条目文案 —— 界面画的就是这一份（判据读同一份，不另写一遍）。
        var sslModeTitles: [String] { sslModes.map { $0.displayName(for: dialect) } }
        /// 上面那几个显示名是按哪个方言取的（判据要用同一个方言拼期望值）。
        var dialect: DatabaseType = .postgresql
    }

    /// 方言那一台的条目（唯一出处：界面 `ForEach` 的就是这一份，判据读同一份）。
    static let dialects: [DatabaseType] = DatabaseType.allCases

    /// 方言那一台画出来的文案 —— 界面画的就是这一份（判据读同一份，不另写一遍）。
    static var dialectTitles: [String] { dialects.map { $0.displayName } }

    /// 换到 `type` 这个方言时，那三件事要变成什么。
    static func adjustments(for type: DatabaseType) -> Adjustments {
        Adjustments(
            port: String(type.defaultPort),
            sslMode: type.defaultSSLMode,
            adjusted: nil,
            sslModes: type.sslModes,
            dialect: type
        )
    }
}

struct ConnectionDialectPicker: View {
    @Binding var dbType: DatabaseType
    @Binding var port: String
    @Binding var sslMode: SSLMode
    @Binding var sslModeWasAdjusted: SSLMode?

    var body: some View {
        Picker(L(.connectionFormDbType), selection: $dbType) {
            ForEach(ConnectionDialectLinkage.dialects) { type in
                Text(type.displayName).tag(type)
            }
        }
        .onChange(of: dbType) { _, newValue in
            // 换方言 = 换一份支持清单（R-53）：`allow` 是 PG 专属，MySQL 没有它。
            // 无脑重置为方言默认值是**有意的**：把 PG 的 `allow` 原样带到 MySQL 上
            // 就是一个"标签撒谎"的组合（见 `DatabaseType.sslModes`）。
            // 三个值只在一处算（`ConnectionDialectLinkage`）——判据读同一份。
            let next = ConnectionDialectLinkage.adjustments(for: newValue)
            port = next.port
            sslMode = next.sslMode
            sslModeWasAdjusted = next.adjusted
        }
    }
}

/// SSL 模式那一行：**按方言列出**模式 + 两句说明之一（被收敛过 ⇒ 黄字说明；这个方言少一档 ⇒ 小字）。
struct ConnectionSSLModeRow: View {
    let dbType: DatabaseType
    @Binding var sslMode: SSLMode
    @Binding var sslModeWasAdjusted: SSLMode?

    var body: some View {
        // SSL 模式**按方言列出**（R-53）：MySQL 系没有 PG 的 `allow`，
        // 摊开六个选项等于让用户选一个我们不认识、也没法真的照做的模式。
        VStack(alignment: .leading, spacing: 2) {
            Picker(L(.connectionFormSSLMode), selection: $sslMode) {
                ForEach(ConnectionDialectLinkage.adjustments(for: dbType).sslModes) { mode in
                    Text(mode.displayName(for: dbType)).tag(mode)
                }
            }
            if let adjusted = sslModeWasAdjusted {
                Text(L(.connectionFormSSLModeAdjusted, adjusted.displayName, sslMode.displayName(for: dbType)))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                    .fixedSize(horizontal: false, vertical: true)
            } else if dbType.sslModes.count != SSLMode.allCases.count {
                Text(L(.connectionFormSSLModeNarrowed))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
