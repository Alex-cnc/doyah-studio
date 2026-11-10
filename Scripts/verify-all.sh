#!/bin/bash
set -euo pipefail

# 本工程的一条命令验证闭环。
#
# 拆开跑过很多次、也就漏跑过很多次（尤其是文档计数与设计令牌这两项），
# 所以合成一条：**改完代码跑它，十九项全过才算完**。
#
# ⚠️ **中止行为与「未执行项」**（队列 L-110，2026-10-11 第 488 轮）：本脚本是 `set -euo pipefail`
# —— 失败**当场中止**，后面的项**根本没跑**（2026-09-30 实测：第 1 项红了 ⇒ 只能报「第 1 项红」，
# 当时文档里那句「十九项里只有第 1 项红」是**没有证据**的写法：**未执行 ≠ 通过**）。现在两条都成机制：
#   · 默认跑法：中止前由 `ERR` 陷阱**自己打印**「失败的是第几项 / 脚本第几行 / **哪些项没跑**」；
#   · `./Scripts/verify-all.sh --keep-going`：**跑完再汇总** —— 单项失败不中止，收尾给一张
#     逐项判定表（通过 / 失败（含行号）/ 平台跳过），有失败则统一 `exit 1`；
#   · 判据自己的证据 = `Scripts/test-verify-all-gate.py` 的 **8 例**（把**本文件原样**拷进临时迷你仓，
#     桩件注入失败 ⇒ 断言两种跑法各自的话都说得对）。
# 失败行的行号 → 项号由**本文件自己的项块行**翻译（与 `check-doc-numbers.py` 的 `gate-scan` 同源）。
#
#   1. Core 单测（SwiftPM，不需要数据库）+ 平台适配层单测
#   2. Core 平台中立性（Core 里不得出现平台专属依赖 —— 否则 Linux 编译不过）
#   3. 本地化：Core 展示文本棘轮（R-037：用户可见文案不得硬编码中文，只能比基线更少）
#      + 「当前语言只有一个来源」（L-13：显式传语言必须走 `effectiveLanguage`）
#      + 语言表**模板占位符 ↔ 调用点实参**对账（L-46：数字实参落 `%@` 槽 / 字符串落数字槽 /
#        实参数 ≠ 占位符数 / 类型不明的实参逐条登记形状 + 双向棘轮，
#        见 `check-format-arguments.py` 与 `format-argument-dispositions.json`）
#      + **文案即所见**（L-19：语言表里不得有 markdown 强调标记 `**`、渲染点不得再出现
#        `LocalizedStringKey` —— 有 4 个键的文案会流进没有 markdown 的通道（状态栏 / 备份恢复日志
#        / `Label` 的 `String` 重载），所以口径只能是纯文本；见 `check-copy-emphasis.py`）
#      + **语言是传进来的，不是写死的**（L-47：写死语言的调用点逐条登记 + 死译文双向对账 +
#        `DiagnosisContext` / `DiagnosisAdvice` 的文本出口必须带 `language:` 形参；见
#        `check-literal-language.py` 与 `literal-language-dispositions.json`）
#      + **写死的英文展示文案**（L-109：上面那条汉字棘轮的窄口是 `HAN = 汉字` ⇒ 写死的英文
#        展示文案全绿（`L-108` 那句 `"Home"` 就是这么漏的）。同一脚本的第二条棘轮 = 白名单
#        `Scripts/core-localization-english.json`：Core 里「像展示文案的英文字面量」必须逐条
#        登记并写清 `kind`（为什么它不是展示文案；确实直达界面的写 `displayDebt` = 已登记欠账），
#        **白名单之外一律报红、白名单只许缩小**；豁免文件（语言表 + 代码语言登记表）逐条登记、
#        与脚本双向对账）
#   4. 文档表格列数与派生计数一致
#      + 变更记录版本号唯一 / 头部版本格可判 / 队列条目号唯一（L-32）
#      + **文档数字的唯一来源**（L-55：闭环项数 / 单测数 / 快照张数收进台账
#        `Scripts/doc-numbers.json`，做「台账 ↔ 实测 ↔ 文档」三向对账 —— 见本项尾部注释）
#      + **§6 待拍板队列的编号与状态纪律**（L-56：编号唯一 / 状态只写词表词 / 与 §4 同源 ——
#        这一节是探针「需用户介入」行的来源，`Q19` 曾因此每轮被报成待拍板项；
#        见 `Scripts/check-doc-q-series.py`）
#      + **门禁自己的证据：例数的唯一来源**（L-72 ㈠：28 族的负例 / 自检例数收进台账
#        `Scripts/self-test-counts.json`，判据 `Scripts/check-self-test-counts.py` 把每一族 runner
#        **真跑一遍**（要求 exit 0）、再与台账和文档里的现状声明逐处对账 —— 此前 `test-*.py`
#        14 个里 **8 个根本没人跑**，其中一个已经坏在第 3 例而无人知）
#   5. 需求状态一致性（一单 §3 台账 ↔ 其它文档状态括注）
#      + **版本范围**（2026-10-20 人类主人令）：哪个版本做哪些需求，由版本计划说清 ——
#        台账 §3 的 `版本` / `版本口径` 两列就是范围台账，判据 = 版本 ⊆ 四档 / alpha 行口径必为 `—` /
#        非 alpha 行口径非空 / 编号唯一 / 空跑防护。旧做法（需求行内写 `[alpha 不含]` +
#        独立账 `alpha-fr-dispositions.json`）已退役，文件归档在 `Scripts/archive/`。
#      + **台账 ↔ 需求索引覆盖 + §4.2 条数**（`check-plan-coverage.py`，2026-11-03 接进闭环）
#      + **派生队列 ↔ 台账一致 + `next_try` 只认规则表**（`plan-batches.py --check`，2026-11-03
#        接进闭环；覆盖范围 = 规则表里有条目的 blocked，跨版携带的逐条打印「未经规则表核对」）
#   6. 设计令牌棘轮（App/ 里的裸颜色 / 裸字号 / 裸间距不得比基线更差）
#   7. 平台等价矩阵（§10.10 ↔ `Docs/平台实现状态.json` 台账，列由台账决定）+ 台账校验自检
#      + `P-*` 平台差异登记的两侧对账（§10.9 ↔ 概要设计 §4：双向覆盖 + 同号同物
#      + §8.5.5「已落条但未并入」判红，队列 L-45）
#      （**2026-09-27 第 25~36 轮之间这一行的注释写着「与 §10.9 登记表一致」，那是不折不扣的假话**：
#      当时这一项只做 §10.10 ↔ 台账的矩阵对账，`§10.9 ↔ §4` 一个判据都没有 —— 第 36 轮（L-45）
#      补上第三个脚本后，这句话才成立；注释里的假话先被改正，判据随后补上）
#   8. 平台中立性棘轮（需求规范书里的平台专属词汇不得比基线更差）
#   9. 界面台账三条（大结果集滚动阈值 / 性能读数表 / 模型服务预设）。
#      **2026-11-10 判据搬家第三批（UI 交互 9 条）**把原先挤在这一项里的六条界面判据逐条处置掉了：
#      空数据按钮（L-50）与编辑面行号（L-111）搬进 `swift test`；命令面板接线、侧边栏折叠状态（L-59）、
#      面板根对齐（L-61）、终端多会话页签（L-84）摘离 —— 它们的那几件事各有更强的接手方
#      （真调用探针 / 像素逐字节探针 / Core 单测 + 真 shell 探针），逐条对照见本项正文那段留痕。
#  10. 插件装配链（笔记模块解耦 FR-STD-ALL-PLUG-007 + 装配与许可 FR-STD-ALL-PLUG-001/02/03/06 + ADR-35）
#      + 笔记模块的**零网络出口**（FR-STD-ALL-PLUG-005 ②：数据不外发，见 `check-notes-offline.py`）
#      + **界面检索走库 + 路线如实标注**（L-44：唯一生产点 / 视图不许内存过滤 /
#        路线逐条登记 / 文案键在位且被引用，见 `check-note-search-route.py`）
#      + **Markdown 解析只有一份**（L-137：行内扫描器唯一定义在笔记侧 / 块级模型只由
#        契约层构造 / 预览真的调用同一个行内函数 / 不引第三方 Markdown 库，
#        见 `check-markdown-single-source.py`）
#  11. 打包 .app（沙箱构建）+ **菜单栏那一层在换语言后不许停在启动语言**（L-145，内测丙2）
#      + **平台矩阵**（NFR-ALL-GATE-COMP-004/005：部署目标四处一致 / 产物带最低版本键 / 三档架构）
#  12. 脚本 shell 多字节安全（bash 3.2 的变量名坑，见 `check-shell-locale-safety.py`）
#  13. 脚本连接信息参数化（连真库的脚本不许写死端口 / 地址 / 账号，见 `check-script-env-parameterization.py`）
#  14. 连接失败的文案覆盖面（驱动错误码 ↔ 文案台账，见 `check-connection-failure-coverage.py`）
#  15. 命令行失败输出的可读化覆盖面（L-15：不许出现「有话说却直接打英文串」的 print，
#      见 `check-cli-failure-readability.py`）
#  16. 越界检查（分层的三书「形态 A」：一次改动不得落在**对侧独占节**内 ——
#      `[独占:macos]` / `[独占:windows]` 标记的节各归其主，见 `check-exclusive-sections.py`）
#  17. vendored SQLite（FR-STD-ALL-PLUG-008 / Q23）：台账对账 + 负例自检 + 现编现跑自证
#      （`check-vendored-sqlite.py`｜`--self-test`｜`smoke-vendored-sqlite.py`）
#      + **笔记存储统一**（同一需求的 ①②③：一份 DDL / 附件只存路径 / 版本单一写者，
#        `check-note-storage-unity.py`｜其 `--self-test` 7 例）
#  18. 生成物一致性（两族）：**生成物不许手改、也不许过期**
#      · 族 ①（L-43，2026-09-27 第 30 轮）：`gen-sqlite-constants.py --check`
#        （`Core/NoteStorage/SQLiteConstants.swift` 与 vendored 头文件逐字节一致）
#        + `--self-test`（5 条篡改都要报红并指名出处）
#      · 族 ②（**L-70，2026-09-28 第 68 轮**）：`check-release-version.py`
#        —— 发布产物版本号的**一个值、三处逐字一致**（`build-app.sh` 的 Info.plist 模板 = 权威／
#        `project.yml` = 源／`.xcodeproj/project.pbxproj` = 生成物，台账 `Scripts/release-version.json`）
#        + **生成物 ↔ 源不许漂移**（目标名 / 包标识 / 每个目标的 `*.swift` 文件名集合，双向；**源目录里的
#        点目录 = 构建残留，不算源码** —— `platform/<平台>/` 自洽包布局下包根就是目标源目录（任务
#        `t_7325ffbf`）：磁盘侧跳过它、**反向还判「生成物不许引用点目录下的 `.swift`」**，因为
#        `xcodegen` 不读 `.gitignore`、会把残留收进生成物并把前一条红**抵消成绿**）
#        + **身份两半分开判**（2026-11-03 修）：`marketingVersion` 由发布标签派生（`beta1.0` → `1.0.0`）
#        ⇒ 权威处 / `project.yml` / 生成物逐字一致；`buildVersion` 是**每次构建的提交数** ⇒ 不登记字面量、
#        产物那一处只判纯数字（逐字相等由 `build-app.sh` 写盘后 `PlistBuddy` 读回自证）。
#        + `--self-test`（19 例：三处各改一处、台账快照改一处、派生式退回字面量、现状声明被删、
#        产物构建号不是数字、生成物少目标 / 少源文件 / 被掏空、锚点写错
#        都要报红；**发布标签那一族** —— 定义值被改 / plist 模板里手抄标签 / 产物名写死 /
#        `dist/` 实物与别名各错一种，也都要报红，另有一例「实物 + 别名都对 ⇒ 绿」；例 1 = 干净夹具 + 源目录里的点目录残留 ⇒ 绿，同一夹具在**点目录之外**多一个 `.swift` ⇒ 红（对照：跳过没把判据掏空）；末例核对真仓库逐字节未变）。**为什么要有它**：`.xcodeproj` 在本仓**没有任何门禁**
#        （`build-app.sh` 走 SwiftPM，根本不读它）⇒ 入库那份曾经 869 行、包标识还是改名前的
#        `com.vnull.PostgresClient*`、且**少了两个目标**，从 2026-09-22 起就一直过期而无人知
#        （`Docs/archive/root-20261026/项目评审-2026-09-23.md` 把这条记成风险，但风险没有判据）。
#  19. 台账两列一致（实现列 ↔ 判据列）：**实现已 ✅ 而判据还是 ⬜/🟡 的行必须为 0**
#      （`check-status-gap.py`｜其 `--self-test` 5 例）。`—`（不适用）与 `➖`（挂起 · 暂不支持）两档
#      不判红，但**逐条点名**打印 —— 免得这两档被当成逃生门。它只查**格子形状**，
#      不查「✅ 是否名副其实」（后者归每条自己的证据文件与本闭环的其余项）。
#
# 第 18 项是 2026-09-27（队列 L-43）补的：生成器与 `--check` 早就写好，**脚本头部自己也写着
# 「本 check 未接进 verify-all」** —— 有判据、没闭环，等于手改一行生成物、或头文件换版后忘了
# 重生成，谁都不会报红（编译照过、单测照绿，只有三端行为悄悄不一致）。除接进闭环外，
# 「生成器 ↔ 生成物 ↔ vendored 头文件」三者的绑定也登记进 `Scripts/vendored-sqlite.json`
# 的 `generator` 节点，由第 17 项的台账门禁逐条对账（台账撒谎 / 接线被删照样报红）。
#
# 第 8 项是 2026-09-23 补的：那天发现命令面板有 9 条命令「设了标志位但没人读」，
# 用户点了完全没反应，而当时已有的 7 项门禁**全部看不见**这类缺陷（编译、单测、
# 文档、令牌、矩阵、打包全过）。所以"命令列出来了"与"命令真能打开东西"之间补一道闸。
#
# 第 10 项 2026-09-26（L-04）改了两处：① 加了 `check-plugin-assembly.py`（原先只有解耦一条）；
# ② **失败要真的让闭环失败** —— 原写法 `if ...; then :; else FAILED=1; fi` 把 FAILED 记下来
# 却没人读，结尾照样打印"全部通过"并以 0 退出（门禁红着、闭环绿着的假绿）。
# 现在两条都直接跑：`set -e` 会让失败当场中止并给出非零退出码。
#
# 第 12 项 2026-09-26（L-05）补的：macOS 自带 `/bin/bash` 是 **3.2.57**，而本工程脚本的 Shebang
# 全是 `#!/bin/bash`。实测：`echo "中文：$X）"` 在 bash 3.2 下会把 `$X` **静默展开成空**（后一个
# 字符也被切坏）；加了 `set -u` 则直接 `X?: unbound variable` 中止脚本。而这类写法在证据脚本里
# 是**不报错的**——脚本照常 exit 0、照常打勾，只是那一行的值空了（与第 10 项那次的假绿同一族）。
# 修法：变量写成 `${X}`。门禁 `check-shell-locale-safety.py` 把这个坑变成机械检查。
#
# 第 14 项 2026-09-26（L-14）补的：驱动是随仓库带走的 Vendor，升版可能多出新的 `PSQLError.Code`，
# 而文案层的 `switch` 有 `default:` 兜底 —— 新原因**不会报错**，只会被说成一句与它无关的话。
# L-14 修掉的正是这一族：主机名解析不了被驱动压成 `serverClosedConnection`
# 且不带原因，用户看到的是「与数据库的连接中断了」。门禁把「每个码怎么处置」变成台账
# （`Scripts/connection-failure-dispositions.json`）与驱动源码、映射文件、解析前置检查、证据脚本逐条对账。
# 第 32 轮（合册 T-20261013-027 · 原单 T-20261010-042）：覆盖面升为**分驱动**（台账 `drivers[]`：Postgres 19 码 + MySQL/GBase 支 `MySQLError` 12 码 + 协议数字码表 1144 条
# 逐名名单 + `Core/MySQLWording.swift` 8 个文案出口面）—— 单驱动结构装不下第二支驱动，往 MySQL 加码原先门禁逐字不动。
# 第 8 轮（R-051）又加了两条：**兜底不许给方向结论**（`default:` 必须 `return nil`），
# 以及台账标「中性归因」的那 9 个码（用户取消 / 主动断开 / 协议层 / LISTEN 通道…）
# 必须在 `nonConnectionKeys` 里逐条点名 + 给出语言表键，且**调用方真的接上了这一档**
# （CLI / ErrorPresenter / 连接表单）—— 否则 `describe` 返回 nil 时用户只剩一句英文调试串。
#
# 平台口径（L-33，2026-09-27 第 29 轮）：本闭环**在非 macOS 机器上也能跑**，方式是——
#   · **第 1 / 11 项（要 Xcode 工具链）按平台跳过 + 打印提示**，收尾行如实报「跑了几项 / 跳了几项」，
#     **跳过 ≠ 通过**（逐条列出跳过的项，并指向 §8.3 / §8.5.3 的等价物）；
#   · 第 4 项里 12 份被 `.gitignore` 排除的本地文档**不存在即跳过并提示**（显式点名 / `--require-all` 判红）；
#   · `DOYAH_PLATFORM=macos|windows|linux` 显式声明平台（缺省按 `uname -s` 推断）；
#   · `./Scripts/verify-all.sh --require-all` = **跳过即红**（主开发机上自我证明用）。
#
# 默认就是非沙箱构建（交付口径）：./Scripts/build-app.sh
# 要试沙箱那一面（上架只走沙箱）：DOYAH_SANDBOX=1 ./Scripts/build-app.sh

