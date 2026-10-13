#!/usr/bin/env python3
"""非文本类型的值「可读 / 认不出要如实说」门禁（队列 L-74，闭环第 15 项）。

存在的理由（真现场）
--------------------
2026-09-28 做 L-63（旁路脚本转正）时读原始输出，撞见会话行里的 `client_addr`（`inet` 列）
那一格印的是一串**控制字符**：驱动在扩展查询协议下给的是 **binary**，而
`Core/PostgresCellFormatter` 原先只覆盖文本类 / 整型 / 浮点 / numeric / 日期时间，
其余类型落到最后一句 `String(describing: buffer)` —— 用户拿到的**不是值**，是驱动
内部对象的描述；值里的换行与控制字符还会把 CLI 的表格排版当场打断（一行值劈成好几行）。
而**所有既有门禁都是绿的**：编译、单测、文档计数、设计令牌、越界检查，没有一个管
「这一格到底印了什么」。

判据（任一不过即失败）
----------------------
A. **台账结构**（`Scripts/cell-decode-coverage.json`）：每型一条，必须写 `disposition`
   （词表：`decoded` / `honest-unknown` / `text-when-readable`）、`why`（不许空）；
   `decoded` 的还要有源码锚点与单测锚点；处置不在词表内即红。三张面（`bannedExits` /
   `tables` / `evidence.sectionAnchor`）**缺一即红** —— 否则那几条判据会被台账静默掏空。
B. **双向对账（台账 ↔ 源码）**：① 台账声明的每个锚点必须在它指名的那份源码里**逐字出现**；
   ② `Core/PostgresCellFormatter.swift::decode` 里那一段 `switch` 的类型标签集合必须与台账的
   `formatterCases` **逐条相等**（认「枚举名 + `where` / 关联值 / 跨行」写法）—— 解了新类型不登记 ⇒ 红；
   台账写着解了、源码里没有 ⇒ 红；③ 三张 oid 表（数组 / 范围 / 多范围）的键数必须与台账登记的一致
   （**表内注释不算键**）；④ 台账声明 `mustNotExist` 的类型（`tid` / `xid` / `record`）不许在源码里长出 `case`。
C. **两种出口都没有了**：① `bannedExits`（`String(describing: buffer)` 那一族）在**判据面**的
   代码行里不许出现（注释里的历史叙述不算）；② `honestFallback` 的形态必须在盘上
   （`unreadable(...)` + `[类型名 字节数B] \\x十六进制`）—— 删掉兜底又回到「什么都印得出来」的老路。
D. **单测逐型钉住**：台账里每个 `testToken` 必须在 `Tests/PostgresCellFormatterTests.swift` 里
   出现（**行尾注释里的 token 不算**），且该文件里的测试函数数不低于下限（防「测试文件被掏空」）。
E. **行为证据**：`Scripts/test-session-management.sh` §7 必须在盘上，两个 heredoc 的用例条数
   必须与台账登记的相等，台账点名的类型名必须在那一节里出现过（防「证据脚本被换掉」）。
F. 空跑防护：类型数 / decoded 数 / 单测锚点数 / 证据用例数 / **被禁出口数 / 表数 / 证据节**七条下限，
   任何一条踩线即红（「判据自己失效」比「发现不了」更危险）。

口径（2026-10-13 合册 `T-20261013-027` · 原单 `T-20261010-058` 起）
--------------------------------------------------------------
- **代码 vs 注释**：「在盘上 / 被引用 / 是不是真出口」一律先 `strip_comments`（字符串感知、
  块注释可嵌套、**等长空格替换** ⇒ 行号与列位都不动）；判「是不是真出口」时再 `blank_strings`。
- **判据面**：由根 `Package.swift` **现读**的生产 target 源码目录（`.target` / `.executableTarget`
  的 `sources:` / `path:` 两种写法都认）；面根数有**硬下限**（写死在脚本里，不读台账）——
  声明了新 target 就自动进面，一行台账也缩不掉它。
- **崩而不报**：sources 指的文件 / 表声明 / 那段 switch / heredoc 读不出来 ⇒ 逐条报 issue，
  **不吐栈**，退出码 **2**（与「判红 1」分开 ⇒ CI 里分得出「有缺口」与「判据自己坏掉」）。
- 边界（如实登记）：本判据判的是**台账与盘上事实对不对得上**，不判解码算法对不对 ——
  算法对不对由 `Tests/PostgresCellFormatterTests.swift` 与 `Scripts/test-session-management.sh` §7 两条真证据承担。

判据自己的证据：`--self-test` **23 例**（红/绿成对，夹具一律在临时目录，末例核对真仓库六份文件逐字节未变）。

用法：
    python3 Scripts/check-cell-decode-coverage.py              # 校验（闭环第 15 项）
    python3 Scripts/check-cell-decode-coverage.py --self-test  # 门禁自己的证据（**23 例**）
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
LEDGER = "Scripts/cell-decode-coverage.json"
DISPOSITIONS = {"decoded", "honest-unknown", "text-when-readable"}
FACE_ROOTS_FLOOR = 7          # 判据面（Package.swift 现读的生产 target 源码目录）根数下限
SELF_BROKEN = 2               # 判据自身坏掉（与「判红 1」分开）


class Issue:
    def __init__(self, where: str, reason: str, self_broken: bool = False) -> None:
        self.where = where
        self.reason = reason
        self.self_broken = self_broken

    def __str__(self) -> str:  # pragma: no cover - 只为打印
        mark = "（判据自身坏掉）" if self.self_broken else ""
        return f"❌ {self.where}：{self.reason}{mark}"


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_checked(root: pathlib.Path, relative: str, label: str) -> tuple[str, Issue | None]:
    """读一份受审文件；读不出来 ⇒ **报 issue 不吐栈**（判据自己坏掉那一类）。"""
    if not relative:
        return "", Issue(label, "台账没写文件名（判据读不出来）", self_broken=True)
    path = root / relative
    if not path.is_file():
        return "", Issue(relative, f"不在盘上（台账 {label} 指的文件不见了）", self_broken=True)
    try:
        return path.read_text(encoding="utf-8"), None
    except (OSError, UnicodeDecodeError) as error:
        return "", Issue(relative, f"读不出来：{type(error).__name__}", self_broken=True)


def _skip_string(text: str, index: int) -> int:
    """从引号处起，返回字符串字面量之后的第一个下标（`\\` 转义；`\"\"\"` 多行）。"""
    n = len(text)
    if text.startswith('"""', index):
        i = index + 3
        while i < n:
            if text[i] == "\\":
                i += 2
                continue
            if text.startswith('"""', i):
                return i + 3
            i += 1
        return n
    i = index + 1
    while i < n:
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == '"':
            return i + 1
        if text[i] == "\n":
            return i
        i += 1
    return n


