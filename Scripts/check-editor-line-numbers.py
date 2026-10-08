#!/usr/bin/env python3
"""编辑器行号列：**哪些编辑面有行号**（队列 `L-111`，2026-09-30 第 121 轮）。

## 这条判据为什么存在

「行号」看着是画出来的东西，但它一半是**口径**（一个逻辑行一个号 / 末尾行终止符多一个空行 /
位置单位 UTF-16 —— 在 `Core/CodeLines`，15 项单测），另一半是**画法**（列宽怎么量、数字怎么对齐、
画哪几行）。第 45 轮给工作区编辑器加了列（`L-64`）之后，数据库侧 SQL 编辑器**一直没有**，
于是同一屏里两个编辑面长着两个样子；而「补上另一个」这件事本身**很容易做错**：
再画一套的下场是同一个文件在两个编辑器里行号不一致、一处改口径另一处忘了跟。

所以这一项判三件事：

1. **没有第二个行号面的漏网之鱼** —— `App/` 里每个 `NSTextView` / `NSTextField` 子类都在台账里，
   要么登记「画行号」（并真的挂上绘制件），要么写明**为什么不该有行号**（台账双向对账：
   盘上多一个没登记的编辑面 ⇒ 红；台账里留着已经不在盘上的 ⇒ 红）。
2. **画行号的编辑面挂的是同一个件** —— 文件里必须同时出现 `LineNumberGutter`、
   `gutter.reload(`、`gutter.draw(in:`（挂法两件套缺一不可），且**不许自己算行起点**
   （`CodeLines.lineStarts(` 出现在别的文件里 ⇒ 红）。
3. **算法只有一个出处** —— `CodeLines.lineStarts(` 在 `App/` 里恰好一处、且落在绘制件里；
   `static func width(digits:` 也恰好一处；任何 `gutterWidth(digits:` 的定义行必须是**转发**
   （同行出现 `LineNumberGutter.width(digits:`），不许自己量一遍数字宽。

另外把**口径本身**钉在文档上（三书各一句锚点）—— 口径只活在代码里，下一个人还是会各画一套。

## 边界（如实登记）

· **扫描范围 = `App/**/*.swift`**（本端 macOS 实现）；SwiftUI 的 `TextField` / `TextEditor` 是值类型、
  不是 `NSTextView` 子类 ⇒ 不在本判据范围，台账里写明；
· **文件数不做等值对账**（只做下限）：另一侧在同一棵树上加视图文件是常事，等值对账会把红灯送给
  不相干的轮次；而**加一个不画行号的编辑面**才是真危险，那一条是等值对账；
· 文档锚点在文档不在盘上时**跳过并高声提示**（`Docs/*` 不在版本控制内，见 `check-doc-q-series.py` 同款口径）；
· 判不到「画出来的样子好不好看」—— 那归读图与人工点验（探针 `SQLLineNumberProbeTests` 判像素层面）。

## 负例

`--self-test`：夹具是一份**真的** `App/Views` + 三份文档的拷贝（临时目录），逐条注入 →
逐条判红 → 末例核对真仓库的台账与源文件**逐字节未变**。
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER_PATH = ROOT / "Scripts" / "editor-line-number-surfaces.json"

SCOPE = "App/**/*.swift"
COMPONENT = "App/Views/LineNumberGutter.swift"
COMPONENT_TYPE = "LineNumberGutter"

# `final class CodeTextView: NSTextView {` / `private final class ResultCellTextField: NSTextField {`
SUBCLASS_RE = re.compile(
    r"^\s*(?:public\s+|private\s+|internal\s+|final\s+)*class\s+([A-Za-z_]\w*)\s*:\s*(NSTextView|NSTextField)\b",
    re.M,
)

# 「挂法」三件：引到绘制件、按需重排、在 `draw` 里画。
HOOKS = {
    "component": COMPONENT_TYPE,
    "reload": "gutter.reload(",
    "draw": "gutter.draw(in:",
}

# 口径的文档锚点（三书各一句；文档不在盘上时跳过并提示）。
DOC_ANCHORS = {
    "Docs/概要设计.md": ["行号列不只工作区编辑器有"],
    "Docs/需求规范书.md": ["数据库侧 SQL 编辑器也有行号列"],
    "Docs/产品能力规划说明书.md": ["SQL 编辑器（数据库侧）行号列已落地"],
}


def app_files(root: Path) -> list[Path]:
    app = root / "App"
    if not app.is_dir():
        return []
    return sorted(path for path in app.rglob("*.swift") if path.is_file())


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def scan_subclasses(root: Path) -> list[dict]:
    """盘上真实的编辑面：`App/` 里每个 `NSTextView` / `NSTextField` 子类。"""
    found = []
    for path in app_files(root):
        for match in SUBCLASS_RE.finditer(read_text(path)):
            found.append(
                {
                    "kind": match.group(2),
                    "name": match.group(1),
                    "file": path.relative_to(root).as_posix(),
                }
            )
    return sorted(found, key=lambda item: (item["file"], item["name"]))


def registry_errors(root: Path, ledger: dict, surfaces: list[dict]) -> list[str]:
    """A：台账 ↔ 磁盘**双向**对账（未登记的新编辑面 ⇒ 红；台账陈旧 ⇒ 红）。"""
    errors = []
    on_disk = {(item["kind"], item["name"]): item for item in surfaces}
    registered = {}
    for entry in ledger["surfaces"]:
        key = (entry["kind"], entry["name"])
        registered[key] = entry
        path = root / entry["file"]
        if not path.is_file():
            errors.append(f"台账里的编辑面 `{entry['name']}` 指向的文件不在盘上：{entry['file']}")
            continue
        if key not in on_disk:
            errors.append(
                f"台账登记 `{entry['name']}`（{entry['kind']}）但 {entry['file']} 里找不到这个类 ⇒ 台账陈旧"
            )
        elif on_disk[key]["file"] != entry["file"]:
            errors.append(
                f"`{entry['name']}` 已经搬到 {on_disk[key]['file']}，台账还写着 {entry['file']}"
            )
    for key, item in on_disk.items():
        if key not in registered:
            errors.append(
                f"{item['file']} 里的 `{item['name']}`（{item['kind']}）**没有登记** —— "
                "新编辑面必须说明「画不画行号、为什么」"
            )
    return errors


def mounting_errors(root: Path, ledger: dict) -> list[str]:
    """B：要画行号的面必须**真的挂上**唯一绘制件，且不许自己算行起点。"""
    errors = []
    for entry in ledger["surfaces"]:
        if not entry.get("hasGutter"):
            continue
        path = root / entry["file"]
        if not path.is_file():
            continue
        text = read_text(path)
        for label, token in HOOKS.items():
            if token not in text:
                errors.append(
                    f"`{entry['name']}`（{entry['file']}）登记了「画行号」，但**挂法**里少了 {label}："
                    f"源码里找不到 `{token}`"
                )
        if "CodeLines.lineStarts(" in text:
            errors.append(
                f"`{entry['name']}`（{entry['file']}）自己算了行起点（`CodeLines.lineStarts(`）—— "
                "行号口径只许在绘制件里算一次"
            )
    return errors


def single_source_errors(root: Path, ledger: dict) -> list[str]:
    """C：算法唯一出处（行起点 / 列宽各一处，转发不许就地重算）。"""
    errors = []
    starts_files = []
    width_defs = []
    forward_defs = []
    component_type = None
    for path in app_files(root):
        rel = path.relative_to(root).as_posix()
        text = read_text(path)
        if "CodeLines.lineStarts(" in text:
            starts_files.append(rel)
        if "static func width(digits:" in text:
            width_defs.append(rel)
        if re.search(r"final\s+class\s+" + COMPONENT_TYPE + r"\b", text):
            component_type = rel
        for line in text.splitlines():
            if "func gutterWidth(digits:" in line and "LineNumberGutter.width(digits:" not in line:
                forward_defs.append((rel, line.strip()))

    expected = ledger["singleSource"]["lineStarts"]
    if starts_files != [expected]:
        errors.append(
            f"`CodeLines.lineStarts(` 在 `App/` 里必须只在 `{expected}` 出现一处，实测 {starts_files}"
        )
    expected_width = ledger["singleSource"]["widthAlgorithm"]
    if width_defs != [expected_width]:
        errors.append(
            f"`static func width(digits:`（列宽算法）在 `App/` 里必须只在 `{expected_width}` 出现一处，"
            f"实测 {width_defs}"
        )
    if component_type != COMPONENT:
        errors.append(f"绘制件 `{COMPONENT_TYPE}` 不在 `{COMPONENT}`（实测 {component_type}）")
    for rel, line in forward_defs:
        errors.append(f"{rel} 里的 `gutterWidth(digits:)` 不是转发，而是就地重算：`{line}`")
    return errors


def policy_errors(ledger: dict) -> list[str]:
    """D：口径本身要写在台账里（不许空话），「不画」的必须给理由。"""
    errors = []
    for entry in ledger["surfaces"]:
        if entry.get("hasGutter"):
            if not entry.get("registry", "").strip():
                errors.append(f"`{entry['name']}` 登记了「画行号」但没写它属哪条需求（registry 空）")
        else:
            if len(entry.get("reason", "").strip()) < 12:
                errors.append(f"`{entry['name']}` 登记为「不画行号」但理由没写清（少于 12 字）")
    if len(ledger.get("policy", "").strip()) < 12:
        errors.append("台账的 `policy`（这条口径本身）没写清")
    return errors


def doc_errors(docs_root: Path | None, anchors: dict) -> list[str]:
    """E：口径的三书锚点（文档不在盘上 ⇒ 跳过并高声提示，不算红）。"""
    errors = []
    if docs_root is None:
        return errors
    for rel, phrases in anchors.items():
        path = docs_root / rel
        if not path.is_file():
            continue
        text = read_text(path)
        for phrase in phrases:
            if phrase not in text:
                errors.append(f"{rel} 里找不到口径锚点「{phrase}」—— 口径只活在代码里，下一个人还会各画一套")
    return errors


def floor_errors(root: Path, ledger: dict, surfaces: list[dict]) -> list[str]:
    """F：空跑防护（扫描路径写坏 / 台账被掏空时不许静默通过）。"""
    errors = []
    files = app_files(root)
    if len(files) < ledger["scanFloor"]:
        errors.append(f"扫到的 App 源文件只有 {len(files)} 个（下限 {ledger['scanFloor']}）⇒ 扫描路径可能写坏了")
    if len(surfaces) < ledger["subclassFloor"]:
        errors.append(f"扫到的编辑面只有 {len(surfaces)} 个（下限 {ledger['subclassFloor']}）")
    if len(ledger["surfaces"]) < ledger["subclassFloor"]:
        errors.append(f"台账里的编辑面只有 {len(ledger['surfaces'])} 条（下限 {ledger['subclassFloor']}）")
    if not (root / COMPONENT).is_file():
        errors.append(f"绘制件文件不在盘上：{COMPONENT}")
    return errors


def run_checks(root: Path, ledger: dict, docs_root: Path | None, anchors: dict = DOC_ANCHORS) -> list[str]:
    surfaces = scan_subclasses(root)
    return (
        registry_errors(root, ledger, surfaces)
        + mounting_errors(root, ledger)
        + single_source_errors(root, ledger)
        + policy_errors(ledger)
        + doc_errors(docs_root, anchors)
        + floor_errors(root, ledger, surfaces)
    )


def load_ledger() -> dict:
    return json.loads(LEDGER_PATH.read_text(encoding="utf-8"))


def docs_root_or_none(root: Path) -> Path | None:
    return root if (root / "Docs").is_dir() else None


def describe(ledger: dict) -> None:
    print(f"📐 编辑面的行号列台账：{LEDGER_PATH.relative_to(ROOT)}")
    print(f"   口径：{ledger['policy']}")
    for entry in ledger["surfaces"]:
        flag = "有行号" if entry.get("hasGutter") else "不画（理由已写）"
        print(f"   · {entry['kind']} {entry['name']}（{entry['editor']}）：{flag}")
    surfaces = scan_subclasses(ROOT)
    print(
        f"   扫描范围 {SCOPE}：{len(app_files(ROOT))} 份源文件（下限 {ledger['scanFloor']}）"
        f" / {len(surfaces)} 个编辑面（下限 {ledger['subclassFloor']}）"
    )
    print(f"   唯一出处：行起点与列宽算法都只许在 {COMPONENT}")
    missing_docs = [rel for rel in DOC_ANCHORS if not (ROOT / rel).is_file()]
    if missing_docs:
        print(f"   ⚠️ 文档不在盘上 ⇒ 锚点这一组跳过（跳过 ≠ 通过）：{'、'.join(missing_docs)}")
    else:
        print(f"   文档锚点：{len(DOC_ANCHORS)} 份")


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    ledger = load_ledger()
    describe(ledger)
    errors = run_checks(ROOT, ledger, docs_root_or_none(ROOT))

    if errors:
        for item in errors:
            print(f"✗ {item}")
        return 1
    print("✓ 编辑面台账自洽：每个编辑面都说明了画不画行号、要画的都挂着同一个绘制件、算法各只有一处出处")
    return 0


FIXTURE_SOURCES = [
    "App/Views/LineNumberGutter.swift",
    "App/Views/CodeEditorView.swift",
    "App/Views/SQLEditorView.swift",
    # 台账里**不画行号**的那一个（`ResultCellTextField` 在结果表网格里）也要进夹具 ——
    # 少了它，「原样应当绿」那一条会红在「台账指向的文件不在盘上」（第 121 轮自检实测）。
    "App/Views/ResultGrid.swift",
    # 同理：2026-10-03 台账补登了标题栏主搜索框（`FR-EDIT-37`）⇒ 它也得进夹具，
    # 否则「原样应当绿（夹具与真仓库同源）」会因为台账指向的文件不在夹具里而红。
    "App/Views/TitleBarSearchField.swift",
    # 同理（2026-10-08）：台账补登笔记面只读预览正文（`PreviewTextView`，N2-3a）⇒ 它也得进夹具，
    # 否则「原样应当绿（夹具与真仓库同源）」会因为台账指向的文件不在夹具里而红。
    "App/Views/NotePreviewBody.swift",
]
FIXTURE_DOCS = list(DOC_ANCHORS)


def build_fixture(directory: Path) -> dict:
    """夹具 = **真的**三份源文件 + 三份文档的拷贝；台账是深拷贝（只把空跑下限调小以适配小夹具）。"""
    for rel in FIXTURE_SOURCES:
        target = directory / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, target)
    for rel in FIXTURE_DOCS:
        source = ROOT / rel
        if not source.is_file():
            continue
        target = directory / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    ledger = load_ledger()
    # 夹具只有 3 份源文件；空跑下限按夹具调小（真仓库那一组由 121 轮实测的 74 份兜着）。
    ledger["scanFloor"] = 2
    ledger["subclassFloor"] = 2
    return ledger


def self_test() -> int:
    digest_before = {
        rel: hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() for rel in FIXTURE_SOURCES
    }
    digest_ledger_before = hashlib.sha256(LEDGER_PATH.read_bytes()).hexdigest()

    def with_fixture(mutate):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            ledger = build_fixture(directory)
            if mutate:
                ledger = mutate(directory, ledger) or ledger
            return run_checks(directory, ledger, docs_root_or_none(directory))

    def edit(directory: Path, rel: str, old: str, new: str) -> None:
        path = directory / rel
        text = read_text(path)
        assert old in text, f"夹具锚点失效：{rel} 里找不到 {old!r}"
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    expectations: list[tuple[str, bool, object]] = []

    expectations.append(("原样应当绿（夹具与真仓库同源）", False, None))

    def drop_surface(directory, ledger):
        ledger["surfaces"] = [e for e in ledger["surfaces"] if e["name"] != "SQLTextView"]
        return ledger

    expectations.append(("台账漏登一个编辑面", True, drop_surface))

    def ghost_surface(directory, ledger):
        ledger["surfaces"].append(
            {
                "editor": "幽灵编辑面",
                "kind": "NSTextView",
                "name": "GhostTextView",
                "file": "App/Views/SQLEditorView.swift",
                "hasGutter": True,
                "registry": "FR-EDIT-36",
                "reason": "",
            }
        )
        return ledger

    expectations.append(("台账里留着盘上没有的编辑面", True, ghost_surface))

    def remove_draw(directory, ledger):
        edit(directory, "App/Views/SQLEditorView.swift", "gutter.draw(in: dirtyRect, of: self)", "")
        return ledger

    expectations.append(("要画行号却没挂上绘制件的 draw 钩子", True, remove_draw))

    def own_line_starts(directory, ledger):
        edit(
            directory,
            "App/Views/SQLEditorView.swift",
            "    func reloadLineNumbers() {",
            "    func reloadLineNumbers() {\n        _ = CodeLines.lineStarts(in: string)",
        )
        return ledger

    expectations.append(("编辑面自己算行起点（第二套行号逻辑）", True, own_line_starts))

    def inline_width(directory, ledger):
        edit(
            directory,
            "App/Views/CodeEditorView.swift",
            "    static func gutterWidth(digits: Int) -> CGFloat { LineNumberGutter.width(digits: digits) }",
            "    static func gutterWidth(digits: Int) -> CGFloat {\n"
            "        let digitWidth = (\"0\" as NSString).size(withAttributes: [.font: lineNumberFont]).width\n"
            "        return CGFloat(digits) * digitWidth\n"
            "    }",
        )
        return ledger

    expectations.append(("列宽不转发、就地重算一遍", True, inline_width))

    def second_width_algorithm(directory, ledger):
        edit(
            directory,
            "App/Views/SQLEditorView.swift",
            "final class SQLTextView: NSTextView {",
            "final class SQLTextView: NSTextView {\n"
            "    static func width(digits: Int) -> CGFloat { CGFloat(digits) * 7 }",
        )
        return ledger

    expectations.append(("第二处列宽算法", True, second_width_algorithm))

    def empty_reason(directory, ledger):
        for entry in ledger["surfaces"]:
            if entry["name"] == "SQLTextView":
                entry["hasGutter"] = False
                entry["reason"] = ""
        return ledger

    expectations.append(("登记「不画行号」却没写理由", True, empty_reason))

    def drop_anchor(directory, ledger):
        edit(directory, "Docs/概要设计.md", "行号列不只工作区编辑器有", "行号列")
        return ledger

    expectations.append(("文档里的口径锚点被删", True, drop_anchor))

    def empty_app(directory, ledger):
        shutil.rmtree(directory / "App")
        return ledger

    expectations.append(("App 目录被掏空（空跑）", True, empty_app))

    failures = 0
    for name, should_be_red, mutate in expectations:
        errors = with_fixture(mutate)
        got_red = bool(errors)
        if got_red == should_be_red:
            detail = f"（{len(errors)} 处）" if got_red else ""
            print(f"  · {name}：{'判红 ✓' if should_be_red else '绿 ✓'}{detail}")
        else:
            failures += 1
            print(f"  ✗ {name}：期望{'判红' if should_be_red else '绿'}，实际{'红' if got_red else '绿'}")
            for item in errors[:3]:
                print(f"      {item}")

    for rel, digest in digest_before.items():
        now = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
        if now != digest:
            failures += 1
            print(f"  ✗ 自检改动了真仓库：{rel}")
    if hashlib.sha256(LEDGER_PATH.read_bytes()).hexdigest() != digest_ledger_before:
        failures += 1
        print("  ✗ 自检改动了真台账")

    print(f"自检：{len(expectations)} 例，{len(expectations) - failures} 达标，{failures} 失败")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
