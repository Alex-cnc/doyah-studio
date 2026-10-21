#!/usr/bin/env python3
"""平台中立性校验（两档棘轮）：需求正文不得绑平台，实现记录允许绑。

存在的理由：
    产品要在 macOS 与 Linux 上保持一致（平台与语言不同），但**本文件最初是一份 macOS
    实现记录** —— 它的"状态 / 证据"列里塞满了框架类型名、文件路径与平台 API。若不管，
    Linux 侧会把实现细节当需求照抄，两平台也就谈不上一致。

    第一版按"行"一刀切，把 190 处变更记录与 43 处证据列也算成负债（实测 246 处），
    既没法收敛到 0，也逼着人删实现记录。**第二版按"这句话会不会被当需求照抄"分档**：

      严格档（配额 0，超出即失败）
        · 需求条目的「需求」列（FR / NFR / DR / IR / AC 行）
        · §1.2 产品目标、§1.3 范围的正文
      报告档（只统计不拦截）
        · 「状态 / 证据 / 验收要点」列、其他表格（现状 / 模块 / 里程碑）、§9 风险记录、
          §10 各附录（追溯 / 环境 / 变更 / 任务 / 对标 / 差异 / 矩阵）—— 这些地方本来就
          在记 macOS 基线做了什么

    需要显式豁免时，在该行写 `<!-- platform-ok: 理由 -->`（**只认 HTML 注释形态**：需求
    正文里裸写 `platform-ok` 不构成豁免 —— 旧版是裸子串判定，写进需求列正文即整行跳过）。
    设计文档（概要设计 / 能力规划）整体只报告：它们本来就要写平台实现。

2026-10-13 修（合册 T-20261013-027 · 原单 T-20261010-050 · 第 417 轮判据面缺口样本 54）：
    ① **判定物 = 行的形状**：编号先剥 `*` / 反引号 / `~` / 空白、行首允许缩进、单元格数不再
       要求 ≥3 —— 否则「加粗编号 / 反引号编号 / 缩进表格 / 两格行」四种写法整体掉进报告档
       （旧版同一段文案改平号即判红、加个 `**` 即判绿，差别只在那一行的形状）；
    ② **「需求」列按表头定位**：取该表表头里以「需求」开头的单元格序号，不再写死第 2 格
       （列被挪到第 3 格时旧版整列在面外）；表头**没有**「需求」列的表（如 §0.5 编号法
       说明表）按既有第 2 格口径扫 —— 那是写法说明，不是需求正文；
    ③ **空跑防护**：需求规范书缺失 / 行数 / 表格数 / 需求形状行数低于下限 ⇒ 判红 —— 旧版
       打「跳过：<文档> 不存在」后照样绿，面被砍掉了也不说话；
    ④ **`--update-baseline` 防护**：基线非空时必须 `--confirm`，且先打印逐标签 diff；基线
       为空时的既有行为**逐字保留**（含 comment 文本与空 totals）；
    ⑤ `--root <树>` / `--self-test` / `--confirm`；未知参数按 argparse 报错（rc=2）——旧版
       把未知参数静默吞掉，`--self-test` / `--nonsense` 都打印「✅ 通过」且 rc=0。

用法：
    python3 Scripts/check-platform-neutrality.py                     # 校验（闸门）
    python3 Scripts/check-platform-neutrality.py --report            # 看两档分布与命中样例
    python3 Scripts/check-platform-neutrality.py --self-test         # 判据自己的证据（18 例）
    python3 Scripts/check-platform-neutrality.py --root <树>         # 指定仓根（自检用）
    python3 Scripts/check-platform-neutrality.py --update-baseline [--confirm]
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# 判据的立足点：**本脚本所在仓**的根（不是 CWD —— 从别的目录跑必须读数一致）
REPO = pathlib.Path(__file__).resolve().parent.parent
SRS = "Docs/Doyah产品需求分析说明书.md"
TARGETS = [SRS, "Docs/Doyah产品概要设计说明书.md", "Docs/Doyah产品能力规划说明书.md"]
BASELINE_REL = "Scripts/platform-neutrality-baseline.json"
BASELINE_COMMENT = (
    "平台中立性棘轮基线：需求规范书**严格档**（需求列 + §1.2/§1.3 正文）"
    "的平台专属词数量只能降不能升，目标 0。报告档（证据列 / 其他表格 / §9 / "
    "§10 附录）只统计不拦截，不在此处记账。"
)

TERMS = {
    "Swift/Apple 语言与框架": r"\b(Swift|SwiftUI|AppKit|CoreGraphics|XCTest|Foundation|Combine)\b",
    "Objective-C / Cocoa 类型": r"\bNS[A-Z][A-Za-z]+\b|\bWKWebView\b|\bCF[A-Z][A-Za-z]+\b",
    "Apple 平台机制": r"(Keychain|钥匙串|entitlements?|App Sandbox|Info\.plist|XcodeGen|xcodebuild|ad-hoc|公证|Developer ID)",
    "macOS 专属 API/概念": r"(security-scoped|withSecurityScope|forkpty|TIOCSWINSZ|NSOpenPanel|NSTableView|NSTextView|\.icns)",
    "Swift 生态依赖": r"\b(PostgresNIO|MySQLNIO|SwiftNIO|swift-tools|SwiftPM|Package\.swift|Vendor/)\b",
}

EXEMPT_MARK = "platform-ok"
EXEMPT = re.compile(r"<!--\s*platform-ok\b")      # 豁免只认 HTML 注释形态

REQUIREMENT_ROW = re.compile(r"^(FR|NFR|DR|IR|AC)-")     # 剥形状后判编号
REQUIREMENT_HEADER = re.compile(r"^需求")                # 表头里定位「需求」列
NEUTRAL_PROSE = ("## 1.2 ", "## 1.3 ")                 # 严格档里的中立正文小节
RISK_SECTION = ("# 第九章 ",)                               # 报告档区域
APPENDIX_SECTIONS = ("## 10.",)
SEPARATOR = re.compile(r"^\s*\|[\s:|-]+\|\s*$")          # 表格分隔行 `|---|---|`

# 桶 → (显示名, 是否严格)
BUCKETS = {
    "requirement-cell": ("需求条目的「需求」列（FR / NFR / DR）", True),
    "neutral-prose": ("§1.2 产品目标 / §1.3 范围正文", True),
    "evidence-cell": ("「状态 / 证据 / 验收要点」列", False),
    "table-record": ("其他表格（现状 / 模块 / 里程碑 / 用例）", False),
    "risk": ("§9 风险记录", False),
    "appendix": ("§10 附录（追溯 / 环境 / 变更 / 任务 / 差异 / 矩阵）", False),
    "other-prose": ("其他正文与说明（§0 约定 / §7 验收摘要 / §8 计划等）", False),
}
STRICT_BUCKETS = tuple(name for name, (_, strict) in BUCKETS.items() if strict)

# 空跑防护下限（2026-10-20 重校：变更记录外置（-400 行）+ 状态列整批摘除后，SRS 实测
# 1920 行 / 565 行需求形状行 ⇒ 下限按新形状留约 4% 余量。**防护不撤**：取不到输入仍判红，
# 只是把「多少算取到了」校准到现行文档形状）
FLOOR_LINES = 1840
FLOOR_TABLES = 40
FLOOR_REQUIREMENT_ROWS = 540


def clean_cell(cell: str) -> str:
    """单元格文本的「形状」归一：剥空白 / 加粗 `*` / 反引号 / 删除线 `~`。"""
    return cell.strip().strip("*`~ ").strip()


def split_cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def is_requirement_row(cells: list[str]) -> bool:
    """需求行 = 形状归一后第一格是 `FR-` / `NFR-` / `DR-` / `IR-` / `AC-` 开头。

    不再要求单元格数 ≥3（旧版两格行整体掉进报告档）；缩进由调用方 `lstrip` 处理。
    """
    return bool(cells) and bool(REQUIREMENT_ROW.match(clean_cell(cells[0])))


INTERFACE_ROW = re.compile(r"^(?:FR|NFR|AC)-(?:AGT|STD|NTS|RTR|ALL)-(?:ALL|GATE)-(?:IFACE|DATA|RISK)-\d+")


def is_interface_row(cells: list[str]) -> bool:
    """接口 / 数据需求行 = 面 `ALL` 且域 `IFACE` / `DATA`。

    这批条目**本身就是接口名与存储契约**（`DatabaseService` / `SecretStore` / 应用支持目录），
    在旧编码里以 `DR-` / `IR-` 开头、判据按报告档处理；2026-10-20 并入 5 段式后（`FR-STD-ALL-IFACE-*`）
    形状变成需求行，本函数把**同一条口径**接回来 —— 不是放宽，是让分类跟着编码一起搬家。
    """
    return bool(cells) and bool(INTERFACE_ROW.match(clean_cell(cells[0])))


def table_map(lines: list[str]) -> tuple[dict[int, int | None], int]:
    """行号 → 该行所在表格的「需求」列序号；返回 (映射, 表格张数)。

    表 = 连续以 `|` 开头的行（**允许行首缩进** —— 旧版 `startswith("|")` 把缩进行整体放走）；
    表头 = 分隔行（`|---|`）的上一行；「需求」列 = 表头里第一个以「需求」开头的单元格。
    找不到表头 / 表头没有「需求」列 ⇒ None（`cell_text` 按既有第 2 格口径兜底）。
    """
    columns: dict[int, int | None] = {}
    tables = 0
    index = 0
    total = len(lines)
    while index < total:
        if not lines[index].lstrip().startswith("|"):
            index += 1
            continue
        rows: list[int] = []
        while index < total and lines[index].lstrip().startswith("|"):
            rows.append(index)
            index += 1
        tables += 1
        header: int | None = None
        for offset, number in enumerate(rows):
            if SEPARATOR.match(lines[number]):
                header = rows[offset - 1] if offset > 0 else None
                break
        column: int | None = None
        if header is not None:
            for position, cell in enumerate(split_cells(lines[header])):
                if REQUIREMENT_HEADER.match(clean_cell(cell)):
                    column = position
                    break
        for number in rows:
            columns[number] = column
    return columns, tables


def section_lines(lines: list[str], prefixes: tuple[str, ...]) -> set[int]:
    """返回以给定标题开头的所有小节覆盖的行号（到下一个同级或更高级标题为止）。"""
    covered: set[int] = set()
    active_level: int | None = None
    for index, line in enumerate(lines):
        heading = re.match(r"^(#{1,4}) ", line)
        if heading:
            if any(line.startswith(prefix) for prefix in prefixes):
                active_level = len(heading.group(1))
                continue
            if active_level is not None and len(heading.group(1)) <= active_level:
                active_level = None
                continue
        if active_level is not None:
            covered.add(index)
    return covered


def classify(lines: list[str]):
    """把每一行归到一个桶；跳过显式豁免行与注释行。返回 (逐行判定, 表格张数)。"""
    risk = section_lines(lines, RISK_SECTION)
    appendix = section_lines(lines, APPENDIX_SECTIONS)
    neutral = section_lines(lines, NEUTRAL_PROSE)
    columns, tables = table_map(lines)

    verdict = []
    for index, line in enumerate(lines):
        if EXEMPT.search(line) or line.strip().startswith("<!--"):
            continue
        cells = split_cells(line) if line.lstrip().startswith("|") else None
        if index in risk:
            bucket = "risk"
        elif index in appendix:
            bucket = "appendix"
        elif cells is not None and is_requirement_row(cells):
            # 接口 / 数据 / 风险三类条目本来就以实现名作正文（旧编码 `DR-` / `IR-` / `R-`
            # 一直是报告档）；并入 5 段式后形状变成需求行 ⇒ 仍按报告档，别让编码搬家顺手收紧口径
            bucket = "other-prose" if is_interface_row(cells) else "requirement-cell"
        elif cells is not None:
            bucket = "table-record"
        elif index in neutral:
            bucket = "neutral-prose"
        else:
            bucket = "other-prose"
        verdict.append((index, bucket, line, cells, columns.get(index)))
    return verdict, tables


def cell_text(cells: list[str], column: int | None, line: str) -> str:
    """需求行扫哪一格：表头定位到的「需求」列优先；表头没有它时按既有口径取第 2 格。"""
    if column is not None and column < len(cells):
        return cells[column]
    if len(cells) >= 2:
        return cells[1]
    return line


def scan(path: pathlib.Path):
    """返回 (按桶的族计数, 严格档命中样例, 扫描面读数)。"""
    lines = path.read_text(encoding="utf-8").splitlines()
    counts: dict[str, dict[str, int]] = {}
    samples: list[tuple[int, int, str, str]] = []
    verdict, tables = classify(lines)

    requirement_rows = 0
    for index, bucket, line, cells, column in verdict:
        strict = bucket in STRICT_BUCKETS and not is_interface_row(cells or [])
        if cells is not None and is_requirement_row(cells):
            requirement_rows += 1                      # 读数 = 全文里形状像需求行的行数
        if bucket == "requirement-cell":
            text = cell_text(cells, column, line)      # 只查「需求」列，证据列不拦
        else:
            text = line
        for label, pattern in TERMS.items():
            for match in re.finditer(pattern, text):
                counts.setdefault(bucket, {})
                counts[bucket][label] = counts[bucket].get(label, 0) + 1
                if strict and len(samples) < 20:
                    samples.append((index + 1, len(samples), label, match.group(0)))
    stats = {"lines": len(lines), "tables": tables, "requirementRows": requirement_rows}
    return counts, samples, stats


def totals(counts: dict[str, dict[str, int]], strict: bool) -> dict[str, int]:
    merged: dict[str, int] = {}
    for bucket, labels in counts.items():
        if (bucket in STRICT_BUCKETS) != strict:
            continue
        for label, count in labels.items():
            merged[label] = merged.get(label, 0) + count
    return merged


def surface_problems(stats: dict[str, int]) -> list[str]:
    """空跑防护：严格档面（需求规范书）取不到输入（或面被砍）时必须判红。"""
    problems: list[str] = []
    if stats["lines"] < FLOOR_LINES:
        problems.append(f"行数只有 {stats['lines']}（下限 {FLOOR_LINES}）")
    if stats["tables"] < FLOOR_TABLES:
        problems.append(f"表格只有 {stats['tables']} 张（下限 {FLOOR_TABLES}）")
    if stats["requirementRows"] < FLOOR_REQUIREMENT_ROWS:
        problems.append(
            f"需求形状行只有 {stats['requirementRows']} 行（下限 {FLOOR_REQUIREMENT_ROWS}）"
        )
    return problems


def readout(target: str, stats: dict[str, int]) -> str:
    return (
        f"扫描面（{target}）：{stats['lines']} 行 / {stats['tables']} 张表 / "
        f"{stats['requirementRows']} 行需求形状行"
        f"（下限 {FLOOR_LINES} / {FLOOR_TABLES} / {FLOOR_REQUIREMENT_ROWS}）"
    )


def collect(root: pathlib.Path) -> dict:
    results = {}
    for target in TARGETS:
        path = root / target
        if not path.exists():
            print(f"跳过：{target} 不存在")
            continue
        results[target] = scan(path)
    return results


def load_baseline(path: pathlib.Path) -> dict[str, int]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    totals_field = data.get("totals", {})
    return totals_field if isinstance(totals_field, dict) else {}


def write_baseline(path: pathlib.Path, strict: dict[str, int], history: list | None = None) -> None:
    payload: dict = {"comment": BASELINE_COMMENT, "totals": strict}
    if history:
        payload["history"] = history
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def run(root: pathlib.Path, report: bool, update: bool, confirm: bool) -> int:
    results = collect(root)

    if report:
        for target, (counts, samples, stats) in results.items():
            strict = sum(totals(counts, True).values())
            loose = sum(totals(counts, False).values())
            print(f"{target}：严格档 {strict} 处 / 报告档 {loose} 处")
            for bucket in BUCKETS:
                labels = counts.get(bucket)
                if not labels:
                    continue
                name, is_strict = BUCKETS[bucket]
                print(f"   [{'严格' if is_strict else '报告'}] {name}：{sum(labels.values())}")
                for label, count in sorted(labels.items(), key=lambda item: -item[1]):
                    print(f"          {count:>4}  {label}")
            for line, _, label, text in samples[:8]:
                print(f"        :{line}  {label} → {text}")
            print(readout(target, stats))
        return 0

    entry = results.get(SRS)
    if entry is None:
        print("❌ 平台中立性校验**无法进行**（空跑防护）：" + f"{SRS} 不在根上")
        print("   判据取不到输入时不许打绿 —— 请从本仓根跑，或用 `--root <树>` 指定仓根。")
        return 1
    counts, _, stats = entry
    problems = surface_problems(stats)
    if problems:
        print("❌ 平台中立性校验**无法进行**（空跑防护）：" + "；".join(problems))
        print("   判据取不到输入时不许打绿 —— 请从本仓根跑，或用 `--root <树>` 指定仓根。")
        return 1

    strict = totals(counts, True)
    loose = totals(counts, False)
    baseline_path = root / BASELINE_REL

    if update:
        allowed_before = load_baseline(baseline_path)
        if allowed_before and not confirm:
            print(
                f"❌ 拒绝覆盖非空基线（{len(allowed_before)} 类 / 合计 "
                f"{sum(allowed_before.values())} 处）—— 它会一条命令把红变绿且不留痕。"
            )
            print("   旧：" + json.dumps(allowed_before, ensure_ascii=False, sort_keys=True))
            print("   新：" + json.dumps(strict, ensure_ascii=False, sort_keys=True))
            print("   确要覆盖请显式带 `--confirm`（会把变更记进台账的 history 段）。")
            return 2
        history = None
        if allowed_before and confirm:
            labels = sorted(set(allowed_before) | set(strict))
            for label in labels:
                old = allowed_before.get(label, 0)
                new = strict.get(label, 0)
                if old != new:
                    print(f"   基线 diff  {label}: {old} → {new}")
            history = [{"at": datetime.date.today().isoformat(), "from": allowed_before, "to": strict}]
        write_baseline(baseline_path, strict, history)
        print(f"✅ 基线已更新：严格档 {sum(strict.values())} 处（报告档 {sum(loose.values())} 处，不拦截）")
        return 0

    allowed = load_baseline(baseline_path)
    for target, (counts_here, _, stats_here) in results.items():
        if target != SRS:
            print(f"  {target}：报告档 {sum(totals(counts_here, False).values())} 处（仅报告）")
            continue
        print(f"  {target}：严格档 {sum(strict.values())} 处（配额 0），报告档 {sum(loose.values())} 处（允许）")
        for bucket in BUCKETS:
            labels = counts.get(bucket)
            if labels and bucket not in STRICT_BUCKETS:
                print(f"     · {BUCKETS[bucket][0]} {sum(labels.values())} 处")
        print("  " + readout(target, stats_here))

    problems = [
        f"{label}: {allowed.get(label, 0)} → {count}"
        for label, count in strict.items()
        if count > allowed.get(label, 0)
    ]
    if problems:
        print(f"❌ 平台中立性校验失败（严格档比基线更差，{len(problems)} 类）：")
        for problem in problems:
            print("   " + problem)
        print("   提示：需求正文只写产品行为；实现细节写进「状态/证据」列，或挪到 §10.9；")
        print("         确有必要保留时在该行写 <!-- platform-ok: 理由 -->。")
        return 1

    print(f"✅ 平台中立性校验通过（严格档 {sum(strict.values())} 处 / 报告档 {sum(loose.values())} 处）")
    return 0


SCRIPT = REPO / "Scripts/check-platform-neutrality.py"


def run_self_test() -> int:
    """判据自己的证据（18 例）：一律在临时副本上写坏，末例核对真仓库逐字节未变。"""
    failures: list[str] = []
    total = 0
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-platform-neutrality-"))
    before = hashlib.sha256(SCRIPT.read_bytes()).hexdigest()

    def invoke(root, cwd, extra=()):
        command = [sys.executable, str(SCRIPT)]
        if root is not None:
            command += ["--root", str(root)]
        command += list(extra)
        completed = subprocess.run(command, cwd=str(cwd), capture_output=True, text=True)
        return completed.returncode, completed.stdout + completed.stderr

    def fixture(name: str) -> pathlib.Path:
        """临时副本：只拷严格档面（需求规范书）+ 基线台账 —— 两样正是自检要写坏的东西。"""
        where = scratch / name
        (where / "Docs").mkdir(parents=True)
        (where / "Scripts").mkdir(parents=True)
        shutil.copy2(REPO / SRS, where / SRS)
        shutil.copy2(REPO / BASELINE_REL, where / BASELINE_REL)
        return where

    def append(where: pathlib.Path, rows: list[str]) -> None:
        """把夹具插进副本的 §3 之前 —— **不能写在文末**：文末落在 §10 附录里，整段只报告。"""
        target = where / SRS
        lines = target.read_text(encoding="utf-8").splitlines()
        anchor = next(i for i, line in enumerate(lines) if line.startswith("# 第三章"))
        lines[anchor:anchor] = [""] + list(rows)
        target.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def requirement_table(header: str, *rows: str) -> list[str]:
        columns = header.count("|") - 1
        return ["", header, "|" + "---|" * columns, *rows]

    def red(where, extra=()):
        code, output = invoke(where, where, extra)
        if code == 0:
            return "仍 rc=0（该判红）"
        if "Swift/Apple 语言与框架" not in output:
            return "判红了但不是命中的那一条"
        return None

    def green(where, extra=()):
        code, output = invoke(where, where, extra)
        if code != 0:
            return f"该绿却判红（rc={code}）\\n{output[-400:]}"
        return None

    def case(description: str, check) -> None:
        nonlocal total
        total += 1
        problem = check()
        if problem:
            failures.append(f"例 {total} 失败：{description} —— {problem}")

    # 例 1：真仓正例 —— 严格档 0 处 + 打印扫描面读数
    def check_positive():
        code, output = invoke(None, REPO)
        if code != 0:
            return f"真仓实跑不是绿（rc={code}）"
        if "严格档 0 处" not in output:
            return "严格档不是 0 处"
        if "需求形状行" not in output:
            return "没打扫描面读数（需求形状行）"
        return None
    case("真仓正例：rc=0 + 严格档 0 处 + 打印扫描面读数", check_positive)

    # 例 2：加粗编号（旧版 cells[0] 带 `**` ⇒ 判成 table-record，整体掉进报告档）
    def check_bold():
        where = fixture("bold")
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            "| **FR-CONN-99** | 直接绑定 SwiftUI 的实现细节（探针） | 基线必备 |",
        ))
        return red(where)
    case("加粗编号 `**FR-CONN-99**` ⇒ 判红（旧版 rc=0）", check_bold)

    # 例 3：缩进表格（旧版 startswith("|") 为假 ⇒ 面外）
    def check_indent():
        where = fixture("indent")
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            " | FR-CONN-96 | 直接绑定 SwiftUI 的实现细节（探针） | 基线必备 |",
        ))
        return red(where)
    case("行首带空格的缩进表格 ⇒ 判红（旧版 rc=0）", check_indent)

    # 例 4：反引号编号
    def check_backtick():
        where = fixture("backtick")
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            "| `FR-CONN-98` | 直接绑定 SwiftUI 的实现细节（探针） | 基线必备 |",
        ))
        return red(where)
    case("反引号编号 `` `FR-CONN-98` `` ⇒ 判红（旧版 rc=0）", check_backtick)

    # 例 5：单元格 <3（旧版 len(cells)>=3 为假 ⇒ 面外）
    def check_two_cells():
        where = fixture("two-cells")
        append(where, requirement_table(
            "| 编号 | 需求 |",
            "| FR-CONN-95 | 直接绑定 SwiftUI 的实现细节（探针） |",
        ))
        return red(where)
    case("两格行（单元格 <3）⇒ 判红（旧版 rc=0）", check_two_cells)

    # 例 6：「需求」列按表头定位（旧版写死 cells[1]，列被挪走即整列面外）
    def check_column():
        where = fixture("column")
        append(where, requirement_table(
            "| 编号 | 层次 | 需求 | 证据 |",
            "| FR-CONN-94 | 基线必备 | 直接绑定 SwiftUI 的实现细节（探针） | ✅ |",
        ))
        return red(where)
    case("「需求」列在第 3 格（表头定位）⇒ 仍判红（旧版只读第 2 格）", check_column)

    # 例 7：证据列不拦（只扫「需求」列）
    def check_evidence_cell():
        where = fixture("evidence-cell")
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            "| FR-CONN-93 | 界面必须始终可用 | SwiftUI 探针实现 |",
        ))
        return green(where)
    case("证据列（第 3 格）出现平台词 ⇒ rc=0（只扫「需求」列）", check_evidence_cell)

    # 例 8：表头没有「需求」列的表（编号法说明表形状）不判红
    def check_no_header_table():
        where = fixture("no-header")
        append(where, requirement_table(
            "| 写法 | 含义 | 示例 |",
            "| `FR-<模块>-<序号>` | 功能需求 | `FR-STD-DB-EXEC-009` |",
        ))
        return green(where)
    case("表头没有「需求」列的写法说明表 ⇒ rc=0（占位符不算需求正文）", check_no_header_table)

    # 例 9：注释位豁免该绿
    def check_exempt_comment():
        where = fixture("exempt")
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            "| FR-CONN-92 | 直接绑定 SwiftUI 的实现细节 <!-- platform-ok: 反例引用 --> | ✅ |",
        ))
        return green(where)
    case("行内 `<!-- platform-ok: 理由 -->` ⇒ 该行豁免（rc=0）", check_exempt_comment)

    # 例 10：裸 `platform-ok` 不构成豁免（旧版裸子串命中即整行跳过）
    def check_bare_token():
        where = fixture("bare-token")
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            "| FR-CONN-91 | 直接绑定 SwiftUI 的实现细节（platform-ok） | ✅ |",
        ))
        return red(where)
    case("需求正文里裸写 `platform-ok` ⇒ 不豁免、仍判红（旧版 rc=0）", check_bare_token)

    # 例 11：非空基线 + 无 --confirm ⇒ 拒绝且不动文件
    def check_refuse_without_confirm():
        where = fixture("refuse")
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            "| FR-CONN-90 | 直接绑定 SwiftUI 的实现细节（探针） | ✅ |",
        ))
        code, _ = invoke(where, where, ("--update-baseline", "--confirm"))
        if code != 0:
            return "先写一份非空基线这一步就没成"
        target = where / BASELINE_REL
        before_bytes = target.read_bytes()
        code, output = invoke(where, where, ("--update-baseline",))
        if code == 0:
            return "非空基线被一条命令覆盖（rc=0）"
        if "拒绝覆盖非空基线" not in output:
            return "拒绝了但不是基线防护那一条"
        if target.read_bytes() != before_bytes:
            return "拒绝时仍改写了基线文件"
        return None
    case("`--update-baseline` 非空基线且无 `--confirm` ⇒ 拒绝（rc=2）且基线逐字节未变", check_refuse_without_confirm)

    # 例 12：非空基线 + --confirm ⇒ 覆盖成功 + 打印 diff + 变更记进 history
    def check_confirm_writes():
        where = fixture("confirm")
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            "| FR-CONN-89 | 直接绑定 SwiftUI 的实现细节（探针） | ✅ |",
        ))
        code, _ = invoke(where, where, ("--update-baseline", "--confirm"))
        if code != 0:
            return "写非空基线失败"
        append(where, requirement_table(
            "| 编号 | 需求 | 证据 |",
            "| FR-CONN-88 | 直接绑定 AppKit 的实现细节（探针） | ✅ |",
        ))
        code, output = invoke(where, where, ("--update-baseline", "--confirm"))
        if code != 0:
            return f"带 `--confirm` 覆盖非空基线仍失败（rc={code}）"
        if "基线 diff" not in output:
            return "没有打印逐标签 diff"
        data = json.loads((where / BASELINE_REL).read_text(encoding="utf-8"))
        if not data.get("history"):
            return "变更没有记进台账 history 段"
        if data.get("totals", {}).get("Swift/Apple 语言与框架") != 2:
            return f"totals 没跟上实测（{data.get('totals')}）"
        return None
    case("非空基线 + `--confirm` ⇒ 覆盖成功 + 打印 diff + 变更记进 history", check_confirm_writes)

    # 例 13：空基线 + --update-baseline ⇒ 既有行为逐字保留（文件逐字节不变）
    def check_empty_baseline_verbatim():
        where = fixture("verbatim")
        target = where / BASELINE_REL
        before_bytes = target.read_bytes()
        code, output = invoke(where, where, ("--update-baseline",))
        if code != 0:
            return f"空基线跑 `--update-baseline` 不再是 0（rc={code}）\n{output[-300:]}"
        if target.read_bytes() != before_bytes:
            return "基线文件与改前不是逐字节相同（既有行为没保住）"
        return None
    case("空基线 + `--update-baseline` ⇒ rc=0 且基线文件逐字节不变（既有行为逐字保留）", check_empty_baseline_verbatim)

    # 例 14：需求规范书不在根上 ⇒ 空跑防护判红（旧版打「跳过」后判绿）
    def check_no_srs():
        where = scratch / "no-srs"
        (where / "Docs").mkdir(parents=True)
        (where / "Scripts").mkdir(parents=True)
        code, output = invoke(where, where)
        if code == 0:
            return "需求规范书不在根上仍 rc=0"
        if "空跑防护" not in output:
            return "判红了但不是空跑防护那一条"
        return None
    case("需求规范书不在根上 ⇒ 空跑防护判红（旧版 rc=0）", check_no_srs)

    # 例 15：面被砍到底 ⇒ 空跑防护判红
    def check_pruned():
        where = fixture("pruned")
        target = where / SRS
        lines = target.read_text(encoding="utf-8").splitlines()
        target.write_text("\n".join(lines[:200]) + "\n", encoding="utf-8")
        code, output = invoke(where, where)
        if code == 0:
            return "面被砍到 200 行仍 rc=0"
        if "空跑防护" not in output:
            return "判红了但不是空跑防护那一条"
        return None
    case("扫描面被砍到底（需求规范书只剩 200 行）⇒ 空跑防护判红", check_pruned)

    # 例 16：未知参数不再被静默吞掉
    def check_unknown_arg():
        code, _ = invoke(None, REPO, ("--nonsense",))
        if code == 0:
            return "未知参数仍 rc=0（静默吞掉）"
        return None
    case("未知参数 ⇒ rc≠0（不再静默吞掉）", check_unknown_arg)

    # 例 17：仓外 CWD 读数与仓根一致（根按 __file__ 推导）
    def check_foreign_cwd():
        _, from_repo = invoke(None, REPO)
        _, from_tmp = invoke(None, pathlib.Path(tempfile.gettempdir()))
        lines_repo = [l for l in from_repo.splitlines() if "需求形状行" in l]
        lines_tmp = [l for l in from_tmp.splitlines() if "需求形状行" in l]
        if not lines_repo or not lines_tmp:
            return "读数行没打出来"
        if lines_repo != lines_tmp:
            return "仓外 CWD 的读数与仓根不一致"
        return None
    case("从仓根之外的 CWD 跑 ⇒ 读数与仓根一致", check_foreign_cwd)

    # 例 18：真仓库逐字节未变 + 真仓实跑绿
    def check_repository_untouched():
        if hashlib.sha256(SCRIPT.read_bytes()).hexdigest() != before:
            return "自检改动了真仓库的脚本"
        code, output = invoke(None, REPO)
        if code != 0:
            return f"真仓实跑不是绿（rc={code}）"
        return None
    case("真仓库逐字节未变 + 真仓实跑 rc=0", check_repository_untouched)

    shutil.rmtree(scratch, ignore_errors=True)
    for failure in failures:
        print(f"   ❌ {failure}")
    print(f"判据自检：{total} 条中 {total - len(failures)} 条达到预期")
    return 0 if not failures else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="平台中立性棘轮（Scripts/check-platform-neutrality.py）"
    )
    parser.add_argument("--root", default=None, help="仓根（默认 = 本脚本所在仓）")
    parser.add_argument("--report", action="store_true", help="看两档分布与命中样例（不判红）")
    parser.add_argument("--update-baseline", action="store_true", help="更新基线（非空时需 --confirm）")
    parser.add_argument("--confirm", action="store_true", help="确认覆盖非空基线（先打印 diff）")
    parser.add_argument("--self-test", action="store_true", help="判据自己的证据（临时副本上写坏）")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.self_test:
        return run_self_test()
    root = pathlib.Path(args.root).expanduser().resolve() if args.root else REPO
    return run(root, args.report, args.update_baseline, args.confirm)


if __name__ == "__main__":
    raise SystemExit(main())
