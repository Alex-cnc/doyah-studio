#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""发布产物版本号：**一个值、三处逐字一致** + **Xcode 工程（生成物）不许与 `project.yml`（源）漂移**

队列 L-70，2026-09-28 开发循环第 68 轮。台账 = `Scripts/release-version.json`。

## 为什么要有它

`Docs/发布方案.md` §2 原来写着「版本号维护位置：`Scripts/build-app.sh` 的 Info.plist 模板、
`project.yml`（Xcode 工程）。**两处必须一致**」—— 第 57 轮做 `v0.2.0-alpha` 发布收口时实测**不成立**：

* `project.yml` 的**应用目标一个版本键都没有**（只有两个框架目标带 XcodeGen 的默认 `MARKETING_VERSION: 1.0`）；
* 入库的 `DoyahStudio.xcodeproj/project.pbxproj` 是**生成物**，里面同样只有那两处 `1.0`；
* 于是那句「两处必须一致」是**纸面纪律** —— 没有任何门禁会说话，谁都不知道哪一处是真的。

更严重的是**生成物早就过期了**且没人知道：入库的 `project.pbxproj` 只有 869 行、包标识仍是
改名前的 `com.vnull.PostgresClient*`、**没有 `DoyahPlatform` / `DoyahPlatformTests` 两个目标**
（2026-09-22 改名与平台拆分之后就没再生成过）。`Docs/项目评审-2026-09-23.md` 把「生成物与源可能
不同步（改了 `project.yml` 忘了重新生成时，Xcode 打开的是旧工程）」记成风险，**但那条风险没有判据**。
「生成文件没有症状」在本仓库是第五次撞上了（第 17 项 vendored SQLite / 第 18 项生成常量 /
L-55 文档数字 / L-72 例数 / 本条）。

## 判据（四条，全部机械）

* **A 台账自洽**：`Scripts/release-version.json` 结构完整（值 / 形状 / 权威处 / 镜像处 / 生成器登记 /
  锚点 / 范围外），值不是空串，镜像处不许为空。
* **B 三处逐字一致**：B1 权威处 = `Scripts/build-app.sh` 的 `<<'PLIST'` heredoc 里那两个键
  （**恰好各一处**）；B2 `project.yml` 应用目标的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；
  B3 生成物里**该目标自己的每一个构建配置**（`Debug` / `Release`，少一档判红）的同名键。
  三处一律不许缺键：**缺键 = 判红**（这正是第 57 轮的现场：键压根不存在）。
* **C 生成物 ↔ 源 不许漂移**：C1 目标名集合双向（`project.yml` ↔ 生成物）；C2 每个目标的
  `PRODUCT_BUNDLE_IDENTIFIER` 一致；C3 每个目标的 `*.swift` **文件名集合**双向（磁盘 ↔ 该目标
  `PBXSourcesBuildPhase` 的引用）。C3 的前提「各目标源目录之间没有同名 `.swift`」**每次实跑重新验**
  （出现同名即判红并提示改用路径口径 —— 不许悄悄放松）。
* **D 空跑防护**：目标数 / 每个目标的源文件数 / 每个目标的构建配置数 / 锚点命中处数都有下限；
  任何一条降到「什么都没查到」就判红（防「判据被掏空 ⇒ 零命中 = 通过」）。

## 明确不判（范围外，每次实跑显式打印）

* 两个框架目标的 `MARKETING_VERSION`（XcodeGen 默认 `1.0`）—— 内部框架不是发布产物的身份。
* 生成器版本**不判红**（`generator.version`）：用户升级 `xcodegen` 不该把无关轮次的闭合门禁判红；
  「生成物是否过期」由 C1/C2/C3 的**内容**对账回答。版本不一致时高声提示，退出码不变。
* `Package.swift` / `dist/*.app` / 标签名与发布说明里的版本叙述（另一条构建路线、产物、历史记录）。

## 用法

    python3 Scripts/check-release-version.py              # 判真仓库
    python3 Scripts/check-release-version.py --root <目录> # 判别的仓库（自测夹具用它）
    python3 Scripts/check-release-version.py --self-test   # 判据自己的证据（10 例）

退出码：0 = 全绿；1 = 判红（逐条点名文件与行号）；2 = 用法 / 夹具错误。
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import sys
import tempfile

LEDGER = "Scripts/release-version.json"

# 空跑防护下限（低于即判红）
FLOOR_TARGETS = 4
FLOOR_SWIFT_PER_TARGET = 1
FLOOR_BUILD_CONFIGS = 2
FLOOR_ANCHOR_SITES = 3


