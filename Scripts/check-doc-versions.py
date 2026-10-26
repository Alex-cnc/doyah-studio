#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""变更记录版本号与条目号的机械查重（队列 L-32）。

为什么需要它（全是真事，不是假想）：

1. 2026-09-27 本侧与对侧在概要设计上同取 `v2.35` —— 靠手工 rebase 解冲突；
2. 同一天队列里 `L-25` / `L-26` / `L-41` 各出现两次（拍板分配的条目与循环新开的条目同号）；
3. 本台账（`Docs/智能体助手-开发规范.md`）的变更记录出现 **5 对**同号行（`v1.46` / `v1.45` /
   `v1.28` / `v1.26` / `v1.19`）；
4. 概要设计 §4 的 `P-15` 与 SRS §10.9 的 `P-15` 同号不同物（那一族的跨文档对账归 **L-45**）。

现有门禁全都看不见它：表格列数比的是「列数」、状态一致性比的是「状态位」、平台矩阵比的是
「台账 ↔ 表格」—— **没有一条比「编号与编号」**。撞号一次要花一整轮去手工善后，所以这里把它
变成机器判据。

判据（三类）：

- **A 版本号唯一**：同一份文档的变更记录里，版本号不得重复（表格式 `| **v1.66** |` 与
  引用式 `> **v1.66（日期）**` 两种形状都认）。
- **B 头部版本格可判**：头部「版本 / 当前版本」格的号必须
  ① **出现在**变更记录里（防「凭空写一个号」），且
  ② **等于**变更记录最高号；若该格带**显式标注**（含「基线 / 首版」字样），则标注里必须写出
  当前最高号（形如 `**v3.28（正式版基线；当前 v3.243）**`）—— 标注意义不丢、当前号也能判。
  没有头部格的文档（如 `Docs/开发记录-*.md`）跳过本档，只按 A 判。
- **C 条目号唯一**：队列文件里**定义行**（首格 `| **L-52** |`）的条目号不得重复；
  正文里的引用不算定义，故不计入（否则判据会被引用次数淹没）。
  **定义行的行形状（2026-09-29 第 70 轮，L-77）**：编号格**允许在 `**L-xx**` 后带括注**
  （`| **L-24**（宿主侧仅此一条） | …` —— 括注算同一格，本队列真有一行这么写）⇒ 尾注不影响识别；
  第 70 轮前该行**不匹配 → 被当成「不是定义行」静默跳过**，它的号被谁占了都不会报（实测本机队列
  定义行 **86 → 87**，多的那一条正是 `L-24`；同一个盲点在本机两个循环脚本里已由队列 **L-77** 修掉）。
- **D 受检清单自洽**（2026-09-29 第 88 轮，队列 **L-88**）：`VERSION_DOCS` 是**手抄**的清单 ——
  新文档建出来**不会自动进来**，于是它连「撞号 + 头部漂移」都**全绿**。实测现场 =
  `Docs/发布计划.md`（2026-09-29 建，两侧都在改：本侧 + §9 归小河马）：**`v1.9` 有两行重复、
  `v1.8` 两行不同内容同号、头部格 `v1.8` ≠ 变更记录最高 `v1.9`** —— 而闭环 18 项全绿。
  判据 = 凡 `COVERAGE_ROOT_GLOBS`（仓根 `*.md` + `Docs/**/*.md`）里**带「变更记录」节**的文档，必须在
  `VERSION_DOCS` 或开发记录通配里，否则判红；`Docs/archive/` 豁免（**理由与命中计数**都写在
    `COVERAGE_EXEMPT` 里；目录在盘而命中 0 份 ⇒ 陈旧豁免判红、目录不在盘 ⇒ 出声但不可判）。

**2026-10-14（合册 `T-20261013-027` · 原单 `T-20261010-075` ㈠~㈦）**：本判据**独立复验**前门 P0 件
`T-20261010-030` 的两笔修复（已落地且逐条吻合）时抓出的**六形缺口**，本轮全部收口 —— ① 行首允许
≤3 空格缩进（表格嵌在列表项 / 引用里是合法写法，旧码缩进一格**整档失明**）；② 队列文件不在盘
（= 任何新克隆 / 对侧 Windows 端的默认条件）时收尾**不得**再写「队列条目号唯一」；③ 头部版本格的
窗口**显式闭合**（扫到「变更记录」节标题为止；节标题之后**带版本号**的头部形状 ⇒ 判「不可判」）；④ 豁免**有钉**
（目录在盘而命中计数为 0 ⇒ 陈旧豁免判红）；⑤ 判定物先**剥围栏与 HTML 注释**（代码块里的示例行不是变更行）；
⑥ 读文档**兜底**（非 UTF-8 / 目录占位逐条报原因，**不吐栈**）。

顺带说明两件「本判据不做」的事（避免下次有人以为查过了）：

- **跨文档编号空间**（`P-*` / `FR-*` 在不同文档里的含义）不在本判据里 —— 归 **L-45**；
- **单调顺序**（变更行必须严格递减）不在本判据里：本台账的引用式记录**本来就不是单调的**
  （历史插行造成 `v1.54` 在 `v1.53` 之前），把顺序判红会造出一堆假红；本判据只判「唯一 + 可判」。

用法：

    python3 Scripts/check-doc-versions.py                # 查全部
    python3 Scripts/check-doc-versions.py --self-test     # 负例（临时目录里写坏，末条核对真仓库未动）
    python3 Scripts/check-doc-versions.py --quiet         # 只打印问题

