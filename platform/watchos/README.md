# platform/watchos/ —— watchOS 端（Apple 全系第三端）实现落点 [独占:watchos]

> **维护者**：**铁皮大河马**（`hugehippo` · macOS/iOS/watchOS 侧）。本文件 = 本落点的**一页声明**
> （归属 / 边界 / 现状）；**只此一页**，不在本格另开第二份说明。
> **状态（2026-10-13 实读）**：**落点已建、尚无工程** —— 无源码、无工程文件、无产品代码；
> 不建空文件充数（「看起来开工了」的占位会进受检集合，变成假进度）。

**由头**：人类主人 2026-10-13 令 —— 平台词表由六个扩为**七个**（新增 `watchos`），
**Apple 全系（`macos` / `ios` / `watchos`）归大河马**、非 Apple 全系归小河马；派单 `T-20261013-004`。

**归属与清单口径**（`Scripts/path-ownership.json`）：`id = watchos` · `owner = macos` ·
`hosts = [darwin]` · `actor = bighippo` · `contract_side = apple` —— 与 `Platform/macOS/`
**同一机组、不同格**（与 Notes 的 `ios` 树同形）。本格独占口径 = `platform/watchos/**`。

**边界**：契约层（三书契约正文 · `AGENT-SPEC.md` · 台账）归前门 `bluewhale`，本格**只读 + 提案**
（改契约走 `Docs/proposals/`）；本格只放 watchOS 实现层 —— 工程 / 源码 / 本端构建与自检入口。

**不做**：不在没有实现需求时建空工程 / 空文件；实现开工时按派单走（拆片 → 判据 → 出包）。
