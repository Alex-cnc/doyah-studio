#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vendored SQLite 的台账门禁（FR-PLUG-08 / Q23 拍板）。

**为什么需要一条台账而不是一句「已 vendoring」**：这份 `sqlite3.c` 是 9.5 MB 的生成文件，
换版本、手改一行、编译宏掉一个，**都不会有任何症状** —— 只会让三端行为悄悄不一致，
或者让「全文检索能用」这条判据在某天静默失效。所以每个事实都必须是**可对账**的：
内容哈希、头文件里的版本字符串、`platform/macos/Package.swift` 里的编译宏、许可声明、接线位置。

对账口径（任一条不一致 ⇒ 非零退出并指名）：

  1. `files[]` 里的每个交付文件：字节数 + SHA-256 与台账一致（含我们自己写的 umbrella 头）；
  2. 头文件里的 `SQLITE_VERSION` / `SQLITE_VERSION_NUMBER` / `SQLITE_SOURCE_ID` 与台账一致；
  3. `platform/macos/Vendor/sqlite3/Package.swift` 的编译宏与台账 `requiredCompileOptions` 逐条一致
     （**宏掉了不会有症状**，只有行为悄悄变），目标名 / 源码 / 公共头目录也对账；
  4. 许可声明文件在、且写明公有领域与来源页（用户看的是这一份）；
  5. `PROVENANCE.md` 里的归档哈希与台账 `archiveSHA256` 一致（换版本时两处必须同时改）；
  6. `THIRD-PARTY-NOTICES.md` 里有这一行（第三方组件声明表是给人看的入口）；
  7. 根 `platform/macos/Package.swift` 里真的接线了这个包；
  8. **没有第二份 SQLite**：产品源码里不许出现 `import SQLite3`（系统自带 libsqlite3 版本随 OS 漂移，
     FR-PLUG-08 的口径就是「三端同一份引擎」）；
  9. `wiring.evidenceAnchors` 里的每个锚点在盘上真的还在（锚点陈旧 = 台账还指着证据、证据已经没了）；
 10. `wiring.inVerifyAll` 里的项号与 `verify-all.sh` 实际的项号一致，且**闭环自己的项号是自洽的**
     （`==> N/M` 标记个数 == 声明的 M、项号连续 —— 「加了项忘了改计数」与先前的假绿同族）。
     第 9 / 10 条是第 18 轮补的：门禁与自证**不进闭环就永远不跑**，而这类「接线悄悄断掉」本身没有任何症状。
 11. `generator` 节点里的「生成器 ↔ 生成物 ↔ vendored 头文件」三份文件都在盘上，`verify-all.sh` 里
     真的跑 `gen-sqlite-constants.py --check` 与 `--self-test`，且台账写的项号 == 闭环实际项号。
     第 11 条是第 30 轮（L-43）补的：**生成物漂移没有任何症状** —— 手改一行生成物、或头文件换版后
     忘了重生成，编译照过、单测照绿，只有三端行为悄悄不一致（`--check` 此前确实存在，
     但生成器自己的头部就写着「未接进 verify-all」⇒ 有判据、没闭环）。

负例（`--self-test`）：把上面几类篡改各造一遍，确认门禁**真的会红** —— 门禁自己也要有证据，
否则它只是「看着在跑」。

用法：
    python3 Scripts/check-vendored-sqlite.py            # 门禁
    python3 Scripts/check-vendored-sqlite.py --self-test # 负例自检

（历史：第 18 轮 L-25 第 1 批。Swift 侧的绑定层因工具链的显式模块构建缺陷暂时未接线，
 证据与排除过程见 `Docs/开发记录-20260926-任务批.md` **§28**（该文件是开发循环的连续记录，
 文件名里的日期是它的起点日期）与 `Docs/design/待接线-SQLiteKit/读我.md`。）
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# 产品里不许出现系统 SQLite 的模块（口径见 FR-PLUG-08：三端同一份引擎）。
PRODUCT_DIRS = ["platform/macos/Core", "platform/macos/Platform", "platform/macos/App", "platform/macos/CLI", "platform/macos/Tools", "platform/macos/Tests"]
SYSTEM_SQLITE_IMPORT = re.compile(r"^\s*import\s+SQLite3\b", re.MULTILINE)

# `verify-all.sh` 的项标记形状：`echo "==> 7/17 …"`
VERIFY_ITEM = re.compile(r"==> (\d+)/(\d+) ")

