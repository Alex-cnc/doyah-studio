#!/bin/bash
set -euo pipefail

# 「待人工验收清单」B 类条目的 **App 内探针**（队列 L-89 —— 把「需要你点一下」变成「机器判得住」）。
#
#   ./Scripts/run-manual-verification-probes.sh                     # 两遍：普通构建 + 沙箱标记
#   ./Scripts/run-manual-verification-probes.sh --filter 用例名片段   # 只跑某一部分（仍跑两遍）
#
# ## 为什么跑**两遍**
#
# 清单里 `FR-CONN-18 沙箱告知` 那一行判的是「**沙箱构建**下界面必须多出一句说明（并给出非沙箱构建的命令）」，
# 而「是不是沙箱」的依据是进程环境变量 `APP_SANDBOX_CONTAINER_ID`（沙箱进程自带标记）——
# **一个进程只能是一面**。两遍合起来才把「环境 → 界面」这条对应关系判完整：
#
#   · 普通那遍：该说明**不许**出现；
#   · 沙箱标记那遍：该说明**必须**出现，且与普通那遍相比**只多它这一句**。
#
# 逐句断言（中英各判一次）写在 `TestsUISnapshot/ManualVerificationProbeTests.swift` 里；
# 本脚本负责把两遍串起来，并**跨清单再判一次** —— 防「两遍其实跑的是同一面」（那种情况下
# 每遍自己都绿，而「环境决定界面」这件事根本没被验过）。
#
# ## 第二批（队列 L-89 ㈡，第 92 轮）：命令面板接线
#
# `TestsUISnapshot/PaletteWiringProbeTests.swift` 判的是清单里 `FR-EDIT-25` 那一句人话
# 「**每个命令都真的打开了对应面板（不是点了没反应）**」—— 静态判据
# （`Scripts/check-palette-wiring.py`：清单 id ↔ 分派器 case ↔ 标志位有没有视图读）判不住这件事，
# 所以它拿真 `AppState` 把**每一条命令都点一遍**、断言登记在案的**落点**确实发生
# （面板标志位 / 新页签 / 编辑器命令 / 状态栏说法 / 页签上的可读错误），
# 落点表与命令清单**双向对账**（新增命令没登记落点 ⇒ 判红）。
# 它不渲染界面、也不连库，跟着本脚本跑两遍（两遍都应当绿）。
#
# ## 第三批（队列 L-89 ㈡ ②，第 93 轮）：主题与字体
#
# `TestsUISnapshot/AppearanceFontProbeTests.swift` 判清单 §2 `FR-EDIT-26` 的三条人话：
# 手输一个已装的等宽族 ⇒ 生效且「当前使用」拼写正确（③）、手输非等宽 ⇒ **明确提示它不是等宽**
# 而不是静默回落（④）、SQL 预览的字形跟着字体走（⑤）。
# 造态走 `FontManager.beginHostPreference(_:)`（宿主语境覆盖，**不落盘**，与主题 / 语言同构）。
# ⑤ 是**像素**判据：面板用 `.defaultScrollAnchor(.bottom)` 渲染，于是字体那一段（默认在折线以下）
# 第一次进得了快照；判的是 SQL 预览那一行的**取样带**（`UISnapshot.band`）——
# 换族必须变、同族重跑必须逐像素相同、上方只多一句提示时必须不变。
#
# ## 第四批（队列 L-92 ㈡①，第 95 轮）：终端 `⌃C`
#
# `TestsUISnapshot/TerminalInterruptProbeTests.swift` 判的是「**非沙箱包（现在的默认与交付口径）
# 里 `⌃C` 能不能打断 `sleep 30`**」—— 清单 §0.3 第 3 条原先**要人点**，改默认非沙箱之后
# 变成机器判得住：往 PTY 喂一个 `0x03` 字节，看前台进程（`tcgetpgrp`）是否真的让开，
# 并要求它在 8 秒内发生（`⌃C` 没送到的话 `sleep` 会占满 30 秒 ⇒ 探针自己红）。
# 它用真 `TerminalPane` + 真 `forkpty` 会话；两遍都跑（沙箱标记只影响界面文案，不影响这条）。
# 边界：**没有**做「同一探针在沙箱里必红」的 A/B（见该文件头注释）。
#
# ## 第五批（队列 L-89 ㈡ ③，第 96 轮）：终端多会话页签那一行
#
# `TestsUISnapshot/TerminalTabsProbeTests.swift` 新加的三个用例判的是清单 §1 `FR-EDIT-29`
# 多会话那一行的**版面**与**落点**（前三个用例是它原有的「真开 shell 的独立性与退出 / 确认链路」）：
#   ① 版面：渲染**真工具条**（`LowerPaneTabStrip` —— 从 `LowerPaneView` 抽出来的独立视图，
#      抽出来就是为了能单独离屏渲染：整块面板一渲染会真开 shell），页签 1 个 → 3 个时
#      **左半必须变、右四分之一逐像素不变** —— 这就是「页签头在左侧、右侧按钮位置不动」的像素版；
#   ② 右侧那排按钮按**面板状态**齐备（终端 / 问题 / 折叠态三态：该有的有、**不该有的不许有**）；
#   ③ `⌘1…9` / `⌘⇧[ ⌘⇧]` / 双击改名落到**对的会话**，且**改名不动那条 PTY**（前台进程不许换人）。
# 它跟着本脚本跑两遍（沙箱标记只影响界面文案，不影响这三条）。
#
# ## 第六批（队列 L-89 ㈡ ④，第 97 轮）：大结果集滚动
#
# `TestsUISnapshot/LargeResultScrollProbeTests.swift` 判清单 §4 `FR-RES-07` 那一行
# 「查 1 万行 × 20 列，上下滚十几秒 ⇒ 不卡、内存不飙」里**能变成机器判据的那部分**：
# ① 虚拟化（物化行视图数只跟可见区域有关，1 万行与 10 万行必须同量级）；
# ② 滚动每一帧画面都在变（位置动了画面没动 = 卡死）且单帧 p50 在上界内；
# ③ 单帧成本不随总行数放大（比值判据，机器无关）；④ 重复同一轮操作常驻内存不再增长。
# 阈值全部读 `Scripts/result-scroll-baseline.json`（唯一来源，由
# `Scripts/check-result-scroll-ledger.py` 看着），文件里不写魔数。
# 它跟着本脚本跑两遍（沙箱标记只影响界面文案，不影响这四条）。
#
# ## 第七批（队列 L-89 ㈡ ⑤，第 99 轮）：跨库浏览
#
# `TestsUISnapshot/CrossDatabaseBrowseProbeTests.swift` 判清单 §5 `FR-META-10` 那一行
# 「展开非当前库的节点（对象树 / 服务器选择器）」→ 过 =「**按需建连**；失败时**给可读原因**」。
# 判据观测的是**服务端**：被测那条走真 `AppState`（与界面同一条路），另一条连接查
# `pg_stat_activity`，两条各打 `application_name` 标记 ⇒「本进程往哪个库开了几条后端」是
# 服务端的事实，不是我们自己的计数器。三条：① 只展开服务器节点 ⇒ 非当前库后端 **0**（不全量预连）；
# ② 展开非当前库的库 / schema 两级 ⇒ 该库后端恰好 **1** 条、子树里是**它自己的表**、重展开仍 1 条；
# ③ 展开不存在的库 ⇒ `ErrorPresenter.message(for:)`（对象树显示失败的唯一收口点）是人话 + 给方向，
# 而原始串确实是 `PSQLError(...)`（反向对照，防判据空转）。
# **这一批要真集群**（`Scripts/lib/test-env.sh` 的本机档；下面会起库、建两个带标记表的临时库），
# 并且**证据文件会被核对** —— 探针跳过 / 没挂上时文件不存在 ⇒ 本脚本判红（跳过 ≠ 通过）。
#
# ## 第八批（队列 L-89 ㈡ 第 6 条，第 101 轮）：分组视图
#
# `TestsUISnapshot/GroupedViewProbeTests.swift` 判清单里 `FR-META-15 分组视图` 那一行
# 「对象树顶部在「层级视图 / 按类型分组」之间切换」→ 过 =「**两种视图都能用**；**切换后选中项不丢**」。
# 三件事：① 可见行模型（`App/Views/ObjectTreeRows.swift`，本轮从视图里搬出来的纯函数）在两种模式下
# 各摊平一遍，输入是**真库读回来的对象** —— 层级面无表头、分组面表头齐、计数与真库对象数逐个相符、
# 非表头行两面逐条相同；② **真点一下**那台分段选择器（`UISnapshot.LiveHost` 里的
# `NSSegmentedControl`：同一进程内 `selectedSegment` + `sendAction` = 真点击，**不需要辅助功能授权**），
# 点完绑定真的翻（两档都到得了），且两档画出来**不是一个样子**、标签跟着界面语言走（中英各一遍）；
# ③ 选中项是**树里的同一个 id** ⇒ 两种行集合里都找得到那一行（「切换不丢选中」的模型侧）。
# 序列 / 函数 / 「其他」三个桶用**合成夹具**补（PG 的 schema 子节点只有表与视图两类）。
#
# **边界（口径已于第 106 轮改正）**：先试过「整棵 `ObjectTreeView` + 真库 + 真点击」那条更狠的路，
# 当时判成「做不到」（真对象树在离屏宿主里始终停在加载分支、工具条不在视图树里）。**第 106 轮（队列
# `L-96`）把根因定死了**：不是树渲染不了，是那批用的**泵循环**（`RunLoop.run`）让「从别的线程跳回主
# actor」的续体落不了地 —— 真库首连（`ensureService`）卡在那里 8 秒没有下一行；换
# `UISnapshot.LiveHost.pumpAsync`（`Task.sleep` 让出主 actor）之后，整棵树在活宿主里**正常加载出来**
# （第十二批就是这么判的）。所以本批这条边界现在只剩：**「在真树上点一下、切换后看选中高亮不丢」**
# 仍是人工点验（切换不丢选中已由模型侧 + 工具栏侧判住），**不再是「整棵树判不了」**。
# 本批同样要真集群（下面第八批那段建临时库并注入 `DOYAH_PROBE_PGGROUP` 等），
# 并且**证据文件会被核对**；源锚点另判三条：行模型是纯函数（不 import 驱动、不碰 `AppState`、不调 `loadMetadata*`）、视图里那台开关两档齐备、**以及视图那条调用点真的把这一台开关传给了模型**。最后这条是**注入实测逼出来的**：把 `groupByType: groupByType` 写死成 `false` 时，模型那一批与工具栏那一批**照样全绿**（探针只从两头取数、不经过那条调用点）—— 判据的覆盖面里当时缺着「模型与工具栏之间那根线」。
#
# ## 第九批（队列 L-89 ㈡ 第 7、8 条，第 102 轮）：笔记检索的两条「只能人工点」
#
# `TestsUISnapshot/NoteSearchProbeTests.swift` 判清单里那两行人话：
#   · **「存完立刻搜」**（搜一个词 → 清空搜索框 → 新建一条带这个词的笔记 → 保存 → 再搜那个词
#     ⇒ 过 = 刚存的那条在结果里）—— 判的是 `reloadNotes()` 末尾那次重算：
#     查询还在搜索框里时保存 ⇒ 新笔记必须**当场**在结果里；删掉 ⇒ 当场消失；清单原文那两个顺序也各判一遍。
#   · **「键盘快打」**（快速连续输入 ⇒ 过 = 结果不「倒回去」）—— 人手打字与查库谁快谁慢不可控，
#     所以判据落在**唯一落地出口**（`AppState.settleNoteSearch(_:for:)`）：
#     ① 一次**真实算出来的**旧词结果送到出口 ⇒ 不许落地（返回值 false + 状态一个字节不动），
#        失败那一档同理；当前词的结果必须落得下去（否则判据会被一句「永远丢掉」骗过去）；
#     ② **端到端**：一次带旧词的检索在途（`runSearch(_:for:)`），词换成新的之后它的结果才回来 ——
#        订阅 `$noteSearchState` 记下每一次落地与那一刻搜索框里的词，不变量 =「没有一次落地是在
#        词与结果对不上时发生的」（**只看最终状态判不出来**：切换后那次会落在它后面，终态一样）。
#     **窗口不靠 sleep 去撞**：`Task { … }` 的函数体在**当前任务下一次挂起**才开始跑，
#     而「把词换成新的」是同步的一句 ⇒ 那一次带旧词的检索**必定**在新词上屏之后才落地。
# 这批**不需要任何环境**（真库 = 每轮清空的临时 `DOYAH_NOTES_DIR`），两遍都该绿；
# 证据文件同样**会被核对**（跳过 ≠ 通过）。
#
# ## 第十批（队列 L-89 ㈡ 第 9 条，第 103 轮）：浏览器页签与下载
#
# `TestsUISnapshot/BrowserTabDownloadProbeTests.swift` 判清单 §10 `FR-EDIT-34` 那一行的三句人话：
#   ① 「新建页签 → 打开一个站点 → 关掉重开应用看是否恢复地址」；
#   ② 「看外发日志：按页签筛一次（下拉里应出现你刚浏览的那个页签）」；
#   ③ 「找一个下载链接点一下 → 提示条『已下载到 <路径>』、文件真的在那个目录里、
#      同名文件不会被覆盖（自动加 -1）」。
#
# **本批最要紧的结论：② 在真机上从来没生效过**（两处真缺陷，本批修掉）——
#   · `EgressLog.append` 的脱敏是**重建**一条记录，那次重建漏了 `tabID` / `tabTitle`
#     ⇒ 内存里有页签身份、**盘上没有**，而界面读的是盘上那份 ⇒ 页签下拉永远是空的、还灰着；
#   · `WebKitBrowserEngine.navigate(to:)`（地址栏 / 后退 / 前进 / 刷新都走它）记日志时漏了 `tabID`
#     ⇒ 只有「页面内点击」那条带着页签身份，两条路记出来的记录形状不一致。
#
# 判据从**盘上**读、从**界面控件**上读（真 `AppState` + 真页签库文件 + 真外发日志文件 +
# 真授权书签 + 真 `EgressLogSheet` / `BrowserTabView` 渲染）：
#   ① 重开之后地址回来了且**没被加载**（`isBrowserPagePristine`）+ 地址栏控件里的文本就是它；
#   ② 盘上两条记录都带页签身份、`EgressFilter(tabID:)` 只留那一个、页签那台下拉里恰好一个页签且**可点**；
#      反向对照 = 日志清空后同一台下拉是灰的（那条断言不是恒真的）；
#   ③ 文件真落在授权目录、同名再来一次得到 `-1` 且第一份一个字节没动、提示条就是
#      「已下载到 <路径>」、外发日志那条 `allowed` 也带页签身份、提示条在画面上（有/无逐字节不同）。
#
# **边界（如实登记）**：WebKit 的字节搬运那一步（`WKDownload` 的回调）**没有被驱动** ——
# 判的是引擎之后的每一环（落盘命名 / 覆盖规避 / 提示条 / 留痕），都喂真文件、真目录；
# 导航打在 `127.0.0.1:9`（discard 口），探针自己不产生真实出网。
# 本批要 `DOYAH_BROWSER_TABS_DIR`（临时页签库）与 `DOYAH_EGRESS_LOG_DIR`（临时外发日志），
# 证据文件同样**会被核对**（跳过 ≠ 通过）。
#
# ## 第十一批（队列 L-89 ㈡ 第 10 条，第 105 轮）：MySQL 表单联动
#
# `TestsUISnapshot/MySQLFormProbeTests.swift` 判清单 §10.7 `FR-DRV-09` 界面那一行
# （「新建连接 → 数据库类型选 MySQL → 端口应自动变成 3306、SSL 默认 prefer；连上后看对象树」）：
#   · **A 组（界面联动）** —— **本机 SwiftUI 的 `Picker` 不落到 AppKit 控件**（第 105 轮实测：
#     宿主视图树里没有 `NSPopUpButton`）⇒「点一下那台下拉」走不通，照 `EgressLogSheet` 当年的处置
#     把联动搬成能直接断言的东西（`ConnectionDialectLinkage`，界面与判据读同一份）+ 一个把**产品那两个
#     视图**接起来的夹具：改夹具里的 `dbType` 就等于在界面里换方言，断言读 ① 绑定侧 ② **界面上那一格
#     真 `NSTextField` 的正文** ③ 真 `ConnectionFormView` 按各方言配置渲染时那一格的正文。
#     三个方言各来一遍（PostgreSQL ⇄ MySQL ⇄ GBase 8a），**来回都判**（联动不是单向的）。
#   · **B 组（对象树 + 数据）** —— 连 `Scripts/mysql-stub/fake_mysql_server.py`
#     （**真跑 MySQL 线协议**，本机没有 mysql / mariadb 二进制），走产品自己的
#     `DatabaseServiceFactory` + `MetadataService` 逐层展开 ⇒ 四层（服务器 → Database →
#     Table → Column）、**没有 schema 节点**、列下面没有第 5 层；再走产品自己的查询入口取一次结果集。
#
# **不声称覆盖**：真实例上的认证 / 类型 / 多版本窗口（归 `Scripts/test-mysql-real.sh`，217）。
# 本批由脚本起假服务器并把地址经 `DOYAH_PROBE_MYSQL_*` 注入，证据文件同样**会被核对**（跳过 ≠ 通过）。
#
# ## 第十二批（队列 L-96，第 106 轮）：同一次刷新被连唤两次 / `reloadRoot` 重入
#
# `TestsUISnapshot/ObjectTreeRefreshProbeTests.swift` 判两件事（真库 + 真渲染 + 真 `ObjectTreeView`）：
#   ① **整棵树在活宿主里真加载出来**：数据分支在场（那台「层级 / 分组」开关**只在「已加载」那一支里**
#      画得出来）、加载分支退场（「正在加载对象…」不许还在画面上）、画面里真有那棵树
#      （与「同一条连接指向一个不存在的库」那个失败态对照宿主比，视图树节点数必须多出来）。
#      **这一格原来是「做不到」**（第 101 轮如实登记）——第 106 轮定位到根上：不是树渲染不了，
#      是当时的泵循环用 `RunLoop.run`，期间「从别的线程跳回主 actor」的续体落不了地，
#      真库**首连**就卡在那里不返回；换 `UISnapshot.LiveHost.pumpAsync`（`Task.sleep` 让出主 actor）
#      之后树**正常加载出来**（那条入口的注释里也记着这条）。
#   ② **同一把刷新键下的重入**：让子树在**上一发还在途**时消失再出现（同一连接、同一元数据版本 ⇒
#      刷新键一字不变）⇒ ① 的结论照样成立（树不许留在加载态、不许掉成空树），且闸门收尾之后
#      `inFlightCount == 0`（没有把键漏在在途表里）。
#   **边界（如实登记）**：行内文字**读不出来**（SwiftUI 的行 `Text` 不落在 `NSTextField` /
#      `NSTextView` / `NSButton` 上 —— 实测这台宿主里只读得到分段选择器的两档标签）⇒ 判到
#      「树进了已加载那一支、画面里真有东西」，**判不到**「某个表名在第几行」（要判名字得走 AX 或像素）。
#   本批用第八批那个真库（`DOYAH_PROBE_PGGROUP`），证据文件同样**会被核对**（跳过 ≠ 通过）；
#   闸门的接线另判源锚点（见下面「刷新重入那两条」那一段）。
#
# ## 第十三批（队列 L-90 ㈡ 第 2 条，第 110 轮）：对象树逐行右键
#
# `TestsUISnapshot/ObjectTreeContextMenuProbeTests.swift` 判清单 §4 `FR-META-14` 那一行：
#   ① **七类节点各渲一遍**（服务器 / 数据库 / schema / 表 / 视图 / 函数 / 列，各落一张图）——
#      菜单里的**动作项**与 Core 的 `ObjectTreeActions.isAvailable` **双向**对账（少一项 / 多一项都判红），
#      且**服务器那七项不许漏到别的行上**（「点数据库弹服务器菜单」那条老缺陷的回归钉）。
#   ② **作用在哪一行**：悬停优先（哪怕选中的是另一行）/ 悬停没命中时兜底「刚点中的那一行」/
#      两样都没有 ⇒ 一句说明（不是空菜单）/ 分组表头与「没有菜单的节点」拿到 nil。
#   ③ **同一行两次渲染逐字节一致、不同行必须不同**（免得菜单其实是个跟行无关的常量）。
#   探针按「内容 + 目标行」两件事判，**不吃鼠标事件、不要任何权限**；菜单内容与作用行解析
#   本轮搬进 `App/Views/ObjectTreeContextMenu.swift`（静态 `@ViewBuilder` 入口 + 一个纯函数），
#   生产路径与判据读的是同一个入口 —— 差别只有外面那层壳（`.contextMenu` 要兄弟节点、图要容器）。
#   **边界（如实登记）**：判得到「这一行该有哪些项、作用在哪一行」，**判不到**「AppKit 把这份内容
#   展成菜单项并在右键位置弹出」（那需要真点一次右键；归人工点验）。
#   **同轮读图抓到的真问题**：先头那版图上七类菜单**叠成一行**（文案集合照样齐、三条用例照样绿）
#   ⇒ 菜单内容改成静态唯一入口、容器由判据那侧加（这条教训立进 `AGENT-SPEC.md` §9 第 85 条）。
#   证据文件同样**会被核对**（跳过 ≠ 通过）。
#
# ## 第十四批（队列 L-89 ㈢ ①，第 112 轮）：空编辑器上「保存」灰否（渲染级）
#
# `TestsUISnapshot/NotesEditorSaveProbeTests.swift` 判清单那一行原先要人点三下的三态
# （**空着灰 / 有内容亮 / 删回灰**）。模型那一半（`AppState.noteEditorHasContent` 三态）与源码
# 那一半（`check-empty-action-buttons.py`）都已经在判，但两层合起来判不到「**渲染出来的那只按钮
# 真的跟着变**」⇒ 本条在**像素**上补这一层：三态各渲染一遍真视图，
# ① 空 ⇒ 按钮那一带只有灰墨水（最暗亮度 ≥ 80，实测 91）；
# ② 有字 ⇒ 同一带出现深墨水（≤ 60，实测 34）且按钮带变了 ≥ 2000 像素（实测 5028）；
# ③ 删回空 ⇒ 与空态**逐字节相同**（差异 0 像素）。
# **边界（如实登记）**：实测这块 SwiftUI `Button` 在离屏宿主里**不落到 `NSButton`**、
# 无障碍树在离屏时不构建 ⇒ 读不到 `isEnabled`，只能判像素；按钮落点/门槛按本机实测定。
# 它不连库、也只渲染面板 ⇒ 跟着本脚本跑两遍（两遍都应当绿）。
#
# ## 第十五批（队列 L-111，第 121 轮）：数据库侧 SQL 编辑器的行号列
#
# `TestsUISnapshot/SQLLineNumberProbeTests.swift` 判的是「**SQL 编辑器的行号列**」这件事
# 里**只有把真视图跑起来才知道**的那几半（口径在 `Core/CodeLines`，另有 15 项单测）：
# ① 列真的**落到排版上** —— 正文起点（`textContainerInset.width`）等于列宽，不是只算了个数；
# ② 列真的**画到像素上** —— 列区里有墨（「算了但不画」正是要挡的假绿），
#    且行数 9 → 151 时同一块列区画出来的东西**变了**（1 位 vs 3 位数字）；
# ③ **两个编辑器同一个件** —— 同样行数下工作区编辑器与 SQL 编辑器的列宽、正文起点逐个相等
#    （「不许新造第二套行号逻辑」的回归钉；各画一套这里就对不上）。
# 图片**语言无关**（画面里只有 SQL 文本与数字行号）⇒ 不按语言各出一张。
# 它不连库、也不改任何偏好 ⇒ 跟着本脚本跑两遍（两遍都应当绿）。
#
# ## 纪律
#
# · 与快照同源：要真渲染视图树、要几分钟 ⇒ **不进** `verify-all.sh`（每轮门禁不跑取证）；
# · 产物落 `.build/`（已在 `.gitignore`）：快照是**证据**，不是交付物；
# · 只读用户数据：笔记 / 外发日志指到每轮清空的临时目录（与 `make-ui-snapshots.sh` 同款），
#   探针不写用户偏好、不连任何数据库。
#
# 退出码：0 = 两遍都绿且跨清单判定成立；非 0 = 某一遍红或跨清单判定不成立。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"
OUT_BASE="${SCRATCH}/manual-verification-probes"
OUT_PLAIN="${OUT_BASE}/plain"
OUT_SANDBOX="${OUT_BASE}/sandbox"
SANDBOX_MARK="com.doyah.manual-verification-probe"

