#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""路径归属判据：一次改动不得落在**对侧子树**上（三仓同源副本，2026-10-02 立）。

**三仓同源副本（逐字节同一份）**：`DoyahStudio/Scripts/` · `DoyahRetro/tools/` ·
`DoyahNotes/tools/logic-check/`。**清单各仓一份**（`path-ownership.json`，与脚本同目录，
清单可以不同，判据逻辑同文本）。

**「同一份」的作用面（2026-10-05 定标 · 派单 `T-20261005-038` ②）**：只指**判据脚本**
（本文件与 `check-exclusive-sections.py`）—— 三份逐字节同一份，改一处须三仓同改；
**清单 `path-ownership.json` 与提交钩子 `tools/hooks/pre-commit` 按仓定制**（各仓路径面 /
钩子覆盖面本就不同）⇒ 它们的差异**不是分叉**，但须在各仓清单 `reason` 或提交信息里登记。

**为什么要有它**：`check-exclusive-sections.py` 判的是「文档里的**节**」归谁（按标题上的独占
标记），而「盘上的**目录/文件**归谁」此前只有口头分工 —— 同一个 `git diff` 里改了别的端
（macOS / Windows / 安卓 / 鸿蒙）的顶层子树，**没有任何判据会报红**。本判据把「路径」这一层补齐：
越界在**落笔处**就被点名，而不是等对侧下次合并时才发现。

**四类路径**：

  1. `trees[].paths` —— 各端**实现子树**（顶层子树为主的路径前缀）。改动落在**别人的**树上
     ⇒ **判红并点名文件**。
  2. `shared` —— **共享面**（`Docs/` · `tools/` · `Scripts/` · `AGENT-SPEC.md` 这类两侧都写的地方）。
     改它**不算越界**，但要走**声明式台账**：清单 `shared_ledger` 里**改前**登记理由（glob 命中
     即算登记），或在**本次新增行**里注 `shared-surface：理由`（要**独占一行**，剥掉注释记号后
     以它开头；只在句子里引用不算），或提交信息里独占一行写 `shared-surface: 理由`。**三处都登记不到理由 ⇒ 判红**（「谁都能改」不等于「谁都可以不吭声
     地改」）。清单里 `shared_require_declaration: false` 可整体放宽（留给各仓自己定）。
  3. `unclassified_allow` —— 仓根杂项（README / LICENSE / `.gitignore` / 工具目录…），**逐条登记理由**。
  4. 其余路径 ⇒ **未登记**，判红并要求登记进清单 —— 路径归属不允许「没人认领」。

**「安卓与鸿蒙怎么分」的那一层**（`DoyahNotes` 的答案，写进它的清单注释）：`android/`（Gradle +
Kotlin）、`entry/` + `AppScope/` + `hvigor/` + `hvigorfile.ts` + `oh-package.json5` +
`build-profile.json5` + `code-linter.json5`（hvigor + ArkTS）、`platform/windows/`（Tauri 2 + Rust）
**在契约层上同属 `[独占:nonapple]`** —— 契约层**不分家**，靠「**顶层子树 + 构建系统**」在盘上分，
一致性靠**同口径的两份实现 + 黄金样例对拍**（`tools/fixtures/*-golden-v1.json`、
`backup-cross-corpus-{android,harmony}.json`、`arkts-harness.mjs`）。
所以本判据按 **`--mine <端>`** 判（`--mine android` / `--mine windows` / `--mine macos`：**子树分家**，
动别人的树即红）；也收 **`--mine nonapple`** 这种**契约侧**写法（**宽松档**：同一 `contract_side`
的几棵树互相都算本侧 —— 判的是**跨契约侧**，不是跨子树）。档位会在输出里写明。

**判据（机械可复算）**：

  · 取 `git diff --name-only <对照点>`，**对照点 = `git merge-base <base> HEAD`**
    （`<base>..HEAD` 是它的子集，还多算了工作区未提交的改动）。为什么不用裸的 `<base>`：
    本地**落后**远端时，`git diff origin/master` 会把**对侧刚推上来的提交**算成「本地改动」⇒
    整批误判成越界。用 merge-base 就没有这个假红（本地落后时它等于 HEAD，只查自己那点改动）。
    `--files` 显式指定时以指定集为准；`--diff-file` 用现成 diff。
  · 分类顺序：`shared` → `trees` → `unclassified_allow` → 未登记；**前缀命中即算命中**，锚在**仓根**上。
  · 任一类判红 ⇒ 退出 1，逐条点名 `路径 ⇒ 原因`（含它属于哪一端的子树）。
  · **清单自校验每次都做**：声明的每条路径**必须真的在盘上**、两棵树的路径不得互相覆盖、子树不得
    与共享面互相覆盖、`shared` 不得为空。清单与盘上不一致 ⇒ 退出 2（**清单过期 = 判据过期**，
    不许静默通过）。

**退出码**（照 §8.3.2 协议）：0 = 全绿；1 = 判红；2 = 跳过 / 拿不到基线 / 清单坏了。
「无候选文件」打印的是 **⚠️ 无内容可查 ≠ 已通过**（退出码仍是 0）。

**先例**：`check-exclusive-sections.py`（三仓同一份、按运行方推断本侧、`--self-test`、退出码协议）
与 `AGENT-SPEC.md` §9 第 47 条（栈改档后「正向 + 反向」两遍扫的规矩）。

**用法**（三仓通用；路径按仓替换：Studio `Scripts/` · Retro `tools/` · Notes `tools/logic-check/`）：

    python3 Scripts/check-path-ownership.py --mine macos                    # 本侧提交前默认姿势
    python3 Scripts/check-path-ownership.py --mine windows --base origin/master
    python3 Scripts/check-path-ownership.py --mine nonapple                 # Notes 写法（契约侧宽松档）
    python3 Scripts/check-path-ownership.py --manifest /tmp/fixture.json    # 换清单（自测 / 夹具）
    python3 Scripts/check-path-ownership.py --files Docs/概要设计.md         # 显式指定改动集
    python3 Scripts/check-path-ownership.py --self-test                     # 自测 34 例