判据自己的证据（28 例）：`--self-test` 把 A/B/C 三档写坏 **16 例** + 判据 D「受检清单自洽」**6 例** + **跨平台标识 1 例**（Windows 形态的相对路径必须落回清单写法，提案 0005）+ **读取兜底与收尾文案 4 例**（非 UTF-8 / 目录占位 / 队列不在盘不得自称唯一 / 队列在盘对手臂）+ **变更记录外置 1 例**（正文只剩指针 ⇒ 不算空，2026-10-20）
（未登记 ⇒ 判红 / 无变更记录节 ⇒ 不纳入 / 在清单里 ⇒ 放行 / `Docs/archive/` ⇒ 豁免）；
例数的唯一来源 = `Scripts/self-test-counts.json`（本行由它机械对账）。

退出码：0 = 全绿；1 = 有撞号 / 头部不可判（逐条打印 `文件:行号`）。
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# 带「变更记录 + 头部版本格」的文档：True = 必须存在（三书），False = 在盘上才查。
VERSION_DOCS = [
    ("Docs/Doyah产品需求规格说明书.md", True),
    ("Docs/Doyah产品开发计划任务清单.md", True),
    ("Docs/Doyah产品能力规划说明书.md", True),
    ("Docs/Doyah产品概要设计说明书.md", True),
    # 2026-10-23：执行契约新体裁 v0.1（自带 §14 变更记录 + 头部版本格）。
    # 2026-10-21：Studio 线详细设计模板（§12 变更记录 + 头部版本格）。
    ("Docs/模板-详细设计说明书-Studio.md", False),
    # 2026-10-23：macOS 端详细设计（自带 §11 变更记录 + 头部版本格）。
    ("Docs/Doyah产品详细设计说明书-macOS.md", False),
    # 2026-10-23：macOS 端开发计划书（自带 §11 变更记录 + 头部版本格）。
    ("Docs/Doyah产品开发计划任务清单-macOS端.md", False),
    ("Docs/Doyah产品开发计划书-安卓端.md", False),
    ("Docs/Doyah产品详细设计说明书-Windows.md", False),
    ("Docs/Doyah产品详细设计说明书-Linux.md", False),
    ("Docs/Doyah产品详细设计说明书-Android.md", False),
    ("Docs/Doyah产品详细设计说明书-iOS.md", False),
    ("Docs/Doyah产品详细设计说明书-HarmonyOS.md", False),
    ("Docs/智能体助手-开发规范.md", False),
    ("Docs/测试用例.md", False),
    ("Docs/兼容性矩阵.md", False),
    ("Docs/发布方案.md", False),
    # ↓ 第 88 轮（L-88）补：这四份此前**不在清单里**，撞号与头部漂移因此无人判。
    ("Docs/发布计划.md", False),
    ("Docs/GBase-技术验证.md", False),
    ("Docs/design/外观方案-v1.md", False),
    ("Docs/design/复盘工具-宿主侧装配需求-20260929.md", False),
    ("Docs/手工验收运行手册.md", False),
    # 2026-10-10 修（T-20261010-030）：仓根入口件纳入受检清单（此前不在清单 ⇒ 三组撞号全绿）
    ("AGENT-SPEC.md", False),
    # 2026-10-14 · 派单 `T-20261014-025`：派生视图《任务清单 · 按平台》入库（有「变更记录」节 +
    # 头部版本格 ⇒ 撞号与头部漂移都该有人判；判据 D「受检清单自洽」要求它必须在清单里）
    ("Docs/任务清单-按平台.md", False),
    # 2026-10-20：两书的变更历史外置成独立文件（人类主人令）—— 撞号与头部漂移也要有人判
    ("Docs/Doyah产品能力规划说明书-变更记录.md", False),
    ("Docs/Doyah产品概要设计说明书-变更记录.md", False),
]
DEV_RECORD_GLOB = "Docs/开发记录-*.md"
QUEUE_FILE = "Docs/design/开发循环-任务队列.md"

# 判据 D「受检清单自洽」（第 88 轮，L-88）：有「变更记录」节的文档不许溜出受检清单。
# 2026-10-10 修（T-20261010-030）：扫描面**与姊妹判据 `check-doc-tables` 同源** = 仓根 `*.md` + `Docs/**/*.md`
# —— 此前只盖 `Docs/**` ⇒ 仓根入口件 `AGENT-SPEC.md` 的三组撞号在判据外**全绿**（假绿）。
COVERAGE_ROOT_GLOBS = ["*.md", "Docs/**/*.md"]
COVERAGE_EXEMPT = {
    "Docs/archive/": "历史归档快照（旧版三书），按「历史引用不回改」不纳入版本纪律",
    "Docs/frozen/": "v1.0 冻结基线快照（四书逐字复制，人类主人 2026-10-25 拍板「只有唯一的四书一单」）—— 它是快照不是活书，版本纪律由活书承担；与活书是否对齐由 `Scripts/check-frozen-sync.py` 单独判。",
    "Docs/Doyah产品需求规格说明书-变更记录.md": "它就是《需求规格说明书》的版本历史（2026-10-20 从正文 §10.5 整体移出，人类主人：变更记录不写在需求规格说明书里）——本文件的每一行都是版本行，不该再被要求「头部版本格 + 唯一版本号」。",
    "Docs/Doyah产品概要设计说明书-变更记录.md": "它就是《概要设计》的版本历史（v3 起）（2026-10-20 与正文同批建）——本文件每一行都是版本行，不该再被要求「头部版本格 + 唯一版本号」；正文里已有「当前 v3.0.0」格。",
}

