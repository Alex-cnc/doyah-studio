#!/usr/bin/env python3
"""条文写法判据 —— 规范条文必须带齐六字段（是什么 / 不是什么 / 判据 / 负例 / 读数口径 / 归属）。

依据：Scripts/rule-schema.json（机读权威）+ 《通用开发规范》§4 首段（人读说明）。

覆盖范围（不许含糊）：
- 只验「字段在场」与「判据标了【机判】/【人判】」，**不验内容对不对**。
- 只扫两本规范：《通用开发规范》《项目管理规范》。三书一单的判据行不归本脚本（它们由各书判据行 + 各自脚本管）。
- 存量条文允许暂缺字段（棘轮：数量记在 rule-schema-baseline.json，只许降不许升）。

判红三情形：
1) 条文「缺字段条数」比基线多 ⇒ 红（新条文不许裸奔，旧条文不许倒退）
2) 「六字段齐全条数」比基线少 ⇒ 红（有人把完整条文改回散文）
3) 解析到的条文总数低于基线 ⇒ 红（空跑防护：解析器坏了，不是规范变好了）

负例（--self-test 内固化）：一条缺「负例」字段的条文必须判红。
"""
# shared-surface：2026-11-10 主人令 —— 两侧共用判据；新增「单向引用」判据（通用条文不得引用项目规范，只能反过来），带正反两例

from __future__ import annotations

import json
import re
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs"
SCHEMA = ROOT / "Scripts" / "rule-schema.json"
BASELINE = ROOT / "Scripts" / "rule-schema-baseline.json"

# 单向引用（2026-11-10 人类主人令）：**通用规范条文不许引用项目规范**，只能反过来
# （项目规范可以写「见《通用开发规范》§X」）。理由：通用规范要能整体搬到另一个项目，
# 里面一旦出现「见《项目管理规范》§5」这种指回，搬过去就是悬空引用。
GENERIC_BOOK = "通用开发规范.md"
PROJECT_REF = re.compile(r"《项目管理规范》|项目管理规范\s*§\s*\d")
PROJECT_REF = re.compile(r"《项目管理规范》|项目管理规范\s*§\s*\d")

# 条文点名的脚本必须存在（2026-11-10）：条文里写 `Scripts/xxx.py` 是「判据在哪」的唯一线索，
# 脚本删了而条文没改 ⇒ 判据静默悬空，到有人真去跑才发现。这里把悬空引用当场判红。
SCRIPT_REF = re.compile(r"(?:\./)?Scripts/([A-Za-z0-9_.\-]+\.(?:py|sh))")
SCRIPT_GONE = ("已删", "已移除", "已退场", "归档到", "搬走")   # 明确写了「已经没了」的行不算悬空


def dangling_scripts(text: str, schema: dict) -> list[str]:
    """条文里点名但文件不存在的脚本（空列表 = 没有悬空引用）。"""
    names = set(schema["字段"].keys())
    missing = []
    for title, body in split_clauses(text, names):
        for line in body.split("\n"):
            if any(k in line for k in SCRIPT_GONE):
                continue
            for m in SCRIPT_REF.finditer(line):
                if not (ROOT / "Scripts" / m.group(1)).exists():
                    missing.append(f"{title}⇒Scripts/{m.group(1)}")
    return missing


SECTION_IDS: set[str] = set()


def section_exits() -> list[str]:
    """归约的机器半边：每个环节必须有「出口」—— 一句话说清「拿到什么算完」。

    没有出口的环节 = 无法判断做完没有 = 新人走到这里只能靠猜（这正是「归约三句」要堵的洞）。
    """
    p = ROOT / "Scripts" / "rule-sections.json"
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return ["rule-sections.json 读不出来 —— 环节定义无从校验"]
    out = []
    for e in data.get("环节", []):
        sid = e.get("id", "?")
        exit_text = (e.get("出口") or "").strip()
        if len(exit_text) < 6:
            out.append(f"环节 {sid}（{e.get('名称','?')}）没有「出口」—— 走到这一步怎么算做完没说")
    if not data.get("环节"):
        out.append("rule-sections.json 里一个环节都没有")
    return out


def load_section_ids() -> set[str]:
    """从 Scripts/rule-sections.json 取合法环节 ID（含 `全局`）；文件缺失则返回空集 ⇒ 本校验跳过。"""
    p = ROOT / "Scripts" / "rule-sections.json"
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return set()
    return {e["id"] for e in data.get("环节", [])} | {"全局"}


def load_enforce() -> bool:
    """rule-sections.json 的 `enforce`：false=宽容期（缺字段不红），true=收紧（每条必须挂环节）。"""
    try:
        return bool(json.loads((ROOT / "Scripts" / "rule-sections.json").read_text(encoding="utf-8")).get("enforce"))
    except (OSError, ValueError):
        return False


def bad_sections(text: str, schema: dict) -> list[str]:
    """环节归属校验：取值必须合法；`enforce=true` 时每条都**必须**有归属环节。"""
    if not SECTION_IDS:
        return []
    names = set(schema["字段"].keys())
    strict = load_enforce()
    out = []
    for title, body in split_clauses(text, names):
        hits = [l for l in body.split("\n") if "**归属环节**" in l]
        if not hits:
            if strict:
                out.append(f"{title}⇒收紧期缺「归属环节」")
            continue
        value = hits[0].split("：", 1)[1].strip().strip("`").split()[0] if "：" in hits[0] else ""
        if value not in SECTION_IDS:
            out.append(f"{title}⇒归属环节「{value}」不在环节表里")
    return out


def load_book_structure() -> dict:
    """`rule-sections.json` 的 `章` 块：非环节章白名单 + 禁词 + 错位上限。缺则返回空字典 ⇒ 本节校验跳过。"""
    try:
        return json.loads((ROOT / "Scripts" / "rule-sections.json").read_text(encoding="utf-8")).get("章", {})
    except (OSError, ValueError):
        return {}


def _chapter_envs(title: str) -> set[str]:
    """章标题点名的环节集合。认三种写法：`B1` / `B1–B6` / 光秃秃一个组字母（`C、D、F` = 整组）。"""
    out: set[str] = set()
    for m in re.finditer(r"([A-F])\s*(\d)?\s*(?:[–\-~]\s*[A-F]?\s*(\d))?", title):
        letter, lo, hi = m.group(1), m.group(2), m.group(3)
        if lo and hi:
            out |= {f"{letter}{i}" for i in range(int(lo), int(hi) + 1)}
        elif lo:
            out.add(f"{letter}{lo}")
        else:
            out |= {i for i in SECTION_IDS if i.startswith(letter)}
    return out


