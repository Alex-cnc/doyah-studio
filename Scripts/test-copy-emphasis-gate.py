#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`check-copy-emphasis.py` 的**负例验证**（队列 L-19）。

为什么要有它：那条门禁每轮都绿。而"一直是绿的"有两种可能 —— 口径守住了，或者它根本拦不住
（第 10 / 11 / 12 / 13 轮各吃过一次：假绿占位图、注释里的假设、只在读图时才看得出来的语言混排、
以及"有判据没人跑"）。本脚本把 9 种常见退化方式逐个写坏，断言门禁**真的退出码 1 并报出对的原因**。

**只在临时副本上改**：把仓库的 `Core/Localization.swift`、`App/Views/RowDetailPanel.swift`、
`Scripts/verify-all.sh`、`Scripts/copy-emphasis-exemptions.json` 拷到临时目录，在副本上写坏，
跑门禁时用 `--root` 指过去。**仓库本身一个字节都不动**（末例断言这一点）。

跑法（改门禁 / 改语言表 / 改渲染点之后各跑一次）：

    python3 Scripts/test-copy-emphasis-gate.py

退出码 0 = 全部负例达到预期。
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
CHECKER = "Scripts/check-copy-emphasis.py"

# 夹具要拷哪些文件（够门禁的五条判据用即可，不必拷整棵树）。
FIXTURE_FILES = (
    "Core/Localization.swift",
    "App/Views/RowDetailPanel.swift",
    "Scripts/verify-all.sh",
    "Scripts/copy-emphasis-exemptions.json",
)

results: list[tuple[str, bool, str]] = []


def build_root() -> pathlib.Path:
    root = pathlib.Path(tempfile.mkdtemp(prefix="doyah-copy-emphasis-"))
    for relative in FIXTURE_FILES:
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / relative, destination)
    return root