def strip_comments(text: str) -> str:
    """把 `//` 与 `/* */`（可嵌套）换成**等长空格**；字符串字面量里的内容一字不动。

    等长 ⇒ 行号与列位都不动（报出来的行号就是真行号）。
    """
    chars = list(text)
    n = len(text)
    i = 0
    depth = 0
    while i < n:
        if depth:
            if text.startswith("/*", i):
                chars[i] = chars[i + 1] = " "
                depth += 1
                i += 2
                continue
            if text.startswith("*/", i):
                chars[i] = chars[i + 1] = " "
                depth -= 1
                i += 2
                continue
            if chars[i] != "\n":
                chars[i] = " "
            i += 1
            continue
        if text.startswith("//", i):
            while i < n and chars[i] != "\n":
                chars[i] = " "
                i += 1
            continue
        if text.startswith("/*", i):
            chars[i] = chars[i + 1] = " "
            depth = 1
            i += 2
            continue
        if chars[i] == '"':
            i = _skip_string(text, i)
            continue
        i += 1
    return "".join(chars)


def blank_strings(text: str) -> str:
    """把字符串字面量的**内容**抹成空格（引号留着，长度不变）—— 判「是不是真代码」时用。"""
    chars = list(text)
    n = len(text)
    i = 0
    while i < n:
        if chars[i] == '"':
            end = _skip_string(text, i)
            for j in range(i + 1, max(i + 1, min(end, n) - 1)):
                if chars[j] != "\n":
                    chars[j] = " "
            i = max(end, i + 1)
            continue
        i += 1
    return "".join(chars)


def code_text(text: str) -> str:
    """判定物 = **代码**（剥注释 + 抹字符串内容）。"""
    return blank_strings(strip_comments(text))


def _strip_hash(line: str) -> str:
    """抹掉 shell 行里的 `#` 注释（等长空格）—— 引号里的 `#` 不算注释。"""
    in_single = in_double = False
    i = 0
    while i < len(line):
        char = line[i]
        if char == "\\" and not in_single:
            i += 2
            continue
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double and (i == 0 or line[i - 1] in " \t"):
            return line[:i] + " " * (len(line) - i)
        i += 1
    return line


