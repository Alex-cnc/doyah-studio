## ★ 顶部条目（优先于常规取活，不得顺延、不得再问）

**★0 · IM 通道凭据口径纠正 —— ✅ 已落地（R42，2026-10-28），本条关闭，不得重复执行**

- **主人的话**（留档，口径本身有效）：「既然指明了是 QQ 通道，为什么还要用户填 wss 地址？按道理只要 QQ 扫码或者输入机器人 AppID 和 AppSecret 就可以啊。」
- **已做**：`Core/AgentIMQQProvisioning.swift`（环境两档 · 取 token · 取网关 · 取不到用该环境固定地址 · 到期前刷新 / 单飞 ·
  401·403·429·5xx·非 JSON·缺 token 分档可读 · 官方 op 码 Identify 2 / 心跳 1 带 seq / 恢复 6 / Hello 10 / dispatch 解帧）·
  配置面四样 → 三样（环境 / AppID / Secret，`gatewayURL` / `botIdentifier` 作废）· 旧 `gatewayURL` 读成自建中继（迁移）·
  面板删地址格 / 加环境选择器 / 自建中继降高级项 / 「去 QQ 开放平台」按钮（**不做运行时扫码**）/ 画出程序取到的地址与 token 尾 4 位 ·
  传输层 `AgentIMGatewayHandshake`（nil = 自建中继原样）· 判据 `Tests/AgentIMQQProvisioningTests` 18 例 + `AgentIMSettingsTests` 27 例。
- **仍差**（不是本条的重复项）：真 AppID + Secret 与一次端到端点验（记 blocked）。
- **官方外发**（`POST /v2/users/{openid}/messages`）**已做**（R43 第四十三批 `Core/AgentIMOutboundSend.swift`）——
  上一版这条写「尚未做」，本行更正（旧说法作废）。

**★1 · IM 通道的「真配置界面」+ 判据收口（`FR-AGT-LINK-CHAN-003`）—— ✅ 已落地，本条关闭，不得重复执行**

- **2026-10-28 第四十批已做**：配置面 `Core/AgentIMSettings.swift`（地址只认 ws/wss · 标识规则 · 配齐判定四样一处 ·
  状态行四档**以配置为先** · 入站策略三档 · 测试连接四档**只有收到一帧才算通**）+ 配置文件扩为四字段（老文件仍能读、
  只改 AppID 不冲掉配置面）+ 面板那一节补全（网关端点 / 机器人标识 / AppID / Secret 尾 4 / 状态行 / 接收任务开关 /
  保存·测试连接·连接·断开·清除）+ 真 WebSocket 通路接线（`AppState` 持传输层）；判据 `Tests/AgentIMSettingsTests` **26 例**，
  反例五段各判红一次。**「传输层未实现」那句已作废（语言表键删除）。**
- **仍差（不是本条的重复项，见 ★2）**：入站任务真跑 + 结果推回；真连 QQ 需主人给网关 URL 与 AppID/Secret。

**★2 · IM 通道「入站任务真跑 + 结果推回」（`FR-AGT-LINK-CHAN-003` 的后半）—— ✅ 已落地（R41），本条关闭，不得重复执行**

- **2026-10-28 第四十一批已做**：`Core/AgentIMInboundRun.swift`（策略 → 去重（平台消息号落盘）→ 建任务 →
  跑（闭包注入，接界面 `AgentChatModel`，**审批照旧**）→ 回话入队 → 推 → **推成才 ack**；抛错也回「没跑成」、
  停在审批上只回「等桌面批准」、长结论截断指路）+ `AppState` 接线（结果队列在 `start()` 前接上、同一时刻只跑一条、
  面板分开报「跑过几轮 / 推回几条」）+ `AgentChatModel.adoptSession`（两个 chat 不共用上下文）；判据
  `Tests/AgentIMInboundRunTests` **17 例**，反例六段各判红。
- **仍差（外部依赖，不是本条的重复项）**：真 QQ 网关 URL + AppID/Secret ⇒ 握手口径与官方 `op` 码对齐（记 blocked）；
  面板与手机的端到端人工点验一次。

**★ 区已清空**：下一条活按台账取（`FR-STD-*` 里实现 `⬜`／`🟡`，优先=高 → 中；同档取判据可机械跑的）。
**R53（2026-10-29）已把 `FR-STD-WS-WEB-003`（网页文件在编辑器内的预览）做成一条纵切**：
① `Core/HTMLPreview` 计划层 —— 渲染哪一份（盘上文件 / **有未保存改动就渲染缓冲**）+ 读权限根 = **这份文件所在的目录**
（同目录 css / 图片要一起读；**目录是磁盘根 `/` 时不给计划** = 不为页面授整机读权限）+ 页面里的资源与链接三档
（根内 `file:` 放行 / 根外拒并带路径 / **远程地址交浏览器页签**）+ 路径按**分量**比不认字符串前缀；
② 引擎 `localReadRoot`（只预览页设，浏览器页签不设 ⇒ 行为不变）+ `loadHTMLString(_:baseDirectory:)`（渲染未保存缓冲，无出网）；
③ 界面 `App/Views/HTMLPreviewView.swift`（与 Markdown 预览同一套交互：分屏只读 · **共用同一枚预览开关** · 刷新 · 「在浏览器页签中打开」）
+ 树上网页文件右键多一枚「以源码打开」（`WorkspaceTabsModel.openAsSource`，当文本打开那段抽成一处）。判据 `Tests/HTMLPreviewTests` 15 例
（反例四段各判红后逐字节还原；开发期被自己判据抓出两处真错：目录 URL 的形状、`../` 多退一级）。实现 **🟡**（差人工点一眼）/ 判据 **✅**。
下一条活 = 台账 `FR-STD-WS-EDIT-022`（缩进检测与状态栏切换；优先=低，但判据全是纯逻辑、跑得快）。
备选：`FR-STD-WS-EDIT-017`（代码折叠）· `FR-STD-WS-EDIT-014`（撤销语义粒度）。
⚠️ `FR-STD-WS-TOOL-003`（DAP 调试器）与 `FR-STD-WS-AI-001`（编辑区 AI 辅助）纵切过大，排后。
**有一条待主人拍板**（已登记，别当已决）：命名分组标题上要不要也给「＋」（现在只有「未分组」那段有）。
**另一条待人工点验**（本批新增，别重复问）：网页预览那一眼 —— 编辑器里切预览看到渲染页 / 同目录样式生效 / 切回源码改动还在 / 点 `../` 链接被拒并说明。

