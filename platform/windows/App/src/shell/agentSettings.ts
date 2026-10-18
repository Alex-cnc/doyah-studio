// 智能体设置的**界面侧纯逻辑**（FR-AI-01）
//
// 这里只放两件**没有副作用**的事：
//   ① **内置提供商预设** —— 端点与常用模型先填好，用户少填一格；填了还能改。
//      与 macOS 侧同一口径（`Core/AgentProviderPreset.swift`）：模型清单**可以是空的**
//      （火山方舟的接入点 ID、vLLM 已加载的模型只能由用户自己填），界面据此把下拉置灰，
//      **不假装有清单**。
//   ② **端点反推预设** —— 用户手改了端点，选中项跟着落回它真正匹配的那一条；
//      匹配不上就老实显示「自定义」，**不许显示一个会撒谎的厂商名**。
//
// 判定（能不能外发）**不在这里**：那份裁决由 Rust 侧 `agent::Gate` 算，经 IPC 回给界面。

/** 一条内置预设。 */
export interface AgentPreset {
  /** 标签 id（同时是 `preset` 落盘值）。 */
  id: string
  /** 语言表键（品牌名不译）。 */
  labelKey: string
  /** 端点（空串 = 交给用户填，例如自建网关）。 */
  endpoint: string
  /** 常用模型（空数组 = 该提供商没有可预置的清单）。 */
  models: readonly string[]
  /** 是否通常需要密钥（**只是提示**；本地端点免密钥由闸门判，不在这里判）。 */
  typicallyNeedsKey: boolean
}

/** 内置预设。顺序 = 界面下拉顺序（常用的在前）。 */
export const AGENT_PRESETS: readonly AgentPreset[] = [
  {
    id: 'deepseek',
    labelKey: 'agent.preset.deepseek',
    endpoint: 'https://api.deepseek.com/v1',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    typicallyNeedsKey: true,
  },
  {
    id: 'openai',
    labelKey: 'agent.preset.openai',
    endpoint: 'https://api.openai.com/v1',
    models: ['gpt-4o-mini', 'gpt-4o'],
    typicallyNeedsKey: true,
  },
  {
    id: 'qwen',
    labelKey: 'agent.preset.qwen',
    endpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: ['qwen-plus', 'qwen-max'],
    typicallyNeedsKey: true,
  },
  {
    id: 'zhipu',
    labelKey: 'agent.preset.zhipu',
    endpoint: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-4-plus', 'glm-4-flash'],
    typicallyNeedsKey: true,
  },
  {
    id: 'ollama',
    labelKey: 'agent.preset.ollama',
    endpoint: 'http://localhost:11434/v1',
    models: ['llama3', 'qwen2.5-coder'],
    typicallyNeedsKey: false,
  },
  {
    id: 'vllm',
    labelKey: 'agent.preset.vllm',
    endpoint: 'http://localhost:8000/v1',
    models: [],
    typicallyNeedsKey: false,
  },
  {
    id: 'custom',
    labelKey: 'agent.preset.custom',
    endpoint: '',
    models: [],
    typicallyNeedsKey: true,
  },
]

/** 端点归一化（去空白 / 小写 / 去尾部斜杠）—— 只用于**匹配预设**，不改用户填的值。 */
export function normalizeEndpoint(endpoint: string): string {
  return endpoint.trim().toLowerCase().replace(/\/+$/, '')
}

/**
 * 端点 ⇒ 预设 id。
 *
 * 匹配不上返回 `custom`；空端点也返回 `custom`（还没填，不能替用户认领一个厂商）。
 */
export function presetForEndpoint(endpoint: string): string {
  const target = normalizeEndpoint(endpoint)
  if (!target) return 'custom'
  const hit = AGENT_PRESETS.find((preset) => preset.endpoint && normalizeEndpoint(preset.endpoint) === target)
  return hit?.id ?? 'custom'
}

/** 取一条预设（认不出返回「自定义」那一条，调用方不用判空）。 */
export function presetById(id: string): AgentPreset {
  const hit = AGENT_PRESETS.find((preset) => preset.id === id)
  if (hit) return hit
  return AGENT_PRESETS[AGENT_PRESETS.length - 1]
}

/**
 * 模型下拉的候选：预设清单 + 当前值（**自填的名字不被吞掉**）。
 *
 * 为什么要带上当前值：用户从下拉里选过 `llama3` 之后又手改了模型名 —— 下拉里没有它，
 * 一渲染就会「跳回」预设的第一条，用户以为自己选错了。
 */
export function modelChoices(presetId: string, current: string): string[] {
  const preset = presetById(presetId)
  const choices = [...preset.models]
  const trimmed = current.trim()
  if (trimmed && !choices.includes(trimmed)) choices.push(trimmed)
  return choices
}

/** 是否「该提供商没有可预置的模型清单」（界面据此把下拉置灰、只留输入框）。 */
export function presetHasModelList(presetId: string): boolean {
  return presetById(presetId).models.length > 0
}