def strip_shell_comments(text: str) -> str:
    """shell：`#` 注释换等长空格；**heredoc 体内的 `#` 是数据不是注释**，一字不动。"""
    out: list[str] = []
    pending: str | None = None
    for line in text.split("\n"):
        if pending is not None:
            out.append(line)
            if line.strip() == pending:
                pending = None
            continue
        marker = re.search(r"<<-?\s*'?\"?([A-Za-z_][A-Za-z0-9_]*)'?\"?", line)
        out.append(_strip_hash(line))
        if marker:
            pending = marker.group(1)
    return "\n".join(out)


def _balanced(text: str, open_index: int) -> tuple[str, bool]:
    """从 `(` 处起取配对的括号内文本（读不出配对 ⇒ 第二个返回值为假）。"""
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[open_index + 1:i], True
    return "", False


def package_production_dirs(root: pathlib.Path) -> tuple[list[str], list[Issue]]:
    """判据面 = 根 `Package.swift` **现读**的生产 target 源码目录。

    认 `.target(` / `.executableTarget(`；`sources: [...]` 优先、`path:` 兜底。
    面**不许写死**：声明了新 target ⇒ 自动进面，一行台账也缩不掉它。
    """
    path = root / "Package.swift"
    if not path.is_file():
        return [], [Issue("Package.swift", "不在盘上（判据面读不出来）", self_broken=True)]
    text = strip_comments(path.read_text(encoding="utf-8"))
    dirs: list[str] = []
    issues: list[Issue] = []
    for hit in re.finditer(r"\.(?:executableTarget|target)\(", text):
        block, ok = _balanced(text, hit.end() - 1)
        if not ok:
            issues.append(Issue("Package.swift", "有 target 声明读不到配对的右括号", self_broken=True))
            continue
        sources = re.search(r"sources:\s*\[([^\]]*)\]", block)
        if sources:
            dirs += re.findall(r'"([^"]+)"', sources.group(1))
            continue
        declared = re.search(r'path:\s*"([^"]+)"', block)
        if declared:
            dirs.append(declared.group(1))
        else:
            issues.append(Issue("Package.swift", "某个生产 target 既没 sources: 也没 path:", self_broken=True))
    return sorted({item for item in dirs if item}), issues


def check_banned_exits(ledger: dict, root: pathlib.Path) -> list[Issue]:
    """C ① 被禁的出口：**判据面**内的代码行里不许出现；报的是**真行号**（剥注释等长，不动行号）。"""
    issues: list[Issue] = []
    banned = ledger.get("bannedExits") or []
    face, face_issues = package_production_dirs(root)
    issues += face_issues
    if len(face) < FACE_ROOTS_FLOOR:
        issues.append(Issue("Package.swift",
                            f"判据面只剩 {len(face)} 个生产源码目录（下限 {FACE_ROOTS_FLOOR}）—— 面被削了"))
    for relative in face:
        directory = root / relative
        if not directory.is_dir():
            issues.append(Issue(relative, "生产 target 的源码目录不在盘上（判据面读不全）", self_broken=True))
            continue
        for path in sorted(directory.rglob("*.swift")):
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as error:
                issues.append(Issue(path.relative_to(root).as_posix(), f"读不出来：{type(error).__name__}",
                                    self_broken=True))
                continue
            if not any(needle in text for needle in banned):
                continue
            scanned = code_text(text)
            for number, line in enumerate(scanned.split("\n"), start=1):
                for needle in banned:
                    if needle in line:
                        issues.append(Issue(f"{path.relative_to(root)}:{number}",
                                            f"被禁的出口又回来了：{needle}"))
    return issues


def _decode_region(formatter: str) -> tuple[str, Issue | None]:
    """`decode(...)` 那一段（到下一个 4 空格缩进的 `static func` 为止）—— 找不到 ⇒ 报 issue 不吐栈。"""
    start_marker = "public static func decode("
    if start_marker not in formatter:
        return "", Issue("Core/PostgresCellFormatter.swift", f"找不到「{start_marker}」（判据读不出来）",
                         self_broken=True)
    start = formatter.index(start_marker)
    tail = re.search(r"\n    (?:public |private |internal |fileprivate )?static func ", formatter[start:])
    if not tail:
        return "", Issue("Core/PostgresCellFormatter.swift", "decode 之后的函数边界找不到（判据读不出来）",
                         self_broken=True)
    return formatter[start:start + tail.start()], None


def _case_pattern(text: str, position: int) -> str | None:
    """从 `case` 之后读到该模式的末尾（顶层 `:` 处）；`where` 之后的部分不算模式。"""
    depth = 0
    i = position
    while i < len(text):
        char = text[i]
        if char in "([":
            depth += 1
        elif char in ")]":
            if depth == 0:
                return None
            depth -= 1
        elif char == "}" and depth == 0:
            return None
        elif depth == 0:
            if text.startswith("where", i) and (i == 0 or not text[i - 1].isalnum()) \
                    and (i + 5 >= len(text) or not text[i + 5].isalnum()):
                return text[position:i]
            if char in "=;":
                return None
            if char == ":":
                return text[position:i]
        i += 1
    return None


