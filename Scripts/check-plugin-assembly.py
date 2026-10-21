#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""**插件装配链的机械门禁**（FR-ALL-ALL-PLUG-001 / 02 / 03 / 06 + ADR-35）。

为什么要有它：`FR-ALL-ALL-PLUG-001~07` 的状态是 ✅，但"当时手动核过一遍"不是证据 ——
新加一个入口、新加一个能力位、把 `private(set)` 拆掉，都能让这些 ✅ 悄悄失效而没人发现。
所以把每条口径写成**可复跑的判据**，接进 `verify-all.sh` 第 10 项，每轮门禁都跑一遍。

守什么（逐条对应需求号）：

  · **FR-ALL-ALL-PLUG-001 同进程内模块**：全仓无 IPC（`NSXPC` / `xpc_` / `import XPC`）；
    笔记源文件随宿主目标一起编译（不存在"笔记插件"这种独立 target / product）。
  · **FR-ALL-ALL-PLUG-002 活动栏与可见性**：活动栏有 `case notes`；**判可见性的只有一处**
    （`LicensePresentation.activityItems`，视图层不许自己 `allCases` 过滤）；
    `notes` 只在能力位允许时出现（不是灰掉）。
  · **FR-ALL-ALL-PLUG-003 单向上下文 / 只传文本与标识**：`AICapture` 的笔记侧入口只收标题 / 正文 / SQL / 连接名；
    **行数据入笔记必须显式 `withRowData()`**，且那个开关全仓只有一处能打开（无法绕过、无法撤回）。
  · **FR-ALL-ALL-PLUG-006 一套许可三能力位**：`LicenseCapabilities.all` 恰好是三个能力位；
    没有"插件单独授权 / 单独开关"这种东西；档位由能力位推导。
  · **ADR-35 单一判据 + 单一写入口**：`selectedActivityItem` 是 `private(set)`；
    全仓赋值只发生在 `AppState.swift`，且每个赋值点所在函数都过了
    `LicensePresentation.resolveSelection`（"未授权区不可达"因此是结构性的）。

2026-10-14 修（合册 `T-20261013-027` · 原单 `T-20261010-033` · 第 401 轮判据面缺口样本 38）：

    ① **㈠「含行数据开关全仓恰好一处」的扫描面改成真·全仓**：此前是
       `(REPO/"Core").glob("*.swift")`（只 Core 顶层），2026-10-13 搬家时又并了
       `Plugins/Notes/Sources`，**两处都非递归** —— 而 docstring / 需求书 FR-ALL-ALL-PLUG-003
       证据格 / 开发记录三处写的都是「**全仓**恰好一处」。真仓 2026-10-14 实测：旧面
       **332** 份 ↔ 全仓 `*.swift` **909** 份 ⇒ `App/` / `CLI/` / `Platform/` /
       任意子目录（`Plugins/Notes/Sources/NoteStorage/` / `Core/NoteStorage/` 等）里
       开这枚开关、加撤回入口**静默放过**（样本 38 的 B/D/E 三臂）。现面 =
       `face_swift_files()`（仓内所有 `*.swift`，只排除点目录 `.git` / `.build` /
       `.worktrees` 这类副本）+ 空跑防护 `FACE_FLOOR` + 读数「面内 N 份 Swift 源文件」
       + 判红**点名真文件与行号**（旧报名字面量写死 `Core/: …`，与「全仓」的声明脱节）。
    ② **㈡ 笔记源清单不再维护第二份副本**：本脚本原先另存一份 **6 条**的 `NOTE_SOURCES`
       复制（权威在隔离门禁：**26 条**且自维护）⇒ 面静默窄到 6/26，`ResultRow` /
       `QueryResult` / `EffectRow` 那三条禁令有 16 个笔记源在网外（样本 38 的 E/F 两臂）。
       现在**运行时**从 `Scripts/check-note-module-isolation.py` 源码里读那两份清单
       （与 `check-notes-offline.py` 同款，不复制粘贴），并加三条钉：**条数下限**
       （只许涨不许跌：删一条即缩面）、**漏登**（按名命中笔记源前缀却两份清单都不认 ⇒ 红）、
       **陈旧**（清单里写着、盘上没有 ⇒ 红）；读不到清单 / 清单为空同样判红。
       垫底事实：Ultra 侧件（`Core/AICaptureUltra.swift`）在隔离门禁里属
       `ULTRA_SIDE_SOURCES` ⇒ 本脚本的笔记侧面不再把它算进来（旧副本把它混在 6 条里）。
    ③ 参数面 `--root` / `--face-floor` / `--note-floor` / `--self-test`；未知参数按
       argparse 报错（rc=2）—— 旧版没有参数面，`--self-test` / `--nonsense` 都被静默
       吞掉并打印 ✅ rc=0。
    ④ **判定物与形状一字未动**：IPC 名单 / 类型白名单 / `NoteSource` 禁字段 / 能力位三条 /
       ADR-35 的赋值点与 `resolveSelection` 口径 / 证据脚本指针 —— 本轮只动「㈠㈡ 两条
       扫描面 + 读数 + 空跑防护 + 点名」。

