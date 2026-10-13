#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""三仓「同源副本」身份对账门禁（合册 `T-20261013-027` · 原单 `T-20261010-039`）。

**为什么要有它**：`check-exclusive-sections.py` / `check-path-ownership.py` 在三仓
（`DoyahStudio/Scripts/` · `DoyahNotes/tools/logic-check/` · `DoyahRetro/tools/`）的 docstring 里
自称「三仓同源副本 · 三份逐字节同一份」，而三仓里**没有任何一门判据去看另外两份**：单仓改一处
⇒ 该仓自己的门禁全绿、另两仓也无从知道，声明当场静默过期（属潜伏缺口 —— 2026-10-10 实测三份仍一致）。
契约层 `AGENT-SPEC.md` 把身份写成具体锚点（各 **943** 行 / sha256 `194c4334…`）也无人守：2026-10-14 实测
盘上已是 **983** 行 / `2c1f314d…` ⇒ 该锚点**已经陈旧**（属契约层落笔面，本判据不判它，已在本册登记请前门跟版）。

**判据（四款 + 两条护栏）**

- **A 每一份 ↔ 台账里「逐仓身份」**（`expect.<仓>`）：sha256 + 行数相符；不符 ⇒ 判红并点名「仓 + 文件 + 期望/实测」。
  台账对**三仓各自**都登记一份身份（本机三仓同处 `~/.dsh/projects` ⇒ 一次跑就三份都读得到）。
- **B 另两仓在盘上时**：逐份比（仓路径取自台账 `repos`；**仓在盘、文件不在** ⇒ 判红；仓不在盘 ⇒ 跳过）。
- **C 另两仓不在盘上**：如实打印「跳过（不在盘上）」+ 高声提示，**跳过 ≠ 通过**；`--require-all` 时跳过即红。
- **D 空跑防护**：台账副本条目 < `floor`（默认 **2**）、或**一份都没比成** ⇒ 判红 —— 不许在「一条都没比」时打勾。
- **E 台账自身坏掉**（缺件 / 不是合法 JSON / 缺 `repos` / `copies`）⇒ 判红、退出码 **2**、不吐栈。
- **F 参数面**：未知参数 ⇒ 退出码 2（argparse 默认，不静默吞掉）。
- **G 三份不一致必须逐仓登记理由**（`divergence`：仓 + 原因 + 依据单）：不登记 ⇒ 判红（无钉 = 逃逸口）；
  三份已一致而登记未删 ⇒ 也判红（陈旧登记）。**本条是 2026-10-14 落地当场抓到的活体分叉逼出来的**：
  `check-path-ownership.py` 三份 sha 各异（Studio `588b7db2…` / Notes `7755593234…` / Retro `66f873cf…`，
  差异 = `T-20261006-057` 的 `platform/windows/` 字面量跟版 + 均衡令文案与自测 34 → 38 例只在 Studio 落地）。

**不做的事（如实登记）**：不比 `path-ownership.json` 与提交钩子（那两件**按仓定制**、不算分叉）；
不判契约层锚点数值（见上）；不判另两仓自己那份台账。

用法：

    python3 Scripts/check-tri-repo-parity.py                      # 本仓（三仓同处一个父目录）
    python3 Scripts/check-tri-repo-parity.py --projects-dir <目录>  # 三仓父目录
    python3 Scripts/check-tri-repo-parity.py --require-all        # 另两仓不在盘上即红
    python3 Scripts/check-tri-repo-parity.py --self-test          # 判据自己的证据（20 例）

退出码：0 = 全绿（或如实跳过）；1 = 判红；2 = 判据自身坏掉（台账读不动 / 参数面）。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEDGER = "Scripts/tri-repo-parity.json"


def stats(path: pathlib.Path):
    """(sha256, 行数)，行数按换行符个数算（与 `wc -l` 同口径）。"""
    data = path.read_bytes()
    return hashlib.sha256(data).hexdigest(), data.count(b"\n")


def load_ledger(root: pathlib.Path):
    """(台账, 错误行)。判据自身坏掉的那一类：不吐栈。"""
    path = root / LEDGER
    if not path.is_file():
        return None, f"❌ 台账不在盘上：{LEDGER}（判据失据 ⇒ 判红）"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return None, f"❌ 台账读不动（不是合法 JSON）：{LEDGER} —— {type(exc).__name__}"
    if not isinstance(data, dict):
        return None, f"❌ 台账顶层不是对象：{LEDGER}"
    return data, ""