# --------------------------------------------------------------------------------------
# 解析：`Scripts/build-app.sh` 的 Info.plist 模板
# --------------------------------------------------------------------------------------
def parse_plist_template(text: str):
    """从 build-app.sh 里取出 Info.plist 模板的键值（key → [(值, 行号), …]）。"""
    lines = text.split("\n")
    start = None
    for index, line in enumerate(lines):
        if re.search(r"<<'PLIST'", line):
            start = index + 1
            break
    if start is None:
        return None, "没有找到 Info.plist 模板的 heredoc 起点（`<<'PLIST'`）"
    end = None
    for index in range(start, len(lines)):
        if lines[index].strip() == "PLIST":
            end = index
            break
    if end is None:
        return None, "Info.plist 模板的 heredoc 没有结束行（单独一行 `PLIST`）"

    found: dict = {}
    index = start
    while index < end:
        match = re.match(r"\s*<key>([^<]+)</key>\s*$", lines[index])
        if not match:
            index += 1
            continue
        key = match.group(1)
        cursor = index + 1
        while cursor < end and not lines[cursor].strip():
            cursor += 1
        if cursor >= end:
            return None, "模板在第 %d 行有 <key>%s</key> 但没有值行" % (index + 1, key)
        value_line = lines[cursor]
        string_match = re.search(r"<string>([^<]*)</string>", value_line)
        if string_match:
            value = string_match.group(1)
        else:
            tag = re.search(r"<([a-zA-Z]+)\s*/?>", value_line)
            value = tag.group(1) if tag else value_line.strip()
        found.setdefault(key, []).append((value, cursor + 1))
        index = cursor + 1
    return found, None


# --------------------------------------------------------------------------------------
# 解析：`project.yml`（只认本仓这份 spec 的形状：2 空格缩进的 targets / settings.base）
# --------------------------------------------------------------------------------------
def parse_project_yml(text: str):
    """返回 {目标名: {type, source_dirs, bundle_id, version_keys, excludes, line}}。"""
    lines = text.split("\n")
    # `targets:` 行（顶层）
    start = None
    for index, line in enumerate(lines):
        if re.match(r"^targets:\s*$", line):
            start = index + 1
            break
    if start is None:
        return None, "`project.yml` 里找不到顶层 `targets:`"
    end = len(lines)
    for index in range(start, len(lines)):
        if lines[index].strip() and not lines[index].startswith(" "):
            end = index
            break

    targets: dict = {}
    current = None
    current_list = None
    for index in range(start, end):
        raw = lines[index]
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()
        if indent == 2 and re.match(r"^[A-Za-z0-9_.\-]+:\s*$", stripped):
            current = stripped[:-1]
            targets[current] = {
                "line": index + 1,
                "type": None,
                "source_dirs": [],
                "excludes": [],
                "bundle_id": None,
                "version_keys": {},
            }
            current_list = None
            continue
        if current is None:
            continue
        # 只认 `sources:` / `excludes:` 这两个列表里的条目：`dependencies:` 下的
        # `- target: …` / `- package: …` 不是排除项（早期版本把它们误收进 excludes）。
        if indent >= 4 and re.match(r"^(sources|excludes):\s*$", stripped):
            current_list = stripped[:-1]
            continue
        if indent == 4 and not stripped.startswith("- "):
            current_list = None
            continue
        if current_list == "sources" and stripped.startswith("- path:"):
            targets[current]["source_dirs"].append(stripped.split(":", 1)[1].strip().strip('"'))
            continue
        if current_list == "excludes" and stripped.startswith("- "):
            targets[current]["excludes"].append(stripped[2:].strip().strip('"'))
            continue
        match = re.match(r"^type:\s*(\S+)\s*$", stripped)
        if match:
            targets[current]["type"] = match.group(1)
            continue
        match = re.match(r"^PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)\s*$", stripped)
        if match:
            targets[current]["bundle_id"] = match.group(1)
            continue
        match = re.match(r"^(MARKETING_VERSION|CURRENT_PROJECT_VERSION):\s*\"?([^\"\s#]+)\"?", stripped)
        if match:
            targets[current]["version_keys"][match.group(1)] = (match.group(2), index + 1)
            continue
    if not targets:
        return None, "`project.yml` 的 `targets:` 下面一个目标都没解析到"
    return targets, None


# --------------------------------------------------------------------------------------
# 解析：`DoyahStudio.xcodeproj/project.pbxproj`
# --------------------------------------------------------------------------------------
PBX_OBJECT = re.compile(r"\n\t\t([A-F0-9]{24}) /\* (.*?) \*/ = \{\n(.*?)\n\t\t\};", re.S)


