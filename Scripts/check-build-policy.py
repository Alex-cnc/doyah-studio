#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# shared-surface：2026-11-10 新增判据 —— 「交付包口径」这条条文原来把 `build-app.sh` 本身当判据物（脚本判自己，等于没判）。
"""出包口径：「默认交付的是非沙箱包」这件事必须有人判。

为什么需要它
------------
《项目管理规范》§5「交付包口径」写着：默认出**非沙箱**包（`App/DoyahStudio-unsandboxed.entitlements`），
沙箱包只是备选。可原来那条的判据物写的是 `Scripts/build-app.sh` 本身 —— **脚本判自己**，
等于没判：2026-11-10 实测把默认 entitlements 从 unsandboxed 改成沙箱，
`check-release-version` 与 `check-release-freeze-parity` 双双 rc=0，没有任何门发现。

判的三件（都是文件状态，不需要真出包）
------------------------------------
1. **默认非沙箱**：`Scripts/build-app.sh` 里必须存在**非注释行**引用
   `App/DoyahStudio-unsandboxed.entitlements`（注释里抄一份不算 —— 这条判据自己就踩过这个坑）。
2. **不许默认沙箱**：非注释行里出现 `--sandbox` ⇒ 判红（沙箱包可以留作参数开关，但不能是默认）。
3. **两份 entitlements 在位**：`App/DoyahStudio.entitlements` 与
   `App/DoyahStudio-unsandboxed.entitlements` 都必须存在（少一份，包签不出来）。

判不了的（如实声明覆盖范围）
--------------------------
- 包**实际**用哪份 entitlements 签名：要真跑一次 `build-app.sh` 并读产物签名（`codesign -d --entitlements`），
  文件层判不了 ⇒ 本判据只判「脚本默认指向哪份」，不判「产物确实是哪份」。
- 产物留存（`dist/` 只留最新一版）：本判据不判；那一半由 `check-release-freeze-parity.py` 的 B/C 段覆盖。

用法
----
    python3 Scripts/check-build-policy.py            # 判真仓库（应 rc=0）
    python3 Scripts/check-build-policy.py --self-test # 判据自己的证据（4 例）
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = "Scripts/build-app.sh"
UNSANDBOXED = "App/DoyahStudio-unsandboxed.entitlements"
SANDBOXED = "App/DoyahStudio.entitlements"


def code_lines(text: str) -> list[str]:
    """非注释、非空行 —— 注释里抄着同一条不算数（`check-release-version` 踩过这个坑）。"""
    out = []
    for line in text.split("\n"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        out.append(s)
    return out


def check(text: str, exists: set[str]) -> list[str]:
    """纯函数（自检用）：返回问题清单，空 = 通过。"""
    problems: list[str] = []
    code = code_lines(text)

    if not any(UNSANDBOXED in l for l in code):
        problems.append(f"`{BUILD}` 的非注释行里找不到 `{UNSANDBOXED}` —— 默认包不是非沙箱口径")
    if any("--sandbox" in l for l in code):
        hit = next(l for l in code if "--sandbox" in l)
        problems.append(f"`{BUILD}` 的非注释行里出现 `--sandbox` ⇒ 默认变成沙箱包（行：{hit[:70]}）")
    for rel in (SANDBOXED, UNSANDBOXED):
        if rel not in exists:
            problems.append(f"缺 `{rel}` —— 两份 entitlements 必须都在位")
    return problems


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    build = ROOT / BUILD
    if not build.exists():
        print(f"❌ 找不到 `{BUILD}` —— 判据自己没面可判")
        return 1
    text = build.read_text(encoding="utf-8")
    exists = {p.relative_to(ROOT).as_posix() for p in (ROOT / "App").glob("*.entitlements")}
    problems = check(text, exists)

    print("出包口径判据（默认非沙箱 + 两份 entitlements 在位）")
    print(f"  面：`{BUILD}` 代码行 {len(code_lines(text))} 行 · `App/*.entitlements` {len(exists)} 份")
    if problems:
        print(f"❌ 出包口径不通过（{len(problems)} 处）：")
        for p in problems:
            print(f"   · {p}")
        return 1
    print("✅ 出包口径通过：默认引 unsandboxed entitlements、代码行无 `--sandbox`、两份 entitlements 在位")
    print("   覆盖范围：只判「脚本默认指向哪份」；产物到底用哪份签名要真出包后读 `codesign -d --entitlements`（本判据不判）")
    return 0


def self_test() -> int:
    good = 'APP="dist/x.app"\ncp App/DoyahStudio-unsandboxed.entitlements /tmp/e.plist\n'
    both = {SANDBOXED, UNSANDBOXED}
    cases = [
        ("正常（默认非沙箱、两份都在）", good, both, 0),
        ("默认改成沙箱 entitlements", good.replace("unsandboxed.entitlements", "DoyahStudio.entitlements"), both, 1),
        ("代码行里出现 --sandbox", good + "codesign --sandbox -s - x.app\n", both, 1),
        ("缺 unsandboxed entitlements", good, {SANDBOXED}, 1),
        ("注释里抄着 unsandboxed、真行是沙箱",
         "# cp App/DoyahStudio-unsandboxed.entitlements /tmp/e\ncp App/DoyahStudio.entitlements /tmp/e\n", both, 1),
    ]
    ok = 0
    for name, text, exists, want in cases:
        got = len(check(text, exists))
        passed = (got == 0) if want == 0 else (got > 0)
        if passed:
            ok += 1
        print(f"  {'✓' if passed else '✗'} {name} ⇒ 问题 {got} 处，应{'绿' if want == 0 else '红'}")
    print(f"自检 {ok}/{len(cases)} 达到预期")
    return 0 if ok == len(cases) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
