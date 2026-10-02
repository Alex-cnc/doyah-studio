#!/usr/bin/env python3
"""校验 Docs/ 下所有 Markdown 表格的列数一致性，以及需求计数的一致性。

背景：本工程的文档表格由脚本增量修改，历史上出现过两类漂移：

1. 「两行被合并成一行」（`| ... || ... |`）导致表格错位；
2. **需求计数没有跟着条目走** —— §10.1 表头长期停在 v3.2 生成时的 `207`，
   而索引实际已经 213 行；《产品能力规划说明书》的能力地图也落后一条
   （FR-EDIT-31 归档未计入）。两者都是"手工维护的数字"，必然漂移。

因此本脚本每次修改文档后运行，确保：

1. 每张表的表头、分隔行、数据行列数一致；
2. 表格内没有 `||`（列之间缺少空格 / 行被拼接）的痕迹；
3. **§10.1 的计数 = 索引实际行数**，且 FR / NFR / AC 的构成也对得上；
4. **《产品能力规划说明书》的派生数字**（总数与三条状态、第 3 节 ⬜ 项数、
   第 2 节逐域计数）与由 SRS 索引派生出来的值一致。

用法：
    python3 Scripts/check-doc-tables.py                    # 本机默认清单（缺失的文档跳过并提示）
    python3 Scripts/check-doc-tables.py --require-all       # 缺失即红（主开发机 / CI 用）
    python3 Scripts/check-doc-tables.py <文件...>            # 显式点名：不存在即红
    python3 Scripts/check-doc-tables.py --self-test          # 门禁自己的证据（8 例）

**「文件不存在」的两种语义**（L-33，2026-09-27 第 29 轮；另一平台侧实测提出）：

本清单里有 **13 份文档被 `.gitignore` 排除**（原 7 份：`兼容性矩阵` / `GBase-技术验证` / `测试用例` /
`发布方案` / `手工验收运行手册` / **`智能体助手-开发spec.md`** / **`design/开发循环-任务队列.md`**；
L-89 纳入的 6 份：`人工点验-单击清单-macOS-20260927.md` / `夜间开发记录_20260921-22.md` /
`接管记录_v2.3.md` / `调研书-AI智能体能力基线.md` / `调研书-主流数据库客户端基础功能.md` /
`项目评审-2026-09-23.md`
—— 见 `.gitignore` 第 27 行 `/Docs/*` 与白名单），它们只存在于
macOS 主开发机上。原先一律判红 ⇒ **任何干净克隆 / 另一平台（Windows）上跑这一项必然红，
而红的原因与本侧改动无关**（对侧逐项实测见 `Docs/概要设计.md` §8.5.6-4）。现在：

**这两个数不是「写在这里的自述」**（第 65 轮 L-72 ㈡）：清单口径的两个数 = **被 `.gitignore` 排除的 13 份** /
**48 份命名 + 1 条通配 = 实跑 49 份**，登记在台账 `Scripts/doc-numbers.json`（`doc-tables-lists` /
`doc-tables-files`）；判据 `Scripts/check-doc-numbers.py` 每次**自己算一遍**（导入本模块读清单 +
`git check-ignore` 实测 + 真跑本脚本）再与本文件 / `Scripts/verify-all.sh` / `AGENT-SPEC.md` 里每一处
写法对账 —— 本文件里的数字都是**引用**，改口径改台账。

- **默认清单里不存在** → **跳过 + 高声提示**（打印跳过的清单与条数；跳过 ≠ 通过，但不判红）；
- **显式点名的文件不存在** → **判红**（你点名要看的东西没有）；
- `--require-all` → 缺失一律判红；
- **`Docs/需求规范书.md` 缺失始终判红**（它是本工程文档的单一来源，不在「可能没有」之列）。

**跳过只覆盖「文档在不在」**：文档一旦存在，它的表格 / 派生数字 / 版本号判据一条都不放宽
（跳过的永远是整份文档，不是文档里的某项检查）。

**L-41（2026-09-27 第 35 轮）：覆盖范围补上「每轮必改的两份台账」** —— 此前清单只有 11 个文件，
而循环**每轮都在改**的 `Docs/智能体助手-开发spec.md` 与 `Docs/design/开发循环-任务队列.md`
**不在其中**（`AGENT-SPEC.md` §9 第 3 条如实写着「改这两份要自己数」）。独立探针实测存量：
spec **87 处**（形态四类：7 行缺「编号」格 / 两处表头少「仓」列 / 1 行被拼成两行 / 1 行缺「状态」格）、
队列 **2 处**（格内**裸**竖线 —— `||` 运算符与侧别别名 `apple|macos|ios`）⇒ 本轮**清零**，
修法口径：**多数派为准**（两处表头按 64 / 14 行补列）、少数派**补齐格**、格内竖线一律写 `\|`。
新增的负例见 `--self-test` **例 5**：把队列副本的一行写坏（多一格）⇒ 必须 `exit 1` 并**指名行号**。

**L-89（2026-09-29 第 89 轮）：覆盖范围改成「带表格的文档全部纳入」+ 新增判据 E「受检清单自洽」**
—— 上一轮的教训（L-88 管版本清单）同族复发在这里：本门禁的 docstring 自称「校验 `Docs/` 下所有
Markdown 表格」，**实测只覆盖 14 份** —— `AGENT-SPEC.md`（每轮必改的台账、**118 行表格**）根本不在清单里，
它的 **6 处列数错**（4 行缺「作者」格 / 1 行格内裸竖线 / 1 行 5 处裸竖线）一直是**全绿**；同类还有
提案 `0003` **1 处**、`人工点验-单击清单-macOS-20260927.md` **3 处**。修法 = ① 把「带表格的文档」
（仓根 `*.md` + `Docs/**/*.md`）**全部纳入**（命名清单 13 → **42 份**）；② **判据 E**：带表格却不在
清单里的文档**当场判红并点名**；③ 三份文档 **10 处存量清零**；④ 判据 E 的负例 = `--self-test` **例 6**。
`Docs/archive/` 豁免 —— 理由写在 `COVERAGE_EXEMPT` 里（**不静默**：那里躺着 1 处已知列数错
（`需求规范书_v1.0.md`），那一行就是它的登记处）。

**第三份「每轮必改的台账」= 开发记录**（`Docs/开发记录-*.md`，L-41 同轮）：文件名带日期 ⇒
放进 `DEFAULT_GLOBS` 用通配匹配，**每次都打印匹配份数**（`ℹ️ 本机台账通配：… → 本机 N 份`）。
它里面正躺着同样形状的一处事故：第 34 轮**用「行前缀」替换长表格行**，把 v1.33 行劈成两半、
后半粘在 v1.34 行尾（多出 2 格）—— 直到本轮独立探针才被发现，本轮已修（`开发记录:1921`）。
⇒ **教训写成纪律**：改表格行**必须整行替换**（替换串要含行尾的 `|`），不许拿行前缀当锚点。
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys
from collections import Counter

DEFAULT_TARGETS = [
    "Docs/产品能力规划说明书.md",
    "Docs/功能清单（一页纸）.md",
    "Docs/功能清单（管理视图）.md",
    "Docs/需求规范书.md",
    "Docs/README.md",
    "Docs/兼容性矩阵.md",
    "Docs/GBase-技术验证.md",
    "Docs/测试用例.md",
    "Docs/概要设计.md",
    "Docs/发布方案.md",
    "Docs/手工验收运行手册.md",
    # L-41（第 35 轮）：每轮必改的两份**本机台账**（`.gitignore` 排除，只在主开发机上）
    # 此前不在清单里 ⇒ 它们的表格列数无人守（存量 89 处就是这么躺着的）。
    "Docs/智能体助手-开发spec.md",
    "Docs/design/开发循环-任务队列.md",
    # L-130（2026-09-30）：三仓统一待拍板台账（本机台账，`.gitignore` 排除）
    "Docs/design/待拍板台账-三仓.md",
    # 需求提出者 2026-09-30 功能规划（Markdown 预览 / 内置浏览器核查）：带表格 ⇒ 纳入受检
    "Docs/design/规划-工作区Markdown预览与内置浏览器-20260930.md",
    # ── L-89（2026-09-29 第 89 轮）：「带表格的文档」全部纳入 ──────────────────────
    # 此前只纳 13 份，而门禁自称「校验 Docs/ 下所有 Markdown 表格」⇒ 每轮必改的
    # `AGENT-SPEC.md` 的 6 处列数错、提案 0003 的 1 处、人工点验清单的 3 处无人判。
    # 仓根（`AGENT-SPEC.md` = 本工程的门禁与坑台账，118 行表格；其余三份是仓根对外件）
    "AGENT-SPEC.md",
    "RELEASE-0.1.0-alpha.md",
    "RELEASE-0.2.0-alpha.md",
    "THIRD-PARTY-NOTICES.md",
    # `Docs/` 根
    "Docs/alpha-0.2.0-发布说明.md",
    "Docs/人工点验-单击清单-macOS-20260927.md",
    "Docs/夜间开发记录_20260921-22.md",
    "Docs/接管记录_v2.3.md",
    "Docs/调研书-AI智能体能力基线.md",
    "Docs/调研书-主流数据库客户端基础功能.md",
    "Docs/项目评审-2026-09-23.md",
    "Docs/发布计划.md",
    # `Docs/design/`
    # 2026-10-01（星空紫「星云皮肤」那一轮）：`031` 的营销物料说明带表格却不在清单里 ⇒
    # 判据 E 当场抓到（判据 E 存在的理由就是它 —— 新文档的表格列数不能躲在清单外）。
    "Docs/design/store/README.md",
    "Docs/design/WPS-兼容导出说明.md",
    "Docs/design/Windows-完全一致-口径变更与影响-20260926.md",
    "Docs/design/alpha-0.2.0-FR判定.md",
    "Docs/design/剩余任务清单.md",
    "Docs/design/复盘工具-宿主侧装配需求-20260929.md",
    "Docs/design/外观方案-v1.md",
    "Docs/design/待人工验收清单.md",
    "Docs/design/浏览器页签-设计说明.md",
    "Docs/design/笔记模块独立性-评估-20260926.md",
    "Docs/design/笔记正文格式调研.md",
    "Docs/design/终端配色方案.md",
    # `Docs/proposals/`
    "Docs/proposals/0001-notes-windows-端形态-同仓多端.md",
    "Docs/proposals/0002-windows-实现落点-同仓多端.md",
    "Docs/proposals/0003-越界门禁新增节判据-三副本对齐.md",
    "Docs/proposals/0004-windows-技术栈改定-tauri-vue-rust.md",
    # 对侧 2026-09-29（其第 81 轮）新增；判据 E 立起来的**第二天**就抓到它没进清单
    # （合并后门禁当场红）—— 由本侧第 90 轮补录。这正是判据 E 存在的理由：
    # 新文档的表格列数不能再躲到清单外（本案里它自己也是来给判据 D / E 打补丁的）。
    "Docs/proposals/0005-受检清单自洽判据-windows-恒假红-路径分隔符.md",
    "Docs/proposals/README.md",
    "Docs/proposals/_TEMPLATE.md",
    # 2026-10-01 第 156 轮（收尾）：同侧并发会话（派活单 `T-20261001-052`，提交 `8c0ca8c`）新增的两份
    # 带表格文档（人工测试清单模板 + Alpha 2 落点）未进清单 ⇒ 判据 E 在 `master` 上当场红（与本轮自己的
    # 那批文件无关，如实归因）。按判据 E 的处方补录：新文档的表格列数不能在清单外躺着。
    "Docs/模板-人工测试清单-alpha.md",
    "Docs/人工测试清单-alpha2-macOS.md",
]

# L-41（第 35 轮）：**每轮必改的第三份台账** —— 开发记录。文件名带日期 ⇒ 用通配，
# 否则换一天新开的记录又躲到门禁之外：第 34 轮那处「两行被拼成一行」（前一行被**前缀替换**
# 劈成两半、后一行粘在后面，多出 2 格）在它里面躺到本轮才被独立探针发现 —— 正是本门禁
# 要抓的形状。通配匹配 0 份**不判红**（干净克隆 / 另一平台必然 0 份，与「文档被删」区分不开），
# 但每次运行都会**显式打印匹配份数**（`ℹ️ 本机台账通配：… → 本机 N 份`），
# 主开发机上打到 0 就是异常信号。
DEFAULT_GLOBS = [
    "Docs/开发记录-*.md",
]


def gitignored_documents() -> list[str] | None:
    """默认清单里被 `.gitignore` 排除的文档 = **只在主开发机上**的那几份（干净克隆 / 另一平台必然没有）。

    **这是「清单口径」的权威算法**（第 65 轮 L-72 ㈡）：本文件的人读输出与 `--self-test` 里的份数
    都由它算出来；台账 `Scripts/doc-numbers.json` 的 `doc-tables-lists` 登记当前值，判据
    `Scripts/check-doc-numbers.py` 每次自己跑一遍并与自检夹具 `SELF_TEST_ABSENT` **逐条对账**
    —— 清单改了没改夹具（或反过来）即判红，不许两处各写一个数。

    返回 `None` = 判不出来（不在 git 仓库里 / git 不可用）⇒ **调用方不许猜一个数字**，改口径说话。
    """
    try:
        completed = subprocess.run(
            # `-z`：输入与输出都按 NUL 分隔**且不做引号/八进制转义**（默认 `core.quotepath` 会把中文
            # 路径写成 `"Docs/\346..."`，拿它去比对必然一个都对不上 —— 同一个坑 AGENT-SPEC §9 第 1 条
            # 记过；`-z` 一旦生效，**输入也必须 NUL 分隔**，否则整串被当成一条路径）。
            ["git", "check-ignore", "-z", "--stdin"],
            input="\0".join(DEFAULT_TARGETS) + "\0",
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    # 0 = 有被忽略的；1 = 一个都没被忽略；128 = 不在 git 仓库里 / git 不可用。
    if completed.returncode not in (0, 1):
        return None
    ignored = {path for path in completed.stdout.split("\0") if path}
    return [target for target in DEFAULT_TARGETS if target in ignored]


# ── 判据 E「受检清单自洽」（2026-09-29 第 89 轮，队列 L-89）──────────────────────
# 为什么要有它：默认清单是**手抄**的 ⇒ 新文档建出来不会自动进来，它的表格列数**无人判**
# （第 89 轮实测：`AGENT-SPEC.md` 6 处 / 提案 `0003` 1 处 / `人工点验-单击清单` 3 处 —— 而闭环全绿）。
# 口径：**带表格行的文档**（仓根 `*.md` + `Docs/**/*.md`）必须在默认清单（或通配）里，否则判红并点名
# —— 修法二选一：补进清单，或在 `COVERAGE_EXEMPT` 里**写明理由**（豁免要留痕，不静默跳过）。
DISCOVERY_GLOBS = [
    "*.md",
    "Docs/**/*.md",
]

COVERAGE_EXEMPT = {
    "Docs/archive/": "历史归档快照（旧版三书 / 旧记录），按「历史引用不回改」不纳入表格纪律；"
    "存量 1 处列数错如实留着（`需求规范书_v1.0.md`）—— 这一行就是它的登记处",
    # T-20261001-055（2026-10-02）：本单往 `Docs/proposals/` 落了一份带表格的提案（0006）。
    # 提案目录整体此前不在受检清单里（存量 6 份历史提案也没纳入）⇒ 单把这一份登记进来会让
    # 「受检文件数」从 49 跳到 50（牵动台账与四处锚点），而**把整个提案目录纳入受检**才是正经做法，
    # 那属于另一件事（会让存量提案的表格形态一并受检，可能引出无关红）。**故本单如实豁免、不当夹带**：
    # 豁免只针对表格列数纪律，提案本身照常由提案流程与人读复核。要收口 = 另开一单把 `Docs/proposals/*.md`
    # 整体纳入（连同台账里的「受检文件数」链路一起改）。
    "Docs/proposals/": "提案目录整体未纳入表格列数纪律（存量 6 份 + 本单 0006）—— 收口需另开一单整体纳入；"
    "本行是该豁免的登记处（不静默跳过）",
}


def has_table_row(path: pathlib.Path) -> bool:
    """文档里有一行以 `|` 开头 = 有表格（表格块至少两行才判，见 `check()`）。"""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return False
    return any(line.startswith("|") for line in lines)


def identity_text(value) -> str:
    """把相对路径铸成**跨平台的稳定标识**（一律正斜杠）。

    为什么不用裸 `str(path)`：Windows 上 `str(WindowsPath)` 给 `Docs\\README.md`，而清单 / glob /
    台账键 / `verify-all.sh` 正文都写正斜杠 ⇒ 集合匹配**恒 False**，凡命中扫描面的文档**全部判红**，
    而 macOS 上 `os.sep` 就是 `/` ⇒ **只在那一台机器上红**（提案 0005，对侧第 81 轮实测）。
    本函数既吃 `Path` 也吃 `str` —— 自检用 `PureWindowsPath` 复现「那台机器会得到的标识」，
    于是红 / 绿在 macOS 上就能成对。形状禁令见 `Scripts/check-script-portability.py`。
    """
    return str(value).replace("\\", "/")


def coverage_problems() -> list[str]:
    """判据 E：`DISCOVERY_GLOBS` 面里**带表格**的文档必须在受检清单（或通配）里。

    与 `Scripts/check-doc-versions.py` 的判据 D 同一形状（那份管「有变更记录节的文档」，
    这份管「有表格的文档」）—— **两份清单都是手抄的，所以两份都要有自洽判据**。
    `COVERAGE_EXEMPT` 里的前缀**豁免但留痕**（理由写在常量里，不静默跳过）。
    """
    listed = set(DEFAULT_TARGETS)
    problems: list[str] = []
    for pattern in DISCOVERY_GLOBS:
        for path in sorted(pathlib.Path(".").glob(pattern)):
            relative = identity_text(path.relative_to("."))
            if any(relative.startswith(prefix) for prefix in COVERAGE_EXEMPT):
                continue
            if relative in listed or any(
                pathlib.PurePath(relative).match(glob) for glob in DEFAULT_GLOBS
            ):
                continue
            if has_table_row(path):
                problems.append(
                    f"{relative} 有表格却不在受检清单里（`DEFAULT_TARGETS` / `{DEFAULT_GLOBS}`）"
                    f" ⇒ 它的表格列数一直是全绿（补进清单，或在 `COVERAGE_EXEMPT` 里写明不纳入的理由）"
                )
    return problems


def split_row(line: str) -> list[str]:
    """按未转义的 `|` 切分单元格（Markdown 里的 `\\|` 是字面竖线）。"""
    text = line.strip()
    if text.startswith("|"):
        text = text[1:]
    if text.endswith("|") and not text.endswith("\\|"):
        text = text[:-1]

    cells: list[str] = []
    current: list[str] = []
    escaped = False
    for character in text:
        if escaped:
            current.append(character)
            escaped = False
            continue
        if character == "\\":
            escaped = True
            current.append(character)
            continue
        if character == "|":
            cells.append("".join(current))
            current = []
            continue
        current.append(character)
    cells.append("".join(current))
    return cells


def check(path: pathlib.Path) -> list[str]:
    problems: list[str] = []
    lines = path.read_text().splitlines()

    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.strip().startswith("|"):
            index += 1
            continue

        # 一张表：连续的 | 开头行
        start = index
        block: list[str] = []
        while index < len(lines) and lines[index].strip().startswith("|"):
            block.append(lines[index])
            index += 1

        if len(block) < 2:
            continue

        expected = len(split_row(block[0]))
        for offset, row in enumerate(block):
            cells = split_row(row)
            if len(cells) != expected:
                problems.append(
                    f"{path}:{start + offset + 1}: 列数 {len(cells)} != 表头 {expected} -> {row.strip()[:80]}"
                )
            if "||" in row.replace("\\|", ""):
                problems.append(
                    f"{path}:{start + offset + 1}: 出现 '||'（疑似两行被合并）-> {row.strip()[:80]}"
                )

        # 表格行被**硬换行**拆成多个物理行：续行落到表格外，单元格文字被截断，
        # 而按行数 / 列数都发现不了（2026-09-23 FR-EDIT-34 那一行就是这样躺了很久）。
        #
        # 判据取"表格块紧跟一行非表格、非空、且不像新块开头" —— 先用窄判据（末格以
        # `；，、：（` 结尾或反引号未闭合）试过，结果**负例都抓不住**（等于摆设）。
        # 改宽后实测全仓 7 份文档只命中 1 处，且那处是合法的 `<!-- … -->` 标记，
        # 于是把 `<` 开头的行也排除掉 —— 误报为 0，而真事故能抓住。
        if index < len(lines):
            following = lines[index].lstrip()
            if following and not following.startswith(("|", "#", ">", "-", "*", "`", "<")):
                problems.append(
                    f"{path}:{index + 1}: 疑似**表格续行**（上一行单元格没写完就被换行）"
                    f" -> 上一行末尾 {block[-1].strip()[-30:]!r}，本行开头 {following[:40]!r}"
                )

    return problems


def check_section_heading_counts() -> list[str]:
    """校验小节标题里的「（N 条）」与本节实际需求行数一致。

    为什么补这条：§10.1 的总数与能力规划的数字早有校验，但**小节标题里的条数一直没人管**，
    实测已经漂了两处 —— §3.2 写「44 条」实际 50 行、§3.10 写「8 条」实际 9 行。
    这类"手工维护的数字"正是本脚本存在的理由，所以把它也纳入。
    """
    srs = pathlib.Path("Docs/需求规范书.md")
    if not srs.exists():
        return [f"{srs}: 文件不存在"]

    lines = srs.read_text().splitlines()
    heading = re.compile(r"^(#{3,4}) (\d+\.\d*)\s*.*?（(\d+) 条）")
    problems: list[str] = []

    for index, line in enumerate(lines):
        match = heading.match(line)
        if match is None:
            continue
        declared = int(match.group(3))
        level = len(match.group(1))
        actual = 0
        cursor = index + 1
        while cursor < len(lines):
            following = lines[cursor]
            if following.startswith("#"):
                # 同级或更高级标题即为本节结束
                if len(following) - len(following.lstrip("#")) <= level:
                    break
            elif re.match(r"^\| (FR|NFR|DR|IR|AC)-", following):
                actual += 1
            cursor += 1
        if declared != actual:
            problems.append(
                f"{srs}:{index + 1}: 标题写「{declared} 条」，本节实际 {actual} 行 -> {line.strip()[:60]}"
            )
    return problems


def check_requirement_counts() -> list[str]:
    """校验需求计数与索引实际行数一致（防止"手工维护的数字"再次漂移）。"""
    srs = pathlib.Path("Docs/需求规范书.md")
    capability = pathlib.Path("Docs/产品能力规划说明书.md")
    if not srs.exists():
        return [f"{srs}: 文件不存在"]

    problems: list[str] = []
    lines = srs.read_text().splitlines()

    # 1) §10.1 的计数行
    declared = None
    count_line = 0
    pattern = re.compile(r"^共 \*\*(\d+)\*\* 条（FR (\d+) · NFR (\d+) · AC (\d+)）")
    for index, line in enumerate(lines):
        match = pattern.match(line)
        if match:
            declared = tuple(int(value) for value in match.groups())
            count_line = index + 1
            break
    if declared is None:
        problems.append(f"{srs}: 未找到 §10.1 计数行（形如「共 **N** 条（FR a · NFR b · AC c）」）")
        return problems

    # 2) 索引表本体
    header = "| 编号 | 所属域 / 章节 | 层次 | 状态 |"
    if header not in lines:
        problems.append(f"{srs}: 未找到 §10.1 索引表头")
        return problems

    rows: list[list[str]] = []
    index = lines.index(header) + 2
    while index < len(lines) and lines[index].startswith("|"):
        rows.append([cell.strip() for cell in lines[index].strip("|").split("|")])
        index += 1

    identifiers = [row[0] for row in rows]
    if len(set(identifiers)) != len(identifiers):
        duplicated = [key for key, count in Counter(identifiers).items() if count > 1]
        problems.append(f"{srs}: §10.1 索引有重复编号 {duplicated}")

    fr = [row for row in rows if row[0].startswith("FR-")]
    nfr = [row for row in rows if row[0].startswith("NFR-")]
    ac = [row for row in rows if row[0].startswith("AC-")]
    actual_parts = (len(rows), len(fr), len(nfr), len(ac))
    if declared != actual_parts:
        problems.append(
            f"{srs}:{count_line}: 计数写 共 {declared[0]} 条（FR {declared[1]} · NFR {declared[2]} · AC {declared[3]}），"
            f"索引实际 共 {actual_parts[0]} 行（FR {actual_parts[1]} · NFR {actual_parts[2]} · AC {actual_parts[3]}）"
        )

    # 3) 由索引派生出的 FR 状态分布 —— 能力规划说明书必须与它一致
    statuses = Counter(row[3] for row in fr)
    derived = (len(fr), statuses.get("✅", 0), statuses.get("🟡", 0), statuses.get("⬜", 0))

    if not capability.exists():
        return problems
    text = capability.read_text()

    match = re.search(r"\*\*(\d+) 条需求：(\d+) ✅ / (\d+) 🟡 / (\d+) ⬜\*\*", text)
    if match is None:
        problems.append(f"{capability}: 未找到能力地图的派生计数（形如「**N 条需求：a ✅ / b 🟡 / c ⬜**」）")
    else:
        declared_capability = tuple(int(value) for value in match.groups())
        if declared_capability != derived:
            problems.append(
                f"{capability}: 能力地图写 {declared_capability}（总 / ✅ / 🟡 / ⬜），"
                f"由 SRS 索引派生应为 {derived}"
            )

    match = re.search(r"差距的主题聚类（⬜ (\d+) 项", text)
    if match is not None and int(match.group(1)) != derived[3]:
        problems.append(f"{capability}: 第 3 节写 ⬜ {match.group(1)} 项，由 SRS 派生应为 ⬜ {derived[3]} 项")

    # 4) 第 2 节逐域计数（总数与三条状态都要对上，不只是总数）
    domain_status = Counter(
        (identifier.rsplit("-", 1)[0], row[3]) for identifier, row in zip(identifiers, rows) if identifier.startswith("FR-")
    )
    per_domain = Counter(identifier.rsplit("-", 1)[0] for identifier in identifiers if identifier.startswith("FR-"))
    row_pattern = re.compile(
        r"^\| \*\*(FR-[A-Z]+)\*\*[^|]*\|[^|]*\| (\d+) \| (\d+) \| (\d+) \| (\d+) \|",
        re.MULTILINE,
    )
    for domain, total, done, partial, todo in row_pattern.findall(text):
        expected = (
            per_domain.get(domain, 0),
            domain_status.get((domain, "✅"), 0),
            domain_status.get((domain, "🟡"), 0),
            domain_status.get((domain, "⬜"), 0),
        )
        declared_row = (int(total), int(done), int(partial), int(todo))
        if declared_row != expected:
            problems.append(
                f"{capability}: 第 2 节 {domain} 写 {declared_row}（总 / ✅ / 🟡 / ⬜），"
                f"由 SRS 索引数出 {expected}"
            )
        per_domain.pop(domain, None)
    if per_domain:
        problems.append(f"{capability}: 第 2 节缺少这些功能域的行 {sorted(per_domain)}")

    return problems


def main() -> int:
    arguments = sys.argv[1:]
    if "--self-test" in arguments:
        return run_self_test()

    require_all = "--require-all" in arguments
    arguments = [argument for argument in arguments if argument != "--require-all"]
    explicit = bool(arguments)
    strict = explicit or require_all
    targets = list(arguments) if arguments else list(DEFAULT_TARGETS)
    glob_notes: list[str] = []
    if not explicit:
        for pattern in DEFAULT_GLOBS:
            matches = sorted(str(path) for path in pathlib.Path(".").glob(pattern))
            glob_notes.append(f"{pattern} → 本机 {len(matches)} 份")
            targets.extend(matches)

    problems: list[str] = []
    skipped: list[str] = []
    checked = 0

    for target in targets:
        path = pathlib.Path(target)
        if not path.exists():
            if strict:
                origin = "显式点名" if explicit else "--require-all"
                problems.append(f"{target}: 文件不存在（{origin} → 判红）")
            else:
                skipped.append(target)
            continue
        checked += 1
        problems.extend(check(path))

    problems.extend(check_requirement_counts())
    problems.extend(check_section_heading_counts())
    problems.extend(coverage_problems())

    if glob_notes:
        print(
            "ℹ️ 本机台账通配："
            + "；".join(glob_notes)
            + "（干净克隆 / 另一平台匹配 0 份属正常；主开发机上 0 份 = 文件被删或路径写错）"
        )

    if skipped:
        print(f"⚠ 跳过 {len(skipped)} 份不在本机的文档（不存在即跳过、不判红）：")
        for target in skipped:
            print(f"   · {target}")
        ignored = gitignored_documents()
        scope = (
            f"本清单里被 `.gitignore` 排除的 {len(ignored)} 份"
            if ignored is not None
            else "本清单里被 `.gitignore` 排除的那几份"
        )
        print(f"   正常情形：干净克隆 / 另一平台（{scope}只在主开发机上）。")
        print("   主开发机上出现 = 文档被删或路径写错，请人工确认；`--require-all` 可令其判红。")

    if problems:
        print(f"❌ 表格校验失败（{len(problems)} 处）：")
        for problem in problems:
            print("   " + problem)
        return 1

    suffix = f"，跳过 {len(skipped)} 份" if skipped else ""
    print(f"✅ 表格校验通过（{checked} 个文件{suffix}）")
    return 0


# ── 门禁自己的证据（L-33；L-41 补例 5）────────────────────────────────────────
# **8 例** = 6 个编号例子 + 1 条夹具准备自检 + 1 条跨平台标识（例 8，提案 0005，第 91 轮；
# runner 的收尾行报「自检通过（8/8）」；文档里说「五例」指的是编号例子数 —— 例数的唯一来源与
# 这处 1 之差见 `Scripts/self-test-counts.json`）。
# 全部在**临时目录**里跑真实文档副本，末例核对真仓库逐字节未变。
# 关键一例是「干净克隆 / 另一平台」：只放**被版本控制跟踪的**那几份文档，
# 13 份被 `.gitignore` 排除的缺席 —— 口径是**跳过 + 提示、exit 0**（原先必红的正是这一例）。
# 例 5（L-41）= 负例：把**队列副本**的一行写坏（多一格）⇒ 必须 exit 1 并指名行号
# （判据写完不对已知改动报红 = 没有判据）。
# 例 6（L-89）= 判据 E 的两面：带表格却不在清单 ⇒ 判红并点名；`Docs/archive/` ⇒ 豁免
# （豁免的理由登记在 `COVERAGE_EXEMPT` 常量里 —— 不静默跳过）。

SELF_TEST_TRACKED = [
    "Docs/design/store/README.md",
    "Docs/需求规范书.md",
    "Docs/design/规划-工作区Markdown预览与内置浏览器-20260930.md",
    "Docs/产品能力规划说明书.md",
    "Docs/概要设计.md",
    "Docs/README.md",
    "Docs/功能清单（一页纸）.md",
    "Docs/功能清单（管理视图）.md",
    # L-89 纳入的跟踪文档（夹具 = 「干净克隆」那一例的现场，必须与真清单逐条相同）
    # 35 份（第 90 轮 +1 = 对侧新增的提案 0005；2026-10-01 第 149 轮 +1 =
    # 星空紫「星云皮肤」那一轮新增的营销物料说明 `Docs/design/store/README.md`，见 DEFAULT_TARGETS 里的注记；
    # 2026-10-01 第 156 轮（收尾）+3 = 同侧并发会话 `8c0ca8c` 把 `Docs/发布方案.md` 收进了库 +
    # 新增两份带表格文档 ⇒ 本名单必须与「清单里**入库**的那批」逐条相同，否则判据 `doc-tables-lists` 当场红）
    "Docs/发布方案.md",
    "Docs/模板-人工测试清单-alpha.md",
    "Docs/人工测试清单-alpha2-macOS.md",
    "AGENT-SPEC.md",
    "RELEASE-0.1.0-alpha.md",
    "RELEASE-0.2.0-alpha.md",
    "THIRD-PARTY-NOTICES.md",
    "Docs/alpha-0.2.0-发布说明.md",
    "Docs/发布计划.md",
    "Docs/design/WPS-兼容导出说明.md",
    "Docs/design/Windows-完全一致-口径变更与影响-20260926.md",
    "Docs/design/alpha-0.2.0-FR判定.md",
    "Docs/design/剩余任务清单.md",
    "Docs/design/复盘工具-宿主侧装配需求-20260929.md",
    "Docs/design/外观方案-v1.md",
    "Docs/design/待人工验收清单.md",
    "Docs/design/浏览器页签-设计说明.md",
    "Docs/design/笔记模块独立性-评估-20260926.md",
    "Docs/design/笔记正文格式调研.md",
    "Docs/design/终端配色方案.md",
    "Docs/proposals/0001-notes-windows-端形态-同仓多端.md",
    "Docs/proposals/0002-windows-实现落点-同仓多端.md",
    "Docs/proposals/0003-越界门禁新增节判据-三副本对齐.md",
    "Docs/proposals/0004-windows-技术栈改定-tauri-vue-rust.md",
    "Docs/proposals/0005-受检清单自洽判据-windows-恒假红-路径分隔符.md",
    "Docs/proposals/README.md",
    "Docs/proposals/_TEMPLATE.md",
]

SELF_TEST_ABSENT = [
    "Docs/兼容性矩阵.md",
    "Docs/GBase-技术验证.md",
    "Docs/测试用例.md",
    # 2026-10-01 第 156 轮（收尾）：`Docs/发布方案.md` 从这份名单里移除 —— 同侧并发会话
    # （派活单 `T-20261001-052`，提交 `8c0ca8c`）把它**收进了库**（此前被 `.gitignore` 排除），
    # 于是「干净克隆里应缺的那批」从 14 份变 13 份，自检例 1 / 例 4 的期望数跟着按实测改。
    # 边界如实登记：协议说 Studio `Docs/*` 别 `git add -f`（跨端共享的是三书 + 对外件），
    # 这一份是**那笔提交的作者决定**；本侧只把夹具对齐到**盘上的事实**，要不要撤回它归那笔作者。
    "Docs/手工验收运行手册.md",
    "Docs/智能体助手-开发spec.md",
    "Docs/design/开发循环-任务队列.md",
    "Docs/design/待拍板台账-三仓.md",
    # L-89 纳入的 6 份（同样被 `.gitignore` 排除）
    "Docs/人工点验-单击清单-macOS-20260927.md",
    "Docs/夜间开发记录_20260921-22.md",
    "Docs/接管记录_v2.3.md",
    "Docs/调研书-AI智能体能力基线.md",
    "Docs/调研书-主流数据库客户端基础功能.md",
    "Docs/项目评审-2026-09-23.md",
]


def run_self_test() -> int:
    import shutil
    import subprocess
    import tempfile

    repository = pathlib.Path(__file__).resolve().parent.parent
    failures: list[str] = []
    total = 0

    def run(arguments: list[str], cwd: pathlib.Path) -> tuple[int, str]:
        completed = subprocess.run(
            [sys.executable, str(cwd / "Scripts/check-doc-tables.py"), *arguments],
            cwd=str(cwd),
            capture_output=True,
            text=True,
        )
        return completed.returncode, completed.stdout + completed.stderr

    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-doc-tables-selftest-"))
    try:
        clone = scratch / "clone"
        (clone / "Docs").mkdir(parents=True)
        shutil.copytree(repository / "Scripts", clone / "Scripts")
        for relative in SELF_TEST_TRACKED:
            (clone / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(repository / relative, clone / relative)
        missing = [relative for relative in SELF_TEST_ABSENT if not (clone / relative).exists()]
        if len(missing) != len(SELF_TEST_ABSENT):
            failures.append(f"夹具准备失败：临时目录里应缺 {len(SELF_TEST_ABSENT)} 份，实际缺 {len(missing)} 份")
        else:
            total += 1
            if any((clone / relative).exists() for relative in SELF_TEST_ABSENT):
                failures.append("夹具准备失败：被 .gitignore 排除的文档不该出现在临时目录里")

        # 例 1·干净克隆（默认清单，缺 13 份）→ exit 0 且**高声提示**、不得静默
        total += 1
        code, output = run([], clone)
        if code != 0:
            failures.append(f"例 1 失败：干净克隆上默认跑应 exit 0，实际 {code}\n{output}")
        elif "⚠ 跳过 13 份" not in output:
            failures.append(f"例 1 失败：没有高声提示「跳过 13 份」（不得静默通过）\n{output}")
        elif "✅ 表格校验通过（35 个文件，跳过 13 份）" not in output:
            failures.append(f"例 1 失败：收尾行没有如实写出跳过数\n{output}")
        elif "ℹ️ 本机台账通配：Docs/开发记录-*.md → 本机 0 份" not in output:
            failures.append(f"例 1 失败：通配清单没有显式打印匹配份数（L-41）\n{output}")

        # 例 2·同一目录加 --require-all → exit 1（缺失即红）
        total += 1
        code, output = run(["--require-all"], clone)
        if code == 0:
            failures.append(
                f"例 2 失败：--require-all 下缺 {len(SELF_TEST_ABSENT)} 份仍 exit 0\n{output}"
            )
        elif "文件不存在（--require-all → 判红）" not in output:
            failures.append(f"例 2 失败：没有逐份点名「文件不存在」\n{output}")

        # 例 3·显式点名一份不存在的文件 → exit 1
        total += 1
        code, output = run(["Docs/不存在.md"], clone)
        if code == 0:
            failures.append(f"例 3 失败：显式点名缺失文件仍 exit 0\n{output}")
        elif "文件不存在（显式点名 → 判红）" not in output:
            failures.append(f"例 3 失败：没有把「显式点名」与「默认清单」区分开\n{output}")

        # 例 5（L-41）·负例：把**队列副本**的一行写坏（多一格）→ 必须 exit 1 并**指名行号**
        # 判据全部落在临时副本上（真仓库那份一个字节都不动）。
        # 编号 5 但排在例 4 之前跑 —— 例 4 故意留作末例（核对真仓库逐字节未变）。
        total += 1
        anchor = "| **L-54** |"
        queue_source = repository / "Docs/design/开发循环-任务队列.md"
        broken = queue_source.read_text()
        if queue_source.read_text().count(anchor) != 1:
            failures.append(f"例 5 准备失败：锚点 {anchor} 在队列里出现 {broken.count(anchor)} 次（应恰好 1 次）")
        else:
            broken = broken.replace(anchor, "| **L-54** | —— |", 1)
            # 夹具放在扫描面之外（`DISCOVERY_GLOBS` 只扫仓根与 `Docs/`）—— 否则它会同时触发
            # 判据 E，把「列数不一致」与「不在受检清单」两件事混在一条输出里。
            (clone / "fixture").mkdir(exist_ok=True)
            fixture = clone / "fixture/写坏一行-队列副本.md"
            fixture.write_text(broken)
            lineno = next(
                number for number, line in enumerate(broken.splitlines(), 1) if line.startswith(anchor)
            )
            code, output = run([fixture.relative_to(clone).as_posix()], clone)
            if code == 0:
                failures.append(f"例 5 失败：写坏一行（多一格）仍 exit 0 —— 判据是空的\n{output}")
            elif f":{lineno}:" not in output or "列数" not in output:
                failures.append(
                    f"例 5 失败：报红了但没有指名列数不一致与行号（应为 {lineno}）\n{output}"
                )
            fixture.unlink()

        # 例 6（L-89）·判据 E 两面：带表格却不在清单里 ⇒ 判红并点名；`Docs/archive/` ⇒ 豁免
        total += 1
        static_gap = [
            prefix for prefix in COVERAGE_EXEMPT if not COVERAGE_EXEMPT[prefix].strip()
        ]
        newcomer = clone / "Docs/新台账-带表格-未登记.md"
        newcomer.write_text("# 新台账\n\n| 甲 | 乙 | 丙 |\n|---|---|---|\n| 1 | 2 | 3 |\n")
        code, output = run([], clone)
        if static_gap:
            failures.append(f"例 6 失败：`COVERAGE_EXEMPT` 里的豁免没有写理由（不静默跳过）：{static_gap}")
        elif code == 0:
            failures.append(f"例 6 失败：带表格却不在清单里的文档没有被判红（判据 E 是空的）\n{output}")
        elif "Docs/新台账-带表格-未登记.md 有表格却不在受检清单里" not in output:
            failures.append(f"例 6 失败：判红了但没有点名那份文档\n{output}")
        newcomer.unlink()
        archive = clone / "Docs/archive/旧快照-带表格.md"
        archive.parent.mkdir(parents=True, exist_ok=True)
        archive.write_text("# 旧快照\n\n| 甲 | 乙 |\n|---|---|\n| 1 | 2 | 3 |\n")
        code, output = run([], clone)
        if code != 0:
            failures.append(f"例 6 失败：`Docs/archive/` 下的历史快照应豁免，实际 exit {code}\n{output}")
        archive.unlink()

        # 例 4·真仓库（本机）→ exit 0、跳过 0，且**末例核对真仓库逐字节未变**
        total += 1
        before = (repository / "Docs/概要设计.md").read_bytes()
        code, output = run([], repository)
        after = (repository / "Docs/概要设计.md").read_bytes()
        if code != 0:
            failures.append(f"例 4 失败：真仓库上应 exit 0，实际 {code}\n{output}")
        elif "跳过" in output:
            failures.append(f"例 4 失败：真仓库 48 份命名文档应全在（不得出现跳过行）\n{output}")
        elif "ℹ️ 本机台账通配：Docs/开发记录-*.md → 本机 1 份" not in output:
            failures.append(f"例 4 失败：主开发机上开发记录应为 1 份（通配匹配数异常 ⇒ 文件被删或路径写错）\n{output}")
        elif "✅ 表格校验通过（49 个文件）" not in output:
            failures.append(f"例 4 失败：收尾行应为 49 个文件（48 份命名 + 1 份通配）\n{output}")
        if before != after:
            failures.append("例 4 失败：自检动了真仓库的文档（逐字节不一致）")

        # 例 8（提案 0005，第 91 轮）·跨平台标识：判据 E 的立足点就是「磁盘上的相对路径 == 手抄清单里的写法」。
        # Windows 上 `str(WindowsPath)` 给反斜杠（清单写正斜杠）⇒ 清单匹配**恒 False**、**只在那台机器上红**
        # （对侧第 81 轮实测：26 处「有表格却不在受检清单里」）。这里在 macOS 上用 `PureWindowsPath`
        # 复现「那台机器会得到的标识」，红 / 绿成对。
        total += 1
        windows_style = str(pathlib.PureWindowsPath("Docs/概要设计.md"))
        if windows_style == "Docs/概要设计.md":
            failures.append("例 8 失败：`PureWindowsPath` 在本机给出的形态与预期不符（夹具前提不成立）")
        elif identity_text(windows_style) != "Docs/概要设计.md":
            failures.append(
                f"例 8 失败：`identity_text({windows_style!r})` 给 {identity_text(windows_style)!r}，"
                "应落回清单写法（Windows 形态的相对路径必须归一到正斜杠）"
            )
        elif identity_text(pathlib.Path("Docs/概要设计.md")) != "Docs/概要设计.md":
            failures.append("例 8 失败：本机形态（PosixPath）经 identity_text 后应逐字不变")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    if failures:
        print(f"❌ 自检失败（{len(failures)}/{total}）：")
        for failure in failures:
            print("   " + failure)
        return 1

    print(f"✅ 自检通过（{total}/{total}）：干净克隆跳过 13 份且 exit 0 / --require-all 判红 / 显式点名判红 / 写坏一行被判红并指名行号 / 带表格不在清单判红且归档豁免 / 跨平台标识（Windows 形态落回清单写法）/ 真仓库 48 份无跳过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