2026-10-14 修（合册 `T-20261013-027` · 原单 `T-20261010-046` · 第 413 轮判据面缺口样本 50）：

    ① **㈠「不存在笔记插件这种独立 target / product」的判定物改成声明星整块解析**：旧正则
       只认 `.target(` / `.testTarget(`、且 `name:` 必须是 `(` 后第一个实参，而本仓 3 个
       target 全是 **`.executableTarget(`**（`Package.swift:77` / `:85` / `:92`），products 里的
       **`.library(`** 从不被枚举 ⇒ 名为 `notes-plugin` 的 executableTarget 与名为
       `NotesPlugin` 的 library product 都判绿（样本 50 的 B / C / D 三臂）。现在按**括号配对**
       取声明星整块（`.target` / `.executableTarget` / `.testTarget` / `.library` /
       `.executable` / `.plugin` 六种），`name:` 不限位置但只认**括号深度 0** 的那一个
       （嵌套 `.product(name: …)` 不算），并**先剥整行注释**（注释里提到不算出现）。
    ② **㈠ 的 IPC 面不再硬编码扫描根**：旧根 `("Core", "App", "CLI", "Plugins/…")` 漏掉
       **编译源根** `Platform/macOS/`（`Package.swift` 的 `path:` 声明星）等 ⇒ 在那里写
       `import XPC` 判绿（样本 50 的 G 臂）。现在直接用**全仓面** `face_swift_files()`
       （与 ㈢ ㈠ 同款、点目录在外）+ 读数 + 同一条 `FACE_FLOOR`；真仓 909 份零命中。
    ③ **负例（FR-ALL-ALL-PLUG-001 此前零覆盖）补在** `Scripts/test-plugin-assembly-gates.py`
       （7 → 11 例）：`executableTarget` 叫 `notes-plugin` / product 叫 `NotesPlugin` /
       `Platform/macOS/` 里写 IPC 三条判红 + 两条对手臂（注释里的提及、嵌套
       `.product(name:)` 不算声明星）。**本门禁自己的 `--self-test` 例数不动**（仍 15）——
       契约层 §6 那一行的跟版归前门（本单边界不许动 `AGENT-SPEC.md`）。
    ④ **判定物本体一字未动**：IPC 名单 / 类型白名单 / `NoteSource` 禁字段 / 能力位三条 /
       ADR-35 口径 / 证据脚本指针 —— 本轮只动「FR-ALL-ALL-PLUG-001 的枚举面 + IPC 面 + 读数 + 负例」。

判据自己的证据：`--self-test` **15 例**（一律在临时夹具树上写坏，真仓零改动）。

用法：
    python3 Scripts/check-plugin-assembly.py                    # 闸门（默认 = 本脚本所在仓）
    python3 Scripts/check-plugin-assembly.py --self-test         # 判据自己的证据
    python3 Scripts/check-plugin-assembly.py --root <树>          # 指定仓根（自检 / 副本用）

退出码：0 = 全过；1 = 有判据不成立（打印文件 / 行号 / 原因）；2 = 用法错（argparse）。
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
# 运行根：默认 = 本脚本所在仓；`--root` 可指到夹具 / 副本（判据自己的证据与成对复跑用）。
ROOT: pathlib.Path = REPO

# FR-ALL-ALL-PLUG-003 ㈠ 的扫描面 = **全仓** `*.swift`（声明就是"全仓"，面就按全仓取）。
# 只排除**点目录**：`.git`（版本库）/ `.build`（构建产物）/ `.worktrees`（工作树副本）
# 都不是"仓里的源码"。`Tests/**` 与 `Vendor/**` **在面内**（它们是仓内真的 Swift 源；
# 本仓 2026-10-14 实测面内命中恰好 1 处 = `Plugins/Notes/Sources/Note.swift` 的
# `NoteDraft.withRowData` ⇒ 全仓口径不误伤）。测试若要构造这枚标痕，用唯一合法入口
# `withRowData()`，或把样本写在仓外（本脚本的 `--self-test` 就是仓外 mkdtemp）。
FACE_FLOOR = 909
# FR-ALL-ALL-PLUG-003 ㈡ 的清单来源：**不复制粘贴**，运行时从隔离门禁源码里读
#（与 `check-notes-offline.py` 的 `_isolation_lists()` 同款）。权威只有那一份。
ISOLATION_GATE = "Scripts/check-note-module-isolation.py"
NOTE_SOURCE_FLOOR = 26          # 隔离门禁 `NOTE_SOURCES` 条数下限（只许涨不许跌）
# "漏登"对账口径：与隔离门禁自己的自维护检查同形（按文件名前缀，两棵树都递归）
NOTE_SOURCE_PREFIXES = ("Note", "AICapture")
NOTE_SOURCE_ROOTS = ("Core", "Plugins/Notes/Sources")

IPC_PATTERNS = [
    (r"\bimport\s+XPC\b", "import XPC"),
    (r"\bNSXPCConnection\b", "NSXPCConnection"),
    (r"\bxpc_connection\b", "xpc_connection"),
    (r"\bxpc_main\b", "xpc_main"),
]


# FR-ALL-ALL-PLUG-001「不存在笔记插件这种独立 target / product」的声明星解析（2026-10-14 ·
# 原单 T-20261010-046 ㈠）：旧实现的正则只认 `.target(` / `.testTarget(`，而本仓 3 个
# target 全是 `.executableTarget(`、products 里的 `.library(` 从不枚举 ⇒ 两条都判绿。
DECL_KINDS = ("target", "executableTarget", "testTarget", "library", "executable", "plugin")
DECL_PATTERN = re.compile(r"\.(" + "|".join(DECL_KINDS) + r")\s*\(")
PLUGIN_NAME = re.compile(r"note|plugin|notebook", re.I)


def manifest_code(manifest: str) -> str:
    """剥掉**整行注释**后的清单正文（与 `code_lines()` 同口径：注释里提的不算出现）。

    判定物因此是"真声明星"，不是"全文里出现过这个串"—— `// 将来也许会有
    .executableTarget(name: "notes-plugin")` 这种注释不判红（对手臂钉住）。
    登记边界：**行尾注释**（`let x = .target(name: "x") // 说明`）仍按声明解析。
    """
    return "\n".join(line for line in manifest.splitlines() if not line.strip().startswith("//"))


def declaration_blocks(manifest: str) -> list[tuple[str, str]]:
    """返回 [(声明星, 整块实参文本)] —— 括号配对；嵌套的 `.product(...)` 也落在块里。"""
    found: list[tuple[str, str]] = []
    for match in DECL_PATTERN.finditer(manifest):
        start = match.end() - 1
        depth, index = 0, start
        while index < len(manifest):
            if manifest[index] == "(":
                depth += 1
            elif manifest[index] == ")":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        found.append((match.group(1), manifest[start + 1:index]))
    return found


def top_level_argument(block: str, key: str) -> str | None:
    """块里括号深度 0 的 `key: "…"` —— 嵌套 `.product(name: …)` 的名字不算本声明的名。"""
    depth = 0
    for match in re.finditer(r"[()]|\b" + key + r":\s*\"([^\"]*)\"", block):
        token = match.group(0)
        if token == "(":
            depth += 1
        elif token == ")":
            depth -= 1
        elif depth == 0:
            return match.group(1)
    return None