# 默认两族都跑：`ManualVerificationProbeTests`（B 类 ㈠：隧道表单 / SSL 收窄 / 沙箱告知）
# + `PaletteWiringProbeTests`（㈡：命令面板接线）
# + `AppearanceFontProbeTests`（㈡：主题与字体 —— 手输族之后界面说的话 + SQL 预览的字形）。
# + `TerminalInterruptProbeTests`（L-92 ㈡①：终端 `⌃C` 打断前台 `sleep 30` —— 非沙箱包的作业控制）。
# + `BrowserTabDownloadProbeTests`（㈡ ⑨：浏览器页签与下载）。
# + `MySQLFormProbeTests`（㈡ ⑩：MySQL 表单联动 —— 换方言当场换端口与 SSL 清单（真点那台下拉）
#   ＋ 对象树四层（服务器 → Database → Table → Column，没有 schema 层）＋ 能查到数据）。
# + `TerminalInteractionProbeTests`（L-90 ㈠：终端交互三面 —— 鼠标上报 / DECCKM / 右键归属。
#   本批的**主入口**是 `Scripts/verify-ui-interactions.sh`（那份只跑一遍、判据与进程环境无关）；
# + `MultiCursorProbeTests`（L-90 ㈡ 第 1 条：`FR-EDIT-27` 多光标与列编辑 —— ⌥⌘D 选下一处 /
#   ⌥⌘↑↓ 加光标 / ⌥ 拖拽列选，各判「打字与 ⌫ 逐个生效」「一次撤销全回退」「位置不漂」。
#   本批的**主入口**同样是 `Scripts/verify-ui-interactions.sh`）
# + `ObjectTreeContextMenuProbeTests`（L-90 ㈡ 第 2 条：`FR-META-14` 对象树逐行右键 ——
#   七类节点各自的菜单内容（动作项与 Core 的规则双向对账）/ 菜单作用在哪一行（悬停优先、
#   盒子空退回选中项）/ 同一行两次逐字节一致、不同行必须画成两个样子。
#   本批的**主入口**同样是 `Scripts/verify-ui-interactions.sh`）
# + `NotesEditorSaveProbeTests`（L-89 ㈢ ①：空编辑器上「保存」灰否 —— 三态渲染 + 像素判据，
#   见下面「第十四批」）。
#   这里同时挂上是为了那条「每个 `*ProbeTests.swift` 都得有入口」的判据
#   `check-result-scroll-ledger.py` ⑤ —— 一处入口漏了就等于一个都跑不到（第 96 轮实测）。
# + `SQLLineNumberProbeTests`（L-111：数据库侧 SQL 编辑器的行号列 —— 正文起点 = 列宽 /
#   列区里有墨 / 行数 9 → 151 时列宽与像素都变 / 两个编辑器的列宽逐个相等，见「第十五批」）。
# + `TodoCalendarEntriesProbeTests`（`TD-CAL-1` 片 · 派单 `T-20261009-026`：待办日历「选中日」那两枚入口 ——
#   ① 选中日直接新建（截止预填该日 09:00，另有对照件证明既有的「新建」不带截止）；② 选中日 →「写笔记」。
#   它落地当轮**漏了接 FILTER**（用例一个都跑不到），由 `check-result-scroll-ledger.py` ⑤ 抓出后补上
#   —— 与 `FormatMenuWiringProbeTests` 当年那一处同一个坏法）。
# + `TodoDetailSearchProbeTests`（`TD-LIST-1` 片 · 派单 `T-20261009-026`：待办清单那两件 ——
#   ① 点一行 ⇒ **右栏只读详情**（渲染右栏两遍：那一条的标题 / 截止 / 优先级 / 标签都在，
#   **编辑器那几句一句都不许出现**；另加反向对照：显式「编辑」之后同一个件必须画得出那几句，
#   否则「没有」可能只是「读不到」）；② `TodoQueryBar` 的**本地关键字检索** ⇒ 清单只剩按标题命中的行
#   （敲一个只配得上一条的子串；反向对照 = 那个词只存在于另一条的**标签**里 ⇒ 一条都不留）。
#   主入口是 `Scripts/run-manual-verification-probes.sh`（它自己会带 `DOYAH_NOTES_DIR`）；
#   挂在这里也是为了那条「每个 `*ProbeTests.swift` 都得有入口」的判据 `check-result-scroll-ledger.py` ⑤）。
# + `PerfTypingProbeTests`（`L-148`：查询页签每键耗时的机器判据 —— 5,000 行 / 739,219 字符，
#   断言**每键 p50 < 5 ms**（实测 33.6 → 1.8 ms，改前 31.74 ms）。`verify-all.sh` 那十八项
#   判的是静态与行为，**判不到运行时开销** —— 这是「每键写全局 @Published」那类错唯一的拦网，
#   见「第十六批」与 §9 第 104 条：探针不挂进 FILTER = 这一族一个都跑不到）。
# + `WorkspaceChromeHeightProbeTests`（`L-144`／内测清单**乙5**：工作区页签条那一行的高度不变量 ——
#   4 种页签组合（含 **2 个空白浏览器页签**原场景）× 5 个宽度量出来的高度**全部相等**（实测 30.0pt），
#   另加两条**对照负例**（会随宽度换行的长文案 / 高理想高度的空态样块）证明这套量法真的判得动）。
#   本批的**主入口其实是 `./Scripts/verify-all.sh` 第 1 项**（它用离屏宿主 `sizeThatFits`、
#   **不渲染位图、不需要窗口与人在场** ⇒ 每轮门禁都跑）；挂在这里是为了那条
#   「每个 `*ProbeTests.swift` 都得有入口」的判据 `check-result-scroll-ledger.py` ⑤ ——
#   一处入口漏了就等于一个都跑不到（第 96 轮实测，第 133 轮又被这条判据逮到一次）。
# + `MarkdownPreviewProbeTests`（`L-137` 第三片：工作区 Markdown 预览的**界面面** ——
#   ① 预览里没有可编辑文本视图（只读），且同一套遍历**能**看见真插进去的可编辑 `NSTextView`
#   （对照：证明"零命中"不是"看不见"）；② 光标行 → 顶层块下标与契约层锚点同解；
#   ③ 截断计数只在真截断时给、逐字段相等；④ 块多则高（证明真画了，不是空底）。
#   主入口同样是 `verify-all.sh` 第 1 项（离屏 `NSHostingController`，不渲染位图、不需要人在场）。
# + `TitleBarSearchProbeTests`（`L-141`／内测清单**甲1**：标题栏搜索栏在**非全屏**窗口下不收敛、
#   遮住窗口标题 —— 量「真视图在每一档窗口宽度下占多宽」：每档与策略 `TitleBarSearchLayout` 同值、
#   窗口变窄只减不增、窄到放不下那一档**整条不显示**（量出来 0），另加**对照**：旧口径
#   （写死 320）在同一套量法下窄窗口必判越界（判据真的能判红）。主入口同样是 `verify-all.sh`
#   第 1 项（离屏 `NSHostingController`，不渲染位图、不需要窗口与人在场）。
# + `WorkspaceFileRoutingProbeTests`（`L-149` 剩余②：工作区打开文件的路由 —— `.html` / `.htm`
#   交给**浏览器页签**那一侧、`.md` / `.sql` 照旧进编辑器（对照）、没接线时回落文本编辑器、
#   同一个文件点两次只开一个页签；不渲染位图 ⇒ 主入口同样是 `verify-all.sh` 第 1 项）。
# + `TitleBarSearchClickProbeTests`（`T-20261002-027`／开发循环第 162 轮：标题栏搜索栏的**点击地图** ——
#   可见框内采样点逐点断言命中目标 = 输入框或其接力层、留白点按下把键盘交给同一框里的输入框、
#   清空按钮那一段留给 SwiftUI，另加**修前对照**（装修层参与命中测试的那份框必须判红）。
#   主入口其实是 `./Scripts/verify-ui-interactions.sh`（真窗口 + 工具条、进程内合成事件、零权限）；
#   挂在这里是为了那条「每个 `*ProbeTests.swift` 都得有入口」的判据 `check-result-scroll-ledger.py` ⑤。
# + `FormatMenuWiringProbeTests`（内测 `#2` 第二轮 · 开发循环第 164 轮：格式化入口**真的能跑到页签上** ——
#   ① `.json` 路径判成 `TextLanguage.json`（判成 fallback 只会得到一句拒绝）；② 乱掉的 JSON 走
#   `formatSelected()` 必须真的投递重排后的文本；③ 主菜单「编辑」那一项必须带可执行 action/target 并真调用一次。
#   **它落地当轮漏了接 FILTER**（写下用例却没入口 = 一个都跑不到），由 `check-result-scroll-ledger.py` ⑤ 抓出后补上。
# + `TerminalSubToolbarProbeTests`（`T-2` 片 · 人类主人 2026-10-08 原话「右侧是常用的工具按钮」：
#   终端二级工具条右侧那四枚的**行为**与**版面** —— ① 一键启动 `dsh-tui` / `hermes` 真的建了页签、
#   页签名 = 预设名、会话起来后**前台进程换人**且屏幕有回显（前门补判据 `T-20261008-026` 要的
#   「确实起了一个 dsh 终端（有回显 / 有进程读数）」）；② 清除会话窗口内容之后**缓冲行数归零**
#   而 pid 不变、会话仍在跑（只擦屏幕）；③ 重启终端**先弹确认**（pid 一个字节没动）→ 确认后
#   **pid 换人**、页签留着；④ 渲染真二级条：页签 1 → 3 时**左半必须变、右四分之一逐像素不变**
#   （右侧那四枚不被页签挤动）+ 左 / 右各切一张图存盘。
#   它**真开 shell**（取证专用，`XCTSkip` 到 `DOYAH_UI_SNAPSHOT=1`），跟着本脚本跑两遍。
# + `QueryHistoryPaneProbeTests`（片 `HIST-2` · 派单 `T-20261009-018` / `T-20261009-010` ·
#   人类主人 2026-10-08 令：下方面板外层页签条新增「历史」，**只在 Database 客户端段出现**，
#   与工具条时钟菜单**同一份**历史源，并给「清空」/「单条删除」两处**二次确认**）：
#   ① 段条件（`FR-EDIT-10`）：Database 段页签可见（渲染出的文案里有「历史」）→ 切工作区段
#   **不可见**且正选中历史时**自动落到终端** → 切回**恢复历史**（三态成对读数 + 选中项 dump）；
#   ② 同源：源码锚点（页面与菜单都读 `appState.queryHistory`）+ **读盘点唯一**
#   （`App/` 里提到落盘门面 `QueryHistoryStore` 的文件只许 `AppState.swift`）；
#   ③ 二次确认（`DR-02`）：点清空/删除 ⇒ **只挂请求**（内存与库都不变）→ 取消不变 →
#   确认才落库（清空 ⇒ 0 / 单条 ⇒ 减 1），读数同时给内存镜像与**库里真值**。
#   ⚠️ ③ 要写临时笔记库（历史与笔记**同库**）⇒ 走 `DOYAH_NOTES_DIR`，没设就 `XCTSkip`。
# `--filter` 传的是**正则**，所以这里用 `|` 连接。
# + `TodoCalendarEntriesProbeTests`（`TD-CAL-1` · 派单 `T-20261009-026`：日历「选中日」那两枚入口 ——
#   新建待办的截止预填该日 09:00 / 「写笔记」新开一篇；正反两面由**渲染记录**判）+ `LunarSubtitleProbeTests`
#   （`TD-CAL-2` 同派单：月视图格的**副条** —— 每格农历日 + 交节那天那一格的节气）。
#   两枚都是「写下用例却没接进 `--filter` = 一个都跑不到」，由 `check-result-scroll-ledger.py` ⑤ 抓出后补上。
# `--filter` 传的是**正则**，所以这里用 `|` 连接。
FILTER="ManualVerificationProbeTests|PaletteWiringProbeTests|AppearanceFontProbeTests|TerminalInterruptProbeTests|TerminalTabsProbeTests|TerminalSubToolbarProbeTests|LargeResultScrollProbeTests|CrossDatabaseBrowseProbeTests|GroupedViewProbeTests|NoteSearchProbeTests|BrowserTabDownloadProbeTests|MySQLFormProbeTests|ObjectTreeRefreshProbeTests|TerminalInteractionProbeTests|MultiCursorProbeTests|ObjectTreeContextMenuProbeTests|NotesEditorSaveProbeTests|SQLLineNumberProbeTests|PerfTypingProbeTests|WorkspaceChromeHeightProbeTests|MarkdownPreviewProbeTests|TitleBarSearchProbeTests|WorkspaceFileRoutingProbeTests|NebulaSkinProbeTests|TitleBarSearchClickProbeTests|FormatMenuWiringProbeTests|NotesLayoutProbeTests|QueryHistoryPaneProbeTests|TodoCalendarEntriesProbeTests|TodoDetailSearchProbeTests|LunarSubtitleProbeTests"
while [ $# -gt 0 ]; do
    case "$1" in
        --filter) FILTER="${2:-}"; shift 2 ;;
        *) echo "未知参数：$1（支持 --filter <片段>）"; exit 2 ;;
    esac
