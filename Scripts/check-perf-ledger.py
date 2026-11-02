#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**性能读数表的阈值与读数**（`NFR-ALL-GATE-PERF-001/002/003`）。

## 这一行原来为什么判不住

三条都写着「🟡（待验证）」，而盘上其实早有一半的东西：1 万 / 10 万行 × 20 列的滚动探针
（`TestsUISnapshot/LargeResultScrollProbeTests.swift`）把每条上界都从
`Scripts/result-scroll-baseline.json` 读，冷启动那条**一个字都没有** —— 没有仪表、
没有阈值、没有读数。于是「≤ 2 s」只是一句话，谁都能说成立。

## 本判据判四件事

  A **阈值只有一个写者**（`Scripts/perf-baseline.json`）：
    · 冷启动 `limitMs` 必须**恰好 2000**（需求原文「≤ 2 s」；改松就是改判据）；
    · `runs ≥ 3`、`reducer == median`、起止点口径写清、理由非空；
    · 结果集那两条**不许在本台账里重复数字**：只登记「去哪份台账取哪个字段」，
      字段必须真的在那个文件里解析出正数（重复写一份 = 两个写者，将来必漂）；
    · 计时源码（`Core/LaunchTimeline.swift` / `App/LaunchReceiptProbe.swift`）
      **不许出现阈值数字** —— 出现就说明有人在代码里另存了一份。
  B **接线在盘**（不是「设计上会接」）：
    · `App/DoyahStudioApp.swift` 的 `init()` 第一句就是 `LaunchReceiptProbe.begin()`
      （往后挪，那一句的耗时就变成免费）；
    · 根视图挂着 `LaunchReceiptMarker()`（终点的落点）；
    · 进场以**内核**的进程创建时刻为起点（`ProcessStartTime`），收据由 `LaunchReceipt` 写；
    · 测量脚本在位，且它读台账、认 `unmeasurable`（拿不到收据 ≠ 0 ms）。
  C **读数对阈值**（`--readings`，读测量脚本写出的 JSON）：每一条实测值都必须
    ≤ 台账阈值；冷启动的「外部墙钟」不许**小于**收据自报的毫秒数（那说明两者不是同一件事，
    收据是编的）；缺读数就报「没有读数」，**不当通过**。
  D 空跑防护：台账里的行名必须与三条需求号一致；上面任何一条解析不到 ⇒ 判红（不是跳过）。

## 用法

    python3 Scripts/check-perf-ledger.py                      # 静态臂（闭环第 9 项里跑）
    python3 Scripts/check-perf-ledger.py --readings .build/perf-cold-start.json .build/perf-resultset.json
    python3 Scripts/check-perf-ledger.py --self-test           # 判据自己的证据：`--self-test` **13 例**

**边界（如实登记）**：本判据不做测量 —— 真启动一遍 App 太重、也太容易受机器状态影响，
冷启动的实测由 `Scripts/measure-cold-start.py` 出、读数文件进 `--readings`（证据文件里贴尾部）。
静态臂只证明「阈值只有一处、仪表接着、代码里没另存一份」，**不证明**这台机器现在跑得动。
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parent.parent

LEDGER = "Scripts/perf-baseline.json"
SCROLL_LEDGER = "Scripts/result-scroll-baseline.json"
MEASURE_SCRIPT = "Scripts/measure-cold-start.py"
APP_ENTRY = "App/DoyahStudioApp.swift"
APP_PROBE = "App/LaunchReceiptProbe.swift"
CORE_TIMELINE = "Core/LaunchTimeline.swift"
SCROLL_PROBE = "TestsUISnapshot/LargeResultScrollProbeTests.swift"

REQUIRED_ROWS = ("NFR-ALL-GATE-PERF-001", "NFR-ALL-GATE-PERF-002", "NFR-ALL-GATE-PERF-003")
COLD_START_LIMIT_MS = 2000
MIN_RATIONALE = 40