def formatter_switch_labels(formatter: str) -> tuple[set[str], Issue | None]:
    """`decode` 那段 switch 的类型标签集合（剥注释 + 抹字符串；认 `where` / 关联值 / 跨行）。"""
    code = code_text(formatter)
    region, problem = _decode_region(code)
    if problem:
        return set(), problem
    labels: set[str] = set()
    for hit in re.finditer(r"\bcase\b", region):
        pattern = _case_pattern(region, hit.end())
        if pattern:
            labels |= {f".{name}" for name in re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", pattern)}
    return labels, None


def table_keys(formatter: str, name: str) -> tuple[list[str], Issue | None]:
    """三张 oid 表的键（**剥注释**再数：表内注释不是键）；表不在盘上 / 形状变了 ⇒ 报 issue。"""
    code = strip_comments(formatter)
    anchor = f"static let {name}"
    if anchor not in code:
        return [], Issue("Core/PostgresCellFormatter.swift", f"表 {name} 的声明不在盘上：{anchor}")
    body = code[code.index(anchor):]
    if "[" not in body:
        return [], Issue("Core/PostgresCellFormatter.swift", f"表 {name} 后面找不到字面量起点「[」")
    literal = body[body.index("["):]
    end = re.search(r"\n\s*\]", literal)
    if not end:
        return [], Issue("Core/PostgresCellFormatter.swift", f"表 {name} 的字面量找不到收尾「]」")
    return re.findall(r"(?<![A-Za-z0-9])(\d+):\s", literal[:end.start()]), None


def heredoc_lines(text: str, marker: str, where: str) -> tuple[list[str], Issue | None]:
    """取 heredoc 体的非空行；起点 / 收尾找不到 ⇒ 报 issue 不吐栈。"""
    opener = next((form for form in (f"<<'{marker}'", f'<<"{marker}"', f"<<{marker}") if form in text), None)
    if opener is None:
        return [], Issue(where, f"找不到 heredoc 起点 <<{marker}（证据脚本形状变了）")
    block = text[text.index(opener):]
    terminator = f"\n{marker}\n"
    if terminator not in block:
        return [], Issue(where, f"heredoc「{marker}」找不到收尾行（形状变了）")
    return [line for line in block[:block.index(terminator)].split("\n")[1:] if line.strip()], None


def load_ledger(root: pathlib.Path) -> tuple[dict | None, list[Issue]]:
    path = root / LEDGER
    if not path.is_file():
        return None, [Issue(LEDGER, "台账不在盘上")]
    try:
        return json.loads(path.read_text(encoding="utf-8")), []
    except json.JSONDecodeError as error:
        return None, [Issue(LEDGER, f"台账不是合法 JSON：{error}")]


def check_ledger(ledger: dict, root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    sources = ledger.get("sources") or {}
    for key in ("formatter", "wireValue", "tests", "evidence"):
        if not sources.get(key):
            issues.append(Issue("台账.sources", f"缺 {key}"))
    types = ledger.get("types") or []
    if not types:
        issues.append(Issue("台账.types", "一条都没有（空台账 = 空跑）"))
    for index, entry in enumerate(types):
        name = entry.get("name") or f"#{index}"
        where = f"{LEDGER}::{name}"
        if not entry.get("why"):
            issues.append(Issue(where, "why 是空的（处置必须写出理由）"))
        disposition = entry.get("disposition")
        if disposition not in DISPOSITIONS:
            issues.append(Issue(where, f"disposition「{disposition}」不在词表 {sorted(DISPOSITIONS)} 内"))
            continue
        if disposition == "decoded":
            if not entry.get("anchor"):
                issues.append(Issue(where, "decoded 的条目必须给源码 anchor（台账不许自说自话）"))
            if not entry.get("testToken"):
                issues.append(Issue(where, "decoded 的条目必须给 testToken（单测要逐型钉住）"))
            if entry.get("file") not in ("formatter", "wireValue"):
                issues.append(Issue(where, "decoded 的条目必须指名 file（formatter / wireValue）"))
    for name, spec in (ledger.get("tables") or {}).items():
        if not spec.get("anchor"):
            issues.append(Issue(f"台账.tables.{name}", "缺 anchor"))
        if not isinstance(spec.get("keys"), int):
            issues.append(Issue(f"台账.tables.{name}", "缺 keys（键数）"))
    if not ledger.get("bannedExits"):
        issues.append(Issue("台账.bannedExits", "被禁出口一条都没有 ⇒ 判据 C① 会被静默掏空"))
    if not ledger.get("tables"):
        issues.append(Issue("台账.tables", "三张 oid 表一条都没登记 ⇒ 判据 B③ 会被静默掏空"))
    evidence = ledger.get("evidence") or {}
    if not evidence.get("file"):
        issues.append(Issue("台账.evidence", "缺 file（行为证据在哪）"))
    if not evidence.get("sectionAnchor"):
        issues.append(Issue("台账.evidence", "缺 sectionAnchor（证据节不许无名）"))
    if not ledger.get("floors"):
        issues.append(Issue("台账.floors", "缺空跑防护下限"))
    return issues


def check_sources(ledger: dict, root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    sources = ledger.get("sources") or {}
    formatter_rel = sources.get("formatter", "")
    wire_rel = sources.get("wireValue", "")
    tests_rel = sources.get("tests", "")
    formatter, formatter_bad = _read_checked(root, formatter_rel, "sources.formatter")
    wire, wire_bad = _read_checked(root, wire_rel, "sources.wireValue")
    tests, tests_bad = _read_checked(root, tests_rel, "sources.tests")
    for problem in (formatter_bad, wire_bad, tests_bad):
        if problem:
            issues.append(problem)

    issues += check_banned_exits(ledger, root)

    code_formatter = strip_comments(formatter)
    code_wire = strip_comments(wire)
    code_tests = strip_comments(tests)
    bare_formatter = code_text(formatter)
    bare_wire = code_text(wire)

    # C ② 诚实兜底必须在盘上（剥注释后仍看得见真代码）
    if not formatter_bad:
        fallback = ledger.get("honestFallback") or {}
        if fallback.get("anchor") and fallback["anchor"] not in code_formatter:
            issues.append(Issue(formatter_rel, f"诚实兜底不见了：{fallback['anchor']}"))
        if fallback.get("shapeLiteral") and fallback["shapeLiteral"] not in code_formatter:
            issues.append(Issue(formatter_rel, "诚实兜底的形态（[类型名 字节数B] \\x十六进制）不在盘上"))

        # B ② 台账声明的 switch 标签 ↔ 源码（双向；判定物 = 剥注释后的代码）
        declared = set(ledger.get("formatterCases") or [])
        actual, problem = formatter_switch_labels(formatter)
        if problem:
            issues.append(problem)
        else:
            for missing in sorted(declared - actual):
                issues.append(Issue(formatter_rel, f"台账说解了 {missing}，源码的 switch 里没有"))
            for extra in sorted(actual - declared):
                issues.append(Issue(formatter_rel, f"源码里解了 {extra}，台账没登记"))

        # B ③ 三张 oid 表的键数
        for name, spec in (ledger.get("tables") or {}).items():
            anchor = spec.get("anchor")
            if anchor and anchor not in code_formatter:
                issues.append(Issue(formatter_rel, f"表 {name} 的锚点不在盘上：{anchor}"))
            keys, problem = table_keys(formatter, name)
            if problem:
                issues.append(problem)
            elif spec.get("keys") != len(keys):
                issues.append(Issue(formatter_rel,
                                    f"表 {name} 的键数：台账 {spec.get('keys')}，实测 {len(keys)}"))

    # B ① 逐条锚点 / mustNotExist / 单测锚点（一律在**剥注释后的代码**上判）
    for entry in ledger.get("types") or []:
        name = entry.get("name")
        anchor = entry.get("anchor")
        if anchor:
            kind = entry.get("file")
            if kind not in ("formatter", "wireValue"):
                issues.append(Issue(f"{LEDGER}::{name}", f"file「{kind}」不认识"))
            elif (kind == "formatter" and formatter_bad) or (kind == "wireValue" and wire_bad):
                continue  # 文件都读不出来，上面已按「判据自身坏掉」报过
            else:
                text = code_formatter if kind == "formatter" else code_wire
                if anchor not in text:
                    issues.append(Issue(f"{LEDGER}::{name}", f"锚点不在 {kind} 里：{anchor}"))
        must_not = entry.get("mustNotExist")
        if must_not:
            for kind, bad, text in (("formatter", formatter_bad, bare_formatter),
                                    ("wireValue", wire_bad, bare_wire)):
                if bad or not text:
                    continue
                if must_not in text:
                    issues.append(Issue(f"{LEDGER}::{name}",
                                        f"源码的 {kind} 里长出了 {must_not}（要么解它、要么登记）"))
        token = entry.get("testToken")
        if token and not tests_bad:
            if token in code_tests:
                continue
            # 例外台账：只有**逐条登记了理由**的条目才认「只活在注释里的 token」（未登记 ⇒ 红）
            if entry.get("testTokenInComment"):
                if not entry.get("testTokenCommentWhy"):
                    issues.append(Issue(f"{LEDGER}::{name}", "testTokenInComment 登记了但理由为空"))
                elif token not in tests:
                    issues.append(Issue(tests_rel, f"登记的注释例外已陈旧：{token} 连注释里都没有了"))
                continue
            issues.append(Issue(tests_rel, f"单测里没有「{name}」的锚点：{token}（只活在注释里不算）"))
    return issues


def check_evidence(ledger: dict, root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    spec = ledger.get("evidence") or {}
    relative = spec.get("file")
    if not relative:
        return [Issue("台账.evidence", "缺 file")]
    text, problem = _read_checked(root, relative, "evidence.file")
    if problem:
        return [problem]
    if spec.get("sectionAnchor") and spec["sectionAnchor"] not in text:
        issues.append(Issue(relative, f"证据节不见了：{spec['sectionAnchor']}"))
    shell_code = strip_shell_comments(text)
    for count_key, marker_key in (("sameCases", "sameHeredoc"), ("boundaryCases", "boundaryHeredoc")):
        marker = spec.get(marker_key)
        if not marker:
            issues.append(Issue("台账.evidence", f"缺 {marker_key}"))
            continue
        lines, problem = heredoc_lines(text, marker, relative)
        if problem:
            issues.append(problem)
        elif not lines:
            issues.append(Issue(relative, f"{marker} 是空的（空跑）"))
        elif spec.get(count_key) != len(lines):
            issues.append(Issue(relative, f"{marker} 用例数：台账 {spec.get(count_key)}，实测 {len(lines)}"))
    for token in spec.get("tokens") or []:
        if token not in shell_code:
            issues.append(Issue(relative, f"台账点名的类型在证据里没出现：{token}"))
    return issues


def measurements(ledger: dict, root: pathlib.Path) -> dict:
    sources = ledger.get("sources") or {}
    spec = ledger.get("evidence") or {}
    evidence_rel = spec.get("file", "")
    formatter, _ = _read_checked(root, sources.get("formatter", ""), "sources.formatter")
    tests, _ = _read_checked(root, sources.get("tests", ""), "sources.tests")
    evidence, _ = _read_checked(root, evidence_rel, "evidence.file")
    types = ledger.get("types") or []
    labels, _ = formatter_switch_labels(formatter)
    same, _ = heredoc_lines(evidence, spec["sameHeredoc"], evidence_rel) if spec.get("sameHeredoc") else ([], None)
    return {
        "types": len(types),
        "decoded": len([e for e in types if e.get("disposition") == "decoded"]),
        "testTokens": len(re.findall(r"^\s+func test", strip_comments(tests), re.M)),
        "formatterCases": len(labels),
        "evidenceSameCases": len(same),
        "evidenceTokens": len(spec.get("tokens") or []),
        "bannedExits": len(ledger.get("bannedExits") or []),
        "tables": len(ledger.get("tables") or {}),
        "evidenceSectionAnchor": 1 if spec.get("sectionAnchor") else 0,
    }


def check_floors(ledger: dict, root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    measured = measurements(ledger, root)
    for key, floor in (ledger.get("floors") or {}).items():
        if key not in measured:
            issues.append(Issue("台账.floors", f"不认识的键：{key}"))
        elif measured[key] < floor:
            issues.append(Issue("台账.floors", f"{key} 实测 {measured[key]} < 下限 {floor}（空跑防护）"))
    return issues


def check(root: pathlib.Path) -> list[Issue]:
    ledger, issues = load_ledger(root)
    if ledger is None:
        return issues
    issues += check_ledger(ledger, root)
    issues += check_sources(ledger, root)
    issues += check_evidence(ledger, root)
    issues += check_floors(ledger, root)
    return issues


def self_test() -> int:
    targets = [
        "Core/PostgresCellFormatter.swift",
        "Core/PostgresWireValue.swift",
        "Tests/PostgresCellFormatterTests.swift",
        "Scripts/test-session-management.sh",
        "Package.swift",
        LEDGER,
    ]
    real = {relative: ROOT / relative for relative in targets}
    before = {relative: _sha(path) for relative, path in real.items()}
    face, _ = package_production_dirs(ROOT)

    def fresh(fixture: pathlib.Path) -> pathlib.Path:
        for relative, path in real.items():
            destination = fixture / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(path, destination)
        for relative in face:
            (fixture / relative).mkdir(parents=True, exist_ok=True)
        return fixture

    def mutate(fixture: pathlib.Path, relative: str, old: str, new: str) -> None:
        path = fixture / relative
        text = path.read_text(encoding="utf-8")
        assert old in text, f"夹具锚点失效：{relative} :: {old[:40]}"
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def write(fixture: pathlib.Path, relative: str, text: str) -> None:
        path = fixture / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def rewrite_ledger(fixture: pathlib.Path, change) -> None:
        path = fixture / LEDGER
        data = json.loads(path.read_text(encoding="utf-8"))
        change(data)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    cases: list[tuple[str, bool, list[Issue], str | None, str | None]] = []

    def add(name: str, expect_red: bool, fixture: pathlib.Path, needle: str | None = None) -> None:
        try:
            cases.append((name, expect_red, check(fixture), needle, None))
        except Exception as error:  # noqa: BLE001 —— 判据崩了本身就是证据不达标
            cases.append((name, expect_red, [], needle, f"{type(error).__name__}: {error}"))

    with tempfile.TemporaryDirectory(prefix="doyah-cell-selftest-") as tmp:
        base = pathlib.Path(tmp)

        add("好情况（绿）", False, fresh(base / "green"))

        emptied = fresh(base / "emptied")
        rewrite_ledger(emptied, lambda data: data.update({"types": []}))
        add("台账被掏空", True, emptied)

        shrunk = fresh(base / "shrunk")
        mutate(shrunk, "Core/PostgresCellFormatter.swift", "case .interval:", "case .interval_unused:")
        add("源码少了一种解码（台账还在）", True, shrunk)

        grew = fresh(base / "grew")
        mutate(grew, "Core/PostgresCellFormatter.swift", "        default:\n            break",
               "        case .tid:\n            return nil\n        default:\n            break")
        add("源码多了一种未登记的 case", True, grew)

        relapse = fresh(base / "relapse")
        mutate(relapse, "Core/PostgresCellFormatter.swift",
               "        return unreadable(cell.dataType, bytes: bytes)",
               "        return String(describing: cell.bytes)")
        add("被禁的出口又回来", True, relapse)

        no_fallback = fresh(base / "no-fallback")
        mutate(no_fallback, "Core/PostgresCellFormatter.swift", "static func unreadable(",
               "static func unreadableGone(")
        add("诚实兜底被删（且不许吐栈）", True, no_fallback, needle="诚实兜底不见了")

        no_test = fresh(base / "no-test")
        mutate(no_test, "Tests/PostgresCellFormatterTests.swift", "func testTimeWithZoneEastAndWest()",
               "func testTimeAndZone()")
        add("单测锚点被改名", True, no_test)

        short_evidence = fresh(base / "short-evidence")
        mutate(short_evidence, "Scripts/test-session-management.sh", "polygon '((1,2),(3,4),(5,6))'\n", "")
        add("证据脚本里少了一条用例", True, short_evidence)

        starved = fresh(base / "starved")
        rewrite_ledger(starved, lambda data: data["floors"].update({"types": 999}))
        add("空跑下限抬到不现实", True, starved)

        commented = fresh(base / "commented-case")
        mutate(commented, "Core/PostgresCellFormatter.swift", "        case .line:", "        // case .line:")
        add("假绿·注释掉的真 case（// case .line:）", True, commented, needle="台账说解了 .line")

        deleted = fresh(base / "deleted-case")
        mutate(deleted, "Core/PostgresCellFormatter.swift",
               "        case .line:\n            return PostgresWireValue.line(bytes)\n", "")
        add("对照·case .line 整行删掉（不许削软）", True, deleted, needle="台账说解了 .line")

        where_case = fresh(base / "where-case")
        mutate(where_case, "Core/PostgresCellFormatter.swift", "        case .polygon:",
               "        case .uuid where cell.dataType == 1:\n        case .polygon:")
        add("假绿·带 where 的新解码", True, where_case, needle="源码里解了 .uuid")

        comment_mustnot = fresh(base / "comment-mustnot")
        mutate(comment_mustnot, "Core/PostgresCellFormatter.swift", "        default:\n            break",
               "        // case .tid: 旧写法，已删\n        default:\n            break")
        add("假阳·mustNotExist 只活在注释里", False, comment_mustnot)

        token_comment = fresh(base / "token-in-comment")
        mutate(token_comment, "Tests/PostgresCellFormatterTests.swift", "func testCidrAlwaysCarriesMask()",
               "func testCidrMaskPresent()  // 原 testCidrAlwaysCarriesMask")
        add("假绿·单测 token 只留行尾注释", True, token_comment, needle="单测里没有")

        no_banned = fresh(base / "no-banned")
        rewrite_ledger(no_banned, lambda data: data.update({"bannedExits": []}))
        add("假绿·台账 bannedExits 被清空", True, no_banned, needle="bannedExits")

        no_tables = fresh(base / "no-tables")
        rewrite_ledger(no_tables, lambda data: data.update({"tables": {}}))
        add("假绿·台账 tables 被删", True, no_tables, needle="tables")

        no_section = fresh(base / "no-section")
        rewrite_ledger(no_section, lambda data: data["evidence"].pop("sectionAnchor"))
        add("假绿·台账 evidence.sectionAnchor 被删", True, no_section, needle="sectionAnchor")

        broken_source = fresh(base / "broken-source")
        rewrite_ledger(broken_source, lambda data: data["sources"].update({"formatter": "Core/NoSuchS62.swift"}))
        add("崩而不报·sources 指向不存在的文件", True, broken_source, needle="判据自身坏掉")

        trailing = fresh(base / "trailing-comment")
        mutate(trailing, "Core/PostgresCellFormatter.swift", "        switch type {",
               "        switch type {  // 旧写法 String(describing: bytes)")
        add("假阳·行尾注释里的被禁出口", False, trailing)

        line_number = fresh(base / "line-number")
        write(line_number, "App/ProbeLineS62.swift",
              "// 注释一行\n// 再一行注释\nfunc probe() { return String(describing: bytes) }\n")
        add("定位·真代码命中报真行号（前两行是注释）", True, line_number, needle="App/ProbeLineS62.swift:3")

        table_comment = fresh(base / "table-comment")
        mutate(table_comment, "Core/PostgresCellFormatter.swift", "        199: 114, 143: 142,",
               "        // 9999: 旧 oid 已删\n        199: 114, 143: 142,")
        add("假阳·表内注释不算键", False, table_comment)

        outside_face = fresh(base / "outside-face")
        write(outside_face, "Platform/macOS/ProbeS62.swift",
              "func probe() { return String(describing: buffer) }\n")
        add("面·面外生产根（Platform/macOS）里的被禁出口", True, outside_face,
            needle="Platform/macOS/ProbeS62.swift:1")

        failed = 0
        for index, (name, expect_red, issues, needle, error) in enumerate(cases, start=1):
            red = bool(issues)
            ok = red == expect_red
            detail = ""
            if error:
                ok = False
                detail = f"（判据崩了：{error}）"
            elif ok and needle:
                dumped = "\n".join(str(issue) for issue in issues)
                if needle not in dumped:
                    ok = False
                    detail = f"（要点名的「{needle}」不在输出里）"
            if not ok and not detail and issues:
                detail = f"（{issues[0]}）"
            print(f"  {'✅' if ok else '❌'} 例 {index} {name}：期望{'红' if expect_red else '绿'}，"
                  f"实际{'红' if red else '绿'}{detail}")
            if not ok:
                failed += 1

        after = {relative: _sha(path) for relative, path in real.items()}
        unchanged = before == after
        print(f"  {'✅' if unchanged else '❌'} 例 {len(cases) + 1} 真仓库六份文件逐字节未变")
        if not unchanged:
            failed += 1
        total = len(cases) + 1
        if failed:
            print(f"判据自己的证据：自测失败（{failed}/{total} 例不达标）")
            return 1
        print(f"判据自己的证据：自测通过（{total} 例）")
        return 0


def main() -> int:
    known = {"--self-test"}
    unknown = [arg for arg in sys.argv[1:] if arg not in known]
    if unknown:
        print(f"❌ 不认识的参数：{' '.join(unknown)}（只认 --self-test）")
        return SELF_BROKEN
    if "--self-test" in sys.argv[1:]:
        return self_test()
    issues = check(ROOT)
    if issues:
        for issue in issues:
            print(issue)
        broken = [issue for issue in issues if issue.self_broken]
        if broken:
            print(f"❌ 非文本类型的值门禁：判据自身坏掉 {len(broken)} 条"
                  f"（另 {len(issues) - len(broken)} 条不过）—— 退出码 {SELF_BROKEN}")
            return SELF_BROKEN
        print(f"❌ 非文本类型的值「可读 / 认不出要如实说」门禁：{len(issues)} 条不过")
        return 1
    ledger, _ = load_ledger(ROOT)
    measured = measurements(ledger or {}, ROOT)
    print(f"✅ 非文本类型的值可读（队列 L-74）：台账 {measured['types']} 条处置"
          f"（解码 {measured['decoded']} · 源码 switch {measured['formatterCases']} 支 · 单测 {measured['testTokens']} 项"
          f" · 真机证据 {measured['evidenceSameCases']} 条字面量）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
