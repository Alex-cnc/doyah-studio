# 判据维护跳（队列空 · 脚本级 · 第七片）· 2026-11-02

条目：无台账行（队列 0 条 todo ⇒ 清自检红族）

## 判据

```
$ python3 Scripts/check-empty-action-buttons.py
· 守卫 45 条 / 台账 45 条
✅ 空数据按钮处置逐条对账通过（守卫 45 条 / 台账 45 条 / 视图 118 个文件）
$ python3 Scripts/check-empty-action-buttons.py --self-test
负例：11/11 通过；真仓库未变：是
$ python3 Scripts/check-literal-language.py
✅ 语言透传门禁通过：扫描 546 个 Swift 文件；写死语言调用点 12 处（登记 15 个文件）；死译文（已登记欠账）1 个键
$ python3 Scripts/test-literal-language-gate.py
✅ 语言透传门禁负例自测 22/22 通过（真仓库逐字节未变）
$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
Executed 5078 tests, with 13 tests skipped and 0 failures (0 unexpected) in 28.338 (28.713) seconds
$ python3 Scripts/check-self-test-counts.py
族 54 个 / 例数合计 1054 / 锚点命中 86 处 / 无锚点但写了理由的族 12 个
❌ 判红 13 处（上一跳 16 处）
```

## 改了什么（两族，全是「台账/判据与盘上事实脱钩」）

1. **`empty-action-buttons` 真仓库红清零**（守卫 44 / 台账 38 → 45 / 45）：7 条未登记的空守卫逐条读体登记
   —— `exportDatabase` / `streamTable` = `explain`（体里有给用户的话）；`revertAgentBatch` /
   `redoAgentBatchRevert` = `internal`（按钮只在 `pending > 0` / `redoPending > 0` 时渲染，空时够不着）；
   `resolveAgentApproval` / `saveAgentWebSearchKey` / `syncWishDelivery` = `internal`（内部路由 / 「空 = 清除」指令 / 私有同步）。
   2 条陈旧：`ghostAction` 源码里根本没有 ⇒ 销账；`gatherDiagnosisEvidence` 是**真漏**见下条。
2. **`AppState.gatherDiagnosisEvidence` 的判据从扫描面里掉出去了**：2026-10-26 起写成
   `if trimmed.isEmpty, objectDiagnosisScope == nil { … return }`，而判据 A 只扫 `guard` 形态 ⇒ 这一处对账看不见。
   改成等价的 guard（德摩根：`guard !trimmed.isEmpty || objectDiagnosisScope != nil`），并在门禁 docstring 写明
   **覆盖范围 = 只扫 `guard`**（新写空早退请用 guard，否则记「未知」）。
3. **`MESSAGE_ASSIGN_RE` 补 `title: L(` / `text: L(`**：`exportDatabase` 那句话是塞进
   `TableExportSummary(text:)` 的，原正则只认 `= L(` 与 `*Message =` ⇒ 真话却被判「没有话」。
4. **`literal-language` 判据 C（界面侧）从文件级子串改成钉调用点实参**：原查「`DiagnosisPanel.swift` 里还有没有
   `effectiveLanguage` 这个词」，而该文件有 3 处 ⇒ 把提示词那一处换成 `shared.language` 仍判绿（自测例 6 实测 rc=0 = 假绿）。
   现在钉 `boundedPromptText(` 的实参必须含 `language: LocalizationManager.shared.effectiveLanguage`；自测例 6 同步改夹具。

## 负例（红绿成对）

- 撤掉 `exportDatabase` 台账条目 ⇒ `未登记的空守卫：App/AppState.swift:2751` 判红；补回 ⇒ 45/45 绿
- 自测 11/11：`_new_silent_guard`（新加静默空守卫）· `_fake_explain`（挂「给理由」的名、体里只有 return）·
  `_stale_entry` · `_broken_ledger` 逐条判红；修前 9/11（基线假红 + `SaveQuerySheet` 锚点已由 `.disabled(…)` 改 `isEnabled: !…`）
- 例 6：修前「该红实测 rc=0」⇒ 修后 rc=1 且点名 `DiagnosisPanel.swift`；干净副本照绿（22/22）

## 未验证

- 全量 `./Scripts/verify-all.sh` 未跑（本片只跑 `swift test` + 文档门禁五道 + 两族自检）；真机点验 0 次；217 真库 0 次
- 13 族红仍在（`cli-failure-readability` · `core-localization` · `design-tokens` · `editor-line-numbers` · `language-registry` ·
  `network-egress` · `palette-wiring` · `panel-root-frames` · `release-version` · `result-scroll-ledger` · `script-portability` ·
  `terminal-tabs` · `tri-repo-parity`）

提交：`da2d4bfb`（证据补记 = 下一个提交）