problems: list[str] = []
passed: list[str] = []
readings: list[str] = []

_note_sources_cache: list[str] | None = None


def reset_state() -> None:
    """每次 run() 前清干净（同一个进程里既跑闸门又跑自检时不留上一轮的账）。"""
    global _note_sources_cache
    problems.clear()
    passed.clear()
    readings.clear()
    _note_sources_cache = None


def read(relative: str) -> str:
    """读不到就**记一条判红、回空串**（不吐栈）—— 面塌了 / 文件改名时，六组判据各自如实报。"""
    try:
        return (ROOT / relative).read_text(encoding="utf-8")
    except OSError:
        problems.append(f"{relative}: 读不到（改名 / 搬家 / 面塌了？）")
        return ""


def read_path(path: pathlib.Path) -> str:
    """同上，但按**绝对路径**读（`_functions_with_assignments` / ADR-35 那几处已经拿着 Path）。"""
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        problems.append(f"{path.name}: 读不到（改名 / 搬家 / 面塌了？）")
        return ""


def face_swift_files() -> list[pathlib.Path]:
    """㈠ 的面：仓内所有 `*.swift`（点目录在外），仓根相对排序 —— 读数与点名都靠它。"""
    return [
        path
        for path in sorted(ROOT.rglob("*.swift"))
        if not any(part.startswith(".") for part in path.relative_to(ROOT).parts)
    ]


def _isolation_lists() -> dict[str, list[str]]:
    """从隔离门禁源码里读它自己那两份清单（不复制粘贴 —— 副本一定会陈旧）。"""
    text = read(ISOLATION_GATE)
    result: dict[str, list[str]] = {}
    for name in ("NOTE_SOURCES", "ULTRA_SIDE_SOURCES"):
        match = re.search(rf"{name}\s*=\s*\[(.*?)\]", text, re.S)
        result[name] = re.findall(r'"([^"]+\.swift)"', match.group(1)) if match else []
    return result


def note_sources() -> list[str]:
    """㈡ 笔记源清单（运行时读权威那一份）+ 三条钉：空面 / 缩面 / 陈旧 + 漏登反向对账。"""
    global _note_sources_cache
    if _note_sources_cache is not None:
        return _note_sources_cache
    try:
        lists = _isolation_lists()
    except OSError:
        problems.append(f"{ISOLATION_GATE}: 读不到（隔离门禁没了？笔记源清单没有权威来源）")
        _note_sources_cache = []
        return []
    sources = lists.get("NOTE_SOURCES") or []
    ultra = lists.get("ULTRA_SIDE_SOURCES") or []
    if not sources:
        problems.append(f"{ISOLATION_GATE}: 读不到 `NOTE_SOURCES`（或它是空的）—— 面不许静默变成空集")
    if sources and len(sources) < NOTE_SOURCE_FLOOR:
        problems.append(
            f"{ISOLATION_GATE}: `NOTE_SOURCES` 只剩 {len(sources)} 条（下限 {NOTE_SOURCE_FLOOR}）"
            f"—— 少一条就是缩面（要减请同批改本脚本的下限并写明理由）"
        )
    if not ultra:
        problems.append(f"{ISOLATION_GATE}: 读不到 `ULTRA_SIDE_SOURCES` —— 宿主侧落点也要认")
    for relative in sources:
        if not (ROOT / relative).exists():
            problems.append(f"{relative}: 清单里有、盘上没有（改名或搬家了？请同步隔离门禁）")
    listed = set(sources + ultra)
    for root_name in NOTE_SOURCE_ROOTS:
        directory = ROOT / root_name
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*.swift")):
            if not path.name.startswith(NOTE_SOURCE_PREFIXES):
                continue
            relative = path.relative_to(ROOT).as_posix()
            if relative not in listed:
                problems.append(
                    f"{relative}: 是笔记源却两份清单都没登记（漏登 = 这个文件偷偷不受约束）"
                )
    _note_sources_cache = sources
    return sources


def code_lines(relative: str) -> list[tuple[int, str]]:
    """返回 (行号, 内容)，跳过整行注释 —— 注释里提到类型名不算引用。"""
    out: list[tuple[int, str]] = []
    for number, line in enumerate(read(relative).splitlines(), 1):
        if line.strip().startswith("//"):
            continue
        out.append((number, line))
    return out
def record(name: str, found: list[str]) -> None:
    if found:
        problems.extend(f"[{name}] {item}" for item in found)
    else:
        passed.append(name)


# ---------------------------------------------------------------- FR-ALL-ALL-PLUG-001

def check_01_single_process() -> list[str]:
    found: list[str] = []
    # 插件目录也算装配面（2026-10-13 · 概设 §7 P3 搬家后，笔记源文件在 `Plugins/Notes/**`）
    ipc_face = face_swift_files()
    readings.append(f"[FR-ALL-ALL-PLUG-001 ㈠] IPC 面 = 全仓 {len(ipc_face)} 份 Swift 源文件（下限 {FACE_FLOOR}）")
    for path in ipc_face:
        relative = path.relative_to(ROOT).as_posix()
        for number, line in code_lines(relative):
                for pattern, label in IPC_PATTERNS:
                    if re.search(pattern, line):
                        found.append(f"{relative}:{number}: 出现 {label}（同进程装配，不许有 IPC）")
    for relative in note_sources() + ["Plugins/Notes/Views/NotesPanel.swift"]:
        if not (ROOT / relative).exists():
            found.append(f"{relative}: 笔记源文件不存在（装配链断了？）")
    # 不存在"笔记插件"这种独立 target / product —— 按 Package.swift 的**声明星整块**解析
    # （2026-10-14 · 原单 T-20261010-046 ㈠）：`.target` / `.executableTarget` / `.testTarget`
    # / `.library` / `.executable` / `.plugin` 六种声明星都进面，`name:` 不限位置
    # （只认括号深度 0 的那一个）；**整行注释先剥掉**（注释里提不算出现）。
    manifest = manifest_code(read("Package.swift"))
    blocks = declaration_blocks(manifest)
    kinds = "、".join(sorted({kind for kind, _ in blocks}))
    readings.append(f"Package.swift：target/product 声明星 {len(blocks)} 条（{kinds}）")
    for kind, block in blocks:
        name = top_level_argument(block, "name")
        if name and PLUGIN_NAME.search(name):
            role = "product" if kind == "library" else "target"
            found.append(
                f'Package.swift: {kind} "{name}" 看起来是独立插件 {role}'
                "（FR-ALL-ALL-PLUG-001 要求同进程内模块）"
            )
    return found


