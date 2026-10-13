#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""笔记模块的**解耦门禁**（FR-PLUG-07 / FR-NOTE-23 / 版本矩阵的硬约束）。

为什么要有它：`Doyah Notes`（Windows / 移动）是**独立应用**，不能背着数据库代码；
而"约定别依赖"这种纪律在几百个文件里迟早失守。所以把它变成一条**机械检查**。

口径（刻意保守，只查真正该干净的那一层）：
  · 扫描范围 = **Core 里直接属于笔记的源文件**（`Note` / `NoteBody` / `License` / `AICapture`）；
  · 禁止 import 平台模块（只允许 Foundation）；
  · 禁止引用**数据库侧类型名**（DatabaseService / PostgresService / MySQLDialect / ConnectionConfig …）；
  · 禁止引用 **Ultra 侧类型名**（DiagnosisContext / MaintenancePlanReview / MaintenanceTask …）
    —— 这些类型只有"数据库 + 工作区 + 笔记"全量的构建里才有，笔记侧文件引用它们就等于绑死在宿主上；
  · 发现违规 → 退出码 1，并列出文件、行号、命中的名字。

**当前未覆盖（写在这里，不让它悄悄通过）**：
  · **App 层**：`AppState` 同时认识笔记与数据库 —— 那是"只装配笔记那一块"改造前的事实。
    插件装配的其它约束（同进程 / 单一判据 / 单向上下文）由 `check-plugin-assembly.py` 守。

**历史（L-04，2026-09-26）**：这条门禁原先只ban数据库类型，而 `AICapture.swift` 里留着两个
helper，**参数就是 Ultra 侧类型**（`fingerprint(of:report:)` / `stateText(_:)`）。它们当时
既不在禁用名单里，也没被本脚本看见 —— 于是门禁绿着，而"笔记侧文件可独立构建"这句话不成立。
修法：两个 helper 搬进 `AICaptureUltra.swift`，Ultra 侧类型名进禁用名单（本脚本现在真能拦住）。

**自维护**：`NOTE_SOURCES` 靠人维护，漏加一个文件＝那个文件偷偷不受约束。所以本脚本每次
都拿 `Core/` 里的实际文件名与清单对账（见 `check_source_list_is_complete`）。

