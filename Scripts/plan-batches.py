#!/usr/bin/env python3
"""按台账/队列重出「批次队列」`.agent/batches.yaml`（v0.4.0 起连 `.agent/plan.yaml` 一起重出）。

为什么要有这个脚本：批次划分是**派生件**，台账一改（某条收口了）批次就得跟着改。
手改一定会漂，所以划分规则写在这里、文件由脚本产出。

用法：
    python3 Scripts/plan-batches.py --check                 # 只比对，不写盘；不一致 rc=1
    python3 Scripts/plan-batches.py --write                 # 重出 batches.yaml
    python3 Scripts/plan-batches.py --emit-plan --write     # 先按台账重出 plan.yaml，再重出批次
    python3 Scripts/plan-batches.py --version 0.3.0 --check # 历史版（只比 batches.yaml ↔ plan.yaml）

覆盖声明（**分版本，别混**）：
- `--version 0.4.0`（默认，当前版）**读台账**。范围 = 台账里 `FR-NTS-NOTE-*` / `FR-NTS-TODO-*`
  且状态未 ✅ 的行（`FR-NTS-ALL-*` 不在范围；已 ✅ 的 `NOTE-EXPORT-001` / `TODO-CALENDAR-003` 自然落选）。
  `--check` 做两件事：① `plan.yaml` 的 todo 集合 == 台账复算集合（缺一条 / 多一条 / 台账已闭而队列仍 todo，都判红）；
  ② `batches.yaml` == 按 `plan.yaml` 重出的结果，且没有条目掉进「未归堆」。
- `--version 0.3.0`（历史）只认 `plan.yaml` 的 `- id:` / `status:` 两列，**不读台账** ——
  那一版队列 35 条与台账 111 条 DB 行不是同一集合，拿台账复算会误报；要复算它得先切回历史的 `plan.yaml`。
"""

from __future__ import annotations

import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / ".agent" / "plan.yaml"
OUT = ROOT / ".agent" / "batches.yaml"
LEDGER = ROOT / "Docs" / "Doyah产品开发计划任务清单-macOS.md"

# --------------------------------------------------------------------------- #
# v0.3.0（历史）：数据库运维面，B1–B7
# --------------------------------------------------------------------------- #
BATCHES_V030: list[dict] = [
    dict(
        id="B1",
        title="快速收口：老底子齐了的 5 条（第一片 TASK-003 已收口，余 4 条）",
        est_min=35,
        match=["FR-STD-DB-TASK-001", "FR-STD-DB-TASK-002", "FR-STD-DB-TASK-003",
               "FR-STD-DB-IO-002", "FR-STD-DB-META-006"],
        why="Core + 测试 + App 引用三件已齐（TASK 三条）或只有测试差接线（IO-002 / META-006）"
            " ⇒ 只补点验与接线，不重写功能。**第一片实测纠正了这句的一半**：TASK 三条的入口"
            "（工具栏菜单 / 审批单 / 回执页三枚动作）是 SwiftUI 控件，离屏宿主里不落 `NSButton`、"
            "无障碍树也不构建 ⇒ 点不到就量不到，收口前得先把入口换成真 AppKit 控件"
            "（TASK-003 已按 `PanelIconButton` 办完）；IO-002 的入口是生产右键菜单（AppKit，已有探针），"
            "META-006 的「重试」还是 SwiftUI 文字按钮",
        exit="余 4 行两列全 ✅；证据一段式（第一片：`.agent/evidence/2026-11-01-B1-TASK-003.md`）",
    ),
    dict(
        id="B2",
        title="结果面收尾：分页 / 筛选 / 流式落盘 / 导出 Excel",
        est_min=50,
        match=["FR-STD-DB-RES-"],
        why="同属 ResultView 一族，探针共用同一套视图夹具，一起改一次跑；"
            "RES-006/007/008 刚在这条线上做过，上下文还热",
        exit="4 行两列全 ✅；结果面视图探针一批跑完",
    ),
    dict(
        id="B3",
        title="元数据面：跨库浏览 / 分组视图 / 对象搜索 / 查看 DDL",
        est_min=60,
        match=["FR-STD-DB-META-"],
        why="五条都在对象树上（层级 / 分组 / 搜索 / 下钻 / 取 DDL），同一棵树改一次比拆五次省一半",
        exit="5 行两列全 ✅；对象树探针一批跑完",
    ),
    dict(
        id="B4",
        title="导入导出：pg_dump/restore / 恢复到指定库 / CSV·JSON 导入 / xlsx 向导",
        est_min=50,
        match=["FR-STD-DB-IO-"],
        why="四条共用 IO 执行器与进度回执，命令拼装可一次写完",
        exit="4 行两列全 ✅；含一条「命令拼错必判红」反例",
    ),
    dict(
        id="B5",
        title="会话与诊断：会话列表 / 取消终止 / 服务器级对象 / 慢查询 / 统计面板 / DIAG-006",
        est_min=70,
        match=["FR-STD-DB-SESS-", "FR-STD-DB-DIAG-"],
        why="全部走 pg_stat_* / pg_cancel_backend 一类系统视图，查询层同构；"
            "DIAG-006 是唯一 ⬜，同批补需求定义",
        exit="6 行两列全 ✅；DIAG-006 先补定义行再判",
    ),
    dict(
        id="B6",
        title="数据编辑与表结构：count(*) / 单元格编辑器 / 外键导航 / 结构编辑器 / Schema 对比",
        est_min=60,
        match=["FR-STD-DB-DATA-", "FR-STD-DB-DDL-"],
        why="都围绕表/列的元数据读写，DDL 生成器一条链；DDL-003 与 DDL-004 共用同一份差异模型",
        exit="5 行两列全 ✅；DDL 生成用例含「不许猜列类型」反例",
    ),
    dict(
        id="B7",
        title="连接与驱动：连接分组 / SSH 隧道 / GBase 8a 驱动",
        est_min=45,
        match=["FR-STD-DB-CONN-", "FR-STD-DB-DRV-"],
        why="连接层同一处改：分组是配置结构、SSH 隧道是连接前段、GBase 是协议族复用",
        exit="3 行两列全 ✅；SSH 隧道允许只落「本机无跳板机」的如实未知",
    ),
]

