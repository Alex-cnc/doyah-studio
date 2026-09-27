#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""越界检查：一次改动不得落在「对侧独占节」内（分层的三书形态 A，2026-09-27 拍板）。

形态约定
--------
三书里每个标题行（`#` ~ `######`）可以带一个独占标记：

    ### 8.1 契约 → macOS 实现（现有）[独占:macos]

该节（含其所有子节）属于该标记的独占范围，**只有该侧有权改**。没有标记的节 = 契约层，
两侧都必须实现、任何人都可改（改契约要走契约评审，不由本脚本判定）。

用法
----
    python3 check-exclusive-sections.py                    # 自动推断本侧，对照 origin/master 的改动
    python3 check-exclusive-sections.py --mine macos       # 显式指定本侧标记
    python3 check-exclusive-sections.py --base HEAD~1 --files Docs/概要设计.md
    python3 check-exclusive-sections.py --diff-file d.patch   # 用现成 diff（CI / 自测）
    python3 check-exclusive-sections.py --self-test           # 自测（不依赖仓库状态）

本侧推断：darwin → macos，其它 → windows（可用 --mine 覆盖，例如 Apple 侧在 Notes 仓写作 apple）。

逃生门（必须是显式的，且会打印理由）
------------------------------------
1. 该行本身或紧邻的上一行含 `exclusive-allow`（可在注释里写理由）；
2. HEAD 提交信息含 `exclusive-allow:`（整批放行，打印理由）。

退出码：0 通过（含无改动）｜1 越界｜2 用法或环境错误
"""
import argparse
import os
import re
import subprocess
import sys

MARKER_RE = re.compile(r"\[独占:([A-Za-z0-9_\-]+)\]")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
ALLOW = "exclusive-allow"
ALLOW_SECTION = "exclusive-allow-section"   # 放在独占节正文里 = 整节豁免（用于「首建占位节」等）


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
            return tok, title
    return None, None


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
        allow = any(ALLOW in it[3] for it in items)
        pairs.append((items, allow))
    return pairs


def check(files, mine, theirs, base, diff_text, quiet=False):
    parsed = parse_diff(diff_text)
    if not parsed:
        if not quiet:
            print("✅ 越界检查：本次改动未涉及受检文档（或无可解析 diff）")
        return 0
    msg = head_message()
    blanket = re.search(r"%s\s*:\s*(.+)" % ALLOW, msg)
    if blanket:
        print("⏭️  越界检查：HEAD 提交信息含豁免（理由：%s）—— 放行" % blanket.group(1).strip())
        return 0
    violations, checked = [], 0
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
                tok, title = section_of(secs, line0)
                if tok is None:
                    continue
                if any(tok == st and s <= line0 <= e for st, s, e in sect_allow):
                    continue
                checked += 1
                if tok != mine:
                    violations.append((path, line1, tok, title, content.strip()[:80]))
    # 去重：同一文件的同一节，同一处改动只报一次
    seen, uniq = set(), []
    for v in violations:
        key = (v[0], v[1], v[2])
        if key in seen:
            continue
        seen.add(key)
        uniq.append(v)
    violations = uniq
    if violations:
        print("❌ 越界检查不通过：%d 处改动落在对侧独占节内（本侧=%s）" % (len(violations), mine))
        for path, ln, tok, title, snip in violations:
            print("   %s:%d 落在 [独占:%s]『%s』：%s" % (path, ln, tok, title[:40], snip))
        print("   处理：① 交对侧来改；② 若确有必要，在该行或上一行注 `%s：理由`；"
              "③ 整批豁免用提交信息 `%s: 理由`。" % (ALLOW, ALLOW))
        return 1
    print("✅ 越界检查通过：受检改动 %d 行，均不在对侧独占节内（本侧=%s）" % (checked, mine))
    return 0


def collect_files(args):
    if args.files:
        return list(args.files)
    if args.base:
        r = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--name-only", args.base],
                           capture_output=True, text=True)
        if r.returncode == 0:
            return [x for x in r.stdout.split() if x.endswith(".md")]
    return []


def self_test():
    import tempfile
    doc = """# 概要设计（样例）

| 阅读约定 | 【契约】= 两端都要实现；【独占:macos】/【独占:windows】= 各侧实现细节 |

