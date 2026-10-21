#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`P-*` 平台差异登记的两侧对账门禁（队列 L-45）。

为什么需要它 —— 两张自称「一一对应」的表，此前**一个判据都没有**：

1. `Docs/Doyah产品概要设计说明书.md` §4「允许不同的部分（平台差异）」与 `Docs/Doyah产品需求分析说明书.md` §9.2
   「平台差异登记表（哪些允许不同）」在正文里互相写着「与 …… 一一对应」；
2. `Scripts/verify-all.sh` **第 7 项的注释**甚至一直写着「平台等价矩阵与 §9.2 登记表一致」——
   那是错的：那一项只做 §10.10 ↔ `Docs/平台实现状态.json` 的矩阵对账（2026-09-27 第 25 轮
   改正了这句注释，并登记本条目）；
3. 实测现状（第 25 轮取证）：概要设计 §4 有 `P-16`，§8.5.5（`[独占:windows]`）另落了
   `P-17`~`P-24` 并原文写明「先在本节落条目，**待契约侧并入 §4**」，而 SRS §9.2 只到
   `P-15` ⇒ **编号空间断档 9 条**，两侧各说各话，没有任何一处会报红。
4. 历史实证（第 27 轮）：`P-15` 在 §4 是「SSH 隧道」、在 SRS §9.2 是「笔记存储引擎」——
   **同号不同物**，靠人读才发现，已按「§9.2 为权威登记表」让号（SSH 隧道 → `P-25`）。

判据（五类）：

- **A 双向覆盖**：§9.2 的编号集合与 §4 的编号集合必须**相等**；各自多出的号逐条点名。
- **B 同号同物**：两侧同号行的**领域**必须指同一件事。归一化 = 去掉 `**` 与反引号 →
  截到首个 `（` / `(` 之前 → 压空白 → 逐字相等（`P-15` 一侧写 `**笔记存储引擎（`FR-STD-ALL-PLUG-008`）**`、
  另一侧写 `笔记存储引擎（`FR-STD-ALL-PLUG-008`）`，归一后都是「笔记存储引擎」）。
- **C §8.5.5 显式告警**：对侧独占节 §8.5.5 里已落的条目（形如 `` `P-17` 终端仿真与 PTY ``），
  只要有一号没有**同时**出现在 §4 与 §9.2，就判红 —— 「已落条但未并入」不许静默（该节的
  合并动作本来就是契约侧的活；它自己那条「待契约侧并入」的注是该节作者的事，本门禁不去改它）。

- **D 同侧编号唯一**：**同一张登记表内部**同号两条 ⇒ 判红并**逐行点名**（`P-01` 在一张表里出现两次）。
  由头 = 汇总册 `T-20261013-027` 第 32 轮（原单 `T-20261010-047`）：旧实现 `parse_registry` 用 dict
  **后行覆盖前行**、判据 A 只比**集合**（天然去重）⇒ 同侧重复定义行**不在任何判据里**（实测：在真
  `P-13` 行之前插一行「同号、另一个领域」⇒ 旧码 rc=0、输出与基线逐字同；逐字重复行同样 rc=0）。
  **只判同一张表内部** —— §8.5.5（`[独占:windows]` 的续排节）里提到已并入的同号是**合法过渡态**，
  归判据 C 管，不在这里判。

- **E 行为名列棘轮**（前门 `T-20261014-201` ㈡ 已裁 · 判据 = 判「行为标识」不判逐字正文）：两侧该列
  **归一后的条目名集合**与台账 `Scripts/p-parity-behavior-baseline.json` **逐号对账** ⇒ 条目名
  **改名 / 增 / 删**、新号未登记、基线死条目、空单元格一律判红（逐行点名）；台账 `_差异读数` 里
  列出「两侧条目名差异号」= **契约层待归口清单**（本判据**不**判两侧是否逐字相同：实测逐字相等
  仅 10/27 条，判逐字就是每轮 17 处假红）。

本判据**仍然不做**的三件事（免得下次有人以为查过了）：

- **不判「两侧逐字相同」**：前门 `T-20261014-201` ㈡ 已裁「判行为标识，不判逐字正文」⇒ 判据 E 判的是
  **归一后的条目名**（措辞与括注属各侧表述自由）；两侧条目名不一致的号**列进台账的 `_差异读数`**
  （待前门逐号归口），**不判红**。
