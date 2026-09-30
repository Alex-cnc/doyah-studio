#!/bin/bash
set -euo pipefail

# 本工程的一条命令验证闭环。
#
# 拆开跑过很多次、也就漏跑过很多次（尤其是文档计数与设计令牌这两项），
# 所以合成一条：**改完代码跑它，十八项全过才算完**。
#
#   1. Core 单测（SwiftPM，不需要数据库）+ 平台适配层单测
#   2. Core 平台中立性（Core 里不得出现平台专属依赖 —— 否则 Linux 编译不过）
#   3. 本地化：Core 展示文本棘轮（R-45：用户可见文案不得硬编码中文，只能比基线更少）
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
#   5. 需求状态一致性（§10.1 索引表 ↔ 正文定义行）
#      + **alpha 范围账**（L-69 条件 ③）：FR 🟡 **逐条**判定 —— 能机器验的给可复跑证据指针、
#        不能机器验的标 `[alpha 不含]`（状态格仍 🟡）。台账 `Scripts/alpha-fr-dispositions.json`，
#        判据 = 台账 ↔ SRS 双向对账 / 标记逐字对上 / 原因档在词表内 / 证据指针存在 / 空跑防护。
#        为什么要有它：v0.1.0-alpha 那次 6 条环境项是**手加**的标记，此后 🟡 增删机器都不说话，
#        发布说明「明确不做什么」那一节就会与文档事实脱节（见脚本头注释）。
#   6. 设计令牌棘轮（App/ 里的裸颜色 / 裸字号 / 裸间距不得比基线更差）
#   7. 平台等价矩阵（§10.10 ↔ `Docs/平台实现状态.json` 台账，列由台账决定）+ 台账校验自检
#      + `P-*` 平台差异登记的两侧对账（§10.9 ↔ 概要设计 §4：双向覆盖 + 同号同物
#      + §8.5.5「已落条但未并入」判红，队列 L-45）
#      （**2026-09-27 第 25~36 轮之间这一行的注释写着「与 §10.9 登记表一致」，那是不折不扣的假话**：
#      当时这一项只做 §10.10 ↔ 台账的矩阵对账，`§10.9 ↔ §4` 一个判据都没有 —— 第 36 轮（L-45）
#      补上第三个脚本后，这句话才成立；注释里的假话先被改正，判据随后补上）
#   8. 平台中立性棘轮（需求规范书里的平台专属词汇不得比基线更差）
#   9. 命令面板接线（清单 ↔ 分派器 ↔ 视图绑定；见脚本注释里的真实缺陷）
#      + 侧边栏折叠状态归属（L-59：状态住在 `AppState`、写入口唯一、默认全展开、未分组不给折叠）
#      + **面板根固定尺寸 frame 的对齐纪律**（L-61：`App/Views/` 里每一处「宽高都是数字字面量」的
#        `.frame(width:height:)` 都要在台账 `panel-root-frames.json` 里有处置；面板根必须**把意图
#        写出来** —— 显式写 `alignment:` 或登记一个在该视图类型里真的存在的撑满令牌，
#        见 `check-panel-root-frames.py`）
#  10. 插件装配链（笔记模块解耦 FR-PLUG-07 + 装配与许可 FR-PLUG-01/02/03/06 + ADR-35）
#      + 笔记模块的**零网络出口**（FR-PLUG-05 ②：数据不外发，见 `check-notes-offline.py`）
#      + **界面检索走库 + 路线如实标注**（L-44：唯一生产点 / 视图不许内存过滤 /
#        路线逐条登记 / 文案键在位且被引用，见 `check-note-search-route.py`）
#  11. 打包 .app（沙箱构建）
#  12. 脚本 shell 多字节安全（bash 3.2 的变量名坑，见 `check-shell-locale-safety.py`）
#  13. 脚本连接信息参数化（连真库的脚本不许写死端口 / 地址 / 账号，见 `check-script-env-parameterization.py`）
#  14. 连接失败的文案覆盖面（驱动错误码 ↔ 文案台账，见 `check-connection-failure-coverage.py`）
#  15. 命令行失败输出的可读化覆盖面（L-15：不许出现「有话说却直接打英文串」的 print，
#      见 `check-cli-failure-readability.py`）
#  16. 越界检查（分层的三书「形态 A」：一次改动不得落在**对侧独占节**内 ——
#      `[独占:macos]` / `[独占:windows]` 标记的节各归其主，见 `check-exclusive-sections.py`）
#  17. vendored SQLite（FR-PLUG-08 / Q23）：台账对账 + 负例自检 + 现编现跑自证
#      （`check-vendored-sqlite.py`｜`--self-test`｜`smoke-vendored-sqlite.py`）
#  18. 生成物一致性（两族）：**生成物不许手改、也不许过期**
#      · 族 ①（L-43，2026-09-27 第 30 轮）：`gen-sqlite-constants.py --check`
#        （`Core/NoteStorage/SQLiteConstants.swift` 与 vendored 头文件逐字节一致）
#        + `--self-test`（5 条篡改都要报红并指名出处）
#      · 族 ②（**L-70，2026-09-28 第 68 轮**）：`check-release-version.py`
#        —— 发布产物版本号的**一个值、三处逐字一致**（`build-app.sh` 的 Info.plist 模板 = 权威／
#        `project.yml` = 源／`.xcodeproj/project.pbxproj` = 生成物，台账 `Scripts/release-version.json`）
#        + **生成物 ↔ 源不许漂移**（目标名 / 包标识 / 每个目标的 `*.swift` 文件名集合，双向）
#        + `--self-test`（10 例：三处各改一处、台账改一处、生成物少目标 / 少源文件 / 被掏空、锚点写错
#        都要报红；末例核对真仓库逐字节未变）。**为什么要有它**：`.xcodeproj` 在本仓**没有任何门禁**
#        （`build-app.sh` 走 SwiftPM，根本不读它）⇒ 入库那份曾经 869 行、包标识还是改名前的
#        `com.vnull.PostgresClient*`、且**少了两个目标**，从 2026-09-22 起就一直过期而无人知
#        （`Docs/项目评审-2026-09-23.md` 把这条记成风险，但风险没有判据）。
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
# 第 8 轮（R-60）又加了两条：**兜底不许给方向结论**（`default:` 必须 `return nil`），
# 以及台账标「中性归因」的那 9 个码（用户取消 / 主动断开 / 协议层 / LISTEN 通道…）
# 必须在 `nonConnectionKeys` 里逐条点名 + 给出语言表键，且**调用方真的接上了这一档**
# （CLI / ErrorPresenter / 连接表单）—— 否则 `describe` 返回 nil 时用户只剩一句英文调试串。
#
# 平台口径（L-33，2026-09-27 第 29 轮）：本闭环**在非 macOS 机器上也能跑**，方式是——
#   · **第 1 / 11 项（要 Xcode 工具链）按平台跳过 + 打印提示**，收尾行如实报「跑了几项 / 跳了几项」，
#     **跳过 ≠ 通过**（逐条列出跳过的项，并指向 §8.3 / §8.5.3 的等价物）；
#   · 第 4 项里 14 份被 `.gitignore` 排除的本地文档**不存在即跳过并提示**（显式点名 / `--require-all` 判红）；
#   · `DOYAH_PLATFORM=macos|windows|linux` 显式声明平台（缺省按 `uname -s` 推断）；
#   · `./Scripts/verify-all.sh --require-all` = **跳过即红**（主开发机上自我证明用）。
#
# 默认就是非沙箱构建（交付口径）：./Scripts/build-app.sh
# 要试沙箱那一面（上架只走沙箱）：DOYAH_SANDBOX=1 ./Scripts/build-app.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${ROOT}"

