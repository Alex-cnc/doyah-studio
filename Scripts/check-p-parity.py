#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`P-*` 平台差异登记的两侧对账门禁（队列 L-45）。

为什么需要它 —— 两张自称「一一对应」的表，此前**一个判据都没有**：

1. `Docs/概要设计.md` §4「允许不同的部分（平台差异）」与 `Docs/需求规范书.md` §10.9
   「平台差异登记表（哪些允许不同）」在正文里互相写着「与 …… 一一对应」；
2. `Scripts/verify-all.sh` **第 7 项的注释**甚至一直写着「平台等价矩阵与 §10.9 登记表一致」——
   那是错的：那一项只做 §10.10 ↔ `Docs/平台实现状态.json` 的矩阵对账（2026-09-27 第 25 轮
   改正了这句注释，并登记本条目）；
3. 实测现状（第 25 轮取证）：概要设计 §4 有 `P-16`，§8.5.5（`[独占:windows]`）另落了
   `P-17`~`P-24` 并原文写明「先在本节落条目，**待契约侧并入 §4**」，而 SRS §10.9 只到
   `P-15` ⇒ **编号空间断档 9 条**，两侧各说各话，没有任何一处会报红。
4. 历史实证（第 27 轮）：`P-15` 在 §4 是「SSH 隧道」、在 SRS §10.9 是「笔记存储引擎」——
   **同号不同物**，靠人读才发现，已按「§10.9 为权威登记表」让号（SSH 隧道 → `P-25`）。

判据（三类）：

- **A 双向覆盖**：§10.9 的编号集合与 §4 的编号集合必须**相等**；各自多出的号逐条点名。
- **B 同号同物**：两侧同号行的**领域**必须指同一件事。归一化 = 去掉 `**` 与反引号 →
  截到首个 `（` / `(` 之前 → 压空白 → 逐字相等（`P-15` 一侧写 `**笔记存储引擎（`FR-PLUG-08`）**`、
  另一侧写 `笔记存储引擎（`FR-PLUG-08`）`，归一后都是「笔记存储引擎」）。
- **C §8.5.5 显式告警**：对侧独占节 §8.5.5 里已落的条目（形如 `` `P-17` 终端仿真与 PTY ``），
  只要有一号没有**同时**出现在 §4 与 §10.9，就判红 —— 「已落条但未并入」不许静默（该节的
  合并动作本来就是契约侧的活；它自己那条「待契约侧并入」的注是该节作者的事，本门禁不去改它）。

本判据**不做**的两件事（免得下次有人以为查过了）：

- **不判行序**：SRS §10.9 本来就不是按号排的（`P-14` 在 `P-13` 之前），判序只会造假红；
- **不判「同域不同号」**：`P-17`（终端仿真与 PTY）与 `P-05`（内嵌终端）同域、`P-19`/`P-21`/`P-24`
  与 `P-06`/`P-08`/`P-09` 同域 —— 那是**登记表要不要合并条目**的设计问题，需对侧拍板，
  归提案与队列条目，不属于「编号对账」（机械判据只判能机械判的那部分）。

用法：

    python3 Scripts/check-p-parity.py               # 查两侧
    python3 Scripts/check-p-parity.py --self-test    # 负例（临时目录里写坏，末条核对真仓库未动）
    python3 Scripts/check-p-parity.py --quiet        # 只打印问题

退出码：0 = 全绿；1 = 有覆盖缺口 / 同号不同物 / §8.5.5 已落条但未并入（逐条打印 `文件:行号`）。
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

SRS = "Docs/需求规范书.md"
DESIGN = "Docs/概要设计.md"

SRS_HEADING = re.compile(r"^### 10\.9 ")
SRS_STOP = re.compile(r"^#{1,3} ")
DESIGN_HEADING = re.compile(r"^## 4\. ")
DESIGN_STOP = re.compile(r"^#{1,2} ")
WINDOWS_HEADING = re.compile(r"^#### 8\.5\.5 ")
WINDOWS_STOP = re.compile(r"^#{1,4} ")

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


def parse_registry(body: list[tuple[int, str]]) -> dict[str, tuple[int, str]]:
    """解析登记表：编号 → (行号, 领域原文)。只认**定义行**（首格就是编号）。"""
    rows: dict[str, tuple[int, str]] = {}
    for lineno, line in body:
        match = DEFINITION_ROW.match(line)
        if not match:
            continue
        cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", line)]
        if len(cells) < 3:
            continue
        rows[match.group(1)] = (lineno, cells[2])
    return rows


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
        problems.append(f"{SRS}：找不到「### 10.9 平台差异登记表」小节")
    if not design_body:
        problems.append(f"{DESIGN}：找不到「## 4. 允许不同的部分（平台差异）」小节")
    if problems:
        return problems, notes

    srs_rows = parse_registry(srs_body)
    design_rows = parse_registry(design_body)
    if not srs_rows:
        problems.append(f"{SRS}:{srs_body[0][0]}：§10.9 里一行 `P-*` 定义行都解析不到")
    if not design_rows:
        problems.append(f"{DESIGN}:{design_body[0][0]}：§4 里一行 `P-*` 定义行都解析不到")
    if problems:
        return problems, notes

    # A 双向覆盖
    only_srs = sorted(set(srs_rows) - set(design_rows))
    only_design = sorted(set(design_rows) - set(srs_rows))
    for number in only_srs:
        lineno, domain = srs_rows[number]
        problems.append(
            f"{SRS}:{lineno}：`{number}`（{normalize_domain(domain)}）只在 §10.9 登记，§4 没有 —— "
            f"两张表自称一一对应，缺一边就是「编号空间断档」"
        )
    for number in only_design:
        lineno, domain = design_rows[number]
        problems.append(
            f"{DESIGN}:{lineno}：`{number}`（{normalize_domain(domain)}）只在 §4 登记，§10.9 没有 —— "
            f"§10.9 是权威登记表（编号冲突以它为准），未登记的差异按契约「必须一致」处理"
        )
    if not only_srs and not only_design:
        notes.append(
            f"双向覆盖：两侧编号集合相等（{len(srs_rows)} 条：{sorted(srs_rows)[0]} ~ {sorted(srs_rows)[-1]}）"
        )

    # B 同号同物
    mismatches = 0
    for number in sorted(set(srs_rows) & set(design_rows)):
        srs_lineno, srs_domain = srs_rows[number]
        design_lineno, design_domain = design_rows[number]
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
                missing.append("§10.9")
            if number not in design_rows:
                missing.append("§4")
            problems.append(
                f"{DESIGN}:{landed[number]}：§8.5.5（`[独占:windows]`）已落条目 `{number}`，"
                f"但它还没进 {' / '.join(missing)} —— 「已落条但未并入」不许静默（归档动作见队列 L-45："
                f"照抄不改写 + 补「为什么必须不同」与「用户可感知的差异」）"
            )
        if not unmerged:
            notes.append(f"§8.5.5 告警：该节已落的 {len(landed)} 条编号全部已并入 §4 与 §10.9")

    return problems, notes


