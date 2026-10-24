#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**模型服务预设只有一个出处，界面只许消费它**（队列 `L-146`，闭环第 9 项）。

**为什么有它**：需求提出者 2026-09-30 内测原话「AI 助理配置时应该提供主流大模型配置 url
和可选择模型，毕竟很多人是不懂的」。这件事有两个**不会报错的坏法**：

1. 界面自己写死一个端点（面板里的默认值、某个视图里的常量、提示串里的真地址）——
   于是「端点只改一处」当场不成立，而编译照过、单测照绿；
2. 目录长在 Core 里、**界面却没接上**（或者接了提供商、没接模型下拉）——
   功能看起来做了，用户打开面板还是两个空框。

判据：

- **A 唯一出处**：提供商宿主名（**从 `Core/AgentProviderPreset.swift` 里解析出来**，不手抄一份）
  在**产品源面**内只许出现在那个文件里（面 = `SCAN_DIRS`：`App/` / `Core/` / `Platform/` / `CLI/`，
  除目录文件与语言表）命中即判红，逐处点名 `文件:行号`。**面外不判、但必须记账**：白名单以外的
  每一份 `.swift` 都进面外读数；面外命中**逐条登记理由**，未登记 / 死登记 / 陈旧登记 / 登记被掏空
  四种都判红（否则「声明是全仓唯一、面只有四根」就是一道静默缺口 —— 那条老账的由来）。
- **B 界面接线**：`App/Views/AgentSettingsSheet.swift` 必须真的消费目录 ——
  ① 提供商下拉遍历 `AgentProviderCatalog.all` ② 选中值 = 稳定标识（`.tag(preset.id)`）
  ③ 模型下拉内容取自契约层（`modelOptions(currentModel: model)`）
  ④ `.task` 里按端点**恢复选中**（重开面板不许落回自定义）
  ⑤ 选提供商 ⇒ 自动填端点与模型（`applyProvider(` 定义在位）。
- **C 形状**：标识唯一 / 端点唯一（归一化后）/ 「自定义」恰一条且端点为**空**、模型清单为空 /
  条数下限 / 每条 `labelKey` 都在语言表里有中英两条非空 / 目录靠 `all[all.count - 1]` 认「最后一条」。
- **D 空跑防护**：扫描文件数 / 预设条数 / 宿主名数三条下限（正则失配 ⇒ 零命中 ⇒ 假绿，
  这是这类判据最经典的坏法）。
- **判据自己的证据**：`--self-test`（**15 例**：8 例旧形状 + 7 例面边界 / 面外台账 / 真仓静态臂）。

**与 Core 单测的分工（如实登记）**：`Tests/AgentProviderPresetTests.swift` 判**类型行为**
（端点匹配、模型下拉内容、本地判定同源、不许有凭据字段）；本判据判**盘上源码的形状**
（端点有没有第二个主人、界面有没有接上）—— 后者单测看不见。两处**故意有一处重叠**
（标识 / 端点唯一）：单测管「运行时是真唯一」，这里管「改了源码但没跑单测也拦得住」。

**边界（如实登记 · 规则式，不再是枚举式）**：面 = `SCAN_DIRS` 常量白名单（产品源面）；
**白名单以外的每一份 `.swift` 都进面外读数**（隐藏目录与构建产物目录除外 —— `.git` / `.build*` /
`.backups` / `DerivedData` / `build` / `node_modules`）。面外**当前命中的两份**（`Tests/` 下的单测
夹具，要拿真端点当输入才有得判）逐条登记在 `OUT_OF_FACE_LEDGER`：面外新增命中而不登记 ⇒ 判红，
登记指到不在盘的文件 / 登记的那份已不再命中 / 登记被清空 ⇒ 也都判红。`Docs/` 里引一句地址是叙述
不是实现（且 `Docs/` 无 `.swift`）。这条判据也不管**模型名新旧**（服务商上新比本仓发版快，
清单是起点不是白名单，用户永远可以自己填）。

用法：
    python3 Scripts/check-agent-provider-presets.py              # 人读结论，失败非零退出
    python3 Scripts/check-agent-provider-presets.py --json       # 机器读
    python3 Scripts/check-agent-provider-presets.py --root <树>  # 负例验证用（临时副本）
    python3 Scripts/check-agent-provider-presets.py --self-test  # 负例自检（临时副本上写坏）
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9，`X | None` 这类注解需要它

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parent.parent

