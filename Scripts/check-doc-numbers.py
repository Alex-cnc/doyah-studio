#!/usr/bin/env python3
"""「文档里的数字」的唯一来源台账 + 双向对账（队列 L-55）。

**为什么要有它**（第 61 轮，L-55 条目原文）：同一件事在好几处各写一遍 ——
闭环项数 `十八项` 在 `AGENT-SPEC.md` 有多处、`Scripts/verify-all.sh` 头注释与脚本正文里各写一次、
三书里也各写一次；单测项数写在 §7 门禁行与 `Docs/概要设计.md` §8.3 闸门表等多处。
**表格结构合法、编译照过、单测照绿** —— 数字陈旧时谁都不说话。本轮实测的现场：
`Docs/概要设计.md` §8.3 闸门表写着 `Scripts/verify-core.sh`（**760** 项），而实测 **2056** 项
（那是 2026-09-23 的旧值，L-55 条目原文登记它时是 2003，此后又漂了两次）。

**口径（本侧拍板，三选一里取「唯一来源 + 机械判据」这条）**：

1. **唯一来源 = `Scripts/doc-numbers.json`**（照 `Scripts/vendored-sqlite.json` 的做法：
   一份台账登记「值 + 这个值怎么来的 + 文档里有哪些现状声明」）。
2. **能机械复算的必须复算** —— 判据不看台账的自述，自己算一遍：
   - `gate-scan`：数 `Scripts/verify-all.sh` 里的 `==> N/M` 项块 ⇒ 编号必须 1..M 连续、
     写死的 `$((M - SKIPPED_COUNT))` 与中文写法也必须同一个数（本轮实测：`skip_step` 里
     还有一处写死的 `$1/18`，即同一数字在脚本里有五处）；
   - `count-file`：读 `Scripts/verify-core.sh` **同一次运行**写下的 `.build/core-test-count.txt`
     （`verify-all.sh` 在第 1 项之前删掉它 ⇒ 本轮没跑第 1 项时它不存在，
     判据如实报「跳过」而不是拿旧值当现状）；
   - `snapshot-manifest`：读 `.build/ui-snapshots/manifest.json` 数张数与组数。
   - `doc-tables-lists` / `doc-tables-run`（第 65 轮 L-72 ㈡）：`check-doc-tables.py` 的**清单口径**
     两个数 —— 「被 `.gitignore` 排除的份数」由**那个模块自己的** `gitignored_documents()` 算，
     判据再用 `git check-ignore -z` 实测一遍（**不是**信它的自述）并与它的自检夹具
     `SELF_TEST_ABSENT` / `SELF_TEST_TRACKED` 逐条对账；「受检文件数」= **真跑一遍那个脚本**
     （默认清单），从它自己的收尾行抓。读不到模块 / 跑不过 / 抓不到收尾行都判红。
3. **文档对账双向**：`anchors`（精确上下文正则 + 捕获组）每一处必须命中且值相等
   —— **写错判红 / 数字被删光也判红**；`reverseScans` 做有限反扫，在「现状口径」语境里
   凡出现的同类数字都必须是台账值（防「新增一处写错的数字」）。

**边界（如实登记，不假装判住）**：

- **不做全文反扫**：三书与开发记录里充满历史值（`十八项 → 十七项` 一路写下来），
  全文反扫会红一片而把真问题埋掉。反扫只覆盖台账登记的「现状语境」，
  缺口 = 「新增一处错误数字且不在反扫语境里」抓不到 ⇒ 已在 `doc-numbers.json` 的
  `notCovered` 里记明，连同逐族例数一起转队列 **L-72**。
- **扫描范围遵守红线第 6 条**：对侧独占节（`[独占:windows]` / `[独占:linux]`）内的行整段跳过
  —— 本侧不改对侧节，本侧也不拿它判红。本轮实测的现场：`Docs/概要设计.md` §8.5.3（`[独占:windows]`）
  里有一处「项数仍十七」是陈旧值，**本侧不改**（走提醒），判据在这里如实报「跳过 N 行」。
- **变更记录行整行跳过**（`| v1.2x` / `| **v2.6x**`）：历史值本来就该不同，那不是漂移。
- `checkScriptParity`：「有判据、没闭环」那一族 —— `Scripts/check-*.py` 每个都必须被
  `Scripts/verify-all.sh` 引用，或在台账里逐条登记理由（现有 1 条豁免：快照语言覆盖门禁）。

用法：
    python3 Scripts/check-doc-numbers.py                # 本仓（默认）
    python3 Scripts/check-doc-numbers.py --root <目录>   # 夹具仓（自测用）
    python3 Scripts/check-doc-numbers.py --self-test     # 判据自己的证据（11 例）

退出码：0 = 全绿；1 = 有判红项。**判红时空跑防护也一起报**（一处都没解析到 ⇒ 不许「零命中 = 通过」）。
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
LEDGER_REL = "Scripts/doc-numbers.json"
GATE_REL = "Scripts/verify-all.sh"

HEADING = re.compile(r"^(#{1,6})\s")
COUNTERPART_SECTION = re.compile(r"\[独占:(windows|linux)\]")
CHANGELOG_ROW = re.compile(r"^\s*\|\s*\*{0,2}v\d+\.\d+")
GATE_BLOCK = re.compile(r"==>\s*(\d+)/(\d+)")
GATE_CLOSE = re.compile(r"\$\(\((\d+)\s*-\s*SKIPPED_COUNT\)\)")
CHINESE_NUMERAL = re.compile(r"(?<![那这哪某每逐同第的])([一二三四五六七八九十]+)项")

MEASURE_KINDS = {"gate-scan", "count-file", "snapshot-manifest", "doc-tables-lists", "doc-tables-run"}
CN_DIGITS = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def cn_to_int(text: str) -> int | None:
    """十/十八/二十 这类写法转数字；判据与文档都只有小数目（≤ 几十），够用。"""
    if not text:
        return None
    if text == "十":
        return 10
    if text.startswith("十"):
        rest = text[1:]
        return 10 + CN_DIGITS.get(rest, 0) if rest else 10
    if text.endswith("十"):
        head = text[:-1]
        return CN_DIGITS.get(head, 0) * 10 if head else 10
    if "十" in text:
        head, _, tail = text.partition("十")
        return CN_DIGITS.get(head, 0) * 10 + (CN_DIGITS.get(tail, 0) if tail else 0)
    if len(text) == 1:
        return CN_DIGITS.get(text)
    return None


def normalize(token: str):
    """把捕获到的值规范化成可比较的东西：数字串 → int；中文数字 → int（比对时两侧都这么走）。"""
    token = token.strip()
    if token.isdigit():
        return int(token)
    value = cn_to_int(token)
    return value if value is not None else token


# 台账 skipSections：整节按**历史叙述**跳过（理由随台账逐条写明）。
# 与「变更记录行整行跳过」同族 —— 这些节里写的数字**本来就该和现状不一样**，反扫它们只会红一片。
SKIP_SECTIONS: dict[str, list[tuple[re.Pattern, re.Pattern]]] = {}


def load_skip_sections(ledger: dict):
    SKIP_SECTIONS.clear()
    for rule in ledger.get("skipSections") or []:
        SKIP_SECTIONS.setdefault(rule["file"], []).append(
            (re.compile(rule["from"]), re.compile(rule["to"]))
        )


def read_lines(root: pathlib.Path, rel: str, skip_changelog: bool = True):
    """读一份文本并按纪律裁剪：跳过对侧独占节、跳过变更记录行、跳过台账登记的「历史叙述」整节。
    返回 [(行号, 行)] 或 None（文件不在）。"""
    path = root / rel
    if not path.exists():
        return None
    lines = []
    skip_level = None
    section_skip = None
    for index, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        if section_skip is not None:
            if section_skip.search(line):
                section_skip = None
            continue
        for from_re, to_re in SKIP_SECTIONS.get(rel, ()):
            if from_re.search(line):
                section_skip = to_re
                break
        if section_skip is not None:
            continue
        heading = HEADING.match(line)
        if heading:
            level = len(heading.group(1))
            if skip_level is not None and level <= skip_level:
                skip_level = None
            elif COUNTERPART_SECTION.search(line):
                skip_level = level
        if skip_level is not None:
            continue
        if skip_changelog and CHANGELOG_ROW.match(line):
            continue
        lines.append((index, line))
    return lines


def count_counterpart_lines(root: pathlib.Path, rel: str) -> int:
    """如实报「有多少行因对侧独占节被跳过」（跳过 ≠ 通过：把它打印出来，别让人以为全查过）。"""
    path = root / rel
    if not path.exists():
        return 0
    skipped = 0
    skip_level = None
    for line in path.read_text(encoding="utf-8").split("\n"):
        heading = HEADING.match(line)
        if heading:
            level = len(heading.group(1))
            if skip_level is not None and level <= skip_level:
                skip_level = None
            elif COUNTERPART_SECTION.search(line):
                skip_level = level
        if skip_level is not None:
            skipped += 1
    return skipped


def load_doc_tables_module(root: pathlib.Path, rel: str, key, problems: list):
    """把 `Scripts/check-doc-tables.py` 当模块读进来 —— **清单口径的权威数据就写在那里**。

    为什么读真模块而不是在本判据里复刻一份清单：复刻 = 两套清单，改了 A 忘了 B 谁都不知道
    （本判据存在的理由就是这件事）。读不到 / 导入炸 ⇒ **判红**，不许静默跳过。
    """
    path = root / rel
    if not path.exists():
        problems.append(f"[{key}] 实测复核失败：找不到 {rel}（清单口径的权威数据在那里）")
        return None
    try:
        module_spec = importlib.util.spec_from_file_location("doyah_check_doc_tables", path)
        if module_spec is None or module_spec.loader is None:
            problems.append(f"[{key}] 实测复核失败：{rel} 取不到模块规格（路径 / 权限异常）")
            return None
        module = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(module)
    except Exception as error:  # noqa: BLE001 —— 模块级异常一律判红（「导入失败」也是证据坏了）
        problems.append(f"[{key}] 实测复核失败：{rel} 导入失败（{type(error).__name__}: {error}）")
        return None
    for attribute in ("DEFAULT_TARGETS", "DEFAULT_GLOBS", "SELF_TEST_ABSENT", "SELF_TEST_TRACKED", "gitignored_documents"):
        if not hasattr(module, attribute):
            problems.append(f"[{key}] 实测复核失败：{rel} 里没有 {attribute}（清单口径的入口被改名 / 删掉了）")
            return None
    return module


def measure(root: pathlib.Path, entry: dict, problems: list, notes: list):
    """实测复核：返回实测值列表，或 None（= 本机没有可实测的量 ⇒ 跳过，绝不拿台账自述当真）。"""
    spec = entry.get("measure") or {}
    kind = spec.get("kind")
    key = entry.get("key")

    if kind == "gate-scan":
        text = (root / GATE_REL).read_text(encoding="utf-8") if (root / GATE_REL).exists() else None
        if text is None:
            problems.append(f"[{key}] 实测复核失败：找不到 {GATE_REL}")
            return None
        blocks = [(int(a), int(b)) for a, b in GATE_BLOCK.findall(text)]
        if not blocks:
            problems.append(f"[{key}] 实测复核失败：{GATE_REL} 里一个 `==> N/M` 项块都没有（解析口径变了？）")
            return None
        totals = {b for _, b in blocks}
        numbers = sorted(a for a, _ in blocks)
        if len(totals) != 1:
            problems.append(f"[{key}] `==> N/M` 里的总数不唯一：{sorted(totals)} —— 项数在脚本里就自相矛盾")
        total = max(totals)
        if numbers != list(range(1, total + 1)):
            problems.append(f"[{key}] 项块编号不连续：得到 {numbers}，期望 1..{total}")
        for value in {m for m in GATE_CLOSE.findall(text)}:
            if int(value) != total:
                problems.append(f"[{key}] 收尾行写死 {value}，与项块数 {total} 不一致")
        for token in set(CHINESE_NUMERAL.findall(text)):
            if normalize(token) != total:
                problems.append(f"[{key}] 脚本里中文写法「{token}项」与项块数 {total} 不一致")
        return [total]

    if kind == "count-file":
        path = root / spec["file"]
        if not path.exists():
            notes.append(
                f"[{key}] 跳过实测：{spec['file']} 不在（本轮没跑到写它的那一步 —— {spec.get('writtenBy', '')}）"
            )
            return None
        match = re.search(spec.get("regex", r"(\d+)"), path.read_text(encoding="utf-8"))
        if not match:
            problems.append(f"[{key}] 实测复核失败：{spec['file']} 里解析不出数字（regex {spec.get('regex')!r}）")
            return None
        return [int(g) for g in match.groups()]

    if kind == "snapshot-manifest":
        path = root / spec["file"]
        if not path.exists():
            notes.append(
                f"[{key}] 跳过实测：{spec['file']} 不在（本轮没出快照 —— {spec.get('writtenBy', '')}）"
            )
            return None
        try:
            manifest = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            problems.append(f"[{key}] 实测复核失败：清单不是合法 JSON（{error}）")
            return None
        snapshots = manifest.get("snapshots") or []
        bases = set()
        for record in snapshots:
            name = record.get("name") or ""
            for suffix in ("-zh", "-en"):
                if name.endswith(suffix):
                    name = name[: -len(suffix)]
                    break
            bases.add(name)
        if not snapshots:
            problems.append(f"[{key}] 实测复核失败：清单里一条快照都没有（零命中不许当通过）")
            return None
        return [len(snapshots), len(bases)]

    if kind == "doc-tables-lists":
        # `check-doc-tables` 的**清单口径**（第 65 轮 L-72 ㈡）：两个数都由真模块 + git 实测算出来，
        # 并与自检夹具逐条对账 —— 清单改了没改夹具（或反过来）即判红。
        module = load_doc_tables_module(root, spec["module"], key, problems)
        if module is None:
            return None
        ignored = module.gitignored_documents()
        named = list(module.DEFAULT_TARGETS)
        if ignored is None:
            ignored = list(module.SELF_TEST_ABSENT)
            notes.append(
                f"[{key}] git 侧复核**跳过**：`{root}` 不是 git 仓库（`git check-ignore` 判不了）—— "
                f"「被 `.gitignore` 排除」这句在本轮**没有被实测**，只按模块里的清单计"
            )
        elif sorted(ignored) != sorted(module.SELF_TEST_ABSENT):
            problems.append(
                f"[{key}] 清单口径与自检夹具**脱钩**：`git check-ignore` 说被 `.gitignore` 排除的是 "
                f"{len(ignored)} 份，而 `SELF_TEST_ABSENT` 写着 {len(module.SELF_TEST_ABSENT)} 份"
                f"（两处必须逐条相同：夹具是「干净克隆」那一例的前提）"
            )
        tracked = [target for target in named if target not in set(ignored)]
        if sorted(tracked) != sorted(module.SELF_TEST_TRACKED):
            problems.append(
                f"[{key}] 跟踪文档集合与 `SELF_TEST_TRACKED` 不一致：{len(tracked)} 份 vs "
                f"{len(module.SELF_TEST_TRACKED)} 份"
            )
        return [len(ignored), len(tracked)]

    if kind == "doc-tables-run":
        # 真跑一遍 `check-doc-tables.py`（默认清单），拿它**自己的输出**当受检文件数 ——
        # 跑不过 / 抓不到收尾行都判红（格式被改坏 = 证据坏了，不许拿台账自述当真）。
        module = load_doc_tables_module(root, spec["module"], key, problems)
        if module is None:
            return None
        completed = subprocess.run(
            [sys.executable, str(root / spec["module"])],
            cwd=str(root),
            capture_output=True,
            text=True,
        )
        output = completed.stdout + completed.stderr
        if completed.returncode != 0:
            tail = output.strip().splitlines()[-1] if output.strip() else "无输出"
            problems.append(f"[{key}] 实测复核失败：{spec['module']} 默认跑 exit {completed.returncode}（{tail}）")
            return None
        match = re.search(spec["regex"], output)
        if not match:
            problems.append(
                f"[{key}] 实测复核失败：`{spec['module']}` 的输出里抓不到受检文件数"
                f"（regex {spec['regex']!r} —— 收尾行格式变了）"
            )
            return None
        return [int(match.group(1)), len(module.DEFAULT_TARGETS)]

    problems.append(f"[{key}] 台账的 measure.kind 不在词表内：{kind!r}（词表 {sorted(MEASURE_KINDS)}）")
    return None


def expected_values(entry: dict) -> list:
    values = [entry.get("value")]
    secondary = entry.get("secondary")
    if secondary:
        values.append(secondary.get("value"))
    return values


def scan_anchors(root: pathlib.Path, entry: dict, problems: list) -> int:
    key = entry.get("key")
    hits = 0
    expected = expected_values(entry)
    if any(v is None for v in expected):
        problems.append(f"[{key}] 台账缺 value（或 secondary.value）")
        return 0
    for anchor in entry.get("anchors") or []:
        rel = anchor.get("file")
        lines = read_lines(root, rel)
        if lines is None:
            problems.append(f"[{key}] 锚点文件不存在：{rel}")
            continue
        pattern = re.compile(anchor["regex"])
        expect = anchor.get("expect")
        if expect is None:
            expect = list(expected)
            if pattern.groups == 1 and entry.get("spellout") and "一二三四五六七八九十" in anchor["regex"]:
                expect = [entry["spellout"]]
        matches = []
        for index, line in lines:
            for hit in pattern.finditer(line):
                matches.append((index, hit))
        if len(matches) < anchor.get("minSites", 1):
            problems.append(
                f"[{key}] {rel}: 锚点只命中 {len(matches)} 处、要求 ≥ {anchor.get('minSites', 1)} 处"
                f"（数字被删或被改写；note = {anchor.get('note', '')}）"
            )
            continue
        for index, hit in matches:
            groups = list(hit.groups())
            if len(groups) != len(expect):
                problems.append(
                    f"[{key}] {rel}:{index}: 锚点捕获组数（{len(groups)}）与登记值数（{len(expect)}）不符"
                )
                continue
            for got, want in zip(groups, expect):
                if normalize(got) != normalize(str(want)):
                    problems.append(
                        f"[{key}] {rel}:{index}: 写的是「{got}」、台账值是「{want}」"
                        f"（note = {anchor.get('note', '')}）"
                    )
            hits += 1
    return hits


def scan_reverse(root: pathlib.Path, entry: dict, problems: list) -> int:
    key = entry.get("key")
    expected = expected_values(entry)
    hits = 0
    for rule in entry.get("reverseScans") or []:
        rel = rule["file"]
        lines = read_lines(root, rel)
        if lines is None:
            problems.append(f"[{key}] 反扫文件不存在：{rel}")
            continue
        context = re.compile(rule["contextRegex"])
        number = re.compile(rule["numberRegex"])
        for index, line in lines:
            if not context.search(line):
                continue
            for hit in number.finditer(line):
                hits += 1
                groups = [normalize(g) for g in hit.groups()]
                wants = [normalize(str(v)) for v in expected]
                if len(groups) != len(wants):
                    problems.append(
                        f"[{key}] {rel}:{index}: 反扫捕获到 {len(groups)} 个数字、台账登记 {len(wants)} 个"
                    )
                    continue
                if groups != wants:
                    problems.append(
                        f"[{key}] {rel}:{index}: 现状语境里的数字是 {groups}、台账值是 {wants}"
                        f"（note = {rule.get('note', '')}）"
                    )
    return hits


def check_script_parity(root: pathlib.Path, ledger: dict, problems: list, notes: list) -> int:
    parity = ledger.get("checkScriptParity") or {}
    glob = parity.get("glob")
    gate = parity.get("mustBeReferencedIn")
    if not glob or not gate:
        problems.append("[checkScriptParity] 台账缺 glob / mustBeReferencedIn")
        return 0
    gate_path = root / gate
    if not gate_path.exists():
        problems.append(f"[checkScriptParity] 找不到闭环脚本 {gate}")
        return 0
    gate_text = gate_path.read_text(encoding="utf-8")
    scripts = sorted((root / glob.rsplit("/", 1)[0]).glob(glob.rsplit("/", 1)[1]))
    if not scripts:
        problems.append(f"[checkScriptParity] 一个判据脚本都没找到（glob {glob}）—— 零命中不许当通过")
        return 0
    exempt = {item["script"]: item.get("reason", "") for item in parity.get("exempt") or []}
    exempt_seen = set()
    for script in scripts:
        rel = str(script.relative_to(root))
        if rel in gate_text:
            continue
        if rel in exempt:
            exempt_seen.add(rel)
            if not exempt[rel].strip():
                problems.append(f"[checkScriptParity] 豁免没写理由：{rel}")
            continue
        problems.append(
            f"[checkScriptParity] {rel} 没被 {gate} 引用（有判据、没闭环 —— 要么接进去，要么在台账里登记理由）"
        )
    for rel in exempt:
        if rel not in exempt_seen and rel in gate_text:
            problems.append(f"[checkScriptParity] {rel} 已经在闭环里了，台账里的豁免条目陈旧（请删掉）")
    notes.append(
        f"[checkScriptParity] 判据脚本 {len(scripts)} 个：被闭环引用 {len(scripts) - len(exempt_seen)} 个、"
        f"登记豁免 {len(exempt_seen)} 个"
    )
    return len(scripts)


def check(root: pathlib.Path):
    problems: list[str] = []
    notes: list[str] = []
    ledger_path = root / LEDGER_REL
    if not ledger_path.exists():
        return [f"找不到台账 {LEDGER_REL}"], notes
    try:
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return [f"台账不是合法 JSON：{error}"], notes

    load_skip_sections(ledger)
    for rule in ledger.get("skipSections") or []:
        for field in ("file", "from", "to", "reason"):
            if not rule.get(field):
                problems.append(f"skipSections 有一条缺 {field}（跳过必须写明理由，否则就是开天窗）")
        try:
            re.compile(rule.get("from", ""))
            re.compile(rule.get("to", ""))
        except re.error as error:
            problems.append(f"skipSections 的正则不合法（{rule.get('file')}）：{error}")
    if SKIP_SECTIONS:
        for rel, rules in SKIP_SECTIONS.items():
            for _from, _to in rules:
                notes.append(
                    f"skipSections 生效：{rel} 的 {_from.pattern} → {_to.pattern} 整节按**历史叙述**跳过"
                    f"（{next((r['reason'] for r in ledger['skipSections'] if r['file'] == rel), '')}）"
                )

    entries = ledger.get("numbers") or []
    if not entries:
        return ["台账里一条数字都没有（零命中不许当通过）"], notes

    seen_keys = set()
    hits = 0
    skipped_docs = 0
    for entry in entries:
        key = entry.get("key")
        if not key:
            problems.append("台账里有条目缺 key")
            continue
        if key in seen_keys:
            problems.append(f"[{key}] 台账里同一个 key 出现两次")
            continue
        seen_keys.add(key)

        # A 台账自洽
        if not isinstance(entry.get("value"), int):
            problems.append(f"[{key}] value 必须是整数")
            continue
        if not entry.get("unit"):
            problems.append(f"[{key}] 缺 unit")
        if not entry.get("anchors"):
            problems.append(f"[{key}] 缺 anchors（至少一条现状声明落点，否则这个数字没有任何文档面在管）")
        measure_spec = entry.get("measure") or {}
        if measure_spec.get("kind") not in MEASURE_KINDS:
            problems.append(f"[{key}] measure.kind 缺失或不在词表内")
        if measure_spec.get("expect") != expected_values(entry):
            problems.append(
                f"[{key}] measure.expect {measure_spec.get('expect')} 与 value/secondary "
                f"{expected_values(entry)} 不一致（台账自己就写错）"
            )

        # B 实测复核
        measured = measure(root, entry, problems, notes)
        if measured is not None and measured != measure_spec.get("expect"):
            problems.append(
                f"[{key}] 实测与台账不一致：实测 {measured}、台账 {measure_spec.get('expect')}"
            )

        # C 文档正向对账
        hits += scan_anchors(root, entry, problems)
        # D 有限反扫
        hits += scan_reverse(root, entry, problems)

        for anchor in entry.get("anchors") or []:
            skipped_docs += count_counterpart_lines(root, anchor["file"])
        for rule in entry.get("reverseScans") or []:
            skipped_docs += count_counterpart_lines(root, rule["file"])

    # E 空跑防护
    if hits == 0:
        problems.append("空跑防护：一处文档落点都没解析到 —— 「零命中 = 通过」是最典型的假绿")

    # F 「有判据、没闭环」
    hits += check_script_parity(root, ledger, problems, notes)

    notes.append(f"[scope] 文档落点命中 {hits} 处；因对侧独占节被跳过的行 {skipped_docs} 行（红线第 6 条：本侧不改的，本侧也不拿它判红）")
    return problems, notes


# ── 自测（判据自己的证据；夹具一律在临时目录的合成小仓里，末例核对真仓库逐字节未变）──

FIXTURE_LEDGER = {
    "version": 1,
    "checkScriptParity": {
        "glob": "Scripts/check-*.py",
        "mustBeReferencedIn": "Scripts/verify-all.sh",
        "exempt": [{"script": "Scripts/check-exempt.py", "reason": "夹具：已登记理由的豁免条目"}],
    },
    "numbers": [
        {
            "key": "gate-items",
            "label": "闭环项数",
            "value": 18,
            "unit": "项",
            "spellout": "十八",
            "measure": {"kind": "gate-scan", "script": "Scripts/verify-all.sh", "expect": [18]},
            "anchors": [
                {"file": "AGENT-SPEC.md", "regex": "一条命令闭环（\\*\\*([一二三四五六七八九十]+)项\\*\\*）", "minSites": 1},
                {"file": "Scripts/verify-all.sh", "regex": "跑它，([一二三四五六七八九十]+)项全过", "minSites": 1},
            ],
            "reverseScans": [
                {
                    "file": "AGENT-SPEC.md",
                    "contextRegex": "(verify-all|闭环)",
                    "numberRegex": "([一二三四五六七八九十]+)项",
                }
            ],
        },
        {
            "key": "core-tests",
            "label": "单测项数",
            "value": 2056,
            "unit": "项",
            "measure": {"kind": "count-file", "file": ".build/core-test-count.txt", "regex": "(\\d+)", "expect": [2056]},
            "anchors": [{"file": "AGENT-SPEC.md", "regex": "单测 \\*\\*(\\d{3,5})\\*\\* 项", "minSites": 1}],
        },
        {
            "key": "ui-snapshots",
            "label": "快照张数",
            "value": 152,
            "unit": "张",
            "secondary": {"label": "组", "value": 76},
            "measure": {"kind": "snapshot-manifest", "file": ".build/ui-snapshots/manifest.json", "expect": [152, 76]},
            "anchors": [{"file": "AGENT-SPEC.md", "regex": "快照 \\*\\*(\\d+) 张 / (\\d+) 组\\*\\*", "minSites": 1}],
        },
    ],
}


def build_fixture(base: pathlib.Path, ledger: dict | None = None, gate_items: int = 18, snapshots=(152, 76), count=2056):
    shutil.rmtree(base, ignore_errors=True)
    (base / "Scripts").mkdir(parents=True)
    (base / "Docs").mkdir(parents=True)
    (base / ".build" / "ui-snapshots").mkdir(parents=True)
    (base / LEDGER_REL).write_text(
        json.dumps(ledger if ledger is not None else FIXTURE_LEDGER, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    word = "十八" if gate_items == 18 else "十七"
    gate = ["#!/bin/bash", "# 改完代码跑它，%s项全过才算完" % word]
    for index in range(1, gate_items + 1):
        gate.append('echo "==> %d/%d 第 %d 项"' % (index, gate_items, index))
    gate.append('echo "跑 $((%d - SKIPPED_COUNT)) 项"' % gate_items)
    (base / GATE_REL).write_text("\n".join(gate) + "\n", encoding="utf-8")
    (base / "AGENT-SPEC.md").write_text(
        "\n".join(
            [
                "# 夹具入口",
                "./Scripts/verify-all.sh        # %s项，先确认基线是绿的" % word,
                "| 一条命令闭环（**%s项**） | `Scripts/verify-all.sh` | 夹具行 |" % word,
                "- **门禁**：`./Scripts/verify-all.sh` **%s项全绿**；Core 单测 **%d** 项 0 failures；界面快照 **%d 张 / %d 组**"
                % (word, count, snapshots[0], snapshots[1]),
                "| v1.1 | 2026-01-01 | 历史行：当时是 十七项、单测 1947 项、快照 19 张 / 10 组 |",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (base / ".build" / "core-test-count.txt").write_text("%d tests\n" % count, encoding="utf-8")
    (base / ".build" / "ui-snapshots" / "manifest.json").write_text(
        json.dumps(
            {"snapshots": [{"name": "panel-%d-zh" % i, "file": "x"} for i in range(snapshots[0] // 2)]
             + [{"name": "panel-%d-en" % i, "file": "y"} for i in range(snapshots[0] // 2)]},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    (base / "Scripts" / "check-fine.py").write_text("# fine\n", encoding="utf-8")
    (base / "Scripts" / "check-exempt.py").write_text("# exempt\n", encoding="utf-8")
    (base / "Scripts" / "verify-all.sh").write_text(
        (base / GATE_REL).read_text(encoding="utf-8") + "python3 Scripts/check-fine.py\n", encoding="utf-8"
    )
    return base


def self_test() -> int:
    real_gate = (REPO / GATE_REL).read_bytes()
    real_spec = (REPO / "AGENT-SPEC.md").read_bytes()
    real_ledger = (REPO / LEDGER_REL).read_bytes()
    cases = []

    def run(name, mutate, expect_red, expect_text=None):
        cases.append((name, mutate, expect_red, expect_text))

    def clean(base):
        return build_fixture(base)

    run("① 干净夹具 ⇒ exit 0", lambda b: clean(b), False)
    run(
        "② 台账值写错（18 → 19）⇒ 实测复核判红",
        lambda b: build_fixture(b, ledger={**FIXTURE_LEDGER, "numbers": [{**FIXTURE_LEDGER["numbers"][0], "value": 19, "measure": {"kind": "gate-scan", "script": GATE_REL, "expect": [19]}}]}),
        True,
    )
    run(
        "③ 闭环脚本少一个项块 ⇒ 编号不连续判红",
        lambda b: build_fixture(b, gate_items=17),
        True,
    )
    run(
        "④ 文档写的数字与台账不符（十八 → 十七）⇒ 双向对账判红并点名",
        lambda b: _mutate(b, "AGENT-SPEC.md", "**十八项全绿**", "**十七项全绿**"),
        True,
        "17",
    )
    run(
        "⑤ 文档里的现状声明被删光 ⇒ 锚点判红（不许『没有了就当通过』）",
        lambda b: _mutate(b, "AGENT-SPEC.md", "| 一条命令闭环（**十八项**） | `Scripts/verify-all.sh` | 夹具行 |", ""),
        True,
    )
    run(
        "⑥ 单测数同一次运行实测与台账不符 ⇒ 判红",
        lambda b: build_fixture(b, count=2050),
        True,
    )
    run(
        "⑦ 快照组数与台账不符 ⇒ 判红",
        lambda b: build_fixture(b, snapshots=(152, 70)),
        True,
    )
    run(
        "⑧ 判据脚本没进闭环且没登记理由 ⇒ 判红（有判据没闭环）",
        lambda b: (clean(b), (b / "Scripts" / "check-orphan.py").write_text("# orphan\n", encoding="utf-8")),
        True,
    )
    run(
        "⑨ 台账写坏（缺 anchors）⇒ 自洽判红",
        lambda b: build_fixture(b, ledger={**FIXTURE_LEDGER, "numbers": [{k: v for k, v in FIXTURE_LEDGER["numbers"][0].items() if k != "anchors"}]}),
        True,
    )
    run(
        "⑩ 新 kind（`doc-tables-lists`）的模块不在盘上 ⇒ 判红，不许静默跳过",
        lambda b: build_fixture(
            b,
            ledger={
                **FIXTURE_LEDGER,
                "numbers": [
                    {
                        "key": "doc-tables-lists",
                        "label": "夹具：清单口径",
                        "value": 1,
                        "unit": "份",
                        "measure": {
                            "kind": "doc-tables-lists",
                            "module": "Scripts/不存在-的-门禁.py",
                            "expect": [1],
                        },
                        "anchors": [{"file": "AGENT-SPEC.md", "regex": "(夹具)入口", "minSites": 1}],
                    }
                ],
            },
        ),
        True,
        "找不到",
    )

    failures = []
    with tempfile.TemporaryDirectory(prefix="doc-numbers-selftest-") as temp:
        for index, (name, mutate, expect_red, *rest) in enumerate(cases):
            base = pathlib.Path(temp) / f"case{index}"
            mutate(base)
            problems, _ = check(base)
            red = bool(problems)
            if red != expect_red:
                failures.append(f"{name}：期望{'判红' if expect_red else '绿'}、实际{'判红' if red else '绿'}：{problems[:2]}")
                continue
            if rest and rest[0] and not any(rest[0] in p for p in problems):
                failures.append(f"{name}：判红理由里没有点名「{rest[0]}」：{problems[:2]}")
                continue
            print(f"  ✅ {name}")

        # 末例：真仓库逐字节未变 + 真仓库实跑
        for rel, before in ((GATE_REL, real_gate), ("AGENT-SPEC.md", real_spec), (LEDGER_REL, real_ledger)):
            if (REPO / rel).read_bytes() != before:
                failures.append(f"末例：真仓库 {rel} 被自测改动了（夹具必须只落在临时目录）")
        problems, _ = check(REPO)
        if problems:
            failures.append(f"末例：真仓库应当是绿的，实际判红 {len(problems)} 条：{problems[:3]}")
        if not failures:
            print("  ✅ 末例：真仓库三份文件逐字节未变，且真仓库实跑 exit 0")

    if failures:
        print(f"\n❌ 自测未通过（{len(failures)} 例）：")
        for item in failures:
            print(f"   · {item}")
        return 1
    print(f"\n✅ 自测通过（{len(cases) + 1} 例）")
    return 0


def _mutate(base: pathlib.Path, rel: str, old: str, new: str):
    build_fixture(base)
    path = base / rel
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具里找不到要改的文本：{old!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(REPO))
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--report", action="store_true", help="打印台账里的每个数字（人读用）")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    root = pathlib.Path(args.root).resolve()
    problems, notes = check(root)

    if args.report:
        ledger = json.loads((root / LEDGER_REL).read_text(encoding="utf-8"))
        print(f"📒 台账 {LEDGER_REL}（v{ledger.get('version')}）：{len(ledger.get('numbers') or [])} 个数字")
        for entry in ledger.get("numbers") or []:
            extra = f"（或 {entry['secondary']['value']} {entry['secondary']['label']}）" if entry.get("secondary") else ""
            print(f"   · {entry['key']} = {entry['value']} {entry.get('unit', '')}{extra}")
        return 0

    for note in notes:
        print(f"ℹ️ {note}")
    if problems:
        print(f"\n❌ 文档数字对账未通过（{len(problems)} 项）：")
        for item in problems:
            print(f"   · {item}")
        return 1
    print("\n✅ 文档数字对账通过（台账 ↔ 实测 ↔ 文档 三向一致）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
