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
都拿 `platform/macos/Core/` 里的实际文件名与清单对账（见 `check_source_list_is_complete`）。
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
# 只扫"Core 里直接属于笔记"的文件；新增笔记源文件时把它加进来（漏加会被下面的自维护检查抓到）。
NOTE_SOURCES = [
    "platform/macos/Core/Note.swift",
    "platform/macos/Core/NoteBody.swift",
    "platform/macos/Core/License.swift",
    # 拆分后 `AICapture` 只剩"笔记侧"的映射（诊断 / 维护那两个已移到 AICaptureUltra）
    "platform/macos/Core/AICapture.swift",
    # 入库判定（队列 L-134）：同指纹默认不重复存 + 显式逃生门 —— 只吃 `NoteDraft` / `Note`
    # 与存储入口，不引用数据库侧与 Ultra 侧任何类型（所以它属笔记侧）
    "platform/macos/Core/AICaptureIntake.swift",
    # 队列 `L-97` 第一~四片：两层归属的结构模型（架 / 笔记本 + 归属解析 + 删除计划）——
    # 只吃 Foundation 值类型与 `NoteStorage` 协议，不引用数据库侧与 Ultra 侧任何类型
    "platform/macos/Core/Notebook.swift",
    # 队列 `L-97` 界面半第一片：宿主装配侧的选中态 / 范围过滤 / 计数 / 新建落点（纯函数，
    # 无网络、无库）—— 它算笔记侧，因为改它的人必须同时受「不许碰网络 / 库」的约束
    "platform/macos/Core/NoteNavigation.swift",
    # 队列 `L-97` 界面半第二片：删除确认框的动作 / 顺序 / 文案键（纯值类型，无网络、无库；
    # 只吃 `ContainerRemovalPlan` 与 `LKey`）—— 同上，算笔记侧
    "platform/macos/Core/NotebookRemovalPrompt.swift",
    # 队列 `L-97` 界面半第三片：跨笔记本移动的目标清单 / 「能不能去」的规则 / 文案键（纯值类型，
    # 无网络、无库；只吃 `NotebookDirectory` / `NotebookPlacement` / `LKey`）—— 同上，算笔记侧
    "platform/macos/Core/NotebookMovePrompt.swift",
    # 队列 `L-97` 界面半第四片：新建 / 重命名 / 排序的规则与文案键（纯值类型，无网络、无库；
    # 只吃 `NotebookDirectory` / `NotesScope` / `LKey`）—— 同上，算笔记侧
    "platform/macos/Core/NotebookEditPrompt.swift",
    # 队列 `L-97` 界面半第五片：批量多选 / 拖拽载荷 / 落点（纯值类型，无网络、无库；
    # 只吃 `UUID` / `LKey`）—— 同上，算笔记侧
    "platform/macos/Core/NoteSelectionPrompt.swift",
    # 队列 `L-97` 界面半第六片（跨架移动）：目标清单 / 落点判定 / 文案键（纯值类型，无网络、
    # 无库；只吃 `NotebookDirectory` / `LKey`）—— 同上，算笔记侧
    "platform/macos/Core/NotebookShelfMovePrompt.swift",
    # 队列 `L-184` 三栏重排：中栏卡片的摘要与相对时间（纯函数，无网络、无库；只吃 `Date` /
    # `Calendar` / `LKey`）—— 同上，算笔记侧
    "platform/macos/Core/NotePresentation.swift",
    # 队列 `N-11` 的 macOS 核心层半：待办任务清单的**模型**（`Todo` + `TodoPriority`；纯值类型、
    # 无网络、无库）—— 库表 / 行映射在 `platform/macos/Core/NoteStorage/NoteDatabase.swift`（那一层不在本清单
    # 的扫描面内，它的零网络出口由同一族判据按目录口径另管）
    "platform/macos/Core/Todo.swift",
    # 队列 `L-100` 清单界面（待办清单的三件纯逻辑：分区 / 截止档位 / 空标题）：同上，台账里有它
    # ⇒ 副本必须带上
    "platform/macos/Core/TodoPresentation.swift",
    # 队列 `L-100` 日历的 Core 半第二片（月 / 周格子 + 日期算术 + 投影）—— 第 186 轮落文件时
    # **漏登**（本轮补）：同上，算笔记侧（纯函数，无网络、无库；只吃 `Date` / `Calendar`）
    "platform/macos/Core/TodoCalendar.swift",
    # 队列 `L-100` 的「与提醒联动」Core 半（第 188 轮）：提醒的调度语义（纯函数，无网络、无库；
    # 只吃 Foundation；契约 §2.10 §3.12）
    "platform/macos/Core/Reminder.swift",
    # 队列 `L-100` 落法 ④ 的**界面半第一片**的 Core 半（第 190 轮）：档位 → 规则 / 权限 → 排不排 /
    # 规则 → 一句话（纯函数，无网络、无库、零平台 API；只吃 `Todo` / `Date` / `LKey`）
    "platform/macos/Core/ReminderPresentation.swift",
    # 队列 `L-100` 落法 ④ 的**界面入口半**（第 193 轮）：那一区的合成状态（档位空间 / 选中档 /
    # 档位回显 / 规则 / 求解 / 权限那一档 / 排不排）—— 纯函数，零平台 API，无网络无库
    "platform/macos/Core/ReminderEntry.swift",
    # 队列 `L-100` 的**组织与检索半**（第 191 轮）：排序三档（契约 §3.13 四条）+ 筛选 / 分组 / 视图
    # 入口（与对侧 `TodoSort` / `TodoQuery` 同口径）—— 纯函数，无网络、无库、零平台 API
    "platform/macos/Core/TodoSort.swift",
    "platform/macos/Core/TodoQuery.swift",
]

# 刻意**不在**清单里的笔记相关文件：它们按设计就引用 Ultra 侧类型，属于宿主侧适配层。
# 在这里显式列出（而不是靠"忘了加"），自维护检查才不会误报。
ULTRA_SIDE_SOURCES = [
    "platform/macos/Core/AICaptureUltra.swift",
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
    """`platform/macos/Core/` 下的笔记源文件必须"要么在清单里、要么在豁免名单里"。"""
    problems: list[str] = []
    on_disk = sorted(
        path.name for path in (REPO / "platform/macos/Core").glob("*.swift")
        if path.name.startswith("Note") or path.name.startswith("AICapture")
    )
    listed = {pathlib.Path(item).name for item in NOTE_SOURCES + ULTRA_SIDE_SOURCES}
    for name in on_disk:
        if name not in listed:
            problems.append(
                f"platform/macos/Core/{name}: 新的笔记源文件没进本脚本的清单"
                f"（是笔记侧就加进 NOTE_SOURCES，是宿主侧就加进 ULTRA_SIDE_SOURCES）"
            )
    for name in sorted(listed):
        if not (REPO / "platform/macos/Core" / name).exists():
            problems.append(f"platform/macos/Core/{name}: 清单里有、磁盘上没有（改名了？请同步更新本脚本）")
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
        f"无数据库侧类型引用、无 Ultra 侧类型引用；清单与 platform/macos/Core/ 实际文件对账一致）"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
