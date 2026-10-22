#!/usr/bin/env python3
"""三书结构自审门禁（「九轮清单」的机械层）。

用法：
    check-doc-layout.py                 # 三书全跑（cap / req / design）
    check-doc-layout.py <书.md> --mode cap|req|design [--srs 需求书.md] [--allow-platform]

九轮（每轮全书扫，不是分章扫；一轮全清即可，不必真跑九遍）：
  1 结构 单节章 / 空章 / 断号 / 过短节
  2 标题 日期·轮次·队列号·「已上移」·加粗·内嵌注释 / 能力书 >6 汉字
  3 节序 同章内 N.M 逆序或跳号
  4 引用 §x.y 解析不到（近处点了书名 = 跨书，放行）
  5 排印 「。 **」双空格 / 水平线紧贴标题 / 行尾空格 / 空括号
  6 章内 标题并列两项、章内却只有一节
  7 追溯 契约节无需求编号 / 编号在需求书里不存在（--mode design）
  8 平台名 正文（非 [独占:*] 节）出现平台名
  9 节号唯一 同一个 N.M(.K) 出现两次（交叉引用会指错门）

豁免：Scripts/doc-layout-exempt.json —— {"<文件>": [{"match": "摘要子串", "reason": "…"}]}
命中必须能对上一条豁免的 match 子串，否则照旧判红（豁免不是关闸）。
"""
import json, re, sys, pathlib

PLAT = re.compile(r"macOS|Windows|Linux|iOS|iPadOS|watchOS|Android|鸿蒙")
CROSS = re.compile(r"Doyah产品|AGENT-SPEC|核心契约|计划书|规划书|需求规范书|开发记录|清单|SRS|proposal|外观方案|\.md|第[一二三四五六七八九十]+章|本书|本册|旧本|旧版|契约|需求书|需求分析|概要设计|能力规划")
META = re.compile(r"(20\d\d-\d\d-\d\d)|(队列\s*[LNT]-\d+)|(第\s*\d+\s*轮)|((已上移))")
CJK = re.compile(r"[\u4e00-\u9fff]")
DOCS = {"cap": "Docs/Doyah产品能力规划说明书.md",
        "req": "Docs/Doyah产品需求规格说明书.md",
        "design": "Docs/Doyah产品概要设计说明书.md"}


def headings(lines):
    out, fenced = [], False
    for i, l in enumerate(lines):
        if l.startswith("```"):
            fenced = not fenced
        if not fenced:
            m = re.match(r"^(#{1,6}) (.*)$", l)
            if m:
                out.append((i, len(m.group(1)), m.group(2).rstrip()))
    return out


def num_of(t):
    m = re.match(r"^(\d+(?:\.\d+)*) ", t)
    return m.group(1) if m else None


def scope_map(lines):
    own, stack = {}, {}
    for i, l in enumerate(lines):
        m = re.match(r"^(#{1,6}) ", l)
        if m:
            lv = len(m.group(1))
            mk = re.findall(r"\[独占:([a-z|]+)\]", l)
            for k in [x for x in stack if x >= lv]:
                del stack[k]
            stack[lv] = mk[0] if mk else None
        eff = None
        for k in sorted(stack):
            if stack[k]:
                eff = stack[k]
        own[i] = eff
    return own


