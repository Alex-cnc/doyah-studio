# SEARCH-001 阻塞前提量测 · 2026-11-03

条目：`FR-NTS-NOTE-SEARCH-001`（状态列**未动**：🟡 / 🟡）
判据：本跳只更正「① 语义检索要嵌入模型」这条阻塞前提的**事实层**，两条可能的路各量一次：

```bash
# ① 端点有没有嵌入接口（真密钥从 .secrets 还原，只打长度/尾 4 位，未落文件未进命令行）
$ python3 .build/derived/searchembed/probe-embeddings-endpoint.py
endpoint=https://api.deepseek.com/v1 model=deepseek-v4-flash key_len=35 key_tail4=2158
POST /embeddings (真密钥) -> HTTP 404
POST /definitely-not-a-path (真密钥) -> HTTP 404     # 对照：不存在路径同码 ⇒ 404 是「没有这个接口」

# ② 本机离线模型（macOS 自带 NLEmbedding，零联网）
$ DEVELOPER_DIR=… swift .build/derived/searchembed/probe-nlembedding.swift
LANG zh-Hans dim=640 ...   LANG en dim=512 ...   LANG zh-Hant NO_SENTENCE_EMBEDDING

# ② 的可用性：8 条笔记语料 × 8 条同义改写查询（查询词不在语料里）
$ DEVELOPER_DIR=… swift .build/derived/searchembed/probe-nlembedding-retrieval.swift
SUMMARY top1 1/8 · 平均余量 -0.0151 · dim=640
```

结论：嵌入端点**无**（404，与不存在路径同码）；离线模型**有但不可用**（top-1 1/8，余量 −0.0151 = 排错多于排对）。
⇒ 旧话「本机无端点、无本地模型」两侧都不准：端点有、模型也有，缺的是「能用的嵌入」。
门禁：`plan-batches --check` rc=0（0 todo / 23 blocked）· 九道文档门禁全 rc=0 · `check-self-test-counts --no-run` 族 56 / 例 1077 / 锚点 86。

提交：`ccf81543`（已推送，`local == origin/master`；checkpoint 与提交号由下一笔补）
未验证：只这一台机器（`zh-Hant` 无句向量）· 语料 8 条、查询由本跳手写（不是标注集，1/8 只能证「不能用」，不能当精确质量分）· 未试第三方嵌入端点 / 未试本地大模型 · `SHOULD` 语义召回阈值未定（本条判据要的是「两种检索并列」，阈值属实现期）· 代码套件本跳未跑（未改 Swift 一行）。
