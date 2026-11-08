#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""冻结号 ⟷ 软件版本号：**书冻结哪个版本，软件就必须出哪个版本**

主人 2026-11-08 原话：「冻结了四书哪个版本，软件就应该出哪个版本。」
由来：此前是两套号 —— 包标签 `beta1.0.x`（App `1.0.x`）却建在**冻结 v1.1** 的四书上，
两个号各说各的，谁也说不清「手上这份包对的是哪一版契约」。

## 判据（三条，全部机械）

* **A 冻结号 → 软件号**：取 `Docs/frozen/` 里最新的 `-vX.Y-YYYYMMDD.md` ⇒ 软件 marketing 必须是
  `X.Y.0`、发布标签必须是 `betaX.Y`（`Scripts/release-version.json` 是这两个值的台账）。
* **B 产物跟随**：`dist/` 里若有 `DoyahStudio-<发布标签>.app`，它的 `Info.plist`
  的 `CFBundleShortVersionString` 必须逐字等于 marketing、`DoyahReleaseLabel` 必须逐字等于发布标签。
  **产物还没构建时不是通过** —— 打印「未知（尚未构建）」并把结论降为 `INCOMPLETE`（退出码 2，
  与「判红」区分：没人能拿「还没打包」冒充「已对齐」）。
* **C 不许有更旧的号冒充最新**：`dist/` 里若有版本号**小于**冻结号的产物，判红（旧包还在，
  容易被装错）；同号或更大不判（更大的号属于下一次冻结之前的状态，由 A 管）。

## 明确不判（范围外，每次实跑打印）

* 书内部的「活书版本」（`v1.2.NNN`）：那是演进号，与冻结号不是同一个东西（冻结件里才是 `v1.2`）。
* 产物字节内容 / 签名 / 构建号（`CFBundleVersion`）：那是构建确定性，不是身份。
* `Docs/frozen/README.md` 之外的登记表：本判据只认「文件名 + 台账 + 产物 plist」三处。

用法：
    python3 Scripts/check-release-freeze-parity.py            # 判
    python3 Scripts/check-release-freeze-parity.py --self-test # 负例自检（必须判红）
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FROZEN_DIR = ROOT / "Docs" / "frozen"
RELEASE_JSON = ROOT / "Scripts" / "release-version.json"
DIST_DIR = ROOT / "dist"

FROZEN_RE = re.compile(r"-v(\d+)\.(\d+)-(\d{8})\.md$")
PRODUCT_RE = re.compile(r"^DoyahStudio-(?P<label>[A-Za-z][A-Za-z0-9]*\.\d+)\.app$")


def latest_frozen_version(frozen_dir: pathlib.Path) -> tuple[int, int] | None:
    """冻结件里最新的段号（`v1.2-20261108` ⇒ (1, 2)）；一份都没有返回 None。"""
    best: tuple[int, int] | None = None
    for path in frozen_dir.glob("*.md"):
        m = FROZEN_RE.search(path.name)
        if not m:
            continue
        seg = (int(m.group(1)), int(m.group(2)))
        if best is None or seg > best:
            best = seg
    return best