def audit(path, mode, srs_path=None, allow_platform=False, min_chars=100, cjk_max=6):
    lines = pathlib.Path(path).read_text(encoding="utf-8").split("\n")
    H = headings(lines)
    own = scope_map(lines)
    hits = []

    def add(k, msg):
        hits.append((k, msg))

    h1 = [h[0] for h in H if h[1] == 1]
    for n, (i, lv, t) in enumerate(H):
        if lv != 1:
            continue
        end = next((x for x in h1 if x > i), len(lines))
        subs = [h for h in H if i < h[0] < end and h[1] == 2]
        if len(subs) == 1 and "非目标" not in t and not t.startswith("附录"):
            add(1, f"L{i+1} 单节章「{t[:36]}」只有 {subs[0][2][:36]}")
        body = "".join(l for l in lines[i + 1:end] if l.strip())
        if not subs and len(re.sub(r"\s", "", body)) < min_chars:
            add(1, f"L{i+1} 空章「{t[:36]}」")
    for n, (i, lv, t) in enumerate(H):
        if lv >= 4 or lv == 1:
            continue
        end = H[n + 1][0] if n + 1 < len(H) else len(lines)
        child = (n + 1 < len(H) and H[n + 1][1] > lv)
        body = "".join(l for l in lines[i + 1:end] if l.strip() and not l.startswith("#"))
        if not child and len(re.sub(r"\s", "", body)) < min_chars:
            add(1, f"L{i+1} 过短节「{t[:36]}」{len(body)} 字")
    ch = [int(num_of(t).split(".")[0]) for _, lv, t in H if lv == 1 and num_of(t) and num_of(t).split(".")[0].isdigit()]
    for k in range(1, len(ch)):
        if ch[k] != ch[k - 1] + 1:
            add(1, f"章号断档 {ch[k-1]} → {ch[k]}")

    for i, lv, t in H:
        if own.get(i) and "windows" in own[i]:
            continue
        bad = []
        if META.search(t):
            bad.append("含日期/轮次/队列号/已上移")
        if "**" in t:
            bad.append("含加粗")
        if "<!--" in t:
            bad.append("含内嵌注释")
        if mode == "cap" and lv >= 2:
            name = re.sub(r"^(第[一二三四五六七八九十]+章|附录\s*[A-Z]|\d+(?:\.\d+)*)\s*", "", t)
            if len(CJK.findall(name)) > cjk_max:
                bad.append(f"汉字 {len(CJK.findall(name))} 超 {cjk_max}")
        if bad:
            add(2, f"L{i+1} 「{t[:44]}」→ {'、'.join(bad)}")

    per = {}
    for i, lv, t in H:
        n = num_of(t)
        if lv == 2 and n and n.count(".") == 1:
            per.setdefault(n.split(".")[0], []).append((n, i))
    for c, lst in per.items():
        prev = 0
        for n, i in lst:
            v = int(n.split(".")[1])
            if v < prev:
                add(3, f"L{i+1} 节序逆序 {n}")
            elif v > prev + 1:
                add(3, f"L{i+1} 节号跳号 {c}.{prev:02d} → {n}")
            prev = max(prev, v)

    # ⑨ 节号唯一：全书引用都靠节号，撞号等于把读者指到另一节去（2026-10-22 实测撞过一次）。
    seen_num = {}
    for i, lv, t in H:
        n = num_of(t)
        if lv >= 2 and n:
            if n in seen_num:
                add(9, f"L{i+1} 节号重复 {n}（首次在 L{seen_num[n]+1}）")
            else:
                seen_num[n] = i

    hnums = {num_of(t) for _, _, t in H if num_of(t)}
    for _, lv, t in H:
        m = re.match(r"^第([一二三四五六七八九十]+)章", t)
        if m:
            v = m.group(1)
            cn = "一二三四五六七八九"
            if v in cn:
                hnums.add(str(cn.index(v) + 1))
            elif v == "十":
                hnums.add("10")
            elif v.startswith("十") and v[1] in cn:
                hnums.add(str(11 + cn.index(v[1])))
            elif v.endswith("十") and v[0] in cn:
                hnums.add(str((cn.index(v[0]) + 1) * 10))
    for i, l in enumerate(lines):
        if "<!--" in l:
            continue
        if own.get(i):  # [独占:*] 节里的是该侧自己的引用体系，本侧不判
            continue
        cross = bool(CROSS.search(l))
        for m in re.finditer(r"§\s*(\d+(?:\.\d+)*)", l):
            ref = m.group(1)
            if ref in hnums or cross:
                continue
            add(4, f"L{i+1} §{ref} 解析不到｜{l[max(0,m.start()-24):m.start()+24].strip()[:60]}")

    fenced = False
    for i, l in enumerate(lines):
        if l.startswith("```"):
            fenced = not fenced
            continue
        if fenced or l[:1] in "│┌└├─┐┘┤┬┴┼":
            continue
        if "。 **" in l:
            add(5, f"L{i+1} 「。 **」双空格")
        if l != l.rstrip():
            add(5, f"L{i+1} 行尾空格")
        if "（）" in l or "( )" in l:
            add(5, f"L{i+1} 空括号")
        if not l.startswith(("|", " ", "\t", "-", "*", ">")) and re.search(r"[^\s]\s{3,}[^\s]", l):
            add(5, f"L{i+1} 句中三连空格")
    for i, lv, t in H:
        if i + 1 < len(lines) and lines[i + 1].strip() == "---":
            add(5, f"L{i+1} 水平线紧贴标题「{t[:28]}」")

    for n, (i, lv, t) in enumerate(H):
        if lv != 1 or t.startswith("附录"):
            continue
        end = next((x for x in h1 if x > i), len(lines))
        subs = [h for h in H if i < h[0] < end and h[1] in (2, 3)]
        title = re.sub(r"^第[一二三四五六七八九十]+章\s*", "", t)
        body_len = len(re.sub(r"\s", "", "".join(lines[i + 1:end])))
        if re.search(r"[与和、]", title) and len(subs) <= 1 and body_len < 400:
            add(6, f"L{i+1} 「{title[:28]}」标题并列两项，章内只有 {len(subs)} 节")

    if mode == "design":
        srs = pathlib.Path(srs_path).read_text(encoding="utf-8") if srs_path else ""
        for i, lv, t in H:
            if lv != 2 or "【契约】" not in t:
                continue
            end = next((h[0] for h in H if h[0] > i), len(lines))
            body = "\n".join(lines[i:end])
            if not re.search(r"(FR|NFR|AC)-(?:[A-Z0-9]{2,8}-){1,3}\d", body):
                add(7, f"L{i+1} 契约节无需求编号「{t[:36]}」")
            if srs:
                for m in sorted(set(re.findall(r"(?:FR|NFR|AC)-(?:[A-Z0-9]{2,8}-){1,3}\d{2,3}", body))):
                    if m not in srs:
                        add(7, f"L{i+1} 引用的 {m} 在需求书里不存在")

    if not allow_platform:
        appx = next((i for i, l in enumerate(lines) if re.match(r"^#+ 附录 [DE]", l)), len(lines))
        for i, l in enumerate(lines):
            if i >= appx or own.get(i) or l.startswith("#"):
                continue
            m = PLAT.search(l)
            if m:
                add(8, f"L{i+1} 正文平台名「{m.group(0)}」｜{l[max(0,m.start()-24):m.start()+24].strip()[:56]}")
    return lines, H, hits