def book_structure(text: str) -> list[str]:
    """**本书的章 = 环节**：判三件，另记一个必须下降的读数。

    ① 每个 `## ` 章要么是环节章（标题点名 A1…F4），要么在白名单里 —— 不在 ⇒ 红（不许随手新开一章）。
    ② 白名单里的章正文已经没有了 ⇒ 红（白名单只减不增，删掉的章必须同批从白名单划掉）。
    ③ 条文「归属环节」必须落在它所在章点名的环节里（非环节章按整表算，因为它是跨环节的元规则章）；
       落不进去的记一条「错位」，条数只许下降（`错位上限`）—— 这是「补记」欠下的债，得还。
    另：章标题里出现禁词（补记/杂项/临时/其它）⇒ 红，且白名单也不豁免（现状已在白名单里，靠只减不增收口）。
    """
    cfg = load_book_structure()
    if not cfg or not SECTION_IDS:
        return []
    whitelist = set(cfg.get("非环节章白名单", []))
    banned = cfg.get("禁词", [])
    ceiling = int(cfg.get("错位上限", 0))
    out: list[str] = []
    seen_chapters: set[str] = set()
    chapter = ""
    misplaced = 0
    for line in text.split("\n"):
        m = re.match(r"^## (.+)$", line)
        if m:
            chapter = m.group(1).strip()
            seen_chapters.add(chapter)
            for word in ([] if chapter in whitelist else banned):
                if word in chapter:
                    out.append(f"章「{chapter}」带禁用名「{word}」—— 章节名要写它是什么环节，"
                               f"「补记」是结构失控的痕迹；现存这几章靠白名单只减不增收口，不许再新开")
            if chapter not in whitelist and not _chapter_envs(chapter):
                out.append(f"章「{chapter}」既不是环节章（标题没点名 A1…F4）也不在非环节章白名单里 —— "
                           f"新章必须是环节章；跨环节的元规则只能进既有白名单章")
            continue
        if line.startswith("- **归属环节**：") and chapter:
            env = line.split("：", 1)[1].strip().split()[0] if "：" in line else ""
            if env in ("", "全局"):
                continue
            allowed = _chapter_envs(chapter) or SECTION_IDS
            if env not in allowed:
                misplaced += 1
    for gone in sorted(whitelist - seen_chapters):
        out.append(f"白名单里的章「{gone}」正文已经没有了 —— 把它从 rule-sections.json 划掉（白名单只减不增）")
    legacy = [c for c in sorted(whitelist & seen_chapters) if any(w in c for w in banned)]
    if legacy:
        # 已存在的「补记」章不判红 —— 判据永远红等于没人看；但它们进债务读数，重排完必须归零。
        out.append(f"[债务] 白名单里还挂着 {len(legacy)} 个「补记」章（只减不增）："
                   + "；".join(c.split(" ")[0] for c in legacy))
    if misplaced > ceiling:
        out.append(f"条文错位 {misplaced} 条 > 上限 {ceiling} 条（条文躺在了不点它归属环节的章里）—— "
                   f"新条文必须落进自己的环节章；这个读数只许下降")
    return out


def clause_genre(text: str, schema: dict, book: str) -> tuple[list[str], list[str]]:
    """**条文体裁（七问）**：每条必须回答 `Why / What / How / Capability / Who / When`。

    六字段只管「是什么 + 怎么判」；缺的两问是：
    - **为什么**（Why）：这条是从哪件事上长出来的、不写会出什么事。没有它，条文就是无来由的检查项。
    - **能力前提**（Capability）：要什么工具 / 权限 / 环境，才守得住、才判得了。没有它，条文在拿不到那个能力的场合就是一句空话。

    判定用**计数棘轮**（存量欠账见 `rule-schema.json` 的 `体裁.棘轮`）：缺这两问的条文条数只许降。
    这样新条文缺字段会立刻让计数上升 ⇒ 判红；补一条老条文，基线跟着降一条。
    """
    genre = schema.get("体裁", {})
    ratchet = genre.get("棘轮", {})
    if not ratchet:
        return [], []
    names = set(schema["字段"].keys()) | {"为什么", "能力前提"}
    per_book = ratchet.get(book, {})
    why_floor = int(per_book.get("为什么基线", 0))
    cap_floor = int(per_book.get("能力前提基线", 0))
    total = missing_why = missing_cap = 0
    for _title, body in split_clauses(text, names, require_judge=False):
        total += 1
        if "**为什么**" not in body:
            missing_why += 1
        if "**能力前提**" not in body:
            missing_cap += 1
    out: list[str] = []
    if missing_why > why_floor:
        out.append(f"缺「为什么」的条文 {missing_why} 条 > 基线 {why_floor} 条 —— 新条文必须写清"
                   f"「这条是从哪件事上长出来的、不写会怎样」")
    if missing_cap > cap_floor:
        out.append(f"缺「能力前提」的条文 {missing_cap} 条 > 基线 {cap_floor} 条 —— 不写要什么工具/权限/环境，"
                   f"条文在拿不到那能力的场合就是空话")
    notes = [f"[欠账] 七问欠账：缺「为什么」{missing_why}/{total} 条、缺「能力前提」{missing_cap}/{total} 条（只许降）"]
    return out, notes


PREAMBLE_HEAD = re.compile(r"^##\s*序言\s*$", re.M)
# 序言里出现这些词，说明它开始写规矩了 —— 规矩只许写进「条」，序言只许叙述
PREAMBLE_SPEECH = re.compile(r"必须|不得|不许|禁止|判据|【机判】|【人判】|归属环节|第\s*[一二三四五六七八九十百零〇0-9]+\s*条")


