#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""**「文案即所见」的机械门禁**（队列 L-19）：语言表里不许有 markdown 强调标记，渲染口径只剩纯文本。

守的是什么 —— 第 13 轮读图抓到的真缺陷（`routine-candidates-empty-zh` 上
`**四条判据全满足**才列进候选` 星号**肉眼可见**）：

  · 第 13 轮登记：语言表里带 `**` 的中文槽位 **17 个**（其中 `backupRestoreCommandPreview`
    的 `***` 是**密码掩码**、有意）；
  · 同一批键在不同渲染点走**两种口径** —— `RowDetailPanel.swift` 是
    `Text(LocalizedStringKey(L(...)))`（markdown 生效，**故意**），`RoutineCandidatesPanel.swift`
    是 `Text(L(...))`（`Text(String)` **不解析** markdown ⇒ 星号原样露出）。

**口径为什么定 ②「把标记从文案里去掉」而不是 ①「一律走 markdown」**（第 43 轮取证后拍板）：

  · 17 个键里有 **4 个**（`routineCandidatesHint` 之外还有 `lowerPaneProblemSkipped` /
    `backupRestoreStopped` / `backupRestoreTargetDatabaseHint`）的文案会流进
    **根本没有 markdown 这条路的通道** —— `statusMessage`（`String`，状态栏那一行）、
    `backupRestoreLog`（`[String]`，日志逐行），以及 `Label(L(...), systemImage:)`
    的 `String` 重载；在这些地方 markdown **结构上永远不会生效**；
  · `routineCandidatesHint` **一个键同时被两条路用**（面板里 `Text` + `statusMessage` 拼接）
    ⇒ 选 ① 也修不掉它，只会把「同一个键两处不一样」留在产品里（正是 L-19 要消灭的那类不一致）；
  · 英文侧 17 个键里只有 **4 个**带 `**` —— 中英两份文案本来就不在同一个口径上。
  ⇒ 唯一能覆盖**全部**渲染点的口径是「文案里不写标记」。代价（丢掉粗体强调）如实记在开发记录里。

判据（**双向棘轮**，例外只能靠写明理由留在台账里，不能靠改判据）：

  A 文案层：语言表（`Core/Localization.swift` 的 `LocalizedStrings.table`）每个条目的
    **两种语言**槽位都不许含 `**`（marker 例外键除外）；
  B 渲染层：产品源文件里不许再出现 `LocalizedStringKey`（口径只剩纯文本一种；例外按文件登记 +
    反向对账）—— **判定物先剥注释与字符串字面量**（旧实现只跳「整行注释」⇒ 行尾注释 / 块注释 /
    字符串字面量三处假红），面不写死（判据 F）；
  C 防静默：解析出的语言表条目数不得低于下限；且**语言槽位必须全部落在条目里**
    （全文件槽位命中数 ≠ 条目数 ⇒ 有条目形状落在判定物之外 ⇒ 判红点名，而不是少算几条还判绿）；
  D 例外两端对账：marker 例外键必须在表里且**仍含**登记的标记形态（`***`）、必须写明理由；
    renderer 例外文件必须存在且**仍在使用** `LocalizedStringKey`（否则陈旧）；
    例外表不许有没理由的条目；
  E 接线：本门禁与它的负例必须在 `Scripts/verify-all.sh`（闭环第 3 项）里被真的跑到 ——
    判定物是**非注释行**（旧实现只做全文子串 ⇒ 把调用注释掉仍判绿）；
  F 面不许写死：`FACE_DIRS` 与 `Package.swift` **生产** target 的 `path:`/`sources:` 双向对账
    （派生出的生产 root 未纳入面 ⇒ 判红；面里的根已不是生产 root ⇒ 死条目判红；
    生产 target 既没声明 `path:` 也没声明 `sources:` / 根不在盘 / 面为空 ⇒ 判红）。