NAMES = {1: "结构", 2: "标题", 3: "节序", 4: "交叉引用", 5: "排印", 6: "章内完整", 7: "追溯", 8: "平台名", 9: "节号唯一"}


def run(path, mode, srs=None, allow_platform=False, min_chars=100, exempt=None):
    lines, H, hits = audit(path, mode, srs, allow_platform, min_chars)
    keep = []
    for k, msg in hits:
        ok = False
        for e in (exempt or {}).get(path, []):
            if e.get("match") and e["match"] in msg:
                ok = True
                break
        if not ok:
            keep.append((k, msg))
    print(f"== {path}｜{len(lines)} 行｜标题 {len(H)} 个｜{mode}")
    for k in sorted(NAMES):
        sub = [m for kk, m in keep if kk == k]
        if not sub:
            print(f"  [{k}] {NAMES[k]} 0")
            continue
        print(f"  [{k}] {NAMES[k]} {len(sub)}")
        for m in sub[:30]:
            print(f"      · {m}")
        if len(sub) > 30:
            print(f"      · …还有 {len(sub)-30} 条")
    return len(keep)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    mode = "cap"
    srs = None
    allow_platform = False
    min_chars = None
    for i, a in enumerate(sys.argv):
        if a == "--mode" and i + 1 < len(sys.argv):
            mode = sys.argv[i + 1]
        if a == "--srs" and i + 1 < len(sys.argv):
            srs = sys.argv[i + 1]
        if a == "--allow-platform":
            allow_platform = True
        if a == "--min-chars" and i + 1 < len(sys.argv):
            min_chars = int(sys.argv[i + 1])
    ex_path = pathlib.Path("Scripts/doc-layout-exempt.json")
    exempt = json.loads(ex_path.read_text(encoding="utf-8")) if ex_path.exists() else {}
    if args:
        mc = min_chars if min_chars is not None else (80 if mode == "cap" else 100)
        bad = run(args[0], mode, srs, allow_platform, mc, exempt)
        print("✓ 九轮全清" if bad == 0 else f"❌ 九轮自审未清：{bad} 条")
        return 0 if bad == 0 else 1
    total = 0
    for m, rel in DOCS.items():
        total += run(rel, m, DOCS["req"] if m == "design" else None,
                     m != "cap", 80 if m == "cap" else 100, exempt)
    print("\n✓ 三书九轮全清" if total == 0 else f"\n❌ 三书九轮自审未清：{total} 条")
    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
