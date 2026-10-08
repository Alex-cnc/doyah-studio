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
  **C3 磁盘侧的扫描口径：点开头的目录不算源码**（`.build` / `.build-cache` / `.swiftpm` / `.secrets`）。
  由头（任务 `t_7325ffbf`，2026-10-08 实测）：`platform/<平台>/` 是**自洽包**布局
  （`origin/migrate/platform-macos` 分支的树里 `platform/macos/Package.swift` 与
  `platform/macos/TestsUISnapshot/**` 都在——包根就在 `Platform/macOS`）⇒ 包自己那份 `.build/`
  落在**目标源目录之内**；切回 master 之后包的文件被 git 收走、被忽略的 `.build/` 留下 ⇒
  残留里的 `.swift` 被算成「该进工程而没进」⇒ **假红**（干净克隆上不出现，只在那台跑过包的机器上红）。
  跳过**不许静默**：每次实跑打印跳过了哪几处。
  **反向那一半也判**：生成物里**引用**了源目录点目录下的 `.swift` ⇒ 判红并点名（`xcodegen generate`
  会把残留收进工程，而这一条会因此**变绿** —— 最坏的那种绿；`project.yml` 的 `excludes` 是堵它的
  第一道，这条判据是第二道）。判据**不读 `.gitignore`**：自测夹具不是 git 仓库，口径取纯文件系统
  那一份（点目录 = 非源码），与 `.gitignore` 里 `.build/` 的收口同向。
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
    python3 Scripts/check-release-version.py --self-test   # 判据自己的证据（16 例）

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
    quoted = False
    for index, line in enumerate(lines):
        match = re.search(r"<<\s*('PLIST'|PLIST)", line)
        if match:
            start = index + 1
            # 带引号的 heredoc **不展开** `${…}`；`<<PLIST` 才展开 —— 发布标签靠这一条派生。
            quoted = match.group(1).startswith("'")
            break
    if start is None:
        return None, "没有找到 Info.plist 模板的 heredoc 起点（`<<'PLIST'` / `<<PLIST`）"
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

    # `<<PLIST`（不带引号）会展开模板里的 `${变量}` —— 把这种**引用**解析成 shell 里的定义值，
    # 这样「一处定义、两处派生」才有判据（派活单 `T-20261002-028`）。
    assignments = shell_assignments(text)
    resolved: dict = {}
    for key, sites in found.items():
        entries = []
        for value, line in sites:
            reference = re.fullmatch(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", value.strip())
            if reference and not quoted:
                name = reference.group(1)
                definitions = assignments.get(name) or []
                if len(definitions) != 1:
                    return None, ("模板第 %d 行用 `${%s}` 派生，但这个变量在本脚本里有 %d 处定义"
                                  "（只许一处）" % (line, name, len(definitions)))
                value = definitions[0][0]
            entries.append((value, line))
        resolved[key] = entries
    return resolved, None


def shell_assignments(text: str):
    """shell 里的字面量赋值：{变量名: [(值, 行号), …]}（只认 `NAME="值"` 独占一行的形状）。"""
    found: dict = {}
    for match in re.finditer(r"^[ \t]*([A-Za-z_][A-Za-z0-9_]*)=\"([^\"]*)\"[ \t]*$", text, re.M):
        line = text[:match.start()].count("\n") + 1
        found.setdefault(match.group(1), []).append((match.group(2), line))
    return found


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
#
# **点开头的目录不算源码**（构建残留 / 本机杂件）：口径与由头见文件头「C 生成物 ↔ 源」那一段。
# --------------------------------------------------------------------------------------
def swift_names_in(directory: pathlib.Path):
    """某个目录下**全部** `*.swift` 的名字（含点目录 —— 反向判据要用它认领生成物里的残留）。"""
    out = []
    stack = [directory]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(str(current)))
        except OSError:
            continue
        for entry in entries:
            if entry.is_dir(follow_symlinks=True):
                stack.append(pathlib.Path(entry.path))
            elif entry.name.endswith(".swift"):
                out.append(entry.name)
    return out


