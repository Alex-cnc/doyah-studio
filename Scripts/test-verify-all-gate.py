#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`Scripts/verify-all.sh` 的**控制流**负例验证（队列 L-110）。

为什么要有它：本脚本是 `set -euo pipefail` ⇒ 第 N 项失败**当场中止**，后面的项**根本没跑**。
2026-09-30 就是这样说出「十八项里只有第 1 项红」这句**没有证据**的话的 —— 未执行 ≠ 通过。
第 488 轮把两件事落成机制（默认跑法的「**未执行项**」如实报 + `--keep-going` 跑完再汇总），
而**机制自己也得有判据**：一个把 `set -e` 写错、把陷阱装晚、把项表数错的改动，
症状是「它说话时说得像模像样、却一句真话都没有」，编译照过、别的门禁照绿。

**夹具 = 真脚本原样 + 桩件**：把仓库的 `Scripts/verify-all.sh` **逐字节**拷进临时迷你仓，
再按它引用的每个 `Scripts/*.py|*.sh` 造一个桩；桩读 `<夹具>/.stub-failures` 清单 ——
清单里点了名的桩就以退出码 3 失败（= 那一项红），其余退出 0。于是整条闭环能在
**零点几秒**内跑完十九项（桩不做实事），而**控制流一行都不是仿写**：项表、行号 → 项号的翻译、
`ERR` 陷阱、两种跑法的话，全跑的是真文件。

断言的都是「它说了什么」这件事本身：

  例 1 绿对照（默认）· 例 2 默认跑法第 3 项红 ⇒ 点名第 3 项 + **未执行**逐项列出且不谎报
        （例 1 另判**侧名词表**：第 16 项的越界判据必须按**演员名**调用 —— 桩件本来跑不出这一类错，
         2026-11-02 实测它让「契约所有者改三书」在全量验收里永远判红；桩现在把 argv 记进 `.stub-argv`）
  例 3 默认跑法第 1 项红 ⇒ 未执行从第 2 项起、**不含第 1 项**
  例 4 `DOYAH_PLATFORM=linux` + 第 16 项红 ⇒ 未执行里**不许**出现被跳过的第 1 / 11 项
  例 5 `--keep-going` + 第 3 项红 ⇒ **第 4 项到第 19 项真的跑了**（输出里有它们的项块头）
  例 6 `--keep-going` + 两处红（第 3 / 12 项，两个不同的项）⇒ 汇总**两项都点名**（不许只报第一个）
  例 7 `--keep-going` 绿 ⇒ 逐项判定表十九行全 ✅ 且收尾仍报「十九项全过」
  例 8 末例：真仓库 `Scripts/verify-all.sh` 逐字节未变（「只在副本上写坏」这句话本身要被验证）

跑法（改 `verify-all.sh` 的控制流之后跑一次）：

    python3 Scripts/test-verify-all-gate.py

退出码 0 = 全部达到预期。
"""

from __future__ import annotations

import hashlib
import os
import pathlib
import re
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
TARGET = "Scripts/verify-all.sh"

STUB_PY = """#!/usr/bin/env python3
import pathlib, sys
name = pathlib.Path(__file__).name
root = pathlib.Path(__file__).resolve().parent.parent
# 记录被调用时的实参：侧名词表这类「传进去的名字对不对」的错，桩不记 argv 就永远看不见
# （2026-11-02 实测：第 16 项传平台名给认演员名的判据 ⇒ 契约所有者自己改三书判红，而桩测试全绿）
with open(root / ".stub-argv", "a", encoding="utf-8") as fh:
    fh.write(name + " " + " ".join(sys.argv[1:]) + "\\n")
fail = root / ".stub-failures"
listed = fail.read_text(encoding="utf-8").split() if fail.is_file() else []
if name in listed:
    print(f"[stub] 故意失败：{name}（夹具注入）", file=sys.stderr)
    sys.exit(3)
sys.exit(0)
"""

STUB_SH = """#!/bin/bash
name="$(basename "$0")"
echo "${name} $*" >> "$(dirname "$0")/../.stub-argv"
fail="$(dirname "$0")/../.stub-failures"
if [ -f "${fail}" ] && grep -qx "${name}" "${fail}" >/dev/null 2>&1; then
  echo "[stub] 故意失败：${name}（夹具注入）" >&2
  exit 3