**2026-10-14 修（派单 `T-20261010-043` · 合册 `T-20261013-027` 本册表第 28 行）**：对账面**不再靠文件名前缀猜** ——
`Plugins/Notes/Sources/**` 的每一个 `.swift` 都进面（那棵树整棵就是笔记模块），`Core/**` 仍按前缀扫；
前缀无关的件（库绑定 `SQLiteKit` / `SQLiteConstants`、云同步 `CloudAuth` / `CloudSyncService` / `SyncCore` /
`SyncQueue`）逐件登记在 `ULTRA_SIDE_SOURCES`（宿主侧适配层：只对账、不套笔记侧禁令），
「云同步是否属笔记模块」请前门定性。
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
# 只扫"Core 里直接属于笔记"的文件；新增笔记源文件时把它加进来（漏加会被下面的自维护检查抓到）。
NOTE_SOURCES = [
    "Plugins/Notes/Sources/Note.swift",
    "Plugins/Notes/Sources/NoteBody.swift",
    "Core/License.swift",
    # 拆分后 `AICapture` 只剩"笔记侧"的映射（诊断 / 维护那两个已移到 AICaptureUltra）
    "Core/AICapture.swift",
    # 入库判定（队列 L-134）：同指纹默认不重复存 + 显式逃生门 —— 只吃 `NoteDraft` / `Note`
    # 与存储入口，不引用数据库侧与 Ultra 侧任何类型（所以它属笔记侧）
    "Core/AICaptureIntake.swift",
    # 队列 `L-97` 第一~四片：两层归属的结构模型（架 / 笔记本 + 归属解析 + 删除计划）——
    # 只吃 Foundation 值类型与 `NoteStorage` 协议，不引用数据库侧与 Ultra 侧任何类型
    "Plugins/Notes/Sources/Notebook.swift",
    # 队列 `L-97` 界面半第一片：宿主装配侧的选中态 / 范围过滤 / 计数 / 新建落点（纯函数，
    # 无网络、无库）—— 它算笔记侧，因为改它的人必须同时受「不许碰网络 / 库」的约束
    "Plugins/Notes/Sources/NoteNavigation.swift",
    # 队列 `L-97` 界面半第二片：删除确认框的动作 / 顺序 / 文案键（纯值类型，无网络、无库；
    # 只吃 `ContainerRemovalPlan` 与 `LKey`）—— 同上，算笔记侧
    "Plugins/Notes/Sources/NotebookRemovalPrompt.swift",
    # 队列 `L-97` 界面半第三片：跨笔记本移动的目标清单 / 「能不能去」的规则 / 文案键（纯值类型，
    # 无网络、无库；只吃 `NotebookDirectory` / `NotebookPlacement` / `LKey`）—— 同上，算笔记侧
    "Plugins/Notes/Sources/NotebookMovePrompt.swift",
    # 队列 `L-97` 界面半第四片：新建 / 重命名 / 排序的规则与文案键（纯值类型，无网络、无库；
    # 只吃 `NotebookDirectory` / `NotesScope` / `LKey`）—— 同上，算笔记侧
    "Plugins/Notes/Sources/NotebookEditPrompt.swift",
    # 队列 `L-97` 界面半第五片：批量多选 / 拖拽载荷 / 落点（纯值类型，无网络、无库；
    # 只吃 `UUID` / `LKey`）—— 同上，算笔记侧
    "Plugins/Notes/Sources/NoteSelectionPrompt.swift",
    # 队列 `L-97` 界面半第六片（跨架移动）：目标清单 / 落点判定 / 文案键（纯值类型，无网络、
    # 无库；只吃 `NotebookDirectory` / `LKey`）—— 同上，算笔记侧
    "Plugins/Notes/Sources/NotebookShelfMovePrompt.swift",
    # 队列 `L-184` 三栏重排：中栏卡片的摘要与相对时间（纯函数，无网络、无库；只吃 `Date` /
    # `Calendar` / `LKey`）—— 同上，算笔记侧
    "Plugins/Notes/Sources/NotePresentation.swift",
    # 队列 `N-11` 的 macOS 核心层半：待办任务清单的**模型**（`Todo` + `TodoPriority`；纯值类型、
    # 无网络、无库）—— 库表 / 行映射在 `Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift`
    # （那一层自 2026-10-14 起**也**在本清单里：扫描面改递归后按真路径登记，见文件尾那 5 条）
    "Core/Todo.swift",
    # 队列 `L-100` 清单界面（待办清单的三件纯逻辑：分区 / 截止档位 / 空标题）：同上，台账里有它
    # ⇒ 副本必须带上
    "Core/TodoPresentation.swift",
    # 队列 `L-100` 日历的 Core 半第二片（月 / 周格子 + 日期算术 + 投影）—— 第 186 轮落文件时
    # **漏登**（本轮补）：同上，算笔记侧（纯函数，无网络、无库；只吃 `Date` / `Calendar`）
    "Core/TodoCalendar.swift",
    # 队列 `L-100` 的「与提醒联动」Core 半（第 188 轮）：提醒的调度语义（纯函数，无网络、无库；
    # 只吃 Foundation；契约 §2.10 §3.12）
    "Core/Reminder.swift",
    # 队列 `L-100` 落法 ④ 的**界面半第一片**的 Core 半（第 190 轮）：档位 → 规则 / 权限 → 排不排 /
    # 规则 → 一句话（纯函数，无网络、无库、零平台 API；只吃 `Todo` / `Date` / `LKey`）
    "Core/ReminderPresentation.swift",
    # 队列 `L-100` 落法 ④ 的**界面入口半**（第 193 轮）：那一区的合成状态（档位空间 / 选中档 /
    # 档位回显 / 规则 / 求解 / 权限那一档 / 排不排）—— 纯函数，零平台 API，无网络无库
    "Core/ReminderEntry.swift",
    # 队列 `L-100` 的**组织与检索半**（第 191 轮）：排序三档（契约 §3.13 四条）+ 筛选 / 分组 / 视图
    # 入口（与对侧 `TodoSort` / `TodoQuery` 同口径）—— 纯函数，无网络、无库、零平台 API
    "Core/TodoSort.swift",
    "Core/TodoQuery.swift",
    # 2026-10-14（派单 `T-20261010-031` · 合册 `T-20261013-027` · 本条 = 本册表第 18 行）：
    # 2026-10-13 搬家（概设 §7 P3）后，`NoteStorage/` 是 `Plugins/Notes/Sources/` 下的**子目录**，
    # 而本函数的扫描面当时是非递归 glob ⇒ 这 5 件在这个自维护检查里**整体看不见**（真仓实测全绿）。
    # 扫描面改递归后按真路径登记：它们是笔记侧（库表 / 行映射 / 自动保存 / 检索披露），零网络出口
    # 与「不背数据库代码」两条约束对它们同样成立。
    "Plugins/Notes/Sources/NoteStorage/NoteAutosave.swift",
    "Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift",
    "Plugins/Notes/Sources/NoteStorage/NoteLibrary.swift",
    "Plugins/Notes/Sources/NoteStorage/NoteLibraryMigration.swift",
    "Plugins/Notes/Sources/NoteStorage/NoteSearchDisclosure.swift",
]