# 行首**允许 ≤3 空格缩进**（㈠）：Markdown 里表格嵌在列表项 / 引用里是**合法写法**（缩进一格即成为
# 该项的一部分），而旧码三个锚都写死行首紧贴 ⇒ **缩进一格整档失明**、撞号全绿（成对实测 P1a rc=0 /
# P1b rc=1）。`RE_INDENT` 是判定物的形状，不是给人看的排版。
RE_INDENT = r"[ \t]{0,3}"
TABLE_ROW = re.compile(RE_INDENT + r"\|\s*\*{0,2}(v\d+\.\d+)\*{0,2}\s*\|")
QUOTE_ROW = re.compile(RE_INDENT + r">\s*\*\*(v\d+\.\d+)")
HEAD_TABLE = re.compile(RE_INDENT + r"\|\s*(?:当前版本|版本)\s*\|(.+?)\|\s*$")
HEAD_QUOTE = re.compile(RE_INDENT + r">\s*\*\*版本\*\*\s*(v\d+\.\d+)")
# 「节标题之后的头部形状」专用（㈢）：**必须带版本号**才认 —— 真仓 `Docs/发布计划.md:259` 有一张
# 别的表（`| 版本 | 交付日 | 小河马侧（Windows）交付 |`），它的表头行**不含版本号**，不该被当头部格。
HEAD_LATE = re.compile(RE_INDENT + r"\|\s*(?:当前版本|版本)\s*\|([^|]*v\d+\.\d+[^|]*)\|\s*$")
ID_DEF = re.compile(RE_INDENT + r"\|\s*\*{0,2}([LNR]-\d+)\*{0,2}[^|]*\|")
BASELINE_HINTS = ("基线", "首版")
# 头部版本格的**显式窗口**（㈢）：旧码 `HEAD_SCAN_LINES = 25` 把窗口外的头部格**静默当成「没有头部
# 格」**（既不报「不可判」也不判红 —— 成对实测 P3a 落在第 33 行 ⇒ rc=0）。现读法 = 扫到「变更记录」
# 节标题为止（**不限行数**）；节标题**之后**出现头部形状 ⇒ 报「不可判」并判红（见 `stray_head_cell()`）。
SECTION_HINT = "变更记录"
HEAD_HEADER_WORDS = ("日期", "变更", "变更摘要", "内容", "作者", "说明", "备注", "状态", "摘要", "影响", "条目")



def version_key(token: str) -> tuple[int, int]:
    major, minor = token[1:].split(".")
    return (int(major), int(minor))


def mask_non_content(lines: list[str]) -> list[str]:
    """把**不是文档内容**的行等长抹白（围栏代码块内 / `<!-- -->` 注释内），行号不动（㈤）。

    为什么：判定物是「变更行 / 定义行 / 头部格」，而**围栏里的示例**（把 `| **v1.4** | …` 抄一行进
    ```` ```markdown ```` 块）与 **HTML 注释**里的同形行**不是**变更行 —— 旧码照匹配 ⇒ 假阳（成对实测
    P5a rc=1，报红话术与真撞号**逐字相同**，只差行号 ⇒ 分不出「示例」与「真撞号」）。抹白是**单调**的
    （只会把假阳变绿，不造新命中），且等长替换 ⇒ 行号与列位置都不动。
    """
    masked: list[str] = []
    fence: str | None = None
    comment = False
    for line in lines:
        if comment:
            masked.append(" " * len(line))
            comment = "-->" not in line
            continue
        stripped = line.strip()
        if fence is None and stripped.startswith("<!--"):
            masked.append(" " * len(line))
            comment = "-->" not in stripped
            continue
        marker = stripped[:3] if stripped[:3] in ("```", "~~~") else None
        if marker:
            if fence is None:
                fence = marker
            elif stripped.startswith(fence):
                fence = None
            masked.append(" " * len(line))
            continue
        masked.append(" " * len(line) if fence else line)
    return masked


def read_lines(path: pathlib.Path) -> tuple[list[str], str | None]:
    """读文档并**兜底**（㈥）：非 UTF-8 / 目录占位等一律逐条报原因。

    旧码 `path.read_text()`（`:136`）无兜底 ⇒ 成对实测 P6a 吐 `UnicodeDecodeError` **栈**、一条
    `❌ 文件:行号` 诊断都没有（与它自称「逐条打印」相反）—— **一处坏文件吃掉全部已收集诊断**。
    """
    try:
        return path.read_text(encoding="utf-8").splitlines(), None
    except UnicodeDecodeError as error:
        return [], f"字节不是 UTF-8（首个坏字节在第 {error.start} 字节：{error.reason}）"
    except OSError as error:
        return [], f"读不出来（{type(error).__name__}: {error.strerror or error}）"


def section_start(lines: list[str]) -> int:
    """「变更记录」节标题所在行号（1 起）；没有该节 ⇒ 文末 + 1（= 窗口到文末）。"""
    for index, line in enumerate(lines, 1):
        if line.lstrip().startswith("#") and SECTION_HINT in line:
            return index
    return len(lines) + 1


def _is_header_row(cell: str) -> bool:
    """表头行（`| 版本 | 日期 | 变更摘要 |`）≠ 头部版本格：**格内一个版本号都没有**且每一段都是
    表头词。真仓实测四份文档的变更记录表头行都是这个形状（概要设计 / 外观方案 / 复盘工具 / AGENT-SPEC）
    —— 它们落在「变更记录」节**标题之后**，旧码靠 25 行窗口把这类行挡在门外，窗口一放开就必须显式判掉。"""
    if re.search(r"v\d+\.\d+", cell):
        return False
    parts = [part.strip().strip("`*") for part in cell.split("|") if part.strip()]
    return bool(parts) and all(part in HEAD_HEADER_WORDS for part in parts)


