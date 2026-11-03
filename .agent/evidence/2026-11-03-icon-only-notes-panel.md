# 按钮图标化收尾（a 类 7 → 0）· 2026-11-03

条目：无台账行（界面纪律债 = 人类主人令 2026-10-13 `T-20261013-042` 的未落地余项）
队列：`plan-batches.py --version 0.7.0 --check` ⇒ 0 todo / 21 blocked（无可认领批次）

## 做了什么

`Scripts/check-button-icon-only.py` 是 `verify-all.sh` 第 3 项的红出处之一，余 7 处全在
`Plugins/Notes/Views/NotesPanel.swift`。处置按 `--inventory` 盘点清单逐条来（清单早就给了每条
的处置，本跳没自选口径）：

| 站点 | 动作 | 处置 |
|---|---|---|
| `:88` 撤销 | `Button(L(.notesUndo))` → 回转箭头图标 | 图标化（清单第 31 号「改图标」） |
| `:436` 归档 | `Label { Text } icon:` → 纯 `Image` | 图标化（第 35 号） |
| `:3025` 恢复 | 文字 → `arrow.uturn.backward` | 图标化（第 54 号） |
| `:3033` 永久删除 | 文字 → `trash` | 图标化（第 55 号） |
| `:620` 回收站侧栏行 | 图标 + 行名不动 | 登记「内容承载」（第 36 号） |
| `:2986` 彻底清除·取消 | 文字不动 | 登记「弹框」（第 52 号） |
| `:2990` 彻底清除·永久删除 | 文字不动 | 登记「弹框」（本跳改判：清单拟「改图标 + `bolt`」而该图标与动作无关，属「待裁」；见 decisions） |

四枚图标按钮都带 `.help` + `.accessibilityLabel`（判据 F 要成对），`accessibilityIdentifier`
一个未改（探针按 id 抓，不按文案）。

## 判据

$ python3 Scripts/check-button-icon-only.py
    a 类 水平按钮（**必改**）：0 处（未登记）（改前读数 277 · 目标 0）
    例外台账（②）：站点 51 条 · 动作图标 1 条（Scripts/button-icon-exceptions.json）
    已是纯图标（合格）：93 处 · 存疑（登记待裁）：2 处 · 无可见文案豁免：2 处
    判据 F 提示 / 无障碍标签：合格 93/93 处 · 缺 0 处（目标 0）
✅ 水平按钮一律图标（a 类 0 处）
RESULT=PASS

$ python3 Scripts/check-button-icon-only.py --self-test
✅ ㊹ 真仓例外台账读得出 + 形状对
✅ ㉑ 真仓库盘点基线逐字节未变
全部 48 例达到预期（自检 exit 0）

反例两段（各判红后逐字节还原，`sha256` 见下）：
- 把 `:3025` 改回 `Button(L(.notesTrashRestore))` ⇒ a 类 **1 处**，`未登记差异：…:3025` +
  `判据 C … 例：…:3025 L(.notesTrashRestore)`，`RESULT=FAIL`；还原后 `RESULT=PASS`。
  还原 sha256 `d4c442435c31c70002649305a46f897c8aebe29b04f80c40afbf51a1b26a436d`。
- 删掉台账里 `:620` 那条「内容承载」⇒ a 类 **1 处** 且 `未登记差异：…:620`，`RESULT=FAIL`；
  还原后 `RESULT=PASS`（台账三条是承重的，不是装饰）。

$ ./Scripts/verify-core.sh
ℹ️ Core 单测 5366 项（已写入 .build/core-test-count.txt）· 0 failures

$ ./Scripts/verify-ui-interactions.sh
✓ 133 条都真跑过（十九批）、都以 passed 收尾、没有跳过
Executed 133 tests, with 0 failures (0 unexpected) in 42.668 (42.696) seconds   （RC=0）

$ swift build
Build complete! (26.84 sec)

文档 / 纪律门禁（逐条 rc）：doc-invariants 0 · doc-tables 0 · doc-numbers 0 ·
plan-coverage 0 · status-consistency 0 · version-scope 0 · status-gap 0 · doc-layout 0 ·
agents-index 0 · blocker-table 0 · design-tokens 0 · empty-action-buttons 0 ·
palette-wiring 0 · self-test-counts `--no-run` 族 57 / 例 1082 / 锚点 86 全对。

## 未验证（≠ 通过）

- **`verify-all.sh` 全量本跳未跑**（约 35 分钟，逐项读数见上；第 11 项打包 / 第 3 项另一处
  `check-format-arguments` 230 > 190 / 第 11 项 `check-menu-language` 真启动取证 均未执行）。
- 四枚新图标按钮**真鼠标未点**（机械证据 = 源码 + 133 条 UI 探针全绿；探针不按文案抓按钮，
  所以本跳没给它们新增点击型探针）。
- 「同一个动作同一图标」只到仓内对账（判据 G/H 61 处覆盖），跨端一致未判（另两端不在场）。
- 观感（图标大小 / 与邻行基线对齐）未看。