def read_ledger(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def plist_value(app: pathlib.Path, key: str) -> str | None:
    plist = app / "Contents" / "Info.plist"
    if not plist.exists():
        return None
    try:
        out = subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Print :{key}", str(plist)],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() or None if out.returncode == 0 else None


def judge(frozen_dir: pathlib.Path, ledger: dict, dist_dir: pathlib.Path) -> tuple[str, list[str], list[str]]:
    """返回 (结论, 判红列表, 读数行)。结论 ∈ {"PASS", "FAIL", "INCOMPLETE"}。"""
    problems: list[str] = []
    readings: list[str] = []

    seg = latest_frozen_version(frozen_dir)
    if seg is None:
        return "FAIL", ["Docs/frozen/ 里一份冻结件都没有 ⇒ 没有基线可比（空跑判红）"], readings
    want_marketing = f"{seg[0]}.{seg[1]}.0"
    want_label = f"beta{seg[0]}.{seg[1]}"
    readings.append(f"最新冻结段 = v{seg[0]}.{seg[1]} ⇒ 软件应为 `{want_label}` / marketing `{want_marketing}`")

    got_marketing = ledger.get("marketingVersion")
    got_label = ledger.get("releaseLabel")
    readings.append(f"台账 release-version.json = `{got_label}` / marketing `{got_marketing}`")
    if got_marketing != want_marketing:
        problems.append(f"[A] 台账 marketingVersion = `{got_marketing}`，冻结 v{seg[0]}.{seg[1]} 要求 `{want_marketing}`")
    if got_label != want_label:
        problems.append(f"[A] 台账 releaseLabel = `{got_label}`，冻结 v{seg[0]}.{seg[1]} 要求 `{want_label}`")

    # C：盘上不许躺着比冻结号更旧的包
    if dist_dir.is_dir():
        for app in sorted(dist_dir.glob("DoyahStudio-*.app")):
            m = PRODUCT_RE.match(app.name)
            if not m:
                continue
            label = m.group("label")
            num = label.split(".")[-1]
            milestone = re.sub(r"^(alpha|beta|rc)", "", label)
            parts = milestone.split(".")
            if len(parts) < 2:
                continue
            on_disk = (int(parts[0]), int(parts[1]))
            if on_disk < seg:
                problems.append(f"[C] dist 里还有更旧的包 `{app.name}`（v{on_disk[0]}.{on_disk[1]} < 冻结 v{seg[0]}.{seg[1]}）—— 容易装错")
            readings.append(f"dist 产物 `{app.name}` ⇒ v{on_disk[0]}.{on_disk[1]}")

    # B：产物跟随
    target = dist_dir / f"DoyahStudio-{want_label}.app" if dist_dir.is_dir() else None
    if target is None or not target.exists():
        readings.append(f"产物 `DoyahStudio-{want_label}.app` 尚未构建 ⇒ 版本号对不对**未知**（跳过 ≠ 通过）")
        return ("FAIL" if problems else "INCOMPLETE"), problems, readings

    got_plist = plist_value(target, "CFBundleShortVersionString")
    got_plist_label = plist_value(target, "DoyahReleaseLabel")
    readings.append(f"产物 plist = `{got_plist_label}` / `{got_plist}`")
    if got_plist != want_marketing:
        problems.append(f"[B] 产物 CFBundleShortVersionString = `{got_plist}`，应为 `{want_marketing}`")
    if got_plist_label != want_label:
        problems.append(f"[B] 产物 DoyahReleaseLabel = `{got_plist_label}`，应为 `{want_label}`")

    return ("FAIL" if problems else "PASS"), problems, readings


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    ledger = read_ledger(RELEASE_JSON)
    verdict, problems, readings = judge(FROZEN_DIR, ledger, DIST_DIR)
    for line in readings:
        print(f"ℹ️ {line}")
    print("ℹ️ 范围外：活书演进号（vX.Y.NNN）、产物字节内容 / 构建号、其它登记表")
    if problems:
        print(f"\n❌ 冻结号 ⟷ 软件号对账不通过（{len(problems)} 处）：")
        for p in problems:
            print(f"   · {p}")
        print("RESULT: FAIL")
        return 1
    if verdict == "INCOMPLETE":
        print("\n⚠️ 结论：INCOMPLETE（台账与冻结号已对齐，但产物还没构建 ⇒ 产物那一半未知）")
        print("RESULT: INCOMPLETE")
        return 2
    print("RESULT: PASS")
    return 0


def self_test() -> int:
    """负例：故意让台账落后一个冻结段 / 产物 plist 写错号 —— 两条都必须判红。"""
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        frozen = base / "frozen"
        frozen.mkdir()
        (frozen / "Doyah产品需求规格说明书-v1.3-20261201.md").write_text("x", encoding="utf-8")
        dist = base / "dist"
        dist.mkdir()
        ledger = {"marketingVersion": "1.2.0", "releaseLabel": "beta1.2"}
        verdict, problems, _ = judge(frozen, ledger, dist)
        if verdict != "FAIL" or not any("[A]" in p for p in problems):
            print(f"✗ 负例 1（冻结 v1.3 而台账 1.2.0）没判红：{verdict} {problems}")
            failures += 1
        else:
            print("✓ 负例 1：冻结 v1.3 而台账 1.2.0 ⇒ 判红")
        ledger2 = {"marketingVersion": "1.3.0", "releaseLabel": "beta1.3"}
        verdict, problems, _ = judge(frozen, ledger2, dist)
        if verdict != "INCOMPLETE":
            print(f"✗ 负例 2（台账对齐但产物未构建）结论应为 INCOMPLETE：{verdict}")
            failures += 1
        else:
            print("✓ 负例 2：台账对齐、产物未构建 ⇒ INCOMPLETE（不许冒充通过）")
        # 更旧的包躺在 dist 里 ⇒ 判红
        old = dist / "DoyahStudio-beta1.1.app"
        (old / "Contents").mkdir(parents=True)
        ledger3 = {"marketingVersion": "1.3.0", "releaseLabel": "beta1.3"}
        verdict, problems, _ = judge(frozen, ledger3, dist)
        if verdict != "FAIL" or not any("[C]" in p for p in problems):
            print(f"✗ 负例 3（更旧包还在）没判红：{verdict} {problems}")
            failures += 1
        else:
            print("✓ 负例 3：dist 里躺着更旧的 beta1.1 ⇒ 判红")
    print("SELF-TEST: " + ("PASS" if failures == 0 else f"FAIL（{failures} 例）"))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