def parse_pbxproj(text: str):
    objects = {}
    for match in PBX_OBJECT.finditer(text):
        ident, comment, body = match.group(1), match.group(2), match.group(3)
        isa = re.search(r"isa = (\w+);", body)
        objects[ident] = {"isa": isa.group(1) if isa else "?", "comment": comment, "body": body}

    native_targets: dict = {}
    sources_phases: dict = {}
    config_lists: dict = {}
    configs: dict = {}
    for ident, obj in objects.items():
        if obj["isa"] == "PBXNativeTarget":
            name = re.search(r"\n\t\t\tname = ([^;]+);", obj["body"])
            phases = re.search(r"\n\t\t\tbuildPhases = \((.*?)\);", obj["body"], re.S)
            config_list = re.search(r"buildConfigurationList = ([A-F0-9]{24})", obj["body"])
            product_type = re.search(r'productType = "([^"]+)"', obj["body"])
            native_targets[ident] = {
                "name": name.group(1).strip() if name else obj["comment"],
                "phase_ids": re.findall(r"([A-F0-9]{24}) /\* ", phases.group(1)) if phases else [],
                "config_list": config_list.group(1) if config_list else None,
                "product_type": product_type.group(1) if product_type else None,
            }
        elif obj["isa"] == "PBXSourcesBuildPhase":
            files = re.search(r"\n\t\t\tfiles = \((.*?)\);", obj["body"], re.S)
            names = []
            if files:
                for entry in re.finditer(r"/\* (.*?) in Sources \*/", files.group(1)):
                    names.append(entry.group(1))
            sources_phases[ident] = names
        elif obj["isa"] == "XCConfigurationList":
            name = re.search(r'Build configuration list for PBXNativeTarget "(.*?)"', obj["comment"])
            ids = re.findall(r"([A-F0-9]{24}) /\* (\w+) \*/", obj["body"])
            config_lists[ident] = {
                "target": name.group(1) if name else None,
                "configs": [(ident_, label) for ident_, label in ids],
            }
        elif obj["isa"] == "XCBuildConfiguration":
            entry = {"name": obj["comment"], "keys": {}}
            for key_match in re.finditer(
                r"^\t{4}([A-Z_]+) = ([^;]+);$", obj["body"], re.M
            ):
                entry["keys"][key_match.group(1)] = key_match.group(2).strip().strip('"')
            configs[ident] = entry
    return {
        "targets": native_targets,
        "sources_phases": sources_phases,
        "config_lists": config_lists,
        "configs": configs,
    }


def pbx_target_configs(pbx: dict, target_id: str):
    """该目标的构建配置：[(配置名, 配置对象), …]（按配置列表给定的顺序）。"""
    target = pbx["targets"][target_id]
    config_list = pbx["config_lists"].get(target["config_list"] or "")
    if not config_list:
        return []
    out = []
    for config_id, label in config_list["configs"]:
        entry = pbx["configs"].get(config_id)
        if entry is None:
            continue
        out.append((label or entry["name"], entry))
    return out


def pbx_target_swift_names(pbx: dict, target_id: str):
    names = []
    for phase_id in pbx["targets"][target_id]["phase_ids"]:
        if phase_id in pbx["sources_phases"]:
            names.extend(pbx["sources_phases"][phase_id])
    return sorted(names)


# --------------------------------------------------------------------------------------
# 磁盘侧：源目录里的 *.swift（跟随目录符号链接 —— 自测夹具用软链指真源目录）
# --------------------------------------------------------------------------------------
def swift_names_on_disk(root: pathlib.Path, relative: str):
    base = root / relative
    if not base.is_dir():
        return None
    out = []
    stack = [base]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(str(current)))
        except OSError:
            return None
        for entry in entries:
            if entry.is_dir(follow_symlinks=True):
                stack.append(pathlib.Path(entry.path))
            elif entry.name.endswith(".swift"):
                out.append(entry.name)
    return sorted(out)


# --------------------------------------------------------------------------------------
# 判据
# --------------------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.problems = []
        self.notes = []
        self.sites = 0

    def bad(self, message: str):
        self.problems.append(message)

    def note(self, message: str):
        self.notes.append(message)


def read_text(root: pathlib.Path, relative: str, report: Report):
    path = root / relative
    if not path.is_file():
        report.bad("文件不存在：%s" % relative)
        return None
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:  # pragma: no cover - 读盘失败属于环境问题
        report.bad("读不了 %s：%s" % (relative, error))
        return None