OWNER = "Core/AgentProviderPreset.swift"
SHEET = "App/Views/AgentSettingsSheet.swift"
LANGUAGE = "Core/Localization.swift"

SCAN_DIRS = ("App", "Core", "Platform", "CLI")
SKIP_FILES = {OWNER, LANGUAGE}

# 面外：白名单以外的每一份 `.swift` 都进读数（隐藏目录与构建产物目录除外 —— 盘上有
# `.build-agent-*` 这类一打构建缓存，它们不是源码面）。面外**命中必须逐条登记理由**。
EXCLUDE_DIR_PARTS = (".git", ".build", ".build-agent", ".backups", ".worktrees",
                     "DerivedData", "build", "node_modules")

# 面外命中台账（路径 → 理由）。三条棘轮：① 盘上命中不在表里 ⇒ 判红 ② 表里的路径不在盘上 ⇒ 判红（死登记）
# ③ 表里的路径已不再命中 / 已被收进面内 ⇒ 判红（陈旧登记，请销账）。清空整表也判红。
OUT_OF_FACE_LEDGER = {
    "Tests/AgentProviderPresetTests.swift": (
        "单测夹具：判「端点匹配 / 模型下拉内容 / 本地判定同源」必须拿真端点当输入，"
        "没有真地址这条单测判不了（= 老 :34 那条豁免的落地形态）"),
    "Tests/AgentProfileTests.swift": (
        "单测夹具：档案（profile）合并 / 覆盖 / 掩码三组断言要以真端点串作输入，"
        "换成假地址就判不出「模型与端点是否一起被覆盖」—— 逐条登记，不整目录豁免"),
    "Tests/LLMStreamingAuthTests.swift": (
        "单测夹具：流式鉴权要按真实宿主名分派头（x-api-key / Authorization），"
        "宿主名本身是被断言的输入之一"),
    "TestsUISnapshot/AgentChatTUILookProbeTests.swift": (
        "界面探针夹具：消息头里显示的服务商名来自 profile 的端点，探针要照真名渲染才拍得出对照图"),
    "Tests/EgressLogTests.swift": (
        "单测夹具：出网日志要有一条真 URL 才造得出日志（同一个理由，逐条登记而不是整目录豁免）"),
}
MIN_OUT_OF_FACE_LEDGER = 2

# 目录里每一行的**规整形状**（一行一条）—— 解析不到就判红，不做模糊匹配。
PRESET_LINE = re.compile(
    r'AgentProviderPreset\(\s*id:\s*"([^"]+)",\s*labelKey:\s*\.([A-Za-z0-9_]+),\s*'
    r'endpoint:\s*"([^"]*)",\s*models:\s*\[([^\]]*)\]\s*\)'
)
CONSTRUCTOR = re.compile(r"AgentProviderPreset\(id:")
LABEL_KEY = re.compile(r"\bcase\s+(agentProvider[A-Za-z0-9_]+)\b")
LABEL_ENTRY = re.compile(
    r'\.(agentProvider[A-Za-z0-9_]+):\s*\[\s*\.simplifiedChinese:\s*"([^"]*)",\s*'
    r'\.english:\s*"([^"]*)"\s*\]'
)
HOST = re.compile(r"https?://([A-Za-z0-9_.\-]+)")
MODEL_LITERAL = re.compile(r'"([^"]*)"')

CUSTOM_ID = "custom"
MIN_PRESETS = 12
MIN_SCANNED_FILES = 300   # 实测 340（2026-10-14，`App+Core+Platform+CLI` 减 2 份豁免）
MIN_HOSTS = 10

# 环回 / 通配地址**不算提供商宿主名**：本机服务满仓都是它们（SSH 隧道、连接默认值、CLI 冒烟），
# 拿它当标识会红一片而把真问题埋掉。A 判的是「公网提供商地址有没有第二个主人」。
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "0.0.0.0", "::1"}

# 「最后一条是自定义」这个约定必须真在源码里（界面 / 匹配都靠它取 custom）。
LAST_ENTRY_ANCHOR = "all[all.count - 1]"

