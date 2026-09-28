import SwiftUI
import DoyahCore

/// 合成数据面板（FR-AI-07）。
///
/// 三件事按"风险从低到高"排开，按钮也照这个顺序：
/// **生成预览**（纯计算）→ **导出 INSERT 到编辑器**（不执行）→ **写入目标表**（走审批闸门）。
/// 规格默认按表结构自动推断 —— 让用户对着十几列手写规则等于把功能藏起来。
struct SyntheticDataPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let object: DatabaseObject

    /// 面板的**初始规格**（队列 L-60 的口子；形状照 L-12 / L-18）。
    ///
    /// 为什么需要它：`spec` 由 `.task → appState.syntheticSpec(for:)` **从真库结构**推出来 ⇒
    /// 离屏（没连库）只能停在「取不到结构」那一支，而那是**错误态不是空态**（L-16 第 5 批登记）；
    /// 「连上了、这一次**一行都没生成**」这个纯空态因此**拍不到**。
    ///
    /// 三条口径（与 L-12 / L-18 同源，另加本条自己的一条）：
    /// ① **只给初值**，生产路径不传（`ConnectionListView` 传的是 `object:` 一个参数）；
    /// ② **不是测试后门**：写入照样走审批闸门、导出照样不执行；
    /// ③ `nil` = 没注入 ⇒ 照旧查库；给了（哪怕是 0 列的规格）⇒ 这一遍**不查库**；
    /// ④ **注入了也不跳过生成，而且第一遍渲染就带着行** —— `rows` 仍由生成器真跑一遍得到
    ///    （纯计算、不碰库，见 `init` 里的 `generated(_:)`），所以图上那 0 行是**生成器真的产出
    ///    0 行**（`rowCount = 0`），不是界面自己塞了一个空数组。
    private let injectedSpec: SyntheticTableSpec?

    init(object: DatabaseObject, initialSpec: SyntheticTableSpec? = nil) {
        self.object = object
        self.injectedSpec = initialSpec
        // 注入的那一份**照样跑一遍生成**（`AppState.syntheticRows(for:)`，纯计算、不碰库）——
        // 而且**在第一遍渲染之前就位**。为什么非要一次到位：离屏宿主的第一帧也会被画出来
        // （注入只有 `spec`、`rows` 还空着时，首帧会先画出「一行都没有」，随后才被 `.task` 换成真行；
        // 实测两遍文案都留在渲染记录里 ⇒ 判据没法判「这一遍到底有没有生成」，图也白拍了）。
        let built = SyntheticDataPanel.generated(initialSpec)
        _spec = State(initialValue: built.spec)
        _rows = State(initialValue: built.rows)
        _localError = State(initialValue: built.error)
    }

    /// 规格 → (规格, 行, 错误)。**唯一出处**：`init` 的注入那一路与 `regenerate` 那一路都走这里。
    ///
    /// `AppState.syntheticRows(for:)` 是静态的（`init` 里拿不到 `@EnvironmentObject`），
    /// 所以两条路的行与失败措辞逐字同一份；失败时收场也一致：**规格清掉**（回到错误态）、
    /// 错误就地显示 —— 与「结构取不到」那一支分得开，与它同形。
    private static func generated(
        _ spec: SyntheticTableSpec?
    ) -> (spec: SyntheticTableSpec?, rows: [[String?]], error: String?) {
        guard let spec else { return (nil, [], nil) }
        do {
            return (spec, try AppState.syntheticRows(for: spec), nil)
        } catch {
            return (nil, [], L(.syntheticSpecIssue, ErrorPresenter.message(for: error)))
        }
    }

    @State private var spec: SyntheticTableSpec?
    @State private var rows: [[String?]] = []
    @State private var rowCountText = "100"
    @State private var seedText = "1"
    @State private var overwrite = false
    @State private var isLoading = false
    @State private var localError: String?

    private var rowCount: Int { Int(rowCountText.trimmingCharacters(in: .whitespaces)) ?? 100 }
    private var seed: UInt64 { UInt64(seedText.trimmingCharacters(in: .whitespaces)) ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L(.syntheticTitle, object.name)).font(Theme.font(.title))

            // 说清"规则从哪来"，否则用户会以为要自己填十几个生成器。
            Text(L(.syntheticAutoSpecNote))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.m) {
                labelled(L(.syntheticRows)) {
                    TextField("", text: $rowCountText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.font(.data))
                        .frame(width: 90)
                }
                labelled(L(.syntheticSeed)) {
                    TextField("", text: $seedText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.font(.data))
                        .frame(width: 90)
                }
                Toggle(L(.syntheticOverwrite), isOn: $overwrite)
                    .font(Theme.font(.caption))
                Spacer()
                Button(L(.syntheticGenerate)) {
                    Task { await regenerate() }
                }
                .disabled(isLoading)
            }

            if let localError {
                Text(localError)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.danger))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = appState.syntheticDataMessage {
                Text(message)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = appState.syntheticDataError {
                Text(error)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.danger))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L(.syntheticColumns)).font(Theme.font(.bodyStrong))
            if let spec {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.hair) {
                        ForEach(Array(spec.columns.enumerated()), id: \.offset) { _, column in
                            HStack(spacing: Spacing.s) {
                                Text(column.name)
                                    .font(Theme.font(.monoSmall))
                                    .frame(width: 160, alignment: .leading)
                                Text(describe(column.generator))
                                    .font(Theme.font(.caption))
                                    .foregroundStyle(Theme.text(.secondary))
                                if column.isUnique {
                                    Text("UNIQUE").font(Theme.font(.caption)).foregroundStyle(Theme.text(.tertiary))
                                }
                                if column.nullProbability > 0 {
                                    Text("NULL \(Int(column.nullProbability * 100))%")
                                        .font(Theme.font(.caption))
                                        .foregroundStyle(Theme.text(.tertiary))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
            } else if isLoading {
                HStack(spacing: Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text(L(.tableDesignLoading)).font(Theme.font(.body))
                }
            }

            Text(L(.syntheticPreview)).font(Theme.font(.bodyStrong))
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: Spacing.hair) {
                    if let spec {
                        Text(spec.columns.map(\.name).joined(separator: " | "))
                            .font(Theme.font(.monoSmall))
                            .foregroundStyle(Theme.text(.tertiary))
                    }
                    ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { _, row in
                        Text(row.map { $0 ?? "NULL" }.joined(separator: " | "))
                            .font(Theme.font(.monoSmall))
                            .textSelection(.enabled)
                    }
                    // **空态要说出来**（队列 L-60）：0 行时这里原本什么都不画 —— 两个动作按钮
                    // 灰着、也没有一句解释。按钮的处置（灰着）本身符合 §3.26 的口径，缺的是那句
                    // 「为什么灰」：这行就是它。触发条件按「生成跑过了（没有错误）且一行都没有」——
                    // 生成是纯计算，`rows` 为空只可能是 `rowCount = 0`，所以这句话说的是事实。
                    if rows.isEmpty, let spec, localError == nil {
                        Text(L(.syntheticPreviewEmpty))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s)
            }
            .frame(height: 120)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.surface(.panel)))

            HStack {
                Spacer()
                Button(L(.commonClose)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L(.syntheticExport)) {
                    guard let spec else { return }
                    appState.exportSyntheticInsert(spec, rows: rows, overwrite: overwrite)
                }
                .disabled(rows.isEmpty || spec == nil)
                // 写入是**有副作用**的动作，放在最后且走审批 —— 位置本身就是提示。
                Button(L(.syntheticWrite)) {
                    Task {
                        guard let spec else { return }
                        await appState.writeSyntheticData(spec, rows: rows, overwrite: overwrite)
                    }
                }
                .disabled(rows.isEmpty || spec == nil)
            }
        }
        .padding(Spacing.l)
        .frame(width: 760, height: 620)
        .task {
            // `injectedSpec != nil` = 注入过 ⇒ 这一遍**不查库**（唯一的「给了初值就不去取」保证，
            // 见 `init(object:initialSpec:)`）。注入的规格与行在 `init` 里已经就位 ⇒ 这里什么都不做。
            if injectedSpec == nil {
                await regenerate()
            }
        }
    }

    // MARK: 零件

    @ViewBuilder
    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(Theme.font(.caption)).foregroundStyle(Theme.text(.secondary))
            content()
        }
    }

    private func regenerate() async {
        isLoading = true
        localError = nil
        appState.syntheticDataMessage = nil
        appState.syntheticDataError = nil
        do {
            apply(try await appState.syntheticSpec(for: object, rowCount: rowCount, seed: seed))
        } catch {
            // 结构取不到（没连库 / 查挂了）—— 这是**错误态**，与「取到了但一行都没有」分开。
            spec = nil
            rows = []
            localError = L(.syntheticSpecIssue, ErrorPresenter.message(for: error))
        }
        isLoading = false
    }

    /// 规格 → 行。**唯一出处**：查库那一条路与注入那一条路都走这里。
    ///
    /// 生成是纯计算（`SyntheticDataGenerator` 不碰库），所以注入的规格**照跑一遍** ——
    /// 于是「0 行」这个态是生成器真的产出 0 行（`rowCount = 0`），而不是界面造出来的空数组；
    /// 失败时把 `spec` 一并清掉，两条路的收场逐字一致。
    private func apply(_ built: SyntheticTableSpec) {
        spec = built
        do {
            rows = try appState.generateSyntheticRows(built)
        } catch {
            spec = nil
            rows = []
            localError = L(.syntheticSpecIssue, ErrorPresenter.message(for: error))
        }
    }

    /// 生成规则的人话描述（Core 只给枚举，文案在界面层）。
    ///
    /// **语言来自语言表**（队列 L-60 读图产出）：原先「字符 / 位 / 项 / 近 N 天」是**写死在这里的
    /// 汉字**，`L(...)` 一个都没用 ⇒ 英文界面上印出 `text(8…24 字符)`、`timestamp(近 365 天)`
    /// （`synthetic-data-empty-rows-en` 实测）。规则名、语序与量词交给语言表 —— 各语言的写法本来就不一样。
    /// 数字在**这里**先格式化成字符串（`"\(…)"`）再过 `%@`：模板只管语序与量词，槽位不会收到数值
    /// ⇒ L-46 那一族「`%@` 配 `Int` 印出 `(null)`」的失败模式在这里无从发生；小数的写法也就保持
    /// 与改前逐字一致（不套 `%f` 的默认精度）。
    private func describe(_ generator: ColumnGenerator) -> String {
        switch generator {
        case .sequence(let start, let step): return "sequence(\(start), +\(step))"
        case .integer(let min, let max): return "integer(\(min)…\(max))"
        case .decimal(let min, let max, let precision):
            return L(.syntheticRuleDecimal, "\(min)", "\(max)", "\(precision)")
        case .boolean(let probability): return "boolean(\(probability))"
        case .text(let minLength, let maxLength):
            return L(.syntheticRuleText, "\(minLength)", "\(maxLength)")
        case .choice(let values): return "choice(\(values.joined(separator: "/")))"
        case .weightedChoice(let values): return L(.syntheticRuleWeighted, "\(values.count)")
        case .email: return "email"
        case .fullName: return "name"
        case .date(let lastDays): return L(.syntheticRuleDateWithin, "\(lastDays)")
        case .timestamp(let lastDays): return L(.syntheticRuleTimestampWithin, "\(lastDays)")
        case .uuid: return "uuid"
        case .constant(let value): return "constant(\(value))"
        }
    }
}
