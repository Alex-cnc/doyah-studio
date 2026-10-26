#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vendored SQLite 的台账门禁（FR-STD-ALL-PLUG-008 / Q23 拍板）。

**为什么需要一条台账而不是一句「已 vendoring」**：这份 `sqlite3.c` 是 9.5 MB 的生成文件，
换版本、手改一行、编译宏掉一个，**都不会有任何症状** —— 只会让三端行为悄悄不一致，
或者让「全文检索能用」这条判据在某天静默失效。所以每个事实都必须是**可对账**的：
内容哈希、头文件里的版本字符串、`Package.swift` 里的编译宏、许可声明、接线位置。

对账口径（任一条不一致 ⇒ 非零退出并指名）：

  1. `files[]` 里的每个交付文件：字节数 + SHA-256 与台账一致（含我们自己写的 umbrella 头）；
  2. 头文件里的 `SQLITE_VERSION` / `SQLITE_VERSION_NUMBER` / `SQLITE_SOURCE_ID` 与台账一致；
  3. `Vendor/sqlite3/Package.swift` 的编译宏与台账 `requiredCompileOptions` 逐条一致
     （**宏掉了不会有症状**，只有行为悄悄变），目标名 / 源码 / 公共头目录也对账；
  4. 许可声明文件在、且写明公有领域与来源页（用户看的是这一份）；
  5. `PROVENANCE.md` 里的归档哈希与台账 `archiveSHA256` 一致（换版本时两处必须同时改）；
  6. `THIRD-PARTY-NOTICES.md` 里有这一行（第三方组件声明表是给人看的入口）；
  7. 根 `Package.swift` 里真的接线了这个包；
  8. **没有第二份 SQLite**：产品源码里不许出现 `import SQLite3`（系统自带 libsqlite3 版本随 OS 漂移，
     FR-STD-ALL-PLUG-008 的口径就是「三端同一份引擎」）；
  9. `wiring.evidenceAnchors` 里的每个锚点在盘上真的还在（锚点陈旧 = 台账还指着证据、证据已经没了）；
 10. `wiring.inVerifyAll` 里的项号与 `verify-all.sh` 实际的项号一致，且**闭环自己的项号是自洽的**
     （`==> N/M` 标记个数 == 声明的 M、项号连续 —— 「加了项忘了改计数」与先前的假绿同族）。
     第 9 / 10 条是第 18 轮补的：门禁与自证**不进闭环就永远不跑**，而这类「接线悄悄断掉」本身没有任何症状。
 11. `generator` 节点里的「生成器 ↔ 生成物 ↔ vendored 头文件」三份文件都在盘上，`verify-all.sh` 里
     真的跑 `gen-sqlite-constants.py --check` 与 `--self-test`，且台账写的项号 == 闭环实际项号。
     第 11 条是第 30 轮（L-43）补的：**生成物漂移没有任何症状** —— 手改一行生成物、或头文件换版后
     忘了重生成，编译照过、单测照绿，只有三端行为悄悄不一致（`--check` 此前确实存在，
     但生成器自己的头部就写着「未接进 verify-all」⇒ 有判据、没闭环）。
 12. **判定面**由根 `Package.swift` 的 target **现读**（`sources:` 优先、其次 `path:`、再次 target 名；
     多根如 `Core` + `Plugins/Notes/Sources` 一并进面），面内扫 + **面外回流**两臂；判「在盘上 /
     在闭环里」一律读**剥注释后的正文**（`.sh` 走活行、`.py` 剥 `#`、C 族剥 `//` 与块注释），
     `import` 那类再抹掉字符串字面量；`files[]` / `requiredCompileOptions` / `evidenceAnchors` /
     面根数各有**硬下限**（写死在脚本里 —— 清空台账不该等于关掉一整类对账）。
     第 12 条是 2026-10-13（合册 `T-20261013-027` · 原单 `T-20261010-059`）补的：实测三簇假绿 ——
     ①把接线**注释掉**仍 rc=0（对照：整行删即红）；②锚点/宏/根接线同样只判子串 ⇒ 只剩一行注释也过；
     ③判定面无下限（清空 `requiredCompileOptions` + 删光宏 ⇒ rc=0，成功行还写着「0 条编译宏」）、
     面写死 6 个目录（同为 test 的 `TestsPlatform/` 静默在面外，P3 rc=0）。

负例（`--self-test`）：**25 例** = 篡改 23 条（上面几类各造一遍，确认门禁**真的会红**）+ 对手臂 2 条
（「块注释里的 `import`」与「别项注释里提到命令名」**不许**误报 —— 分不出「注释里提过」与
「代码里长出来」的判据会逼着人把真判据拆掉）。另有前提自检：干净副本必须绿（L-119：沙箱缺文件
会让整族负例假绿）。门禁自己也要有证据，否则它只是「看着在跑」。

用法：
    python3 Scripts/check-vendored-sqlite.py            # 门禁
    python3 Scripts/check-vendored-sqlite.py --self-test # 负例自检（25 例）
    python3 Scripts/check-vendored-sqlite.py --root <目录> # 夹具仓

退出码：0 = 全绿；1 = 判红；2 = **判据自身坏掉**（不留栈、已收集的诊断照打 —— 过去崩了只吐栈、
rc 与「判红」同为 1，CI 里不可分）。

（历史：第 18 轮 L-25 第 1 批。Swift 侧的绑定层因工具链的显式模块构建缺陷暂时未接线，
 证据与排除过程见 `Docs/archive/root-20261026/开发记录-20260926-任务批.md` **§28**（该文件是开发循环的连续记录，
 文件名里的日期是它的起点日期）与 `Docs/design/待接线-SQLiteKit/读我.md`。）
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# 产品里不许出现系统 SQLite 的模块（口径见 FR-STD-ALL-PLUG-008：三端同一份引擎）。
PRODUCT_DIRS = ["Core", "Platform", "App", "CLI", "Tools", "Tests"]
SYSTEM_SQLITE_IMPORT = re.compile(r"^\s*import\s+SQLite3\b", re.MULTILINE)