# 界面接线的五处锚点（少一处就判红 —— 「接了提供商没接模型下拉」正是要拦的那种半成品）。
SHEET_ANCHORS = (
    ("提供商下拉遍历目录", r"ForEach\(AgentProviderCatalog\.all\)"),
    ("选中值 = 稳定标识", r"\.tag\(preset\.id\)"),
    ("模型下拉内容取自契约层", r"modelOptions\(currentModel:\s*model\)"),
    ("重开面板按端点恢复选中", r"providerID = AgentProviderCatalog\.resolved\(endpoint: configuration\.endpoint\)\.id"),
    ("选提供商 ⇒ 自动填端点 / 模型", r"private func applyProvider\("),
)


def read_lines(root: pathlib.Path, relative: str):
    path = root / relative
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8").splitlines()


def parse_presets(text: str):
    """把目录里的预设逐条解析出来（返回 [dict]，解析不出行号的条目直接丢）。"""
    presets = []
    for index, line in enumerate(text.splitlines(), 1):
        match = PRESET_LINE.search(line)
        if not match:
            continue
        models = [m for m in MODEL_LITERAL.findall(match.group(4)) if m.strip()]
        presets.append(
            {
                "line": index,
                "id": match.group(1),
                "labelKey": match.group(2),
                "endpoint": match.group(3),
                "models": models,
                "raw": line,
            }
        )
    return presets


def iter_swift(root: pathlib.Path):
    """仓内所有 `.swift`（相对路径, 绝对路径），跳过隐藏目录与构建产物目录。"""
    for path in sorted(root.rglob("*.swift")):
        relative = path.relative_to(root)
        parents = [part for part in relative.parts[:-1]]
        if any(part.startswith(".") or part in EXCLUDE_DIR_PARTS for part in parents):
            continue
        yield relative.as_posix(), path


def host_hits(path: pathlib.Path, hosts):
    """逐行找宿主名（注释行不算 —— 注释里举例子不是端点的主人）。"""
    hits = []
    for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        for host in hosts:
            if host in line:
                hits.append((index, host))
                break
    return hits