def evaluate(root: pathlib.Path, projects_dir: pathlib.Path, require_all: bool) -> dict:
    """⇒ {problems, skips, compared, detail, copies, floor, code}"""
    result = {"problems": [], "skips": [], "compared": 0, "detail": [], "copies": 0, "floor": 2, "code": 0}
    problems, skips, detail = result["problems"], result["skips"], result["detail"]
    ledger, err = load_ledger(root)
    if ledger is None:
        return {"problems": [err], "skips": [], "compared": 0, "detail": [], "copies": 0, "floor": 2, "code": 2}
    repos, copies = ledger.get("repos"), ledger.get("copies")
    if not isinstance(repos, list) or not repos:
        return {"problems": ["❌ 台账缺 `repos`（或为空）⇒ 判红（空跑防护：不知道本仓是哪一份）"],
                "skips": [], "compared": 0, "detail": [], "copies": 0, "floor": 2, "code": 2}
    if not isinstance(copies, list):
        return {"problems": ["❌ 台账缺 `copies`（或不是数组）⇒ 判红（空跑防护）"],
                "skips": [], "compared": 0, "detail": [], "copies": 0, "floor": 2, "code": 2}
    result["copies"] = len(copies)
    floor = ledger.get("floor", 2)
    if not isinstance(floor, int) or floor < 2:
        problems.append("❌ 台账 `floor` 不是 >= 2 的整数 ⇒ 按 2 兜底并判红（不许把下限调到 1 以下）")
        floor = 2
    result["floor"] = floor
    if len(copies) < floor:
        problems.append(f"❌ 台账副本条目 {len(copies)} 条 < 下限 {floor} ⇒ 判红（空跑防护：不许在「一条都没比」时打勾）")
    by_id = {}
    for repo in repos:
        if not isinstance(repo, dict) or not repo.get("id") or not repo.get("dir"):
            problems.append("❌ 台账 `repos` 里有一项缺 `id` / `dir`")
            continue
        by_id[repo["id"]] = repo
    if not any(r.get("self") for r in by_id.values()):
        problems.append("❌ 台账 `repos` 里没有一项标 `self: true` ⇒ 判红（不知道本仓是哪一份）")
    for copy in copies:
        if not isinstance(copy, dict) or not copy.get("file") or not isinstance(copy.get("paths"), dict):
            problems.append("❌ 台账 `copies` 里有一项缺 `file` / `paths`")
            continue
        fname = copy["file"]
        expect = copy.get("expect") if isinstance(copy.get("expect"), dict) else {}
        divergence = copy.get("divergence") if isinstance(copy.get("divergence"), list) else []
        basis = copy.get("basis", "?")
        seen = {}
        for rid, rel in copy["paths"].items():
            repo = by_id.get(rid)
            if repo is None:
                problems.append(f"❌ 台账 `{fname}` 的 `paths` 指到未登记的仓 `{rid}`")
                continue
            label = repo.get("label") or repo["dir"]
            want = expect.get(rid)
            if not isinstance(want, dict) or not isinstance(want.get("sha256"), str):
                problems.append(f"❌ 台账 `{fname}` 没登记 `{rid}` 那份的身份（`expect.{rid}.sha256`）"
                                "⇒ 判红（宁可缺件报红，不许缺件放过）")
                continue
            if repo.get("self"):
                base = root
            else:
                base = projects_dir / repo["dir"]
                if not base.is_dir():
                    skips.append(f"{label}（{repo['dir']}/{rel}）")
                    continue
            path = base / rel
            if not path.is_file():
                problems.append(f"❌ {label} 在盘上、但这份文件不在：{repo['dir']}/{rel}（仓在、文件不在 ⇒ 判红）")
                continue
            sha, nlines = stats(path)
            result["compared"] += 1
            seen[rid] = sha
            detail.append(f"  · {label}/{rel}  sha256={sha[:16]}…  行数={nlines}")
            if sha != want["sha256"]:
                problems.append(f"❌ {label} 那份与台账不符（sha256）：{repo['dir']}/{rel} "
                                f"期望 {want['sha256'][:16]}… 实测 {sha[:16]}…（依据 {basis}）")
            if isinstance(want.get("lines"), int) and nlines != want["lines"]:
                problems.append(f"❌ {label} 那份与台账不符（行数）：{repo['dir']}/{rel} "
                                f"期望 {want['lines']} 实测 {nlines}（依据 {basis}）")
        if len(set(seen.values())) > 1:
            self_id = next((r["id"] for r in by_id.values() if r.get("self")), None)
            anchor_sha = seen.get(self_id) if self_id else None
            if anchor_sha is None:
                anchor_sha = max(set(seen.values()), key=list(seen.values()).count)
            registered = {d.get("repo") for d in divergence if isinstance(d, dict)}
            for rid in sorted(rid for rid, sha in seen.items() if sha != anchor_sha):
                if rid not in registered:
                    problems.append(f"❌ `{fname}` 三份不一致而未登记理由：`{rid}`（{seen[rid][:16]}… ≠ "
                                    f"本仓 {str(anchor_sha)[:16]}…）⇒ 台账 `divergence` 里逐条写「仓 + 原因 + 依据单」才算数")
        elif seen and divergence:
            problems.append(f"❌ `{fname}` 的台账登记了 `divergence`（{len(divergence)} 条），"
                            "但盘上三份已经一致 ⇒ 陈旧登记，删掉它（豁免无钉 = 逃逸口）")
    if result["compared"] == 0:
        problems.append("❌ 一份都没比成（三仓都读不到）⇒ 判红（空跑防护）")
    if require_all and skips:
        problems.append(f"❌ --require-all：有 {len(skips)} 处「不在盘上」被跳过 ⇒ 判红（跳过 ≠ 通过）")
    result["code"] = 1 if problems else 0
    return result


