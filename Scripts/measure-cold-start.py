#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""冷启动测量（`NFR-ALL-GATE-PERF-001`：App 冷启动到可交互 ≤ 2 s，本机 SSD）。

## 量什么

真起一个 `DoyahStudio.app` 进程，让它自己在「可交互」那一刻写一份收据
（`App/LaunchReceiptProbe.swift` → `Core/LaunchTimeline.swift`），本脚本读那份收据。
两条读数一起报，**都不许少**：

  · `elapsedMs`（收据里）：**进程创建 → 首帧**。起点是内核记录的 `p_starttime`
    （含 dyld / 静态初始化），不是「App 里第一行执行到的地方」；
  · `externalMs`（本脚本自己的墙钟）：`Popen` 之前 → 收据出现。多出来的是
    进程创建前的 shell 侧开销与被测方看不见的那一段 —— 两条一比就能看出
    「收据是不是自己商量出来的数」。

口径：跑 `runs` 遍（默认 3，取**中位数**），每一遍的读数都打出来；不挑最快那一遍。

## 用法

    python3 Scripts/measure-cold-start.py                     # 默认 3 遍 + 判
    python3 Scripts/measure-cold-start.py --json-out .build/perf-cold-start.json
    python3 Scripts/measure-cold-start.py --runs 5
    DOYAH_LAUNCH_ARTIFICIAL_DELAY_MS=2500 python3 Scripts/measure-cold-start.py
        # 负例：人为把「首帧」拖慢 2.5 s ⇒ 必须判红（证明判据真的在比，而不是台账自己说了算）

`--app` 指到哪个可执行文件就量哪个（红绿对照 / 量旧包时用）。

## 边界（如实登记）

· 不含 GPU 上屏合成（收据的终点是「首帧已经画了」）；
· 文件缓存是热的：每遍新起进程，但不重启系统、不清缓存 —— 首次安装后的
  **冷缓存首启**不在本口径内（台账 `notCovered` 里记着）；
· 用户正开着应用时也能跑：收据探针走单实例保护的放行口（`isLaunchReceiptProbe`），
  本脚本只杀自己起的那个 pid，不碰别人的进程。
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import statistics
import subprocess
import sys
import tempfile
import time

BASE = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_APP = BASE / "dist" / "DoyahStudio.app" / "Contents" / "MacOS" / "DoyahStudio"
LEDGER = BASE / "Scripts" / "perf-baseline.json"
RECEIPT_ENV = "DOYAH_LAUNCH_RECEIPT"
DELAY_ENV = "DOYAH_LAUNCH_ARTIFICIAL_DELAY_MS"
BUILD_ENV = "DOYAH_BUILD_FLAVOR"


