#!/usr/bin/env python3
"""负例执行器 —— 证明每条【机判】条文真的会拦；拦不了的要**明写为什么**。

为什么要有它：条文里写的「负例：… ⇒ 必须判红」只是**声称**。铁律 #14 要求的是
「故意违规时它真的变红」。本脚本把声称变成实测：就地制造违规 → 跑对应判据 → 断言 rc != 0
→ 无论成败都还原文件（字节级备份 + finally 还原 + 还原后校验 sha256）。

处置模型（2026-11-10 第二轮，覆盖到「未处置 = 0」）
--------------------------------------------------
每条带【机判】的条文，三选一，**没有第四种**：

  ① **实测红**（`CASES`）：文件层造得出违规、对应判据真的从绿变红；
  ② **处置登记**（`Scripts/rule-negative-dispositions.json`）：造不出文件层负例，必须写清为什么 ——
     `needs-build`（违约只能在真实构建 / 全量门禁里发生）· `baseline-red`（判据当前本身就红，附实测
     rc 与原因）· `wrong-gate`（条文指的判据根本不核对这件事，已在条文里改正）·
     `unsupported`（其他不可在文件层复现的情形）；
  ③ **改正后已不是机判**（登记里 `now` 非空）：原文标的【机判】经实测**没有任何脚本**核这件事，
     已把条文改成【人判】—— 这一条不再是机判条文，单独报数，不混进「实测红」。

复跑三读数（口径写死在这里，不许口头改）：
  实测红 N = `CASES` 里真的从绿变红的条数（每条都必须红，一条不红即 rc=1）；
  明示不可在文件层复现 M = 处置登记里**仍属机判**的条数（按类别分组打印）；
  未处置 K = 【机判】条文里既没有用例、也没有处置登记的条数 —— **K 必须为 0**。

用例的 `key` 是条文标题的**前缀**（唯一匹配，冲突即报错）：条文标题改字不炸用例，
但标题被大改会立刻暴露成「用例指向不存在的条文」。

只覆盖「文件类」判据：需要构建 / 真机 / 网络才能复现的违规一律进处置登记，不写假用例。
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile

# shared-surface：2026-11-10 负例覆盖轮 · 本条把「每条机判条文都有处置」变成可跑的读数
ROOT = pathlib.Path(__file__).resolve().parent.parent
# 假密钥：运行时拼接，源码里不允许出现完整形态（否则本文件自己就被 check-no-user-data 判红 —— 已踩过）
FAKE_KEY = "s" + "k" + "-" + "a" * 40
PY = sys.executable
DISPOSITIONS = ROOT / "Scripts" / "rule-negative-dispositions.json"
CATEGORIES = ("needs-build", "baseline-red", "wrong-gate", "unsupported")

PRODUCT_DESIGN = "Docs/Doyah产品概要设计说明书.md"      # 记号：共享面 / 契约层判据都用它
SRS = "Docs/Doyah产品需求规格说明书.md"
PLAN = "Docs/Doyah产品开发计划任务清单-macOS.md"
PM = "Docs/项目管理规范.md"
GENERAL = "Docs/通用开发规范.md"

# 契约层锁定用的判据参数：以对侧（windows）身份改概设 ⇒ 越界必须判红
EXCLUSIVE_ARGS = ("--mine", "windows", "--files", PRODUCT_DESIGN)
HARMONY = "Docs/Doyah产品详细设计说明书-HarmonyOS.md"   # 2026-11-10 按安卓基准派生（9/9）
WINDOWS = "Docs/Doyah产品详细设计说明书-Windows.md"     # 按 macOS 基准派生（40/40）
# 「开工先看工作区」那一条要用 diff 通道：`check-path-ownership.py` 的改动集默认取 `git diff <base>`，
# 而本轮自身对 `Scripts/*.json` 的改动**没法在 JSON 里注 `shared-surface：理由`**（JSON 没有注释语法），
# 于是全量基线里那一条永远是红的 —— 那样就分不清「负例拦下」还是「本来就红」。改用脚本自带的
# `--diff-file` 通道：基线喂空 diff（无内容可查 ⇒ rc=0），违规喂**真实改动**渲染出的 diff（rc=1）。
# diff 文件落临时目录（TMPDIR），不写进仓。
_DIFF_TMP = pathlib.Path(tempfile.mkdtemp(prefix="rule-neg-"))
EMPTY_DIFF = _DIFF_TMP / "empty.diff"
EMPTY_DIFF.write_text("", encoding="utf-8")
SIDE_TREE_DIFF = _DIFF_TMP / "side-tree.diff"

# 契约节表格锚点（概设 §3 组件契约；无 `[独占:*]` 标记 ⇒ 契约层）
CONTRACT_TABLE_HEAD = "| 组件 | 必须做 | 禁止做 | 依赖 | 对外暴露 |\n"
CONTRACT_ROW = "| 负例造出来的组件 | 越界 | 越界 | 越界 | 越界 |"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def run(script: str, *args: str) -> int:
    return subprocess.run([PY, str(ROOT / "Scripts" / script), *args],
                          cwd=ROOT, capture_output=True, text=True).returncode


# ── 违规动作 ────────────────────────────────────────────────────────────────
def violate_status_word(ctx) -> None:
    ctx.patch(PM, "| Notes 安卓端开工前置 | ⏳ 待提供 |", "| Notes 安卓端开工前置 | 讨论中 |")


def violate_doc_version_row(ctx) -> None:
    """头部与「文档版本」行必须同值：只改后者即红。

    刻意**不碰** `Docs/Doyah产品详细设计说明书-Linux.md` —— 那一份正由对侧在改，
    临时改写再还原会踩到别人的在途改动（2026-11-10 从 Linux 详设改为概设）。
    """
    ctx.regex(PRODUCT_DESIGN, r"- 文档版本：v\d+\.\d+\.\d+（头部版本同步）",
              "- 文档版本：v1.2.1（头部版本同步）")


def violate_extra_doc(ctx) -> None:
    ctx.create("Docs/Doyah产品测试台账.md", "# 多余的书\n\n本文件不该存在。\n")


def violate_bad_req_id(ctx) -> None:
    """形制错 = 产品码不在 registry（`FR-ZZZ-…`）。`FR-STD-05` 属冻结三段老号，规范明写不迁移，不算违规。"""
    ctx.patch(SRS, "\n## ", "\n| `FR-ZZZ-DB-DRV-005` | 产品码不存在的编号 | 应判红 |\n\n## ")


def violate_doc_numbers(ctx) -> None:
    """改台账里的权威值（`numbers` 是**列表**，每条 {key,label,value,measure}）。

    改一条 value 即与实测/文档双向对不上 —— 这是 `check-doc-numbers` 的立身之本。
    """
    p = ROOT / "Scripts" / "doc-numbers.json"
    data = json.loads(p.read_text(encoding="utf-8"))
    target = next(n for n in data["numbers"]
                  if isinstance(n.get("value"), int) and isinstance(n.get("measure"), dict))
    target["value"] = target["value"] + 1          # 只动 +1，保证原值是整数且必然对不上
    ctx.write("Scripts/doc-numbers.json", json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def violate_handover_count(ctx) -> None:
    """交接三件里的 `core-tests` 写死成 5000（实测由 `swift test` 复算，必然对不上）。"""
    p = ROOT / "Scripts" / "doc-numbers.json"
    data = json.loads(p.read_text(encoding="utf-8"))
    target = next(n for n in data["numbers"] if n.get("key") == "core-tests")
    target["value"] = 5000
    ctx.write("Scripts/doc-numbers.json", json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def violate_bare_clause(ctx) -> None:
    ctx.write(GENERAL,
              (ROOT / GENERAL).read_text(encoding="utf-8").rstrip("\n")
              + "\n\n- **裸条文（无负例）**：只写了判据的条文，必须被判红。判据：评审。\n")


def violate_missing_negative_field(ctx) -> None:
    """六字段里只缺「负例」：条文仍带判据，但缺字段数 +1。"""
    ctx.patch(GENERAL, "## 2 三书一单",
              "- **缺负例字段的条文**：这条故意不写负例字段，必须判红。\n"
              "- **判据**：【机判】`true`。\n"
              "- **读数口径**：无。\n- **归属**：本节。\n\n## 2 三书一单")


def violate_extra_end_sheet(ctx) -> None:
    ctx.create("Docs/Doyah产品开发计划任务清单-Windows.md", "# 多余的一单\n\n未开发端不该有一单。\n")


def violate_unknown_end_sheet(ctx) -> None:
    """`ALLOWED_SHEETS` 只有六端 ⇒ 建一份野端的单即「不属于允许的端」。"""
    ctx.create("Docs/Doyah产品开发计划任务清单-Web端.md", "# 野端一单\n\n端不在允许清单里。\n")


def violate_foreign_design_ref(ctx) -> None:
    """一单头部只许认同端详设：多引一本别端详设即红。"""
    ctx.patch(PLAN, "（`Docs/Doyah产品详细设计说明书-macOS.md`）",
              "（`Docs/Doyah产品详细设计说明书-macOS.md`）；对照《Doyah产品详细设计说明书-Linux.md》")


def violate_internal_ip(ctx) -> None:
    """凭据类才是判红（内网地址在该脚本里只到「提示」级）。

    必须写进**已被跟踪**的文件：`check-no-user-data` 扫的是 `git ls-files`。
    """
    ctx.write(PRODUCT_DESIGN,
              (ROOT / PRODUCT_DESIGN).read_text(encoding="utf-8").rstrip("\n")
              + "\n\n- 示例密钥：`" + FAKE_KEY + "`（不该出现在 PUBLIC 仓）\n")


def violate_frozen_edit(ctx) -> None:
    frozen = sorted((ROOT / "Docs" / "frozen").glob("*v1.3*.md"))
    assert frozen, "找不到 v1.3 冻结件"
    p = frozen[0]
    text = p.read_text(encoding="utf-8")
    ctx.write(p.relative_to(ROOT).as_posix(), text.replace("## ", "### 手改痕迹 ## ", 1))


def violate_bold_heading(ctx) -> None:
    ctx.write(PM, (ROOT / PM).read_text(encoding="utf-8").rstrip("\n")
              + "\n\n### 带**加粗**的标题\n\n标题里不许有加粗。\n")


def violate_dup_q(ctx) -> None:
    """编号唯一：把 Q37 行复制一份（同号两行）。"""
    t = (ROOT / PM).read_text(encoding="utf-8")
    line = next(l for l in t.split("\n") if l.startswith("| **Q37**"))
    ctx.write(PM, t.replace(line, line + "\n" + line, 1))


def violate_version_regress(ctx) -> None:
    """冻结 = 升一段 ⇒ 版本号不许回退到更早的段。"""
    ctx.regex(PM, r"> \*\*版本\*\* v\d+\.\d+\.\d+", "> **版本** v0.9.99")


def violate_flow_over_999(ctx) -> None:
    """流水段上限 999：写到 1000 必须判红（该段先冻结再转下一段）。"""
    ctx.regex(PM, r"> \*\*版本\*\* v\d+\.\d+\.\d+", "> **版本** v1.0.1000")


def violate_version_downgrade(ctx) -> None:
    """并发写版本号：凭记忆写一个更小的号 = 降号，必须判红。"""
    ctx.regex(PM, r"> \*\*版本\*\* v\d+\.\d+\.\d+", "> **版本** v1.0.5")


def violate_changelog(ctx) -> None:
    """不许有「变更记录」文件。"""
    ctx.create("Docs/变更记录.md", "# 变更记录\n\n不许有这个文件。\n")


def violate_end_sheet_snapshot(ctx) -> None:
    """一单永远只有一份活件：给同一端再建一份带版本号的快照。"""
    ctx.create("Docs/Doyah产品开发计划任务清单-macOS-v1.2.md", "# 一单快照\n\n不许有。\n")


def violate_release_label(ctx) -> None:
    """包标签 = 出包序号：台账标签与 `build-app.sh` 的 RELEASE_LABEL 不一致即红。"""
    p = ROOT / "Scripts" / "release-version.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d["releaseLabel"] = "beta9.9"
    ctx.write("Scripts/release-version.json", json.dumps(d, ensure_ascii=False, indent=2) + "\n")


def violate_freeze_parity(ctx) -> None:
    """冻结号 = 软件号：台账 marketingVersion 与最新冻结段不符即红。"""
    p = ROOT / "Scripts" / "release-version.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d["marketingVersion"] = "1.9.9"
    ctx.write("Scripts/release-version.json", json.dumps(d, ensure_ascii=False, indent=2) + "\n")


def violate_linux_sync(ctx) -> None:
    """macOS 冻结 ⇒ 同日同步 Linux：拿掉同日那份 Linux 冻结件。"""
    cands = sorted((ROOT / "Docs" / "frozen").glob("*-Linux-v1.3-*.md"))
    assert cands, "没有 Linux v1.3 冻结件"
    ctx.move(cands[-1])


def violate_button_text(ctx) -> None:
    """按钮图标化：水平按钮条里塞一个**文字按钮**、且不登记例外 ⇒ 判据 C + 未登记差异双红。

    造在 `AgentWorkspaceSection` 那条 HStack 里（真界面的按钮条），不是造一个没人用的样例。
    """
    ctx.patch("App/Views/AgentWorkspaceSection.swift",
              "            HStack(spacing: Spacing.s) {\n",
              "            HStack(spacing: Spacing.s) {\n                Button(L(.commonOk)) { }\n")


def violate_fascicle_stale(ctx) -> None:
    """分册只继承、不自造：**全量书改了、分册没重裁** ⇒ 分册那行在全量里找不到即红。

    造的是真事故的形态（本轮 128 行的成因），不是往分册里塞野编号：从需求书删掉一行，
    分册里那一行立刻成了「自造」。**不去写 `../notes`** —— 那个仓的改动不该由用例承担，
    临时改写再还原也会踩到别人正在编辑的文件。
    """
    ctx.patch(SRS, "- 在（类型 · 产品 · 面 · 域）四元组内从 1 开始递增，**全局唯一**。\n", "")


def violate_derivation_declaration(ctx) -> None:
    """平台详设必须写明「派生自 <基准> 详设 vX」：拿掉鸿蒙详设的那一行即红。"""
    text = (ROOT / HARMONY).read_text(encoding="utf-8")
    line = next(l for l in text.split("\n") if l.startswith("> **派生自**"))
    ctx.patch(HARMONY, line, "> 本文件为鸿蒙端独立编写，不派生自任何基准。")


def violate_derivation_row(ctx) -> None:
    """逐节表态：拿掉 Windows 详设 §0.2 的一行（§3.1）⇒ 39/40 即红。"""
    ctx.patch(WINDOWS, "| `§3.1` | 沿用 | 同源 Rust 连接层（`Db`）就在本端，Windows 是它的宿主 |\n", "")


def violate_side_tree(ctx) -> None:
    """开工先看工作区：改动落在**对侧子树**（Windows 端）即红。

    真改文件 → 把 `git diff` 渲染成 `--diff-file`（见文件头 `_DIFF_TMP` 的说明）。
    """
    victim = "platform/windows/App/README.md"
    ctx.write(victim, (ROOT / victim).read_text(encoding="utf-8").rstrip("\n")
              + "\n\n本轮从对侧手改这一行（负例）。\n")
    diff = subprocess.run(["git", "-c", "core.quotepath=false", "diff", "--unified=0", "--", victim],
                          cwd=ROOT, capture_output=True, text=True).stdout
    assert victim in diff, "取不到对侧文件的 diff"
    SIDE_TREE_DIFF.write_text(diff, encoding="utf-8")


def violate_status_annotation(ctx) -> None:
    """一条拍板只落一处：在别的册子里写「编号（⬜）」而台账是 ✅ ⇒ 红。"""
    ctx.patch(PRODUCT_DESIGN, "## 1. 设计范围与边界\n",
              "## 1. 设计范围与边界\n\n构建工程那条 FR-STD-ALL-BLD-001（⬜）还没做。\n")


def violate_selftest_count(ctx) -> None:
    """每条判据配负例：台账里的例数与实跑/锚点对不上即红（`--no-run` 只做台账与锚点对账）。"""
    p = ROOT / "Scripts" / "self-test-counts.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    fam = next(f for f in d["families"] if f["key"] == "doc-versions")
    fam["cases"] = fam["cases"] + 1
    ctx.write("Scripts/self-test-counts.json", json.dumps(d, ensure_ascii=False, indent=2) + "\n")


def violate_platform_impl_in_srs(ctx) -> None:
    """PC 一体化：端专属实现写进**需求书严格档**（§1.3 正文）即红。"""
    ctx.patch(SRS, "## 1.3 术语与缩略语\n",
              "## 1.3 术语与缩略语\n\nNotes 移动端用 SwiftUI 实现，iOS 侧用 AppKit 兜底。\n")


def violate_ledger_extra_id(ctx) -> None:
    """一单是唯一进度源：台账多一条需求书索引没有的编号 ⇒ 红（多方向覆盖两个都判）。"""
    head = ("| 编号 | 一句话 | 领域 | 层次 | 优先级 | 状态 | 状态原值 | 版本 | 版本口径 |\n"
            "|---|---|---|---|---|---|---|---|---|\n")
    ctx.patch(PLAN, head, head + "| FR-STD-DB-DRV-014 | 负例造出来的假需求 | DB | L2 | P1 | ⬜ | ⬜ | v1.1+ | 排期 |\n")


def violate_doc_root_release_plan(ctx) -> None:
    ctx.create("Docs/发布方案.md", "# 发布方案\n\n过程件不许放根上。\n")


def violate_doc_root_matrix(ctx) -> None:
    ctx.create("Docs/平台矩阵.md", "# 平台矩阵\n\n派生件不许放根上。\n")


def violate_risk_as_req(ctx) -> None:
    """风险不是需求：`NFR-STD-RISK-001` 不是五段式（域码 RISK 也没登记）⇒ 红。"""
    ctx.patch(SRS, "## 1.6 维护约定",
              "| NFR-STD-RISK-001 | 风险冒充需求 | 应判红 |\n\n## 1.6 维护约定")


def violate_req_index_drift(ctx) -> None:
    """新需求落齐派生出口：正文加一行而机器视图不重生成 ⇒ 红。"""
    head = "| 编号 | 需求 | 判据 | 不做 | 层次 | 优先级 |\n| --- | --- | --- | --- | --- | --- |\n"
    ctx.patch(SRS, head, head + "| FR-STD-DB-DRV-014 | **负例造出来的假需求**：正文加了索引没跟 | 判据待补 | 不是真需求 | 常用增强 | 中 |\n")


def violate_contract_layer(ctx) -> None:
    """契约层锁定：以对侧身份往契约节加一行（不带 `contract-change：理由`）。"""
    ctx.patch(PRODUCT_DESIGN, CONTRACT_TABLE_HEAD, CONTRACT_TABLE_HEAD + CONTRACT_ROW + "\n")


def violate_notes_clause_in_studio(ctx) -> None:
    """能力变 → 跟 Notes 契约：把笔记能力条款直接写进 Studio 概设 §15 契约节。"""
    ctx.patch(PRODUCT_DESIGN, "### 15.1 【契约】快速捕获",
              "### 15.1 【契约】快速捕获\n\n从 Windows 侧直接加一条笔记能力条款。")


def violate_allow_marker_pair(ctx) -> None:
    """主人直接指令 > 定稿权：**成对**证明「标记就是那个开关」。

    ① 同样的越界 + `contract-change：理由` ⇒ 必须**放行**（逃生门在位）；
    ② 把标记摘掉 ⇒ 必须判红。两步都做，只证一半等于没证。
    """
    text = (ROOT / PRODUCT_DESIGN).read_text(encoding="utf-8")
    marked = text.replace(CONTRACT_TABLE_HEAD,
                          CONTRACT_TABLE_HEAD + CONTRACT_ROW + " <!-- contract-change：负例对照（带标记应放行） -->\n", 1)
    ctx.write(PRODUCT_DESIGN, marked)
    if run("check-exclusive-sections.py", *EXCLUSIVE_ARGS) != 0:
        raise AssertionError("带 contract-change 标记的越界本应放行 —— 逃生门没生效")
    ctx.write(PRODUCT_DESIGN, text.replace(CONTRACT_TABLE_HEAD, CONTRACT_TABLE_HEAD + CONTRACT_ROW + "\n", 1))


def violate_doc_gate_skipped(ctx) -> None:
    """文档改动必过门禁：造一条文档违规（Q37 同号两行），看**入场判据**会不会把它拦下来。

    2026-11-10 之前这条是 needs-build（理由：跑没跑门禁是执行行为）—— 实测发现不对：
    `action-router --changed --check --fast` 本身就是文件层的入场判据，违规造得出来。
    （顺带修出它自己的洞：原实现只看暂存区，暂存两个脚本就丢掉未暂存的文档改动 ⇒ 这里造得出而它 rc=0。）
    """
    t = (ROOT / PM).read_text(encoding="utf-8")
    line = next(l for l in t.split("\n") if l.startswith("| **Q37**"))
    ctx.write(PM, t.replace(line, line + "\n" + line, 1))


CASES = [
    ("文档改动必过门禁",               "action-router.py",             violate_doc_gate_skipped, ("--changed", "--check", "--fast")),
    ("状态只写词表词",                "check-queue-needs-user.py",   violate_status_word, ()),
    ("版本只写头部",                  "check-doc-versions.py",       violate_doc_version_row, ()),
    ("不擅自扩大文档体系",             "check-doc-invariants.py",     violate_extra_doc, ()),
    ("编号形制五段式",                "check-req-ids.py",            violate_bad_req_id, ("--all",)),
    ("数字与路径都不写死",             "check-doc-numbers.py",        violate_doc_numbers, ()),
    ("存量条文允许暂缺字段",           "check-rule-schema.py",        violate_bare_clause, ()),
    ("编号唯一",                     "check-doc-versions.py",       violate_dup_q, ()),
    ("冻结 = 升一段",                 "check-doc-versions.py",       violate_version_regress, ()),
    ("不许有「变更记录」文件",          "check-doc-versions.py",       violate_changelog, ()),
    ("一单永远只有一份活件",            "check-end-sheets.py",         violate_end_sheet_snapshot, ()),
    ("冻结号 = 软件号",                "check-release-freeze-parity.py", violate_freeze_parity, ()),
    ("公开仓不留凭据",            "check-no-user-data.py",       violate_internal_ip, ()),
    ("冻结件只能冻结",                 "check-frozen-sync.py",        violate_frozen_edit, ()),
    # ── 第二轮新增（2026-11-10）────────────────────────────────────────────
    ("开工先看工作区",                "check-path-ownership.py",     violate_side_tree,
     ("--diff-file", str(SIDE_TREE_DIFF)), ("--diff-file", str(EMPTY_DIFF))),
    ("一条拍板只落一处结论",           "check-status-consistency.py", violate_status_annotation, ()),
    ("每条判据配一条",                "check-self-test-counts.py",   violate_selftest_count, ("--no-run",)),
    ("PC 一体化",                     "check-platform-neutrality.py", violate_platform_impl_in_srs, ()),
    ("一单只给正在开发的端建",          "check-end-sheets.py",         violate_unknown_end_sheet, ()),
    ("一单与详设同构",                "check-end-sheets.py",         violate_foreign_design_ref, ()),
    ("一单是唯一进度源",               "check-plan-coverage.py",      violate_ledger_extra_id, ()),
    ("`Docs/` 根只许三书",            "check-doc-invariants.py",     violate_doc_root_release_plan, ()),
    ("跨端视图不是书",                "check-doc-invariants.py",     violate_doc_root_matrix, ()),
    ("风险不是需求",                  "check-req-ids.py",            violate_risk_as_req, ()),
    ("新需求登记一次性落齐派生出口",     "check-req-index.py",          violate_req_index_drift, ()),
    ("负例（本条自己也要有）",          "check-rule-schema.py",        violate_missing_negative_field, ()),
    ("每轮交接三件",                  "check-doc-numbers.py",        violate_handover_count, ()),
    ("契约层锁定",                    "check-exclusive-sections.py", violate_contract_layer, EXCLUSIVE_ARGS),
    ("能力变 → 跟 Notes 的能力契约",    "check-exclusive-sections.py", violate_notes_clause_in_studio, EXCLUSIVE_ARGS),
    ("主人直接指令",                  "check-exclusive-sections.py", violate_allow_marker_pair, EXCLUSIVE_ARGS),
    ("自动冻结",                      "check-doc-versions.py",       violate_flow_over_999, ()),
    ("并发写版本号先重读文件",          "check-doc-versions.py",       violate_version_downgrade, ()),
    ("端详设从本族基准派生",      "check-platform-derivation.py", violate_derivation_declaration, ()),
    ("macOS 冻结 ⇒ 同日同步 Linux",     "check-platform-derivation.py", violate_derivation_row, ()),
    ("包标签 = 出包序号",               "check-release-version.py",    violate_release_label, ()),
    ("分册的需求书与概设不许按端拆",      "check-book-subset.py",        violate_fascicle_stale, ()),
    ("归口改判必须落判据例外台账",        "check-button-icon-only.py",   violate_button_text, ()),
]


class Ctx:
    """字节级备份 + finally 还原。"""

    def __init__(self) -> None:
        self.backup: dict[pathlib.Path, bytes] = {}
        self.created: list[pathlib.Path] = []
        self.moved: list[tuple[pathlib.Path, pathlib.Path]] = []

    def _remember(self, path: pathlib.Path) -> None:
        if path not in self.backup and path.exists():
            self.backup[path] = path.read_bytes()

    def patch(self, rel: str, old: str, new: str) -> None:
        p = ROOT / rel
        self._remember(p)
        text = p.read_text(encoding="utf-8")
        assert old in text, f"{rel} 里找不到要替换的片段：{old[:40]}"
        p.write_text(text.replace(old, new, 1), encoding="utf-8")

    def regex(self, rel: str, pattern: str, repl: str) -> None:
        """按正则替换首处：版本号那类「每次改动都会变」的锚点用它，免得用例跟着版本漂。"""
        p = ROOT / rel
        self._remember(p)
        text = p.read_text(encoding="utf-8")
        new_text, hits = re.subn(pattern, repl, text, count=1)
        assert hits == 1, f"{rel} 里匹配不到正则：{pattern}"
        p.write_text(new_text, encoding="utf-8")

    def write(self, rel: str, text: str) -> None:
        p = ROOT / rel
        self._remember(p)
        p.write_text(text, encoding="utf-8")

    def move(self, path: pathlib.Path) -> None:
        """把文件挪到 scratch（删除类违规），还原时挪回。"""
        tmp = pathlib.Path("/tmp") / ("neg_move_" + path.name)
        path.rename(tmp)
        self.moved.append((path, tmp))

    def create(self, rel: str, text: str) -> None:
        p = ROOT / rel
        assert not p.exists(), f"{rel} 已存在，不能当负例"
        p.write_text(text, encoding="utf-8")
        self.created.append(p)

    def restore(self) -> list[str]:
        bad = []
        for p, raw in self.backup.items():
            before = sha(p) if p.exists() else None
            p.write_bytes(raw)
            if sha(p) != hashlib.sha256(raw).hexdigest()[:16] or before is None and not p.exists():
                bad.append(str(p))
        for p in self.created:
            if p.exists():
                p.unlink()
        for orig, tmp in self.moved:
            if tmp.exists():
                tmp.replace(orig)
        return bad


def clauses() -> list[tuple[str, str, bool]]:
    """复用 check-rule-schema 的切条逻辑（口径必须一致）：[(title, book, is_machine)]。"""
    import importlib.util

    spec_path = ROOT / "Scripts" / "check-rule-schema.py"
    spec = importlib.util.spec_from_file_location("rule_schema_mod", spec_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    schema = json.loads((ROOT / "Scripts" / "rule-schema.json").read_text(encoding="utf-8"))
    names = set(schema["字段"].keys())
    out: list[tuple[str, str, bool]] = []
    for book in ("通用开发规范.md", "项目管理规范.md"):
        text = (ROOT / "Docs" / book).read_text(encoding="utf-8")
        for title, body in mod.split_clauses(text, names):
            out.append((title, book, "【机判】" in body))
    return out


def resolve(key: str, all_clauses: list[tuple[str, str, bool]]) -> tuple[str, str, bool]:
    """key = 标题前缀；必须唯一命中（0 个 = 条文被改名/删了；多于 1 个 = key 太短）。"""
    hits = [c for c in all_clauses if c[0].startswith(key)]
    if len(hits) != 1:
        raise LookupError(f"「{key}」命中 {len(hits)} 条条文（需恰好 1 条）：{[h[0] for h in hits]}")
    return hits[0]


def load_dispositions() -> list[dict]:
    data = json.loads(DISPOSITIONS.read_text(encoding="utf-8"))
    entries = data["entries"]
    for entry in entries:
        if entry.get("category") not in CATEGORIES:
            raise ValueError(f"处置类别不合法：{entry.get('clause')} → {entry.get('category')}")
        if not entry.get("reason", "").strip():
            raise ValueError(f"处置缺理由：{entry.get('clause')}")
        if entry["category"] in ("baseline-red", "wrong-gate") and not entry.get("evidence", "").strip():
            raise ValueError(f"{entry['category']} 必须附实测证据：{entry.get('clause')}")
    return entries


def main() -> int:
    all_clauses = clauses()
    machine = [c for c in all_clauses if c[2]]
    problems: list[str] = []

    case_titles: dict[str, str] = {}
    for case in CASES:
        key = case[0]
        try:
            title = resolve(key, all_clauses)[0]
        except LookupError as exc:
            problems.append(f"用例指向不存在的条文：{exc}")
            continue
        if title in case_titles:
            problems.append(f"条文「{title}」被两个用例重复登记（{case_titles[title]} / {key}）")
        case_titles[title] = key

    entries = load_dispositions()
    dispo_titles: dict[str, dict] = {}
    for entry in entries:
        try:
            title, book, is_machine = resolve(entry["clause"], all_clauses)
        except LookupError as exc:
            problems.append(f"处置指向不存在的条文：{exc}")
            continue
        if entry.get("book") and entry["book"] != book:
            problems.append(f"处置登记的书不对：{entry['clause']} 写 {entry['book']}，实际 {book}")
        if title in dispo_titles:
            problems.append(f"条文「{title}」被两条处置重复登记")
        if not is_machine and not entry.get("now"):
            problems.append(f"条文「{title}」已不是【机判】，处置须写 `now`（改成什么了）：{entry['clause']}")
        if title in case_titles:
            problems.append(f"条文「{title}」既在用例里又在处置里 —— 二者只能选一个")
        dispo_titles[title] = entry

    unhandled = [c[0] for c in machine if c[0] not in case_titles and c[0] not in dispo_titles]
    by_cat = {c: [t for t, e in dispo_titles.items() if e["category"] == c and by_machine(t, machine)]
              for c in CATEGORIES}
    reclassified = [t for t, e in dispo_titles.items() if not by_machine(t, machine)]

    print(f"负例实测（文件类）：用例 {len(CASES)} 条 / 处置登记 {len(entries)} 条"
          f"（其中仍属机判 {len(entries) - len(reclassified)} 条 / 改人判 {len(reclassified)} 条）"
          f" / 【机判】条文共 {len(machine)} 条\n")

    ok, failed, errors, blocked = [], [], [], []
    for case in CASES:
        # 用例 = (key, 判据脚本, 违规动作, 违规时参数[, 基线参数]) —— 基线参数缺省 = 同违规参数
        key, script, action, args = case[:4]
        base_args = case[4] if len(case) > 4 else args
        base = run(script, *base_args)
        label = key
        if base != 0:
            blocked.append(f"{key}（{script} 基线本红 rc={base}）")
            print(f"  ⏸ {label:26} {script:28} 基线本红 rc={base} —— 判不了负例，应改为 baseline-red 处置")
            continue
        ctx = Ctx()
        try:
            action(ctx)
            rc = run(script, *args)
        except Exception as exc:                                    # noqa: BLE001
            rc, note = None, f"{type(exc).__name__}: {exc}"
        else:
            note = ""
        finally:
            bad = ctx.restore()
        if bad:
            print(f"  ❗ {label:26} 还原失败，已中止：{bad}")
            return 2
        if rc is None:
            errors.append(f"{key}: 违规动作失败（{note}）")
            print(f"  ⚠️  {label:26} 造不出违规：{note[:60]}")
        elif rc != 0:
            ok.append(key)
            print(f"  ✓ {label:26} {script:28} 实测红（rc={rc}）")
        else:
            failed.append(key)
            print(f"  ✗ {label:26} {script:28} **声称会红，实际 rc=0 —— 判据失灵**")

    print()
    print(f"实测红 {len(ok)} / 登记 {len(CASES)}（用例）")
    print(f"明示不可在文件层复现 {sum(len(v) for v in by_cat.values())}"
          f"（needs-build {len(by_cat['needs-build'])} · baseline-red {len(by_cat['baseline-red'])} ·"
          f" wrong-gate {len(by_cat['wrong-gate'])} · unsupported {len(by_cat['unsupported'])}）")
    print(f"未处置 {len(unhandled)}")
    if reclassified:
        print(f"另：{len(reclassified)} 条指错门已改【人判】（不再计入机判）：")
        for t in reclassified:
            print("   ·", t)
    print(f"合计：【机判】{len(machine)} 条 = 实测红 {len(ok)} + 明示不可复现 {sum(len(v) for v in by_cat.values())}"
          f"；另 {len(reclassified)} 条原【机判】经实测无门可指，已改【人判】（连同机判条文共 {len(machine) + len(reclassified)} 条可逐一追溯）")
    if unhandled:
        print("  未处置条文（不当作通过）：")
        for t in unhandled:
            print("   ·", t)
    if blocked:
        print(f"  ⏸ 基线本红 {len(blocked)} 条（应改处置登记）：")
        for b in blocked:
            print("   ·", b)
    if problems:
        print("❌ 登记本身有问题：")
        for p in problems:
            print("   ·", p)
    if failed:
        print(f"❌ 失灵 {len(failed)} 条：{' / '.join(failed)}")
    if failed or errors or blocked or unhandled or problems:
        print("❌ 负例实测未通过")
        return 1
    print("✅ 每条【机判】条文都有处置：用例全部实测判红，造不出负例的逐条写明原因（未处置 0）")
    return 0


def by_machine(title: str, machine: list[tuple[str, str, bool]]) -> bool:
    return any(c[0] == title for c in machine)


if __name__ == "__main__":
    sys.exit(main())