def preamble_form(text: str, require: bool = True) -> tuple[list[str], list[str]]:
    """序言是叙述层：无条号、无判据、无负例 —— 但它也不许藏规矩。

    判据只查一件：序言正文里有没有规范语句（必须/不得/判据/第N条…）。
    有 ⇒ 红，理由是「规矩只许写进条里」—— 今天 §4.2 就是以 `**规矩**：` 躺在散文里、
    判据整整一年看不见它，这条判据就是防它复发。
    返回 (违规, 读数)。
    """
    m = PREAMBLE_HEAD.search(text)
    if not m:
        return [], (["[待建] 序言未建立：重建后启用本判（今天起它只是缺件读数，不判红）"] if require else [])
    rest = text[m.end():]
    nxt = re.search(r"^##\s", rest, re.M)
    body = rest[: nxt.start()] if nxt else rest
    hits = []
    for i, line in enumerate(body.split("\n"), 1):
        s = line.strip()
        if not s:
            continue
        for mm in PREAMBLE_SPEECH.finditer(s):
            hits.append(f"序言第 {i} 行出现规范语句「{mm.group(0)}」⇒ 规矩只许写进「条」，序言只许叙述：{s[:40]}")
            break
    return hits, []


def coverage_gap(text: str, schema: dict) -> list[str]:
    """写了【判据】却没声明「覆盖范围」的条文标题（铁律 13 的落地判据）。

    棘轮：数量记 `rule-schema-baseline.json` 的「覆盖范围缺」，**只许降不许升**。
    判不了：覆盖范围写得对不对（那是人判），只判「有没有写」。
    """
    fields = set(schema["字段"]) | {"覆盖范围"}
    gap, cur = [], None
    for ln in text.split("\n"):
        m = CLAUSE_RE.match(ln)
        # 「曾经的错指向」是挂在条文里的**注解**（踩坑记录），不是条文本身：它夹在六字段中间，
        # 会被当成一个块。按前缀排除，避免把注解算成「缺覆盖范围的条文」。
        if m and m.group("title") not in fields and not m.group("title").startswith("曾经的"):
            cur = {"title": m.group("title"), "has_cov": False, "fields": 0}
            gap.append(cur)
            continue
        if cur is not None:
            if "覆盖范围" in ln:
                cur["has_cov"] = True
            if re.match(r"^- \*\*(判据|负例|读数口径|不是什么|归属|归属环节|是什么)\*\*", ln):
                cur["fields"] += 1
    # 只算真条文：块内至少两个六字段才算。文档里的加粗注解（「曾经的错指向」）与流程步骤项不是条文
    return [b["title"] for b in gap if b["fields"] >= 2 and not b["has_cov"]]


def index_drift(text: str, schema: dict) -> list[str]:
    """§1.6 反向索引（环节 → 条文）与条文实际归属对账。

    索引表是手写的 ⇒ 加了条文忘改索引时，索引会静静落后。判「每行列出的条数 = 实际挂该环节的条数」，
    不判标题文字（表里是缩写，逐字比会误报）。
    """
    from collections import Counter
    fields = set(schema["字段"]) | {"覆盖范围"}
    actual: Counter = Counter()
    cur_is_clause = False
    for ln in text.split("\n"):
        m = CLAUSE_RE.match(ln)
        if m and m.group("title") not in fields:
            cur_is_clause = True
            continue
        m2 = re.match(r"^- \*\*归属环节\*\*：(.*)$", ln)
        if m2 and cur_is_clause:
            for sec in re.findall(r"([A-F][1-9]|全局)", m2.group(1)):
                actual[sec] += 1
    m_sec = re.search(r"^## \d+\.\d+ 环节索引", text, re.M)
    start = m_sec.start() if m_sec else -1
    end = text.find("\n## ", start + 5) if start >= 0 else -1
    section = text[start:end if end > 0 else len(text)]
    listed: Counter = Counter()
    for row in re.findall(r"^\|\s*`([A-F][1-9]|全局)`\s*\|([^|]*)\|([^|]*)\|\s*$", section, re.M):
        listed[row[0]] = len([x for x in row[2].split("·") if x.strip()])
    out = []
    for sec in sorted(set(listed) | set(actual)):
        if listed.get(sec, 0) != actual.get(sec, 0):
            out.append(f"§1.6 索引「{sec}」列了 {listed.get(sec, 0)} 条，条文实际挂 {actual.get(sec, 0)} 条（加了条文要同批改索引）")
    return out


# 通用册纯净度（2026-11-18 人类主人：「如果规范里出现了 xcode / swift 之类的，就有问题了，
# 这是苹果生态的 iOS 或 macOS 等特定项目里才会出现的」）。
# 通用册只写「对所有项目成立的规则」：具体脚本路径、具体命令、平台与生态专有名一律不许出现，
# **也不许留指回项目的指针**（2026-11-18 方向反转：此前用 `〈落点 #NN〉` 指到项目册表，等于通用册依赖项目册编号）。
# 现在的方向只有一个：项目册的落点表逐行写「这条判据落在我仓哪儿」，通用册一个字都不指向它。
PURITY_RE = re.compile(
    r"(?:Scripts|Tests|platform|Plugins)/"                 # 具体路径
    r"|(?:^|[^A-Za-z])(?:python3|bash|swift|xcrun|xcodebuild)(?![A-Za-z])"  # 具体工具链
    r"|codesign|spctl|xcodegen|swiftc|XCTest|SwiftUI|AppKit|Cocoa|Foundation\.framework"
    r"|project\.yml|Package\.swift|Podfile|Info\.plist"
    r"|macOS|iOS|iPadOS|watchOS|tvOS|Linux|Windows|Android|HarmonyOS|Ubuntu|Debian"
    r"|SQLite|Gatekeeper|notariz|staple"
    r"|\.(?:py|sh|swift|yml|xcodeproj)\b"
    r"|AGENTS\.md|AGENT-SPEC|Docs/"                        # 本仓文件名与文档目录
    r"|(?:^|[^A-Za-z])(?:Studio|Notes|Retro)(?![A-Za-z])"   # 本仓仓名
    r"|`(?:check|gen|verify|test|action)-[a-z0-9-]+`"      # 本仓判据脚本名（不带扩展也算）
    r"|\.build/(?:derived/)?|URLSession|\.alert|confirmationDialog"  # 构建产物目录 / 平台 UI 专有名
    r"|\.agent/|Docs 根|\d+\s*份白名单"                    # 本仓隐藏目录 / 旧术语残留
    r"|公证|keychain|Keychain|App Store|TestFlight"          # 中文写的平台生态专有名（英文正则漏掉的）
    r"|本件"                                                # 指自己只许用「本册」（2026-11-18 统一）
    r"|(?:概设|需求书|详设|一单|项目册|项目规范)\s*§"        # 跨册节号引用（通用册不许指别册的节）
    r"|一单|FR-[A-Z]"                                    # 项目侧的进度载体名与需求条目号（2026-11-18）
)
# 节号引用：指向本册不存在的小节也算写错（别册的节号在这里抓不到，靠上面那条前缀规则）
SECTION_RE = re.compile(r"§\s?(\d+(?:\.\d+)*)")
LANDING_REF = re.compile(r"〈落点 #(\d+)〉")
LANDING_ROW = re.compile(r"^\| #(\d+) \|", re.M)
HISTORY_LINE = re.compile(r"^> \*\*版本\*\*")   # 版本历史行记的是过去发生过的事实，不判


