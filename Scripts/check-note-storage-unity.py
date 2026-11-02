#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**桌面各端一条本地 SQLite**（`FR-STD-ALL-PLUG-008` 判据 ①②③）。

## 这一行原来为什么判不住

台账写着「界面点击点验待人工；打包项按平台口径非本侧」，两列都是 🟡 —— 而「三端用同一套表结构、
schema 版本一致」这句话当时**没有任何机器判据**：表结构活在 `NoteDatabase.swift` 里是真的，
但没人拦得住「在别处再抄一份 DDL」或者「某端自己写个 v13」；「附件不进 BLOB」也只是注释里的一句承诺。

## 本判据判五件事（全部只认**产品源面**：Core / Plugins / App / CLI / Platform）

  A **表结构只有一份定义**：`CREATE TABLE note (` / `note_tag` / `note_timeline` /
    `note_attachment` 在源面里各恰好出现 **1** 次，且都在 `NoteDatabase.swift`。
    第二份 DDL 就是「三端表结构一致」当场不成立的起点（也是漂移的起点）。
  B **附件永不进 BLOB**：`note_attachment` 的 DDL 里必须有 `path TEXT`，且整块 DDL 里
    **不许出现 `BLOB`**（附件字节留在文件系统，库里只存路径）。
  C **schema 版本只有一个写者**：`PRAGMA user_version` 的赋值只能来自
    `NoteSchemaV<N>.version` 的升级链，且链尾那个 N 必须就是 `supportedVersion` 用的那个。
    「升级链到 v14、supportedVersion 说 v13」这种错位不会有任何症状 —— 只会让另一端的库被判成更新。
  D **WAL 与事务**：`journal_mode = WAL` 在位（删掉就退回单文件日志，崩溃恢复语义当场不同）；
    唯一允许改成 `DELETE` 的地方必须是**快照 / 换名迁移**那条路（DDL 块里要写明「单文件日志」）。
  E **存储层不带平台分支**：`Plugins/Notes/Sources/NoteStorage/*.swift` 里不许出现
    `#if os(` / `#if canImport(` —— 一出现就说明「同一套表结构」开始按端分家。

## 用法

    python3 Scripts/check-note-storage-unity.py            # 静态臂（闭环第 17 项里跑）
    python3 Scripts/check-note-storage-unity.py --self-test # 判据自己的证据：`--self-test` 7 例
    python3 Scripts/check-note-storage-unity.py --root <树>