def run(root: pathlib.Path, projects_dir: pathlib.Path, require_all: bool) -> int:
    d = evaluate(root, projects_dir, require_all)
    for line in d["problems"]:
        print(line)
    print(f"[checkTriRepoParity] 三仓同源副本 {d['copies']} 份（下限 {d['floor']}）："
          f"比成 {d['compared']} 处 · 跳过 {len(d['skips'])} 处")
    for line in d["detail"]:
        print(line)
    for line in d["skips"]:
        print(f"⚠ 跳过（不在盘上）：{line} —— 跳过 ≠ 通过（要「全部到盘才算数」请加 --require-all）")
    if d["code"]:
        if d["code"] == 2:
            print("[checkTriRepoParity] 判据自身坏掉（台账读不动）⇒ 退出码 2，不做任何比对")
        return d["code"]
    if d["skips"]:
        print(f"✅ 副本身份对账通过：比成 {d['compared']} 处（{len(d['skips'])} 处不在盘上、未比）")
    else:
        print(f"✅ 三仓副本身份对账通过：{d['copies']} 份 / 比成 {d['compared']} 处 / 零跳过")
    return 0


FIXTURE_BODY = "#!/usr/bin/env python3\nprint('fixture')\n"


def _fixture(base: pathlib.Path):
    """三仓沙箱：<base>/studio（本仓）+ <base>/DoyahNotes + <base>/DoyahRetro，两份同源副本。"""
    studio = base / "studio"
    (studio / "Scripts").mkdir(parents=True, exist_ok=True)
    targets = {
        "studio": studio / "Scripts/check-fixture.py",
        "notes": base / "DoyahNotes/tools/logic-check/check-fixture.py",
        "retro": base / "DoyahRetro/tools/check-fixture.py",
        "studio2": studio / "Scripts/check-fixture2.py",
        "notes2": base / "DoyahNotes/tools/logic-check/check-fixture2.py",
        "retro2": base / "DoyahRetro/tools/check-fixture2.py",
    }
    for path in targets.values():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(FIXTURE_BODY, encoding="utf-8")
    sha, nlines = stats(targets["studio"])
    copies = []
    for name in ("check-fixture.py", "check-fixture2.py"):
        want = {rid: {"sha256": sha, "lines": nlines} for rid in ("studio", "notes", "retro")}
        copies.append({
            "file": name, "basis": "T-20261010-039", "expect": want, "divergence": [],
            "paths": {"studio": "Scripts/" + name,
                      "notes": "tools/logic-check/" + name,
                      "retro": "tools/" + name},
        })
    ledger = {
        "version": 1, "purpose": "自测夹具", "basis": ["T-20261010-039"], "floor": 2,
        "repos": [
            {"id": "studio", "label": "DoyahStudio", "dir": "studio", "self": True},
            {"id": "notes", "label": "DoyahNotes", "dir": "DoyahNotes"},
            {"id": "retro", "label": "DoyahRetro", "dir": "DoyahRetro"},
        ],
        "copies": copies,
    }
    return studio, targets, ledger