# ── 平台判定与「跳过」语义（L-33，开发循环第 29 轮）────────────────────────────
# 十八项里有 **两项是 macOS 专属**：第 1 项（Core 单测）与第 11 项（打包 .app）——
# 两者都要 Xcode 工具链（`DEVELOPER_DIR` → `/Applications/Xcode.app/...`，见两份脚本的第 10 / 24 行）。
# 在非 macOS 机器（另一平台 / Linux）上跑，原先会以「命令或路径不存在」的形式**硬失败**，
# 看起来像门禁红了，其实只是平台不适用（对侧逐项实测见 `Docs/概要设计.md` §8.5.6-4）。
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
for argument in "$@"; do
  if [ "${argument}" = "--require-all" ]; then
    REQUIRE_ALL=1
  fi
done

SKIPPED_COUNT=0
SKIPPED_ITEMS=""

skip_step() {   # skip_step <项号> <说明>
  SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  SKIPPED_ITEMS="${SKIPPED_ITEMS}   · 第 $1 项 ${2}
"
  echo "==> $1/18 ⏭ 跳过（平台不适用：PLATFORM=${PLATFORM}，缺 Xcode 工具链）—— ${2}"
  echo "    等价物见 Docs/概要设计.md §8.3（每端必需项清单）与 §8.5.3（另一平台的 PowerShell 版）"
}

if [ "${PLATFORM}" = "macos" ]; then
  # 第 1 项之前先删掉单测数证据文件：留在盘上的旧值会被 Scripts/check-doc-numbers.py 当成
  # 「这一轮的实测」（第 4 项那条判据只认同一次运行的数）。删掉之后，本轮没跑第 1 项时
  # 判据会如实报「跳过实测」——而不是拿一个陈旧数字冒充现状。
  rm -f .build/core-test-count.txt
  echo "==> 1/18 Core 与平台适配层单测"
  ./Scripts/verify-core.sh
else
  skip_step 1 "Core 与平台适配层单测（Scripts/verify-core.sh 要 Xcode 工具链的 swift）"
fi

echo "==> 2/18 平台中立性（Core 不含平台专属依赖 · 脚本不含平台专属路径标识 · 语言登记形状）"
python3 Scripts/check-core-portability.py
# 第 91 轮（提案 0005 **采纳**）：第二条管的是 **`Scripts/*.py` 自己** ——
# `Scripts/` 是**两侧都在跑**的判据（Windows 侧 `windows/Tools/verify-all.ps1` 第 ③ 项就是
# `python Scripts/check-doc-tables.py` + `python Scripts/check-doc-versions.py`），而它们把相对路径
# 铸成字符串（`str(path.relative_to(root))`）去和**手抄的正斜杠清单**比对时，Windows 上
# `str(WindowsPath)` 给 `Docs\README.md` ⇒ **集合匹配恒 False**、凡命中扫描面的文档全部判红，
# 而 macOS 上 `os.sep` 就是 `/` ⇒ **只在那一台机器上红**（对侧 2026-09-29 第 81 轮实测：
# `check-doc-versions.py` 误报 6 份、`check-doc-tables.py` 误报 26 处，而 A/B/C 三档全过）。
# 判据 A 禁这一形状（仓内 13 处已全部改 `.as_posix()`，其中第三处 `check-doc-numbers.py` 是本轮扫出来的）、
# B 例外台账默认**空**、C 空跑防护、D 判据自己的证据（8 例）。样式见 `Docs/概要设计.md` §8.3。
python3 Scripts/check-script-portability.py

