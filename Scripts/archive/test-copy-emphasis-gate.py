#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`check-copy-emphasis.py` 的**负例验证**（队列 L-19）。

为什么要有它：那条门禁每轮都绿。而"一直是绿的"有两种可能 —— 口径守住了，或者它根本拦不住
（第 10 / 11 / 12 / 13 轮各吃过一次：假绿占位图、注释里的假设、只在读图时才看得出来的语言混排、
以及"有判据没人跑"）。本脚本把 14 种常见退化方式逐个写坏，断言门禁**真的退出码 1 并报出对的原因**。

**只在临时副本上改**：把仓库的 `Core/Localization.swift`、`App/Views/RowDetailPanel.swift`、
`Scripts/verify-all.sh`、`Scripts/copy-emphasis-exemptions.json`、`Package.swift`、
`Tools/LicenseTool/main.swift` 拷到临时目录，在副本上写坏，
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
    # 判据 F 从这里派生面（生产 target 的 `path:` / `sources:`）；例 14 往这个文件里加生产 target。
    "Package.swift",
    # 面外的生产 root（`Package.swift` 的 `.executableTarget`）：例 12 往它里面放渲染点。
    "Tools/LicenseTool/main.swift",
)

# 判据 F 派生出的生产 root 里，夹具**没拷到**的那几根用空目录补齐 —— 判据 F 有一条
# 「面里的根不在盘 ⇒ 判红」，夹具只拷 6 份文件，不补就会让每个负例都先红一次（那会掩盖真判据）。
FACE_STUB_DIRS = (
    "CLI",
    "Platform/macOS",
    "Plugins/Notes/Sources",
    "Plugins/Notes/Views",
)

results: list[tuple[str, bool, str]] = []


def build_root() -> pathlib.Path:
    root = pathlib.Path(tempfile.mkdtemp(prefix="doyah-copy-emphasis-"))
    for relative in FIXTURE_FILES:
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / relative, destination)
    for relative in FACE_STUB_DIRS:
        (root / relative).mkdir(parents=True, exist_ok=True)
    return root


def run(root: pathlib.Path) -> tuple[int, str]:
    proc = subprocess.run(
        [sys.executable, CHECKER, "--root", str(root)],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def match_bracket(text: str, index: int) -> int:
    """`text[index]` 必须是 `[`，返回配平的 `]` 下标（跳过字符串字面量里的括号）。"""
    depth, i, in_string = 0, index, False
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "[":
                depth += 1
            elif ch == "]":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    raise AssertionError("括号未配平")


def reshape_entry(root: pathlib.Path, key: str, body: str) -> None:
    """把副本语言表里某个条目的 `[...]` 块换成另一种**合法写法**（顺序 / 空白 / 跨行）。"""
    path = root / "Core/Localization.swift"
    text = path.read_text(encoding="utf-8")
    start = text.index(f".{key}: ")
    open_index = text.index("[", start)
    close_index = match_bracket(text, open_index)
    path.write_text(text[: open_index + 1] + body + text[close_index:], encoding="utf-8")


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

    # 例 10：条目形状换个**合法写法**（顺序 / 空白 / 跨行）⇒ 仍然判红并点名（判定物不写死形状）。
    # 旧判定物把形状逐字钉死（`[` 紧贴 + `.simplifiedChinese` 在前 + `]` 紧贴 + 单行）⇒
    # 这三条整条不进判定物，既不计数也不判 A（真仓活体 33 条同型）。
    def reshape_three_ways(root: pathlib.Path) -> None:
        reshape_entry(root, "objectSearchHint",
                      '.english: "plain", .simplifiedChinese: "**加粗**文字"')
        reshape_entry(root, "mcpApprovalHint",
                      ' .simplifiedChinese: "**加粗**文字", .english: "plain" ')
        reshape_entry(root, "rowDetailNoSelection",
                      '\n            .simplifiedChinese: "**加粗**文字",\n'
                      '            .english: "plain"\n        ')

    case("例 10 形状换合法写法（顺序 / 空白 / 跨行）仍判红",
         1, ["objectSearchHint", "mcpApprovalHint", "rowDetailNoSelection"], reshape_three_ways)

    # 例 11：判定物是**代码面** —— 行尾注释 / 块注释 / 字符串字面量里的 `LocalizedStringKey`
    # 一律**不算渲染点**（旧实现只跳「整行注释」⇒ 这三条全假红）。
    def add_false_positive_sources(root: pathlib.Path) -> None:
        path = root / "App/Views/RowDetailPanel.swift"
        extra = (
            "\n// 探针：整行注释里提一次 LocalizedStringKey\n"
            "let probeTail = 1 // LocalizedStringKey\n"
            "/* LocalizedStringKey */\n"
            'let probeText = "LocalizedStringKey"\n'
        )
        path.write_text(path.read_text(encoding="utf-8") + extra, encoding="utf-8")

    case("例 11 注释与字符串字面量里的 `LocalizedStringKey` 不假红", 0, [],
         add_false_positive_sources)

    # 例 12：面完备性 —— 往**面外的生产 root** `Tools/LicenseTool`（`Package.swift:84` 的
    # `.executableTarget`）里放一个渲染点 ⇒ 判红（旧面写死四根 ⇒ rc=0、输出与基线逐字同）。
    def inject_into_license_tool(root: pathlib.Path) -> None:
        path = root / "Tools/LicenseTool/main.swift"
        path.write_text(path.read_text(encoding="utf-8")
                        + '\nlet probe = LocalizedStringKey("probe")\n', encoding="utf-8")

    case("例 12 面外生产 root（Tools/LicenseTool）里的渲染点判红",
         1, ["Tools/LicenseTool/main.swift"], inject_into_license_tool)

    # 例 13：判据 E 的判定物是**非注释行** —— 把两条调用注释掉 ⇒ 判红（旧实现只做全文子串 ⇒ 判绿）。
    def comment_out_wiring(root: pathlib.Path) -> None:
        path = root / "Scripts/verify-all.sh"
        text = path.read_text(encoding="utf-8")
        for command in ("python3 Scripts/check-copy-emphasis.py",
                        "python3 Scripts/test-copy-emphasis-gate.py"):
            text = text.replace(command + "\n", "# " + command + "\n")
        path.write_text(text, encoding="utf-8")

    case("例 13 两条调用被注释掉判红（判定物 = 非注释行）", 1, ["没接进闭环"], comment_out_wiring)

    # 例 14：判据 F —— `Package.swift` 里**新增生产 root** 而未纳入面 ⇒ 判红
    # （面不许写死：新增 root 必须同轮进面，否则往里写违规是静默通过）。
    def add_new_production_target(root: pathlib.Path) -> None:
        path = root / "Package.swift"
        text = path.read_text(encoding="utf-8")
        text = text.replace(
            "    targets: [",
            '    targets: [\n        .executableTarget(name: "ProbeTool", path: "Tools/ProbeTool"),',
            1,
        )
        path.write_text(text, encoding="utf-8")

    case("例 14 新增生产 root 未纳入面判红（判据 F）", 1, ["Tools/ProbeTool"],
         add_new_production_target)

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