**判定物（条目形状）不写死**（原单 `T-20261010-054` ㈠）：旧 `ENTRY` 把条目形状逐字钉死成
「`[` 紧贴 + `.simplifiedChinese` 在前 + `.english` 在后 + `"` 后紧贴 `]` + 单行」⇒
**同一份文案换个合法写法就整条看不见**（既不计数、也不判 A）。真仓实测（2026-10-14 · HEAD `113ad1e`）：
旧判定物 **2036** 条 / 新判定物 **2069** 条 ⇒ **33 条活体在旧面外**（29 条槽位换行的多行写法
+ 4 条「同一行里紧跟前一条」的第二条）；另 4 条「同行首条」的旧读物把**邻条目整段粘进了 `en` 值**
（旧读数污染，`en` 与真值不同、`zh` 相同）。任一条写进 `**` 都不会有人知道。
现按「条目 = `.键: [` 之后**方括号配平**的块 + 两个语言槽位（**顺序 / 空白 / 跨行都无关**）」解析。

跑法：

    python3 Scripts/check-copy-emphasis.py              # 每轮跑（verify-all.sh 第 3 项）
    python3 Scripts/test-copy-emphasis-gate.py          # 负例（只在临时副本上写坏，不碰仓库）

退出码：0 = 全过；1 = 有判据不成立（打印文件 / 行号 / 键名 / 原因）；2 = 环境不对（找不到语言表 / 台账）。
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

TABLE_FILE = "Core/Localization.swift"
EXEMPTIONS = "Scripts/copy-emphasis-exemptions.json"
VERIFY_ALL = "Scripts/verify-all.sh"
PACKAGE_REL = "Package.swift"
GATE_COMMAND = "python3 Scripts/check-copy-emphasis.py"
SELF_TEST_COMMAND = "python3 Scripts/test-copy-emphasis-gate.py"

# 判据 B 的面：**不写死** —— 与 `Package.swift` 的生产 target 双向对账（判据 F）。
# 测试 target（`Tests` / `TestsUISnapshot` / `TestsPlatform`）不进面：那里的 `LocalizedStringKey`
# 是断言用的字面量，不是界面渲染点。旧实现写死四根、与 `Package.swift` 无任何对账 ⇒
# `Tools/LicenseTool`（`.executableTarget`）与 `Plugins/Notes/**` 两个生产 root 长期在面外
# ⇒ 往里写一处真违规是**静默通过**。
FACE_DIRS = (
    "App",
    "CLI",
    "Core",
    "Platform",
    "Plugins/Notes/Sources",
    "Plugins/Notes/Views",
    "Tools/LicenseTool",
)

# 判据 A 的标记：markdown 强调用的一对星号。
MARKER = "**"

# 语言槽位名（判据 A 就扫这两个；条目形状解析按名字认槽位，不按出现顺序）。
LANGUAGE_SLOTS = ("simplifiedChinese", "english")

# 判据 C 的下限：语言表条目 2026-10-14 实测 **2069** 条（旧判定物当时读作 2036 ⇒ 33 条在面外）。
# 取 1500 留余量：低于此值先怀疑表被掏空，而不是「表变小了」。真正的防静默靠**槽位对账**。
MIN_TABLE_ENTRIES = 1500

# 条目起点：`.键: [` —— 允许出现在**行首**或**同类条目之后（`,\n` 或 `,` 之后 + 空白）**，
# 即「同一行里紧跟前一条」的第二条也算（旧实现只认行首 `^\s*\.`）。语言槽位名排除在外，
# 免得把 `.simplifiedChinese: [` 这种当成条目。
ENTRY_START = re.compile(
    r"(?:(?<=^)|(?<=[,\n]))[ \t]*\.(?!simplifiedChinese\b|english\b)(?P<key>[A-Za-z0-9_]+)"
    r"[ \t]*:[ \t]*(?P<open>\[)",
    re.M,
)

# 语言槽位：`.<槽位名>: "值"`（值里支持 `\"` 转义；顺序 / 空白 / 换行与判定物无关）。
SLOT = re.compile(
    r'\.(?P<name>simplifiedChinese|english)[ \t]*:[ \t]*"(?P<value>(?:[^"\\]|\\.)*)"'
)

TARGET_START = re.compile(r"\.(?P<kind>\w*[Tt]arget)[ \t]*\(")


# ── 解析小工具（剥注释 / 剥字符串 / 方括号配平 / 顶层逗号切分）────────────────────