SCRIPT_PATH="$0"   # L-110：项表要读**本文件自己**（`cd` 之后相对路径就取不到了）
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${ROOT}"

# ── 平台判定与「跳过」语义（L-33，开发循环第 29 轮）────────────────────────────
# 十九项里有 **两项是 macOS 专属**：第 1 项（Core 单测）与第 11 项（打包 .app）——
# 两者都要 Xcode 工具链（`DEVELOPER_DIR` → `/Applications/Xcode.app/Contents/Developer`；两份脚本各自在设置段
# `${DEVELOPER_DIR:-…}` 兜底并可被外部覆盖，且每次跑都把工具链版本打进输出 —— 回执可复现，见单 T-20261009-095 ②）。
# 在非 macOS 机器（另一平台 / Linux）上跑，原先会以「命令或路径不存在」的形式**硬失败**，
# 看起来像门禁红了，其实只是平台不适用（对侧逐项实测见 `Docs/Doyah产品概要设计说明书.md` §8.5.6-4）。
# 现在的口径：**按平台跳过 + 打印提示**，且**跳过 ≠ 通过** —— 收尾行如实写「跑了几项 / 跳了几项」
# 并逐条列出跳过的项；需要「跳过即红」（主开发机上自我证明）加 `--require-all`。
# 平台取值：显式 `DOYAH_PLATFORM=macos|windows|linux` 优先，否则按 `uname -s` 推断。
PLATFORM="$(uname -s)"
case "${DOYAH_PLATFORM:-}" in
  "") ;;
  macos | darwin | Darwin | macOS) PLATFORM="macos" ;;
  windows | Windows) PLATFORM="windows" ;;
  linux | Linux) PLATFORM="linux" ;;
  *) PLATFORM="${DOYAH_PLATFORM}" ;;
esac
case "${PLATFORM}" in
  Darwin | darwin) PLATFORM="macos" ;;
  MINGW* | MSYS* | CYGWIN* | Windows*) PLATFORM="windows" ;;
  Linux | linux) PLATFORM="linux" ;;
esac

REQUIRE_ALL=0
KEEP_GOING=0
for argument in "$@"; do
  case "${argument}" in
    --require-all) REQUIRE_ALL=1 ;;
    --keep-going) KEEP_GOING=1 ;;
    *) echo "⚠️ 认不出的参数：${argument}（本脚本只认 --require-all / --keep-going）" >&2 ;;
  esac
done

SKIPPED_COUNT=0
SKIPPED_ITEMS=""

skip_step() {   # skip_step <项号> <说明>
  SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  SKIPPED_ITEMS="${SKIPPED_ITEMS}   · 第 $1 项 ${2}
"
  echo "==> $1/19 ⏭ 跳过（平台不适用：PLATFORM=${PLATFORM}，缺 Xcode 工具链）—— ${2}"
  echo "    等价物见 Docs/Doyah产品概要设计说明书.md §8.3（每端必需项清单）与 §8.5.3（另一平台的 PowerShell 版）"
}

# ── L-110（2026-10-11 第 488 轮）：失败行的行号 → 项号 + 「未执行项」如实报 ──────────────────
# 项表**从本文件自己数**（`==> N/M` 项块的行号；与 `check-doc-numbers.py` 的 `gate-scan` 同源），
# 于是 `ERR` 陷阱里那个行号能翻译成「第几项」。项块行全文只在正文里出现十九次（注释里不写死项块）。
ITEM_PAIRS=""
while read -r table_line; do
  [ -n "${table_line}" ] || continue
  table_lineno="${table_line%%:*}"
  table_item="$(printf '%s\n' "${table_line#*:}" | sed -E 's/.*==>[[:space:]]*([0-9]+)\/[0-9]+.*/\1/')"
  case "${table_item}" in
    '' | *[!0-9]*) continue ;;
  esac
  ITEM_PAIRS="${ITEM_PAIRS}${ITEM_PAIRS:+ }${table_item}:${table_lineno}"
done <<ITEM_TABLE
$(grep -nE '==>[[:space:]]*[0-9]+/[0-9]+' "${SCRIPT_PATH}" || true)
ITEM_TABLE

item_total() {   # 项块数（从本文件数出来的，不手抄）
  local count=0 pair
  for pair in ${ITEM_PAIRS}; do count=$((count + 1)); done
  printf '%s' "${count}"
}

item_for_line() {   # item_for_line <行号> ⇒ 项号（0 = 第 1 项之前的前导段）
  local target="$1" best=0 pair
  for pair in ${ITEM_PAIRS}; do
    if [ "${pair##*:}" -le "${target}" ]; then best="${pair%%:*}"; fi
  done
  printf '%s' "${best}"
}

platform_skipped_items() {   # 本平台会被 skip_step 跳过的项号（与正文两处调用逐字同条件）
  if [ "${PLATFORM}" = "macos" ]; then
    printf ''
  else
    printf '1 11'
  fi
}

unexecuted_summary() {   # unexecuted_summary <已中止项号> ⇒ 点名「本平台接下来本会跑、但没跑」的项
  local from="$1" n out="" skipped
  skipped="$(platform_skipped_items)"
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
    if [ "${n}" -le "${from}" ]; then continue; fi
    case " ${skipped} " in
      *" ${n} "*) continue ;;
    esac
    out="${out}${out:+ / }第 ${n} 项"
  done
  if [ -z "${out}" ]; then
    printf '（无 —— 中止就发生在末项）'
  else
    printf '%s' "${out}"
  fi
}
FAILED_ITEMS=""
FAILED_LINES=""
FAILED_COUNT=0
FAILED_ITEM_COUNT=0

on_failure() {   # ERR 陷阱：$1 = 退出码 · $2 = 行号 · $3 = 命令原文
  local status="$1" line_no="$2" command_text="$3" item
  item="$(item_for_line "${line_no}")"
  FAILED_COUNT=$((FAILED_COUNT + 1))
  FAILED_LINES="${FAILED_LINES}   · 第 ${item} 项（脚本第 ${line_no} 行，退出码 ${status}）：${command_text}
"
  case " ${FAILED_ITEMS} " in
    *" ${item} "*) ;;
    *)
      FAILED_ITEMS="${FAILED_ITEMS}${FAILED_ITEMS:+ }${item}"
      FAILED_ITEM_COUNT=$((FAILED_ITEM_COUNT + 1))
      ;;
  esac
  if [ "${KEEP_GOING}" = "1" ]; then
    echo "⚠️  第 ${item} 项：脚本第 ${line_no} 行失败（退出码 ${status}）⇒ **记下来接着跑**（--keep-going）"
    echo "           ${command_text}"
  else
    echo ""
    if [ "${item}" = "0" ]; then
      echo "⛔ 失败在前导段（脚本第 ${line_no} 行，退出码 ${status}）：${command_text}"
    else
      echo "⛔ 第 ${item} 项失败（脚本第 ${line_no} 行，退出码 ${status}）：${command_text}"
    fi
    echo "   口径：本脚本是 \`set -euo pipefail\` ⇒ **当场中止**，后面的项**没有跑**。"
    echo "   **未执行**（本平台接下来本会跑的项）：$(unexecuted_summary "${item}")"
    echo "   要一次拿到全部项块的覆盖面 ⇒ ./Scripts/verify-all.sh --keep-going（跑完再汇总，统一 exit 1）。"
    echo "   纪律：**未执行 ≠ 通过** —— 报告里不许把没跑的项说成绿。"
  fi
}

trap 'on_failure "$?" "$LINENO" "$BASH_COMMAND"' ERR
if [ "${KEEP_GOING}" = "1" ]; then
  set +e
  echo "==> 跑法：--keep-going（跑完再汇总：单项失败不中止，收尾统一 exit 1；未执行项 = 无）"
fi

if [ "${PLATFORM}" = "macos" ]; then
  # 第 1 项之前先删掉单测数证据文件：留在盘上的旧值会被 Scripts/check-doc-numbers.py 当成
  # 「这一轮的实测」（第 4 项那条判据只认同一次运行的数）。删掉之后，本轮没跑第 1 项时
  # 判据会如实报「跳过实测」——而不是拿一个陈旧数字冒充现状。
  rm -f .build/core-test-count.txt
  echo "==> 1/19 Core 与平台适配层单测"
  ./Scripts/verify-core.sh
else
  skip_step 1 "Core 与平台适配层单测（Scripts/verify-core.sh 要 Xcode 工具链的 swift）"
fi

echo "==> 2/19 平台中立性（Core 不含平台专属依赖 · 脚本不含平台专属路径标识 · 语言登记形状）"
python3 Scripts/check-core-portability.py
# 第 91 轮（提案 0005 **采纳**）：第二条管的是 **`Scripts/*.py` 自己** ——
# `Scripts/` 是**两侧都在跑**的判据（Windows 侧 `platform/windows/Tools/verify-all.ps1` 第 ③ 项就是
# `python Scripts/check-doc-tables.py` + `python Scripts/check-doc-versions.py`），而它们把相对路径
# 铸成字符串（`str(path.relative_to(root))`）去和**手抄的正斜杠清单**比对时，Windows 上
# `str(WindowsPath)` 给 `Docs\README.md` ⇒ **集合匹配恒 False**、凡命中扫描面的文档全部判红，
# 而 macOS 上 `os.sep` 就是 `/` ⇒ **只在那一台机器上红**（对侧 2026-09-29 第 81 轮实测：
# `check-doc-versions.py` 误报 6 份、`check-doc-tables.py` 误报 26 处，而 A/B/C 三档全过）。
# 判据 A 禁这一形状（仓内 13 处已全部改 `.as_posix()`，其中第三处 `check-doc-numbers.py` 是本轮扫出来的）、
# B 例外台账默认**空**、C 空跑防护、D 判据自己的证据（8 例）。样式见 `Docs/Doyah产品概要设计说明书.md` §8.3。
python3 Scripts/check-script-portability.py