done

export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="${SCRATCH}/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="${SCRATCH}/swift-module-cache"
export DOYAH_UI_SNAPSHOT=1

# 与用户真实数据解耦：笔记 / 统一外发日志指到每轮清空的临时目录。
PROBE_DATA="${SCRATCH}/manual-verification-probe-data"
rm -rf "${PROBE_DATA}"
mkdir -p "${PROBE_DATA}/notes" "${PROBE_DATA}/egress" "${PROBE_DATA}/browser-tabs"
export DOYAH_NOTES_DIR="${PROBE_DATA}/notes"
export DOYAH_EGRESS_LOG_DIR="${PROBE_DATA}/egress"
# 浏览器页签库（第十批）：`AppState` 用的是 `BrowserTabStore.shared`（没有注入口），
# 所以恢复 / 落盘这类行为只能靠这个变量指到临时目录 —— 否则探针会往真实数据家写页签。
export DOYAH_BROWSER_TABS_DIR="${PROBE_DATA}/browser-tabs"

mkdir -p "${CACHE}" "${SCRATCH}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}"
cd "${ROOT}"

# ---- 跨库浏览那一批要的**真库**（第七批）------------------------------------
#
# 判据观测的是**服务端**（`pg_stat_activity`），所以要有真集群。连接信息不在这里手抄 ——
# 走 `Scripts/lib/test-env.sh`（真库目标的唯一来源）：本机档会起集群，库名带 `doyah_probe_` 前缀，
# 两个临时库各建一张**独有**的标记表 ——「跨库展开列出来的是不是它自己的表」才判得动。
source "${ROOT}/Scripts/lib/test-env.sh"
doyah_test_env_start_cluster
echo
echo "==> 跨库浏览判据的真库目标"
doyah_test_env_summary

