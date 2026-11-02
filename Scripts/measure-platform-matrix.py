#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""平台矩阵实测（`NFR-ALL-GATE-COMP-004` ① / `NFR-ALL-GATE-COMP-005` ①③）。

## 量什么

对着**真产物**量四件事，一件都不许由台账自己说了算：

  1. `lipo -archs` —— 这个可执行文件里到底有几个架构（不是「配置里写了 universal」）；
  2. 逐个切片的 `LC_BUILD_VERSION.minos` —— 每个架构**自己的**最低系统版本
     （`vtool -show-build`；不是 Info.plist 抄来的那一个）；
  3. 真启动一遍，等**启动收据**（`App/LaunchReceiptProbe.swift`，与冷启动同一条仪表）：
     收据落盘 = 进程起来了、根视图出现了、事件循环转了一圈。拿不到收据 ⇒ 这一档没跑起来；
  4. Rosetta 侧：`arch -x86_64 /bin/sh -c 'sysctl -n sysctl.proc_translated'` 必须回 `1`
     —— 否则「x86_64 切片能跑」那句话证明的是 arch(1)，不是 Rosetta。

## 用法

    DOYAH_ARCH=universal ./Scripts/build-app.sh          # 先出双架构产物
    python3 Scripts/measure-platform-matrix.py --json-out .build/platform-matrix.json
    python3 Scripts/measure-platform-matrix.py --app <瘦架构二进制>   # 红绿对照用

判读（对阈值）不在这里，由 `Scripts/check-platform-compat.py --readings` 做 ——
本脚本只产读数，**不自己判通过**。

## 边界（如实登记，别折成通过）

· **真 macOS 14 / 15 未测**：本机是 macOS 27；14 / 15 的「能启动」没有机器可跑。
  这里能给的是「两个切片各自的 minos 都是 14.0」+「编译在 14.0 部署目标下过」
  （后者由 `swift build` 自己按 `-target …macosx14.0` 编，用了更高版本的 API 会编译失败）；
· **真 Intel 机未测**：Rosetta 下跑 x86_64 切片只是近似证据，不等于 Intel 硬件；
· 收据的终点是「首帧 + 一圈事件循环」，不含 GPU 上屏合成与首次安装的冷缓存首启。
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

BASE = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_APP = BASE / "dist" / "DoyahStudio.app" / "Contents" / "MacOS" / "DoyahStudio"
DEFAULT_PLIST = BASE / "dist" / "DoyahStudio.app" / "Contents" / "Info.plist"
RECEIPT_ENV = "DOYAH_LAUNCH_RECEIPT"
REQUIRED_ARCHS = ("arm64", "x86_64")


def run(command, timeout=60.0):
    """跑一条命令，返回 (rc, stdout+stderr)。**不吞错**：非 0 由调用方决定怎么记账。"""
    try:
        finished = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout
        )
        return finished.returncode, (finished.stdout or "") + (finished.stderr or "")
    except subprocess.TimeoutExpired:
        return -9, "超时（%.0f 秒）：%s" % (timeout, " ".join(command))
    except FileNotFoundError as error:
        return -2, "命令不存在：%s" % error


def architecture_report(binary: pathlib.Path):
    rc, text = run(["lipo", "-archs", str(binary)])
    if rc != 0:
        return None, text.strip()
    archs = text.strip().split()
    return archs, text.strip()