# 刻意**不在**清单里的笔记相关文件：它们按设计就引用 Ultra 侧类型，属于宿主侧适配层。
# 在这里显式列出（而不是靠"忘了加"），自维护检查才不会误报。
ULTRA_SIDE_SOURCES = [
    "Core/AICaptureUltra.swift",
    # 2026-10-14（派单 `T-20261010-043` · 合册 `T-20261013-027` 本册表第 28 行）：插件树里的**名字不含
    # `Note` / `AICapture` 前缀**那几个件 —— 它们此前连面都进不来（枚举按文件名前缀猜），所以既不在清单里、
    # 也没人发现。前两个字是**库绑定**（`import CSQLite3`，三端共用的薄封装，不是笔记逻辑），
    # 后四个是**云同步层**（`import FoundationNetworking` / 真 HTTP 客户端：是否属笔记模块
    # 待前门定性，见派单 `T-20261010-043` / 离线门禁台账 knownGaps ④）⇒ 按**宿主侧适配层**登记：
    # 只做「清单 ↔ 磁盘」双向对账，不套笔记侧那两条禁令（它们按设计就用平台模块）。
    "Plugins/Notes/Sources/NoteStorage/SQLiteKit.swift",
    "Plugins/Notes/Sources/NoteStorage/SQLiteConstants.swift",
    "Plugins/Notes/Sources/NoteSync/CloudAuth.swift",
    "Plugins/Notes/Sources/NoteSync/CloudSyncService.swift",
    "Plugins/Notes/Sources/NoteSync/SyncCore.swift",
    "Plugins/Notes/Sources/NoteSync/SyncQueue.swift",
]

BANNED_IMPORTS = re.compile(r"^\s*import\s+(?!Foundation\b)(\w+)", re.M)
BANNED_TYPES = [
    # 数据库侧（Doyah Notes 不能背数据库代码）
    "DatabaseService", "NotImplementedDatabaseService", "PostgresService", "MySQLService",
    "GBaseService", "SQLDialect", "PostgresDialect", "MySQLDialect", "GBaseDialect",
    "DatabaseServiceFactory", "SQLDialectFactory", "MetadataService", "StatementSplitter",
    "ConnectionConfig", "ConnectionStore", "DatabaseType",
    # Ultra 侧（只有全量构建里才有这些类型）
    "DiagnosisContext", "DiagnosisAdviceReport", "DiagnosisReport",
    "MaintenancePlanReview", "MaintenanceTask", "MaintenancePlan",
]