def _m_none(base, targets, ledger):
    return None


def _m_touch_self(base, targets, ledger):
    targets["studio"].write_text(FIXTURE_BODY + "# 本仓自己多了一行\n", encoding="utf-8")
    return None


def _m_touch_notes(base, targets, ledger):
    targets["notes"].write_text(FIXTURE_BODY + "# 另仓多了一行\n", encoding="utf-8")
    return None


def _m_drop_retro_file(base, targets, ledger):
    targets["retro"].unlink()
    return None


def _m_move_retro_repo(base, targets, ledger):
    shutil.rmtree(base / "DoyahRetro")
    return None


def _m_bad_sha(base, targets, ledger):
    for copy in ledger["copies"]:
        for rid in copy["expect"]:
            copy["expect"][rid]["sha256"] = "0" * 64
    return None


def _m_bad_lines(base, targets, ledger):
    for copy in ledger["copies"]:
        for rid in copy["expect"]:
            copy["expect"][rid]["lines"] = copy["expect"][rid]["lines"] + 1
    return None


def _m_empty_copies(base, targets, ledger):
    ledger["copies"] = []
    return None


def _m_one_copy(base, targets, ledger):
    ledger["copies"] = ledger["copies"][:1]
    return None


def _m_bad_ledger_json(base, targets, ledger):
    return "{ 这不是 JSON"


def _m_drop_self_file(base, targets, ledger):
    targets["studio"].unlink()
    return None


def _m_unknown_repo(base, targets, ledger):
    for copy in ledger["copies"]:
        copy["paths"]["macos"] = "Scripts/check-fixture.py"
    return None


def _m_all_gone(base, targets, ledger):
    for key in ("studio", "studio2"):
        targets[key].unlink()
    shutil.rmtree(base / "DoyahNotes")
    shutil.rmtree(base / "DoyahRetro")
    return None


def _m_drift_documented(base, targets, ledger):
    for key in ("notes", "notes2"):
        targets[key].write_text(FIXTURE_BODY + "# 另仓的历史差异（已逐仓登记理由）\n", encoding="utf-8")
    for copy in ledger["copies"]:
        key = "notes" if copy["file"] == "check-fixture.py" else "notes2"
        sha, nlines = stats(targets[key])
        copy["expect"]["notes"] = {"sha256": sha, "lines": nlines}
        copy["divergence"] = [{"repo": "notes", "reason": "夹具：一份先跟版、另份未跟（等价于真仓抓到的活体分叉）",
                               "basis": "T-20261006-057"}]
    return None


def _m_drift_unregistered(base, targets, ledger):
    targets["notes"].write_text(FIXTURE_BODY + "# 另仓变了但台账没登记理由\n", encoding="utf-8")
    sha, nlines = stats(targets["notes"])
    for copy in ledger["copies"]:
        if copy["file"] == "check-fixture.py":
            copy["expect"]["notes"] = {"sha256": sha, "lines": nlines}
    return None


def _m_stale_divergence(base, targets, ledger):
    for copy in ledger["copies"]:
        copy["divergence"] = [{"repo": "retro", "reason": "夹具：三份早已一致而登记未删", "basis": "?"}]
    return None


def _m_missing_expect(base, targets, ledger):
    for copy in ledger["copies"]:
        copy["expect"].pop("notes", None)
    return None