def _head_match(line: str) -> str | None:
    """认出头部版本格；**表头行**（`| 版本 | 日期 | 变更 | 作者 |`）不算头部格。

    旧码靠 25 行窗口把表头行挡在门外 —— **两缺陷互相掩盖**（㈦ 如实登记的「未发生」的假红）：
    窗口一放开就会触发，所以窗口放开的同时必须把表头行判掉。
    """
    match = HEAD_TABLE.match(line)
    if match:
        cell = match.group(1).strip()
        return None if _is_header_row(cell) else cell
    match = HEAD_QUOTE.match(line)
    return match.group(1) if match else None


def head_cell(lines: list[str]) -> tuple[int, str] | None:
    """第一处头部版本格（在「变更记录」节标题**之前**，不限 25 行）。"""
    for index, line in enumerate(lines[:section_start(lines) - 1], 1):
        cell = _head_match(line)
        if cell is not None:
            return index, cell
    return None


def stray_head_cell(lines: list[str]) -> tuple[int, str] | None:
    """头部形状落在「变更记录」节标题**之后**（窗口外）⇒ 判「不可判」并判红（㈢）。

    **边界（如实登记）**：只认**带版本号**的头部形状（`HEAD_LATE`）—— 节标题之后那些别的表格
    （如 `Docs/发布计划.md` 的「版本 / 交付日 / 小河马侧交付」路线表）**不算**，否则就成了假红。
    """
    limit = section_start(lines) - 1
    for index, line in enumerate(lines[limit:], limit + 1):
        match = HEAD_LATE.match(line)
        if match:
            cell = match.group(1).strip()
            if not _is_header_row(cell):
                return index, cell
    return None


def change_rows(lines: list[str]) -> list[tuple[int, str]]:
    rows: list[tuple[int, str]] = []
    for index, line in enumerate(lines, 1):
        match = TABLE_ROW.match(line) or QUOTE_ROW.match(line)
        if match:
            rows.append((index, match.group(1)))
    return rows



def check_doc(relative: str, root: pathlib.Path) -> tuple[list[str], str]:
    """返回 (问题列表, 摘要)。"""
    path = root / relative
    lines, error = read_lines(path)
    problems: list[str] = []
    if error is not None:
        return [f"{relative} 不可读：{error} ⇒ **不可判**（不是「已通过」）"], "不可读"
    lines = mask_non_content(lines)
    rows = change_rows(lines)

    seen: dict[str, list[int]] = {}
    for index, token in rows:
        seen.setdefault(token, []).append(index)
    for token, indexes in sorted(seen.items(), key=lambda item: version_key(item[0])):
        if len(indexes) > 1:
            places = ", ".join(f":{i}" for i in indexes)
            problems.append(f"{relative}{places} 版本号 {token} 出现 {len(indexes)} 次（变更记录里必须唯一）")

    head = head_cell(lines)
    has_section = any(line.lstrip().startswith("#") and SECTION_HINT in line for line in lines)
    stray = stray_head_cell(lines)
    if stray is not None:
        problems.append(
            f"{relative}:{stray[0]} 头部版本形状落在「{SECTION_HINT}」节标题**之后**（窗口外）"
            f" ⇒ **不可判**（把它挪到节标题之前，或删掉这行）"
        )
    if not rows:
        # 2026-10-20：正文只剩「本节已外置」的指针时不算空 —— 历史行在那份 `-变更记录.md` 里，
        # 且它已登记进 VERSION_DOCS 单独受检（撞号、头部漂移都有人判）。
        external = any("-变更记录.md" in line for line in lines)
        if head and has_section and not external:
            problems.append(f"{relative}:{head[0]} 有头部版本格 {head[1]}、也有变更记录节，但一节变更行都没有")
        return problems, "无变更记录（跳过）"
    maximum = max((token for _, token in rows), key=version_key)

    if head is None:
        return problems, f"变更 {len(rows)} 行 / 最高 {maximum} / 无头部版本格"

    index, cell = head
    tokens = re.findall(r"v\d+\.\d+", cell)
    if not tokens:
        problems.append(f"{relative}:{index} 头部版本格里读不出版本号（原文：{cell}）")
        return problems, f"变更 {len(rows)} 行 / 最高 {maximum} / 头部不可判"

    stated = tokens[0]
    if stated not in seen:
        problems.append(f"{relative}:{index} 头部版本 {stated} 在变更记录里找不到（凭空写的号）")
    elif stated != maximum:
        annotated = any(hint in cell for hint in BASELINE_HINTS)
        if not (annotated and maximum in cell):
            problems.append(
                f"{relative}:{index} 头部版本 {stated} ≠ 变更记录最高 {maximum}"
                f"，且该格既没有「基线 / 首版」标注、标注里也没写出 {maximum}"
                f"（原文：{cell}）"
            )
    return problems, f"变更 {len(rows)} 行 / 最高 {maximum} / 头部 {stated}"


def check_queue(relative: str, root: pathlib.Path) -> tuple[list[str], str]:
    path = root / relative
    lines, error = read_lines(path)
    if error is not None:
        return [f"{relative} 不可读：{error} ⇒ **不可判**（不是「已通过」）"], "不可读"
    lines = mask_non_content(lines)
    problems: list[str] = []
    definitions: dict[str, list[int]] = {}
    for index, line in enumerate(lines, 1):
        match = ID_DEF.match(line)
        if match:
            definitions.setdefault(match.group(1), []).append(index)
    for token, indexes in sorted(definitions.items()):
        if len(indexes) > 1:
            places = ", ".join(f":{i}" for i in indexes)
            problems.append(
                f"{relative}{places} 条目号 {token} 被 {len(indexes)} 条定义行占用"
                f"（取号 = `python3 Scripts/next-doc-version.py` 的同族纪律：队列取号用 max+1）"
            )
    return problems, f"定义行 {len(definitions)} 个条目号"