# ---------------------------------------------------------------- FR-ALL-ALL-PLUG-002

def check_02_visibility() -> list[str]:
    found: list[str] = []
    bar = read("Core/ActivityBar.swift")
    if not re.search(r"^\s*case notes\b", bar, re.M):
        found.append("Core/ActivityBar.swift: 活动栏没有 `case notes`")

    # 判可见性的只有 LicensePresentation 一处：全仓 `ActivityBarItem.allCases` 只许在 Core 里出现。
    for directory in ("App", "CLI"):
        for path in sorted((ROOT / directory).rglob("*.swift")):
            relative = path.relative_to(ROOT).as_posix()
            for number, line in code_lines(relative):
                if "ActivityBarItem.allCases" in line:
                    found.append(
                        f"{relative}:{number}: 视图层自己过滤 allCases 决定可见性 —— "
                        f"可见性判据必须只有 LicensePresentation.activityItems 一处"
                    )
    # 唯一判据：能力位 -> 是否显示笔记（不是灰掉、不是另写一个条件）
    presentation = read("Core/LicensePresentation.swift")
    if not re.search(r"case \.notes:\s*return capabilities\.contains\(\.notes\)", presentation):
        found.append("Core/LicensePresentation.swift: 笔记项的可见性不再是 capabilities.contains(.notes)")
    if len(re.findall(r"ActivityBarItem\.allCases\.filter", presentation)) != 1:
        found.append("Core/LicensePresentation.swift: 能力位过滤 allCases 的地方不再是恰好一处")

    # App 侧的"该显示哪几项"只有一条来源。
    app_state = read("App/AppState.swift")
    # 2026-10-12（契约 §3.52④ 挂点判据）：调用形态允许带**挂点参数**
    # —— `activityItems(for:mounts:)` 仍是同一个唯一判据，只是多了"插件在不在"这一半；
    # 断言因此匹配到实参开头（不带右括号），否则合法实现会被判红。
    if "LicensePresentation.activityItems(for: licenseCapabilities" not in app_state:
        found.append("App/AppState.swift: visibleActivityItems 不再走 LicensePresentation.activityItems")
    if len(re.findall(r"var visibleActivityItems\b", app_state)) != 1:
        found.append("App/AppState.swift: visibleActivityItems 定义不唯一")
    return found


# ---------------------------------------------------------------- FR-ALL-ALL-PLUG-003

def check_03_one_way_context() -> list[str]:
    found: list[str] = []
    capture = read("Core/AICapture.swift")

    # 笔记侧入口只收文本与标识（类型白名单：String / [String] 及其可选）。
    allowed_types = {"String", "String?", "[String]", "[String]?"}
    for signature_name in ("skillNote", "sqlNote"):
        match = re.search(rf"public static func {signature_name}\((.*?)\)\s*->", capture, re.S)
        if not match:
            found.append(f"Core/AICapture.swift: 找不到 {signature_name} 的签名（改名了？）")
            continue
        for parameter in match.group(1).split(","):
            if ":" not in parameter:
                continue
            type_name = " ".join(parameter.split(":", 1)[1].split("=", 1)[0].split())
            if type_name not in allowed_types:
                found.append(
                    f"Core/AICapture.swift: {signature_name} 的参数类型 {type_name} 不在白名单 "
                    f"{sorted(allowed_types)}（只许文本与标识）"
                )

    # 行数据开关：全仓只有一处能打开，且没有"撤回"入口。
    # 面 = face_swift_files()（真·全仓口径，见文件头 ①）；报名字面量随之改"真文件:行号"。
    face = face_swift_files()
    readings.append(f"[FR-ALL-ALL-PLUG-003 ㈠] 面内 {len(face)} 份 Swift 源文件（全仓口径 · 下限 {FACE_FLOOR}）")
    if len(face) < FACE_FLOOR:
        found.append(
            f"扫描面只剩 {len(face)} 份 Swift 源文件（下限 {FACE_FLOOR}）"
            f"—— 面塌了：先查仓根 / 目录改名（旧版把面塌到 0 份也照打 ✅）"
        )
    open_hits: list[str] = []
    withdraw_hits: list[str] = []
    for path in face:
        relative = path.relative_to(ROOT).as_posix()
        for number, line in code_lines(relative):
            if re.search(r"rowDataConfirmed\s*=\s*true", line):
                open_hits.append(
                    f"{relative}:{number}: 打开\"含行数据\"（全仓必须恰好 1 处：NoteDraft.withRowData）"
                )
            if re.search(r"func\s+(withoutRowData|clearRowData|unsetRowData)\b", line):
                withdraw_hits.append(
                    f"{relative}:{number}: 撤回\"含行数据\"标痕的入口（留痕必须不可撤回）"
                )
    if len(open_hits) != 1:
        found.append(
            f"全仓打开\"含行数据\"的地方有 {len(open_hits)} 处（必须恰好 1 处：NoteDraft.withRowData）"
        )
        found.extend(open_hits)
    found.extend(withdraw_hits)

    # 笔记源清单：本脚本不再维护第二份副本 ⇒ 运行时读权威那一份（空面 / 缩面 / 陈旧 / 漏登四钉在
    # note_sources() 里），读数把"面有多宽"打出来（旧版面 6 份时不声不响）。
    sources = note_sources()
    readings.append(
        f"[FR-ALL-ALL-PLUG-003 ㈡] 笔记源清单 {len(sources)} 份"
        f"（运行时读自 {ISOLATION_GATE} · 下限 {NOTE_SOURCE_FLOOR}）"
    )

    # 来源只记连接名：不存口令 / 连接串 / 主机字段。
    source_block = re.search(r"public struct NoteSource\b.*?\n}\n", read("Plugins/Notes/Sources/Note.swift"), re.S)
    if not source_block:
        found.append("Plugins/Notes/Sources/Note.swift: 找不到 NoteSource 定义")
    else:
        for banned in ("password", "connectionString", "dsn", "uri"):
            if re.search(rf"\b{banned}\b", source_block.group(0), re.I):
                found.append(f"Plugins/Notes/Sources/Note.swift: NoteSource 里出现 {banned}（来源只许连接名字）")

    # 笔记侧文件不引用结果行类型。
    for relative in note_sources():
        for number, line in code_lines(relative):
            for banned in ("ResultRow", "QueryResult", "EffectRow"):
                if re.search(rf"\b{banned}\b", line):
                    found.append(f"{relative}:{number}: 引用了结果行类型 {banned}")
    return found