def swift_names_on_disk(root: pathlib.Path, relative: str):
    """源目录里的 `*.swift`（**点目录不算**）。

    返回 `(名字, 被跳过的点目录, 点目录里的 .swift 名字)`；源目录不存在 ⇒ `None`（调用方判红）。
    """
    base = root / relative
    if not base.is_dir():
        return None, [], []
    out, dot_dirs, dot_swift = [], [], []
    stack = [base]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(str(current)))
        except OSError:
            return None, [], []
        for entry in entries:
            if entry.name.startswith("."):
                # `.build` / `.build-cache` / `.swiftpm` / `.secrets`：`platform/<平台>/` 自洽包
                # 布局下包根就是源目录，包自己的 `.build/` 会落在源目录之内（实测见文件头）。
                if entry.is_dir(follow_symlinks=True):
                    dot_dirs.append(pathlib.Path(entry.path).relative_to(base).as_posix())
                    dot_swift.extend(swift_names_in(pathlib.Path(entry.path)))
                continue
            if entry.is_dir(follow_symlinks=True):
                stack.append(pathlib.Path(entry.path))
            elif entry.name.endswith(".swift"):
                out.append(entry.name)
    return sorted(out), sorted(dot_dirs), sorted(dot_swift)


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
    # 发布标签（派活单 `T-20261002-028`）：一处定义、两处派生 —— 台账要指名出处，否则判据没基准。
    label = ledger.get("releaseLabel")
    if not isinstance(label, str) or not re.match(r"^[A-Za-z][A-Za-z0-9]*\.\d+$", label):
        report.bad("[台账] releaseLabel 缺失或形状不对（期望 `<里程碑>.<子号>`，如 `alpha2.0`）：%r" % label)
    source = ledger.get("releaseLabelSource") or {}
    for field in ("path", "variable", "derivationAnchor", "plistKey"):
        if not source.get(field):
            report.bad("[台账] releaseLabelSource.%s 缺失（发布标签从哪派生要写清）" % field)
    policy = ledger.get("distPolicy") or {}
    for field in ("glob", "latestAlias", "keepAtLeast", "policy"):
        if not policy.get(field):
            report.bad("[台账] distPolicy.%s 缺失（别名与实物的口径没写清 = 判据只能猜）" % field)
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
        dot_dirs, dot_swift = [], []
        for source_dir in target["source_dirs"]:
            found, dirs, names = swift_names_on_disk(root, source_dir)
            if found is None:
                report.bad("C3 目标 `%s` 的源目录不存在：`%s`" % (name, source_dir))
                continue
            disk_swift.extend(found)
            dot_dirs.extend("%s/%s" % (source_dir, item) for item in dirs)
            dot_swift.extend(names)
        if dot_dirs:
            # 跳过不许静默：跳了哪几处、为什么跳，每次实跑都打出来。
            report.note("C3 目标 `%s`：源目录里的**点目录不算源码**（构建残留），已跳过 %d 处：%s"
                        % (name, len(dot_dirs), brief(dot_dirs)))
        if len(disk_swift) < FLOOR_SWIFT_PER_TARGET:
            report.bad("C3 目标 `%s` 的源目录里一个 `.swift` 都没找到（空跑防护）" % name)
        missing_in_pbx = sorted(set(disk_swift) - set(pbx_swift))
        leaked = sorted(set(pbx_swift) & set(dot_swift))
        if leaked:
            # 反向那一半：生成物**不许**引用点目录下的 `.swift` —— 那种「绿」是最坏的
            # （垃圾被收进生成物，同时把「磁盘上有、生成物里没有」这一条判红条件抵消掉）。
            report.bad("C3 目标 `%s`：生成物引用了源目录**点目录**下的 `.swift`：%s（%s）"
                       "—— `xcodegen generate` 把构建残留收进了工程；删掉残留重生成"
                       "（`project.yml` 的 `excludes` 是堵它的第一道，本条是第二道）"
                       % (name, brief(leaked), "、".join(dot_dirs)))
        missing_on_disk = sorted(set(pbx_swift) - set(disk_swift) - set(leaked))
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

    # 范围外显式打印（`xcodegen` 按这些条目**不收**进工程；点目录的构建残留就是靠它挡在门外）
    for name, target in sorted(targets.items()):
        if target["excludes"]:
            report.note("生成器排除项（`%s` 的 excludes，`xcodegen` 不收进工程）：%s"
                        % (name, "、".join(target["excludes"])))

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


