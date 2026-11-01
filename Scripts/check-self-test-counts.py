#!/usr/bin/env python3
"""「门禁自己的证据」的例数台账 + 实跑对账（队列 L-72 ㈠，闭环第 4 项）。

**为什么要有它**（第 65 轮）：每一族负例 / 自检的例数此前在 `AGENT-SPEC.md` §6 资产表、
脚本自己的 docstring、spec 与开发记录里**各写一遍** —— 例数被删一个、runner 的收尾行格式被改坏、
夹具锚点随源码重构失效，谁都说话。同族更严重的一层：`Scripts/test-*.py` 这 14 个「门禁自己的证据」
**没有任何门禁管**（`doc-numbers.json` 的「有判据、没闭环」对账只覆盖 `check-*.py`）⇒
其中 8 个当时**根本没人跑**。实测现场：`Scripts/test-plugin-assembly-gates.py` 每次都在第 3 例崩掉
（`Core/AICapture.swift` 的 `sqlNote` 签名改成多行 + 多一个 `tag:` 参数，夹具锚点还是老单行签名），
**没人发现**。判据写完不对已知改动报红 = 没有判据。

**口径**：

1. **唯一来源 = `Scripts/self-test-counts.json`**（照 `doc-numbers.json` / `vendored-sqlite.json` 的做法）。
2. **能机械复算的必须复算** —— 本判据不看台账的自述：**把每一族 runner 真跑一遍**，
   要求 `exit 0`（崩了 = 这一族的负例没跑），再从它的输出里按台账登记的 `countRegex` 抓例数。
   抓不到 ⇒ 判红（**不许静默跳过**：收尾行格式被改坏本身就是「证据坏了」）。
3. **每族有独立墙钟上限**（默认 300s，台账可用家族的 `timeout` 覆写）：超时**判红**，
   不是「跳过」。`2026-11-02` 现场：默认 900s 时某个 runner 卡在 `communicate` 的
   `selectors.select` 上（父进程早退、孙进程握着管道），全跑只能记「未知」；
   现在超时**整组 SIGKILL**（`start_new_session` + `killpg`），且每族起跑/收尾各打一行
   进度（卡住时最后一行就是卡住的那一族）。
4. **文档对账**：台账登记的每一处「现状声明」（精确上下文正则 + 捕获组 + `minSites`）
   捕获到的数字必须等于 `cases`；写错 / 数字被删光都判红。
   `expect` 用于「同一格同时写着历史值与现状值」的写法（§6 的 `17 → 27 例`）。
5. **没有锚点要有理由**：`noAnchorReason` 必须写明（「没有锚点」与「没人看过」不是一回事）。
6. **静态棘轮**（可选 `sourceRatchet`）：例数在 runner 里是 `len()` 算出来、源码里没有字面量的族
   （`--check-anchors` 那一族），按正则数脚本里的用例定义条数，必须 == `cases`（否则「删掉一个用例」
   在 runner 那一侧只是数字变小）。
7. **空跑防护**：族数 / 例数合计 / 锚点命中处数三条下限，低于即判红。
8. **本机台账不在盘上时，那几族自检如实跳过**（2026-10-08 · 任务 `t_004a679b`）：有的族的
   `--self-test` 要读**真仓库那几份本机台账**（`.gitignore` 内、只在主开发机上）—— 如
   `check-doc-q-series` / `check-queue-needs-user` 要 `design/开发循环-任务队列.md` 与
   `智能体助手-开发规范.md`。干净克隆 / 并行工作树 / 另一平台**没有它们** ⇒ 那几族如实打印
   「干净克隆上跳过」、**退出 0、不打例数**（不是崩、也不是静默）。这样的族在台账里登记
   `hostLedgerSelfTest`（`files` 真缺 **且** `marker` 命中才算跳过）—— **两个条件都满足才认**，
   否则照旧判红（口径出处 = `AGENT-SPEC.md` §9 第 147 条 ④；在**主开发机**上这条永不生效）。

**边界（如实登记，不假装判住）**：

- 只判**例数**，不判例子的内容，也不判「这一族的判据覆盖了该覆盖的口径」（那是每个门禁自己的事）。
- 只扫**版本控制内**的文件（`AGENT-SPEC.md` / `Scripts/*`）：`spec` / `开发记录` / `任务队列`
  在 `.gitignore` 内、每轮都被写且含大量历史值 ⇒ 不在锚点范围（见台账 `notCovered`）。
- **不做全文反扫**（同族历史值太多，反扫会红一片而把真问题埋掉）：只查台账登记的落点。
  ⇒ 缺口 = 「新增一处写错的例数且不在登记的落点里」抓不到，已在 `notCovered` 记明。
- 本判据**自己跑别人的负例脚本**：那些脚本一律只在临时目录里写坏（`test-plugin-assembly-gates.py`
  的完整跑法会临时改真源码 ⇒ 本判据只跑它的只读那一半 `--check-anchors`）。

用法：
    python3 Scripts/check-self-test-counts.py                # 本仓（默认）
    python3 Scripts/check-self-test-counts.py --root <目录>   # 夹具仓（自测用）
    python3 Scripts/check-self-test-counts.py --no-run       # 只做台账/锚点对账（调试用，不跑 runner）
    python3 Scripts/check-self-test-counts.py --self-test    # 判据自己的证据（12 例）
    python3 Scripts/check-self-test-counts.py --family-timeout 60   # 单族墙钟上限（默认 300s）

退出码：0 = 全绿；1 = 有判红项。
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

REPO = pathlib.Path(__file__).resolve().parent.parent
LEDGER_REL = "Scripts/self-test-counts.json"

HEADING = re.compile(r"^(#{1,6})\s")
COUNTERPART_SECTION = re.compile(r"\[独占:(windows|linux)\]")
CHANGELOG_ROW = re.compile(r"^\s*\|\s*\*{0,2}v\d+\.\d+")

CN_DIGITS = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def cn_to_int(text: str) -> int | None:
    """十/十八/二十 这类写法转数字（文档里写中文数字时用它比对）。"""
    if not text:
        return None
    if text == "十":
        return 10
    if text.startswith("十"):
        rest = text[1:]
        return 10 + CN_DIGITS.get(rest, 0)
    if text.endswith("十"):
        head = text[:-1]
        return CN_DIGITS.get(head, 0) * 10
    if "十" in text:
        head, _, tail = text.partition("十")
        return CN_DIGITS.get(head, 0) * 10 + (CN_DIGITS.get(tail, 0) if tail else 0)
    if len(text) == 1:
        return CN_DIGITS.get(text)
    return None


def normalize(token) -> int | str:
    token = str(token).strip()
    if token.isdigit():
        return int(token)
    value = cn_to_int(token)
    return value if value is not None else token


SKIP_SECTIONS: dict[str, list[tuple[re.Pattern, re.Pattern]]] = {}


def load_skip_sections(ledger: dict) -> None:
    """台账 skipSections：整节按**历史叙述**跳过（理由随台账逐条写明）。"""
    SKIP_SECTIONS.clear()
    for rule in ledger.get("skipSections") or []:
        SKIP_SECTIONS.setdefault(rule["file"], []).append(
            (re.compile(rule["from"]), re.compile(rule["to"]))
        )


def read_lines(root: pathlib.Path, rel: str):
    """读一份文本并按纪律裁剪：跳过对侧独占节（红线第 6 条）、变更记录行（历史值本来就该不同）、
    台账登记的「历史叙述」整节。返回 [(行号, 行)] 或 None（文件不在）。"""
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
            # **两段独立判定**（合册 `T-20261013-027` / 原单 `T-20261010-029`）：与
            # `Scripts/check-doc-numbers.py` 同一份结构、同一个缺陷 —— `elif` 让「结束上一段跳过」
            # 挡掉「开启新段跳过」，相邻同级对侧节的第二节整节漏跳过。
            if skip_level is not None and level <= skip_level:
                skip_level = None
            if skip_level is None and COUNTERPART_SECTION.search(line):
                skip_level = level
        if skip_level is not None:
            continue
        if CHANGELOG_ROW.match(line):
            continue
        lines.append((index, line))
    return lines


def validate_ledger(ledger: dict, root: pathlib.Path) -> list[str]:
    problems: list[str] = []
    families = ledger.get("families")
    if not isinstance(families, list) or not families:
        return ["台账里一个族都没有（零族不许当通过）"]
    floors = ledger.get("floors") or {}
    for field in ("families", "totalCases", "anchorSites"):
        if not isinstance(floors.get(field), int):
            problems.append(f"[台账] floors.{field} 缺失或不是整数（空跑防护不许留空）")

    seen: set[str] = set()
    for index, family in enumerate(families, 1):
        key = family.get("key")
        label = f"[台账] 第 {index} 族"
        if not key or not isinstance(key, str):
            problems.append(f"{label} 缺 key")
            key = f"#{index}"
        if key in seen:
            problems.append(f"[台账] key 重复：{key}（例数台账按 key 认族，重复就认不出是谁）")
        seen.add(key)
        label = f"[{key}]"

        script = family.get("script")
        if not script or not (root / script).exists():
            problems.append(f"{label} 脚本不存在：{script!r}")
        if not isinstance(family.get("cases"), int) or family.get("cases", 0) <= 0:
            problems.append(f"{label} cases 缺失或不是正整数")
        if not family.get("why"):
            problems.append(f"{label} 缺 why（这族是谁的证据、归哪个闭环项）")

        pattern_text = family.get("countRegex")
        if not pattern_text:
            problems.append(f"{label} 缺 countRegex（抓不到例数 = 这族没人看）")
        else:
            try:
                if re.compile(pattern_text).groups < 1:
                    problems.append(f"{label} countRegex 一个捕获组都没有")
            except re.error as error:
                problems.append(f"{label} countRegex 不合法：{error}")

        anchors = family.get("anchors") or []
        if not anchors and not (family.get("noAnchorReason") or "").strip():
            problems.append(f"{label} 既没有 anchors、也没写 noAnchorReason（数字没人看，也不说为什么）")
        for anchor in anchors:
            for field in ("file", "regex", "minSites", "note"):
                if not anchor.get(field):
                    problems.append(f"{label} 锚点缺 {field}（note 是给下一次改的人看的）")
            try:
                groups = re.compile(anchor.get("regex", "")).groups
            except re.error as error:
                problems.append(f"{label} 锚点正则不合法（{anchor.get('file')}）：{error}")
                continue
            expect = anchor.get("expect")
            if expect is not None and len(expect) != groups:
                problems.append(
                    f"{label} 锚点的 expect 有 {len(expect)} 个值、正则有 {groups} 个捕获组（对不上）"
                )

        ratchet = family.get("sourceRatchet")
        if ratchet:
            for field in ("file", "regex", "note"):
                if not ratchet.get(field):
                    problems.append(f"{label} sourceRatchet 缺 {field}")
            try:
                re.compile(ratchet.get("regex", ""))
            except re.error as error:
                problems.append(f"{label} sourceRatchet 正则不合法：{error}")

        # `hostLedgerSelfTest`（2026-10-08 · 任务 `t_004a679b`）：这一族的自检要读真仓库那几份
        # 本机台账；全缺时它如实跳过、不打例数。三个字段缺一不可（跳过要写理由，不许静默）。
        host_ledgers = family.get("hostLedgerSelfTest")
        if host_ledgers is not None:
            if not (host_ledgers.get("files") or []):
                problems.append(f"{label} hostLedgerSelfTest 缺 files（要写明它读哪几份本机台账）")
            if not (host_ledgers.get("marker") or "").strip():
                problems.append(f"{label} hostLedgerSelfTest 缺 marker（要写明那一族跳过的原话）")
            if not (host_ledgers.get("note") or "").strip():
                problems.append(f"{label} hostLedgerSelfTest 缺 note（跳过要写理由，不静默）")
    return problems


def _kill_tree(process: subprocess.Popen) -> None:
    """整组 SIGKILL。

    **为什么不能只 `process.kill()`**（2026-11-02 实测）：`capture_output` 是一条管道，
    runner 若自己起了子进程（或 shell 套 shell）而那个孙进程继承了 stdout，父进程被杀之后
    管道**仍然有人握着** —— `subprocess.run` 的超时分支会再调一次 `communicate()`，于是
    `timeout=` 形同虚设，整条链卡死在 `selectors.select`（实测 8 分钟 0% CPU、无子进程，
    全跑记「未知」）。`start_new_session=True` 让 runner 自成一组，这里按组杀，孙进程一起收。
    """
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            process.kill()
        except ProcessLookupError:
            pass


def run_family(
    root: pathlib.Path,
    family: dict,
    problems: list,
    notes: list,
    timeout: int,
    progress: str = "",
) -> None:
    """真跑一遍 runner，要求 exit 0，再按 countRegex 抓例数并与台账比对。

    `timeout` = 这一族的墙钟上限（台账可用 `timeout` 字段逐族覆写）：超时**判红**，
    不静默跳过 —— 「没跑完」与「跑过并通过」是两件事。
    """
    key = family["key"]
    if not family.get("countRegex"):
        # 结构问题已在 validate_ledger 里报过；这里不再崩，只跳过实跑。
        return
    script = root / family["script"]
    command = [sys.executable, str(script), *(family.get("args") or [])]
    limit = family.get("timeout") if isinstance(family.get("timeout"), int) else timeout
    # 先打印「正在跑谁」：卡住时最后一行就是卡住的那一族（不然只有一片沉默）。
    if progress:
        print(f"   {progress} {key} …", file=sys.stderr, flush=True)
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            command,
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
    except OSError as error:
        problems.append(f"[{key}] runner 起不来：{error}")
        return
    try:
        output = process.communicate(timeout=limit)[0] or ""
        returncode = process.returncode
    except subprocess.TimeoutExpired:
        _kill_tree(process)
        # 杀完整组后再等一次，但**必须有限**：孙进程若已脱离该组（例如自己 setsid 守护化），
        # 管道仍可能不关；这时宁可丢掉输出也要返回「超时」，不许把判据自己挂死。
        try:
            output = process.communicate(timeout=5)[0] or ""
        except subprocess.TimeoutExpired:
            output = ""
            try:
                if process.stdout is not None:
                    process.stdout.close()
            except OSError:
                pass
            process.wait(timeout=5)
        elapsed = time.monotonic() - started
        tail = "\n".join(output.strip().splitlines()[-6:])
        problems.append(
            f"[{key}] runner 超时（{limit}s，已整组 SIGKILL，实际 {elapsed:.1f}s）：{' '.join(command)}"
            + (f"\n超时前输出尾部：\n{tail}" if tail else "\n超时前无输出")
        )
        return
    if progress:
        print(f"   {progress} {key} 完 ({time.monotonic() - started:.1f}s)", file=sys.stderr, flush=True)
    if returncode != 0:
        tail = "\n".join(output.strip().splitlines()[-12:])
        problems.append(
            f"[{key}] runner 退出码 {returncode}（必须 0）—— 这一族的负例**根本没跑**。"
            f"输出尾部：\n{tail}"
        )
        return

    matches = list(re.finditer(family["countRegex"], output))
    if not matches:
        # 台账登记了 `hostLedgerSelfTest` 的族：它的自检要读真仓库那几份本机台账（`.gitignore` 内、
        # 只在主开发机上）⇒ 台账**真缺**、且它自己**说了跳过**，两个条件都满足才认（跳过 ≠ 通过）。
        # 主开发机上台账在盘 ⇒ 这条分支永不生效，收尾行被改坏照样判红（口径 = `AGENT-SPEC.md` §9 第 147 条 ④）。
        skip_rule = family.get("hostLedgerSelfTest") or {}
        declared = skip_rule.get("files") or []
        if declared and all(not (root / rel).exists() for rel in declared) and re.search(
            skip_rule.get("marker", ""), output
        ):
            notes.append(
                f"[{key}] 跳过实跑：本机台账 {'、'.join(declared)} 不在盘上，"
                f"这一族的自检如实跳过（跳过 ≠ 通过；{skip_rule.get('note', '')}）"
            )
            return
        tail = "\n".join(output.strip().splitlines()[-6:])
        problems.append(
            f"[{key}] 解析不到例数（countRegex = {family['countRegex']!r}）—— 收尾行格式被改坏，"
            f"不许静默跳过。输出尾部：\n{tail}"
        )
        return
    groups = []
    for token in matches[-1].groups():
        try:
            groups.append(int(token))
        except (TypeError, ValueError):
            problems.append(f"[{key}] 收尾行抓到的不是数字：{token!r}")
            return
    for value in groups:
        if value != family["cases"]:
            problems.append(
                f"[{key}] runner 报 {value} 例、台账是 {family['cases']} 例"
                f"（改了例子就要改台账与文档，改完一起提交）"
            )
    notes.append(f"[{key}] 实跑 {groups[-1]} 例（要求全部 == {family['cases']}）")


def scan_source_ratchet(root: pathlib.Path, family: dict, problems: list) -> None:
    ratchet = family.get("sourceRatchet")
    if not ratchet:
        return
    key = family["key"]
    lines = read_lines(root, ratchet["file"])
    if lines is None:
        problems.append(f"[{key}] sourceRatchet 文件不存在：{ratchet['file']}")
        return
    pattern = re.compile(ratchet["regex"])
    hits = sum(1 for _, line in lines if pattern.search(line))
    if hits != family["cases"]:
        problems.append(
            f"[{key}] {ratchet['file']} 里的用例定义有 {hits} 条、台账是 {family['cases']} 条"
            f"（note = {ratchet['note']}）"
        )


def scan_anchors(root: pathlib.Path, family: dict, problems: list) -> int:
    key = family["key"]
    expected = family["cases"]
    hits_total = 0
    for anchor in family.get("anchors") or []:
        rel = anchor["file"]
        lines = read_lines(root, rel)
        if lines is None:
            problems.append(f"[{key}] 锚点文件不存在：{rel}")
            continue
        pattern = re.compile(anchor["regex"])
        expect = anchor.get("expect") or [expected] * pattern.groups
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
                if normalize(got) != normalize(want):
                    problems.append(
                        f"[{key}] {rel}:{index}: 写的是「{got}」、台账值是「{want}」"
                        f"（note = {anchor.get('note', '')}）"
                    )
            hits_total += 1
    return hits_total


def check(root: pathlib.Path, run_runners: bool = True, timeout: int = 300):
    problems: list[str] = []
    notes: list[str] = []
    ledger_path = root / LEDGER_REL
    if not ledger_path.exists():
        return [f"找不到台账 {LEDGER_REL}"], notes, {}
    try:
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return [f"台账不是合法 JSON：{error}"], notes, {}

    problems.extend(validate_ledger(ledger, root))
    load_skip_sections(ledger)
    for rule in ledger.get("skipSections") or []:
        for field in ("file", "from", "to", "reason"):
            if not rule.get(field):
                problems.append(f"skipSections 有一条缺 {field}（跳过必须写明理由，否则就是开天窗）")
    families = ledger.get("families") or []

    anchor_hits = 0
    cases_total = 0
    runnable = sum(1 for f in families if isinstance(f.get("cases"), int) and f.get("countRegex"))
    seen = 0
    for family in families:
        if not isinstance(family.get("cases"), int):
            continue
        cases_total += family["cases"]
        if run_runners:
            seen += 1
            run_family(root, family, problems, notes, timeout, progress=f"[{seen}/{runnable}]")
        else:
            notes.append(f"[{family.get('key')}] 跳过实跑（--no-run）：只做台账与锚点对账")
        scan_source_ratchet(root, family, problems)
        anchor_hits += scan_anchors(root, family, problems)

    floors = ledger.get("floors") or {}
    if isinstance(floors.get("families"), int) and len(families) < floors["families"]:
        problems.append(f"[空跑防护] 台账只有 {len(families)} 族、下限 {floors['families']} 族")
    if isinstance(floors.get("totalCases"), int) and cases_total < floors["totalCases"]:
        problems.append(f"[空跑防护] 例数合计只有 {cases_total}、下限 {floors['totalCases']}")
    if isinstance(floors.get("anchorSites"), int) and anchor_hits < floors["anchorSites"]:
        problems.append(
            f"[空跑防护] 锚点命中只有 {anchor_hits} 处、下限 {floors['anchorSites']} 处"
            f"（锚点被成片删掉时，'没命中' 与 '没查' 必须区分开）"
        )

    stats = {
        "families": len(families),
        "cases": cases_total,
        "anchors": anchor_hits,
        "noAnchor": sum(1 for f in families if not (f.get("anchors") or [])),
    }
    return problems, notes, stats


# ── 判据自己的证据 ───────────────────────────────────────────────────────────
# 十二例：好情况全绿 / runner 非零退出 / 例数漂移 / 收尾行解析不到 / 锚点值写错 /
# 锚点被删（minSites 不满足）/ 台账结构错（重复 key、缺 countRegex）/ 空跑防护 /
# 静态棘轮（对齐 + 用例被删）/ runner 卡住不放（判红 + 及时返回 + 孙进程一起收）/
# 末例核对真仓库逐字节未变。夹具一律在临时目录里（真仓库一个字节都不动）。

FIXTURE_SCRIPTS = {
    "good.py": 'print("✅ 例子 3/3 达到预期")\n',
    "bad.py": 'import sys\nprint("boom")\nsys.exit(1)\n',
    "drift.py": 'print("✅ 例子 4/4 达到预期")\n',
    "unparsable.py": 'print("✅ 都过了")\n',
    "cases.py": 'print("case 1")\nprint("case 2")\nprint("✅ 全部 2 个负例的夹具锚点都在位")\n',
    # 例 10 的夹具：**卡住不放**的 runner —— 父进程睡 60s，同时起一个继承 stdout 的孙进程，
    # 并把孙进程 pid 写进 argv[1]。这正是真实现场的形状（父已死、孙进程还握着管道 ⇒
    # `communicate` 停在 `selectors.select` 等 EOF）。
    "hang.py": (
        "import subprocess, sys, time\n"
        'child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])\n'
        "open(sys.argv[1], \"w\").write(str(child.pid))\n"
        'print("✅ 例子 3/3 达到预期", flush=True)\n'
        "time.sleep(60)\n"
    ),
}

GOOD_FAMILY = {
    "key": "good",
    "script": "Scripts/good.py",
    "args": [],
    "cases": 3,
    "countRegex": "例子 (\\d+)/\\d+ 达到预期",
    "why": "自测夹具：好情况",
    "anchors": [
        {
            "file": "AGENT-SPEC.md",
            "regex": "`Scripts/good\\.py`[^\\n]*?\\*\\*(\\d+) 例\\*\\*",
            "minSites": 1,
            "note": "自测夹具锚点",
        }
    ],
}

FIXTURE_SPEC = "| 资产 | 位置 | 说明 |\n|---|---|---|\n| 好情况 | `Scripts/good.py` | 负例 **3 例**（自测夹具） |\n"


def write_fixture(scratch: pathlib.Path, ledger: dict, spec_text: str = FIXTURE_SPEC) -> pathlib.Path:
    root = scratch / "repo"
    (root / "Scripts").mkdir(parents=True, exist_ok=True)
    for name, text in FIXTURE_SCRIPTS.items():
        (root / "Scripts" / name).write_text(text, encoding="utf-8")
    (root / "AGENT-SPEC.md").write_text(spec_text, encoding="utf-8")
    (root / LEDGER_REL).write_text(json.dumps(ledger, ensure_ascii=False, indent=2), encoding="utf-8")
    return root


def fixture_ledger(families: list, floors: dict | None = None) -> dict:
    return {
        "version": 1,
        "families": families,
        "floors": floors or {"families": 1, "totalCases": 1, "anchorSites": 1},
    }


def run_gate(root: pathlib.Path, extra: list[str] | None = None):
    command = [sys.executable, str(pathlib.Path(__file__).resolve()), "--root", str(root), *(extra or [])]
    completed = subprocess.run(command, capture_output=True, text=True)
    return completed.returncode, completed.stdout + completed.stderr


def run_self_test() -> int:
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-self-test-counts-"))
    results: list[tuple[str, bool, str]] = []
    before = {
        rel: (REPO / rel).read_bytes()
        for rel in ("Scripts/self-test-counts.json", "AGENT-SPEC.md")
    }

    def record(name: str, ok: bool, detail: str = "") -> None:
        results.append((name, ok, detail))

    try:
        # 例 1·好情况全绿
        root = write_fixture(scratch / "e1", fixture_ledger([GOOD_FAMILY]))
        code, output = run_gate(root)
        record("例 1 好情况 exit 0", code == 0, output.strip().splitlines()[-1] if output else "")

        # 例 2·runner 非零退出 ⇒ 判红并点名（负例脚本崩了 = 证据没了）
        ledger = fixture_ledger(
            [
                GOOD_FAMILY,
                {
                    "key": "bad",
                    "script": "Scripts/bad.py",
                    "args": [],
                    "cases": 1,
                    "countRegex": "(\\d+)",
                    "why": "自测夹具：崩掉的 runner",
                    "noAnchorReason": "自测夹具",
                },
            ]
        )
        root = write_fixture(scratch / "e2", ledger)
        code, output = run_gate(root)
        record(
            "例 2 runner 非零退出 ⇒ 判红并点名",
            code == 1 and "[bad]" in output and "runner 退出码 1" in output,
            output.strip().splitlines()[-1] if output else "",
        )

        # 例 3·例数漂移（runner 报 4、台账 3）⇒ 判红
        drift = dict(GOOD_FAMILY, script="Scripts/drift.py", noAnchorReason="自测夹具")
        root = write_fixture(scratch / "e3", fixture_ledger([drift]))
        code, output = run_gate(root)
        record(
            "例 3 例数漂移 ⇒ 判红",
            code == 1 and "runner 报 4 例、台账是 3 例" in output,
            output.strip().splitlines()[-1] if output else "",
        )

        # 例 4·收尾行解析不到 ⇒ 判红（不许静默跳过）
        unparsable = dict(GOOD_FAMILY, script="Scripts/unparsable.py", noAnchorReason="自测夹具")
        root = write_fixture(scratch / "e4", fixture_ledger([unparsable]))
        code, output = run_gate(root)
        record(
            "例 4 解析不到例数 ⇒ 判红",
            code == 1 and "解析不到例数" in output,
            output.strip().splitlines()[-1] if output else "",
        )

        # 例 5·文档里写错值（AGENT-SPEC 写 4 例、台账 3）⇒ 判红
        root = write_fixture(
            scratch / "e5",
            fixture_ledger([GOOD_FAMILY]),
            spec_text=FIXTURE_SPEC.replace("**3 例**", "**4 例**"),
        )
        code, output = run_gate(root)
        record(
            "例 5 锚点值写错 ⇒ 判红",
            code == 1 and "写的是「4」、台账值是「3」" in output,
            output.strip().splitlines()[-1] if output else "",
        )

        # 例 6·锚点被整片删掉 ⇒ 判红（minSites 不满足）
        root = write_fixture(
            scratch / "e6",
            fixture_ledger([GOOD_FAMILY]),
            spec_text="| 资产 | 位置 | 说明 |\n|---|---|---|\n| 好情况 | 见脚本 | 没有数字 |\n",
        )
        code, output = run_gate(root)
        record(
            "例 6 锚点被删 ⇒ 判红",
            code == 1 and "锚点只命中 0 处" in output,
            output.strip().splitlines()[-1] if output else "",
        )

        # 例 7·台账结构错（缺 countRegex / 缺 noAnchorReason）⇒ 判红
        broken = dict(GOOD_FAMILY)
        broken.pop("countRegex")
        broken.pop("anchors")
        root = write_fixture(scratch / "e7", fixture_ledger([broken]))
        code, output = run_gate(root)
        record(
            "例 7 台账结构错 ⇒ 判红",
            code == 1 and "缺 countRegex" in output and "noAnchorReason" in output,
            output.strip().splitlines()[-1] if output else "",
        )

        # 例 8·空跑防护（族数低于下限）⇒ 判红
        root = write_fixture(
            scratch / "e8",
            fixture_ledger([GOOD_FAMILY], floors={"families": 25, "totalCases": 300, "anchorSites": 20}),
        )
        code, output = run_gate(root)
        record(
            "例 8 空跑防护 ⇒ 判红",
            code == 1 and "[空跑防护]" in output,
            output.strip().splitlines()[-1] if output else "",
        )

        # 例 9·静态棘轮（用例定义被删）⇒ 判红
        ratchet_family = {
            "key": "cases",
            "script": "Scripts/cases.py",
            "args": [],
            "cases": 2,
            "countRegex": "全部 (\\d+) 个负例",
            "why": "自测夹具：静态棘轮",
            "noAnchorReason": "自测夹具",
            "sourceRatchet": {
                "file": "Scripts/cases.py",
                "regex": "^print\\(\"case",
                "note": "自测夹具",
            },
        }
        root = write_fixture(
            scratch / "e9",
            fixture_ledger([ratchet_family], floors={"families": 1, "totalCases": 1, "anchorSites": 0}),
        )
        code, output = run_gate(root)
        record("例 9a 静态棘轮对齐 ⇒ exit 0", code == 0, output.strip().splitlines()[-1] if output else "")
        (root / "Scripts/cases.py").write_text(
            'print("case 1")\nprint("✅ 全部 1 个负例的夹具锚点都在位")\n', encoding="utf-8"
        )
        code, output = run_gate(root)
        record(
            "例 9b 用例定义被删 ⇒ 判红",
            code == 1 and "用例定义有 1 条、台账是 2 条" in output,
            output.strip().splitlines()[-1] if output else "",
        )

        # 例 10·runner 卡住不放 ⇒ 判红，且**判据自己不许跟着挂**
        # （2026-11-02：全跑实测卡在 `communicate` 8 分钟 0% CPU ⇒ 全跑只能记「未知」。
        #   修法 = 每族独立短超时 + 整组 SIGKILL；这里钉住「卡住的族必须判红且及时返回」。）
        pid_file = scratch / "e10-child.pid"
        hang = dict(
            GOOD_FAMILY,
            key="hang",
            script="Scripts/hang.py",
            args=[str(pid_file)],
            noAnchorReason="自测夹具：卡住的 runner",
        )
        root = write_fixture(scratch / "e10", fixture_ledger([hang]))
        started = time.monotonic()
        code, output = run_gate(root, ["--family-timeout", "1"])
        elapsed = time.monotonic() - started
        orphan = "夹具没写出孙进程 pid"
        try:
            pid = int(pid_file.read_text(encoding="utf-8").strip())
            try:
                os.kill(pid, 0)
                orphan = f"孙进程 {pid} 还活着（握管道不放 ⇒ 下一次 communicate 还会挂）"
            except ProcessLookupError:
                orphan = ""
        except (OSError, ValueError) as error:
            orphan = f"夹具没写出孙进程 pid：{error}"
        record(
            "例 10 runner 卡住 ⇒ 判红、及时返回、孙进程一起收",
            code == 1 and "[hang] runner 超时" in output and elapsed < 30 and not orphan,
            f"rc={code} 用时 {elapsed:.1f}s（要求 <30s，夹具自身要睡 60s）"
            + (f"；{orphan}" if orphan else "")
            + f"；{output.strip().splitlines()[-1] if output else ''}",
        )
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    after = {
        rel: (REPO / rel).read_bytes()
        for rel in ("Scripts/self-test-counts.json", "AGENT-SPEC.md")
    }
    record("末例 真仓库逐字节未变", before == after, "自测动了真仓库的文件")

    failures = [f"{name}: {detail}" for name, ok, detail in results if not ok]
    for name, ok, detail in results:
        print(("  PASS  " if ok else "  FAIL  ") + name + (f"  [{detail}]" if detail and not ok else ""))
    if failures:
        print(f"❌ 自检失败（{len(results) - len(failures)}/{len(results)}）：")
        for failure in failures:
            print("   " + failure)
        return 1
    print(f"✅ 负例自检：{len(results)} 条中 {len(results)} 条达到预期")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="门禁自己的证据：例数台账对账（队列 L-72 ㈠）")
    parser.add_argument("--root", default=None, help="仓根（默认：脚本所在仓）")
    parser.add_argument("--no-run", action="store_true", help="不跑 runner，只做台账与锚点对账")
    parser.add_argument("--self-test", action="store_true", help="跑判据自己的证据")
    parser.add_argument(
        "--family-timeout",
        type=int,
        default=300,
        help="单族 runner 墙钟上限（秒，默认 300；台账可用家族里的 `timeout` 字段逐族覆写）。"
        "超时判红，不静默跳过",
    )
    arguments = parser.parse_args()

    if arguments.self_test:
        return run_self_test()

    root = pathlib.Path(arguments.root).resolve() if arguments.root else REPO
    problems, notes, stats = check(
        root, run_runners=not arguments.no_run, timeout=arguments.family_timeout
    )

    print(f"== 自检例数台账（{LEDGER_REL}）· 仓根 {root.name} ==")
    for note in notes:
        print("   " + note)
    if stats:
        print(
            f"   族 {stats['families']} 个 / 例数合计 {stats['cases']} / 锚点命中 {stats['anchors']} 处"
            f" / 无锚点但写了理由的族 {stats['noAnchor']} 个"
        )
    if problems:
        print(f"❌ 判红 {len(problems)} 处：")
        for problem in problems:
            print("   · " + problem)
        return 1
    if arguments.no_run:
        # 口径：未执行 ≠ 通过（`--no-run` 只对账台账与锚点，一个 runner 都没跑）
        print("⚠️ 台账与锚点全部对上，但 `--no-run` **没有真跑**各族 runner —— 未执行 ≠ 通过")
        return 0
    print("✅ 全部通过：每一族的负例都真跑了一遍（exit 0）、例数与台账一致、文档里的现状声明逐处对上")
    return 0


if __name__ == "__main__":
    sys.exit(main())
