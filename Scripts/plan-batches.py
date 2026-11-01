#!/usr/bin/env python3
"""按台账/队列重出「批次队列」`.agent/batches.yaml`。

为什么要有这个脚本：批次划分是**派生件**，台账一改（某条收口了）批次就得跟着改。
手改一定会漂，所以划分规则写在这里、文件由脚本产出。

用法：
    python3 Scripts/plan-batches.py --check   # 只比对，不写盘；不一致 rc=1
    python3 Scripts/plan-batches.py --write   # 重出文件

覆盖声明：本脚本只认 `.agent/plan.yaml` 里的 `- id:` / `status:` 两列，
**不读台账**（台账解析在 `Scripts/ledger-row.py`，那是唯一事实源）。
所以「已收口的条目」以 plan.yaml 为准 —— 队列落后于台账时先修队列，不在这里兜。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / ".agent" / "plan.yaml"
OUT = ROOT / ".agent" / "batches.yaml"

# 批次划分规则：顺序即执行顺序，先快后难，同域归一堆。
BATCHES: list[dict] = [
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


def read_plan() -> list[tuple[str, str]]:
    text = PLAN.read_text(encoding="utf-8")
    ids = re.findall(r"- id: (\S+)", text)
    status = re.findall(r"status: (\w+)", text)
    if len(ids) != len(status):
        raise SystemExit(f"plan.yaml 形状异常：id {len(ids)} 个 / status {len(status)} 个")
    return list(zip(ids, status))


def assign(todos: list[str]) -> list[tuple[dict, list[str]]]:
    """把 todo 按规则分堆；已收口（非 todo）的条目不出现在批次里。"""
    taken: set[str] = set()
    batches = []
    for spec in BATCHES:
        if spec["id"] == "B1":
            items = [i for i in spec["match"] if i in todos]
        else:
            items = [i for i in todos if i not in taken
                     and any(i.startswith(p) for p in spec["match"])]
        items = [i for i in items if i not in taken]
        taken.update(items)
        batches.append((spec, items))
    rest = [i for i in todos if i not in taken]
    if rest:
        batches.append((dict(id="B8", title="未归堆（划分规则漏了）", est_min=40,
                             why="plan.yaml 里出现了不属于任何批次的条目 ⇒ 补规则，不许手工硬塞",
                             exit="归堆后再跑"), rest))
    return batches


def render(batches: list[tuple[dict, list[str]]], todos: list[str]) -> str:
    done = [i for i, s in read_plan() if s != "todo"]
    total = sum(len(items) for _, items in batches)
    est = sum(spec["est_min"] for spec, items in batches if items)
    lines = [
        "# v0.3.0 数据库运维面 · 批次队列（一跳 = 一批，3–6 条同类项）",
        "#",
        "# 唯一事实源 = Docs/Doyah产品开发计划任务清单-macOS.md（活书台账）。",
        "# 本文件只决定「一跳做哪几条」，不许反向改台账。",
        f"# 生成于 {__import__('datetime').date.today().isoformat()}，"
        f"源 = plan.yaml 里 {len(todos)} 条 status: todo"
        + (f"（已收口 {len(done)} 条：{', '.join(x.split('-')[-2] + '-' + x.split('-')[-1] for x in done)}）" if done else ""),
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
            f"    title: \"{spec['title']}\"",
            "    status: todo",
            f"    est_min: {spec['est_min']}",
            f"    items: [{', '.join(items)}]",
            f"    why: \"{spec['why']}\"",
            f"    exit: \"{spec['exit']}\"",
            "",
        ]
    lines += [
        f"# 合计 {total} 条，覆盖 plan.yaml 全部 todo。",
        f"# 粗估 {est} 分钟 ≈ {est / 60:.1f} 小时（原一格一条的节奏按 20 分钟/条算）。",
    ]
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    todos = [i for i, s in read_plan() if s == "todo"]
    text = render(assign(todos), todos)
    if "--check" in argv:
        old = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if old.strip() != text.strip():
            print("✗ .agent/batches.yaml 与 plan.yaml 不一致 ⇒ 跑 --write 重出")
            return 1
        print(f"✅ 批次队列一致（{len(todos)} 条待办）")
        return 0
    if "--write" in argv:
        OUT.write_text(text, encoding="utf-8")
        print(f"✅ 已重出 .agent/batches.yaml（{len(todos)} 条待办）")
        return 0
    print("用法：--check | --write")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