# 无依赖：只产出 `platform/macos/Vendor/sqlite3/{platform/macos/Package.swift,Sources/CSQLite3/**,LICENSE.txt,PROVENANCE.md}`。
# 第 18 轮补了两份**接线与锚点所在**的文件：不把它们拷进负例沙箱，第 9 / 10 两条就验不了。
# 第 30 轮（L-43）再补两份：生成器与它的生成物 —— 第 11 条（生成器绑定）读的就是这两份。
SELF_TEST_TARGETS = [
    "platform/macos/Vendor/sqlite3",
    "Scripts/vendored-sqlite.json",
    "Scripts/smoke-vendored-sqlite.py",
    "Scripts/verify-all.sh",
    "Scripts/gen-sqlite-constants.py",
    "platform/macos/Core/NoteStorage/SQLiteConstants.swift",
    "THIRD-PARTY-NOTICES.md",
    "platform/macos/Package.swift",
]


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
        manifest = self.root / "platform/macos/Vendor" / "sqlite3" / "platform/macos/Package.swift"
        if not manifest.exists():
            self.fail("platform/macos/Vendor/sqlite3/Package.swift 不在")
            return
        text = manifest.read_text(encoding="utf-8")
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
        provenance = self.root / "platform/macos/Vendor" / "sqlite3" / "PROVENANCE.md"
        if not provenance.exists():
            self.fail("platform/macos/Vendor/sqlite3/PROVENANCE.md 不在")
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
        manifest = self.root / "platform/macos/Package.swift"
        if not manifest.exists():
            self.fail("根 platform/macos/Package.swift 不在")
            return
        if '.package(path: "platform/macos/Vendor/sqlite3")' not in manifest.read_text(encoding="utf-8"):
            self.fail("根 platform/macos/Package.swift 没有接线 platform/macos/Vendor/sqlite3")

    def check_no_second_sqlite(self) -> None:
        for directory in PRODUCT_DIRS:
            base = self.root / directory
            if not base.is_dir():
                continue
            for path in base.rglob("*.swift"):
                text = path.read_text(encoding="utf-8", errors="replace")
                if SYSTEM_SQLITE_IMPORT.search(text):
                    self.fail(f"{path.relative_to(self.root)} 里 import 了系统 SQLite3（口径：三端同一份 vendored 引擎）")

    def check_evidence_anchors(self, ledger: dict) -> None:
        """台账里登记的「证据锚点」必须还在盘上。

        锚点的意义是「用户/评审照着台账就能找到证据」；证据被重构掉而台账没跟着改，
        台账就从「可追溯」变成「看着很可追溯」—— 这一类没有任何症状，所以做成对账。
        """
        anchors = ledger.get("wiring", {}).get("evidenceAnchors", [])
        if not anchors:
            self.fail("台账 wiring.evidenceAnchors 空了（证据锚点是给人照着找的入口，不许清空）")
            return
        for anchor in anchors:
            path = self.root / anchor["file"]
            if not path.exists():
                self.fail(f"证据锚点所在文件不在：{anchor['file']}")
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            if anchor["anchor"] not in text:
                self.fail(
                    f"证据锚点陈旧：台账指向 {anchor['file']} 里的 `{anchor['anchor']}`，但盘上找不到"
                    f"（{anchor['why']}）"
                )

    def check_verify_all_wiring(self, ledger: dict) -> None:
        """门禁与自证必须真的在闭环里，且闭环自己的项号是自洽的。

        「加了项忘了改计数」在这个仓有过先例（第 10 项那次假绿同族）：项标记写着 `N/16`、
        实际跑的是 17 项，或者新项压根没进 `verify-all.sh` —— 两种都不会有任何症状。
        """
        script = self.root / "Scripts" / "verify-all.sh"
        if not script.exists():
            self.fail("Scripts/verify-all.sh 不在")
            return
        text = script.read_text(encoding="utf-8")
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
        text = script.read_text(encoding="utf-8")
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
        ledger = self.ledger()
        self.check_files(ledger)
        self.check_header_version(ledger)
        self.check_vendored_manifest(ledger)
        self.check_license(ledger)
        self.check_provenance(ledger)
        self.check_third_party_notice(ledger)
        self.check_wiring()
        self.check_no_second_sqlite()
        self.check_evidence_anchors(ledger)
        self.check_verify_all_wiring(ledger)
        self.check_generator_binding(ledger)
        if self.failures:
            print(f"❌ vendored SQLite 台账对账失败（{len(self.failures)} 处）：")
            for failure in self.failures:
                print("   · " + failure)
            return 1
        print(
            f"✅ vendored SQLite 台账一致：{ledger['component']} {ledger['version']}"
            f"（{len(ledger['files'])} 份交付文件 + {len(ledger['requiredCompileOptions'])} 条编译宏"
            f" + 许可 / 来源 / 第三方声明 / 接线 / {len(ledger['wiring']['evidenceAnchors'])} 条证据锚点"
            f" + 闭环项号自洽）"
        )
        return 0