# ------------------------------------------------------------------ 小工具

def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def strip_comments(source: str) -> str:
    """去掉 `//` 行注释与 `/* … */` 块注释（字符串里的不动 —— 够用且不误伤）。"""
    out, index, length = [], 0, len(source)
    in_string = False
    while index < length:
        char = source[index]
        nxt = source[index + 1] if index + 1 < length else ""
        if in_string:
            out.append(char)
            if char == "\\":
                if nxt:
                    out.append(nxt)
                    index += 2
                    continue
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            index += 1
            continue
        if char == "/" and nxt == "/":
            while index < length and source[index] != "\n":
                index += 1
            continue
        if char == "/" and nxt == "*":
            index += 2
            while index + 1 < length and not (source[index] == "*" and source[index + 1] == "/"):
                if source[index] == "\n":
                    out.append("\n")
                index += 1
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def json_path(document, dotted: str):
    """按 `frame.p50MsLimit` 这样的点号路径取值；取不到抛 `KeyError`。"""
    current = document
    for part in dotted.split("."):
        if not isinstance(current, dict) or part not in current:
            raise KeyError(dotted)
        current = current[part]
    return current


def number(value) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("不是一个数：%r" % (value,))
    return float(value)


# ------------------------------------------------------------------ A/B：静态臂