fi
exit 0
"""
def build_fixture() -> pathlib.Path:
    """临时迷你仓：真 `verify-all.sh` 逐字节 + 每个被引用的 `Scripts/*.py|*.sh` 一个桩。"""
    root = pathlib.Path(tempfile.mkdtemp(prefix="verify-all-gate-"))
    scripts = root / "Scripts"
    scripts.mkdir(parents=True, exist_ok=True)
    (scripts / "verify-all.sh").write_bytes((REPO / TARGET).read_bytes())
    text = (REPO / TARGET).read_text(encoding="utf-8")
    referenced = sorted(set(re.findall(r"Scripts/[A-Za-z0-9_.\-]+\.(?:py|sh)", text)))
    for relative in referenced:
        if relative == TARGET:   # 真身就是它自己，绝不能被桩盖掉
            continue
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if relative.endswith(".py"):
            target.write_text(STUB_PY, encoding="utf-8")
        else:
            target.write_text(STUB_SH, encoding="utf-8")
            target.chmod(0o755)
    (root / ".build").mkdir(exist_ok=True)
    return root


def run_gate(root: pathlib.Path, failures: tuple[str, ...] = (),
             args: tuple[str, ...] = (), platform: str = "macos") -> tuple[int, str]:
    """跑夹具里的**真脚本**。failures = 要注入失败的桩名（= 让那一项红）。"""
    (root / ".stub-failures").write_text("\n".join(failures) + "\n", encoding="utf-8")
    (root / ".stub-argv").write_text("", encoding="utf-8")
    environment = os.environ.copy()
    environment["DOYAH_PLATFORM"] = platform
    completed = subprocess.run(
        ["bash", TARGET, *args], cwd=str(root), env=environment,
        capture_output=True, text=True, timeout=300,
    )
    return completed.returncode, completed.stdout + completed.stderr


def unexecuted_line(output: str) -> str:
    for line in output.splitlines():
        if "未执行**（本平台接下来本会跑的项）" in line:
            return line
    return ""
def main() -> int:
    before = hashlib.sha256((REPO / TARGET).read_bytes()).hexdigest()
    root = build_fixture()
    results: list[tuple[str, bool, str]] = []

    def case(name: str, ok: bool, detail: str = "") -> None:
        results.append((name, ok, detail))

    rc, out = run_gate(root)
    # 侧名词表（2026-11-02）：第 16 项把**平台名**传给认**演员名**的判据 ⇒ 契约所有者自己改三书被判越界
    # （与 pre-commit 的 `--mine hugehippo` 相反判定）。桩跑不出来的正是这一类「传进去的名字对不对」——
    # 所以桩把 argv 记进 `.stub-argv`，这里逐条核对：越界判据每次调用都必须带当前的演员名。
    argv_lines = [ln for ln in (root / ".stub-argv").read_text(encoding="utf-8").splitlines()
                  if ln.startswith("check-exclusive-sections.py ")]
    side_ok = bool(argv_lines) and all("--mine hugehippo" in ln for ln in argv_lines) \
        and not any("--mine macos" in ln for ln in argv_lines)
    case("例 1 绿对照（默认跑法）⇒ rc=0 + 「十九项全过」+ 第 16 项按**演员名**调用判据",
         rc == 0 and "✅ 验证闭环全部通过（十九项）" in out and "未执行" not in out and side_ok,
         f"rc={rc} side_ok={side_ok} argv={' | '.join(argv_lines[:3])}")

    # 注入点 = 第 3 项**现在真实存在**的那条 python 判据。
    # 2026-11-10：原注入点是 `check-effective-language.py`，它已整体搬进 swift test（`Tests/Localization…`），
    # 不再是闭环里的一项 ⇒ 桩根本不会被调用（`rc=0`、例 2/5/6 假红）。第 3 项现在只剩
    # `check-button-icon-only.py`（+ 它的 `--self-test`），项号与 `set -e` 中止位置一字未变，
    # 所以「点名第 3 项 + 未执行从第 4 项起」这两句断言的语义保持原样。
    rc, out = run_gate(root, failures=("check-button-icon-only.py",))
    line = unexecuted_line(out)
    case("例 2 默认跑法 · 第 3 项红 ⇒ 点名第 3 项 + **未执行**从第 4 项列到第 19 项",
         rc != 0 and "⛔ 第 3 项失败" in out and line.startswith("   **未执行**")
         and "第 4 项" in line and "第 19 项" in line and "全部通过" not in out,
         f"rc={rc} 未执行行={line!r}")

    rc, out = run_gate(root, failures=("verify-core.sh",))
    line = unexecuted_line(out)
    case("例 3 默认跑法 · 第 1 项红 ⇒ 未执行从第 2 项起、**不含第 1 项**",
         rc != 0 and "⛔ 第 1 项失败" in out and "第 2 项" in line and "第 1 项" not in line,
         f"rc={rc} 未执行行={line!r}")

    rc, out = run_gate(root, failures=("check-exclusive-sections.py",), platform="linux")
    line = unexecuted_line(out)
    case("例 4 linux · 第 16 项红 ⇒ 未执行 = 17/19，被跳过的第 1 / 11 项不进「未执行」",
         rc != 0 and "⛔ 第 16 项失败" in out and "第 17 项" in line and "第 19 项" in line
         and "第 1 项" not in line and "第 11 项" not in line and out.count("⏭ 跳过") == 2,
         f"rc={rc} 未执行行={line!r} 跳过行数={out.count('⏭ 跳过')}")

    rc, out = run_gate(root, failures=("check-button-icon-only.py",), args=("--keep-going",))
    case("例 5 --keep-going · 第 3 项红 ⇒ 第 4 项到第 19 项**真的跑了**（项块头在输出里）",
         rc != 0 and "==> 4/19" in out and "==> 19/19" in out
         and re.search(r"第\s+3 项\s+❌ 失败", out) is not None
         and re.search(r"第\s+4 项\s+✅ 通过", out) is not None
         and "❌ --keep-going 汇总" in out,
         f"rc={rc}")

    # 第二处红改用第 12 项（`check-shell-locale-safety.py`，整项只调一次）：
    # 第 3 项现在有两次调用（判据 + `--self-test`），配上第 16 项那两次（`--mine` + `--self-test`）
    # 会变成「4 处 / 2 项」；而这一例要验的是**处 ≠ 项 且两个项都被点名**（不许只报第一个），
    # 不是某个具体项号 ⇒ 取两个「一项一处」的项，`3 处 / 2 项` 的读数原样保留。
    rc, out = run_gate(root, failures=("check-button-icon-only.py", "check-shell-locale-safety.py"),
                       args=("--keep-going",))
    case("例 6 --keep-going · 两处红（第 3 项 + 第 12 项，两个不同的项）⇒ 汇总**两项都点名**（不许只报第一个）",
         rc != 0 and "失败 3 处 / 2 项" in out
         and "第 3 项（脚本第" in out and "第 12 项（脚本第" in out,
         f"rc={rc}")

    rc, out = run_gate(root, args=("--keep-going",))
    table_rows = re.findall(r"第\s+(\d+) 项\s+✅ 通过", out)
    case("例 7 --keep-going 绿 ⇒ 逐项判定表十九行全 ✅ + 收尾仍报「十九项全过」",
         rc == 0 and len(table_rows) == 19 and "项块 19 个" in out
         and "✅ 验证闭环全部通过（十九项）" in out,
         f"rc={rc} 表行数={len(table_rows)}")

    after = hashlib.sha256((REPO / TARGET).read_bytes()).hexdigest()
    case("例 8 真仓库 Scripts/verify-all.sh 逐字节未变（只在临时副本里做夹具）",
         before == after, f"{before[:12]} → {after[:12]}")

    passed = sum(1 for _, ok, _ in results if ok)
    for name, ok, detail in results:
        print(f"{'✅' if ok else '❌'} {name}" + (f"\n    {detail}" if detail and not ok else ""))
    print(f"\n{'✅' if passed == len(results) else '❌'} 夹具 {passed}/{len(results)} 例达到预期")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())