## 3. 【契约】平台适配层契约

契约正文，两侧都可改。

### 3.1 连接配置

契约细节。

## 8. 实现映射

### 8.1 契约 → macOS 实现（现有）[独占:macos]

macOS 实现细节：SwiftUI / Keychain。

### 8.5 契约 → Windows 实现（待建）[独占:windows]

Windows 实现细节：待补。

## 9. 已知边界（分平台）

边界表格。
"""
    d = tempfile.mkdtemp()
    os.chdir(d)
    subprocess.run(["git", "init", "-q"], check=True)
    subprocess.run(["git", "config", "user.email", "t@t"], check=True)
    subprocess.run(["git", "config", "user.name", "t"], check=True)
    path = "Doc.md"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(doc)
    subprocess.run(["git", "add", path], check=True)
    subprocess.run(["git", "commit", "-qm", "init"], check=True)

    def run(edit_old, edit_new, label):
        text = open(path, encoding="utf-8").read().replace(edit_old, edit_new, 1)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        diff = subprocess.run(["git", "diff", "--unified=0", "HEAD", "--", path],
                              capture_output=True, text=True).stdout
        subprocess.run(["git", "checkout", "-q", "--", path], check=True)
        rc = check([path], "macos", ["windows"], "HEAD", diff, quiet=True)
        ok = (rc == 1) if label == "应该报红" else (rc == 0)
        print("  自测[%s] %s → %s" % (label, edit_old[:22].strip() or "…", "✅" if ok else "❌ 不符预期"))
        return ok

    a = run("Windows 实现细节：待补。", "Windows 实现细节：小河马补的。", "应该报红")
    b = run("macOS 实现细节：SwiftUI / Keychain。", "macOS 实现细节：SwiftUI / Keychain / AppKit。", "应该通过")
    c = run("契约正文，两侧都可改。", "契约正文，两侧都可改（第二版）。", "应该通过")
    d2 = run("Windows 实现细节：待补。", "Windows 实现细节：小河马补的。 exclusive-allow：跨端联调需要", "应该通过")
    print("自测汇总：%s" % ("全部通过" if all([a, b, c, d2]) else "有失败"))
    return 0 if all([a, b, c, d2]) else 1


def main():
    ap = argparse.ArgumentParser(description="越界检查：改动不得落在对侧独占节内")
    ap.add_argument("--mine", default=None, help="本侧独占标记（默认按平台推断）")
    ap.add_argument("--theirs", default=None, help="对侧标记，逗号分隔（仅用于报错提示）")
    ap.add_argument("--base", default=None, help="对照的基线 ref（默认 origin/master，失败回退 HEAD）")
    ap.add_argument("--files", nargs="*", default=None, help="只检查这些文件")
    ap.add_argument("--diff-file", default=None, help="从文件读 diff（CI / 自测）")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    mine = args.mine or ("macos" if sys.platform == "darwin" else "windows")
    theirs = [x for x in (args.theirs.split(",") if args.theirs else []) if x] or \
             [t for t in ("macos", "windows", "apple", "android", "harmony", "linux") if t != mine]

    if args.diff_file:
        with open(args.diff_file, encoding="utf-8") as fh:
            diff_text = fh.read()
        return check(args.files or [], mine, theirs, args.base, diff_text, args.quiet)

    base = args.base
    if base is None:
        for cand in ("origin/master", "HEAD~1", "HEAD"):
            r = subprocess.run(["git", "rev-parse", "--verify", "-q", cand],
                               capture_output=True, text=True)
            if r.returncode == 0:
                base = cand
                break
    if base is None:
        print("⚠️  越界检查跳过：当前目录不是 git 仓库，且未指定 --base")
        return 0
    files = collect_files(args)
    if not files:
        if not args.quiet:
            print("✅ 越界检查通过：基线 %s 起没有受检的 .md 改动" % base)
        return 0
    r = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--unified=0", base, "--"] + files,
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("⚠️  越界检查跳过：git diff 失败（%s）" % r.stderr.strip()[:120])
        return 0
    return check(files, mine, theirs, base, r.stdout, args.quiet)


if __name__ == "__main__":
    sys.exit(main())