def check_ledger(root: pathlib.Path) -> list:
    problems = []
    ledger_path = root / LEDGER
    if not ledger_path.exists():
        return ["台账不在盘上：%s" % LEDGER]
    try:
        ledger = json.loads(read_text(ledger_path))
    except json.JSONDecodeError as error:
        return ["台账解析不了（%s）：%s" % (LEDGER, error)]

    environment = ledger.get("environment") or {}
    for key in ("measuredOn", "measuredBy", "build"):
        if not str(environment.get(key) or "").strip():
            problems.append("环境那一格缺 `%s` —— 读数表要能说清这台机器 / 这个包是什么" % key)

    cold = ledger.get("coldStart") or {}
    limit = cold.get("limitMs")
    try:
        limit_value = number(limit)
    except ValueError:
        problems.append("冷启动阈值不是数：%r" % (limit,))
        limit_value = None
    if limit_value is not None and limit_value != COLD_START_LIMIT_MS:
        problems.append(
            "冷启动阈值被写成了 %s ms —— 需求原文是「≤ 2 s」，改它等于改判据（要改先去改契约）"
            % ("%g" % limit_value)
        )
    if int(cold.get("runs") or 0) < 3:
        problems.append("冷启动的 `runs` = %r < 3：一遍定生死会被机器瞬时负载骗" % (cold.get("runs"),))
    if cold.get("reducer") != "median":
        problems.append("冷启动的代表值口径不是 median：%r（不许报最快那一遍）" % (cold.get("reducer"),))
    if len(str(cold.get("rationale") or "").strip()) < MIN_RATIONALE:
        problems.append("冷启动那一段的理由过短（≤ %d 字）：阈值必须有来源" % MIN_RATIONALE)
    for key in ("startPoint", "endPoint", "receiptEnvironment"):
        if not str(cold.get(key) or "").strip():
            problems.append("冷启动缺 `%s`（口径不写清，读数就没有意义）" % key)
    if cold.get("rows") != [REQUIRED_ROWS[0]]:
        problems.append("冷启动的 `rows` 应是 %r，实测 %r" % ([REQUIRED_ROWS[0]], cold.get("rows")))
    if str(cold.get("measurement") or "") != MEASURE_SCRIPT:
        problems.append("冷启动的 `measurement` 应指向 %s，实测 %r" % (MEASURE_SCRIPT, cold.get("measurement")))

    # 结果集那两条：只许指路，不许复制数字
    result_set = ledger.get("resultSet") or {}
    rows = result_set.get("rows") or {}
    if sorted(rows) != sorted(REQUIRED_ROWS[1:]):
        problems.append("结果集两行的键应是 %r，实测 %r" % (sorted(REQUIRED_ROWS[1:]), sorted(rows)))
    scroll_document = None
    scroll_path = root / SCROLL_LEDGER
    if scroll_path.exists():
        try:
            scroll_document = json.loads(read_text(scroll_path))
        except json.JSONDecodeError as error:
            problems.append("结果集台账解析不了（%s）：%s" % (SCROLL_LEDGER, error))
    else:
        problems.append("结果集台账不在盘上：%s" % SCROLL_LEDGER)

    for row, spec in sorted(rows.items()):
        if not isinstance(spec, dict):
            problems.append("`%s` 的登记不是对象" % row)
            continue
        if str(spec.get("ledger") or "") != SCROLL_LEDGER:
            problems.append("`%s` 指到了 %r —— 结果集的阈值唯一来源是 %s" % (row, spec.get("ledger"), SCROLL_LEDGER))
        if str(spec.get("probe") or "") != SCROLL_PROBE:
            problems.append("`%s` 的探针应指向 %s，实测 %r" % (row, SCROLL_PROBE, spec.get("probe")))
        if scroll_document is not None:
            for key in ("rowsField", "columnsField"):
                field = spec.get(key)
                try:
                    value = number(json_path(scroll_document, str(field)))
                except (KeyError, ValueError):
                    problems.append("`%s` 的 `%s`（%r）在 %s 里解析不到数" % (row, key, field, SCROLL_LEDGER))
                    continue
                if value <= 0:
                    problems.append("`%s` 的 `%s` 不是正数：%r" % (row, key, value))
            limits = [key for key in ("frameLimitField", "rasterLimitField", "ratioLimitField", "memoryLimitField") if spec.get(key)]
            if not limits:
                problems.append("`%s` 一个上限字段都没登记" % row)
            for key in limits:
                try:
                    value = number(json_path(scroll_document, str(spec[key])))
                except (KeyError, ValueError):
                    problems.append("`%s` 的 `%s`（%r）在 %s 里解析不到数" % (row, key, spec[key], SCROLL_LEDGER))
                    continue
                if value <= 0:
                    problems.append("`%s` 的上限 `%s` 不是正数：%r" % (row, key, value))

    # 规模对得上需求（1 万 / 10 万行 × 20 列）：从结果集台账现读，不信本台账自述
    if scroll_document is not None:
        try:
            if number(json_path(scroll_document, "smallRows")) != 10000:
                problems.append("结果集台账的 `smallRows` 不是 1 万")
            if number(json_path(scroll_document, "largeRows")) != 100000:
                problems.append("结果集台账的 `largeRows` 不是 10 万")
            if number(json_path(scroll_document, "columns")) != 20:
                problems.append("结果集台账的 `columns` 不是 20")
        except (KeyError, ValueError):
            problems.append("结果集台账缺 `smallRows` / `largeRows` / `columns`")

    # 计时源码里不许另存阈值
    for relative in (CORE_TIMELINE, APP_PROBE):
        path = root / relative
        if not path.exists():
            problems.append("计时源码不在盘上：%s" % relative)
            continue
        code = strip_comments(read_text(path))
        if re.search(r"(?<![0-9])%d(?![0-9])" % COLD_START_LIMIT_MS, code):
            problems.append("%s 里出现了阈值数字 %d —— 阈值只许待在 %s" % (relative, COLD_START_LIMIT_MS, LEDGER))
    return problems