# L-106（FR-STD-WS-NAV-002 ①③，2026-09-30 开发循环第 117 轮）：语言的**登记形状** ——
# 与本项同源，都是「Core 的形状」那类判据（项数仍十九）。
# 「语言表声明式登记」这句话要能被机械看住：语言知识（扩展名映射 + 关键字 / 类型 / 字面量 /
# 注释 / 运算符规则集）只允许住在 `Core/CodeLanguageDefinitions.swift`，而**消费方那一族**
# （词法器 / 规则集 / 判语言 / 补全 / 两个编辑器 / CLI）里出现 `language == .xxx` / `case .sql:`
# 这类**身份分支**即判红 —— 那正是「加一个语言要改核心代码」的形状，而它不报错、只是变笨。
# 顺带看住三件登记自洽：语言标识与登记项**同集合** / 扩展名与文件名不许两个主人 /
# `isCode` 为真者必须给得出注释规则与字符串界定符（缺了 = 识别了却一个颜色都没有）。
# 高亮色一律走 `SyntaxTone` 令牌（FR-STD-WS-NAV-002 ③）：编辑器里出现裸色值即判红。
# E 档（`L-149` 剩余②，2026-10-01 开发循环第 145 轮）：**「这个文件用哪种视图打开」只有一处出处** ——
# 登记表里声明 `defaultView: .browser` 的语言**恰好**是 HTML；`App/` 下读 `defaultView` 的文件
# **恰好**是台账里那一个（`App/WorkspaceTabsModel.swift`，双向对账），且它必须真的把这一档交给
# 浏览器那一侧（交接锚点 `openInBrowserTab`）。多一处 = 又一条自己决定「用什么打开」的路。
# 判据自己的证据两处：`--self-test` **16 例**（夹具一律在临时副本上写坏，末例核对真仓库逐字节未变；
# 2026-10-14 原单 `T-20261010-048` 起，A 档面与盘上发现面双向对账、判定物分辨枚举、非法台账判红）
# + 入口证据 `Scripts/test-language-registry-gate.py` **例数 4**（走的是**命令行路径**：
# 真仓库 exit 0 / 写坏 exit 1 并点名到文件 / 参数错 exit 2 / 真仓库逐字节未变 —— 函数路径与
# 命令行路径的坏法不同，两条都要有人跑）。
# **2026-11-09 判据搬家（第一批 · 本地化 / 文案 8 条）**：下面这 8 条原先各是一份
# `Scripts/check-*.py`，已搬进 `swift test`（`./Scripts/verify-core.sh` 会真的跑到）：
#   check-language-registry      → Tests/LanguageRegistryShapeTests.swift
#   check-core-localization      → Tests/LocalizationCoreRatchetTests.swift
#   check-effective-language     → Tests/LocalizationEffectiveLanguageTests.swift
#   check-format-arguments       → Tests/LocalizationFormatArgumentTests.swift
#   check-copy-emphasis          → Tests/LocalizationCopyGateTests.swift
#   check-literal-language       → Tests/LocalizationLiteralLanguageTests.swift
#   check-menu-language          → TestsUISnapshot/MenuLanguageGateTests.swift（打包之后那一步，要真 App）
#   check-ui-snapshot-languages  → TestsUISnapshot/UISnapshotLanguageCoverageTests.swift（快照收尾）
# 旧脚本与它们的负例 runner 原样留在 `Scripts/archive/`（不删，只摘离闭环）。

echo "==> 3/19 本地化：Core 展示文本棘轮（R-037）+「当前语言只有一个来源」（L-13）+「文案即所见」（L-19）+「语言是传进来的」（L-47）"
# L-109（2026-10-11 第 487 轮）：同一条命令跑**两条**棘轮 —— ① 含汉字的字面量（R-037，基线
# `Scripts/core-localization-baseline.json`）② 写死的英文展示文案（白名单
# `Scripts/core-localization-english.json`：白名单之外一律报红、只许缩小；每条登记项带 `kind`）。
# L-13：界面语言有两条路 —— `L(...)` 与**显式传语言下去**（`summary(language:)` 之类）。
# 后者原先取的是**用户选择**（`LocalizationManager.shared.language`），绕过了渲染语境：
# 第 13 轮读图抓到的真缺陷就是它 —— 中文界面的行详情侧栏写着 `Text · 12 characters`。
# 收成一个口子 `effectiveLanguage`（宿主语境优先），并把这个口径变成机械判据。
# L-46（2026-09-27 第 37 轮）：上面两条只比**模板与模板**，没有人比过**模板与实参**。
# 真缺陷就长在这条缝里（第 37 轮实测）：`App/Views/AboutLicenseSheet.swift` 三处
# `L(.licAboutEdition)` / `L(.licAboutAppVersion)` / `L(.licAboutActivityItems)` 不传实参，
# 而模板是 `当前版本：%@` —— `LocalizationManager.text` 在 `arguments.isEmpty` 时
# **原样返回模板**，于是界面上印出的就是 `%@` 本身（中文英文都一样）。
# 判据四条：A 数字实参落 `%@` 槽 / A′ 字符串字面量落 `%d` 槽 / B 实参数 ≠ 占位符数 /
# C·D 类型不明的实参必须**逐条登记形状**（台账 `Scripts/format-argument-dispositions.json`）
# 且命中处数只许不增（棘轮）；**预算只量「无据」的实参**（未登记 + unverified），
# 登记成 text/number 的形状带出处、进 A/A′ 槽位交叉检查，不占预算。
# 第二条是**门禁自己的证据**：16 例负例（A / A′ / B / C / D / F / G /
# 例外陈旧 / 空跑不许通过 …，夹具一律在临时目录，末例核对真仓库文件逐字节未变）。
# L-19（2026-09-28 第 43 轮）：上面几条比的都是「文案内部」（汉字棘轮 / 语言来源 / 模板与实参），
# 谁都没管**文案与渲染口径**。真缺陷正长在这条缝里（第 13 轮读图 `routine-candidates-empty-zh`）：
# 语言表里 17 个键写着 markdown 强调 `**…**`，其中 `routineCandidatesHint` **一个键同时被两条路用**
# —— 面板里 `Text(L(...))`（`Text(String)` **不解析** markdown ⇒ 星号原样露出）与状态栏
# `statusMessage`（`String`，markdown 在这个通道**结构上永远不生效**）；备份恢复的日志行
# （`[String]`）、`Label(L(...), systemImage:)` 的 `String` 重载也是同一形状。
# ⇒ 口径拍板为「**文案即所见**」（纯文本）：去掉 16 个键的标记、`RowDetailPanel` 那处
# `LocalizedStringKey` 一并收口（**选 markdown 那条路修不干净** —— 有 4 个键的文案会流进
# 没有 markdown 的通道，`routineCandidatesHint` 更是两处都走）。
# 判据五条：A 语言表两语槽位不得含 `**`（密码掩码 `***` 按键登记例外）/ B 产品源文件不得再出现
# `LocalizedStringKey` / C 解析条目数下限（正则失配 ⇒ 零命中假绿当场报红）/ D 例外两端对账
# （条目陈旧报红）/ E 本门禁与它的负例必须在闭环里被真的跑到。负例 `test-copy-emphasis-gate.py`
# 一律在临时副本上写坏，末例核对真仓库逐字节未变。
# L-47（2026-09-28 第 46 轮）：上面几条比的都是「文案怎么取」，谁都没管**语言从哪来**。
# 真缺陷正长在这条缝里（第 46 轮读图 `diagnosis-empty-en`）：英文界面上界面文案都是英文，
# 唯独「给模型的资料」整块中文 —— `Core/DiagnosisContext.swift` 的文件私有取值助手把
# `language:` **钉死**成 `.simplifiedChinese`，而语言表里 `diagnosisTarget` /
# `diagnosisFormatConclusion` … 这些键**都有英文译文**却只被这一处引用 ⇒ **英文译文永远
# 不可达（死译文）**。R-037 的棘轮数的是「含**汉字**的字面量」（这里一个汉字都没有）、
# `check-effective-language.py` 只扫 `App/` 且只禁「按用户选择取语言」⇒ 两边都没覆盖
# 「把语言写成字面量」这个形状。
# 判据四条：A 写死语言的调用点必须逐条登记（按文件，带 maxSites 与理由；`maxSites: 0` =
# 回归钉）/ B 死译文双向对账（新增未登记的死键 ⇒ 红；修好不销账 ⇒ 红；包装函数
# `func t(_ key: LKey …)` 的每个调用点都算写死语言）/ C 本轮修的那一族不许回退
# （`DiagnosisContext` 的文本出口必须带 `language:` 形参、`DiagnosisAdvice.parse` 必须带、
# 面板必须传 `effectiveLanguage` —— 只靠 A 挡不住「删掉形参再在函数体里写死」）/
# D 空跑不许通过（语言表解析不到键、键引用为 0、扫到的文件过少都判红）。
# 台账 `Scripts/literal-language-dispositions.json`；负例 `test-literal-language-gate.py` **22 例**（判定物第 39 轮升代码面后 +5 例）
# （第 46 轮落地时 9 例，L-65 第 2/3/4 批又各补了 1~3 例、第 5 批 +3 例 —— 例数的唯一来源与逐处对账见
# `Scripts/self-test-counts.json`，一律在临时副本上写坏）。
# 人类主人令 2026-10-13（信箱 `T-20261013-042`）+ 2026-10-14 裁决（`T-20261014-003`）：
# 「界面任何按钮都用图标」的**机械判据**。第二段批 1–6 把 277 处水平按钮落到纯图标（`ToolbarIconButton`，
# 提示 + 无障碍标签装在组件本体）；批 7 修判据 F 的观察窗（控件本体 + 修饰链）；余 20 处（弹框 7 / 菜单件 4 /
# 内容承载 9）按 `T-20261014-003` ①/② **逐条登记进例外台账** `Scripts/button-icon-exceptions.json`
# （站点指纹 · 理由 · 依据 · 关闭条件 ⇒ 三条棘轮：未登记差异红 / 陈旧登记红 / 死登记红）⇒ a 类读数 0。
python3 Scripts/check-button-icon-only.py
python3 Scripts/check-button-icon-only.py --self-test

echo "==> 4/19 文档表格与派生计数"
# L-33（2026-09-27 第 29 轮）：本项的默认清单里有 **12 份被 `.gitignore` 排除的文档**
# （兼容性矩阵 / GBase-技术验证 / 测试用例 / 发布方案 / 手工验收运行手册 + **L-41 起纳入的
# `智能体助手-开发规范.md` 与 `design/开发循环-任务队列.md`** + **L-89 起纳入的 6 份**：
# `人工点验-单击清单-macOS-20260927.md` / `夜间开发记录_20260921-22.md` / `接管记录_v2.3.md` /
# `调研书-AI智能体能力基线.md` / `调研书-主流数据库客户端基础功能.md` / `项目评审-2026-09-23.md`）
# —— 它们只在主开发机上，
# 干净克隆与另一平台都没有。原先一律判红 ⇒ 那台机器上这一项**必红且与改动无关**（§8.5.6-4）。
# 现在：默认清单里不存在 → **跳过 + 高声提示**；显式点名 / `--require-all` → 判红。
# 本闭环传不传 `--require-all` 由参数决定（主开发机上自我证明时加）。
# **口径的两个数不是这里说了算**（第 65 轮 L-72 ㈡）：`12 份被排除` / `58 份命名 + 1 条通配 =
# 实跑 59 份` 由台账 `Scripts/doc-numbers.json`（`doc-tables-lists` / `doc-tables-files`）登记，
# 判据 `Scripts/check-doc-numbers.py` 每次自己算一遍（导入 `check-doc-tables.py` 读清单 +
# `git check-ignore` 实测 + 真跑它一遍）再与本文件 / 该脚本 / `AGENT-SPEC.md` 逐处对账。
if [ "${REQUIRE_ALL}" = "1" ]; then
  python3 Scripts/check-doc-tables.py --require-all
  # 2026-11-10 摘离 `check-ui-design-section.py`（判据搬家第三批）：拦截史 0 次，且它在 HEAD 上就红
  # （文档层级改版后「找不到 `## 9.1` 节」）—— 规则比事实旧。界面设计节够不够格现由
  # `Scripts/check-doc-layout.py`（结构 / 标题 / 节序 / 章内完整）+ `Docs/规范/界面设计节-写作规范.md`
  # （写作规范里那几项主题清单）+ 评审管。
else
  python3 Scripts/check-doc-tables.py
  python3 Scripts/check-agents-index.py
