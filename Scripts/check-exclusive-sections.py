#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""层级门禁：一次改动不得越界（三书分层形态 A + 契约层锁定，2026-09-27 拍板）。

**三仓同源副本**：`DoyahStudio/Scripts/` · `DoyahRetro/tools/` · `DoyahNotes/tools/logic-check/`
三份**逐字节同一份**（本文件 = 提案 `0003` 裁决后的「并集」版）。标记四种 —— `[独占:apple]` /
`[独占:nonapple]` / `[独占:linux]` / `[开放]`，无标记 = 契约层。（Notes 的词表出自其
`Docs/概要设计.md` §2.2；Studio / Retro 同义写作 `[独占:macos]` / `[独占:windows]`，由下面的
别名归一 —— 脚本因此三仓通用。）

三类节 —— 标题行（`#`~`######`）可带标记，标记对**该节及其所有子节**生效（外层优先于内层）：

  1. `[独占:X]`  —— **只有 X 侧**能改（例：`### 2.3 契约 → Linux 实现 [独占:linux]`）
  2. `[开放]`    —— 台账类节（变更记录 / 索引）：**任何一侧**都能追加，含自己平台的行
  3. 无标记      —— **契约层**：**只有契约所有者**（`--contract-owner`，默认 `apple` = 大河马）能改；
                    其他侧要么走提案（`Docs/proposals/`），要么在改动行 / 上一行 / 提交信息注
                    `contract-change：理由` 留痕
  4. 新增节      —— **非契约所有者**不得在契约层锁定的文档里**新开一个节**（含新开 `[开放]` 台账节）：
                    **纯插入**的节标题必须带 `[独占:X]`（对侧 L-42 判据 / 提案 `0003`，2026-09-27 第 20 轮移植）。
                    `[开放]` 的语义是「台账节任何一侧都能追加」，**不是自己开新节的许可证** —— 新节点由
                    契约所有者开；逃生门同第 3 类

**侧别别名**（三仓词表混用时脚本不用改）：`apple|macos|ios` → apple，`nonapple|windows|android|harmony` → nonapple。
于是三仓通用钩子里那一行 `--mine windows` 与 Notes 的 `--mine nonapple` 等价。⚠️ 但**钩子把侧别写死**
会让**运行方自己被当成对侧**（在 macOS 机器上提交判红）⇒ 装钩子前先让钩子按运行方推断侧别
（`DOYAH_SIDE`，缺省按 `uname`）—— 队列 **L-48** 第 0 步，未解决前不装。

契约层锁定只对**三书**生效（文件名含 `概要设计` / `需求规范书` / `产品能力规划说明书`；
可用 `--contract-docs` 追加，例如把 `核心契约` 也纳入）；其他 .md（开发记录、任务清单、提案、
跨平台框架设计等）只受独占节规则约束 —— 记录类文件是本侧可写面，不该被契约层锁住。

逃生门（都会打印理由）：
  · 行内或上一行注 `exclusive-allow：理由`（独占节）/ `contract-change：理由`（契约层）
  · 提交信息整批 `exclusive-allow: 理由` / `contract-change: 理由`
  · 独占节正文注 `exclusive-allow-section`（整节豁免，用于「首建占位节」）

汇报：任一类违规 → 退出 1 并点名 `文件:行号`；**拿不到基线 → 退出 2**（含「`--base` 显式给了却解析不到」
那一档，不以「没基线 / 基线解析不到」为由静默放行 = 修掉越界门禁的空跑缺陷）；无候选文件 → 退出 0 但
措辞是 **⚠️ 无内容可查 ≠ 已通过**；全合法 → 退出 0（并打印受检行数与所用基线）。


未跟踪文档
----------
· **未跟踪的新增 `.md` 也纳入受检**（提案 `0003` 裁决，2026-09-27 本仓第 24 轮）：候选集 = 已跟踪改动 ∪
  未跟踪新增。旧版只收 `git diff` 里的已跟踪改动，对未跟踪文档**是盲的** —— 「写一份未跟踪文档、
  里面带着对侧 `[独占:*]` 节」能整份绕过越界门禁（对侧第 24 轮红/绿成对证据）。渲染用
  `git diff --no-index /dev/null <path>`，**不动索引**（不必先 `git add -N`）；命中时**显式播报**
  （`ℹ️ 未跟踪的新增文档 N 份…`），不做静默多查。`--files` 显式指定时以指定集为准。
  **代价（已知、接受）**：尚未 `git add` 的草稿也会被判 —— 口径是三仓一律纳入，判据与其他新增文件完全相同。