- **领域归一仍截到首个 `（` 之前**（原设计，不变）：改成「不截括号」会让 `P-16` 当场判红 —— §9.2 写
  `多库驱动（`FR-STD-DB-DRV-010` / `FR-STD-DB-DRV-009`）`、§4 写 `多库驱动（FR-STD-DB-DRV-010 / 08）`（括号内写法不同）。
  前门 `T-20261014-201` ㈢ 已裁**维持现规则**（`P-16` 的括号内引用写法差异按平台差异登记）；
  本侧按边界**不动 `Docs/**`**（本文件与 §§9.2 / §4 正文一字未改）。
本判据**不做**的两件事（免得下次有人以为查过了）：

- **不判行序**：SRS §9.2 本来就不是按号排的（`P-14` 在 `P-13` 之前），判序只会造假红；
- **不判「同域不同号」**：`P-17`（终端仿真与 PTY）与 `P-05`（内嵌终端）同域、`P-19`/`P-21`/`P-24`
  与 `P-06`/`P-08`/`P-09` 同域 —— 那是**登记表要不要合并条目**的设计问题，需对侧拍板，
  归提案与队列条目，不属于「编号对账」（机械判据只判能机械判的那部分）。

用法：

    python3 Scripts/check-p-parity.py               # 查两侧
    python3 Scripts/check-p-parity.py --self-test    # 负例（临时目录里写坏，末条核对真仓库未动）
    python3 Scripts/check-p-parity.py --quiet        # 只打印问题
    python3 Scripts/check-p-parity.py --write-baseline   # 按当前两份文档重写行为名列基线（须留痕）

退出码：0 = 全绿；1 = 有覆盖缺口 / 同号不同物 / §8.5.5 已落条但未并入（逐条打印 `文件:行号`）。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

SRS = "Docs/Doyah产品需求分析说明书.md"
DESIGN = "Docs/Doyah产品概要设计说明书.md"

SRS_HEADING = re.compile(r"^## 9\.2 ")
SRS_STOP = re.compile(r"^#{1,2} ")
DESIGN_HEADING = re.compile(r"^# 第四章 ")
DESIGN_STOP = re.compile(r"^# ")
WINDOWS_HEADING = re.compile(r"^### 8\.5\.5 ")
WINDOWS_STOP = re.compile(r"^#{1,3} ")

DEFINITION_ROW = re.compile(r"^\|\s*[`*]{0,2}(P-\d{2})[`*]{0,2}\s*\|")
P_REFERENCE = re.compile(r"(P-\d{2})")


def section(lines: list[str], heading: re.Pattern[str], stop: re.Pattern[str]) -> list[tuple[int, str]]:
    """返回小节正文（不含标题行）的 `(行号, 行)` 列表；找不到标题返回空列表。"""
    start = None
    for index, line in enumerate(lines):
        if heading.match(line):
            start = index
            break
    if start is None:
        return []
    body: list[tuple[int, str]] = []
    for offset in range(start + 1, len(lines)):
        line = lines[offset]
        if stop.match(line):
            break
        body.append((offset + 1, line))
    return body


def normalize_domain(text: str) -> str:
    """领域名归一：去强调 / 反引号 → 截到首个括号之前 → 压空白。"""
    plain = text.replace("**", "").replace("`", "")
    plain = re.split(r"[（(]", plain, maxsplit=1)[0]
    return " ".join(plain.split())


def parse_registry(body: list[tuple[int, str]]) -> dict[str, list[tuple[int, str]]]:
    """解析登记表：编号 → [(行号, 领域原文), …]（**保留同号多行**，判据 D 要看它）。

    旧实现是 `rows[号] = (行号, 领域)` —— 同侧出现两个同号定义行时**后行静默覆盖前行**，
    而判据 A 比的是 `set(...)`（天然去重）⇒ 重复行**一处判据都碰不到**（2026-10-14 汇总册
    `T-20261013-027` 第 32 轮实测）。现在把每次出现都留下。
    """
    rows: dict[str, list[tuple[int, str]]] = {}
    for lineno, line in body:
        match = DEFINITION_ROW.match(line)
        if not match:
            continue
        cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", line)]
        if len(cells) < 3:
            continue
        rows.setdefault(match.group(1), []).append((lineno, cells[2]))
    return rows