fi
# 这一半是门禁自己的证据（L-33；L-41 补例 5；L-89 补例 6）：干净克隆跳过 12 份且 exit 0 /
# --require-all 判红 / 显式点名判红 / **写坏一行被判红并指名行号** / **带表格却不在清单判红且归档豁免** /
# 真仓库 74 份受检无跳过（74 份命名 + 0 份通配；
# **末例核对真仓库逐字节未变**）。
# **本项里那几处「要看本机台账」的地方在干净克隆 / 并行工作树 / 另一平台上如实报「跳过」**
# （2026-10-08 · 任务 `t_004a679b` · 口径 = `AGENT-SPEC.md` §9 第 147 条 ④）：`check-doc-tables
# --self-test` 的例 4 / 例 5、`check-doc-numbers` 的 `[doc-tables-files]`、
# `check-self-test-counts` 里登记了 `hostLedgerSelfTest` 的那几族 ——
# **跳过 ≠ 通过**（逐条打印跳过的是哪几例 / 哪几处锚点），**主开发机上这几处一条都不放宽**。
python3 Scripts/check-doc-tables.py --self-test
python3 Scripts/check-req-index.py   # 机器视图（requirement-index.jsonl）与正文表格逐条对账
# 三书结构自审（「九轮清单」的机械层：结构 / 标题 / 节序 / 交叉引用 / 排印 / 章内完整 / 追溯 / 平台名）。
# 一轮全清即可，不必真跑九遍 —— 清单的九类是分类，不是轮次；豁免见 Scripts/doc-layout-exempt.json（每条带理由）。
python3 Scripts/check-doc-layout.py
# 需求编号三方对账：正文定义域（第 3/4/7 章）↔ 需求索引 ↔ 一单台账。
# 两份派生件互比（台账↔索引）永远绿，正文这一侧此前没人比；§5 数据需求 / §6 接口需求另账、§8 风险与待决同号两表属刻意。
# 端级一一对应（详设 ↔ 任务清单；人类主人 2026-10-26 令「与详细设计文档对标」）
python3 Scripts/check-end-sheets.py
# 2026-11-01：加上 --all 做存量体检 —— 只扫 diff 时，历史存量（15 条两位序号）永远看不见。
python3 Scripts/check-req-ids.py --all
# L-32（2026-09-27 第 28 轮）：变更记录版本号**唯一**、头部版本格**可判**（= 变更记录最高号，
# 或带「基线 / 首版」标注并在标注里写出当前号）、队列**定义行**条目号唯一。
# 取号唯一来源 = `Scripts/next-doc-version.py`（max+1）—— 禁止手抄：撞过三次
# （概要设计 v2.35 与对侧同号 / 队列 L-25·L-26·L-41 同号 / 三书 P-15 同号不同物）。
# 本项现在跑三个脚本，与第 3 / 7 / 10 / 15 项同一做法（**项数不变**）。
python3 Scripts/check-doc-versions.py
python3 Scripts/check-doc-invariants.py
python3 Scripts/check-rule-schema.py
python3 Scripts/check-frozen-sync.py || echo "⚠ 冻结基线有漂移（超阈值 ⇒ 该问人类『冻结到新版本吗』；不是失败）"
# **冻结号 ⟷ 软件号**（2026-11-08 主人令「冻结了四书哪个版本，软件就应该出哪个版本」）：
# 最新冻结段 vX.Y ⇒ 台账必须 `betaX.Y` / marketing `X.Y.0`，产物 plist 必须同号；dist 里躺着更旧的包判红。
# 未出包时返回 2（产物那一半**未知**）—— 打印警告但不中止，跳过 ≠ 通过；台账与冻结件不一致仍是 1（红）。
_frz_rc=0
python3 Scripts/check-release-freeze-parity.py || _frz_rc=$?
if [ "${_frz_rc}" = "2" ]; then
  echo "⚠ 版本号第二半未知：产物尚未构建（跳过 ≠ 通过）"
elif [ "${_frz_rc}" != "0" ]; then
  echo "❌ 冻结号 ⟷ 软件号不一致（见上）"; exit 1
fi
# 派生文件不得漂移：终端配色 JSON ↔ Core ↔ 人读文档三方一致（FR-STD-WS-TOOL-001 的跨平台交接物）
# 2026-11-09：`check-terminal-palette.py` 摘离（拦截史 0 —— 唯一一次相关提交 19df1fa0 是它抓自己的自检缺陷）。
# 三方一致改由 `Scripts/test-terminal-palette.sh` 跑（真跑 `CLI terminal-palette --json` + 从 hex 独立复算
# WCAG + 文档落点；alpha 链的 assert 项），色板本身由 `TerminalPaletteTests` 逐槽钉住。
# L-55（2026-09-28 第 61 轮）：上面几条管的是**表格结构**（列数 / 计数 / 版本号 / 派生计数），
# 管不了「独立写在各处的**工程设施数字**」—— 闭环项数、单测数、快照张数。真现场：
# `Docs/Doyah产品概要设计说明书.md` §8.3 闸门表写着 `verify-core.sh`（**760** 项），实测 2056 项（那是 09-23 的旧值）；
# `AGENT-SPEC.md` 跑法注释里写着 2046 tests / 快照 140 张 · 70 组，实测 2056 / 152 · 76。
# 口径 = **唯一来源台账** `Scripts/doc-numbers.json`（照 `Scripts/vendored-sqlite.json` 的做法），
# 判据 `Scripts/check-doc-numbers.py` 做**三向对账**：台账 ↔ 实测（能机械复算的必须复算：
# 闭环项数从 `==> N/M` 项块数、单测数读 verify-core.sh **同一次运行**写下的计数文件、
# 快照读 manifest）↔ 文档里每一处现状声明（精确锚点 + 有限反扫，写错 / 删光都判红）。
# 它同时管住「有判据、没闭环」那一族：`Scripts/check-*.py` 每个都必须被本脚本引用，
# 或在台账里逐条登记理由（现有 1 条豁免 = 快照语言覆盖门禁；界面按钮图标化判据已于
# `T-20261014-003` ① 承前接线并销掉豁免）。**豁免表自身三条自证**（合册 `T-20261013-027` ·
# 原单 `T-20261010-027`）：死豁免（豁免指向的脚本已不在盘）判红 / 理由里「随 X 的收尾跑」这种可对账
# 主张必须与磁盘相符 / 缺 `script` 键判红点名；收尾打印「豁免 N 条（有效 M / 死 K）」。
# 边界（如实登记，见脚本 docstring）：**不做全文反扫**（三书与开发记录里充满历史值），
# **对侧独占节整段跳过**（红线第 6 条：本侧不改的也不拿它判红），**变更记录行整行跳过**。
python3 Scripts/check-doc-numbers.py
python3 Scripts/check-doc-numbers.py --self-test
# L-56（2026-09-28 第 62 轮）：上面几条仍然管不到 **§6 待拍板队列的编号与状态**。真现场三类：
# ① `Q28` 同号两条（Retro 技术栈 / 本仓与宿主的关系）—— 两条不同的问题共用一个号；
# ② **8 行编号格是 L-41 修列数时补的 `——` 占位**（FR-STD-DB-IO-003 / FR-AGT-GUARD-PERM-004 / `.et` /
#    NFR-ALL-GATE-COMP-001 / cua-driver 两个授权 / 本机模型凭据 / 环境类授权（9 项）/ 机器载荷失败原串）
#    —— 表格结构合法了，但条目**无法被引用、无法被对账**；
# ③ `Q19` 早已在 §4 记「已拍板（2026-09-27）」，§6 却一直挂着「⏳ 待拍板」⇒ **每轮探针都把它
#    报成「待你拍板」**（同族另有 Q29 前提作废、Q34 / Q35 / Q36 / Q40 已随当日口径关闭）。
# 判据 `Scripts/check-doc-q-series.py`：A 编号可判且唯一 / B 状态只写词表词 / C 关闭行成对 /
# D §4 ↔ §6 同源（Q17~Q23 = Studio 号空间）/ E 空跑防护（行数 / 号数 / 对账对数下限）。
# 该文件与 check-doc-tables 那份同属 `.gitignore` 内的本机台账 ⇒ 不在盘上时**跳过 + 高声提示**，
# `--require-all` 判红；负例 `--self-test` **8 例** + 末例核对真仓库逐字节未变（例 1 = 前提自检
# 「干净副本必须绿」且真的解析到输入 —— 队列 L-119）。
if [ "${REQUIRE_ALL}" = "1" ]; then
  python3 Scripts/check-doc-q-series.py --require-all
else
  python3 Scripts/check-doc-q-series.py
fi
python3 Scripts/check-doc-q-series.py --self-test
# L-150（2026-10-02 第 159 轮）：上面这条管的是 **§6 自己**（编号 / 状态 / 与 §4 同源），
# 管不了**队列里引用 §6 的那一行** —— 真现场 = `L-10`（「需拍板类」汇总格）成员一个个已决之后
# **没人关格**，状态格还挂着 `needs-user`，于是每轮探针都替已经拍过板的事问「要不要拍板」
# （需求提出者当场问：「`L-10` 是什么，感觉是不是早就拍过版了」）。判据 `check-queue-needs-user.py`：
# 每条 `needs-user` 行必须**点名一个仍未决的拍板号**（`Q<号>` / `提案 <编号>`），或写出**挂起理由**
# （「挂起」+ `≠ 待拍板` / `不重复追问` / `不具备条件` —— **挂起 ≠ 待拍板**）；
# 全部已决 / 挂起、点了查无此号、空壳格（不点名也没理由）**逐条判红并指名行号**。
# 该文件与 spec 同属 `.gitignore` 内的本机台账 ⇒ 不在盘上**跳过 + 高声提示**，`--require-all` 判红；
# 负例 `--self-test` **11 例**（= 10 条负例 + 末例核对真仓库两份台账逐字节未变；含 `L-10` 旧文本复刻 ⇒ 必须判红）。
if [ "${REQUIRE_ALL}" = "1" ]; then
  python3 Scripts/check-queue-needs-user.py --require-all
else
  python3 Scripts/check-queue-needs-user.py
fi
python3 Scripts/check-queue-needs-user.py --self-test
# L-130 ②（2026-10-12 第 501 轮）：上面两条管「队列行点名一个仍未决的号」与「§6 自己的编号 / 状态」，
# 都管不了**唯一汇总处** —— `Docs/design/待拍板台账-三仓.md`（本机台账、`.gitignore` 排除）自己漂了没人知道。
# 真现场（本判据落地当天抓到）：`Q56` / `Q57` / `Q60` / `Q62` 四条 §6 里 `⏳ 待拍板` **从未进台账**，
# 而台账快照写着「仍开着 2 条」⇒ 需求提出者读到的清单少 4 条。
# 判据 `check-pending-agenda.py`：**R1** 面内未决号必须在台账有登记且结论格为 `⏳`（只有号却写成已决
# 也判红；台账写明理由的「挂起」按 `check-queue-needs-user.py` 同口径放行）· **R2** 台账挂 `⏳` 的行，
# 首个编号必须在面内原书里仍未决（`Q` ⇒ §6 仍 `⏳`；`L` ⇒ 队列在且非 `done`）· **R3** 挂 `⏳` 却无可解析编号。
# 面 = Studio `spec §6` + 队列 `needs-user`；**面外**（落点指向 Notes / Retro 书的行）本版**只计数不判定**（收尾行打印）。
# 台账不在盘上 ⇒ 跳过 + 高声提示，`--require-all` 判红（跳过 ≠ 通过）；负例 `--self-test` **9 例**
# （含 R1 两级 / R2 / R3 / 空跑防护 / 跳过 / 挂起放行 / 真仓库真内容）。
if [ "${REQUIRE_ALL}" = "1" ]; then
  python3 Scripts/check-pending-agenda.py --require-all
else
  python3 Scripts/check-pending-agenda.py