def section_refs(text: str) -> list[str]:
    """本册内 `§N.M` 引用必须指到真实存在的小节（写错的节号 = 读者找不到规矩）。"""
    have = {m.group(1) for m in re.finditer(r"^#{2,3}\s+(\d+(?:\.\d+)*)", text, re.M)}
    bad = []
    for idx, line in enumerate(text.split("\n"), 1):
        if HISTORY_LINE.match(line):
            continue
        for m in SECTION_RE.finditer(line):
            if m.group(1) not in have:
                bad.append(f"第 {idx} 行引用 §{m.group(1)}，本册没有这一节：{line.strip()[:60]}")
    return bad


def term_closure(generic: str, project: str) -> list[str]:
    """术语闭环（两半，都是机判得住的）：

    ① 术语表里的词，正文必须真的用到 —— 防止术语表变成「加了没人用」的空词柜；
    ② 项目册的「术语对应」段必须覆盖通用册**全部**术语 —— 防止只清了一边。

    判不了的第三半（正文里自造的词有没有定义）**不在本函数里**，它是人判：
    自造词不可枚举，机器认不出「哪个词是自造词」。
    """
    lines = generic.split("\n")
    start = next((i for i, l in enumerate(lines) if "**术语（" in l), None)
    if start is None:
        return ["通用册没有术语表 —— 术语无从闭环"]
    end = next((i for i in range(start + 1, len(lines)) if "这些名字" in lines[i]), len(lines))
    block = "\n".join(lines[start:end])
    body = "\n".join(lines[:start] + lines[end:])
    terms = [t.strip() for t in re.findall(r"\*\*([^*\n]+)\*\*\s*=", block)]
    if not terms:
        return ["术语表里一个 `**词** = 解释` 都没有"]
    issues: list[str] = []
    for term in terms:
        key = term.split(" #")[0].strip()
        if key not in body:
            issues.append(f"术语表里的「{key}」正文一次都没用到（空词）")
    proj_start = project.find("**术语对应**")
    proj_sec = project[proj_start:] if proj_start >= 0 else ""
    if not proj_sec:
        issues.append("项目册没有「术语对应」段 —— 术语只在本册转，不知道在本仓叫什么")
    else:
        proj_sec = proj_sec.split("\n| #")[0]
        for term in terms:
            key = term.split(" #")[0].strip()
            if key not in proj_sec:
                issues.append(f"项目册「术语对应」缺「{key}」—— 本仓这个术语指什么没说")
    return issues


def landing_purity(text: str) -> list[str]:
    """通用册里出现的落点/平台专有名（空列表 = 干净）。"""
    bad = []
    for idx, line in enumerate(text.split("\n"), 1):
        if idx == 1 or HISTORY_LINE.match(line):
            continue
        m = PURITY_RE.search(line)
        if m:
            bad.append(f"第 {idx} 行出现「{m.group(0).strip()}」—— 通用册只写形态，具体工具/平台/项目名写进项目册："
                       f"{line.strip()[:70]}")
    return bad


def _generic_clause_refs(text: str) -> list[dict]:
    """通用册条文 → 标题 / 归属环节 / 引用的落点号（含标题行上的引用）。"""
    clause_re = re.compile(r"^(?:\d+\.|-)\s+\*\*(?P<t>[^*]{2,120}?)\*\*")
    env_re = re.compile(r"^- \*\*归属环节\*\*：(.+)$")
    field = {"判据", "负例", "覆盖范围", "不是什么", "归属环节", "处理方式", "为什么", "读数口径", "归属", "落点"}
    out: list[dict] = []
    cur = None
    for line in text.split("\n"):
        em = env_re.match(line)
        if em:
            if cur is not None and not cur["env"]:
                cur["env"] = em.group(1).strip()
            continue
        cm = clause_re.match(line)
        if cm and cm.group("t").strip() not in field:
            cur = {"title": cm.group("t").strip(), "env": "", "refs": [int(x) for x in LANDING_REF.findall(line)]}
            out.append(cur)
            continue
        if cur is not None:
            for r in LANDING_REF.findall(line):
                if int(r) not in cur["refs"]:
                    cur["refs"].append(int(r))
    return out