def check_wiring(root: pathlib.Path) -> list:
    problems = []
    entry = root / APP_ENTRY
    probe = root / APP_PROBE
    core = root / CORE_TIMELINE
    measure = root / MEASURE_SCRIPT
    for path in (entry, probe, core, measure):
        if not path.exists():
            problems.append("接线文件不在盘上：%s" % path.relative_to(root))
    if problems:
        return problems

    entry_code = strip_comments(read_text(entry))
    match = re.search(r"\binit\(\)\s*\{", entry_code)
    if not match:
        problems.append("%s 里找不到 `init() {`（App 的入口口径变了？判据要跟着改）" % APP_ENTRY)
    else:
        tail = entry_code[match.end():]
        first = next((line.strip() for line in tail.splitlines() if line.strip()), "")
        if first != "LaunchReceiptProbe.begin()":
            problems.append(
                "`init()` 的第一句不是 `LaunchReceiptProbe.begin()`（实测 %r）—— "
                "往后挪一句，那一句的耗时就算作免费" % first[:60]
            )
    if "LaunchReceiptMarker()" not in entry_code:
        problems.append("根视图没挂 `LaunchReceiptMarker()` ⇒ 终点没有落点（收据永远写不出来）")
    if "isLaunchReceiptProbe" not in entry_code:
        problems.append("单实例保护没有放行收据探针 ⇒ 用户开着应用时测量会被静默赶走")

    probe_code = strip_comments(read_text(probe))
    for needle, why in (
        ("ProcessStartTime.current()", "起点必须取内核记录的进程创建时刻（`ProcessStartTime`）"),
        ("LaunchTimeline(", "打点必须走 `Core/LaunchTimeline`（口径只有一处）"),
        ("LaunchReceipt(", "收据必须走 `LaunchReceipt`（时间用秒，不用 ISO8601 字符串）"),
        ("artificialDelayKey", "负例开关（`DOYAH_LAUNCH_ARTIFICIAL_DELAY_MS`）不在位 ⇒ 超阈值判红没法证"),
        ("startFellBackToFirstLine", "起点取不到内核时刻时必须如实登记（不许静默当成同一件事）"),
    ):
        if needle not in probe_code:
            problems.append("%s：找不到 %r" % (why, needle))
    core_code = strip_comments(read_text(core))
    for needle in ("struct LaunchTimeline", "struct LaunchReceipt", "enum LaunchBudget"):
        if needle not in core_code:
            problems.append("%s 里缺 %r" % (CORE_TIMELINE, needle))
    if "ISO8601" in core_code:
        problems.append("%s 用了 ISO8601 字符串存时刻 —— 存字符串就得在两处各选一次格式（踩过）" % CORE_TIMELINE)

    measure_code = read_text(measure)
    for needle, why in (
        ("perf-baseline.json", "测量脚本必须读阈值台账（唯一来源）"),
        ("DOYAH_LAUNCH_RECEIPT", "测量脚本必须用收据环境变量"),
        ("unmeasurable", "测量脚本必须把「拿不到收据」判成判不了，而不是 0 ms"),
    ):
        if needle not in measure_code:
            problems.append("%s：%s（找不到 %r）" % (MEASURE_SCRIPT, why, needle))
    return problems


# ------------------------------------------------------------------ C：读数对阈值