fi
python3 Scripts/check-pending-agenda.py --self-test
# L-72 ㈠（2026-09-28 第 65 轮）：上面几条管的是**跨文档的工程设施数字**（闭环项数 / 单测数 /
# 快照张数），管不了**逐族的负例例数**。真现场两件：① `AGENT-SPEC.md` §6 资产表里那三处 ——
# 语言透传族的例数写着 10（实测 14）、待拍板队列族写着 7（实测 8）、本项第 17 条注释写着
# 「共十类」篡改（实测 13 条）；② 更重的一条 —— `Scripts/test-*.py` 这
# 14 个「门禁自己的证据」**没有任何门禁管**（`check-*.py` 有 doc-numbers 的「有判据、没闭环」
# 对账，`test-*.py` 没有）⇒ 其中 **8 个根本没人跑**，而 `test-plugin-assembly-gates.py`
# 已经坏在第 3 例（`Core/AICapture.swift` 的 `sqlNote` 签名改成多行 + 多一个 `tag:` 参数，
# 夹具锚点还是老单行签名）无人知 —— 「判据写完不对已知改动报红，等于没有」。
# 台账 `Scripts/self-test-counts.json`；判据 `Scripts/check-self-test-counts.py`：
# A 台账结构（每族 key / script / cases / countRegex / why；没锚点必须写 noAnchorReason）
# B **把每一族 runner 真跑一遍**（要求 exit 0 —— 崩了就是「这族的负例没跑」）并按各族登记的
#   countRegex 抓例数，与台账逐族比对（抓不到 = 收尾行格式被改坏 = 判红，不许静默跳过）
# C 文档锚点逐处对账（`AGENT-SPEC.md` §6 资产表 / `Scripts/verify-all.sh` 注释 / 脚本自己的
#   docstring；写错、数字被删光都判红）+ D 可选静态棘轮（`sourceRatchet`：例数只在 runner 里用
#   `len()` 算出来的族，另按正则数脚本里的用例条数）+ E 空跑防护（族数 / 例数合计 / 锚点命中
#   处数三条下限）+ F 边界如实打印（无锚点但写了理由的族数）。
# 负例 `--self-test` 12 例（好情况 / runner 非零退出 / 例数漂移 / 收尾行解析不到 / 锚点值写错 /
# 锚点被删 / 台账结构错 / 空跑防护 / 静态棘轮 / runner 卡住不放（判红 + 及时返回 + 孙进程一起收）/
# 末例核对真仓库逐字节未变），夹具一律在临时目录。每族另有独立墙钟上限（默认 300s，
# `--family-timeout` 可改）：超时判红，不是跳过。
python3 Scripts/check-self-test-counts.py
python3 Scripts/check-self-test-counts.py --self-test
# §3.38（2026-11-07，beta1.0.8 主人令「前门等所有改动记得要同步到详细设计里去，别事情干完了又不同步四书」）：
# 上面这一大段管的是「文档之间」的一致性（表格结构 / 计数 / 版本号 / 口径 / 队列），**管不了**
# 「代码改了、书没跟着改」这一格 —— 真现场：beta1.0.7 那批（一轮一个思考区 / 三行汇总 / 吸顶 /
# 输入历史 / 审批三档 / 外层跟随）全是**先改代码、隔一两个提交才补详设**，靠人记。
# 判据 `check-doc-sync.py`：列出最近 12 个提交里「碰了 `App/` 或 `Core/`、却一个 `Docs/` 文件都没碰」
# 的提交，逐条打印它碰了哪几个代码文件（`--limit N` 可调；`--self-test` 5 例）。
# **提示级、只报告不拦截**（`|| echo` 兜住，`set -e` 下也不会中断闭环）：改了代码不等于改了契约性行为，
# 硬拦只会逼出 `--no-verify` 与「代码一个提交、文档一个提交」的假同步；真正的纪律写在详设 §3.38
# —— 凡改契约性行为必须**同批**改详设，提交前跑这一条。
python3 Scripts/check-doc-sync.py --limit 12 \
  || echo "⚠ 待补文档判据自身出错（不是「无待补」）—— 见上面那行 stderr"

echo "==> 5/19 文档口径对账（状态括注 / 版本范围 / 台账↔需求索引覆盖 / §4.2 条数 / 派生队列与 next_try）"
python3 Scripts/check-status-consistency.py
# L-69 ③（2026-09-28 第 56 轮）：上面那条管的是「其它文档括注 ↔ 台账**状态一致**」（2026-10-20 改口径，
# 原为「索引 ↔ 定义行」），管不了「这条 🟡 到底算不算本版范围」。
# **2026-10-20 改口径（人类主人令）：「不同版本该具备哪些能力 / 需求」由版本计划说清** ——
# 旧做法在需求行内写 `[alpha 不含]` 括注、另存一本 `alpha-fr-dispositions.json`；状态列迁出后
# 括注丢了大半、账目与正文对不上（70 条账目里 63 条的标记在需求书里已不存在）。
# 现在范围只在**一处**：台账 §3 的 `版本`（四档）+ `版本口径`（为什么不在本版）两列。
# 判据 = 版本 ⊆ 四档 / alpha 行口径必为 `—` / 非 alpha 行口径非空 / 编号唯一 / 空跑防护（行数与 alpha 条数双下限）。
# 负例 `--self-test` 8 例，全部在内存里写坏（不碰盘、无副作用）。
python3 Scripts/check-version-scope.py
python3 Scripts/check-version-scope.py --self-test

# **台账 ↔ 需求索引的覆盖 + §4.2 条数**（2026-11-03 接进闭环）：本条原先在 `doc-numbers.json` 里
# 登记为「豁免 · 待接进闭环」—— 判据在盘上却不在每轮跑的清单里，等于「有判据、没闭环」，
# 出了洞没人知道（实测它的 §4.2 条数一漂就漂了 20 条）。现在回收尾：
#   ① 台账 §3 编号集合 == 需求索引编号集合（不多不少）；② 状态合法；③ 需求书正文不写状态；
#   ④ 不许空壳行（「一句话」是 `—` 的行不许存在，更不许翻 ✅）；
#   ⑤ **§4.2 六个里程碑条数 / 头部未闭总数 / §2 §3 §4 三个标题的条数 == 台账逐行复算**，
#      未闭行必须**恰好**落一个里程碑（无孤儿、无重复归属）。
# 负例 `--self-test` 6 例（现状绿 + 改坏未闭行 / 已闭行 / 插孤儿行 / 改头部总数 / 改 §3 标题），全程在内存里改文本。
python3 Scripts/check-plan-coverage.py
python3 Scripts/check-plan-coverage.py --self-test

# **派生队列 ↔ 台账一致 + `next_try` 只认规则表**（2026-11-03 接进闭环 · 判据 F 的收尾）：
# 这一条原先只在手工 `python3 Scripts/plan-batches.py --check` 里生效 —— 「有判据、没闭环」，
# 队列漂了没人知道（实测：规则表三处已改成 TCP 复测当证据，`plan.yaml` 里还留着旧话
# 「217 ping 全丢」，而 `ping` 在本 shell 有假阴性，按 skill 不许作判据）。
#   判据 = ① 台账未闭集合 == 队列 todo ∪ blocked（缺 / 多 / 台账已闭仍 todo，逐条点名）；
#          ② **每个 blocked 的 `next_try` 逐字等于规则表**（`BLOCKED_V050/V060/V070` 旧→新合并）；
#          ③ `batches.yaml` == 按 `plan.yaml` 重出的结果，没有条目掉进「未归堆」。
#   覆盖范围（红线 13）：第 ② 条只认规则表里有条目的 blocked；跨版携带的那些（现 1 条
#   `FR-NTS-NOTE-ORG-002`）没有可比对的规则 ⇒ 运行时打印「覆盖 27/28 · 未经规则表核对：<id>」，
#   不静默算通过。不加 `--version`：跟着脚本的 `DEFAULT_VERSION`（= 当前队列版本）走，
#   换版时门禁不会停在旧版上判绿。
#   负例（2026-11-03 实测）：手改 `plan.yaml` 一条 `next_try` ⇒ rc=1 点名该 id；还原后复绿。
python3 Scripts/plan-batches.py --check

echo "==> 6/19 设计令牌棘轮（2026-11-09 搬进 swift test；同批摘离四条，理由见各脚本头一行）"
# 判据 `Scripts/check-design-tokens.py` → `Tests/DesignTokenRatchetTests.swift`（15 例，随本项跑的 swift test 一起）：
#   ① 六条规则逐处判：裸色（**字面色值永远判红**；`NSColor` 语义色按白名单放行）/ 裸字号 / 裸间距 / 裸圆角 /
#      系统文本样式 / 系统语义前景色 —— 判定物只认**代码**那半（块注释 / 行尾注释 / 字符串与多行串都先切开）；
#   ② 棘轮双口径：按「文件 × 规则」与「规则合计」都不得高于 `Scripts/design-token-baseline.json`；
#   ③ 逃逸口台账三态：未登记 / 理由为空 / 陈旧（盘上已无标记）都判红；白名单只许 `NSColor` 角色色；
#   ④ 空跑防护：面下限 105 份 / 25000 代码行 + 与 `Package.swift` 的 `DoyahStudioApp` `sources:` 对账。
#   **HEAD 上本来就红的两处照实保留**：`App/Views/ProductOverviewSheet.swift` 的 bare-textstyle 0 → 5 /
#   bare-foreground 0 → 3 以 `knownDrift` **精确**钉在测试里（少一处 / 多一处都红）—— 不改判据、不改产品代码。
#   **与老脚本的读数逐位相等**：187 份 / 45888 代码行 / 331 处（bare-color 2 · bare-foreground 97 ·
#   bare-spacing 52 · bare-textstyle 180），逐文件 19/19 完全一致。
#
# 同批摘离（移 `Scripts/archive/`，一行理由写在各自文件头）：外观样张同源（L-79 ㈡）/ 主题集（L-80 ㈠㈡ ·
# L-85 · L-155）/ 编辑面令牌（L-142）/ 终端配色三方一致。四条**拦截史为零或仅拦过自己的自检**（主人令：
# 没拦过就删）。现在由什么拦住：样张与产品**编译期同源**（`render-design-mock.sh` 与 `Core/DesignTokens.swift`
# 一起 `swiftc`，样张里写不出产品没有的颜色）；主题值表由 `Tests/DesignThemeTests` + `Tests/AppearanceAxesTests`
# （判据侧**独立复算** WCAG）与样张像素探针；编辑面底色由 `TestsUISnapshot/EditorSurfaceTokenParityProbeTests`
# （三面同底 · 切主题切深浅成套 · 7 例）与 `NotesEditorSaveProbeTests`；终端配色由
# `Scripts/test-terminal-palette.sh`（真跑 `CLI terminal-palette --json` + WCAG 独立复算 + 文档落点）。

echo "==> 7/19 平台等价矩阵 + P-* 平台差异登记对账"
# L-26（2026-09-27 第 25 轮）：这一项跑两条 ——
# ① `--check`：SRS §10.10 的表是否与 `Docs/平台实现状态.json` 台账一致（列由台账决定，
#    加平台 = 加台账里的一项，见脚本头注释）；
# ② `--self-test`：上一半自己的证据 —— 台账写错编号 / 状态取值非法 / 平台缺 label·role·owner /
#    macOS 混进台账 / `notPlatforms` 缺理由 / 顶层键拼错 / 表被手工改坏 / 标记被删，
#    共 11 例负例，**写坏只发生在临时目录**（末条核对真仓库逐字节未变）。
# 这一项此前**只覆盖一半**：矩阵自身的漂移能拦住，而台账写错（编号拼错、状态写个 🟢）会
# 静默通过、症状只是一整列 ⬜ —— 属"没人报红"那一族。
python3 Scripts/gen-platform-parity.py --check
python3 Scripts/gen-platform-parity.py --self-test
# L-45（2026-09-27 第 36 轮）：上面两条只做 §10.10 ↔ 台账。§4 与 SRS §10.9 这两张**自称一一对应**
# 的表此前一个判据都没有（第 7 项注释里那句「与 §10.9 登记表一致」是假话，已改正）。现在补上 ——
# ① 对账：两侧 `P-*` 编号集合必须互相覆盖、同号必须同物（领域归一后逐字相等）、**同侧编号唯一**
#    （同一张登记表内部同号两条判红并逐行点名 —— 后行会静默覆盖前行）、**判据 E 行为名列棘轮**
#    （该列归一后的条目名集合 ↔ 台账 `Scripts/p-parity-behavior-baseline.json` 逐号对账：
#    条目名改名 / 增 / 删、新号未登记、死条目、空单元格判红；**不判两侧逐字** —— 差异清单落
#    台账 `_差异读数`，前门 `T-20261014-201` ㈡ 裁「判行为标识不判逐字正文」）；
# ② `--self-test`：16 例负例（未并入权威登记表 / 编号空间断档 / 同号不同物 / 同侧同号两条 /
#    同侧逐字重复行 / §8.5.5 续排节重复提到同号**不**判红（对手臂）/ 归一有效 /
#    §8.5.5 已落条但未并入 / 小节被删不许空跑当通过 / 行为名列改名 / 删项 / 死条目 /
#    加括注仍绿的对手臂 / 台账不在盘判红 …，末条核对真仓库两份文档逐字节未变）。
# 它顺带把「对侧在 §8.5.5 先落条、待契约侧并入」这个流程变成判红项：不并入就一直是红的。
python3 Scripts/check-p-parity.py
python3 Scripts/check-p-parity.py --self-test
# 派单 `T-20261014-015`（人类主人令 2026-10-14「`fatshark` 要对齐 macOS 版开发进度」）：
# 上面两条管的是 §10.10 那张**矩阵**（谁到哪了）；Windows 侧还要一张**落点索引**
# （每条需求去哪个文件读 macOS 实现）⇒ `Docs/archive/root-20261026/平台对齐-Studio-Windows对macOS.md` 有生成器。
# `--check` = 产出件与三书 §10.1/§10.2 + 台账一致（需求索引或追溯表一变、产出件没重跑就报红）。
python3 Scripts/gen-studio-win-align.py --check
# 派单 `T-20261014-025`（人类主人令 2026-10-14 追问「怎么到现在你还没有 macOS 的任务清单？」）：
# 上面几条管的是**矩阵本身**（§10.10 ↔ 台账）；这一条管**派生视图** —— 人读的完成度面
# `Docs/任务清单-按平台.md`（`PC-BOARD-001`）的每一格是不是从 §10.10 **逐列重算**来的
# （不符即判红；§10.10 表头 / 本文件一览行读不到 ⇒ **空跑判红**；`--self-test` 16 例负例）。
# **生成侧**（2026-10-20）：三节改由 `gen-platform-board.py` 从真源机械重写（手抄那一半退役）——
# `--check` 判「真源动了而看板没重生成」，`--self-test` 9 例负例（含「台账翻一格 ⇒ 看板必须报红」）。
python3 Scripts/gen-platform-board.py --check
python3 Scripts/gen-platform-board.py --self-test
python3 Scripts/check-board-parity.py
python3 Scripts/check-board-parity.py --self-test

echo "==> 8/19 平台中立性棘轮"
python3 Scripts/check-platform-neutrality.py