def mask_comments(src: str) -> str:
    """把注释字符换成空格（等长、换行保留 ⇒ 行号不动），字符串字面量内容不动。"""
    out = list(src)
    i, n, in_string = 0, len(src), False
    while i < n:
        ch = src[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if ch == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def mask_code(src: str) -> str:
    """「代码面」：注释**与字符串字面量**都抹成等长空白（换行保留 ⇒ 行号不动）。

    判据 B 的判定物必须是代码面：注释里提一句 `LocalizedStringKey`、或调试字符串里写一遍，
    都不是「渲染点」（旧实现只跳「整行注释」⇒ 行尾注释 / 块注释 / 字符串字面量三处假红）。
    已知边界（如实登记）：原始字符串（`.\#` 形式）与多行字符串按普通字符串处理，本仓实测 0 处；
    本仓实测 0 处；日后引入时这里要跟版。
    """
    out = list(mask_comments(src))
    i, n, in_string = 0, len(src), False
    while i < n:
        ch = src[i]
        if in_string:
            if ch == "\\":
                if i + 1 < n and out[i + 1] != "\n":
                    out[i + 1] = " "
                i += 2
                continue
            if ch == '"':
                in_string = False
            elif out[i] != "\n":
                out[i] = " "
            i += 1
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        i += 1
    return "".join(out)


def match_bracket(text: str, index: int, open_ch: str = "[", close_ch: str = "]") -> int:
    """`text[index]` 必须是 open_ch，返回配平的 close_ch 下标（跳过字符串字面量里的括号）。"""
    depth, i, in_string, n = 0, index, False, len(text)
    while i < n:
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
        elif ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("括号未配平")


def split_top_level(block: str) -> list[str]:
    """按**顶层**逗号切分（括号 / 方括号 / 字符串里的逗号不算分隔符）。"""
    pieces, buf, depth, i, n, in_string = [], [], 0, 0, len(block), False
    while i < n:
        ch = block[i]
        if in_string:
            buf.append(ch)
            if ch == "\\":
                if i + 1 < n:
                    buf.append(block[i + 1])
                    i += 2
                    continue
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            buf.append(ch)
        elif ch in "([{":
            depth += 1
            buf.append(ch)
        elif ch in ")]}":
            depth -= 1
            buf.append(ch)
        elif ch == "," and depth == 0:
            pieces.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
        i += 1
    pieces.append("".join(buf))
    return [piece for piece in (p.strip() for p in pieces) if piece]


def production_face(root: pathlib.Path) -> tuple[list[str], list[str], list[str]]:
    """从 `Package.swift` 的**生产 target** 声明派生扫描面（判据 F）。

    返回（面 · 既没声明 `path:` 也没声明 `sources:` 的生产 target 名 · 测试 target 名）。
    `.target(path: ".", sources: [...])` 这种「根 + 源列表」按 `sources` 展开成子根。
    """
    package = root / PACKAGE_REL
    if not package.exists():
        return [], [], []
    src = mask_comments(package.read_text(encoding="utf-8"))
    face: list[str] = []
    undeclared: list[str] = []
    tests: list[str] = []
    for match in TARGET_START.finditer(src):
        kind = match.group("kind")
        open_index = src.index("(", match.end() - 1)
        try:
            block = src[open_index + 1 : match_bracket(src, open_index, "(", ")")]
        except ValueError:
            undeclared.append(f"{kind}(未配平)")
            continue
        fields: dict[str, str] = {}
        for piece in split_top_level(block):
            label, _, value = piece.partition(":")
            fields.setdefault(label.strip(), value.strip())
        name = fields.get("name", "?").strip('"')
        if kind == "testTarget":
            tests.append(name)
            continue
        path = fields.get("path", "")
        sources = fields.get("sources", "")
        if not path and not sources:
            undeclared.append(name or kind)
            continue
        base = path.strip().strip('"') or "."
        items = re.findall(r'"([^"]*)"', sources) if sources else [""]
        for item in items:
            rel = (pathlib.Path(base) / item).as_posix() if item else base
            if rel.startswith("./"):
                rel = rel[2:]
            if rel and rel not in face:
                face.append(rel)
    return face, undeclared, tests


def covers(face_dir: str, derived_root: str) -> bool:
    """`face_dir` 是否覆盖派生 root（相等，或派生 root 在它下面）。"""
    return derived_root == face_dir or derived_root.startswith(face_dir.rstrip("/") + "/")


def read_entries(root: pathlib.Path):
    """解析语言表 → （[(键, 行号, zh, en)], 解析不出的条目点名）。

    条目 = `.键:` 之后的**方括号配平块**，块里恰好两个语言槽位（顺序 / 空白 / 跨行都无关），
    除槽位与逗号外只剩空白（允许块内注释）。**判定物不写死形状**，但**解析不出的候选一律点名**
    ——旧实现是「形状不认识就整条跳过」，静默丢条目（真仓 33 条活体）。
    """
    table = root / TABLE_FILE
    if not table.exists():
        return None, None, f"找不到语言表 {TABLE_FILE}"
    text = table.read_text(encoding="utf-8")
    entries = []
    unparsed: list[str] = []
    consumed = -1
    for match in ENTRY_START.finditer(text):
        if match.start() < consumed:
            continue
        open_index = match.end() - 1
        line = text.count("\n", 0, match.start()) + 1
        key = match.group("key")
        try:
            close_index = match_bracket(text, open_index)
        except ValueError:
            unparsed.append(f"{TABLE_FILE}:{line} [. {key}]：方括号未配平")
            continue
        consumed = close_index
        body = mask_comments(text[open_index + 1 : close_index])
        slots: dict[str, str] = {}
        spans: list[tuple[int, int]] = []
        for slot in SLOT.finditer(body):
            slots[slot.group("name")] = slot.group("value")
            spans.append((slot.start(), slot.end()))
        rest = body
        for start, end in sorted(spans, reverse=True):
            rest = rest[:start] + rest[end:]
        if set(slots) != set(LANGUAGE_SLOTS) or rest.strip(" \t\r\n,") != "":
            found = "/".join(sorted(slots)) or "无"
            unparsed.append(
                f"{TABLE_FILE}:{line} [. {key}]：块里读到的语言槽位是 {found}、"
                f"槽位之外还剩 {rest.strip()[:60]!r}"
            )
            continue
        entries.append((key, line, slots["simplifiedChinese"], slots["english"]))
    return entries, unparsed, None


def count_language_slots(root: pathlib.Path) -> dict[str, int]:
    """全文件语言槽位命中数（判据 C 的对账面：槽位必须全部落在解析出的条目里）。"""
    table = root / TABLE_FILE
    if not table.exists():
        return {}
    text = table.read_text(encoding="utf-8")
    counts = {name: 0 for name in LANGUAGE_SLOTS}
    for slot in SLOT.finditer(text):
        counts[slot.group("name")] += 1
    return counts


def scan_render_sites(root: pathlib.Path, face: tuple[str, ...]) -> dict[str, list[int]]:
    """判据 B：产品源文件里出现 `LocalizedStringKey` 的地方（**代码面**，注释与字符串先剥掉）。"""
    hits: dict[str, list[int]] = {}
    for directory in face:
        base = root / directory
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            relative = path.relative_to(root).as_posix()
            masked = mask_code(path.read_text(encoding="utf-8")).splitlines()
            for index, line in enumerate(masked, start=1):
                if "LocalizedStringKey" in line:
                    hits.setdefault(relative, []).append(index)
    return hits


def load_exemptions(root: pathlib.Path):
    path = root / EXEMPTIONS
    if not path.exists():
        return None, f"找不到例外台账 {EXEMPTIONS}"
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except json.JSONDecodeError as error:
        return None, f"{EXEMPTIONS} 不是合法 JSON：{error}"


def mask_shell(src: str) -> str:
    """shell 的「代码面」：把 `#` 起的注释抹成等长空白（单 / 双引号里的 `#` 不算）。

    判据 E 的判定物必须是**非注释行**：把调用注释掉不算接线（旧实现只做全文子串 ⇒
    把两条调用注释掉仍判绿）。**不许**拿 C 风格的 `mask_comments` 代用 —— shell 里的 glob
    （`Scripts/*`）会被当成 `/*` 块注释的开头，把后面几十行 shell 一起吃掉
    （实测量：`verify-all.sh` 那两条调用行正好被吞掉，判据 E 当场假红）。
    """
    out = list(src)
    i, n, quote = 0, len(src), ""
    while i < n:
        ch = src[i]
        if quote:
            if ch == "\\" and quote == '"':
                i += 2
                continue
            if ch == quote:
                quote = ""
            i += 1
            continue
        if ch in "'\"":
            quote = ch
        elif ch == "#":
            j = src.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description="文案即所见：语言表无 `**`、渲染口径唯一（L-19）")
    parser.add_argument("--root", default=str(REPO), help="扫描哪个仓库根（负例验证用）")
    args = parser.parse_args()
    root = pathlib.Path(args.root)

    problems: list[str] = []

    entries, unparsed, error = read_entries(root)
    if entries is None:
        print(f"❌ {error}（根目录：{root}）")
        return 2

    exemptions, error = load_exemptions(root)
    if exemptions is None:
        print(f"❌ {error}（根目录：{root}）")
        return 2

    marker_exemptions = {item["key"]: item for item in exemptions.get("markerExemptions", [])}
    renderer_exemptions = {item["file"]: item for item in exemptions.get("rendererExemptions", [])}
    for item in exemptions.get("markerExemptions", []) + exemptions.get("rendererExemptions", []):
        if not str(item.get("reason", "")).strip():
            problems.append(f"{EXEMPTIONS}：例外条目 `{item.get('key') or item.get('file')}` 没有写理由")

    # ── 判据 C：防静默（表被掏空 / 条目形状落在判定物之外 / 正则失配）──────────────
    if len(entries) < MIN_TABLE_ENTRIES:
        problems.append(
            f"{TABLE_FILE}：只解析出 {len(entries)} 条语言表条目（下限 {MIN_TABLE_ENTRIES}）——"
            f" 先把判定物与表的形状对上，再谈判据 A"
        )
    if not entries:
        problems.append(f"{TABLE_FILE}：一条条目都没解析出来 —— 零命中不是通过")
    slots = count_language_slots(root)
    for name in LANGUAGE_SLOTS:
        if slots.get(name, 0) != len(entries):
            problems.append(
                f"{TABLE_FILE}：语言槽位 `.{name}` 全文件命中 {slots.get(name, 0)} 处，"
                f"而条目解析出 {len(entries)} 条 —— 落差 = 有条目形状落在判定物之外（条目被静默跳过）"
            )
    for item in unparsed:
        problems.append(f"{item} —— 条目形状落进判定物之外：修判定物，不许整条跳过")

    # ── 判据 A：文案层不许有标记（两种语言都扫）────────────────────────────────
    keyed = {key: (line, zh, en) for key, line, zh, en in entries}
    marker_hits: list[str] = []
    for key, line, zh, en in entries:
        for language, value in (("zh", zh), ("en", en)):
            if MARKER not in value:
                continue
            if key in marker_exemptions:
                continue
            marker_hits.append(f"{TABLE_FILE}:{line} [. {key}]（{language}）{value.strip()[:90]}")
            problems.append(
                f"{TABLE_FILE}:{line}：键 `{key}` 的 {language} 槽位里有 markdown 强调标记 `{MARKER}` —— "
                f"口径 ② 是「文案即所见」，标记会照字面显示在纯文本渲染点上"
            )

    # ── 判据 D：marker 例外两端对账 ────────────────────────────────────────────
    for key, item in sorted(marker_exemptions.items()):
        marker = item.get("marker", "")
        if key not in keyed:
            problems.append(f"{EXEMPTIONS}：marker 例外 `{key}` 在语言表里不存在（陈旧条目）")
        elif marker and marker not in (keyed[key][1] + keyed[key][2]):
            problems.append(
                f"{EXEMPTIONS}：marker 例外 `{key}` 登记的形态 `{marker}` 已不在这条文案里 —— 条目陈旧，请删掉"
            )

    # ── 判据 F：面不许写死（`FACE_DIRS` ↔ `Package.swift` 生产 target 双向对账）──────
    derived, undeclared, test_targets = production_face(root)
    for name in undeclared:
        problems.append(
            f"[F] {PACKAGE_REL}：生产 target `{name}` 既没声明 `path:` 也没声明 `sources:` —— 面无从派生"
        )
    for rel in derived:
        if not any(covers(entry, rel) for entry in FACE_DIRS):
            problems.append(
                f"[F] {PACKAGE_REL}：生产 root `{rel}` 不在判据 B 的面内（{', '.join(FACE_DIRS)}）——"
                f" 新增生产 root 必须同轮进面，否则往里写违规是静默通过"
            )
    for entry in FACE_DIRS:
        if not any(covers(entry, rel) for rel in derived):
            problems.append(
                f"[F] 面里的根 `{entry}` 已不是 {PACKAGE_REL} 的生产 root（死条目）—— 请同轮销账"
            )
    for entry in FACE_DIRS:
        if not (root / entry).is_dir():
            problems.append(f"[F] 面里的根 `{entry}` 在盘上不存在（盘：{root}）")
    scanned = sorted(
        path.relative_to(root).as_posix()
        for entry in FACE_DIRS
        if (root / entry).is_dir()
        for path in (root / entry).rglob("*.swift")
    )
    if not scanned:
        problems.append(f"[F] 判据 B 的面里一份 `.swift` 都没有（面：{', '.join(FACE_DIRS)}）—— 空跑不是通过")

    # ── 判据 B：渲染层口径唯一（判定物 = 代码面）──────────────────────────────
    render_hits = scan_render_sites(root, FACE_DIRS)
    for relative, lines in sorted(render_hits.items()):
        if relative in renderer_exemptions:
            continue
        problems.append(
            f"{relative}:{','.join(str(line) for line in lines)}：出现 `LocalizedStringKey` —— "
            f"口径 ② 下渲染点一律走 `Text(L(...))`（纯文本）；确需保留的按文件写进 {EXEMPTIONS}"
        )

    # 反向对账：登记了例外，却已经不用了 ⇒ 陈旧
    for relative, item in sorted(renderer_exemptions.items()):
        if not (root / relative).exists():
            problems.append(f"{EXEMPTIONS}：renderer 例外 `{relative}` 这个文件不存在")
        elif relative not in render_hits:
            problems.append(
                f"{EXEMPTIONS}：renderer 例外 `{relative}` 条目陈旧 —— 这个文件里已经没有 `LocalizedStringKey` 了"
            )

    # ── 判据 E：接线（门禁与它的负例必须在闭环里真的跑到）────────────────────────
    verify_all = root / VERIFY_ALL
    if not verify_all.exists():
        problems.append(f"找不到 {VERIFY_ALL} —— 判据 E 无从下手")
    else:
        # 判定物 = **非注释行**：把调用注释掉不算接线（旧实现只做全文子串 ⇒ 注释掉仍判绿）
        script = mask_shell(verify_all.read_text(encoding="utf-8"))
        for command in (GATE_COMMAND, SELF_TEST_COMMAND):
            if command not in script:
                problems.append(
                    f"{VERIFY_ALL} 的非注释行里没有 `{command}` —— 本门禁没接进闭环（有判据、没闭环）"
                )

    # ── 打印 ─────────────────────────────────────────────────────────────────
    print("🅰 文案层：语言表里的 markdown 强调标记 `**`")
    print(f"   · 解析出语言表条目 {len(entries)} 条（下限 {MIN_TABLE_ENTRIES}）")
    print(
        f"   · 槽位对账：`.simplifiedChinese` {slots.get('simplifiedChinese', 0)} 处 / "
        f"`.english` {slots.get('english', 0)} 处 == 条目 {len(entries)} 条"
        f"（对不上即判红；解析不出的候选 {len(unparsed)} 处）"
    )
    print(f"   · 命中 `{MARKER}` 且未登记的键：{len(marker_hits)} 个")
    for hit in marker_hits:
        print(f"     - {hit}")
    print(f"   · 已登记标记例外：{len(marker_exemptions)} 条 —— " + ("、".join(sorted(marker_exemptions)) or "（无）"))
    print(
        f"🅱 渲染层：`LocalizedStringKey`（口径只剩一种）· 面 {len(FACE_DIRS)} 个源根 / "
        f"{len(scanned)} 份 `.swift`；`{PACKAGE_REL}` 派生生产 root {len(derived)} 个"
        + (f"（测试 target {len(test_targets)} 个不进面）" if test_targets else "")
    )
    if render_hits:
        for relative, lines in sorted(render_hits.items()):
            marks = "（已登记例外）" if relative in renderer_exemptions else ""
            print(f"   · {relative}{marks}:{','.join(str(line) for line in lines)}")
    else:
        print(f"   · 面内 {len(scanned)} 份产品源文件的代码面上 0 处（注释与字符串里的不算）")

    if problems:
        print(f"\n❌ 文案口径门禁未通过（{len(problems)} 项）：")
        for problem in problems:
            print(f"   - {problem}")
        return 1

    print("✅ 文案口径门禁通过：语言表无标记、渲染点只剩纯文本一种口径")
    return 0


if __name__ == "__main__":
    sys.exit(main())
