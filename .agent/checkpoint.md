# 检查点

- 队列：`.agent/batches.yaml`（**4 批 / 18 条待办**，2026-11-01 B3 收口后重出；`plan-batches.py --write` 已过）
- 已完成：**16 / 35**（`B1` 四条 + `B2` 四条 + **`B3` 四条：META-007 / META-008 / META-011 / META-015**）
- 阻塞：**1**（`FR-STD-DB-META-002` GBase 8a 树形结构 —— 本机无 GBase 8a 实例 ⇒ 端到端 0 次；层级映射由 `Tests/MetadataServiceTests` 5 例判，判据列留 🟡 不冒充 ✅。next_try = 拿到 GBase 8a 测试实例后补端到端）
- **下一批：`B4 导入导出`**（`FR-STD-DB-IO-003` pg_dump/restore · `IO-004` 恢复到指定库 · `IO-006` CSV/JSON 导入 · `IO-007` xlsx 向导）
  - `B3` 证据：`.agent/evidence/2026-11-01-B3.md`（`B2` 那份在 `2026-11-01-B2.md`；前四片 `-B1-*.md`）
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳读数：`run-manual-verification-probes.sh --filter "CrossDatabaseBrowseProbeTests|GroupedViewProbeTests|MetadataDeliveryProbeTests"` ⇒ **8 例 × 两遍 = 0 失败**（跨库 3 / 分组 3 / 元数据交付 2；本机档真集群 16.2，0 跳过，两个输出目录各两枚证据文件）；`test-object-ddl.sh` exit 0（视图 / 函数 DDL 真机取回并装配）· `test-object-search.sh` exit 0（跨 schema 搜索）· `verify-core.sh` **5059 例 / 13 skipped / 0 失败** · `verify-ui-interactions.sh` **76 条全绿 / 无跳过 / 源锚点全在** · 文档门禁七道 rc=0
- **本跳新增**：`TestsUISnapshot/MetadataDeliveryProbeTests` 2 例 —— 走生产入口 `performTreeAction(.viewDDL)` / `searchObjects` / `browseSearchHit`，读**页签里真实落的文本**（视图带限定名与定义体 / 函数两重载两段 / 表 CREATE TABLE 带列 / 搜索跨两 schema / 浏览 `"probe_b"."mkt_orders" LIMIT 200`）；已接进 `run-manual-verification-probes.sh` 的 FILTER、`DOYAH_PROBE_PGMETA` 注入与证据核对（两遍都核）
- **本跳反例三段**（各判红后逐字节还原）：装配丢 schema（报「限定名丢了」）· 函数只取第一个重载（报「应有两段…实际 1 段」）· 浏览丢 schema（`SELECT * FROM "mkt_orders"` 被拒）
- **同批修的存量红**：`Scripts/test-object-ddl.sh` 收尾行把版本号写死「真机 18.6」，而本机档实际跑 16.2（读数与结论不符）⇒ 改成按 `SHOW server_version` 打印，实测「真机 16.2」
- 覆盖边界（本片）：搜索面板输入框打字与 250ms 防抖手感归人工（面板只做防抖 / 呈现 / 转交，匹配排序在 Core）· 真树上「点选后高亮不丢」归人工（行集合两档都找得到那一行已判）· 跨库只判 PostgreSQL 一侧（MySQL 协议族无 schema 层，不冒充判过）· 表 DDL 不还原索引 / 约束 / 注释
- 未验证 / 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（本跳未改 App 视图，`dist/` 未重建）；`Scripts/verify-all.sh` 全量未跑
- 存量红（不是本跳引入）：`Scripts/check-doc-layout.py` 报三书自审 18 条（全在 `Docs/Doyah产品概要设计说明书.md` §14 交叉引用）
