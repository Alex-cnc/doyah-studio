#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""结果集读数（`NFR-ALL-GATE-PERF-002/003`）：把滚动探针量出来的数收成一份 JSON。

探针本体在 `TestsUISnapshot/LargeResultScrollProbeTests.swift`（每条上界都从
`Scripts/result-scroll-baseline.json` 读）；本脚本只做两件事：

  1. 用 `DOYAH_UI_SNAPSHOT=1` 真跑那一族（不跑就不出读数 —— 空壳不算）；
  2. 把探针自己打印的四条读数（📊 物化行视图 / ⏱️ 帧成本 / ⚖️ 比值 / 🧠 常驻内存增量）
     解析成 `kind: result-set` 的 JSON，交 `Scripts/check-perf-ledger.py --readings` 对阈值。

## 为什么读探针的输出、不在脚本里另算一遍

阈值与量法都在探针里（它读台账）。脚本再算一遍就会变成第二套量法 —— 两边迟早不一致，
而「两边不一致」在这类判据上永远表现成「都绿」。

## 用法

    python3 Scripts/measure-result-set.py                       # 跑 + 打印 + 写 .build/perf-result-set.json
    python3 Scripts/measure-result-set.py --json-out /tmp/x.json
    python3 Scripts/measure-result-set.py --reuse /tmp/x.json   # 不跑，只把已有日志里的读数重新解析

**边界（如实登记）**：与探针同一条 —— 离屏渲染（不上屏合成）、合成结果（不连数据库）、
观感可感知性归人工。
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import time

BASE = pathlib.Path(__file__).resolve().parent.parent
FILTER = "LargeResultScrollProbeTests"

FRAME = re.compile(r"帧（脏区重画）p50 ([\d.]+) ms")
RASTER = re.compile(r"整幅重画 p50 ([\d.]+) ms")
RATIO = re.compile(r"（([\d.]+)×")
MEMORY = re.compile(r"常驻内存增量 (-?[\d.]+) MB")
MATERIALIZED = re.compile(r"(\d+) 行 × (\d+) 列：物化行视图 (\d+) 个")


def parse_readings(log: str) -> dict:
    readings = {}
    for line in log.splitlines():
        if "⏱️" in line:
            if (match := FRAME.search(line)):
                readings["frameP50Ms"] = float(match.group(1))
            if (match := RASTER.search(line)):
                readings["rasterP50Ms"] = float(match.group(1))
        elif "⚖️" in line:
            if (match := RATIO.search(line)):
                readings["ratioFactor"] = float(match.group(1))
        elif "🧠" in line:
            if (match := MEMORY.search(line)):
                readings["residentDeltaMB"] = float(match.group(1))
        elif "📊" in line:
            if (match := MATERIALIZED.search(line)):
                readings.setdefault("materializedRowViews", {})[match.group(1)] = int(match.group(3))
                readings["columns"] = int(match.group(2))
    return readings


def run_probe() -> tuple:
    environment = dict(os.environ)
    environment["DOYAH_UI_SNAPSHOT"] = "1"
    environment["DEVELOPER_DIR"] = environment.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    started = time.monotonic()
    process = subprocess.run(
        ["swift", "test", "--filter", FILTER],
        cwd=str(BASE), env=environment, capture_output=True, text=True,
    )
    return process, time.monotonic() - started


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="结果集读数（NFR-ALL-GATE-PERF-002/003）")
    parser.add_argument("--json-out", default=str(BASE / ".build" / "perf-result-set.json"))
    parser.add_argument("--reuse", default=None, help="不跑探针：从这份日志里重新解析读数")
    parser.add_argument("--log-out", default=str(BASE / ".build" / "perf-result-set.log"))
    args = parser.parse_args(argv)

    if args.reuse:
        log = pathlib.Path(args.reuse).read_text(encoding="utf-8", errors="replace")
        exit_code = 0
    else:
        print("跑探针：swift test --filter %s（DOYAH_UI_SNAPSHOT=1）" % FILTER)
        process, seconds = run_probe()
        log = (process.stdout or "") + (process.stderr or "")
        pathlib.Path(args.log_out).write_text(log, encoding="utf-8")
        exit_code = process.returncode
        print("探针结束：rc=%d · %.1f 秒 · 日志 %s" % (process.returncode, seconds, args.log_out))
        # 摘要行有多处（嵌套套件会印 `Executed 0 tests`）：取**用例数最大**那一行，
        # 「跑了 0 例」不许读成「跑过且通过」。
        counts = [int(match.group(1)) for match in re.finditer(r"Executed (\d+) tests", log)]
        for line in log.splitlines():
            if "Executed" in line and counts and ("Executed %d tests" % max(counts)) in line:
                print("  %s" % line.strip())
                break
        if not counts or max(counts) == 0:
            print("✗ 探针一例都没跑（跳过 / 没匹配上）—— 那不是通过")
            return 1

    readings = parse_readings(log)
    missing = [key for key in ("frameP50Ms", "rasterP50Ms", "ratioFactor", "residentDeltaMB") if key not in readings]
    print()
    for key in ("frameP50Ms", "rasterP50Ms", "ratioFactor", "residentDeltaMB", "materializedRowViews"):
        if key in readings:
            print("  %-22s %s" % (key, readings[key]))
    if missing:
        print("✗ 探针输出里缺读数：%s（跳过了？没渲染成？—— 都算没量到，不是通过）" % ", ".join(missing))
        return 1
    if exit_code != 0:
        print("✗ 探针自己有失败用例（rc=%d）—— 读数不能用，先看日志" % exit_code)
        return 1

    document = {
        "kind": "result-set",
        "measuredOn": time.strftime("%Y-%m-%d"),
        "command": "DOYAH_UI_SNAPSHOT=1 swift test --filter %s  → python3 Scripts/measure-result-set.py" % FILTER,
        "filter": FILTER,
        "probe": "TestsUISnapshot/LargeResultScrollProbeTests.swift",
        "readings": readings,
        "frameP50Ms": readings["frameP50Ms"],
        "rasterP50Ms": readings["rasterP50Ms"],
        "ratioFactor": readings["ratioFactor"],
        "residentDeltaMB": readings["residentDeltaMB"],
    }
    target = pathlib.Path(args.json_out)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("读数：%s" % target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