def check_readings(root: pathlib.Path, paths: list) -> list:
    ledger = json.loads(read_text(root / LEDGER))
    cold = ledger["coldStart"]
    limit_ms = number(cold["limitMs"])
    scroll = json.loads(read_text(root / SCROLL_LEDGER))
    rows = (ledger.get("resultSet") or {}).get("rows") or {}
    problems, seen = [], set()

    for path in paths:
        document = json.loads(read_text(pathlib.Path(path)))
        kind = document.get("kind")
        if kind == "cold-start":
            seen.add("cold-start")
            median_ms = document.get("medianMs")
            external_ms = document.get("externalMedianMs")
            try:
                median_value = number(median_ms)
            except ValueError:
                problems.append("%s：没有可用的中位数读数（%r）⇒ 判不了，不是通过" % (path, median_ms))
                continue
            if median_value > limit_ms:
                problems.append("%s：冷启动中位数 %.1f ms > %.0f ms" % (path, median_value, limit_ms))
            try:
                external_value = number(external_ms)
            except ValueError:
                problems.append("%s：缺外部墙钟读数（收据自报的数没人对照）" % path)
            else:
                if external_value + 1.0 < median_value:
                    problems.append(
                        "%s：外部墙钟 %.1f ms 小于收据自报 %.1f ms —— 两者不是同一件事，收据不可信"
                        % (path, external_value, median_value)
                    )
            if document.get("verdict") == "within" and median_value > limit_ms:
                problems.append("%s：脚本自报 within 而读数超阈值（测量脚本自己的判定与台账不一致）" % path)
        elif kind == "result-set":
            seen.add("result-set")
            checks = (
                ("NFR-ALL-GATE-PERF-002", "frameP50Ms", "frameLimitField"),
                ("NFR-ALL-GATE-PERF-002", "rasterP50Ms", "rasterLimitField"),
                ("NFR-ALL-GATE-PERF-002", "ratioFactor", "ratioLimitField"),
                ("NFR-ALL-GATE-PERF-003", "residentDeltaMB", "memoryLimitField"),
            )
            for row, measured_key, limit_key in checks:
                spec = rows.get(row) or {}
                field = spec.get(limit_key)
                if not field:
                    problems.append("台账里 `%s` 没登记 `%s`，没法对读数" % (row, limit_key))
                    continue
                try:
                    limit_value = number(json_path(scroll, str(field)))
                except (KeyError, ValueError):
                    problems.append("`%s` 的 `%s` 在结果集台账里解析不到" % (row, field))
                    continue
                try:
                    measured_value = number(document.get(measured_key))
                except ValueError:
                    problems.append("%s：缺 `%s` 读数（%r）" % (path, measured_key, document.get(measured_key)))
                    continue
                if measured_value > limit_value:
                    problems.append(
                        "%s：`%s` 实测 %g > 阈值 %g（%s）" % (path, measured_key, measured_value, limit_value, field)
                    )
        else:
            problems.append("%s：不认识的读数种类 %r" % (path, kind))
    for missing in ("cold-start", "result-set"):
        if missing not in seen:
            problems.append("没有 `%s` 的读数 ⇒ 这一条判不了（不是通过）" % missing)
    return problems


def report(root: pathlib.Path, paths: list) -> None:
    """人读的读数表（阈值 / 实测 / 基准环境）。"""
    ledger = json.loads(read_text(root / LEDGER))
    environment = ledger.get("environment") or {}
    scroll = json.loads(read_text(root / SCROLL_LEDGER))
    rows = (ledger.get("resultSet") or {}).get("rows") or {}
    print("性能读数表（阈值 ← %s；结果集阈值 ← %s）" % (LEDGER, SCROLL_LEDGER))
    print("基准环境：%s · %s" % (environment.get("measuredBy", "?"), environment.get("build", "?")))
    documents = {}
    for path in paths:
        document = json.loads(read_text(pathlib.Path(path)))
        documents[document.get("kind")] = document

    cold = documents.get("cold-start") or {}
    print("| 条目 | 阈值 | 实测 | 口径 |")
    print("|---|---|---|---|")
    print("| NFR-ALL-GATE-PERF-001 | ≤ %d ms | %s | 中位数 %s 遍 · 外部墙钟 %s ms |"
          % (ledger["coldStart"]["limitMs"],
             ("%.1f ms" % cold["medianMs"]) if cold.get("medianMs") is not None else "无读数",
             ledger["coldStart"]["runs"],
             ("%.1f" % cold["externalMedianMs"]) if cold.get("externalMedianMs") is not None else "-"))
    result = documents.get("result-set") or {}
    for row, key, limit_key in (
        ("NFR-ALL-GATE-PERF-002", "frameP50Ms", "frameLimitField"),
        ("NFR-ALL-GATE-PERF-002", "rasterP50Ms", "rasterLimitField"),
        ("NFR-ALL-GATE-PERF-002", "ratioFactor", "ratioLimitField"),
        ("NFR-ALL-GATE-PERF-003", "residentDeltaMB", "memoryLimitField"),
    ):
        field = (rows.get(row) or {}).get(limit_key)
        limit_value = json_path(scroll, str(field)) if field else "?"
        measured = result.get(key)
        print("| %s · %s | ≤ %s | %s | %s |"
              % (row, key, limit_value, ("%g" % measured) if measured is not None else "无读数", field or "-"))