echo "==> 9/19 界面接线与状态归属（命令面板 FR-STD-WS-UI-005 / 侧边栏折叠 FR-STD-DB-CONN-012 / 空数据按钮 L-50 / 终端多会话页签 L-84）"
# **2026-11-10 判据搬家第三批（UI 交互 9 条）**：按「先查拦截史，没拦过就删」逐条处置。
# 本项原先跑六个 `Scripts/check-*.py`，现在**一条 python 都不跑**（项号仍是第 9 项）：
#   · 命令面板接线（FR-STD-WS-UI-005）—— 拦截史 1 次（`7507af20` 笔记面 6 条落点补登记）⇒ 摘离。
#     现由 `TestsUISnapshot/PaletteWiringProbeTests` 以**真调用**拦：每条命令拿真 `AppState` 调一遍
#     `performPaletteCommand`，断言登记在案的落点真的变了 + 落点表 ↔ 命令清单双向对账。
#   · 侧边栏折叠状态归属（L-59）—— 拦截史 1 次（`6abecaf5` `AgentChatView.collapsedToolBlocks` 进例外表）
#     ⇒ 摘离。现由 `TestsUISnapshot/UISnapshotSidebarStateTests` 拦：活动栏切换前后**像素逐字节相同**，
#     把状态改回视图局部 `@State` 当场判红（行为探针强于源码形状扫描）。
#   · 空数据按钮处置（L-50）—— 拦截史 4 次（`fb539b30` / `d55a2617` / `da2d4bfb` / `6abecaf5`）
#     ⇒ **搬进 `Tests/EmptyActionButtonGateTests.swift`**（7 例；守卫 50 条 = 台账 50 条，与老脚本读数相等）。
#   · 面板根固定尺寸 frame 的对齐纪律（L-61）—— 拦截史 1 次且是台账跟版（`31990bd0`）⇒ 摘离。
#     真缺陷那一类（固定尺寸面板根里内容浮着 / 底部动作区被裁）现由像素探针
#     `TestsUISnapshot/ImportSheetLayoutProbeTests` + `UISnapshotPanelsTests` 量。
#   · 编辑面行号（L-111）—— 拦截史 3 次（`8e4690c8` 第二处行起点算法 / `0371913b` 未登记预览面 /
#     `fb539b30` 同族）⇒ **搬进 `Tests/EditorLineNumberSurfacesTests.swift`**（7 例；190 份源文件 /
#     7 个编辑面，与老脚本读数相等）。
#   · 终端多会话页签（L-84）—— 拦截史 0 次产品回潮 ⇒ 摘离。Core 七组由 `Tests/TerminalTabsTests`（27 例）、
#     真 PTY 行为由 `TestsUISnapshot/TerminalTabsProbeTests`（真开 shell）、「Core 不出中文字面量」由第一批
#     搬进 swift test 的 `Tests/LocalizationCoreRatchetTests` 各自拦。
# 六份脚本与两份负例 runner 原样归档在 `Scripts/archive/`（每个文件头一行写着「本来拦什么 / 现在由什么拦」）。
# 本项现在只剩三条**与上述九条同批处置无关**的台账判据（大结果集滚动阈值 / 性能读数表 / 模型服务预设）。

# L-89 ㈡ ④（第 97 轮）：**大结果集滚动**（清单 §4 FR-STD-DB-RES-011）那一行的阈值台账 ——
# 探针 `TestsUISnapshot/LargeResultScrollProbeTests.swift` 的每一条上界都从
# `Scripts/result-scroll-baseline.json` 读（容差必须有来源：基线实测值 + 倍数 + 理由），
# 于是那份台账**本身就是判据的输入**，谁也不能悄悄改松它：
#   · 字段齐备 / 规模对得上清单原文（≥ 1 万行 × 20 列）/ 基线是正数；
#   · 每条上界对**实测基线**至少有 3 倍余量（不许紧到换台机器就红）、也不许松到没有意义；
#   · 理由非空（改动必须说明为什么）；
#   · **探针必须真挂在取证脚本上** —— 第 96 轮实测过「新用例没接进
#     `run-manual-verification-probes.sh --filter` ⇒ 一个都跑不到」，所以这一条按
#     「`TestsUISnapshot/` 里每个 `*ProbeTests.swift` 都得在 FILTER 里，否则要在豁免表里写明理由」
#     逐文件对账（实测抓出 `AppearanceAxesProbeTests` 从 2026-09-29 起就没被任何脚本跑过）。
# 自检用例 `--self-test` **18 例**（红 / 绿成对，夹具在临时目录，末例核对真仓库台账逐字节未变）。
python3 Scripts/check-result-scroll-ledger.py
python3 Scripts/check-result-scroll-ledger.py --self-test

# C2（`NFR-ALL-GATE-PERF-001/002/003`）：**性能读数表**的阈值台账。冷启动那条原来连仪表都没有
# （「≤ 2 s」只是一句话）：阈值现只在 `Scripts/perf-baseline.json` 一处，App 在可交互那一刻写收据
# （起点 = **内核**记录的进程创建时刻，含 dyld）、`Scripts/measure-cold-start.py` 量、本判据看着
# 「阈值只有一个写者 / 接线在盘 / 读数不超阈值」。结果集那两条**不复制数字**，只登记去哪份台账取哪个字段。
# 静态臂在这里跑；实测（要真启动 App）另由 `Scripts/measure-cold-start.py` 与 `Scripts/measure-result-set.py` 出。
# 判据自己的证据：`--self-test` **13 例**（阈值被放宽 / 为负 / 理由掏空 / 只跑一遍 / 结果集改指自己 /
# 字段解析不到 / Core 硬编码阈值 / `begin()` 挪到第二句 / 终点标记被摘 / 读数超阈值 / 外部墙钟小于自报 /
# 缺读数，逐条判红后还原）。
python3 Scripts/check-perf-ledger.py
python3 Scripts/check-perf-ledger.py --self-test

# L-146（内测清单丁3，2026-10-01 第 142 轮）：**模型服务预设只有一个出处，界面只许消费它**。
# 需求原话「AI 助理配置时应该提供主流大模型配置 url 和可选择模型，毕竟很多人是不懂的」——
# 这件事有两个不会报错的坏法：① 界面自己写死一个端点（「端点只改一处」当场不成立，而编译照过、
# 单测照绿）；② 目录长在 Core 里、界面却没接上（用户打开面板还是两个空框）。
# 判据：A 唯一出处（提供商宿主名**从 `Core/AgentProviderPreset.swift` 里解析出来**、在**产品源面**内
# 只许出现在那个文件；环回地址不算提供商宿主名；面外不判但必须记账：面外读数 + 面外命中逐条登记）/ B 界面接线五处锚点（遍历目录 · 选中值 = 稳定标识 ·
# 模型下拉内容取自契约层 · 重开面板按端点恢复选中 · 选提供商自动填端点与模型）/
# C 形状（标识唯一 · 端点唯一 · 「自定义」恰一条且端点为「空」· 标签键中英齐备）/
# D 空跑防护（预设条数 · 宿主数 · 产品源面 ≥300 份 · 面外登记条数四条下限）。
# `Scripts/check-agent-provider-presets.py`（L-146 的负例 `--self-test` **15 例**：绿对照 / 别处写死端点 /
# 预设被削到 1 条 / 两条共用端点 / 下拉不再遍历目录 / 模型下拉绕开契约层 / 标签键没进语言表 /
# 扫描面被削掉 / 面外新增未登记出网件判红 / 面外无关文件不误伤 / 登记陈旧 / 登记死登 / 登记被掏空 /
# 真仓静态臂 / 末例核对真仓库逐字节未变）。
python3 Scripts/check-agent-provider-presets.py
python3 Scripts/check-agent-provider-presets.py --self-test

echo "==> 10/19 插件装配链（FR-STD-ALL-PLUG-001~03 / 06 / 07 + ADR-35）"
python3 Scripts/check-note-module-isolation.py
python3 Scripts/check-plugin-assembly.py
# L-22：FR-STD-ALL-PLUG-005 的「Linux 笔记＝本地离线、数据不外发（公司合规）」不能只是一句话 ——
# 笔记模块范围内**逐行扫网络 API 令牌表**（URLSession / import Network / NWConnection /
# http(s) 字面量 / URL(string: …），命中即红并点名文件与行号；范围声明与磁盘事实、
# 与上面那份解耦清单**两边对账**（漏登一个源文件也是红）。判据与台账见
# `Scripts/notes-offline-gate.json`（关键令牌不许被拿掉、例外要写明理由且锚点陈旧报红）。
# 2026-10-14（派单 T-20261010-043）：枚举面改成「插件树整棵进面 + Core/App 按前缀」+ 逐树下限 + 
# 面外（outOfScope）件命中令牌表打 ⚠️（不判红、不许静默）。**调用方式一字未动**。
python3 Scripts/check-notes-offline.py
# Notes SRS **v3.94 §6.4「按面分层的文件级显式清单」**（前门落笔 `987ace7` · 回执 T-20261009-149 ③ ·
# 收执行侧 ⑰ 相抵上报）：上面那条零网络门禁只扫 `Core/` 下文件名以 `Note` 开头的文件与 `App/Note*`，
# 而 `Core/NoteSync/` 是**子目录**、文件名不以 `Note` 开头 ⇒ 云同步面 / 认证面**不在它的扫描面内**（假绿）。
# 本门禁把「谁可以出网」收成一张**文件级**清单并逐文件判：`App/` `Core/` 里除四个面（笔记同步 =
# `Core/NoteSync/CloudSyncService.swift` / 认证 = `Core/NoteSync/CloudAuth.swift` / AI 既有豁免 =
# `Core/LLMClient.swift` + `Core/EgressLog.swift` / 装配缝 = `App/AppState.swift` +
# `App/Auth/AccountFlowModel.swift`）之外，任何文件**代码里**出现 `URLSession` / `URLRequest`
# ⇒ 判红并点名 `文件:行号`。口径：**只判代码出现** —— `//` / `///` 注释与字符串字面量里的提及
# **不算出现**（与 `check-core-portability.py` / `check-editor-surface-tokens.py` 同一口径：
# 「注释里提到某个标识不算它还在用」）；装配缝只许注入 transport、直接出网判红；目录级豁免无效。
# 台账 `Scripts/network-egress-whitelist.json`；负例 `Scripts/test-network-egress-gate.py`
# （15 例：注入两种令牌 / 白名单与装配缝对照 / 装配缝直接出网 / 注释与字符串提及 / 台账漏登与幽灵文件 /
# 令牌表掏空 / 拆接线 / 真仓库逐字节未变）。
python3 Scripts/check-network-egress.py
# L-44：界面检索**走库**（唯一生产点）+ **所走路线如实标注**（子串兜底 / 检索没跑成）——
# 视图不许拿已加载的列表自己过滤；每条路线都要在台账里登记处置（给键或显式 nil）并与实现
# 逐条相等；文案键要真的在语言表里（中英都在）且真的被引用（死键也判红）。
# L-89 ㈡ 第 8 条：**结果落地只有一个出口**（「键盘快打」那一行）—— 出口里的词比对在位 /
# 两处落地形状各只出现一次且都在出口体内 / `runSearch()` 两条分支都经出口且不自己落地 /
# `runSearch()` 不读搜索框（词是参数）/ `searchNotes()` 真的走到 `runSearch()`。
# 判据与台账见 `Scripts/check-note-search-route.py` / `Scripts/note-search-route.json`；
# 负例 `test-note-search-route.py`（26 例：生产点消失 / 第二条路 / 视图过滤 / 台账与实现不一致 /
# 新增路线没登记 / 语言表缺中文 / 死键 / 两处空跑防护 / 落地出口的词比对被删 / 一条分支绕过出口 /
# 落地形状多出一处 / 查库那一步又读搜索框 / **合册 T-20261013-027 · 原单 T-20261010-056 新增十一条**：
# 逗号列表路线 / 改名后的搜索框属性 / 块注释假阳 / 字符串假阳 / 注释冒充引用（死键）/ 多行条目 /
# 面外回流（`Platform/macOS` 检索路 · `Core` 内存检索）/ 面内新增不误报 / 逗号列表已登记不误报 /
# 生产面缩面（删 target）/ 面外根死登记 / 真仓库逐字节未变）。
python3 Scripts/check-note-search-route.py
python3 Scripts/test-note-search-route.py
# L-137（2026-09-30 第 130 轮）：**Markdown 解析只有一份，预览只许消费它** ——
# 需求提出者要「工作区的编辑器带 markdown 预览」，而这条路上有个必然的诱惑：再写一套块级解析
# 或引一个第三方渲染库。一旦那样做，同一份 `**粗体**` 在笔记里是粗体、在预览里是星号，
# 而**编译照过、单测照绿**，没有任何东西看得见。判据五条：行内扫描器 `nextMarker` **与链接扫描器
# `linkMarker`** 的定义都唯一且在 `Core/NoteBody.swift`（名字也不许出这个文件，见 `L-137` 剩余③）/
# 块级模型 `MarkdownBlock(` 只许
# `Core/MarkdownDocument.swift` 构造（界面与平台层只渲染）/ 块级模型里必须**真的调用**
# `NoteBodyProjection.parseInline(`（至少 4 处 —— 同源判的是调用点，不是注释）/
# `import` 与依赖声明里不得出现第三方 Markdown 库。另加四条空跑防护（扫描面 / 块构造处数 /
# 同源调用处数 / 解析层用例数下限）。
# 判据见 `Scripts/check-markdown-single-source.py`；负例 `--self-test` 24 例
# 2026-10-13（合册 T-20261013-027 · 原单 T-20261010-062）：判定物改判**代码**（剥注释与字符串、等长）·
# 行内标记清单改判**集合**（换函数名 / 换序也红）· 用例须**非空带断言**（下限 36 = 实测）·
# 面 = `Package.swift` 现读的生产 target 源码目录（补 `Tools/LicenseTool` 那条面外回流口）
# （行内扫描器出现第二份 / 定义被删 / **链接扫描器出现第二份** / 界面自己造块 / 模型被掏空 /
# 同源调用被删 / 第三方库两种引法 / 用例文件被删 / 用例被掏空 / 扫描面被削掉 / 绿对照 /
# 末例真仓库逐字节未变）。
python3 Scripts/check-markdown-single-source.py
python3 Scripts/check-markdown-single-source.py --self-test
# L-149 ③④（2026-10-01 第 134 轮）**内置浏览器页签的归属 = 工作区**：2026-11-10 摘离（判据搬家第三批）。
# 拦截史 1 次（`292516a9` 建判据时订正归属；`db609bd5` 是结构债收口），且它在 HEAD 上红在「Retro 插件三个
# 源码根未登记进面」（纯台账跟版）。路由那一半现由 `TestsUISnapshot/WorkspaceFileRoutingProbeTests` 真跑
# 登记表拦：`.html` / `.htm` / 大写扩展名都交给浏览器侧且**不同时**开成文本页签，非标记文件照旧进编辑器。
# 遗留（如实登记，别当已验）：「数据库侧不许再出现浏览器页签」这一条在摘离后**没有探针覆盖** ——
# 本批为了不制造真空，把它的 A 面（`App/` 下出现 `browserPages` / `BrowserTabView` 等七个标识的文件必须
# 在台账里登记、`QueryWorkspaceView.swift` 命中即红）留在归档件里备查，下一步要么补一条离屏探针
# （把浏览器页签渲染进数据库侧应不可达），要么把这条判定并进 `WorkspaceFileRoutingProbeTests`。

