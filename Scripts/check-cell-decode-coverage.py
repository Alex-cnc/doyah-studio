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
   `decoded` 的还要有源码锚点与单测锚点；处置不在词表内即红。
B. **双向对账（台账 ↔ 源码）**：① 台账声明的每个锚点必须在它指名的那份源码里**逐字出现**；
   ② `platform/macos/Core/PostgresCellFormatter.swift::decode` 里那一段 `switch` 的类型标签集合必须与台账的
   `formatterCases` **逐条相等** —— 解了新类型不登记 ⇒ 红；台账写着解了、源码里没有 ⇒ 红；
   ③ 三张 oid 表（数组 / 范围 / 多范围）的键数必须与台账登记的一致；④ 台账声明
   `mustNotExist` 的类型（`tid` / `xid` / `record`）不许在源码里长出 `case` —— 这也是反向的。
C. **两种出口都没有了**：① `bannedExits`（`String(describing: buffer)` 那一族）在
   `platform/macos/Core/` 与 `platform/macos/App/` 的**代码行**里不许出现（注释里的历史叙述不算）；② `honestFallback`
   的形态必须在盘上（`unreadable(...)` + `[类型名 字节数B] \\x十六进制`）—— 删掉兜底又回到
   「什么都印得出来」的老路。
D. **单测逐型钉住**：台账里每个 `testToken` 必须在 `platform/macos/Tests/PostgresCellFormatterTests.swift`
   里出现，且该文件里的测试函数数不低于下限（防「测试文件被掏空」）。
E. **行为证据**：`Scripts/test-session-management.sh` §7 必须在盘上，两个 heredoc 的用例条数
   必须与台账登记的相等，台账点名的类型名必须在那一节里出现过（防「证据脚本被换掉」）。
F. 空跑防护：类型数 / decoded 数 / 单测锚点数 / 证据用例数四条下限，任何一条踩线即红
   （「判据自己失效」比「发现不了」更危险）。

边界（如实登记）：本判据判的是**台账与盘上事实对不对得上**，不判解码算法对不对 ——
算法对不对由 `platform/macos/Tests/PostgresCellFormatterTests.swift`（逐型造字节断言文本）与
`Scripts/test-session-management.sh` §7（逐条与 psql 的文本形态比对）两条真证据承担。

判据自己的证据：`--self-test` **10 例**（红/绿成对，夹具一律在临时目录，末例核对真仓库四份文件逐字节未变）。

用法：
    python3 Scripts/check-cell-decode-coverage.py              # 校验（闭环第 15 项）
    python3 Scripts/check-cell-decode-coverage.py --self-test  # 门禁自己的证据（**10 例**）
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
SWIFT_SCAN_DIRS = ("Core", "App")