**本侧推断**：清单里某棵树的 `hosts` 命中 `uname` 时才敢默认；推断不出就要求 `--mine`（退出 2，
**不猜**）。

**已知局限（如实登记，不假装判住）**：

  · 只判**路径**，不判内容（改本侧子树里的对侧逻辑，本判据看不见 —— 那是 `check-exclusive-sections.py`
    与各侧单测的事）。
  · **未跟踪文件不在** `git diff --name-only` 里（未跟踪的 `.md` 由 `check-exclusive-sections.py`
    单独收口）；本判据不看未跟踪增量。
  · 重命名在 `--name-only` 下表现为两条路径（一条旧、一条新）；本判据不做重命名识别。
  · `shared_ledger` 的粒度是**路径 glob**，只判「登记过没有」，**不判理由是否成立**（那是人的事）。
  · 清单里的 `label` / `at` 只用于打印与留痕，判据不读它们的语义。
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

EXIT_PASS, EXIT_RED, EXIT_SKIP = 0, 1, 2
TAG = "shared-surface"
DECL_RE = re.compile(r"^%s\s*[:：]\s*(\S.*?)\s*$" % TAG)
MARK_RE = re.compile(r"^\s*(?:#+|//+|/\*+|\*+|<!--|-->|;+|-|\*)?\s*")
TAIL_RE = re.compile(r"\s*(?:-->|\*/)\s*$")


def declaration_reason(text: str):
    """一行是不是**声明行**：剥掉注释记号后**以 `shared-surface：理由` 开头**才算。

    ⚠️ 只在句子里**引用**这个写法（解释判据自己的注释 / docstring）**不算**声明 —— 否则
    「写一句解释」就能给自己放行。实测踩过：门禁接进 `verify-all.sh` 时在注释里引了一次这个
    写法，整批改动就被当成本次新增行的注记放行了（判据自己的注记必须**独占一行**）。
    """
    t = TAIL_RE.sub("", MARK_RE.sub("", text.strip())).strip()
    m = DECL_RE.match(t)
    return m.group(1).strip() if m else None


# ── 演员名（四规范名）与契约所有者（2026-10-03 人类主人制度变更 · 派单 `T-20261003-003`）─────────
# 契约定：三书**契约层**归 `bluewhale`（蓝色鲸鱼娘）；**平台实现层**归各平台助理：
#   `bighippo` = macOS / iOS · `tinyhippo` = 安卓 / 鸿蒙 · `fatshark` = Windows。
# 与「标记只表达平台」不冲突：**路径清单**里各端子树仍按平台分（tree.id = macos / windows / android…），
# 演员名只出现在**命令行这一轴**（`--mine bighippo` ≡ `--mine macos,ios`；`bluewhale` 无平台集 ⇒ 契约模式）。
ACTOR_PLATFORMS = {"bluewhale": (), "bighippo": ("macos", "ios"),
                   "tinyhippo": ("android", "harmony"), "fatshark": ("windows",)}
# **退役侧名 → 现行规范名**（只保留识别，**不得再作为现行名**；派单 `T-20261005-038` ①）：
# 2026-10-04 家族改名令（`T-20261004-028`）后 Windows dsh = `fatshark`，旧名 `fatfish` 退役
# （改属公司 Linux 平台的 dsh）。留着它只为**不把历史单 / 历史提交判红** —— 命令行给了退役名
# 照样展开成同一个平台集（提示一条「退役旧名」）。
LEGACY_ACTOR_ALIASES = {"fatfish": "fatshark"}
DEFAULT_CONTRACT_OWNER = "bluewhale"


def norm(p: str) -> str:
    """统一成仓根相对的 POSIX 路径（去 `./`、反斜杠转正斜杠）。"""
    p = str(p).replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p.strip()


def has_prefix(path: str, prefix: str) -> bool:
    """前缀命中（锚在仓根）：`App/` 只命中顶层 `App/`；文件前缀要整段相等或后面跟 `/`。"""
    prefix = norm(prefix)
    if prefix.endswith("/"):
        return path.startswith(prefix)
    return path == prefix or path.startswith(prefix + "/")