def identity_text(value) -> str:
    """把相对路径铸成**跨平台的稳定标识**（一律正斜杠）。

    为什么不用裸 `str(path)`：Windows 上 `str(WindowsPath)` 给 `Docs\\README.md`，而清单 / glob /
    台账键 / `verify-all.sh` 正文都写正斜杠 ⇒ 集合匹配**恒 False**，凡命中扫描面的文档**全部判红**，
    而 macOS 上 `os.sep` 就是 `/` ⇒ **只在那一台机器上红**（提案 0005，对侧第 81 轮实测）。
    本函数既吃 `Path` 也吃 `str` —— 自检用 `PureWindowsPath` 复现「那台机器会得到的标识」，
    于是红 / 绿在 macOS 上就能成对。形状禁令见 `Scripts/check-script-portability.py`。
    """
    return str(value).replace("\\", "/")


def coverage_problems(root: pathlib.Path) -> tuple[list[str], str]:
    """判据 D：有「变更记录」节的文档必须在受检清单里（VERSION_DOCS ∪ 开发记录通配）。

    为什么要有它：清单是手抄的 ⇒ 新文档建出来不会自动进来，它的撞号与头部漂移**全绿**
    （第 88 轮实测：`Docs/发布计划.md` 两行 `v1.9` 重复、两行 `v1.8` 同号、头部 `v1.8` ≠ 最高）。
    `Docs/archive/` 的事由写在 `COVERAGE_EXEMPT` 里 —— 豁免也要**给出理由**，不静默跳过；
    **豁免还要有命中计数**（㈣）：目录在盘而命中 0 份 ⇒ 判红「陈旧豁免」（旧码只写理由、无计数，
    留着也没人知道它在不在用）；目录不在盘 ⇒ 只出声不判红（`Docs/archive/` 的快照件不入库 ⇒ 判红
    会变成跨侧假红）。

    **边界（如实跟版 · 2026-10-14 合册 `T-20261013-027` / 原单 `T-20261010-075` ㈦）**：扫描面 =
    `COVERAGE_ROOT_GLOBS`（仓根 `*.md` + `Docs/**/*.md`）—— 仓根入口件 `AGENT-SPEC.md` 已在
    2026-10-10（`T-20261010-030`）纳入 `VERSION_DOCS`；它那张表头行（`| 版本 | 日期 | 变更 | 作者 |`）
    不再需要靠 25 行窗口挡着 —— `_head_match()` 直接判掉表头行（**两缺陷互相掩盖**的登记到此为止）。
    """
    listed = {relative for relative, _ in VERSION_DOCS}
    problems: list[str] = []
    hits = {prefix: 0 for prefix in COVERAGE_EXEMPT}
    for path in sorted({p for _g in COVERAGE_ROOT_GLOBS for p in root.glob(_g)}):
        relative = identity_text(path.relative_to(root))
        exempt = next((prefix for prefix in COVERAGE_EXEMPT if relative.startswith(prefix)), None)
        if exempt is not None:
            hits[exempt] += 1  # ㈣ 豁免**有钉**：命中 0 ⇒ 陈旧豁免（判红），不再静默留着
            continue
        if relative in listed or pathlib.PurePath(relative).match(DEV_RECORD_GLOB):
            continue
        lines, error = read_lines(path)
        if error is not None:
            problems.append(f"{relative} 不可读：{error} ⇒ **不可判**（不是「已通过」）")
            continue
        if any(line.lstrip().startswith("#") and SECTION_HINT in line for line in lines):
            problems.append(
                f"{relative} 有「变更记录」节却不在受检清单里（`VERSION_DOCS` / `{DEV_RECORD_GLOB}`）"
                f" ⇒ 它的撞号与头部漂移一直是全绿（加进清单，或在 `COVERAGE_EXEMPT` 里写明不纳入的理由）"
            )
    for prefix, count in hits.items():
        # ㈣ 豁免**有钉**：目录在盘却一份都没命中 ⇒ **陈旧豁免**判红。**目录不在盘**时只出声、**不判红**：
        # `Docs/archive/` 的快照件**不入库**（`git ls-files Docs/archive` = 0）⇒ 任何新克隆 / 对侧都没有
        # 这个目录，判红会变成**跨侧假红**（与「真仓读数逐字节相同」的口径相抵）。
        if count == 0 and (root / prefix).is_dir():
            problems.append(
                f"豁免 `{prefix}` 命中 0 份（目录在盘、面里一份都没有）⇒ **陈旧豁免**：要么删掉这条豁免，"
                f"要么它护着的东西真的不在了 —— 旧码豁免只写理由、**无命中计数、无失效判红**"
            )
    readings = []
    for prefix, reason in COVERAGE_EXEMPT.items():
        count = hits[prefix]
        if count:
            note = f"命中 {count}"
        elif (root / prefix).is_dir():
            note = "命中 0，目录在盘但空 ⇒ **陈旧豁免**判红"
        else:
            note = "命中 0，目录不在盘 ⇒ **不可判**（快照件不入库）"
        readings.append(f"`{prefix}`（{reason}）{note}")
    return problems, "、".join(readings)


def collect_targets(root: pathlib.Path) -> list[tuple[str, bool]]:
    targets = list(VERSION_DOCS)
    for path in sorted(root.glob(DEV_RECORD_GLOB)):
        targets.append((identity_text(path.relative_to(root)), False))
    return targets


