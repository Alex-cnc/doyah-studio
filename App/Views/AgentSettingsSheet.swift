import AppKit
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

    // 联网检索（`FR-AGT-TOOL-INGEST-004`）：后端选择 + Tavily key（只进 0600 文件）
    @State private var webBackend: AgentWebSearchConfig.Backend = .auto
    @State private var webKeyInput = ""
    @State private var webKeyStatus = ""
    @State private var isEnabled = false
    /// 当前编辑的**模型档**（多端点 · `FR-AGT-LINK-CHAN-001` ⑥）：切档即换一整套端点 / 模型 / 密钥。
    @State private var selectedProfileID: String?
    @State private var profileLine: String?
    @State private var endpoint = ""
    @State private var model = ""
    /// 选中的提供商（队列 `L-146`）：**由端点反推**，不在配置里多存一个字段 ——
    /// 重开面板时按端点认一次，认不出就是「自定义」。
    @State private var providerID = AgentProviderCatalog.customID
    @State private var timeoutSeconds = "60"
    @State private var maxRequests = ""
    @State private var maxOutputTokens = ""
    @State private var maxTotalTokens = ""
    /// 配额清零那一枚的结论（点完给一句，不然按了没反应）。
    @State private var quotaLine = ""
    /// 新输入的 Key；为空表示「不改动已保存的 Key」。
    @State private var apiKeyInput = ""
    /// IM 通道凭据（`FR-AGT-LINK-CHAN-003`）：AppID 明文 + Secret 草稿。
    /// Secret 草稿留空 = 不改动已存的那把；**输入框永不回填本体**（只显示长度与尾 4）。
    @State private var imAppID = ""
    @State private var imSecretInput = ""
    /// 扫码接入（`FR-AGT-LINK-CHAN-003`）：一条正规路径，和手填 AppID/Secret 并列。
    @State private var isQQScanPresented = false
    @State private var imLine: String?
    /// 配置面三格（网关端点 / 机器人标识 / 接收任务开关）—— 与凭据同一份文件。
    /// ★0（2026-10-28 主人拍板）：地址不再由用户填 —— 只选环境，网关地址由程序自己取。
    @State private var imEnvironment: AgentIMQQEnvironment?
    /// 高级项：自建中继地址（留空 = 走官方）。
    @State private var imRelayURL = ""
    @State private var imReceiveTasks = false
    @State private var isTestingIM = false
    /// 自检结论（「配置了不起作用」时先看这一行，不猜）。
    @State private var imSelfCheckLine: String?
    /// 连接测试的结果行（`nil` = 还没测过）。
    @State private var testLine: String?
    @State private var isTesting = false
    @State private var clearAPIKey = false
    @State private var isLoaded = false
    /// 当前页签（分页只影响呈现；保存仍是一处保存全部）。
    @State private var selectedTab: AgentSettingsTab = .model
    /// 授权粒度（`FR-AI-34`）：任务范围内代签 = 少问；每个动作都问 = 老行为。
    @State private var scopeMode: AgentTaskScope.Mode = .taskScope
    /// **真值源**（`FR-AI-25` 信息面三格）：上下文窗口 + 每百万 token 价目。
    /// 空串 = 没填（窗口退回内置表、价钱那一格不出现）。
    @State private var contextWindowText = ""
    /// MCP 服务器配置面（`FR-AI-21` 界面片）的开合。
    @State private var showsMCPServers = false
    /// **运行策略草稿**（`FR-AGT-OPS-OBS-002`）：五项一屏可改，改完点「保存策略」才落盘。
    /// 草稿不动盘上的东西 —— 取消面板就等于没改过（不会出现「碰了一下选项就生效」）。
    @State private var runtimeDraft = AgentRuntimeConfigDraft(snapshot: AgentConfigSnapshot())
    /// 改动理由（必填）：空着保存会被拒，并在同一行说明为什么。
    @State private var runtimeReason = ""
    /// 上一次保存 / 被拒的一句话结论。
    @State private var runtimeLine: String?
    /// 等确认卸载的插件 id（`FR-AGT-LINK-EXT-003`）：**先问再删** —— 卸的是他自己放进目录的东西。
    @State private var pendingExtensionUninstallID: String?
    /// 显示开关那一下的结论（改了立刻落盘，被拒时在这里说一句；`nil` = 没话要说）。
    @State private var displayLine: String?

    /// 设置面板的页签（主人 2026-10-30 令：「配置框太乱了，应该分成几个 Tab 页」）。
    /// 分页按**用户要做的事**切；底栏的「测试连接 / 取消 / 保存」留在页签外，翻到哪页都按得到。
    private enum AgentSettingsTab: Hashable { case model, runtime, im, extensions, display }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L(.agentSettingsTitle))
                .font(Theme.font(.title))

            TabView(selection: $selectedTab) {
                modelTab
                    .tabItem { Label(L(.agentTabModel), systemImage: "cpu") }
                    .tag(AgentSettingsTab.model)
                runtimeTab
                    .tabItem { Label(L(.agentTabRuntime), systemImage: "gauge.with.dots.needle.50percent") }
                    .tag(AgentSettingsTab.runtime)
                imTab
                    .tabItem { Label(L(.agentTabIM), systemImage: "bubble.left.and.bubble.right") }
                    .tag(AgentSettingsTab.im)
                extensionsTab
                    .tabItem { Label(L(.agentTabExtensions), systemImage: "puzzlepiece") }
                    .tag(AgentSettingsTab.extensions)
                displayTab
                    .tabItem { Label(L(.agentTabDisplay), systemImage: "paintbrush") }
                    .tag(AgentSettingsTab.display)
            }
            .frame(minHeight: 380, maxHeight: .infinity)

            // 工作区根 + 来源 + 恢复默认（`FR-STD-WS-FS-011`）：Agent 的读写边界就在这一格里，
            // 放在页签外 —— 不论用户翻到哪一页都看得见它在哪儿动文件。
            AgentWorkspaceSection()

            statusSection

            footerRow
        }
        // 扫码面板（`FR-AGT-LINK-CHAN-003`）：2026-10-30 查实的**死按钮** ——
        // `isQQScanPresented` 之前只置位、没人接 `.sheet`，点了没反应，等于没有这条正规路径。
        .sheet(isPresented: $isQQScanPresented) {
            QQQRLoginSheet { appID, secret in
                imAppID = appID
                if appState.saveAgentIMCredentials(appID: appID, secret: secret) {
                    imSecretInput = ""
                    imLine = L(.agentIMSaved)
                    appState.refreshAgentIMCredentials()
                } else {
                    imLine = appState.errorMessage
                }
            }
        }
        .padding(Spacing.l)
        .frame(width: AgentSettingsSheet.sheetWidth, height: min(sheetHeight, AgentSettingsSheet.maxSheetHeight))
        // 换提供商 ⇒ 自动填端点与模型；手改端点 ⇒ 重认一次「这是谁」。
        // 两条都不自己判，只读契约层（`AgentProviderCatalog`）给的答案。
        // 切档 = 先把这一档的草稿写回盘，再按新档重载（不许「切过去发现上一档的改动丢了」）。
        .onChange(of: selectedProfileID) { oldValue, newValue in
            guard isLoaded, newValue != oldValue else { return }
            Task {
                if let oldValue, oldValue == appState.activeAgentProfileID {
                    _ = await appState.updateActiveAgentProfile(
                        endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                        model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                        timeoutSeconds: TimeInterval(timeoutSeconds) ?? AgentConfiguration.defaultTimeoutSeconds,
                        pricing: draftPricing)
                }
                guard let newValue, await appState.selectAgentProfile(id: newValue) else { return }
                loadProfileDraft()
            }
        }
        .onChange(of: providerID) { _, newValue in applyProvider(newValue) }
        .onChange(of: endpoint) { _, newValue in syncProvider(with: newValue) }
        .task {
            guard !isLoaded else { return }
            isLoaded = true
            // 从菜单「用 QQ 扫码接入…」进来：直接停在 IM 通道页。
            if appState.agentSettingsOpenIM {
                selectedTab = .im
                appState.agentSettingsOpenIM = false
            }
            let configuration = appState.agentConfiguration
            selectedProfileID = configuration.activeProfile?.id
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
            // IM 通道凭据：回填 AppID（明文）；Secret 草稿留空 —— 输入框里永不出现密钥本体。
            appState.refreshAgentIMCredentials()
            imAppID = appState.agentIMAppID
            imEnvironment = appState.agentIMSettings.environment
            imRelayURL = appState.agentIMSettings.relayURL
            imReceiveTasks = appState.agentIMSettings.receiveTasks
            imSecretInput = ""
            imLine = nil
            // 真值源（`FR-AI-25`）：这一档填过的窗口 / 价目要回填 —— 否则重开面板就是空白，
            // 保存一次等于把用户填过的价目**静默清掉**。
            let pricing = configuration.activeProfile?.pricing
            contextWindowText = pricing?.contextWindow.map { String($0) } ?? ""
            // 价目字段不再展示（同上令）——旧配置里存过的价格不读、也不再写回。
            // MCP 那一行的读数（「还没配置 / 已连上 n / m 条」）需要配置与这一轮的发现结果；
            // 配置读一次就够（`loadAgentMCPConfiguration` 幂等），发现结果由对话那条路填。
            appState.loadAgentMCPConfiguration()
            // 运行策略（`FR-AGT-OPS-OBS-002`）：读盘一次并回填草稿 —— 重开面板显示的是
            // **当前生效的那份**，不是空白（空白保存一次就等于把用户设过的全清掉）。
            appState.loadAgentRuntimeConfigIfNeeded()
            runtimeDraft = AgentRuntimeConfigDraft(snapshot: appState.agentRuntimeConfig.snapshot)
            runtimeReason = ""
            runtimeLine = AgentConfigRejectionText.degradedLine(for: appState.agentRuntimeConfigState)
            // 显示开关（`FR-AGT-UX-CONV-012`）：读盘一次并回填 —— 重开面板显示的是
            // **盘上生效的那份**，不是契约默认值（否则用户一开面板就以为自己设的被清了）。
            appState.loadAgentDisplayPreferencesIfNeeded()
            // 插件目录（`FR-AGT-LINK-EXT-003`）：开面板就扫一次 —— 显示的是**此刻盘上的事实**，
            // 不是上一次关闭时留下的旧读数（用户可能刚把插件文件夹拖进去）。
            appState.rescanAgentExtensions()
            pendingExtensionUninstallID = nil
        }
        .sheet(isPresented: $showsMCPServers) {
            MCPServersSheet()
                .environmentObject(appState)
        }
        // 卸载要二次确认（`FR-AGT-LINK-EXT-003`）：它删的是**他自己放进目录的东西**。
        // 确认后走 `AppState.uninstallAgentExtension`（真删自有路径、交回要停的进程），
        // 结论照收据写，不在这句话里替它下「干净了」的判断。
        .confirmationDialog(
            L(.agentExtensionUninstallConfirmTitle),
            isPresented: Binding(
                get: { pendingExtensionUninstallID != nil },
                set: { if !$0 { pendingExtensionUninstallID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = pendingExtensionUninstallID {
                Button(L(.agentExtensionUninstallAction), role: .destructive) {
                    appState.uninstallAgentExtension(pluginID: id)
                    pendingExtensionUninstallID = nil
                }
            }
            Button(L(.commonCancel), role: .cancel) {
                pendingExtensionUninstallID = nil
            }
        } message: {
            Text(L(.agentExtensionUninstallConfirmBody))
        }
    }

    // MARK: - 五页（内容与改动前的 Form 逐字一致，只是搬进各自的滚动区）

    private var modelTab: some View { tabScroll {
                Toggle(isOn: $isEnabled) {
                    Label(L(.agentEnabled), systemImage: "cpu")
                }
                .help(L(.agentEnabled))
                .accessibilityLabel(Text(L(.agentEnabled)))
                Text(L(.agentEnabledHint))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))

                // **模型档位**（多端点 · `FR-AGT-LINK-CHAN-001` 判据 ⑥）：档 = 端点 + 模型名 + 超时 + 一把独立密钥。
                // 2026-11-08 主人令进 beta1.1：「可以做到 beta1.1 里啊」。此前配置层早就支持多档
                // （`AgentConfiguration.profiles`），但界面只暴露一档 —— 换服务就得把上一组擦掉。
                Section(L(.agentProfileSection)) {
                    Picker(L(.agentProfileSection), selection: $selectedProfileID) {
                        ForEach(appState.agentProfiles) { profile in
                            Text(profile.name.isEmpty ? profile.id : profile.name).tag(Optional(profile.id))
                        }
                    }
                    HStack(spacing: Spacing.s) {
                        Button(L(.agentProfileAdd)) {
                            Task {
                                guard await appState.addAgentProfile() else { return }
                                selectedProfileID = appState.activeAgentProfileID
                                loadProfileDraft()
                                profileLine = nil
                            }
                        }
                        Button(L(.agentProfileDelete), role: .destructive) {
                            Task {
                                guard let id = selectedProfileID,
                                      await appState.deleteAgentProfile(id: id) else {
                                    profileLine = L(.agentProfileLastOne)
                                    return
                                }
                                selectedProfileID = appState.activeAgentProfileID
                                loadProfileDraft()
                                profileLine = nil
                            }
                        }
                        .disabled(appState.agentProfiles.count <= 1)
                        .help(appState.agentProfiles.count <= 1 ? L(.agentProfileLastOne) : L(.agentProfileDelete))
                    }
                    if let profileLine {
                        Text(profileLine)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                    }
                }

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
                // 端点判定三档（`NFR-ALL-GATE-AI-006` ③）：这一句由 Core 出，界面只搬结论。
                // 原先界面对「本地 / 远端 / 用不了」三件事一个字都不说 —— 地址写错的人
                // 只会看到「需要 API Key」，然后去补一把用它不上的 Key。
                Text(endpointVerdict)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                HStack(spacing: Spacing.s) {
                    TextField(L(.agentModel), text: $model, prompt: Text(L(.agentModelPlaceholder)))
                    Menu {
                        ForEach(selectedPreset.modelOptions(currentModel: model), id: \.self) { name in
                            Button(name) { model = name }
                        }
                    } label: {
                        // 纯图标的菜单在表单里就是一枚「不知道是什么」的箭头（`FR-STD-WS-UI-014`）：
                        // 加文字之后它才说明自己挑的是「模型名」。
                        Label(L(.agentModel), systemImage: "chevron.up.chevron.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(selectedPreset.models.isEmpty)
                    .help(L(.agentModelPresetHint))
                }
                TextField(L(.agentTimeout), text: $timeoutSeconds)

                // **2026-10-25 人类主人令**：「没有谁在这里去配置价格，我们看成本也只关心消耗的
                // token 数量，而不是直接换算成人民币」⇒ 价目三格与币种选择**整块删掉**，
                // 面板里只留上下文窗口（它是唯一影响「还能装多少」的真值源）。
                Section(L(.agentMeterSection)) {
                    TextField(L(.agentMeterWindow), text: $contextWindowText,
                              prompt: Text(L(.agentMeterWindowPlaceholder)))
                    Text(L(.agentMeterFootnote))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                }

                Section(L(.agentQuotaSection)) {
                    TextField(L(.agentMaxRequests), text: $maxRequests)
                    TextField(L(.agentMaxOutputTokens), text: $maxOutputTokens)
                    TextField(L(.agentMaxTotalTokens), text: $maxTotalTokens)
                    // 已用量（判据 ③ 的「有据可查」那一面）：账本跨重启累计，人得看得见用了多少，
                    // 否则「到了上限」是一句没有上下文的话。
                    quotaUsageLine
                    // **清零入口**：账本不再随退出清零以后，没有这一枚，上限一旦用满就是死路。
                    Button(L(.agentQuotaReset)) {
                        appState.resetAgentQuotaUsage()
                        quotaLine = L(.agentQuotaResetDone)
                    }
                    .help(L(.agentQuotaReset))
                    if !quotaLine.isEmpty {
                        Text(quotaLine)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                    }
                }

                Section(L(.agentScopeSection)) {
                    Picker(L(.agentScopeSection), selection: $scopeMode) {
                        Text(L(.agentScopeTaskScope)).tag(AgentTaskScope.Mode.taskScope)
                        Text(L(.agentScopeAskEach)).tag(AgentTaskScope.Mode.askEachAction)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(L(.agentScopeFootnote))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                }

                // **MCP 服务器**（`FR-AI-21` 界面片）：这里是入口 + 一行读数，
                // 真正的加 / 删 / 开关与「连不上」的原因在弹层里（`MCPServersSheet`）。
                Section(L(.agentAPIKey)) {
                    SecureField(L(.agentAPIKey), text: $apiKeyInput)
                    Text(appState.hasAgentAPIKey ? L(.agentAPIKeyConfigured) : L(.agentAPIKeyMissing))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))

                    if appState.hasAgentAPIKey {
                        Toggle(isOn: $clearAPIKey) {
                            Label(L(.agentAPIKeyClear), systemImage: "key.slash")
                        }
                        .help(L(.agentAPIKeyClear))
                        .accessibilityLabel(Text(L(.agentAPIKeyClear)))
                        .font(Theme.font(.caption))
                    }
                }

                // IM 通道（`FR-AGT-LINK-CHAN-003`）：**能配、能看状态、能测**。
                // 2026-10-28 主人原话：「怎么连配置IM通道的界面都没有呢？」—— 此前这一节只有
                // AppID / Secret 两格 + 一句「传输层未实现」，于是「配齐了没」「连没连上」
                // 没有任何一处说得清。现在四样配置 + 一行状态（未配置 / 未连接 / 正在连接 /
                // 已连接 / 未连通+原因）+ 测试连接；状态与「缺什么」全由 Core 合成，界面只搬结论。
    } }

    private var runtimeTab: some View { tabScroll {
                // **联网检索**（`FR-AGT-TOOL-INGEST-004`）：两个后端任选，DDG 免 key 开箱可用。
                // 读数写「当前后端」而不是用户点的那个选项 —— `auto` 的解析结果才是有用的那句话。
                Section(L(.agentWebSearchSection)) {
                    Picker(L(.agentWebSearchBackend), selection: $webBackend) {
                        Text(L(.agentWebSearchBackendAuto)).tag(AgentWebSearchConfig.Backend.auto)
                        Text("DuckDuckGo").tag(AgentWebSearchConfig.Backend.duckduckgo)
                        Text(L(.agentWebSearchBackendBing)).tag(AgentWebSearchConfig.Backend.bing)
                        Text("Tavily").tag(AgentWebSearchConfig.Backend.tavily)
                    }
                    .onAppear { webBackend = appState.agentWebSearchBackend }
                    .onChange(of: webBackend) { _, newValue in
                        appState.agentWebSearchBackend = newValue
                    }
                    HStack(spacing: Spacing.s) {
                        Text("\(L(.agentWebSearchCurrent))：\(appState.agentWebSearchBackendLine)")
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                    }
                    SecureField(L(.agentWebSearchKey), text: $webKeyInput)
                    HStack(spacing: Spacing.s) {
                        Button(L(.agentWebSearchSave)) {
                            webKeyStatus = appState.saveAgentWebSearchKey(webKeyInput)
                            webKeyInput = ""
                        }
                        .buttonStyle(.bordered)
                        if !webKeyStatus.isEmpty {
                            Text(webKeyStatus)
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                        }
                    }
                    Text(L(.agentWebSearchKeyHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section(L(.agentMCPSection)) {
                    HStack(spacing: Spacing.s) {
                        Button(L(.agentMCPConfigure)) { showsMCPServers = true }
                            .buttonStyle(.bordered)
                        Text(mcpSummary)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                    }
                    Text(L(.agentMCPHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                }

                // **运行策略**（`FR-AGT-OPS-OBS-002`）：五项都带默认值与影响说明；
                // 改完点「保存策略」才落盘（一次全落或一条都不落），并把「谁改的、改前改后、
                // 为什么」留在盘上那份留痕里 —— 下面「最近改动」显示的就是它。
                Section(L(.agentRuntimeSection)) {
                    LabeledContent(L(.agentRuntimeConcurrency)) {
                        TextField(L(.agentRuntimeConcurrency), text: $runtimeDraft.maxConcurrentSubtasks)
                            .labelsHidden()
                    }
                    Text(L(.agentRuntimeConcurrencyHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))

                    LabeledContent(L(.agentRuntimeTimeout)) {
                        TextField(L(.agentRuntimeTimeout), text: $runtimeDraft.commandTimeoutSeconds)
                            .labelsHidden()
                    }
                    Text(L(.agentRuntimeTimeoutHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))

                    LabeledContent(L(.agentRuntimeDailyQuota)) {
                        TextField(L(.agentRuntimeDailyQuota), text: $runtimeDraft.dailyTokenQuota)
                            .labelsHidden()
                    }
                    Text(L(.agentRuntimeDailyQuotaHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                    // 今日读数（日配额的「有据可查」那一面）：用了多少 / 上限多少。
                    todayUsageLine

                    Toggle(isOn: $runtimeDraft.notificationsEnabled) {
                        Label(L(.agentRuntimeNotify), systemImage: "bell")
                    }
                    .help(L(.agentRuntimeNotify))
                    .accessibilityLabel(Text(L(.agentRuntimeNotify)))
                    Text(L(.agentRuntimeNotifyHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))

                    LabeledContent(L(.agentRuntimeWhitelist)) {
                        TextField(L(.agentRuntimeWhitelist), text: $runtimeDraft.toolWhitelist)
                            .labelsHidden()
                    }
                    Text(L(.agentRuntimeWhitelistHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))

                    // **审批策略**（`FR-AGT-OPS-OBS-002`）：工具调用的默认宽严。
                    // 下拉而不是输入框：三档是封闭词表，写错一个字就整份拒收（面板上不该教人背单词）。
                    LabeledContent(L(.agentRuntimeApproval)) {
                        Picker(L(.agentRuntimeApproval), selection: $runtimeDraft.approvalPolicy) {
                            Text(L(.agentRuntimeApprovalAllow)).tag("allow")
                            Text(L(.agentRuntimeApprovalAsk)).tag("ask")
                            Text(L(.agentRuntimeApprovalDeny)).tag("deny")
                        }
                        .labelsHidden()
                    }
                    Text(L(.agentRuntimeApprovalHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                    if !appState.agentToolWhitelistUnknown.isEmpty {
                        // 名单里写了工具名但注册表里没有：**点名**（否则面板上那句「已限制」
                        // 会让人以为限制成功，实际什么都没限到）
                        Text(appState.agentToolWhitelistUnknown.joined(separator: ", "))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.status(.warning))
                    }

                    LabeledContent(L(.agentRuntimeReason)) {
                        TextField(L(.agentRuntimeReason), text: $runtimeReason,
                                  prompt: Text(L(.agentRuntimeReasonPlaceholder)))
                            .labelsHidden()
                    }
                    HStack(spacing: Spacing.s) {
                        Button(L(.agentRuntimeSave)) { saveRuntimePolicy() }
                            .buttonStyle(.bordered)
                        if let runtimeLine {
                            Text(runtimeLine)
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !appState.agentRuntimeConfig.changes.isEmpty {
                        Text(L(.agentRuntimeHistoryTitle))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.tertiary))
                        ForEach(Array(AgentConfigRejectionText
                            .historyLines(appState.agentRuntimeConfig.changes).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // **已授权的操作**（§3.36 ④）：能看见，才能收得回。
                // 会话级（换会话即失效）与全局级（跨重启）都在这一节，逐条可撤、也能一次全撤。
                // 与「审批策略」的关系：那一格管**基线宽严**，这一节管**具体哪一条不再问** ——
                // 撤销之后立刻恢复询问（判定读的就是这本账，不在别处留副本）。
                Section(L(.agentApprovalGrantsSection)) {
                    if appState.agentApprovalGrants.isEmpty {
                        Text(L(.agentApprovalGrantsEmpty))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(appState.agentApprovalGrants) { grant in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                                VStack(alignment: .leading, spacing: Spacing.hair) {
                                    Text("\(grant.tool) · \(grant.scope)")
                                        .font(Theme.font(.caption))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(grant.tier == .always
                                         ? L(.agentApprovalGrantsAlways)
                                         : L(.agentApprovalGrantsSession))
                                        .font(Theme.font(.caption))
                                        .foregroundStyle(Theme.text(.secondary))
                                }
                                Spacer(minLength: Spacing.s)
                                Button(L(.agentApprovalGrantsRevoke)) {
                                    appState.revokeAgentApprovalGrant(id: grant.id)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        Button(L(.agentApprovalGrantsRevokeAll)) {
                            appState.revokeAllAgentApprovalGrants()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .onAppear { appState.loadAgentApprovalGrants() }

                // **插件（扩展点）**（`FR-AGT-LINK-EXT-003` 的界面那一半）：
                // 装了哪些、每个真授权了什么、没装上的为什么、卸完还剩什么 —— 四件都在这一节。
                // 「装」这件事本身 = 把插件文件夹放进目录（面板不假装能凭空拉一个插件下来），
                // 所以这里给的是**目录入口 + 重扫 + 卸载**，不是「安装」按钮。
    } }

    private var imTab: some View { tabScroll {
                Section(L(.agentIMSection)) {
                    // **正规路径放最上面**（主人 2026-10-30：「你说的QQ扫码配置也没有，那只是一个链接
                    // 跳转到QQ机器人官网」——按钮埋在一排次要按钮里，等于没有）。
                    Button(L(.agentIMQRButton)) { isQQScanPresented = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("agent-im-qr-connect")
                    Text(L(.agentIMQRInlineHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    // ★0（2026-10-28 主人原话「既然是 QQ 通道，为什么还要用户填 wss 地址？」）：
                    // 地址整格删掉，只留「环境」—— 程序拿 AppID + Secret 换 token、再问官方要网关地址。
                    Picker(L(.agentIMFieldEnvironment), selection: $imEnvironment) {
                        Text(L(.agentIMEnvironmentNone)).tag(AgentIMQQEnvironment?.none)
                        Text(L(.agentIMEnvironmentProduction)).tag(AgentIMQQEnvironment?.some(.production))
                        Text(L(.agentIMEnvironmentSandbox)).tag(AgentIMQQEnvironment?.some(.sandbox))
                    }
                    TextField(L(.agentIMAppID), text: $imAppID)
                    SecureField(L(.agentIMSecret), text: $imSecretInput)
                    Text(imSecretStatusLine)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                    Text(L(.agentIMSecretKeepHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                    Text(L(.agentIMEnvironmentHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    if imEnvironment == .sandbox {
                        Text(L(.agentIMSandboxHint))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.status(.warning))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 扫码接入（2026-10-29 主人两次点出后的口径）：QQ 官方连接器扫码后**直接返回**
                    // AppID / AppSecret / 主人 openid ⇒ 扫码是一条正规路径，不是「平台登录」。
                    // 手填 AppID/Secret 保留作备用（离线 / 没装 Node 时）。
                    Button(L(.agentIMOpenPlatform)) {
                        if let url = URL(string: "https://q.qq.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Text(L(.agentIMOpenPlatformHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle(isOn: $imReceiveTasks) {
                        Label(L(.agentIMReceiveTasks), systemImage: "tray.and.arrow.down")
                    }
                    .help(L(.agentIMReceiveTasks))
                    .accessibilityLabel(Text(L(.agentIMReceiveTasks)))
                    Text(L(.agentIMReceiveTasksHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                        .fixedSize(horizontal: false, vertical: true)

                    // 高级项：自建中继地址。默认折叠、默认留空 —— 认不出会报错，但不挡主路径
                    // （主人 2026-10-28：「自建中继地址」降为高级项）。
                    DisclosureGroup(L(.agentIMRelayAdvanced)) {
                        TextField(L(.agentIMFieldRelayURL), text: $imRelayURL, prompt: Text("wss://"))
                        Text(L(.agentIMRelayHint))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // 状态行：**一档**（配置齐不齐与传输层状态在 Core 里合成，界面不再各写一句）。
                    Text(imStatusLine)
                        .font(Theme.font(.caption))
                        .foregroundStyle(appState.agentIMStatusKind.isOnline
                                         ? Theme.status(.success) : Theme.status(.warning))
                        .fixedSize(horizontal: false, vertical: true)

                    // 地址是程序自己取的 ⇒ 至少要说清用的是哪一个（取到的 / 兜底的 / 自建中继）。
                    if let gatewayLine = appState.agentIMGatewayLine {
                        Text(gatewayLine)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if appState.agentIMTokenPreview != nil {
                        Text(appState.agentIMTokenLine)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                    }
                    HStack(spacing: Spacing.m) {
                        Button(L(.agentIMSave)) { saveIMCredentials() }
                        Button(L(.agentIMTest)) { testIMConnection() }
                            .disabled(isTestingIM)
                        Button(L(.agentIMConnect)) { connectIMChannel() }
                        Button(L(.agentIMDisconnect)) { disconnectIMChannel() }
                        Button(L(.agentIMClear), role: .destructive) { clearIMCredentials() }
                    }
                    HStack(spacing: Spacing.m) {
                        Button(L(.agentIMSelfCheck)) { runIMSelfCheck() }
                            .accessibilityIdentifier("agent-im-selfcheck")
                        if let imSelfCheckLine {
                            Text(imSelfCheckLine)
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("agent-im-selfcheck-line")
                        }
                        Spacer()
                    }
                    if let imLine {
                        Text(imLine)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let outboundLine = appState.agentIMOutboundLine {
                        // 外发那一档：发不出去时用户要看得见是凭据 / 限流 / 网络（不能只留一句「已连接」）。
                        Text(outboundLine)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if appState.agentIMInboundHandled > 0 {
                        // 两个数**分开**：跑过几轮 ≠ 推回去几条（推不出去的留在队列里等重连补发）。
                        Text(L(.agentIMInboundReceived, Int64(appState.agentIMInboundHandled)))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                        Text(L(.agentIMInboundReplied, Int64(appState.agentIMInboundReplied)))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                    }
                }
    } }

    private var extensionsTab: some View { tabScroll {
                Section(L(.agentExtensionSection)) {
                    extensionDirectorySection
                    extensionInstalledSection
                    extensionProblemsSection
                }
                // **显示开关**（`FR-AGT-UX-CONV-012` 九个，跨端同名同默认）：
                // 每一项**改完立刻生效并落盘**（与运行策略不同 —— 那边要理由、要批量原子校验）。
                // 这里不收理由：观感开关塞进审计会把真正的审计淹掉。
    } }

    private var displayTab: some View { tabScroll {
                Section(L(.agentDisplaySection)) {
                    Text(L(.agentDisplayHint))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))

                    Toggle(isOn: displayToggle(.streaming)) {
                        Label(L(.agentDisplayStreaming), systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    .help(L(.agentDisplayStreaming))
                    .accessibilityLabel(Text(L(.agentDisplayStreaming)))

                    Toggle(isOn: displayToggle(.compact)) {
                        Label(L(.agentDisplayCompact), systemImage: "rectangle.compress.vertical")
                    }
                    .help(L(.agentDisplayCompact))
                    .accessibilityLabel(Text(L(.agentDisplayCompact)))

                    Toggle(isOn: displayToggle(.thinking)) {
                        Label(L(.agentDisplayThinking), systemImage: "brain")
                    }
                    .help(L(.agentDisplayThinking))
                    .accessibilityLabel(Text(L(.agentDisplayThinking)))

                    Toggle(isOn: displayToggle(.timestamps)) {
                        Label(L(.agentDisplayTimestamps), systemImage: "clock")
                    }
                    .help(L(.agentDisplayTimestamps))
                    .accessibilityLabel(Text(L(.agentDisplayTimestamps)))

                    Picker(L(.agentDisplayToolProgress), selection: displayToolProgress) {
                        ForEach(AgentToolProgressMode.allCases, id: \.self) { mode in
                            Text(toolProgressLabel(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(L(.agentDisplayIndicatorGlyph), selection: displayGlyph) {
                        ForEach(AgentIndicatorGlyph.allCases, id: \.self) { style in
                            Text(glyphLabel(style)).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(L(.agentDisplayLongPreview), selection: displayLongPreview) {
                        Text(L(.agentDisplayPreviewOff)).tag(AgentLongMessagePreview.off)
                        ForEach(Self.previewChoices, id: \.self) { choice in
                            Text(L(.agentDisplayPreviewHeadTail,
                                   Int64(choice.edges?.head ?? 0),
                                   Int64(choice.edges?.tail ?? 0))).tag(choice)
                        }
                    }

                    Toggle(isOn: displayToggle(.bottomBarMeta)) {
                        Label(L(.agentDisplayBottomBarMeta), systemImage: "rectangle.bottomthird.inset.filled")
                    }
                    .help(L(.agentDisplayBottomBarMeta))
                    .accessibilityLabel(Text(L(.agentDisplayBottomBarMeta)))

                    Picker(L(.agentDisplaySubmitWhileRunning), selection: displaySubmitWhileRunning) {
                        ForEach(AgentSubmitWhileRunning.allCases, id: \.self) { mode in
                            Text(submitLabel(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: Spacing.s) {
                        Button(L(.agentDisplayResetDefaults)) { resetAgentDisplay() }
                            .buttonStyle(.bordered)
                        if let displayLine {
                            Text(displayLine)
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                        } else if case let .degraded(reason) = appState.agentDisplayPreferencesState {
                            Text(AgentDisplayRejectionText.degradedLine(
                                reason: reason,
                                language: LocalizationManager.shared.effectiveLanguage))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.status(.warning))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

    } }

    /// 每页同一副壳：自己滚动、`Form` 系统样式、吃满剩余高度。
    private func tabScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            Form { content() }
                .formStyle(.grouped)
                // 标签列给足宽度，说明文字整行铺开 —— 不再挤到边框外（2026-10-30 主人指出的窄）。
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private var footerRow: some View {
            HStack(spacing: Spacing.m) {
                Button(L(.agentTestConnection)) {
                    isTesting = true
                    testLine = L(.agentTestRunning)
                    Task {
                        // 用面板里刚输入的那份 Key 去测（否则刚填完 Key 点测试仍会用旧值）
                        let result = await appState.testAgentConnection(apiKeyOverride: apiKeyInput)
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
                        .font(Theme.font(.body))
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(2)
                }

                Spacer()

                Button(L(.commonCancel), role: .cancel) { dismiss() }
                    .buttonStyle(.bordered)

                Button(L(.agentSave)) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L(.agentStatusSection))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))

            HStack(spacing: Spacing.s) {
                Image(systemName: decision.isAllowed ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(decision.isAllowed ? .green : .secondary)
                Text(decision.message)
                    .font(Theme.font(.caption))
                    .foregroundStyle(decision.isAllowed ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !draftConfiguration.issues.isEmpty {
                Label(L(.agentInvalidHint), systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 提供商预设（L-146）

    /// 端点判定那一行话（`NFR-ALL-GATE-AI-006` ③）。
    ///
    /// 只搬 Core 的结论：本地免 Key / 远端需 Key / 不可用 + 具体原因（少协议头、协议不对、缺主机名…）。
    private var endpointVerdict: String {
        AgentConfiguration(endpoint: endpoint)
            .endpointDiagnosis
            .summary(language: LocalizationManager.shared.effectiveLanguage)
    }

    /// 当前选中的提供商：界面画标签与模型下拉都取自它（标识认不出就退回「自定义」）。
    private var selectedPreset: AgentProviderPreset {
        AgentProviderCatalog.preset(id: providerID) ?? AgentProviderCatalog.custom
    }

    /// 选提供商 ⇒ 自动填端点；模型**只在还空着时**带预设第一项。
    ///
    /// **不许顶掉用户手填的模型名**（人类主人 2026-11-03 实测：「我明明设置的是
    /// `deepseek-v4.1-flash`，保存之后打开又显示 `pro`」）。原因就是这里无条件
    /// `model = preset.models.first`：预设清单里只有 `deepseek-v4-pro / -flash`，
    /// 手填的 `v4.1-flash` 一旦被重认提供商（`syncProvider(with:)` 在端点变化/加载时
    /// 都会调过来）就会被覆盖成清单第一项 = `pro`。清单永远是滞后于厂商发版的，
    /// 所以「用户填的 > 预设清单」这条优先序必须写死在这里。
    private func applyProvider(_ id: String) {
        guard let preset = AgentProviderCatalog.preset(id: id), !preset.isCustom else { return }
        endpoint = preset.endpoint
        let typed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty, let first = preset.models.first { model = first }
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
    /// 载入**当前档**的字段到草稿（切档 / 增删档之后调）。
    /// 只搬这一档的四个输入格 + 上下文窗口；配置面的全局项（总开关 / 配额 / 授权粒度）不随档变。
    private func loadProfileDraft() {
        guard let profile = appState.activeAgentProfile else { return }
        endpoint = profile.endpoint
        model = profile.model
        timeoutSeconds = String(Int(profile.timeoutSeconds))
        providerID = AgentProviderCatalog.resolved(endpoint: profile.endpoint).id
        contextWindowText = profile.pricing?.contextWindow.map(String.init) ?? ""
        appState.refreshActiveAgentKey()
        profileLine = nil
    }

    private var draftPricing: AgentModelPricing? {
        // 价目不再由用户填（2026-10-25 令）：只保留上下文窗口。
        let pricing = AgentModelPricing(
            contextWindow: positiveInt(contextWindowText),
            inputPerMillion: nil,
            outputPerMillion: nil,
            cachedInputPerMillion: nil,
            currency: .cny
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

    /// 对话框高度：**跟着可用屏幕算，不跟着内容长**。
    ///
    /// `NSScreen.visibleFrame` 已经扣掉菜单栏与 Dock，再留 96 点给窗口边距 ——
    /// 这样在 13 寸笔记本（可用约 700 点）上也不会把底栏推到 Dock 底下。
    /// 对话框高度上限 = 屏幕可见高度的 85%（再高就会被 Dock / 菜单栏吃掉底部按钮）。
    /// 对话框宽度：**跟着屏幕走**，不再死钉 560 点。
    /// 2026-10-30 主人原话：「就那么一点点宽，字体都撑到两边外面去了」——
    /// `Form(.columns)` 的标签列在 560 点里放不下，直接被裁到边框外。
    static var sheetWidth: CGFloat {
        let visible = NSScreen.main?.visibleFrame.width ?? 1200
        return min(920, max(700, visible * 0.66))
    }

    static var maxSheetHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(420, visible - 120)
    }


    private var sheetHeight: CGFloat {
        let available = (NSScreen.main?.visibleFrame.height ?? 800) - 96
        return min(780, max(460, available))
    }

    /// 今日用量那一行（`%d / %d`）。
    ///
    /// 两个数都先落成**显式标注的局部量**再进模板：门禁 `check-format-arguments` 认不出
    /// `reading.used` 这种冒号取值的类型，而这里形状是确定的 `Int`（日配额账本给的就只有 Int）。
    private var todayUsageLine: some View {
        let reading = appState.agentDailyTokenReading()
        let used: Int = reading.used
        let quota: Int = reading.quota
        return Text(L(.agentRuntimeTodayUsage, used, quota))
            .font(Theme.font(.caption))
            .foregroundStyle(used >= quota ? Theme.status(.warning) : Theme.text(.secondary))
    }

    /// 配额已用量那一行（`NFR-ALL-GATE-AI-004` ③）：次数 / token 两个数 + 账本坏了的如实提示。
    ///
    /// 两个数落成显式 `Int` 局部量再进模板（同 `todayUsageLine`：门禁 `check-format-arguments`
    /// 认不出 `.used` 这种冒号取值的类型）。
    private var quotaUsageLine: some View {
        let reading = appState.agentQuotaUsageReading()
        let requests: Int = reading.ledger.requestCount
        let tokens: Int = reading.ledger.totalTokens
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L(.agentQuotaUsage, requests, tokens))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            if reading.degraded {
                Text(L(.agentQuotaUsageDegraded))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
            }
        }
    }

    /// 保存运行策略：差异 → 原子校验 → 落盘 → 换内存那份；结论列在按钮右边。
    ///
    /// 为什么单独一个按钮、不并进「保存」：这一批改动**要写理由**（`AgentConfigStore` 的硬要求），
    /// 跟模型 / 密钥那种「配好就用」不是一回事 —— 混在一起会让人以为改个超时也要写理由。
    private func saveRuntimePolicy() {
        switch appState.saveAgentRuntimeConfig(draft: runtimeDraft, reason: runtimeReason) {
        case .noChange:
            runtimeLine = L(.agentRuntimeNoChange)
        case .saved(let lines):
            runtimeLine = L(.agentRuntimeSaved) + (lines.isEmpty ? "" : " " + lines.joined(separator: "；"))
            runtimeReason = ""
            // 存完以**盘上那份**回填（顺序 / 归一化都以它为准，草稿不再自己留着旧字符串）
            runtimeDraft = AgentRuntimeConfigDraft(snapshot: appState.agentRuntimeConfig.snapshot)
        case .rejected(let reason):
            runtimeLine = L(.agentRuntimeRejected, reason)
        }
    }

    // MARK: - 插件装卸（`FR-AGT-LINK-EXT-003` 的界面那一半）

    /// 面板要的读数（面板与循环读的是同一份台账，这里不另算一遍）。
    private var extensionPanel: AgentExtensionPanel {
        AgentExtensionPanel(desk: appState.agentExtensionDesk, problems: appState.agentExtensionProblems)
    }

    /// 目录入口：在哪儿放插件、往哪儿看、什么时候重扫。
    private var extensionDirectorySection: some View {
        Group {
            LabeledContent(L(.agentExtensionDirectory)) {
                Text(appState.agentExtensionDirectory.path)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack(spacing: Spacing.s) {
                Button(L(.agentExtensionOpenFolder)) {
                    NSWorkspace.shared.activateFileViewerSelecting([appState.agentExtensionDirectory])
                }
                .buttonStyle(.bordered)
                Button(L(.agentExtensionRescan)) {
                    appState.rescanAgentExtensions()
                }
                .buttonStyle(.bordered)
            }
            if extensionPanel.rows.isEmpty {
                Text(L(.agentExtensionEmpty))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 已装的那几行 + 最近一次卸载的读数。
    private var extensionInstalledSection: some View {
        Group {
            ForEach(extensionPanel.rows) { row in
                agentExtensionRow(row)
            }
            if let receipt = appState.agentExtensionLastUninstall {
                agentExtensionUninstallLine(receipt)
            }
        }
    }

    /// 没装上的清单：逐条「哪个文件 + 为什么」，一条都不静默跳过。
    private var extensionProblemsSection: some View {
        Group {
            if !extensionPanel.problems.isEmpty {
                Text(L(.agentExtensionProblemsTitle))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                ForEach(Array(extensionPanel.problems.enumerated()), id: \.offset) { _, problem in
                    extensionProblemRow(problem)
                }
            }
        }
    }

    private func extensionProblemRow(_ problem: AgentExtensionPanelProblem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(problem.file)
                .font(Theme.font(.monoSmall))
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(AgentExtensionRejectionText.line(for: problem.code))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.status(.warning))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// 已装插件的一行：id · 槽位 · 三样真授权面 · 钩子与自有路径条数 · 卸载。
    ///
    /// 「真授权面」是**这次装批下来的**，不是清单声明的 —— 两者不一样时（比如只批了一个能力），
    /// 在这一行上看到的必须是与运行期一致的那一份，否则面板会替插件吹牛。
    private func agentExtensionRow(_ row: AgentExtensionPanelRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(row.id)
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(Theme.text(.primary))
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button(L(.agentExtensionUninstall)) {
                    pendingExtensionUninstallID = row.id
                }
                .buttonStyle(.bordered)
                .help(L(.agentExtensionUninstallConfirmTitle))
            }
            extensionFact(L(.agentExtensionSlot), row.slot)
            extensionFact(L(.agentExtensionProvides), row.provides.joined(separator: ", "))
            extensionFact(L(.agentExtensionDirectories), row.readableDirectories.joined(separator: ", "))
            extensionFact(L(.agentExtensionCommands), row.allowedCommands.joined(separator: ", "))
            extensionFact(L(.agentExtensionHooks), String(row.hookCount))
            extensionFact(L(.agentExtensionOwnedPaths), String(row.ownedPathCount))
        }
        .padding(.vertical, Spacing.xs)
    }

    /// 「标签：值」一行；值空着就写「无」—— 留空容易被看成「还没加载」。
    private func extensionFact(_ label: String, _ value: String) -> some View {
        let shown = value.isEmpty ? L(.agentExtensionNone) : value
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(label)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
            Text(shown)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// 卸载之后的读数：卸没卸成、还剩什么。**不替它说「干净」以外的任何判断**。
    private func agentExtensionUninstallLine(_ receipt: AgentExtensionUninstallReceipt) -> some View {
        let residue = AgentExtensionPanel.residue(of: receipt)
        return VStack(alignment: .leading, spacing: Spacing.xs / 2) {
            Text(receipt.wasInstalled
                 ? L(.agentExtensionUninstalled) + " " + receipt.pluginID
                 : L(.agentExtensionUninstallMissing))
                .font(Theme.font(.caption))
                .foregroundStyle(receipt.wasInstalled ? Theme.text(.secondary) : Theme.status(.warning))
                .fixedSize(horizontal: false, vertical: true)
            if receipt.wasInstalled {
                if residue.isClean {
                    Text(L(.agentExtensionResidueClean))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                } else {
                    if !residue.paths.isEmpty {
                        Text(L(.agentExtensionResiduePaths) + " " + residue.paths.joined(separator: ", "))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.status(.warning))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !residue.processes.isEmpty {
                        Text(L(.agentExtensionResidueProcesses) + " "
                             + residue.processes.map(String.init).joined(separator: ", "))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.status(.warning))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if residue.grantRemains {
                        Text(L(.agentExtensionResidueGrant))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.status(.warning))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 显示开关（`FR-AGT-UX-CONV-012`）

    /// 面板上「长消息预览」那几个可选行数对（契约默认 2+2 在第一位）。
    static let previewChoices: [AgentLongMessagePreview] = [
        .headTail(head: 2, tail: 2),
        .headTail(head: 3, tail: 3),
        .headTail(head: 5, tail: 5),
    ]

    /// 布尔开关 → 绑定：**改一下就直接落盘**（不攒草稿、不要理由）。
    /// 写失败时把一句人话留在 `displayLine`，并**不换内存那份**（界面与盘上必须一致）。
    private func displayToggle(_ key: AgentDisplayKey) -> Binding<Bool> {
        Binding(
            get: {
                switch key {
                case .streaming: return appState.agentDisplayPreferences.streaming
                case .compact: return appState.agentDisplayPreferences.compact
                case .thinking: return appState.agentDisplayPreferences.thinking
                case .timestamps: return appState.agentDisplayPreferences.timestamps
                case .bottomBarMeta: return appState.agentDisplayPreferences.bottomBarMeta
                case .toolProgress, .indicatorGlyph, .longPreview, .submitWhileRunning: return false
                }
            },
            set: { newValue in
                applyDisplay(key: key, value: newValue ? "on" : "off")
            }
        )
    }

    private var displayToolProgress: Binding<AgentToolProgressMode> {
        Binding(get: { appState.agentDisplayPreferences.toolProgress },
                set: { applyDisplay(key: .toolProgress, value: $0.rawValue) })
    }

    private var displayGlyph: Binding<AgentIndicatorGlyph> {
        Binding(get: { appState.agentDisplayPreferences.indicatorGlyph },
                set: { applyDisplay(key: .indicatorGlyph, value: $0.rawValue) })
    }

    private var displayLongPreview: Binding<AgentLongMessagePreview> {
        Binding(get: { appState.agentDisplayPreferences.longPreview },
                set: { applyDisplay(key: .longPreview, value: $0.canonicalValue) })
    }

    private var displaySubmitWhileRunning: Binding<AgentSubmitWhileRunning> {
        Binding(get: { appState.agentDisplayPreferences.submitWhileRunning },
                set: { applyDisplay(key: .submitWhileRunning, value: $0.rawValue) })
    }

    private func applyDisplay(key: AgentDisplayKey, value: String) {
        switch appState.setAgentDisplay(key: key, value: value) {
        case .saved: displayLine = nil
        case let .rejected(line): displayLine = line
        }
    }

    private func resetAgentDisplay() {
        switch appState.resetAgentDisplayPreferences() {
        case .saved: displayLine = nil
        case let .rejected(line): displayLine = line
        }
    }

    private func toolProgressLabel(_ mode: AgentToolProgressMode) -> String {
        switch mode {
        case .all: return L(.agentDisplayProgressAll)
        case .summary: return L(.agentDisplayProgressSummary)
        case .off: return L(.agentDisplayProgressOff)
        }
    }

    private func glyphLabel(_ style: AgentIndicatorGlyph) -> String {
        switch style {
        case .emoji: return L(.agentDisplayGlyphEmoji)
        case .unicode: return L(.agentDisplayGlyphUnicode)
        case .ascii: return L(.agentDisplayGlyphAscii)
        }
    }

    private func submitLabel(_ mode: AgentSubmitWhileRunning) -> String {
        switch mode {
        case .interrupt: return L(.agentDisplaySubmitInterrupt)
        case .queue: return L(.agentDisplaySubmitQueue)
        }
    }

    /// 面板上的密钥读数：只给长度与尾 4（本体永不出钥匙串）。
    private var imSecretStatusLine: String {
        if appState.hasAgentIMSecret {
            // 显式成 Int / String：`L(...)` 的占位符类型必须能被判据认出（`%d` / `%@`）。
            let length: Int = appState.agentIMSecretLength ?? 0
            let tail: String = appState.agentIMSecretTail ?? ""
            return L(.agentIMSecretConfigured, length, tail)
        }
        return L(.agentIMSecretMissing)
    }

    /// 面板那一行状态（Core 合成的一档：未配置 / 未连接 / 正在连接 / 已连接 / 未连通+原因）。
    private var imStatusLine: String {
        AgentIMStatusText.line(for: appState.agentIMStatusKind,
                               language: LocalizationManager.shared.effectiveLanguage)
    }

    /// 存通道：**先存配置面（环境 / 中继 / 开关），再存凭据**。
    /// 两步都走 Core 校验：任何一步不合法，那一步什么都不落盘，原因落在 `imLine`。
    /// 自检：把「盘上有没有配置 / 有没有 AppID / 钥匙串有没有 Secret / 选没选环境」念出来。
    private func runIMSelfCheck() {
        let directory = AgentIMCredentialStore.defaultDirectory()
        let file = directory.appendingPathComponent(AgentIMChannelCredentialKind.qq.configFileName)
        let facts = AgentIMSelfCheckFacts(
            appID: imAppID,
            hasSecret: appState.hasAgentIMSecret,
            environment: imEnvironment,
            receiveTasks: imReceiveTasks,
            configFileExists: FileManager.default.fileExists(atPath: file.path)
        )
        let problems = AgentIMSelfCheck.problems(facts)
        if problems.isEmpty {
            imSelfCheckLine = L(.agentIMSelfCheckReady)
        } else {
            imSelfCheckLine = problems.map { problem in
                switch problem {
                case .configFileMissing: return L(.agentIMSelfCheckNoConfig)
                case .appIDMissing: return L(.agentIMSelfCheckNoAppID)
                case .appIDNotNumeric: return L(.agentIMSelfCheckBadAppID)
                case .secretMissing: return L(.agentIMSelfCheckNoSecret)
                case .environmentMissing: return L(.agentIMSelfCheckNoEnvironment)
                }
            }.joined(separator: LocalizationManager.shared.effectiveLanguage == .english ? "; " : "；")
        }
    }

    private func saveIMCredentials() {
        guard appState.saveAgentIMSettings(environment: imEnvironment,
                                           relayURL: imRelayURL,
                                           receiveTasks: imReceiveTasks) else {
            imLine = appState.errorMessage
            return
        }
        let secret: String? = imSecretInput.isEmpty ? nil : imSecretInput
        if appState.saveAgentIMCredentials(appID: imAppID, secret: secret) {
            imSecretInput = ""
            imLine = L(.agentIMSaved)
        } else {
            imLine = appState.errorMessage
        }
    }

    /// 连接：**先存再连**（否则连的是上一次落盘的那份配置 —— 面板上刚改的地址不生效）。
    private func connectIMChannel() {
        saveIMCredentials()
        guard appState.agentIMReadiness.isReady else {
            imLine = appState.agentIMProbeLine ?? imStatusLine
            return
        }
        appState.connectAgentIM()
        imLine = nil
    }

    private func disconnectIMChannel() {
        appState.disconnectAgentIM()
        imLine = nil
    }

    /// 测试连接：真发一帧（失败给可读原因，**不弹成功**）。
    private func testIMConnection() {
        isTestingIM = true
        Task {
            let line = await appState.testAgentIMConnection()
            await MainActor.run {
                imLine = line
                isTestingIM = false
            }
        }
    }

    private func clearIMCredentials() {
        appState.disconnectAgentIM()
        if appState.saveAgentIMCredentials(appID: imAppID, secret: nil, clearFirst: true) {
            // 清除是**整条通道**：凭据文件一起没了 ⇒ 面板上那三格也必须跟着空（否则显示的是盘上不存在的配置）。
            imAppID = ""
            imEnvironment = nil
            imRelayURL = ""
            imReceiveTasks = false
            imSecretInput = ""
            imLine = L(.agentIMCleared)
        } else {
            imLine = appState.errorMessage
        }
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
