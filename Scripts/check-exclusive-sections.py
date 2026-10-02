#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""层级门禁：一次改动不得越界（三书分层形态 A + 契约层锁定，2026-09-27 拍板）。

**三仓同源副本**：`DoyahStudio/Scripts/` · `DoyahRetro/tools/` · `DoyahNotes/tools/logic-check/`
三份**逐字节同一份**（本文件 = 提案 `0003` 裁决后的「并集」版 + 2026-10-02 三仓统一词表版）。

**词表（三仓唯一一份，2026-10-02 人类主人拍板 · 派单 `T-20261002-038`）**
合法侧名只有**平台名**这六个：`macos` · `ios` · `windows` · `android` · `harmony` · `linux`。
- 标记形态：`[独占:<平台名>[|<平台名>…]]` —— **多值用半角竖线**（例 `[独占:windows|android|harmony]`），
  **成员必须都是平台名**。
- `[开放]` = 台账类节（**节**，不是侧）；**无标记 = 契约层**。
- **标记只表达平台，不表达人** —— 「谁负责哪个平台」写在文档的职责表里：Studio Windows 端从温迪
  小河马交接给黄鳍大肥鱼这类人事变动，**不需要改任何标记**。
- **退役词 `apple` / `nonapple`**：旧归一（`apple|macos|ios → apple`、`nonapple|windows|android|harmony
  → nonapple`）**已删除**，一律**判红并点名行号** —— 这是迁移护栏，半改状态不会静默放行。

**放行判据 = 集合语义**：`--mine <侧名>[|<侧名>…]` 与标记集合**相交**才放行（命令行多值建议写半角逗号：`--mine windows,android,harmony`
—— **`|` 在 shell 里是管道符**，命令行里不加引号会被拆成三段）。单值即「`--mine <侧名>`
∈ 标记集合」，多值标记**逐成员判定**（`[独占:windows|android|harmony]` 下 `--mine windows` ⇒ 绿、
`--mine macos` ⇒ 红）。`--mine` 也允许写多个平台（Windows 机上同时做安卓 / 鸿蒙的会话写
`--mine windows|android|harmony`）—— **侧名只说平台，不说人**。

**旧词判红的两条命中面（都点名 `文件:行号`）**：
  ① 本次**新增行**的正文里带着退役标记文本（**引用也算** —— 迁移没做完就不许再从别处抄旧词）；
  ② 本次**新增行**落在**标记仍是退役词的节**里（节标题的标记带旧词 ⇒ 该节任何新增都红）。
  旧词的 **`-` 侧（被搬走的那一行）只记提示不判红**：**迁移本身就是把旧词搬走**，判红会把迁移
  自己挡在门外；代价 = 迁移窗口内旧词节里的**纯删除**不会被判红（旧词归零即消失）。

三类节 —— 标题行（`#`~`######`）可带标记，标记对**该节及其所有子节**生效（外层优先于内层）：

  1. `[独占:<平台名>]`  —— 标记集合里含本侧的侧才能改（例：`### 2.3 契约 → Linux 实现 [独占:linux]`）
  2. `[开放]`    —— 台账类节（变更记录 / 索引）：**任何一侧**都能追加，含自己平台的行
  3. 无标记      —— **契约层**：**只有契约所有者**（`--contract-owner`，默认 `macos` = 大河马）能改；
                    其他侧要么走提案（`Docs/proposals/`），要么在改动行 / 上一行 / 提交信息注
                    `contract-change：理由` 留痕
  4. 新增节      —— **非契约所有者**不得在契约层锁定的文档里**新开一个节**（含新开 `[开放]` 台账节）：
                    **纯插入**的节标题必须带 `[独占:*]`（对侧 L-42 判据 / 提案 `0003`）。`[开放]` 的语义
                    是「台账节任何一侧都能追加」，**不是自己开新节的许可证** —— 新节点由契约所有者开；
                    逃生门同第 3 类

