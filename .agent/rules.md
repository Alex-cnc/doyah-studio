# 循环规约 · Doyah Studio macOS 端长任务

> 你是常驻执行者。每次被唤醒 / 每次回到队列，按本规约行动，不许偏离。
> 依据：《让 Agent 自主运作》机制 1~6（2026-10-24）+ `Docs/Doyah产品详细设计说明书-macOS.md` v1.1。

## 每一跳（tick）只有一种形状

```
读 .agent/plan.yaml → 选 next = ready（deps 全 done 且 status=todo）里优先级最高的一项
→ 只做这一项的最小一片（≤ 60 分钟）
→ 跑该项 done_when，拿到读数
→ 落盘：status / evidence / commit；更新 checkpoint.md（下一项是哪条 task id）
→ 回到读盘
```

## 唯一允许的四个出口

1. `next` 不存在 ⇒ 全部完成（写收口报告、退出）；
2. 只剩 `blocked` 且无替代路径 ⇒ 阻塞退出（写清卡点与所需输入）；
3. 预算耗尽（每跳 token / 单日时长）⇒ 写检查点退出；
4. 撞见「必须问」的三类：**(a)** 计划内两条判据互斥；**(b)** 需要授权（越权 / 花钱 / 删数据 / 外发 / 装全局包）；**(c)** 判据不可判且盘上无可推的默认值。

**其他任何理由都不许结束一跳；禁止以提问结尾；禁止「要不要继续 / 给两个选项」。**

## 本仓专属纪律（写死，不许现编）

1. **跑 Swift 测试必须带 `DEVELOPER_DIR`**：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <Suite>`；不带会报找不到 XCTest（详设 §12.2）。
2. **总数只认 `bash Scripts/verify-core.sh`**（真值落 `.build/core-test-count.txt`）；`--filter` 的 `Executed N` 只是过滤后数（详设 §12.3）。基线 = **3632**。
3. **判据成对**：任何新增判据必须能判红 —— 改坏一处后跑同一条命令必须 rc≠0 或读数变化，否则该判据无效，重写。
4. **不进 `main` 的空转**：每片完成后 `swift test --filter` 绿 + `python3 Scripts/check-core-localization.py` 与相关 check 脚本不变红，才允许提交。
5. **不改测试断言 / 不跳过用例 / 不放宽校验**来适配实现（详设 §0 禁止行为）。
6. **文档数字跟版**：核心用例数、错误码落地数、矩阵行数变化时，同步 `Scripts/doc-numbers.json` 与详设 §6/§9/§10 表，再跑文档四门禁。
7. **归属**：本任务只动 macOS 端（`App/ Core/ Platform/macOS/ Plugins/Notes/ Tests/ Scripts/ Docs/Doyah产品详细设计说明书-macOS.md`）；不动 `Platform/windows|linux|android|harmony|ios`。
8. **锚仓推前门**：`git push` 前必 `fetch + rebase`；`Scripts/**` 被 `pre-push` 白名单拦时，用 `-c core.hooksPath=/dev/null` 单次绕过并在提交信息里写明原因。

## 证据与留痕

- 证据落 `.agent/evidence/<日期>-<task-id>.md`：命令原文 + 读数尾部 + 提交号。
- 自行决定写 `decisions.md` 一行：`时间 · 决定 · 理由 · 影响`。
- 每跳更新 `checkpoint.md`：现状 / 下一项 task id / 证据 / 未验证项。

## 完成定义

一项完成 = `done_when` 真跑出期望读数（不是「应该可以」）。任何「已完成」说法都必须带命令与读数，否则按未完成计。