def check_source_list_is_complete() -> list[str]:
    """笔记源文件必须"要么在清单里、要么在豁免名单里"。

    笔记源文件现在有**两个落点**（2026-10-13 · 概设 §7 P3 搬家）：
      · `Plugins/Notes/Sources/` —— 插件目录（Note / Notebook / 存储 / 同步 / 视图）；
      · `Core/` —— 尚未搬家的笔记侧件（`License` / `AICapture` / `Todo` / `Reminder` 族）。
    两处都要扫 —— 只扫 `Core/` 会让搬过去的新文件**默默不受本门禁约束**（本函数存在的理由）。
    **2026-10-14 修（派单 `T-20261010-031`）**：两棵树都改成**递归**（`rglob`）并按**仓库相对路径**
    对账 —— 搬家之后 `NoteStorage/` / `NoteSync/` 是子目录，非递归 glob 会让它们整层在面外
    （真仓实测 `Plugins/Notes/Sources/NoteStorage/` 5 件在本检查里看不见）。
    """
    problems: list[str] = []
    roots = [REPO / "Core", REPO / "Plugins" / "Notes" / "Sources"]
    # 2026-10-14（派单 `T-20261010-031` · 合册 `T-20261013-027`）：`glob` → `rglob` + 按**真路径**对账。
    # 此前两棵树都是非递归 glob ⇒ `Plugins/Notes/Sources/NoteStorage/` 一层的笔记源文件整体在面外
    # （真仓实测 5 件全绿）；而 `NOTE_SOURCES` / `ULTRA_SIDE_SOURCES` 本来就写的是**仓库相对路径**
    # ⇒ 按路径对账比按文件名对账更严（同名不同目录不再互相顶数）。
    candidates = [p for root in roots if root.is_dir() for p in root.rglob("*.swift")]
    # 2026-10-14（派单 `T-20261010-043`）：**插件树不再按文件名前缀筛** —— `Plugins/Notes/Sources/` 整个
    # 就是笔记模块的新家，任何 `.swift`（`SQLiteKit` / `CloudAuth` 这种一个前缀都不命中的也算）都必须
    # 在清单里；只有 `Core/`（共享目录）仍按前缀扫。此前两处都靠前缀猜 ⇒ 子目录里的前缀无关件整体在面外。
    plugin_tree = str((REPO / "Plugins" / "Notes" / "Sources").resolve())
    on_disk = sorted(
        p.relative_to(REPO).as_posix()
        for p in candidates
        if str(p.resolve()).startswith(plugin_tree + "/")
        or p.name.startswith("Note")
        or p.name.startswith("AICapture")
    )
    listed = set(NOTE_SOURCES + ULTRA_SIDE_SOURCES)
    for rel in on_disk:
        if rel not in listed:
            problems.append(
                f"{rel}: 新的笔记源文件没进本脚本的清单"
                f"（是笔记侧就加进 NOTE_SOURCES，是宿主侧就加进 ULTRA_SIDE_SOURCES）"
            )
    for item in NOTE_SOURCES + ULTRA_SIDE_SOURCES:
        if not (REPO / item).exists():
            problems.append(f"{item}: 清单里有、磁盘上没有（改名或搬家了？请同步更新本脚本）")
    return problems


def main() -> int:
    problems: list[str] = []
    checked = 0
    for relative in NOTE_SOURCES:
        path = REPO / relative
        if not path.exists():
            print(f"⚠️  找不到 {relative}（改名了？请同步更新本脚本的清单）")
            problems.append(f"{relative}: 文件不存在")
            continue
        checked += 1
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for match in BANNED_IMPORTS.finditer(line):
                problems.append(f"{relative}:{line_number}: import {match.group(1)}")
            for name in BANNED_TYPES:
                # 用词边界，避免把 NoteBodyFormat 之类误判
                if re.search(rf"\b{name}\b", line):
                    problems.append(f"{relative}:{line_number}: 引用了 {name}")

    problems.extend(check_source_list_is_complete())

    if problems:
        print("❌ 笔记模块解耦门禁失败（Doyah Notes 不能背数据库 / Ultra 侧代码）：")
        for item in problems:
            print("   " + item)
        return 1
    print(
        f"✅ 笔记模块解耦门禁通过（{checked} 个笔记源文件：无平台 import、"
        f"无数据库侧类型引用、无 Ultra 侧类型引用；清单与 `Core/` 实际文件、"
        f"`Plugins/Notes/Sources/**` 整棵树双向对账一致 —— 其中前缀无关的库绑定 / 云同步件"
        f"按宿主侧适配层逐件登记）"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
