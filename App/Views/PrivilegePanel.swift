import SwiftUI
import DoyahCore

/// 「权限…」面板（FR-SESS-04）。
///
/// 两件事：
/// 1. 查看指定角色在**库 / schema / 表 / 视图 / 序列**上的已授权限（按对象分组）；
/// 2. 生成 `GRANT` / `REVOKE` —— **执行前先把语句摊开给人看**，非法输入直接禁用按钮。
struct PrivilegePanel: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    /// 变更对象类别（面板只暴露最常用的四类）。
    private enum ObjectKindChoice: String, CaseIterable, Identifiable {
        case database
        case schema
        case table
        case sequence

        var id: String { rawValue }
        var title: String { rawValue }
    }

    @State private var role = ""
    @State private var privileges: [ObjectPrivilege] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var errorText: String?

    @State private var objectKind: ObjectKindChoice = .table
    @State private var objectName = ""
    @State private var schema = ""
    @State private var privilegeList = "SELECT"
    @State private var grantee = ""
    @State private var withGrantOption = false

    /// 面板的**初始角色与已授权限**（队列 L-18 的口子；L-16 第 6 批的前置就是它）。
    ///
    /// 为什么需要它：`role` / `privileges` 都是私有 `@State`、`.task` 打开即查库 ⇒
    /// 没选连接时离线只能拍到「未选连接」那一支；「连上了、这个角色**一个对象权限都没有**」
    /// 这个**纯空态**根本拍不到（L-16 第 5 批实测登记）。
    ///
    /// 三条口径：① 只给初值，生产路径不传（`role` 仍取当前连接用户名）⇒ 行为逐字不变；
    /// ② 不是测试后门（`GRANT` / `REVOKE` 照样要预览 + 确认，不放行任何写动作）；
    /// ③ `initialPrivileges` 为 `nil` 表示没注入 ⇒ 照旧查库；给了（哪怕是 `[]`）就**不去查**，
    ///    并把 `hasLoaded` 置真 —— 于是画面停在 `privilegeEmpty` 那一支而不是占位空格。
    private let injectedRole: String?
    private let injectedPrivileges: [ObjectPrivilege]?

    init(initialRole: String? = nil, initialPrivileges: [ObjectPrivilege]? = nil) {
        self.injectedRole = initialRole
        self.injectedPrivileges = initialPrivileges
        _role = State(initialValue: initialRole ?? "")
        _privileges = State(initialValue: initialPrivileges ?? [])
        _hasLoaded = State(initialValue: initialPrivileges != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L(.privilegeTitle))
                    .font(.headline)
                Spacer()
                Button(L(.commonClose)) { dismiss() }
            }

            roleRow
            privilegeListSection
            Divider()
            composerSection
        }
        .padding(20)
        // **顶对齐**（队列 L-58）：`.frame(width:height:)` 不写 `alignment` 时 SwiftUI 按默认 `.center`
        // 把内容摆在正中，而本面板的 `VStack` 里**没有一个可伸缩高度的子视图**（已授权限列表空着时
        // 只有一行文案）⇒ 内容整体被推到中间：`privilege-panel-empty-zh` 实测「权限」标题落在
        // y ≈ 420/1240pt 处、上下各一大片空白。同批另两块面板不这样 —— `ServerObjectsPanel` 的
        // `content` 有 `.frame(maxHeight: .infinity)`、`DatabaseStatsPanel` 是 `ScrollView` 撑满，
        // 两者都自然顶对齐。这里显式写 `.top` 让「有内容 / 空 / 加载中」三态用同一条口径
        // （对齐落在**面板根**、与内容无关，所以三态一起正、不会改一处让另两态错位）。
        .frame(width: 720, height: 620, alignment: .top)
        .task {
            // `injectedPrivileges != nil` = 注入过 ⇒ 这一遍不查库（唯一的「给了初值就不去取」保证，
            // 见 `init(initialRole:initialPrivileges:)`）。
            if injectedPrivileges == nil {
                if role.isEmpty {
                    role = appState.selectedConnection?.username ?? ""
                }
                await load()
            }
        }
    }

    // MARK: - 已授权限

    private var roleRow: some View {
        HStack(spacing: 8) {
            Text(L(.privilegeRole))
                .font(.caption)
            TextField(L(.privilegeRole), text: $role)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { Task { await load() } }

            Button(L(.privilegeLoad)) {
                Task { await load() }
            }
            .disabled(isLoading || !PrivilegeProbe.isValidRoleName(role))

            if isLoading {
                ProgressView().controlSize(.small)
            }

            Spacer()

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var privilegeListSection: some View {
        if privileges.isEmpty {
            Text(hasLoaded ? L(.privilegeEmpty) : " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ObjectPrivilegeParser.groupedByObject(privileges), id: \.object.id) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(group.object.objectKind.rawValue) \(group.object.qualifiedObjectName)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            ForEach(group.privileges) { privilege in
                                Text("\(privilege.privilege) · \(privilege.grantee)\(privilege.isGrantable ? " · \(L(.privilegeColumnGrantOption))" : "")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
        }
    }

    // MARK: - 授予 / 回收

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(.privilegeGrantSection))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker(L(.privilegeObjectKind), selection: $objectKind) {
                    ForEach(ObjectKindChoice.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .frame(width: 160)

                TextField(L(.privilegeObjectName), text: $objectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)

                TextField(L(.privilegeSchema), text: $schema)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .disabled(objectKind == .database || objectKind == .schema)
            }

            HStack(spacing: 8) {
                TextField(L(.privilegePrivileges), text: $privilegeList)
                    .textFieldStyle(.roundedBorder)

                TextField(L(.privilegeGrantee), text: $grantee)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            Toggle(L(.privilegeWithGrantOption), isOn: $withGrantOption)
                .font(.caption)

            statementPreview

            HStack {
                Spacer()

                Button(L(.privilegeRevoke)) {
                    Task { await apply(revoke: true) }
                }
                .disabled(revokeStatement == nil)

                Button(L(.privilegeGrant)) {
                    Task { await apply(revoke: false) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(grantStatement == nil)
            }
        }
    }

    @ViewBuilder
    private var statementPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(.privilegePreview))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let statement = grantStatement {
                Text(statement)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Label(L(.privilegeInvalid), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 组装与执行

    private var change: SQLGenerator.PrivilegeChange? {
        let names = privilegeList
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }

        let trimmedObject = objectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSchema = schema.trimmingCharacters(in: .whitespacesAndNewlines)
        let schemaOrNil = trimmedSchema.isEmpty ? nil : trimmedSchema

        let object: SQLGenerator.PrivilegeObject
        switch objectKind {
        case .database: object = .database(trimmedObject)
        case .schema: object = .schema(trimmedObject)
        case .table: object = .table(schema: schemaOrNil, name: trimmedObject)
        case .sequence: object = .sequence(schema: schemaOrNil, name: trimmedObject)
        }

        return SQLGenerator.PrivilegeChange(
            privileges: names,
            object: object,
            grantee: grantee.trimmingCharacters(in: .whitespacesAndNewlines),
            withGrantOption: withGrantOption
        )
    }

    private var grantStatement: String? {
        guard let change else { return nil }
        return appState.privilegeStatement(change, revoke: false)
    }

    private var revokeStatement: String? {
        guard let change else { return nil }
        return appState.privilegeStatement(change, revoke: true)
    }

    private func load() async {
        guard PrivilegeProbe.isValidRoleName(role) else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            privileges = try await appState.loadObjectPrivileges(role: role)
            hasLoaded = true
        } catch {
            privileges = []
            hasLoaded = true
            errorText = ErrorPresenter.message(for: error)
        }
    }

    private func apply(revoke: Bool) async {
        guard let change else { return }
        let succeeded = await appState.applyPrivilegeChange(change, revoke: revoke)
        if succeeded {
            await load()
        } else {
            errorText = appState.errorMessage
        }
    }
}
