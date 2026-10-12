#!/usr/bin/env python3
"""Core 展示文本本地化的**棘轮**（R-45 / FR-DATA-04 / 队列 L-109）。

本脚本管**两条**「展示文本」棘轮，口径一致：**只挡变差，销账即降基线**。

棘轮 A（R-45，原有）——「含汉字」：
    Core 里有一批**直接给用户看**的中文字面量（`LocalizedError` 的描述、拒绝理由、
    单元格摘要…）。它们不经过任何语言表，于是英文界面上会混出中文。R-45 与 FR-DATA-04
    各记了一处，但真正的问题是它**会继续长** —— 每加一个 `LocalizedError` 就多一串。
    · 统计 `Core/**/*.swift`（排除 `Localization.swift` —— 那里是语言表本身）里
      "字符串字面量含汉字"的行数，按「文件数」与「行数」两个口径记账；
    · 比基线更差即失败；想增加就必须**同时**在基线里显式加数字（一次有意识的决定）；
    · 已修的地方要**降基线**（`--update-baseline`），否则棘轮只挡增长、不记进步。

棘轮 B（**队列 L-109**，2026-10-11 开发循环第 487 轮）——「写死的英文展示文案」：
    A 的判据是 `HAN = [\\u4e00-\\u9fff]` ⇒ **只挡「含汉字」的字面量**，于是写死的英文展示
    文案**整个门禁体系里全绿**：第 96 轮修 `L-108` 时实测 `Core/WorkspaceTab.swift` 里
    那句 `"Home"`（中文界面直接印英文）就是这样漏过去的。**那一处已经修了，判据的窄口
    一直在** —— 这一条把洞补上。
    · 扫描面 = `Core/**/*.swift`（与 A 同一表面）；**豁免** = `Localization.swift`
      （语言表本身）+ `CodeLanguageDefinitions.swift`（代码语言的登记表：关键字表 /
      语言名 / 补全项**整表都是技术标识**，与语言表同一性质）。豁免清单逐条登记在台账
      `pathExempt` 里，判据与脚本里的清单**双向对账**（多列少列都报红）。
    · 候选形状（**英文展示文案的窄口**）：一行里去掉注释后，取「真的是两个字界引号之间的」
      字面量（开引号的前一个字符不许是 `'` —— 挡住 `replacingOccurrences(of: "'", with: "''")`
      这种转义串里**被两个引号夹出来的假字面量** `, with: `），满足：含拉丁字母 / 不含汉字 /
      只含 `A-Za-z0-9 空格 , . ' : ; ! ? / + -` / 不含转义与格式与语法记号
      （`\\ % { } < > * _ = # @ $ | & ~ \` [ ] ( )`）/ 剥掉首尾空白后 3 ≤ 长度 ≤ 60，
      且**剥离后是多词短语，或 Title-case 单词**（`^[A-Z][a-z]{2,}$` —— 正是 `"Home"` 那一档）。
    · 判定 = **白名单**（台账 `Scripts/core-localization-english.json`）：
      **白名单之外一律报红**；每条登记项要写 `kind`（为什么它不是展示文案：SQL 方言片段 /
      驱动错误匹配串 / 协议串 / 格式串 …；**确实直达界面而暂时没翻的写 `displayDebt` =
      已登记的欠账，不是放行**），`kind` 只认脚本里那套词表。
    · 白名单**只许缩小**：盘上已经没有的登记项 ⇒ **报红并提示销账**（留着一条死白名单 =
      那个串下次写回来会**静默过关**）。`--update-baseline-english` 只负责把盘上现状
      抄进台账、**不替人分类**：新条目落成 `unclassified`，而 `unclassified` 不在词表内
      ⇒ 仍然红 —— 「加一条白名单」必须是一次有意识的分类决定。

边界（**如实登记，本轮没做的那一半**）：
    · 只扫 `Core/**` —— `App/` / `CLI/` 里写死的英文展示文案**仍漏网**（与棘轮 A 的
      扫描面一致，不是本判据新引入的洞；要覆盖得先有「App 的展示文案一律走语言表」这条
      已成立的纪律，见证据「边界」节）。
    · **全大写的单词不在候选面**（`TSV` / `CSV` / `INSERT` 这类格式名与 SQL 关键字同形；
      只有前后补空格的 SQL 片段如 `" CASCADE"`、`"WHERE "` 剥离后同样落在这一档），
      逐条登记的价值低于噪声 —— 代价如实记在证据里。
    · 只判**字面量**，不判「这个串会不会真的到界面」（后者机器判不了）。登记项的
      `kind` 是人给的分类，判据只判它在不在词表内 —— 分类对不对靠读代码 + 随轮证据。

用法：
    python3 Scripts/check-core-localization.py                    # 闸门：A + B 两条都跑
    python3 Scripts/check-core-localization.py --report                # 按文件列 A 的命中
    python3 Scripts/check-core-localization.py --report-english        # 按 kind 列 B 的命中
    python3 Scripts/check-core-localization.py --update-baseline          # 降 A 的基线
    python3 Scripts/check-core-localization.py --update-baseline-english  # 抄现状进 B 台账
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

CORE = pathlib.Path("Core")
# 扫描面（2026-10-13 · 概设 §7 P3 搬家）：笔记的**自有逻辑**搬到 `Plugins/Notes/Sources/` 之后，
# 这两条纪律（「汉字字面量只降不升」与「写死的英文展示文案要登记」）**跟着代码走** ——
# 棘轮只挡增长 ⇒ 不跟过去就等于「搬一次家把这一族的欠账从账上抹掉」（免费降基线）。
CORE_SOURCES = (CORE, pathlib.Path("Plugins/Notes/Sources"))
SRC_SELF = pathlib.Path(__file__)
BASELINE = pathlib.Path("Scripts/core-localization-baseline.json")
ENGLISH_LEDGER = pathlib.Path("Scripts/core-localization-english.json")

# ---- 棘轮 A：含汉字的字面量 -------------------------------------------------
EXEMPT = {"Localization.swift"}
HAN = re.compile(r"[\u4e00-\u9fff]")
STRING_LITERAL = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')

# ---- 棘轮 B：写死的英文展示文案 ---------------------------------------------
# 豁免：语言表本身 + 代码语言的登记表（整表都是技术标识）。
ENGLISH_PATH_EXEMPT = {
    "Localization.swift": "语言表本身（这里就是两语槽位；汉字棘轮同样豁免它）",
    "CodeLanguageDefinitions.swift": "代码语言的登记表：关键字表 / 语言名 / 补全项 —— 整表都是技术标识，与语言表同一性质；"
                                     "该表里合法的语言显示名（`Plain Text` / `Python`…）是**专名**，按 R-53 同族口径保持协议原文",
}
# 真字面量：开引号的前一个字符必须是「引出引号的字符」（空白 / `(` / `=` / `:` / `,` / `[` …），
# 不能是字母数字或引号类字符 —— 后者会从 `replacingOccurrences(of: "'", with: "''")` 这种
# 转义串里夹出假字面量 `, with: `（前一个字符分别是 `'` / 反引号 / `\n` 里的 `n`）。
ENGLISH_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
ENGLISH_LITERAL_BLOCKERS = ("'", '"', "\\", "`")


def _introduces_literal(line: str, start: int) -> bool:
    if start <= 0:
        return True
    previous = line[start - 1]
    return not previous.isalnum() and previous not in ENGLISH_LITERAL_BLOCKERS
ENGLISH_BAD_CHARS = set("\\%{}<>*_=#@$+|&~`[]()")
ENGLISH_ALLOWED_CHARS = re.compile(r"^[A-Za-z0-9 ,.';:!?/+-]+$")
ENGLISH_TITLE_CASE = re.compile(r"^[A-Z][a-z]{2,}$")
ENGLISH_MIN, ENGLISH_MAX = 3, 60

ENGLISH_KINDS = {
    "sql": "SQL 方言片段 / 关键字 / 迁移 SQL —— 拼 SQL 用的，不是展示文案",
    "dbType": "数据库类型名（PG / MySQL 的类型原文）",
    "wireValue": "协议层取值字面量（如 PG 文本表示里的 `Infinity`）",
    "explainField": "PG `EXPLAIN` 输出或 JSON 的字段名 —— 解析用，不是展示文案",
    "driverMessage": "驱动 / 系统错误文本的**匹配子**（`contains` 用）",
    "serverMessageMatch": "服务端错误原文的匹配子 / 归类用",
    "internalErrorDescription": "内部错误描述的**机器载荷**（`LocalizedError` 的技术串；"
                                "人话一律由带 `language:` 的渲染入口给 —— 概要设计 §7「协议入口不许写死语言」）",
    "protocolToken": "协议 / 接口层的固定串（HTTP 头名、认证方案、JSON-RPC 错误文本、"
                     "SSL 模式名、MCP 方法名、剪贴板格式名）",
    "formatPattern": "日期 / 数字格式串",
    "pathName": "路径 / 目录名",
    "assetName": "字体 / 资源名",
    "xmlElementName": "XML 元素 / 属性名（xlsx OOXML）",
    "cliFlag": "命令行开关",
    "parseToken": "解析用户文本时要匹配的关键字（如维护计划里的 `cost: high`）",
    "logOnly": "只进日志",
    "guardrailPattern": "提示注入检测的模式串",
    "productName": "产品 / 品牌专名（按 R-53 同族口径不翻）",
    "sampleValue": "合成数据的样例值",
    "displayDebt": "**已登记的欠账**：确实直达界面、暂时写死英文 —— 不是放行，棘轮只挡变差",
}
ENGLISH_ALLOWED_KINDS = set(ENGLISH_KINDS)
ENGLISH_PENDING_KIND = "unclassified"


def scan() -> tuple[dict[str, int], dict[str, list[int]]]:
    """返回 (每个文件的命中行数, 每个文件的行号列表)。"""
    counts: dict[str, int] = {}
    lines_by_file: dict[str, list[int]] = {}
    for path in sorted(p for source in CORE_SOURCES for p in source.rglob("*.swift")):
        if path.name in EXEMPT:
            continue
        hits: list[int] = []
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for literal in STRING_LITERAL.findall(line):
                if HAN.search(literal):
                    hits.append(number)
                    break
        if hits:
            counts[path.name] = len(hits)
            lines_by_file[path.name] = hits
    return counts, lines_by_file


def english_candidates() -> dict[str, list[str]]:
    """返回 {字面量: ["文件:行", …]} —— 盘上「像写死的英文展示文案」的全部字面量。"""
    found: dict[str, list[str]] = {}
    for path in sorted(p for source in CORE_SOURCES for p in source.rglob("*.swift")):
        if path.name in ENGLISH_PATH_EXEMPT:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for match in ENGLISH_LITERAL.finditer(line):
                if not _introduces_literal(line, match.start()):
                    continue
                literal = match.group(1)
                if not re.search(r"[A-Za-z]", literal):
                    continue
                if HAN.search(literal):
                    continue
                if any(char in ENGLISH_BAD_CHARS for char in literal):
                    continue
                if not ENGLISH_ALLOWED_CHARS.match(literal):
                    continue
                text = literal.strip()
                if not (3 <= len(text) <= ENGLISH_MAX):
                    continue
                if " " not in text and not ENGLISH_TITLE_CASE.match(text):
                    continue
                found.setdefault(text, []).append(f"{path.as_posix()}:{number}")
    return found


def load_ledger() -> dict:
    if not ENGLISH_LEDGER.exists():
        return {"note": "", "kinds": {}, "pathExempt": {}, "entries": {}}
    return json.loads(ENGLISH_LEDGER.read_text(encoding="utf-8"))


def check_english() -> tuple[list[str], str]:
    """棘轮 B。返回 (问题列表, 一行读数)。"""
    ledger = load_ledger()
    entries = ledger.get("entries") or {}
    on_disk = english_candidates()
    problems: list[str] = []

    declared_kinds = set((ledger.get("kinds") or {}).keys())
    if declared_kinds != ENGLISH_ALLOWED_KINDS:
        problems.append(
            f"[台账] `kinds` 与脚本里的词表不一致：台账独有 {sorted(declared_kinds - ENGLISH_ALLOWED_KINDS)} / "
            f"脚本独有 {sorted(ENGLISH_ALLOWED_KINDS - declared_kinds)}"
        )
    declared_exempt = set((ledger.get("pathExempt") or {}).keys())
    if declared_exempt != set(ENGLISH_PATH_EXEMPT):
        problems.append(
            f"[台账] `pathExempt` 与脚本里的豁免清单不一致：台账独有 {sorted(declared_exempt - set(ENGLISH_PATH_EXEMPT))} / "
            f"脚本独有 {sorted(set(ENGLISH_PATH_EXEMPT) - declared_exempt)}"
        )

    for literal, entry in sorted(entries.items()):
        kind = (entry or {}).get("kind")
        if kind == ENGLISH_PENDING_KIND or kind not in ENGLISH_ALLOWED_KINDS:
            problems.append(
                f"[未分类] `{literal}` 的 kind = `{kind}` 不在词表内 —— "
                f"白名单的每一条都要有人给一个词表里的分类（{ENGLISH_PENDING_KIND} = 抄现状还没分类）"
            )
    fresh = sorted(set(on_disk) - set(entries))
    for literal in fresh:
        problems.append(
            f"[新增] `{literal}` 是写死的英文展示文案，不在白名单里（首处 {on_disk[literal][0]}）—— "
            f"要么改走语言表，要么说明它为什么不是展示文案、用 --update-baseline-english 登记后**给它分类**"
        )
    stale = sorted(set(entries) - set(on_disk))
    for literal in stale:
        problems.append(
            f"[陈旧] 白名单里的 `{literal}` 盘上已经没有了 —— 请销账（--update-baseline-english），"
            f"留着一条死白名单等于那个串下次写回来会静默过关"
        )

    by_kind: dict[str, int] = {}
    for entry in entries.values():
        kind = (entry or {}).get("kind") or "?"
        by_kind[kind] = by_kind.get(kind, 0) + 1
    summary = "，".join(f"{kind} {count}" for kind, count in sorted(by_kind.items()))

    if problems:
        return problems, (
            f"❌ Core 写死的英文展示文案（棘轮 B · 队列 L-109）：{len(problems)} 项 —— "
            f"白名单 {len(entries)} 条 / 盘上候选 {len(on_disk)} 条"
        )
    return [], (
        f"✅ Core 写死的英文展示文案（棘轮 B · 队列 L-109）：白名单外 0 条、陈旧 0 条"
        f"（白名单 {len(entries)} 条 = 盘上候选 {len(on_disk)} 条；{summary}；"
        f"豁免文件 {len(ENGLISH_PATH_EXEMPT)} 个、其名逐条登记在台账里）"
    )


def write_english_ledger() -> int:
    """抄现状进台账：已有条目保留原 kind，新条目落成 unclassified（仍需人分类）。"""
    ledger = load_ledger()
    entries = ledger.get("entries") or {}
    on_disk = english_candidates()
    merged: dict[str, dict] = {}
    for literal in sorted(on_disk):
        entry = dict(entries.get(literal) or {})
        entry["kind"] = entry.get("kind") or ENGLISH_PENDING_KIND
        entry.setdefault("sites", on_disk[literal][:3])
        merged[literal] = entry
    pending = sum(1 for entry in merged.values() if entry["kind"] == ENGLISH_PENDING_KIND)
    document = {
        "note": (
            "「Core 里写死的英文展示文案」白名单 + 棘轮（队列 L-109）。判据与用法见 "
            "Scripts/check-core-localization.py 头部（棘轮 B）。口径：**白名单之外一律报红；"
            "白名单只许缩小**（盘上已经没有的条目要销账，留着 = 那个串下次写回来会静默过关）。"
            "每条的 kind 只认脚本里那套词表；`unclassified` = 抄现状还没分类，**不在词表内 ⇒ 判红** "
            "—— 「加一条白名单」必须是一次有意识的分类决定，本文件的 --update-baseline-english "
            "只抄现状、不替人分类。`displayDebt` = 确实直达界面、暂时写死英文的**已登记欠账**"
            "（不是放行）。"
        ),
        "kinds": ENGLISH_KINDS,
        "pathExempt": ENGLISH_PATH_EXEMPT,
        "entries": merged,
    }
    ENGLISH_LEDGER.write_text(
        json.dumps(document, ensure_ascii=False, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )
    print(
        f"✅ 英文白名单台账已按盘上现状重写：{len(merged)} 条"
        f"（其中待分类 {pending} 条 —— 待分类不在词表内，闸门仍会红，请逐条给 kind）"
    )
    return 0


def self_test() -> int:
    """判据自己的证据：在**临时副本**上把每条口径各弄坏一次，要求当场报红；
    末例核对真仓库逐字节未变（「判据写完不对已知改动报红，等于没有」）。"""
    import hashlib
    import shutil
    import subprocess
    import tempfile

    watched = [ENGLISH_LEDGER, BASELINE, SRC_SELF] + [
        CORE / "WorkspaceTab.swift",
        pathlib.Path("Plugins/Notes/Sources/Note.swift"),
    ]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}

    root = pathlib.Path(tempfile.mkdtemp(prefix="l109-selftest-"))
    for source in CORE_SOURCES:
        shutil.copytree(source, root / source)
    (root / "Scripts").mkdir()
    for name in (SRC_SELF.name, ENGLISH_LEDGER.name, BASELINE.name):
        shutil.copy(pathlib.Path("Scripts") / name, root / "Scripts" / name)
    ledger_path = root / "Scripts" / ENGLISH_LEDGER.name
    original_ledger = ledger_path.read_text(encoding="utf-8")

    def run(workdir: pathlib.Path) -> tuple[int, str]:
        done = subprocess.run([sys.executable, "Scripts/" + SRC_SELF.name],
                              cwd=workdir, capture_output=True, text=True)
        return done.returncode, done.stdout + done.stderr

    results: list[tuple[str, bool, str]] = []

    def case(title: str, expect_rc: int, marker: str, mutate) -> None:
        mutate()
        rc, output = run(root)
        hit = marker in output
        results.append((title, rc == expect_rc and hit, f"rc={rc}（要求 {expect_rc}）｜命中「{marker}」={hit}"))
        probe = root / "Core/__SelfTestProbe.swift"
        if probe.exists():
            probe.unlink()
        ledger_path.write_text(original_ledger, encoding="utf-8")

    def probe_file(body: str):
        return lambda: (root / "Core/__SelfTestProbe.swift").write_text(body, encoding="utf-8")

    def edit_ledger(change):
        def mutate() -> None:
            document = json.loads(original_ledger)
            change(document)
            ledger_path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return mutate

    case("① 新增 Title-case 展示名（`\"Home\"` = L-109 的原始症状）⇒ 红", 1, "[新增] `Home`",
         probe_file('enum SelfTestProbe {\n    static let title = "Home"\n}\n'))
    case("② 新增多词英文展示文案 ⇒ 红", 1, "[新增] `Untitled Document`",
         probe_file('enum SelfTestProbe {\n    static let title = "Untitled Document"\n}\n'))
    case("③ 盘上少了白名单条目 ⇒ 红（陈旧 / 要销账）", 1, "[陈旧]",
         edit_ledger(lambda doc: doc["entries"].update({"Ghost Label": {"kind": "sql"}})))
    case("④ 白名单条目没分类（kind=unclassified）⇒ 红", 1, "[未分类]",
         edit_ledger(lambda doc: doc["entries"]["Node Type"].update({"kind": "unclassified"})))
    case("⑤ 豁免清单与脚本对不上 ⇒ 红", 1, "`pathExempt`",
         edit_ledger(lambda doc: doc["pathExempt"].pop("CodeLanguageDefinitions.swift")))
    case("⑥ 对照组：没有坏东西 ⇒ 绿", 0, "白名单外 0 条、陈旧 0 条", lambda: None)

    shutil.rmtree(root)
    after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}
    untouched = before == after

    for title, ok, note in results:
        print(f"{'✅' if ok else '❌'} {title}  {note}")
    print(f"{'✅' if untouched else '❌'} 真仓库逐字节未变（{len(watched)} 份：判据 / 两份台账 / 两个 Core 源文件）")
    passed = sum(1 for _, ok, _ in results if ok)
    print(f"—— Core 展示文本棘轮（A+B）自检：{passed}/{len(results)} 例达标"
          f"（另 1 条真仓库未变）")
    if SRC_SELF.exists() and (passed != len(results) or not untouched):
        return 1
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    for name in ("--update-baseline-english", "--report-english"):
        if name in sys.argv:
            if name == "--update-baseline-english":
                return write_english_ledger()
            on_disk = english_candidates()
            ledger = load_ledger()
            entries = ledger.get("entries") or {}
            by_kind: dict[str, list[str]] = {}
            for literal in sorted(on_disk):
                kind = (entries.get(literal) or {}).get("kind") or ENGLISH_PENDING_KIND
                by_kind.setdefault(kind, []).append(literal)
            for kind in sorted(by_kind):
                print(f"— {kind}（{len(by_kind[kind])} 条）")
                for literal in by_kind[kind]:
                    print(f"    {literal!r}   {on_disk[literal][0]}")
            print(f"合计：{len(on_disk)} 个候选字面量")
            return 0

    counts, lines_by_file = scan()
    current = {"files": len(counts), "lines": sum(counts.values())}

    if "--update-baseline" in sys.argv:
        BASELINE.write_text(
            json.dumps(
                {
                    "comment": "Core 展示文本本地化棘轮基线：Core 里「字符串字面量含汉字」的"
                               "文件数与行数只能降不能升。修掉一批后用 --update-baseline 降基线。",
                    "baseline": current,
                },
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"✅ 基线已更新：{current['files']} 个文件 / {current['lines']} 行")
        return 0

    if "--report" in sys.argv:
        for name, count in sorted(counts.items(), key=lambda item: -item[1]):
            print(f"{count:>4}  {name}  行号 {lines_by_file[name][:6]}{' …' if count > 6 else ''}")
        print(f"合计：{current['files']} 个文件 / {current['lines']} 行")
        return 0

    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))["baseline"] if BASELINE.exists() else {"files": 0, "lines": 0}
    problems_a = []
    if current["files"] > baseline["files"]:
        problems_a.append(f"文件数 {baseline['files']} → {current['files']}")
    if current["lines"] > baseline["lines"]:
        problems_a.append(f"行数 {baseline['lines']} → {current['lines']}")

    problems_b, line_b = check_english()

    if problems_a:
        print(f"❌ Core 展示文本本地化棘轮失败（{len(problems_a)} 项比基线更差）：")
        for problem in problems_a:
            print("   " + problem)
        print("   提示：新写的用户可见文案请走 `LocalizedStrings.text(_:language:)`（Core 的语言表），")
        print("         把语言作为参数传进来（默认中文，界面传当前语言）；确有必要保留字面量时，")
        print("         请先在 `Scripts/core-localization-baseline.json` 里显式加数字并说明原因。")
    else:
        print(
            f"✅ Core 展示文本本地化棘轮通过（{current['files']} 个文件 / {current['lines']} 行；"
            f"基线 {baseline['files']} / {baseline['lines']}）"
        )

    print(line_b)
    if problems_b:
        for problem in problems_b:
            print("   " + problem)
        print("   提示：这两条棘轮的口径是「**只挡变差**」—— 棘轮 B 的白名单 = "
              "`Scripts/core-localization-english.json`（豁免文件与每条的分类理由都在里面）。")

    return 1 if (problems_a or problems_b) else 0


if __name__ == "__main__":
    raise SystemExit(main())
