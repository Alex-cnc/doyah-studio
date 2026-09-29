import Foundation
import DoyahCore

/// 对象树里的一行：**真对象行**，或分组视图下的**虚拟类型表头**（FR-META-15）。
struct ObjectTreeVisibleRow: Identifiable {
    let object: DatabaseObject
    let depth: Int
    let isExpandable: Bool
    let isExpanded: Bool
    let isLoading: Bool
    let error: String?
    let children: [DatabaseObject]?
    /// 分组视图下的虚拟类型表头（不是真实数据库对象）。
    let isGroupHeader: Bool

    var id: String { object.id }
}

/// 对象树的**可见行模型**（FR-META-15）：把这几个状态摊平成一维行数组。
///
/// ## 为什么它从视图里搬出来（队列 `L-89` ㈡ 第 6 条 · 分组视图那一行）
///
/// 待人工验收清单里那一行的人话是「对象树顶部在「层级视图 / 按类型分组」之间切换 →
/// **两种视图都能用；切换后选中项不丢**」。这句话在「单测 + 人工一眼」里挂了很多轮，
/// 而它的**主体就是这里这段摊平逻辑**：换视图 = 对同一份缓存重新聚合（`groupByType` 为真时
/// 在已展开的容器下插一层类型表头），**不重新查库**。原来它是 `ObjectTreeView` 的
/// `private var` ⇒「换视图之后行集合对不对」「选中项那一行还在不在」只能靠人眼看。
///
/// 搬成**纯函数**（输入只有：根节点、展开集合、子节点缓存、在途集合、错误表、视图模式、语言）之后，
/// 这两件事都能拿**真库读回来的对象**当输入机械判（见
/// `TestsUISnapshot/GroupedViewProbeTests.swift`），而「切视图不重查库」也不再只是注释里的
/// 一句承诺 —— 这个文件**没有任何取数能力**（不 import 驱动、不碰 `AppState`、不调 `loadMetadata*`）。
///
/// 生产路径只有一个调用者（`ObjectTreeView.visibleRows`）；行为与搬出前逐字一致。
enum ObjectTreeRows {

    /// 摊平成可见行。
    ///
    /// - Parameters:
    ///   - roots: 根节点（通常是服务器节点）。
    ///   - expandedIDs: 已展开节点的 id 集合。
    ///   - childrenCache: `节点 id → 已加载的子节点`（空数组 = 加载过但没有子节点）。
    ///   - loadingIDs: 正在加载子节点的节点 id 集合（那一行下面画「正在加载…」）。
    ///   - errors: `节点 id → 加载失败文案`（那一行下面画那句人话）。
    ///   - groupByType: 是否按类型分组（分组只对**已缓存的子节点**做聚合 ⇒ 切视图不重新查库）。
    ///   - language: 分组表头文案的语言（界面语言由调用方按**生效语言**给出）。
    static func visibleRows(
        roots: [DatabaseObject],
        expandedIDs: Set<String>,
        childrenCache: [String: [DatabaseObject]],
        loadingIDs: Set<String> = [],
        errors: [String: String] = [:],
        groupByType: Bool,
        language: AppLanguage
    ) -> [ObjectTreeVisibleRow] {
        var rows: [ObjectTreeVisibleRow] = []

        func visit(_ object: DatabaseObject, depth: Int) {
            let isExpanded = expandedIDs.contains(object.id)
            rows.append(
                ObjectTreeVisibleRow(
                    object: object,
                    depth: depth,
                    isExpandable: object.isExpandable,
                    isExpanded: isExpanded,
                    isLoading: loadingIDs.contains(object.id),
                    error: errors[object.id],
                    children: childrenCache[object.id],
                    isGroupHeader: false
                )
            )

            if isExpanded, let children = childrenCache[object.id] {
                if groupByType {
                    // 分组只对**已缓存的子节点**做聚合，因此切换视图不触发重新查库。
                    for group in ObjectTreeGrouping.groupedByType(
                        children,
                        parentID: object.id,
                        language: language
                    ) {
                        rows.append(
                            ObjectTreeVisibleRow(
                                object: DatabaseObject(
                                    id: group.id,
                                    name: group.title(language: language),
                                    kind: ObjectTreeGrouping.headerKind(for: group.kind),
                                    detail: "\(group.count)"
                                ),
                                depth: depth + 1,
                                isExpandable: false,
                                isExpanded: false,
                                isLoading: false,
                                error: nil,
                                children: nil,
                                isGroupHeader: true
                            )
                        )
                        for child in group.objects {
                            visit(child, depth: depth + 2)
                        }
                    }
                } else {
                    for child in children {
                        visit(child, depth: depth + 1)
                    }
                }
            }
        }

        for root in roots {
            visit(root, depth: 0)
        }
        return rows
    }
}