def check_release_label(root: pathlib.Path, ledger: dict, report: Report):
    """B4 —— 发布标签：一处定义，产物名与 Info.plist 两处派生（派活单 `T-20261002-028`）。"""
    label = ledger["releaseLabel"]
    source = ledger["releaseLabelSource"]
    relative = source["path"]
    variable = source["variable"]
    plist_key = source["plistKey"]
    text = read_text(root, relative, report)
    if text is None:
        return
    sites = shell_assignments(text).get(variable) or []
    if not sites:
        report.bad("%s：没有 `%s=\"…\"` —— 发布标签没有出处，产物名与 Info.plist 从哪派生？"
                   % (relative, variable))
    elif len(sites) > 1:
        report.bad("%s：`%s` 定义了 %d 次（%s）—— 只许一处，否则又是多处副本"
                   % (relative, variable, len(sites),
                      "、".join("第 %d 行" % line for _, line in sites)))
    else:
        value, line = sites[0]
        report.sites += 1
        if value != label:
            report.bad("%s:%d 的 `%s` = `%s`，台账 `releaseLabel` = `%s`"
                       % (relative, line, variable, value, label))
    anchor = source["derivationAnchor"]
    if anchor not in text:
        report.bad("%s：找不到产物名派生式 `%s`（产物名被写死了 / 不再跟着发布标签走）"
                   % (relative, anchor))
    table, error = parse_plist_template(text)
    if table is None:
        report.bad("%s：%s" % (relative, error))
        return
    raw = re.search(r"<key>%s</key>[ \t]*\n[ \t]*<string>([^<]*)</string>" % re.escape(plist_key), text)
    if raw is None:
        report.bad("%s：Info.plist 模板里没有 `%s`（产物自己不带发布标签 = 认不出手上是哪份构建）"
                   % (relative, plist_key))
        return
    if raw.group(1).strip() != "${%s}" % variable:
        report.bad("%s：`%s` 的值是 `%s`，不是 `${%s}` —— 手抄第二份，将来必定漂移"
                   % (relative, plist_key, raw.group(1).strip(), variable))
    for value, line in table.get(plist_key) or []:
        report.sites += 1
        if value != label:
            report.bad("%s:%d 的 `%s` = `%s`，台账 `releaseLabel` = `%s`"
                       % (relative, line, plist_key, value, label))


