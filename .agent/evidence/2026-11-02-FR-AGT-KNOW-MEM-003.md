# v0.5.0 A2 第一片 · FR-AGT-KNOW-MEM-003 · 2026-11-02

条目：`FR-AGT-KNOW-MEM-003`（对话记忆：可检视 / 删除 / 解释）—— 两列全 ✅

## 判据

```
$ python3 Scripts/ledger-row.py FR-AGT-KNOW-MEM-003
FR-AGT-KNOW-MEM-003 ✅

$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AgentMemoryDeskTests
Executed 13 tests, with 0 failures (0 unexpected) in 0.022 seconds

$ env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh
Executed 5241 tests, with 13 tests skipped and 1 failure (0 unexpected) in 31.966
  ✗ SSHTunnelRuntimeTests.testBusyPortFailsFastWithoutStartingAnything —— 存量抖动
    （单族连跑 3 次：4 tests / 0 failures ×3；与 HEAD 无关，本跳未碰隧道）

$ ./Scripts/verify-ui-interactions.sh
✓ 116 条都真跑过（十七批）、都以 passed 收尾、没有跳过   （rc=0）

文档门禁十道 rc=0：tables 74 · numbers 三向 5241 · plan-coverage/status/version-scope 471 ·
doc-invariants 5/5 · doc-layout 0 · doc-versions 17 · req-index 488 · agents-index 15 · doc-q-series 10
`python3 Scripts/plan-batches.py --version 0.5.0 --check` ⇒ 2 条待办，台账复算一致
```

## 反例（判红后 `sha256` 逐字节还原）

- 撤掉对话入口那句 `rememberAgentMemoryFromPrompt(prompt, workspacePath: workspacePath)` ⇒ 源锚点判红（「对话入口必须接写入」）
- 删除不重建索引（返回 `.deleted(indexRebuilt: true)` 但不动盘）⇒ 1 红（索引仍 1 条 · 期望 0）
- 解析放大问句（删掉 `hasSuffix("？")` 那道闸）⇒ 2 红
- 陈旧索引恒报「不陈旧」⇒ 1 红
- 还原后：`AppState.swift` `36976c9b…` / `AgentMemoryDesk.swift` `54772a39…`

## 覆盖边界（未验证 ≠ 通过）

- 真鼠标点「删除 / 清空 / 重建索引」未点：机械证据在 Core + `AppState` 方法层 + 源锚点
- 真模型未连：本条不涉及外发（写入只落本机事实源）
- 模型自发的写入仍只转候选等人确认（`FR-AGT-KNOW-MEM-006` 既有口径，不在本条）
- `verify-all.sh` 第 11 / 18 项本跳未执行

## 存量红（HEAD `9a8e8956` 工作树逐条复跑，读数与本跳工作树相同）

`check-format-arguments` 225/22（预算 188）· `check-design-tokens` 17 处 · `check-button-icon-only` 判据 F 1 处 ·
`check-network-egress` 8 处 · `check-core-localization` 棘轮 B · `panel-root-frames` 台账 118 ↔ 实测 119
（本跳新增视图后实测 120，已同批把台账更到 120）

提交：见下方 git log（本片一次提交）
