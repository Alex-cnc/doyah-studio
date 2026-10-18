// 智能体设置的两块**纯逻辑**：内置预设 + 端点反推（FR-AI-01）。
//
// 这些不是「随便挑几个厂商名」：反推错一格，界面就会显示一个**会撒谎的厂商名** ——
// 用户以为自己在连 A，实际连的是 B。所以逐条钉住：空端点不认领厂商、
// 尾斜杠 / 大小写 / 空白都归一、自填的模型名不被下拉吞掉。
import { describe, expect, it } from 'vitest'
import {
  AGENT_PRESETS,
  modelChoices,
  normalizeEndpoint,
  presetById,
  presetForEndpoint,
  presetHasModelList,
} from './agentSettings'

describe('内置预设', () => {
  it('每条预设都有中文与英文标签键，且 id 不重复', () => {
    const ids = AGENT_PRESETS.map((preset) => preset.id)
    expect(new Set(ids).size).toBe(ids.length)
    for (const preset of AGENT_PRESETS) {
      expect(preset.labelKey.startsWith('agent.preset.')).toBe(true)
    }
  })

  it('本地端点的预设标注「通常不需要密钥」，远端标注「通常需要」', () => {
    expect(presetById('ollama').typicallyNeedsKey).toBe(false)
    expect(presetById('vllm').typicallyNeedsKey).toBe(false)
    expect(presetById('deepseek').typicallyNeedsKey).toBe(true)
  })

  it('认不出 id 时落回「自定义」，不编一个厂商', () => {
    expect(presetById('no-such-provider').id).toBe('custom')
  })
})

describe('端点反推预设', () => {
  it('尾斜杠 / 大写 / 前后空白都归一后仍能认出同一家', () => {
    expect(normalizeEndpoint('  HTTPS://API.DeepSeek.com/v1/  ')).toBe('https://api.deepseek.com/v1')
    expect(presetForEndpoint('https://api.deepseek.com/v1/')).toBe('deepseek')
    expect(presetForEndpoint('  https://API.deepseek.com/v1  ')).toBe('deepseek')
  })

  it('空端点不认领任何厂商（还没填，不能替用户选）', () => {
    expect(presetForEndpoint('')).toBe('custom')
    expect(presetForEndpoint('   ')).toBe('custom')
  })

  it('自建网关 / 私有部署落回「自定义」而不是显示一个假厂商名', () => {
    expect(presetForEndpoint('https://llm.internal.corp/v1')).toBe('custom')
    expect(presetForEndpoint('http://localhost:11434/v1')).toBe('ollama')
  })
})

describe('模型下拉候选', () => {
  it('预设清单在前，用户自填的名字跟在后面（不被吞掉）', () => {
    expect(modelChoices('ollama', 'my-finetune')).toEqual(['llama3', 'qwen2.5-coder', 'my-finetune'])
  })

  it('当前值已在清单里时不重复', () => {
    expect(modelChoices('ollama', 'llama3')).toEqual(['llama3', 'qwen2.5-coder'])
  })

  it('没有预置清单的提供商（vLLM）只回用户填的那个', () => {
    expect(presetHasModelList('vllm')).toBe(false)
    expect(modelChoices('vllm', 'Qwen2.5-7B')).toEqual(['Qwen2.5-7B'])
    expect(modelChoices('vllm', '')).toEqual([])
  })
})