# ---------------------------------------------------------------- FR-ALL-ALL-PLUG-006

def check_06_one_license() -> list[str]:
    found: list[str] = []
    license_source = read("Core/License.swift")
    if not re.search(
        r"static let all:\s*LicenseCapabilities\s*=\s*\[\.workspaces,\s*\.database,\s*\.notes\]",
        license_source,
    ):
        found.append("Core/License.swift: `LicenseCapabilities.all` 不再是三个能力位")
    bits = re.findall(r"static let (workspaces|database|notes)\s*=\s*LicenseCapabilities\(rawValue:\s*1\s*<<\s*(\d+)\)", license_source)
    if sorted(int(bit) for _, bit in bits) != [0, 1, 2]:
        found.append(f"Core/License.swift: 能力位不是恰好三位 {bits}")
    # 没有"插件单独授权"这种东西。
    for pattern in (r"static let\s+(notes|plugin)\w*License", r"var\s+isPluginEnabled", r"LicenseEdition\.\w*plugin"):
        if re.search(pattern, license_source, re.I):
            found.append(f"Core/License.swift: 出现插件独立授权痕迹（{pattern}）—— 一套许可三能力位，不做独立开关")
    if not re.search(r"case \.pro:\s*return \[\.workspaces,\s*\.database\]", license_source):
        found.append("Core/License.swift: Pro 档不再等于「工作区 + 数据库」（档位必须由能力位推导）")
    if not re.search(r"case \.standard:\s*return \.notesOnly", license_source):
        found.append("Core/License.swift: Standard 档不再等于「只有笔记」")
    return found


# ---------------------------------------------------------------- ADR-35

def _functions_with_assignments(path: pathlib.Path, needle: str) -> tuple[list[tuple[int, str]], list[str]]:
    """返回 (赋值点列表, 每个赋值点所在函数体里**没**出现 resolveSelection 的说明)。"""
    text = read_path(path)
    lines = text.splitlines()
    assignment = re.compile(rf"(?<![\w.]){needle}\s*=(?!=)")
    declaration = re.compile(rf"\bvar\s+{needle}\b")
    assignments: list[tuple[int, str]] = []
    missing_guard: list[str] = []
    for index, line in enumerate(lines, 1):
        if line.strip().startswith("//"):
            continue
        if declaration.search(line) or not assignment.search(line):
            continue
        assignments.append((index, line.strip()))
        # 往上找最近的 `func`，往下按花括号深度取到函数结束。
        start = index - 1
        while start >= 0 and not re.search(r"\bfunc\s+\w+", lines[start]):
            start -= 1
        depth = 0
        end = index - 1
        for cursor in range(start, len(lines)):
            depth += lines[cursor].count("{") - lines[cursor].count("}")
            if cursor > start and depth <= 0:
                end = cursor
                break
        body = "\n".join(lines[start:end + 1])
        function_name = "<未知>"
        if start >= 0:
            function_match = re.search(r"\bfunc\s+(\w+)", lines[start])
            if function_match:
                function_name = function_match.group(1)
        if "LicensePresentation.resolveSelection" not in body:
            missing_guard.append(
                f"{path.name}:{index}: 函数 {function_name}() 直接改了 {needle} 而没过 resolveSelection"
            )
    return assignments, missing_guard


def check_adr35_single_write_entry() -> list[str]:
    found: list[str] = []
    app_state = ROOT / "App/AppState.swift"
    if not re.search(
        r"@Published\s+private\(set\)\s+var\s+selectedActivityItem", read_path(app_state)
    ):
        found.append("App/AppState.swift: selectedActivityItem 不再是 private(set)（写入口会多起来）")

    assignments, missing_guard = _functions_with_assignments(app_state, "selectedActivityItem")
    found.extend(missing_guard)
    if not assignments:
        found.append("App/AppState.swift: 找不到任何 selectedActivityItem 赋值（改名了？）")

    for path in sorted((ROOT / "App").rglob("*.swift")):
        if path.name == "AppState.swift":
            continue
        for number, line in code_lines(path.relative_to(ROOT).as_posix()):
            if re.search(r"selectedActivityItem\s*=(?!=)", line):
                found.append(
                    f"{path.relative_to(ROOT)}:{number}: 在视图 / 命令层直接改了选中项 —— "
                    f"必须走 AppState.selectActivityItem"
                )
    return found


# ---------------------------------------------------------------- 指向别的门禁

def check_pointers() -> list[str]:
    """本轮不重复跑的两条：它们各有自己的脚本，这里只确认指针没断。"""
    found: list[str] = []
    for relative in ("Scripts/check-note-module-isolation.py", "Scripts/test-note-data-boundary.sh"):
        if not (ROOT / relative).exists():
            found.append(f"{relative}: 被引用的证据脚本不存在（FR-ALL-ALL-PLUG-004 / 07 的指针断了）")
    return found