def check(root: pathlib.Path):
    """返回 (problems, stats)。"""
    problems: list[str] = []
    stats: dict = {}

    owner_path = root / OWNER
    if not owner_path.is_file():
        return [f"[A] 目录文件不在盘上：{OWNER}"], stats
    owner_text = owner_path.read_text(encoding="utf-8")

    presets = parse_presets(owner_text)
    constructors = len(CONSTRUCTOR.findall(owner_text))
    stats["presets"] = len(presets)

    # ── C1 形状：每一处构造都解析得到（解析不到 = 形状变了 ⇒ 判据空转，必须红）
    if len(presets) != constructors:
        problems.append(
            f"[C] {OWNER}：{constructors} 处构造里有 {len(presets)} 条解析不出来"
            "（预设一行一条、字段顺序固定；形状变了就改解析式，别让判据空转）"
        )
    if len(presets) < MIN_PRESETS:
        problems.append(f"[D] 预设条数 {len(presets)} < 下限 {MIN_PRESETS}（空跑防护）")

    # ── C2 标识唯一（界面 `.tag()` 与匹配都吃它）
    seen_ids: dict[str, int] = {}
    for preset in presets:
        if preset["id"] in seen_ids:
            problems.append(
                f"[C] {OWNER}:{preset['line']} 标识重复：{preset['id']}"
                f"（第一次出现在第 {seen_ids[preset['id']]} 行）"
            )
        seen_ids[preset["id"]] = preset["line"]

    # ── C3 「自定义」恰一条 + 端点唯一
    custom = [p for p in presets if p["id"] == CUSTOM_ID]
    if len(custom) != 1:
        problems.append(f"[C] 「{CUSTOM_ID}」条目应当恰有一条，实际 {len(custom)} 条")
    for entry in custom:
        if entry["endpoint"] != "":
            problems.append(f"[C] {OWNER}:{entry['line']} 「{CUSTOM_ID}」条目的端点必须是空串")
        if entry["models"]:
            problems.append(f"[C] {OWNER}:{entry['line']} 「{CUSTOM_ID}」条目不该有模型清单")

    normalized: dict[str, int] = {}
    for preset in presets:
        if preset["id"] == CUSTOM_ID:
            continue
        if not preset["endpoint"]:
            problems.append(f"[C] {OWNER}:{preset['line']} {preset['id']} 缺端点")
            continue
        key = preset["endpoint"].rstrip("/").lower()
        if key in normalized:
            problems.append(
                f"[C] {OWNER}:{preset['line']} 端点与第 {normalized[key]} 行重复：{preset['endpoint']}"
                "（端点必须唯一，否则匹配会随顺序漂移）"
            )
        normalized[key] = preset["line"]

    if LAST_ENTRY_ANCHOR not in owner_text:
        problems.append(f"[C] {OWNER} 不再按 `{LAST_ENTRY_ANCHOR}` 取「自定义」条目（约定变了？）")

    # ── C4 语言表：每条 labelKey 都在表里、中英非空（品牌名不硬编码在 Core）
    language_text = (root / LANGUAGE).read_text(encoding="utf-8") if (root / LANGUAGE).is_file() else ""
    declared = set(LABEL_KEY.findall(language_text))
    entries = {m[0]: (m[1], m[2]) for m in LABEL_ENTRY.findall(language_text)}
    if not declared:
        problems.append(f"[D] {LANGUAGE} 里一个 `agentProvider*` 标签键都没解析到（空跑防护）")
    for preset in presets:
        if preset["labelKey"] not in declared:
            problems.append(f"[C] {OWNER}:{preset['line']} 标签键 `.{preset['labelKey']}` 没有声明")
        pair = entries.get(preset["labelKey"])
        if pair is None:
            problems.append(f"[C] 语言表缺条目：.{preset['labelKey']}")
        elif not pair[0].strip() or not pair[1].strip():
            problems.append(f"[C] 语言表条目写着空串：.{preset['labelKey']}")

    # ── A 唯一出处：宿主名只许出现在目录文件里
    def host_of(endpoint: str):
        match = HOST.search(endpoint)
        return match.group(1).lower() if match else None

    hosts = sorted({h for h in (host_of(p["endpoint"]) for p in presets) if h and h not in LOOPBACK_HOSTS})
    stats["hosts"] = len(hosts)
    if len(hosts) < MIN_HOSTS:
        problems.append(f"[D] 宿主名只解析到 {len(hosts)} 个 < 下限 {MIN_HOSTS}（空跑防护）")
    face = "/".join(SCAN_DIRS)
    scanned = 0
    for relative, path in iter_swift(root):
        if relative.split("/", 1)[0] not in SCAN_DIRS or relative in SKIP_FILES:
            continue
        scanned += 1
        for index, host in host_hits(path, hosts):
            problems.append(
                f"[A] {relative}:{index} 出现提供商宿主名 `{host}` ——"
                f"端点只许住在 {OWNER}（产品源面 = {face}；界面照 `AgentProviderCatalog.all` 画）"
            )
    stats["scanned"] = scanned
    if scanned < MIN_SCANNED_FILES:
        problems.append(
            f"[D] 产品源面（{face}）只有 {scanned} 个文件 < 下限 {MIN_SCANNED_FILES}（空跑防护）"
        )

    # ── A′ 面外记账：面外读数 + 面外命中逐条登记（面外不判 A，但必须有人签字）
    out_of_face = 0
    out_hits: dict = {}
    for relative, path in iter_swift(root):
        if relative.split("/", 1)[0] in SCAN_DIRS:
            continue
        out_of_face += 1
        hits = host_hits(path, hosts)
        if hits:
            out_hits[relative] = hits
    for relative, hits in sorted(out_hits.items()):
        reason = OUT_OF_FACE_LEDGER.get(relative)
        if reason is None:
            for index, host in hits:
                problems.append(
                    f"[A′] {relative}:{index} 面外出现提供商宿主名 `{host}` 而未登记 ——"
                    "面外命中要逐条登记理由（`OUT_OF_FACE_LEDGER`），未登记不许当通过"
                )
        elif not reason.strip():
            problems.append(f"[A′] {relative} 的面外登记没写理由（登记 = 签字，空话不算）")
    for relative, reason in sorted(OUT_OF_FACE_LEDGER.items()):
        if not (root / relative).is_file():
            problems.append(f"[A′] 面外登记指到盘上不存在的文件：{relative}（死登记，请销账）")
        elif relative.split("/", 1)[0] in SCAN_DIRS:
            problems.append(f"[A′] {relative} 已被收进面内却还挂在面外台账上（陈旧登记，请销账）")
        elif relative not in out_hits:
            problems.append(f"[A′] {relative} 已不再出现提供商宿主名，登记过期（陈旧登记，请销账）")
    if len(OUT_OF_FACE_LEDGER) < MIN_OUT_OF_FACE_LEDGER:
        problems.append(
            f"[A′] 面外登记只剩 {len(OUT_OF_FACE_LEDGER)} 条 < 下限 {MIN_OUT_OF_FACE_LEDGER}"
            "（零登记不许当通过）"
        )
    stats["outOfFaceScanned"] = out_of_face
    stats["outOfFaceHits"] = len(out_hits)
    stats["outOfFaceLedger"] = len(OUT_OF_FACE_LEDGER)

    # ── B 界面接线（少一处就判红：接了提供商没接模型下拉 = 半成品）
    sheet_text = (root / SHEET).read_text(encoding="utf-8") if (root / SHEET).is_file() else ""
    if not sheet_text:
        problems.append(f"[B] 面板文件不在盘上：{SHEET}")
    hit = 0
    for label, pattern in SHEET_ANCHORS:
        if re.search(pattern, sheet_text):
            hit += 1
        else:
            problems.append(f"[B] {SHEET} 少了锚点：{label}（{pattern}）")
    stats["sheetAnchors"] = f"{hit}/{len(SHEET_ANCHORS)}"

    return problems, stats