# 判定物口径（2026-10-13 · 合册 T-20261013-027 · 原单 T-20261010-059）：
# 本仓实测过一整族同形缺陷 —— **一行注释**就能满足一条子串判据（对照：整行删掉当场判红）。
# 所以凡判「在盘上 / 在闭环里」的地方，判定物一律取**剥掉注释之后**的正文；`import` 这类
# 还要把字符串字面量抹掉（写在串里的一句不算真 import）。**有意住在注释里**的锚点（如生成物
# 的「本文件由…生成」）走台账 `wiring.docAnchors` 显式登记并写理由 —— 未登记不许豁免。
COMMENT_STYLE = {".swift": "c", ".h": "c", ".c": "c", ".m": "c", ".py": "python", ".sh": "shell"}

# 判定面 / 判定物的**硬下限**（写死在脚本里、不读台账 —— 台账被清空时下限不该跟着消失）。
# 由头：原单 ㈢ P5 —— 清空 `requiredCompileOptions` + 删光 vendored 宏 ⇒ 旧版 rc=0，成功行还
# 自己把证据写成「0 条编译宏」。下限照既有 `evidenceAnchors` 那条口径补齐。
MIN_DELIVERED_FILES = 3
MIN_COMPILE_OPTIONS = 4
MIN_EVIDENCE_ANCHORS = 1
# 判定面根数下限：面由 `Package.swift` 现读（不写死目录），这条下限防「面被削成一个目录」。
MIN_FACE_ROOTS = 8

# 面外回流那一臂要跳过的根（第三方面 / 构建产物 / 工作树 / 脚本与文档面）。
EXCLUDED_ROOTS = {"Vendor", ".build", ".git", ".worktrees", ".dsh", "Scripts", "Docs",
                  "Resources", "assets", "DoyahStudio.xcodeproj"}

# 台账必须有的顶层字段（缺字段 ⇒ 点名判红；旧版是 KeyError 栈）。
LEDGER_KEYS = ("component", "version", "versionNumber", "sourceID", "downloadURL", "archiveSHA256",
               "licenseFile", "files", "requiredCompileOptions", "swiftTarget", "generator", "wiring")


def strip_comments(text: str, style: str | None) -> str:
    """剥注释，**保留字符串字面量**（`style="c"` 认 `//` 与 `/* */`；`"python"` 认 `#`）。

    为什么字符串要留：本仓的锚点有住在字符串里的（`tokenize = 'trigram'` 是 SQL 文本、
    `.product(name: "CSQLite3", …)` 是清单行）—— 一律抹掉字符串会把真证据一起判没。
    """
    if not style:
        return text
    out: list[str] = []
    index, length, quote = 0, len(text), None
    while index < length:
        char = text[index]
        if quote:
            out.append(char)
            if char == "\\" and index + 1 < length:
                out.append(text[index + 1])
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue
        if char in "\"'":
            quote = char
            out.append(char)
            index += 1
            continue
        if style == "c" and text.startswith("//", index):
            while index < length and text[index] != "\n":
                index += 1
            continue
        if style == "c" and text.startswith("/*", index):
            end = text.find("*/", index + 2)
            index = length if end < 0 else end + 2
            continue
        if style == "python" and char == "#":
            while index < length and text[index] != "\n":
                index += 1
            continue
        out.append(char)
        index += 1
    return "".join(out)


def blank_strings(text: str) -> str:
    """把字符串字面量的**内容**抹成空格（引号留着）—— 挡「串里提过一句」这类假证据。"""
    out: list[str] = []
    index, length, quote = 0, len(text), None
    while index < length:
        char = text[index]
        if quote:
            if char == "\\" and index + 1 < length:
                out.append("  ")
                index += 2
                continue
            if char == quote:
                quote = None
                out.append(char)
                index += 1
                continue
            out.append("\n" if char == "\n" else " ")
            index += 1
            continue
        if char in "\"'":
            quote = char
        out.append(char)
        index += 1
    return "".join(out)


def active_shell(text: str) -> str:
    """shell 的「活行」：整行 `#` 的丢掉，` #` 之后的尾巴切掉。

    由头（原单 ㈠/㈥）：`# python3 Scripts/xxx.py` 这种**手工停用**是现实里最常见的一形，
    旧版读原文 ⇒ 注释掉仍 rc=0；别项块里一句注释提到命令名还会把「接线在第几项」判偏。
    """
    lines: list[str] = []
    for line in text.split("\n"):
        if line.lstrip().startswith("#"):
            continue
        cut = line.find(" #")
        lines.append(line[:cut] if cut >= 0 else line)
    return "\n".join(lines)


def comment_free(text: str, path) -> str:
    """按扩展名选口径（`.sh` 走活行、`.py` 剥 `#`、C 族剥 `//` 与块注释、其余原样）。"""
    style = COMMENT_STYLE.get(pathlib.Path(path).suffix)
    if style == "shell":
        return active_shell(text)
    return strip_comments(text, style)


# 判定面**从 `Package.swift` 现读**（原单 ㈣）：旧版把 6 个目录名写死 ⇒ 同为 test 根的
# `TestsPlatform/` / `TestsUISnapshot/` 静默落在面外（实测 P3 rc=0、对照放面内 rc=1）。
TARGET_OPENER = re.compile(r"\.(?:target|executableTarget|testTarget|plugin|systemLibrary|macro)\(")
TARGET_NAME = re.compile(r'name:\s*"([^"]+)"')
TARGET_PATH = re.compile(r'^\s*path:\s*"([^"]+)"', re.MULTILINE)
TARGET_SOURCES = re.compile(r'^\s*sources:\s*\[([^\]]*)\]', re.MULTILINE | re.DOTALL)