def load_ledger(root: pathlib.Path, report: Report):
    text = read_text(root, LEDGER, report)
    if text is None:
        return None
    try:
        ledger = json.loads(text)
    except json.JSONDecodeError as error:
        report.bad("%s 不是合法 JSON：%s" % (LEDGER, error))
        return None
    # A 台账自洽
    if not isinstance(ledger.get("version"), int):
        report.bad("[台账] version 缺失或不是整数")
    for field in ("marketingVersion", "buildVersion"):
        value = ledger.get(field)
        if not isinstance(value, str) or not value.strip():
            report.bad("[台账] %s 缺失或为空" % field)
    if not re.match(r"^\d+(\.\d+)*$", str(ledger.get("marketingVersion", ""))):
        report.bad("[台账] marketingVersion 形状不对（期望 `主.次.修订`）：%r" % ledger.get("marketingVersion"))
    if not re.match(r"^\d+$", str(ledger.get("buildVersion", ""))):
        report.bad("[台账] buildVersion 形状不对（期望纯数字）：%r" % ledger.get("buildVersion"))
    authority = ledger.get("authority") or {}
    if not authority.get("path"):
        report.bad("[台账] authority.path 缺失（谁是权威不写清 = 判据没有基准）")
    mirrors = ledger.get("mirrors")
    if not isinstance(mirrors, list) or not mirrors:
        report.bad("[台账] mirrors 缺失或为空（三处一致至少要有镜像处）")
    configs = ledger.get("buildConfigurations")
    if not isinstance(configs, list) or len(configs) < FLOOR_BUILD_CONFIGS:
        report.bad("[台账] buildConfigurations 缺失或少于 %d 档" % FLOOR_BUILD_CONFIGS)
    generator = ledger.get("generator") or {}
    for field in ("tool", "version", "command"):
        if not generator.get(field):
            report.bad("[台账] generator.%s 缺失（生成物由谁产出要可追）" % field)
    if not ledger.get("anchors"):
        report.bad("[台账] anchors 缺失（文档里的现状声明没人看）")
    if not ledger.get("notInScope"):
        report.bad("[台账] notInScope 缺失（范围外不写清 = 偷偷放过）")
    return ledger


def check_authority(root: pathlib.Path, ledger: dict, report: Report):
    """B1 —— 权威处：build-app.sh 的 Info.plist 模板。"""
    relative = ledger["authority"]["path"]
    keys = ledger["authority"].get("keys") or {}
    text = read_text(root, relative, report)
    if text is None:
        return
    table, error = parse_plist_template(text)
    if table is None:
        report.bad("%s：%s" % (relative, error))
        return
    for field, plist_key in (("marketingVersion", keys.get("marketingVersion")),
                             ("buildVersion", keys.get("buildVersion"))):
        if not plist_key:
            report.bad("[台账] authority.keys.%s 缺失" % field)
            continue
        sites = table.get(plist_key) or []
        if not sites:
            report.bad("%s：Info.plist 模板里没有 `%s`（发布产物的版本从哪来？）" % (relative, plist_key))
            continue
        if len(sites) > 1:
            report.bad("%s：Info.plist 模板里 `%s` 出现 %d 次（只许一处，否则又是多处副本）"
                       % (relative, plist_key, len(sites)))
        for value, line in sites:
            report.sites += 1
            if value != ledger[field]:
                report.bad("%s:%d 的 `%s` = `%s`，台账 `%s` = `%s`（权威处与台账不一致）"
                           % (relative, line, plist_key, value, field, ledger[field]))


def check_project_yml(root: pathlib.Path, ledger: dict, report: Report):
    """B2 —— 源：project.yml 应用目标的版本键。"""
    text = read_text(root, "project.yml", report)
    if text is None:
        return None
    targets, error = parse_project_yml(text)
    if targets is None:
        report.bad("project.yml：%s" % error)
        return None
    for mirror in ledger["mirrors"]:
        if mirror["path"] != "project.yml":
            continue
        target = targets.get(mirror.get("target"))
        if target is None:
            report.bad("project.yml：台账点名的目标 `%s` 不在 spec 里（目标被改名 / 删掉了？）"
                       % mirror.get("target"))
            continue
        for field, key in (mirror.get("keys") or {}).items():
            entry = target["version_keys"].get(key)
            if entry is None:
                report.bad("project.yml:%d（目标 `%s`）没有 `%s` —— 缺键就是第 57 轮那个现场"
                           % (target["line"], mirror["target"], key))
                continue
            value, line = entry
            report.sites += 1
            if value != ledger[field]:
                report.bad("project.yml:%d 的 `%s` = `%s`，台账 `%s` = `%s`"
                           % (line, key, value, field, ledger[field]))
    return targets