class Issue:
    def __init__(self, where: str, reason: str) -> None:
        self.where = where
        self.reason = reason

    def __str__(self) -> str:  # pragma: no cover - 只为打印
        return f"❌ {self.where}：{self.reason}"


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read(root: pathlib.Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def code_lines(text: str) -> list[str]:
    """只留代码行（`//` 与 `///` 注释不算出口 —— 注释里会引用历史写法）。"""
    return [line for line in text.splitlines() if not line.strip().startswith("//")]


def formatter_switch_labels(formatter: str) -> set[str]:
    region = formatter[formatter.index("public static func decode("):formatter.index("static func unreadable")]
    labels: list[str] = []
    for group in re.findall(r"case ((?:\.[A-Za-z0-9_]+(?:\s*,\s*)?)+):", region):
        labels += [item.strip() for item in group.split(",")]
    return set(labels)


def table_keys(formatter: str, name: str) -> list[str]:
    body = formatter[formatter.index(f"static let {name}"):]
    literal = body[body.index("["):body.index("\n    ]")]
    return re.findall(r"(?<![A-Za-z0-9])(\d+):\s", literal)


def heredoc_lines(text: str, marker: str) -> list[str]:
    block = text[text.index("<<'" + marker + "'"):]
    block = block[:block.index("\n" + marker + "\n")]
    return [line for line in block.split("\n")[1:] if line.strip()]


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
    if not (ledger.get("evidence") or {}).get("file"):
        issues.append(Issue("台账.evidence", "缺 file（行为证据在哪）"))
    if not ledger.get("floors"):
        issues.append(Issue("台账.floors", "缺空跑防护下限"))
    return issues


def check_sources(ledger: dict, root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    sources = ledger.get("sources") or {}
    formatter_rel = sources.get("formatter", "")
    wire_rel = sources.get("wireValue", "")
    tests_rel = sources.get("tests", "")
    formatter = _read(root, formatter_rel)
    wire = _read(root, wire_rel)
    tests = _read(root, tests_rel)

    # C ① 被禁的出口（只扫代码行：注释里会引用历史写法）
    for relative_root in SWIFT_SCAN_DIRS:
        for path in sorted((root / relative_root).rglob("*.swift")):
            for number, line in enumerate(code_lines(path.read_text(encoding="utf-8")), start=1):
                for banned in ledger.get("bannedExits") or []:
                    if banned in line:
                        issues.append(Issue(f"{path.relative_to(root)}:{number}", f"被禁的出口又回来了：{banned}"))

    # C ② 诚实兜底必须在盘上
    fallback = ledger.get("honestFallback") or {}
    if fallback.get("anchor") and fallback["anchor"] not in formatter:
        issues.append(Issue(formatter_rel, f"诚实兜底不见了：{fallback['anchor']}"))
    if fallback.get("shapeLiteral") and fallback["shapeLiteral"] not in formatter:
        issues.append(Issue(formatter_rel, "诚实兜底的形态（[类型名 字节数B] \\x十六进制）不在盘上"))

    # B ② 台账声明的 switch 标签 ↔ 源码（双向）
    declared = set(ledger.get("formatterCases") or [])
    actual = formatter_switch_labels(formatter)
    for missing in sorted(declared - actual):
        issues.append(Issue(formatter_rel, f"台账说解了 {missing}，源码的 switch 里没有"))
    for extra in sorted(actual - declared):
        issues.append(Issue(formatter_rel, f"源码里解了 {extra}，台账没登记"))

    # B ③ 三张 oid 表的键数
    for name, spec in (ledger.get("tables") or {}).items():
        anchor = spec.get("anchor")
        if anchor and anchor not in formatter:
            issues.append(Issue(formatter_rel, f"表 {name} 的锚点不在盘上：{anchor}"))
        keys = table_keys(formatter, name)
        if spec.get("keys") != len(keys):
            issues.append(Issue(formatter_rel, f"表 {name} 的键数：台账 {spec.get('keys')}，实测 {len(keys)}"))

    # B ① 逐条锚点 / mustNotExist / 单测锚点
    for entry in ledger.get("types") or []:
        name = entry.get("name")
        anchor = entry.get("anchor")
        if anchor:
            if entry.get("file") not in ("formatter", "wireValue"):
                issues.append(Issue(f"{LEDGER}::{name}", f"file「{entry.get('file')}」不认识"))
            else:
                text = formatter if entry["file"] == "formatter" else wire
                if anchor not in text:
                    issues.append(Issue(f"{LEDGER}::{name}", f"锚点不在 {entry['file']} 里：{anchor}"))
        must_not = entry.get("mustNotExist")
        if must_not and (must_not in formatter or must_not in wire):
            issues.append(Issue(f"{LEDGER}::{name}", f"源码里长出了 {must_not}（要么解它、要么登记）"))
        token = entry.get("testToken")
        if token and token not in tests:
            issues.append(Issue(tests_rel, f"单测里没有「{name}」的锚点：{token}"))
    return issues


def check_evidence(ledger: dict, root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    spec = ledger.get("evidence") or {}
    relative = spec.get("file")
    if not relative:
        return [Issue("台账.evidence", "缺 file")]
    text = _read(root, relative)
    if spec.get("sectionAnchor") and spec["sectionAnchor"] not in text:
        issues.append(Issue(relative, f"证据节不见了：{spec['sectionAnchor']}"))
    for count_key, marker_key in (("sameCases", "sameHeredoc"), ("boundaryCases", "boundaryHeredoc")):
        marker = spec.get(marker_key)
        if not marker:
            issues.append(Issue("台账.evidence", f"缺 {marker_key}"))
            continue
        lines = heredoc_lines(text, marker)
        if not lines:
            issues.append(Issue(relative, f"{marker} 是空的（空跑）"))
        elif spec.get(count_key) != len(lines):
            issues.append(Issue(relative, f"{marker} 用例数：台账 {spec.get(count_key)}，实测 {len(lines)}"))
    for token in spec.get("tokens") or []:
        if token not in text:
            issues.append(Issue(relative, f"台账点名的类型在证据里没出现：{token}"))
    return issues


def measurements(ledger: dict, root: pathlib.Path) -> dict:
    sources = ledger.get("sources") or {}
    formatter = _read(root, sources.get("formatter", ""))
    tests = _read(root, sources.get("tests", ""))
    evidence = _read(root, (ledger.get("evidence") or {}).get("file", ""))
    types = ledger.get("types") or []
    spec = ledger.get("evidence") or {}
    return {
        "types": len(types),
        "decoded": len([e for e in types if e.get("disposition") == "decoded"]),
        "testTokens": len(re.findall(r"^\s+func test", tests, re.M)),
        "formatterCases": len(formatter_switch_labels(formatter)),
        "evidenceSameCases": len(heredoc_lines(evidence, spec["sameHeredoc"])) if spec.get("sameHeredoc") else 0,
        "evidenceTokens": len(spec.get("tokens") or []),
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
        "platform/macos/Core/PostgresCellFormatter.swift",
        "platform/macos/Core/PostgresWireValue.swift",
        "platform/macos/Tests/PostgresCellFormatterTests.swift",
        "Scripts/test-session-management.sh",
        LEDGER,
    ]
    real = {relative: ROOT / relative for relative in targets}
    before = {relative: _sha(path) for relative, path in real.items()}

    def fresh(fixture: pathlib.Path) -> pathlib.Path:
        for relative, path in real.items():
            destination = fixture / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(path, destination)
        return fixture

    def mutate(fixture: pathlib.Path, relative: str, old: str, new: str) -> None:
        path = fixture / relative
        text = path.read_text(encoding="utf-8")
        assert old in text, f"夹具锚点失效：{relative} :: {old[:40]}"
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def rewrite_ledger(fixture: pathlib.Path, change) -> None:
        path = fixture / LEDGER
        data = json.loads(path.read_text(encoding="utf-8"))
        change(data)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    cases: list[tuple[str, bool, list[Issue]]] = []
    with tempfile.TemporaryDirectory(prefix="doyah-cell-selftest-") as tmp:
        greenery = fresh(pathlib.Path(tmp) / "green")
        cases.append(("好情况（绿）", False, check(greenery)))

        emptied = fresh(pathlib.Path(tmp) / "emptied")
        rewrite_ledger(emptied, lambda data: data.update({"types": []}))
        cases.append(("台账被掏空", True, check(emptied)))

        shrunk = fresh(pathlib.Path(tmp) / "shrunk")
        mutate(shrunk, "platform/macos/Core/PostgresCellFormatter.swift", "case .interval:", "case .interval_unused:")
        cases.append(("源码少了一种解码（台账还在）", True, check(shrunk)))

        grew = fresh(pathlib.Path(tmp) / "grew")
        mutate(grew, "platform/macos/Core/PostgresCellFormatter.swift", "        default:\n            break",
               "        case .tid:\n            return nil\n        default:\n            break")
        cases.append(("源码多了一种未登记的 case", True, check(grew)))

        relapse = fresh(pathlib.Path(tmp) / "relapse")
        mutate(relapse, "platform/macos/Core/PostgresCellFormatter.swift",
               "        return unreadable(cell.dataType, bytes: bytes)",
               "        return String(describing: cell.bytes)")
        cases.append(("被禁的出口又回来", True, check(relapse)))

        no_fallback = fresh(pathlib.Path(tmp) / "no-fallback")
        mutate(no_fallback, "platform/macos/Core/PostgresCellFormatter.swift", "static func unreadable(", "static func unreadableGone(")
        cases.append(("诚实兜底被删", True, check(no_fallback)))

        no_test = fresh(pathlib.Path(tmp) / "no-test")
        mutate(no_test, "platform/macos/Tests/PostgresCellFormatterTests.swift", "func testTimeWithZoneEastAndWest()",
               "func testTimeAndZone()")
        cases.append(("单测锚点被改名", True, check(no_test)))

        short_evidence = fresh(pathlib.Path(tmp) / "short-evidence")
        mutate(short_evidence, "Scripts/test-session-management.sh", "polygon '((1,2),(3,4),(5,6))'\n", "")
        cases.append(("证据脚本里少了一条用例", True, check(short_evidence)))

        starved = fresh(pathlib.Path(tmp) / "starved")
        rewrite_ledger(starved, lambda data: data["floors"].update({"types": 999}))
        cases.append(("空跑下限抬到不现实", True, check(starved)))

        failed = 0
        for index, (name, expect_red, issues) in enumerate(cases, start=1):
            red = bool(issues)
            ok = red == expect_red
            detail = f"（{issues[0]}）" if (not ok and issues) else ""
            print(f"  {'✅' if ok else '❌'} 例 {index} {name}：期望{'红' if expect_red else '绿'}，"
                  f"实际{'红' if red else '绿'}" + detail)
            if not ok:
                failed += 1

        after = {relative: _sha(path) for relative, path in real.items()}
        unchanged = before == after
        print(f"  {'✅' if unchanged else '❌'} 例 {len(cases) + 1} 真仓库五份文件逐字节未变")
        if not unchanged:
            failed += 1
        total = len(cases) + 1
        if failed:
            print(f"判据自己的证据：自测失败（{failed}/{total} 例不达标）")
            return 1
        print(f"判据自己的证据：自测通过（{total} 例）")
        return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    issues = check(ROOT)
    if issues:
        for issue in issues:
            print(issue)
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
