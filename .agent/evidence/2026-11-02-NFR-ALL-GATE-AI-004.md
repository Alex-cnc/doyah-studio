# NFR-ALL-GATE-AI-004 · 2026-11-02

条目：`NFR-ALL-GATE-AI-004`（成本与配额：token / 调用次数上限与超时；超限即终止并提示）

## 判据

```
$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AgentQuotaPersistenceTests
    Executed 9 tests, with 0 failures (0 unexpected) in 0.034 (0.035) seconds

$ env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh
    Executed 5228 tests, with 13 tests skipped and 0 failures (0 unexpected) in 28.645 (29.002) seconds
ℹ️ Core 单测 5228 项（已写入 .build/core-test-count.txt）

$ ./Scripts/verify-ui-interactions.sh
✓ 116 条都真跑过（十七批）、都以 passed 收尾、没有跳过     (EXIT=0)

$ 文档门禁十道 rc=0
check-doc-tables 74 文件 · check-doc-numbers 三向 5228 · check-plan-coverage 471 · check-status-consistency 471
check-version-scope 471 · check-doc-invariants 5/5 · check-agents-index 15 · check-doc-versions 17
check-doc-layout 0 · check-req-index 488

$ python3 Scripts/plan-batches.py --version 0.5.0 --check
✅ 批次队列一致（3 条待办，台账复算一致）
```

## 改了什么

- `Core/AgentQuotaLedgerStore.swift`（新）：`agent-quota-ledger.json` 两键账本 —— 读（文件不在 = 全新、读不出 = 按 0 计并标 `degraded`）、写（原子）、`reset()`（真删文件）。
- `Core/AgentConfiguration.swift`：`AgentQuotaLedger.merged(with:)` / `delta(since:)`（负数按 0，不许退配额）。
- `Core/AgentLoop.swift` + `Core/AgentSubagentExecution.swift` + `Core/AgentOrchestrator.swift`：`runSubagentDispatch` 多返一项「这一批子代理花掉的配额」；`AgentLoopSubtaskRunner.baseLedger` 让子循环从**主控当前账本**起算并按「末 − 始」交回；`AgentSubtaskResult.quotaUsage`（`nil` = 没记，不当 0）。
- `App/AppState.swift`：账本改为**落盘 + 读盘幂等**（`loadAgentQuotaLedgerIfNeeded` / `agentQuotaLedgerForNextCall` / 唯一记账出口 `recordAgentQuota` / `resetAgentQuotaUsage`）；四条真实外发路径全部改读共用账本 —— 对话循环、生成 SQL、数据任务规格、**编辑区 AI 辅助**（此前完全没有配额判定）、**测试连接**（同上）。
- `App/Views/AgentSettingsSheet.swift` + `Core/Localization.swift`：配额区新增「已用 N 次 · M token」读数、「重置用量」与降级提示（中英各四键）。
- 台账 `NFR-ALL-GATE-AI-004` 两列全 ✅；§4.2 v0.5.0 14 → **13**（11 / 2）。

## 反例（判红后逐字节还原）

| 故意违规 | 读数 | 还原 |
|---|---|---|
| 撤掉子代理并账 | **2 红**（主账只记父 2 次 / 20 token，子代理 2 次不存在） | `Core/AgentLoop.swift` `b7985001…` |
| `load()` 恒返回空账本 | **6 红**（重启后拦不住；被拦的那次真发出 1 条请求） | `Core/AgentQuotaLedgerStore.swift` `a6d45e8c…` |
| 编辑区闸门改成恒真（`isAllowed` 后接假条件） | 源锚点判红（**字在、闸没**） | `App/AppState.swift` `343e7bcb…` |
| 记账不落盘 | 源锚点判红（落盘出口 0 处） | `App/AppState.swift` `343e7bcb…` |

第一条负例当场抓出被判据的一句话：源锚点原本只查 `LLMError.quotaExceeded` 那几个字，把闸门写成恒真时它照样绿 ⇒ 改成钉 `guard quotaDecision.isAllowed else` 这一形状。

## 未验证（≠ 通过）

- 真抓包（tcpdump）未做：量的是账本读数与调用点，不是线上字节。
- 并发派活时各路从**同一个起点**起算 ⇒ 最坏可超出「并发路数 − 1」次调用，**不是精确限流**（要精确得让子循环共享一个计数器）。
- 端点不回 `usage` 时 token 不涨（存量口径：客户端不数 token，已在需求书 R-41 登记）。
- 超时：判定面在盘（`LLMRequest.timeoutSeconds` → `urlRequest.timeoutInterval`，配置层校验 > 0 且 ≤ 上限），但**没有一条新判据量「超时真的会中断」**；本片不报它通过。
- `verify-all.sh` 第 11 项（打包 `.app`）与第 18 项（生成物一致性）本片未执行。

提交：`<见本轮报告>`