def landing_drift(generic: str, project: str) -> list[str]:
    """**单向**校验（2026-11-18 方向反转）：通用册不许指回项目；项目册落点表必须点对本册条文。

    旧版是双向对账 —— 通用册用 `〈落点 #NN〉` 指到项目册 §0.6，两边号必须一一对上。
    人类主人指出这就是反向引用：通用册的正文里写着项目册的编号，换一个项目两个册子都得改。
    现在改成：通用册零指针；项目册那张表的「用在」列自己点名本册条文（项目 → 本册，单向）。

    三样照判：① 通用册正文不许出现落点编号；② 表里每行「用在」必须点到本册真实条文（占位、点错都红）；
    ③ 每行「环节」必须等于它点到的条文的归属环节（环节写错 = 查表的人找错环节）。
    """
    drift: list[str] = []

    # ① 通用册正文里的落点编号 = 反向引用（版本历史行记过去事实、负例行本身就是反例示范，两者跳过）
    for idx, line in enumerate(generic.split("\n"), 1):
        if HISTORY_LINE.match(line) or line.lstrip().startswith("- **负例**"):
            continue
        for m in LANDING_REF.finditer(line):
            drift.append(f"通用册第 {idx} 行指回了项目册编号「{m.group(0)}」—— 只许项目册指过来，不许本册指回去")

    clauses = _generic_clause_refs(generic)
    rows = re.compile(r"^\| #(?P<id>\d+) \| (?P<what>[^|]+)\| (?P<env>[^|]+)\| (?P<use>[^|]+)\|", re.M)

    # ②③ 项目册逐行：用在 → 本册条文（按标题前缀认），环节 → 那些条文的归属环节
    for m in rows.finditer(project):
        cid, env_cell, use = int(m.group("id")), m.group("env"), m.group("use").strip()
        if use in ("—", "见条文引用处") or not use:
            drift.append(f"落点表 #{cid:02d} 的「用在」是占位（{use or '空'}）—— 这行没人维护")
            continue
        # 「用在」列写的是本册条文标题的**前缀**（可能带「…」省略）：只认前缀，不做子串模糊匹配 ——
        # 模糊匹配会把无关条文一起算进来，环节一多就假红，假红等于没人看。
        # 先整串当前缀比（「用在」本身可能就是标题前缀），再按顿号拆开逐段比 ——
        # 有些标题自己带顿号（「版本、冻结、发布规则不在本节」），只拆不比会把整条漏掉。
        cand = [use.strip().strip("…").strip()] + [s.strip().strip("…").strip() for s in re.split(r"[、，]", use)]
        cand = [c for c in cand if len(c) >= 3]
        matched = [c for c in clauses if any(c["title"].startswith(cd) for cd in cand)]
        if not matched:
            names = "；".join(c["title"] for c in clauses[:3])
            drift.append(f"落点表 #{cid:02d} 的「用在」（{use[:24]}）没点到本册任何条文 —— "
                         f"本册条文形如：{names}…")
            continue
        # 环节判**覆盖**不判相等：「用在」是摘要（常带「…」），一个判据物本来就可能挂在更多环节上；
        # 但漏写就是查表的人少跑一个环节，所以「点到的条文的环节」必须被行里的环节盖住。
        env_true = {c["env"] for c in matched if c["env"]}
        env_cells = {x.strip() for x in env_cell.split("/") if x.strip() and x.strip() != "—"}
        missing = env_true - env_cells
        if missing:
            drift.append(f"落点表 #{cid:02d} 的「环节」漏了 {sorted(missing)}"
                         f"（它点到的条文挂 {sorted(env_true)}，行里写 {sorted(env_cells) or ['—']}）")
    return drift


def project_refs(text: str, schema: dict) -> list[str]:
    """通用规范里引用了项目规范的条文标题（空列表 = 单向干净）。"""
    names = set(schema["字段"].keys())
    return [title for title, body in split_clauses(text, names) if PROJECT_REF.search(body)]
BOOKS = ["Doyah产品需求规格说明书_不做.md"]  # 占位，实际用下面 NORMS
PROJECT_BOOK = "项目管理规范.md"
NORMS = [GENERIC_BOOK, PROJECT_BOOK]

# 条文起行：`- **标题**：` / `1. **标题**：` / `- **标题**（2016-09-29 定）。`
# 口径：**带「判据」声明的条目**才算条文（没声明判据的是叙述，不是条文）。
CLAUSE_RE = re.compile(r"^(?:-|\d+\.) \*\*(?P<title>[^*]{2,120}?)\*\*(?:（[^）]{0,120}）)?[：:。]?")
# 法条形态：`第N条【标题】`（重建后唯一形态；旧 `- **标题**：` 在迁移期内继续认）
STATUTE_RE = re.compile(r"^第\s*[一二三四五六七八九十百千零〇0-9]+\s*条\s*[【\[]\s*(?P<title>[^】\]]{2,120}?)\s*[】\]]")


def load_schema() -> dict:
    return json.loads(SCHEMA.read_text(encoding="utf-8"))


def fields_of(schema: dict) -> list[str]:
    return list(schema["字段"].keys())


def split_clauses(text: str, field_names: set[str], require_judge: bool = True) -> list[tuple[str, str]]:
    """切条文：返回 [(title, body)]。body = 该条起到下一个条文/标题为止。

    字段行（如 `- **判据**：…`）是条文的组成部分，不是新条文 —— 必须排除，
    否则六字段齐全的条文会被切成 7 条（自检「六字段齐全」曾因此误判红）。
    """
    lines = text.split("\n")
    out: list[tuple[str, str]] = []
    cur_title: str | None = None
    cur: list[str] = []
    for line in lines:
        if line.startswith("#"):
            if cur_title is not None:
                out.append((cur_title, "\n".join(cur)))
                cur_title, cur = None, []
            continue
        sm = STATUTE_RE.match(line)
        if sm:
            if cur_title is not None:
                out.append((cur_title, "\n".join(cur)))
            cur_title, cur = sm.group("title"), [line]
            continue
        m = CLAUSE_RE.match(line)
        if m and m.group("title") in field_names:
            if cur_title is not None:
                cur.append(line)
            continue
        if m:
            if cur_title is not None:
                out.append((cur_title, "\n".join(cur)))
            cur_title, cur = m.group("title"), [line]
            continue
        if cur_title is not None:
            cur.append(line)
    if cur_title is not None:
        out.append((cur_title, "\n".join(cur)))
    if require_judge:
        out = [(t, b) for (t, b) in out if "**判据**" in b or "判据：" in b]
    return out


CN_DIGITS = "零一二三四五六七八九"


def num_to_cn(n: int) -> str:
    """1 → 一，10 → 十，16 → 十六，116 → 一百一十六（法条口径）。"""
    if n <= 0:
        return "零"
    if n < 10:
        return CN_DIGITS[n]
    if n < 20:
        return "十" + (CN_DIGITS[n % 10] if n % 10 else "")
    out, zero = "", False
    for unit_val, unit in ((1000, "千"), (100, "百"), (10, "十"), (1, "")):
        d = n // unit_val % 10
        if d:
            if zero and out:
                out += "零"
            out += CN_DIGITS[d] + unit
            zero = False
        elif out:
            zero = True
    return out


def cn_to_num(s: str) -> int:
    s = s.strip()
    if s.isdigit():
        return int(s)
    unit = {"千": 1000, "百": 100, "十": 10}
    total, section, last = 0, 0, 0
    for ch in s:
        if ch in CN_DIGITS:
            last = CN_DIGITS.index(ch)
            section = last
        elif ch in unit:
            section = (last or 1) * unit[ch]
            total += section
            last = 0
    return total + last


CLAUSE_NUM_RE = re.compile(r"^第\s*([一二三四五六七八九十百千零〇0-9]+)\s*条")