# --------------------------------------------------------------------------- #
# v0.4.0：笔记与任务闭环，N1–N3（原计划 N1–N4，实测 14 条的分布后合成 3 批，见 why）
# --------------------------------------------------------------------------- #
BATCHES_V040: list[dict] = [
    dict(
        id="N1",
        title="笔记面收尾：采集 / 附件 / 版本 / 笔记本归属 / 私密 / 同步冲突",
        est_min=90,
        match=["FR-NTS-NOTE-CAPTURE-001", "FR-NTS-NOTE-ATTACH-001", "FR-NTS-NOTE-VERSION-001",
               "FR-NTS-NOTE-ORG-002", "FR-NTS-NOTE-PRIVACY-001", "FR-NTS-NOTE-SYNC-002"],
        why="六条都在笔记这本身上（一个动作记下 / 附件引用 / 版本回滚 / 单层笔记本 / 私密不进搜索同步 / "
            "记录级 LWW 留两版），共用 `NotesStore` + 同一份检索与同步口径 ⇒ 一次改到位比一条一跳省手续费。"
            "原计划的 N1/N2 边界（采集·格式·附件 / 检索·组织·回收站）在台账上只剩这几条未闭："
            "FORMAT / SEARCH / ORG-001 / TRASH / SYNC-001 早已 ✅",
        exit="6 行两列全 ✅；每条的证据必须是探针或单测读数（`ledger-row.py <ID>` 出现 ✅ 只算抽查）",
    ),
    dict(
        id="N2",
        title="待办条目：本体 / 清单视图 / 组织检索 / 与笔记双向转化",
        est_min=70,
        match=["FR-NTS-TODO-LIST-001", "FR-NTS-TODO-LIST-002", "FR-NTS-TODO-LIST-003",
               "FR-NTS-TODO-LINK-001"],
        why="四条都是「一条待办记录本身」的读写（字段 / 列表增删改排序 / 分组筛选排序 / 与笔记互转带回指），"
            "同一个模型与同一套同步，拆开做会重复写迁移",
        exit="4 行两列全 ✅；含一条「任务与笔记互转后回指可撤销」的反例",
    ),
    dict(
        id="N3",
        title="待办日历与状态一致性：月/周视图 / 当天详情 / 完成与改期同一事务 / 单一事实源",
        est_min=60,
        match=["FR-NTS-TODO-CALENDAR-001", "FR-NTS-TODO-CALENDAR-002",
               "FR-NTS-TODO-STATE-001", "FR-NTS-TODO-STATE-002"],
        why="四条互相咬：日历只是同一份任务的第二种视图，所以「完成 / 改期同一事务」与「日历不另存」"
            "必须同批落地，否则先做日历就会做出第二套状态",
        exit="4 行两列全 ✅；含一条「日历另存一份 ⇒ 必须判红」的反例",
    ),
]