def slice_minimum(binary: pathlib.Path, arch: str, scratch: pathlib.Path):
    """切出单个架构再看它自己的最低系统版本。

    为什么要切：fat 文件的 `vtool -show-build` 只报**一个** LC_BUILD_VERSION，
    两个切片理论上可以不一样 —— 不切开就是把两件事读成一件。
    """
    thin = scratch / ("slice-%s" % arch)
    rc, text = run(["lipo", "-thin", arch, str(binary), "-output", str(thin)])
    if rc != 0:
        # 已经是**瘦**二进制时 `lipo -thin` 会拒（`must be a fat file`）——
        # 那不是读不出 minos，是没得可切：直接对本体读（红绿对照时就会走这一支）。
        archs, _ = architecture_report(binary)
        if archs == [arch]:
            thin = binary
        else:
            return None, "lipo -thin 失败：%s" % text.strip()
    rc, text = run(["vtool", "-show-build", str(thin)])
    if rc != 0:
        return None, "vtool 失败：%s" % text.strip()
    minimum = None
    platform = None
    for line in text.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[0] == "minos":
            minimum = fields[1]
        elif len(fields) == 2 and fields[0] == "platform":
            platform = fields[1]
    return {"arch": arch, "minos": minimum, "platform": platform}, text


def launch_once(binary: pathlib.Path, arch: str, receipt: pathlib.Path, timeout: float):
    """按指定架构起一遍，等收据。返回 {ok, elapsedMs?, error?}。"""
    if receipt.exists():
        receipt.unlink()
    environment = dict(os.environ)
    environment[RECEIPT_ENV] = str(receipt)
    environment.setdefault("DOYAH_BUILD_FLAVOR", "platform-matrix")
    command = []
    if arch == "x86_64":
        # `arch -x86_64` 选的是**切片**，Rosetta 负责翻译；没有 Rosetta 时它会直接报错。
        command = ["/usr/bin/arch", "-x86_64"]
    command += [str(binary), "-AppleLanguages", "(zh-Hans)", "-app.language", "zh-Hans"]
    started = time.monotonic()
    process = subprocess.Popen(
        command, env=environment,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        deadline = started + timeout
        payload = None
        while time.monotonic() < deadline:
            if receipt.exists() and receipt.stat().st_size > 0:
                try:
                    payload = json.loads(receipt.read_text(encoding="utf-8"))
                    break
                except json.JSONDecodeError:
                    time.sleep(0.01)   # 原子写的换名瞬间，再等一轮
                    continue
            if process.poll() is not None and not receipt.exists():
                return {
                    "ok": False,
                    "error": "进程提前退出（rc=%s）且没写收据" % process.returncode,
                }
            time.sleep(0.01)
        if payload is None:
            return {"ok": False, "error": "等了 %.0f 秒没等到收据" % timeout}
        return {
            "ok": True,
            "elapsedMs": payload.get("elapsedMs"),
            "externalMs": round((time.monotonic() - started) * 1000.0, 1),
            "schema": payload.get("schema"),
        }
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def rosetta_report():
    """Rosetta 到底在不在、而且真把进程翻译着跑 —— 这两件事得分开问。"""
    running = "arm64" if os.uname().machine == "arm64" else os.uname().machine
    translated = None
    if running == "arm64":
        rc, text = run(["/usr/bin/arch", "-x86_64", "/bin/sh", "-c",
                        "sysctl -n sysctl.proc_translated"])
        translated = text.strip() if rc == 0 else None
    return {
        "hostArch": running,
        "available": translated == "1",
        "procTranslated": translated,
        "note": "proc_translated=1 = 这个进程真在 Rosetta 翻译态下跑（不是 arch(1) 选了个切片就算）",
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="平台矩阵实测（架构 / minos / 真启动）")
    parser.add_argument("--app", default=str(DEFAULT_APP), help="待量的可执行文件")
    parser.add_argument("--plist", default=str(DEFAULT_PLIST), help="产物 Info.plist")
    parser.add_argument("--runs", type=int, default=2, help="每个架构起几遍（默认 2）")
    parser.add_argument("--timeout", type=float, default=120.0, help="单遍等收据的上限（秒）")
    parser.add_argument("--json-out", default=None, help="读数写成 JSON（给 check-platform-compat 读）")
    args = parser.parse_args(argv)

    binary = pathlib.Path(args.app)
    if not binary.exists():
        print("✗ 没有可执行文件：%s" % binary)
        print("  先构建：DOYAH_ARCH=universal ./Scripts/build-app.sh")
        return 2

    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-platform-", dir=str(BASE / ".build")))
    readings = {
        "kind": "platform-matrix",
        "measuredOn": time.strftime("%Y-%m-%d"),
        "command": "python3 Scripts/measure-platform-matrix.py --json-out %s" % (args.json_out or "-"),
        "app": str(binary),
        "hostOS": subprocess.run(["sw_vers", "-productVersion"], capture_output=True,
                                 text=True).stdout.strip(),
        "slices": [],
        "launches": [],
        "rosetta": rosetta_report(),
    }
    ok = True

    archs, report = architecture_report(binary)
    readings["archs"] = archs
    readings["archReport"] = report
    print("架构：%s" % (report or "(读不出)"))
    if not archs:
        print("✗ 读不出架构 —— 这个文件不是可执行文件？")
        ok = False

    for arch in archs or []:
        info, raw = slice_minimum(binary, arch, scratch)
        if info is None:
            print("✗ %s 切片读不出 minos：%s" % (arch, raw))
            ok = False
            readings["slices"].append({"arch": arch, "minos": None, "error": raw})
            continue
        readings["slices"].append(info)
        print("  切片 %-7s minos %s · platform %s" % (arch, info["minos"], info["platform"]))

    plist = pathlib.Path(args.plist)
    minimum = None
    if plist.exists():
        try:
            with plist.open("rb") as handle:
                payload = plistlib.load(handle)
            minimum = payload.get("LSMinimumSystemVersion")
        except Exception as error:   # noqa: BLE001 — 读不出来要如实说，不能当成没有
            print("✗ Info.plist 读不出来：%s" % error)
            ok = False
    readings["plistMinimum"] = minimum
    print("Info.plist LSMinimumSystemVersion：%s" % (minimum or "(没有：低于最低版本的机器不会被告知)"))

    for arch in archs or []:
        if arch not in REQUIRED_ARCHS:
            continue
        runs = []
        for index in range(1, args.runs + 1):
            receipt = scratch / ("receipt-%s-%d.json" % (arch, index))
            result = launch_once(binary, arch, receipt, args.timeout)
            runs.append(result)
            if result.get("ok"):
                print("  启动 %-7s 第 %d 遍：收据 %s ms · 外部 %s ms"
                      % (arch, index, result.get("elapsedMs"), result.get("externalMs")))
            else:
                print("  启动 %-7s 第 %d 遍：✗ %s" % (arch, index, result.get("error")))
        launch = {
            "arch": arch,
            "mode": "native" if arch == os.uname().machine else "rosetta",
            "runs": runs,
            "ok": all(item.get("ok") for item in runs),
        }
        readings["launches"].append(launch)
        if not launch["ok"]:
            ok = False

    missing = [arch for arch in REQUIRED_ARCHS if arch not in (archs or [])]
    if missing:
        print("✗ 产物缺架构：%s（需求要 arm64 与 x86_64 都在）" % "、".join(missing))
        ok = False
    if readings["rosetta"]["hostArch"] == "arm64" and not readings["rosetta"]["available"]:
        print("⚠ Rosetta 不可用（proc_translated=%s）⇒ x86_64 切片这一档没跑起来"
              % readings["rosetta"]["procTranslated"])
        ok = False

    readings["verdict"] = "measured" if ok else "incomplete"
    readings["boundaries"] = [
        "真 macOS 14 / 15 未测（本机 %s）" % readings["hostOS"],
        "真 Intel 硬件未测（Rosetta 只是近似证据）",
        "收据终点 = 首帧 + 一圈事件循环，不含 GPU 上屏合成",
    ]
    if args.json_out:
        target = pathlib.Path(args.json_out)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(readings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("读数：%s" % target)

    shutil.rmtree(scratch, ignore_errors=True)
    print("结论：%s" % ("矩阵实测完成（判读交给 check-platform-compat.py --readings）" if ok
                       else "有缺口，见上面的 ✗（不等于通过）"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