def run() -> int:
    reset_state()
    record("FR-ALL-ALL-PLUG-001 同进程内模块（无 IPC / 无独立插件 target）", check_01_single_process())
    record("FR-ALL-ALL-PLUG-002 可见性单一判据（未授权不出现）", check_02_visibility())
    record("FR-ALL-ALL-PLUG-003 单向上下文（只传文本与标识 / 行数据显式留痕）", check_03_one_way_context())
    record("FR-ALL-ALL-PLUG-006 一套许可三能力位（无插件独立授权）", check_06_one_license())
    record("ADR-35 单一判据 + 单一写入口", check_adr35_single_write_entry())
    record("证据脚本指针（FR-ALL-ALL-PLUG-004 / 07）", check_pointers())

    for line in readings:
        print(line)
    if problems:
        print(f"❌ 插件装配链门禁失败（{len(problems)} 条）：")
        for item in problems:
            print("   " + item)
        return 1
    for name in passed:
        print(f"✅ {name}")
    print(f"✅ 插件装配链门禁通过（{len(passed)} 组判据）")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="插件装配链门禁（Scripts/check-plugin-assembly.py）")
    parser.add_argument("--root", default=None, help="仓根（默认 = 本脚本所在仓）")
    parser.add_argument("--face-floor", type=int, default=None, help="㈠ 面内 Swift 份数下限（默认 = 本仓实测值）")
    parser.add_argument("--note-floor", type=int, default=None, help="㈡ 笔记源清单条数下限（默认 = 本仓实测值）")
    parser.add_argument("--self-test", action="store_true", help="判据自己的证据（临时夹具树上写坏）")
    return parser


def main() -> int:
    global ROOT, FACE_FLOOR, NOTE_SOURCE_FLOOR
    args = build_parser().parse_args()
    if args.self_test:
        return run_self_test()
    ROOT = pathlib.Path(args.root).expanduser().resolve() if args.root else REPO
    if args.face_floor is not None:
        FACE_FLOOR = args.face_floor
    if args.note_floor is not None:
        NOTE_SOURCE_FLOOR = args.note_floor
    return run()


FIXTURE_ISOLATION = """NOTE_SOURCES = [
    "Plugins/Notes/Sources/Note.swift",
    "Plugins/Notes/Sources/NoteBody.swift",
    "Core/License.swift",
    "Core/AICapture.swift",
    "Core/AICaptureIntake.swift",
    "Core/Todo.swift",
]
ULTRA_SIDE_SOURCES = [
    "Core/AICaptureUltra.swift",
]
"""

# 夹具树（最小可绿）：文件内容只求"六组判据都过"，不求像真源码。
FIXTURE_FILES = {
    "Package.swift": '// swift-tools-version:5.9\nlet package = Package(name: "Fixture", targets: [.target(name: "App")])\n',
    "App/AppState.swift": (
        "import Foundation\n\n"
        "final class AppState {\n"
        "    @Published private(set) var selectedActivityItem: ActivityBarItem = .workspaces\n"
        "    private var licenseCapabilities: LicenseCapabilities = .all\n"
        "    var visibleActivityItems: [ActivityBarItem] {\n"
        "        LicensePresentation.activityItems(for: licenseCapabilities, mounts: [])\n"
        "    }\n"
        "\n"
        "    func selectActivityItem(_ item: ActivityBarItem) {\n"
        "        selectedActivityItem = LicensePresentation.resolveSelection(item) ?? .workspaces\n"
        "    }\n"
        "}\n"
    ),
    "Core/ActivityBar.swift": (
        "enum ActivityBarItem {\n"
        "    case workspaces\n"
        "    case database\n"
        "    case notes\n"
        "}\n"
    ),
    "Core/LicensePresentation.swift": (
        "enum LicensePresentation {\n"
        "    static func activityItems(for capabilities: LicenseCapabilities, mounts: [String]) -> [ActivityBarItem] {\n"
        "        return ActivityBarItem.allCases.filter { isVisible($0, capabilities) }\n"
        "    }\n"
        "    static func isVisible(_ item: ActivityBarItem, _ capabilities: LicenseCapabilities) -> Bool {\n"
        "        switch item {\n"
        "        case .notes: return capabilities.contains(.notes)\n"
        "        default: return true\n"
        "        }\n"
        "    }\n"
        "    static func resolveSelection(_ item: ActivityBarItem) -> ActivityBarItem? { item }\n"
        "}\n"
    ),
    "Core/License.swift": (
        "public struct LicenseCapabilities: OptionSet {\n"
        "    public let rawValue: Int\n"
        "    public init(rawValue: Int) { self.rawValue = rawValue }\n"
        "    public static let workspaces = LicenseCapabilities(rawValue: 1 << 0)\n"
        "    public static let database = LicenseCapabilities(rawValue: 1 << 1)\n"
        "    public static let notes = LicenseCapabilities(rawValue: 1 << 2)\n"
        "    public static let all: LicenseCapabilities = [.workspaces, .database, .notes]\n"
        "}\n"
        "public enum LicenseEdition {\n"
        "    case pro, standard\n"
        "    public var capabilities: LicenseCapabilities {\n"
        "        switch self {\n"
        "        case .pro: return [.workspaces, .database]\n"
        "        case .standard: return .notesOnly\n"
        "        }\n"
        "    }\n"
        "}\n"
    ),
    "Core/AICapture.swift": (
        "public struct AICapture {\n"
        "    public static func skillNote(title: String, body: String) -> NoteDraft { NoteDraft() }\n"
        "    public static func sqlNote(tag: String, sql: String) -> NoteDraft { NoteDraft() }\n"
        "}\n"
    ),
    "Core/AICaptureIntake.swift": "public struct AICaptureIntake { public let id: String }\n",
    "Core/AICaptureUltra.swift": "public struct AICaptureUltra { public let id: String }\n",
    "Core/Todo.swift": "public struct Todo { public let id: String }\n",
    "Plugins/Notes/Sources/Note.swift": (
        "public struct NoteSource {\n"
        "    public let connectionName: String\n"
        "}\n"
        "\n"
        "public struct NoteDraft {\n"
        "    public var rowDataConfirmed = false\n"
        "\n"
        "    public func withRowData() -> NoteDraft {\n"
        "        var copy = self\n"
        "        copy.rowDataConfirmed = true\n"
        "        return copy\n"
        "    }\n"
        "}\n"
    ),
    "Plugins/Notes/Sources/NoteBody.swift": "public struct NoteBody { public let text: String }\n",
    "Plugins/Notes/Views/NotesPanel.swift": "struct NotesPanel {}\n",
}