注意事项（血泪换来的三条，别踩）
--------------------------------
· **标记只从标题行读；标题里提到对侧的标记文本 = 声明「本节归该侧」** —— 正文里引用标记无妨，
  但把 `[独占:windows]` 写进标题（哪怕本意只是「引用」）会让整节被判归对侧。2026-09-27 实测：
  概要设计 §8.5 标题里引用了 `[独占:windows]`，`--mine macos` **当场报红 14 处**。
· **「一节的归属 = 它自己的标题 / 最近祖先的标题」** —— 非所有者想「先给标题追加 `[开放]` 解锁、
  再写正文」是行不通的：**改标题行本身**就被判成契约层改动（L-42 探针 V5/V6 实测报红）。
  这是**正确行为**，不是误报 —— 别再按「误报」去改判词。
· **负例必须在「改后」的工作区上跑**：夹具若「先 `git checkout` 还原、再调用 `check()`」，测的是旧
  内容 —— 「末尾新增的节」会被算成 `line0 >= len(lines)` 而**静默跳过**，自测照样全绿（L-42 实测）。

已知局限
--------
· 打印「受检改动 0 行」不是假绿：文件确在候选里，只是**范围内没有可判的行**（无标记且不在三书里）。
· 判据 ④（新增节必须带 `[独占:*]`）只对**契约层锁定的文档**（默认三书 + `--contract-docs` 追加的）生效，
  且只看**纯插入**的标题行（`-`/`+` 成对的标题改动走普通改动判定，不重复判）。
· 契约层锁定只认文件名（含 `概要设计` / `需求规范书` / `产品能力规划说明书`），改名会绕过。
· 未跟踪文件按「整份都是新增行」处理：`-` 侧为空 ⇒「新文件里删了旧文件的东西」这种情形看不见。
· 「无候选文件」时打印的是**⚠️ 无内容可查 ≠ 已通过**（退出码仍是 0）—— 「查了个空」不许读成「查过且合法」
  （口径来自第 24 / 31 轮；未跟踪增量并入后这条不再是盲点信号，但仍保留在措辞里）。

用法（三仓通用；路径按仓替换：Studio `Scripts/` · Retro `tools/` · Notes `tools/logic-check/`）
--------------------------------------------------------------------------------------------
    python3 Scripts/check-exclusive-sections.py                          # 自动推断本侧，基线默认 origin/master
    python3 Scripts/check-exclusive-sections.py --mine macos --base origin/master   # 提交前默认姿势（显式基线最稳）
    python3 Scripts/check-exclusive-sections.py --mine nonapple          # Notes 仓写法（别名等价）
    python3 Scripts/check-exclusive-sections.py --contract-owner macos    # 契约层归属（默认 apple ≡ macos / 大河马）
    python3 Scripts/check-exclusive-sections.py --contract-docs 核心契约  # 追加契约层锁定的文档
    python3 Scripts/check-exclusive-sections.py --base HEAD~1 --files Docs/概要设计.md
    python3 Scripts/check-exclusive-sections.py --diff-file d.patch       # 用现成 diff（CI / 自测）
    python3 Scripts/check-exclusive-sections.py --self-test               # 自测 18 例（含判据 ④ 与未跟踪增量）