契约层锁定只对**三书**生效（文件名含 `概要设计` / `需求规范书` / `产品能力规划说明书`；
可用 `--contract-docs` 追加，例如把 `核心契约` 也纳入）；其他 .md（开发记录、任务清单、提案、
跨平台框架设计等）只受独占节规则约束 —— 记录类文件是本侧可写面，不该被契约层锁住。

逃生门（都会打印理由）：
  · **本次新增的行**自己带 `exclusive-allow：理由`（独占节 / 旧词节）/ `contract-change：理由`（契约层）
  · 同一次改动里成对新增的多行块：上一行**也是本次新增行**时，上一行的注记也算
  · 提交信息整批 `exclusive-allow: 理由` / `contract-change: 理由`（**纯删除**走这条）
  · 独占节正文注 `exclusive-allow-section`（整节豁免，用于「首建占位节」；**未随口径 A 收窄**）

**口径 A（2026-10-01 拍板 · 三仓同改）：新增行必须自带注记**
  豁免只认**本次新增行自己带的注记**：① 替换对里的 `-` 侧（老内容）不再提供豁免 —— 旧版两侧任一
  带注记即整体豁免，实测「把已提交在案那行的注记摘掉再跑」会报 **「受检改动 0 行」判绿**；
  ② 上一行豁免只在上一行**也是本次新增行**时成立（在案的上一行不再放行）。
  成对证据见 `--self-test` 的「口径 A」五例（① 新增行不带注记 ⇒ 红并点名行号 / ② 新增行自带注记 ⇒ 绿 /
  ③ 摘掉在案那行的注记 ⇒ 红 / ④ 只靠**在案**的上一行 ⇒ 红 / ⑤ 上一行与本次新增行**同批新增**且上一行
  带注记 ⇒ 绿）。

汇报：任一类违规（越界 / 契约层 / 新增节 / **旧词残留**）→ 退出 1 并点名 `文件:行号`；
**拿不到基线 → 退出 2**（含「`--base` 显式给了却解析不到」那一档，不以「没基线 / 基线解析不到」为由
静默放行 = 修掉越界门禁的空跑缺陷）；无候选文件 → 退出 0 但措辞是 **⚠️ 无内容可查 ≠ 已通过**；
全合法 → 退出 0（并打印受检行数与所用基线）。


未跟踪文档
----------
· **未跟踪的新增 `.md` 也纳入受检**（提案 `0003` 裁决）：候选集 = 已跟踪改动 ∪ 未跟踪新增。渲染用
  `git diff --no-index /dev/null <path>`，**不动索引**；命中时**显式播报**，不做静默多查。
  **代价（已知、接受）**：尚未 `git add` 的草稿也会被判 —— 口径是三仓一律纳入。

注意事项（血泪换来的三条，别踩）
--------------------------------
· **标记只从标题行读；标题里提到对侧 / 旧词的标记文本 = 声明「本节归该侧」** —— 正文里引用标记无妨，
  但把 `[独占:windows]` 写进标题（哪怕本意只是「引用」）会让整节被判归对侧；把**旧词**写进标题
  则整节判红（迁移护栏）。
· **「一节的归属 = 它自己的标题 / 最近祖先的标题」** —— 非所有者想「先给标题追加 `[开放]` 解锁、
  再写正文」是行不通的：**改标题行本身**就被判成契约层改动。这是**正确行为**，不是误报。
· **负例必须在「改后」的工作区上跑**：夹具若「先 `git checkout` 还原、再调用 `check()`」，测的是旧
  内容 —— 「末尾新增的节」会被算成 `line0 >= len(lines)` 而**静默跳过**，自测照样全绿。

