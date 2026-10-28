# 第四十三批 · `FR-AGT-LINK-CHAN-003` 官方 REST 外发（收尾片）

日期：2026-10-28 · 轮次：R43 · 状态：判据 ✅ / 实现 🟡（差真凭据与端到端点验）

## 1. 为什么这一片非做不可

R41 把「聊天里派活 ⇒ 桌面跑 ⇒ 结论推回」整条链接通了，但**回话那一端**发的是本侧约定的一帧
`{"op":"reply","chatID":…,"text":…}`，往官方 WebSocket 上写。官方网关只认 REST 发消息
（`POST /v2/users/{openid}/messages` / `POST /v2/groups/{group_openid}/messages`），
所以「手机收到结论」这一段**其实从来没通过**。本批把外发从帧改成官方两条端点。

## 2. 落法（一处实现）

- `Core/AgentIMOutboundSend.swift`（新）：
  - `AgentIMOutboundTarget`：`kind`（c2c / group）+ `openID`；`validated()` 用**窄放行集**
    （字母数字 + `-_.`，拒 `/` `?` 空白 `..`）—— `openid` 是外部输入且要拼进 URL 路径。
  - `AgentIMQQMessageEndpoint`：路径只在这一处拼（`/v2/users|groups/{openid}/messages`），
    URL 挂在 `environment.apiBase`（正式 / 沙箱）；target 认不出返回 `nil`，不「尽量拼一个」。
  - `AgentIMQQMessageBody`：`content` + `msg_type:0`（**数字**，不是 `"0"`）+ 被动回复的
    `msg_id` / `msg_seq`（没有 `msg_id` 就不许带 `msg_seq`）；键序固定（`sortedKeys`）。
  - `AgentIMReplySeqLedger`：`msg_seq` 唯一分配处，落盘 `im-reply-seq.json`；**同一条结果重发
    复用同一个序号**（换号 = 手机两条，复用 = 被 QQ 当重复丢）。
  - `AgentIMSendOutcome` + `AgentIMOutboundSender`：401 / 403 / 429 / 5xx / 2xx-非 JSON
    （**仍算发出去**）/ 其余原样带码；取 token 那一步的失败按同一套分档。
  - `AgentIMOutboundDrain`：只补官方条目、发成才 ack、一条失败不挡后面的。
  - `AgentIMSendText`：九档人话（中英齐）。

- `Core/AgentIMChannel.swift`：`AgentIMChatKind`（c2c / group）；`AgentIMInboundMessage` 带
  `chatKind`；`AgentIMResultQueue.Entry` 加 `target` / `replyToMessageID`（老条目该两字段为 nil，
  解码兼容）；新增 `relayPending()`（只挑走 WebSocket 帧那条路的未投递条目）。
- `Core/AgentIMInboundRun.swift`：入口那条链入队的是**正文**（不再是帧），并把 target / replyTo 一并落盘。
- `Core/AgentIMQQProvisioning.swift`：官方 dispatch 按事件与 `group_openid` 定死 `chatKind`。
- `Core/AgentIMTransport.swift`：`replayPending` 改走 `relayPending()`（官方条目不许糊上网关）。
- `Platform/macOS/URLSessionAgentIMQQClient.swift`：加 `post(url, payload:String, headers:)`
  （`msg_type` / `msg_seq` 是数字，走 `[String:String]` 会被写成字符串被服务端拒）+ 工厂 `outbound()`。
- `App/AppState.swift`：交付口**一处岔**（官方 REST / 自建中继帧）、`makeAgentIMOutboundSender`、
  连上即 `flushAgentIMOutboundQueue()`（传输层只补中继）、`agentIMOutboundLine` 读数。
- `App/Views/AgentSettingsSheet.swift`：面板多一行「最近一次外发」（发不出去要看得见是哪一档）。
- `Core/Localization.swift`：新增 9 个键（`agentIMSendDelivered/NotReady/Unauthorized/Forbidden/
  RateLimited/ServerFailed/NotJSON/Rejected/NetworkFailed`），中英各一句。

## 3. 判据（命令原文 + 读数）

