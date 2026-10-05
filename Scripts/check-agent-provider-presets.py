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

- **A 唯一出处**：提供商宿主名（**从 `platform/macos/Core/AgentProviderPreset.swift` 里解析出来**，不手抄一份）
  只许出现在那个文件里；`platform/macos/App/` / `platform/macos/Core/` / `Platform/` / `platform/macos/CLI/`（除目录文件与语言表）
  命中即判红，逐处点名 `文件:行号`。
- **B 界面接线**：`platform/macos/App/Views/AgentSettingsSheet.swift` 必须真的消费目录 ——
  ① 提供商下拉遍历 `AgentProviderCatalog.all` ② 选中值 = 稳定标识（`.tag(preset.id)`）
  ③ 模型下拉内容取自契约层（`modelOptions(currentModel: model)`）
  ④ `.task` 里按端点**恢复选中**（重开面板不许落回自定义）
  ⑤ 选提供商 ⇒ 自动填端点与模型（`applyProvider(` 定义在位）。
- **C 形状**：标识唯一 / 端点唯一（归一化后）/ 「自定义」恰一条且端点为**空**、模型清单为空 /
  条数下限 / 每条 `labelKey` 都在语言表里有中英两条非空 / 目录靠 `all[all.count - 1]` 认「最后一条」。
- **D 空跑防护**：扫描文件数 / 预设条数 / 宿主名数三条下限（正则失配 ⇒ 零命中 ⇒ 假绿，
  这是这类判据最经典的坏法）。
- **判据自己的证据**：`--self-test`（**9 例**）。

**与 Core 单测的分工（如实登记）**：`platform/macos/Tests/AgentProviderPresetTests.swift` 判**类型行为**
（端点匹配、模型下拉内容、本地判定同源、不许有凭据字段）；本判据判**盘上源码的形状**
（端点有没有第二个主人、界面有没有接上）—— 后者单测看不见。两处**故意有一处重叠**
（标识 / 端点唯一）：单测管「运行时是真唯一」，这里管「改了源码但没跑单测也拦得住」。

**边界（如实登记）**：`platform/macos/Tests/` 与 `Docs/` 不在 A 的扫描面（判据自己的夹具要用真端点当输入；
三书里引一句地址是叙述不是实现）。这条判据也不管**模型名新旧**（服务商上新比本仓发版快，
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

OWNER = "platform/macos/Core/AgentProviderPreset.swift"
SHEET = "platform/macos/App/Views/AgentSettingsSheet.swift"
LANGUAGE = "platform/macos/Core/Localization.swift"

SCAN_DIRS = ("platform/macos/App", "platform/macos/Core", "platform/macos/Platform", "platform/macos/CLI")
SKIP_FILES = {OWNER, LANGUAGE}

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
MIN_SCANNED_FILES = 60
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
    scanned = 0
    for dirname in SCAN_DIRS:
        directory = root / dirname
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*.swift")):
            relative = path.relative_to(root).as_posix()
            if relative in SKIP_FILES:
                continue
            scanned += 1
            for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("///"):
                    continue
                for host in hosts:
                    if host in line:
                        problems.append(
                            f"[A] {relative}:{index} 出现提供商宿主名 `{host}` ——"
                            f"端点只许住在 {OWNER}（界面照 `AgentProviderCatalog.all` 画）"
                        )
                        break
    stats["scanned"] = scanned
    if scanned < MIN_SCANNED_FILES:
        problems.append(f"[D] 扫描面只有 {scanned} 个文件 < 下限 {MIN_SCANNED_FILES}（空跑防护）")

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
        f"扫描文件 {stats.get('scanned', 0)} 个 · 界面锚点 {stats.get('sheetAnchors', '0/0')}"
    )
    if problems:
        print(f"❌ 判红 {len(problems)} 处：")
        for problem in problems:
            print(f"   · {problem}")
        return 1
    print("✅ A 唯一出处：提供商宿主名只出现在 platform/macos/Core/AgentProviderPreset.swift")
    print("✅ B 界面接线：面板真的消费目录（遍历 / 选中值 / 模型内容 / 恢复选中 / 自动填充）")
    print("✅ C 形状：标识唯一 · 端点唯一 · 自定义恰一条且为空 · 标签键中英齐备")
    print("✅ D 空跑防护：预设条数 / 宿主数 / 扫描面三条下限都在")
    return 0


# ── 负例自检 ────────────────────────────────────────────────────────────────
#
# 纪律：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。

WATCHED = (OWNER, SHEET, LANGUAGE, "platform/macos/Core/AppError.swift")


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
        (stray / "platform/macos/App/Views").mkdir(parents=True, exist_ok=True)
        (stray / "platform/macos" / "App/Views/StrayEndpoint.swift").write_text(
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
        for path in sorted((gutted / "platform/macos/Core").rglob("*.swift")):
            if path.name != pathlib.Path(OWNER).name:
                path.unlink()
        for path in sorted((gutted / "platform/macos/App").rglob("*.swift")):
            if path.name != pathlib.Path(SHEET).name:
                path.unlink()
        cases.append(("扫描面被削掉", bool(check(gutted)[0])))

        # ⑨ 末例：真仓库逐字节未变 + 真仓库实跑绿
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
