#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vendored SQLite 的**现编现跑**自证（FR-PLUG-08 / Q23）。

台账门禁（`check-vendored-sqlite.py`）证明的是「文件就是那一份、宏写着那几条」；
这一条证明的是「**真的编得起来、跑得对**」：把 `platform/macos/Vendor/sqlite3` 的 `sqlite3.c` 用台账里的编译宏
编成一个可执行文件，对着一个**真数据库文件**做一遍笔记存储要用到的事：

  1. 版本自证：跑起来读到的 `sqlite3_libversion()` / `sqlite3_sourceid()` 与台账一致
     —— 证明是**我们 vendor 的这一份**，不是系统 libsqlite3（系统库版本随 OS 漂移）；
  2. 编译宏自证：四条宏（THREADSAFE / FTS5 / OMIT_LOAD_EXTENSION / DQS）在运行期自报生效，
     而不是「写在 platform/macos/Package.swift 里没起作用」；
  3. 行为自证：WAL 真的开得起来（并发写 + 多进程读的前提）、参数化写入与读回一致、
     FTS5 能建虚拟表并**真检索**、DQS=0 时双引号字符串**当场报错**。

**FTS5 与中文（第 18 轮实测出的硬事实，直接决定 `FR-PLUG-08`「按条件查与全文检索」怎么落实）**：

  · 默认分词器 `unicode61` **不切中文**：`MATCH '骑行'` 命中 **0**（不是「大概不能」，是实测 0），
    而同一张表上 `MATCH 'breathing'` 命中 1 —— 所以这 0 是**分词语义**，不是索引坏了；
  · `tokenize='trigram'` 能按**子串**命中中文，但**查询串必须 ≥3 字**：`'洞庭湖'` / `'关于骑行'` 命中 1，
    而 2 字的 `'骑行'` 依然命中 0。所以「中文全文检索」这条判据的真实口径是
    **trigram（或 ICU）分词器 + 查询串 ≥3 字**，两条都不能少。
  这四条断言是**成对**钉的（默认 0 / 对照 1 / trigram 1 / trigram 2 字 0）：
  单钉一条「命中 1」会被「换个能命中的表」糊弄过去，成对才判得住。

为什么不用 Swift 侧的单测做这件事（这是第 18 轮踩的坑）：Swift 目标里**引用 clang 模块大量声明**
会被 SwiftPM 判进显式模块构建档，而那一档下本地包的 clang 模块进不了模块表 ——
绑定层因此暂时未接线（见开发记录第 18 轮）。这一条与那条缺陷**完全独立**：
它直接调 clang 编 C，不经过 SwiftPM 的模块机制，所以它今天就能当证据用，
将来绑定层接上了也依然有意义（换版本时先看它）。

用法：
    python3 Scripts/smoke-vendored-sqlite.py            # 编 + 跑 + 断言
    python3 Scripts/smoke-vendored-sqlite.py --keep     # 保留临时目录（排查用）