VERSION_SPECS: dict[str, dict] = {
    "0.4.0": dict(
        title="v0.4.0 笔记与任务闭环",
        rest_id="N9",
        ledger_scope=("FR-NTS-NOTE-", "FR-NTS-TODO-"),
        batches=BATCHES_V040,
    ),
    "0.3.0": dict(
        title="v0.3.0 数据库运维面",
        rest_id="B8",
        ledger_scope=None,
        batches=BATCHES_V030,
    ),
}
DEFAULT_VERSION = "0.4.0"
EVIDENCE_CMD = "cd ~/dev/doyah/lead/studio && python3 Scripts/ledger-row.py {id} | grep -q '✅'"


def read_plan() -> list[tuple[str, str]]:
    text = PLAN.read_text(encoding="utf-8")
    ids = re.findall(r"- id: (\S+)", text)
    status = re.findall(r"status: (\w+)", text)
    if len(ids) != len(status):
        raise SystemExit(f"plan.yaml 形状异常：id {len(ids)} 个 / status {len(status)} 个")
    return list(zip(ids, status))


def read_ledger() -> list[dict]:
    """台账逐行：只取 `编号` / `一句话` / `层次` / `优先级` / `状态` 五格（第 6 格起是证据，可能含 `|`）。"""
    rows: list[dict] = []
    for line in LEDGER.read_text(encoding="utf-8").splitlines():
        if not re.match(r"\|\s*(FR|AC|NFR)-", line):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6:
            continue
        rows.append(dict(id=cells[0], goal=cells[1], layer=cells[3],
                         prio=cells[4], status=cells[5]))
    return rows


def ledger_open(scope: tuple[str, ...] | None) -> list[dict]:
    rows = read_ledger()
    if scope is not None:
        rows = [r for r in rows if r["id"].startswith(scope)]
    return [r for r in rows if r["status"] != "✅"]


def matches(item: str, patterns: list[str]) -> bool:
    return any(item == p if not p.endswith("-") else item.startswith(p) for p in patterns)


def assign(todos: list[str], spec_version: dict) -> list[tuple[dict, list[str]]]:
    """把 todo 按规则分堆；已收口（非 todo）的条目不出现在批次里。"""
    taken: set[str] = set()
    batches = []
    for spec in spec_version["batches"]:
        items = [i for i in todos if i not in taken and matches(i, spec["match"])]
        taken.update(items)
        batches.append((spec, items))
    rest = [i for i in todos if i not in taken]
    if rest:
        batches.append((dict(id=spec_version["rest_id"], title="未归堆（划分规则漏了）", est_min=40,
                             why="plan.yaml 里出现了不属于任何批次的条目 ⇒ 补规则，不许手工硬塞",
                             exit="归堆后再跑"), rest))
    return batches