def check_pbxproj(root: pathlib.Path, ledger: dict, report: Report):
    """B3 —— 生成物：该目标每个构建配置的版本键。"""
    relative = None
    for mirror in ledger["mirrors"]:
        if mirror["path"].endswith("project.pbxproj"):
            relative = mirror["path"]
    if relative is None:
        report.bad("[台账] mirrors 里没有生成物（`.xcodeproj/project.pbxproj`）")
        return None
    text = read_text(root, relative, report)
    if text is None:
        return None
    pbx = parse_pbxproj(text)
    if not pbx["targets"]:
        report.bad("%s：一个 PBXNativeTarget 都没解析到（生成物是空的 / 格式变了）" % relative)
        return None

    wanted = [mirror for mirror in ledger["mirrors"] if mirror["path"].endswith("project.pbxproj")][0]
    target_id = None
    for ident, target in pbx["targets"].items():
        if target["name"] == wanted.get("target"):
            target_id = ident
            break
    if target_id is None:
        report.bad("%s：台账点名的目标 `%s` 在生成物里不存在（**生成物过期**的典型症状）"
                   % (relative, wanted.get("target")))
        return pbx

    entries = pbx_target_configs(pbx, target_id)
    if len(entries) < FLOOR_BUILD_CONFIGS:
        report.bad("%s：目标 `%s` 只解析到 %d 档构建配置（少于 %d 档 = 有一档没人守）"
                   % (relative, wanted["target"], len(entries), FLOOR_BUILD_CONFIGS))
    seen_names = set()
    for name, entry in entries:
        seen_names.add(name)
        for field, key in (wanted.get("keys") or {}).items():
            value = entry["keys"].get(key)
            if value is None:
                report.bad("%s：目标 `%s` 的 `%s` 配置里没有 `%s`" % (relative, wanted["target"], name, key))
                continue
            report.sites += 1
            if value != ledger[field]:
                report.bad("%s：目标 `%s` 的 `%s` 配置里 `%s` = `%s`，台账 `%s` = `%s`"
                           % (relative, wanted["target"], name, key, value, field, ledger[field]))
    expected = set(ledger.get("buildConfigurations") or [])
    missing = expected - seen_names
    if missing:
        report.bad("%s：目标 `%s` 缺构建配置 %s（台账 `buildConfigurations` 要求齐全）"
                   % (relative, wanted["target"], "、".join(sorted(missing))))
    # 范围外：其他目标的版本键，显式打印
    outside = []
    for ident, target in pbx["targets"].items():
        if ident == target_id:
            continue
        for name, entry in pbx_target_configs(pbx, ident):
            for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
                if key in entry["keys"]:
                    outside.append("%s/%s=%s" % (target["name"], key, entry["keys"][key]))
    if outside:
        report.note("范围外（内部框架 / 测试目标，不判）：%s" % "、".join(sorted(set(outside))))
    return pbx


def brief(names, limit: int = 8) -> str:
    names = list(names)
    if len(names) <= limit:
        return "、".join(names)
    return "、".join(names[:limit]) + " 等 %d 个" % len(names)