```
$ export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
$ bash Scripts/verify-core.sh   # rc=0
ℹ️ Core 单测 4482 项          # 台账 .build/core-test-count.txt = `4482 tests`（4462 → +20）
$ python3 Scripts/check-doc-numbers.py   # rc=0
$ python3 Scripts/check-doc-tables.py    # rc=0（71 个文件）
$ python3 Scripts/check-doc-versions.py  # rc=0
$ python3 Scripts/check-doc-invariants.py# rc=0（5 条铁律）
$ python3 Scripts/check-version-scope.py # rc=0（台账 462 条）
```

新增/改动用例：`Tests/AgentIMOutboundSendTests` **18 例**（端点两档 · 沙箱域 · 数字型正文 ·
序号递增与重发复用 · 主动消息不带 msg_seq · 五档状态映射 · 2xx 非 JSON 仍算发出 · 凭据失败不发请求 ·
网络失败独立 · openid 五种坏写法一律当场拒 · 空正文 · 无 target · 补发只挑官方且发成才 ack ·
失败不 ack · relayPending 排除官方 · 九档都有中英 · dispatch 定死 chatKind）；
`Tests/AgentIMInboundRunTests` 17 → **18 例**（新增群聊 target/replyTo；原「重连补发」那条改成
「只补中继帧、官方留队列」）。

## 4. 反例四段（每条新判据都真的能判红）

| 注入 | 改坏什么 | 期望 | 实测 |
|---|---|---|---|
| `seq-reuse` | 重发时序号 +1（不再复用） | `testRetryOfSameEntryReusesItsSequenceEvenAfterRestart` 红 | rc=1 ✅ |
| `endpoint-swap` | 私聊走 `groups`、群走 `users` | 端点两条判据红 | rc=1 ✅ |
| `relay-filter` | `relayPending()` 不再过滤 target | 「官方条目不许糊上网关」红 | rc=1 ✅ |
| `openid-guard` | 跳过 `validated()` 的放行集 | 五种坏 openid 全放过 ⇒ 红 | rc=1 ✅ |

四段各自注入 → 判红 → 从备份还原 → `sha256` 逐字节相同 → 复跑 `AgentIMOutboundSendTests` rc=0（GREEN）。
脚本落在临时目录（`~/.hermes/cache/scratch/inject_outbound.py`），**不进仓库**；日志在同目录 `injections/`。

## 5. 门禁红的归因（干净树对照，不是本片的账）

`git worktree add /tmp/wt-r43 HEAD` 拉干净树复跑同三条判据，**红的原因与条数逐条相同**：

- `check-core-localization`：棘轮 B 24 项（白名单 158 / 盘上候选 182）—— 存量。
- `check-core-portability`：1 处（`Core/AgentCodeRunner.swift:57` 硬编码 `/usr/local/…`）—— 存量。
- `check-format-arguments`：`App/WorkspaceStore.swift:319` 未登记形状 + `<name>` 12 > 上限 11 + 172 > 预算 170 —— 存量。

本片新增的 Core 文件里**零汉字字符串字面量**（注释不算），9 个新语言键走 `LocalizedStrings`。

## 6. 产物身份

```
交付: 目录=/Users/alex/dev/doyah/lead/studio/dist/DoyahStudio-beta1.0.app 标签=beta1.0
      sha256=b953fcb12f5a48fdefa5cd00e1f0519c7a7b8e3db3dc9e6cf6f6c285f320f125
      构建时刻=2026-10-28T23:15:19+0800
```

`nm` 实测：`AgentIMOutboundSender` 26 处 · `AgentIMReplySeqLedger` 79 处 · `AgentIMOutboundDrain` 33 处
在包里；98,604 KB。发布说明同批改口径：旧的「外发帧 `op` 名仍是本侧约定、未与官方 op 码对齐」
**已作废**（官方路径走 REST），「未含」改成「真连一次 QQ（缺 AppID + Secret 与端到端点验）」。

## 7. 仍未验证（如实登记）

- **真发一条**：要 AppID + Secret + 一个真人手机（`手机发一句话 ⇒ 桌面出该轮 ⇒ 手机收到结论`）。
- **被动回复的有效期**：QQ 对 `msg_id` 有时间窗与次数上限；官方文档给的具体数字未在真环境复核过 ⇒
  本片**不擅自定义**窗口策略（宁可让服务端拒、由结局分档如实报出来）。真连上后按实测再落一条。
- **群聊主动消息**：没有 `msg_id` 时按主动消息发（无 `msg_seq`），是否受配额限制未实测。