已知局限
--------
· 打印「受检改动 0 行」不是假绿：文件确在候选里，只是**范围内没有可判的行**（无标记且不在三书里）。
· 判据 ④（新增节必须带 `[独占:*]`）只对**契约层锁定的文档**生效，且只看**纯插入**的标题行。
· 契约层锁定只认文件名（含 `概要设计` / `需求规范书` / `产品能力规划说明书`），改名会绕过。
· 未跟踪文件按「整份都是新增行」处理：`-` 侧为空 ⇒「新文件里删了旧文件的东西」这种情形看不见。
· 旧词节的 **`-` 侧不判红**（见上文「旧词判红的两条命中面」）。
· 「无候选文件」时打印的是**⚠️ 无内容可查 ≠ 已通过**（退出码仍是 0）—— 「查了个空」不许读成「查过且合法」。

用法（三仓通用；路径按仓替换：Studio `Scripts/` · Retro `tools/` · Notes `tools/logic-check/`）
--------------------------------------------------------------------------------------------
    python3 Scripts/check-exclusive-sections.py                          # 自动推断本侧，基线默认 origin/master
    python3 Scripts/check-exclusive-sections.py --mine macos --base origin/master   # 提交前默认姿势（显式基线最稳）
    python3 Scripts/check-exclusive-sections.py --mine windows,android,harmony      # 多平台侧（同一台 Windows 机做三端）
    python3 Scripts/check-exclusive-sections.py --contract-owner macos    # 契约层归属（默认 macos = 大河马）
    python3 Scripts/check-exclusive-sections.py --contract-docs 核心契约  # 追加契约层锁定的文档
    python3 Scripts/check-exclusive-sections.py --base HEAD~1 --files Docs/概要设计.md
    python3 Scripts/check-exclusive-sections.py --diff-file d.patch       # 用现成 diff（CI / 自测）
    python3 Scripts/check-exclusive-sections.py --self-test               # 自测 29 例（含判据 ④、未跟踪增量、口径 A 五例、集合语义与旧词护栏）