def effective(rows: dict[str, list[tuple[int, str]]], number: str) -> tuple[int, str]:
    """该号在**本表**里的生效行 = **最后一条**（旧实现的 dict 覆盖语义 ⇒ 判据 A/B/C 行为一字不变）。"""
    return rows[number][-1]
BEHAVIOR_BASELINE = "Scripts/p-parity-behavior-baseline.json"


def parse_behaviors(body: list[tuple[int, str]]) -> dict[str, list[tuple[int, str]]]:
    """与 `parse_registry` 同形，取登记表的**第 4 格**（「必须一致的行为（跨平台契约）」列原文）。"""
    rows: dict[str, list[tuple[int, str]]] = {}
    for lineno, line in body:
        match = DEFINITION_ROW.match(line)
        if not match:
            continue
        cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", line)]
        if len(cells) < 4:
            continue
        rows.setdefault(match.group(1), []).append((lineno, cells[3]))
    return rows


def behavior_items(text: str) -> list[str]:
    """行为名列归一 ⇒ **条目名**列表（判据 E 的判定物）。

    口径 = 前门 `T-20261014-201` ㈡「判行为标识，不判逐字正文」：归一 = 去强调（`**`）与反引号
    → **去括注（连内容）** → 按 `、` / `；` / `;` 切条 → 压空白、去首尾标点。括注与措辞属
    各侧表述自由、**不进集合**；进集合的是条目名 ⇒ 名改 / 名增 / 名删由判据 E 与基线对账。
    """
    plain = text.replace("**", "").replace("`", "")
    plain = re.sub(r"[（(][^（()）]*[)）]", "", plain)
    items: list[str] = []
    for part in re.split(r"[、；;]", plain):
        token = " ".join(part.split()).strip(" 。，,、=：:")
        token = re.sub(r"^(与|和)", "", token)
        if token:
            items.append(token)
    return items


def behavior_diff_readout(numbers: dict) -> dict:
    """台账里的**差异读数** = 契约层待归口清单（前门照这份清单逐号处置，不判红）。"""
    diff = [n for n, v in numbers.items() if set(v["srs"]) != set(v["des"])]
    return {
        "两侧归一后条目名差异号数": len(diff),
        "差异号": diff,
        "SRS 独有项": sum(len(set(v["srs"]) - set(v["des"])) for v in numbers.values()),
        "DES 独有项": sum(len(set(v["des"]) - set(v["srs"])) for v in numbers.values()),
    }


def build_baseline(srs_body: list[tuple[int, str]], design_body: list[tuple[int, str]]) -> dict:
    """从两节正文生成基线（`--write-baseline` 与夹具走**同一段代码路径**）。"""
    srs_rows = parse_behaviors(srs_body)
    design_rows = parse_behaviors(design_body)
    numbers: dict[str, dict] = {}
    for number in sorted(set(srs_rows) & set(design_rows)):
        numbers[number] = {
            "srs": behavior_items(srs_rows[number][-1][1]),
            "des": behavior_items(design_rows[number][-1][1]),
        }
    return {
        "_说明": ("行为名列基线（棘轮）。**改本文件 = 契约层动作，必须留痕** —— 它是「行为名"
                  "不得改名、不得增删」的唯一真值源（前门 `T-20261014-201` ㈡ 裁「判行为标识」）。"),
        "_口径": "归一 = 去强调/反引号 → 去括注（连内容）→ 按 `、`/`；` 切条 → 压空白、去首尾标点。",
        "_生成": "python3 Scripts/check-p-parity.py --write-baseline",
        "_差异读数": behavior_diff_readout(numbers),
        "numbers": numbers,
    }