if [ "${PLATFORM}" = "macos" ]; then
  echo "==> 11/19 打包 .app（沙箱）"
  ./Scripts/build-app.sh
  # L-145（2026-10-01 内测丙2 · 「中文菜单里有 2 个英文菜单」）：**菜单栏那一层**的判据。
  # 由头 = 界面快照拍不到菜单栏（它不在任何视图里）、源码判据也读不到它（`NSMenuItem.title` 是
  # 运行期值）⇒ 键都登记了、表也齐全、门禁全绿，菜单栏却停在**启动语言**上（实测：切完语言后
  # AppKit 会把 File / Edit / View / Window / Help 的顶层标题按启动语言再本地化一次，**不发任何通知**）。
  # 判据 = 真启动两档（英文→中文 / 中文→英文，走用户真实的语言切换入口）+ 判 dump 的 A 段
  # （**还没点开任何菜单**时的原样 = 用户看见菜单栏的那一刻）：不许有任何菜单项停在启动语言；
  # 「认不出」的项只许在白名单里（应用名 / 语言显示名 / 窗口标题）；外加空跑防护与形状判据。
  # **第二代（2026-10-02 · 内测第三批）扩面**：`显示` / `窗口` 里有一批项是 AppKit **展开菜单时**才插进
  # 树里的（显示标签页栏 / 显示所有标签页 / 填充 / 居中 / 移动与调整大小 / 全屏幕平铺…）⇒ 探针先
  # `DOYAH_MENU_DUMP_OPEN=1` 把 9 个顶层菜单各展开两遍再 dump，判 A/C/B 三段：表内一致 + **每一项的
  # 可见标题（含子菜单自己的标题）都要跟当前界面语言同语** + 未覆盖项逐条点名 + 必检项两档（硬族缺即红 /
  # 条件族单档缺如实登记、两档都没出现才红）。
  # 判据 L-145 的负例 `--self-test` **19 例**（含「停启动语言」「认不出没登记」「缺系统菜单」「展开族缺项」
  # 「缺 C 段」「同一条 dump 改一字节即判红」「第 140 轮那份留档在第 2 代必须判红」）。
  # 放在打包之后：它要跑刚构建出来的那个包（`dist/DoyahStudio.app`）。
  # 判据已搬进 `TestsUISnapshot/MenuLanguageGateTests.swift`（判定逻辑的 9 条负例每次 swift test 都跑；
  # 这里只补**真启动两档**那一半 —— 它要刚构建出来的 `dist/DoyahStudio.app`）。
  MENU_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  # 2026-11-09：真启动两档要**本仓的 swift 包**。门禁自己的桩仓（`Scripts/test-verify-all-gate.py`
  # 的夹具：只有 `Scripts/` 下的桩，没有 `Package.swift`）里这一档没有意义 —— 如实说「跳过」，
  # 不让桩仓里的 `swift test` 把这一项判红（那是夹具的形态，不是产品的缺陷）。
  if [ -f "${ROOT}/Package.swift" ]; then
    DOYAH_MENU_LANGUAGE_GATE=1 DEVELOPER_DIR="${MENU_DEVELOPER_DIR}" \
      "${MENU_DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" test \
        --disable-sandbox --package-path "${ROOT}" --scratch-path "${ROOT}/.build" \
        --manifest-cache local --filter MenuLanguageGateTests -Xswiftc -disable-sandbox
  else
    echo "⚠️  本仓没有 Package.swift（桩仓 / 夹具）：菜单栏真启动两档**跳过**（跳过 ≠ 通过）"
  fi
  # 平台矩阵（NFR-ALL-GATE-COMP-004 / -005）：**部署目标只有一个值**（包定义 / 工程文件 /
  # 生成物 pbxproj / Info.plist 模板四处）+ 产物信息带 `LSMinimumSystemVersion`（老机器上
  # 系统那句「需要 macOS 14.0 或更高版本」的唯一依据）+ 构建脚本认 arm64 / x86_64 / universal
  # 三档且 universal 真走 `lipo -create`。放在打包之后：产物面就在这里。
  # 真读数（两个切片的 minos / 双架构各起一遍拿到启动收据 / Rosetta 真在翻译态）由
  # `Scripts/measure-platform-matrix.py` 出、`check-platform-compat.py --readings` 判 ——
  # **不进闭环**（要双架构构建 + 4 次真启动），读数与判读结论贴证据文件。
  python3 Scripts/check-platform-compat.py
  python3 Scripts/check-platform-compat.py --self-test
else
  skip_step 11 "打包 .app（Scripts/build-app.sh 走 xcodebuild，且产物是 .app 包）"
fi

echo "==> 12/19 脚本 shell 多字节安全（bash 3.2 变量名坑）"
python3 Scripts/check-shell-locale-safety.py

echo "==> 13/19 脚本连接信息参数化（连真库的脚本不许写死端口 / 地址 / 账号）"
python3 Scripts/check-script-env-parameterization.py

echo "==> 14/19 连接失败的文案覆盖面（驱动错误码 ↔ 文案台账）"
python3 Scripts/check-connection-failure-coverage.py

echo "==> 15/19 可读化覆盖面（L-15 命令行失败输出 + L-74 非文本类型那一格的值）"
# L-15：CLI 有 57 处「把失败说给用户看」的输出原先各写各的（`print("…：\(error.localizedDescription)")`），
# 打出来是 `The operation couldn't be completed. (PostgresNIO.PSQLError error 1.)` —— 既不是人话、
# 也没给方向，而驱动其实说过原因（SQLSTATE / 驱动码），只是没人接。这一项把「每一处用户可见的
# 失败输出都必须经同一个入口」变成**结构**判据（新增一处裸英文输出当场报红并指名行号），
# 并把入口自己的三条口径（认得出给方向 / 中性归因 / 认不出原样）与调用处数棘轮一起钉住。
python3 Scripts/check-cli-failure-readability.py
# L-74（**2026-09-29 第 79 轮**）：同一条「可读化」的口径,这次管的是**值** ——
# 驱动在扩展查询协议下给的是 binary，而 `Core/PostgresCellFormatter` 原先只覆盖文本 / 整型 /
# 浮点 / numeric / 日期时间，其余类型落到 `String(describing: buffer)` ⇒ 用户拿到的不是值，
# 是驱动内部对象的描述（现场：会话行的 `client_addr` 那一格印控制字符，CLI 表格当场被劈开）。
# 判据 = 台账 `Scripts/cell-decode-coverage.json` ↔ 源码双向对账（解了不登记 / 登记了没解都报红）
# + 那条被禁的出口（`String(describing: buffer)`）不许在 `Core/` `App/` 的代码行里回来
# + 诚实兜底（点名类型 + 字节数 + 十六进制预览）必须在位 + 单测逐型锚点 + 真机证据（证据脚本 §7
# 与 psql 的文本形态逐条相等）。L-74 的负例 **23 例**（一律只在临时副本上写坏，末例核对真仓库六份文件逐字节未变）—— 判定物改判**代码**（剥注释等长替换 + 抹字符串）/ 判据面由 `Package.swift` **现读**（面根数硬下限 + 面外生产根判红）/ 台账三处面缺一即红 / 三处 `index()` 兜底（判据自身坏掉 ⇒ 不吐栈、退出码 2）。
python3 Scripts/check-cell-decode-coverage.py
python3 Scripts/check-cell-decode-coverage.py --self-test

echo "==> 16/19 越界检查（三书独占节 + 路径归属：改动不得落在对侧节 / 对侧子树上）"
# 形态 A（2026-09-27 拍板）：三书单点定稿，但「平台实现」层按端独占 —— 标记 `[独占:macos]` /
# `[独占:windows]` 的节只由该侧改；本机 = macOS 侧。判据与逃生门见脚本头注释。
# 第二条是**门禁自己的证据**（L-42）：**44 例**负例里含「非所有者新开 `[开放]` 节」这条窄通道 ——（**2026-10-03 订正 23 → 29 → 35**（29 → 35 = 派活单 `T-20261003-003` 的契约所有者 = 演员名 6 例；**35 → 41 = 派活单 `T-20261005-038` 的演员名跟版护栏 6 例**；**41 → 44 = 派单 `T-20261013-005` §四.1 的平台词表 `watchos`**）：实跑 `python3 Scripts/check-exclusive-sections.py --self-test` = **44/44 通过**（2026-11-02 实测；此前这条尾巴写「41 → 45 / 45/45」，与脚本里 `self_test()` 的 44 个 `r.append` 和 `self-test-counts.json` 的 `cases: 44` 都对不上，按实跑归位）；数字的唯一来源 = `Scripts/self-test-counts.json` 的 `exclusive-sections`，`check-doc-numbers` 对账）
# 判据写完不对已知改动报红，等于没有。两个脚本对外只认退出码，`--self-test` 红了整项就红。
# 第 33 轮起本脚本是**三副本同源**的「并集」版（提案 0003 裁决：Notes 副本的侧别别名 / `--contract-docs` /
# 拿不到基线退出 2 + 本侧未跟踪增量），`--base` 显式给了却解析不到**也退出 2**（不许静默放行）。
# ⚠️ **两侧词表撞在同一个变量名上**：`DOYAH_SIDE` 在**技能共享仓**那套工具里认**化身名**
# （`bluewhale` 鲸鱼娘 / `bighippo` 大河马 …，见《蓝色鲸鱼娘赛博基本法》），在本仓的越界判据里
# 认**平台名**（`macos` / `windows` …）；用户 shell rc 里设的是化身名 ⇒ 判据按「退役词」退出 2
# （实测 2026-10-03：`--mine=bluewhale` ⇒ 整项红）。这里按 `uname` **显式**把平台名传给它们，
# 不在脚本里写死 mac；技能仓那套工具照旧用自己的化身名，互不干扰。
# 2026-10-13（派单 `T-20261013-004` · 人类主人令「macOS/iOS/watchOS 归大河马」）：Darwin 机的本侧
# 由单值 `macos` 扩为 **`macos,watchos`** —— 清单里 `watchos` 是**独立一棵树**（`owner = macos` 同一
# 机组、不同格，与 Notes 的 `ios` 树同形），而 `check-path-ownership.py` 认「命令行给了树 id 就只取
# 该树」，不写全就把本侧自己的 `platform/watchos/**` 读成对侧。`ios` 格暂不加（Studio 无 ios 树；
# 加它会让既有 `[独占:ios]` 节由红转绿 —— 属另一次口径变更，见派单一节）。
# **2026-11-02 订正（空队列维护跳）**：上面这一套**只对 `check-path-ownership.py` 成立** —— 它认的是
# **盘上的树 id**（平台名），必须写全本侧那几棵树。`check-exclusive-sections.py` 不能跟着传平台名：
# 它的**契约层**一轴判的是「改的人是不是契约所有者」，而契约所有者自 2026-10-15（基本法第四十八条 /
# 派单 `T-20261015-005`）起是**演员名 `hugehippo`**；传 `macos,watchos` ⇒ 判据按收紧判据（所有者有平台
# 集 ⇒ 必须同名）把**所有者本人**的三书改动算成越界。实测（同一处契约层改动、同一个基线 HEAD）：
#   `--mine macos,watchos` ⇒ rc=1「契约层锁定不通过：2 处改动落在契约层」（假红）
#   `--mine hugehippo`     ⇒ rc=0「受检改动 2 行（含契约层），均合法」
# 而 pre-commit 钩子用的就是 `--mine hugehippo` ⇒ 原先**两道门禁对同一改动给出相反判定**（钩子绿、
# 全量验收红），上表这一项从此永远判红。所以：契约层那一道改传**演员名**（按 `uname` 显式给、不写死、
# 也不让 shell rc 里的化身名漏进来），路径归属那一道照旧传树 id。
# 演员名 ↔ 平台集由判据自己的词表展开（`hugehippo` = macos / ios / watchos；`babyhippo` = android /
# harmony / windows / linux，2026-10-22 人类主人令 Linux 划入小河马）—— 这里只做「本机是谁」的映射。
case "$(uname -s)" in
  Darwin) DOYAH_PLATFORM_SIDE=macos,watchos ; DOYAH_ACTOR_SIDE=hugehippo ;;
  Linux)  DOYAH_PLATFORM_SIDE=linux ; DOYAH_ACTOR_SIDE=babyhippo ;;
  *)      DOYAH_PLATFORM_SIDE=windows ; DOYAH_ACTOR_SIDE=babyhippo ;;