**边界（如实登记）**：判据①「元数据 / 正文 / 标签 / 时间线落库」与④「写入原子、崩溃后库不自坏」
由 `Tests/NoteCrashSafetyTests` 真写 / 真杀进程取证；②附件落文件系统的一半同上（字节相同 + 库没被撑大）。
本判据只判**结构与版本口径**，不跑库。判据③的跨端那一半：Windows 端笔记模块（alpha 3.0）与
Linux 端笔记面在本仓**还没有实现**，所以「三端各自建库后表一致」只能记**未知**，不许折算成通过。
"""

from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parent.parent

# 产品源面：**不含** Tests（那里有刻意的迷你 DDL 夹具）、Scripts（冒烟脚本同理）、
# Docs、Vendor、以及 `.worktrees/`（别人的工作树，不是本仓源）。
SOURCE_DIRS = ("Core", "Plugins", "App", "CLI", "Platform", "Tools")
STORAGE_DIR = "Plugins/Notes/Sources/NoteStorage"
DATABASE_FILE = STORAGE_DIR + "/NoteDatabase.swift"

REQUIRED_TABLES = ("note", "note_tag", "note_timeline", "note_attachment")
CHAIN_PATTERN = re.compile(r"user_version = \\\(NoteSchemaV(\d+)\.version")
SUPPORTED_PATTERN = re.compile(r"supportedVersion\s*=\s*NoteSchemaV(\d+)\.version")
LITERAL_VERSION_PATTERN = re.compile(r"user_version\s*=\s*\d+\b")
JOURNAL_PATTERN = re.compile(r"journal_mode\s*=\s*([A-Za-z]+)")
PLATFORM_BRANCH = re.compile(r"#if\s+(os\(|canImport\()")

MIN_SOURCE_FILES = 40   # 空跑防护：源面至少这么多 .swift 才像话


class Report:
    def __init__(self) -> None:
        self.problems: list[str] = []
        self.notes: list[str] = []
        self.checked = 0

    def fail(self, message: str) -> None:
        self.problems.append(message)

    def note(self, message: str) -> None:
        self.notes.append(message)

    def print(self) -> None:
        for line in self.notes:
            print("  · %s" % line)
        for line in self.problems:
            print("  ✗ %s" % line)


def source_files(root: pathlib.Path):
    for directory in SOURCE_DIRS:
        base = root / directory
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            parts = path.relative_to(root).parts
            if ".build" in parts or ".worktrees" in parts:
                continue
            yield path


def ddl_block(text: str, table: str):
    """取出 `CREATE TABLE <table> (` 那一块（到配对右括号为止）—— 判附件列时只要这一块。"""
    marker = "CREATE TABLE %s (" % table
    start = text.find(marker)
    if start < 0:
        return None
    depth = 0
    for index in range(start + len(marker) - 1, len(text)):
        char = text[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    return text[start:]


def check_table_definitions(root: pathlib.Path, report: Report, files) -> None:
    counts = {table: [] for table in REQUIRED_TABLES}
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        for table in REQUIRED_TABLES:
            if "CREATE TABLE %s (" % table in text:
                counts[table].append(path.relative_to(root).as_posix())
    for table, places in counts.items():
        if not places:
            report.fail("源面里没有 `CREATE TABLE %s (` —— 表结构丢了" % table)
        elif len(places) > 1:
            report.fail("`CREATE TABLE %s (` 在源面出现了 %d 次（%s）—— 一份表结构只能有一个写者"
                        % (table, len(places), "、".join(places)))
        else:
            report.checked += 1
            if places[0] != DATABASE_FILE:
                report.fail("`%s` 的 DDL 不在 %s（在 %s）" % (table, DATABASE_FILE, places[0]))

    # fts5 虚表（检索面），与四张实体表同处
    database = root / DATABASE_FILE
    if database.exists():
        text = database.read_text(encoding="utf-8")
        if "CREATE VIRTUAL TABLE note_fts USING fts5" not in text:
            report.fail("%s 里没有 `note_fts` 虚表（检索面不在库里）" % DATABASE_FILE)


def check_attachment_columns(root: pathlib.Path, report: Report) -> None:
    database = root / DATABASE_FILE
    if not database.exists():
        report.fail("缺 %s（附件列无处可判）" % DATABASE_FILE)
        return
    block = ddl_block(database.read_text(encoding="utf-8"), "note_attachment")
    if block is None:
        report.fail("%s 里没有 note_attachment 的 DDL" % DATABASE_FILE)
        return
    report.checked += 1
    if "path TEXT" not in block:
        report.fail("note_attachment 里没有 `path TEXT`（库里只存路径这条不成立）")
    if re.search(r"\bBLOB\b", block, flags=re.IGNORECASE):
        report.fail("note_attachment 的 DDL 里出现了 BLOB 列 —— 附件字节不许进库")


def check_schema_chain(root: pathlib.Path, report: Report) -> None:
    database = root / DATABASE_FILE
    if not database.exists():
        report.fail("缺 %s（版本链无处可判）" % DATABASE_FILE)
        return
    text = database.read_text(encoding="utf-8")
    chain = [int(value) for value in CHAIN_PATTERN.findall(text)]
    if not chain:
        report.fail("%s 里一条 `user_version = NoteSchemaV<N>.version` 都没有" % DATABASE_FILE)
        return
    report.checked += 1
    if chain != sorted(chain) or len(set(chain)) != len(chain):
        report.fail("升级链的版本号不是严格递增且有重复：%s" % chain)
    supported = SUPPORTED_PATTERN.search(text)
    if supported is None:
        report.fail("%s 里解析不到 `supportedVersion = NoteSchemaV<N>.version`" % DATABASE_FILE)
        return
    report.checked += 1
    tail = supported.group(1)
    if int(tail) != max(chain):
        report.fail("supportedVersion 指向 v%s，而升级链最高只到 v%d —— 两端对同一份库的版本认识不一致"
                    % (tail, max(chain)))
    if LITERAL_VERSION_PATTERN.search(text):
        report.fail("%s 里有用字面量写 `user_version = <数字>` 的地方（版本号必须来自 NoteSchemaV<N>）"
                    % DATABASE_FILE)


def check_wal(root: pathlib.Path, report: Report, files) -> None:
    wal_places, delete_places = [], []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        for value in JOURNAL_PATTERN.findall(text):
            relative = path.relative_to(root).as_posix()
            if value.upper() == "WAL":
                wal_places.append(relative)
            elif value.upper() == "DELETE":
                delete_places.append(relative)
            else:
                report.fail("%s 把 journal_mode 设成了 %s（只允许 WAL；快照迁移那一路可临时 DELETE）"
                            % (relative, value))
    if not wal_places:
        report.fail("源面里没有 `journal_mode = WAL` —— 崩溃恢复语义与「多进程读」当场不同")
    else:
        report.checked += 1
        report.note("journal_mode = WAL 出现在：%s" % "、".join(sorted(set(wal_places))))
    for place in delete_places:
        text = (root / place).read_text(encoding="utf-8")
        if "单文件日志" not in text:
            report.fail("%s 把 journal_mode 改成 DELETE，却没有说明是快照 / 换名迁移那一路" % place)


def check_no_platform_branches(root: pathlib.Path, report: Report) -> None:
    directory = root / STORAGE_DIR
    if not directory.exists():
        report.fail("缺目录 %s（存储层扫描面不在）" % STORAGE_DIR)
        return
    scanned = 0
    for path in sorted(directory.rglob("*.swift")):
        scanned += 1
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in PLATFORM_BRANCH.finditer(text):
            line = text[:match.start()].count("\n") + 1
            report.fail("%s:%d 出现 `#if %s` —— 存储层不许按平台分家（同一套表结构靠的是同一份源码）"
                        % (path.relative_to(root), line, match.group(1).rstrip("(")))
    if scanned == 0:
        report.fail("%s 下一个 .swift 都没扫到（空跑防护）" % STORAGE_DIR)
    else:
        report.checked += 1
        report.note("存储层扫了 %d 个文件，无平台分支" % scanned)


def report_other_ends(root: pathlib.Path, report: Report) -> None:
    """另两端现在的实现面现状 —— **如实报，不折成通过**。"""
    ends = {}
    for platform in ("windows", "linux"):
        base = root / "Platform" / platform
        hits = 0
        if base.exists():
            for path in base.rglob("*"):
                if path.suffix.lower() not in (".rs", ".ts", ".swift", ".py"):
                    continue
                if ".build" in path.parts or "target" in path.parts or "node_modules" in path.parts:
                    continue
                try:
                    text = path.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                if "CREATE TABLE note (" in text:
                    hits += 1
        ends[platform] = hits
    if all(hits == 0 for hits in ends.values()):
        report.note("Windows / Linux 端**当前没有笔记库实现**（0 处 note DDL）⇒ "
                    "「三端各自建库后表一致」记未知，不算通过")


def evaluate(root: pathlib.Path) -> Report:
    report = Report()
    files = list(source_files(root))
    if len(files) < MIN_SOURCE_FILES:
        report.fail("产品源面只扫到 %d 个 .swift（< %d）—— 扫描面疑似被砍（空跑防护）"
                    % (len(files), MIN_SOURCE_FILES))
    check_table_definitions(root, report, files)
    check_attachment_columns(root, report)
    check_schema_chain(root, report)
    check_wal(root, report, files)
    check_no_platform_branches(root, report)
    report_other_ends(root, report)
    if report.checked == 0:
        report.fail("一条检查都没真的跑起来（空跑防护）")
    return report


# ------------------------------------------------------------------ 自检

def copy_fixture(source: pathlib.Path, target: pathlib.Path) -> None:
    """只搬扫描面用到的那几个目录（保证自检跑的是**同一份源码**，不是另写一份夹具）。"""
    for folder in ("Core", "Plugins/Notes/Sources", "App", "CLI", "Platform/macOS"):
        origin = source / folder
        if not origin.exists():
            continue
        shutil.copytree(origin, target / folder, ignore=shutil.ignore_patterns(".build", "*.o"))
    # 空跑防护要的是「源面文件数够」—— 搬进来的正是真源面，够就是够，不够就该判红。


def mutate(root: pathlib.Path, relative: str, old: str, new: str, label: str, count: int = 1) -> bool:
    path = root / relative
    if not path.exists():
        print("  ✗ 自检 %s：夹具缺 %s" % (label, relative))
        return False
    original = path.read_text(encoding="utf-8")
    if old not in original:
        print("  ✗ 自检 %s：夹具里找不到要改的那一句" % label)
        return False
    path.write_text(original.replace(old, new, count), encoding="utf-8")
    report = evaluate(root)
    red = bool(report.problems)
    path.write_text(original, encoding="utf-8")
    print("  %s 自检 %s：%s" % ("✓" if red else "✗", label, "判红（如预期）" if red else "判绿（如预期）"))
    if not red:
        print("     期望判红，实际全绿 —— 这条判据是哑的")
    return red


def self_test() -> int:
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-note-unity-", dir=str(BASE / ".build")))
    ok = True
    try:
        fixture = scratch / "pristine"
        fixture.mkdir()
        copy_fixture(BASE, fixture)

        pristine = evaluate(fixture)
        print("  例 1（控制组：干净夹具）%s" % ("✓ 绿" if not pristine.problems else "✗ 红：%s" % pristine.problems))
        ok = ok and not pristine.problems
        if pristine.problems:
            print("     控制组不绿 ⇒ 后面每条「判红」都不作数")

        # 例 2：表名被改（一端自己改了名）
        ok &= mutate(fixture, DATABASE_FILE, "CREATE TABLE note (", "CREATE TABLE notes (",
                     "例 2（note 表被改名）")
        # 例 3：附件改成 BLOB
        ok &= mutate(fixture, DATABASE_FILE, "path TEXT NOT NULL,", "path TEXT NOT NULL,\n            payload BLOB,",
                     "例 3（note_attachment 放进 BLOB 列）")
        # 例 4：在别处又抄了一份 DDL
        second = fixture / STORAGE_DIR / "NoteSchemaCopy.swift"
        second.write_text(
            "// 故意抄了一份\nlet secondCopy = \"CREATE TABLE note (uuid TEXT PRIMARY KEY)\"\n",
            encoding="utf-8",
        )
        report = evaluate(fixture)
        print("  %s 自检 例 4（第二份 note DDL）：%s"
              % ("✓" if report.problems else "✗", "判红（如预期）" if report.problems else "判绿（如预期）"))
        ok = ok and bool(report.problems)
        second.unlink()
        # 例 5：supportedVersion 落后一档 —— 版本号**从盘上现读**，不写死。
        # 写死 `v14 → v13` 这一条在 schema 升到 v15 后就找不到锚点，整族自检 rc=1
        # （2026-11-03 实测；判据本身是对的，坏的是夹具）。
        database = fixture / DATABASE_FILE
        matched = SUPPORTED_PATTERN.search(database.read_text(encoding="utf-8"))
        if matched is None:
            print("  ✗ 自检 例 5：夹具里找不到 `supportedVersion = NoteSchemaV<N>.version`")
            ok = False
        else:
            head = int(matched.group(1))
            ok &= mutate(fixture, DATABASE_FILE,
                         "supportedVersion = NoteSchemaV%d.version" % head,
                         "supportedVersion = NoteSchemaV%d.version" % (head - 1),
                         "例 5（supportedVersion 落后链尾 v%d → v%d）" % (head, head - 1),)
        # 例 6：WAL 被删
        ok &= mutate(fixture, DATABASE_FILE, 'setPragma("journal_mode = WAL")',
                     'setPragma("journal_mode = TRUNCATE")', "例 6（journal_mode 不是 WAL）")
        # 例 7：存储层按平台分家
        ok &= mutate(fixture, DATABASE_FILE, "public enum NoteSchemaV1 {",
                     "#if os(Windows)\n#endif\npublic enum NoteSchemaV1 {",
                     "例 7（存储层出现 #if os(Windows)）")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print("自检：%s" % ("7 例全过" if ok else "有失败项，见上"))
    return 0 if ok else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="桌面各端一条本地 SQLite 门禁（FR-STD-ALL-PLUG-008）")
    parser.add_argument("--root", default=str(BASE), help="仓根（自检用）")
    parser.add_argument("--self-test", action="store_true", help="跑判据自己的证据")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    root = pathlib.Path(args.root)
    report = evaluate(root)
    report.print()
    if report.problems:
        print("✗ 笔记存储统一门禁：%d 处问题（检查 %d 面）" % (len(report.problems), report.checked))
        return 1
    print("✅ 笔记存储统一门禁通过：四张表各一份 DDL（%s）· 附件只存路径 · schema 版本单一写者 · "
          "WAL 在位 · 存储层无平台分支（检查 %d 面）" % (DATABASE_FILE, report.checked))
    return 0


if __name__ == "__main__":
    sys.exit(main())