def yaml_str(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_batches(batches: list[tuple[dict, list[str]]], todos: list[str], spec_version: dict) -> str:
    done = [i for i, s in read_plan() if s == "done"]
    blocked = [i for i, s in read_plan() if s == "blocked"]
    total = sum(len(items) for _, items in batches)
    est = sum(spec["est_min"] for spec, items in batches if items)
    short = (lambda x: x.split("-")[-2] + "-" + x.split("-")[-1])
    lines = [
        f"# {spec_version['title']} · 批次队列（一跳 = 一批，3–6 条同类项）",
        "#",
        "# 唯一事实源 = Docs/Doyah产品开发计划任务清单-macOS.md（活书台账）。",
        "# 本文件只决定「一跳做哪几条」，不许反向改台账。",
        f"# 生成于 {datetime.date.today().isoformat()}，"
        f"源 = plan.yaml 里 {len(todos)} 条 status: todo"
        + (f"（已收口 {len(done)} 条：{', '.join(short(x) for x in done)}）" if done else "")
        + (f"（另有 {len(blocked)} 条 blocked，不在批次里：{', '.join(blocked)}）" if blocked else ""),
        "#",
        "# 生成命令：python3 Scripts/plan-batches.py --write   （--check 只比对不写盘）",
        "",
        "batches:",
        "",
    ]
    for spec, items in batches:
        if not items:
            continue
        lines += [
            f"  - id: {spec['id']}",
            f"    title: {yaml_str(spec['title'])}",
            "    status: todo",
            f"    est_min: {spec['est_min']}",
            f"    items: [{', '.join(items)}]",
            f"    why: {yaml_str(spec['why'])}",
            f"    exit: {yaml_str(spec['exit'])}",
            "",
        ]
    lines += [
        f"# 合计 {total} 条，覆盖 plan.yaml 全部 todo。",
        f"# 粗估 {est} 分钟 ≈ {est / 60:.1f} 小时（原一格一条的节奏按 20 分钟/条算）。",
    ]
    return "\n".join(lines) + "\n"


def render_plan(rows: list[dict], spec_version: dict) -> str:
    """按台账未闭行重出 plan.yaml（派生队列，不许手写）。"""
    order: dict[str, int] = {}
    for spec in spec_version["batches"]:
        for i, ident in enumerate(spec["match"]):
            order.setdefault(ident, len(order))
    rows = sorted(rows, key=lambda r: order.get(r["id"], 10_000))
    yellow = sum(1 for r in rows if r["status"] == "🟡")
    white = sum(1 for r in rows if r["status"] == "⬜")
    lines = [
        f"# {spec_version['title']} · 执行队列（**派生件**）",
        "# 唯一事实源 = Docs/Doyah产品开发计划任务清单-macOS.md（活书台账）。",
        "# 本文件只做「下一跳」排序，不许反向改台账；台账一改就跑 --emit-plan 重出，别手改。",
        f"# 生成于 {datetime.date.today().isoformat()}，源 = 台账里 "
        f"{' / '.join(spec_version['ledger_scope'])} 未闭 {len(rows)} 条（{yellow} 🟡 / {white} ⬜）。",
        "tasks:",
    ]
    for r in rows:
        lines += [
            f"  - id: {r['id']}",
            f"    goal: {yaml_str(r['goal'])}",
            f"    done_when: {yaml_str(EVIDENCE_CMD.format(id=r['id']))}",
            f"    layer: {yaml_str(r['layer'])}",
            f"    prio: {yaml_str(r['prio'])}",
            "    status: todo",
            '    evidence: ""',
        ]
    return "\n".join(lines) + "\n"


def check_against_ledger(rows: list[dict], spec_version: dict) -> list[str]:
    """台账复算 ↔ plan.yaml 对账。返回错误清单（空 = 通过）。"""
    expected = {r["id"] for r in rows}
    actual = {i for i, s in read_plan() if s == "todo"}
    closed_in_plan = {i for i, s in read_plan() if s != "todo"}
    problems: list[str] = []
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing:
        problems.append(f"台账未闭但队列里没有（{len(missing)} 条）：{', '.join(missing)}")
    if extra:
        problems.append(f"队列仍是 todo 但台账已闭 / 不在本版范围（{len(extra)} 条）：{', '.join(extra)}")
    both = sorted(expected & closed_in_plan)
    if both:
        problems.append(f"台账未闭但队列里标成非 todo（{len(both)} 条）：{', '.join(both)}")
    return problems


def main(argv: list[str]) -> int:
    version = DEFAULT_VERSION
    if "--version" in argv:
        idx = argv.index("--version")
        if idx + 1 >= len(argv):
            print("✗ --version 后面缺版本号（0.3.0 / 0.4.0）", file=sys.stderr)
            return 2
        version = argv[idx + 1]
    if version not in VERSION_SPECS:
        print(f"✗ 未知版本 {version}（只认 {', '.join(VERSION_SPECS)}）", file=sys.stderr)
        return 2

    spec_version = VERSION_SPECS[version]
    if spec_version["ledger_scope"] is not None and "--emit-plan" in argv and "--write" in argv:
        rows = ledger_open(spec_version["ledger_scope"])
        PLAN.write_text(render_plan(rows, spec_version), encoding="utf-8")
        print(f"✅ 已按台账重出 .agent/plan.yaml（{len(rows)} 条 todo）")

    todos = [i for i, s in read_plan() if s == "todo"]
    batches = assign(todos, spec_version)
    text = render_batches(batches, todos, spec_version)

    if "--check" in argv:
        rc = 0
        if spec_version["ledger_scope"] is not None:
            problems = check_against_ledger(ledger_open(spec_version["ledger_scope"]), spec_version)
            for line in problems:
                print(f"✗ {line}")
            if problems:
                rc = 1
        rest = next((items for spec, items in batches if spec["id"] == spec_version["rest_id"]), [])
        if rest:
            print(f"✗ 有 {len(rest)} 条没归进任何批次：{', '.join(rest)}（补规则，不许手塞）")
            rc = 1
        old = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if old.strip() != text.strip():
            print("✗ .agent/batches.yaml 与 plan.yaml 不一致 ⇒ 跑 --write 重出")
            rc = 1
        if rc == 0:
            print(f"✅ 批次队列一致（{len(todos)} 条待办"
                  + ("，台账复算一致" if spec_version["ledger_scope"] is not None else "") + "）")
        return rc
    if "--write" in argv:
        OUT.write_text(text, encoding="utf-8")
        print(f"✅ 已重出 .agent/batches.yaml（{len(todos)} 条待办）")
        return 0
    print("用法：--check | --write [--emit-plan] [--version 0.3.0|0.4.0]")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