# L-106（FR-EDIT-38 ①③，2026-09-30 开发循环第 117 轮）：语言的**登记形状** ——
# 与本项同源，都是「Core 的形状」那类判据（项数仍十八）。
# 「语言表声明式登记」这句话要能被机械看住：语言知识（扩展名映射 + 关键字 / 类型 / 字面量 /
# 注释 / 运算符规则集）只允许住在 `Core/CodeLanguageDefinitions.swift`，而**消费方那一族**
# （词法器 / 规则集 / 判语言 / 补全 / 两个编辑器 / CLI）里出现 `language == .xxx` / `case .sql:`
# 这类**身份分支**即判红 —— 那正是「加一个语言要改核心代码」的形状，而它不报错、只是变笨。
# 顺带看住三件登记自洽：语言标识与登记项**同集合** / 扩展名与文件名不许两个主人 /
# `isCode` 为真者必须给得出注释规则与字符串界定符（缺了 = 识别了却一个颜色都没有）。
# 高亮色一律走 `SyntaxTone` 令牌（FR-EDIT-38 ③）：编辑器里出现裸色值即判红。
# 判据自己的证据两处：`--self-test` **7 例**（夹具一律在临时副本上写坏，末例核对真仓库逐字节未变）
# + 入口证据 `Scripts/test-language-registry-gate.py` **例数 4**（走的是**命令行路径**：
# 真仓库 exit 0 / 写坏 exit 1 并点名到文件 / 参数错 exit 2 / 真仓库逐字节未变 —— 函数路径与
# 命令行路径的坏法不同，两条都要有人跑）。
python3 Scripts/check-language-registry.py
python3 Scripts/check-language-registry.py --self-test
python3 Scripts/test-language-registry-gate.py

echo "==> 3/18 本地化：Core 展示文本棘轮（R-45）+「当前语言只有一个来源」（L-13）+「文案即所见」（L-19）+「语言是传进来的」（L-47）"
python3 Scripts/check-core-localization.py
# L-13：界面语言有两条路 —— `L(...)` 与**显式传语言下去**（`summary(language:)` 之类）。
# 后者原先取的是**用户选择**（`LocalizationManager.shared.language`），绕过了渲染语境：
# 第 13 轮读图抓到的真缺陷就是它 —— 中文界面的行详情侧栏写着 `Text · 12 characters`。
# 收成一个口子 `effectiveLanguage`（宿主语境优先），并把这个口径变成机械判据。
python3 Scripts/check-effective-language.py
# L-46（2026-09-27 第 37 轮）：上面两条只比**模板与模板**，没有人比过**模板与实参**。
# 真缺陷就长在这条缝里（第 37 轮实测）：`App/Views/AboutLicenseSheet.swift` 三处
# `L(.licAboutEdition)` / `L(.licAboutAppVersion)` / `L(.licAboutActivityItems)` 不传实参，
# 而模板是 `当前版本：%@` —— `LocalizationManager.text` 在 `arguments.isEmpty` 时
# **原样返回模板**，于是界面上印出的就是 `%@` 本身（中文英文都一样）。
# 判据四条：A 数字实参落 `%@` 槽 / A′ 字符串字面量落 `%d` 槽 / B 实参数 ≠ 占位符数 /
# C·D 类型不明的实参必须**逐条登记形状**（台账 `Scripts/format-argument-dispositions.json`）
# 且命中处数只许不增（棘轮）。第二条是**门禁自己的证据**：9 例负例（A / A′ / B / C / D /
# 例外陈旧 / 空跑不许通过 …，夹具一律在临时目录，末例核对真仓库文件逐字节未变）。
python3 Scripts/check-format-arguments.py
python3 Scripts/check-format-arguments.py --self-test
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
python3 Scripts/check-copy-emphasis.py
python3 Scripts/test-copy-emphasis-gate.py
# L-47（2026-09-28 第 46 轮）：上面几条比的都是「文案怎么取」，谁都没管**语言从哪来**。
# 真缺陷正长在这条缝里（第 46 轮读图 `diagnosis-empty-en`）：英文界面上界面文案都是英文，
# 唯独「给模型的资料」整块中文 —— `Core/DiagnosisContext.swift` 的文件私有取值助手把
# `language:` **钉死**成 `.simplifiedChinese`，而语言表里 `diagnosisTarget` /
# `diagnosisFormatConclusion` … 这些键**都有英文译文**却只被这一处引用 ⇒ **英文译文永远
# 不可达（死译文）**。R-45 的棘轮数的是「含**汉字**的字面量」（这里一个汉字都没有）、
# `check-effective-language.py` 只扫 `App/` 且只禁「按用户选择取语言」⇒ 两边都没覆盖
# 「把语言写成字面量」这个形状。
# 判据四条：A 写死语言的调用点必须逐条登记（按文件，带 maxSites 与理由；`maxSites: 0` =
# 回归钉）/ B 死译文双向对账（新增未登记的死键 ⇒ 红；修好不销账 ⇒ 红；包装函数
# `func t(_ key: LKey …)` 的每个调用点都算写死语言）/ C 本轮修的那一族不许回退
# （`DiagnosisContext` 的文本出口必须带 `language:` 形参、`DiagnosisAdvice.parse` 必须带、
# 面板必须传 `effectiveLanguage` —— 只靠 A 挡不住「删掉形参再在函数体里写死」）/
# D 空跑不许通过（语言表解析不到键、键引用为 0、扫到的文件过少都判红）。
# 台账 `Scripts/literal-language-dispositions.json`；负例 `test-literal-language-gate.py` **17 例**
# （第 46 轮落地时 9 例，L-65 第 2/3/4 批又各补了 1~3 例、第 5 批 +3 例 —— 例数的唯一来源与逐处对账见
# `Scripts/self-test-counts.json`，一律在临时副本上写坏）。
python3 Scripts/check-literal-language.py
python3 Scripts/test-literal-language-gate.py