def check_behavior(root: pathlib.Path, srs_body, design_body) -> tuple[list[str], list[str]]:
    """判据 E：行为名列与基线逐号对账 ⇒（问题, 说明行）。"""
    problems: list[str] = []
    notes: list[str] = []
    srs_rows, design_rows = parse_behaviors(srs_body), parse_behaviors(design_body)

    for label, rows in ((SRS, srs_rows), (DESIGN, design_rows)):
        for number in sorted(rows):
            lineno, text = rows[number][-1]
            if not behavior_items(text):
                problems.append(
                    f"{label}:{lineno}：`{number}` 的「必须一致的行为」列一行条目名都解析不到 —— "
                    f"面不许空跑（空单元格或判据自坏都算）")

    path = root / BEHAVIOR_BASELINE
    if not path.exists():
        problems.append(
            f"{BEHAVIOR_BASELINE}：行为名列基线台账不在盘 ⇒ 判据 E 的棘轮无从对账"
            f"（生成：python3 Scripts/check-p-parity.py --write-baseline）")
        return problems, notes
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        baseline = payload.get("numbers") or {}
    except (OSError, ValueError) as exc:
        problems.append(f"{BEHAVIOR_BASELINE}：读不出（{exc.__class__.__name__}: {exc}）⇒ 不可判")
        return problems, notes

    both = sorted(set(srs_rows) & set(design_rows))
    for number in [n for n in both if n not in baseline]:
        problems.append(f"`{number}`：两侧登记表都在盘、但行为名列基线里没有这个号 —— 新号必须登记（未登记号）")
    for number in sorted(set(baseline) - set(srs_rows) - set(design_rows)):
        problems.append(f"{BEHAVIOR_BASELINE}：`{number}` 是死条目 —— 两侧登记表里都没有它了")
    for number in both:
        if not isinstance(baseline.get(number), dict):
            continue
        for side, label in (("srs", SRS), ("des", DESIGN)):
            rows = srs_rows if side == "srs" else design_rows
            lineno = rows[number][-1][0]
            new = set(behavior_items(rows[number][-1][1]))
            old = set(baseline[number].get(side) or [])
            for name in sorted(new - old):
                problems.append(
                    f"{label}:{lineno}：`{number}` 行为名列出现基线里没有的条目名「{name}」—— 未登记变化")
            for name in sorted(old - new):
                problems.append(
                    f"{label}:{lineno}：`{number}` 行为名列条目名「{name}」与基线不符（改名或消失）—— 未登记变化")
    if not problems:
        readout = payload.get("_差异读数") or {}
        notes.append(
            f"行为名棘轮：基线 {len(baseline)} 号逐号对上 · 两侧归一后条目名差异 "
            f"{readout.get('两侧归一后条目名差异号数', '?')} 号（待前门归口清单见台账 `_差异读数`）")
    return problems, notes