# ------------------------------------------------------------------ 自检

def _copy_fixture(target: pathlib.Path, source: pathlib.Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def _fixture(root: pathlib.Path, base: pathlib.Path) -> None:
    for relative in (LEDGER, SCROLL_LEDGER, MEASURE_SCRIPT, APP_ENTRY, APP_PROBE,
                     CORE_TIMELINE, SCROLL_PROBE):
        _copy_fixture(root / relative, base / relative)


def _write_ledger(root: pathlib.Path, mutate) -> None:
    path = root / LEDGER
    document = json.loads(read_text(path))
    mutate(document)
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def self_test(base: pathlib.Path) -> int:
    cases = []

    def case(name, condition):
        cases.append((name, bool(condition)))
        print("%s %s" % ("✓" if condition else "✗", name))

    # 1 绿对照：真仓库静态臂
    case("真仓库静态臂通过", not check_ledger(base) and not check_wiring(base))

    with tempfile.TemporaryDirectory(prefix="doyah-perf-ledger-") as scratch:
        scratch_path = pathlib.Path(scratch)
        # 2 阈值被放宽
        root = scratch_path / "loosen"
        _fixture(root, base)
        _write_ledger(root, lambda document: document["coldStart"].__setitem__("limitMs", 5000))
        case("阈值改成 5 s ⇒ 判红", any("改判据" in problem for problem in check_ledger(root)))
        # 3 阈值改成负 / 非数
        root = scratch_path / "negative"
        _fixture(root, base)
        _write_ledger(root, lambda document: document["coldStart"].__setitem__("limitMs", -1))
        case("阈值为负 ⇒ 判红", bool(check_ledger(root)))
        # 4 理由被掏空
        root = scratch_path / "empty-rationale"
        _fixture(root, base)
        _write_ledger(root, lambda document: document["coldStart"].__setitem__("rationale", "够了"))
        case("理由被掏空 ⇒ 判红", any("理由" in problem for problem in check_ledger(root)))
        # 5 只跑一遍
        root = scratch_path / "one-run"
        _fixture(root, base)
        _write_ledger(root, lambda document: document["coldStart"].__setitem__("runs", 1))
        case("只跑一遍 ⇒ 判红", any("runs" in problem for problem in check_ledger(root)))
        # 6 结果集那两条被复制了数字（指向自己）
        root = scratch_path / "copied-numbers"
        _fixture(root, base)

        def repoint(document):
            document["resultSet"]["rows"]["NFR-ALL-GATE-PERF-003"]["ledger"] = LEDGER
        _write_ledger(root, repoint)
        case("结果集阈值改指本台账 ⇒ 判红", any("唯一来源" in problem for problem in check_ledger(root)))
        # 7 结果集字段指错
        root = scratch_path / "bad-field"
        _fixture(root, base)

        def bad_field(document):
            document["resultSet"]["rows"]["NFR-ALL-GATE-PERF-002"]["frameLimitField"] = "frame.nopeMs"
        _write_ledger(root, bad_field)
        case("结果集上限字段解析不到 ⇒ 判红", any("nopeMs" in problem for problem in check_ledger(root)))
        # 8 计时源码里另存阈值
        root = scratch_path / "hardcoded"
        _fixture(root, base)
        timeline = root / CORE_TIMELINE
        timeline.write_text(read_text(timeline).replace(
            "public var interactiveAt: Date?",
            "public var budget: Double { 2000 }\n    public var interactiveAt: Date?"),
            encoding="utf-8")
        case("Core 里硬编码阈值 ⇒ 判红", any("阈值数字" in problem for problem in check_ledger(root)))
        # 9 begin() 被挪到 init 的第二句
        root = scratch_path / "late-begin"
        _fixture(root, base)
        entry = root / APP_ENTRY
        entry.write_text(read_text(entry).replace(
            "        LaunchReceiptProbe.begin()\n",
            "", 1).replace(
            "        PDFTextExtractor.install()",
            "        PDFTextExtractor.install()\n        LaunchReceiptProbe.begin()", 1),
            encoding="utf-8")
        case("begin() 挪到第二句 ⇒ 判红", any("第一句" in problem for problem in check_wiring(root)))
        # 10 终点标记被摘掉
        root = scratch_path / "no-marker"
        _fixture(root, base)
        entry = root / APP_ENTRY
        entry.write_text(read_text(entry).replace(".background(LaunchReceiptMarker())", "", 1),
                         encoding="utf-8")
        case("根视图摘掉终点标记 ⇒ 判红", any("LaunchReceiptMarker" in problem for problem in check_wiring(root)))

        # 11 读数超阈值
        cold_over = scratch_path / "cold-over.json"
        cold_over.write_text(json.dumps({
            "kind": "cold-start", "medianMs": 2600, "externalMedianMs": 2700, "verdict": "over",
        }), encoding="utf-8")
        result_ok = scratch_path / "result-ok.json"
        result_ok.write_text(json.dumps({
            "kind": "result-set", "frameP50Ms": 0.02, "rasterP50Ms": 28.4,
            "ratioFactor": 1.0, "residentDeltaMB": 0.1,
        }), encoding="utf-8")
        case("冷启动读数 2.6 s ⇒ 判红",
             any("中位数" in problem for problem in check_readings(base, [cold_over, result_ok])))

        # 12 收据自报比外部墙钟还快（自相矛盾）+ 缺结果集读数
        cold_liar = scratch_path / "cold-liar.json"
        cold_liar.write_text(json.dumps({
            "kind": "cold-start", "medianMs": 900, "externalMedianMs": 200, "verdict": "within",
        }), encoding="utf-8")
        problems = check_readings(base, [cold_liar, result_ok])
        case("外部墙钟小于收据自报 ⇒ 判红", any("不可信" in problem for problem in problems))
        problems = check_readings(base, [result_ok])
        case("缺冷启动读数 ⇒ 判不了（判红）", any("cold-start" in problem for problem in problems))

    passed = sum(1 for _, ok in cases if ok)
    print("\n自检：%d 例（通过 %d / 失败 %d）" % (len(cases), passed, len(cases) - passed))
    return 0 if passed == len(cases) else 1


# ------------------------------------------------------------------ main

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="性能读数表判据（NFR-ALL-GATE-PERF-001/002/003）")
    parser.add_argument("--readings", nargs="*", default=None, help="测量脚本写出的读数 JSON（可多份）")
    parser.add_argument("--self-test", action="store_true", help="判据自己的证据（合成夹具）")
    parser.add_argument("--report", action="store_true", help="打印读数表（需 --readings）")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test(BASE)

    problems = check_ledger(BASE) + check_wiring(BASE)
    if args.readings is not None:
        if not args.readings:
            problems.append("--readings 后面没给文件")
        else:
            problems.extend(check_readings(BASE, args.readings))
    if args.report:
        if not args.readings:
            print("--report 需要 --readings（没有读数就没有读数表）")
            return 2
        report(BASE, args.readings)

    if problems:
        print("✗ 性能读数表判红 %d 条：" % len(problems))
        for problem in problems:
            print("  · %s" % problem)
        return 1
    print("✓ 性能读数表：阈值唯一来源在位（冷启动 ≤ %d ms / 结果集两条指路 %s）、接线在盘%s"
          % (COLD_START_LIMIT_MS, SCROLL_LEDGER,
             "、读数未超阈值" if args.readings else "、本次未给读数（读数另由测量脚本出）"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
