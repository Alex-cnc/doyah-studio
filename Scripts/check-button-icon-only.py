#!/usr/bin/env python3
"""按钮图标化门禁（人类主人令 2026-10-13 · 信箱 `T-20261013-042`）。

口径（前门按人类主人 2026-10-13 18:2x 裁定 ㈠）
--------------------------------------------
- **a 类「水平排列的按钮」**（工具条 / 顶带 / 左栏 / 弹层动作条 / 表单动作行 / 空态操作）：**一律图标**，
  不许以中/英文文案作可见形态 —— 这是被文案宽度挤压的那批。
- **b 类「下拉菜单 / 上下文菜单的菜单项」**：**保留文字**（菜单是竖列表、横向空间充足）⇒ **只盘不改**。
- **非按钮**（纯文本标签 / 标题 / 说明 / 占位符 / 状态提示）：本令不涉。

判据
----
A. **盘点面不抽样**：本侧 UI 面 `App/**` + `Plugins/Notes/Views/**` + `Platform/macOS/**` 的**全部** `.swift`。
B. **逐处分类**（判定物**先剥注释与字符串**）：`Button(` 的标签形态 ——
   ① 首个实参是标签（字符串 / `L(.key)` / `Text(` / `xxx.title` …）⇒ **a 类**；
   ② 首个实参是 `Image(systemName:)`，或**标签闭包**里只有 `Image(systemName:)` 且无 `Text(` / `Label(` / 字符串 ⇒ 图标（合格）；
   ③ 落在**菜单块**（`Menu {` / `Menu(` / `CommandMenu(` / `.contextMenu {` / `.menu {` / `commands {` / `MenuBarExtra(`）
      里 ⇒ **b 类**（保留文字）；
   ④ 判不出的登记成**存疑**（不许静默放过）。
   `Toggle(`（带字符的切换式按钮，本令范围第 3 条）与 `Button` 同判；`Picker` 是**非按钮控件** ⇒ 只列进附录（归口待裁）。
C. **断言**：a 类命中数 ≤ 基线 `targetTextButtons`（本令的目标 = **0**）⇒ 改前红、改完绿；
   基线里同时留 `beforeTextButtons`（改前读数）做**成对留痕**。
D. **空跑防护**：UI 文件数下限 + 面与 `Package.swift` 对账（面目录不在盘上 ⇒ 红）。
E. `--inventory` 打印逐条清单（Markdown：界面 / 文件:行 / 控件 / 现行字符 / 拟用图标 / 处置）——
   这份清单是 `T-20261013-042` 第一段的交付物，落点 `Scripts/button-icon-inventory.md`。

判据自己的证据：`--self-test` **23 例**（红/绿成对：文字按钮红 / 图标按钮绿 / 菜单项绿 / 存疑如实登记 / 空串豁免 …）。
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

BASELINE = "Scripts/button-icon-baseline.json"
UI_DIRS = ("App", "Plugins/Notes/Views", "Platform/macOS")

# 菜单构造件台账（路径 → 理由）：这些文件里产出的 `Button` **全是菜单项**（b 类 · 保留文字），
# 哪怕文件里没有字面量 `Menu {` 块（它们由调用处以 `.contextMenu { … }` 挂上去）。
# 规矩：UI 面里文件名带 `Menu` 的 `.swift` 必须在下面登记，否则判红（新增菜单件不许静默溜过）。
MENU_FILES = {
    "App/Views/ObjectTreeContextMenu.swift": "对象树右键菜单项构造件 —— 本文件产出的都是菜单项（`.contextMenu` 挂在树上）",
    "App/Views/ObjectTreeAppKitMenu.swift": "AppKit 菜单构造件（NSMenu 那一侧）—— 同样是菜单项，不是水平按钮",
    "App/MainMenuLocalizer.swift": "菜单**标题**本地化器（按语言改写菜单项 title）—— 不产出任何 `Button`（登记在册即可）",
}
MIN_FILES = 120          # 实测 127 份 .swift（App + Plugins/Notes/Views + Platform/macOS）

BUTTON = re.compile(r"\b(Button|Toggle)\s*\(")
MENU_OPEN = re.compile(r"(?:\bMenu\s*[({]|\bCommandMenu\s*\(|\bCommandGroup\b|\bMenuBarExtra\s*\("
                       r"|\.contextMenu\b|\.menu\b|\bcontextMenu\b|\bcommands\b)")
ICON_ONLY = re.compile(r"\bImage\s*\(\s*systemName")
# 图标助手：`toolbarIcon(` / `ToolbarIcon(` / `transactionIcon(` 这类**名字里带 icon** 的自定义视图
ICON_HELPER = re.compile(r"\b(?:[A-Za-z_][A-Za-z0-9_]*[Ii]con|Icon[A-Za-z0-9_]*)\b")
LABELS_HIDDEN = re.compile(r"\.labelsHidden\s*\(")
STRINGY = re.compile(r'(?:"|L\s*\(|\bText\s*\(|\bLabel\s*\(|\bLocalizedStringKey\b|\bString\s*\()')
PICKER = re.compile(r"\bPicker\s*\(")
ARG_LABELED = re.compile(r"\s*[A-Za-z_][A-Za-z0-9_]*\s*:")

RAW_HASH = re.compile(r"#+")

def strip_noncode(text: str) -> str:
    """把注释与字符串字面量换成空格（**保留换行、长度与行号**）：判定物只看代码。

    覆盖：行尾 / 整行 `//`、块注释 `/* … */`（Swift 允许**嵌套**）、普通字符串 `"…"`、
    多行字符串 `\"\"\"…\"\"\"`、原始字符串 `#"…"#` / `#\"\"\"…\"\"\"#`。
    这是 2026-10-13 升级的核心（㈠㈡）：旧版只认「行首 `//` / `*` / `/*`」⇒
    行尾注释与块注释中间行里的字面量 / 示例代码都当真命中（假阳三连）。
    """
    characters = list(text)
    length = len(text)

    def blank(start: int, stop: int) -> None:
        for index in range(start, min(stop, length)):
            if characters[index] != "\n":
                characters[index] = " "

    index = 0
    while index < length:
        if text.startswith("//", index):
            stop = text.find("\n", index)
            stop = length if stop < 0 else stop
            blank(index, stop)
            index = stop
            continue
        if text.startswith("/*", index):
            depth = 1
            cursor = index + 2
            while cursor < length and depth > 0:
                if text.startswith("/*", cursor):
                    depth += 1
                    cursor += 2
                elif text.startswith("*/", cursor):
                    depth -= 1
                    cursor += 2
                else:
                    cursor += 1
            blank(index, cursor)
            index = cursor
            continue
        raw = RAW_HASH.match(text, index)
        if raw and index + raw.end() < length and text[index + raw.end()] == '"':
            opening = index + raw.end()
            hashes = raw.group(0)
            if text.startswith('"""', opening):
                stop = text.find('"""' + hashes, opening + 3)
                stop = length if stop < 0 else stop + 3 + len(hashes)
            else:
                stop = text.find('"' + hashes, opening + 1)
                stop = length if stop < 0 else stop + 1 + len(hashes)
            blank(index, stop)
            index = stop
            continue
        if text.startswith('"""', index):
            stop = text.find('"""', index + 3)
            stop = length if stop < 0 else stop + 3
            blank(index, stop)
            index = stop
            continue
        if text[index] == '"':
            cursor = index + 1
            while cursor < length:
                if text[cursor] == "\\":
                    cursor += 2
                    continue
                if text[cursor] == '"':
                    cursor += 1
                    break
                if text[cursor] == "\n":   # 普通字符串不跨行（容错：到行尾为止）
                    break
                cursor += 1
            blank(index, cursor)
            index = cursor
            continue
        index += 1
    return "".join(characters)