本侧推断：darwin → `macos,ios`（本机同时做 macOS / iOS 实现）；linux → `linux`；其它 → `windows,android,harmony`
（Windows 机同时做三端）。可用 `--mine` 覆盖，或设环境变量 `DOYAH_SIDE`（钩子按运行方推断侧别，
队列 **L-48** 第 0 步：**钩子把侧别写死会让运行方自己被当成对侧**，装钩子前先把侧别定下来）。
**侧名一律平台名** —— `--mine apple` / `--mine nonapple` 这类旧词**直接退出 2**（词表已统一，不再归一）。
基线推断顺序 origin/master → HEAD~1 → HEAD，实际采用哪一个会打印出来（拿不到就退出 2，绝不当成「没问题」）。
"""
import argparse
import os
import re
import subprocess
import sys

MARKER_RE = re.compile(r"\[独占:([A-Za-z0-9_\-|]+)\]")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
ALLOW = "exclusive-allow"          # 独占节的显式豁免
CONTRACT_TAG = "contract-change"    # 契约层的显式痕迹（等价豁免，但语义是「该动契约」）
ALLOW_SECTION = "exclusive-allow-section"   # 独占节正文里的整节豁免（用于「首建占位节」等）
OPEN_MARK = "[开放]"               # 开放节：任何一侧都可改（变更记录 / 索引这类台账节）
DEFAULT_DOCS = ("概要设计", "需求规范书", "产品能力规划说明书")   # 契约锁定范围：三书（可用 --contract-docs 追加）
# 侧名 = **平台名**（三仓统一词表，2026-10-02 人类主人拍板 · 派单 T-20261002-038）：只有这六个合法。
PLATFORMS = ("macos", "ios", "windows", "android", "harmony", "linux")
# 退役词（旧词表）：归一已删除 —— 旧词一律判红并点名行号（迁移护栏；存量清单见派单 T-20261002-038）。
RETIRED = ("apple", "nonapple")


def mark_tokens(tok):
    """把标记值（或 `--mine` 取值）拆成平台名列表；多值用半角竖线（标记）/ 半角逗号或竖线（命令行）。"""
    if tok is None:
        return []
    return [t.strip().lower() for t in re.split(r"[|,]", tok) if t.strip()]


def bad_tokens(tok):
    """标记值里的退役词 / 词表外名字（旧词残留）—— 非空即判红并点名行号。"""
    return [t for t in mark_tokens(tok) if t not in PLATFORMS]


def allowed(tok, mine):
    """集合语义：`--mine`（可多值）与标记集合**相交**才放行；标记里有退役词 ⇒ 不放行（走旧词判红）。"""
    if bad_tokens(tok):
        return False
    return bool(set(mark_tokens(tok)) & set(mark_tokens(mine)))


def same_side(a, b):
    """两侧是否算同一侧（集合相交）—— 契约所有者判定用。"""
    return bool(set(mark_tokens(a)) & set(mark_tokens(b)))


def infer_side():
    """按运行方推断本侧侧名（平台名，可多值）。`DOYAH_SIDE` / `--mine` 可覆盖 —— 队列 L-48 第 0 步：
    钩子按运行方推断侧别，别把侧别写死（写死会把运行方自己当成对侧）。"""
    if sys.platform == "darwin":
        return "macos|ios"          # 本机同时做 macOS / iOS 实现（旧词表的 `apple` = 这两端）
    if sys.platform.startswith("linux"):
        return "linux"
    return "windows|android|harmony"   # Windows 机同时做三端（旧词表的 `nonapple` = 这三端）


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
    violations, legacy, legacy_soft, checked, contracts = [], [], [], 0, []
    newsecs = []          # 判据 ④：非契约所有者新开、又没带 [独占:*] 的节标题（含新开 [开放]）
    # 口径 A（2026-10-01 拍板 · 三仓同改）：豁免只认「本次新增行自己带的注记」。先把本次 diff 的
    # **新增行号集**按文件收好（`+` 侧的 new 行号），供「上一行也算自己带的」那条判定用。
    added_idx = {_p: {nl for kd, _o, nl, _c in _hs if kd == "+"} for _p, _hs in parsed.items()}
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
        added_here = added_idx.get(path, set())
        for items, _pair_allow in group_pairs(hunks):
            # 口径 A：豁免只认**本次新增行自己带的注记** —— 替换对由 `+` 侧代表（`-` 侧是在案老内容，
            # 它的注记不再为本次改动放行：旧版「任一侧带注记即整对豁免」，实测会让「把在案那行的注记
            # 摘掉再跑」报 **「受检改动 0 行」判绿**）。老注记不豁免，但 `-` 侧**照判** —— 老内容所在
            # 的层级正是「这处改动是否越界」的判据（成对证据见 `--self-test`「口径 A③」）。
            if any(kd == "+" and has_tag(c) for kd, _o, _n, c in items):
                continue
            for kind, old_l, new_l, content in items:
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
                # 口径 A：上一行的注记只在「上一行也是本次新增行」时算数 —— 已提交在案的上一行
                # 不再为下面那一行放行（旧版实测松紧；成对证据见 --self-test「口径 A④」）。
                if kind == "+" and (line0 - 1) in added_here and has_tag(prev):
                    continue
                # ④ 新增节必须带 [独占:*]（对侧 L-42 判据，本仓第 20 轮移植）：非契约所有者不得在
                #    契约层锁定的文档里新开一个「谁都能写」的节。只看**纯插入**的标题行（len(items)==1），
                #    `-`/`+` 成对的标题改动走下面的普通判定（改标题行本身已属契约层改动）；
                #    新开 `[开放]` 台账节同样判红 —— 「先解锁再改」就是靠这个绕开锁定的。
                if (kind == "+" and len(items) == 1 and not same_side(mine, contract_owner)
                        and any(d in os.path.basename(path) for d in contract_docs)
                        and HEADING_RE.match(content) and not MARKER_RE.search(content)):
                    newsecs.append((path, line1, content.strip()[:80]))
                    continue
                # 旧词残留（命中面 ①）：**本次新增行**正文里带着退役标记文本（引用也算）⇒ 判红点名。
                if kind == "+":
                    for _mk in MARKER_RE.finditer(content):
                        if bad_tokens(_mk.group(1)):
                            legacy.append((path, line1, _mk.group(1), bad_tokens(_mk.group(1)),
                                           content.strip()[:80]))
                tok, title, _rng = section_of(secs, line0)
                if tok is not None:
                    if any(tok == st and s <= line0 <= e for st, s, e in sect_allow):
                        continue
                    checked += 1
                    _bad = bad_tokens(tok)
                    if _bad:
                        # 命中面 ②：新增行落在标记仍是退役词的节里 ⇒ 红（迁移没做完）。
                        # `-` 侧只记提示：迁移本身就是把旧词搬走，判红会把迁移挡在门外。
                        (legacy if kind == "+" else legacy_soft).append(
                            (path, line1, tok, _bad, content.strip()[:80]))
                    elif not allowed(tok, mine):
                        violations.append((path, line1, tok, title, content.strip()[:80]))
                    continue
                # 无独占标记 → 契约层（锁定给 contract_owner）或 [开放] 节
                if not any(d in os.path.basename(path) for d in contract_docs):
                    continue          # 非三书：不锁契约层（只保护独占节）
                k, _ = kind_of(lines, line0)
                if k != "contract":
                    continue          # [开放] / 无标题：放行
                checked += 1
                if not same_side(mine, contract_owner):
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
    legacy = _dedupe(legacy, 2)
    legacy_soft = _dedupe(legacy_soft, 2)
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
    if legacy:
        print("❌ 旧词残留（词表已统一为平台名，`apple` / `nonapple` 退役）：%d 处（本侧=%s）"
              % (len(legacy), mine))
        for _p, _ln, _tok, _bd, _snip in legacy:
            print("   %s:%d 标记 `[独占:%s]` 含退役词 %s：%s" % (_p, _ln, _tok, "/".join(_bd), _snip))
        print("   处理：① 按三仓词表换成平台名（例 `[独占:windows|android|harmony]`）；"
              "② 存量迁移清单与「旧词处数 → 0」的读数见派单 `T-20261002-038` 的 `## 结果`；"
              "③ 确有必要时在该行注 `%s：理由`（或提交信息 `%s: 理由`）。" % (ALLOW, ALLOW))
    if legacy_soft:
        print("ℹ️  旧词节的 `-` 侧 %d 处只记提示（迁移正是在把旧词搬走，不判红）" % len(legacy_soft))
    if newsecs or violations or contracts or legacy:
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
    import contextlib
    import io
    import tempfile
    import contextlib as _cl
    import io as _io2
    doc = """# 概要设计（样例）