def numbering(text: str) -> list[str]:
    """条号连续性：从第一条起，逐条 +1，不许跳号 / 重号 / 复用。

    只认行首 `第N条` 的条文标题行。没有条号的旧形态（`- **标题**`）不算 —— 重建期间
    它报 [待建] 读数，不判红。
    """
    nums = [cn_to_num(m.group(1)) for m in (CLAUSE_NUM_RE.match(l) for l in text.split("\n")) if m]
    if not nums:
        return ["[待建] 尚未使用条号（第一条…）：重建后启用条号连续性判据"]
    bad = []
    for i, n in enumerate(nums, 1):
        if n != i:
            bad.append(f"第 {i} 条位置写的是第 {n} 条（{num_to_cn(i)} ⇒ {num_to_cn(n)}）—— 条号必须从 1 连续、不跳号不重号")
            if len(bad) >= 5:
                bad.append("（其余同类问题略）")
                break
    return bad


def audit(text: str, schema: dict) -> tuple[int, int, list[str]]:
    """返回 (总数, 完整数, 问题列表)。问题列表只列「缺了必填字段」的条文。"""
    required = [f for f, spec in schema["字段"].items() if spec.get("必填")]  # 「是什么」由首行承载，不在此列
    names = set(schema["字段"].keys())
    total = complete = 0
    problems: list[str] = []
    for title, body in split_clauses(text, names):
        total += 1
        missing = [f for f in required if f"**{f}**" not in body]
        head = body.split("\n")[0]
        head_text = head.split("：", 1)[1].strip() if "：" in head else ""
        # 「是什么」两种合法承载：单列 `- **是什么**：` 一行，或直接写在条文首行标题之后
        if "**是什么**" not in body and len(head_text) < 8:
            missing.insert(0, "是什么（既无独立字段，首行正文也不足 8 字）")
        has_judge = "**判据**" in body
        if has_judge and ("【机判】" not in body and "【人判】" not in body):
            problems.append(f"「{title}」判据没标【机判】还是【人判】")
        if not missing:
            complete += 1
        else:
            problems.append(f"「{title}」缺：{' / '.join(missing)}")
    return total, complete, problems


