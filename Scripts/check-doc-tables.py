#!/usr/bin/env python3
"""校验 Docs/ 下所有 Markdown 表格的列数一致性，以及需求计数的一致性。

背景：本工程的文档表格由脚本增量修改，历史上出现过两类漂移：

1. 「两行被合并成一行」（`| ... || ... |`）导致表格错位；
2. **需求计数没有跟着条目走** —— §10.1 表头长期停在 v3.2 生成时的 `207`，
   而索引实际已经 213 行；《产品能力规划说明书》的能力地图也落后一条
   （FR-STD-DB-EXEC-001 归档未计入）。两者都是"手工维护的数字"，必然漂移。

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
    python3 Scripts/check-doc-tables.py --self-test          # 门禁自己的证据（17 例）

**「文件不存在」的两种语义**（L-33，2026-09-27 第 29 轮；另一平台侧实测提出）：

本清单里有 **12 份文档被 `.gitignore` 排除**（原 7 份：`兼容性矩阵` / `GBase-技术验证` / `测试用例` /
`发布方案`（已于 2026-10-01 入库，此处枚举不追改）/ `手工验收运行手册` / **`design/开发循环-任务队列.md`**；
（**2026-10-11 · 派单 `T-20261011-014`「台账归台账、契约归契约」**：`智能体助手-开发spec.md` 入库 ⇒
被排除数 **13 → 12**、受控夹具 **35 → 36**；这一行就是那笔改动的登记处）
L-89 纳入的 6 份：`人工点验-单击清单-macOS-20260927.md` / `夜间开发记录_20260921-22.md` /
`接管记录_v2.3.md` / `调研书-AI智能体能力基线.md` / `调研书-主流数据库客户端基础功能.md` /
`项目评审-2026-09-23.md`
—— 见 `.gitignore` 第 27 行 `/Docs/*` 与白名单），它们只存在于
macOS 主开发机上。原先一律判红 ⇒ **任何干净克隆 / 另一平台（Windows）上跑这一项必然红，
而红的原因与本侧改动无关**（对侧逐项实测见 `Docs/Doyah产品概要设计说明书.md` §8.5.6-4）。现在：

**这两个数不是「写在这里的自述」**（第 65 轮 L-72 ㈡）：清单口径的两个数 = **被 `.gitignore` 排除的 12 份** /
**69 份命名 + 1 条通配 = 实跑 70 份**，登记在台账 `Scripts/doc-numbers.json`（`doc-tables-lists` /
`doc-tables-files`）；判据 `Scripts/check-doc-numbers.py` 每次**自己算一遍**（导入本模块读清单 +
`git check-ignore` 实测 + 真跑本脚本）再与本文件 / `Scripts/verify-all.sh` / `AGENT-SPEC.md` 里每一处
写法对账 —— 本文件里的数字都是**引用**，改口径改台账。

- **默认清单里不存在** → **跳过 + 高声提示**（打印跳过的清单与条数；跳过 ≠ 通过，但不判红）；
- **显式点名的文件不存在** → **判红**（你点名要看的东西没有）；
- `--require-all` → 缺失一律判红；
- **`Docs/Doyah产品需求规格说明书.md` 缺失始终判红**（它是本工程文档的单一来源，不在「可能没有」之列）。

**跳过只覆盖「文档在不在」**：文档一旦存在，它的表格 / 派生数字 / 版本号判据一条都不放宽
（跳过的永远是整份文档，不是文档里的某项检查）。

**自检也不许硬读本机台账**（2026-10-08 · 任务 `t_004a679b`）：`--self-test` 里**依赖真仓库那几份
本机台账**的两例 —— 例 5（写坏队列副本一行）与例 4 的真仓库断言（68 份命名全在 / 实跑 69 个文件 /
无跳过行）—— 在台账不在盘上时**跳过 + 高声提示**：既不崩（例 5 原先直接 `FileNotFoundError`），
也不假红（例 4 原先把「干净克隆必然缺台账」读成「文档被删」）。口径同上面这一条，出处 =
`AGENT-SPEC.md` §9 第 147 条 ④（本机台账类判据一律「不在盘上就跳过 + 高声提示」）。**在
主开发机上这两例照旧必须真跑、一条都不放宽**（`--self-test` 的例数仍是 17，不因跳过而改）。

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
    "Docs/规范/界面设计节-写作规范.md",
    "Docs/人工点验清单-20261018.md",
    "Docs/人工点验清单-20261018-重分版.md",
    "Docs/Doyah产品能力规划说明书.md",
    "Docs/功能清单（一页纸）.md",
    "Docs/功能清单（管理视图）.md",
    "Docs/Doyah产品需求规格说明书.md",
    "Docs/Doyah产品需求规格说明书-变更记录.md",
    "Docs/Doyah产品能力规划说明书-变更记录.md",
    "Docs/Doyah产品概要设计说明书-变更记录.md",
    "Docs/Doyah产品需求规格说明书-需求索引.md",
    "Docs/Doyah产品需求规格说明书-追溯表.md",
    "Docs/Doyah产品开发计划书.md",
    "Docs/README.md",
    "Docs/兼容性矩阵.md",
    "Docs/GBase-技术验证.md",
    "Docs/测试用例.md",
    "Docs/Doyah产品概要设计说明书.md",
    # 2026-10-21：详设模板（Studio 线，填空槽形态）—— 有表格就得进受检清单。
    "Docs/模板-详细设计说明书-Studio.md",
    "Docs/Doyah产品详细设计说明书-macOS.md",
    "Docs/Doyah产品详细设计说明书-Windows.md",
    "Docs/Doyah产品详细设计说明书-Linux.md",
    "Docs/Doyah产品详细设计说明书-Android.md",
    "Docs/Doyah产品详细设计说明书-iOS.md",
    "Docs/Doyah产品详细设计说明书-HarmonyOS.md",
    # 2026-10-23：macOS 端开发计划书（有表格 ⇒ 进受检；本端执行计划，不改状态源）
    "Docs/Doyah产品开发计划书-macOS端.md",
    "Docs/Doyah产品开发计划书-安卓端.md",
    "Docs/发布方案.md",
    "Docs/手工验收运行手册.md",
    # L-41（第 35 轮）：每轮必改的两份**本机台账**（`.gitignore` 排除，只在主开发机上）
    # 此前不在清单里 ⇒ 它们的表格列数无人守（存量 89 处就是这么躺着的）。
    "Docs/智能体助手-开发spec.md",
    # 2026-10-17：核心能力扩展草案（灵魂 / IM / 记忆 / 技能自进化）—— 有表格就得进受检清单。
    "Docs/智能体助手-核心能力扩展-草案-v0.1.md",
    # 2026-10-14 · 派单 `T-20261014-015`（人类主人令「`fatshark` 要对齐 macOS 版开发进度」）：
    # 平台对齐件入库（`.gitignore` 白名单 + 本清单 + `verify-all.sh` 第 7 项 `--check`）⇒
    # 受控夹具 36 → 37；被 `.gitignore` 排除的仍是 12 份（它是入库件）。
    "Docs/平台对齐-Studio-Windows对macOS.md",
    # 2026-10-14 · 派单 `T-20261014-025`（人类主人令 2026-10-14 追问「怎么到现在你还没有 macOS 的任务清单？」）：
    # 派生视图《任务清单 · 按平台》入库（`.gitignore` 白名单 + 本清单 + 闭环第 7 项
    # `Scripts/check-board-parity.py`）；被 `.gitignore` 排除的仍是 12 份（它是入库件）。
    "Docs/任务清单-按平台.md",
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
    "Docs/beta1.0-发布说明.md": "**发布快照**（另一条循环在 2026-10-21 落库，提交 `393dc4af`）—— 里面是 tag 读数与当版条目清单，编号是**当时那一版**的快照；按「历史引用不回改」不纳入表格纪律，也不参与编号迁移（回改会让发布说明与它描述的包对不上）。豁免留痕，不静默跳过；要纳入须由发布方另开一单，连同受检文件数与锚点一起改。",
    "Docs/design/编辑器能力基线-编程助手.md": "编辑器能力基线件（2026-10-15 人类主人令「编程工具的基本能力都要有」下的调研 + 比对底稿）—— "
    "体裁是**能力清单**（能力项 / 我方现状 / 缺口），不是契约面也不是台账面；"
    "**纳入受检会牵动「受检文件数」链路（51→52 与四处锚点）**，与本次交办不符 ⇒ 按既有先例如实豁免并留痕"
    "（不静默跳过）；要正式纳入 = 另开一单，连台账与锚点一起改。",
    "Docs/design/AI-native组织探索-复盘-20261015.md": "**对侧交付件**（studio 提交 `6aecf3d`「交付：AI-native 组织探索复盘 · 人类主人令 · 供下载到公司电脑查阅」）—— "
    "该件的表格**未纳入受检清单**（它的扫描面由交付方决定）。按「**不擅改对方文档 + 豁免要留痕**」两条：本处如实豁免并写明出处，"
    "**不静默、也不代改**；若要把 `Docs/design/**` 整体纳入受检（会牵动「受检文件数」链路与锚点），由归属者另开一单。",
    "Docs/design/macOS-开发计划-20261022.md": "**开发计划进度表**（2026-10-22 人类主人令「先列出开发计划进度表」）—— 体裁是**批次日程**（批次 / 项 / 现状 / 判据 / 估时），不是契约面也不是台账面；"
    "它与三书的锚点无关，且会被逐日回填（估时一改、列数就跟不上）⇒ 按既有先例如实豁免并留痕（不静默跳过）；"
    "要把它当台账受检，另开一单连受检文件数与锚点一起改。",
    "Docs/design/brand/": "品牌资产登记（2026-10-15 人类主人交办：吉祥物图片入库作项目标识）—— 本目录只登 1 张表（原图 / 展示件两行），"
    "内容是**图片资产清单**、非产品文档；**纳入受检会牵动「受检文件数」链路（49→50 + 四处锚点）**，"
    "与本次交办不符 ⇒ 按既有先例如实豁免并留痕（非静默跳过）；若要正式纳入，另开一单连同台账与四处锚点一起改。",
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
    # 2026-10-11 第 485 轮（基线红修 · 队列 `L-188`）：`Docs/evidence/**` 是**逐轮证据归档**
    # （读数 / dump / 点名表 / 截图清单），**不是文档**、也不进任何清单。第 484 轮之后判据 E
    # 因上一轮那份带表格的证据件（`Docs/evidence/基本法v5.0-引用跟版-T-20261011-010.md`）
    # **当场判红**（循环第 4 项 = 基线红）⇒ 按判据 E 自己的第二条修法「在 `COVERAGE_EXEMPT`
    # 里写明理由」登记豁免（豁免机制本身由自检**例 6** 两面覆盖 —— 带表格不在清单仍判红 /
    # 在豁免前缀内豁免并留痕 ⇒ **例数不变 9/9**）。
    # 豁免范围只到「表格列数纪律」：证据件里的读数照旧由本轮一页回报 + 归档件本身负责。
    # shared-surface：Scripts/check-doc-tables.py —— 判据脚本归机组（本仓 `Scripts/**` 属机组面，
    # 前门改门禁一律出补丁交机组应用）；本次只加一条豁免登记项 + 理由（**不改任何判据断言**、例数仍 9），
    # 故依 `path-ownership.json` 的 `shared` 口径在本行就地声明。
    "Docs/evidence/": "逐轮证据归档（读数 / dump / 点名表 / 截图清单，非文档），不纳入表格列数纪律；"
    "本行是该豁免的登记处（不静默跳过）",
    # 2026-10-13（铁皮大河马 · 全量闭环首红修正）：`Docs/design/AI助手-现状梳理与优先级-20261012.md`
    # 是**未入库的工作件**（AI 助手现状梳理 + 优先级排序的简报底稿，供人类主人过目），
    # 带表格 ⇒ 判据 E 当场判红。它**不是交付文档**、也不进任何清单 ⇒ 按判据 E 第二条修法
    # 登记豁免（豁免留痕、不静默跳过）。**收口条件**：该件若随交付面入库（转为正式设计文档），
    # 就把它从本表移除并纳入 `DEFAULT_TARGETS`（连同「受检文件数」链路一起改）。
    # shared-surface：Scripts/check-doc-tables.py —— 判据脚本归机组（本仓 `Scripts/**` 属机组面）；
    # 本次只加一条豁免登记项 + 理由（**不改任何判据断言**、例数仍 9），依 `path-ownership.json` 的
    # `shared` 口径在本行就地声明。
    "Docs/design/AI助手-现状梳理与优先级-20261012.md": "未入库的工作件（AI 助手现状梳理与优先级简报底稿），"
    "非交付文档，不纳入表格列数纪律；收口 = 随交付面入库时移出本表",
}


DELIMITER_ROW = re.compile(r"^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$")


def unescaped_pipes(text: str) -> int:
    """数**未转义**的 `|`（`\\|` 是格内的字面竖线，不算分隔符）。"""
    count = 0
    escaped = False
    for character in text:
        if escaped:
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == "|":
            count += 1
    return count


def pipes_outside_code(text: str) -> int:
    """数**行内代码（反引号）之外**的未转义竖线 —— 真续行的行尾会带着表格的格分隔竖线。"""
    return unescaped_pipes(re.sub(r"`[^`]*`", "", text))


def is_delimiter_row(line: str) -> bool:
    """GFM 表格的第二行（`--- | ---`，两端竖线可有可无、可带对齐冒号）。"""
    return bool(DELIMITER_ROW.match(line.strip()))


def is_table_row(line: str) -> bool:
    """一行是不是**表行**：行首竖线可有可无（GFM 允许省略两端竖线）。

    判定物从「行首字面 `|`」（原单 T-20261010-070 ㈠ 的病根）升到 GFM 的合法写法：
    剥掉首尾空白后**还有未转义的 `|`** 就是表行。
    """
    text = line.strip()
    if not text:
        return False
    return text.startswith("|") or unescaped_pipes(text) > 0


def starts_new_block(text: str) -> bool:
    """下一行是不是**自己开了新块**（标题 / 引用 / 围栏 / 列表 …）⇒ 不算上一张表的续行。

    收窄（原单 ㈣）：`**加粗**` 开头的真续行**不再放走**（`**` 不是块首标记）；
    `-` / `*` / `+` 只有在**后面跟空白**时才算列表项（`*强调*` / `-3 度` 不算）。
    """
    if text.startswith(("|", "#", ">", "`", "<")):
        return True
    if text.startswith("**"):
        # 加粗开头：**真续行**（行内还带 ≥ 2 个表格分隔竖线 ⇒ 是被硬换行截断的行尾）判红；
        # 完整的加粗引导句（`**独占标记（2026-09-27 形态 A…）**：…` 这类散文 —— 原单 ㈣ 的真仓活体
        # = `Docs/Doyah产品概要设计说明书.md:11-12`）仍算「新块」、不误报。口径 = 行内竖线个数（如实登记的边界）。
        return pipes_outside_code(text) < 2
    if len(text) >= 3 and set(text) <= set("-*_ \t"):
        # 分隔线 / setext 下划线（`---` / `***` / `___`）—— 自己就是一个块，不是续行
        return True
    return text[0] in "-*+" and (len(text) == 1 or text[1].isspace())


def table_blocks(lines: list[str]) -> list[tuple[int, list[str]]]:
    """按 GFM 口径切**表格块**：(起点行号（0 起）, 行列表)；块长 < 2 不算表。

    这是「什么算表格」的**唯一入口** —— `check()` 与 `has_table_row()` 都走它
    （原单 ㈢：判据 E 的「有一行以 `|` 开头」与 `check()` 的「块 ≥ 2 行」原先各一套口径）。
    两条路各自保守：
      · **带首竖线**（绝大多数存量表）：与以前逐字节相同的口径（连续 `|` 开头的行）；
      · **无首竖线**（GFM 合法写法，原单 ㈠）：首行含未转义竖线**且第二行是分隔行**才算表 ——
        靠分隔行把「表格」与「散文里出现了一个竖线」分开，存量散文不受影响。
    """
    blocks: list[tuple[int, list[str]]] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.strip().startswith("|"):
            start = index
            rows: list[str] = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                rows.append(lines[index])
                index += 1
            if len(rows) >= 2:
                blocks.append((start, rows))
            continue
        if (
            unescaped_pipes(line.strip()) > 0
            and index + 1 < len(lines)
            and is_delimiter_row(lines[index + 1])
        ):
            start = index
            rows = [line]
            cursor = index + 1
            while cursor < len(lines) and is_table_row(lines[cursor]):
                rows.append(lines[cursor])
                cursor += 1
            blocks.append((start, rows))
            index = cursor
            continue
        index += 1
    return blocks


def has_table_row(path: pathlib.Path) -> bool:
    """文档里**确实有一张表**（≥ 2 个表行；行首竖线可有可无，与 `check()` 同一个入口）。"""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return False
    return bool(table_blocks(lines))


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
    lines = path.read_text(encoding="utf-8").splitlines()

    for start, block in table_blocks(lines):
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

        # 表格行被**硬换行**拆成多个物理行：续行落到表格外，单元格文字被截断，按行数 / 列数都
        # 发现不了（2026-09-23 FR-STD-WS-WEB-001 那一行就是这样躺了很久）。判据 = 「表格块紧跟一行
        # **自己没开新块**的非空行」；「什么算新块」收进 `starts_new_block()`（原单
        # T-20261010-070 ㈣：`**加粗**` 开头的真续行原先被 `*` 一并放走 ⇒ 逃逸）。
        index = start + len(block)
        if index < len(lines):
            following = lines[index].lstrip()
            if following and not starts_new_block(following):
                problems.append(
                    f"{path}:{index + 1}: 疑似**表格续行**（上一行单元格没写完就被换行）"
                    f" -> 上一行末尾 {block[-1].strip()[-30:]!r}，本行开头 {following[:40]!r}"
                )

        # 判据 F（T-20261011-001 · 2026-10-11）：同一张逻辑表被**空行**截断成两张 —— 两张的
        # 表头逐格相同 ⇒ 判红。此前抓不到：两张表各自**列数都自洽**，所以上面那条「列数一致」
        # 看得过去（三书落笔时的定点审计人工抓到一处空行拆表，而门禁全绿 ⇒ 补这条）。
        # 真要是两张表：表头别写成一样，或中间加小节标题（只有空行的间隔才算「相邻」）。
        cursor = index
        while cursor < len(lines) and not lines[cursor].strip():
            cursor += 1
        if cursor < len(lines) and lines[cursor].strip().startswith("|"):
            following_block: list[str] = []
            probe = cursor
            while probe < len(lines) and lines[probe].strip().startswith("|"):
                following_block.append(lines[probe])
                probe += 1
            if len(following_block) >= 2:
                header = [cell.strip() for cell in split_row(block[0])]
                following_header = [cell.strip() for cell in split_row(following_block[0])]
                if header == following_header and any(header):
                    problems.append(
                        f"{path}:{start + 1}: 与 {path}:{cursor + 1}: 相邻两表**表头逐格相同**"
                        f"（中间只隔空行）⇒ 疑似一张表被空行截断成两张"
                        f"（或删掉空行、或把两张表表头写开、或中间加小节标题）"
                        f" -> {block[0].strip()[:80]}"
                    )

    return problems


def check_section_heading_counts() -> list[str]:
    """校验小节标题里的「（N 条）」与本节实际需求行数一致。

    为什么补这条：§10.1 的总数与能力规划的数字早有校验，但**小节标题里的条数一直没人管**，
    实测已经漂了两处 —— §3.2 写「44 条」实际 50 行、§3.10 写「8 条」实际 9 行。
    这类"手工维护的数字"正是本脚本存在的理由，所以把它也纳入。
    """
    srs = pathlib.Path("Docs/Doyah产品需求规格说明书.md")
    if not srs.exists():
        return [f"{srs}: 文件不存在"]

    lines = srs.read_text(encoding="utf-8").splitlines()
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
            elif re.match(r"^\| (?:\*\*)?(FR|NFR|DR|IR|AC)-", following):
                actual += 1
            cursor += 1
        if declared != actual:
            problems.append(
                f"{srs}:{index + 1}: 标题写「{declared} 条」，本节实际 {actual} 行 -> {line.strip()[:60]}"
            )
    return problems


def check_requirement_counts() -> list[str]:
    """校验需求计数与索引实际行数一致（防止"手工维护的数字"再次漂移）。"""
    # 2026-10-20：编号索引从正文附录移出成独立文件（机械派生件）⇒ 计数行与索引表都读那份。
    srs = pathlib.Path("Docs/Doyah产品需求规格说明书-需求索引.md")
    capability = pathlib.Path("Docs/Doyah产品能力规划说明书.md")
    if not srs.exists():
        return [f"{srs}: 文件不存在"]

    problems: list[str] = []
    lines = srs.read_text(encoding="utf-8").splitlines()

    # 1) 索引文件的计数行
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
    # 2026-10-20：状态列迁出到《开发计划书》⇒ 索引表头不再带「状态」。
    # 两种形状都认（带 / 不带状态），免得改口径时判据自己先崩。
    candidates = ["| 编号 | 所属域 / 章节 | 层次 | 状态 |", "| 编号 | 所属域 / 章节 | 层次 |"]
    header = next((c for c in candidates if c in lines), None)
    if header is None:
        problems.append(f"{srs}: 未找到 索引表头")
        return problems
    has_status = "状态" in header

    rows: list[list[str]] = []
    index = lines.index(header) + 2
    # 表体切分**与 `check()` 一套口径**（`split_row`，认格内合法转义 `\|` —— 原单 ㈤(b)：
    # 原先这里是 `strip("|").split("|")`，按本仓纪律在格里写 `\|` 反而判红）。
    while index < len(lines) and lines[index].startswith("|"):
        rows.append([cell.strip() for cell in split_row(lines[index])])
        index += 1
    # 表体中断显式化（原单 ㈤(a)）：表体后面紧跟一行**仍是表行形状**（`FR-…` 开头、行首多一个
    # 空格之类）却没被连上 ⇒ 原先静默读成 0 行、派生数变成 (0, 0, 0, 0)，一条「解析中断」都不说。
    if index < len(lines) and re.match(r"^\s{1,3}\|?\s*(FR|NFR|AC|DR|IR)-", lines[index]):
        problems.append(
            f"{srs}:{index + 1}: 索引表体在此中断（该行行首不是 `|`，但它仍是表行形状 ⇒ "
            f"后续行未被解析、计数会算成 0）-> {lines[index].strip()[:80]}"
        )

    identifiers = [row[0] for row in rows]
    if len(set(identifiers)) != len(identifiers):
        duplicated = [key for key, count in Counter(identifiers).items() if count > 1]
        problems.append(f"{srs}: 索引有重复编号 {duplicated}")

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
    # 取格兜底（原单 ㈥）：FR 行缺一格原先直接 `IndexError` 崩掉、已收集的诊断**全丢**
    # （CI 里「判红」与「脚本崩了」不可分）；现在先报「格数不足」，再按现有格子算下去。
    needed = 4 if has_status else 3
    short_rows = [number for number, row in enumerate(rows, 1) if len(row) < needed]
    if short_rows:
        # 2026-10-20：状态列迁出后表头只剩三列，旧版把这条诊断锁在 `has_status` 里 ⇒
        # 三列版的缺格行会**静默放过**（少一格的行仍被算进派生数）。门槛跟着表头走，不再看有没有状态列。
        problems.append(
            f"{srs}: 索引有 {len(short_rows)} 条行**格数不足 {needed}**（表体行序 {short_rows[:6]}）"
            f" ⇒ 疑似缺格（{'缺「状态」格' if has_status else '缺「层次」格'}），派生数按现有格子算"
            f"（旧版这里会直接崩掉、已收集的诊断全丢）"
        )
    statuses = Counter(row[3] for row in fr if len(row) > 3) if has_status else Counter()
    derived = (len(fr), statuses.get("✅", 0), statuses.get("🟡", 0), statuses.get("⬜", 0))

    if not capability.exists():
        return problems
    text = capability.read_text(encoding="utf-8")

    # 2026-10-18 口径变更（人类主人令：三书不写状态）：能力地图不再承载 ✅/🟡/⬜ 计数，
    # 派生计数与逐域计数两项检查作废；只校验「SRS 里出现的每个功能域，本书 §2 都有对应一行」。
    # 状态与条数唯一源 = 需求说明书状态列（`Docs/Doyah产品需求规格说明书.md` §10.1）。
    # 2026-10-18 第二次口径变更：能力书不再承载需求书的 `FR-*` 功能域分类（`FR-LIC` / `FR-BLD`
    # 这类工程域本就不是产品能力）。旧检查「SRS 每个域在 §2 有说明行」随之作废。
    # 新检查更强：**正文里的节号引用必须解析到真实标题** —— 过去改章节时留下的过期引用
    # （如「权限写 3.8.3」而实际在 3.3.1）就是靠这条抓出来的。附录（含变更记录的历史节号）不在此列。
    body = text[:text.index("# 附录 A")] if "# 附录 A" in text else text
    headings = set(re.findall(r"^#{2,4} (\d+\.\d+(?:\.\d+)?) ", text, re.M))
    cited = set(re.findall(r"(?<![\d.v])(\d+\.\d+(?:\.\d+)?)(?![\d.])", body))
    for number in sorted(cited):
        if number not in headings:
            problems.append(f"{capability}: 正文引用了不存在的节号 {number}")

    return problems



CAPABILITY_BOOK = pathlib.Path("Docs/Doyah产品能力规划说明书.md")
STATUS_MARKS = ("⬜", "🟡", "✅")


def check_capability_book_purity() -> list[str]:
    """能力书「不写状态」判据（2026-10-20 · 人类主人问「能力说明书怎么会有状态字段呢」）。

    **为什么要它**：能力书 1.1 维护约定① 与陈述 S-04 都写明「本文件不写状态 —— 状态与条数的
    唯一源是需求说明书」。但**这条以前只靠自觉**：能力书正文没有状态列时全绿，一旦有人在表里
    加一列「状态」、或者写上 ⬜🟡✅，同样全绿 —— 口径是靠人记的，不是靠判据守的。

    实测逮到的第一例：Retro 仓能力书 §1「能力分组」表带一列全 ⬜ 的状态（4 列 14 行，旧体例残留）。

    **判据两条**：
    - **A 表头不得有「状态」单元格**（匹配 `| 状态 |`）：状态属需求书，能力书只要「做到哪 / 不做到哪」。
    - **B 正文不得出现状态符号** ⬜ 🟡 ✅：符号本身就是状态；出现在「能力书里怎么标」的说明句里也不行。
    """
    problems: list[str] = []
    if not CAPABILITY_BOOK.exists():
        return problems
    lines = CAPABILITY_BOOK.read_text(encoding="utf-8").split("\n")
    # 附录 E（变更记录）是**历史文本**：它会引用当时的「⬜ 6 项」这类读数，不算违反
    # 「正文不写状态」—— 只查正文段。
    body_end = len(lines)
    for index, line in enumerate(lines):
        if line.startswith("# 附录 E"):
            body_end = index
            break
    for index, line in enumerate(lines[:body_end], 1):
        if re.match(r"^\|.*\|\s*状态\s*\|", line) and line.lstrip().startswith("|"):
            problems.append(
                f"{CAPABILITY_BOOK}:{index}: 表头出现「状态」列 —— 能力书不写状态（唯一源 = 需求书），"
                f"状态要么删、要么改成「界限 / 判据」：{line.strip()[:60]}"
            )
        for mark in STATUS_MARKS:
            if mark in line:
                problems.append(
                    f"{CAPABILITY_BOOK}:{index}: 正文出现状态符号「{mark}」—— 能力书不写状态：{line.strip()[:60]}"
                )
                break
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

    # 在场下限（原单 T-20261010-070 ㈡）：以前缺件只 `skipped.append` —— 删掉一份 tracked 文档
    # （判据 ③④ 依赖的《产品能力规划说明书》），派生对账就**随它一起消失**，本件自己看不出来
    # （原先靠兄弟判据 `check-doc-numbers.py` 的绝对数兜住 ⇒ 摘掉兄弟判据即失守）。现在两条判：
    #   · 受检数 + 跳过数 == 受检面（构造上必等；不等 = 本脚本自己算错，判红，不静默）；
    #   · 跳过的那几份里**不在** `.gitignore` 排除名单里的 = 主开发机上文档被删 / 路径写错 ⇒ 判红。
    if checked + len(skipped) != len(targets):
        problems.append(
            f"内部一致性问题：受检 {checked} + 跳过 {len(skipped)} != 受检面 {len(targets)}"
            f"（算面这一步自己写错了 ⇒ 判红，免得静默）"
        )
    ignored_targets = gitignored_documents()
    if skipped and ignored_targets is None:
        print(
            f"⚠ 无法与 `.gitignore` 对账（不在 git 仓库里 / git 不可用）⇒ 上面跳过的 {len(skipped)} 份"
            "**未**被证明是本机台账；请人工确认是不是被删或路径写错。"
        )
    elif skipped:
        hard_missing = [target for target in skipped if target not in ignored_targets]
        if hard_missing:
            problems.append(
                f"受检清单里有 {len(hard_missing)} 份文档不在盘上、也不在 `.gitignore` 排除名单里"
                f"（= 被删或路径写错；本件自己判红，不靠兄弟判据）：{hard_missing[:8]}"
            )
    problems.extend(check_requirement_counts())
    problems.extend(check_section_heading_counts())
    problems.extend(coverage_problems())
    problems.extend(check_capability_book_purity())

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
# **17 例** = 15 个编号例子（例 1~9 + 例 10~17 = 原单 `T-20261010-070` 那族 8 例）+ 1 条夹具准备自检；
# 其中例 8 = 跨平台标识
# （提案 0005，第 91 轮）、例 9 = 判据 F 两面（空行拆表 · 表头逐格相同 ⇒ 判红 / 表头不同 ⇒ 对照绿，
# 派单 `T-20261011-001`，2026-10-11）；
# runner 的收尾行报「自检通过（17/17）」；文档里说「五例」指的是编号例子数 —— 例数的唯一来源与
# 这处 1 之差见 `Scripts/self-test-counts.json`）。
# 全部在**临时目录**里跑真实文档副本，末例核对真仓库逐字节未变。
# 关键一例是「干净克隆 / 另一平台」：只放**被版本控制跟踪的**那几份文档，
# 12 份被 `.gitignore` 排除的缺席 —— 口径是**跳过 + 提示、exit 0**（原先必红的正是这一例）。
# 例 5（L-41）= 负例：把**队列副本**的一行写坏（多一格）⇒ 必须 exit 1 并指名行号
# （判据写完不对已知改动报红 = 没有判据）。
# 例 6（L-89）= 判据 E 的两面：带表格却不在清单 ⇒ 判红并点名；`Docs/archive/` ⇒ 豁免
# （豁免的理由登记在 `COVERAGE_EXEMPT` 常量里 —— 不静默跳过）。
#
# **例 4 / 例 5 要看真仓库那几份本机台账**（`.gitignore` 内、只在主开发机上）⇒ 不在盘上时**跳过 +
# 高声提示**（2026-10-08 · 任务 `t_004a679b`）：干净克隆 / 并行工作树 / 另一平台必然没有它们 ——
# 原先例 5 直接 `FileNotFoundError`（闭环第 4 项当轮必崩，与当轮改动无关）、例 4 把缺席读成
# 「文档被删或路径写错」而假红。口径出处 = `AGENT-SPEC.md` §9 第 147 条 ④（本机台账类判据
# 一律「不在盘上就跳过 + 高声提示」，`--require-all` 才判红）。跳过的只是**这两例**，其余各例照跑；
# 例数仍是 17（跳过不改总数、也不许静默）。

SELF_TEST_TRACKED = [
    "Docs/Doyah产品详细设计说明书-Windows.md",
    "Docs/Doyah产品详细设计说明书-Linux.md",
    "Docs/Doyah产品详细设计说明书-Android.md",
    "Docs/Doyah产品详细设计说明书-iOS.md",
    "Docs/Doyah产品详细设计说明书-HarmonyOS.md",
    # 2026-10-23：macOS 端开发计划书（有表格 ⇒ 进受检；本端执行计划，不改状态源）
    "Docs/Doyah产品开发计划书-macOS端.md",
    "Docs/Doyah产品开发计划书-安卓端.md",
    "Docs/模板-详细设计说明书-Studio.md",  # 2026-10-21 详设模板（入库件）
    "Docs/规范/界面设计节-写作规范.md",  # 2026-10-22 界面设计规范进仓（对侧无本侧技能包，规则跟着代码走）
    "Docs/Doyah产品需求规格说明书-追溯表.md",  # 2026-10-20 从 SRS §9.1 外置（瘦身令），必须入库
    "Docs/Doyah产品能力规划说明书-变更记录.md",
    "Docs/Doyah产品概要设计说明书-变更记录.md",
    "Docs/Doyah产品开发计划书.md",
    "Docs/人工点验清单-20261018.md",
    "Docs/人工点验清单-20261018-重分版.md",
    "Docs/design/store/README.md",
    "Docs/Doyah产品需求规格说明书.md",
    "Docs/design/规划-工作区Markdown预览与内置浏览器-20260930.md",
    "Docs/Doyah产品能力规划说明书.md",
    "Docs/Doyah产品概要设计说明书.md",
    "Docs/Doyah产品详细设计说明书-macOS.md",
    "Docs/README.md",
    "Docs/功能清单（一页纸）.md",
    "Docs/功能清单（管理视图）.md",
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
    "Docs/智能体助手-开发spec.md",
    "Docs/平台对齐-Studio-Windows对macOS.md",
    "Docs/任务清单-按平台.md",
    "Docs/智能体助手-核心能力扩展-草案-v0.1.md",
    "Docs/Doyah产品需求规格说明书-变更记录.md",
    "Docs/Doyah产品需求规格说明书-需求索引.md",
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
    # 2026-10-11 · 派单 `T-20261011-014`（人类主人令「台账归台账、契约归契约」）：`智能体助手-开发spec.md`
    # 入库 ⇒ 从本名单移除、加进 `SELF_TEST_TRACKED`；被排除数 13 → 12、受控夹具 35 → 36。
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
    skipped: list[str] = []
    total = 0

    # 本机台账（`.gitignore` 内、只在主开发机上的那几份）在不在盘上 —— 决定**要看真仓库那几份台账**
    # 的两例（例 4 的真仓库断言 / 例 5 的写坏队列副本）能不能在这台机器上真跑。
    # 口径出处：`AGENT-SPEC.md` §9 第 147 条 ④（本机台账类判据一律「不在盘上就跳过 + 高声提示」）；
    # 干净克隆 / 并行工作树 / 另一平台必然没有它们 —— 原先例 5 崩、例 4 假红（任务 `t_004a679b`）。
    absent_host_ledgers = [
        relative for relative in SELF_TEST_ABSENT if not (repository / relative).exists()
    ]
    # 「**全缺**」= 台账根本不在这台机器上（干净克隆 / 并行工作树 / 另一平台）⇒ 跳过；
    # 「**缺一部分**」= 其余台账在盘上 ⇒ 这里就是主开发机，缺的那几份是**被删或路径写错** ⇒ 照旧判红。
    host_ledgers_absent_entirely = len(absent_host_ledgers) == len(SELF_TEST_ABSENT)

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


        # 夹具里立一个**真的 git 仓库**（`gitignored_documents()` 靠 `git check-ignore`）：`.gitignore`
        # 逐条列出 `SELF_TEST_ABSENT`（那批就是「被 .gitignore 排除的本机台账」）⇒ 例 1 的「跳过 12 份」
        # 是**经对账**的（与 gitignore 名单核过），例 17 才能验「tracked 文档被删 ⇒ 判红」（原单 ㈡）。
        subprocess.run(["git", "init", "-q"], cwd=str(clone), capture_output=True, text=True)
        (clone / ".gitignore").write_text(
            "\n".join(SELF_TEST_ABSENT) + "\n", encoding="utf-8"
        )

        # 例 1·干净克隆（默认清单，缺 12 份）→ exit 0 且**高声提示**、不得静默
        total += 1
        code, output = run([], clone)
        if code != 0:
            failures.append(f"例 1 失败：干净克隆上默认跑应 exit 0，实际 {code}\n{output}")
        elif "⚠ 跳过 12 份" not in output:
            failures.append(f"例 1 失败：没有高声提示「跳过 12 份」（不得静默通过）\n{output}")
        elif not re.search(r"✅ 表格校验通过（(\d+) 个文件，跳过 12 份）", output):
            failures.append(f"例 1 失败：收尾行没有如实写出跳过数\n{output}")
        elif int(re.search(r"✅ 表格校验通过（(\d+) 个文件，跳过 12 份）", output).group(1)) < 40:
            # 文件数是随仓库增长的（本片实测 70 份）—— 这里只保「不是空跑」，不再钉死某一个数，
            # 否则每加一份文档就要改一次自检（本来就该让它跟着真相走）。
            failures.append(f"例 1 失败：文件数低于空跑下限 40\n{output}")
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
        broken = queue_source.read_text(encoding="utf-8") if queue_source.exists() else None
        if broken is None and not host_ledgers_absent_entirely:
            # 主开发机（其余本机台账在盘上）却缺这一份 ⇒ 文档被删或路径写错，判红。
            failures.append(
                "例 5 准备失败：本机台账 `Docs/design/开发循环-任务队列.md` 不在盘上，"
                "而其余本机台账在盘上（主开发机上文档被删或路径写错）"
            )
        elif broken is None:
            # 本机台账不在盘上（干净克隆 / 并行工作树 / 另一平台）⇒ 本项**跳过 + 高声提示**：
            # 不崩、也不判红（口径见函数头注释与 `AGENT-SPEC.md` §9 第 147 条 ④）。
            skipped.append(
                "例 5（把队列副本一行写坏 ⇒ 必须 exit 1 并指名行号）："
                "本机台账 `Docs/design/开发循环-任务队列.md` 不在盘上"
            )
        elif broken.count(anchor) != 1:
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

        # 例 9（T-20261011-001 · 2026-10-11）·判据 F 两面：同一张表被**空行**截断成两张
        # （表头逐格相同）⇒ 判红并指名行号；**对照**（表头不同）= 两张真表 ⇒ exit 0。
        # 夹具放在扫描面之外（同例 5 的理由：别同时触发判据 E，把两件事混在一条输出里）。
        total += 1
        split_table = clone / "fixture/空行拆表.md"
        split_table.parent.mkdir(exist_ok=True)
        split_table.write_text(
            "# 空行拆表\n\n| 甲 | 乙 |\n|---|---|\n| 1 | 2 |\n\n| 甲 | 乙 |\n|---|---|\n| 3 | 4 |\n"
        )
        code, output = run([split_table.relative_to(clone).as_posix()], clone)
        if code == 0:
            failures.append(f"例 9 失败：表头逐格相同的相邻两表仍 exit 0 —— 判据 F 是空的\n{output}")
        elif ":3:" not in output or "表头逐格相同" not in output:
            failures.append(f"例 9 失败：判红了但没有指名「表头逐格相同」与行号（应为 3 / 7）\n{output}")
        else:
            split_table.write_text(
                "# 两张表\n\n| 甲 | 乙 |\n|---|---|\n| 1 | 2 |\n\n| 丙 | 丁 |\n|---|---|\n| 3 | 4 |\n"
            )
            code, output = run([split_table.relative_to(clone).as_posix()], clone)
            if code != 0:
                failures.append(f"例 9 失败：表头不同的两张表应 exit 0（对照），实际 {code}\n{output}")
        split_table.unlink()

        # ── 原单 T-20261010-070 的负例族（例 10~17；合册 T-20261013-027 销账）────────────

        # 例 10（㈠）·GFM 无首竖线的表格：显式点名 ⇒ 判红「列数 2 != 表头 3」；
        # 对照臂 = 同一内容**带首竖线**（标准写法）⇒ 同样的读数（「行首竖线」不再是唯一入口）。
        total += 1
        gfm = clone / "fixture/无首竖线表.md"
        gfm.parent.mkdir(exist_ok=True)
        gfm.write_text("# 无首竖线\n\n甲 | 乙 | 丙\n--- | --- | ---\n1 | 2\n", encoding="utf-8")
        code, output = run([gfm.relative_to(clone).as_posix()], clone)
        gfm.write_text("# 标准写法\n\n| 甲 | 乙 | 丙 |\n|---|---|---|\n| 1 | 2 |\n", encoding="utf-8")
        code_arm, output_arm = run([gfm.relative_to(clone).as_posix()], clone)
        if code == 0 or "列数 2 != 表头 3" not in output:
            failures.append(
                f"例 10 失败：无首竖线的表格（少一格）应判红并报「列数 2 != 表头 3」，实际 rc={code}\n{output}"
            )
        elif code_arm == 0 or "列数 2 != 表头 3" not in output_arm:
            failures.append(
                f"例 10 失败：对照臂（标准写法）读数应与无首竖线写法一致，实际 rc={code_arm}\n{output_arm}"
            )
        gfm.unlink()

        # 例 11（㈠ 的判据 E 面）·无首竖线的表格放进扫描面且不被点名 ⇒ 判据 E 也要看得见
        total += 1
        gfm_doc = clone / "Docs/新-无首竖线表-未登记.md"
        gfm_doc.write_text("# 新台账\n\n甲 | 乙\n--- | ---\n1 | 2\n", encoding="utf-8")
        code, output = run([], clone)
        if code == 0:
            failures.append(
                f"例 11 失败：带（无首竖线）表格却不在清单里的文档没被判红 —— 判据 E 还是「行首竖线」口径（原单 ㈠）\n{output}"
            )
        elif "Docs/新-无首竖线表-未登记.md 有表格却不在受检清单里" not in output:
            failures.append(f"例 11 失败：判红了但没有点名那份文档\n{output}")
        gfm_doc.unlink()

        # 例 12（㈢）·判据 E 与 check() 口径对齐：正文只有一行含竖线 ⇒ 块长 < 2 不算表 ⇒ 不判
        total += 1
        single = clone / "Docs/单行竖线-不算表.md"
        single.write_text("# 单行\n\n| 只是散文里的一个竖线\n", encoding="utf-8")
        code, output = run([], clone)
        if code != 0:
            failures.append(
                f"例 12 失败：只有一行竖线的文档不该算表格（块长 < 2 不算，原单 ㈢），实际 rc={code}\n{output}"
            )
        single.unlink()
        # 例 13（㈣）·续行白名单收紧：`**加粗**` 开头的真续行 ⇒ 判红；`- 列表项` ⇒ 不误报
        total += 1
        cont = clone / "fixture/续行白名单.md"
        cont.parent.mkdir(exist_ok=True)
        cont.write_text("# 续行\n\n| 甲 | 乙 |\n|---|---|\n| 1 | 2 |\n**加粗**尾巴 | 3 | 4 |\n", encoding="utf-8")
        code, output = run([cont.relative_to(clone).as_posix()], clone)
        if code == 0:
            failures.append(
                f"例 13 失败：`**加粗**` 开头的续行仍 exit 0 —— `*` 把它一并放走了（原单 ㈣）\n{output}"
            )
        elif "疑似**表格续行**" not in output:
            failures.append(f"例 13 失败：判红了但没有报「疑似**表格续行**」\n{output}")
        else:
            cont.write_text("# 续行\n\n| 甲 | 乙 |\n|---|---|\n| 1 | 2 |\n- 列表项\n", encoding="utf-8")
            code, output = run([cont.relative_to(clone).as_posix()], clone)
            if code != 0:
                failures.append(
                    f"例 13 失败：`- 列表项` 自己开了新块、不该算续行（对照臂），实际 rc={code}\n{output}"
                )
        cont.unlink()

        # 例 14（㈤(a)）·索引表体中断：首条数据行行首多一个空格 ⇒ 判红 + 报行号 + 「表体在此中断」
        # 2026-10-20：索引已从需求书正文 §10.1 外置成 `Docs/Doyah产品需求规格说明书-需求索引.md`
        # （状态列整批迁走后只剩「编号 / 所属域 / 层次」三列），夹具跟着改锚点。
        total += 1
        idx_copy = clone / "Docs/Doyah产品需求规格说明书-需求索引.md"
        original_idx = idx_copy.read_text(encoding="utf-8")
        idx_lines = original_idx.splitlines()
        header_at = idx_lines.index("| 编号 | 所属域 / 章节 | 层次 |")
        idx_lines[header_at + 2] = " " + idx_lines[header_at + 2]
        idx_copy.write_text("\n".join(idx_lines) + "\n", encoding="utf-8")
        code, output = run([], clone)
        if code == 0:
            failures.append(f"例 14 失败：索引表体被行首空格打断仍 exit 0（原单 ㈤(a)）\n{output}")
        elif "表体在此中断" not in output or f":{header_at + 3}:" not in output:
            failures.append(
                f"例 14 失败：判红了但没有报「表体在此中断」与行号（应为 {header_at + 3}）\n{output}"
            )
        idx_copy.write_text(original_idx, encoding="utf-8")

        # 例 15（㈤(b)）·一套切分口径：格内写合法转义（反斜杠 + 竖线）⇒ rc=0（旧版此处判红）
        total += 1
        idx_lines = original_idx.splitlines()
        row_at = header_at + 2
        cells = idx_lines[row_at].split("|")
        cells[2] = cells[2] + chr(92) + "| 浏览器"
        idx_lines[row_at] = "|".join(cells)
        idx_copy.write_text("\n".join(idx_lines) + "\n", encoding="utf-8")
        code, output = run([], clone)
        if code != 0:
            failures.append(
                f"例 15 失败：格内写合法转义的竖线不该判红（切分要与 split_row 一套口径，原单 ㈤(b)），实际 rc={code}\n{output}"
            )
        idx_copy.write_text(original_idx, encoding="utf-8")
        # 例 16（㈥）·取格兜底：索引行缺一格 ⇒ 打印已收集的诊断 + 「格数不足」，不许 IndexError
        total += 1
        idx_lines = original_idx.splitlines()
        cells = idx_lines[row_at].split("|")
        del cells[2]
        idx_lines[row_at] = "|".join(cells)
        idx_copy.write_text("\n".join(idx_lines) + "\n", encoding="utf-8")
        code, output = run([], clone)
        if code == 0:
            failures.append(f"例 16 失败：索引行缺一格应判红（原单 ㈥）\n{output}")
        elif "Traceback" in output or "IndexError" in output:
            failures.append(
                f"例 16 失败：缺一格时崩了（IndexError / traceback）—— 已收集的诊断全丢\n{output}"
            )
        elif "格数不足 3" not in output or "❌ 表格校验失败" not in output:
            failures.append(
                f"例 16 失败：判红了但没有报「格数不足 3」/ 没有把人读的失败清单打出来\n{output}"
            )
        idx_copy.write_text(original_idx, encoding="utf-8")

        # 例 17（㈡）·在场下限：删掉一份 tracked 文档（不在 .gitignore 名单里）⇒ 本件自己判红并点名
        total += 1
        capability_doc = clone / "Docs/Doyah产品能力规划说明书.md"
        capability_backup = capability_doc.read_text(encoding="utf-8")
        capability_doc.unlink()
        code, output = run([], clone)
        if code == 0:
            failures.append(
                f"例 17 失败：删掉 tracked 文档（不在 .gitignore 名单里）仍 exit 0 —— 面无下限（原单 ㈡）\n{output}"
            )
        elif "Doyah产品能力规划说明书.md" not in output or "被删或路径写错" not in output:
            failures.append(
                f"例 17 失败：判红了但没有点名被删的文档 / 没说「被删或路径写错」\n{output}"
            )
        capability_doc.write_text(capability_backup, encoding="utf-8")

        # 例 4·真仓库（本机）→ exit 0、跳过 0，且**末例核对真仓库逐字节未变**
        total += 1
        before = (repository / "Docs/Doyah产品概要设计说明书.md").read_bytes()
        code, output = run([], repository)
        after = (repository / "Docs/Doyah产品概要设计说明书.md").read_bytes()
        if code != 0:
            failures.append(f"例 4 失败：真仓库上应 exit 0，实际 {code}\n{output}")
        elif host_ledgers_absent_entirely:
            # 真仓库里那几份本机台账**整批**不在盘上 ⇒「68 份命名全在 / 不许出现跳过行 / 实跑 69 个文件」
            # 这三条**在这台机器上核不了**（口径同例 5）⇒ 本项跳过 + 高声提示；
            # 仍然断言另一半：缺台账时如实报「跳过」，不是崩、也不是静默。
            # （只缺一部分时走下面的严格分支 —— 那是主开发机上文档被删。）
            if "跳过" not in output:
                failures.append(
                    f"例 4 失败：本机台账缺席时应如实报「跳过」（不得静默通过），实际输出里没有跳过行\n{output}"
                )
            else:
                skipped.append(
                    "例 4（真仓库 69 份命名文档全在、实跑 70 个文件、无跳过行）："
                    f"{len(absent_host_ledgers)} 份本机台账不在盘上（干净克隆 / 并行工作树 / 另一平台）"
                )
        elif "跳过" in output:
            failures.append(f"例 4 失败：真仓库 69 份命名文档应全在（不得出现跳过行）\n{output}")
        elif "ℹ️ 本机台账通配：Docs/开发记录-*.md → 本机 1 份" not in output:
            failures.append(f"例 4 失败：主开发机上开发记录应为 1 份（通配匹配数异常 ⇒ 文件被删或路径写错）\n{output}")
        elif "✅ 表格校验通过（70 个文件）" not in output:
            failures.append(f"例 4 失败：收尾行应为 70 个文件（69 份命名 + 1 份通配）\n{output}")
        if before != after:
            failures.append("例 4 失败：自检动了真仓库的文档（逐字节不一致）")

        # 例 8（提案 0005，第 91 轮）·跨平台标识：判据 E 的立足点就是「磁盘上的相对路径 == 手抄清单里的写法」。
        # Windows 上 `str(WindowsPath)` 给反斜杠（清单写正斜杠）⇒ 清单匹配**恒 False**、**只在那台机器上红**
        # （对侧第 81 轮实测：26 处「有表格却不在受检清单里」）。这里在 macOS 上用 `PureWindowsPath`
        # 复现「那台机器会得到的标识」，红 / 绿成对。
        total += 1
        windows_style = str(pathlib.PureWindowsPath("Docs/Doyah产品概要设计说明书.md"))
        if windows_style == "Docs/Doyah产品概要设计说明书.md":
            failures.append("例 8 失败：`PureWindowsPath` 在本机给出的形态与预期不符（夹具前提不成立）")
        elif identity_text(windows_style) != "Docs/Doyah产品概要设计说明书.md":
            failures.append(
                f"例 8 失败：`identity_text({windows_style!r})` 给 {identity_text(windows_style)!r}，"
                "应落回清单写法（Windows 形态的相对路径必须归一到正斜杠）"
            )
        elif identity_text(pathlib.Path("Docs/Doyah产品概要设计说明书.md")) != "Docs/Doyah产品概要设计说明书.md":
            failures.append("例 8 失败：本机形态（PosixPath）经 identity_text 后应逐字不变")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    if failures:
        print(f"❌ 自检失败（{len(failures)}/{total}）：")
        for failure in failures:
            print("   " + failure)
        return 1

    # 收尾行里那份「例 4 / 例 5 的结论」（真仓库 69 份无跳过）只在**真跑过**时才算数；
    # 跳过时如实换掉措辞（跳过的例不许冒充跑过 —— 跳过 ≠ 通过）。
    tail = (
        "真仓库 69 份无跳过"
        if not skipped
        else "真仓库那两例在这台机器上不适用（本机台账不在盘上，见上面的跳过提示）"
    )
    if skipped:
        print(f"⚠ 跳过 {len(skipped)} 例（本机台账不在盘上 —— 干净克隆 / 并行工作树 / 另一平台；**跳过 ≠ 通过**）：")
        for item in skipped:
            print("   · " + item)
        print("   在主开发机上跑同一条命令，这几例必须真跑；其余各例在两种机器上都照跑。")
    suffix = f"，跳过 {len(skipped)} 例" if skipped else ""
    # 收尾行的**头部格式不许动**（`self-test-counts.json` 的 countRegex 就认
    # `自检通过（N/M）`）⇒ 跳过数写在方括号外的 `suffix` 位置，别挤进括号里。
    print(f"✅ 自检通过（{total}/{total}）{suffix}：干净克隆跳过 12 份且 exit 0 / --require-all 判红 / 显式点名判红 / 写坏一行被判红并指名行号 / 带表格不在清单判红且归档豁免 / 空行拆表（表头逐格相同）判红且对照（表头不同）不判红 / 跨平台标识（Windows 形态落回清单写法）/ GFM 无首竖线表也判（显式点名 + 判据 E 两面）/ 单行竖线不算表 / 加粗开头的续行判红且列表项不误报 / §10.1 表体中断指名行号 / 格内转义竖线不判红 / FR 行缺格报「格数不足」不崩 / tracked 文档被删判红（在场下限）/ {tail}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