# 每轮卡 · Studio macOS 端自主开发（2026-10-28 起）

> 每轮先读这一页（≈1.5KB），按它取活；细则见 `.agent/rules.md`（本卡优先）。
> **队列唯一来源 = `Docs/Doyah产品开发计划任务清单-macOS端.md`**（`FR-STD-*` 里实现为 `⬜`／`🟡` 的行）。
> `.agent/plan.yaml` **已停用**（2026-10-28 起以台账为准，读它等于读旧账）。

## 第 0 步：轮次锁（防两轮叠在同一棵树上）

```
若 .agent/round.lock 存在且 mtime 在 90 分钟内 ⇒ 上一轮还在跑，本轮什么都不做，直接结束（不汇报）
否则：写 .agent/round.lock（内容=时间戳+本轮取的条号）→ 干活 → 收尾时删掉它
```

## 一跳的形状（一次只做一条）

```
读台账 → 取一条（优先=高 → 中 → 低；同档取「判据可机械跑」的）
→ 做这一条的最小纵切（Core 机制 + 接线 + 用例），≤ 一轮
→ verify-core 取新总数 → 同批改：doc-numbers / AGENT-SPEC / 台账行（实现·判据·备注）/ 变化记录版本行
→ 五门：numbers tables versions invariants version-scope（全绿才收）
→ xcodegen generate → Scripts/build-app.sh → 记包哈希
→ 落 .agent/evidence/<日期>-<条号>.md（命令原文 + 读数尾部）→ 改 checkpoint.md 的「下一项」
→ 汇报三行
```

## 写死的口径

1. **纵切优先**：先把一条从头到尾打通，不铺半成品。
2. **不虚翻**：Core 有代码但界面上点不到 ⇒ 实现 `🟡`（备注写「差哪个入口」），判据可 `✅`。
3. **测试总数只认 `bash Scripts/verify-core.sh`**（真值 `.build/core-test-count.txt`）；`--filter` 的 `Executed N` 只是过滤后数。
4. **跑 Swift 必须 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`**。
5. **单一活书**：只改顶层台账，不新建 v2、不建副本；`Docs/frozen/` 与 `Docs/archive/` 不动。
6. **判据成对**：新增判据必须能判红（改坏一处 ⇒ 红），至少 6 例起步。
7. **不碰**：别人未提交的改动（`git status` 里不是你这片动的文件）、`Platform/` 下别的端、凭据文件。
8. **只提交不推送**：本仓常有两个写者，推送由主人在前台决定；提交前 `git add` 只加本片文件。
9. **版本行必跟**：台账「> **版本**」进一位 + 变化记录写清本批做了什么、读数多少。
10. **不能自己判的**：观感／真机／外部账号 ⇒ 台账留 `🟡` 并在备注写「等人工点验」，**不假装完成**。

## 出口（只有三个，不许以提问结尾）

1. 台账里 `FR-STD-*` 的实现 `⬜` 清零 ⇒ 收口汇报，`cronjob_manage action=pause` 停自己；
2. 只剩 `🟡`（外部依赖 / 人工点验）⇒ 同上，并列出「卡在谁那里」；
3. 撞见需授权（花钱 / 删数据 / 外发 / 改系统配置）⇒ 只记 blocked + 转下一条。

## 节奏：接力（2026-10-28 主人拍板）

- **一轮结束就接下一轮**：收尾时先删 `.agent/round.lock`，若台账里还有可推进的活 ⇒ 立刻
  `cronjob_manage action=run job_id=e98fad41f72d` 点火下一轮，不要等定时器。
- 定时器每 **5 分钟**一跳只作**兜底**（上一轮崩了、或点火没成功时能把链子接回来）；锁还在 ⇒ 空转不汇报。
- 没有活可做 ⇒ `cronjob_manage action=pause` 停自己，不点火。
- 不要改 schedule，不要再按剩余条数自调阶梯。

## 汇报（三行，QQ 只发这个）

- 结论：本轮哪条 + 实现/判据状态 + 包哈希
- 一行证据：`verify-core` 读数 + 五门 rc
- 要我做的事：只列本轮新增的拍板／点击项，无则写「无」
