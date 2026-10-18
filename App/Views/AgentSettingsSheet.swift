import SwiftUI
import DoyahCore

/// 「智能体设置…」面板（FR-AI-01）。
///
/// 界面上把三件事说清楚，避免用户对「发了什么」有误解：
/// 1. **总开关**：关闭时一行提示直接写明「不会向任何模型服务发送数据」（AC-AI-01）；
/// 2. **密钥去向**：API Key 只进系统钥匙串，不写配置文件（面板里明说）；
/// 3. **当前判定**：直接展示 `AgentGate.decide` 的结论 —— 配置不完整 / 缺密钥 / 已放行，
///    用户不用猜「为什么没反应」。
struct AgentSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var isEnabled = false
    @State private var endpoint = ""
    @State private var model = ""
    /// 选中的提供商（队列 `L-146`）：**由端点反推**，不在配置里多存一个字段 ——
    /// 重开面板时按端点认一次，认不出就是「自定义」。
    @State private var providerID = AgentProviderCatalog.customID
    @State private var timeoutSeconds = "60"
    @State private var maxRequests = ""
    @State private var maxOutputTokens = ""
    @State private var maxTotalTokens = ""
    /// 新输入的 Key；为空表示「不改动已保存的 Key」。
    @State private var apiKeyInput = ""
    /// 连接测试的结果行（`nil` = 还没测过）。
    @State private var testLine: String?
    @State private var isTesting = false
    @State private var clearAPIKey = false
    @State private var isLoaded = false
    /// 授权粒度（`FR-AI-34`）：任务范围内代签 = 少问；每个动作都问 = 老行为。
    @State private var scopeMode: AgentTaskScope.Mode = .taskScope
    /// **真值源**（`FR-AI-25` 信息面三格）：上下文窗口 + 每百万 token 价目。
    /// 空串 = 没填（窗口退回内置表、价钱那一格不出现）。
    @State private var contextWindowText = ""
    @State private var inputPriceText = ""
    @State private var outputPriceText = ""
    @State private var cachedPriceText = ""
    @State private var priceCurrency: AgentPriceCurrency = .cny
    /// MCP 服务器配置面（`FR-AI-21` 界面片）的开合。
    @State private var showsMCPServers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.agentSettingsTitle))
                .font(.headline)

            Form {
                Toggle(isOn: $isEnabled) {
                    Image(systemName: "cpu")
                }
                .help(L(.agentEnabled))
                .accessibilityLabel(Text(L(.agentEnabled)))
                Text(L(.agentEnabledHint))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // 提供商预设（FR-AI-01 的配置面 · 队列 L-146）：先选提供商，端点与常用模型
                // 自动填好，两个输入框**仍然可改**（自建网关 / 代理 / 私有部署照旧能用）。
                // 那句说明挂 Section 标题（用系统自己那套小字样式）—— 本面板不再自己写字号与前景色。
                Section(L(.agentProviderHint)) {
                    Picker(L(.agentProvider), selection: $providerID) {
                        ForEach(AgentProviderCatalog.all) { preset in
                            Text(L(preset.labelKey)).tag(preset.id)
                        }
                    }
                }

                TextField(L(.agentEndpoint), text: $endpoint, prompt: Text(L(.agentEndpointPlaceholder)))
                HStack(spacing: 8) {
                    TextField(L(.agentModel), text: $model, prompt: Text(L(.agentModelPlaceholder)))
                    Menu {
                        ForEach(selectedPreset.modelOptions(currentModel: model), id: \.self) { name in
                            Button(name) { model = name }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(selectedPreset.models.isEmpty)
                    .help(L(.agentModelPresetHint))
                }
                TextField(L(.agentTimeout), text: $timeoutSeconds)

                // **信息面三格的真值源**（`FR-AI-25`）：窗口 / 价目。这些数仓里没有、
                // 也不该由程序猜（价格随时变、代理后面那个模型的窗口未必同名同尺寸）⇒
                // 由用户填；不填就不显示那一格。**不做汇率换算**：填哪个币种就用哪个符号。
                Section(L(.agentMeterSection)) {
                    TextField(L(.agentMeterWindow), text: $contextWindowText,
                              prompt: Text(L(.agentMeterWindowPlaceholder)))
                    HStack(spacing: 8) {
                        TextField(L(.agentMeterInputPrice), text: $inputPriceText,
                                  prompt: Text(L(.agentMeterPricePlaceholder)))
                        TextField(L(.agentMeterOutputPrice), text: $outputPriceText,
                                  prompt: Text(L(.agentMeterPricePlaceholder)))
                        TextField(L(.agentMeterCachedPrice), text: $cachedPriceText,
                                  prompt: Text(L(.agentMeterPricePlaceholder)))
                    }
                    Picker(L(.agentMeterCurrency), selection: $priceCurrency) {
                        Text(L(.agentMeterCurrencyCNY)).tag(AgentPriceCurrency.cny)
                        Text(L(.agentMeterCurrencyUSD)).tag(AgentPriceCurrency.usd)
                    }
                    Text(L(.agentMeterFootnote))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section(L(.agentQuotaSection)) {
                    TextField(L(.agentMaxRequests), text: $maxRequests)
                    TextField(L(.agentMaxOutputTokens), text: $maxOutputTokens)
                    TextField(L(.agentMaxTotalTokens), text: $maxTotalTokens)
                }

                Section(L(.agentScopeSection)) {
                    Picker(L(.agentScopeSection), selection: $scopeMode) {
                        Text(L(.agentScopeTaskScope)).tag(AgentTaskScope.Mode.taskScope)
                        Text(L(.agentScopeAskEach)).tag(AgentTaskScope.Mode.askEachAction)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(L(.agentScopeFootnote))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // **MCP 服务器**（`FR-AI-21` 界面片）：这里是入口 + 一行读数，
                // 真正的加 / 删 / 开关与「连不上」的原因在弹层里（`MCPServersSheet`）。
                Section(L(.agentMCPSection)) {
                    HStack(spacing: 8) {
                        Button(L(.agentMCPConfigure)) { showsMCPServers = true }
                            .buttonStyle(.bordered)
                        Text(mcpSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(L(.agentMCPHint))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section(L(.agentAPIKey)) {
                    SecureField(L(.agentAPIKey), text: $apiKeyInput)
                    Text(appState.hasAgentAPIKey ? L(.agentAPIKeyConfigured) : L(.agentAPIKeyMissing))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if appState.hasAgentAPIKey {
                        Toggle(isOn: $clearAPIKey) {
                            Image(systemName: "key.slash")
                        }
                        .help(L(.agentAPIKeyClear))
                        .accessibilityLabel(Text(L(.agentAPIKeyClear)))
                        .font(.caption)
                    }
                }
            }
            .formStyle(.columns)
            .frame(width: 460)

            statusSection

            // **这一块是"二次配置界面"，一律走 macOS 标准按钮**（人类主人 2026-10-16 订正：
            // 「这些弹出对话框、二次配置界面还是标准的系统按钮和风格，主界面的工具条这些直接面对使用者的界面，
            // 才考虑图标化」）—— 原先这里两枚纯图标按钮（叉 / 下载箭头）是理解偏差，已改回文字按钮。
            HStack(spacing: 10) {
                Button(L(.agentTestConnection)) {
                    isTesting = true
                    testLine = L(.agentTestRunning)
                    Task {
                        let result = await appState.testAgentConnection()
                        switch result {
                        case .passed(let model, let millis):
                            // `%d` 槽必须收数字：原来把毫秒转成字符串传进去，`String(format:)`
                            // 会把指针/垃圾数印在「（… 毫秒）」里（门禁 A′ 抓到的）。直接传 Int。
                            testLine = L(.agentTestPassed, model, millis)
                        case .failed(let reason):
                            testLine = L(.agentTestFailed, reason)
                        }
                        isTesting = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)

                if let testLine {
                    Text(testLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(L(.commonCancel)) { dismiss() }
                    .buttonStyle(.bordered)

                Button(L(.agentSave)) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        // 换提供商 ⇒ 自动填端点与模型；手改端点 ⇒ 重认一次「这是谁」。
        // 两条都不自己判，只读契约层（`AgentProviderCatalog`）给的答案。
        .onChange(of: providerID) { _, newValue in applyProvider(newValue) }
        .onChange(of: endpoint) { _, newValue in syncProvider(with: newValue) }
        .task {
            guard !isLoaded else { return }
            isLoaded = true
            let configuration = appState.agentConfiguration
            isEnabled = configuration.isEnabled
            endpoint = configuration.endpoint
            model = configuration.model
            // 按端点认回「上次选的是谁」（认不出 = 自定义）——重开面板不许落回自定义。
            providerID = AgentProviderCatalog.resolved(endpoint: configuration.endpoint).id
            timeoutSeconds = String(Int(configuration.timeoutSeconds))
            maxRequests = configuration.quota.maxRequestsPerSession.map(String.init) ?? ""
            maxOutputTokens = configuration.quota.maxOutputTokensPerRequest.map(String.init) ?? ""
            maxTotalTokens = configuration.quota.maxTotalTokens.map(String.init) ?? ""
            scopeMode = configuration.scopeMode
            // 真值源（`FR-AI-25`）：这一档填过的窗口 / 价目要回填 —— 否则重开面板就是空白，
            // 保存一次等于把用户填过的价目**静默清掉**。
            let pricing = configuration.activeProfile?.pricing
            contextWindowText = pricing?.contextWindow.map { String($0) } ?? ""
            inputPriceText = Self.priceText(pricing?.inputPerMillion)
            outputPriceText = Self.priceText(pricing?.outputPerMillion)
            cachedPriceText = Self.priceText(pricing?.cachedInputPerMillion)
            priceCurrency = pricing?.currency ?? .cny
            // MCP 那一行的读数（「还没配置 / 已连上 n / m 条」）需要配置与这一轮的发现结果；
            // 配置读一次就够（`loadAgentMCPConfiguration` 幂等），发现结果由对话那条路填。
            appState.loadAgentMCPConfiguration()
        }
        .sheet(isPresented: $showsMCPServers) {
            MCPServersSheet()
                .environmentObject(appState)
        }
    }

    // MARK: - MCP 读数

    /// 入口那一行说的话：没配 / 已连上几条。**不假装连上** —— 关掉的、连不上的各算各的。
    private var mcpSummary: String {
        let servers = appState.agentMCPConfiguration.servers
        if servers.isEmpty { return L(.mcpServersSummaryNotConfigured) }
        let connected = appState.agentMCPReports.filter { $0.state.isConnected }.count
        return L(.mcpServersSummary, connected, servers.count)
    }

    // MARK: - 状态

    /// 用「即将保存的配置」算判定，用户改一下开关就能立刻看到结论变化。
    private var decision: AgentOutboundDecision {
        AgentGate.decide(configuration: draftConfiguration, apiKey: effectiveAPIKey)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(.agentStatusSection))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: decision.isAllowed ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(decision.isAllowed ? .green : .secondary)
                Text(decision.message)
                    .font(.caption)
                    .foregroundStyle(decision.isAllowed ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !draftConfiguration.issues.isEmpty {
                Label(L(.agentInvalidHint), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 460, alignment: .leading)
    }

    // MARK: - 提供商预设（L-146）

    /// 当前选中的提供商：界面画标签与模型下拉都取自它（标识认不出就退回「自定义」）。
    private var selectedPreset: AgentProviderPreset {
        AgentProviderCatalog.preset(id: providerID) ?? AgentProviderCatalog.custom
    }

    /// 选提供商 ⇒ 自动填端点；有预设模型清单时把模型也带到第一项。
    /// 清单为空（本机服务 / 接入点 ID 这类）时**不动**用户已填好的模型名。
    private func applyProvider(_ id: String) {
        guard let preset = AgentProviderCatalog.preset(id: id), !preset.isCustom else { return }
        endpoint = preset.endpoint
        if let first = preset.models.first { model = first }
    }

    /// 手改端点 ⇒ 重认一次「这是谁」（认不出就是「自定义」）——
    /// 免得出现「上面显示 OpenAI、实际发往别处」这种面板在撒谎的状态。
    private func syncProvider(with endpoint: String) {
        let target = AgentProviderCatalog.resolved(endpoint: endpoint).id
        if providerID != target { providerID = target }
    }

    // MARK: - 输入 → 配置

    private var draftConfiguration: AgentConfiguration {
        var draft = AgentConfiguration(
            isEnabled: isEnabled,
            endpoint: endpoint,
            model: model,
            timeoutSeconds: Double(timeoutSeconds.trimmingCharacters(in: .whitespaces)) ?? 0,
            quota: AgentQuota(
                maxRequestsPerSession: positiveInt(maxRequests),
                maxOutputTokensPerRequest: positiveInt(maxOutputTokens),
                maxTotalTokens: positiveInt(maxTotalTokens)
            ),
            // **护栏策略不许省略**（本面板没有它的编辑面）：省略就是拿 `.readOnlyDefault` 覆写，
            // 会把用户在「审批与审计」面板里设的只读模式与白名单一起抹掉 ——
            // `AgentConfigurationStore.save` 是**整份覆写**、不做字段合并（L-146 顺带修）。
            guardPolicy: appState.agentConfiguration.guardPolicy,
            // 授权粒度（`FR-AI-34`）：默认 `.taskScope`（少问）；设置里可改回逐次批。
            scopeMode: scopeMode
        )
        // 真值源（`FR-AI-25`）是**档的属性**：草稿是「单档形状」，把它塞进这一档，
        // 由宿主按档合并（别档原样留住）。
        if var profile = draft.activeProfile {
            profile.pricing = draftPricing
            draft.updateProfile(profile)
        }
        return draft
    }

    /// 面板里填的窗口 / 价目。**一个字都没填 ⇒ `nil`**（不往配置里写空壳）。
    private var draftPricing: AgentModelPricing? {
        let pricing = AgentModelPricing(
            contextWindow: positiveInt(contextWindowText),
            inputPerMillion: positiveDouble(inputPriceText),
            outputPerMillion: positiveDouble(outputPriceText),
            cachedInputPerMillion: positiveDouble(cachedPriceText),
            currency: priceCurrency
        )
        return pricing.isEmpty ? nil : pricing
    }

    /// 回填用：价目数字显示成最短形式（`0.5` 不显示成 `0.5000`）。
    static func priceText(_ value: Double?) -> String {
        guard let value else { return "" }
        if value == value.rounded() { return String(Int(value)) }
        return String(value)
    }

    /// 空串 = 不限；非数字 / 非正数一律当作不限（配额是「保护性上限」，填错字符不该误伤）。
    private func positiveInt(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return value > 0 ? value : nil
    }

    /// 价目：只认正数（`0` 与负数当没填 —— 价格不可能是 0，填 0 是把花费读数压成假的）。
    private func positiveDouble(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return value > 0 ? value : nil
    }

    /// 面板里「将要使用的 Key」：新输入优先，其次看是否要清除，最后用已保存的。
    private var effectiveAPIKey: String? {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if clearAPIKey { return nil }
        return appState.agentAPIKey
    }

    private func save() {
        let key: String?
        if !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key = apiKeyInput
        } else if clearAPIKey {
            key = ""
        } else {
            key = nil // 不改动
        }

        Task {
            let succeeded = await appState.saveAgentConfiguration(draftConfiguration, apiKey: key)
            if succeeded {
                dismiss()
            }
        }
    }
}
