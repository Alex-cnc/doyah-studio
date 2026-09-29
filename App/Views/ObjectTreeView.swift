import SwiftUI
import DoyahCore

/// 数据库对象树。
///
/// 实现方式：**扁平化树**。
/// 不用「List 行里嵌套 DisclosureGroup」——那种结构在 SwiftUI `List` 中
/// 只有前两层可靠，第三层（schema → table）经常展不开。
/// 这里自己维护展开状态，把可见节点摊平成一维行数组，任意层级都能展开。
struct ObjectTreeView: View {
    @EnvironmentObject private var appState: AppState

    /// 服务器节点右键菜单「编辑连接…」的回调（由 `ConnectionListView` 传入）。
    var onEdit: ((ConnectionConfig) -> Void)?

    @State private var roots: [DatabaseObject] = []
    /// **这份树是哪个方言加载出来的** —— 不是"当前选中的连接是什么"。
    ///
    /// 为什么要分开（2026-09-25 需求提出者两次报同一件事）：空态文案原先按
    /// `appState.selectedConnection?.dbType` 选，而**首连 / 切连接的那一瞬间，两者可以不是同一件事**
    /// （选中项已经换了、树上还是上一份数据，或反过来）。于是出现了他报的那一幕：
    /// **MySQL 上点开一个空库，却写着「该数据库下暂无 schema」** —— 用的是另一个连接的方言。
    /// 改成在**加载这份树的时候**把方言记下来，文案就永远跟眼前这份数据同源。
    /// （顺带把 `?? .postgresql` 这个兜底去掉了：方言未知时不该冒充 PostgreSQL。）
    @State private var treeDatabaseType: DatabaseType?
    /// id → 已加载的子节点；值为空数组表示「加载过但没有子节点」。
    @State private var childrenCache: [String: [DatabaseObject]] = [:]
    @State private var expandedIDs: Set<String> = []
    @State private var loadingIDs: Set<String> = []
    @State private var errors: [String: String] = [:]
    /// 鼠标当前在哪一行（右键菜单按它决定内容，见 `ObjectTreeMenuTarget.resolve`）。
    ///
    /// **为什么用引用类型装、而不是 `@State`**（2026-09-24 需求提出者实测「鼠标放上去，对象数不停闪烁」）：
    /// `@State` 一写就让视图作废 → 整棵树重算 → 行视图被重建 → `onHover` 再触发一次 →
    /// 悬停状态来回翻，于是"鼠标停着不动，界面自己闪"。而这个盒子**没有任何观察者**：
    /// 写它不产生一次重绘，右键菜单在**呈现那一刻**读它即可。
    @State private var hoverBox = HoverBox()
    @State private var isLoadingRoot = false
    @State private var rootError: String?
    // 注：所有「弹出面板」的目标与开关都**不在这里** —— 它们住在 `AppState`
    // （`createTableTarget` / `alterTableTarget` / `isCreateDatabasePresented` …）。
    //
    // 为什么（2026-09-24 修闪烁时定的规矩）：呈现方必须挂在**单个视图**上。
    // 修饰符挂在 `Group` 上会被 SwiftUI **分发到每个子视图**，而对象树的内容就是"N 行",
    // 于是每个 sheet 各挂 N 份（实测 16 行 × 11 个 sheet），取消时逐个收起 ⇒ 界面连续闪烁。
    // 所以这 11 个 `.sheet` 现在由 `ConnectionListView` 挂在它那个唯一的 `List` 上，
    // 目标状态跟着上移到 AppState —— 与「按条件浏览 / 合成数据」同一套路（见下面原注）。
    // 原注（对本地 state 的告诫，仍然适用）：本地 state 与全局标志位各存一份，
    // 迟早出现"面板开了、对象却是上一个"。
    /// 是否按类型分组显示（FR-META-15）。切换只重新聚合缓存，不重新查库。
    @State private var groupByType = false