def report(problems: list, stats: dict, as_json: bool) -> int:
    if as_json:
        payload = {"ok": not problems, "stats": stats, "problems": problems}
        print(json.dumps(payload, ensure_ascii=False, indent=1))
        return 0 if not problems else 1
    print("== 模型服务预设（队列 L-146 · 闭环第 9 项）==")
    print(
        f"预设 {stats.get('presets', 0)} 条 · 宿主名 {stats.get('hosts', 0)} 个 · "
        f"产品源面 {stats.get('scanned', 0)} 份 · 界面锚点 {stats.get('sheetAnchors', '0/0')}"
    )
    print(
        f"面外 .swift {stats.get('outOfFaceScanned', 0)} 份（其中出现提供商宿主名 "
        f"{stats.get('outOfFaceHits', 0)} 份，已登记 {stats.get('outOfFaceLedger', 0)} 条）"
    )
    if problems:
        print(f"❌ 判红 {len(problems)} 处：")
        for problem in problems:
            print(f"   · {problem}")
        return 1
    print(
        f"✅ A 唯一出处：提供商宿主名在产品源面（{'/'.join(SCAN_DIRS)}）内只出现在 {OWNER}；"
        f"面外命中 {stats.get('outOfFaceHits', 0)} 份全部在册"
    )
    print("✅ B 界面接线：面板真的消费目录（遍历 / 选中值 / 模型内容 / 恢复选中 / 自动填充）")
    print("✅ C 形状：标识唯一 · 端点唯一 · 自定义恰一条且为空 · 标签键中英齐备")
    print("✅ D 空跑防护：预设条数 / 宿主数 / 产品源面 / 面外登记四条下限都在")
    return 0


# ── 负例自检 ────────────────────────────────────────────────────────────────
#
# 纪律：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。

WATCHED = (OWNER, SHEET, LANGUAGE, "Core/AppError.swift")


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fixture(destination: pathlib.Path, root: pathlib.Path) -> pathlib.Path:
    for dirname in SCAN_DIRS:
        source = root / dirname
        if not source.is_dir():
            continue
        target = destination / dirname
        target.mkdir(parents=True, exist_ok=True)
        for path in sorted(source.rglob("*.swift")):
            relative = path.relative_to(source)
            (target / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target / relative)
    # 面外：不整目录复制（面外只进读数与逐条登记），但按真仓实读建出面外根目录 ——
    # 负例要能往真根里种探针，根在不在本身也是夹具的忠实度；登记在册的那几份则必须复制。
    for entry in sorted(root.iterdir()):
        if entry.is_dir() and entry.name not in SCAN_DIRS and not entry.name.startswith("."):
            (destination / entry.name).mkdir(parents=True, exist_ok=True)
    for relative in OUT_OF_FACE_LEDGER:
        source = root / relative
        if not source.is_file():
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    return destination


