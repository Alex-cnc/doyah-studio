#!/usr/bin/env python3
"""四书归位判据（拦人，不是提示）。

由来：同一类错误重复太多次 —— 把「修复轮次/beta 号」「流程纪律/门禁说明」写进产品详细设计，
把契约条文写进台账。人（和 agent）在赶进度时会跳过「该放哪本书」的判断，所以这个判断不能
留在记忆里，必须由提交路径强制。

判据（只查 Docs/ 里被改动的书，按文件名分书；**`Docs/frozen/**` 冻结副本不判** —— 它是活书的逐字副本）：
  A. 详设（详细设计说明书）：禁止出现「第N轮 / 第N批 / betaX.Y.Z / 日期前缀标题」，
     禁止出现流程纪律词（门禁 / 提交前 / 纪律 / 规范要求 / 自检脚本）。
  B. 台账（任务清单）：禁止出现带编号的契约条文（「判据 T-x」「必须/不得 + 判据号」）。
命中即 rc=1，并直接告诉你该挪到哪本书。

用法：
  python3 Scripts/check-doc-placement.py                 # 查工作区已改动 + 已暂存的 Docs 文件
  python3 Scripts/check-doc-placement.py --file <path>   # 查单个文件（自检/夹具用）
  python3 Scripts/check-doc-placement.py --self-test
"""
import json, re, subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

# 书 → 它**不该**装的
FORBIDDEN = {
    # 精度优先：只拦「一眼就能判错书」的形态，不拦正文里正当提到脚本名（判据列本来就该点名脚本）
    "详细设计说明书": [
        (r"^#{1,4}\s*[^\n]*第[0-9一二三四五六七八九十]+轮", "标题里出现「第N轮」", "台账（那里记做第几轮）"),
        (r"^#{1,4}\s*[^\n]*第[0-9一二三四五六七八九十]+批", "标题里出现「第N批」", "台账"),
        (r"^#{1,4}\s*[^\n]*beta\d", "标题里出现 beta 版本号", "台账"),
        (r"^#{1,4}\s*[^\n]*（?20\d\d-\d\d-\d\d", "标题里出现日期", "台账"),
        (r"^#{1,4}\s*[^\n]*(纪律|门禁|规范要求|同步四书)", "标题写成流程/纪律条目", "《项目管理规范》"),
        (r"^[^>|\n]*(提交前(必须)?跑|四书同步纪律|改代码必须同批改文档)", "正文写流程纪律（非版本行/非表格）", "《项目管理规范》"),
    ],
    "任务清单": [
        (r"^#{1,4}\s*[^\n]*判据\s*T-", "标题里写契约判据号", "详细设计说明书"),
    ],
}

def load(p):
    return pathlib.Path(p).read_text(encoding="utf-8", errors="replace").split("\n")

def check_file(path):
    # **冻结件不判**（2026-11-08）：`Docs/frozen/**` 是活书的逐字副本（`freeze-books.py` 复制 + 只重写版本头），
    # 不是「有人把内容写错了书」。判它只会逼人用 `--no-verify` 绕过钩子 —— 那等于把整条归位判据一起关掉。
    # 负例不变：活书里真写错照旧判红（`--self-test` 那两本书的夹具）。
    if "frozen" in pathlib.Path(path).parts:
        return []
    name = pathlib.Path(path).name
    book = next((k for k in FORBIDDEN if k in name), None)
    if not book:
        return []
    exc = exceptions()
    hits = []
    base = pathlib.Path(path).name
    for i, line in enumerate(load(path), 1):
        for pat, why, where in FORBIDDEN[book]:
            if re.search(pat, line):
                key = f"{base}|{line.strip().lstrip('#').strip()}"
                if any(k.split('|')[0] == base and line.strip().lstrip('#').strip().startswith(k.split('|',1)[1]) for k in exc):
                    continue
                hits.append((i, why, where, line.strip()[:70]))
    return hits

def exceptions():
    p = ROOT / "Scripts" / "doc-placement-exceptions.json"
    if not p.exists():
        return {}
    return json.loads(p.read_text(encoding="utf-8")).get("entries", {})

def changed_docs():
    out = subprocess.run(["git", "-C", str(ROOT), "diff", "--name-only", "-z", "HEAD"],
                         capture_output=True, text=True).stdout
    staged = subprocess.run(["git", "-C", str(ROOT), "diff", "--cached", "--name-only", "-z"],
                            capture_output=True, text=True).stdout
    files = {f for f in (out + staged).split("\0") if f.strip()}
    return [str(ROOT / f) for f in files if f.startswith("Docs/") and f.endswith(".md")]

def main():
    if "--self-test" in sys.argv:
        import tempfile, os
        bad = "# 详设\n### 3.99 第二轮：beta1.0.3 真机复验\n正文提到 check-doc-sync.py 与提交前跑一遍\n"
        good = "# 详设\n### 3.99 过程区高度自适应\n正文只讲产品形态与判据读数。\n"
        with tempfile.TemporaryDirectory() as d:
            p1 = os.path.join(d, "Doyah产品详细设计说明书-macOS.md")
            p2 = os.path.join(d, "Doyah产品详细设计说明书-Android.md")
            open(p1, "w", encoding="utf-8").write(bad)
            open(p2, "w", encoding="utf-8").write(good)
            n_bad = len(check_file(p1))
            n_good = len(check_file(p2))
        ok = n_bad >= 2 and n_good == 0
        print(f"自检：坏样本命中 {n_bad} 条（应 ≥2）· 好样本命中 {n_good} 条（应 0）· {'通过' if ok else '失败'}")
        return 0 if ok else 1

    files = [sys.argv[sys.argv.index("--file") + 1]] if "--file" in sys.argv else changed_docs()
    bad = 0
    for f in files:
        for line_no, why, where, text in check_file(f):
            bad += 1
            print(f"❌ {pathlib.Path(f).name}:{line_no} {why} ⇒ 应写在 {where}\n     {text}")
    if bad:
        print(f"\n四书归位：{bad} 处放错书。详设写产品形态与契约；台账写轮次/版本/读数；规范书写流程与门禁。")
        return 1
    print("✅ 四书归位通过（详设无轮次/版本/日期/流程纪律；台账无契约判据号）")
    return 0

if __name__ == "__main__":
    sys.exit(main())
