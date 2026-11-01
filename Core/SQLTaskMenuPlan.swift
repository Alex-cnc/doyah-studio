import Foundation

/// 工具栏「任务」菜单的**内容判定**（`FR-STD-DB-TASK-001` 的交付面）。
///
/// ## 为什么菜单内容要单拎一份到 Core
///
/// 这条需求在台账上剩的那一格是「差人工点一次」：菜单长什么样、点哪一项会发生什么，
/// 此前**只存在于** `QueryToolbar.taskMenu` 那段 SwiftUI `Menu` 的闭包体里 ——
/// 离屏宿主里 SwiftUI `Menu` 不落任何可点的 AppKit 控件（与 `PanelIconButton` 文件头
/// 记的实测同一类），于是「点了之后到底怎样」一次都没人量过。
///
/// 现在把「这一份菜单该有哪些行」收成一份纯值：视图侧的 AppKit 菜单
/// （`App/Views/SQLTaskAppKitMenu.swift`）照它铺、探针照它判，**两边读的是同一处**。
/// 各自判一遍（视图里写一套 `if`、探针里再猜一套）就会在加一项时只改一半。
///
/// ## 行里写什么
///
/// 一条任务只写名字的话，同名不同库的两条定义在菜单里长得一模一样 ——
/// 用户点下去之前分不出哪条是哪个库的。所以每行固定四段：
/// **名字 · 目标库 · 只读还是可写 · 上限（有才写）**，分隔符 ` · `。
public struct SQLTaskMenuPlan: Equatable, Sendable {

    /// 可载入的一条任务（菜单行 + 删除子菜单里的那一项）。
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let targetDatabase: String
        public let accessMode: SQLTaskDefinition.AccessMode
        public let rowLimit: Int?

        public init(
            id: UUID,
            name: String,
            targetDatabase: String,
            accessMode: SQLTaskDefinition.AccessMode,
            rowLimit: Int?
        ) {
            self.id = id
            self.name = name
            self.targetDatabase = targetDatabase
            self.accessMode = accessMode
            self.rowLimit = rowLimit
        }

        /// 菜单行文案：名字 · 库 · 模式 [· ≤ 上限]（空格与冒号都不用，`·` 是这一族菜单的统一分隔）。
        public func label(readOnlyText: String, writableText: String) -> String {
            var parts = [
                name,
                targetDatabase,
                accessMode == .readOnly ? readOnlyText : writableText,
            ]
            if let rowLimit {
                parts.append("≤ \(rowLimit)")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// 「保存当前脚本为任务…」这一项能不能点。
    ///
    /// 判据是**页签里有没有语句**（空白算没有）：空脚本存成任务，就是存了一条永远只能被拒的定义
    /// （`SQLTaskGuard` 会以「语句为空」拒它），而用户点的时候没人拦。
    public let saveEnabled: Bool
    /// 可载入的任务，**按传入顺序**（`AppState.sqlTasks` 已按 `updatedAt` 倒序，最近存的在最上面）。
    public let rows: [Row]
    /// 当前页签绑定的那一条（没有就是 `nil`）。
    public let bound: Row?

    /// 任务册子是空的 —— 菜单里要有一句人话，而不是一条空荡荡的菜单。
    public var isEmpty: Bool { rows.isEmpty }

    public init(saveEnabled: Bool, rows: [Row], bound: Row?) {
        self.saveEnabled = saveEnabled
        self.rows = rows
        self.bound = bound
    }

    /// 唯一的构造入口：页签里有什么、册子里有什么、绑了哪一条 ⇒ 菜单该长什么样。
    ///
    /// - Parameters:
    ///   - tasks: 已保存的任务（调用方给什么顺序就按什么顺序铺）。
    ///   - tabSQL: 当前页签的语句 —— 只用来判「保存」那一项能不能点。
    ///   - boundTaskID: 页签绑定的任务 id（`nil` = 没绑）。
    public static func make(
        tasks: [SQLTaskDefinition],
        tabSQL: String,
        boundTaskID: UUID?
    ) -> SQLTaskMenuPlan {
        let rows = tasks.map {
            Row(
                id: $0.id,
                name: $0.name,
                targetDatabase: $0.targetDatabase,
                accessMode: $0.accessMode,
                rowLimit: $0.rowLimit
            )
        }
        // 绑定项**从册子里取**，不是从「上一次点击」里记：任务被删掉之后，
        // 残留的 id 不该让菜单继续写「本页签绑定任务：被删掉的那条」。
        let bound = boundTaskID.flatMap { id in rows.first { $0.id == id } }
        return SQLTaskMenuPlan(
            saveEnabled: !tabSQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            rows: rows,
            bound: bound
        )
    }
}
