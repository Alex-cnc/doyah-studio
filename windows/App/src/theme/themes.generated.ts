// ⚠️ 生成物 —— 不许手改（改了下次生成即被覆盖，且闸门会判红）。
//
// 主题集（§9.2「候选同名同值」）：id / 显示名键 / 是否「推导草案」/ 谁是默认主题
// 全部由 `tools/gen-tokens.mjs` 从 macOS 侧 Core/DesignTheme.swift 解析 —— 本侧不手抄，
// 免得对侧改了主题集（改名 / 增删 / 值到位后不再是推导草案）而这边照旧显示。
// 重新生成：node windows/App/tools/gen-tokens.mjs（比对：--check）

export const THEME_SCHEMES = [
  { id: 'tech-blue', swift: 'techBlue', nameKey: 'designThemeTechBlue', fallback: true, derivedDraft: false },
  { id: 'bean-green', swift: 'beanGreen', nameKey: 'designThemeBeanGreen', fallback: false, derivedDraft: true },
  { id: 'rose-gold', swift: 'roseGold', nameKey: 'designThemeRoseGold', fallback: false, derivedDraft: true },
  { id: 'stardust', swift: 'stardust', nameKey: 'designThemeStardust', fallback: false, derivedDraft: false },
] as const

export type ThemeSchemeId = (typeof THEME_SCHEMES)[number]['id']