def run(root: pathlib.Path, quiet: bool) -> int:
    problems, notes = check(root)
    if not quiet:
        print("=== P-* 平台差异登记对账（SRS §10.9 ↔ 概要设计 §4，含 §8.5.5 已落条告警）===")
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
        print("\n✅ P-* 对账通过（双向覆盖 + 同号同物 + §8.5.5 无未并入条目）")
    return 0


GOOD_SRS = """# 需求规范书

### 10.9 平台差异登记表（哪些允许不同）

> 与 `Docs/概要设计.md` §4 一一对应。

| 编号 | 领域 | 必须一致的行为（跨平台契约） | 允许不同的实现 | 关联 |
|---|---|---|---|---|
| P-01 | GUI 框架与控件 | 信息架构 | 控件树 | §0.8 |
| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-SEC-01 |

### 10.10 平台等价矩阵（机械生成）

| 编号 | 摘要 |
|---|---|
| FR-XX | 别的表，不该被本判据当成定义行 |
"""

GOOD_DESIGN = """# 概要设计

## 4. 允许不同的部分（平台差异）

完整登记表见 SRS §10.9。

| 编号 | 领域 | 必须一致的行为 | 允许不同的实现 |
|---|---|---|---|
| P-01 | GUI 框架与控件 | 信息架构 | 控件树 |
| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 |

## 5. 关键设计决策（ADR）

### 8.5 契约 → Windows 实现 [独占:windows]

#### 8.5.5 平台差异登记（§4 的 `P-*` 续排，先在本节落条目，待契约侧并入 §4）

`P-01` 甲｜`P-02` 乙。

#### 8.5.6 待定与提案

没有别的号。
"""

CASES = [
    ("两侧一致（好）", GOOD_SRS, GOOD_DESIGN, [], 0),
    ("§4 多一条、§10.9 没有（未并入权威登记表）",
     GOOD_SRS,
     GOOD_DESIGN.replace(
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 |\n",
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 |\n| P-03 | 目录授权 | 授权来自用户 | NTFS |\n"),
     ["P-03", "只在 §4"], 1),
    ("§10.9 多一条、§4 没有（编号空间断档）",
     GOOD_SRS.replace(
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-SEC-01 |\n",
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 | NFR-SEC-01 |\n"
         "| P-07 | 字体与输入法 | 等宽渲染 | 字体选择 | NFR-I18N |\n"),
     GOOD_DESIGN, ["P-07", "只在 §10.9", "编号空间断档"], 1),
    ("同号不同物（P-01 两侧指两件事）",
     GOOD_SRS,
     GOOD_DESIGN.replace("| P-01 | GUI 框架与控件 |", "| P-01 | 终端实现 |"),
     ["P-01", "同号不同物", "终端实现"], 1),
    ("§8.5.5 已落条但未并入 §4 / §10.9",
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
    ("§10.9 的小节被删（判据不许空跑当通过）",
     GOOD_SRS.replace("### 10.9 平台差异登记表（哪些允许不同）", "### 10.9x 别的节"),
     GOOD_DESIGN, ["找不到"], 1),
    ("§4 里一行定义行都解析不到",
     GOOD_SRS,
     GOOD_DESIGN.replace(
         "| P-01 | GUI 框架与控件 | 信息架构 | 控件树 |\n"
         "| P-02 | 凭据存储 | 不落配置文件 | 钥匙串 |\n", ""),
     ["解析不到"], 1),
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

    after = {
        path: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in targets if path.exists()
    }
    if before != after:
        print("❌ 负例跑完真仓库的两份文档被改动了（不合格）")
        failures += 1
    else:
        print(f"✅ 负例全程只在临时目录里写坏，真仓库 {len(before)} 份文档逐字节未变")

    print(f"\n{'✅' if not failures else '❌'} 负例 {len(CASES) - failures}/{len(CASES)} 达到预期")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="P-* 平台差异登记对账（L-45）")
    parser.add_argument("--root", default=None, help="仓库根（默认 = 脚本的上一级目录）")
    parser.add_argument("--quiet", action="store_true", help="只打印问题")
    parser.add_argument("--self-test", action="store_true", help="跑负例（临时目录里写坏）")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    root = pathlib.Path(args.root).resolve() if args.root else ROOT
    return run(root, args.quiet)


if __name__ == "__main__":
    sys.exit(main())