def declared_face(manifest_text: str) -> list[str]:
    """`Package.swift` 的每个 target → 它自己的源码根（`sources:` 优先，其次 `path:`，再次 target 名）。

    只认仓库内的相对路径（绝对路径是**包依赖**的写法，不是 target 的源码根）。
    """
    clean = strip_comments(manifest_text, "c")
    openers = list(TARGET_OPENER.finditer(clean))
    roots: list[str] = []
    for index, opener in enumerate(openers):
        end = openers[index + 1].start() if index + 1 < len(openers) else len(clean)
        chunk = clean[opener.end():end]
        sources = TARGET_SOURCES.search(chunk)
        if sources:
            roots.extend(re.findall(r'"([^"]+)"', sources.group(1)))
            continue
        path = TARGET_PATH.search(chunk)
        if path and path.group(1) != ".":
            roots.append(path.group(1))
            continue
        name = TARGET_NAME.search(chunk)
        roots.extend(PRODUCT_DIRS if path else ([name.group(1)] if name else []))
    ordered: list[str] = []
    for root in roots:
        if not root or root.startswith("/") or root.startswith("."):
            continue
        if root not in ordered:
            ordered.append(root)
    return ordered

# `verify-all.sh` 的项标记形状：`echo "==> 7/17 …"`
VERIFY_ITEM = re.compile(r"==> (\d+)/(\d+) ")

# 沙箱基座（**不是全集**）：真正要拷哪些路径由 `self_test_targets()` 从台账派生 ——
# 写死清单的代价（L-119，第 490 轮实测）：台账 `wiring.evidenceAnchors` 点名的三份文件
# 没进清单 ⇒ 干净副本上 `check_evidence_anchors` 本来就红 ⇒ 下面 13 条负例**全部假绿**
# （判据是「内层 rc != 0」，而 rc 因为环境原因恒 != 0）。
SELF_TEST_TARGETS = [
    "Vendor/sqlite3",
    "Scripts/vendored-sqlite.json",
    "Scripts/smoke-vendored-sqlite.py",
    "Scripts/verify-all.sh",
    "Scripts/gen-sqlite-constants.py",
    "THIRD-PARTY-NOTICES.md",
    "Package.swift",
]


def self_test_targets(root: pathlib.Path) -> list[str]:
    """负例沙箱要拷的路径 —— **从台账派生**（锚点写死过一次，代价见上）。

    由三处派生：交付文件 `files[].path` / `swiftTarget.header` / `licenseFile` /
    `wiring.evidenceAnchors[].file`，再并上基座里那几份「接线所在」的脚本。
    台账新增一处证据锚点 ⇒ 沙箱自动跟上，不会又悄悄回到「干净副本也红」的假绿。
    """
    ledger = json.loads((root / "Scripts" / "vendored-sqlite.json").read_text(encoding="utf-8"))
    derived = list(SELF_TEST_TARGETS)
    derived += [entry["path"] for entry in ledger.get("files", [])]
    derived.append(ledger["swiftTarget"]["header"])
    derived.append(ledger["licenseFile"])
    derived += [anchor["file"] for anchor in ledger.get("wiring", {}).get("evidenceAnchors", [])]
    # 判定面根（`Package.swift` 现读）也拷进沙箱 —— 面变了沙箱跟着变，不必有人记得改本清单。
    manifest = root / "Package.swift"
    if manifest.exists():
        face = declared_face(manifest.read_text(encoding="utf-8"))
        assert len(face) >= MIN_FACE_ROOTS, f"判定面只有 {len(face)} 个根（下限 {MIN_FACE_ROOTS}）"
        derived += face
    ordered: list[str] = []
    for target in derived:
        if target not in ordered:
            ordered.append(target)
    return ordered


def item_blocks(script_text: str) -> dict[int, str]:
    """`==> N/M` 项标记 → 该项自己的正文（到下一个标记为止）。

    「接线在哪一项」这种判断必须按**块**来，不能全文搜一遍关键字 —— 否则把某条命令
    贴在别项的注释里也能骗过门禁（第 18 轮那批负例就是冲这个形状去的）。
    """
    markers = [(match.start(), int(match.group(1)), int(match.group(2))) for match in VERIFY_ITEM.finditer(script_text)]
    blocks: dict[int, str] = {}
    for index, (start, number, _) in enumerate(markers):
        end = markers[index + 1][0] if index + 1 < len(markers) else len(script_text)
        blocks[number] = script_text[start:end]
    return blocks