def run(root: pathlib.Path) -> tuple[int, str]:
    proc = subprocess.run(
        [sys.executable, CHECKER, "--root", str(root)],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def case(name: str, expect_code: int, expect_texts: list[str], mutate) -> None:
    root = build_root()
    try:
        mutate(root)
        code, output = run(root)
        missing = [text for text in expect_texts if text not in output]
        ok = code == expect_code and not missing
        detail = ""
        if not ok:
            detail = (
                f"退出码 {code}（期望 {expect_code}）"
                + (f" / 输出里没找到 {missing}" if missing else "")
                + f"\n    输出：{output.strip()[-500:]}"
            )
        results.append((name, ok, detail))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def put_marker_into(root: pathlib.Path, key: str, language: str, marker: str = "**") -> None:
    """在副本的语言表里，把某个键的某个语言槽位加上标记（模拟"有人又把强调写进文案"）。"""
    path = root / "Core/Localization.swift"
    text = path.read_text(encoding="utf-8")
    marker_at = text.index(f".{key}: [")
    slot = text.index(f".{language}: \"", marker_at)
    value_start = text.index('"', slot) + 1
    path.write_text(text[:value_start] + marker + text[value_start:], encoding="utf-8")


def main() -> int:
    signature_before = {
        relative: hashlib.sha256((REPO / relative).read_bytes()).hexdigest() for relative in FIXTURE_FILES
    }

    # 例 0：基线 —— 真仓库（未写坏）必须 exit 0，否则下面的负例没有意义。
    code, output = run(REPO)
    results.append(("例 0 基线：真仓库 exit 0", code == 0, "" if code == 0 else f"退出码 {code}\n{output[-400:]}"))

    # 例 1：中文槽位又出现 `**` ⇒ 判据 A 报红并指名键与行号。
    case("例 1 中文槽位加回 `**` 判红", 1, ["objectSearchHint", "markdown 强调标记"],
         lambda root: put_marker_into(root, "objectSearchHint", "simplifiedChinese"))

    # 例 2：英文槽位加回 `**` ⇒ 两个语言都要扫（只扫中文是漏判）。
    case("例 2 英文槽位加回 `**` 判红", 1, ["mcpApprovalHint", "（en）"],
         lambda root: put_marker_into(root, "mcpApprovalHint", "english"))

    # 例 3：渲染点又出现 `LocalizedStringKey` ⇒ 判据 B 报红并指名文件与行号。
    def add_localized_string_key(root: pathlib.Path) -> None:
        path = root / "App/Views/RowDetailPanel.swift"
        text = path.read_text(encoding="utf-8")
        path.write_text(text.replace("Text(L(.rowDetailNoSelection))",
                                    "Text(LocalizedStringKey(L(.rowDetailNoSelection)))", 1), encoding="utf-8")

    case("例 3 渲染点加回 `LocalizedStringKey` 判红", 1, ["RowDetailPanel.swift", "LocalizedStringKey"],
         add_localized_string_key)

    # 例 4：marker 例外登记的形态已不在那条文案里 ⇒ 条目陈旧（例外表不能只进不出）。
    def stale_marker_exemption(root: pathlib.Path) -> None:
        path = root / "Scripts/copy-emphasis-exemptions.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["markerExemptions"][0]["marker"] = "###"
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    case("例 4 marker 例外陈旧判红", 1, ["条目陈旧"], stale_marker_exemption)

    # 例 5：marker 例外指向语言表里没有的键 ⇒ 报红。
    def phantom_marker_exemption(root: pathlib.Path) -> None:
        path = root / "Scripts/copy-emphasis-exemptions.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["markerExemptions"][0]["key"] = "noSuchKeyInTheTable"
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    case("例 5 marker 例外指向不存在的键判红", 1, ["在语言表里不存在"], phantom_marker_exemption)

    # 例 6：语言表被掏空 / 正则失配 ⇒ 判据 C 报红（"零命中 = 通过"是假绿）。
    def empty_table(root: pathlib.Path) -> None:
        (root / "Core/Localization.swift").write_text("public enum AppLanguage {}\n", encoding="utf-8")

    case("例 6 语言表解析不到条目判红（防静默）", 1, ["下限 1500"], empty_table)

    # 例 7：闭环里没跑负例 ⇒ 判据 E 报红（有判据、没闭环）。
    def unwire_self_test(root: pathlib.Path) -> None:
        path = root / "Scripts/verify-all.sh"
        text = path.read_text(encoding="utf-8")
        path.write_text(text.replace("python3 Scripts/test-copy-emphasis-gate.py\n", ""), encoding="utf-8")

    case("例 7 闭环漏掉负例判红", 1, ["test-copy-emphasis-gate.py", "没接进闭环"], unwire_self_test)

    # 例 8：例外条目没写理由 ⇒ 报红（例外必须可解释，不能是"加一行就绕开"）。
    def reasonless_exemption(root: pathlib.Path) -> None:
        path = root / "Scripts/copy-emphasis-exemptions.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["markerExemptions"][0]["reason"] = "   "
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    case("例 8 例外条目没写理由判红", 1, ["没有写理由"], reasonless_exemption)

    # 例 9：末例 —— 真仓库那几份夹具逐字节未变（"只在临时副本上写坏"这句话本身要被验证）。
    signature_after = {
        relative: hashlib.sha256((REPO / relative).read_bytes()).hexdigest() for relative in FIXTURE_FILES
    }
    unchanged = signature_before == signature_after
    results.append((
        "例 9 真仓库夹具逐字节未变",
        unchanged,
        "" if unchanged else f"变了：{[k for k in signature_before if signature_before[k] != signature_after.get(k)]}",
    ))

    passed = sum(1 for _, ok, _ in results if ok)
    for name, ok, detail in results:
        print(f"{'✅' if ok else '❌'} {name}" + (f"\n    {detail}" if detail else ""))
    print(f"\n{'✅' if passed == len(results) else '❌'} 负例 {passed}/{len(results)}")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