def check_dist(root: pathlib.Path, ledger: dict, report: Report):
    """C5 —— `dist/` 实物：带版本号的包才是身份，别名只许是软链（派活单 `T-20261002-028`）。"""
    policy = ledger["distPolicy"]
    dist = root / "dist"
    if not dist.is_dir():
        report.note("dist/ 不在盘上 ⇒「实物」那一向本轮**跳过**（干净克隆 / 还没出过包）—— **跳过 ≠ 通过**")
        return
    label = ledger["releaseLabel"]
    packages = sorted(p for p in dist.glob(policy["glob"]) if p.is_dir())
    shaped = re.compile(r"^[A-Za-z][A-Za-z0-9]*\.[0-9]+$")
    for package in packages:
        suffix = package.name[len("DoyahStudio-"):-len(".app")]
        plist_path = package / "Contents" / "Info.plist"
        if not plist_path.is_file():
            report.bad("dist/%s 里没有 Contents/Info.plist（包不完整）" % package.name)
            continue
        plist_text = plist_path.read_text(encoding="utf-8", errors="replace")
        entry = re.search(r"<key>DoyahReleaseLabel</key>[ \t]*\n[ \t]*<string>([^<]*)</string>", plist_text)
        if shaped.match(suffix):
            report.sites += 1
            if entry is None:
                report.bad("dist/%s 的 Info.plist 没有 `DoyahReleaseLabel`（名字说是一个版本、包里没有身份）"
                           % package.name)
            elif entry.group(1) != suffix:
                report.bad("dist/%s 的 Info.plist `DoyahReleaseLabel` = `%s`，与包名那一截对不上"
                           % (package.name, entry.group(1)))
        else:
            report.note("dist/%s 的名字不是发布标签形状（留档件）—— 只登记，不判红" % package.name)
    wanted = dist / ("DoyahStudio-%s.app" % label)
    if not wanted.is_dir():
        report.bad("dist/ 在盘上，却没有带版本号的产物 `%s`（产物名没跟着发布标签走？）" % wanted.name)
    else:
        plist_path = wanted / "Contents" / "Info.plist"
        if plist_path.is_file():
            plist_text = plist_path.read_text(encoding="utf-8", errors="replace")
            for key, field in (("CFBundleShortVersionString", "marketingVersion"),
                               ("DoyahReleaseLabel", "releaseLabel")):
                entry = re.search(r"<key>%s</key>[ \t]*\n[ \t]*<string>([^<]*)</string>" % re.escape(key), plist_text)
                if entry is None:
                    report.bad("%s 的 Info.plist 里没有 `%s`" % (wanted.name, key))
                    continue
                report.sites += 1
                if entry.group(1) != ledger[field]:
                    report.bad("%s 的 Info.plist `%s` = `%s`，台账 `%s` = `%s`"
                               % (wanted.name, key, entry.group(1), field, ledger[field]))
        else:
            report.bad("%s 里没有 Contents/Info.plist（包不完整）" % wanted.name)
    alias = dist / "DoyahStudio.app"
    if alias.is_symlink():
        target = os.path.basename(os.readlink(str(alias)))
        report.sites += 1
        if target != wanted.name:
            report.bad("dist/DoyahStudio.app 指向 `%s`，不是当前发布标签那一份 `%s`" % (target, wanted.name))
    elif alias.exists():
        report.bad("dist/DoyahStudio.app 是**真目录** —— 不带版本号的路径只许是软链（身份 = 带版本号的实物）")
    else:
        report.note("dist/DoyahStudio.app 不存在（别名未建）—— 交付一律用带版本号那份")
    keep = policy["keepAtLeast"]
    report.note("dist/ 里带版本号的包 %d 个（%s）｜台账要求保留最近 ≥%s 个，策略 = %s"
                % (len(packages), "、".join(p.name for p in packages) or "无", keep, policy["policy"]))


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
    check_release_label(root, ledger, report)
    check_dist(root, ledger, report)
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
    "Docs/发布计划.md",
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


def add_dot_residue(fixture: pathlib.Path, real_root: pathlib.Path) -> None:
    """把夹具里的 `Platform` 换成**只含 `macOS/` 的真副本**，再往里造一个**点目录**残留。

    为什么要这一份夹具：`platform/<平台>/` 是**自洽包**布局（`origin/migrate/platform-macos` 的树里
    `platform/macos/Package.swift` + `platform/macos/TestsUISnapshot/**` 都在）⇒ **包根就是目标源目录**，
    包自己那份 `.build/` 落在源目录之内；切回 master 只剩这份被 git 忽略的残留。
    """
    link = fixture / "Platform"
    if link.is_symlink():
        link.unlink()
    elif link.exists():
        shutil.rmtree(str(link))
    shutil.copytree(str(real_root / "Platform" / "macOS"),
                    str(link / "macOS"),
                    ignore=shutil.ignore_patterns(".build", ".build-cache"))
    junk = link / "macOS" / ".build" / "ui-snapshot-scratch"
    junk.mkdir(parents=True, exist_ok=True)
    (junk / "probe-b.swift").write_text("// 构建残留：不是源码\n", encoding="utf-8")