本侧推断：darwin → apple，其它 → nonapple（可用 --mine 覆盖；写 macos / windows 也行，别名等价）。
基线推断顺序 origin/master → HEAD~1 → HEAD，实际采用哪一个会打印出来（拿不到就退出 2，绝不当成「没问题」）。
"""
import argparse
import os
import re
import subprocess
import sys

MARKER_RE = re.compile(r"\[独占:([A-Za-z0-9_\-]+)\]")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
ALLOW = "exclusive-allow"          # 独占节的显式豁免
CONTRACT_TAG = "contract-change"    # 契约层的显式痕迹（等价豁免，但语义是「该动契约」）
ALLOW_SECTION = "exclusive-allow-section"   # 独占节正文里的整节豁免（用于「首建占位节」等）
OPEN_MARK = "[开放]"               # 开放节：任何一侧都可改（变更记录 / 索引这类台账节）
DEFAULT_DOCS = ("概要设计", "需求规范书", "产品能力规划说明书")   # 契约锁定范围：三书（可用 --contract-docs 追加）
# 侧别别名：三仓词表混用（Notes = apple / nonapple，Retro / Studio = macos / windows）时脚本不必各写一份。
# 归一后只有三个 canonical 侧：apple（大河马）/ nonapple（小河马）/ linux（公司 Linux 环境，两侧都别动）。
SIDE_ALIASES = {
    "apple": "apple", "macos": "apple", "ios": "apple",
    "nonapple": "nonapple", "windows": "nonapple", "android": "nonapple",
    "harmony": "nonapple", "harmonyos": "nonapple",
    "linux": "linux",
}


def side(tok):
    """把任一词表里的标记归一成 canonical 侧名；未知标记原样返回（于是仍按「不是本侧」处理）。"""
    if tok is None:
        return None
    return SIDE_ALIASES.get(tok.lower(), tok.lower())


def _unquote(p):
    """把 git 的 C 风格引号路径还原成真实 UTF-8 路径。"""
    if len(p) >= 2 and p.startswith('"') and p.endswith('"'):
        body = p[1:-1]
        out, i = bytearray(), 0
        while i < len(body):
            ch = body[i]
            if ch == "\\" and i + 3 < len(body) and body[i + 1:i + 4].isdigit():
                out += bytes([int(body[i + 1:i + 4], 8)])
                i += 4
            elif ch == "\\" and i + 1 < len(body):
                out += body[i + 1].encode("utf-8")
                i += 2
            else:
                out += ch.encode("utf-8")
                i += 1
        return out.decode("utf-8", "replace")
    return p


def diff_target_path(raw):
    """从 `diff --git a/x b/y` 取出目标路径（兼容引号转义与空格）。"""
    rest = raw[len("diff --git "):]
    m = re.match(r"^(\S+|\"[^\"]*\")\s+(\S+|\"[^\"]*\")\s*$", rest)
    if m:
        return _unquote(m.group(2))[2:] if m.group(2).startswith(("a/", "b/")) else _unquote(m.group(2))
    m = re.search(r' b/(.+)$', rest)
    return _unquote(m.group(1)) if m else None


def parse_sections(lines):
    """返回 [(token, level, start_idx0, end_idx0, title)]，start/end 为 0 基行号（闭区间）。"""
    heads = []
    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if not m:
            continue
        level, title = len(m.group(1)), m.group(2)
        tok = MARKER_RE.search(title)
        heads.append((i, level, tok.group(1) if tok else None, title.strip()))
    out = []
    for idx, (i, level, tok, title) in enumerate(heads):
        if tok is None:
            continue
        end = len(lines) - 1
        for j, lv, _t, _ti in heads[idx + 1:]:
            if lv <= level:
                end = j - 1
                break
        out.append((tok, level, i, end, title))
    return out


def section_of(sections, line0):
    for tok, _lv, s, e, title in sections:
        if s <= line0 <= e:
            return tok, title, (s, e)
    return None, None, None


def parse_all_sections(lines):
    """所有标题（含无标记）→ [(idx0, level, title, tok, is_open)]。"""
    heads = []
    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if not m:
            continue
        title = m.group(2)
        tok = MARKER_RE.search(title)
        heads.append((i, len(m.group(1)), title, tok.group(1) if tok else None, OPEN_MARK in title))
    return heads


def kind_of(lines, line0):
    """某行归属：('exclusive', tok) / ('open', None) / ('contract', None) / ('none', None)。

    按「祖先链」判定：`[独占:X]` / `[开放]` 对**其全部子节**生效（与 parse_sections 一致），
    外层标记优先于内层；一条链上都没有标记 → 契约层（锁定给 contract_owner）。
    """
    stack = []
    for i, lv, title, tok, is_open in parse_all_sections(lines):
        if i > line0:
            break
        while stack and stack[-1][0] >= lv:
            stack.pop()
        stack.append((lv, tok, is_open))
    if not stack:
        return ("none", None)
    for _lv, tok, _o in stack:
        if tok:
            return ("exclusive", tok)
    for _lv, _t, is_open in stack:
        if is_open:
            return ("open", None)
    return ("contract", None)


def enclosing_title(lines, line0):
    """line0 所在「最近的有标题的节」的标题（无标题则返回空串）。

    为什么需要它（对侧 L-42 顺手修掉的一处误报）：无独占标记的节不在 `parse_sections` 的返回里
    （它只收带 `[独占:*]` 的节），于是 `section_of` 给 `None`，报错就印成「契约节『』」——
    空标题读起来像误报。本函数按祖先链取真实标题，报错点得到名（本仓第 20 轮移植）。
    """
    stack = []
    for i, lv, title, _tok, _is_open in parse_all_sections(lines):
        if i > line0:
            break
        while stack and stack[-1][0] >= lv:
            stack.pop()
        stack.append((lv, title.strip(), _tok, _is_open))
    return stack[-1][1] if stack else ""


def read_lines_from_git(base, path):
    r = subprocess.run(["git", "-c", "core.quotepath=false", "show", "%s:%s" % (base, path)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return r.stdout.splitlines()


def parse_diff(text):
    """返回 {path: [(kind, old_line0, new_line0, content)]}，kind ∈ {'+', '-'}。"""
    files, cur, old_no, new_no = {}, None, 0, 0
    for raw in text.splitlines():
        if raw.startswith("diff --git "):
            cur = diff_target_path(raw)
            if cur:
                files.setdefault(cur, [])
            old_no = new_no = 0
            continue
        if raw.startswith("+++ ") or raw.startswith("--- "):
            continue
        m = HUNK_RE.match(raw)
        if m:
            old_no = int(m.group(1))
            new_no = int(m.group(3))
            continue
        if cur is None:
            continue
        if raw.startswith("+"):
            files[cur].append(("+", None, new_no - 1, raw[1:]))
            new_no += 1
        elif raw.startswith("-"):
            files[cur].append(("-", old_no - 1, None, raw[1:]))
            old_no += 1
    return {k: v for k, v in files.items() if v}


def head_message():
    r = subprocess.run(["git", "log", "-1", "--pretty=%B"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


TAGS = (ALLOW, CONTRACT_TAG)


def has_tag(s):
    return any(x in s for x in TAGS)


def group_pairs(hunks):
    """把相邻的 -/+ 折叠成替换对：(idx_list, contents, allow) —— 替换的任一侧带豁免即整体豁免。"""
    pairs, i = [], 0
    while i < len(hunks):
        cur = hunks[i]
        nxt = hunks[i + 1] if i + 1 < len(hunks) else None
        if cur[0] == "-" and nxt and nxt[0] == "+":
            items = [cur, nxt]
            i += 2
        else:
            items = [cur]
            i += 1
        allow = any(has_tag(it[3]) for it in items)
        pairs.append((items, allow))
    return pairs


def check(files, mine, theirs, base, diff_text, quiet=False, contract_owner="apple",
          contract_docs=DEFAULT_DOCS, untracked=()):
    if untracked:
        print("ℹ️  未跟踪的新增文档 %d 份已按「整份新增」纳入检查：%s"
              % (len(untracked), "、".join(untracked[:5]) + ("…" if len(untracked) > 5 else "")))
    parsed = parse_diff(diff_text)
    if not parsed:
        if not quiet:
            print("✅ 越界检查：本次改动未涉及受检文档（或无可解析 diff）")
        return 0
    msg = head_message()
    blanket = None
    for tag in TAGS:
        blanket = re.search(r"%s\s*:\s*(.+)" % tag, msg)
        if blanket:
            break
    if blanket:
        print("⏭️  越界检查：HEAD 提交信息含豁免（理由：%s）—— 放行" % blanket.group(1).strip())
        return 0
    violations, checked, contracts = [], 0, []
    newsecs = []          # 判据 ④：非契约所有者新开、又没带 [独占:*] 的节标题（含新开 [开放]）
    for path, hunks in sorted(parsed.items()):
        if files and path not in files:
            continue
        if not path.endswith(".md"):
            continue
        wd_lines = None
        p = os.path.join(os.getcwd(), path)
        if os.path.exists(p):
            with open(p, encoding="utf-8") as fh:
                wd_lines = fh.read().splitlines()
        base_lines = read_lines_from_git(base, path) if base else None
        new_secs = parse_sections(wd_lines) if wd_lines else []
        old_secs = parse_sections(base_lines) if base_lines else []
        sect_allow = set()
        for tok, _lv, s, e, _ti in (new_secs if wd_lines else []) :
            if any(ALLOW_SECTION in x for x in (wd_lines[s:e + 1] if wd_lines else [])):
                sect_allow.add((tok, s, e))
        for items, pair_allow in group_pairs(hunks):
            if pair_allow:
                continue
            for kind, old_l, new_l, content in items:
                if ALLOW in content:
                    continue
                if kind == "+":
                    lines, secs = wd_lines, new_secs
                    line0 = new_l
                    line1 = new_l + 1
                else:
                    lines, secs = base_lines, old_secs
                    line0 = old_l
                    line1 = old_l + 1
                if not lines or line0 is None or line0 >= len(lines):
                    continue
                prev = lines[line0 - 1] if line0 > 0 else ""
                if ALLOW in prev:
                    continue
                # ④ 新增节必须带 [独占:*]（对侧 L-42 判据，本仓第 20 轮移植）：非契约所有者不得在
                #    契约层锁定的文档里新开一个「谁都能写」的节。只看**纯插入**的标题行（len(items)==1），
                #    `-`/`+` 成对的标题改动走下面的普通判定（改标题行本身已属契约层改动）；
                #    新开 `[开放]` 台账节同样判红 —— 「先解锁再改」就是靠这个绕开锁定的。
                if (kind == "+" and len(items) == 1 and side(mine) != side(contract_owner)
                        and any(d in os.path.basename(path) for d in contract_docs)
                        and HEADING_RE.match(content) and not MARKER_RE.search(content)):
                    newsecs.append((path, line1, content.strip()[:80]))
                    continue
                tok, title, _rng = section_of(secs, line0)
                if tok is not None:
                    if any(tok == st and s <= line0 <= e for st, s, e in sect_allow):
                        continue
                    checked += 1
                    if side(tok) != side(mine):
                        violations.append((path, line1, tok, title, content.strip()[:80]))
                    continue
                # 无独占标记 → 契约层（锁定给 contract_owner）或 [开放] 节
                if not any(d in os.path.basename(path) for d in contract_docs):
                    continue          # 非三书：不锁契约层（只保护独占节）
                k, _ = kind_of(lines, line0)
                if k != "contract":
                    continue          # [开放] / 无标题：放行
                checked += 1
                if side(mine) != side(contract_owner):
                    contracts.append((path, line1, title or enclosing_title(lines, line0),
                                      content.strip()[:80]))
    # 去重：同一文件的同一处改动只报一次（newsecs 的元素只有 (path, line) 两元组）
    def _dedupe(items, keylen):
        seen, out = set(), []
        for it in items:
            key = it[:keylen]
            if key in seen:
                continue
            seen.add(key)
            out.append(it)
        return out

    newsecs = _dedupe(newsecs, 2)
    violations = _dedupe(violations, 3)
    contracts = _dedupe(contracts, 3)
    if newsecs:
        print("❌ 新增节未带独占标记：%d 处（在契约层锁定的文档里新开节点（含 `[开放]`）必须带 "
              "`[独占:*]`，本侧=%s）" % (len(newsecs), mine))
        for path, ln, snip in newsecs:
            print("   %s:%d 新插入的节标题：%s" % (path, ln, snip))
        print("   处理：① 给新节标上 `[独占:%s]`；② 新台账节 / 契约层新地请交 %s 侧开；"
              "③ 确有必要时在该行或上一行注 `%s：理由`（或提交信息 `%s: 理由`）。"
              % (mine, contract_owner, CONTRACT_TAG, CONTRACT_TAG))
    if violations:
        print("❌ 越界检查不通过：%d 处改动落在对侧独占节内（本侧=%s）" % (len(violations), mine))
        for path, ln, tok, title, snip in violations:
            print("   %s:%d 落在 [独占:%s]『%s』：%s" % (path, ln, tok, title[:40], snip))
        print("   处理：① 交对侧来改；② 若确有必要，在该行或上一行注 `%s：理由`；"
              "③ 整批豁免用提交信息 `%s: 理由`。" % (ALLOW, ALLOW))
    if contracts:
        print("❌ 契约层锁定不通过：%d 处改动落在契约层（只允许 %s 侧修改，本侧=%s）"
              % (len(contracts), contract_owner, mine))
        for path, ln, title, snip in contracts:
            print("   %s:%d 落在契约节『%s』：%s" % (path, ln, (title or "")[:40], snip))
        print("   处理：① 契约层改动走提案，交 %s 侧落笔；② 确有必要时在该行或上一行注 "
              "`%s：理由`，或提交信息 `%s: 理由`；③ 台账节请标 `%s`。" % (contract_owner, CONTRACT_TAG, CONTRACT_TAG, OPEN_MARK))
    if newsecs or violations or contracts:
        return 1
    print("✅ 越界检查通过：受检改动 %d 行（含契约层），均合法（本侧=%s，契约层属 %s）"
          % (checked, mine, contract_owner))
    return 0


def collect_files(args, base=None):
    if args.files:
        return list(args.files)
    base = args.base or base          # ← 曾漏掉：不传 --base 时恒返回空 = 门禁空转（假绿）
    # （main 现在保证 base 一定解析得到，拿不到直接退出 2）
    if base:
        r = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--name-only", base],
                           capture_output=True, text=True)
        if r.returncode == 0:
            return [x for x in r.stdout.split() if x.endswith(".md")]
    return []


def untracked_md():
    """未跟踪的新增 `.md`（`git ls-files --others --exclude-standard`）。

    对侧提案 `0003` 裁决（2026-09-27，本仓第 24 轮）：并集含未跟踪文档。旧版只收 `git diff` 里的
    已跟踪改动 ⇒ 对未跟踪文档**是盲的**；代价是「未跟踪草稿也会被判」，故命中时显式播报（见 `check`）。
    """
    r = subprocess.run(["git", "-c", "core.quotepath=false", "ls-files", "--others",
                        "--exclude-standard", "--", "*.md"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return []
    return [_unquote(x) for x in r.stdout.splitlines() if x.strip()]


def diff_of_untracked(path):
    """把未跟踪文档渲染成与 `git diff` 同形状的 diff（整份新增，逐行 `+`）。

    `git diff --no-index /dev/null <path>` —— **不动索引**（所以不必先 `git add -N`）；
    退出码 1 = 「有差异」，属正常，不当失败（0 = 两侧同为空，也不当失败）。
    """
    r = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--no-index", "--unified=0",
                        "--", "/dev/null", path],
                       capture_output=True, text=True)
    return r.stdout if r.returncode in (0, 1) else ""


def assemble_candidates(base, files):
    """受检候选集 = 已跟踪改动 ∪ 未跟踪新增（提案 `0003` 裁决）。

    返回 `(files, diff_text, untracked)`；`diff_text is None` = 渲染失败（调用方退出 2，绝不放行）。
    `--files` 显式指定时以指定集为准，不自动并入未跟踪。
    """
    untracked = [p for p in untracked_md() if not files or p in files]
    allf = list(files) + [p for p in untracked if p not in files]
    diff_text = ""
    if files:
        r = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--unified=0", base, "--"] + files,
                           capture_output=True, text=True)
        if r.returncode != 0:
            return allf, None, untracked
        diff_text = r.stdout
    for p in untracked:
        diff_text += diff_of_untracked(p)
    return allf, diff_text, untracked


def self_test():
    import tempfile
    doc = """# 概要设计（样例）