echo "==> 4/18 文档表格与派生计数"
# L-33（2026-09-27 第 29 轮）：本项的默认清单里有 **14 份被 `.gitignore` 排除的文档**
# （兼容性矩阵 / GBase-技术验证 / 测试用例 / 发布方案 / 手工验收运行手册 + **L-41 起纳入的
# `智能体助手-开发spec.md` 与 `design/开发循环-任务队列.md`** + **L-89 起纳入的 6 份**：
# `人工点验-单击清单-macOS-20260927.md` / `夜间开发记录_20260921-22.md` / `接管记录_v2.3.md` /
# `调研书-AI智能体能力基线.md` / `调研书-主流数据库客户端基础功能.md` / `项目评审-2026-09-23.md`）
# —— 它们只在主开发机上，
# 干净克隆与另一平台都没有。原先一律判红 ⇒ 那台机器上这一项**必红且与改动无关**（§8.5.6-4）。
# 现在：默认清单里不存在 → **跳过 + 高声提示**；显式点名 / `--require-all` → 判红。
# 本闭环传不传 `--require-all` 由参数决定（主开发机上自我证明时加）。
# **口径的两个数不是这里说了算**（第 65 轮 L-72 ㈡）：`14 份被排除` / `44 份命名 + 1 条通配 =
# 实跑 45 份` 由台账 `Scripts/doc-numbers.json`（`doc-tables-lists` / `doc-tables-files`）登记，
# 判据 `Scripts/check-doc-numbers.py` 每次自己算一遍（导入 `check-doc-tables.py` 读清单 +
# `git check-ignore` 实测 + 真跑它一遍）再与本文件 / 该脚本 / `AGENT-SPEC.md` 逐处对账。
if [ "${REQUIRE_ALL}" = "1" ]; then
  python3 Scripts/check-doc-tables.py --require-all
else
  python3 Scripts/check-doc-tables.py
fi
# 这一半是门禁自己的证据（L-33；L-41 补例 5；L-89 补例 6）：干净克隆跳过 14 份且 exit 0 /
# --require-all 判红 / 显式点名判红 / **写坏一行被判红并指名行号** / **带表格却不在清单判红且归档豁免** /
# 真仓库 46 份受检无跳过（45 份命名 + 1 份通配；
# **末例核对真仓库逐字节未变**）。
python3 Scripts/check-doc-tables.py --self-test
# L-32（2026-09-27 第 28 轮）：变更记录版本号**唯一**、头部版本格**可判**（= 变更记录最高号，
# 或带「基线 / 首版」标注并在标注里写出当前号）、队列**定义行**条目号唯一。
# 取号唯一来源 = `Scripts/next-doc-version.py`（max+1）—— 禁止手抄：撞过三次
# （概要设计 v2.35 与对侧同号 / 队列 L-25·L-26·L-41 同号 / 三书 P-15 同号不同物）。
# 本项现在跑三个脚本，与第 3 / 7 / 10 / 15 项同一做法（**项数不变**）。
python3 Scripts/check-doc-versions.py
# 派生文件不得漂移：终端配色 JSON ↔ Core ↔ 人读文档三方一致（FR-EDIT-29 的跨平台交接物）
python3 Scripts/check-terminal-palette.py
# L-55（2026-09-28 第 61 轮）：上面几条管的是**表格结构**（列数 / 计数 / 版本号 / 派生计数），
# 管不了「独立写在各处的**工程设施数字**」—— 闭环项数、单测数、快照张数。真现场：
# `Docs/概要设计.md` §8.3 闸门表写着 `verify-core.sh`（**760** 项），实测 2056 项（那是 09-23 的旧值）；
# `AGENT-SPEC.md` 跑法注释里写着 2046 tests / 快照 140 张 · 70 组，实测 2056 / 152 · 76。
# 口径 = **唯一来源台账** `Scripts/doc-numbers.json`（照 `Scripts/vendored-sqlite.json` 的做法），
# 判据 `Scripts/check-doc-numbers.py` 做**三向对账**：台账 ↔ 实测（能机械复算的必须复算：
# 闭环项数从 `==> N/M` 项块数、单测数读 verify-core.sh **同一次运行**写下的计数文件、
# 快照读 manifest）↔ 文档里每一处现状声明（精确锚点 + 有限反扫，写错 / 删光都判红）。
# 它同时管住「有判据、没闭环」那一族：`Scripts/check-*.py` 每个都必须被本脚本引用，
# 或在台账里逐条登记理由（现有 1 条豁免 = 快照语言覆盖门禁）。
# 边界（如实登记，见脚本 docstring）：**不做全文反扫**（三书与开发记录里充满历史值），
# **对侧独占节整段跳过**（红线第 6 条：本侧不改的也不拿它判红），**变更记录行整行跳过**。
python3 Scripts/check-doc-numbers.py
python3 Scripts/check-doc-numbers.py --self-test
# L-56（2026-09-28 第 62 轮）：上面几条仍然管不到 **§6 待拍板队列的编号与状态**。真现场三类：
# ① `Q28` 同号两条（Retro 技术栈 / 本仓与宿主的关系）—— 两条不同的问题共用一个号；
# ② **8 行编号格是 L-41 修列数时补的 `——` 占位**（FR-IO-04 / FR-AI-12 / `.et` /
#    NFR-COMP-03 / cua-driver 两个授权 / 本机模型凭据 / 环境类授权（9 项）/ 机器载荷失败原串）
#    —— 表格结构合法了，但条目**无法被引用、无法被对账**；
# ③ `Q19` 早已在 §4 记「已拍板（2026-09-27）」，§6 却一直挂着「⏳ 待拍板」⇒ **每轮探针都把它
#    报成「待你拍板」**（同族另有 Q29 前提作废、Q34 / Q35 / Q36 / Q40 已随当日口径关闭）。
# 判据 `Scripts/check-doc-q-series.py`：A 编号可判且唯一 / B 状态只写词表词 / C 关闭行成对 /
# D §4 ↔ §6 同源（Q17~Q23 = Studio 号空间）/ E 空跑防护（行数 / 号数 / 对账对数下限）。
# 该文件与 check-doc-tables 那份同属 `.gitignore` 内的本机台账 ⇒ 不在盘上时**跳过 + 高声提示**，
# `--require-all` 判红；负例 `--self-test` **8 例** + 末例核对真仓库逐字节未变。
if [ "${REQUIRE_ALL}" = "1" ]; then
  python3 Scripts/check-doc-q-series.py --require-all
else
  python3 Scripts/check-doc-q-series.py