FIXTURE_SWIFT_COUNT = 12        # 夹具面内份数（FIXTURE_FILES 的 `.swift` 件 + Package.swift —— 它也是 rglob("*.swift") 的命中）
FIXTURE_NOTE_FLOOR = 6          # FIXTURE_ISOLATION 里 NOTE_SOURCES 的条数（夹具的 --note-floor）
# 新代码的标记：历史版本里**没有**它 ⇒ 按它认出"旧码"（`HEAD^` 这种指法在下一笔提交后就失效）
NEW_MARKER = "NOTE_SOURCE_FLOOR"


def old_code_text() -> str | None:
    """取"上一版"门禁源码：从历史里找第一份**不含新标记**的版本。

    用 `HEAD^` 会在**下一笔提交**之后指到已经改好的版本 ⇒ 那个"旧码对照臂"自己变成假红
    （另见本轮上报的跨单缺陷）。这里按内容认版本，跟着历史走。
    """
    listed = subprocess.run(
        ["git", "log", "--format=%H", "-n", "8", "--", "Scripts/check-plugin-assembly.py"],
        cwd=str(REPO), capture_output=True, text=True,
    )
    if listed.returncode != 0:
        return None
    for sha in listed.stdout.split():
        shown = subprocess.run(
            ["git", "show", f"{sha}:Scripts/check-plugin-assembly.py"],
            cwd=str(REPO), capture_output=True, text=True,
        )
        if shown.returncode == 0 and NEW_MARKER not in shown.stdout:
            return shown.stdout
    return None
