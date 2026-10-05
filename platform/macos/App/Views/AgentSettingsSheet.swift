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
    @State private var clearAPIKey = false
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.agentSettingsTitle))
                .font(.headline)

            Form {
                Toggle(L(.agentEnabled), isOn: $isEnabled)
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

                Section(L(.agentQuotaSection)) {
                    TextField(L(.agentMaxRequests), text: $maxRequests)
                    TextField(L(.agentMaxOutputTokens), text: $maxOutputTokens)
                    TextField(L(.agentMaxTotalTokens), text: $maxTotalTokens)
                }

                Section(L(.agentAPIKey)) {
                    SecureField(L(.agentAPIKey), text: $apiKeyInput)
                    Text(appState.hasAgentAPIKey ? L(.agentAPIKeyConfigured) : L(.agentAPIKeyMissing))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if appState.hasAgentAPIKey {
                        Toggle(L(.agentAPIKeyClear), isOn: $clearAPIKey)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.columns)
            .frame(width: 460)

            statusSection

            HStack {
                Spacer()

                Button(L(.commonCancel)) {
                    dismiss()
                }

                Button(L(.agentSave)) {
                    save()
                }
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
        }
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
        AgentConfiguration(
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
            guardPolicy: appState.agentConfiguration.guardPolicy
        )
    }

    /// 空串 = 不限；非数字 / 非正数一律当作不限（配额是「保护性上限」，填错字符不该误伤）。
    private func positiveInt(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else { return nil }
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