def check_structure(root: pathlib.Path, ledger: dict, targets, pbx, report: Report):
    """C —— 生成物 ↔ 源 不许漂移。"""
    if targets is None or pbx is None:
        return
    by_name = {}
    for ident, target in pbx["targets"].items():
        by_name[target["name"]] = ident

    yml_names = set(targets)
    pbx_names = set(by_name)
    only_yml = yml_names - pbx_names
    only_pbx = pbx_names - yml_names
    if only_yml:
        report.bad("C1 `project.yml` 有的目标在生成物里没有：%s（改了 yml 忘了 `xcodegen generate`）"
                   % "、".join(sorted(only_yml)))
    if only_pbx:
        report.bad("C1 生成物里有的目标在 `project.yml` 里没有：%s" % "、".join(sorted(only_pbx)))
    if len(pbx_names) < FLOOR_TARGETS:
        report.bad("C1 生成物只有 %d 个目标（少于下限 %d 个 —— 空跑防护）" % (len(pbx_names), FLOOR_TARGETS))

    all_names: dict = {}
    for name in sorted(yml_names & pbx_names):
        target = targets[name]
        ident = by_name[name]
        # C2 包标识
        yml_bundle = target["bundle_id"]
        configs = pbx_target_configs(pbx, ident)
        pbx_bundles = {entry["keys"].get("PRODUCT_BUNDLE_IDENTIFIER") for _, entry in configs}
        pbx_bundles.discard(None)
        if yml_bundle and pbx_bundles and yml_bundle not in pbx_bundles:
            report.bad("C2 目标 `%s` 的包标识不一致：`project.yml` = `%s`，生成物 = %s"
                       % (name, yml_bundle, "、".join(sorted(pbx_bundles))))
        if len(pbx_bundles) > 1:
            report.bad("C2 目标 `%s` 在生成物里有两套包标识：%s" % (name, "、".join(sorted(pbx_bundles))))
        # C3 源文件集合（双向）
        pbx_swift = pbx_target_swift_names(pbx, ident)
        disk_swift = []
        for source_dir in target["source_dirs"]:
            found = swift_names_on_disk(root, source_dir)
            if found is None:
                report.bad("C3 目标 `%s` 的源目录不存在：`%s`" % (name, source_dir))
                continue
            disk_swift.extend(found)
        if len(disk_swift) < FLOOR_SWIFT_PER_TARGET:
            report.bad("C3 目标 `%s` 的源目录里一个 `.swift` 都没找到（空跑防护）" % name)
        missing_in_pbx = sorted(set(disk_swift) - set(pbx_swift))
        missing_on_disk = sorted(set(pbx_swift) - set(disk_swift))
        if missing_in_pbx:
            report.bad("C3 目标 `%s`：磁盘上有、生成物里没有的 `.swift`：%s（工程过期）"
                       % (name, brief(missing_in_pbx)))
        if missing_on_disk:
            report.bad("C3 目标 `%s`：生成物里有、磁盘上已没有的 `.swift`：%s（工程过期）"
                       % (name, brief(missing_on_disk)))
        for filename in disk_swift:
            all_names.setdefault(filename, []).append(name)
    duplicated = {name: owners for name, owners in all_names.items() if len(owners) > 1}
    if duplicated:
        report.bad("C3 前提失效：不同目标目录里出现同名 `.swift`（%s）⇒ 文件名口径不再精确，"
                   "请改用路径口径后重跑" % "、".join("%s（%s）" % (k, "/".join(v)) for k, v in sorted(duplicated.items())))

    # 范围外显式打印
    for name, target in sorted(targets.items()):
        if target["excludes"]:
            report.note("范围外（`%s` 的 excludes，均非 `.swift`）：%s" % (name, "、".join(target["excludes"])))

    generator = ledger.get("generator") or {}
    report.note("生成物登记：`%s %s`（命令 `%s`；postGen `%s`）——**版本不判红**（工具链漂移不该判红无关轮次），过期由 C1/C2/C3 判"
                % (generator.get("tool"), generator.get("version"), generator.get("command"), generator.get("postGen")))
    tool = shutil.which(generator.get("tool") or "")
    if tool:
        import subprocess
        try:
            out = subprocess.run([tool, "--version"], capture_output=True, text=True, timeout=30).stdout
        except (OSError, subprocess.SubprocessError) as error:  # pragma: no cover
            out = ""
            report.note("本机 `%s --version` 跑不起来：%s" % (generator.get("tool"), error))
        match = re.search(r"(\d+(?:\.\d+)+)", out or "")
        if match:
            actual = match.group(1)
            if actual != generator.get("version"):
                report.note("⚠️ 本机 `%s` 版本 = `%s`，台账登记 = `%s` —— 工具链变了；"
                            "**重生成一次并把台账 `generator.version` 一并更新**（本次不判红）"
                            % (generator.get("tool"), actual, generator.get("version")))
    else:
        report.note("本机没有 `%s`（判据不需要它 —— 比对的是文件内容，不是「谁跑过」）" % generator.get("tool"))


def check_anchors(root: pathlib.Path, ledger: dict, report: Report):
    """C4 —— 文档里的现状声明逐处对账。"""
    for anchor in ledger.get("anchors") or []:
        relative = anchor.get("path")
        text = read_text(root, relative, report)
        if text is None:
            continue
        try:
            pattern = re.compile(anchor.get("regex", ""), re.M)
        except re.error as error:
            report.bad("[台账] 锚点正则不合法（%s）：%s" % (relative, error))
            continue
        captures = anchor.get("captures") or []
        if pattern.groups != len(captures):
            report.bad("[台账] 锚点 %s 的正则有 %d 个捕获组、captures 有 %d 个（对不上）"
                       % (relative, pattern.groups, len(captures)))
            continue
        hits = list(pattern.finditer(text))
        minimum = int(anchor.get("minSites", 1))
        if len(hits) < minimum:
            report.bad("锚点 %s（%s）命中 %d 处，少于 minSites %d —— 现状声明被删了 / 改写了？"
                       % (relative, anchor.get("note") or "", len(hits), minimum))
            continue
        for hit in hits:
            for index, field in enumerate(captures):
                value = hit.group(index + 1)
                report.sites += 1
                if value != ledger[field]:
                    line = text[:hit.start()].count("\n") + 1
                    report.bad("%s:%d 写的是 `%s`，台账 `%s` = `%s`"
                               % (relative, line, value, field, ledger[field]))