def git(repo: pathlib.Path, *args: str):
    # `-c core.quotePath=false`：否则中文路径会被 git 输出成 `"Docs/\346\246\202…"` 这种 C 风格
    # 八进制转义（实测踩过：本仓 `Docs/概要设计.md` 因此被判成「未登记路径」）—— 路径必须原样读。
    r = subprocess.run(["git", "-C", str(repo), "-c", "core.quotePath=false"] + list(args),
                       capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def detect_repo(start: pathlib.Path) -> pathlib.Path:
    """仓根 = 脚本所在目录所属的 git 顶层（找不到就当脚本目录的上一级）。"""
    code, out, _ = git(start, "rev-parse", "--show-toplevel")
    if code == 0 and out.strip():
        return pathlib.Path(out.strip())
    return start.resolve().parent


class ManifestError(Exception):
    """清单本身坏了（缺文件 / 声明与盘上不一致）⇒ 退出 2，不判红也不放行。"""


class Manifest:
    def __init__(self, data: dict, where: str):
        self.data = data or {}
        self.where = where
        self.trees = self.data.get("trees") or []
        self.shared = [norm(s) for s in (self.data.get("shared") or [])]
        self.allow = []
        for e in self.data.get("unclassified_allow") or []:
            if isinstance(e, str):
                self.allow.append((norm(e), ""))
            else:
                self.allow.append((norm(e.get("path", "")), e.get("reason", "")))
        self.ledger = self.data.get("shared_ledger") or []
        self.aliases = self.data.get("owner_aliases") or {}
        self.require_declaration = bool(self.data.get("shared_require_declaration", True))
        self.repo_name = self.data.get("repo") or "?"
        # 契约所有者（演员名）+ 三书清单：**契约模式**（`--mine <契约所有者>`）下只有这些路径放行，
        # 其余一律判红 —— 人类主人护栏原话：「如果有涉及代码提交就拦，鲸鱼娘只能处理三书这几个文档」。
        self.contract_owner = (self.data.get("contract_owner") or DEFAULT_CONTRACT_OWNER).strip().lower()
        self.contract_docs = [norm(x) for x in (self.data.get("contract_docs") or []) if str(x).strip()]

    @staticmethod
    def load(path: pathlib.Path) -> "Manifest":
        if not path.exists():
            raise ManifestError("清单不在盘上：%s（判据的输入没了，不放行也不判红）" % path)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            raise ManifestError("清单不是合法 JSON：%s（%s）" % (path, exc))
        return Manifest(data, str(path))

    def validate(self, repo: pathlib.Path):
        """清单 ↔ 盘面自校验：返回问题列表（空 = 清单与盘上一致）。"""
        probs = []
        if not self.trees:
            probs.append("清单里没有 trees（各端子树是判据的输入）")
        if not self.shared:
            probs.append("清单里 shared 为空（共享面必须先说清是哪些）")
        for t in self.trees:
            for p in t.get("paths", []):
                if not (repo / norm(p).rstrip("/")).exists():
                    probs.append("tree[%s] 声明的路径在盘上不存在：%s" % (t.get("id"), p))
        for a, _r in self.allow:
            if a and not (repo / a.rstrip("/")).exists():
                probs.append("unclassified_allow 里的路径在盘上不存在：%s" % a)
        for d in self.contract_docs or []:
            if not (repo / d.rstrip("/")).exists():
                probs.append("contract_docs（三书）声明的路径在盘上不存在：%s" % d)
        def overlap(p1, p2):
            return has_prefix(norm(p1).rstrip("/") + "/x", p2) or \
                   has_prefix(norm(p2).rstrip("/") + "/x", p1)
        for i, t1 in enumerate(self.trees):
            for t2 in self.trees[i + 1:]:
                for p1 in t1.get("paths", []):
                    for p2 in t2.get("paths", []):
                        if overlap(p1, p2):
                            probs.append("两棵树路径互相覆盖：%s[%s] ∩ %s[%s]"
                                         % (t1.get("id"), p1, t2.get("id"), p2))
            for p1 in t1.get("paths", []):
                for s in self.shared:
                    if overlap(p1, s):
                        probs.append("子树路径与共享面互相覆盖：%s[%s] ∩ shared[%s]"
                                     % (t1.get("id"), p1, s))
        return probs

    def _one(self, tok: str):
        """单个标识 → (tree id 集合, 档位)；认不出 ⇒ (None, None)。

        `tok` 可以是：tree id（`macos` / `windows` / `android` / `harmony`）· tree 的 owner 名 ·
        契约侧名 · **演员名**（`bighippo` / `tinyhippo` / `fatshark`；旧名 `fatfish` 只保留识别 ⇒ 展开成它名下的子树；
        2026-10-03 制度变更）。契约所有者（`bluewhale`，平台集为空）由 `evaluate()` 走**契约模式**。
        """
        want = LEGACY_ACTOR_ALIASES.get(tok, tok)      # 退役侧名 → 现行名（识别保留）
        if want in ACTOR_PLATFORMS and ACTOR_PLATFORMS[want]:
            plats = set(ACTOR_PLATFORMS[want])
            ids = {t["id"] for t in self.trees
                   if t.get("id") in plats or t.get("owner") in plats
                   or (t.get("actor") or "") in (want, tok)}
            return (ids or None), ("actor" if ids else None)
        if tok in {t.get("id") for t in self.trees}:
            return {tok}, "tree"
        alias = self.aliases.get(tok, tok)
        ids = {t["id"] for t in self.trees
               if t.get("owner") == alias or t.get("id") == alias}
        if ids:
            return ids, "tree"
        sides = {t.get("contract_side") for t in self.trees}
        if tok in sides:
            return {t["id"] for t in self.trees if t.get("contract_side") == tok}, "side"
        return None, None

    def side_of(self, mine: str):
        """`--mine` → (本侧 tree id 集合, 档位说明)；认不出 ⇒ (None, None)。

        收逗号列表（例：`--mine android,harmony` = 同一个实现者手里的两条子树）。
        """
        toks = [x.strip() for x in (mine or "").split(",") if x.strip()]
        ids, kinds, bad = set(), set(), []
        for tok in toks:
            i, k = self._one(tok)
            if i is None:
                bad.append(tok)
                continue
            ids |= i
            kinds.add(k)
        if not toks or bad or not ids:
            return None, None
        mode = "契约侧（宽松档）" if kinds == {"side"} else "端（子树分家）"
        return ids, mode


def classify(path: str, man: Manifest):
    """分类顺序：shared → trees → unclassified_allow → 未登记。"""
    for s in man.shared:
        if has_prefix(path, s):
            return "shared", s, None
    for t in man.trees:
        for p in t.get("paths", []):
            if has_prefix(path, p):
                return "tree", p, t
    for a, r in man.allow:
        if a and has_prefix(path, a):
            return "allow", a, r
    return "unregistered", None, None


def ledger_reason(path: str, man: Manifest):
    for e in man.ledger:
        g = norm(e.get("glob") or e.get("path") or "")
        if not g:
            continue
        if fnmatch.fnmatch(path, g) or has_prefix(path, g.rstrip("*")):
            return e.get("reason") or ""
    return None


def evaluate(paths, man: Manifest, mine: str, inline=None, commit_note=None):
    """核心判据（纯函数，自测直接调它）。返回 (exit_code, 打印行列表, 计数)。"""
    inline = inline or {}
    counts0 = {"shared": 0, "mine": 0, "other": 0, "unregistered": 0, "allow": 0}
    if not [p for p in paths if norm(p)]:
        return EXIT_PASS, ["⚠️ 无内容可查 ≠ 已通过（改动集为空 —— 「确实没改」与「基线选错 / 查了个空」不是一回事）"], counts0
    counts = {"shared": 0, "mine": 0, "other": 0, "unregistered": 0, "allow": 0}
    out, reds = [], []
    # —— 契约模式（2026-10-03 制度变更）：`mine` = 契约所有者 ⇒ 只许处理三书，碰到别的就拦 ——
    if (mine or "").strip().lower() == (man.contract_owner or DEFAULT_CONTRACT_OWNER):
        if not man.contract_docs:
            return EXIT_SKIP, ["⚠️ 契约模式判不了：清单里没登记 `contract_docs`（三书清单）"
                               " —— 契约所有者 = %s；补清单前不判绿" % man.contract_owner], counts
        for raw in sorted(set(norm(p) for p in paths if norm(p))):
            if any(has_prefix(raw, d) for d in man.contract_docs):
                counts["mine"] += 1
                out.append("✅ 契约层（三书）：%s ⇒ 归 `%s`" % (raw, man.contract_owner))
            else:
                counts["other"] += 1
                reds.append("❌ 契约层护栏：%s ⇒ `%s` 只能处理三书（%s）—— 人类主人护栏"
                            "「有涉及代码提交就拦，鲸鱼娘只能处理三书这几个文档」"
                            % (raw, man.contract_owner, "、".join(man.contract_docs)))
        code = EXIT_RED if reds else EXIT_PASS
        return code, out + reds, counts
    mine_ids, mode = man.side_of(mine)
    if mine_ids is None:
        return EXIT_SKIP, ["⚠️ 认不出本侧（`--mine %s`）—— 清单里的端 = %s，契约侧 = %s"
                           % (mine, "、".join(t.get("id", "?") for t in man.trees),
                              "、".join(sorted({t.get("contract_side", "?") for t in man.trees})))], counts
    for raw in sorted(set(norm(p) for p in paths if norm(p))):
        kind, hit, tree = classify(raw, man)
        if kind == "shared":
            counts["shared"] += 1
            reason = ledger_reason(raw, man)
            src = "台账" if reason else None
            if not reason:
                ir = inline.get(raw)
                if ir:
                    reason, src = ir, "新增行注记"
                elif commit_note:
                    reason, src = commit_note, "提交信息"
            if reason or not man.require_declaration:
                out.append("✅ 共享面：%s ⇒ %s（%s）"
                           % (raw, src or "本仓关闭了声明要求", (reason or man.data.get("shared_note", ""))[:80]))
            else:
                reds.append("❌ 共享面未登记：%s ⇒ 在清单 `shared_ledger` 里改前登记理由（glob 命中），"
                            "或在本次新增行注 `%s：理由`，或提交信息写 `%s: 理由`" % (raw, TAG, TAG))
        elif kind == "tree":
            if tree.get("id") in mine_ids:
                counts["mine"] += 1
                out.append("✅ 本侧子树：%s ⇒ %s" % (raw, tree.get("label") or tree.get("id")))
            else:
                counts["other"] += 1
                reds.append("❌ 对侧子树：%s ⇒ 属于「%s」（tree=%s），本侧 = %s"
                            % (raw, tree.get("label") or tree.get("id"), tree.get("id"), mine))
        elif kind == "allow":
            counts["allow"] += 1
            out.append("✅ 白名单：%s ⇒ %s" % (raw, hit))
        else:
            counts["unregistered"] += 1
            reds.append("❌ 未登记路径：%s ⇒ 加进 `trees[].paths`（谁的子树）/ `shared` / "
                        "`unclassified_allow`（杂项，带理由）" % raw)
    code = EXIT_RED if reds else EXIT_PASS
    return code, out + reds, counts


def resolve_base(repo: pathlib.Path, explicit: str | None):
    """基线推断顺序 origin/master → HEAD~1 → HEAD；**拿不到就退出 2**（绝不当成「没问题」）。"""
    def ok(ref):
        return git(repo, "rev-parse", "--verify", "-q", ref)[0] == 0
    if explicit:
        if not ok(explicit):
            return None, "⚠️ 显式给的基线解析不到：%s" % explicit
        return explicit, "显式指定"
    for ref in ("origin/master", "HEAD~1", "HEAD"):
        if ok(ref):
            return ref, "推断（origin/master → HEAD~1 → HEAD）"
    return None, "⚠️ 推断不出基线（origin/master / HEAD~1 / HEAD 都不解析）"


def base_commit(repo: pathlib.Path, ref: str):
    """把基线 ref 换成**对照点**：`git merge-base <ref> HEAD`（拿不到就用 ref 本身）。"""
    code, out, _ = git(repo, "merge-base", ref, "HEAD")
    if code == 0 and out.strip():
        return out.strip(), "merge-base(%s, HEAD)" % ref
    return ref, "拿不到 merge-base ⇒ 直接用 %s（本地落后远端时可能误判）" % ref


def changed_paths(repo: pathlib.Path, base: str, files, diff_file):
    """改动集 = `git diff --name-only <base>`（基线到**工作区**，含未提交改动；`base..HEAD` 是其子集）。"""
    if files:
        return [norm(f) for f in files], "显式 --files（%d 条）" % len(files)
    if diff_file:
        text = pathlib.Path(diff_file).read_text(encoding="utf-8")
        names = []
        for line in text.splitlines():
            if line.startswith("diff --git "):
                parts = line.split()
                if len(parts) >= 4:
                    names.append(norm(_unquote(parts[3][2:])))
        return sorted(set(names)), "现成 diff（--diff-file）"
    code, out, err = git(repo, "diff", "--name-only", base)
    if code != 0:
        return None, "⚠️ `git diff --name-only %s` 失败：%s" % (base, err.strip()[:120])
    return [norm(x) for x in out.splitlines() if x.strip()], "git diff --name-only %s" % base


def _unquote(p: str) -> str:
    """把 git 的 C 风格引号路径还原成真实 UTF-8 路径（`\346\246\202` 这类八进制转义）。"""
    if len(p) < 2 or not (p.startswith('"') and p.endswith('"')):
        return p
    body, raw = p[1:-1], bytearray()
    esc = {"n": 10, "t": 9, "r": 13, "a": 7, "b": 8, "f": 12, "v": 11,
           '"': 34, "\\": 92}
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            if nxt in "01234567":
                digits, j = "", i + 1
                while j < len(body) and len(digits) < 3 and body[j] in "01234567":
                    digits += body[j]
                    j += 1
                raw.append(int(digits, 8) & 0xFF)
                i = j
                continue
            raw.append(esc.get(nxt, ord(nxt) & 0xFF))
            i += 2
            continue
        raw += c.encode("utf-8")
        i += 1
    return raw.decode("utf-8", "replace")


def inline_notes(repo: pathlib.Path, base: str, diff_file):
    """本次**新增行**里的 `shared-surface：理由` ⇒ {路径: 理由}（理由为空不算登记）。"""
    if diff_file:
        text = pathlib.Path(diff_file).read_text(encoding="utf-8")
    else:
        text = git(repo, "diff", "-U0", base)[1]
    notes, cur = {}, None
    for line in text.splitlines():
        if line.startswith("diff --git "):
            parts = line.split()
            cur = norm(_unquote(parts[3][2:])) if len(parts) >= 4 else None
            continue
        if line.startswith("+++ ") or line.startswith("--- "):
            continue
        if not line.startswith("+") or cur is None:
            continue
        reason = declaration_reason(line[1:])
        if reason:
            notes.setdefault(cur, reason)
    return notes


def commit_note(repo: pathlib.Path, base: str):
    """提交信息里的 `shared-surface: 理由`（整批豁免，照 check-exclusive-sections.py 的先例）。"""
    code, out, _ = git(repo, "log", "--format=%B", "%s..HEAD" % base)
    if code != 0 or not out.strip():
        return None
    for line in out.splitlines():
        reason = declaration_reason(line)
        if reason:
            return reason
    return None


FIXTURE = {
    "version": 1,
    "repo": "Fixture",
    "trees": [
        {"id": "macos", "owner": "macos", "contract_side": "apple", "hosts": ["darwin"],
         "label": "macOS 端", "paths": ["App/", "Package.swift"]},
        {"id": "android", "owner": "mobile", "contract_side": "nonapple",
         "label": "安卓端（Gradle + Kotlin）", "paths": ["android/"]},
        {"id": "harmony", "owner": "mobile", "contract_side": "nonapple",
         "label": "鸿蒙端（hvigor + ArkTS）", "paths": ["entry/", "hvigorfile.ts"]},
        {"id": "windows", "owner": "windows", "contract_side": "nonapple",
         "label": "Windows 端（Tauri 2 + Rust）", "paths": ["platform/windows/"]},
    ],
    "contract_owner": "bluewhale",
    "contract_docs": ["Docs/需求规范书.md", "Docs/概要设计.md"],
    "shared": ["Docs/", "tools/", "AGENT-SPEC.md"],
    "unclassified_allow": [{"path": "README.md", "reason": "仓根门面"}],
    "shared_ledger": [{"glob": "Docs/发布计划.md", "reason": "台账追加", "by": "macos",
                       "at": "2026-10-02"}],
}


def _fx(**over) -> Manifest:
    d = json.loads(json.dumps(FIXTURE))
    d.update(over)
    return Manifest(d, "<fixture>")


def _fixture_repo(root: pathlib.Path):
    """自测用的假仓：清单里声明的每条路径都真的建出来（否则 validate 那两例测不到点子上）。"""
    for p in ("App", "android", "entry", "platform/windows", "Docs", "tools"):
        (root / p).mkdir(parents=True, exist_ok=True)
    for f in ("Package.swift", "hvigorfile.ts", "README.md"):
        (root / f).write_text("x\n", encoding="utf-8")
    for f in ("Docs/需求规范书.md", "Docs/概要设计.md"):
        (root / f).write_text("x\n", encoding="utf-8")


def selftest(repo: pathlib.Path, man: Manifest) -> int:
    results = []
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="path-ownership-selftest-"))
    _fixture_repo(tmp)

    def check(name, expect, paths=(), mine="macos", inline=None, commit=None, man=None,
              wants=(), not_wants=(), man_validate=None, raw_ok=None):
        if raw_ok is not None:
            results.append((name, bool(raw_ok()), "-", str(expect), ""))
            return
        m = man_validate if man_validate is not None else (man or _fx())
        if man_validate is not None:
            probs = m.validate(tmp)
            code, text = (EXIT_SKIP if probs else EXIT_PASS), " / ".join(probs)
        else:
            code, lines, _c = evaluate(list(paths), m, mine, inline=inline, commit_note=commit)
            text = "\n".join(lines)
        ok = (code == expect and all(w in text for w in wants)
              and not any(w in text for w in not_wants))
        results.append((name, ok, code, expect, text))

    # 1 空改动集：绿 + ⚠️ 措辞（「查了个空」不许读成「查过且合法」）
    check("① 不动 ⇒ 绿，且打印「无内容可查 ≠ 已通过」", EXIT_PASS, paths=[],
          wants=["无内容可查 ≠ 已通过"])
    # 2 只改本侧子树 ⇒ 绿
    check("② 只改本侧子树 ⇒ 绿", EXIT_PASS,
          paths=["App/Views/A.swift", "Package.swift"], wants=["本侧子树"])
    # 3 改对侧子树 ⇒ 红 + 点名文件
    check("③ 改对侧子树 ⇒ 红并点名文件", EXIT_RED, paths=["platform/windows/Core/src/lib.rs"],
          wants=["对侧子树", "platform/windows/Core/src/lib.rs", "Windows 端"])
    # 4 混合 ⇒ 红，且只点名对侧那一份
    check("④ 本侧 + 对侧混在一批 ⇒ 红，且只点名对侧", EXIT_RED,
          paths=["App/a.swift", "android/app/Main.kt"],
          wants=["对侧子树", "android/app/Main.kt"],
          not_wants=["❌ 对侧子树：App/a.swift"])
    # 5 共享面未登记 ⇒ 红
    check("⑤ 共享面未登记 ⇒ 红", EXIT_RED, paths=["Docs/概要设计.md"],
          wants=["共享面未登记", "shared-surface"])
    # 6 共享面 + 台账 glob 命中 ⇒ 绿
    check("⑥ 共享面 + 台账已登记 ⇒ 绿", EXIT_PASS, paths=["Docs/发布计划.md"],
          wants=["共享面", "台账"])
    # 7 共享面 + 本次新增行注记 ⇒ 绿
    check("⑦ 共享面 + 新增行注记 ⇒ 绿", EXIT_PASS, paths=["Docs/概要设计.md"],
          inline={"Docs/概要设计.md": "台账跟版"}, wants=["新增行注记"])
    # 8 注记理由为空 ⇒ 不算登记（红）
    check("⑧ 注记理由为空 ⇒ 不算登记（仍判红）", EXIT_RED, paths=["Docs/概要设计.md"],
          inline={"Docs/概要设计.md": ""}, wants=["共享面未登记"])
    # 9 提交信息整批豁免 ⇒ 绿
    check("⑨ 提交信息里注理由 ⇒ 绿", EXIT_PASS, paths=["tools/check-x.py"],
          commit="本轮落判据（shared-surface: 落判据）", wants=["提交信息"])
    # 10 未登记路径 ⇒ 红
    check("⑩ 未登记路径 ⇒ 红并要求登记", EXIT_RED, paths=["somewhere/new.txt"],
          wants=["未登记路径"])
    # 11 白名单 ⇒ 绿
    check("⑪ 白名单（仓根杂项，带理由）⇒ 绿", EXIT_PASS, paths=["README.md"],
          wants=["白名单"])
    # 12 清单声明路径不在盘上 ⇒ 退出 2（清单过期 = 判据过期）
    check("⑫ 清单声明了盘上没有的路径 ⇒ 退出 2", EXIT_SKIP,
          man_validate=_fx(trees=[{"id": "macos", "owner": "macos", "contract_side": "apple",
                                   "paths": ["App/", "Nope/"]},
                                  {"id": "windows", "owner": "windows",
                                   "contract_side": "nonapple", "paths": ["platform/windows/"]}]),
          wants=["在盘上不存在"])
    # 13 两棵树路径互相覆盖 ⇒ 退出 2
    check("⑬ 两棵树路径互相覆盖 ⇒ 退出 2", EXIT_SKIP,
          man_validate=_fx(trees=[{"id": "android", "owner": "mobile",
                                   "contract_side": "nonapple", "paths": ["android/"]},
                                  {"id": "harmony", "owner": "mobile",
                                   "contract_side": "nonapple", "paths": ["android/entry/"]},
                                  {"id": "macos", "owner": "macos", "contract_side": "apple",
                                   "paths": ["App/"]}]),
          wants=["互相覆盖"])
    # 14 子树与共享面互相覆盖 ⇒ 退出 2（这正是「Scripts/ 该算谁的」那一类冲突的防线）
    check("⑭ 子树与共享面互相覆盖 ⇒ 退出 2", EXIT_SKIP,
          man_validate=_fx(trees=[{"id": "macos", "owner": "macos", "contract_side": "apple",
                                   "paths": ["App/", "tools/"]},
                                  {"id": "windows", "owner": "windows",
                                   "contract_side": "nonapple", "paths": ["platform/windows/"]}]),
          wants=["与共享面互相覆盖"])
    # 15 契约侧宽松档：同一 contract_side 的几棵树互相都算本侧
    check("⑮ 契约侧宽松档（--mine nonapple）改 platform/windows/ ⇒ 绿", EXIT_PASS,
          paths=["platform/windows/src/lib.rs"], mine="nonapple", wants=["本侧子树"])
    # 16 子树分家档：端 ≠ 本侧 ⇒ 红（安卓与鸿蒙就是靠这一档分的）
    check("⑯ 子树分家档（--mine windows）改 android/ ⇒ 红", EXIT_RED,
          paths=["android/app/a.kt"], mine="windows", wants=["对侧子树", "安卓端"])
    # 17 认不出的本侧 ⇒ 退出 2（不猜）
    check("⑰ 认不出的本侧（--mine nosuch）⇒ 退出 2，不猜", EXIT_SKIP,
          paths=["App/a.swift"], mine="nosuch", wants=["认不出本侧"])
    # 18 行内注记的解析：理由为空不算登记（TAG_RE 只认非空理由）
    check("⑱ 声明行解析：剥注释记号后以它开头才算（两种注释形态 + 理由为空不算）",
          True, raw_ok=lambda: declaration_reason("shared-surface：") is None
          and declaration_reason("# shared-surface：本轮落判据") == "本轮落判据"
          and declaration_reason("// shared-surface: reason") == "reason"
          and declaration_reason("<!-- shared-surface：理由 -->") == "理由")
    check("⑱b 只在句子里**引用**这个写法 ≠ 声明（不许自己给自己放行）",
          True, raw_ok=lambda: declaration_reason(
              "# 共享面：清单 `shared_ledger` 改前登记 / 新增行注 `shared-surface：理由`") is None)
    # 19 真仓库：本仓清单与盘面对齐（每条声明路径都存在）+ 空改动 ⇒ 绿
    probs = man.validate(repo)
    check("⑲ 真仓库：本仓清单与盘面对齐且空改动 ⇒ 绿", EXIT_PASS,
          paths=[], man=man, wants=["无内容可查 ≠ 已通过"])
    if probs:
        results.append(("⑲b 真仓库清单自校验（声明路径都在盘上）", False, "-", "-",
                        " / ".join(probs)))
    else:
        results.append(("⑲b 真仓库清单自校验（声明路径都在盘上）", True, "-", "-", ""))

    # ㉑ 逗号列表：同一个实现者手里的两条子树（`--mine android,harmony`）
    check("㉑ 逗号列表（--mine android,harmony）：改 android/ 绿、改 platform/windows/ 红", EXIT_PASS,
          paths=["android/app/a.kt", "entry/src/main/ets/Main.ets"], mine="android,harmony",
          wants=["本侧子树", "鸿蒙端"])
    check("㉑b 逗号列表下改 platform/windows/ ⇒ 红", EXIT_RED, paths=["platform/windows/src/lib.rs"],
          mine="android,harmony", wants=["对侧子树"])

    # ⑳ 本地**落后**远端时不许把「对侧刚推上来的提交」算成本地改动（merge-base 兜住这一类假红）
    fx = tmp / "gitfixture"
    fx.mkdir()
    _fixture_repo(fx)                      # 清单声明的路径全部建出来（清单自校验要过）
    (fx / "platform" / "windows" / "w.rs").write_text("x\n", encoding="utf-8")
    (fx / "path-ownership.json").write_text(json.dumps(FIXTURE, ensure_ascii=False), encoding="utf-8")

    def _g(*a):
        return subprocess.run(["git", "-C", str(fx)] + list(a), capture_output=True, text=True)

    _g("init", "-q")
    _g("config", "user.email", "t@example.invalid")
    _g("config", "user.name", "t")
    _g("add", "-A")
    _g("commit", "-qm", "c1")
    c1 = _g("rev-parse", "HEAD").stdout.strip()
    _g("update-ref", "refs/remotes/origin/master", c1)
    (fx / "platform" / "windows" / "w.rs").write_text("y\n", encoding="utf-8")
    _g("add", "-A")
    _g("commit", "-qm", "c2")
    c2 = _g("rev-parse", "HEAD").stdout.strip()
    _g("update-ref", "refs/remotes/origin/master", c2)
    _g("reset", "--hard", c1)          # 本地落后：远端已经多了一条改对侧子树的提交
    run = subprocess.run([sys.executable, str(pathlib.Path(__file__).resolve()),
                          "--repo", str(fx), "--manifest", str(fx / "path-ownership.json"),
                          "--mine", "macos"], capture_output=True, text=True)
    results.append(("⑳ 本地落后远端（对侧新提交不算自己的改动）⇒ 不误判", run.returncode == EXIT_PASS,
                    run.returncode, str(EXIT_PASS), run.stdout.strip()[-300:]))

    # ㉒ 中文路径还原：git 的 C 风格引号路径（八进制转义）必须还原成真实 UTF-8
    check("㉒ C 风格引号路径（八进制转义）⇒ 还原成真实 UTF-8 路径",
          True, raw_ok=lambda: _unquote(r'"Docs/\346\246\202\350\246\201.md"') == "Docs/概要.md"
          and _unquote("plain/x.md") == "plain/x.md")
    # ㉓ 端到端：中文名的**共享面**改动必须认成「共享面未登记」，不许掉进「未登记路径」
    (fx / "Docs" / "概要-中文.md").write_text("x\n", encoding="utf-8")
    _g("add", "-A")
    _g("commit", "-qm", "c3 中文路径")
    run2 = subprocess.run([sys.executable, str(pathlib.Path(__file__).resolve()),
                           "--repo", str(fx), "--manifest", str(fx / "path-ownership.json"),
                           "--mine", "macos"], capture_output=True, text=True)
    ok2 = (run2.returncode == EXIT_RED and "共享面未登记" in run2.stdout
           and "未登记路径" not in run2.stdout)
    results.append(("㉓ 中文路径端到端 ⇒ 认成共享面（不是「未登记路径」）", ok2, run2.returncode,
                    str(EXIT_RED), run2.stdout.strip()[-320:]))

    # ── ㉔~㉙ 契约所有者 = 演员名（2026-10-03 人类主人制度变更 · 派单 `T-20261003-003`）──────────────
    # 契约定：三书**契约层**归 `bluewhale`；平台实现层按平台名归各平台助理。护栏原话（人类主人）：
    # 「如果有涉及代码提交就拦，鲸鱼娘只能处理三书这几个文档」。成对证据：同一条改动上
    # 「所有者改 ⇒ 绿 / 碰非三书 ⇒ 红」，以及「演员名 ≡ 平台集」这层映射真的生效。
    check("㉔ 契约所有者 `bluewhale` 改三书 ⇒ 绿", EXIT_PASS,
          paths=["Docs/需求规范书.md"], mine="bluewhale", wants=["契约层（三书）"])
    check("㉕ 契约所有者碰到代码 ⇒ 红（护栏：有涉及代码提交就拦）", EXIT_RED,
          paths=["App/Views/A.swift"], mine="bluewhale",
          wants=["契约层护栏", "只能处理三书", "Docs/需求规范书.md"])
    check("㉖ 契约所有者碰脚本 / 仓根杂项 ⇒ 也红（三书之外的都拦，含共享面与白名单）", EXIT_RED,
          paths=["tools/hack.py", "README.md"], mine="bluewhale", wants=["契约层护栏"])
    check("㉗ 演员名 `bighippo` ≡ `macos,ios`：改 macOS 子树 ⇒ 绿", EXIT_PASS,
          paths=["App/Views/A.swift"], mine="bighippo", wants=["本侧子树"])
    check("㉘ 演员名 `tinyhippo` ≡ 安卓/鸿蒙：改 windows 子树 ⇒ 红（跨平台仍越界）", EXIT_RED,
          paths=["platform/windows/Core/src/lib.rs"], mine="tinyhippo", wants=["对侧子树"])
    check("㉙ 演员名现行规范名 `fatshark` ≡ windows：改 windows 子树 ⇒ 绿", EXIT_PASS,
          paths=["platform/windows/Core/src/lib.rs"], mine="fatshark", wants=["本侧子树"])
    # ㉚ / ㉛ 演员名跟版护栏（2026-10-05 · 派单 `T-20261005-038` ①）：旧名 `fatfish` 退役
    # （2026-10-04 家族改名令 `T-20261004-028` 后改属公司 Linux 侧）⇒ 规范名表里必须是
    # `fatshark`，而 `fatfish` 只保留识别（历史单 / 历史提交不判红）。成对证据见 ⑰（词表外名 ⇒ 退出 2）。
    check("㉚ 退役侧名 `fatfish` 仍可识别（历史单 / 历史提交不判红）：≡ windows ⇒ 绿", EXIT_PASS,
          paths=["platform/windows/Core/src/lib.rs"], mine="fatfish", wants=["本侧子树"])
    check("㉛ 防回退：规范名表含 `fatshark`、不含退役名 `fatfish`",
          True, raw_ok=lambda: ACTOR_PLATFORMS.get("fatshark") == ("windows",)
          and "fatfish" not in ACTOR_PLATFORMS
          and LEGACY_ACTOR_ALIASES.get("fatfish") == "fatshark")

    bad = [r for r in results if not r[1]]
    for name, ok, code, expect, text in results:
        print("  %s %s（退出码 %s，期望 %s）" % ("✅" if ok else "❌", name, code, expect))
        if not ok and text:
            print("      实测输出：%s" % text.replace("\n", "\n      ")[:600])
    print("自测：%d/%d 例通过" % (len(results) - len(bad), len(results)))
    return EXIT_PASS if not bad else EXIT_RED