def main(argv: list[str]) -> int:
    schema = load_schema()
    if "--self-test" in argv:
        return self_test(schema)

    global SECTION_IDS
    SECTION_IDS = load_section_ids()
    base = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
    bad: list[str] = []
    rows: list[str] = []
    new_base: dict[str, dict] = {}
    for hit in section_exits():
        bad.append(f"环节定义: {hit}")
    for name in NORMS:
        path = DOCS / name
        text = path.read_text(encoding="utf-8")
        total, complete, problems = audit(text, schema)
        if name == GENERIC_BOOK:
            for title in project_refs(text, schema):
                bad.append(f"{name}: 条文「{title}」引用了项目规范 —— 只许项目规范引用本册（单向）")
            for hit in landing_purity(text):
                bad.append(f"{name}: {hit}")
            for hit in section_refs(text):
                bad.append(f"{name}: {hit}")
            proj_path = DOCS / PROJECT_BOOK
            for hit in term_closure(text, proj_path.read_text(encoding="utf-8") if proj_path.exists() else ""):
                bad.append(f"{name}: {hit}")
        for drift in index_drift(text, schema):
            bad.append(f"{name}: {drift}")
        for bad_sec in bad_sections(text, schema):
            bad.append(f"{name}: {bad_sec}")
        if name == GENERIC_BOOK:
            for hit in book_structure(text):
                if hit.startswith("[债务]"):
                    rows.append(f"{name}: {hit}")          # 债务读数：报出来但不判红
                else:
                    bad.append(f"{name}: {hit}")
        for hit in numbering(text):
            (rows if hit.startswith("[待建]") else bad).append(f"{name}: {hit}")
        pre_bad, pre_notes = preamble_form(text, require=(name == GENERIC_BOOK))
        rows.extend(f"{name}: {n}" for n in pre_notes)
        bad.extend(f"{name}: {hit}" for hit in pre_bad)
        genre_bad, genre_notes = clause_genre(text, schema, name)
        rows.extend(f"{name}: {n}" for n in genre_notes)
        bad.extend(f"{name}: {hit}" for hit in genre_bad)
        for miss in dangling_scripts(text, schema):
            bad.append(f"{name}: 条文点名的脚本不存在 —— 「{miss}」（判据悬空，删脚本必须同批改条文）")
        incomplete = total - complete
        prev = base.get(name, {})
        first_baseline = "--write-baseline" in argv and name not in base
        floor_total = prev.get("总数", 0)
        prev_incomplete = prev.get("缺字段", 0)
        if total < floor_total:
            bad.append(f"{name}: 只解析到 {total} 条条文 < 基线 {floor_total}（空跑防护：解析器坏了或被删条文）")
        if incomplete > prev_incomplete and not first_baseline:
            bad.append(f"{name}: 缺字段条文 {incomplete} 条 > 基线 {prev_incomplete} 条（新条文不许裸奔）")
        if complete < prev.get("完整", 0) and not first_baseline:
            bad.append(f"{name}: 六字段完整 {complete} 条 < 基线 {prev.get('完整', 0)} 条（不许把完整条文改回散文）")
        gap = coverage_gap(text, schema)
        prev_gap = prev.get("覆盖范围缺", 0)
        if len(gap) > prev_gap and not first_baseline:
            bad.append(f"{name}: {len(gap)} 条条文写了判据却没声明覆盖范围（> 基线 {prev_gap}）—— 铁律 13：覆盖不全只许报「未知」，不许报「发现」")
        rows.append(f"  {name}: 条文 {total} 条 · 完整 {complete} · 缺字段 {incomplete} · 缺覆盖范围 {len(gap)}")
        new_base[name] = {"总数": max(total, floor_total), "完整": max(complete, prev.get("完整", 0)),
                          "缺字段": min(incomplete, prev_incomplete) if prev else incomplete,
                          "覆盖范围缺": min(len(gap), prev_gap) if prev else len(gap)}
        for p in problems[:40]:
            rows.append(f"    · {p}")

    # 落点**单向**校验（项目册 §0.6 → 通用册；反方向一律判红）
    generic_text = (DOCS / GENERIC_BOOK).read_text(encoding="utf-8")
    project_text = (DOCS / "项目管理规范.md").read_text(encoding="utf-8")
    for drift in landing_drift(generic_text, project_text):
        bad.append(f"落点表: {drift}")

    print("条文写法判据（六字段）")
    print("\n".join(rows))
    if bad:
        print("❌ 条文写法未通过：")
        for b in bad:
            print("  ·", b)
        return 1
    if "--write-baseline" in argv:
        BASELINE.write_text(json.dumps(new_base, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"基线已写：{BASELINE.name}")
    print("✅ 条文写法通过（缺字段只许降不许升）")
    print("   覆盖范围：只判条文里**明文写的** `Scripts/<文件名>` 是否存在 —— "
          "`import 模块名`（不带 .py）、跨仓引用、cron / launchd 调用判不了，"
          "那三类靠「挪而不删 + 全量门禁跑一遍」兜（见 Scripts/archive/README.md）")
    return 0


def self_test(schema: dict) -> int:
    global SECTION_IDS
    SECTION_IDS = load_section_ids()
    good = """- **样例条文**：这条条文的首行正文承载「是什么」，长度必须够八个字
- **是什么**：一句话。
- **不是什么**：边界。
- **判据**：【机判】`true`。
- **负例**：改坏必红。
- **读数口径**：无。
- **归属环节**：B1
- **归属**：本条文自身。
"""
    miss_negative = good.replace("- **负例**：改坏必红。\n", "")
    no_judge_kind = good.replace("【机判】", "")
    ghost_script = good.replace("- **判据**：【机判】`true`。", "- **判据**：【机判】`Scripts/no-such-gate.py`。")
    cites_project = good.replace("- **读数口径**：无。", "- **读数口径**：见《项目管理规范》§5。")
    generic_ok = good  # 同一条文放进「通用」这一侧，只要不引用项目规范就该绿
    bad_section = good.replace("**归属环节**：B1", "**归属环节**：ZZ9")
    good_section = good
    no_section = good.replace("- **归属环节**：B1\n", "")
    cases = [
        ("六字段齐全", good, True),
        ("归属环节写错 ⇒ 判红", bad_section, False),
        ("归属环节合法 ⇒ 绿", good_section, True),
        ("收紧期缺归属环节 ⇒ 判红", no_section, False),
        ("缺负例字段", miss_negative, False),
        ("判据没标机判/人判", no_judge_kind, False),
        ("通用条文引用项目规范 ⇒ 判红", cites_project, False),
        ("通用条文不引用项目规范 ⇒ 绿", generic_ok, True),
        ("条文点名不存在的脚本 ⇒ 判红", ghost_script, False),
        ("通用条文写回具体命令 ⇒ 判红",
         good.replace("- **判据**：【机判】`true`。", "- **判据**：【机判】`swift test` 的收尾行。"), False),
        ("通用条文写平台专有名 ⇒ 判红",
         good.replace("- **读数口径**：无。", "- **读数口径**：在 macOS 上跑。"), False),
        ("通用条文写本仓文件名 ⇒ 判红", "- **样例条文**：入口页 `AGENTS.md` 必须与规范同号。\n- **判据**：【人判】核条数。\n- **覆盖范围**：只核条数。\n- **归属环节**：E3\n", False),
        ("通用条文用「本件」指自己 ⇒ 判红", "- **样例条文**：本件不引用项目规范。\n- **判据**：【人判】核。\n- **覆盖范围**：只核。\n- **归属环节**：D1\n", False),
        ("通用条文写中文平台词「公证」⇒ 判红", "- **样例条文**：分发前必须公证，否则别人的机器不让跑。\n- **判据**：【人判】核。\n- **覆盖范围**：只核。\n- **归属环节**：D3\n", False),
        ("通用条文写本仓脚本名 ⇒ 判红", "- **样例条文**：这条判据由 `check-doc-numbers` 把关，够八个字。\n- **判据**：【人判】核。\n- **覆盖范围**：只核。\n- **归属环节**：C3\n", False),
        ("通用条文用落点编号 ⇒ 绿",
         good.replace("- **判据**：【机判】`true`。", "- **判据**：【机判】〈落点 #01〉 的收尾行。"), True),
    ]
    ok = 0
    for name, text, want_pass in cases:
        total, complete, problems = audit(text, schema)
        passed = (total == 1 and not problems and not project_refs(text, schema)
                  and not dangling_scripts(text, schema) and not bad_sections(text, schema)
                  and not landing_purity(text))
        mark = "✓" if passed == want_pass else "✗"
        if passed == want_pass:
            ok += 1
        print(f"  {mark} {name} ⇒ {'绿' if passed else '红'}，应为{'绿' if want_pass else '红'}")
    # 落点**单向**校验（2026-11-18 方向反转）：通用册指回项目 ⇒ 判红；项目册「用在」点不到条文 ⇒ 判红
    clause_clean = ("- **样例条文**：这条条文的首行正文承载「是什么」，长度必须够八个字\n"
                    "- **判据**：【机判】〈判据物〉。\n"
                    "- **归属环节**：B1\n")
    clause_with_ref = ("- **样例条文**：这条条文的首行正文承载「是什么」，长度必须够八个字\n"
                       "- **判据**：【机判】〈落点 #01〉。\n"
                       "- **归属环节**：B1\n")
    drift_cases = [
        ("通用册指回项目编号 ⇒ 判红", clause_with_ref, "| #01 | `x` | B1 | 样例条文 |", False),
        ("通用册零指针 + 项目册点到条文 ⇒ 绿", clause_clean, "| #01 | `x` | B1 | 样例条文 |", True),
        ("项目册「用在」是占位 ⇒ 判红", clause_clean, "| #01 | `x` | B1 | 见条文引用处 |", False),
        ("项目册「用在」点到不存在的条文 ⇒ 判红", clause_clean, "| #01 | `x` | B1 | 另一条不相干的条文 |", False),
        ("项目册「环节」漏了条文所在环节 ⇒ 判红", clause_clean, "| #01 | `x` | C9 | 样例条文 |", False),
    ]
    for name, generic, project, want_pass in drift_cases:
        passed = not landing_drift(generic, project)
        mark = "✓" if passed == want_pass else "✗"
        if passed == want_pass:
            ok += 1
        print(f"  {mark} {name} ⇒ {'绿' if passed else '红'}，应为{'绿' if want_pass else '红'}")
    # 术语闭环：空词必须判红、项目册缺词必须判红、两边都闭环才绿
    g_term = ("> **术语（固定含义）**：\n> **入口页** = 仓根那份索引；\n"
              "> 这些名字每个项目各自不同。\n\n正文里要用到入口页这个词。\n")
    p_term_ok = "> **术语对应**：入口页 = 本仓根目录那份索引。\n\n| # | 判据物 |\n|---|---|\n"
    term_cases = [
        ("术语表里的词正文一次没用 ⇒ 判红",
         g_term.replace("正文里要用到入口页这个词。", "正文。"), p_term_ok, False),
        ("项目册「术语对应」缺词 ⇒ 判红",
         g_term, "> **术语对应**：文档根 = 文档目录。\n\n| # | 判据物 |\n|---|---|\n", False),
        ("术语两边闭环 ⇒ 绿", g_term, p_term_ok, True),
    ]
    for name, gt, pt, want_clean in term_cases:
        clean = not term_closure(gt, pt)
        mark = "✓" if clean == want_clean else "✗"
        if clean == want_clean:
            ok += 1
        print(f"  {mark} {name} ⇒ {'绿' if clean else '红'}，应为{'绿' if want_clean else '红'}")
    # 章结构（本书的章 = 环节）：新章必须是环节章；「补记」类章不许新开；条文不许躺错章
    cfg = load_book_structure()
    whitelist_heads = "".join(f"## {c}\n\n" for c in cfg.get("非环节章白名单", []))
    def _book(chapter: str, env: str = "B1", repeat: int = 1) -> str:
        body = "".join(f"- **样例条文**：{i} 号条文的首行正文要够八个字\n- **判据**：【机判】`true`。\n"
                       f"- **归属环节**：{env}\n\n" for i in range(repeat))
        return whitelist_heads + f"## {chapter}\n\n" + body
    structure_cases = [
        ("新开「其他补记」章 ⇒ 判红", _book("10 其他补记"), False),
        ("新开环节章且条文归属对得上 ⇒ 绿", _book("10 实现环节规则（B1）"), True),
        ("条文躺进不点它的章 ⇒ 超上限判红", _book("10 实现环节规则（B1）", env="F1", repeat=64), False),
        ("环节章点名范围覆盖条文归属 ⇒ 绿", _book("10 实现环节规则（B1–B6）", env="B4"), True),
    ]
    for name, text, want_clean in structure_cases:
        hits = [h for h in book_structure(text) if not h.startswith("[债务]")]
        clean = not hits
        mark = "✓" if clean == want_clean else "✗"
        if clean == want_clean:
            ok += 1
        print(f"  {mark} {name} ⇒ {'绿' if clean else '红'}，应为{'绿' if want_clean else '红'}")
    # 条文体裁（七问）：新条文缺「为什么 / 能力前提」⇒ 计数超基线 ⇒ 红
    def _genre_clause(i: int, with_why: bool = False) -> str:
        body = (f"- **样例条文{i}**：这条条文的首行正文要够八个字\n"
                f"- **判据**：【机判】`true`。\n- **归属环节**：B1\n")
        return body + (("- **为什么**：从某次事故上长出来的。\n"
                        "- **能力前提**：要一个能跑门禁的终端。\n") if with_why else "")
    genre_cases = [
        ("新条文不写为什么 ⇒ 超基线判红", "".join(_genre_clause(i) for i in range(117)), False),
        ("新条文写满 Why / What / How ⇒ 绿", "".join(_genre_clause(i) for i in range(116)) + _genre_clause(999, True), True),
    ]
    for name, text, want_clean in genre_cases:
        hits, _ = clause_genre(text, schema, "通用开发规范.md")
        clean = not hits
        mark = "✓" if clean == want_clean else "✗"
        if clean == want_clean:
            ok += 1
        print(f"  {mark} {name} ⇒ {'绿' if clean else '红'}，应为{'绿' if want_clean else '红'}")
    # 序言是叙述层：写「为什么」绿；写规矩或引用条号红；没有序言只出待建读数
    pre_cases = [
        ("序言只讲为什么 ⇒ 绿", "## 序言\n\n这本规范是从三次返工里长出来的。它替接手的人省掉重复踩坑。\n\n## 1 总纲\n", 0, False),
        ("序言里写「必须」⇒ 红", "## 序言\n\n改完文档必须以 exit 0 收尾。\n\n## 1 总纲\n", 1, False),
        ("序言里引用条号 ⇒ 红", "## 序言\n\n详见第 42 条。\n\n## 1 总纲\n", 1, False),
        ("没有序言 ⇒ 不算违规，只记待建", "## 1 总纲\n", 0, True),
    ]
    for name, text, want_red, want_note in pre_cases:
        hits, notes = preamble_form(text)
        clean = (len(hits) == want_red) and (bool(notes) == want_note)
        mark = "✓" if clean else "✗"
        if clean:
            ok += 1
        print(f"  {mark} {name} ⇒ 违规 {len(hits)} 条 / 读数 {len(notes)} 条")
    # 条号连续性：连续绿 / 跳号红 / 重号红 / 还未用条号只记待建
    num_cases = [
        ("条号连续 ⇒ 绿", "第一条【甲】\n（一）**是什么**：够八个字的正文。\n第二条【乙】\n（一）**是什么**：够八个字的正文。\n", False, False),
        ("条号跳号 ⇒ 红", "第一条【甲】\n第二条【乙】\n第三条【丙】…\n第五条【丁】\n", True, False),
        ("条号重号 ⇒ 红", "第一条【甲】\n第三条【乙】\n第三条【丙】\n", True, False),
        ("还没用条号 ⇒ 只记待建", "- **甲**：够八个字的正文。\n- **判据**：【机判】`true`\n", False, True),
    ]
    for name, text, want_red, want_note in num_cases:
        hits = numbering(text)
        real = [h for h in hits if not h.startswith("[待建]")]
        note = len(real) != len(hits)
        clean = (bool(real) == want_red) and (note == want_note)
        mark = "✓" if clean else "✗"
        if clean:
            ok += 1
        print(f"  {mark} {name} ⇒ 违规 {len(hits) if not note else 0} 条 / 待建 {int(note)}")
    total_cases = len(cases) + len(drift_cases) + len(term_cases) + len(structure_cases) + len(genre_cases) + len(pre_cases) + len(num_cases)
    print(f"自检 {ok}/{total_cases} 达到预期")
    return 0 if ok == total_cases else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