def check(root: pathlib.Path):
    report = Report()
    ledger = load_ledger(root, report)
    if ledger is None:
        return report
    check_authority(root, ledger, report)
    targets = check_project_yml(root, ledger, report)
    pbx = check_pbxproj(root, ledger, report)
    check_structure(root, ledger, targets, pbx, report)
    check_anchors(root, ledger, report)
    if report.sites < FLOOR_ANCHOR_SITES:
        report.bad("空跑防护：全部比对点只有 %d 处（少于下限 %d）—— 判据被掏空了？"
                   % (report.sites, FLOOR_ANCHOR_SITES))
    return report


def run_gate(root: pathlib.Path, quiet: bool = False) -> int:
    report = check(root)
    if not quiet:
        for note in report.notes:
            print("ℹ️ %s" % note)
    if report.problems:
        print("❌ 发布产物版本号对账不通过（%d 处）：" % len(report.problems))
        for problem in report.problems:
            print("   · %s" % problem)
        print("RESULT: FAIL")
        return 1
    print("✅ 发布产物版本号三处逐字一致 + 生成物与 `project.yml` 不漂移（比对点 %d 处）" % report.sites)
    print("RESULT: OK")
    return 0


# --------------------------------------------------------------------------------------
# 自测（判据自己的证据）：夹具 = 真文件的副本 + 源目录软链（真仓库带 Vendor/，不能整份复制）
# --------------------------------------------------------------------------------------
FIXTURE_FILES = [
    "project.yml",
    "Scripts/build-app.sh",
    LEDGER,
    "DoyahStudio.xcodeproj/project.pbxproj",
    "Docs/发布方案.md",
    "AGENT-SPEC.md",
]
FIXTURE_LINKS = ["Core", "App", "Platform", "Tests", "TestsPlatform"]


def build_fixture(scratch: pathlib.Path, real_root: pathlib.Path) -> pathlib.Path:
    fixture = scratch / "repo"
    if fixture.exists():
        shutil.rmtree(str(fixture))
    for relative in FIXTURE_FILES:
        source = real_root / relative
        target = fixture / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(source), str(target))
    for relative in FIXTURE_LINKS:
        source = real_root / relative
        if source.is_dir():
            os.symlink(str(source), str(fixture / relative))
    return fixture


