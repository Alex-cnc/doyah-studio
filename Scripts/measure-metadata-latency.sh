#!/bin/bash
set -euo pipefail

# 元数据单层懒加载耗时测量（NFR-ALL-GATE-PERF-004）。
#
# 口径（判据行原文）：单层懒加载在局域网内 ≤ 1 s ——
#   · **只算冷加载**：`--timings` 打的 `cold=1` 才算；命中缓存的时间不能拿去证明懒加载够快；
#   · 一次运行里同一层可能有多条冷加载（每个库首次展开各一条）⇒ 每次运行按层取**最大**值；
#   · 跨 ≥10 次运行取**中位数与 P95**，两层（database / schema，即 depth=2/3）各自对阈值。
#
# 用法：
#   PGHOST=192.168.5.26 PGUSER=zxvmax PGPASSWORD=… PGDATABASE=zxvmax PGSSLMODE=disable \
#     ./Scripts/measure-metadata-latency.sh          # 默认 12 次
#   RUNS=20 ... ./Scripts/measure-metadata-latency.sh
#
# 退出码：0 = 各层中位数与 P95 都 ≤ 1000 ms；1 = 超阈；2 = 一条冷加载读数都没采到（不许当通过）。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
CLI="${ROOT}/.build/debug/DoyahCLI"
OUTDIR="${ROOT}/.build/metadata-latency"
RUNS="${RUNS:-12}"
THRESHOLD_MS="${THRESHOLD_MS:-1000}"
TIMEOUT_S="${TIMEOUT_S:-120}"

export DEVELOPER_DIR
mkdir -p "$OUTDIR"
rm -f "$OUTDIR"/run-*.log

echo "==> 编译 CLI（增量）"
"${SWIFT}" build --product DoyahCLI --disable-sandbox >/dev/null

echo "==> 跑 ${RUNS} 次（每次一条 --tree --timings）"
for i in $(seq 1 "$RUNS"); do
    if ! PGHOST="${PGHOST:?}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:?}" \
         PGPASSWORD="${PGPASSWORD:?}" PGDATABASE="${PGDATABASE:?}" PGSSLMODE="${PGSSLMODE:-prefer}" \
         perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_S" "$CLI" --tree --columns --timings \
         > "$OUTDIR/run-$i.log" 2>&1; then
        echo "  第 $i 次失败（见 $OUTDIR/run-$i.log）" >&2
        tail -3 "$OUTDIR/run-$i.log" >&2 || true
    else
        echo "  第 $i 次完成"
    fi
done

echo "==> 汇总（只算 cold=1）"
python3 - "$OUTDIR" "$THRESHOLD_MS" <<'PY'
import glob, os, re, statistics, sys

outdir, threshold = sys.argv[1], float(sys.argv[2])
pat = re.compile(r"\[timing\] depth=(\d+) kind=(\S+) name=(\S+) ms=([\d.]+) cold=([01])")
per_depth = {}          # depth -> [每次运行的最大冷加载 ms]
runs_with_data = 0
kinds = {}

for path in sorted(glob.glob(os.path.join(outdir, "run-*.log"))):
    best = {}
    found = False
    for line in open(path, encoding="utf-8", errors="replace"):
        m = pat.search(line)
        if not m:
            continue
        depth, kind, _name, ms, cold = int(m.group(1)), m.group(2), m.group(3), float(m.group(4)), m.group(5)
        if cold != "1":
            continue
        found = True
        kinds[depth] = kind
        best[depth] = max(best.get(depth, 0.0), ms)
    if found:
        runs_with_data += 1
    for depth, ms in best.items():
        per_depth.setdefault(depth, []).append(ms)

if not per_depth:
    print("✗ 一条冷加载读数都没采到 —— 记「未测到」，不是通过")
    sys.exit(2)

# 判据覆盖范围声明（需求 ①「逐层首次展开」）：这两层都要有冷样本，
# 缺一层就只能记「未知」——不许拿另一层的读数替它判通过。
REQUIRED = {2: "database", 3: "schema"}
missing = [f"depth={d}({k})" for d, k in REQUIRED.items() if not per_depth.get(d)]
if missing:
    print("✗ 覆盖不全：这些层零冷样本 —— " + " · ".join(missing))
    print("  记「未知」，不是通过（缺层的读数不能由别的层代判）")
    sys.exit(2)

def p95(values):
    if len(values) == 1:
        return values[0]
    ordered = sorted(values)
    idx = max(0, min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1)))))
    return ordered[idx]

print(f"运行次数：{runs_with_data} 次有冷加载读数 · 阈值 {threshold:.0f} ms")
print(f"{'层':<10}{'样本':>6}{'中位数':>10}{'P95':>10}{'最大':>10}  判定")
worst = 0
for depth in sorted(per_depth):
    vals = per_depth[depth]
    med, p, mx = statistics.median(vals), p95(vals), max(vals)
    worst = max(worst, med, p)
    ok = "✅" if med <= threshold and p <= threshold else "❌ 超阈"
    label = f"depth={depth}({kinds.get(depth, '?')})"
    print(f"{label:<10}{len(vals):>6}{med:>9.1f}{p:>10.1f}{mx:>10.1f}  {ok}")

sys.exit(0 if worst <= threshold else 1)
PY
rc=$?
echo "读数目录：$OUTDIR"
exit $rc