fi
python3 Scripts/check-doc-q-series.py --self-test
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
# 负例 `--self-test` 11 例（好情况 / runner 非零退出 / 例数漂移 / 收尾行解析不到 / 锚点值写错 /
# 锚点被删 / 台账结构错 / 空跑防护 / 静态棘轮 / 末例核对真仓库逐字节未变），夹具一律在临时目录。
python3 Scripts/check-self-test-counts.py
python3 Scripts/check-self-test-counts.py --self-test

echo "==> 5/18 需求状态一致性（索引表 ↔ 正文定义行）+ alpha 范围账（FR 🟡 逐条判定）"
python3 Scripts/check-status-consistency.py
# L-69 ③（2026-09-28 第 56 轮）：上面那条管的是「索引 ↔ 定义行**状态一致**」，管不了
# 「这条 🟡 到底算不算 alpha 范围」。v0.1.0-alpha 给 6 条环境项手加了 `[alpha 不含]`，
# 此后 🟡 增删、标记被删、标记被挪格，机器一句都不说 ⇒ 发布说明「明确不做什么」写不出来。
# 现在把它变成台账 + 双向判据（台账 `Scripts/alpha-fr-dispositions.json`）：
# A 台账 ↔ SRS 双向对账（漏一条 / 留陈旧条目都红）；B 台账声明的标记必须逐字出现在定义行里，
# 反向也判（手写标记绕不过对账）；C 原因档必须在词表内；D 每条至少一个**存在的**证据指针；
# E 空跑防护。负例 `--self-test` 11 例，一律在临时副本上写坏，末例核对真仓库逐字节未变。
python3 Scripts/check-alpha-fr-dispositions.py
python3 Scripts/check-alpha-fr-dispositions.py --self-test

echo "==> 6/18 设计令牌棘轮 + 外观样张与产品同源 + 主题集（三选一）"
python3 Scripts/check-design-tokens.py
# L-79 ㈡（2026-09-29 第 76 轮）：上面那条棘轮管的是 **App/ 里的裸颜色 / 裸字号 / 裸间距**，
# 管不了「**样张到底是不是照着产品画的**」。真现场：`Scripts/design-mock.swift` 自带一份调色板
# （头部注释写着「未来会变成 Core/DesignTokens.swift 的真身」）⇒ 方案 D 换值后，它照样出**旧配色**
# 的图（深色中性灰 + 旧强调色），而逐屏复查 / 定调 / 跨端对照全都建立在这张图上。
# 判据 `Scripts/check-design-mock-tokens.py`（项数仍十八）：
#   A 渲染脚本里不许有色值字面量（只豁免 3 个 macOS 交通灯系统外壳色）+ 两条「第二份调色板形态」回归钉
#   B 渲染脚本必须真的引用令牌（8 类符号，有处数下限 —— 引用被删光就是空跑）
#   C 渲染入口 `Scripts/render-design-mock.sh` 必须把 `Core/DesignTokens.swift` 编进来
#   D **逐屏复查**：产品源码（Core / App / Tests / CLI / Platform / Tools / TestsUISnapshot，
#     现 417 个文件）里不许残留**方案 D 之前的旧调色板值**；豁免只有两处 —— `Core/AccentTheme.swift`
#     与它的单测（交互强调色是**另一条轴**，用户可切的那三个候选本来就不在 D 的值表里）
#   E **行为证据**：真跑一遍渲染入口（要求 exit 0 + 自检收尾行 + 张数下限），并判**深色样张的内容底
#     必须带蓝调**（方案 D 深海军蓝实测 B−R ≈ 45；旧中性灰 ≈ 11 ⇒ 门槛 20）—— 非 macOS 跳过并高声提示
# L-79 ㈡ 的负例 **13 例**（红/绿成对，夹具一律在临时目录，末例核对真仓库两份文件逐字节未变）。
python3 Scripts/check-design-mock-tokens.py
python3 Scripts/check-design-mock-tokens.py --self-test
# L-80 ㈠（2026-09-29 第 77 轮）：上面两条管的是**一套值**（方案 D = 默认主题）画出来的样子，
# 管不了「**三套值**（主题三选一）各自成不成立」。真现场：需求提出者要「一个 theme 主题选项」，
# Linux 版早有豆芽绿 / 玫瑰金 / 科技蓝三选一 ⇒ 令牌从一套变三套，而这件事有三个缝：
#   ① 单测与值表**用同一份实现**算对比度（判据与被判对象同源）⇒ 新加一套表时，
#      "漏了某个角色""某个值不过门槛"只会在同一个实现里红；
#   ② 主题名要与 Linux 侧对齐、推导出来的两套值**不许静默当实际值**—— 这两件事单测根本看不见；
#   ③ 「语法六档挂家族」这条口径在换表时最容易脱钩（有人直接把某个语法色写回十六进制）。
# 判据 `Scripts/check-design-themes.py`（项数仍十八）：
#   A 主题集 = 台账里那三个（id 与顺序），`DesignTheme.all` 不许漏列主题，`ThemePalette.of` 三支齐全
#   B 每套值表必须含全部 20 个字段（18 色角色 + 发丝线两参数），缺一个即红
#   C **独立复算**：本脚本自己重新实现 WCAG，从 Swift 源里解析出三套值，逐主题 × 深浅两态复算
#     186 条门槛（正文 ≥4.5 / 强对比 ≥7 且强于正文 / 辅助 ≥3.0 / 禁用更淡且 ≥1.5 /
#     状态色在两表面 ≥3.0 / 强调家族按角色 4.5 与 3.0 / 语法六档两两不同 / 深色五档明度递增 /
#     浅色 content 最亮 / 表面距离 ≥0.02 / 浅色发丝线比 content 暗）
#   D `SyntaxTone.color(in:)` 的六行映射逐行对账（keyword→accentGlow / string→warm / number→teal /
#     function→accent / identifier→primary / comment→tertiary）
#   E 名对齐（三个主题名 = Linux 侧的名，**认 §9 主题表里那一行**，正文提到不算）+
#     推导主题 ↔ 待值登记成对（值表紧挨的注释块里必须有「推导草案」标记 +
#     `Docs/发布计划.md` 的待输入表还登记着「豆芽绿 / 玫瑰金 色值（Linux 侧）」）
#   F 空跑防护（主题数 / 字段数 / 复算条数 / 文档落点四条下限）
# L-80 ㈠+㈡ 的负例 **25 例**（24 个红/绿成对 + 末例核对真仓库十三份文件逐字节未变，
# 夹具一律在临时目录）。**两条是自检当场抓出来的门禁太松**：⑨ 文档侧原先只查"正文里提过这个名"
# ⇒ 表被改坏也放过；⑮ 推导标记原先只认"推导"两个字 ⇒ 抹掉标记行、说明段里的"推导口径"照样顶数。
# ㈡ 那六例（第 78 轮）钉的是**入口**这一层：入口被削成非 `DesignTheme.all` / 少一个真实场景 /
# 推导不逐条标注 / 强调色入口被静默删 / 宿主语境覆盖写了盘 / 主题行被掏空。
# L-85 那三例（第 83 轮）钉的是**两轴正交**：深浅轴少一态 / 两轴串键（配色轴的运行时对象里出现
# 深浅轴的键）/ 组合没到像素（面板快照不再取角像素）。
python3 Scripts/check-design-themes.py
python3 Scripts/check-design-themes.py --self-test