def edit(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError("夹具锚点失效：在 %s 里找不到 %r" % (path.name, old[:60]))
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def make_fixture_dist(fixture: pathlib.Path, label: str, marketing: str,
                      plist_label=None, alias_target=None, alias_as_dir: bool = False) -> None:
    """合成一个 `dist/` 夹具（真产物几十 MB 且不进库）：只写判据会读的那几行。"""
    dist = fixture / "dist"
    package = dist / ("DoyahStudio-%s.app" % label)
    (package / "Contents").mkdir(parents=True, exist_ok=True)
    (package / "Contents" / "Info.plist").write_text(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n"
        "    <key>CFBundleShortVersionString</key>\n    <string>%s</string>\n"
        "    <key>DoyahReleaseLabel</key>\n    <string>%s</string>\n"
        "</dict>\n</plist>\n" % (marketing, plist_label or label), encoding="utf-8")
    alias = dist / "DoyahStudio.app"
    if alias_as_dir:
        alias.mkdir()
    else:
        os.symlink(alias_target or package.name, str(alias))


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
        label = ledger["releaseLabel"]
        variable = ledger["releaseLabelSource"]["variable"]
        shas_before = {
            relative: __import__("hashlib").sha256((real_root / relative).read_bytes()).hexdigest()
            for relative in FIXTURE_FILES + ["Scripts/release-version.json"]
        }

        # 例 1：干净夹具 + 源目录里的**点目录**残留 ⇒ 通过（点目录不算源码）；
        #       同一夹具再放一个点目录**之外**的 `.swift` ⇒ 判红（对照：跳过没有把判据掏空）
        fixture = build_fixture(scratch, real_root)
        add_dot_residue(fixture, real_root)
        with_residue = check(fixture)
        (fixture / "Platform" / "macOS" / "loose-stray.swift").write_text(
            "// 点目录之外的乱入源码（夹具用）\n", encoding="utf-8")
        with_stray = check(fixture).problems
        record("例 1 干净夹具（含源目录里的点目录残留）⇒ rc 0（%d 个比对点）；"
               "多一个点目录之外的 `.swift` ⇒ 判红" % with_residue.sites,
               not with_residue.problems and any("loose-stray.swift" in p for p in with_stray),
               "；".join(with_residue.problems[:2])
               or "没点名乱入的那个文件：" + "；".join(with_stray[:2]))

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

        # 例 11：发布标签的定义值被改 ⇒ 判红并点名
        fixture = build_fixture(scratch, real_root)
        edit(fixture / "Scripts/build-app.sh", 'RELEASE_LABEL="%s"' % label,
             'RELEASE_LABEL="alpha9.9"')
        problems = check(fixture).problems
        record("例 11 发布标签的定义值 ≠ 台账 ⇒ 判红",
               any("RELEASE_LABEL" in p for p in problems), "；".join(problems[:2]))

        # 例 12：Info.plist 模板里那处**引用**被手抄成字面量 ⇒ 判红（值还等于台账，只有「手抄」这一条能抓）
        fixture = build_fixture(scratch, real_root)
        edit(fixture / "Scripts/build-app.sh", "<string>${%s}</string>" % variable,
             "<string>%s</string>" % label)
        problems = check(fixture).problems
        record("例 12 plist 模板里手抄标签（不再引用变量）⇒ 判红",
               any("手抄第二份" in p for p in problems), "；".join(problems[:2]))

        # 例 13：产物名不再派生（写死）⇒ 判红
        fixture = build_fixture(scratch, real_root)
        edit(fixture / "Scripts/build-app.sh",
             'APP="${ROOT}/dist/DoyahStudio-${%s}.app"' % variable,
             'APP="${ROOT}/dist/DoyahStudio.app"')
        problems = check(fixture).problems
        record("例 13 产物名写死（不派生）⇒ 判红",
               any("派生式" in p for p in problems), "；".join(problems[:2]))

        # 例 14：合成 dist 且都对 ⇒ 绿（「实物」那一向真的量到了）
        fixture = build_fixture(scratch, real_root)
        make_fixture_dist(fixture, label, marketing)
        problems = check(fixture).problems
        record("例 14 dist 实物 + 别名都对 ⇒ 绿", not problems, "；".join(problems[:2]))

        # 例 15：包内身份与包名对不上 + 别名指向别处 ⇒ 两处都判红
        fixture = build_fixture(scratch, real_root)
        make_fixture_dist(fixture, label, marketing, plist_label="alpha9.9",
                          alias_target="DoyahStudio-alpha9.9.app")
        problems = check(fixture).problems
        record("例 15 实物身份对不上 + 别名指向别处 ⇒ 两处判红",
               any("对不上" in p for p in problems) and any("指向" in p for p in problems),
               "；".join(problems[:3]))

        # 例 16：别名做成真目录（不再是软链）⇒ 判红
        fixture = build_fixture(scratch, real_root)
        make_fixture_dist(fixture, label, marketing, alias_as_dir=True)
        problems = check(fixture).problems
        record("例 16 别名做成真目录 ⇒ 判红",
               any("只许是软链" in p for p in problems), "；".join(problems[:2]))

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