def queue_clause(checked: bool) -> str:
    """㈡：收尾行的「队列条目号唯一」只在**真查过**队列时才敢写。

    旧码在队列文件不在盘（= 任何新克隆 / 对侧 Windows 端的默认条件）时照写「队列条目号唯一」——
    实读**一个定义行都没有**，而「读过且唯一」与「根本没读」两种情形下的文案**逐字相同**（假绿）。
    """
    return "队列条目号唯一" if checked else "队列条目号**未查 ⇒ 不可判**"


def run(root: pathlib.Path, quiet: bool) -> int:
    problems: list[str] = []
    for relative, required in collect_targets(root):
        path = root / relative
        if not path.exists():
            if required:
                problems.append(f"{relative} 不在盘上（该文档必须存在）")
            elif not quiet:
                print(f"⚠️  {relative} 不在盘上，跳过（**不是「已通过」**）")
            continue
        found, summary = check_doc(relative, root)
        problems.extend(found)
        if not quiet:
            mark = "❌" if found else "✅"
            print(f"{mark} {relative} —— {summary}")

    queue = root / QUEUE_FILE
    queue_checked = False
    if queue.exists():
        found, summary = check_queue(QUEUE_FILE, root)
        problems.extend(found)
        queue_checked = summary != "不可读"
        if not quiet:
            print(f"{'❌' if found else '✅'} {QUEUE_FILE} —— {summary}")
    elif not quiet:
        print(f"⚠️  {QUEUE_FILE} 不在盘上 ⇒ 条目号查重**未查**（**不可判**，不是「已通过」）")

    uncovered, exempt = coverage_problems(root)
    problems.extend(uncovered)
    if not quiet:
        mark = "❌" if uncovered else "✅"
        _globdesc = " + ".join(COVERAGE_ROOT_GLOBS)
        print(f"{mark} 受检清单自洽 —— `{_globdesc}` 里带「变更记录」节的文档全部在清单内"
              f"（豁免：{exempt}）")

    if problems:
        print("")
        for problem in problems:
            print(f"❌ {problem}")
        return 1
    if not quiet:
        print(f"\n✅ 变更记录版本号唯一、头部版本可判、{queue_clause(queue_checked)}")
    return 0


# --------------------------------------------------------------------------- 负例

GOOD_DOC = """# 样例文档

| 项目 | 内容 |
|---|---|
| 版本 | **v1.2** |

## 变更记录 [开放]

| 版本 | 日期 | 内容 | 作者 |
|---|---|---|---|
| **v1.2** | 2026-01-02 | 第二条 | 甲 |
| **v1.1** | 2026-01-01 | 第一条 | 甲 |
"""

EXTERNAL_DOC = """# 外置台账

| 项目 | 内容 |
|---|---|
| 版本 | **v1.2** |

## 变更记录 [开放]

> **本节已外置** —— 历史在 `Docs/Doyah产品能力规划说明书-变更记录.md`。
"""

QUOTE_DOC = """# 引用式台账

> **版本** v1.2 ｜（本格与最新变更行同步）

> **v1.2（2026-01-02）**：第二条。
> **v1.1（2026-01-01）**：第一条。
"""

GOOD_QUEUE = """# 队列

| 编号 | 任务 | 状态 |
|---|---|---|
| **L-02** | 第二条 | todo |
| **L-01** | 第一条 | done |
"""

LATE_HEAD_DOC = ("# 样例文档\n\n" + "填充行（把头部格推到第 26 行以外）\n" * 30 + "\n"
                 "| 版本 | {head} |\n\n## 变更记录 [开放]\n\n"
                 "| 版本 | 日期 | 内容 | 作者 |\n|---|---|---|---|\n"
                 "| **v1.2** | 2026-01-02 | 第二条 | 甲 |\n"
                 "| **v1.1** | 2026-01-01 | 第一条 | 甲 |\n")

# 读取兜底与收尾文案（㈡ / ㈥）：kind = bytes（非 UTF-8）/ dir（目录占位）/ noqueue / queue。
EXTRA_CASES = [
    ("非 UTF-8 字节 ⇒ 逐条报原因、不吐栈（㈥）", "bytes", 1),
    ("目录占位 ⇒ 逐条报原因、不吐栈（㈥）", "dir", 1),
    ("队列不在盘 ⇒ 收尾不得自称「队列条目号唯一」（㈡ 假绿）", "noqueue", 0),
    ("队列在盘且唯一 ⇒ 收尾照写「队列条目号唯一」（㈡ 对手臂）", "queue", 0),
]

