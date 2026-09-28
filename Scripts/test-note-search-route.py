#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""负例：`Scripts/check-note-search-route.py`（界面检索口径门禁）**红得出来吗**。

**为什么单开一个脚本**：门禁绿着只能说明「现在没违规」，**不能**说明它看得见违规 ——
本工程已经栽过三次（L-04「失败只记进没人读的变量」、L-05「断言被删也照绿」、
第 14 项「删掉两处出口里的一处仍能顶数」），所以每条新门禁都配一组负例：
**写坏 → 必须报红 → 点名哪一处**。

这条门禁尤其需要负例：真仓库现在**每一条路都配了文案**、**界面只有一处检索调用**，
「绿」这个结果本身分不清「真的都对」还是「扫了个寂寞」。

**做法**：不改真仓库的文件，把**必要的那几个文件**拷进临时目录，在副本上写坏、
把门禁指过去（`--root`）。跑完断言真仓库一个字节没动。

用法：`python3 Scripts/test-note-search-route.py`
"""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = "Scripts/check-note-search-route.py"
LEDGER = "Scripts/note-search-route.json"

# 副本需要的最小文件集（门禁会读：路线枚举 / 映射 / 语言表 / 界面状态 / 视图目录 / 台账）
TREE_FILES = [
    "Core/NoteStorage/NoteDatabase.swift",
    "Core/NoteStorage/NoteSearchDisclosure.swift",
    "Core/Localization.swift",
    "App/AppState.swift",
    "App/Views/NotesPanel.swift",
    "Tests/NoteTests.swift",
    GATE,
    LEDGER,
]

passed: list[str] = []
failed: list[str] = []


def record(ok: bool, label: str, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  {'✅' if ok else '❌'} {label}" + (f"  —— {detail}" if detail and not ok else ""))


def make_tree() -> Path:
    tree = Path(tempfile.mkdtemp(prefix="doyah-note-search-"))
    for rel in TREE_FILES:
        destination = tree / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, destination)
    return tree


def run(tree: Path) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, GATE, "--root", str(tree)],
        cwd=tree,
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def edit(tree: Path, rel: str, old: str, new: str, count: int = 1) -> None:
    path = tree / rel
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具前提不成立：{rel} 里找不到 {old!r}"
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    print("负例：界面检索口径门禁（Scripts/check-note-search-route.py）")
    before = {rel: digest(ROOT / rel) for rel in TREE_FILES}

    # 0) 基线：未改动的副本必须**绿**（否则下面每一条「红」都没有意义）
    tree = make_tree()
    code, output = run(tree)
    record(code == 0, "基线（未改动的副本）判绿", output.strip()[-400:])

    # 1) 生产点消失（界面退回内存过滤的形状）
    tree = make_tree()
    edit(tree, "App/AppState.swift", "let result = try await NoteLibrary.defaultLibrary().search(trimmed)", "let result = NoteDatabase.SearchResult(route: .substring, notes: [])")
    code, output = run(tree)
    record(code != 0 and "命中 0 处" in output, "界面检索生产点被拿掉 ⇒ 判红", output.strip()[-300:])

    # 2) 多出第二条检索路
    tree = make_tree()
    edit(
        tree,
        "App/AppState.swift",
        "func searchNotes() async {",
        "func searchAgain() async { _ = try? await NoteLibrary.defaultLibrary().search(notesQuery) }\n\n    func searchNotes() async {",
    )
    code, output = run(tree)
    record(code != 0 and "命中" in output, "出现第二条检索路 ⇒ 判红", output.strip()[-300:])

    # 3) 视图自己过滤（点名 文件:行号）
    tree = make_tree()
    edit(
        tree,
        "App/Views/NotesPanel.swift",
        "        .padding(.vertical, Spacing.s)",
        "        .padding(.vertical, Spacing.s)\n        .onChange(of: appState.notesQuery) { _, _ in _ = NoteSearch.match(appState.notes, query: appState.notesQuery) }",
    )
    code, output = run(tree)
    record(
        code != 0 and "App/Views/NotesPanel.swift:" in output and "内存过滤" in output,
        "视图里出现内存过滤 ⇒ 判红并点名行号",
        output.strip()[-300:],
    )

    # 4) 实现与台账不一致（把子串路的交代偷偷改成「不必说」）
    tree = make_tree()
    edit(tree, "Core/NoteStorage/NoteSearchDisclosure.swift", "return .noteSearchSubstring", "return nil")
    code, output = run(tree)
    record(code != 0 and "两边必须逐条相等" in output, "实现改了、台账没跟 ⇒ 判红", output.strip()[-300:])

    # 5) 新增一条路线却没登记（穷尽性被破坏时也要红）
    tree = make_tree()
    edit(
        tree,
        "Core/NoteStorage/NoteDatabase.swift",
        "            case substring",
        "            case substring\n            /// 夹具：新增一条没登记的路线\n            case scratchRoute",
    )
    code, output = run(tree)
    record(code != 0 and "scratchRoute" in output, "新增路线没登记处置 ⇒ 判红", output.strip()[-300:])

    # 6) 语言表里缺一条中文（键在、文案不在）
    tree = make_tree()
    edit(
        tree,
        "Core/Localization.swift",
        ".noteSearchSubstring: [.simplifiedChinese: \"这次是子串匹配（全文检索需要 3 个字以上，或这一次没命中）\", .english:",
        ".noteSearchSubstring: [.english:",
    )
    code, output = run(tree)
    record(code != 0 and "simplifiedChinese" in output, "语言表缺中文 ⇒ 判红", output.strip()[-300:])

    # 7) 失败那一句成了死键（语言表里有、没人引用）
    tree = make_tree()
    edit(tree, "App/AppState.swift", "return L(.noteSearchUnavailable, failure)", "return failure")
    code, output = run(tree)
    record(code != 0 and "死键" in output, "「检索没跑成」没人引用 ⇒ 判红（死键）", output.strip()[-300:])

    # 8) 空跑防护：路线枚举一条都解析不到
    tree = make_tree()
    edit(tree, "Core/NoteStorage/NoteDatabase.swift", "public enum Route: String, Equatable, Sendable {", "public enum RouteX: String, Equatable, Sendable {")
    code, output = run(tree)
    record(code != 0 and "空跑不许通过" in output, "解析不到 `Route` 枚举 ⇒ 判红（空跑不许通过）", output.strip()[-300:])

    # 9) 空跑防护：台账 routes 清空
    tree = make_tree()
    ledger_path = tree / LEDGER
    payload = json.loads(ledger_path.read_text(encoding="utf-8"))
    payload["routes"] = []
    ledger_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    code, output = run(tree)
    record(code != 0 and "空跑不许通过" in output, "台账 `routes` 清空 ⇒ 判红（空跑不许通过）", output.strip()[-300:])

    # 10) 主仓库一个字节没动
    after = {rel: digest(ROOT / rel) for rel in TREE_FILES}
    record(before == after, "跑完核对真仓库逐字节未变", "被改动的文件：" + "、".join(k for k in before if before[k] != after[k]))

    print(f"\n结果：{len(passed)} 通过 / {len(failed)} 未达预期")
    if failed:
        for label in failed:
            print(f"  ❌ {label}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