def host_tokens():
    import platform
    sysname = platform.system().lower()
    return {"darwin": ["darwin"], "windows": ["win32", "windows"],
            "linux": ["linux"]}.get(sysname, [sysname])


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="路径归属判据（三仓同源；清单 = 与脚本同目录的 path-ownership.json）")
    ap.add_argument("--mine", default=None,
                    help="本侧：端 id / owner / 契约侧（apple·nonapple）")
    ap.add_argument("--base", default=None, help="对照基线（默认 origin/master → HEAD~1 → HEAD）")
    ap.add_argument("--files", nargs="*", default=None, help="显式指定改动集（自测 / 夹具用）")
    ap.add_argument("--diff-file", default=None, help="用现成的 diff 文本")
    ap.add_argument("--manifest", default=None, help="换清单（默认：脚本同目录）")
    ap.add_argument("--repo", default=None, help="仓根（默认：脚本所在仓的 git 顶层）")
    ap.add_argument("--actor", default=None,
                    help="执行者（演员名）：`bluewhale`(=契约模式，只许三书) / `bighippo`(macOS,iOS) / "
                         "`tinyhippo`(安卓,鸿蒙) / `fatshark`(Windows；旧名 `fatfish` 保留识别)；"
                         "等价于 `--mine <演员名>`")
    ap.add_argument("--self-test", action="store_true", help="跑自测（34 例）")
    args = ap.parse_args(argv)

    script_dir = pathlib.Path(__file__).resolve().parent
    repo = pathlib.Path(args.repo).resolve() if args.repo else detect_repo(script_dir)
    man_path = pathlib.Path(args.manifest) if args.manifest else script_dir / "path-ownership.json"
    try:
        man = Manifest.load(man_path)
    except ManifestError as exc:
        print("⚠️ %s" % exc)
        print("RESULT: SKIP (exit 2)")
        return EXIT_SKIP

    if args.self_test:
        return selftest(repo, man)

    probs = man.validate(repo)
    if probs:
        print("⚠️ 清单与盘上不一致（清单过期 = 判据过期，不许静默通过）：")
        for p in probs:
            print("   · %s" % p)
        print("RESULT: SKIP (exit 2)")
        return EXIT_SKIP

    mine, src = (args.actor or args.mine), ("--actor" if args.actor else "--mine")
    if not mine:
        env_mine = os.environ.get("DOYAH_OWNER") or os.environ.get("DOYAH_SIDE")
        if env_mine:
            if env_mine.strip().lower() == (man.contract_owner or DEFAULT_CONTRACT_OWNER) \
                    or man.side_of(env_mine)[0] is not None:
                mine, src = env_mine, "环境变量（DOYAH_OWNER / DOYAH_SIDE）"
            else:
                print("ℹ️ 环境变量 DOYAH_OWNER / DOYAH_SIDE = %s 在本仓清单里认不出"
                      "（本仓的端 = %s）⇒ **忽略它**，改按 `hosts` 推断"
                      % (env_mine, "、".join(t.get("id", "?") for t in man.trees)))
    if mine and src not in ("--mine", "--actor"):
        print("ℹ️ 本侧来自%s = %s" % (src, mine))
    if not mine:
        toks = host_tokens()
        for t in man.trees:
            if any(h in toks for h in (t.get("hosts") or [])):
                mine = t["id"]
                break
        if mine:
            print("ℹ️ 本侧由清单 `hosts` 推断 = %s（可用 --mine 覆盖）" % mine)
    if not mine:
        print("⚠️ 推断不出本侧（清单里没有 hosts 命中当前系统）⇒ 显式给 --mine（端 / owner / 契约侧）")
        print("RESULT: SKIP (exit 2)")
        return EXIT_SKIP

    base, how = resolve_base(repo, args.base)
    if base is None:
        print(how)
        print("RESULT: SKIP (exit 2)")
        return EXIT_SKIP
    base, how_base = base_commit(repo, base)
    paths, how2 = changed_paths(repo, base, args.files, args.diff_file)
    if paths is None:
        print(how2)
        print("RESULT: SKIP (exit 2)")
        return EXIT_SKIP
    inline = {} if args.files else inline_notes(repo, base, args.diff_file)
    cnote = None if args.files else commit_note(repo, base)
    _ids, mode = man.side_of(mine)
    print("路径归属判据 · 仓 = %s · 清单 = %s" % (man.repo_name, man_path.name))
    print("本侧 = %s（%s）｜基线 = %s / %s（%s）｜改动集 = %s"
          % (mine, mode or "认不出", base[:12], how_base, how, how2))
    code, lines, counts = evaluate(paths, man, mine, inline=inline, commit_note=cnote)
    for line in lines:
        print("   " + line)
    print("受检路径 %d 条：共享面 %d / 本侧 %d / 对侧 %d / 白名单 %d / 未登记 %d"
          % (len(paths), counts["shared"], counts["mine"], counts["other"],
             counts["allow"], counts["unregistered"]))
    stale = [e.get("glob") for e in man.ledger
             if e.get("glob") and not any(fnmatch.fnmatch(p, e["glob"]) for p in paths)]
    if stale:
        print("ℹ️ 台账里 %d 条本轮没用到（合并进基线后可以删）：%s" % (len(stale), "、".join(stale)))
    if code == EXIT_PASS:
        print("✅ 路径归属通过：没有一条改动落在对侧子树上" if paths
              else "⚠️ 无内容可查 ≠ 已通过")
    print("RESULT: %s (exit %d)" % ({0: "PASS", 1: "FAIL", 2: "SKIP"}[code], code))
    return code


if __name__ == "__main__":
    sys.exit(main())