echo "==> 7/18 平台等价矩阵 + P-* 平台差异登记对账"
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
# ① 对账：两侧 `P-*` 编号集合必须互相覆盖、同号必须同物（领域归一后逐字相等）；
# ② `--self-test`：8 例负例（未并入权威登记表 / 编号空间断档 / 同号不同物 / 归一有效 /
#    §8.5.5 已落条但未并入 / 小节被删不许空跑当通过 …，末条核对真仓库两份文档逐字节未变）。
# 它顺带把「对侧在 §8.5.5 先落条、待契约侧并入」这个流程变成判红项：不并入就一直是红的。
python3 Scripts/check-p-parity.py
python3 Scripts/check-p-parity.py --self-test

echo "==> 8/18 平台中立性棘轮"
python3 Scripts/check-platform-neutrality.py

echo "==> 9/18 界面接线与状态归属（命令面板 FR-EDIT-25 / 侧边栏折叠 FR-CONN-15 / 空数据按钮 L-50 / 终端多会话页签 L-84）"
python3 Scripts/check-palette-wiring.py
# L-59：**侧边栏的折叠状态住在 `AppState`，不住在视图里** —— 人工点验批次 1 第 3 条实测为挂
# （「记不住折叠状态」）：`ConnectionListView` 的局部 `@State` 随活动栏分支重建归零，而当时
# 所有门禁全绿。判据 = 视图不许有局部折叠状态 / 状态必须是 `@State`-free 的 `AppState` 属性
# 且 `private(set)`、写入口唯一、默认全展开 / 视图绑定必须经 appState / 未分组那一段不许有折叠 /
# 空跑防护；台账式常量在脚本里，负例 `Scripts/test-sidebar-collapse-state.py`（11 例）。
# 行为那一半（重建前后像素逐字节相同）在 `TestsUISnapshot/UISnapshotSidebarStateTests.swift`，
# 按 L-01 的纪律不进每轮门禁（要 `DOYAH_UI_SNAPSHOT=1`）。
python3 Scripts/check-sidebar-collapse-state.py
python3 Scripts/test-sidebar-collapse-state.py
# L-50：**空数据时按钮必须有个说法**（灰着 / 可点给理由 / 够不着按钮），不许「可点却静默无反应」。
# 2026-09-26 读图在笔记编辑器上抓到过第三种（「保存」满色可点、点下去静默 return）。这一项把
# `App/AppState.swift` 里每条「内容为空」守卫与它的处置逐条对账（双向：未登记 ⇒ 红、陈旧 ⇒ 红），
# 并钉住 `view-disabled` 那一档的**唯一出处**（判据属性全局只定义一次 / 守卫必须用它 /
# 指定视图必须真的 `.disabled` 它 / 视图不许再自己算一遍）。台账与词表见脚本 docstring，
# 台账 `Scripts/empty-action-button-dispositions.json`；负例 `Scripts/test-empty-action-buttons.py`
# 11 例（视图处置被删 / 守卫改回裸判断 / 新增未登记守卫 / explain 其实没话 / 视图本地锚点被删 /
# 判据两处定义 / 视图重新推导 / 台账陈旧 / 台账写坏 / 前提自检 / 真仓库逐字节未变）。
python3 Scripts/check-empty-action-buttons.py
python3 Scripts/test-empty-action-buttons.py
# L-61（2026-09-28 第 64 轮）：上面两条管的是「按钮有没有说法」与「状态该活多久」，
# 管不到**面板根自己的尺寸与对齐**。真现场（第 41 轮修 L-58 时实测）：`PrivilegePanel` 的
# 内容在它自己的 `720×620` 里被**垂直居中**（顶上约 150pt 空白）—— `.frame(width:height:)`
# 不写 `alignment:` ⇒ SwiftUI 取默认 `.center`，而那个 `VStack` 里没有可伸缩高度的子视图。
# 当时编译过、Core 单测全绿、文档与快照门禁全绿（「内容在自己尺寸里浮着」没人看）。
# 判据判的是**把意图写出来**（不判居中对不对 —— 静态查不出可伸缩子视图，docstring 里写清了）：
# A 扫描完整性 · 双向对账（每一处「宽高都是数字字面量」的 `.frame` 恰好一条台账；新增没登记 /
# 台账陈旧 / 处数不符都判红）/ B 面板根（width ≥ 台账门槛 400）与装饰的分类对账 /
# C 面板根必须选一条路线并留下盘上锚点 —— `explicit-alignment`（源码**真的**写了 `alignment:`，
# 值逐字对账）或 `content-stretches`（`stretchProbe` 取自台账 `probeVocab`，且在**该视图类型
# 范围内真的存在**）/ D 理由不许空 / E 空跑防护（文件数 · 命中数 · 面板根数 · 台账数下限，
# 台账声明的扫描事实与磁盘相等）/ F 范围外（用设计令牌 / 变量给尺寸的 `.frame`）**显式打印**数量。
# 负例 `--self-test` 19 例（含「现造一块既没写 alignment、类型里又没有撑满容器的面板根 ⇒
# 三条路线全红」这一组，与一条「显式对齐被删但登记还在」；夹具只拷 `App/`，末例核对真仓库逐字节未变）。
python3 Scripts/check-panel-root-frames.py
python3 Scripts/check-panel-root-frames.py --self-test
# L-111（2026-09-30 第 121 轮）：**编辑面的行号列**判据。行号一半是口径（在 `Core/CodeLines`，
# 15 项单测早就钉住了），另一半是画法 —— 画法这一半此前**没有判据**：工作区编辑器自己长了一套
# 列宽算法 + 行起点计算，数据库侧 SQL 编辑器一行都没有，于是在队列上挂了 4 天的「要不要一起加」。
# 判据：A 双向对账（`App/**/*.swift` 里每个 `NSTextView` / `NSTextField` 子类都要在台账
# `Scripts/editor-line-number-surfaces.json` 登记「画 / 不画 + 为什么」）/ B 挂法齐备（登记为「画」的
# 编辑面必须真的 `gutter.reload(` + `gutter.draw(in:`）/ C 唯一出处（`CodeLines.lineStarts(` 在 `App/`
# 里恰好一处、列宽算法全工程恰好一处、别处的 `gutterWidth(digits:` 只许转发）/ D 三书里的口径语句
# 锚点仍在（`Docs/` 不在盘上时跳过并高声提示，跳过 ≠ 通过）/ E 空跑防护。
# `Scripts/check-editor-line-numbers.py` 的负例 `--self-test` **10 例**（夹具 = 真源文件与真文档的拷贝，
# 末例核对真仓库逐字节未变）。
python3 Scripts/check-editor-line-numbers.py
python3 Scripts/check-editor-line-numbers.py --self-test
# L-84 ㈠㈡（2026-09-29 第 81 / 82 轮）：终端**多会话（页签）**判据。需求提出者把它提为刚需
# 时给的原话是「一个 terminal 在执行 dsh-tui，遇到要执行命令只能去开系统终端，违背了我这个软件的初衷」。
# 判据判的是「新建 / 关闭 / 切换 / 标题推导 / 关闭确认 / 按键映射」这**六组判断真的在 `Core/TerminalTabs.swift` 里**、
# 且被 `Tests/TerminalTabsTests.swift` 逐组钉住（另加「Core 不出用户可见文案」与「页签文案键中英齐」）；
# **㈡ 起同一判据还判界面接线**（App 侧锚点 **41 处**，L-89 ㈡ ③ 第 96 轮扩）：页签头在工具条
# `Spacer` **之前**（口径①「左侧」，位置也判）/ 右侧那排按钮**六个符号一个不少**（清单数的是五个动作，
# 第 6 个是折叠态的展开箭头）**且新画的按钮必须登记**（反向对账棘轮 `RIGHT_SIDE_CALL_SITES` ——
# 只判「登记过的还在」拦不住「新画一个没登记的」）/ 每页签一条独立会话（不是「一个模型切屏」）/
# ⌘T ⌘W ⌘1…9 的接线点（判定仍只有 Core 一处）/ 双击重命名 / 二次确认 / 退出标记 / 重启作用在当前页签 /
# 工具条那一行是**独立视图** `LowerPaneTabStrip`（抽出来才能单独离屏渲染）。
# App 侧探针**六个用例**锚点（`TestsUISnapshot/TerminalTabsProbeTests.swift`：前三个真开 shell 验
# 独立性与退出、确认链路；后三个 = 版面（页签头在左 / 右侧按钮位置不动的**像素**判据）、按钮按状态齐备、
# ⌘1…9 / ⌘⇧[ ⌘⇧] / 改名落到对的会话）。
# 真人点验 = 主诉场景（一个页签跑 `dsh-tui`、另一个执行命令，互不干扰）。
# 负例 `--self-test` **13 例**（红 / 绿成对，夹具一律在临时目录，末例核对真仓库十三份文件逐字节未变）。
python3 Scripts/check-terminal-tabs.py
python3 Scripts/check-terminal-tabs.py --self-test