esac
python3 Scripts/check-exclusive-sections.py --mine "$DOYAH_ACTOR_SIDE"
python3 Scripts/check-exclusive-sections.py --mine "$DOYAH_ACTOR_SIDE" --self-test
# 路径归属判据（派活单 `T-20261002-029`，2026-10-02 立；三仓同源副本，清单 = `Scripts/path-ownership.json`）：
# 上面那个判据管「文档里的**节**」归谁，这一个管「盘上的**目录 / 文件**」归谁 ——
# 改动落在**不属本侧的子树**（谁属谁以同目录 `path-ownership.json` 为准）⇒ 判红并点名文件；
# 共享面（`Docs/` · `Scripts/` · `AGENT-SPEC.md`）不算越界，但要**声明式台账**：
# 清单 `shared_ledger` 改前登记理由（glob 命中）/ 本次新增行注 `shared-surface：理由` /
# 提交信息注 `shared-surface: 理由`，三处都没有理由 ⇒ 判红。本侧由清单 `hosts` 推断
# （macOS = `darwin` ⇒ macos 端），不写死 —— 换台机器跑不会把运行方当成对侧。
# 第二条是**门禁自己的证据**：**38 例**（对侧子树 / 共享面未登记 / 清单过期 / 本地落后远端 / 中文路径… / **契约模式 6 例**：契约所有者只许三书、碰代码即拦 / **均衡令 4 例**（`T-20261013-006`）：现行名 `hugehippo` 改本侧绿 · 改对侧红 · 旧名只作只读别名 · 本仓无 `ios` 子树时 `--mine macos,ios,watchos` 认不出退出 2）。
# 数字的唯一来源 = 实跑 `python3 Scripts/check-path-ownership.py --self-test`（34 例 → 38 例：均衡令新增 4 例；本注释里的旧值 32 自第 32 轮起就陈旧，本批一并归位）。
# ⚠️ 同 691 行的道理：这里也**显式**传平台名，不让环境里的 `DOYAH_SIDE`（技能仓那套认化身名）漏进来 ——
DOYAH_SIDE="$DOYAH_PLATFORM_SIDE" python3 Scripts/check-path-ownership.py
DOYAH_SIDE="$DOYAH_PLATFORM_SIDE" python3 Scripts/check-path-ownership.py --self-test

# 三仓「同源副本」身份对账（合册 `T-20261013-027` · 原单 `T-20261010-039`，2026-10-14）—— 判据自己的证据：`--self-test` **20 例**；判据 = `Scripts/check-tri-repo-parity.py`，两份同源判据
# （`check-exclusive-sections.py` / `check-path-ownership.py`）在三处（`Studio/Scripts/` · `Notes/tools/logic-check/` ·
# `Retro/tools/`）的 **sha256 + 行数**逐仓登记在台账 `Scripts/tri-repo-parity.json` —— 改一处要三仓同改，否则判红并
# 点名「仓 + 文件 + 期望/实测」；三份不一致必须逐仓登记 `divergence`（原因 + 依据单），三份已一致而登记未删也判红。
# 另两仓不在盘上 ⇒ 如实「跳过 + 高声提示」（跳过 ≠ 通过，`--require-all` 才判红）；台账条目 < 下限或一份都没比成 ⇒ 判红。
# **判据落地当场抓到活体分叉**：`check-path-ownership.py` 三份 sha 各异（`588b7db2…` / `7755593234…` / `66f873cf…`
# —— `platform/windows/` 字面量跟版与均衡令文案只在 Studio 落地）⇒ 已在台账 `divergence` 里逐仓登记理由。
# 夹具一律只在临时目录里写坏，末例核对真仓库三份文件逐字节未变（红绿成对 20 例）。
python3 Scripts/check-tri-repo-parity.py
python3 Scripts/check-tri-repo-parity.py --self-test

echo "==> 17/19 vendored SQLite（FR-STD-ALL-PLUG-008 / Q23）：台账对账 + 负例 + 现编现跑自证"
# 为什么这三条必须一起跑（第 18 轮 L-25 第 1 批）：
#   · 这份 `sqlite3.c` 是 9.5 MB 的**生成文件**，换版本 / 手改一行 / 编译宏掉一个都**不会有症状**，
#     只会让三端行为悄悄不一致（FR-STD-ALL-PLUG-008 的口径是「三端同一份引擎，不许换系统 libsqlite3」）；
#     所以第一条把每个事实（文件哈希 / 头文件版本串 / 宏 / 公共头目录 / 许可 / 来源 / 接线）都做成对账；
#   · 第二条是**门禁自己的证据**（**25 例**：篡改 23 条必须被抓到并指名出处 + 对手臂 2 条不许
#     误报 —— 六类篡改 + 证据锚点 + 接线 + 项号自洽 + 台账空跑防护，另加「把接线**注释掉**」
#     这一最常见的手工停用、**锚点被重构掉只剩一行注释**、**编译宏被注释掉**、
#     **判定面被台账自消**、**面外 testTarget 根与面外回流**、台账缺字段不留栈、退出码 2 = 自坏）；
#   · 第三条是**行为证据**：把 sqlite3.c 现编成可执行文件跑一遍 —— 版本 / 四条宏 / WAL / 参数化
#     读写 / DQS=0 报错，以及 **FTS5 中文检索**（默认分词器 0 命中、trigram 3 字以上才命中，
#     两条都钉住 —— 这是「笔记按条件查与全文检索」这条判据的真正口径）。
#     它**不经过 SwiftPM**，所以与绑定层那个工具链缺陷无关，今天就能当证据。
python3 Scripts/check-vendored-sqlite.py
python3 Scripts/check-vendored-sqlite.py --self-test
python3 Scripts/smoke-vendored-sqlite.py
# 同一条需求（`FR-STD-ALL-PLUG-008`）的**结构与版本口径**：四张表在源面各只有一份 DDL /
# 附件只存路径不进 BLOB / `user_version` 只来自升级链且链尾 == `supportedVersion` /
# `journal_mode = WAL` 在位 / 存储层没有平台分支（`--self-test` **7 例**）。
# 行为面（元数据正文标签时间线真落库、附件字节在文件系统、**SIGKILL 中途崩掉库不自坏**）
# 由 `Tests/NoteCrashSafetyTests` 取证，不在这里跑。
python3 Scripts/check-note-storage-unity.py
python3 Scripts/check-note-storage-unity.py --self-test

echo "==> 18/19 生成物一致性（L-43）：生成物 ↔ vendored 头文件逐字节"
# 为什么这一项必须有（第 30 轮 L-43）：`Core/NoteStorage/SQLiteConstants.swift` 是**生成物**，
# 生成器 `gen-sqlite-constants.py` 早就写好了 `--check`，**而且脚本头部自己就写着
# 「本 check 未接进 verify-all.sh」** —— 有判据、没闭环。后果：手改生成物一行、
# 或头文件换版后忘了重生成，编译照过、单测照绿、谁都不会报红（与第 17 项那个 9.5 MB
# 生成文件同一族 —— 「生成文件没有症状」）。同理**不许拿「我重跑过生成器」当证据**：
# 判据是逐字节比对，不是记忆。
# 第二条是门禁自己的证据（5 条篡改：手改生成物一行 / 生成物丢失 / 改头文件宏值致生成物过期 /
# 头文件删掉正文在用的宏 / 正文引用头文件里没有的宏 —— 每条都必须报红**并指名出处**），
# 夹具一律在临时目录里（末例核对真仓库三份文件逐字节未变）。
# 台账侧绑定见 `Scripts/vendored-sqlite.json` 的 `generator` 节点（第 17 项对账）。
python3 Scripts/gen-sqlite-constants.py --check
python3 Scripts/gen-sqlite-constants.py --self-test
# 族 ②：发布产物版本号的「一个值、三处逐字一致」+ Xcode 工程（生成物）不许与 project.yml 漂移
# （L-70，第 68 轮）。它与上一族同属「生成文件没有症状」：`.xcodeproj` 在本仓**没有别的门禁**
# （`build-app.sh` 走 `swift build`，不读工程文件）⇒ 过期了编译照过、单测照绿、发布照发。
python3 Scripts/check-release-version.py
python3 Scripts/check-release-version.py --self-test

echo "==> 19/19 台账两列一致（实现列 ↔ 判据列）：实现已 ✅ 而判据还是 ⬜/🟡 的行必须为 0"
# 为什么要有这一项（2026-11-02）：v0.4.0 收口时按**实现列**报「13/14 已收口」，而 8 条判据格还空着 ——
# 同一件事在两列里各说各话，最晚到 v1.0.0 门前才会以「总数对不上」的形态爆出来。
# 判据 `Scripts/check-status-gap.py`：§3 台账**全部行**逐行比第 6 格（实现）与第 7 格（判据）；
# 判据格是 `—`（不适用）或 `➖`（挂起 · 暂不支持那一族）的不判红，但**逐条点名**打印出来
# （免得这两档被当成逃生门）。它只查**格子形状**，不查「✅ 是否名副其实」—— 后者归每条自己的证据文件。
# 第二条是门禁自己的证据：`--self-test` 5 例（全绿 · 判据⬜ 必红 · 判据🟡 必红 · 判据 — 不红 · 判据 ➖ 挂起不红）。
python3 Scripts/check-status-gap.py
python3 Scripts/check-status-gap.py --self-test
# 同一项的第二族（2026-11-03，项数不变）：§7.1「智能体剩余 N 条」卡点表是手抄摘要，台账才是状态唯一源
# （铁律 12）—— EXT-001/002 双 ✅ 收口后摘要里仍写「无真 MCP 对端实例」，读的人会去办已办完的事。
# 判据 `Scripts/check-blocker-table.py`：表头「剩余 N 条」= 表行数 · 表里不许再有 §3 已双 ✅ 的号 ·
# §3 未双 ✅ 的 FR-AGT 号一条不许漏登 · 卡点格不许空；「已收口留痕」子表按表头跳过（那里放已闭的号合法）。
# 第二条是门禁自己的证据：`--self-test` 5 例（全绿 · 已收口仍留表 · 表头数不符 · 未闭漏登 · 台账行数不足）。
python3 Scripts/check-blocker-table.py
python3 Scripts/check-blocker-table.py --self-test

if [ "${KEEP_GOING}" = "1" ]; then
  echo ""
  echo "── 逐项判定（--keep-going：跑完再汇总）──────────────────────────────"
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
    n_status="✅ 通过"
    case " ${FAILED_ITEMS} " in
      *" ${n} "*) n_status="❌ 失败" ;;
    esac
    case " $(platform_skipped_items) " in
      *" ${n} "*) n_status="⏭ 跳过（平台不适用）" ;;
    esac
    printf '   第 %2s 项  %s\n' "${n}" "${n_status}"
  done
  echo "   合计：项块 $(item_total) 个 · 失败 ${FAILED_ITEM_COUNT} 项（共 ${FAILED_COUNT} 处）· 平台跳过 ${SKIPPED_COUNT} 项"
fi

if [ "${FAILED_COUNT}" -gt 0 ]; then
  echo ""
  echo "❌ --keep-going 汇总：**失败 ${FAILED_COUNT} 处 / ${FAILED_ITEM_COUNT} 项** —— 逐处点名（行号 = 脚本第几行）："
  echo "${FAILED_LINES}"
  echo "   覆盖面：**项块 ${FAILED_ITEM_COUNT} 项红之外，其余项都跑了**（未执行项 = 无）；平台跳过 ${SKIPPED_COUNT} 项（跳过 ≠ 通过）。"
  exit 1
fi

if [ "${REQUIRE_ALL}" = "1" ] && [ "${SKIPPED_COUNT}" -gt 0 ]; then
  echo "❌ 有 ${SKIPPED_COUNT} 项被跳过，而本次要求「跳过即红」（--require-all）："
  echo "${SKIPPED_ITEMS}"
  exit 1
fi

if [ "${SKIPPED_COUNT}" -gt 0 ]; then
  echo "✅ 本平台（${PLATFORM}）可跑的项全部通过：十九项中跑 $((19 - SKIPPED_COUNT)) 项、跳过 ${SKIPPED_COUNT} 项"
  echo "   —— **跳过 ≠ 通过**，跳过的是平台不适用项，逐条如下（等价物见 §8.3 / §8.5.3）："
  echo "${SKIPPED_ITEMS}"
else
  echo "✅ 验证闭环全部通过（十九项）"
fi
python3 "$ROOT/Scripts/check-doc-placement.py" || FAIL=1