# ---------------------------------------------------------------- 通用

def match_paren(code: str, open_index: int) -> int | None:
    depth = 0
    for index in range(open_index, len(code)):
        if code[index] == "(":
            depth += 1
        elif code[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


def balanced_block(code: str, open_index: int) -> str:
    """从 `{` 起取配对块（返回**块内**文本，不含两端花括号）。"""
    depth = 0
    for index in range(open_index, len(code)):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if depth == 0:
                return code[open_index + 1:index]
    return code[open_index + 1:]


def split_args(args: str) -> list[str]:
    parts: list[str] = []
    depth, current = 0, []
    for char in args:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append("".join(current))
            current = []
            continue
        current.append(char)
    parts.append("".join(current))
    return parts


def _kind_from_args(label: str) -> dict:
    text = " ".join(label.split())
    if ICON_ONLY.search(label) and not STRINGY.search(label):
        return {"kind": "icon", "detail": text[:70]}
    return {"kind": "text", "detail": text[:70]}


def _kind_from_blob(blob: str) -> dict:
    text = " ".join(blob.split())
    if not text:
        return {"kind": "unclear", "detail": "（空标签）"}
    if ICON_ONLY.search(blob) and not STRINGY.search(blob):
        return {"kind": "icon", "detail": text[:70]}
    if ICON_HELPER.search(blob) and not STRINGY.search(blob):
        return {"kind": "icon", "detail": text[:70]}
    if STRINGY.search(blob):
        return {"kind": "text", "detail": text[:70]}
    return {"kind": "unclear", "detail": text[:70]}


def classify(code: str, raw: str, start: int) -> dict:
    """判定一处 `Button` / `Toggle` 的标签形态（start = 控件名起点）。"""
    head = re.match(r"\b(?:Button|Toggle)\s*", code[start:])
    after = code[start + head.end():]
    if raw[start + head.end():start + head.end() + 8].lstrip().startswith('(""'):
        return {"kind": "empty", "detail": "（空串标签：无可见文案）"}
    if after.startswith("("):
        open_index = start + head.end()
        close = match_paren(code, open_index)
        args = code[open_index + 1:close] if close is not None else ""
        tail = code[(close + 1) if close is not None else open_index:]
        if LABELS_HIDDEN.search(tail[:200]):
            return {"kind": "empty", "detail": "（`.labelsHidden()`：标签不可见）"}
        label = split_args(args)[0].strip() if args.strip() else ""
        if label and not ARG_LABELED.match(label):
            return _kind_from_args(label)
        explicit = re.search(r"\blabel\s*:\s*\{", args)
        if explicit:
            return _kind_from_blob(balanced_block(args, args.index("{", explicit.start())))
        brace = tail.find("{")
        if brace < 0:
            return {"kind": "unclear", "detail": "（找不到标签块）"}
        body = balanced_block(tail, brace)
        # `Button(role: …) { 动作 } label: { 标签 }`：动作块之后才是标签
        rest = tail[brace + len(body) + 2:]
        later = re.match(r"\s*label\s*:\s*\{", rest)
        if later:
            return _kind_from_blob(balanced_block(rest, later.end() - 1))
        return _kind_from_blob(body)
    brace = code.find("{", start)
    if brace < 0:
        return {"kind": "unclear", "detail": "（找不到块）"}
    body = balanced_block(code, brace)
    rest_start = brace + len(body) + 2
    explicit = re.match(r"\s*label\s*:\s*\{", code[rest_start:])
    if explicit:
        return _kind_from_blob(balanced_block(code, rest_start + explicit.end() - 1))
    return _kind_from_blob(body)


CONTROL = re.compile(r"\b(Button|Toggle)\s*(?=[({])")


def scan_file(root: pathlib.Path, relative: str) -> dict:
    raw = (root / relative).read_text(encoding="utf-8", errors="ignore")
    code = strip_noncode(raw)   # 保长度 ⇒ 需要看原文（如空串标签）时按同偏移查 raw
    frames: list[str] = ["menu"] if relative in MENU_FILES else []
    rows: list[dict] = []
    pickers: list[dict] = []
    index, length = 0, len(code)
    while index < length:
        char = code[index]
        if char == "{":
            window = code[max(0, index - 240):index + 1]
            head, near_to = window[:-1], window[-1:]
            cut = max(head.rfind("{"), head.rfind("}"), head.rfind(";"))
            frames.append("menu" if MENU_OPEN.search(head[cut + 1:] + near_to) else "other")
            index += 1
            continue
        if char == "}":
            if frames:
                frames.pop()
            index += 1
            continue
        control = CONTROL.match(code, index)
        if control:
            info = classify(code, raw, index)
            info["control"] = control.group(1)
            info["line"] = code.count("\n", 0, index) + 1
            info["in_menu"] = "menu" in frames
            rows.append(info)
            index = control.end()
            continue
        picker = PICKER.match(code, index)
        if picker:
            open_index = index + len(picker.group(0)) - 1
            close = match_paren(code, open_index)
            label = split_args(code[open_index + 1:close or open_index])[0].strip()
            pickers.append({"line": code.count("\n", 0, index) + 1,
                            "text": " ".join(label.split())[:70]})
            index = picker.end()
            continue
        index += 1
    for row in rows:
        row["path"] = relative
    for row in pickers:
        row["path"] = relative
    return {"path": relative, "rows": rows, "pickers": pickers}


# ---------------------------------------------------------------- 面 / 统计 / 基线

def ui_files(root: pathlib.Path) -> tuple[list[str], list[str]]:
    files: list[str] = []
    missing: list[str] = []
    for directory in UI_DIRS:
        base = root / directory
        if not base.is_dir():
            missing.append(directory)
            continue
        for path in sorted(base.rglob("*.swift")):
            files.append(path.relative_to(root).as_posix())
    return files, missing


class Issue:
    def __init__(self, where: str, reason: str):
        self.where = where
        self.reason = reason

    def __str__(self) -> str:
        return f"{self.where}: {self.reason}"


def tally(results: list[dict]) -> dict:
    """把逐文件结果分桶：a=水平按钮（必改）· b=菜单项（保留）· icon=已合格 · pending=存疑 · empty=空串豁免。"""
    out = {"a": [], "b": [], "icon": [], "pending": [], "empty": [], "pickers": []}
    for result in results:
        for row in result["rows"]:
            if row["in_menu"]:
                out["b"].append(row)
            elif row["kind"] == "text":
                out["a"].append(row)
            elif row["kind"] == "icon":
                out["icon"].append(row)
            elif row["kind"] == "empty":
                out["empty"].append(row)
            else:
                out["pending"].append(row)
        out["pickers"].extend(result["pickers"])
    return out


def load_baseline(root: pathlib.Path) -> tuple[dict | None, list[Issue]]:
    path = root / BASELINE
    if not path.exists():
        return None, [Issue(BASELINE, "盘点基线不在盘上 —— 断言没有立足点（先落基线再判）")]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return None, [Issue(BASELINE, f"盘点基线读不出来：{exc}")]
    if not isinstance(data, dict):
        return None, [Issue(BASELINE, "盘点基线的形状不对（要一个对象）")]
    return data, []


def assert_issues(files: list[str], missing: list[str], buckets: dict,
                  baseline: dict | None) -> list[Issue]:
    """判据 C/D：a 类命中数 ≤ 目标（本令目标 = 0）+ 空跑防护。"""
    issues: list[Issue] = []
    for directory in missing:
        issues.append(Issue(directory, "UI 面目录不在盘上 —— 面被削过，不许通过（空跑）"))
    if not files:
        issues.append(Issue("UI 面", "一份 .swift 都没扫到 —— 面为空不许通过"))
    elif len(files) < MIN_FILES:
        issues.append(Issue("UI 面", f"只扫到 {len(files)} 份 .swift（下限 {MIN_FILES}）—— 面被削过"))
    loose_menus = [path for path in files
                   if "Menu" in path.rsplit("/", 1)[-1] and path not in MENU_FILES]
    if loose_menus:
        issues.append(Issue("菜单件台账", f"UI 面里文件名带 `Menu` 却没登记进 MENU_FILES：{loose_menus}"
                                          f" —— 新增菜单构造件不许静默溜过（登记时写明理由）"))
    if not baseline:
        issues.append(Issue(BASELINE, f"盘点基线缺失（{BASELINE}）—— 断言没有立足点"))
        return issues
    target = int(baseline.get("targetTextButtons", 0))
    count = len(buckets["a"])
    if count > target:
        head = "; ".join(f"{row['path']}:{row['line']} {row['detail'][:32]}" for row in buckets["a"][:3])
        issues.append(Issue("判据 C", f"水平按钮（a 类）仍以字符文案为可见形态的还有 {count} 处"
                                      f"（目标 {target}，改前读数 {baseline.get('beforeTextButtons')}）"
                                      f" —— 例：{head}"))
    return issues


SYMBOL_HINTS = (
    ("close", "xmark"), ("cancel", "xmark.circle"), ("ok", "checkmark"), ("confirm", "checkmark"),
    ("save", "square.and.arrow.down"), ("delete", "trash"), ("drop", "trash"), ("remove", "trash"),
    ("clear", "xmark.bin"), ("refresh", "arrow.clockwise"), ("reload", "arrow.clockwise"),
    ("retry", "arrow.clockwise"), ("copy", "doc.on.doc"), ("edit", "pencil"), ("rename", "pencil"),
    ("add", "plus"), ("new", "plus"), ("create", "plus"), ("insert", "plus"), ("apply", "checkmark"),
    ("run", "play.fill"), ("execute", "play.fill"), ("generate", "wand.and.stars"),
    ("stop", "stop.fill"), ("export", "square.and.arrow.up"), ("import", "square.and.arrow.down"),
    ("choose", "folder"), ("openfolder", "folder"), ("reveal", "folder"), ("open", "arrow.up.forward.app"),
    ("test", "bolt"), ("check", "checkmark.circle"), ("search", "magnifyingglass"),
    ("find", "magnifyingglass"), ("browse", "tablecells"), ("revert", "arrow.uturn.backward"),
    ("rollback", "arrow.uturn.backward"), ("undo", "arrow.uturn.backward"), ("fit", "arrow.up.left.and.arrow.down.right"),
    ("settings", "gearshape"), ("approve", "checkmark.circle"), ("allow", "checkmark.circle"),
    ("deny", "xmark.circle"), ("reject", "xmark.circle"), ("veto", "hand.raised"),
    ("send", "paperplane"), ("format", "text.alignleft"), ("write", "square.and.pencil"),
    ("today", "calendar"), ("reschedule", "calendar.badge.clock"), ("close", "xmark"),
)


def symbol_hint(detail: str) -> str:
    low = detail.lower()
    for needle, symbol in SYMBOL_HINTS:
        if needle in low:
            return f"`{symbol}`"
    return "**待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话）"


def inventory_md(files: list[str], buckets: dict) -> str:
    def label(row: dict) -> str:
        return row["path"].split("/")[-1].replace(".swift", "")
    lines = [
        "# 按钮图标化 · 逐条盘点清单（`T-20261013-042` 第一段）",
        "",
        "- 口径：人类主人 2026-10-13 令 + 前门 18:2x 裁定 ㈠（水平按钮一律图标 / 菜单项保留文字）。",
        f"- 面：`App/**` + `Plugins/Notes/Views/**` + `Platform/macOS/**` 的**全部** `.swift`（**{len(files)} 份**，不抽样）。",
        f"- 命令：`python3 Scripts/check-button-icon-only.py --inventory`（判定物先剥注释与字符串）。",
        "",
        f"## a 类 · 水平按钮（**必改**）· {len(buckets['a'])} 处",
        "",
        "| # | 界面 | 文件:行 | 控件 | 现行字符 | 拟用图标 | 处置 |",
        "|---|---|---|---|---|---|---|",
    ]
    for index, row in enumerate(buckets["a"], 1):
        lines.append(f"| {index} | {label(row)} | `{row['path']}:{row['line']}` | {row['control']} | "
                     f"`{row['detail']}` | {symbol_hint(row['detail'])} | 改图标 + 保留 tooltip/可访问性标签 |")
    lines += ["", f"## b 类 · 菜单项（**保留文字**，只盘不改）· {len(buckets['b'])} 处", "",
              "| # | 界面 | 文件:行 | 控件 | 现行字符 | 处置 |", "|---|---|---|---|---|---|"]
    for index, row in enumerate(buckets["b"], 1):
        lines.append(f"| {index} | {label(row)} | `{row['path']}:{row['line']}` | {row['control']} | "
                     f"`{row['detail']}` | 保留文字（可选加图标前缀） |")
    lines += ["", f"## 已合格 · 已是纯图标按钮 · {len(buckets['icon'])} 处", ""]
    lines += [f"- `{row['path']}:{row['line']}`" for row in buckets["icon"][:40]]
    if len(buckets["icon"]) > 40:
        lines.append(f"- …… 共 {len(buckets['icon'])} 处（余 {len(buckets['icon']) - 40} 处）")
    lines += ["", f"## 存疑（登记待裁）· {len(buckets['pending'])} 处", ""]
    lines += [f"- `{row['path']}:{row['line']}` {row['control']}：`{row['detail']}`" for row in buckets["pending"]]
    lines += ["", f"## 附录 · 非按钮控件 `Picker`（归口待裁）· {len(buckets['pickers'])} 处", ""]
    lines += [f"- `{row['path']}:{row['line']}` `{row['text']}`" for row in buckets["pickers"]]
    lines += ["", f"## 空串按钮（豁免：无可见文案）· {len(buckets['empty'])} 处", ""]
    lines += [f"- `{row['path']}:{row['line']}`" for row in buckets["empty"]]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- 自检

def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def self_test() -> int:
    cases: list[tuple[str, bool]] = []
    real_baseline = ROOT / BASELINE
    before = _sha(real_baseline) if real_baseline.exists() else None
    good_baseline = {"targetTextButtons": 0, "beforeTextButtons": 1,
                     "dirs": list(UI_DIRS)}
    enough = [f"App/Views/Fake{index}.swift" for index in range(MIN_FILES)]
    empty_buckets = {"a": [], "b": [], "icon": [], "pending": [], "empty": [], "pickers": []}

    with tempfile.TemporaryDirectory(prefix="doyah-btn-selftest-") as tmp:
        root = pathlib.Path(tmp)
        counter = [0]

        def rows_of(text: str, relative: str = "App/Views/Probe.swift") -> list[dict]:
            counter[0] += 1
            path = root / f"case{counter[0]}" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            return scan_file(root, f"case{counter[0]}/{relative}")["rows"]

        def kinds(text: str) -> list[str]:
            return [row["kind"] for row in rows_of(text)]

        def menus(text: str) -> list[bool]:
            return [row["in_menu"] for row in rows_of(text)]

        cases.append(("① 水平按钮 · 文字（a 类必改）",
                      kinds("Button(L(.commonSave)) { save() }\n") == ["text"]))
        cases.append(("② 水平按钮 · 图标（合格）",
                      kinds('Button(action: tap) { Image(systemName: "xmark") }\n') == ["icon"]))
        cases.append(("③ 无括号形态 · 图标（合格）",
                      kinds('Button { tap() } label: { Image(systemName: "plus") }\n') == ["icon"]))
        cases.append(("④ 无括号形态 · 文字（a 类必改）",
                      kinds("Button { tap() } label: { Text(L(.commonSave)) }\n") == ["text"]))
        cases.append(("⑤ 菜单项 ⇒ b 类（保留文字）",
                      menus("Menu { Button(L(.menuNewQuery)) { open() } }\n") == [True]))
        cases.append(("⑥ 上下文菜单项 ⇒ b 类",
                      menus(".contextMenu { Button(L(.treeActionDrop)) { dropTable() } }\n") == [True]))
        cases.append(("⑦ 注释里的按钮不算（剥注释）",
                      rows_of('// Button("保存") { save() }\n') == []))
        cases.append(("⑧ 字符串里的按钮不算（剥字符串）",
                      rows_of('let s = "Button(\\"保存\\") { save() }"\n') == []))
        cases.append(("⑨ 空串标签 ⇒ 无可见文案豁免（查 raw 文本）",
                      kinds('Button("") { x() }\n') == ["empty"]))
        cases.append(("⑨′ `.labelsHidden()` ⇒ 标签不可见（豁免）",
                      kinds('Toggle("", isOn: $y).labelsHidden()\n') == ["empty"]))
        cases.append(("⑨″ 图标助手名（`toolbarIcon(` / `ToolbarIcon(`）⇒ 图标",
                      kinds('Button(action: tap) { toolbarIcon("folder") }\n') == ["icon"]))
        cases.append(("⑩ Toggle 带字符 ⇒ a 类（切换式按钮同判）",
                      kinds("Toggle(L(.x), isOn: $y)\n") == ["text"]))
        cases.append(("⑪ Toggle 纯图标 ⇒ 合格",
                      kinds('Toggle(isOn: $y) { Image(systemName: "bolt") }\n') == ["icon"]))
        cases.append(("⑫ 判不出 ⇒ 存疑（不许静默放过）",
                      kinds("Button { a() } label: { customLabel }\n") == ["unclear"]))
        cases.append(("⑬ 纯文本不是按钮（本令不涉）", rows_of('Text("保存")\n') == []))
        def scan_of(text: str) -> dict:
            counter[0] += 1
            path = root / f"case{counter[0]}" / "App/Views/Probe.swift"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            return scan_file(root, f"case{counter[0]}/App/Views/Probe.swift")

        picker_scan = scan_of('Picker(L(.x), selection: $y) { Text(L(.a)) }\n')
        cases.append(("⑭ Picker 不是按钮（只进附录）",
                      picker_scan["rows"] == [] and len(picker_scan["pickers"]) == 1))
        text_in_button = scan_of('Button { tap() } label: { HStack { Image(systemName: "x"); Text(L(.save)) } }\n')
        cases.append(("⑮ 图标+文字混排 ⇒ 带字符（a 类）",
                      [row["kind"] for row in text_in_button["rows"]] == ["text"]))
        cases.append(("⑮′ 断言：Menu 命名的文件未登记进 MENU_FILES ⇒ 红",
                      bool(assert_issues(enough + ["App/Views/FooMenu.swift"], [], empty_buckets,
                                         good_baseline))))
        cases.append(("⑰ 断言：a 类命中 > 目标 ⇒ 报红",
                      bool(assert_issues(enough, [], {"a": [{"path": "App/Views/X.swift", "line": 1,
                                                             "detail": "L(.save)"}], "b": [], "icon": [],
                                                       "pending": [], "empty": [], "pickers": []},
                                         good_baseline))))
        cases.append(("⑱ 断言：a 类 0 处 + 面齐 ⇒ 绿",
                      not assert_issues(enough, [], empty_buckets, good_baseline)))
        cases.append(("⑲ 断言：面目录不在盘上 ⇒ 红",
                      bool(assert_issues(enough, ["Platform/macOS"], empty_buckets, good_baseline))))
        cases.append(("⑳ 基线不在盘上 ⇒ 红", bool(load_baseline(root / "no-baseline")[1])))

    after = _sha(real_baseline) if real_baseline.exists() else None
    cases.append(("㉑ 真仓库盘点基线逐字节未变", before == after))

    failures = 0
    for name, ok in cases:
        if not ok:
            failures += 1
        print(f"{'✅' if ok else '❌'} {name}")
    total = len(cases)
    if failures:
        print(f"{total - failures}/{total} 例达到预期")
    else:
        print(f"全部 {total} 例达到预期（自检 exit 0）")
    return 0 if failures == 0 else 1


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    unknown = [arg for arg in argv if arg != "--inventory"]
    if unknown:
        print(f"❌ 未知参数 {unknown} —— 参数面要显式")
        print("RESULT=FAIL")
        return 2
    files, missing = ui_files(ROOT)
    results = [scan_file(ROOT, relative) for relative in files]
    buckets = tally(results)
    baseline, issues = load_baseline(ROOT)
    issues += assert_issues(files, missing, buckets, baseline)
    if "--inventory" in argv:
        print(inventory_md(files, buckets), end="")
        return 1 if issues else 0
    print("==> 按钮图标化盘点（人类主人令 2026-10-13 · 信箱 T-20261013-042）")
    print(f"    a 类 水平按钮（**必改**）：{len(buckets['a'])} 处"
          f"（改前读数 {baseline.get('beforeTextButtons') if baseline else '-'} · 目标 "
          f"{baseline.get('targetTextButtons') if baseline else '-'}）")
    print(f"    b 类 菜单项（保留文字）：{len(buckets['b'])} 处"
          f"（其中已是图标 {sum(1 for row in buckets['b'] if row['kind'] == 'icon')} 处）")
    print(f"    已是纯图标（合格）：{len(buckets['icon'])} 处 · 存疑（登记待裁）：{len(buckets['pending'])} 处 · "
          f"无可见文案豁免：{len(buckets['empty'])} 处 · Picker（附录·归口待裁）：{len(buckets['pickers'])} 处")
    print(f"    面：{len(files)} 份 .swift（App + Plugins/Notes/Views + Platform/macOS，不抽样）")
    if issues:
        print(f"\n❌ {len(issues)} 处未过：")
        for issue in issues:
            print(f"   · {issue}")
        print("RESULT=FAIL")
        return 1
    print("\n✅ 水平按钮一律图标（a 类 0 处）")
    print("RESULT=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