# L-89 ㈡ ④（第 97 轮）：**大结果集滚动**（清单 §4 FR-RES-07）那一行的阈值台账 ——
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
# 自检用例 `--self-test` **11 例**（红 / 绿成对，夹具在临时目录，末例核对真仓库台账逐字节未变）。
python3 Scripts/check-result-scroll-ledger.py
python3 Scripts/check-result-scroll-ledger.py --self-test

echo "==> 10/18 插件装配链（FR-PLUG-01~03 / 06 / 07 + ADR-35）"
python3 Scripts/check-note-module-isolation.py
python3 Scripts/check-plugin-assembly.py
# L-22：FR-PLUG-05 的「Linux 笔记＝本地离线、数据不外发（公司合规）」不能只是一句话 ——
# 笔记模块范围内**逐行扫网络 API 令牌表**（URLSession / import Network / NWConnection /
# http(s) 字面量 / URL(string: …），命中即红并点名文件与行号；范围声明与磁盘事实、
# 与上面那份解耦清单**两边对账**（漏登一个源文件也是红）。判据与台账见
# `Scripts/notes-offline-gate.json`（关键令牌不许被拿掉、例外要写明理由且锚点陈旧报红）。
python3 Scripts/check-notes-offline.py
# L-44：界面检索**走库**（唯一生产点）+ **所走路线如实标注**（子串兜底 / 检索没跑成）——
# 视图不许拿已加载的列表自己过滤；每条路线都要在台账里登记处置（给键或显式 nil）并与实现
# 逐条相等；文案键要真的在语言表里（中英都在）且真的被引用（死键也判红）。
# L-89 ㈡ 第 8 条：**结果落地只有一个出口**（「键盘快打」那一行）—— 出口里的词比对在位 /
# 两处落地形状各只出现一次且都在出口体内 / `runSearch()` 两条分支都经出口且不自己落地 /
# `runSearch()` 不读搜索框（词是参数）/ `searchNotes()` 真的走到 `runSearch()`。
# 判据与台账见 `Scripts/check-note-search-route.py` / `Scripts/note-search-route.json`；
# 负例 `test-note-search-route.py`（15 例：生产点消失 / 第二条路 / 视图过滤 / 台账与实现不一致 /
# 新增路线没登记 / 语言表缺中文 / 死键 / 两处空跑防护 / 落地出口的词比对被删 / 一条分支绕过出口 /
# 落地形状多出一处 / 查库那一步又读搜索框 / 真仓库逐字节未变）。
python3 Scripts/check-note-search-route.py
python3 Scripts/test-note-search-route.py

