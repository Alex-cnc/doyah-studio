# 证据 · 2026-10-28 第四十二批 `FR-AGT-LINK-CHAN-003` ★0 凭据口径纠正

> 由头（主人原话，2026-10-28）：「既然指明了是 QQ 通道，为什么还要用户填 wss 地址？按道理只要 QQ 扫码
> 或者输入机器人 AppID 和 AppSecret 就可以啊。」⇒ **地址不再由用户填**，程序自己取。

## 一、判据读数（命令原文 + 尾部）

```
$ export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
$ bash Scripts/verify-core.sh
 Executed 4462 tests, with 12 tests skipped and 0 failures (0 unexpected) in 23.598 (23.931) seconds
rc=0 ；.build/core-test-count.txt = `4462 tests`（4443 → +19）
```

```
$ python3 Scripts/check-doc-numbers.py      → rc=0  ✅ 文档数字对账通过（台账 ↔ 实测 ↔ 文档 三向一致）
$ python3 Scripts/check-doc-tables.py       → rc=0  ✅ 表格校验通过（71 个文件）
$ python3 Scripts/check-doc-versions.py     → rc=0  ✅ 版本纪律通过（17 份书/单）
$ python3 Scripts/check-doc-invariants.py   → rc=0  ✅ 5 条铁律全部成立
$ python3 Scripts/check-version-scope.py    → rc=0  ✅ 版本范围校验通过（台账 462 条）
```

```
$ python3 Scripts/check-network-egress.py
✅ 全仓网络出口与 Notes SRS v3.94 §6.4 的清单一致（本轮把 8 处不合规清到 0：
   补登 `Platform/macOS/URLSessionAgentIMSocket.swift`（第四十批落地时漏登）+ 新登 `URLSessionAgentIMQQClient.swift`
   + 修 `WebKitBrowserEngine.swift` 的陈旧登记 + 把 `AppState` 里的出网构造改走 `AgentIMQQClients.system()` 工厂）
```

## 二、包身份

```
$ bash Scripts/build-app.sh          → rc=0 ；0 error
$ shasum -a 256 dist/DoyahStudio-beta1.0.app/Contents/MacOS/DoyahStudio | cut -c1-8
cca86c1e
$ du -sk dist/DoyahStudio-beta1.0.app → 98,316 KB
$ nm -gU …/DoyahStudio | grep -c 'AgentIMQQProvisioner\|AgentIMQQTokenVault\|AgentIMQQHandshake\|AgentIMQQClients'
68
```

## 三、反例自证（判据真的会判红；注入后逐字节还原）

三处注入，每处都只跑**那一条**判据（`swift test --filter`），跑完即还原并复跑全量：

| 注入 | 判据 | 读数 |
|---|---|---|
| `problem(for:)` 把 401 吞成 nil | `AgentIMQQProvisioningTests/testStatus401IsCredentialProblemNotNetworkProblem` | **rc=1**，1 test / 3 failures |
| `AgentIMReadiness` 不再要求 Secret | `AgentIMSettingsTests/testReadinessListsMissingFieldsInOrder` | **rc=1**，1 test / 1 failure |
| 拆掉 `TokenVault` 的单飞 | `AgentIMQQProvisioningTests/testVaultSingleFlightSharesOneRequest` | **rc=1**，1 test / 1 failure |

还原后 `diff -q` 两份源码均「byte-identical」，随后全量 4462 / 0 failures 复绿。

## 四、本片新增 / 改动的面

- 新 `Core/AgentIMQQProvisioning.swift`：环境两档 + 端点表 · `AgentIMQQHTTPClient` 协议 · `AgentIMQQProvisioner`
  （token / 网关 / `relay` 旁路）· `AgentIMQQToken`（刷新窗口）· `AgentIMQQTokenVault`（内存 / 单飞 / 失败保留）·
  `AgentIMQQHandshake`（Identify 2 · 心跳 1 带 seq · 恢复 6 · Hello 10 · dispatch → 入站任务）· 失败人话。
- 新 `Platform/macOS/URLSessionAgentIMQQClient.swift`：REST 真实现 + `AgentIMQQClients.system()` 装配工厂。
- 改 `Core/AgentIMSettings.swift`：配置面四样 → **三样**（environment / appID / secret）；`gatewayURL` / `botIdentifier`
  两族字段、状态码与人话键作废；`relayURL` 校验（空合法）；`AgentIMConnectivityProbe.run` 加 `frame:`（官方路径发 Identify）。
- 改 `Core/AgentIMCredentials.swift`：盘上字段 `environment` / `relayURL`，旧 `gatewayURL` **读成**中继地址（迁移），
  再保存即迁形。
- 改 `Core/AgentIMTransport.swift`：`AgentIMGatewayHandshake` 注入（头 / Identify / 心跳 / seq / 解帧；nil = 自建中继原样）。
- 改 `App/AppState.swift`：`provisionAgentIM()` 唯一准备链、`makeAgentIMQQHandshake`、换环境/中继即断开重来（`settingsChanged`）、
  地址与 token 尾 4 位读数。
- 改 `App/Views/AgentSettingsSheet.swift`：删「网关端点」「机器人标识」两格 → 环境选择器（不默认正式）+ 自建中继高级项
  + 「去 QQ 开放平台」按钮 + 沙箱提示 + 程序取到的地址。
- 改 `Core/Localization.swift`：删 8 个旧键、加 21 个新键（中英齐）。
- 判据：新 `Tests/AgentIMQQProvisioningTests` **18 例**；`Tests/AgentIMSettingsTests` 26 → **27 例**（新增「只改 Secret 不冲掉配置面」
  「老文件 gatewayURL 迁移成中继」「配齐判定不再要地址」）。

## 五、未验证项 / 既有状态（如实记）

- **真连 QQ**：缺真 AppID + Secret，端到端一次人工点验未做 ⇒ 实现仍 🟡（不画假绿）。
- **官方外发未做**：回话仍是本侧外发帧（`{"op":"reply",…}`）；官方 C2C/群消息要走
  `POST /v2/users/{openid}/messages`（被动回复 `msg_id` + `msg_seq`）⇒ 下一批另立一条（需要真凭据实测）。
- 既有红（**与 HEAD 逐条相同，非本片引入**，用 `git worktree add /tmp/cleanstudio HEAD` 干净树复跑比对）：
  `check-core-localization`（`AgentSQLStatementJudge.swift:90` 的写死英文）· `check-format-arguments`
  （172 处类型不明实参 > 预算 170、3 条占位符对账）· `check-literal-language`（`AgentNotifyChannel.swift` 2 处）·
  `check-pending-agenda`（缺 `Docs/智能体助手-开发规范.md`）。