| 阅读约定 | `[独占:apple]` / `[独占:nonapple]` = 各侧实现细节；无标记 = 契约层 |

## 3. 平台适配层契约

契约正文，只有契约所有者能改。

### 3.1 连接配置

契约细节。

## 8. 实现映射

### 8.1 契约 → Apple 实现（现有）[独占:apple]

Apple 实现细节：SwiftUI / Keychain。

### 8.5 契约 → 非 Apple 实现（待建）[独占:nonapple]

非 Apple 实现细节：待补。

## 9. 已知边界（分平台）

边界表格。

## 10. 变更记录 [开放]

台账行。
"""
    d = tempfile.mkdtemp()
    os.chdir(d)
    subprocess.run(["git", "init", "-q"], check=True)
    subprocess.run(["git", "config", "user.email", "t@t"], check=True)
    subprocess.run(["git", "config", "user.name", "t"], check=True)
    path = "概要设计.md"    # 三书文件名 → 契约层锁定生效（非三书不锁契约层）
    other = "开发记录.md"   # 记录类文件 → 只受独占节规则约束（本侧可写面）
    for fname, body in ((path, doc), (other, "# 开发记录\n\n## 1. 协议\n\n记录正文。\n")):
        with open(fname, "w", encoding="utf-8") as fh:
            fh.write(body)
    subprocess.run(["git", "add", path, other], check=True)
    subprocess.run(["git", "commit", "-qm", "init"], check=True)

    def run(edit_old, edit_new, label, mine="nonapple", fname=None):
        fname = fname or path
        text = open(fname, encoding="utf-8").read().replace(edit_old, edit_new, 1)
        with open(fname, "w", encoding="utf-8") as fh:
            fh.write(text)
        diff = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--unified=0", "HEAD", "--", fname],
                              capture_output=True, text=True).stdout
        # 顺序要紧：门禁必须读**改后**的工作区（真实用法就是这样）；先还原再判等于拿旧内容判新 diff
        # —— 对侧 L-42 实测：还原在前时「末尾新开节」那类用例会被算成 `line0 >= len(lines)` 而静默跳过，
        #    自测照样全绿（假绿）。本仓第 20 轮一起改正。
        rc = check([fname], mine, ["apple" if side(mine) == "nonapple" else "nonapple"], "HEAD", diff,
                   quiet=True, contract_owner="apple")
        subprocess.run(["git", "checkout", "-q", "--", fname], check=True)
        ok = (rc == 1) if "应该报红" in label else (rc == 0)
        print("  自测[%s] %s → %s" % (label, edit_old[:22].strip() or "…", "✅" if ok else "❌ 不符预期"))
        return ok

    r = []
    r.append(run("非 Apple 实现细节：待补。", "非 Apple 实现细节：小河马补的。", "本侧改本侧独占节 · 应该通过"))
    r.append(run("非 Apple 实现细节：待补。", "非 Apple 实现细节：Apple 侧越过界了。",
                 "对侧改对侧标记之外的独占节 · 应该报红", mine="apple"))
    r.append(run("Apple 实现细节：SwiftUI / Keychain。", "Apple 实现细节：SwiftUI / Keychain / AppKit。",
                 "Apple 侧改 apple 独占节 · 应该通过", mine="apple"))
    r.append(run("Apple 实现细节：SwiftUI / Keychain。", "Apple 实现细节：被本侧改了。",
                 "本侧改 apple 独占节 · 应该报红"))
    r.append(run("契约正文，只有契约所有者能改。", "契约正文（第二版）。",
                 "契约所有者改契约节 · 应该通过", mine="apple"))
    r.append(run("契约正文，只有契约所有者能改。", "契约正文：本侧直接改了。",
                 "非所有者改契约节 · 应该报红"))
    r.append(run("契约正文，只有契约所有者能改。", "契约正文：带着痕迹改。 contract-change：跨端要先改契约",
                 "非所有者改契约节带痕迹 · 应该通过"))
    r.append(run("非 Apple 实现细节：待补。", "非 Apple 实现细节：走一次豁免。 exclusive-allow：跨端联调",
                 "独占节带豁免 · 应该通过", mine="apple"))
    r.append(run("台账行。", "台账行：本侧加了一行。", "改 [开放] 台账节 · 应该通过"))
    r.append(run("非 Apple 实现细节：待补。", "非 Apple 实现细节：钩子用 windows 词表调用。",
                 "词表别名 windows ≡ nonapple · 应该通过", mine="windows"))
    r.append(run("记录正文。", "记录正文：本侧在记录类文件里加一行。",
                 "记录类文件（非三书）不锁契约层 · 应该通过", fname=other))
    r.append(run("台账行。", "台账行。\n\n## 11. 小节 [开放]\n\n非所有者开的开放节。",
                 "非所有者新开 [开放] 节（判据 ④）· 应该报红"))
    r.append(run("台账行。", "台账行。\n\n## 11. 非 Apple 侧新节 [独占:nonapple]\n\n本侧正文。",
                 "非所有者用自己标记新开节 · 应该通过"))
    r.append(run("台账行。", "台账行。\n\n## 11. 新契约节\n\n契约正文。",
                 "契约所有者新开无标记节 · 应该通过", mine="apple"))
    r.append(run("## 9. 已知边界（分平台）", "## 9. 已知边界（分平台）[开放]",
                 "非所有者给已有标题追加 [开放]（自我解锁）· 应该报红"))

    # ── 未跟踪增量（提案 0003 裁决）3 例：候选集含未跟踪新增文档 ──────────────────
    import contextlib
    import io as _io

    def run_untracked(body, label, expect_red=True, expect_text=None, fname="Docs/未跟踪草案.md"):
        p = os.path.join(d, fname)
        if os.path.dirname(p):
            os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(body)
        before = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout
        cand, diff_text, unt = assemble_candidates("HEAD", [])
        buf = _io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = check(cand, "nonapple", ["apple"], "HEAD", diff_text, quiet=True,
                       contract_owner="apple", untracked=unt)
        out = buf.getvalue()
        after = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout
        os.remove(p)
        ok = ((rc == 1) == expect_red
              and "未跟踪的新增文档" in out
              and (expect_text in out if expect_text else True)
              and before == after and "??" in after)
        print("  自测[%s] %s → %s" % (label, fname, "✅" if ok else "❌ 不符预期（rc=%d）" % rc))
        return ok

    r.append(run_untracked(
        "# 越界草案\n\n## 1. 摘要\n\n正文。\n\n## 2. 对侧细节 [独占:apple]\n\n本侧不该写这一节。\n",
        "未跟踪文档内含对侧独占节 · 应该报红", expect_red=True, expect_text="落在对侧独占节内"))
    r.append(run_untracked(
        "# 本侧草案\n\n## 1. 本侧实现 [独占:nonapple]\n\n本侧正文。\n",
        "未跟踪文档只写本侧独占节 · 应该通过", expect_red=False, expect_text="越界检查通过"))
    r.append(run_untracked(
        "# 概要设计-草案\n\n## 1. 新节\n\n契约正文。\n",
        "未跟踪的同名三书里新开无标记节（判据 ④）· 应该报红",
        expect_red=True, expect_text="新增节未带独占标记", fname="概要设计-草案.md"))

    print("自测汇总：%s（%d/%d）" % ("全部通过" if all(r) else "有失败", sum(r), len(r)))
    return 0 if all(r) else 1


def main():
    ap = argparse.ArgumentParser(description="越界检查：改动不得落在对侧独占节 / 契约层里")
    ap.add_argument("--mine", default=None, help="本侧独占标记（默认按平台推断：darwin → apple，其它 → nonapple）")
    ap.add_argument("--theirs", default=None, help="对侧标记，逗号分隔（仅用于报错提示）")
    ap.add_argument("--base", default=None, help="对照的基线 ref（默认 origin/master，退 HEAD~1 / HEAD；拿不到退出 2）")
    ap.add_argument("--files", nargs="*", default=None, help="只检查这些文件")
    ap.add_argument("--diff-file", default=None, help="从文件读 diff（CI / 自测）")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--contract-owner", default="apple",
                    help="契约层（无独占标记）的归属侧，默认 apple（大河马）；词表别名可写 macos")
    ap.add_argument("--contract-docs", nargs="*", default=None,
                    help="契约层锁定的文档名片段（默认三书：概要设计 / 需求规范书 / 产品能力规划说明书）")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    mine = args.mine or ("apple" if sys.platform == "darwin" else "nonapple")
    theirs = [x for x in (args.theirs.split(",") if args.theirs else []) if x] or \
             [t for t in ("apple", "nonapple", "linux") if t != side(mine)]
    contract_docs = tuple(DEFAULT_DOCS) + tuple(args.contract_docs or ())

    if args.diff_file:
        with open(args.diff_file, encoding="utf-8") as fh:
            diff_text = fh.read()
        return check(args.files or [], mine, theirs, args.base, diff_text, args.quiet,
                     contract_owner=args.contract_owner, contract_docs=contract_docs)

    base = args.base
    if base is None:
        for cand in ("origin/master", "HEAD~1", "HEAD"):
            r = subprocess.run(["git", "rev-parse", "--verify", "-q", cand],
                               capture_output=True, text=True)
            if r.returncode == 0:
                base = cand
                break
    if base is None:
        # 空跑缺陷的正面修法：**没有基线就报错退出**，不许静默放行（旧版在这里 return 0 = 假绿）
        print("❌ 越界检查无法执行：拿不到基线（非 git 仓库？），且未指定 --base")
        print("   处理：显式给基线，例如 --base origin/master；门禁不以「没基线」为由判通过")
        return 2
    # --base 显式给了但解析不到（拼错 / 没 fetch）同样不许静默放行：collect_files 会返回空候选集，
    # 日志读起来像「本次没改动」—— 与「拿不到基线」是同一族空跑缺陷（第 33 轮补齐；在此以前
    # collect_files 的注释「main 现在保证 base 一定解析得到」是句与实现不符的话）。
    rv = subprocess.run(["git", "rev-parse", "--verify", "-q", base], capture_output=True, text=True)
    if rv.returncode != 0:
        print("❌ 越界检查无法执行：基线 %s 解析不到（拼错？远端没 fetch？）" % base)
        print("   处理：先 git fetch origin；或不传 --base 让脚本按 origin/master → HEAD~1 → HEAD 自动推断。"
              "门禁不以「基线解析不到」为由判通过")
        return 2
    if not args.quiet:
        print("基线：%s（本侧=%s，契约层属 %s）" % (base, mine, args.contract_owner))
    files = collect_files(args, base)
    files, diff_text, untracked = assemble_candidates(base, files)
    if not files:
        if not args.quiet:
            # 第 24 / 31 轮口径：**「查了个空」不许读成「查过且合法」** —— 未跟踪增量并入后这条不再是
            # 盲点信号（候选集已含未跟踪新增），但措辞保留，免得日志里出现无法追责的 ✅。
            print("   ⚠️  越界检查：基线 %s 起没有受检的 .md 改动（已把未跟踪的新增文档并入候选）"
                  "—— 本次无内容可查，**不是「已通过」**" % base)
        return 0
    if diff_text is None:
        print("❌ 越界检查无法执行：git diff %s 失败（已跟踪改动渲染不出）" % base)
        return 2
    return check(files, mine, theirs, base, diff_text, args.quiet,
                 contract_owner=args.contract_owner, contract_docs=contract_docs, untracked=untracked)


if __name__ == "__main__":
    sys.exit(main())