if [ "${PLATFORM}" = "macos" ]; then
  echo "==> 11/18 打包 .app（沙箱）"
  ./Scripts/build-app.sh
else
  skip_step 11 "打包 .app（Scripts/build-app.sh 走 xcodebuild，且产物是 .app 包）"
fi

echo "==> 12/18 脚本 shell 多字节安全（bash 3.2 变量名坑）"
python3 Scripts/check-shell-locale-safety.py

echo "==> 13/18 脚本连接信息参数化（连真库的脚本不许写死端口 / 地址 / 账号）"
python3 Scripts/check-script-env-parameterization.py

echo "==> 14/18 连接失败的文案覆盖面（驱动错误码 ↔ 文案台账）"
python3 Scripts/check-connection-failure-coverage.py

echo "==> 15/18 可读化覆盖面（L-15 命令行失败输出 + L-74 非文本类型那一格的值）"
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
# 与 psql 的文本形态逐条相等）。L-74 的负例 **10 例**（一律只在临时副本上写坏，末例核对真仓库逐字节未变）。
python3 Scripts/check-cell-decode-coverage.py
python3 Scripts/check-cell-decode-coverage.py --self-test

echo "==> 16/18 越界检查（三书独占节：改动不得落在对侧节内）"
# 形态 A（2026-09-27 拍板）：三书单点定稿，但「平台实现」层按端独占 —— 标记 `[独占:macos]` /
# `[独占:windows]` 的节只由该侧改；本机 = macOS 侧。判据与逃生门见脚本头注释。
# 第二条是**门禁自己的证据**（L-42）：**18 例**负例里含「非所有者新开 `[开放]` 节」这条窄通道 ——
# 判据写完不对已知改动报红，等于没有。两个脚本对外只认退出码，`--self-test` 红了整项就红。
# 第 33 轮起本脚本是**三副本同源**的「并集」版（提案 0003 裁决：Notes 副本的侧别别名 / `--contract-docs` /
# 拿不到基线退出 2 + 本侧未跟踪增量），`--base` 显式给了却解析不到**也退出 2**（不许静默放行）。
python3 Scripts/check-exclusive-sections.py
python3 Scripts/check-exclusive-sections.py --self-test

echo "==> 17/18 vendored SQLite（FR-PLUG-08 / Q23）：台账对账 + 负例 + 现编现跑自证"
# 为什么这三条必须一起跑（第 18 轮 L-25 第 1 批）：
#   · 这份 `sqlite3.c` 是 9.5 MB 的**生成文件**，换版本 / 手改一行 / 编译宏掉一个都**不会有症状**，
#     只会让三端行为悄悄不一致（FR-PLUG-08 的口径是「三端同一份引擎，不许换系统 libsqlite3」）；
#     所以第一条把每个事实（文件哈希 / 头文件版本串 / 宏 / 公共头目录 / 许可 / 来源 / 接线）都做成对账；
#   · 第二条是**门禁自己的证据**（**13 条**篡改全部要被抓到并指名出处 —— 六类篡改 + 证据锚点 +
#     接线 + 项号自洽 + 台账空跑防护 …，必须真的报红）；
#   · 第三条是**行为证据**：把 sqlite3.c 现编成可执行文件跑一遍 —— 版本 / 四条宏 / WAL / 参数化
#     读写 / DQS=0 报错，以及 **FTS5 中文检索**（默认分词器 0 命中、trigram 3 字以上才命中，
#     两条都钉住 —— 这是「笔记按条件查与全文检索」这条判据的真正口径）。
#     它**不经过 SwiftPM**，所以与绑定层那个工具链缺陷无关，今天就能当证据。
python3 Scripts/check-vendored-sqlite.py
python3 Scripts/check-vendored-sqlite.py --self-test
python3 Scripts/smoke-vendored-sqlite.py

echo "==> 18/18 生成物一致性（L-43）：生成物 ↔ vendored 头文件逐字节"
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

if [ "${REQUIRE_ALL}" = "1" ] && [ "${SKIPPED_COUNT}" -gt 0 ]; then
  echo "❌ 有 ${SKIPPED_COUNT} 项被跳过，而本次要求「跳过即红」（--require-all）："
  echo "${SKIPPED_ITEMS}"
  exit 1
fi

if [ "${SKIPPED_COUNT}" -gt 0 ]; then
  echo "✅ 本平台（${PLATFORM}）可跑的项全部通过：十八项中跑 $((18 - SKIPPED_COUNT)) 项、跳过 ${SKIPPED_COUNT} 项"
  echo "   —— **跳过 ≠ 通过**，跳过的是平台不适用项，逐条如下（等价物见 §8.3 / §8.5.3）："
  echo "${SKIPPED_ITEMS}"
else
  echo "✅ 验证闭环全部通过（十八项）"
fi