CASES = [
    ("好文档（头部 = 最高，唯一）", GOOD_DOC, None, [], 0),
    ("引用式好台账", QUOTE_DOC, None, [], 0),
    ("变更记录外置成独立文件（正文只剩指针）⇒ 不算空", EXTERNAL_DOC, None, [], 0),
    ("重复版本号", GOOD_DOC.replace("| **v1.1** | 2026-01-01", "| **v1.2** | 2026-01-01"), None, ["v1.2"], 1),
    ("头部号在记录里找不到",
     GOOD_DOC.replace("| 版本 | **v1.2** |", "| 版本 | **v9.9** |"), None, ["找不到"], 1),
    ("头部号 ≠ 最高且无标注",
     GOOD_DOC.replace("| 版本 | **v1.2** |", "| 版本 | **v1.1** |"), None, ["≠ 变更记录最高"], 1),
    ("头部号 ≠ 最高但有基线标注且写出当前号",
     GOOD_DOC.replace("| 版本 | **v1.2** |", "| 版本 | **v1.1**（正式版基线；当前 v1.2） |"), None, [], 0),
    ("头部号 ≠ 最高、标注里没写当前号",
     GOOD_DOC.replace("| 版本 | **v1.2** |", "| 版本 | **v1.1**（正式版基线） |"), None, ["没写出"], 1),
    ("有头部格却找不到变更记录行",
     GOOD_DOC.replace("| **v1.2** | 2026-01-02 | 第二条 | 甲 |\n| **v1.1** | 2026-01-01 | 第一条 | 甲 |\n", ""),
     None, ["一节变更行都没有"], 1),
    ("队列条目号重复",
     GOOD_QUEUE,
     "# 队列\n\n| 编号 | 任务 | 状态 |\n|---|---|---|\n| **L-02** | 第二条 | todo |\n| **L-02** | 与上一条撞号 | todo |\n",
     ["L-02"], 1),
    ("队列引用不算定义（同一号在正文里出现多次）",
     GOOD_QUEUE + "\n> 参见 `L-01` 与 **L-01** 的处理方式，另见 L-01。\n", None, [], 0),
    ("队列定义行带括注也算定义行（同号 ⇒ 判红）—— 第 70 轮 L-77 的回归例",
     GOOD_QUEUE,
     "# 队列\n\n| 编号 | 任务 | 状态 |\n|---|---|---|\n"
     "| **L-02**（宿主侧仅此一条） | 第二条 | todo |\n"
     "| **L-02**（另一条） | 与上一条撞号 | todo |\n",
     ["L-02"], 1),
    ("缩进一格的表格行也是变更行（㈠ 假绿）",
     GOOD_DOC.replace("| **v1.1** | 2026-01-01", " | **v1.2** | 2026-01-01"), None, ["出现 2 次"], 1),
    ("围栏代码块里的同号示例不算撞号（㈤ 假阳）",
     GOOD_DOC + "\n```markdown\n| **v1.2** | 2026-01-02 | 示例 | 甲 |\n```\n", None, [], 0),
    ("头部格推到第 26 行以外且号写错 ⇒ 不许静默当「没有头部格」（㈢ 红臂）",
     LATE_HEAD_DOC.format(head="**v9.9**"), None, ["凭空写的号"], 1),
    ("头部格推到第 26 行以外且号正确 ⇒ 不判红（㈢ 绿臂）",
     LATE_HEAD_DOC.format(head="**v1.2**"), None, [], 0),
    ("头部形状落在「变更记录」节之后 ⇒ 报「不可判」（㈢ 窗口闭合）",
     GOOD_DOC + "\n| 版本 | **v1.2** |\n", None, ["窗口外"], 1),
]

# 判据 D 的负例（第 88 轮，L-88）：夹具只有**一个文件**，所以「在清单里」的那一例用清单里
# 已有的名字（`Docs/测试用例.md`）—— 判据看的是**相对路径**，不看内容。
# ㈣（2026-10-14）起**每条夹具都带一份归档件**：豁免要「有命中」，否则陈旧豁免那一档会先判红，
# 这一组用例就测不到原来的判定物了（陈旧豁免单独一例）。
COVERAGE_CASES = [
    ("有变更记录节却不在受检清单 ⇒ 判红（豁免侧另有命中，见夹具）",
     {"Docs/未登记.md": "# 未登记\n\n## 变更记录\n\n| 版本 | 日期 | 内容 |\n|---|---|---|\n| v1.0 | 2026-01-01 | 首版 |\n",
      "Docs/archive/旧快照.md": "# 旧快照\n\n早年的存档件。\n"},
     [], 1),
    ("没有变更记录节 ⇒ 不纳入（不判红）",
     {"Docs/随笔.md": "# 随笔\n\n随手记，没有版本纪律。\n",
      "Docs/archive/旧快照.md": "# 旧快照\n\n早年的存档件。\n"},
     [], 0),
    ("有变更记录节且名字在受检清单里 ⇒ 不判红",
     {"Docs/测试用例.md": "# 测试用例\n\n## 变更记录\n\n| 版本 | 日期 | 内容 |\n|---|---|---|\n| v1.0 | 2026-01-01 | 首版 |\n",
      "Docs/archive/旧快照.md": "# 旧快照\n\n早年的存档件。\n"},
     [], 0),
    ("归档目录豁免（不判红）",
     {"Docs/archive/旧需求书.md": "# 旧需求书\n\n## 变更记录\n\n| 版本 | 日期 |\n|---|---|\n| v1.0 | 2026-01-01 |\n"},
     [], 0),
    ("豁免目录在盘但命中 0 份 ⇒ 陈旧豁免（㈣ 判红）",
     {"Docs/随笔.md": "# 随笔\n\n随手记。\n"},
     ["Docs/archive"], 1),
    ("豁免目录不在盘 ⇒ 出声但不判红（快照件不入库 · 边界登记）",
     {"Docs/随笔.md": "# 随笔\n\n随手记。\n"},
     [], 0),
]