PROBE_PG_CURRENT="$(doyah_test_env_scratch_name crossdb_main)"
PROBE_PG_OTHER="$(doyah_test_env_scratch_name crossdb_side)"
PROBE_PG_MISSING="$(doyah_test_env_scratch_name crossdb_missing)"
PROBE_MARKER_CURRENT="crossdb_marker_main"
PROBE_MARKER_OTHER="crossdb_marker_side"

probe_psql() {  # $1 = 库；$2 = SQL（只跑一条；出错即停）
    "${DOYAH_TEST_PG_BIN}/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" \
        -U "${DOYAH_TEST_PGUSER}" -d "$1" -q -v ON_ERROR_STOP=1 -c "$2" >/dev/null
}

# 建两个临时库（DROP + CREATE，幂等）+ 各自的标记表；第三个库**故意不建**（判失败态用）。
doyah_test_env_scratch_db crossdb_main >/dev/null
probe_psql "${PROBE_PG_CURRENT}" "CREATE TABLE ${PROBE_MARKER_CURRENT}(id int);"
doyah_test_env_scratch_db crossdb_side >/dev/null
probe_psql "${PROBE_PG_OTHER}" "CREATE TABLE ${PROBE_MARKER_OTHER}(id int);"
"${DOYAH_TEST_PG_BIN}/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" \
    -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" -q \
    -c "DROP DATABASE IF EXISTS \"${PROBE_PG_MISSING}\" WITH (FORCE);" >/dev/null 2>&1

export DOYAH_PROBE_PGHOST="${DOYAH_TEST_PGHOST}"
export DOYAH_PROBE_PGPORT="${DOYAH_TEST_PGPORT}"
export DOYAH_PROBE_PGUSER="${DOYAH_TEST_PGUSER}"
export DOYAH_PROBE_PGCURRENT="${PROBE_PG_CURRENT}"
export DOYAH_PROBE_PGOTHER="${PROBE_PG_OTHER}"
export DOYAH_PROBE_PGMISSING="${PROBE_PG_MISSING}"
export DOYAH_PROBE_PGMARKER_CURRENT="${PROBE_MARKER_CURRENT}"
export DOYAH_PROBE_PGMARKER_OTHER="${PROBE_MARKER_OTHER}"
echo "  · 跨库探针：当前库 ${PROBE_PG_CURRENT}（有 ${PROBE_MARKER_CURRENT}）"
echo "              非当前库 ${PROBE_PG_OTHER}（有 ${PROBE_MARKER_OTHER}）｜不存在的库 ${PROBE_PG_MISSING}"