class Gate:
    def __init__(self, root: pathlib.Path) -> None:
        self.root = root
        self.failures: list[str] = []
        self.face_cache: list[str] | None = None
        self.anchor_counts: tuple[int, int] = (0, 0)

    def fail(self, message: str) -> None:
        self.failures.append(message)

    def ledger(self) -> dict:
        return json.loads((self.root / "Scripts" / "vendored-sqlite.json").read_text(encoding="utf-8"))

    def check_files(self, ledger: dict) -> None:
        for entry in ledger["files"]:
            path = self.root / entry["path"]
            if not path.exists():
                self.fail(f"交付文件不在：{entry['path']}")
                continue
            blob = path.read_bytes()
            if len(blob) != entry["bytes"]:
                self.fail(f"{entry['path']} 字节数不符：台账 {entry['bytes']}，实际 {len(blob)}")
            digest = hashlib.sha256(blob).hexdigest()
            if digest != entry["sha256"]:
                self.fail(f"{entry['path']} SHA-256 不符：台账 {entry['sha256'][:16]}…，实际 {digest[:16]}…")

    def check_header_version(self, ledger: dict) -> None:
        header = self.root / ledger["swiftTarget"]["header"]
        if not header.exists():
            self.fail(f"头文件不在：{ledger['swiftTarget']['header']}")
            return
        text = header.read_text(encoding="utf-8", errors="replace")
        expectations = [
            (r'#define SQLITE_VERSION\s+"([^"]+)"', ledger["version"], "SQLITE_VERSION"),
            (r"#define SQLITE_VERSION_NUMBER\s+(\d+)", str(ledger["versionNumber"]), "SQLITE_VERSION_NUMBER"),
            (r'#define SQLITE_SOURCE_ID\s+"([^"]+)"', ledger["sourceID"], "SQLITE_SOURCE_ID"),
        ]
        for pattern, expected, label in expectations:
            match = re.search(pattern, text)
            if not match:
                self.fail(f"头文件里找不到 {label}")
            elif match.group(1) != expected:
                self.fail(f"{label} 与台账不符：台账 {expected}，头文件 {match.group(1)}")

    def check_vendored_manifest(self, ledger: dict) -> None:
        manifest = self.root / "Vendor" / "sqlite3" / "Package.swift"
        if not manifest.exists():
            self.fail("Vendor/sqlite3/Package.swift 不在")
            return
        text = strip_comments(manifest.read_text(encoding="utf-8"), "c")
        target = ledger["swiftTarget"]
        for option in ledger["requiredCompileOptions"]:
            define, value = option["define"].split("=", 1)
            pattern = re.compile(rf'\.define\(\s*"{re.escape(define)}"\s*,\s*to:\s*"{re.escape(value)}"\s*\)')
            if not pattern.search(text):
                self.fail(f"编译宏掉了或值不对：{option['define']}（{option['why']}）")
        if f'name: "{target["name"]}"' not in text:
            self.fail(f'vendored 包里的目标名不是 {target["name"]}')
        if f'publicHeadersPath: "{target["publicHeadersPath"]}"' not in text:
            self.fail(f'publicHeadersPath 不是 {target["publicHeadersPath"]}（SwiftPM 只在这里找头文件）')
        if f'path: "{target["targetPath"]}"' not in text:
            self.fail(f'clang 目标的 path 不是 {target["targetPath"]}')
        # 源码文件必须在盘上（manifest 里只有目录，文件名靠 SwiftPM 自动发现）
        for source in target["sources"]:
            if not (self.root / target["path"] / source).exists():
                self.fail(f"vendored 包的源码不在盘上：{target['path']}/{source}")

    def check_license(self, ledger: dict) -> None:
        license_path = self.root / ledger["licenseFile"]
        if not license_path.exists():
            self.fail(f"许可声明文件不在：{ledger['licenseFile']}")
            return
        text = license_path.read_text(encoding="utf-8").lower()
        if "public domain" not in text:
            self.fail("许可声明里没有 public domain 字样")
        if "sqlite.org/copyright.html" not in text:
            self.fail("许可声明里没有指向来源页（sqlite.org/copyright.html）")

    def check_provenance(self, ledger: dict) -> None:
        provenance = self.root / "Vendor" / "sqlite3" / "PROVENANCE.md"
        if not provenance.exists():
            self.fail("Vendor/sqlite3/PROVENANCE.md 不在")
            return
        text = provenance.read_text(encoding="utf-8")
        if ledger["archiveSHA256"] not in text:
            self.fail("PROVENANCE.md 的归档哈希与台账不一致（换版本时两处必须同时改）")
        if ledger["downloadURL"] not in text:
            self.fail("PROVENANCE.md 里没有下载地址")

    def check_third_party_notice(self, ledger: dict) -> None:
        notice = self.root / "THIRD-PARTY-NOTICES.md"
        if not notice.exists():
            self.fail("THIRD-PARTY-NOTICES.md 不在")
            return
        if "sqlite-amalgamation" not in notice.read_text(encoding="utf-8"):
            self.fail("THIRD-PARTY-NOTICES.md 里没有 sqlite-amalgamation 这一行")

    def check_wiring(self) -> None:
        manifest = self.root / "Package.swift"
        if not manifest.exists():
            self.fail("根 Package.swift 不在")
            return
        text = strip_comments(manifest.read_text(encoding="utf-8"), "c")
        if '.package(path: "Vendor/sqlite3")' not in text:
            self.fail("根 Package.swift 没有接线 Vendor/sqlite3"
                      "（剥注释后找不到 —— 把接线注释掉不算接线）")

    def face_roots(self) -> list[str]:
        """判定面 = `Package.swift` 现读的 target 源码根 ∪ 产品目录里真在盘上的那几个。

        `sources:` 里的多根（`Core` + `Plugins/Notes/Sources`）与 `path:` 指的目录一并进面 ——
        「同模块搬家」之后新根自动进面，不必再有人记得来改这份清单。
        """
        if self.face_cache is None:
            manifest = self.root / "Package.swift"
            if not manifest.exists():
                self.fail("根 Package.swift 不在（判定面读不出来 ⇒ 面外的代码无人扫）")
                self.face_cache = []
            else:
                roots = declared_face(manifest.read_text(encoding="utf-8"))
                for directory in PRODUCT_DIRS:
                    if (self.root / directory).is_dir() and directory not in roots:
                        roots.append(directory)
                if len(roots) < MIN_FACE_ROOTS:
                    self.fail(f"判定面只有 {len(roots)} 个根（下限 {MIN_FACE_ROOTS}）"
                              f"—— `Package.swift` 的 target 被削了？实读 {roots}")
                self.face_cache = roots
        return self.face_cache

    def check_no_second_sqlite(self) -> None:
        """产品面里不许出现 `import SQLite3`（口径见 FR-STD-ALL-PLUG-008：三端同一份引擎）。两臂：

        · **面靠 `Package.swift` 现读**（原单 ㈣）：旧版写死 6 个目录名 ⇒ 面外的 test 根静默放过；
        · **面外回流**（同族反向）：面外目录里出现 `import SQLite3` 也判红 —— 只靠「面内扫」
          挡不住「把文件放进没人扫的目录」，而哪些目录在面内恰恰由这条判据自己决定。
        判定物 = 剥注释 + 抹字符串（原单 ㈤：块注释里的 import 与真 import 判成同一件事，
        两个都红、话术逐字相同 ⇒ 分不出「注释里提过」与「代码里长出来」）。
        """
        face = self.face_roots()
        scanned = 0
        for directory in face:
            base = self.root / directory
            if not base.is_dir():
                continue
            for path in sorted(base.rglob("*.swift")):
                scanned += 1
                if SYSTEM_SQLITE_IMPORT.search(self.active_source(path)):
                    self.fail(f"{path.relative_to(self.root)} 里 import 了系统 SQLite3"
                              f"（口径：三端同一份 vendored 引擎）")
        if scanned == 0:
            self.fail(f"判定面 {face} 里一份 `.swift` 都没扫到（面读歪了？空面 = 假绿）")
        for path in self.out_of_face_sources(face):
            if SYSTEM_SQLITE_IMPORT.search(self.active_source(path)):
                self.fail(f"面外回流：{path.relative_to(self.root)} 不在判定面内，"
                          f"却 import 了系统 SQLite3（面 = `Package.swift` 现读；放面外不算过）")

    def active_source(self, path: pathlib.Path) -> str:
        """源码的判定物 = 剥注释 + 抹字符串（注释与串里的 import 都不算）。"""
        raw = path.read_text(encoding="utf-8", errors="replace")
        return blank_strings(comment_free(raw, path))

    def out_of_face_sources(self, face: list[str]) -> list[pathlib.Path]:
        """面外目录里的 `.swift`（跳过第三方面 / 构建产物 / 工作树 / 脚本与文档面）。"""
        inside = [self.root / directory for directory in face]
        found: list[pathlib.Path] = []
        for base, dirs, names in os.walk(self.root):
            here = pathlib.Path(base)
            if here == self.root:
                dirs[:] = [name for name in dirs if name not in EXCLUDED_ROOTS]
            if any(here == root or root in here.parents for root in inside):
                dirs[:] = []
                continue
            found.extend(here / name for name in names if name.endswith(".swift"))
        return found

    def check_floors(self, ledger: dict) -> None:
        """判定面的**下限**（原单 ㈢）：清空 `requiredCompileOptions` / 删掉 `files[]` 条目就等于
        把一整类对账关掉，而门禁照样绿、成功行还替它作证（「0 条编译宏」）。下限写死在脚本里。
        """
        counts = {
            "files": len(ledger.get("files") or []),
            "requiredCompileOptions": len(ledger.get("requiredCompileOptions") or []),
            "evidenceAnchors": len((ledger.get("wiring") or {}).get("evidenceAnchors") or []),
        }
        for key, minimum in (("files", MIN_DELIVERED_FILES),
                             ("requiredCompileOptions", MIN_COMPILE_OPTIONS),
                             ("evidenceAnchors", MIN_EVIDENCE_ANCHORS)):
            if counts[key] < minimum:
                self.fail(f"台账 {key} 只有 {counts[key]} 条 < 判据硬下限 {minimum} —— "
                          f"判定面被自削（「宏掉了没有症状」：清空台账 = 关掉这类对账）")

    def check_ledger_shape(self, ledger: dict) -> None:
        """台账的**必需字段**（原单 ㈦）：缺字段过去是 `KeyError` 栈、且已收集的诊断一条不打印
        （rc 同为 1，CI 里与「判红」不可分）。现在缺字段点名，诊断照打。
        """
        for key in LEDGER_KEYS:
            if ledger.get(key) in (None, "", [], {}):
                self.fail(f"台账缺 `{key}`（缺字段不许让判据崩 —— 点名，并把已收集的诊断照打）")
        target = ledger.get("swiftTarget") or {}
        for key in ("name", "path", "targetPath", "header", "sources", "publicHeadersPath"):
            if key not in target:
                self.fail(f"台账 swiftTarget 缺 `{key}`（头文件 / 目标形状对不了账）")

    def check_evidence_anchors(self, ledger: dict) -> None:
        """台账登记的「证据锚点」必须还在**正文**里（原单 ㈡，P4 实测）。

        旧版读原文 ⇒ 把锚点全改名、只在文件尾留一行 `# 旧实现曾用 journal_mode 这个词（锚点已被
        重构掉）` 就仍 rc=0（输出与基线逐字同、仍报「17 条证据锚点」）。现在代码位锚点读剥注释后的
        正文；**有意住在注释里**的锚点（生成物头注释那种）走 `wiring.docAnchors` 显式登记 + 写理由，
        且登记项必须与证据锚点一一配对（没登记的锚点不许豁免、登记了不存在的锚点判红）。
        """
        wiring = ledger.get("wiring") or {}
        anchors = wiring.get("evidenceAnchors") or []
        doc_anchors = wiring.get("docAnchors") or []
        if len(anchors) < MIN_EVIDENCE_ANCHORS:
            self.fail(f"台账 wiring.evidenceAnchors 只有 {len(anchors)} 条（下限 "
                      f"{MIN_EVIDENCE_ANCHORS}；证据锚点是给人照着找的入口，不许清空）")
            return
        registered = {(entry.get("file"), entry.get("anchor")) for entry in anchors}
        for entry in doc_anchors:
            key = (entry.get("file"), entry.get("anchor"))
            if key not in registered:
                self.fail(f"文档锚点 {entry.get('file')} :: `{entry.get('anchor')}` 没有对应的证据锚点"
                          f"（豁免只许给在册锚点）")
            if not entry.get("why"):
                self.fail(f"文档锚点 {entry.get('file')} 没写理由（「住在注释里」必须逐条说清）")
        doc_keys = {(entry.get("file"), entry.get("anchor")) for entry in doc_anchors}
        code_count = 0
        for anchor in anchors:
            path = self.root / anchor["file"]
            if not path.exists():
                self.fail(f"证据锚点所在文件不在：{anchor['file']}")
                continue
            raw = path.read_text(encoding="utf-8", errors="replace")
            if (anchor.get("file"), anchor.get("anchor")) in doc_keys:
                position, text = "文档", raw
            else:
                position, text = "代码", comment_free(raw, anchor["file"])
                code_count += 1
            if anchor["anchor"] not in text:
                self.fail(f"证据锚点陈旧（{position}位）：台账指向 {anchor['file']} 里的 "
                          f"`{anchor['anchor']}`，剥注释后找不到（{anchor['why']}）")
        self.anchor_counts = (code_count, len(doc_anchors))

    def check_verify_all_wiring(self, ledger: dict) -> None:
        """门禁与自证必须真的在闭环里，且闭环自己的项号是自洽的。

        「加了项忘了改计数」在这个仓有过先例（第 10 项那次假绿同族）：项标记写着 `N/16`、
        实际跑的是 17 项，或者新项压根没进 `verify-all.sh` —— 两种都不会有任何症状。
        """
        script = self.root / "Scripts" / "verify-all.sh"
        if not script.exists():
            self.fail("Scripts/verify-all.sh 不在")
            return
        text = active_shell(script.read_text(encoding="utf-8"))
        for name in ("check-vendored-sqlite.py", "smoke-vendored-sqlite.py"):
            if f"python3 Scripts/{name}" not in text:
                self.fail(f"接线不在：verify-all.sh 里没有 `python3 Scripts/{name}`（不进闭环就永远不跑）")
        if "check-vendored-sqlite.py --self-test" not in text:
            self.fail("接线不在：verify-all.sh 里没跑台账门禁的负例（`--self-test`）—— 门禁自己是没被验过的")

        markers = [(match.start(), int(match.group(1)), int(match.group(2))) for match in VERIFY_ITEM.finditer(text)]
        if not markers:
            self.fail("verify-all.sh 里找不到 `==> N/M` 项标记（闭环的项号是给人读的，不许没有）")
            return
        totals = sorted({marker[2] for marker in markers})
        if len(totals) != 1:
            self.fail(f"verify-all.sh 的项数声明不一致：{totals}（改项数时漏改了几处）")
        if len(markers) != totals[0]:
            self.fail(f"verify-all.sh 实际有 {len(markers)} 个项标记，但声明总数是 {totals[0]}")
        numbers = [marker[1] for marker in markers]
        if numbers != list(range(1, len(markers) + 1)):
            self.fail(f"verify-all.sh 的项号不连续或有重复：{numbers}")

        declared = re.search(r"第\s*(\d+)\s*项", ledger.get("wiring", {}).get("inVerifyAll", ""))
        if not declared:
            self.fail("台账 wiring.inVerifyAll 里没写「第 N 项」（写了才判得出漂移）")
            return
        blocks = item_blocks(text)
        actual = next((number for number, block in blocks.items() if "smoke-vendored-sqlite.py" in block), None)
        if actual is None:
            self.fail("verify-all.sh 里 `smoke-vendored-sqlite.py` 不在任何一项的块内")
        elif actual != int(declared.group(1)):
            self.fail(f"台账项号与 verify-all.sh 不符：台账写第 {declared.group(1)} 项，实际在第 {actual} 项")

    def check_generator_binding(self, ledger: dict) -> None:
        """「生成器 ↔ 生成物 ↔ vendored 头文件」三者的绑定（第 11 条，L-43，第 30 轮）。

        为什么单列一条：生成物漂移**没有任何症状** —— 手改一行生成物、或头文件换版后忘了
        重生成，编译照过、单测照绿，只有三端行为悄悄不一致。而这条绑定此前只写在生成器
        自己的 docstring 里（还没接进闭环），等于没人守。这里把「台账怎么写」与
        「闭环里到底跑没跑、跑在第几项」变成可对账的两件事。
        """
        generator = ledger.get("generator")
        if not generator:
            self.fail("台账缺 `generator` 节点（生成器 ↔ 生成物 ↔ 头文件三者的绑定，L-43）")
            return
        for key in ("script", "output", "header", "inVerifyAll", "negativeCases"):
            if not generator.get(key):
                self.fail(f"台账 generator.{key} 为空 —— 绑定写不全就判不出漂移")
        for key in ("script", "output", "header"):
            relative = generator.get(key)
            if relative and not (self.root / relative).exists():
                self.fail(f"台账 generator.{key} 指向的文件不在盘上：{relative}")

        script = self.root / "Scripts" / "verify-all.sh"
        if not script.exists():
            return  # 上一条已经报过
        text = active_shell(script.read_text(encoding="utf-8"))
        for command in ("python3 Scripts/gen-sqlite-constants.py --check",
                        "python3 Scripts/gen-sqlite-constants.py --self-test"):
            if command not in text:
                self.fail(f"接线不在：verify-all.sh 里没有 `{command}`（不进闭环就永远不跑）")

        declared = re.search(r"第\s*(\d+)\s*项", generator.get("inVerifyAll", ""))
        if not declared:
            self.fail("台账 generator.inVerifyAll 里没写「第 N 项」（写了才判得出漂移）")
            return
        blocks = item_blocks(text)
        actual = next((number for number, block in blocks.items() if "gen-sqlite-constants.py" in block), None)
        if actual is None:
            self.fail("verify-all.sh 里 `gen-sqlite-constants.py` 不在任何一项的块内")
        elif actual != int(declared.group(1)):
            self.fail(f"台账 generator.inVerifyAll 与闭环不符：台账写第 {declared.group(1)} 项，实际在第 {actual} 项")

    def run(self) -> int:
        """退出码：0 = 全绿；1 = 判红；2 = **判据自身坏掉**（原单 ㈦：过去崩了只吐栈、rc 与判红
        同为 1，CI 里不可分；且已收集的诊断一条都打不出来）。
        """
        try:
            ledger = self.ledger()
        except (OSError, ValueError) as error:
            print(f"❌ 判据自身坏掉：台账读不出来（{type(error).__name__}: {error}）")
            return 2
        try:
            self.check_ledger_shape(ledger)
            self.check_files(ledger)
            self.check_header_version(ledger)
            self.check_vendored_manifest(ledger)
            self.check_license(ledger)
            self.check_provenance(ledger)
            self.check_third_party_notice(ledger)
            self.check_wiring()
            self.check_floors(ledger)
            self.check_no_second_sqlite()
            self.check_evidence_anchors(ledger)
            self.check_verify_all_wiring(ledger)
            self.check_generator_binding(ledger)
        except (KeyError, FileNotFoundError, TypeError, ValueError, re.error) as error:
            print(f"❌ 判据自身坏掉：{type(error).__name__}: {error}"
                  f"（已收集的 {len(self.failures)} 条诊断照打，不吞）")
            for failure in self.failures:
                print("   · " + failure)
            return 2
        if self.failures:
            print(f"❌ vendored SQLite 台账对账失败（{len(self.failures)} 处）：")
            for failure in self.failures:
                print("   · " + failure)
            return 1
        code_anchors, doc_anchors = getattr(self, "anchor_counts", (0, 0))
        face = self.face_cache or []
        print(
            f"✅ vendored SQLite 台账一致：{ledger.get('component')} {ledger.get('version')}"
            f"（{len(ledger.get('files') or [])} 份交付文件 + {len(ledger.get('requiredCompileOptions') or [])} 条编译宏"
            f" + 许可 / 来源 / 第三方声明 / 接线 / {code_anchors} 条代码锚点 + {doc_anchors} 条文档锚点"
            f" + 判定面 {len(face)} 个根（`Package.swift` 现读）+ 闭环项号自洽）"
        )
        return 0