def edit(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError("夹具锚点失效：在 %s 里找不到 %r" % (path.name, old[:60]))
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def run_self_test() -> int:
    real_root = pathlib.Path(__file__).resolve().parent.parent
    cases = []

    def record(name: str, ok: bool, detail: str = "") -> None:
        cases.append((name, ok, detail))

    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-release-version-"))
    try:
        ledger_path = real_root / LEDGER
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        marketing = ledger["marketingVersion"]
        build = ledger["buildVersion"]
        shas_before = {
            relative: __import__("hashlib").sha256((real_root / relative).read_bytes()).hexdigest()
            for relative in FIXTURE_FILES + ["Scripts/release-version.json"]
        }

        # 例 1：干净夹具 ⇒ 通过
        fixture = build_fixture(scratch, real_root)
        report = check(fixture)
        record("例 1 干净夹具 ⇒ rc 0（%d 个比对点）" % report.sites, not report.problems,
               "；".join(report.problems[:2]))

        # 例 2：只改 project.yml 一处 ⇒ 判红并点名
        fixture = build_fixture(scratch, real_root)
        edit(fixture / "project.yml", 'MARKETING_VERSION: "%s"' % marketing,
             'MARKETING_VERSION: "9.9.9"')
        problems = check(fixture).problems
        record("例 2 只改 project.yml 的版本 ⇒ 判红", any("project.yml" in p and "9.9.9" in p for p in problems),
               "；".join(problems[:2]))

        # 例 3：只改生成物一处 ⇒ 判红
        fixture = build_fixture(scratch, real_root)
        edit(fixture / "DoyahStudio.xcodeproj/project.pbxproj",
             "CURRENT_PROJECT_VERSION = %s;" % build, "CURRENT_PROJECT_VERSION = 99;")
        problems = check(fixture).problems
        record("例 3 只改生成物的构建号 ⇒ 判红", any("pbxproj" in p and "99" in p for p in problems),
               "；".join(problems[:2]))

        # 例 4：只改权威处（Info.plist 模板）⇒ 判红
        fixture = build_fixture(scratch, real_root)
        edit(fixture / "Scripts/build-app.sh", "<string>%s</string>" % build, "<string>99</string>")
        problems = check(fixture).problems
        record("例 4 只改权威处（Info.plist 模板）⇒ 判红",
               any("build-app.sh" in p and "99" in p for p in problems), "；".join(problems[:2]))

        # 例 5：只改台账 ⇒ 判红（三处都与台账不一致）
        fixture = build_fixture(scratch, real_root)
        text = (fixture / LEDGER).read_text(encoding="utf-8")
        (fixture / LEDGER).write_text(text.replace('"marketingVersion": "%s"' % marketing,
                                                   '"marketingVersion": "9.9.9"', 1), encoding="utf-8")
        problems = check(fixture).problems
        record("例 5 只改台账的值 ⇒ 判红", len(problems) >= 3, "；".join(problems[:2]))

        # 例 6：生成物缺一个目标（改了 yml 忘重生成）⇒ 判红
        fixture = build_fixture(scratch, real_root)
        text = (fixture / "DoyahStudio.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        new_text, removed = re.subn(r"\n\t\t[A-F0-9]{24} /\* DoyahPlatformTests \*/ = \{\n.*?\n\t\t\};",
                                    "", text, count=1, flags=re.S)
        if removed != 1:
            raise AssertionError("夹具锚点失效：生成物里找不到 DoyahPlatformTests 目标块")
        (fixture / "DoyahStudio.xcodeproj/project.pbxproj").write_text(new_text, encoding="utf-8")
        problems = check(fixture).problems
        record("例 6 生成物少一个目标 ⇒ 判红（C1）", any("C1" in p for p in problems), "；".join(problems[:2]))

        # 例 7：生成物的 Sources 阶段少一个源文件 ⇒ 判红（C3）
        fixture = build_fixture(scratch, real_root)
        text = (fixture / "DoyahStudio.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        new_text, removed = re.subn(r"\n\t\t\t\t[A-F0-9]{24} /\* ([A-Za-z0-9_]+\.swift) in Sources \*/,",
                                    "", text, count=1)
        if removed != 1:
            raise AssertionError("夹具锚点失效：生成物的 Sources 阶段里找不到文件条目")
        (fixture / "DoyahStudio.xcodeproj/project.pbxproj").write_text(new_text, encoding="utf-8")
        problems = check(fixture).problems
        record("例 7 生成物少登记一个源文件 ⇒ 判红（C3）", any("C3" in p for p in problems), "；".join(problems[:2]))

        # 例 8：掏空生成物 ⇒ 判红（空跑防护）
        fixture = build_fixture(scratch, real_root)
        (fixture / "DoyahStudio.xcodeproj/project.pbxproj").write_text("// empty\n", encoding="utf-8")
        problems = check(fixture).problems
        record("例 8 掏空生成物 ⇒ 判红（空跑防护）",
               any("一个 PBXNativeTarget 都没解析到" in p for p in problems), "；".join(problems[:2]))

        # 例 9：文档锚点写错 ⇒ 判红
        fixture = build_fixture(scratch, real_root)
        edit(fixture / "Docs/发布方案.md", "| `%s` | `%s` |" % ("CFBundleVersion", build),
             "| `CFBundleVersion` | `7` |")
        problems = check(fixture).problems
        record("例 9 文档锚点写错 ⇒ 判红", any("发布方案.md" in p for p in problems), "；".join(problems[:2]))

        # 例 10：真仓库 —— 四份文件逐字节未变 + 真仓库实跑绿
        shas_after = {
            relative: __import__("hashlib").sha256((real_root / relative).read_bytes()).hexdigest()
            for relative in FIXTURE_FILES + ["Scripts/release-version.json"]
        }
        unchanged = all(shas_before[k] == shas_after[k] for k in shas_before)
        real_report = check(real_root)
        record("例 10 真仓库逐字节未变（%d 份）+ 真仓库实跑绿" % len(shas_before),
               unchanged and not real_report.problems,
               ("；".join(real_report.problems[:2]) if real_report.problems else "夹具动了真仓库" if not unchanged else ""))
    finally:
        shutil.rmtree(str(scratch), ignore_errors=True)

    good = sum(1 for _, ok, _ in cases if ok)
    for name, ok, detail in cases:
        print("%s %s%s" % ("✅" if ok else "❌", name, ("　— " + detail) if (detail and not ok) else ""))
    print("自测通过（%d 例）" % good if good == len(cases) else "自测失败：%d/%d" % (good, len(cases)))
    return 0 if good == len(cases) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="发布产物版本号三处一致 + 生成物不漂移（队列 L-70）")
    parser.add_argument("--root", default=None, help="仓库根（默认 = 脚本的上一级目录）")
    parser.add_argument("--self-test", action="store_true", help="跑判据自己的证据（夹具在临时目录）")
    args = parser.parse_args()
    if args.self_test:
        try:
            return run_self_test()
        except AssertionError as error:
            print("❌ 自测夹具错误：%s" % error)
            return 2
    root = pathlib.Path(args.root).resolve() if args.root else pathlib.Path(__file__).resolve().parent.parent
    if not (root / LEDGER).is_file():
        print("❌ 找不到台账 %s（--root 指对了吗？）" % (root / LEDGER))
        return 2
    return run_gate(root)


if __name__ == "__main__":
    sys.exit(main())