def load_ledger(path: pathlib.Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def run_once(binary: pathlib.Path, scratch: pathlib.Path, run: int, timeout: float) -> dict:
    """起一遍，等收据。返回这一遍的读数（拿不到就给 `error`，不编造数字）。"""
    receipt_path = scratch / ("run-%d.json" % run)
    if receipt_path.exists():
        receipt_path.unlink()

    environment = dict(os.environ)
    environment[RECEIPT_ENV] = str(receipt_path)
    environment.setdefault(BUILD_ENV, "Debug")

    started = time.monotonic()
    process = subprocess.Popen(
        [str(binary), "-AppleLanguages", "(zh-Hans)", "-app.language", "zh-Hans"],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    receipt = None
    try:
        deadline = started + timeout
        while time.monotonic() < deadline:
            if receipt_path.exists() and receipt_path.stat().st_size > 0:
                try:
                    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
                    break
                except json.JSONDecodeError:
                    # 原子写：换名那一瞬读不到就再等一轮（不是「没有收据」）。
                    time.sleep(0.01)
                    continue
            if process.poll() is not None and not receipt_path.exists():
                return {"run": run, "error": "进程提前退出（rc=%s）且没写收据" % process.returncode}
            time.sleep(0.005)
        external_ms = (time.monotonic() - started) * 1000.0
        if receipt is None:
            return {"run": run, "error": "等了 %.0f 秒没等到收据" % timeout}
        return {
            "run": run,
            "elapsedMs": receipt.get("elapsedMs"),
            "externalMs": round(external_ms, 1),
            "phasesMs": receipt.get("phasesMs") or {},
            "build": receipt.get("build"),
            "processStartEpoch": receipt.get("processStartEpoch"),
        }
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def median_of(values):
    usable = [value for value in values if isinstance(value, (int, float)) and value >= 0]
    return statistics.median(usable) if usable else None


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="冷启动到可交互的实测（NFR-ALL-GATE-PERF-001）")
    parser.add_argument("--app", default=str(DEFAULT_APP), help="待量的可执行文件")
    parser.add_argument("--ledger", default=str(LEDGER), help="阈值台账（唯一来源）")
    parser.add_argument("--runs", type=int, default=None, help="跑几遍（默认取台账 coldStart.runs）")
    parser.add_argument("--timeout", type=float, default=90.0, help="单遍等收据的上限（秒）")
    parser.add_argument("--json-out", default=None, help="把读数写成 JSON（给 check-perf-ledger 读）")
    parser.add_argument("--keep", action="store_true", help="保留临时收据（排查用）")
    args = parser.parse_args(argv)

    ledger = load_ledger(pathlib.Path(args.ledger))
    cold = ledger["coldStart"]
    limit_ms = float(cold["limitMs"])
    runs = args.runs or int(cold.get("runs", 3))

    binary = pathlib.Path(args.app)
    if not binary.exists():
        print("✗ 没有可执行文件：%s" % binary)
        print("  先构建：./Scripts/build-app.sh   （或 --app 指到已有的包）")
        return 2

    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-cold-start-", dir=str(BASE / ".build")))
    print("冷启动测量：%d 遍 · 阈值 %.0f ms（来源 %s）" % (runs, limit_ms, args.ledger))
    print("包：%s" % binary)
    if os.environ.get(DELAY_ENV):
        print("⚠ 负例开关 %s=%s（人为拖慢，这一轮**故意**应当判红）" % (DELAY_ENV, os.environ[DELAY_ENV]))

    results = []
    for index in range(1, runs + 1):
        result = run_once(binary, scratch, index, args.timeout)
        results.append(result)
        if "error" in result:
            print("  第 %d 遍：✗ %s" % (index, result["error"]))
        else:
            print(
                "  第 %d 遍：收据 %8.1f ms · 外部墙钟 %8.1f ms · 各段 %s"
                % (
                    index,
                    result["elapsedMs"],
                    result["externalMs"],
                    " / ".join("%s %.0f" % (key, value) for key, value in (result["phasesMs"] or {}).items()),
                )
            )

    measured = [item.get("elapsedMs") for item in results if "elapsedMs" in item]
    external = [item.get("externalMs") for item in results if "elapsedMs" in item]
    representative = median_of(measured)
    external_median = median_of(external)

    readings = {
        "kind": "cold-start",
        "measuredOn": time.strftime("%Y-%m-%d"),
        "command": "python3 Scripts/measure-cold-start.py --json-out %s" % (args.json_out or "-"),
        "app": str(binary),
        "limitMs": limit_ms,
        "ledger": args.ledger,
        "runs": results,
        "medianMs": representative,
        "externalMedianMs": external_median,
        "artificialDelayMs": os.environ.get(DELAY_ENV),
        "environment": ledger.get("environment") or {},
    }

    print()
    if representative is None:
        readings["verdict"] = "unmeasurable"
        print("✗ 判不了：%d 遍一遍都没拿到收据（%d 遍给了原因）" % (runs, len(results) - len(measured)))
        verdict_ok = False
    elif representative <= limit_ms:
        readings["verdict"] = "within"
        print("✓ 达标：中位数 %.1f ms ≤ %.0f ms（各遍 %s；外部墙钟中位数 %.1f ms）"
              % (representative, limit_ms, ", ".join("%.0f" % value for value in measured), external_median or -1))
        verdict_ok = True
    else:
        readings["verdict"] = "over"
        print("✗ 超阈值：中位数 %.1f ms > %.0f ms（各遍 %s；外部墙钟中位数 %.1f ms）"
              % (representative, limit_ms, ", ".join("%.0f" % value for value in measured), external_median or -1))
        verdict_ok = False

    if args.json_out:
        target = pathlib.Path(args.json_out)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(readings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("读数：%s" % target)

    if not args.keep:
        for leftover in scratch.glob("run-*.json"):
            leftover.unlink(missing_ok=True)
        try:
            scratch.rmdir()
        except OSError:
            pass

    return 0 if verdict_ok else 1


if __name__ == "__main__":
    sys.exit(main())