CASES = [
    ("基线（三仓同盘 · 台账相符）", _m_none, [], 0, ["比成 6 处", "零跳过"]),
    ("本仓那份多一行", _m_touch_self, [], 1, ["DoyahStudio", "不符（sha256）"]),
    ("另仓（Notes）那份多一行", _m_touch_notes, [], 1, ["DoyahNotes", "不符（sha256）"]),
    ("另仓在盘、文件不在（Retro 删文件）", _m_drop_retro_file, [], 1, ["仓在、文件不在"]),
    ("另仓整棵不在盘（Retro 移走）", _m_move_retro_repo, [], 0, ["跳过（不在盘上）", "比成 4 处"]),
    ("同上 + --require-all", _m_move_retro_repo, ["--require-all"], 1, ["--require-all", "跳过 ≠ 通过"]),
    ("台账 sha 写错", _m_bad_sha, [], 1, ["不符（sha256）", "期望 0000000000000000"]),
    ("台账行数写错", _m_bad_lines, [], 1, ["不符（行数）"]),
    ("台账副本条目被掏空", _m_empty_copies, [], 1, ["下限 2", "一份都没比成"]),
    ("台账副本只剩 1 条（低于下限）", _m_one_copy, [], 1, ["下限 2"]),
    ("台账不是合法 JSON", _m_bad_ledger_json, [], 2, ["读不动"]),
    ("本仓那份文件不在盘", _m_drop_self_file, [], 1, ["DoyahStudio", "这份文件不在"]),
    ("台账 paths 指到未登记的仓", _m_unknown_repo, [], 1, ["未登记的仓"]),
    ("三仓全不可比（一份都没比成）", _m_all_gone, [], 1, ["一份都没比成"]),
    ("另仓漂移 · 台账已逐仓登记理由", _m_drift_documented, [], 0, ["比成 6 处", "零跳过"]),
    ("另仓漂移 · 台账未登记理由", _m_drift_unregistered, [], 1, ["未登记理由"]),
    ("三份已一致而登记未删（陈旧登记）", _m_stale_divergence, [], 1, ["陈旧登记"]),
    ("台账缺某仓的逐仓身份", _m_missing_expect, [], 1, ["没登记"]),
    ("未知参数（参数面）", _m_none, ["--nonsense"], 2, ["unrecognized arguments"]),
]


def self_test() -> int:
    script = pathlib.Path(__file__).resolve()
    real_root = script.parent.parent
    real_files = [real_root / LEDGER,
                  real_root / "Scripts/check-exclusive-sections.py",
                  real_root / "Scripts/check-path-ownership.py"]
    before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in real_files if p.is_file()}
    failures = 0
    for idx, (name, mutate, extra, expect_rc, expect) in enumerate(CASES, 1):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            studio, targets, ledger = _fixture(base)
            raw = mutate(base, targets, ledger)
            text = raw if raw is not None else json.dumps(ledger, ensure_ascii=False, indent=2) + "\n"
            (studio / LEDGER).write_text(text, encoding="utf-8")
            proc = subprocess.run([sys.executable, str(script), "--root", str(studio),
                                   "--projects-dir", str(base)] + extra,
                                  capture_output=True, text=True)
            out = proc.stdout + proc.stderr
            missing = [f for f in expect if f not in out]
            ok = proc.returncode == expect_rc and not missing
            hint = "" if not missing else " / 缺：" + "、".join(missing)
            print(f"{'✅' if ok else '❌'} 例 {idx} {name}（期望 rc={expect_rc}，实得 {proc.returncode}{hint}）")
            if not ok:
                failures += 1
                print("     实得输出：")
                for line in out.strip().splitlines()[:12]:
                    print("       " + line)
    total = len(CASES) + 1
    proc = subprocess.run([sys.executable, str(script)], capture_output=True, text=True)
    real_ok = proc.returncode == 0
    print(f"{'✅' if real_ok else '❌'} 例 {total} 真仓库实跑：rc={proc.returncode}（三仓在盘 ⇒ 期望全绿）")
    if not real_ok:
        failures += 1
        print(proc.stdout.strip()[-800:])
    after = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in real_files if p.is_file()}
    if before != after:
        print("❌ 负例跑完真仓库的台账 / 两份同源脚本被改动了（不合格）")
        failures += 1
    else:
        print(f"✅ 负例全程只在临时目录里写坏，真仓库 {len(before)} 份文件逐字节未变")
    print(f"\n{'✅' if not failures else '❌'} 负例 {total - failures}/{total} 达到预期")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="三仓「同源副本」身份对账（原单 T-20261010-039）")
    parser.add_argument("--root", default=None, help="仓库根（默认 = 脚本的上一级目录）")
    parser.add_argument("--projects-dir", default=None, help="三仓父目录（默认 = 仓根的上一级目录）")
    parser.add_argument("--require-all", action="store_true", help="另两仓不在盘上 ⇒ 判红（跳过即红）")
    parser.add_argument("--self-test", action="store_true", help="判据自己的证据（20 例，只在临时目录里写坏）")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    root = pathlib.Path(args.root).resolve() if args.root else ROOT
    projects_dir = pathlib.Path(args.projects_dir).resolve() if args.projects_dir else root.parent
    return run(root, projects_dir, args.require_all)


if __name__ == "__main__":
    sys.exit(main())