def _edit(path: pathlib.Path, old: str, new: str) -> None:
    """写坏夹具（只在临时副本上）：锚点不在就当场 assert —— 夹具锚点陈旧会让负例**假绿**。

    **替换全部命中**（不是第一处）：第 68~70 轮踩过 ——「改一处、别处还在」会让负例 rc=0
    （假绿），而那个绿看起来像「判据坏了」，实际是夹具没改干净。
    """
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具锚点不在 {path}：{old[:60]!r}"
    path.write_text(text.replace(old, new), encoding="utf-8")


def _ledger_edit(copy: pathlib.Path, mutate) -> None:
    path = copy / "Scripts" / "vendored-sqlite.json"
    ledger = json.loads(path.read_text(encoding="utf-8"))
    mutate(ledger)
    path.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _comment_in_item_block(copy: pathlib.Path, item: str) -> None:
    """在某一项的正文里插一行**注释**提到命令名（原单 ㈥ P10：旧版会把项号判定带偏）。"""
    script = copy / "Scripts" / "verify-all.sh"
    text = script.read_text(encoding="utf-8")
    marker = next(line for line in text.split("\n") if item in line)
    _edit(script, marker, marker + "\n# smoke-vendored-sqlite.py 在这里也提过一句（只是注释，别当成接线）")


