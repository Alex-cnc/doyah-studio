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