# ---- 分组视图那一批要的**真库**（第八批）--------------------------------------
#
# 判据要「用真库读回来的对象喂可见行模型」，并且要判「表头上的条数与真库对象数逐个相符」——
# 所以临时库里得有两种类型（表 / 视图）的对象，各带一个**独有**标记名（名字只有一处来源：
# 这里建、经环境变量给探针；探针不手抄表名）。
PROBE_PG_GROUP="$(doyah_test_env_scratch_name group_view)"
PROBE_GROUP_TABLE_A="gv_marker_table_a"
PROBE_GROUP_TABLE_B="gv_marker_table_b"
PROBE_GROUP_VIEW="gv_marker_view"

doyah_test_env_scratch_db group_view >/dev/null
probe_psql "${PROBE_PG_GROUP}" "CREATE TABLE ${PROBE_GROUP_TABLE_A}(id int);"
probe_psql "${PROBE_PG_GROUP}" "CREATE TABLE ${PROBE_GROUP_TABLE_B}(id int);"
probe_psql "${PROBE_PG_GROUP}" "CREATE VIEW ${PROBE_GROUP_VIEW} AS SELECT id FROM ${PROBE_GROUP_TABLE_A};"

export DOYAH_PROBE_PGGROUP="${PROBE_PG_GROUP}"
export DOYAH_PROBE_PGTABLE_A="${PROBE_GROUP_TABLE_A}"
export DOYAH_PROBE_PGTABLE_B="${PROBE_GROUP_TABLE_B}"
export DOYAH_PROBE_PGVIEW="${PROBE_GROUP_VIEW}"
echo "  · 分组视图探针：库 ${PROBE_PG_GROUP}（表 ${PROBE_GROUP_TABLE_A} / ${PROBE_GROUP_TABLE_B} + 视图 ${PROBE_GROUP_VIEW}）"

# ---- MySQL 表单联动那一批要的服务端（第十一批）----------------------------------
#
# 本机**没有** mysql / mariadb 二进制（清单 §10.7 与「卡环境」那一段都记着），所以这里起
# `Scripts/mysql-stub/fake_mysql_server.py`（**真跑 MySQL 线协议**）。判的是「我们这一侧
# 把四层树搭对没有、能不能查到数据」——**不声称覆盖真实例**（那归 `Scripts/test-mysql-real.sh`）。
MYSQL_STUB_PORT=33097
MYSQL_STUB_LOG="${SCRATCH}/fake-mysql-probe-$$.log"
rm -f "${MYSQL_STUB_LOG}"
python3 "${ROOT}/Scripts/mysql-stub/fake_mysql_server.py" --port "${MYSQL_STUB_PORT}" --log "${MYSQL_STUB_LOG}" &
MYSQL_STUB_PID=$!
# 两遍跑完（或中途红）都要把这个进程收掉，否则端口留着、下一轮起不来。
mysql_stub_stop() { kill "${MYSQL_STUB_PID}" 2>/dev/null; wait 2>/dev/null; }
trap mysql_stub_stop EXIT
for _ in $(seq 1 30); do
    grep -q "listening" "${MYSQL_STUB_LOG}" 2>/dev/null && break
    sleep 0.2
done
if grep -q "listening" "${MYSQL_STUB_LOG}" 2>/dev/null; then
    echo "==> 假 MySQL 服务器已在 127.0.0.1:${MYSQL_STUB_PORT} 上监听（第十一批）"
else
    echo "✗ 假 MySQL 服务器没起来（日志 ${MYSQL_STUB_LOG}）"
    exit 1
fi
export DOYAH_PROBE_MYSQL_HOST="127.0.0.1"
export DOYAH_PROBE_MYSQL_PORT="${MYSQL_STUB_PORT}"
export DOYAH_PROBE_MYSQL_USER="root"
export DOYAH_PROBE_MYSQL_PASSWORD="secret"
export DOYAH_PROBE_MYSQL_DATABASE="testdb"

run_pass() {  # $1 = 输出目录；$2 = 该遍要设的 APP_SANDBOX_CONTAINER_ID（空 = 不设）
    local out="$1" mark="$2" label="$3"
    rm -rf "${out}"
    mkdir -p "${out}"
    echo
    echo "==> ${label}（快照目录 ${out}）"
    if [ -n "${mark}" ]; then
        APP_SANDBOX_CONTAINER_ID="${mark}" DOYAH_SNAPSHOT_DIR="${out}" "${SWIFT}" test \
            --disable-sandbox \
            --package-path . \
            --cache-path "${CACHE}" \
            --scratch-path "${SCRATCH}" \
            --manifest-cache local \
            -Xswiftc -disable-sandbox \
            --filter "${FILTER}"
    else
        DOYAH_SNAPSHOT_DIR="${out}" "${SWIFT}" test \
            --disable-sandbox \
            --package-path . \
            --cache-path "${CACHE}" \
            --scratch-path "${SCRATCH}" \
            --manifest-cache local \
            -Xswiftc -disable-sandbox \
            --filter "${FILTER}"
    fi
}

run_pass "${OUT_PLAIN}" "" "第一遍：普通构建（不设沙箱标记）"
run_pass "${OUT_SANDBOX}" "${SANDBOX_MARK}" "第二遍：带沙箱标记 APP_SANDBOX_CONTAINER_ID=${SANDBOX_MARK}"

echo
echo "==> 跨清单判定：环境（沙箱标记）确实改变了界面"
python3 - "${OUT_PLAIN}/manifest.json" "${OUT_SANDBOX}/manifest.json" <<'PY'
import json
import sys

plain_path, sandbox_path = sys.argv[1], sys.argv[2]


def load(path):
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    return {item["name"]: set(item["localizedStrings"]) for item in payload["snapshots"]}


plain, sandbox = load(plain_path), load(sandbox_path)

if set(plain) != set(sandbox):
    print(f"✗ 两遍产出的快照集合不同：{sorted(set(plain) ^ set(sandbox))}")
    sys.exit(1)

# 这一组图判的是「沙箱构建多一句说明」：逐张比，沙箱那遍必须**恰好多一句**，
# 且那一句里必须点出 ssh 与沙箱（否则只是"多了一行别的字"）。
target = "manual-check-ssh-sandbox-notice"
if f"{target}-zh" not in sandbox:
    print(f"✗ 清单里没有 {target}-zh —— 探针没跑（检查 --filter / DOYAH_UI_SNAPSHOT）")
    sys.exit(1)

failures = []
for suffix in ("-zh", "-en"):
    name = f"{target}{suffix}"
    extra = sandbox[name] - plain[name]
    missing = plain[name] - sandbox[name]
    if len(extra) != 1:
        failures.append(f"{name}：沙箱那遍应当**恰好多 1 句**，实际多 {len(extra)} 句 {sorted(extra)}")
        continue
    only = next(iter(extra))
    if "ssh" not in only:
        failures.append(f"{name}：多出来的那句没有点明 ssh：「{only}」")
    if missing:
        failures.append(f"{name}：普通那遍多出了 {sorted(missing)}（说明判据方向反了）")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)

print("✓ 两遍产出成对；沙箱那一遍逐语言恰好多一句 ssh 沙箱说明；普通那一遍没有它")
print(f"✓ 本轮产出的快照：{len(sandbox)} 张（两遍各一份）")
PY

echo
echo "==> 跨库浏览那条：两遍都**真跑过**了吗（跳过 ≠ 通过）"
python3 - "${OUT_PLAIN}" "${OUT_SANDBOX}" <<'PY'
import json
import os
import sys

CASES = {
    "serverNodeListing": [
        ("currentBackends", 1),
        ("otherBackends", 0),
    ],
    "crossDatabaseOnDemand": [
        ("otherBackendsAfterListingDatabase", 1),
        ("otherBackendsAfterSchema", 1),
        ("otherBackendsAfterRepeat", 1),
        ("otherTableMarkerSeen", True),
        ("currentMarkerLeakedIntoOther", False),
    ],
    "missingDatabaseReadable": [
        ("rawIsDriverDump", True),
    ],
}