def check(root: pathlib.Path) -> tuple[list[str], list[str]]:
    """返回 `(问题, 说明行)`。问题非空即判红。"""
    problems: list[str] = []
    notes: list[str] = []

    srs_path = root / SRS
    design_path = root / DESIGN
    for path in (srs_path, design_path):
        if not path.exists():
            problems.append(f"{path.relative_to(root)}：文件不存在 —— 本判据必须两侧都在才能对账")
            return problems, notes

    srs_lines = srs_path.read_text(encoding="utf-8").splitlines()
    design_lines = design_path.read_text(encoding="utf-8").splitlines()

    srs_body = section(srs_lines, SRS_HEADING, SRS_STOP)
    design_body = section(design_lines, DESIGN_HEADING, DESIGN_STOP)
    if not srs_body:
        problems.append(f"{SRS}：找不到「## 9.2 平台差异登记表」小节")
    if not design_body:
        problems.append(f"{DESIGN}：找不到「第四章 允许不同的部分（平台差异）」小节")
    if problems:
        return problems, notes

    srs_rows = parse_registry(srs_body)
    design_rows = parse_registry(design_body)
    if not srs_rows:
        problems.append(f"{SRS}:{srs_body[0][0]}：§9.2 里一行 `P-*` 定义行都解析不到")
    if not design_rows:
        problems.append(f"{DESIGN}:{design_body[0][0]}：§4 里一行 `P-*` 定义行都解析不到")
    if problems:
        return problems, notes

    # A 双向覆盖
    only_srs = sorted(set(srs_rows) - set(design_rows))
    only_design = sorted(set(design_rows) - set(srs_rows))
    for number in only_srs:
        lineno, domain = effective(srs_rows, number)
        problems.append(
            f"{SRS}:{lineno}：`{number}`（{normalize_domain(domain)}）只在 §9.2 登记，§4 没有 —— "
            f"两张表自称一一对应，缺一边就是「编号空间断档」"
        )
    for number in only_design:
        lineno, domain = effective(design_rows, number)
        problems.append(
            f"{DESIGN}:{lineno}：`{number}`（{normalize_domain(domain)}）只在 §4 登记，§9.2 没有 —— "
            f"§9.2 是权威登记表（编号冲突以它为准），未登记的差异按契约「必须一致」处理"
        )
    if not only_srs and not only_design:
        notes.append(
            f"双向覆盖：两侧编号集合相等（{len(srs_rows)} 条：{sorted(srs_rows)[0]} ~ {sorted(srs_rows)[-1]}）"
        )

    # B 同号同物
    mismatches = 0
    for number in sorted(set(srs_rows) & set(design_rows)):
        srs_lineno, srs_domain = effective(srs_rows, number)
        design_lineno, design_domain = effective(design_rows, number)
        left, right = normalize_domain(srs_domain), normalize_domain(design_domain)
        if left != right:
            mismatches += 1
            problems.append(
                f"`{number}` 同号不同物：{SRS}:{srs_lineno} 写「{left}」/ "
                f"{DESIGN}:{design_lineno} 写「{right}」—— 同号必须指同一件事（历史实证 `P-15`："
                f"SSH 隧道 vs 笔记存储引擎）"
            )
    if not mismatches:
        notes.append(f"同号同物：两侧共有编号 {len(set(srs_rows) & set(design_rows))} 条，领域归一后逐条一致")

    # D 同侧编号唯一（同一张登记表内部不许同号两条 —— 后行会静默覆盖前行）
    dup_sides = 0
    for label, rows in ((SRS, srs_rows), (DESIGN, design_rows)):
        for number in sorted(rows):
            occurrences = rows[number]
            if len(occurrences) < 2:
                continue
            dup_sides += 1
            sites = " / ".join(f"{label}:{lineno}" for lineno, _ in occurrences)
            problems.append(
                f"{label}：`{number}` 在**同一张登记表里出现 {len(occurrences)} 次**（{sites}）—— "
                f"同侧同号两条不许存在：解析按**后行生效**，前行会被**静默吞掉**（判据 A 只比集合、看不出来）。"
                f"（本判据只判同一张表内部；§8.5.5 那种「先落条、待并入」的续排提到同号不算 —— 归判据 C）"
            )
    if not dup_sides:
        notes.append(
            f"编号唯一：§9.2 定义行 {sum(len(v) for v in srs_rows.values())} 行 / "
            f"§4 定义行 {sum(len(v) for v in design_rows.values())} 行，两侧同号重复 0 处"
        )

    # C §8.5.5 已落条但未并入
    windows_body = section(design_lines, WINDOWS_HEADING, WINDOWS_STOP)
    if not windows_body:
        notes.append("§8.5.5 小节不存在（对侧独占节尚未落条）—— 本档跳过，不等于通过")
    else:
        landed: dict[str, int] = {}
        for lineno, line in windows_body:
            for number in P_REFERENCE.findall(line):
                landed.setdefault(number, lineno)
        unmerged = sorted(
            number for number in landed
            if number not in srs_rows or number not in design_rows
        )
        for number in unmerged:
            missing = []
            if number not in srs_rows:
                missing.append("§9.2")
            if number not in design_rows:
                missing.append("§4")
            problems.append(
                f"{DESIGN}:{landed[number]}：§8.5.5（`[独占:windows]`）已落条目 `{number}`，"
                f"但它还没进 {' / '.join(missing)} —— 「已落条但未并入」不许静默（归档动作见队列 L-45："
                f"照抄不改写 + 补「为什么必须不同」与「用户可感知的差异」）"
            )
        if not unmerged:
            notes.append(f"§8.5.5 告警：该节已落的 {len(landed)} 条编号全部已并入 §4 与 §9.2")

    # E 行为名列棘轮（前门 `T-20261014-201` ㈡ 裁「判行为标识，不判逐字正文」）
    behavior_problems, behavior_notes = check_behavior(root, srs_body, design_body)
    problems.extend(behavior_problems)
    notes.extend(behavior_notes)
    return problems, notes


