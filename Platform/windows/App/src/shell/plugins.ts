// 插件清单状态（界面侧的**唯一消费口**）
//
// 契约②：「插件清单 = 一处声明；界面与构建**只消费它**」。
// 所以界面**不自己写**"活动栏有哪几项、能不能看见"，一律从这里读。
//
// 数据来源 = 领域层 `Db/src/plugins.rs` → 命令 `plugins_manifest` → `ipc.ts`。
// 浏览器旁路给**空清单**（不是编一份假清单）：界面据此如实显示"没有插件"。

import { ref, computed } from 'vue'
import { pluginsManifest, type PluginEntry, type PluginFinding } from '../ipc'

/** 清单（原始）。 */
const plugins = ref<readonly PluginEntry[]>([])
/** 领域层自检发现的问题（空 = 自洽）。 */
const findings = ref<readonly PluginFinding[]>([])
/** 是否已装载过（避免重复请求）。 */
const loaded = ref(false)

/** 装载清单（启动时调一次；失败**不抛** —— 契约④不许因插件面报错）。 */
export async function loadPlugins(): Promise<void> {
  if (loaded.value) return
  try {
    const manifest = await pluginsManifest()
    plugins.value = manifest.plugins ?? []
    findings.value = manifest.findings ?? []
  } catch {
    // 取不到清单 ⇒ 按"没有插件"处理（挂点整体消失），并把这一笔如实记进 findings，
    // **不抛异常**：界面不能因为插件面而白屏。
    plugins.value = []
    findings.value = [
      { plugin: '<清单>', code: 'manifest-unavailable', detail: '插件清单取不到（命令不可用）' },
    ]
  } finally {
    loaded.value = true
  }
}

/** 全部插件（顺序 = 清单顺序 = 活动栏展示顺序）。 */
export const pluginList = computed<readonly PluginEntry[]>(() => plugins.value)

/** 某个挂点上有哪些插件。 */
export function pluginsOnMount(mount: string): readonly PluginEntry[] {
  return plugins.value.filter((p) => p.mounts.includes(mount))
}

/** 按 id 取插件。 */
export function pluginById(id: string): PluginEntry | undefined {
  return plugins.value.find((p) => p.id === id)
}

/** 清单自检结果（空 = 自洽）。 */
export const pluginFindings = computed<readonly PluginFinding[]>(() => findings.value)

/**
 * 清单是否自洽。
 *
 * **一个口径，两个用途**：界面用它决定"这份清单能不能信"，判据用它决定"红不红"。
 * 所以自洽性**只看 findings** —— 别再自己算一遍"清单看起来对不对"（那就会有两份实现）。
 */
export const pluginsConsistent = computed(() => findings.value.length === 0)

/** 仅供判据/测试：把清单与自检结果**一起**换掉（两者同源，必须成对设置）。 */
export function setManifestForTest(
  entries: readonly PluginEntry[],
  issues: readonly PluginFinding[] = [],
): void {
  plugins.value = entries
  findings.value = issues
  loaded.value = true
}
