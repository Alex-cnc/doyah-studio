# 检查点

updated: 2026-10-28T20:41

## 现状

- 循环卡 = `.agent/loop-card.md`（**2026-10-28 20:08 主人改成接力制**：一轮收尾即 `cronjob_manage action=run job_id=e98fad41f72d` 点火下一轮；定时器 5 分钟一跳只做兜底；不再按剩余条数自调阶梯）。
- 队列唯一来源 = `Docs/Doyah产品开发计划任务清单-macOS端.md`（`FR-STD-*` 里实现为 `⬜`／`🟡`）；`.agent/plan.yaml` 已停用。
- 最近读数（2026-10-28 R34）：`verify-core` **4305 例 / 12 skipped / 0 failures**；五门 rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 前缀 `5c30c03b` · 97,204 KB。

## 下一项

按台账取「优先=高 → 中；同档取判据可机械跑的」：

1. `FR-STD-WS-FS-003` → `WS-FS-004/005/006`（Explorer 文件操作：Core `WorkspaceFileOperations` 与 `WorkspaceStore` 已在盘、
   界面悬浮菜单已在盘 ⇒ **先核验再翻状态**，缺口只剩「新建后自动打开且光标首行」「改名页签跟随 / 可撤回」这几条）；
2. `FR-STD-WS-EDIT-015` / `FR-STD-WS-AI-002` 剩的一半 —— 界面入口（Core 13 / 19 例已在盘）；
3. `FR-STD-DB-TASK-002`（高危任务执行前逐条列出 + 审批；`DataTask*` 已在盘，先核验）；
4. `FR-STD-WS-WEB-004` 剩的真站点点验（人工）；
5. 存量红 3 处（非任何一片引入，见「未验证项」），做「清红」片时一并处理。

## 已完成的片

- **R34（2026-10-28 20:41）· `FR-STD-WS-WEB-004` Core 面 + 引擎接线** —— 新 `Core/BrowserIdentity.swift`
  （确定性 UA 不带产品名 / 站点存储缺省持久化 / 弹窗必有可见结果 / 证书三类失败必问人 / 用常规浏览器打开的出口）
  + `Platform/macOS/WebKitBrowserEngine.swift` 接线（`customUserAgent`、`applicationNameForUserAgent = nil`、
  `WKUIDelegate` 弹窗、server-trust 挑战）+ `Tests/BrowserIdentityTests` 10 例 + 平台 3 例；
  读数 `verify-core` 4305 / 0 failures，五门全绿，包 `5c30c03b`。台账 实现 🟡 / 判据 ✅（差真站点点验）。
  **口径变更**：站点存储缺省 非持久化 → 持久化（由头见引擎注释 ③ 与证据文件）。
- **R1（2026-10-28 20:15）· 在途件收尾** —— 前一会话 10-27 06:58 ~ 10-28 18:59 落盘未提交的 42 改 + 26 新文件，复核（verify-core 4276/0 failures + 五门全绿）后补提交 `893cc774`，未改其一字。
- **R1（2026-10-28 20:13）· `FR-STD-WS-AI-002` Core 面** —— `Core/WishStaging.swift`（暂存面：只动内存 / 清单 + 差异 / 验证没跑通标「没跑通」且默认不许验收 / 验收才写盘一次）+ `Tests/WishStagingTests.swift` **19 例**；同批给 `AgentWriteBatchRevert` 补 `record(_ snapshot:)` 与「自己删的能还原」分支。读数：`verify-core` 4295 / 0 failures，反例两次各判红（4 红 / 1 红）。台账 `FR-STD-WS-AI-002` 判据 `✅`、实现 `🟡`（差界面入口）。
- `T0.1`~`T5.2`（2026-10-24/25，plan.yaml 时代，历史见 `.agent/evidence/`）。

## 证据

- `.agent/evidence/2026-10-28-WS-WEB-004.md`（命令原文 + 读数 + 反例三段 + 口径变更由头）
- `.agent/evidence/2026-10-28-WS-AI-002.md`（命令原文 + 读数 + 反例三段）
- 更早的片见 `.agent/evidence/2026-10-2*.md`。

## 未验证项

- `FR-STD-WS-AI-002` 的界面面（许愿输入框 + 差异视图 + 验收按钮）未做 ⇒ 实现 `🟡`，等下一片。
- 存量红 3 处（本轮未动）：`check-core-localization`（`Core/AgentSQLStatementJudge.swift:90` 的 `you are now` 未登记）· `check-literal-language`（`Core/AgentNotifyChannel.swift` 2 处写死语言）· `check-core-portability`（`Core/AgentCodeRunner.swift:57` 硬编码 `/usr/local/…`）。
- `verify-all.sh`（十八项）本轮未跑：上述三处存量红会挡它，需先清红再整跑。
