# 检查点

updated: 2026-10-28T20:15

## 现状

- 循环卡 = `.agent/loop-card.md`（**2026-10-28 20:08 主人改成接力制**：一轮收尾即 `cronjob_manage action=run job_id=e98fad41f72d` 点火下一轮；定时器 5 分钟一跳只做兜底；不再按剩余条数自调阶梯）。
- 队列唯一来源 = `Docs/Doyah产品开发计划任务清单-macOS端.md`（`FR-STD-*` 里实现为 `⬜`／`🟡`）；`.agent/plan.yaml` 已停用。
- 最近读数（2026-10-28 R1）：`verify-core` **4295 例 / 12 skipped / 0 failures**；五门 rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 前缀 `c37fdab902bccd20` · 97,156 KB。

## 下一项

按台账取「优先=高 → 中；同档取判据可机械跑的」：

1. `FR-STD-WS-EDIT-015` 剩的一半 —— 撤回按钮接上 `AgentWriteBatchStore` / `AgentWriteBatchRevert`（Core 13 例已在盘，差界面）；
2. `FR-STD-WS-AI-002` 剩的一半 —— 工作区「许愿」入口 + 差异视图（Core 19 例已在盘，差界面）；
3. `FR-STD-WS-FS-003`（Explorer 文件操作）→ `WS-FS-004/005/006` → `WS-WEB-004` / `DB-TASK-002`。
4. 存量红 3 处（非任何一片引入，见「未验证项」），做「清红」片时一并处理。

## 已完成的片

- **R1（2026-10-28 20:15）· 在途件收尾** —— 前一会话 10-27 06:58 ~ 10-28 18:59 落盘未提交的 42 改 + 26 新文件，复核（verify-core 4276/0 failures + 五门全绿）后补提交 `893cc774`，未改其一字。
- **R1（2026-10-28 20:13）· `FR-STD-WS-AI-002` Core 面** —— `Core/WishStaging.swift`（暂存面：只动内存 / 清单 + 差异 / 验证没跑通标「没跑通」且默认不许验收 / 验收才写盘一次）+ `Tests/WishStagingTests.swift` **19 例**；同批给 `AgentWriteBatchRevert` 补 `record(_ snapshot:)` 与「自己删的能还原」分支。读数：`verify-core` 4295 / 0 failures，反例两次各判红（4 红 / 1 红）。台账 `FR-STD-WS-AI-002` 判据 `✅`、实现 `🟡`（差界面入口）。
- `T0.1`~`T5.2`（2026-10-24/25，plan.yaml 时代，历史见 `.agent/evidence/`）。

## 证据

- `.agent/evidence/2026-10-28-WS-AI-002.md`（命令原文 + 读数 + 反例三段）
- 更早的片见 `.agent/evidence/2026-10-2*.md`。

## 未验证项

- `FR-STD-WS-AI-002` 的界面面（许愿输入框 + 差异视图 + 验收按钮）未做 ⇒ 实现 `🟡`，等下一片。
- 存量红 3 处（本轮未动）：`check-core-localization`（`Core/AgentSQLStatementJudge.swift:90` 的 `you are now` 未登记）· `check-literal-language`（`Core/AgentNotifyChannel.swift` 2 处写死语言）· `check-core-portability`（`Core/AgentCodeRunner.swift:57` 硬编码 `/usr/local/…`）。
- `verify-all.sh`（十八项）本轮未跑：上述三处存量红会挡它，需先清红再整跑。