def _patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具写坏失败：`{old}` 不在 {path.name} 里")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def self_test(root: pathlib.Path) -> int:
    before = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
    cases: list[tuple[str, bool]] = []   # (名字, 期望报红)
    with tempfile.TemporaryDirectory(prefix="doyah-agent-presets-") as tmp:
        workspace = pathlib.Path(tmp)

        def fresh(name: str) -> pathlib.Path:
            return _fixture(workspace / name, root)

        # ① 绿：真仓库的副本，判据必须全过
        cases.append(("绿对照：真仓库副本应全过", not check(fresh("green"))[0]))

        # ② 红：任何一侧自己写死一个提供商端点（这一族缺陷的标准形状）
        stray = fresh("stray-endpoint")
        (stray / "App/Views").mkdir(parents=True, exist_ok=True)
        (stray / "App/Views/StrayEndpoint.swift").write_text(
            "import Foundation\n\nlet defaultEndpoint = \"https://api.deepseek.com/v1\"\n",
            encoding="utf-8",
        )
        cases.append(("界面（或别处）自己写死端点", bool(check(stray)[0])))

        # ③ 红：预设被削到 1 条（空跑防护）
        thin = fresh("thin")
        owner = thin / OWNER
        kept = [
            line for line in owner.read_text(encoding="utf-8").splitlines()
            if not line.startswith("        AgentProviderPreset(id:")
        ]
        kept.append("        AgentProviderPreset(id: \"custom\", labelKey: .agentProviderCustom, endpoint: \"\", models: [])")
        owner.write_text("\n".join(kept) + "\n", encoding="utf-8")
        cases.append(("预设被削到 1 条", bool(check(thin)[0])))

        # ④ 红：两条预设共用同一个端点（匹配会随顺序漂移）
        duplicate = fresh("duplicate-endpoint")
        _patch(
            duplicate / OWNER,
            'id: "deepseek", labelKey: .agentProviderDeepSeek, endpoint: "https://api.deepseek.com/v1"',
            'id: "deepseek", labelKey: .agentProviderDeepSeek, endpoint: "https://api.openai.com/v1"',
        )
        cases.append(("两条预设共用端点", bool(check(duplicate)[0])))

        # ⑤ 红：界面下拉不再遍历目录（接了别的来源 = 目录形同虚设）
        no_picker = fresh("no-picker")
        _patch(no_picker / SHEET, "ForEach(AgentProviderCatalog.all)", "ForEach(AgentProviderCatalog.presets)")
        cases.append(("界面下拉不再遍历目录", bool(check(no_picker)[0])))

        # ⑥ 红：模型下拉绕开契约层（界面自己拼清单）
        own_models = fresh("own-models")
        _patch(own_models / SHEET, "selectedPreset.modelOptions(currentModel: model)", "selectedPreset.models")
        cases.append(("模型下拉绕开契约层", bool(check(own_models)[0])))

        # ⑦ 红：标签键没声明 / 没进语言表
        unregistered = fresh("label-unregistered")
        _patch(unregistered / OWNER, "labelKey: .agentProviderGroq,", "labelKey: .agentProviderNotRegistered,")
        cases.append(("标签键没声明 / 没进语言表", bool(check(unregistered)[0])))

        # ⑧ 红：扫描面被削掉（空跑防护 —— 零命中不许当通过）
        gutted = fresh("gutted")
        for path in sorted((gutted / "Core").rglob("*.swift")):
            if path.name != pathlib.Path(OWNER).name:
                path.unlink()
        for path in sorted((gutted / "App").rglob("*.swift")):
            if path.name != pathlib.Path(SHEET).name:
                path.unlink()
        cases.append(("扫描面被削掉", bool(check(gutted)[0])))

        # ⑨ 红：面外新增一枚**未登记**的出网件（面外的洞 = 老账「声明全仓、面只有四根」那种静默）
        planted = fresh("out-of-face-planted")
        (planted / "TestsUISnapshot").mkdir(parents=True, exist_ok=True)
        (planted / "TestsUISnapshot/PlantedEndpoint.swift").write_text(
            "import Foundation\n\nlet plantedEndpoint = \"https://api.deepseek.com/v1\"\n",
            encoding="utf-8",
        )
        planted_problems = check(planted)[0]
        cases.append((
            "面外新增未登记的出网件（判红并点名）",
            any("[A′]" in item and "PlantedEndpoint.swift" in item for item in planted_problems),
        ))

        # ⑩ 绿：面外新增一枚**无关**文件（对手臂 —— 面外不是一律判红）
        innocent = fresh("out-of-face-innocent")
        (innocent / "TestsUISnapshot").mkdir(parents=True, exist_ok=True)
        (innocent / "TestsUISnapshot/InnocentProbe.swift").write_text(
            "import Foundation\n\nlet innocentProbe = 1\n", encoding="utf-8"
        )
        cases.append(("面外新增无关文件（对手臂，不许误伤）", not check(innocent)[0]))

        # ⑪ 红：在册那份**已不再命中** ⇒ 登记过期（陈旧登记，请销账）
        stale = fresh("ledger-stale")
        stale_file = stale / "Tests/EgressLogTests.swift"
        stale_text = stale_file.read_text(encoding="utf-8")
        for host in ("api.openai.com", "api.deepseek.com"):
            stale_text = stale_text.replace(host, "api.example.invalid")
        stale_file.write_text(stale_text, encoding="utf-8")
        stale_problems = check(stale)[0]
        cases.append((
            "面外在册那份已不再命中（陈旧登记）",
            any("[A′]" in item and "EgressLogTests.swift" in item for item in stale_problems),
        ))

        # ⑫ 红：面外登记指到盘上不存在的文件（死登记）
        dead = fresh("ledger-dead")
        (dead / "Tests/EgressLogTests.swift").unlink()
        dead_problems = check(dead)[0]
        cases.append((
            "面外登记指到不在盘的文件（死登记）",
            any("[A′]" in item and "EgressLogTests.swift" in item for item in dead_problems),
        ))

        # ⑬ 红：面外登记被掏空（零登记不许当通过）
        saved = dict(OUT_OF_FACE_LEDGER)
        try:
            OUT_OF_FACE_LEDGER.clear()
            emptied = bool(check(fresh("ledger-emptied"))[0])
        finally:
            OUT_OF_FACE_LEDGER.clear()
            OUT_OF_FACE_LEDGER.update(saved)
        cases.append(("面外登记被掏空（零登记不许当通过）", emptied))

        # ⑭ 静态臂：真仓面钉与面外台账不许回退（夹具比值会被夹具自己的实测压小，真仓由这一例看住）
        cases.append((
            "静态臂：真仓面钉 ≥300 且面外台账逐条在盘、在面外、有理由",
            MIN_SCANNED_FILES >= 300
            and len(OUT_OF_FACE_LEDGER) >= MIN_OUT_OF_FACE_LEDGER
            and all(reason.strip() for reason in OUT_OF_FACE_LEDGER.values())
            and all((root / rel).is_file() for rel in OUT_OF_FACE_LEDGER)
            and all(rel.split("/", 1)[0] not in SCAN_DIRS for rel in OUT_OF_FACE_LEDGER),
        ))

        # ⑮ 末例：真仓库逐字节未变 + 真仓库实跑绿
        after = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
        cases.append(("末例：真仓库逐字节未变且实跑绿", after == before and not check(root)[0]))

    passed_cases = 0
    for name, ok in cases:
        print(f"{'✅' if ok else '❌'} {name}")
        passed_cases += 1 if ok else 0
    ok = passed_cases == len(cases)
    print(f"{'✅' if ok else '❌'} 负例自检：{len(cases)} 条中 {passed_cases} 条达到预期")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="模型服务预设的唯一出处与界面接线（队列 L-146）")
    parser.add_argument("--root", default=None, help="仓根（夹具 / 另一份拷贝用）")
    parser.add_argument("--json", action="store_true", dest="as_json", help="机器读输出")
    parser.add_argument("--self-test", action="store_true", dest="self_test", help="负例自检")
    arguments = parser.parse_args()

    root = pathlib.Path(arguments.root).resolve() if arguments.root else BASE
    if arguments.self_test:
        return self_test(root)
    problems, stats = check(root)
    return report(problems, stats, arguments.as_json)


if __name__ == "__main__":
    sys.exit(main())