def run_self_test() -> int:
    script = pathlib.Path(__file__).resolve()
    before = hashlib.sha256(script.read_bytes()).hexdigest()
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="cpa-selftest-"))
    total = 0
    failures: list[str] = []

    def invoke(where, extra=()):
        command = [sys.executable, str(script)]
        if where is not None:
            command += ["--root", str(where)]
        command += list(extra)
        completed = subprocess.run(command, cwd=str(scratch), capture_output=True, text=True)
        return completed.returncode, completed.stdout + completed.stderr

    def write(where: pathlib.Path, relative: str, text: str) -> None:
        target = where / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def fixture(name: str, isolation: str = FIXTURE_ISOLATION) -> pathlib.Path:
        where = scratch / name
        for relative, text in FIXTURE_FILES.items():
            write(where, relative, text)
        write(where, ISOLATION_GATE, isolation)
        write(where, "Scripts/test-note-data-boundary.sh", "#!/bin/sh\nexit 0\n")
        return where

    GREEN = ("--face-floor", str(FIXTURE_SWIFT_COUNT), "--note-floor", str(FIXTURE_NOTE_FLOOR))

    def red(where, extra=(), needle=""):
        code, output = invoke(where, extra)
        if code == 0:
            return f"仍 rc=0（该判红）\n{output[-300:]}"
        if needle and needle not in output:
            return f"判红了但没点名 {needle!r}\n{output[-300:]}"
        return None

    def case(description: str, check) -> None:
        nonlocal total
        total += 1
        problem = check()
        if problem:
            failures.append(f"例 {total} 失败：{description} —— {problem}")

    # 例 1：真仓正例 —— rc=0 + 两个读数（面内份数 / 清单份数）都在
    def check_positive():
        code, output = invoke(None)
        if code != 0:
            return f"真仓实跑不是绿（rc={code}）\n{output[-400:]}"
        for needle in ("面内", "全仓口径", "笔记源清单"):
            if needle not in output:
                return f"没打扫描面读数（缺 {needle}）\n{output[-300:]}"
        return None
    case("真仓正例：rc=0 + 打印「面内 N 份 Swift 源文件」与「笔记源清单 N 份」", check_positive)

    # 例 2：夹具正例 —— 最小可绿树 rc=0，读数 = 夹具实测份数
    def check_fixture_green():
        where = fixture("green")
        code, output = invoke(where, GREEN)
        if code != 0:
            return f"夹具本该全绿（rc={code}）\n{output[-400:]}"
        if f"面内 {FIXTURE_SWIFT_COUNT} 份" not in output:
            return f"面读数不对\n{output[-300:]}"
        if f"笔记源清单 {FIXTURE_NOTE_FLOOR} 份" not in output:
            return f"清单读数不对\n{output[-300:]}"
        return None
    case("夹具正例：最小可绿树 rc=0，读数 = 面内 12 份 / 清单 6 份", check_fixture_green)

    # 例 3：㈠ 面外（旧面整体漏掉的位置）—— App/ 下开开关 ⇒ 判红点名真文件:行号
    def check_app_planted():
        where = fixture("planted-app")
        write(where, "App/Planted.swift", "import Foundation\n\nfunc planted() { copy.rowDataConfirmed = true }\n")
        return red(where, GREEN, "App/Planted.swift:3")
    case("㈠ 面外：`App/` 里开开关 ⇒ 判红点名 `App/Planted.swift:3`（旧面 rc=0）", check_app_planted)

    # 例 4：㈠ 面外·子目录（2026-10-13 搬家后的同形缺陷）
    def check_subdir_planted():
        where = fixture("planted-subdir")
        write(where, "Plugins/Notes/Sources/NoteStorage/Planted.swift",
              "import Foundation\n\nfunc planted() { copy.rowDataConfirmed = true }\n")
        return red(where, GREEN, "Plugins/Notes/Sources/NoteStorage/Planted.swift:3")
    case("㈠ 面外·子目录：`NoteStorage/` 里开开关 ⇒ 判红点名真路径（旧面非递归 ⇒ rc=0）", check_subdir_planted)

    # 例 5：㈠ 面内回归对照 —— 旧面也盖到的位置照旧判红（不是本轮新误差）
    def check_core_planted():
        where = fixture("planted-core")
        write(where, "Core/Planted.swift", "import Foundation\n\nfunc planted() { copy.rowDataConfirmed = true }\n")
        return red(where, GREEN, "Core/Planted.swift:3")
    case("㈠ 面内回归：`Core/` 顶层同一负例照旧判红（两版同红）", check_core_planted)

    # 例 6：㈠ 撤回入口（旧面外）
    def check_withdraw():
        where = fixture("withdraw-app")
        write(where, "App/WithdrawPlanted.swift", "import Foundation\n\nfunc clearRowData() {}\n")
        return red(where, GREEN, "App/WithdrawPlanted.swift:3")
    case("㈠ 撤回入口：`App/` 里 `func clearRowData()` ⇒ 判红点名（旧面 rc=0）", check_withdraw)

    # 例 7：㈠ 空跑防护 —— 面塌到 0 份（旧版照打 ✅）
    def check_floor_collapse():
        where = fixture("floor-collapse")
        for path in sorted(where.rglob("*.swift")):
            if path.name != "Package.swift":
                path.unlink()
        return red(where, (), "扫描面只剩 1 份")
    case("㈠ 空跑防护：面收剩 1 份 ⇒ 判红点名下限（旧版照打 ✅；用默认下限 909）", check_floor_collapse)

    # 例 8：㈠ 下限真的会咬 —— 面内 10 份、下限写 11 ⇒ 判红
    def check_floor_bites():
        where = fixture("floor-bites")
        return red(where, ("--face-floor", str(FIXTURE_SWIFT_COUNT + 1), "--note-floor", str(FIXTURE_NOTE_FLOOR)),
                   "下限 13")
    case("㈠ 下限会咬：面内 12 份 + 下限 13 ⇒ 判红（棘轮不是摆设）", check_floor_bites)

    # 例 9：㈡ 清单来自运行时读取 —— 登在权威清单里的笔记源（旧本地副本 6 条里没有它）照扫
    def check_notebook_result_row():
        isolation = FIXTURE_ISOLATION.replace(
            '    "Core/Todo.swift",',
            '    "Core/Todo.swift",\n    "Plugins/Notes/Sources/Notebook.swift",')
        where = fixture("notebook-result-row", isolation=isolation)
        write(where, "Plugins/Notes/Sources/Notebook.swift",
              "import Foundation\n\nfunc planted(_ r: ResultRow) {}\n")
        return red(where, GREEN, "Plugins/Notes/Sources/Notebook.swift:3")
    case("㈡ 清单运行时读取：`Notebook.swift` 引 `ResultRow` ⇒ 判红点名（旧副本里没这条 ⇒ rc=0）",
         check_notebook_result_row)

    # 例 10：㈡ 漏登 —— 盘上是笔记源、两份清单都不认 ⇒ 判红
    def check_unlisted_note_source():
        where = fixture("unlisted-note-source")
        write(where, "Plugins/Notes/Sources/Notebook.swift", "public struct Notebook { public let id: String }\n")
        return red(where, GREEN, "两份清单都没登记")
    case("㈡ 漏登：`Notebook.swift` 在盘上却两份清单都没登记 ⇒ 判红（旧码静默）", check_unlisted_note_source)

    # 例 11：㈡ 陈旧 —— 清单里写着、盘上没有 ⇒ 判红
    def check_stale_entry():
        isolation = FIXTURE_ISOLATION.replace(
            '    "Core/Todo.swift",', '    "Core/Todo.swift",\n    "Core/Ghost.swift",')
        where = fixture("stale-entry", isolation=isolation)
        return red(where, GREEN, "Core/Ghost.swift")
    case("㈡ 陈旧：清单里多一条盘上没有的件 ⇒ 判红点名（旧码零对账）", check_stale_entry)

    # 例 12：㈡ 空清单 —— 不许静默把面收成空集
    def check_empty_list():
        isolation = 'NOTE_SOURCES = []\nULTRA_SIDE_SOURCES = [\n    "Core/AICaptureUltra.swift",\n]\n'
        where = fixture("empty-list", isolation=isolation)
        return red(where, GREEN, "空集")
    case("㈡ 空清单：`NOTE_SOURCES = []` ⇒ 判红（旧码把面缩成空还打 ✅）", check_empty_list)

    # 例 13：㈡ 缩面 —— 清单条数跌破下限 ⇒ 判红（只许涨不许跌）
    def check_note_floor():
        isolation = ('NOTE_SOURCES = [\n    "Plugins/Notes/Sources/Note.swift",\n    "Core/License.swift",\n]\n'
                     'ULTRA_SIDE_SOURCES = [\n    "Core/AICaptureUltra.swift",\n]\n')
        where = fixture("note-floor", isolation=isolation)
        return red(where, GREEN, "下限 6")
    case("㈡ 缩面：清单只剩 2 条（下限 6）⇒ 判红点名下限", check_note_floor)

    # 例 14：旧码对照 —— 同一负例（面外位置）旧码 rc=0（假绿现场）
    def check_old_code():
        old = old_code_text()
        if old is None:
            return "取不到上一版源码（git 历史里没有不含新标记的版本）"
        where = fixture("old-code")
        write(where, "App/Planted.swift", "import Foundation\n\nfunc planted() { copy.rowDataConfirmed = true }\n")
        write(where, "Scripts/check-plugin-assembly.py", old)
        completed = subprocess.run([sys.executable, str(where / "Scripts/check-plugin-assembly.py")],
                                   cwd=str(where), capture_output=True, text=True)
        if completed.returncode != 0:
            return f"旧码不是假绿（rc={completed.returncode}）—— 对照臂不成立\n{(completed.stdout + completed.stderr)[-300:]}"
        return None
    case("旧码对照：同一负例（`App/` 里开开关）旧码 rc=0（假绿现场）", check_old_code)

    # 例 15：用法错 rc=2 + 真仓逐字节未变 + 真仓实跑 rc=0
    def check_usage_and_repo_untouched():
        where = fixture("unknown-arg")
        code, _ = invoke(where, ("--nonsense",))
        if code != 2:
            return f"未知参数没有 rc=2（rc={code}）"
        if hashlib.sha256(script.read_bytes()).hexdigest() != before:
            return "自检改动了真仓库的脚本"
        code, output = invoke(None)
        if code != 0:
            return f"真仓实跑不是绿（rc={code}）\n{output[-300:]}"
        return None
    case("未知参数 ⇒ rc=2（旧版静默吞掉、rc=0）+ 真仓脚本逐字节未变 + 真仓 rc=0", check_usage_and_repo_untouched)

    shutil.rmtree(scratch, ignore_errors=True)
    for failure in failures:
        print(f"   ❌ {failure}")
    print(f"判据自检：{total} 条中 {total - len(failures)} 条达到预期")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