    var body: some View {
        Group {
            if appState.selectedConnection == nil {
                Text(L(.objectTreeSelectPrompt))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            } else if isLoadingRoot && roots.isEmpty {
                HStack(spacing: Spacing.s) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L(.treeLoadingObjects))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                }
            } else if let rootError {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(L(.treeLoadFailed), systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.status(.warning))
                    Text(rootError)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(4)
                        .textSelection(.enabled)
                    Button(L(.commonRetry)) {
                        Task { await reloadRoot() }
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, Spacing.hair)
            } else if roots.isEmpty {
                Text(L(.treeEmpty))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            } else {
                // 整棵树放进**一个** `List` 行里（下面的 `VStack`）：`List`（sidebar 样式）会给
                // 每个行加固定行距、且**不理会** `listRowInsets`（实测：行内容 22pt 却排成 28pt，
                // 清零与负内边距都没用）。把行距的所有权拿回来，树的密度才是我们说了算 ——
                // 需求提出者实测：「层级行与行的间隔太大了，显得很松散，表稍微多一点就要向下拉滚动条」。
                // 队列的副作用是"整棵树是一行"：它本来就自带选中高亮 / 右键菜单 / 点击展开，
                // 不依赖 `List` 的行级能力。
                VStack(alignment: .leading, spacing: 0) {
                    refreshRow
                    ForEach(visibleRows) { row in
                        // **每行各自挂一份菜单**（FR-META-14）：右键命中的就是**指针底下这一行**，
                        // 不再要求"先左键点一下把行钉进悬停记录"。
                        // 2026-09-29 需求提出者实测原话：「直接点右键几乎无法选择任意对象，要先鼠标
                        // 左键点一个对象才有几率右键打开」—— 根因是整棵树只有一份菜单、目标由悬停
                        // 记录决定，而 `onHover` 会在整树重算（选中态一变就重算）后被 SwiftUI 补一个
                        // 假的 `mouseExited` 清掉。行级菜单把这个不确定来源整个绕开。
                        rowView(row)
                            // **每一行自己接右键**（不碰坐标）：先选中本行，再把事件交还系统弹菜单。
                            .overlay(
                                RowRightClickCatcher(tag: row.id) {
                                    appState.selectTreeObject(row.object)
                                }
                            )
                            .contextMenu {
                                ObjectTreeContextMenu.items(
                                    object: row.object,
                                    appState: appState,
                                    onEdit: onEdit
                                )
                            }
                    }
                }
                // 收每行的框 + **右键即选中**：指针在哪一行，右键就把那一行设为选中
                // （本地事件监听，零授权；只读事件不改事件 ⇒ 系统照常弹菜单）。
                // 这一步是"已选中 A 时右键 B 选不中 B"的修法：行级 hover 在整树重算后必被清空，
                // 指针位置才是可靠事实。

                // 整棵树这一份**保留**：只用于右键点到行之外的空白（内边距 / 底下空区），
                // 内容仍按"鼠标底下那一行"算，没有就退回选中项。
                .contextMenu {
                    ObjectTreeContextMenu.items(
                        object: menuTargetObject,
                        appState: appState,
                        onEdit: onEdit
                    )
                }
            }
        }
        // 这里**不要**再加 `.id(appState.selectedConnectionID)`：
        // 那会让整棵子树被销毁重建，切连接 / 删连接时侧栏会明显闪一下；
        // 而下面 `.task(id:)` 已经会在连接变化时调 `reloadRoot()`，
        // 由它负责把缓存与展开状态清干净，效果一样但不会整块重建。
        .task(
            id: ObjectTreeRefreshKey(
                connectionID: appState.selectedConnectionID,
                revision: appState.metadataRevision
            )
        ) {
            await reloadRoot()
        }
        // 注：10 个 `.sheet` **不在这里** —— 它们挂在 `ConnectionListView` 那个唯一的 `List` 上。
        //
        // 原因（2026-09-24 修「编辑表结构」取消时连续闪烁）：修饰符挂在 `Group` 上会被
        // SwiftUI 分发到**每个子视图**，而这里的内容是"N 行"，于是每个 sheet 各挂 N 份
        // （实测 16 行 × 10 个 sheet = 160 个呈现槽）—— 取消时它们逐个收起，界面就连续闪烁。
        // 留在本文件里的话，"挂哪儿"这件事迟早又会被改回 Group 上，所以在这一行留个路标。
    }

    // MARK: - 扁平化

    /// 可见行 = 「状态 → 行数组」的**纯函数**，住在 `App/Views/ObjectTreeRows.swift`。
    ///
    /// 为什么搬出去（队列 `L-89` ㈡ 第 6 条）：那一行的判据是「两种视图都能用；
    /// 切换后选中项不丢」——判的正是那个函数的输出，而它原先在本文件里是 `private`
    /// ⇒ 只能靠人眼看。搬出去之后 `TestsUISnapshot/GroupedViewProbeTests.swift`
    /// 可以拿**真库读回来的对象**喂它。
    private var visibleRows: [ObjectTreeVisibleRow] {
        ObjectTreeRows.visibleRows(
            roots: roots,
            expandedIDs: expandedIDs,
            childrenCache: childrenCache,
            loadingIDs: loadingIDs,
            errors: errors,
            groupByType: groupByType,
            language: LocalizationManager.shared.effectiveLanguage
        )
    }

    // MARK: - 行渲染

    /// 视图切换 + 刷新（FR-META-15 / FR-META-12 / FR-META-11）—— 真视图在 `App/Views/ObjectTreeToolbar.swift`。
    ///
    /// 抽出来（与 `LowerPaneTabStrip` 同一个理由）是为了**能单独离屏渲染**：这一份 body 只有在
    /// 「选中了连接、根节点也加载回来了」之后才画得出来，判据不该被异步加载的时序绑架。
    /// 接线一字未改 —— `$groupByType` 还是这一个 `@State`。
    private var refreshRow: some View {
        ObjectTreeToolbar(
            groupByType: $groupByType,
            isRefreshing: isLoadingRoot,
            onSearch: { appState.isObjectSearchPresented = true },
            onRefresh: { Task { await reloadRoot() } }
        )
    }

    private func rowView(_ row: ObjectTreeVisibleRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            HStack(spacing: Spacing.s) {
                if row.isGroupHeader {
                    Color.clear.frame(width: 12, height: 12)
                } else if row.isExpandable {
                    Button {
                        toggle(row.object)
                    } label: {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.text(.secondary))
                            .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                            .frame(width: 12, height: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12, height: 12)
                }

                Image(systemName: row.object.symbolName)
                    .font(Theme.font(.caption))
                    .foregroundStyle(color(for: row.object.kind))
                    .frame(width: 14)

                Text(row.object.name)
                    .font(Theme.font(.caption))
                    .fontWeight(row.isGroupHeader ? .semibold : .regular)
                    .lineLimit(1)

                if let detail = row.object.detail {
                    Text(detail)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.tertiary))
                        .lineLimit(1)
                }
            }
            .padding(.leading, CGFloat(row.depth) * Metrics.listIndent)
            // 点击区**铺满整行**：默认只覆盖内容宽度 ⇒ 标签右边那一截空白点不到，
            // 表现就是「经常选不中」（2026-09-29 需求提出者实测）。`maxWidth: .infinity`
            // 之后 `contentShape` 覆盖的是整行，选中高亮也随之一整行铺开（树的常规做法）。
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // 选中态要看得见：⌘K 里"浏览数据 / 查看 DDL / 合成数据"都作用在选中项上，
            // 没有可见的选中标记时那句"请先在对象树里点选"会让人莫名其妙。
            .background(
                row.object.id == appState.selectedTreeObject?.id
                    ? Theme.accentColor.opacity(
                        Theme.isDarkAppearance ? Overlay.Selection.darkAlpha : Overlay.Selection.lightAlpha
                    )
                    : Color.clear
            )
            // 双击表 / 视图 → 浏览前 N 行（FR-DATA-01）。
            // 双击手势必须写在单击之前，否则会被单击吞掉。
            .onTapGesture(count: 2) {
                guard !row.isGroupHeader else { return }
                guard ObjectTreeActions.isAvailable(.browseRows, for: row.object.kind) else { return }
                appState.selectTreeObject(row.object)
                // 点击本身就是「指针在这一行」的铁证：顺手写进悬停盒子 ——
                // 重建补的那个假 mouseExited 会清空它，而指针不动就不会再来 mouseEntered。
                hoverBox.rowID = row.object.id
                Task { await appState.performTreeAction(.browseRows, on: row.object) }
            }
            .onTapGesture {
                guard !row.isGroupHeader else { return }
                // 单击既"选中"也"展开"：表 / 视图这类节点本来就靠单击展开看列，
                // 分两次点击才叫选中会让命令面板的目标变得不可预期。
                appState.selectTreeObject(row.object)
                // 同上：点完立刻右键的人，菜单目标靠这一行（见 `menuTargetObject`）。
                hoverBox.rowID = row.object.id
                guard row.isExpandable else { return }
                toggle(row.object)
            }
            // 右键菜单**不再挂在每一行上**（原因见 `ObjectTreeMenuTarget.resolve`）：整棵树现在是一个 `List` 行，
            // AppKit 按 List 行解析右键菜单、只会用找到的第一个 —— 那会让"点数据库弹出服务器菜单"。
            // 这里只负责记下"鼠标在哪一行"，菜单由整块挂的那一个按它决定内容。
            .onHover { hovering in
                guard !row.isGroupHeader else { return }
                if hovering {
                    hoverBox.rowID = row.object.id
                } else if hoverBox.rowID == row.object.id {
                    hoverBox.rowID = nil
                }
            }

            if row.isExpanded && !row.isGroupHeader {
                if row.isLoading {
                    placeholderRow(
                        text: L(.treeLoading),
                        depth: row.depth + 1,
                        systemImage: nil,
                        color: Theme.text(.secondary)
                    )
                } else if let error = row.error {
                    placeholderRow(
                        text: error,
                        depth: row.depth + 1,
                        systemImage: "exclamationmark.triangle.fill",
                        color: Theme.status(.warning)
                    )
                } else if let children = row.children, children.isEmpty {
                    placeholderRow(
                        text: emptyText(for: row.object),
                        depth: row.depth + 1,
                        systemImage: nil,
                        color: Theme.text(.tertiary)
                    )
                }
            }
        }
        .frame(height: Metrics.listRowHeight)
    }

    /// 菜单打开那一刻真正的目标行（悬停优先、盒子空时退回选中项）——
    /// 解析是**纯函数**（`ObjectTreeMenuTarget.resolve`，住在 `App/Views/ObjectTreeContextMenu.swift`）。
    private var menuTargetObject: DatabaseObject? {
        ObjectTreeMenuTarget.resolve(
            hoveredRowID: hoverBox.rowID,
            selected: appState.selectedTreeObject,
            rows: visibleRows
        )
    }

    private func placeholderRow(
        text: String,
        depth: Int,
        systemImage: String?,
        color: Color
    ) -> some View {
        HStack(spacing: Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.font(.caption))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(Theme.font(.caption))
                .foregroundStyle(color)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.leading, CGFloat(depth) * Metrics.listIndent + Metrics.listIndent + Spacing.xs)
    }

    // MARK: - 交互

    private func toggle(_ object: DatabaseObject) {
        guard object.isExpandable else { return }

        if expandedIDs.contains(object.id) {
            expandedIDs.remove(object.id)
            return
        }

        expandedIDs.insert(object.id)
        // **空结果不算"查过了"**：别人在别的客户端建了表，这个节点也得能重查出来
        // （规则与理由在 Core 的 `ObjectTreeReloadPolicy`，有单测）。
        guard ObjectTreeReloadPolicy.shouldLoad(
            cached: childrenCache[object.id],
            isLoading: loadingIDs.contains(object.id)
        ) else { return }
        Task { await loadChildren(of: object) }
    }

    private func loadChildren(of object: DatabaseObject) async {
        loadingIDs.insert(object.id)
        // **必须**用 defer 收：取消（切连接 / 视图重建时 `.task` 被取消）也会从这里返回，
        // 漏掉这一步那一行就永远转圈（2026-09-24 实测："对象树一直在加载"）。
        defer { loadingIDs.remove(object.id) }
        errors[object.id] = nil
        do {
            let children = try await appState.loadMetadataChildren(of: object)
            childrenCache[object.id] = children
            // **首连时序类的怪事只能靠日志说话**（2026-09-25 需求提出者两次报"点开没有 schema 的库
            // 会出错"，而 Core 那条路我单独跑过是干净的 —— 那就把"到底发生了什么"留下来）。
            // 两个方言都记：树上这份数据的方言 vs 当前选中连接的方言 ——
            // **它们不一致时，就是"文案说错方言"的直接证据**。
            if object.kind == .database, children.isEmpty {
                StartupLog.write(
                    "对象树：库 \(object.name) 下 0 个子节点"
                        + "（树方言=\(treeDatabaseType?.rawValue ?? "未记录")"
                        + "，连接方言=\(appState.selectedConnection?.dbType.rawValue ?? "无")"
                        + "，节点 id=\(object.id)）"
                )
            }
        } catch {
            // 取消不是故障（见 `CancellationNoise`）：展开/折叠与切连接时 `.task` 会被取消，
            // 不区分的话树上会莫名出现一条"加载失败"。
            guard !CancellationNoise.isNoise(error, taskIsCancelled: Task.isCancelled) else { return }
            let message = ErrorPresenter.message(for: error)
            errors[object.id] = message
            StartupLog.write("对象树加载失败：\(object.kind.rawValue) \(object.name)（id=\(object.id)）→ \(message)")
        }
        loadingIDs.remove(object.id)
    }

    private func reloadRoot() async {
        guard appState.selectedConnection != nil else {
            roots = []
            childrenCache = [:]
            expandedIDs = []
            errors = [:]
            rootError = nil
            treeDatabaseType = nil
            appState.selectedTreeObject = nil
            return
        }

        if !isLoadingRoot { isLoadingRoot = true }
        // 同上：**任何**返回路径（含"取消 → 直接 return"）都必须把"加载中"收掉，
        // 否则首屏会永远停在「正在加载对象…」。
        defer { if isLoadingRoot { isLoadingRoot = false } }
        if rootError != nil { rootError = nil }

        var loaded: [DatabaseObject] = []
        do {
            // 先把新数据取回来，**再**清缓存与展开状态：否则请求往返期间树会先空掉一次，
            // 那也是一次可见的闪。
            //
            // **同一次刷新只许有一次在途**（队列 `L-96`）：这一发过闸门，键 = 连接 + 元数据版本，
            // 与上面 `.task(id:)` 的 id 是**同一个类型、同一份取值**（不各拼一份）。
            // 同键之下第二个来者（刷新按钮连点 / 重试按钮 / 视图重建后 `.task` 再跑一遍）
            // **并到这一发上**，不再各查一遍库、也不会两份结果抢着落地。
            let newRoots = try await appState.objectTreeRefreshGate.roots(
                for: ObjectTreeRefreshKey(
                    connectionID: appState.selectedConnectionID,
                    revision: appState.metadataRevision
                )
            ) {
                try await appState.loadMetadataRoot()
            }
            // 被取消的那一发**不许再写状态**：闸门下这一发的取数**不受调用方取消影响**
            // （那一发可能正被并上来的新实例用着），所以这里要自己问一句 ——
            // 否则切连接时上一个连接的数据会糊到眼前的树上。
            guard !Task.isCancelled else { return }
            roots = newRoots
            loaded = newRoots
            // **与这份数据同时记下方言**：后面所有文案（空态等）只认它，
            // 于是"树上是什么数据"与"按谁的规矩说话"不可能再对不上。
            treeDatabaseType = appState.selectedConnection?.dbType
            childrenCache = [:]
            expandedIDs = []
            errors = [:]
            // 树的内容换了（换连接 / 新建立了对象），旧的选中项可能已经不存在：
            // 留着它会让 ⌘K 里的"浏览数据"作用在一个陈旧的节点上。
            appState.selectedTreeObject = nil
        } catch {
            // 同上：`.task(id:)` 在连接切换 / 视图重建时会取消上一次加载，
            // 那不是"对象树加载失败"，不该把错误留在界面上。
            // （"加载中"的收尾由上面的 defer 负责 —— 取消路径不能把它漏掉。）
            guard !CancellationNoise.isNoise(error, taskIsCancelled: Task.isCancelled) else { return }
            roots = []
            childrenCache = [:]
            expandedIDs = []
            errors = [:]
            rootError = ErrorPresenter.message(for: error)
            treeDatabaseType = nil
            appState.selectedTreeObject = nil
        }
        if isLoadingRoot { isLoadingRoot = false }

        // 自动展开到「看得见表」（FR-META-01）：放在收起"加载中"**之后** —— 这一步还要走两三次
        // 元数据往返，挂在首屏上会让人以为界面卡住。
        await autoExpandToTables(roots: loaded)
    }

    /// 连上之后展开到表：服务器 → **连接自己那个库** → `public`。
    ///
    /// 为什么要有它：层级是「服务器 → 数据库 → schema → 表」，而展开状态是本地状态、每次连接
    /// 都从全部折叠开始 —— 实测反馈「连上了，那么多数据库里没看到 `customers`」就是这么来的
    /// （`customers` 是**表**，在连接自己那个库里，当时还得再点三次）。
    /// 策略本身在 Core（`ObjectTreeAutoExpansion`，有单测），这里只按顺序把名字喂进去，
    /// 走的是与用户手点**同一条** `loadChildren`（否则缓存与错误显示会分叉）。
    private func autoExpandToTables(roots: [DatabaseObject]) async {
        guard let server = roots.first, server.isExpandable else { return }

        expandedIDs.insert(server.id)
        await loadChildrenIfNeeded(of: server)

        guard let databases = childrenCache[server.id],
              let databaseName = ObjectTreeAutoExpansion.database(
                  in: databases.map(\.name),
                  connectionDatabase: appState.selectedConnection?.database
              ),
              let database = databases.first(where: { $0.name == databaseName }) else { return }

        expandedIDs.insert(database.id)
        await loadChildrenIfNeeded(of: database)

        guard let schemas = childrenCache[database.id],
              let schemaName = ObjectTreeAutoExpansion.schema(in: schemas.map(\.name)),
              let schema = schemas.first(where: { $0.name == schemaName }) else { return }

        expandedIDs.insert(schema.id)
        await loadChildrenIfNeeded(of: schema)
    }

    /// `loadChildren` 的幂等包装：已经加载过、或正在加载中就不再打一次
    /// （自动展开与用户手点可能撞在同一节点上）。
    private func loadChildrenIfNeeded(of object: DatabaseObject) async {
        guard ObjectTreeReloadPolicy.shouldLoad(
            cached: childrenCache[object.id],
            isLoading: loadingIDs.contains(object.id)
        ) else { return }
        await loadChildren(of: object)
    }

    // MARK: - 文案与配色

    private func emptyText(for object: DatabaseObject) -> String {
        switch object.kind {
        case .server:
            return L(.treeEmptyServer)
        case .database:
            // 空态文案按**这份树是用哪个方言加载的**来选（见 `treeDatabaseType`），
            // 而不是"当前选中的连接是什么" —— 首连 / 切连接的瞬间两者可能不是同一件事，
            // 那正是"MySQL 的库却写「暂无 schema」"的成因（2026-09-25 实测两次）。
            guard let type = treeDatabaseType else {
                // 方言未知（还没加载完 / 刚清空）：给一句**不冒充任何方言**的话，
                // 而不是默认按 PostgreSQL 说"schema"。
                return L(.treeEmptyDatabaseUnknown)
            }
            return L(type.databaseNodeEmptyKey)
        case .schema:
            return L(.treeEmptySchema)
        case .table, .view, .sequence:
            return L(.treeEmptyTable)
        case .column, .function:
            return L(.treeEmptyGeneric)
        }
    }

    private func color(for kind: DatabaseObject.Kind) -> Color {
        switch kind {
        case .server:
            return .accentColor
        case .database:
            return .blue
        case .schema:
            return .purple
        case .table:
            return .green
        case .view:
            return .teal
        case .column:
            return .secondary
        case .function:
            return .orange
        case .sequence:
            return .indigo
        }
    }
}

/// 鼠标悬停行的**无观察者**小盒子（见 `ObjectTreeView.hoverBox` 的说明）。
///
/// 刻意不是 `ObservableObject`、也不放进 `@State` 的观察链：它的用途只有"右键菜单呈现那一刻读一眼"，
/// 而任何"写一下就让整棵树重算"的做法都会把悬停变成闪烁。
final class HoverBox {
    var rowID: String?
}
