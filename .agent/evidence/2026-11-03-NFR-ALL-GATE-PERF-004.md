# NFR-ALL-GATE-PERF-004 · 2026-11-03
条目：NFR-ALL-GATE-PERF-004（元数据单层懒加载在局域网内 ≤ 1 s）

判据：
$ PGHOST=192.168.5.26 PGUSER=zxvmax PGDATABASE=zxvmax PGSSLMODE=disable \
    ./Scripts/measure-metadata-latency.sh
运行次数：12 次有冷加载读数 · 阈值 1000 ms
层             样本       中位数       P95        最大  判定
depth=1(server)    12     12.0      18.5      31.3  ✅
depth=2(database)    12     14.1      24.0      28.1  ✅
depth=3(schema)    12     18.6      29.3      30.1  ✅
depth=4(table)    12     21.1      33.3      34.0  ✅
读数目录：.build/metadata-latency
rc=0

反例两段（改坏 ⇒ 判红 ⇒ 还原复绿）：
$ RUNS=2 THRESHOLD_MS=1 ./Scripts/measure-metadata-latency.sh
depth=1…depth=4 四层全部 `❌ 超阈`  ⇒ rc=1
$ （CLI 冷加载临时退回旧口径 `metadataCache[database] != nil`）RUNS=1 …/measure-metadata-latency.sh
✗ 覆盖不全：这些层零冷样本 —— depth=3(schema)
  记「未知」，不是通过（缺层的读数不能由别的层代判）  ⇒ rc=2
还原后 `sha256`：CLI/main.swift `9417202f…` · Scripts/measure-metadata-latency.sh `abda500b…`（改前改后逐字节一致）

顺带（派生队列缺陷，与本条同片）：
$ python3 Scripts/plan-batches.py --version 0.7.0 --emit-plan --write
修前 28 blocked（其中 PERF-004 / COMP-001 台账已双 ✅ 仍被「跨版携带」永久保留）
修后 26 blocked（已闭条目从队列消失）· --check rc=0

提交：fa49e0d0
未验证：
- 只这一台局域网实例（PG 18.6，同一台见 `NFR-ALL-GATE-COMP-001` 备注）；跨网段 / 高延迟链路未测。
- 只走 CLI 对象树这条路（`DoyahCLI --tree --columns --timings`）；界面里手工展开的计时未采 ⇒ 界面侧记「未覆盖」。
- 冷加载按节点判（本进程内该节点子层首次展开）；同一进程内二次展开为热，符合需求 ③，但「换进程后重连开销」不含在内。