def _write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _replace_all(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具锚点不在 {path}：{old[:60]!r}"
    path.write_text(text.replace(old, new), encoding="utf-8")


def _append(path: pathlib.Path, text: str) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(text)


def _drop_all_defines(path: pathlib.Path) -> None:
    lines = [line for line in path.read_text(encoding="utf-8").split("\n")
             if not line.strip().startswith(".define(")]
    path.write_text("\n".join(lines), encoding="utf-8")

def self_test() -> int:
    """负例 + 对手臂：每类篡改都必须让门禁红，每条**不该红的**都不许误报。

    为什么要有对手臂（原单 ㈤/㈥）：旧版把「块注释里的 `import SQLite3`」与真 import 判成同一件事
    （都红、话术逐字相同）⇒ 分不出「注释里提过」与「代码里长出来」；这类假阳会逼着人把真判据
    拆掉。灰/绿臂与红臂**成对**才算证据。
    """
    root = pathlib.Path(__file__).resolve().parent.parent
    print("==> vendored SQLite 门禁负例自检")
    cases: list[tuple[str, object, str]] = [
        ("头文件被改一个字节", lambda d: _edit(
            d / "Vendor/sqlite3/Sources/CSQLite3/include/sqlite3.h",
            "#define SQLITE_VERSION", "#define SQLITE_VERSION "), "红"),
        ("编译宏掉一条（FTS5）", lambda d: _edit(
            d / "Vendor/sqlite3/Package.swift",
            '.define("SQLITE_ENABLE_FTS5", to: "1")', ""), "红"),
        ("公共头目录写错（头文件当场看不见）", lambda d: _edit(
            d / "Vendor/sqlite3/Package.swift",
            'publicHeadersPath: "include"', 'publicHeadersPath: "."'), "红"),
        ("第三方声明表里删掉这一行", lambda d: _replace_all(
            d / "THIRD-PARTY-NOTICES.md", "sqlite-amalgamation", "sqlite"), "红"),
        ("台账里的归档哈希被改", lambda d: _edit(
            d / "Scripts/vendored-sqlite.json", '"archiveSHA256": "1', '"archiveSHA256": "0'), "红"),
        ("产品源码里 import 系统 SQLite3",
         lambda d: _write(d / "Core" / "Sneaky.swift", "import SQLite3\n"), "红"),
        ("证据锚点陈旧（smoke 里不再有 journal_mode）", lambda d: _edit(
            d / "Scripts/smoke-vendored-sqlite.py", "journal_mode", "journalMode"), "红"),
        ("闭环里的自证接线被删", lambda d: _edit(
            d / "Scripts/verify-all.sh", "python3 Scripts/smoke-vendored-sqlite.py\n", ""), "红"),
        ("闭环里没跑门禁负例（去掉 --self-test）", lambda d: _edit(
            d / "Scripts/verify-all.sh",
            "python3 Scripts/check-vendored-sqlite.py --self-test", "true"), "红"),
        ("台账写的项号与闭环实际不符", lambda d: _edit(
            d / "Scripts/vendored-sqlite.json", "第 17 项", "第 16 项"), "红"),
        ("闭环项数声明漏改（一项写 1/17、其余 18）", lambda d: _edit(
            d / "Scripts/verify-all.sh", "==> 1/18 ", "==> 1/17 "), "红"),
        ("生成器没进闭环（删掉 gen-sqlite-constants 的 --check）", lambda d: _edit(
            d / "Scripts/verify-all.sh", "python3 Scripts/gen-sqlite-constants.py --check\n", ""), "红"),
        ("台账 generator 项号与闭环不符", lambda d: _edit(
            d / "Scripts/vendored-sqlite.json", "第 18 项", "第 17 项"), "红"),
        # 2026-10-13（合册 T-20261013-027 · 原单 T-20261010-059）：三簇缺口的成对证据 ——
        # ①「注释掉」是现实里最常见的手工停用（旧版原文子串 ⇒ 注释掉仍 rc=0）；
        # ②判定物分不出「代码里还在」与「注释里提过」；③判定面无下限、面写死目录。
        ("闭环自证接线被**注释掉**（手工停用最常见那一形）", lambda d: _edit(
            d / "Scripts/verify-all.sh",
            "python3 Scripts/check-vendored-sqlite.py --self-test",
            "# python3 Scripts/check-vendored-sqlite.py --self-test"), "红"),
        ("闭环自证接线被**注释掉**（smoke）", lambda d: _edit(
            d / "Scripts/verify-all.sh",
            "python3 Scripts/smoke-vendored-sqlite.py", "# python3 Scripts/smoke-vendored-sqlite.py"), "红"),
        ("生成器接线被**注释掉**", lambda d: _edit(
            d / "Scripts/verify-all.sh",
            "python3 Scripts/gen-sqlite-constants.py --check",
            "# python3 Scripts/gen-sqlite-constants.py --check"), "红"),
        ("锚点被重构掉、只在文件尾留一行注释提及", lambda d: (
            _edit(d / "Scripts/smoke-vendored-sqlite.py", "journal_mode", "journalMode"),
            _append(d / "Scripts/smoke-vendored-sqlite.py",
                    "# 旧实现曾用 journal_mode 这个词（锚点已被重构掉）\n")), "红"),
        ("编译宏被**注释掉**（值没动、整行注释）", lambda d: _edit(
            d / "Vendor/sqlite3/Package.swift", '.define("SQLITE_ENABLE_FTS5", to: "1")',
            '// .define("SQLITE_ENABLE_FTS5", to: "1")'), "红"),
        ("根 Package.swift 的接线被**注释掉**", lambda d: _edit(
            d / "Package.swift", '.package(path: "Vendor/sqlite3")',
            '// .package(path: "Vendor/sqlite3")'), "红"),
        ("台账 requiredCompileOptions 清空 + vendored 宏全删（判定面无下限）",
         lambda d: (_ledger_edit(d, lambda ledger: ledger.__setitem__("requiredCompileOptions", [])),
                    _drop_all_defines(d / "Vendor/sqlite3/Package.swift")), "红"),
        ("面外 testTarget 根（TestsPlatform/）里 import 系统 SQLite3（面靠 Package.swift 现读）",
         lambda d: (d / "TestsPlatform" / "ProbeS65.swift").write_text("import SQLite3\n", encoding="utf-8"), "红"),
        ("**面外回流**：面外新建目录里 import 系统 SQLite3",
         lambda d: _write(d / "Widgets65" / "Probe.swift", "import SQLite3\n"), "红"),
        ("（对手臂·不许误报）块注释里的 `import SQLite3` 不算真 import",
         lambda d: _write(d / "Core" / "Commented.swift", "/*\nimport SQLite3\n*/\n"), "绿"),
        ("（对手臂·不许误报）别项的注释里提一句命令名，不改项号判定",
         lambda d: _comment_in_item_block(d, "==> 1/18 "), "绿"),
        ("（自坏兜底）台账缺 swiftTarget + 同时有哈希不符 ⇒ 不留栈、已收集诊断照打",
         lambda d: (_ledger_edit(d, lambda ledger: ledger.pop("swiftTarget", None)),
                    _edit(d / "Vendor/sqlite3/Sources/CSQLite3/include/sqlite3.h",
                          "#define SQLITE_OK", "#define SQLITE_OK ")), "红·无栈·留诊断"),
    ]
    expectations = {
        "红": lambda result: result["rc"] != 0,
        "绿": lambda result: result["rc"] == 0,
        "红·无栈·留诊断": lambda result: (result["rc"] != 0
                                    and "Traceback" not in result["output"]
                                    and "SHA-256 不符" in result["output"]),
    }
    failures: list[str] = []

    def run_case(mutate) -> dict:
        """在**独立临时副本**上跑一次门禁，返回退出码与人读输出。"""
        with tempfile.TemporaryDirectory(prefix="vendored-sqlite-selftest-") as tmp:
            copy = pathlib.Path(tmp)
            for relative in self_test_targets(root):
                source = root / relative
                target = copy / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if source.is_dir():
                    shutil.copytree(source, target, ignore=shutil.ignore_patterns(".build"), dirs_exist_ok=True)
                else:
                    shutil.copy2(source, target)
            (copy / "Core").mkdir(exist_ok=True)
            mutate(copy)  # type: ignore[operator]
            result = subprocess.run(
                [sys.executable, str(pathlib.Path(__file__).resolve()), "--root", str(copy)],
                capture_output=True, text=True,
            )
        return {"rc": result.returncode, "output": result.stdout + result.stderr}

    # 前提自检（L-119）：干净副本必须绿。少了它，沙箱只要缺一份文件，下面每条负例都会「报红」
    # —— 红的是环境不是篡改，整族证据一起变成假绿（第 490 轮实测）。
    clean = run_case(lambda d: None)
    if clean["rc"] != 0:
        failures.append("前提自检：干净副本不绿（沙箱缺文件 ⇒ 下面的负例都是假绿）")
    print(f"   {'✅' if clean['rc'] == 0 else '❌'} 前提自检：干净副本必须绿"
          + ("" if clean["rc"] == 0 else f" → 实测 rc={clean['rc']}"))

    for index, (label, mutate, expectation) in enumerate(cases, start=1):
        result = run_case(mutate)
        ok = bool(expectations[expectation](result))
        print(f"   {'✅' if ok else '❌'} 例 {index}［{expectation}］：{label} → "
              + ("符合预期" if ok else f"**不符预期**（rc={result['rc']}）"))
        if not ok:
            failures.append(label)
    reds = sum(1 for _, _, expectation in cases if expectation != "绿")
    greens = len(cases) - reds
    if failures:
        print(f"❌ 有 {len(failures)} 条不符预期：" + "、".join(failures))
        return 1
    print(f"✅ 负例自检通过（{len(cases)} 例：篡改 {reds} 条全部被抓 + 对手臂 {greens} 条不误报）")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="vendored SQLite 台账门禁")
    parser.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parent.parent))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    return Gate(pathlib.Path(args.root).resolve()).run()


if __name__ == "__main__":
    sys.exit(main())