def run(root: pathlib.Path, quiet: bool) -> int:
    problems, notes = check(root)
    if not quiet:
        print("=== P-* 平台差异登记对账（SRS §9.2 ↔ 概要设计 §4，含 §8.5.5 已落条告警）===")
        for line in notes:
            print(f"    ℹ️ {line}")
        if problems:
            print(f"\n❌ 判红 {len(problems)} 处：")
        for line in problems:
            print(f"  · {line}")
    if problems:
        print(f"\n❌ P-* 对账不通过（{len(problems)} 处）")
        return 1
    if not quiet:
        print("\n✅ P-* 对账通过（双向覆盖 + 同号同物 + 编号唯一 + §8.5.5 无未并入条目 "
              "+ 行为名棘轮对上）")
    return 0


GOOD_SRS = """# 需求规范书

## 9.2 平台差异登记表（哪些允许不同）

> 与 `Docs/Doyah产品概要设计说明书.md` §4 一一对应。

| 编号 | 领域 | 必须一致的行为（跨平台契约） | 允许不同的实现 | 关联 |
|---|---|---|---|---|
| P-01 | GUI 框架与控件 | 信息架构 | 控件树 | §0.8 |
| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-ALL-GATE-SEC-001 |

### 10.10 平台等价矩阵（机械生成）

| 编号 | 摘要 |
|---|---|
| FR-XX | 别的表，不该被本判据当成定义行 |
"""

GOOD_DESIGN = """# 概要设计

# 第四章 允许不同的部分（平台差异）

完整登记表见 SRS §9.2。

| 编号 | 领域 | 必须一致的行为 | 允许不同的实现 |
|---|---|---|---|
| P-01 | GUI 框架与控件 | 信息架构 | 控件树 |
| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 |

## 5. 关键设计决策（ADR）

## 8.5 契约 → Windows 实现 [独占:windows]

### 8.5.5 平台差异登记（§4 的 `P-*` 续排，先在本节落条目，待契约侧并入 §4）

`P-01` 甲｜`P-02` 乙。

### 8.5.6 待定与提案

没有别的号。
"""