| 阅读约定 | `[独占:macos\|ios]` / `[独占:windows\|android\|harmony]` = 各侧实现细节；无标记 = 契约层 |

## 3. 平台适配层契约

契约正文，只有契约所有者能改。

### 3.1 连接配置

契约细节。

## 8. 实现映射

### 8.1 契约 → macOS / iOS 实现（现有）[独占:macos|ios]

macOS / iOS 实现细节：SwiftUI / Keychain。

### 8.5 契约 → 非 macOS / iOS 端实现（待建）[独占:windows|android|harmony]

非 macOS / iOS 实现细节：待补。

## 9. 已知边界（分平台）

边界表格。

## 10. 变更记录 [开放]

台账行。
"""
    self_path = os.path.abspath(__file__)   # 在 chdir 之前取：main 级用例用绝对路径反问自己
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

    def run(edit_old, edit_new, label, mine="windows", fname=None, expect_text=None):
        fname = fname or path
        text = open(fname, encoding="utf-8").read().replace(edit_old, edit_new, 1)
        with open(fname, "w", encoding="utf-8") as fh:
            fh.write(text)
        diff = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--unified=0", "HEAD", "--", fname],
                              capture_output=True, text=True).stdout
        # 顺序要紧：门禁必须读**改后**的工作区（真实用法就是这样）；先还原再判等于拿旧内容判新 diff
        # —— 对侧 L-42 实测：还原在前时「末尾新开节」那类用例会被算成 `line0 >= len(lines)` 而静默跳过，
        #    自测照样全绿（假绿）。本仓第 20 轮一起改正。
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = check([fname], mine, ["macos", "ios"], "HEAD", diff, quiet=True, contract_owner="macos")
        out = buf.getvalue()
        subprocess.run(["git", "checkout", "-q", "--", fname], check=True)
        ok = ((rc == 1) == ("应该报红" in label)) and (expect_text in out if expect_text else True)
        print("  自测[%s] %s → %s" % (label, edit_old[:22].strip() or "…", "✅" if ok else "❌ 不符预期"))
        return ok

    r = []
    r.append(run("非 macOS / iOS 实现细节：待补。", "非 macOS / iOS 实现细节：小河马补的。", "本侧改本侧独占节 · 应该通过"))
    r.append(run("非 macOS / iOS 实现细节：待补。", "非 macOS / iOS 实现细节：Apple 侧越过界了。",
                 "对侧改对侧标记之外的独占节 · 应该报红", mine="macos"))
    r.append(run("macOS / iOS 实现细节：SwiftUI / Keychain。", "macOS / iOS 实现细节：SwiftUI / Keychain / AppKit。",
                 "macOS / iOS 侧改本侧独占节 · 应该通过", mine="macos"))
    r.append(run("macOS / iOS 实现细节：SwiftUI / Keychain。", "macOS / iOS 实现细节：被本侧改了。",
                 "windows 侧改 `macos|ios` 独占节 · 应该报红"))
    r.append(run("契约正文，只有契约所有者能改。", "契约正文（第二版）。",
                 "契约所有者改契约节 · 应该通过", mine="macos"))
    r.append(run("契约正文，只有契约所有者能改。", "契约正文：本侧直接改了。",
                 "非所有者改契约节 · 应该报红"))
    r.append(run("契约正文，只有契约所有者能改。", "契约正文：带着痕迹改。 contract-change：跨端要先改契约",
                 "非所有者改契约节带痕迹 · 应该通过"))
    r.append(run("非 macOS / iOS 实现细节：待补。", "非 macOS / iOS 实现细节：走一次豁免。 exclusive-allow：跨端联调",
                 "独占节带豁免 · 应该通过", mine="macos"))
    r.append(run("台账行。", "台账行：本侧加了一行。", "改 [开放] 台账节 · 应该通过"))
    r.append(run("非 macOS / iOS 实现细节：待补。", "非 macOS / iOS 实现细节：多值标记下 windows 侧调用。",
                 "集合语义：多值标记 `[独占:windows|android|harmony]` 下 --mine windows · 应该通过", mine="windows"))
    r.append(run("非 macOS / iOS 实现细节：待补。", "非 macOS / iOS 实现细节：macOS 侧写进了三端节。",
                 "集合语义：同一多值标记下 --mine macos · 应该报红", mine="macos"))
    r.append(run("记录正文。", "记录正文：本侧在记录类文件里加一行。",
                 "记录类文件（非三书）不锁契约层 · 应该通过", fname=other))
    r.append(run("台账行。", "台账行。\n\n## 11. 小节 [开放]\n\n非所有者开的开放节。",
                 "非所有者新开 [开放] 节（判据 ④）· 应该报红"))
    r.append(run("台账行。", "台账行。\n\n## 11. 本侧新节 [独占:windows|android|harmony]\n\n本侧正文。",
                 "非所有者用自己平台的标记新开节 · 应该通过"))
    r.append(run("台账行。", "台账行。\n\n## 11. 新契约节\n\n契约正文。",
                 "契约所有者新开无标记节 · 应该通过", mine="macos"))
    r.append(run("## 9. 已知边界（分平台）", "## 9. 已知边界（分平台）[开放]",
                 "非所有者给已有标题追加 [开放]（自我解锁）· 应该报红"))

    # ── 口径 A（2026-10-01 拍板 · 三仓同改）5 例：豁免只认「本次新增行自己带的注记」 ──────────
    import contextlib as _cl
    import io as _io2

    def run_a(pre, edit_old, edit_new, label, expect_red=True, expect_text=None, mine="windows"):
        """先按 `pre` 造出「已在案」的基线（提交掉），再施加本次改动并判定（口径 A 成对证据）。"""
        base_sha = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        if pre is not None:
            text = open(path, encoding="utf-8").read().replace(pre[0], pre[1], 1)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            subprocess.run(["git", "commit", "-qam", "pre"], check=True)
        text = open(path, encoding="utf-8").read().replace(edit_old, edit_new, 1)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        diff = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--unified=0", "HEAD", "--", path],
                              capture_output=True, text=True).stdout
        buf = _io2.StringIO()
        with _cl.redirect_stdout(buf):
            rc = check([path], mine, ["macos"], "HEAD", diff, quiet=True, contract_owner="macos")
        out = buf.getvalue()
        subprocess.run(["git", "reset", "-q", "--hard", base_sha], check=True)
        ok = ((rc == 1) == expect_red) and (expect_text in out if expect_text else True)
        print("  自测[%s] → %s" % (label, "✅" if ok else "❌ 不符预期（rc=%d）" % rc))
        return ok

    CL = "契约正文，只有契约所有者能改。"
    CL_TAGGED = CL + " contract-change：跨端要先改契约"      # 「已在案」的带注记行

    r.append(run_a(None, CL, CL + "\n契约正文续：本侧加的一行。",
                   "口径 A① 本次新增行不带注记 · 应该报红并点名行号", expect_text="概要设计.md:"))
    r.append(run_a(None, CL, CL + "\n契约正文续：带痕迹的一行。 contract-change：跨端要先改契约",
                   "口径 A② 本次新增行自带注记 · 应该通过", expect_red=False))
    r.append(run_a((CL, CL_TAGGED), CL_TAGGED, CL,
                   "口径 A③ 摘掉在案那行的注记（旧版报「受检改动 0 行」判绿）· 应该报红"))
    r.append(run_a((CL, CL_TAGGED), CL_TAGGED, CL_TAGGED + "\n契约正文续：本侧加的一行。",
                   "口径 A④ 只靠在案的上一行（注记不在本次新增行上）· 应该报红"))
    r.append(run_a(None, CL, CL + "\n契约正文续：带痕迹。 contract-change：跨端要先改契约\n契约正文续：正文。",
                   "口径 A⑤ 上一行与新增行同批新增且带注记 · 应该通过", expect_red=False))

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
            rc = check(cand, "windows", ["macos"], "HEAD", diff_text, quiet=True,
                       contract_owner="macos", untracked=unt)
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
        "# 越界草案\n\n## 1. 摘要\n\n正文。\n\n## 2. 对侧细节 [独占:macos]\n\n本侧不该写这一节。\n",
        "未跟踪文档内含对侧独占节 · 应该报红", expect_red=True, expect_text="落在对侧独占节内"))
    r.append(run_untracked(
        "# 本侧草案\n\n## 1. 本侧实现 [独占:windows|android|harmony]\n\n本侧正文。\n",
        "未跟踪文档只写本侧独占节 · 应该通过", expect_red=False, expect_text="越界检查通过"))
    r.append(run_untracked(
        "# 概要设计-草案\n\n## 1. 新节\n\n契约正文。\n",
        "未跟踪的同名三书里新开无标记节（判据 ④）· 应该报红",
        expect_red=True, expect_text="新增节未带独占标记", fname="概要设计-草案.md"))

    # ── 旧词护栏（2026-10-02 · 派单 T-20261002-038）：旧词一律判红并点名行号；迁移不被挡在门外 ──
    LEG_SEC = "## 12. 旧词节 [独占:nonapple]"           # 迁移前的样子（夹具里现造）
    NEW_SEC = "## 12. 旧词节 [独占:windows|android|harmony]"
    pre_leg = ("台账行。", "台账行。\n\n" + LEG_SEC + "\n\n旧词节正文。")
    r.append(run_a(pre_leg, "旧词节正文。", "旧词节正文。\n本侧加的一行。",
                   "旧词①：新增行落在旧词节里 · 应该报红并点名行号", expect_text="旧词残留"))
    r.append(run_a(None, "台账行。", "台账行：引用旧词的 [独占:apple] 一行。",
                   "旧词②：新增行正文里带着旧词（引用也算）· 应该报红并点名行号", expect_text="旧词残留"))
    r.append(run_a(pre_leg, LEG_SEC, NEW_SEC,
                   "旧词③：把旧词标题换成平台名（迁移本身）· 应该通过", expect_red=False,
                   expect_text="越界检查通过"))

    # ── 旧词入参 / 空跑防护（main 级）2 例 ──────────────────────────────────────────
    def run_main(argv, label, expect_rc, expect_text=None):
        p = subprocess.run([sys.executable, self_path] + argv, cwd=d, capture_output=True, text=True)
        out = p.stdout + p.stderr
        ok = (p.returncode == expect_rc) and (expect_text in out if expect_text else True)
        print("  自测[%s] → %s" % (label, "✅" if ok else "❌ 不符预期（rc=%d）" % p.returncode))
        return ok

    r.append(run_main(["--mine", "nonapple"],
                      "旧词入参 `--mine nonapple` ⇒ 退出 2（词表已统一，不再有别名归一）", 2, "退役"))
    r.append(run_main(["--mine", "windows", "--base", "no-such-ref"],
                      "空跑防护：`--base` 解析不到 ⇒ 退出 2（门禁不以「没基线」为由判通过）", 2, "基线"))

    print("自测汇总：%s（%d/%d）" % ("全部通过" if all(r) else "有失败", sum(r), len(r)))
    return 0 if all(r) else 1


def main():
    ap = argparse.ArgumentParser(description="越界检查：改动不得落在对侧独占节 / 契约层里")
    ap.add_argument("--mine", default=None,
                    help="本侧侧名 = 平台名，可多值（半角竖线分隔，例 `windows|android|harmony`）；默认按运行方"
                         "推断（darwin → macos|ios，linux → linux，其它 → windows|android|harmony），"
                         "也可用环境变量 DOYAH_SIDE")
    ap.add_argument("--theirs", default=None, help="对侧标记，逗号分隔（仅用于报错提示）")
    ap.add_argument("--base", default=None, help="对照的基线 ref（默认 origin/master，退 HEAD~1 / HEAD；拿不到退出 2）")
    ap.add_argument("--files", nargs="*", default=None, help="只检查这些文件")
    ap.add_argument("--diff-file", default=None, help="从文件读 diff（CI / 自测）")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--contract-owner", default="macos",
                    help="契约层（无独占标记）的归属侧 = 平台名，默认 macos（大河马，本机同时做 macOS / iOS）")
    ap.add_argument("--contract-docs", nargs="*", default=None,
                    help="契约层锁定的文档名片段（默认三书：概要设计 / 需求规范书 / 产品能力规划说明书）")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    mine = args.mine or os.environ.get("DOYAH_SIDE") or infer_side()
    # 词表已统一为平台名（2026-10-02）：旧词**不归一**，直接退出 2 —— 否则「侧名」与「标记」会两套词表并存。
    for _who, _val in (("--mine", mine), ("--contract-owner", args.contract_owner)):
        _bad = bad_tokens(_val)
        if _bad:
            print("❌ 侧名用了词表外的名字：%s=%s（退役词 %s）" % (_who, _val, "/".join(_bad)))
            print("   处理：侧名一律平台名（%s）；`apple` / `nonapple` 已于 2026-10-02 退役 —— 三仓统一词表"
                  "（Notes §2.2）+ 派单 `T-20261002-038` 的迁移清单" % " · ".join(PLATFORMS))
            return 2
    theirs = [x for x in (args.theirs.split(",") if args.theirs else []) if x] or \
             [t for t in PLATFORMS if not same_side(t, mine)]
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
