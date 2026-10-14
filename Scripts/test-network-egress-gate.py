#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""负例：`Scripts/check-network-egress.py`（全仓网络出口门禁）**红得出来吗**。

**为什么单开一个脚本**：门禁绿着只能说明「现在没违规」，**不能**说明它看得见违规 ——
本工程已经栽过三次（L-04「失败只记进没人读的变量」、L-05「断言被删也照绿」、
第 14 项「删掉两处出口里的一处仍能顶数」），所以每条新门禁都配一组负例：
**写坏 → 必须报红 → 点名哪一处**。

这条门禁尤其需要负例：**真仓库里白名单之外一条出网 API 都扫不出来**，
也就是说「绿」这个结果本身分不清「真的没有」还是「扫了个寂寞」。

**做法**：不改真仓库的文件，把**必要的那几个文件**拷进临时目录，在副本上写坏、
把门禁指过去（`--root`）。跑完断言真仓库一个字节没动。

用法：`python3 Scripts/test-network-egress-gate.py`
"""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = "Scripts/check-network-egress.py"
LEDGER = "Scripts/network-egress-whitelist.json"

# 副本需要的最小文件集（门禁会读：台账登记的那 6 个面文件、扫描面里的干净文件、闭环脚本、台账、负例自己）
TREE_FILES = [
    # 四个「面」登记的 7 个文件（台账里有它 ⇒ 副本必须带上，否则「干净副本」这一例会假红）
    "Plugins/Notes/Sources/NoteSync/CloudSyncService.swift",
    "Plugins/Notes/Sources/NoteSync/CloudAuth.swift",
    "Core/LLMClient.swift",
    "Core/EgressLog.swift",
    # AI 面第 3 件（FR-AI-16 流式面 · 2026-10-14 按前门 `T-20261014-207` ① 登记）：
    "Core/LLMStreaming.swift",
    "App/AppState.swift",
    "App/Auth/AccountFlowModel.swift",
    # 只在**文档注释**里提到 URLSession 的文件（判据 3 的 grep 会数到它，但门禁判红集不含它）：
    # 带上它，才能证明「注释提及 ≠ 出现」这一条真的生效（组长第 371 轮 ④）。
    "Core/DataTaskSpecGenerator.swift",
    # 台账 `outOfFace`（面外登记）里的 10 个文件 —— 面外登记必须能跟盘上事实对账：
    # 少带一个，干净副本那一例就会按「面外登记磁盘上不存在 / 陈旧登记」判红（2026-10-14 · 原单 T-20261010-040）。
    "CLI/main.swift",
    "Platform/macOS/WebKitBrowserEngine.swift",
    "Tests/AgentObservationTests.swift",
    "Tests/AgentQuotaSessionTests.swift",
    "Tests/AgentSQLGeneratorTests.swift",
    "Tests/EgressLogTests.swift",
    "Tests/LLMRetryTests.swift",
    "Tests/LLMStreamTests.swift",
    "Tests/LLMStreamingClientTests.swift",
    "Tests/NoteSyncE2ETests.swift",
    "Scripts/verify-all.sh",
    GATE,
    LEDGER,
    "Scripts/test-network-egress-gate.py",
]

passed: list[str] = []
failed: list[str] = []


def record(ok: bool, label: str, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  {'✅' if ok else '❌'} {label}" + (f"  —— {detail}" if detail and not ok else ""))


def make_tree() -> Path:
    tree = Path(tempfile.mkdtemp(prefix="doyah-net-egress-"))
    for rel in TREE_FILES:
        destination = tree / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, destination)
    # 夹具台账跟版（2026-10-14 · 合册 `T-20261013-027` · 清册第 9~11 行 · 前门 `T-20261014-204` 第 9 条）：
    # 扫描面已由「产品源面四根」改成**全仓** ⇒ 夹具树自己数一遍 `.swift`（真仓下限 911 由末段**静态臂**看住），
    # 登记条数下限也按真仓台账现值对齐 —— 否则「干净副本应当绿」这一例会假红。
    tree_swift = sum(1 for _ in tree.rglob("*.swift"))
    registered = len(json.loads((ROOT / LEDGER).read_text(encoding="utf-8")).get("outOfFace") or [])
    edit_ledger(tree, lambda data: data["floors"].update(
        {"minFilesScanned": tree_swift, "minRegisteredEgress": registered}))
    return tree


def run_gate(tree: Path) -> tuple[int, str]:
    proc = subprocess.run(
        [sys.executable, str(tree / GATE), "--root", str(tree), "--json"],
        capture_output=True, text=True,
    )
    try:
        data = json.loads(proc.stdout)
        return proc.returncode, "；".join(data.get("problems", []))
    except json.JSONDecodeError:
        return proc.returncode, (proc.stdout + proc.stderr).strip()


def edit(tree: Path, rel: str, transform) -> None:
    path = tree / rel
    path.write_text(transform(path.read_text(encoding="utf-8")), encoding="utf-8")


def edit_ledger(tree: Path, transform) -> None:
    path = tree / LEDGER
    data = json.loads(path.read_text(encoding="utf-8"))
    transform(data)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def case_red(label: str, mutate, *expects: str) -> None:
    """在**新副本**上写坏 → 门禁必须非零退出，且报出的问题里点到期望的几处。"""
    tree = make_tree()
    mutate(tree)
    code, problems = run_gate(tree)
    ok = code != 0 and all(expect in problems for expect in expects)
    record(ok, label, f"exit={code}；实际报出：{problems[:400]}")
    shutil.rmtree(tree, ignore_errors=True)


def case_green(label: str, mutate) -> None:
    """在**新副本**上做一个「应当仍然绿」的对照 → 门禁必须 exit 0（否则判据太严＝误报）。"""
    tree = make_tree()
    mutate(tree)
    code, problems = run_gate(tree)
    record(code == 0, label, f"exit={code}；实际报出：{problems[:400]}")
    shutil.rmtree(tree, ignore_errors=True)


def snapshot() -> dict[str, str]:
    return {rel: hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() for rel in TREE_FILES}


def surface_files(data: dict, key: str) -> list:
    for surface in data["surfaces"]:
        if surface["key"] == key:
            return surface["files"]
    raise AssertionError(f"夹具台账里没有面 {key}")


def main() -> int:
    before = snapshot()

    print("— 副本本身必须是绿的（否则后面「红了」归因不到写坏上）—")
    tree = make_tree()
    code, problems = run_gate(tree)
    record(code == 0, "干净副本：exit 0", f"exit={code}；{problems[:300]}")
    shutil.rmtree(tree, ignore_errors=True)

    print("— 其余一切文件出现出网 API ⇒ 判红并点名文件:行号 —")
    case_red(
        "非白名单文件注入 `URLSession.shared` → 报红并点名文件与行号",
        lambda tree: (tree / "Core/NetLeakProbe.swift").write_text(
            "import Foundation\nlet session = URLSession.shared\n", encoding="utf-8"
        ),
        "Core/NetLeakProbe.swift:2", "URLSession", "不在台账任何一面里",
    )
    case_red(
        "非白名单文件注入 `URLRequest(` → 报红",
        lambda tree: (tree / "Core/NetRequestProbe.swift").write_text(
            "import Foundation\nlet request = URLRequest(url: URL(fileURLWithPath: \"/tmp/x\"))\n",
            encoding="utf-8",
        ),
        "URLRequest", "不在台账任何一面里",
    )

    print("— 白名单面 / 装配缝：该绿的必须绿（否则判据太严＝误报）—")
    case_green(
        "白名单面（笔记同步面）文件里出现 URLSession → 仍绿（对照）",
        lambda tree: edit(
            tree, "Plugins/Notes/Sources/NoteSync/CloudSyncService.swift",
            lambda text: text + "\n// 对照：白名单面文件本来就可以出网\nlet probe = URLSession.shared\n",
        ),
    )
    case_green(
        "装配缝文件只注入 transport → 绿（对照）",
        lambda tree: edit(
            tree, "App/Auth/AccountFlowModel.swift",
            lambda text: text + "\nlet probeTransport = URLSessionTransport()\n",
        ),
    )
    case_red(
        "装配缝文件注入**直接出网调用** → 判红（SRS v3.94 §6.4 纪律③）",
        lambda tree: edit(
            tree, "App/AppState.swift",
            lambda text: text + "\nlet direct = URLSession.shared\n",
        ),
        "App/AppState.swift", "直接出网调用",
    )

    print("— 判定对象 = 代码出现：注释 / 字符串里的提及不算出现 —")
    case_green(
        "注释里的 `URLSession` 提及 ≠ 出现 → 绿（同 `Core/DataTaskSpecGenerator.swift:7` 的形态）",
        lambda tree: (tree / "Core/NetCommentProbe.swift").write_text(
            "import Foundation\n"
            "/// 负例：本类型里没有任何 URLSession / URLRequest —— 注释提及不算出现。\n"
            "// URLSession.shared 也只是注释里的字眼\n",
            encoding="utf-8",
        ),
    )
    case_green(
        "字符串字面量里的 `URLSession` 提及 ≠ 出现 → 绿",
        lambda tree: (tree / "Core/NetStringProbe.swift").write_text(
            "import Foundation\n"
            "let note = \"URLSession / URLRequest 只是字符串里的字眼\"\n",
            encoding="utf-8",
        ),
    )

    print("— 台账 ↔ 事实（漏登 / 陈旧 / 掏空令牌表）—")
    case_red(
        "台账漏登（把有出网出现的面文件从台账里删掉）→ 判红（漏登＝它有出现却不受约束）",
        lambda tree: edit_ledger(
            tree,
            lambda data: surface_files(data, "sync").clear(),
        ),
        "不在台账任何一面里",
    )
    case_red(
        "台账登记了盘上没有的文件 → 判红（声明与事实不符）",
        lambda tree: edit_ledger(
            tree,
            lambda data: surface_files(data, "sync").append("Core/NoteSync/Ghost.swift"),
        ),
        "磁盘上不存在",
    )
    case_red(
        "从令牌表删掉关键令牌 `URLRequest`（它仍被 `requiredTokens` 要求）→ 判红（删令牌＝把门禁改成永远通过）",
        lambda tree: edit_ledger(
            tree,
            lambda data: data.update({
                "tokens": [entry for entry in data["tokens"] if entry["token"] != "URLRequest"]
            }),
        ),
        "消失",
    )
    case_red(
        "关键令牌榜 `requiredTokens` 被掏空 → 判红（清空关键令牌榜＝把这条判据改成永远通过）",
        lambda tree: edit_ledger(
            tree,
            lambda data: data.update({"requiredTokens": []}),
        ),
        "掏空",
    )
    case_red(
        "令牌没写明理由 → 判红（说不清为什么禁它）",
        lambda tree: edit_ledger(
            tree,
            lambda data: data["tokens"].__setitem__(0, {"token": "URLSession", "reason": ""}),
        ),
        "没写明理由",
    )

    print("— 面钉与登记棘轮（原单 T-20261010-018 / T-20261010-040）：面 = **全仓**、登记不许抹 —")
    case_red(
        "台账把 `scan.scope` 改窄（改回产品源面）⇒ 判红（面钉⑦：一行台账缩不了面 · 原单 T-20261010-018）",
        lambda tree: edit_ledger(tree, lambda data: data["scan"].update({"scope": "product"})),
        "scan.scope", "不是 `repo`",
    )
    case_red(
        "把真源码目录塞进排除名单（`excludeDirs` 加 `CLI`）⇒ 判红（排除名单也有钉）",
        lambda tree: edit_ledger(tree, lambda data: data["scan"]["excludeDirs"].append("CLI")),
        "未登记", "CLI",
    )
    case_red(
        "排除名单的钉被掏空（`excludeDirsAllowed` 清空）⇒ 判红（排除名单没有钉）",
        lambda tree: edit_ledger(tree, lambda data: data["scan"].update({"excludeDirsAllowed": []})),
        "排除名单没有钉",
    )
    def drop_registration(tree):
        edit_ledger(tree, lambda data: data.update({
            "outOfFace": [e for e in data["outOfFace"] if e["file"] != "CLI/main.swift"]}))
        (tree / "CLI/main.swift").unlink()
    case_red(
        "登记被抹（删掉 `CLI/main.swift` 的登记 + 文件）⇒ 判红（前门令：**登记不许抹**）",
        drop_registration,
        "登记清单被抹",
    )
    case_red(
        "面外新出现未登记的出网文件（`CLI/EgressLeak.swift`）⇒ 判红点名（面外登记的只减不增棘轮）",
        lambda tree: (tree / "CLI/EgressLeak.swift").write_text(
            "import Foundation\nlet leak = URLSession.shared\n", encoding="utf-8"),
        "CLI/EgressLeak.swift", "不在登记清单",
    )
    case_green(
        "面外新增**非**出网文件（`CLI/Notes.swift` 无令牌）⇒ 仍绿（不许地毯式判红）",
        lambda tree: (tree / "CLI/Notes.swift").write_text(
            "import Foundation\nlet note = 1\n", encoding="utf-8"),
    )
    case_red(
        "面外登记被掏空（`outOfFace` 清空）⇒ 判红（零登记不许当通过）",
        lambda tree: edit_ledger(tree, lambda data: data.update({"outOfFace": []})),
        "零登记不许当通过",
    )
    case_red(
        "已登记文件现在一处令牌都不出现（陈旧登记）⇒ 判红",
        lambda tree: edit(
            tree, "CLI/main.swift",
            lambda text: "import Foundation\nlet clean = 1\n",
        ),
        "陈旧登记",
    )
    case_red(
        "面外登记指到盘上没有的文件 ⇒ 判红（死登记不许留着）",
        lambda tree: edit_ledger(tree, lambda data: data["outOfFace"][0].update(
            {"file": "CLI/Ghost.swift"})),
        "CLI/Ghost.swift", "磁盘上不存在",
    )
    case_red(
        "全仓扫描面被削到下限以下 ⇒ 判红（空跑防护：911 那个下限真会响）",
        lambda tree: edit_ledger(tree, lambda data: data["floors"].update(
            {"minFilesScanned": data["floors"]["minFilesScanned"] + 50})),
        "扫描面只有",
    )

    print("— 接线：门禁必须在闭环里真的被调用 —")
    case_red(
        "从 verify-all.sh 删掉本门禁的调用 → 判红（存在但没接线＝红不起来）",
        lambda tree: edit(
            tree, "Scripts/verify-all.sh",
            lambda text: text.replace("check-network-egress.py", ""),
        ),
        "没有本门禁",
    )

    print("— 真仓台账的静态臂（面钉 / 排除名单钉 / 登记不得回退）—")
    real_ledger = json.loads((ROOT / LEDGER).read_text(encoding="utf-8"))
    real_scan = real_ledger.get("scan") or {}
    real_floors = real_ledger.get("floors") or {}
    real_floor = real_floors.get("minFilesScanned") or 0
    record(real_floor >= 900, "真仓 `floors.minFilesScanned` ≥ 900（全仓面钉不得回退）", f"实际 {real_floor}")
    record((real_scan.get("scope") or "") == "repo",
           "真仓 `scan.scope` == `repo`（声明 = 全仓，不得改窄）", f"实际 {real_scan.get('scope')!r}")
    record(len(real_scan.get("excludeDirsAllowed") or []) >= 5,
           "真仓 `scan.excludeDirsAllowed` ≥ 5 项（排除名单有钉）",
           f"实际 {real_scan.get('excludeDirsAllowed')}")
    real_reg_floor = real_floors.get("minRegisteredEgress") or 0
    record(real_reg_floor >= 10, "真仓 `floors.minRegisteredEgress` ≥ 10（**登记不许抹**）", f"实际 {real_reg_floor}")
    real_out = {entry.get("file") for entry in (real_ledger.get("outOfFace") or [])}
    record({"CLI/main.swift", "Platform/macOS/WebKitBrowserEngine.swift"} <= real_out,
           "真仓 `outOfFace` 仍登记着两处生产面外活体（不得删已知缺口）", f"实际 {sorted(real_out)}")

    print("— 末条：真仓库一个字节没动 —")
    after = snapshot()
    changed = [rel for rel in before if before[rel] != after.get(rel)]
    record(not changed, "写坏只发生在副本上，真仓库未被改动", "；".join(changed))

    print(f"\n结果：{len(passed)} 项达到预期，{len(failed)} 项不符")
    if failed:
        print("未达到预期的：")
        for label in failed:
            print(f"  · {label}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