def self_test() -> int:
    real_root = pathlib.Path(__file__).resolve().parent.parent
    before = {}
    for relative, _ in collect_targets(real_root):
        path = real_root / relative
        if path.exists():
            before[relative] = hashlib.sha256(path.read_bytes()).hexdigest()

    failures = 0
    for name, doc, queue, expect, expected_code in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Docs").mkdir()
            (root / "Docs" / "样例.md").write_text(doc, encoding="utf-8")
            if queue:
                (root / "Docs" / "design").mkdir()
                (root / "Docs" / "design" / "开发循环-任务队列.md").write_text(queue, encoding="utf-8")
            if doc.lstrip().startswith(">"):
                problems, _ = check_doc("Docs/样例.md", root)
            else:
                problems, _ = check_doc("Docs/样例.md", root)
            text = "\n".join(problems)
            qproblems: list[str] = []
            if queue:
                qproblems, _ = check_queue("Docs/design/开发循环-任务队列.md", root)
                qtext = "\n".join(qproblems)
                # 队列用例：文档半边必须干净，断言只打在队列半边（判据不同，不能混着判）
                hit = (not problems) and all(fragment in qtext for fragment in expect)
            else:
                hit = all(fragment in text for fragment in expect) if expect else not problems
            code = 1 if (problems or (queue and qproblems)) else 0
            ok = hit and code == expected_code
            print(f"{'✅' if ok else '❌'} 负例 {name}（期望退出码 {expected_code}，实得 {code}"
                  f"{'' if hit else ' / 报出的原因与期望不符'}）")
            if not ok:
                failures += 1
                print(f"     报出：{text or '（无）'}")
                if queue:
                    print(f"     队列：{qtext or '（无）'}")

    total = len(CASES) + len(COVERAGE_CASES) + len(EXTRA_CASES)

    for name, files, dirs, expected_code in COVERAGE_CASES:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for extra in dirs:
                (root / extra).mkdir(parents=True, exist_ok=True)
            for relative, content in files.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            found, _ = coverage_problems(root)
            code = 1 if found else 0
            ok = code == expected_code
            print(f"{'✅' if ok else '❌'} 负例 {name}（期望退出码 {expected_code}，实得 {code}"
                  f"{'' if ok else ' / 报出的原因与期望不符'}）")
            if not ok:
                failures += 1
                print(f"     报出：{chr(10).join(found) or '（无）'}")

    # 跨平台（提案 0005，第 91 轮）：判据 D 的立足点就是「磁盘上的相对路径 == 手抄清单里的写法」。
    # Windows 上 `str(WindowsPath)` 给反斜杠（清单写正斜杠）⇒ 清单匹配**恒 False**、**只在那台机器上红**；
    # 本处在 macOS 上用 `PureWindowsPath` 复现「那台机器会得到的标识」，红 / 绿成对。
    # 读取兜底与收尾文案（㈡ / ㈥）：四例成对 —— 红臂（非 UTF-8 / 目录占位）与绿臂（队列在盘）
    # + 文案臂（队列不在盘时**不得**自称「队列条目号唯一」）。
    for name, kind, expected_code in EXTRA_CASES:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Docs" / "archive").mkdir(parents=True)
            (root / "Docs" / "archive" / "旧快照.md").write_text("# 旧快照\n", encoding="utf-8")
            # 三书是 `required=True` ⇒ run() 会判「不在盘上」，夹具必须把它们铺上（否则测到的是别的红）
            # 2026-10-20：清单里的 `True` 档是活文档须在盘（三书 + 开发计划书）—— 别手抄名字，
            # 直接遍历 `VERSION_DOCS`，否则清单加减一份，夹具就会测到「另一条红」（假红）。
            for relative, required in VERSION_DOCS:
                if required:
                    target = root / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text("# 占位\n", encoding="utf-8")
            probe = root / "Docs" / "测试用例.md"
            if kind == "bytes":
                probe.write_bytes(b"# \xd6\xd0\xce\xc4\n\n## \xe5\x8f\x98\xe6\x9b\xb4\xe8\xae\xb0\xe5\xbd\x95\n")
                problems, _ = check_doc("Docs/测试用例.md", root)
                code = 1 if problems else 0
                ok = code == expected_code and any("不可读" in item for item in problems)
                detail = "\n".join(problems)
            elif kind == "dir":
                probe.mkdir()
                problems, _ = check_doc("Docs/测试用例.md", root)
                code = 1 if problems else 0
                ok = code == expected_code and any("不可读" in item for item in problems)
                detail = "\n".join(problems)
            else:
                probe.write_text(GOOD_DOC, encoding="utf-8")
                if kind == "queue":
                    (root / "Docs" / "design").mkdir()
                    (root / "Docs" / "design" / "开发循环-任务队列.md").write_text(
                        GOOD_QUEUE, encoding="utf-8")
                buffer = io.StringIO()
                with contextlib.redirect_stdout(buffer):
                    code = run(root, False)
                out = buffer.getvalue()
                ok = ("队列条目号唯一" in out) == (kind == "queue") and code == expected_code
                detail = out.strip().splitlines()[-1] if out.strip() else "（无输出）"
            label = "✅" if ok else "❌"
            print(f"{label} 负例 {name}（期望退出码 {expected_code}，实得 {code}"
                  f"{'' if ok else ' / 报出的原因与期望不符'}）")
            if not ok:
                failures += 1
                print(f"     报出：{detail or '（无）'}")
    total += 1
    windows_style = str(pathlib.PureWindowsPath("Docs/README.md"))
    cross_ok = (
        windows_style != "Docs/README.md"  # 先确证「不归一」会得到什么
        and identity_text(windows_style) == "Docs/README.md"
        and identity_text(pathlib.PureWindowsPath("Docs/README.md")) == "Docs/README.md"
        and identity_text(pathlib.Path("Docs/README.md")) == "Docs/README.md"
    )
    print(f"{'✅' if cross_ok else '❌'} 负例 跨平台标识（Windows 形态的相对路径必须落回清单写法）")
    if not cross_ok:
        failures += 1
        print(f"     str(PureWindowsPath) = {windows_style!r}；identity_text 给 {identity_text(windows_style)!r}")

    after = {}
    for relative, _ in collect_targets(real_root):
        path = real_root / relative
        if path.exists():
            after[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    if before != after:
        print("❌ 负例跑完真仓库的文档被改动了（不合格）")
        failures += 1
    else:
        print(f"✅ 负例全程只在临时目录里写坏，真仓库 {len(before)} 份文档逐字节未变")

    print(f"\n{'✅' if not failures else '❌'} 负例 {total - failures}/{total} 达到预期")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="变更记录版本号与条目号查重（L-32）")
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