def load(directory, case):
    path = os.path.join(directory, f"cross-database-evidence-{case}.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


failures = []
for directory in sys.argv[1:]:
    for case, expectations in CASES.items():
        payload = load(directory, case)
        if payload is None:
            failures.append(
                f"{os.path.basename(directory)}：没有 {case} 的证据文件 —— 探针没真跑（跳过不算通过）"
            )
            continue
        for key, expected in expectations:
            actual = payload.get(key)
            if actual != expected:
                failures.append(f"{os.path.basename(directory)}/{case}：{key} 期望 {expected}、实测 {actual}")
        if "databasesWithBackends" in payload and payload["databasesWithBackends"] != [payload["currentDatabase"]]:
            failures.append(
                f"{os.path.basename(directory)}/{case}：展开服务器节点后连过的库不止当前库："
                f"{payload['databasesWithBackends']}"
            )
        shown = payload.get("shownMessage")
        if shown is not None and ("PSQLError(" in shown or "serverInfo:" in shown):
            failures.append(f"{os.path.basename(directory)}/{case}：界面那句话里出现了驱动转储：{shown!r}")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 两遍都真跑过：非当前库按需恰好 1 条 / 展开前 0 条 / 子树来自那个库 / 失败给可读原因")
PY

echo
echo "==> 分组视图那条：两遍都**真跑过**了吗（跳过 ≠ 通过）"
python3 - "${OUT_PLAIN}" "${OUT_SANDBOX}" <<'PY'
import json
import os
import sys

# 期望值只写「不变量」：与标记数/证据自洽的那些关系，而不是把探针里的数字再抄一遍
# （抄一遍 = 两个真值来源，改一处漏一处）。
def load(directory, case):
    path = os.path.join(directory, f"grouped-view-evidence-{case}.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


failures = []
for directory in sys.argv[1:]:
    base = os.path.basename(directory)

    real = load(directory, "realObjects")
    if real is None:
        failures.append(f"{base}：没有 realObjects 的证据文件 —— 探针没真跑（跳过不算通过）")
    else:
        if real.get("hierarchyDepths") != [0, 1, 2, 3, 3, 3]:
            failures.append(f"{base}/realObjects：层级面深度不对：{real.get('hierarchyDepths')}")
        if real.get("groupedDepths") != [0, 1, 2, 3, 4, 5, 6, 6, 5, 6]:
            failures.append(f"{base}/realObjects：分组面深度不对：{real.get('groupedDepths')}")
        tables = real.get("tableCount")
        views = real.get("viewCount")
        # 每一层展开的容器都会被分组 ⇒ 容器层的库 / schema 各一个「其他」组（条数 1）
        if real.get("headerCounts") != ["1", "1", str(tables), str(views)]:
            failures.append(
                f"{base}/realObjects：表头条数与真库对象数不符："
                f"{real.get('headerCounts')} vs 表 {tables} / 视图 {views}"
            )
        if tables != len(real.get("markerTables") or []):
            failures.append(f"{base}/realObjects：真库表数 {tables} 与标记数不符")
        if views != 1:
            failures.append(f"{base}/realObjects：真库视图数 {views} 不是 1")
        for marker in (real.get("markerTables") or []) + [real.get("markerView")]:
            if marker not in (real.get("realObjectNames") or []):
                failures.append(f"{base}/realObjects：真库读回来的对象里没有标记对象 {marker}")

    buckets = load(directory, "syntheticBuckets")
    if buckets is None:
        failures.append(f"{base}：没有 syntheticBuckets 的证据文件")
    else:
        if buckets.get("headerCounts") != ["2", "1", "1", "1", "1"]:
            failures.append(f"{base}/syntheticBuckets：五个桶的条数不对：{buckets.get('headerCounts')}")
        if len(buckets.get("headerTitles") or []) != 5:
            failures.append(f"{base}/syntheticBuckets：桶的表头不是五个：{buckets.get('headerTitles')}")
        if buckets.get("emptyChildrenRowCount") != 1:
            failures.append(f"{base}/syntheticBuckets：空子节点产出了行：{buckets.get('emptyChildrenRowCount')}")

    # 第三份：顶部那台开关的真点击（工具栏粒度）
    toolbar = load(directory, "toolbarSwitch")
    if toolbar is None:
        failures.append(f"{base}：没有 toolbarSwitch 的证据文件 —— 真点击那条没跑（跳过不算通过）")
    else:
        if toolbar.get("segmentCount") != 2:
            failures.append(f"{base}/toolbarSwitch：分段选择器不是两档：{toolbar.get('segmentCount')}")
        if toolbar.get("history") != ["grouped", "hierarchy"]:
            failures.append(
                f"{base}/toolbarSwitch：点两档没把绑定翻过去：{toolbar.get('history')}"
            )
        if not (toolbar.get("toolbarDiffPixels") or 0) > 0:
            failures.append(
                f"{base}/toolbarSwitch：两档画出来逐像素相同（{toolbar.get('toolbarDiffPixels')}）"
            )
        for key in ("zhHierarchy", "zhGrouped", "enHierarchy", "enGrouped"):
            if not (toolbar.get(key) or "").strip():
                failures.append(f"{base}/toolbarSwitch：语言表里缺 {key}")
        if (toolbar.get("zhHierarchy") or "") == (toolbar.get("enHierarchy") or ""):
            failures.append(f"{base}/toolbarSwitch：中英两档文案一模一样，语言那一遍没起作用")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 两遍都真跑过：两种视图的行集合一致 / 计数与真库相符 / 真点击两档都到得了（中英各一遍）")
PY

echo
echo "==> 分组视图那四条：源锚点（行模型是纯函数 / 分组只有一处来源 / 那台开关两档齐备 / **生产路径的接线本身**）"
python3 - "${ROOT}" <<'PY'
import os
import re
import sys

root = sys.argv[1]


def source(relative):
    with open(os.path.join(root, relative), encoding="utf-8") as handle:
        return handle.read()


def code_only(text):
    """只看代码，不看注释 —— 注释里写「不碰 AppState」这句话本身不该被判红。"""
    return "\n".join(line for line in text.split("\n") if not line.strip().startswith("//"))


rows = source("App/Views/ObjectTreeRows.swift")
view = source("App/Views/ObjectTreeView.swift")
toolbar = source("App/Views/ObjectTreeToolbar.swift")

failures = []
# ① 分组聚合**只有一处来源**：视图里自己再拼一份 = 两份口径迟早不一致
for name, text in (("App/Views/ObjectTreeView.swift", view), ("App/Views/ObjectTreeToolbar.swift", toolbar)):
    if "ObjectTreeGrouping.groupedByType(" in code_only(text):
        failures.append(f"{name} 里自己拼了一份分组行 —— 分组只能由 ObjectTreeRows 出")
if "ObjectTreeGrouping.groupedByType(" not in code_only(rows):
    failures.append("ObjectTreeRows.swift 里没有调用分组聚合 —— 行模型被掏空了？")
# ② 「切视图不重查库」的结构保证：行模型不许有任何取数能力
for forbidden in ("AppState", "loadMetadata", "DatabaseService", "PostgresService", "MySQLService", "URLSession"):
    if forbidden in code_only(rows):
        failures.append(f"ObjectTreeRows.swift 里出现了 {forbidden} —— 行模型必须是纯函数（切视图不重查库）")
# ③ 那台开关：两档齐备、且接的就是视图里那一个 @State
if 'Picker("", selection: $groupByType)' not in code_only(toolbar):
    failures.append("ObjectTreeToolbar.swift 里没有绑定 groupByType 的分段选择器")
for key in (".treeGroupHierarchy", ".treeGroupByType"):
    if key not in code_only(toolbar):
        failures.append(f"分段选择器少了 {key} 那一档")
if "ObjectTreeToolbar(" not in code_only(view):
    failures.append("ObjectTreeView.swift 没有把那一行装回去（ObjectTreeToolbar 没被用上）")
# ④ **生产路径的接线本身也要判**（第 101 轮注入实测补上的一格）：
#    模型判住了、工具栏判住了，**它们之间那根线**当时没人判 —— 把
#    `ObjectTreeView.swift` 里的 `groupByType: groupByType` 写死成 `false`（界面照旧能点、模型照旧对），
#    两遍**全绿**（探针只从模型和工具栏两头取数，不经过那条调用点）。
#    ⇒ 逐字（允许空白）要求那台开关传进模型：写死 `true` / `false` / 别的变量都判红。
if "ObjectTreeRows.visibleRows(" not in code_only(view):
    failures.append("ObjectTreeView.swift 没有调用行模型 ObjectTreeRows.visibleRows( —— 生产路径断了")
elif not re.search(r"groupByType:\s*groupByType", code_only(view)):
    failures.append(
        "ObjectTreeView.swift 调行模型时没有把那一台开关传进去（groupByType: groupByType）"
        " —— 模型与工具栏各自判得住，不等于它们之间接着线"
    )

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 分组只有一处来源（ObjectTreeRows）；行模型没有任何取数能力；开关两档齐备且接的是视图那一个 @State")
PY

echo
echo "==> 刷新重入那两条：证据核对（跳过 ≠ 通过）+ 源锚点（生产路径真的过闸门）"
python3 - "${OUT_PLAIN}" "${OUT_SANDBOX}" "${ROOT}" <<'PY'
import json
import os
import re
import sys

plain, sandbox, root = sys.argv[1], sys.argv[2], sys.argv[3]
failures = []


def load(directory, case):
    path = os.path.join(directory, "object-tree-refresh-evidence-%s.json" % case)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


for directory in (plain, sandbox):
    base = os.path.basename(directory)

    tree = load(directory, "wholeTree")
    if tree is None:
        failures.append("%s：没有 wholeTree 的证据文件 —— 探针没真跑（跳过不算通过）" % base)
    else:
        if tree.get("toolbarPresent") is not True:
            failures.append("%s/wholeTree：整棵树没进到「已加载」那一支" % base)
        if tree.get("controlToolbarPresent") is not False:
            failures.append(
                "%s/wholeTree：对照宿主（不存在的库）里也有那台开关 —— 「开关在场」这个信号认不出失败态" % base
            )
        if tree.get("loadingTextPresent") is not False:
            failures.append("%s/wholeTree：加载态没收干净（「正在加载对象…」还在画面上）" % base)
        nodes, control = tree.get("nodesLoaded"), tree.get("nodesControl")
        if not (isinstance(nodes, int) and isinstance(control, int) and nodes > control):
            failures.append("%s/wholeTree：真库那棵树不比失败态多（%s vs %s）" % (base, nodes, control))
        if tree.get("inFlightAfterSettle") != 0:
            failures.append(
                "%s/wholeTree：收尾之后还有键留在在途表里（%s）" % (base, tree.get("inFlightAfterSettle"))
            )

    reentry = load(directory, "reentry")
    if reentry is None:
        failures.append("%s：没有 reentry 的证据文件 —— 重入那条没跑（跳过不算通过）" % base)
    else:
        if reentry.get("toolbarAfterReentry") is not True:
            failures.append("%s/reentry：重入之后树没回到「已加载」那一支" % base)
        if reentry.get("loadingTextAfterReentry") is not False:
            failures.append("%s/reentry：重入之后加载态没收干净" % base)
        if reentry.get("inFlightAfterSettle") != 0:
            failures.append("%s/reentry：重入之后还有键留在在途表里" % base)


def source(relative):
    with open(os.path.join(root, relative), encoding="utf-8") as handle:
        return handle.read()


def code_only(text):
    """只看代码，不看注释 —— 注释里写「不许各拼一份」这句话本身不该被判红。"""
    return "\n".join(line for line in text.split("\n") if not line.strip().startswith("//"))


view = code_only(source("App/Views/ObjectTreeView.swift"))
appstate = code_only(source("App/AppState.swift"))
gate = code_only(source("Core/ObjectTreeRefreshGate.swift"))

# ① 生产路径真的过闸门（抽了闸门而没人用 = 没抽，第 101 轮的教训）
if "objectTreeRefreshGate.roots(" not in view:
    failures.append("ObjectTreeView 取根节点没走闸门 —— 同一次刷新又会各查一遍库")
# ② 闸门里那一次取数仍然是产品那条路（判据里不许另开一条取数口径）
if "try await appState.loadMetadataRoot()" not in view:
    failures.append("闸门里那一次取数不再是 AppState.loadMetadataRoot() —— 取数口径出现了第二处")
# ③ 刷新键**只有一份**：视图里 `.task(id:)` 与闸门都必须是 ObjectTreeRefreshKey（连接 + 元数据版本）
if "ObjectTreeRefreshKey(" not in view:
    failures.append("ObjectTreeView 没有用 ObjectTreeRefreshKey —— 刷新键又变成各写一份")
elif len(re.findall(r"ObjectTreeRefreshKey\(", view)) < 2:
    failures.append("ObjectTreeView 里刷新键只出现一次 —— .task(id:) 与闸门用的不是同一把键")
if not re.search(r"revision:\s*appState\.metadataRevision", view):
    failures.append("刷新键里没有元数据版本 —— 「同一次刷新」判不准")
if "struct RefreshKey" in view:
    failures.append("ObjectTreeView 里又出现了私有的 RefreshKey —— 同一把键两个真值来源")
# ④ 闸门住在 AppState（长命对象）上：视图销毁重建时 @State 会归零，闸门必须比它活得久
if "let objectTreeRefreshGate = ObjectTreeRefreshGate()" not in appstate:
    failures.append("闸门没挂在 AppState 上 —— 视图重建之后新实例没得可并（重入还是两次取数）")
if "@State private var objectTreeRefreshGate" in view:
    failures.append("闸门挂在视图的 @State 上 —— 视图重建会把它清零")
# ⑤ 闸门下的取数**不受调用方取消影响** ⇒ 调用方必须自己问一句，否则切连接会把旧连接的数据糊上树
if "guard !Task.isCancelled" not in view:
    failures.append("取数回来没有问 Task.isCancelled —— 被取消的那一发会把上一个连接的数据写进树")
# ⑥ 闸门本身不许退化：收尾必须挂在**这一发自己**身上（否则键会永久留在在途表里）
if "defer { inFlight[key] = nil }" not in gate:
    failures.append("ObjectTreeRefreshGate 收尾没挂在那一发自己身上 —— 键可能永远留在在途表里")
if "inFlightCount" not in gate:
    failures.append("ObjectTreeRefreshGate 没有 inFlightCount —— 判据读不到「还在途几个键」")

if failures:
    for item in failures:
        print("✗ %s" % item)
    sys.exit(1)
print("✓ 两遍都真跑过：整棵树在活宿主里真加载出来（对照宿主认得出失败态）／重入之后照样「已加载」且没漏键")
print("✓ 源锚点：生产路径过闸门 / 取数仍是那条路 / 刷新键只有一份 / 闸门挂在长命对象上 / 取消那一发不许写状态")
PY

echo
echo "==> 笔记检索那两条：两遍都**真跑过**了吗（跳过 ≠ 通过）"
python3 - "${OUT_PLAIN}" "${OUT_SANDBOX}" <<'PY'
import json
import os
import sys

# 期望值只写「不变量」：与证据自洽的关系，而不是把探针里的数字再抄一遍。
def load(directory, case):
    path = os.path.join(directory, f"note-search-evidence-{case}.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


failures = []
for directory in sys.argv[1:]:
    base = os.path.basename(directory)

    saved = load(directory, "saveThenSearch")
    if saved is None:
        failures.append(f"{base}：没有 saveThenSearch 的证据文件 —— 探针没真跑（跳过不算通过）")
    else:
        if saved.get("beforeSaveCount") != 0:
            failures.append(f"{base}/saveThenSearch：保存前就已经有结果（前提不成立）：{saved.get('beforeSaveCount')}")
        if saved.get("queryAfterSave") in (None, ""):
            failures.append(f"{base}/saveThenSearch：保存之后搜索框是空的 —— 这条判据要的是「查询还在」")
        if len(saved.get("afterSaveTitles") or []) != 1:
            failures.append(
                f"{base}/saveThenSearch：保存之后结果里应当**恰好**是刚存的那条，实测：{saved.get('afterSaveTitles')}"
            )

    deleted = load(directory, "deleteWhileSearching")
    if deleted is None:
        failures.append(f"{base}：没有 deleteWhileSearching 的证据文件")
    else:
        if deleted.get("beforeDeleteCount") != 2:
            failures.append(f"{base}/deleteWhileSearching：删除前的结果数不是 2：{deleted.get('beforeDeleteCount')}")
        if len(deleted.get("remainingTitles") or []) != 1:
            failures.append(
                f"{base}/deleteWhileSearching：删掉之后结果里应当只剩一条，实测：{deleted.get('remainingTitles')}"
            )

    cleared = load(directory, "clearSaveSearch")
    if cleared is None:
        failures.append(f"{base}：没有 clearSaveSearch 的证据文件")
    elif (cleared.get("foundTitles") or []) != ["后来补的"]:
        failures.append(
            f"{base}/clearSaveSearch：按清单原文（清空 → 保存 → 再搜）没搜到刚存的那条：{cleared.get('foundTitles')}"
        )

    for case in ("lateResultDropped", "quickTyping"):
        if load(directory, case) is None:
            failures.append(f"{base}：没有 {case} 的证据文件 —— 「键盘快打」那条没跑（跳过不算通过）")

    dropped = load(directory, "lateResultDropped")
    if dropped is not None:
        if dropped.get("staleResultApplied") is not False:
            failures.append(f"{base}/lateResultDropped：旧词的结果落地了：{dropped.get('staleResultApplied')}")
        if dropped.get("staleFailureApplied") is not False:
            failures.append(f"{base}/lateResultDropped：旧词的失败落地了：{dropped.get('staleFailureApplied')}")
        if dropped.get("appliedForCurrentWord") is not True:
            failures.append(f"{base}/lateResultDropped：当前词的结果没落地 —— 判据空转")

    typing = load(directory, "quickTyping")
    if typing is not None:
        # 不变量：切换之后**没有一次**落地带来的是旧词的结果。
        if typing.get("staleLandingsAfterSwitch") != 0:
            failures.append(
                f"{base}/quickTyping：切换之后有 {typing.get('staleLandingsAfterSwitch')} 次落地来自旧词"
                "（迟到的结果覆盖了新的）"
            )
        if not (typing.get("landingsAfterSwitch") or 0) >= 1:
            failures.append(
                f"{base}/quickTyping：切换之后一次落地都没有（{typing.get('landingsAfterSwitch')}）"
                "—— 那说明新词那一次没跑，不变量是空的"
            )
        if (typing.get("finalTitles") or []) != ["山的那条"]:
            failures.append(f"{base}/quickTyping：终态不是最后那个词的结果：{typing.get('finalTitles')}")
        if typing.get("finalTitles") != typing.get("stateAfterLateArrival"):
            failures.append(
                f"{base}/quickTyping：旧词的结果晚到之后状态变了："
                f"{typing.get('finalTitles')} → {typing.get('stateAfterLateArrival')}"
            )

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 两遍都真跑过：查询还在时保存/删除当场生效；旧词的结果与失败都不落地；"
      "切换后没有一次落地来自旧词（终态 = 最后那个词）")
PY

echo "==> 浏览器页签与下载那条：两遍都**真跑过**了吗（跳过 ≠ 通过）"
python3 - "${OUT_PLAIN}" "${OUT_SANDBOX}" "${ROOT}" <<'PY'
import json
import os
import sys


def load(directory, case):
    path = os.path.join(directory, f"browser-tab-evidence-{case}.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


failures = []
plain, sandbox, root = sys.argv[1], sys.argv[2], sys.argv[3]
for directory in (plain, sandbox):
    base = os.path.basename(directory)
    restored = load(directory, "restoredTab")
    if restored is None:
        failures.append(f"{base}：没有 restoredTab 的证据文件 —— 那条没跑（跳过不算通过）")
    else:
        if restored.get("restoredAddress") != restored.get("address"):
            failures.append(
                f"{base}/restoredTab：重开之后地址不是上次那个：{restored.get('restoredAddress')}"
            )
        if restored.get("pristineAfterRestart") is not True:
            failures.append(f"{base}/restoredTab：恢复出来的页签被当成已加载（打开应用就出网了）")
        if restored.get("address") not in (restored.get("addressFieldValues") or []):
            failures.append(
                f"{base}/restoredTab：地址栏里没有那个地址：{restored.get('addressFieldValues')}"
            )

    egress = load(directory, "egressByTab")
    if egress is None:
        failures.append(f"{base}：没有 egressByTab 的证据文件")
    else:
        ids = egress.get("entryTabIDs") or []
        if len(ids) != 2 or any(value in (None, "", "nil") for value in ids):
            failures.append(f"{base}/egressByTab：盘上那份记录没带页签身份：{ids}")
        if ids and any(value != egress.get("tabA") for value in ids):
            failures.append(f"{base}/egressByTab：记录的页签身份不是那个页签：{ids}")
        origins = egress.get("entryOrigins") or []
        for wanted in ("浏览器 · 页签", "浏览器 · 下载"):
            if wanted not in origins:
                failures.append(f"{base}/egressByTab：日志里没有「{wanted}」那条：{origins}")
        if egress.get("filterCountForTabA") != 2:
            failures.append(f"{base}/egressByTab：按那个页签筛出来的条数不是 2：{egress.get('filterCountForTabA')}")
        if egress.get("filterCountForTabB") != 0:
            failures.append(f"{base}/egressByTab：按没发过请求的页签筛出了记录：{egress.get('filterCountForTabB')}")
        if (egress.get("tabPickerIDs") or []) != [egress.get("tabA")]:
            failures.append(f"{base}/egressByTab：下拉里的页签不是恰好那一个：{egress.get('tabPickerIDs')}")
        if (egress.get("tabPickerLabels") or []) != [egress.get("tabATitle")]:
            failures.append(f"{base}/egressByTab：下拉里的显示名不对：{egress.get('tabPickerLabels')}")
        if (egress.get("tabPickerLabelsWhenEmpty") or []) != []:
            failures.append(
                f"{base}/egressByTab：日志清空后还有页签选项（「可点」那条断言恒真了）："
                f"{egress.get('tabPickerLabelsWhenEmpty')}"
            )
        if egress.get("sheetRenderedAllTabs") is not True:
            failures.append(f"{base}/egressByTab：外发日志面板上没渲染出「页签」那台下拉")

    landing = load(directory, "downloadLanding")
    if landing is None:
        failures.append(f"{base}：没有 downloadLanding 的证据文件")
    else:
        if landing.get("firstFile") != "report.zip":
            failures.append(f"{base}/downloadLanding：第一份的文件名不是 report.zip：{landing.get('firstFile')}")
        if landing.get("secondFile") != "report-1.zip":
            failures.append(f"{base}/downloadLanding：同名那一份没加 -1（会覆盖）：{landing.get('secondFile')}")
        if landing.get("firstUnchanged") is not True:
            failures.append(f"{base}/downloadLanding：第二份把第一份写坏了")
        if (landing.get("filesOnDisk") or []) != ["report-1.zip", "report.zip"]:
            failures.append(f"{base}/downloadLanding：授权目录里的文件不对：{landing.get('filesOnDisk')}")
        wanted_path = os.path.join(landing.get("authorizedDirectory") or "", landing.get("secondFile") or "")
        if wanted_path and wanted_path not in (landing.get("notice") or ""):
            failures.append(f"{base}/downloadLanding：提示条里没有那个路径：{landing.get('notice')}")
        if landing.get("egressOutcome") != "allowed":
            failures.append(f"{base}/downloadLanding：下载那条外发记录的结果不是 allowed：{landing.get('egressOutcome')}")
        if landing.get("egressTabID") != landing.get("tabID"):
            failures.append(f"{base}/downloadLanding：下载那条记录没带页签身份：{landing.get('egressTabID')}")

# 源锚点：「视图用的就是那个纯函数」—— 纯函数抽出来而没人用等于没抽（第 101 轮的教训）
with open(os.path.join(root, "App/Views/EgressLogSheet.swift"), encoding="utf-8") as handle:
    sheet_text = handle.read()
if "EgressTabOptions.options(from: appState.egressEntries)" not in sheet_text:
    failures.append("EgressLogSheet 不再用 EgressTabOptions 推导选项（判据与界面脱钩了）")
if ".disabled(tabOptions.isEmpty)" not in sheet_text:
    failures.append("EgressLogSheet 里那条「没有页签就灰着」的接线不见了")
if "for entry in appState.egressEntries" in sheet_text:
    failures.append("EgressLogSheet 又在自己算一遍选项（同一口径出现了第二处）")
if not os.path.exists(os.path.join(root, "Core/EgressTabOptions.swift")):
    failures.append("Core/EgressTabOptions.swift 不在盘上")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 两遍都真跑过：重开地址还在（且没加载、地址栏里就是它）／盘上两份记录都带页签身份、"
      "筛得出来、下拉里恰好那一个页签（清空即无）／下载落在授权目录、同名加 -1、提示条写着那个路径")
PY

echo
echo "==> MySQL 表单联动的证据核对（第十一批）"
python3 - "${OUT_PLAIN}" "${OUT_SANDBOX}" "${ROOT}" <<'PY'
import json
import os
import sys

plain, sandbox, root = sys.argv[1], sys.argv[2], sys.argv[3]
failures = []


def load(directory, base, name):
    path = os.path.join(directory, "mysql-form-evidence-%s.json" % name)
    if not os.path.exists(path):
        failures.append("%s：没有 %s 的证据文件 —— 探针没真跑（跳过不算通过）" % (base, name))
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


# 期望值只写「不变量」：与界面上那两台下拉自洽的关系，而不是把探针里的数字再抄一遍。
for directory, base in ((plain, "普通那遍"), (sandbox, "带沙箱标记那遍")):
    linkage = load(directory, base, "formLinkage")
    if linkage:
        if linkage.get("dialectItems") != ["PostgreSQL", "MySQL", "GBase 8a"]:
            failures.append("%s/formLinkage：方言下拉的条目不对：%s" % (base, linkage.get("dialectItems")))
        mysql_items = linkage.get("mysqlSSLItems") or []
        if len(mysql_items) != 5:
            failures.append("%s/formLinkage：MySQL 的 SSL 清单不是五项：%s" % (base, mysql_items))
        if "Allow" in mysql_items:
            failures.append("%s/formLinkage：MySQL 的 SSL 清单里还有 Allow（R-53 会复发）" % base)
        if "Verify Identity" not in mysql_items:
            failures.append("%s/formLinkage：MySQL 下没有 Verify Identity 那一档" % base)
        pg_items = linkage.get("pgSSLItems") or []
        if "Allow" not in pg_items or len(pg_items) != 6:
            failures.append("%s/formLinkage：PG 的 SSL 清单不是六项含 Allow：%s" % (base, pg_items))
        if linkage.get("mysqlSSLSelection") != "Prefer":
            failures.append("%s/formLinkage：MySQL 的 SSL 选中项不是 Prefer：%s" % (base, linkage.get("mysqlSSLSelection")))
        after_pg = linkage.get("fieldValuesAfterBackToPG") or []
        if "5432" not in after_pg:
            failures.append("%s/formLinkage：点回 PG 之后端口没回到 5432（联动是单向的？）" % base)
        if "3306" in after_pg:
            failures.append("%s/formLinkage：点回 PG 之后端口还留着 MySQL 的 3306" % base)

    tree = load(directory, base, "treeLayers")
    if tree:
        layers = tree.get("layerKinds") or []
        if len(layers) != 4:
            failures.append("%s/treeLayers：展开出的层级不是四层：%s" % (base, layers))
        else:
            if layers[0] != ["server"]:
                failures.append("%s/treeLayers：第 1 层不是服务器：%s" % (base, layers[0]))
            if not layers[1] or any(kind != "database" for kind in layers[1]):
                failures.append("%s/treeLayers：第 2 层不是库：%s" % (base, layers[1]))
            if not layers[2] or any(kind not in ("table", "view") for kind in layers[2]):
                failures.append("%s/treeLayers：第 3 层不是表 / 视图：%s" % (base, layers[2]))
            if not layers[3] or any(kind != "column" for kind in layers[3]):
                failures.append("%s/treeLayers：第 4 层不是列：%s" % (base, layers[3]))
        if tree.get("schemaNodes") != 0:
            failures.append("%s/treeLayers：树里出现了 schema 节点（MySQL 里库 = schema）" % base)
        if tree.get("beyondColumnCount") != 0:
            failures.append("%s/treeLayers：列下面还有子节点 ⇒ 不是四层" % base)
        if not (tree.get("columnNames") or []):
            failures.append("%s/treeLayers：一列都没展开出来（DESC 那条路）" % base)
        if not any(detail for detail in (tree.get("columnDetails") or [])):
            failures.append("%s/treeLayers：列的「类型」一个都没读到（只读到了列名）" % base)

    rows_evidence = load(directory, base, "queryRows")
    if rows_evidence:
        if rows_evidence.get("columns") != ["id", "name", "note", "amount"]:
            failures.append("%s/queryRows：回来的列名不对：%s" % (base, rows_evidence.get("columns")))
        if (rows_evidence.get("rowCount") or 0) < 1:
            failures.append("%s/queryRows：一条数据都没查回来" % base)

# 源锚点：判据盯的必须是**产品那条联动线**（第 101 轮的教训：判据与界面脱钩就白判）。
# 本机 SwiftUI 的 Picker 不落到 AppKit 控件 ⇒ 联动被搬进 `ConnectionDialectLinkage`，
# 于是这里要钉住两头：**界面真的读了那一份**（表单把绑定交给那两个视图、视图真的调它），
# 以及**那一份本身没被架空**（端口 / SSL 默认值 / 清单都取自方言自己）。
anchors = {
    "App/Views/ConnectionFormView.swift": (
        ("ConnectionDialectPicker(", "表单不再用那两个视图了（联动与界面之间的线断了）"),
        ("sslModeWasAdjusted: $sslModeWasAdjusted", "表单没把「收敛说明」那格交给视图"),
        ("ConnectionSSLModeRow(", "SSL 那一行不再用那个视图了"),
    ),
    "App/Views/ConnectionDialectSection.swift": (
        ("ForEach(ConnectionDialectLinkage.dialects)", "方言那一台不再读唯一出处里的条目清单"),
        ("ConnectionDialectLinkage.adjustments(for: newValue)", "换方言那条回调不再走唯一出处"),
        ("port = next.port", "换方言时端口不再跟着换"),
        ("sslMode = next.sslMode", "换方言时 SSL 不再收敛到方言默认值"),
        ("sslModeWasAdjusted = next.adjusted", "换方言时那条收敛说明不再清掉"),
        ("ForEach(ConnectionDialectLinkage.adjustments(for: dbType).sslModes)", "SSL 那一台不再按方言列模式（Allow 会漏到 MySQL 上）"),
        ("port: String(type.defaultPort)", "唯一出处里的端口不再取自方言"),
        ("sslMode: type.defaultSSLMode", "唯一出处里的 SSL 默认值不再取自方言"),
        ("sslModes: type.sslModes", "唯一出处里的清单不再取自方言"),
    ),
}
for relative, needles in anchors.items():
    with open(os.path.join(root, relative), encoding="utf-8") as handle:
        anchor_text = handle.read()
    for needle, why in needles:
        if needle not in anchor_text:
            failures.append("%s 里「%s」不见了：%s" % (relative, needle, why))
if not os.path.exists(os.path.join(root, "TestsUISnapshot/MySQLFormProbeTests.swift")):
    failures.append("TestsUISnapshot/MySQLFormProbeTests.swift 不在盘上")

if failures:
    for item in failures:
        print("✗ %s" % item)
    sys.exit(1)
print("✓ 两遍都真跑过：换方言当场换端口（3306 / 5258）与 SSL 清单（五项、无 Allow、Verify Identity）；"
      "对象树四层（服务器 → Database → Table → Column）、树里没有 schema 节点、列下面没有第 5 层；"
      "同一路查询入口真的从服务端取回了那一份结果集")
PY

echo
echo "==> 完成：证据在 ${OUT_BASE}/（每张图另有中英两份，逐张断言见 ManualVerificationProbeTests）"
echo "    「待人工验收清单」里被机器化的行：§10.6 隧道表单字段显隐 / §10.6 沙箱告知 / §10.7 R-53 SSL 收窄说明"
echo "    ＋ §2 FR-EDIT-25 命令面板接线（PaletteWiringProbeTests：每条命令点一遍、断言落点）"
echo "    ＋ §2 FR-EDIT-26 主题与字体（AppearanceFontProbeTests：手输族的三档说法 + SQL 预览取样带）"
echo "    ＋ §0.3 第 3 条 终端 ⌃C（TerminalInterruptProbeTests：喂 0x03 看前台 sleep 让不让开）"
echo "    ＋ §1 FR-EDIT-29 多会话那一行的版面与落点（TerminalTabsProbeTests 后三个用例：左半变 / 右四分之一逐像素不变、"
echo "       右侧按钮按状态齐备、⌘1…9 与 ⌘⇧[ ⌘⇧] 与改名落到对的会话）"
echo "    ＋ §4 FR-RES-07 大结果集滚动（LargeResultScrollProbeTests：虚拟化 / 帧在变 / 单帧成本不随总行数放大 / 内存不飙）"
echo "    ＋ §5 FR-META-10 跨库浏览（CrossDatabaseBrowseProbeTests：按需建连 / 子树来自那个库 / 失败给可读原因）"
echo "    ＋ §5 FR-META-15 分组视图（GroupedViewProbeTests：两种视图的行集合一致 / 表头计数与真库相符 /"
echo "       真点开关两档都到得了、两档不是一个样子（中英各一遍）；序列·函数·其他三个桶用合成夹具补）"
echo "    ＋ 笔记检索「存完立刻搜」与「键盘快打」（NoteSearchProbeTests：查询还在时保存/删除当场生效 /"
echo "       旧词的结果与失败都不许落地 / 切换后没有一次落地来自旧词 —— 真 AppState + 真库）"
echo "    ＋ §10 FR-EDIT-34 浏览器页签与下载（BrowserTabDownloadProbeTests：重开地址还在且没加载 /"
echo "       盘上两条记录都带页签身份、筛得出来、下拉里恰好那一个 / 下载落在授权目录、同名加 -1）"
echo "    ＋ §10.7 FR-DRV-09 MySQL 表单联动（MySQLFormProbeTests：换方言 ⇒ 端口当场变 3306、"
echo "       SSL 清单五项无 Allow、来回都判；连假 MySQL 服务器逐层展开 ⇒ 四层树、无 schema 层、查得到数据）"