CASES = [
    ("两侧一致（好）", GOOD_SRS, GOOD_DESIGN, [], 0),
    ("§4 多一条、§9.2 没有（未并入权威登记表）",
     GOOD_SRS,
     GOOD_DESIGN.replace(
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 |\n",
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 |\n| P-03 | 目录授权 | 授权来自用户 | NTFS |\n"),
     ["P-03", "只在 §4"], 1),
    ("§9.2 多一条、§4 没有（编号空间断档）",
     GOOD_SRS.replace(
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-ALL-GATE-SEC-001 |\n",
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-ALL-GATE-SEC-001 |\n"
         "| P-07 | 字体与输入法 | 等宽渲染 | 字体选择 | NFR-I18N |\n"),
     GOOD_DESIGN, ["P-07", "只在 §9.2", "编号空间断档"], 1),
    ("同号不同物（P-01 两侧指两件事）",
     GOOD_SRS,
     GOOD_DESIGN.replace("| P-01 | GUI 框架与控件 |", "| P-01 | 终端实现 |"),
     ["P-01", "同号不同物", "终端实现"], 1),
    ("§8.5.5 已落条但未并入 §4 / §9.2",
     GOOD_SRS,
     GOOD_DESIGN.replace("`P-01` 甲｜`P-02` 乙。", "`P-01` 甲｜`P-02` 乙｜`P-17` 终端仿真与 PTY。"),
     ["P-17", "§8.5.5", "未并入"], 1),
    ("归一有效：加粗 / 反引号 / 括号附注 / 多余空白都算同一件事",
     GOOD_SRS.replace(
         "| P-01 | GUI 框架与控件 | 信息架构 | 控件树 | §0.8 |",
         "| **P-01** | **GUI 框架与控件（`NSView` 树）** | 信息架构 | 控件树 | §0.8 |"),
     GOOD_DESIGN.replace(
         "| P-01 | GUI 框架与控件 | 信息架构 | 控件树 |",
         "| `P-01` | GUI   框架与控件（窗口与控件树） | 信息架构 | 控件树 |"),
     [], 0),
    ("§9.2 的小节被删（判据不许空跑当通过）",
     GOOD_SRS.replace("## 9.2 平台差异登记表（哪些允许不同）", "### 9.2x 别的节"),
     GOOD_DESIGN, ["找不到"], 1),
    ("§4 里一行定义行都解析不到",
     GOOD_SRS,
     GOOD_DESIGN.replace(
         "| P-01 | GUI 框架与控件 | 信息架构 | 控件树 |\n"
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 |\n", ""),
     ["解析不到"], 1),
    ("同侧同号两条（后行会静默覆盖前行 —— 旧码输出与基线逐字同）",
     GOOD_SRS.replace(
         "| P-01 | GUI 框架与控件 | 信息架构 | 控件树 | §0.8 |",
         "| P-01 | 终端实现（探针） | 信息架构 | 控件树 | §0.8 |\n"
         "| P-01 | GUI 框架与控件 | 信息架构 | 控件树 | §0.8 |"),
     GOOD_DESIGN, ["P-01", "同一张登记表里出现 2 次", "静默吞掉"], 1),
    ("同侧逐字重复行（集合去重看不见）",
     GOOD_SRS.replace(
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-ALL-GATE-SEC-001 |",
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-ALL-GATE-SEC-001 |\n"
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-ALL-GATE-SEC-001 |"),
     GOOD_DESIGN, ["P-02", "同一张登记表里出现 2 次"], 1),
    ("对手臂：§8.5.5 续排节里重复提到同一号 ⇒ 不判红（跨节同号是合法过渡态）",
     GOOD_SRS,
     GOOD_DESIGN.replace("`P-01` 甲｜`P-02` 乙。", "`P-01` 甲｜`P-01` 甲续｜`P-02` 乙。"),
     [], 0),
]


def _write_baseline_file(root: pathlib.Path, payload: dict) -> None:
    path = root / BEHAVIOR_BASELINE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _baseline_from_text(srs_text: str, design_text: str) -> dict:
    """夹具基线：与 `--write-baseline` 走同一段代码路径（`section` + `build_baseline`）。"""
    return build_baseline(
        section(srs_text.splitlines(), SRS_HEADING, SRS_STOP),
        section(design_text.splitlines(), DESIGN_HEADING, DESIGN_STOP),
    )


E_CASES: list[tuple] = [
    ("行为名列条目名改名（未登记 ⇒ 判红）",
     None,
     GOOD_SRS.replace("| P-01 | GUI 框架与控件 | 信息架构 |", "| P-01 | GUI 框架与控件 | 信息架构与导航 |"),
     GOOD_DESIGN, ["P-01", "信息架构与导航", "未登记变化"], 1),
    ("行为名列条目名删掉（基线那一条消失 ⇒ 判红）",
     {"numbers": {"P-01": {"srs": ["信息架构", "交互语义"], "des": ["信息架构"]},
                  "P-02": {"srs": ["不落配置文件"], "des": ["不落配置文件"]}}},
     GOOD_SRS, GOOD_DESIGN, ["交互语义", "未登记变化"], 1),

    ("基线里的死条目（两侧登记表都没有这个号 ⇒ 判红）",
     {"numbers": {"P-01": {"srs": ["信息架构"], "des": ["信息架构"]},
                  "P-02": {"srs": ["不落配置文件"], "des": ["不落配置文件"]},
                  "P-09": {"srs": ["自动更新"], "des": ["自动更新"]}}},
     GOOD_SRS, GOOD_DESIGN, ["P-09", "死条目"], 1),
    ("对手臂：加括注 / 加粗 / 换空白 ⇒ 仍绿（括注与措辞不进行为名集合）",
     None,
     GOOD_SRS.replace("| P-01 | GUI 框架与控件 | 信息架构 | 控件树 | §0.8 |",
                      "| P-01 | GUI 框架与控件 | **信息架构**（活动栏 / 侧栏 / 编辑器区） | 控件树 | §0.8 |"),
     GOOD_DESIGN.replace("| P-01 | GUI 框架与控件 | 信息架构 | 控件树 |",
                         "| P-01 | GUI 框架与控件 | 信息架构（窗口与控件树） | 控件树 |"),
     [], 0),
    ("基线台账不在盘 ⇒ 判红（面必须钉住）",
     "MISSING", GOOD_SRS, GOOD_DESIGN, ["不在盘"], 1),
]


def self_test() -> int:
    real_root = pathlib.Path(__file__).resolve().parent.parent
    targets = [real_root / SRS, real_root / DESIGN]
    before = {
        path: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in targets if path.exists()
    }

    failures = 0
    for name, srs_text, design_text, expect, expected_code in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Docs").mkdir()
            (root / SRS).write_text(srs_text, encoding="utf-8")
            (root / DESIGN).write_text(design_text, encoding="utf-8")
            _write_baseline_file(root, _baseline_from_text(GOOD_SRS, GOOD_DESIGN))
            problems, _ = check(root)
            text = "\n".join(problems)
            hit = all(fragment in text for fragment in expect) if expect else not problems
            code = 1 if problems else 0
            ok = hit and code == expected_code
            print(f"{'✅' if ok else '❌'} 负例 {name}（期望退出码 {expected_code}，实得 {code}"
                  f"{'' if hit else ' / 报出的原因与期望不符'}）")
            if not ok:
                failures += 1
                print(f"     报出：{text or '（无）'}")

    for name, baseline, srs_text, design_text, expect, expected_code in E_CASES:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Docs").mkdir()
            (root / SRS).write_text(srs_text, encoding="utf-8")
            (root / DESIGN).write_text(design_text, encoding="utf-8")
            if baseline != "MISSING":
                _write_baseline_file(
                    root,
                    baseline if isinstance(baseline, dict)
                    else _baseline_from_text(GOOD_SRS, GOOD_DESIGN))
            problems, _ = check(root)
            text = "\n".join(problems)
            hit = all(fragment in text for fragment in expect) if expect else not problems
            code = 1 if problems else 0
            ok = hit and code == expected_code
            print(f"{'✅' if ok else '❌'} 负例 E {name}（期望退出码 {expected_code}，实得 {code}"
                  f"{'' if hit else ' / 报出的原因与期望不符'}）")
            if not ok:
                failures += 1
                print(f"     报出：{text or '（无）'}")

    after = {
        path: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in targets if path.exists()
    }
    if before != after:
        print("❌ 负例跑完真仓库的两份文档被改动了（不合格）")
        failures += 1
    else:
        print(f"✅ 负例全程只在临时目录里写坏，真仓库 {len(before)} 份文档逐字节未变")

    total = len(CASES) + len(E_CASES)
    print(f"\n{'✅' if not failures else '❌'} 负例 {total - failures}/{total} 达到预期")
    return 1 if failures else 0


def write_baseline(root: pathlib.Path) -> int:
    """按当前两份文档重写行为名列基线（`--write-baseline`）。"""
    for path in (root / SRS, root / DESIGN):
        if not path.exists():
            print(f"❌ {path.relative_to(root)} 不存在 —— 基线无从生成")
            return 1
    payload = build_baseline(
        section((root / SRS).read_text(encoding="utf-8").splitlines(), SRS_HEADING, SRS_STOP),
        section((root / DESIGN).read_text(encoding="utf-8").splitlines(), DESIGN_HEADING, DESIGN_STOP),
    )
    _write_baseline_file(root, payload)
    readout = payload["_差异读数"]
    print(f"✅ 已写 {BEHAVIOR_BASELINE}：{len(payload['numbers'])} 号 · 两侧归一后条目名差异 "
          f"{readout['两侧归一后条目名差异号数']} 号 · SRS 独有 {readout['SRS 独有项']} 项 / "
          f"DES 独有 {readout['DES 独有项']} 项（差异号：{' '.join(readout['差异号'])}）")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="P-* 平台差异登记对账（L-45）")
    parser.add_argument("--root", default=None, help="仓库根（默认 = 脚本的上一级目录）")
    parser.add_argument("--quiet", action="store_true", help="只打印问题")
    parser.add_argument("--self-test", action="store_true", help="跑负例（临时目录里写坏）")
    parser.add_argument("--write-baseline", action="store_true",
                        help="按当前两份文档重写行为名列基线（判据 E 的台账；改基线 = 契约层动作，须留痕）")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    root = pathlib.Path(args.root).resolve() if args.root else ROOT
    if args.write_baseline:
        return write_baseline(root)
    return run(root, args.quiet)


if __name__ == "__main__":
    sys.exit(main())