def self_test() -> int:
    """负例：每一类篡改都必须让门禁红。门禁自己不验，就只是「看着在跑」。"""
    root = pathlib.Path(__file__).resolve().parent.parent
    print("==> vendored SQLite 门禁负例自检")
    cases: list[tuple[str, object]] = [
        ("头文件被改一个字节", lambda d: (d / "platform/macos/Vendor/sqlite3/Sources/CSQLite3/include/sqlite3.h").write_bytes(
            (d / "platform/macos/Vendor/sqlite3/Sources/CSQLite3/include/sqlite3.h").read_bytes() + b"\n")),
        ("编译宏掉一条（FTS5）", lambda d: (d / "platform/macos/Vendor/sqlite3/Package.swift").write_text(
            (d / "platform/macos/Vendor/sqlite3/Package.swift").read_text(encoding="utf-8").replace(
                '.define("SQLITE_ENABLE_FTS5", to: "1")', ""), encoding="utf-8")),
        ("公共头目录写错（头文件当场看不见）", lambda d: (d / "platform/macos/Vendor/sqlite3/Package.swift").write_text(
            (d / "platform/macos/Vendor/sqlite3/Package.swift").read_text(encoding="utf-8").replace(
                'publicHeadersPath: "include"', 'publicHeadersPath: "."'), encoding="utf-8")),
        ("第三方声明表里删掉这一行", lambda d: (d / "THIRD-PARTY-NOTICES.md").write_text(
            (d / "THIRD-PARTY-NOTICES.md").read_text(encoding="utf-8").replace("sqlite-amalgamation", "sqlite"), encoding="utf-8")),
        ("台账里的归档哈希被改", lambda d: (d / "Scripts/vendored-sqlite.json").write_text(
            (d / "Scripts/vendored-sqlite.json").read_text(encoding="utf-8").replace(
                '"archiveSHA256": "1', '"archiveSHA256": "0'), encoding="utf-8")),
        ("产品源码里 import 系统 SQLite3", lambda d: (d / "Core" / "Sneaky.swift").write_text(
            "import SQLite3\n", encoding="utf-8")),
        # 第 18 轮补的四类：证据锚点 / 接线 / 台账项号 / 闭环项数自洽 ——
        # 它们的共同点是「断了不会有任何症状」，所以每一类都必须有一条负例证明门禁真的会红。
        ("证据锚点陈旧（smoke 里不再有 journal_mode 这个锚点）", lambda d: (d / "Scripts/smoke-vendored-sqlite.py").write_text(
            (d / "Scripts/smoke-vendored-sqlite.py").read_text(encoding="utf-8").replace(
                "journal_mode", "journalMode"), encoding="utf-8")),
        ("闭环里的自证接线被删", lambda d: (d / "Scripts/verify-all.sh").write_text(
            (d / "Scripts/verify-all.sh").read_text(encoding="utf-8").replace(
                "python3 Scripts/smoke-vendored-sqlite.py\n", ""), encoding="utf-8")),
        ("闭环里没跑门禁负例（去掉 --self-test）", lambda d: (d / "Scripts/verify-all.sh").write_text(
            (d / "Scripts/verify-all.sh").read_text(encoding="utf-8").replace(
                "python3 Scripts/check-vendored-sqlite.py --self-test", "true"), encoding="utf-8")),
        ("台账写的项号与闭环实际不符", lambda d: (d / "Scripts/vendored-sqlite.json").write_text(
            (d / "Scripts/vendored-sqlite.json").read_text(encoding="utf-8").replace(
                "第 17 项", "第 16 项"), encoding="utf-8")),
        ("闭环项数声明漏改（一项写 1/17、其余 18）", lambda d: (d / "Scripts/verify-all.sh").write_text(
            (d / "Scripts/verify-all.sh").read_text(encoding="utf-8").replace(
                '==> 1/18 ', '==> 1/17 '), encoding="utf-8")),
        # 第 30 轮（L-43）：生成器绑定的两类篡改。生成物漂移没有症状，所以「绑定断了门禁会红」
        # 与「生成物过期门禁会红」这两件事各自都要有证据（后者在生成器自己的 --self-test 里）。
        ("生成器没进闭环（删掉 gen-sqlite-constants 的 --check）", lambda d: (d / "Scripts/verify-all.sh").write_text(
            (d / "Scripts/verify-all.sh").read_text(encoding="utf-8").replace(
                "python3 Scripts/gen-sqlite-constants.py --check\n", ""), encoding="utf-8")),
        ("台账 generator 项号与闭环不符", lambda d: (d / "Scripts/vendored-sqlite.json").write_text(
            (d / "Scripts/vendored-sqlite.json").read_text(encoding="utf-8").replace(
                "第 18 项", "第 17 项"), encoding="utf-8")),
    ]
    failures: list[str] = []
    for index, (label, mutate) in enumerate(cases, start=1):
        with tempfile.TemporaryDirectory(prefix="vendored-sqlite-selftest-") as tmp:
            copy = pathlib.Path(tmp)
            for relative in SELF_TEST_TARGETS:
                source = root / relative
                target = copy / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if source.is_dir():
                    shutil.copytree(source, target, ignore=shutil.ignore_patterns(".build"))
                else:
                    shutil.copy2(source, target)
            (copy / "Core").mkdir(exist_ok=True)
            mutate(copy)  # type: ignore[operator]
            result = subprocess.run(
                [sys.executable, str(pathlib.Path(__file__).resolve()), "--root", str(copy)],
                capture_output=True, text=True,
            )
        ok = result.returncode != 0
        print(f"   {'✅' if ok else '❌'} 负例 {index}：{label} → 门禁{'报红' if ok else '**没报红**'}")
        if not ok:
            failures.append(label)
    if failures:
        print(f"❌ 有 {len(failures)} 条负例没被抓住：" + "、".join(failures))
        return 1
    print(f"✅ 负例自检通过（{len(cases)} 条篡改全部被抓）")
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