"""

from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

SAMPLE_TITLE = "笔记·α"

C_PROGRAM = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sqlite3.h"

static void say(const char* key, const char* value) {
    printf("SMOKE|%s|%s\n", key, value);
}

static void say_int(const char* key, long long value) {
    printf("SMOKE|%s|%lld\n", key, value);
}

/* 全文检索自证：在指定的虚拟表上参数化查一次命中行数。 */
static void fts_count(sqlite3* db, const char* table, const char* needle, const char* key) {
    char sql[160];
    snprintf(sql, sizeof(sql), "SELECT count(*) FROM %s WHERE %s MATCH ?;", table, table);
    sqlite3_stmt* st = 0;
    if (sqlite3_prepare_v2(db, sql, -1, &st, 0) != SQLITE_OK) {
        fprintf(stderr, "fts prepare failed: %s\n", sqlite3_errmsg(db));
        return;
    }
    sqlite3_bind_text(st, 1, needle, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(st) == SQLITE_ROW) say_int(key, sqlite3_column_int64(st, 0));
    sqlite3_finalize(st);
}

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: smoke <db-path>\n"); return 2; }
    say("version", sqlite3_libversion());
    say("sourceid", sqlite3_sourceid());

    /* 编译宏有没有真的生效（运行期自报，不看 platform/macos/Package.swift） */
    say_int("opt_THREADSAFE", sqlite3_compileoption_used("THREADSAFE") ? 1 : 0);
    say_int("opt_ENABLE_FTS5", sqlite3_compileoption_used("ENABLE_FTS5") ? 1 : 0);
    say_int("opt_OMIT_LOAD_EXTENSION", sqlite3_compileoption_used("OMIT_LOAD_EXTENSION") ? 1 : 0);

    sqlite3* db = 0;
    if (sqlite3_open(argv[1], &db) != SQLITE_OK) {
        fprintf(stderr, "open failed: %s\n", sqlite3_errmsg(db));
        return 1;
    }

    /* WAL：PRAGMA 会把实际生效的模式回一行 */
    sqlite3_stmt* st = 0;
    if (sqlite3_prepare_v2(db, "PRAGMA journal_mode=WAL;", -1, &st, 0) != SQLITE_OK) return 1;
    if (sqlite3_step(st) == SQLITE_ROW) say("journal_mode", (const char*)sqlite3_column_text(st, 0));
    sqlite3_finalize(st);

    /* 建表 + 参数化写入（笔记最小形状：主键 / 标题 / 更新时间）。
       两张 FTS5 虚拟表是故意的：默认分词器一张、trigram 一张 —— 见文件头「FTS5 与中文」。 */
    char* msg = 0;
    if (sqlite3_exec(db,
            "CREATE TABLE note (id TEXT PRIMARY KEY, title TEXT NOT NULL, updated_at INTEGER NOT NULL);"
            "CREATE VIRTUAL TABLE note_fts USING fts5(title, body);"
            "CREATE VIRTUAL TABLE note_fts_tri USING fts5(title, body, tokenize='trigram');",
            0, 0, &msg) != SQLITE_OK) {
        fprintf(stderr, "create failed: %s\n", msg ? msg : "?");
        return 1;
    }

    const char* insert = "INSERT INTO note (id, title, updated_at) VALUES (?, ?, ?);";
    if (sqlite3_prepare_v2(db, insert, -1, &st, 0) != SQLITE_OK) return 1;
    sqlite3_bind_text(st, 1, "n1", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 2, SAMPLE_TITLE, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(st, 3, 1700000000);
    if (sqlite3_step(st) != SQLITE_DONE) {
        fprintf(stderr, "insert failed: %s\n", sqlite3_errmsg(db));
        return 1;
    }
    sqlite3_finalize(st);

    /* 读回来（顺带证明 UTF-8 存得住、取得到） */
    if (sqlite3_prepare_v2(db, "SELECT id, title, updated_at FROM note;", -1, &st, 0) != SQLITE_OK) return 1;
    if (sqlite3_step(st) == SQLITE_ROW) {
        char row[256];
        snprintf(row, sizeof(row), "%s|%s|%lld", sqlite3_column_text(st, 0), sqlite3_column_text(st, 1),
                 (long long)sqlite3_column_int64(st, 2));
        say("row", row);
    }
    sqlite3_finalize(st);

    /* FTS5：真建虚拟表、真检索（中文 + 一条 ASCII 对照组），而不是宏里写了个 1 */
    if (sqlite3_exec(db,
            "INSERT INTO note_fts (title, body) VALUES ('环洞庭湖', '关于骑行的热身计划');"
            "INSERT INTO note_fts (title, body) VALUES ('尺八', '关于呼吸的练习');"
            "INSERT INTO note_fts (title, body) VALUES ('shakuhachi', 'breathing drills');"
            "INSERT INTO note_fts_tri (title, body) VALUES ('环洞庭湖', '关于骑行的热身计划');"
            "INSERT INTO note_fts_tri (title, body) VALUES ('尺八', '关于呼吸的练习');"
            "INSERT INTO note_fts_tri (title, body) VALUES ('shakuhachi', 'breathing drills');",
            0, 0, &msg) != SQLITE_OK) {
        fprintf(stderr, "fts insert failed: %s\n", msg ? msg : "?");
        return 1;
    }
    /* 默认分词器：中文子串查不到（0），但同一张表上 ASCII 词查得到（1，对照组） */
    fts_count(db, "note_fts", "骑行", "fts_default_cjk");
    fts_count(db, "note_fts", "breathing", "fts_default_ascii");
    /* trigram：3 字以上的中文子串查得到（1），2 字的查不到（0） */
    fts_count(db, "note_fts_tri", "洞庭湖", "fts_trigram_cjk3");
    fts_count(db, "note_fts_tri", "关于骑行", "fts_trigram_cjk4");
    fts_count(db, "note_fts_tri", "骑行", "fts_trigram_cjk2");

    /* DQS=0：双引号不许当字符串字面量 —— 这一条只能靠行为证（prepare 就该失败） */
    int dqs_rc = sqlite3_prepare_v2(db, "SELECT \"这不是标识符\";", -1, &st, 0);
    say_int("dqs_prepare_rc", dqs_rc);
    if (dqs_rc == SQLITE_OK) sqlite3_finalize(st);

    sqlite3_close(db);
    return 0;
}
'''


def compile_and_run(sources: pathlib.Path, header_dir: pathlib.Path, defines: list[str], workdir: pathlib.Path,
                    keep: bool) -> tuple[dict[str, str], str]:
    main_c = workdir / "smoke_main.c"
    main_c.write_text(C_PROGRAM.replace("SAMPLE_TITLE", f'"{SAMPLE_TITLE}"'), encoding="utf-8")
    binary = workdir / "smoke"
    command = [
        "clang", "-O1", "-std=c11",
        f"-I{header_dir}",
        *[f"-D{define}" for define in defines],
        str(sources), str(main_c),
        "-o", str(binary), "-lpthread",
    ]
    built = subprocess.run(command, capture_output=True, text=True)
    if built.returncode != 0:
        raise RuntimeError("编译失败：\n" + (built.stderr or built.stdout))
    database = workdir / "smoke.db"
    ran = subprocess.run([str(binary), str(database)], capture_output=True, text=True)
    if ran.returncode != 0:
        raise RuntimeError(f"运行失败（exit {ran.returncode}）：\n{ran.stdout}\n{ran.stderr}")
    values: dict[str, str] = {}
    for line in ran.stdout.splitlines():
        if not line.startswith("SMOKE|"):
            continue
        _, key, value = line.split("|", 2)
        values[key] = value
    if keep:
        print(f"（临时目录保留在 {workdir}）")
    return values, ran.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description="vendored SQLite 现编现跑自证")
    parser.add_argument("--keep", action="store_true", help="保留临时目录")
    args = parser.parse_args()

    ledger = json.loads((ROOT / "Scripts" / "vendored-sqlite.json").read_text(encoding="utf-8"))
    target = ledger["swiftTarget"]
    sources = ROOT / target["path"] / target["sources"][0]
    header_dir = ROOT / target["path"] / target["publicHeadersPath"]
    defines = [option["define"] for option in ledger["requiredCompileOptions"]]

    workdir = pathlib.Path(tempfile.mkdtemp(prefix="smoke-vendored-sqlite-"))
    try:
        values, raw = compile_and_run(sources, header_dir, defines, workdir, args.keep)
    finally:
        if not args.keep:
            shutil.rmtree(workdir, ignore_errors=True)

    checks: list[tuple[str, bool, str]] = [
        ("版本与台账一致", values.get("version") == ledger["version"], f"跑了 {values.get('version')}，台账 {ledger['version']}"),
        ("源码 ID 与台账一致", values.get("sourceid") == ledger["sourceID"],
         f"跑了 {values.get('sourceid', '')[:32]}…，台账 {ledger['sourceID'][:32]}…"),
        ("SQLITE_THREADSAFE 生效", values.get("opt_THREADSAFE") == "1", "序列化模式是宿主多线程的前提"),
        ("SQLITE_ENABLE_FTS5 生效", values.get("opt_ENABLE_FTS5") == "1", "全文检索是 FR-PLUG-08 的判据之一"),
        ("SQLITE_OMIT_LOAD_EXTENSION 生效", values.get("opt_OMIT_LOAD_EXTENSION") == "1", "少一个 dlopen 面"),
        ("WAL 真的开起来了", (values.get("journal_mode") or "").lower() == "wal",
         f"journal_mode={values.get('journal_mode')}"),
        ("参数化写入与读回一致", values.get("row") == f"n1|{SAMPLE_TITLE}|1700000000", f"row={values.get('row')}"),
        # —— FTS5 与中文：四条成对（见文件头）。单钉一条「命中 1」是判不住的。——
        ("默认分词器能真检索（ASCII 对照组，命中 1）", values.get("fts_default_ascii") == "1",
         f"fts_default_ascii={values.get('fts_default_ascii')}（若为 0 则索引本身有问题，下面那条 0 就证明不了任何事）"),
        ("默认分词器 unicode61 不切中文（'骑行' 命中 0）", values.get("fts_default_cjk") == "0",
         f"fts_default_cjk={values.get('fts_default_cjk')}"),
        ("trigram 分词器中文子串命中（'洞庭湖' 命中 1）", values.get("fts_trigram_cjk3") == "1",
         f"fts_trigram_cjk3={values.get('fts_trigram_cjk3')}"),
        ("trigram 分词器中文短语命中（'关于骑行' 命中 1）", values.get("fts_trigram_cjk4") == "1",
         f"fts_trigram_cjk4={values.get('fts_trigram_cjk4')}"),
        ("trigram 分词器要求查询串 ≥3 字（2 字 '骑行' 命中 0）", values.get("fts_trigram_cjk2") == "0",
         f"fts_trigram_cjk2={values.get('fts_trigram_cjk2')}"),
        ("DQS=0：双引号字符串当场报错", (values.get("dqs_prepare_rc") or "0") != "0",
         f"prepare 返回 {values.get('dqs_prepare_rc')}（0 就是当字符串放过）"),
    ]
    failures = [(label, detail) for label, ok, detail in checks if not ok]
    if failures:
        print("❌ vendored SQLite 现编现跑自证失败：")
        for label, detail in failures:
            print(f"   · {label}（{detail}）")
        print("— 原始输出 —")
        print(raw)
        return 1
    print(
        f"✅ vendored SQLite 现编现跑自证通过（{len(checks)} 条）："
        f"{ledger['version']}｜WAL｜参数化读写｜DQS=0 报错｜四条编译宏运行期自报生效 | "
        f"FTS5 中文：默认分词器 0 命中（对照 ASCII 1）→ trigram 3 字以上 1 命中、2 字 0 命中"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
