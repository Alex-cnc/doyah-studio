#!/usr/bin/env python3
"""主题集（配色方案）门禁（队列 L-80 ㈠，闭环第 6 项，与设计令牌棘轮 / 样张同源门禁同项）。

存在的理由（真现场）
--------------------
2026-09-29 需求提出者要求「增加一个 theme 主题选项」，并指出 Linux 版早有**豆芽绿 / 玫瑰金 / 科技蓝**
三选一。于是令牌值从「一套」变成「**三套**」，而这件事有一个单测天然守不住的地方：

    · 单测（`Tests/DesignTokensTests.swift` / `DesignThemeTests.swift`）与新主题
      **用同一份实现**算对比度（`ColorContrast`）。没错，但"判据与被判对象同源"意味着
      —— 如果值表里某一档被改坏、或有人**新加一套表**却漏了某个角色，只会红在同一个实现里；
    · 更要紧的是"**主题名与 Linux 侧对齐**""**待值登记还在**"这两件事**根本不是单测能看的**：
      它们是跨文档的事实（`Docs/design/外观方案-v1.md` §9 的表 / `Docs/archive/root-20261026/发布计划.md` 的待输入表 /
      `Core/Localization.swift` 的双语文案）。

本脚本因此做了两件与单测互补的事：
    ① **独立复算**：用 Python 自己重新实现 WCAG 相对亮度 / 对比度 / 表面距离，
       从 Swift 源里**解析出**三套值，逐条复算门槛（不同语言、不同实现 ⇒ 不是自证）；
    ② **跨文档对账**：主题名 ↔ §9 表 ↔ 双语名；有几个推导主题 ↔ 待值登记行。

判据（任一不过即失败）
----------------------
A. **主题集**：`Core/DesignTheme.swift` 的 `case <名> = "<id>"` 集合与顺序必须等于台账（`tech-blue` /
   `bean-green` / `rose-gold` / `stardust` / `deep-space`）；`DesignTheme.all` 把五个主题**都**列了出来、且**界面顺序
   逐格**等于台账 `THEME_UI_ORDER`（列漏一个 = 用户选不到它；顺序变了 = 用户看到的次序变了 —— 判的是
   **身份与顺序**，不是「数个数」）；`ThemePalette.of(_:)` 每一支必须取**同名**值表（取错表 = 那个主题
   整屏用的是别人的颜色）。判点处数有下限（空跑防护）。
B. **四套值表角色齐全**：每个 `ThemePalette` 块必须含全部 20 个字段（18 个色角色 + 发丝线两参数），
   缺一个即红 —— 缺角色在 Swift 里是编译错误，但"新加一套表时少写一行"这类改动会先在
   **复制粘贴的中间态**里存在；`of(_:)` 的 switch 必须三支齐全（每个主题都取得到值）。
C. **独立复算门槛**（本脚本自己实现，不看 Swift 的实现）：五主题 × 深浅两态逐条判 ——
   正文 ≥4.5 / 强对比 ≥7 且强于正文 / 辅助 ≥3.0 / 禁用比辅助淡且 ≥1.5 / 状态色在两表面 ≥3.0 /
   强调家族按角色 ≥4.5（文字链接）与 ≥3.0（图标线，基准 = 深色对 window、浅色对白）/
   语法六档两两不同且各自过关 / 深色五档明度严格递增 / 浅色 content 最亮 /
   表面之间距离 ≥0.02 / 浅色发丝线比 content 暗。
D. **语法色必须仍挂在家族角色上**：`Core/DesignTokens.swift` 的 `SyntaxTone.color(in:)` 六行映射
   逐行对账（keyword→accentGlow / string→warm / number→teal / function→accent /
   identifier→primary / comment→tertiary）—— 谁把某个语法色改回硬编码，六档就与家族脱钩。
   判定物 = **`switch` 块内的非注释代码**（先切片、再剥注释）：先前在整份文件上找、也不剥注释，
   六条真映射整行注释掉仍绿（原单 `T-20261010-068` ㈠），映射搬到块外也照样绿。
E. **主题名与 Linux 侧对齐 + 待值登记成对**：
   ① `Core/Localization.swift` 里五个主题名键的中文值必须是「科技蓝 / 豆芽绿 / 玫瑰金 / 星空紫 / 深空苍穹」，
      且 `Docs/design/外观方案-v1.md` §9 的主题表里三行**同名**（双向覆盖，缺一即红）；
   ② 有推导主题（`isDerivedDraft`）就必须 ① 值表**紧挨着的那段注释**里标着「推导草案」
      （§9.1 的原话）② `Docs/archive/root-20261026/发布计划.md` 的待输入表里登记着「豆芽绿 / 玫瑰金 色值（Linux 侧）」
      那件事 —— 推导值不许**静默变成**实际值。
F. 空跑防护：主题数 / 角色数 / 实测对数 / 文档锚点处数四条下限，任何一条踩线即红。
G. **界面入口（㈡ 加上的那一半）**：值表分组了、运行时也能切了，但**用户手上那个入口**是另一件事
   —— 五个主题里有没有人**选不到**、预览是不是只给一块色卡、推导值有没有在界面上**逐条**标出来、
   以及"加了主题就把原来那个强调色入口删掉"这类**静默收功能**。判据：① 面板必须逐个列出主题集
   （`ForEach(DesignTheme.all)`）且选主题走**唯一写入口** `select(_:)`，且**订阅**了主题管理器
   （否则换了主题这块面板自己不跟着变）；② 主题行必须画出**三个真实场景**（选中行 / 主按钮 / 焦点环）
   且预览画在**该主题自己**的表面上（`palette.content`）＋用**该主题配套**的强调色（`theme.accent`）；
   ③ 推导主题必须**逐条**标注（行里问 `isDerivedDraft` + 画出标记键 + 语言表里有那句中文）；
   ④ `AccentTheme.all` 入口不许消失（FR-STD-WS-UI-009 的「强调色可配置」是已交付能力，要收得先改 SRS 与判据）；
   ⑤ 宿主语境覆盖（`beginHostTheme` / `endHostTheme`）**不许写盘**（拍一张快照不许改用户偏好 ——
   语言那条路定过这个口径），而 `select(_:)` **必须**写盘。判点只看**那一段源码切片**，不看整文件
   （否则"别处写过一句"就顶数 —— 第 77 轮自检例 ⑨/⑮ 两次栽在这上面）；且判定物
   **先剥注释**（注释里留一句「入口还在」不算实现 —— 原单 `T-20261010-068` ㈢）。

判据 I（**「星云皮肤」的存在 / 开关 / 三层表面**（2026-10-16 泛化：星云不再专属星空紫，改由主题声明），队列 `L-155`，第 154 轮）
------------------------------------------------------------------------------------
`L-153` 把星云皮肤落进产品时**如实登记了**一处判据缺口：皮肤"真的画了 / 关了真回纯色 /
别的主题真的不画"三件事当时**没有任何门禁在看**，现有的判据只证了"编译进包 / 无裸色值 /
台账对齐"。判据 I 补的就是"存在、开关与三层表面"这一半（另一半是**像素**判据，
在 `TestsUISnapshot/NebulaSkinProbeTests.swift`；静态与像素的分工写在那个文件头）：

  ① **规则只有一处出处**：键 / 缺省值 / 读法 / 生效条件全在 `Core/NebulaSkinPreference.swift`
     —— 键的字面量在**入库源码面**（十根 + 仓根，见 `SWIFT_FACE_ROOTS` 与
     `Scripts/design-themes-key-baseline.json`）里**只许出现在登记过的落点**（写两处 ⇒ 改一处就让
     老用户的开关选择静默失效；2026-10-13 按 `T-20261010-036` 把面从 4 根扩到入库源码面 ——
     扩面前 `Tests/` 里那份「断言键值 = 契约」的第二份在面外，判据看不见）；
     读法逐字必须是 `object(forKey:) as? Bool ?? 缺省`
     （`bool(forKey:)` 对"从未设过"返回 `false` ⇒ 缺省值被静默改成关）；
  ② **生效条件 = 主题声明要星云 且 开关开**（2026-10-16 泛化前是「星空紫 且 开关开」），
     且 `NebulaBackground.body` **只许调它、不许再写一遍**
     （切片里出现 `.stardust` 即红 —— 两处口径必然分叉）；
  ③ **三层表面（侧栏 / 内容区 / 下方面板）各自恰有一处落点**：少了那一层没皮肤、
     多了那一层重复铺（观感与性能都是问题）；面 = **宿主 target 的 `sources:` 现读**
     （`App` + `Plugins/Notes/Views`，不写死 `App/`）；
  ④ **界面那个开关接到唯一写入口**（`designTheme.setNebulaSkinEnabled`，绑本地 `@State` 就落不了盘），
     且**只在声明要星云的主题下出现**（别的主题下摆一个点了没反应的开关是把用户绕晕）；
  ⑤ 两族的落点都在位：像素探针（三张主角 + 逐像素比对口子 + 阈值出处）**必须挂进**
     `Scripts/run-manual-verification-probes.sh` 的 FILTER（AGENT-SPEC §9 第 104 条：不挂进
     FILTER 的这一族一个都跑不到），以及 Core 侧规则单测的几条点名用例。

判据自己的证据：`--self-test` **54 例**（53 个红/绿成对 + 末例核对真仓库二十一份文件逐字节未变；
夹具一律在临时目录）；判据面与 `Package.swift` 的 target 源码目录**双向对账**（新目录落在面外 / 面里
多一根没理由的根 ⇒ 判红）。

用法：
    python3 Scripts/check-design-themes.py              # 校验（闭环第 6 项）
    python3 Scripts/check-design-themes.py --self-test  # 门禁自己的证据（54 例）
"""

from __future__ import annotations

import hashlib
import json
import math
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

THEMES_SWIFT = "Core/DesignTheme.swift"
TOKENS_SWIFT = "Core/DesignTokens.swift"
LOCALIZATION_SWIFT = "Core/Localization.swift"
DESIGN_DOC = "Docs/design/外观方案-v1.md"
RELEASE_PLAN = "Docs/archive/root-20261026/发布计划.md"
APPEARANCE_SWIFT = "App/Views/AppearanceSheet.swift"
THEME_MANAGER_SWIFT = "App/DesignThemeManager.swift"

# ---- 判据 H（两轴正交，队列 L-85）的台账（每条都带理由）-------------------------------------

APPEARANCE_PREF_SWIFT = "Core/AppearancePreference.swift"     # 深浅轴（三态）的类型与落盘键
APP_STATE_SWIFT = "App/AppState.swift"                        # 深浅档的写盘点
AXES_TESTS_SWIFT = "Tests/AppearanceAxesTests.swift"          # 两轴的单测（真值表 / 正交 / 矩阵 / 门槛）
AXES_PROBE_SWIFT = "TestsUISnapshot/AppearanceAxesProbeTests.swift"  # 真管理器 + 真 UserDefaults 上的探针
SNAPSHOT_KIT_SWIFT = "TestsUISnapshot/UISnapshotKit.swift"    # 取色口子（像素断言）
PANELS_TESTS_SWIFT = "TestsUISnapshot/UISnapshotPanelsTests.swift"   # 主题面板快照的角像素断言
# 深浅轴的三态（顺序 = 界面上列出的顺序；与 `AppearancePreference` 的 case 名逐字相同）。
AXIS_STATES = ("followSystem", "alwaysDark", "alwaysLight")
# 系统当前深浅两态：`followSystem` 这一档必须在**两态**下都取得到值、都过门槛。
AXIS_SYSTEM_STATES = (False, True)
# 真值表：三态 → `resolvesToDark` 里那一行的返回表达式（逐格对账，不看注释）。
AXIS_TRUTH_TABLE = (("followSystem", "systemIsDark"), ("alwaysDark", "true"), ("alwaysLight", "false"))
# 未知偏好值的回落（偏好文件被手改 / 版本降级后读到新值都不该让界面起不来）。
AXIS_FALLBACK = "else { return .followSystem }"
AXIS_APPEARANCE_KEY = "appearance.mode"            # 深浅轴落盘键 = `AppearancePreference.Storage.appKey`
AXIS_APPEARANCE_TERMINAL_KEY = "terminal.appearance"  # 终端的深浅档（第三个键：终端可单独覆盖）
AXIS_THEME_KEY = "ui.designTheme"                  # 配色轴落盘键 = `DesignTheme.Storage.key`
# 像素比对的容差：**实测出来的**（快照 PNG 往返把通道值偏移最多 4：深色 `window #02070A` 读回
# `#02060A`、浅色 `#F1F5FA` 读回 `#F4F7FB`）⇒ 取 8。它必须小于「换一个主题」在这套值上的差异
# （深色 `window` 四个主题实测 #02060A / #03160A / #1A070B / #0C1018，两两至少差 14 以上）。
AXIS_PIXEL_TOLERANCE = 8
# 取色口子的锚点（定义是 `sampledRGB(ofPNGAt path:…)`、调用点是 `sampledRGB(ofPNGAt: …)`）——
# 取到「ofPNGAt」为止即可同时认这两处；带上冒号反而只认调用点（第 83 轮判据当场抓出来的）。
AXIS_PIXEL_HOOK = "sampledRGB(ofPNGAt"
AXIS_PROBE_CASE = "testSwitchingOneAxisNeverResetsTheOther"   # 探针里那条「切一轴不重置另一轴」
AXIS_DOC_HEADING = "### 9.6 两轴正交"                # 文档落点（外观方案里的那一节）
# 单测点名（少一条即红）——判据只认「这一条存在」，跑绿由 `swift test` 保证。
AXIS_TEST_CASES = {
    "testAppearanceTruthTableOverEveryStateAndSystemValue": "三态 × 系统两态 = 6 组真值表",
    "testDarkResolutionIsIndependentOfTheme": "换主题不改深浅判定",
    "testPaletteSelectionIsIndependentOfAppearanceAxis": "换深浅不改配色",
    "testAxisMatrixCoversEveryCombinationExactlyOnce": "30 组组合不重不漏",
    "testFollowSystemBothStatesClearThresholdsInEveryTheme": "跟随系统两态都过门槛",
    "testStorageKeysAreSeparateAndNamespaced": "两轴落盘键分开",
}
MIN_AXIS_SITES = 30   # 判据 H：判点处数下限（空跑防护：扫描面被削即红）
# 组合数（3 态 × 2 系统态 × 5 主题 = 30）在单测里必须是**真断言形状**的条数下限：
# `combinations.count` 与 `Set(combinations).count` 各一条（少一条 = 少一种「重复组合」判法）。
AXIS_COMBO_ASSERTIONS = 2


# ---- 判据 I（星云皮肤：存在 / 开关 / 三层表面；队列 L-155）的台账（每条都带理由）----------------
NEBULA_SWIFT = "App/Views/NebulaBackground.swift"          # 绘制侧（Canvas + 三层强度）
NEBULA_PREF_SWIFT = "Core/NebulaSkinPreference.swift"      # 规则的唯一出处（键 / 缺省 / 读法 / 生效条件）
MAIN_WINDOW_SWIFT = "App/Views/MainWindow.swift"           # 侧栏与内容区两层落点的所在
LOWER_PANE_SWIFT = "App/Views/LowerPaneView.swift"         # 下方面板那一层落点的所在
NEBULA_PROBE_SWIFT = "TestsUISnapshot/NebulaSkinProbeTests.swift"   # 像素级证据（三张主角 + 对照件）
NEBULA_TESTS_SWIFT = "Tests/NebulaSkinPreferenceTests.swift"        # 规则的单测（默认开 / 重开仍关）
PROBE_RUNNER_SH = "Scripts/run-manual-verification-probes.sh"       # 探针的跑法（FILTER 是唯一入口）
NEBULA_TOGGLE_KEY = "ui.nebulaSkin"                        # 落盘键（键名就是契约）
NEBULA_KEY_DECL = f'public static let key = "{NEBULA_TOGGLE_KEY}"'
# 读法的**实体**（逐字）：`bool(forKey:)` 对"从未设过"返回 false ⇒ 缺省值被静默改成关。
NEBULA_READ_BODY = "defaults.object(forKey: key) as? Bool ?? defaultEnabled"
# 生效条件的**实体**（逐字）：两个条件缺一不可（少前半 = 别的主题也长星星；少后半 = 关不掉）。
# 2026-10-16（T-20261016-201）泛化：前半从写死的 `theme == .stardust` 改成**主题自己声明**
# （`DesignTheme.paintsNebula`）—— 「哪些主题有星云」不再钉死在这一个函数里，新主题改的是它的值表。
NEBULA_EFFECT_BODY = "theme.paintsNebula && isSkinEnabled"
# 绘制侧只许**调用**那一条规则（判据 I ② 认的是这串标记）。
NEBULA_EFFECT_CALL = "NebulaSkinPreference.paintsNebula("
NEBULA_DEFAULT_DECL = "public static let defaultEnabled = true"
# 三层表面各自的落点（层名 → 应当出现的文件；字面量逐字）。
# 少了那一层没皮肤；多了那一层重复铺（先铺表面再叠星云，铺两遍是两倍的绘制）。
NEBULA_LAYER_SITES = {
    "侧栏": (MAIN_WINDOW_SWIFT, "NebulaSurface(surface: .sidebar, layer: .sidebar)"),
    "内容区": (MAIN_WINDOW_SWIFT, "NebulaBackground(layer: .content)"),
    "下方面板": (LOWER_PANE_SWIFT, "NebulaBackground(layer: .panel)"),
}
# 界面入口（外观面板）：绑唯一写入口 + 只在**声明要星云的主题**下露面。
NEBULA_SHEET_BINDING = "designTheme.setNebulaSkinEnabled($0)"
NEBULA_SHEET_CONDITION = "if designTheme.theme.paintsNebula {"
# 像素探针里必须在场的标记（三张主角 + 比对口子 + 阈值出处）。
NEBULA_PROBE_MARKERS = (
    "nebula-skin-", "stardust-on", "stardust-off", "techblue-on",
    "UISnapshot.differingPixels", "minimumPaintedPixels",
)
# 规则单测里必须是命名的用例（少一条即红）—— 判据只认"这一条存在"，跑绿由 `swift test` 保证。
NEBULA_TEST_CASES = {
    "testNeverSetMeansEnabled": "从未设过 ⇒ 开（新装直接看到皮肤）",
    "testReadRuleDiffersFromBoolForKeyOnAFreshStore": "读法不许退回 bool(forKey:)",
    "testOffIsPersistedAndSurvivesReopen": "关掉之后重开仍是关",
    "testPaintsNebulaTruthTableOverEveryThemeAndSwitchState": "生效条件真值表（4 主题 × 2 态）",
}
MIN_NEBULA_SITES = 22   # 判据 I：判点处数下限（空跑防护）

# ---- 判据 I ② 的扫描面（2026-10-13 按 `T-20261010-036` 从 4 根扩到**入库源码面**）-------------
# 由头（原单现场）：判据 I ② 自称「键字面量**全仓**只许一处」，而实现面只有 Core/App/Platform/CLI
# 四根（338/586 = 58%）—— 面外**真有一份**同形字面量（`Tests/NebulaSkinPreferenceTests.swift:44`），
# 而那一份正是判据 I ⑥ 自己要它存在的「规则单测」：判据手里拿着它自己看不见的第二份。
# 口径：面 = 下表十根（每条带理由）+ 仓根 `*.swift`；`Vendor/` 与点目录**显式排除**并写明理由；
# 根表 / 面内文件数 / 允许持有点三样都上账 `Scripts/design-themes-key-baseline.json`（增减都报红）。
SWIFT_FACE_ROOTS = {
    "Core": "产品核心层（值表 / 令牌 / 偏好规则）",
    "App": "界面层（外观面板 / 星云绘制 / 三层落点）",
    "Platform": "平台适配层",
    "CLI": "命令行入口",
    "Plugins": "插件源码（Notes）",
    "Tests": "Core 单测（**含「断言键值 = 契约」的正当第二份**）",
    "TestsPlatform": "平台面单测",
    "TestsUISnapshot": "界面快照探针",
    "Scripts": "门禁脚本自身（脚本要点名那个键才判得动）",
    "Tools": "工具 target（LicenseTool）",
}
SWIFT_FACE_ROOT_GLOB = True   # 仓根 `*.swift`（`Package.swift`）也在面内
SWIFT_FACE_EXCLUDED = {
    "Vendor": "第三方代码（不由我们维护 —— 与同族判据对 `Vendor/` 的判定同口径）",
    "点目录（`.git` / `.worktrees` 等）": "同一份源码的副本，不是「第二处实现」",
}
PACKAGE_SWIFT = "Package.swift"                              # 判据面与它逐条对账（`path:` / `sources:`）
# 面里有、但**不是**任何 target 源码目录的根（每条必须带理由；理由为空即红）。
# 由头（原单 `T-20261010-068` ㈥）：面原先与 `Package.swift` 完全没有对账 —— `Tools/LicenseTool/`
# （`Package.swift` 的**生产 target**）落在面外，在那里抄一份键字面量判据看不见。
FACE_ROOTS_NOT_A_TARGET = {
    "Scripts": "门禁脚本自身（不是 SwiftPM target —— 脚本要点名那个键才判得动）",
}

KEY_BASELINE = "Scripts/design-themes-key-baseline.json"   # 面对账台账（根表 / 文件数 / 允许持有点）
KEY_LITERAL = f'"{NEBULA_TOGGLE_KEY}"'                     # 要唯一化的那个字面量（带引号）

# ---- 台账式常量（每条都带理由；理由为空即红）-------------------------------------------------

# 主题 id 的**声明顺序**（= `Core/DesignTheme.swift` 里 case 的书写顺序；与 Linux 侧同名）。
# 2026-10-01（T-20261001-031）：加第 4 个「星空紫」（需求提出者要的「比科技蓝更梦幻」那一档）。
# 2026-10-16（T-20261016-201）：加第 5 个「深空苍穹」（交付件 `Docs/design/theme-deepspace-spec.html`；
#   人类主人令「做一个深空苍穹主题」）—— 声明顺序把它排在**最后**（case 写在星空紫之后）。
# 认的是**声明顺序**，不是界面顺序 —— 界面顺序（`DesignTheme.all`，科技蓝打头）由判据 A 另判。
THEME_IDS = ["tech-blue", "bean-green", "rose-gold", "stardust", "deep-space"]
# 界面**列出**的顺序（= `Core/DesignTheme.all` 的书写顺序，科技蓝打头）—— 判据 A 逐格对账。
# 由头（原单 `T-20261010-068` ㈡）：`Core/DesignTheme.swift:188` 的台账注释原文写着「界面顺序
# （`DesignTheme.all`，科技蓝打头）由判据 A **另判**」，而判据 A 原先只数个数（顺序倒置仍绿）
# ⇒ 判据与自述相抵。改这张表 = 改用户看到的主题次序，须同时改三书 §9 与台账。
# 2026-10-16：深空苍穹插在星空紫之后（两个「深」主题相邻）。
THEME_UI_ORDER = ["techBlue", "stardust", "deepSpace", "beanGreen", "roseGold"]
# 枚举 case 名（= 声明顺序）：`ThemePalette.of(_:)` 的每一支必须取**同名**值表。
THEME_CASE_NAMES = ["techBlue", "beanGreen", "roseGold", "stardust", "deepSpace"]
MIN_THEME_SET_SITES = 15  # 判据 A 的判点**条目数**下限（5 声明 + 5 界面顺序 + 5 逐格映射；削即红）

THEME_NAMES_ZH = {
    "tech-blue": "科技蓝",
    "bean-green": "豆芽绿",
    "rose-gold": "玫瑰金",
    "stardust": "星空紫",
    "deep-space": "深空苍穹",
}
# 「推导草案」**只有** Linux 侧实际色值未到的那两个（2026-10-01 由「不是科技蓝就算推导」改成点名）：
# 星空紫的值来自需求提出者给的观感（NASA 韦伯「宇宙悬崖」NGC 3324 取色）⇒ 是实际值，
# 界面上标「推导草案」就是说假话；新增主题必须在这里显式决定自己算不算推导。
DERIVED_THEME_IDS = ["bean-green", "rose-gold"]
# 值表必须有的字段：18 个色角色 + 发丝线两个参数。
COLOR_ROLES = (
    "window", "sidebar", "content", "panel", "raised",
    "textBright", "textPrimary", "textSecondary", "textTertiary", "textDisabled",
    "success", "warning", "danger",
    "accent", "accentGlow", "accentSoft", "accentTeal", "accentWarm",
)
HAIRLINE_FIELDS = ("hairlineLight", "hairlineDarkAlpha")
# 注意：这里的名字是**值表字段名**（`ThemePalette` 的字段），不是枚举 case 名。
WEAK_ROLES = ("textPrimary", "textSecondary")          # 正文：≥4.5
AUX_ROLES = ("textTertiary",)                          # 辅助：≥3.0
LINK_ROLES = ("accentGlow", "accentTeal", "accentWarm")  # 会落到文字 / 链接上：≥4.5
ICON_ROLES = ("accent", "accentSoft")                   # 只做图标线：≥3.0

# 语法六档 → 家族角色（判据 D 的对照表；改这张表要同时改 `Core/DesignTokens.swift` 与文档）。
SYNTAX_BINDING = {
    "keyword": "accentGlow",
    "identifier": "primary",
    "string": "warm",
    "number": "teal",
    "function": "accent",
    "comment": "tertiary",
}

# 门槛（与 `Core/ColorContrast.Threshold` 同值；这里**独立实现**，所以必须各写一份）。
BODY_TEXT = 4.5
STRONG_TEXT = 7.0
LARGE_TEXT = 3.0
COMPONENT = 3.0
SURFACE_SEPARATION = 0.02

MIN_THEMES = 5          # 判据 F：主题数下限
MIN_ROLES = 20          # 判据 F：每套表的字段数下限
MIN_CHECKS = 300        # 判据 F：实测对数下限（5 主题 × 2 态 × 每个角色若干条 ⇒ 实测 310）

# ---- 判据 G（界面入口）的对照表（每条都带理由）------------------------------------------------
# 主题候选行必须画出的**三个真实场景** —— 缺一个就退化成"只给一块色卡"（用户只能凭想象选）。
# 理由与 `AccentOptionRow` 同源（FR-STD-WS-UI-009 原文：选色不该靠想象），但主题要**多一层**：
# 预览得画在该主题**自己**的表面上（见 `THEME_SURFACE_MARKER`）。
SCENE_MARKERS = {
    "选中行": ".fill(tintColor)",
    "主按钮": ".foregroundStyle(.white)",
    "焦点环": ".strokeBorder(accentColor, lineWidth: 1.5)",
}
# 预览的底必须来自**该主题的值表**（不是当前界面的表面）——
# 少了它，"豆芽绿 / 玫瑰金 的底"在界面上一眼都看不到。
THEME_SURFACE_MARKER = "palette.content"
# 「推导草案」这句话在界面上的落点：行里要画出这个键，语言表里要有这句中文原话。
DERIVED_MARKER_KEY = ".appearanceDesignThemeDerived"
DERIVED_LKEY = "appearanceDesignThemeDerived"
MIN_PANEL_LINES = 400   # 判据 G：面板文件行数下限（被掏空即红）
MIN_ROW_CHARS = 1200    # 判据 G：主题行源码字符下限（被掏空即红）
MIN_ENTRY_SITES = 12    # 判据 G：界面入口的判点处数下限（空跑防护）

PALETTE_BLOCK = re.compile(r"public static let (\w+) = ThemePalette\((.*?)\n    \)", re.S)
THEME_CASE = re.compile(r'^\s*case (\w+) = "([a-z-]+)"', re.M)
COLOR_FIELD = re.compile(r"(\w+): ThemeColor\(light: (0x[0-9A-Fa-f]{6}), dark: (0x[0-9A-Fa-f]{6})\)")
HEX_FIELD = re.compile(r"(hairlineLight): (0x[0-9A-Fa-f]{6})")
ALPHA_FIELD = re.compile(r"(hairlineDarkAlpha): ([0-9.]+)")


class Issue:
    def __init__(self, where: str, reason: str):
        self.where = where
        self.reason = reason

    def __str__(self) -> str:
        return f"{self.where}: {self.reason}"


# ---------------------------------------------------------------- WCAG（本脚本自己的实现）

def _linear(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def luminance(hex_value: int) -> float:
    red = ((hex_value >> 16) & 0xFF) / 255
    green = ((hex_value >> 8) & 0xFF) / 255
    blue = (hex_value & 0xFF) / 255
    return 0.2126 * _linear(red) + 0.7152 * _linear(green) + 0.0722 * _linear(blue)


def ratio(lhs: int, rhs: int) -> float:
    a, b = luminance(lhs), luminance(rhs)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def distance(lhs: int, rhs: int) -> float:
    parts = []
    for shift in (16, 8, 0):
        parts.append((((lhs >> shift) & 0xFF) - ((rhs >> shift) & 0xFF)) / 255)
    return math.sqrt(sum(part * part for part in parts))


# ---------------------------------------------------------------- 解析

def parse_palettes(text: str) -> dict[str, dict]:
    """从 `Core/DesignTheme.swift` 解析出每套值表：{表名: {字段: 值}}。"""
    palettes: dict[str, dict] = {}
    for name, body in PALETTE_BLOCK.findall(text):
        entry: dict = {"_colors": {}, "_hairlineLight": None, "_hairlineAlpha": None}
        for role, light, dark in COLOR_FIELD.findall(body):
            entry["_colors"][role] = (int(light, 16), int(dark, 16))
        for role, value in HEX_FIELD.findall(body):
            entry["_hairlineLight"] = int(value, 16)
        for role, value in ALPHA_FIELD.findall(body):
            entry["_hairlineAlpha"] = float(value)
        id_match = re.search(r"id: \.(\w+)", body)
        entry["_id"] = id_match.group(1) if id_match else None
        palettes[name] = entry
    return palettes


def theme_swift_text(root: pathlib.Path) -> str:
    return (root / THEMES_SWIFT).read_text(encoding="utf-8")


def palette_for(root: pathlib.Path, theme_id: str) -> dict | None:
    """按主题 id 找它对应的值表（通过 `id: .xxx` 与 case 名的映射）。"""
    text = theme_swift_text(root)
    case_names = {name: ident for name, ident in THEME_CASE.findall(text)}
    ident = None
    for name, ident_value in case_names.items():
        if ident_value == theme_id:
            ident = name
            break
    if ident is None:
        return None
    palettes = parse_palettes(text)
    for paletted in palettes.values():
        if paletted["_id"] == ident:
            return paletted
    return None


def theme_ids_in_source(root: pathlib.Path) -> list[str]:
    return [ident for _, ident in THEME_CASE.findall(theme_swift_text(root))]


def _strip_comments(text: str) -> str:
    """剥掉注释（`//` 行注释与 `/* */` 块注释），**字符串字面量里的一律不算**。

    为什么必须有这一步：`NebulaBackground` 的说明注释里**原文就写着**
    「在这里再写一遍 `== .stardust && …` 只会让两处慢慢分叉」—— 不剥注释，
    判据会把这句**说明文字**当成"第二处实现"而误判（第 154 轮实测）。

    2026-10-13（合册 `T-20261013-027` · 原单 `T-20261010-068` 第 ⑥ 条）之前，这里只按
    `line.split("//", 1)[0]` 处理行注释、且**不看字符串**，两个后果都实测过：① 判据 H 的串轴检查
    被一句「注意：这里绝不许出现 `appearance.mode`」的说明注释顶成红（假阳）；② 块注释里的说明
    又完全不剥（假绿）。⇒ 改为逐字符扫：行注释与块注释都剥，且**只在字符串外认注释起点**
    （本仓有 14 处 `/*` 落在字符串里，如 `head.hasPrefix("/*")` —— 当成块注释起点会把后面的真代码
    整段吞掉）。**边界（如实登记）**：字符串字面量本身**保留**（判定物都是代码形状；写在字符串里的
    文本不构成本判据的实现或断言，属登记过的边界，不是漏判）。
    """
    out: list[str] = []
    i, n = 0, len(text)
    in_line = False
    block_depth = 0
    in_string = False
    quote = ""
    while i < n:
        char = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_string:
            out.append(char)
            if char == "\\" and nxt:
                out.append(nxt)
                i += 2
                continue
            if char == quote:
                in_string = False
            i += 1
            continue
        if in_line:
            if char == "\n":
                in_line = False
                out.append(char)
            i += 1
            continue
        if block_depth:
            if char == "*" and nxt == "/":
                block_depth -= 1
                i += 2
                continue
            if char == "/" and nxt == "*":
                block_depth += 1
                i += 2
                continue
            if char == "\n":
                out.append(char)
            i += 1
            continue
        if char == "/" and nxt == "/":
            in_line = True
            i += 2
            continue
        if char == "/" and nxt == "*":
            block_depth = 1
            i += 2
            continue
        if char in "\"'":
            in_string = True
            quote = char
            out.append(char)
            i += 1
            continue
        out.append(char)
        i += 1
    return "".join(out)


def _type_slice(text: str, marker: str, closing: str = "\n}") -> str | None:
    """取**一段声明**的源码切片（从 `marker` 到它自己的收尾行）。

    判据 G 要问的是「这一段里有没有画出那三个场景」，就必须只看**这一段**：
    拿整个文件去 `in`，等于"别处写过一句也算"（第 77 轮自检例 ⑨/⑮ 两次栽在这上面）。
    类型（`struct … {`）以列 0 的 `}` 收尾，函数以缩进四格的 `}` 收尾。
    """
    start = text.find(marker)
    if start < 0:
        return None
    end = text.find(closing, start)
    if end < 0:
        return None
    return text[start:end]


# ---------------------------------------------------------------- 判据 A

def check_theme_set(root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    ids = theme_ids_in_source(root)
    if ids != THEME_IDS:
        issues.append(Issue(THEMES_SWIFT, f"主题集是 {ids}，台账登记的是 {THEME_IDS}"
                                         f" —— 加减主题要同时改台账与三书（§9）"))
    text = theme_swift_text(root)
    all_match = re.search(r"public static let all: \[DesignTheme\] = \[(.*?)\]", text, re.S)
    if not all_match:
        issues.append(Issue(THEMES_SWIFT, "找不到 `DesignTheme.all` —— 判据 A 的前提没了"))
        return issues
    listed = re.findall(r"\.(\w+)", all_match.group(1))
    if listed != THEME_UI_ORDER:
        issues.append(Issue(THEMES_SWIFT, f"`DesignTheme.all` 是 {listed}，台账登记的界面顺序是"
                                         f" {THEME_UI_ORDER} —— 判的是**身份与顺序**：列漏一个用户选不到，"
                                         f"顺序变了用户看到的次序就变了（改台账要同时改三书 §9）"))
    of_match = re.search(r"public static func of\(_ theme: DesignTheme\) -> ThemePalette \{(.*?)\n    \}",
                         text, re.S)
    if not of_match:
        issues.append(Issue(THEMES_SWIFT, "找不到 `ThemePalette.of(_:)` —— 判据 A 的前提没了"))
    else:
        pairs = dict(re.findall(r"case \.(\w+): return \.(\w+)", of_match.group(1)))
        for case_name in THEME_CASE_NAMES:
            if pairs.get(case_name) != case_name:
                issues.append(Issue(THEMES_SWIFT,
                                    f"`ThemePalette.of(_:)` 里 `.{case_name}` 取的是"
                                    f" `.{pairs.get(case_name)}` 的值表 —— 取错表 = 那个主题整屏"
                                    f"用的是别人的颜色"))
        if len(pairs) != len(THEME_IDS):
            issues.append(Issue(THEMES_SWIFT, f"`ThemePalette.of(_:)` 只覆盖 {len(pairs)} 个主题"
                                             f"（应为 {len(THEME_IDS)}）—— 少的那一个取不到值"))
    sites = len(ids) + len(listed) + len(pairs)      # 声明集 + 界面顺序 + 逐格映射（实读条数）
    if sites < MIN_THEME_SET_SITES:
        issues.append(Issue(THEMES_SWIFT, f"判据 A 只判到 {sites} 个条目（下限 {MIN_THEME_SET_SITES}）"
                                         f" —— 判点被削过，不许通过"))
    return issues


# ---------------------------------------------------------------- 判据 B

def check_palette_shape(root: pathlib.Path) -> tuple[list[Issue], int]:
    issues: list[Issue] = []
    palettes = parse_palettes(theme_swift_text(root))
    if len(palettes) < MIN_THEMES:
        issues.append(Issue(THEMES_SWIFT, f"只解析到 {len(palettes)} 套值表（下限 {MIN_THEMES}）"
                                         f" —— 解析面被削过或表被删了，不许通过"))
        return issues, 0
    role_total = 0
    for name, palette in palettes.items():
        missing = [role for role in COLOR_ROLES if role not in palette["_colors"]]
        if missing:
            issues.append(Issue(THEMES_SWIFT, f"{name} 少了 {len(missing)} 个色角色：{missing}"
                                             f" —— 角色不齐就是「这一档用了别的主题的颜色」"))
        if palette["_hairlineLight"] is None:
            issues.append(Issue(THEMES_SWIFT, f"{name} 少了发丝线浅色实色"))
        if palette["_hairlineAlpha"] is None:
            issues.append(Issue(THEMES_SWIFT, f"{name} 少了发丝线深色透明度"))
        role_total += len(palette["_colors"]) + (1 if palette["_hairlineLight"] is not None else 0) \
            + (1 if palette["_hairlineAlpha"] is not None else 0)
        if len(palette["_colors"]) < MIN_ROLES - len(HAIRLINE_FIELDS):
            issues.append(Issue(THEMES_SWIFT, f"{name} 的色角色只有 {len(palette['_colors'])} 个"
                                             f"（下限 {MIN_ROLES - len(HAIRLINE_FIELDS)}）"))
    return issues, role_total


# ---------------------------------------------------------------- 判据 C

def check_thresholds(root: pathlib.Path) -> tuple[list[Issue], int]:
    issues: list[Issue] = []
    checks = 0
    for theme_id in THEME_IDS:
        palette = palette_for(root, theme_id)
        if palette is None:
            issues.append(Issue(THEMES_SWIFT, f"主题 {theme_id} 找不到对应的值表"))
            continue
        colors = palette["_colors"]
        hairline_light = palette["_hairlineLight"]
        hairline_alpha = palette["_hairlineAlpha"]
        if hairline_light is None or hairline_alpha is None:
            issues.append(Issue(THEMES_SWIFT, f"{theme_id} 的发丝线参数不全，无法复算"))
            continue
        for is_dark in (True, False):
            state = "深色" if is_dark else "浅色"
            index = 1 if is_dark else 0

            def c(role: str) -> int:
                return colors[role][index]

            content = c("content")

            def judge(label: str, value: float, floor: float, extra_fail: bool = False) -> None:
                nonlocal checks
                checks += 1
                if value < floor or extra_fail:
                    issues.append(Issue(
                        f"{THEMES_SWIFT} ({theme_id}/{state})",
                        f"{label} 实测 {value:.2f}，门槛 {floor}"
                    ))

            for role in WEAK_ROLES:
                judge(f"正文 {role}", ratio(c(role), content), BODY_TEXT)
            for role in AUX_ROLES:
                judge(f"辅助 {role}", ratio(c(role), content), LARGE_TEXT)
            bright_ratio = ratio(c("textBright"), content)
            judge("强对比 textBright", bright_ratio, STRONG_TEXT)
            checks += 1
            if bright_ratio <= ratio(c("textPrimary"), content):
                issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/{state})",
                                    "textBright 不比 textPrimary 强 —— bright 这个名字就没有意义"))
            disabled_ratio = ratio(c("textDisabled"), content)
            checks += 1
            if disabled_ratio >= ratio(c("textTertiary"), content):
                issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/{state})",
                                    f"禁用态 {disabled_ratio:.2f} 不淡于辅助色"
                                    f" {ratio(c('textTertiary'), content):.2f}"))
            judge("禁用态下限", disabled_ratio, 1.5)

            # 表面：距离 + 顺序
            for role in ("sidebar", "panel", "window"):
                checks += 1
                if distance(content, c(role)) < SURFACE_SEPARATION:
                    issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/{state})",
                                        f"内容区与 {role} 太接近（距离 {distance(content, c(role)):.3f}，"
                                        f"门槛 {SURFACE_SEPARATION}）"))
            order = ["window", "sidebar", "content", "panel", "raised"]
            luminances = [luminance(c(role)) for role in order]
            checks += 1
            if is_dark:
                for previous, current, a, b in zip(luminances, luminances[1:], order, order[1:]):
                    if not current > previous:
                        issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/深色)",
                                            f"{b} 不比 {a} 亮（深色靠明度递增表达层次）"))
                        break
            else:
                for role, value in zip(order, luminances):
                    if role != "content" and value > luminances[order.index("content")]:
                        issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/浅色)",
                                            f"{role} 比 content 还亮（浅色不变式）"))
                        break

            # 状态色
            for role in ("success", "warning", "danger"):
                for background in ("content", "panel"):
                    judge(f"状态 {role} on {background}", ratio(c(role), c(background)), COMPONENT)

            # 强调家族（基准 = 深色对 window、浅色对白）
            base = c("window") if is_dark else 0xFFFFFF
            for role in LINK_ROLES:
                judge(f"强调家族 {role}（文字 / 链接）", ratio(c(role), base), BODY_TEXT)
            for role in ICON_ROLES:
                judge(f"强调家族 {role}（图标线）", ratio(c(role), base), COMPONENT)

            # 语法六档（按角色取家族值）
            syntax_values = {
                "keyword": c("accentGlow"), "identifier": c("textPrimary"), "string": c("accentWarm"),
                "number": c("accentTeal"), "function": c("accent"), "comment": c("textTertiary"),
            }
            checks += 1
            if len(set(syntax_values.values())) != len(syntax_values):
                issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/{state})", "语法六档有重复值"))
            for role, value in syntax_values.items():
                floor = LARGE_TEXT if role == "comment" else BODY_TEXT
                judge(f"语法 {role}", ratio(value, content), floor)

            # 发丝线
            checks += 1
            if not is_dark:
                if luminance(hairline_light) >= luminance(content):
                    issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/浅色)",
                                        "浅色发丝线不比 content 暗（白的线在白底上等于没有）"))
            checks += 1
            if not 0.05 <= hairline_alpha <= 0.20:
                issues.append(Issue(f"{THEMES_SWIFT} ({theme_id})",
                                    f"深色发丝线透明度 {hairline_alpha} 不在 0.05~0.20 的区间里"))
    return issues, checks


# ---------------------------------------------------------------- 判据 D

def check_syntax_binding(root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    text = (root / TOKENS_SWIFT).read_text(encoding="utf-8")
    block = re.search(r"public func color\(in theme: DesignTheme\) -> ThemeColor \{\n        switch self \{\n(.*?)\n        \}",
                      text, re.S)
    if block is None:
        issues.append(Issue(TOKENS_SWIFT, "语法六档的映射块找不到（判据 D 的前提没了）"))
        return issues
    # 判定物 = **`switch` 块内的非注释代码**（原单 `T-20261010-068` ㈠）：先前拿整份文件去
    # `re.findall`（`block` 的捕获组从未被用过）⇒ 六条真映射**整行注释掉**仍绿（判据照打
    # 「6 条映射对账」），映射搬到块外也照样绿。
    body = _strip_comments(block.group(1))
    lines = re.findall(r"case \.(\w+): return (\w+)\.(\w+)\.color\(in: theme\)", body)
    mapping = {tone: role for tone, family, role in lines}
    if len(mapping) != len(SYNTAX_BINDING):
        issues.append(Issue(TOKENS_SWIFT, f"`switch` 块里只有 {len(mapping)} 条映射"
                                         f"（应为 {len(SYNTAX_BINDING)}）—— 少的那几档与家族脱钩"))
    for tone, role in SYNTAX_BINDING.items():
        if mapping.get(tone) != role:
            issues.append(Issue(TOKENS_SWIFT,
                                f"语法 {tone} 应挂 {role}，实测 {mapping.get(tone)}"
                                f" —— 六档与家族脱钩就是留了一个孤立的语法色"))
    return issues


# ---------------------------------------------------------------- 判据 E

def check_names_and_pending(root: pathlib.Path) -> tuple[list[Issue], int]:
    issues: list[Issue] = []
    sites = 0
    localization = (root / LOCALIZATION_SWIFT).read_text(encoding="utf-8")
    for theme_id, chinese in THEME_NAMES_ZH.items():
        key = "designTheme" + "".join(part.capitalize() for part in theme_id.split("-"))
        match = re.search(rf"\.{key}: \[\.simplifiedChinese: \"([^\"]+)\"", localization)
        sites += 1
        if not match:
            issues.append(Issue(LOCALIZATION_SWIFT, f"找不到主题名键 .{key} 的中文条目"))
        elif match.group(1) != chinese:
            issues.append(Issue(LOCALIZATION_SWIFT,
                                f"主题名 {theme_id} 的中文是「{match.group(1)}」，应为「{chinese}」"
                                f" —— 三个名字是 Linux 侧给的名，不许改"))
    doc = (root / DESIGN_DOC).read_text(encoding="utf-8") if (root / DESIGN_DOC).exists() else ""
    for chinese in THEME_NAMES_ZH.values():
        sites += 1
        # 严格认**主题表里的那一行**（`| 序号 | 主题名 | …`）：正文别处提到这个名字不算
        # —— 否则"表被改坏了、正文还提过"就会静默放过（本判据的自检例 ⑨ 就是这么抓出来的）。
        if not re.search(rf"^\|\s*\d+\s*\|\s*{re.escape(chinese)}\s*\|", doc, re.M):
            issues.append(Issue(DESIGN_DOC, f"§9 的主题表里找不到「{chinese}」这一行"
                                            f" —— 名对齐是判据 E 的一半"))
    # 推导主题 ↔ 待值登记（成对）：有推导主题就必须 ① 值表旁标着「推导」② 发布计划还登记着那件待值
    theme_text = theme_swift_text(root)
    derived = DERIVED_THEME_IDS
    release = (root / RELEASE_PLAN).read_text(encoding="utf-8") if (root / RELEASE_PLAN).exists() else ""
    for theme_id in derived:
        palette_name = "".join(
            part if index == 0 else part.capitalize() for index, part in enumerate(theme_id.split("-"))
        )
        marker = f"public static let {palette_name} = ThemePalette("
        position = theme_text.find(marker)
        sites += 1
        if position < 0:
            issues.append(Issue(THEMES_SWIFT, f"找不到主题 {theme_id} 的值表（{palette_name}）"))
            continue
        # 认**紧挨着声明的那一段注释块**（抬头文件注释里到处都写着"推导"，
        # 拿它当证据等于没判 —— 本判据的自检例 ⑮ 就是这么抓出来的）。
        header_lines: list[str] = []
        for line in reversed(theme_text[:position].splitlines()):
            if line.strip().startswith("//") or not line.strip():
                header_lines.append(line)
            else:
                break
        preamble = "\n".join(header_lines)
        # 标记词取 §9.1 的原话「推导草案」：只认"推导"两个字太松 —— 紧挨着的说明段里
        # 本来就会写"推导口径"，那样抹掉标记行也照样绿（自检例 ⑮ 的另一半就这么抓出来的）。
        if "推导草案" not in preamble:
            issues.append(Issue(THEMES_SWIFT,
                                f"{palette_name} 的值表旁没有「推导草案」标记 —— "
                                f"待值期间推导值必须逐块标出来（不许当实际值卖）"))
        sites += 1
        if not re.search(r"豆芽绿 / 玫瑰金 色值（Linux 侧）", release):
            issues.append(Issue(RELEASE_PLAN,
                                "有推导主题（推导值），但发布计划的待输入表里没有登记那件待值"
                                " —— 推导值不许静默变成实际值"))
    return issues, sites


# ---------------------------------------------------------------- 判据 G

def check_ui_entry(root: pathlib.Path) -> tuple[list[Issue], int]:
    """界面入口：主题真的能被选到、每主题三个真实场景、推导值如实标注、强调色入口不许消失。"""
    issues: list[Issue] = []
    sites = 0
    panel_path = root / APPEARANCE_SWIFT
    if not panel_path.exists():
        return [Issue(APPEARANCE_SWIFT, "「外观」面板文件不存在 —— 主题入口无处落地")], sites
    panel_raw = panel_path.read_text(encoding="utf-8")
    line_count = len(panel_raw.splitlines())
    # 判定物一律**先剥注释**（原单 `T-20261010-068` ㈢：先前是裸子串 —— 把真用法改成注释行，
    # 判据照样打「界面入口已接上」）。
    panel = _strip_comments(panel_raw)
    sites += 1
    if line_count < MIN_PANEL_LINES:
        issues.append(Issue(APPEARANCE_SWIFT, f"面板只有 {line_count} 行（下限 {MIN_PANEL_LINES}）"
                                              f" —— 扫描面被削过，不许通过"))

    # ① 入口：主题集必须被**逐个列出**（用户在面板上选得到），且选中走 `select(_:)`
    #    —— 「换主题」这件事只有一个写入口，界面不许自己往 UserDefaults 里写。
    sites += 1
    if "ForEach(DesignTheme.all)" not in panel:
        issues.append(Issue(APPEARANCE_SWIFT, "面板里没有逐个列出主题集（`ForEach(DesignTheme.all)`）"
                                              " —— 三个主题里就有人选不到"))
    sites += 1
    if not re.search(r"designTheme\.select\(|DesignThemeManager\.shared\.select\(", panel):
        issues.append(Issue(APPEARANCE_SWIFT, "面板里没有走 `select(_:)` 的选主题调用点"
                                              " —— 换主题的唯一写入口在 `DesignThemeManager`（持久化也归它）"))
    sites += 1
    if "@ObservedObject" not in panel or "DesignThemeManager.shared" not in panel:
        issues.append(Issue(APPEARANCE_SWIFT, "面板没有订阅主题管理器 ⇒ 换了主题这块面板自己不跟着变"
                                              "（其它面板会因根视图重建而变，它是唯一漏网的那块）"))

    # ② 主题行：三个**真实场景**必须画在**该主题自己的表面**上
    row = _type_slice(panel, "struct DesignThemeOptionRow")
    sites += 1
    if row is None:
        issues.append(Issue(APPEARANCE_SWIFT, "找不到主题候选行（`struct DesignThemeOptionRow`）"
                                              " —— 主题列表画不出来"))
    else:
        if len(row) < MIN_ROW_CHARS:
            issues.append(Issue(APPEARANCE_SWIFT, f"主题行只有 {len(row)} 字符（下限 {MIN_ROW_CHARS}）"
                                                  f" —— 行被掏空，不许通过"))
        for label, marker in SCENE_MARKERS.items():
            sites += 1
            if marker not in row:
                issues.append(Issue(APPEARANCE_SWIFT,
                                    f"主题行里没有「{label}」这个真实场景（缺标记 `{marker}`）"
                                    f" —— 只给一块色卡，用户只能凭想象"))
        sites += 1
        if THEME_SURFACE_MARKER not in row:
            issues.append(Issue(APPEARANCE_SWIFT,
                                f"主题行的预览没有画在**该主题自己的表面**上（缺 `{THEME_SURFACE_MARKER}`）"
                                f" —— 那样看到的还是当前界面的底，换主题等于没预览"))
        sites += 1
        if not re.search(r"theme\.accent", row):
            issues.append(Issue(APPEARANCE_SWIFT, "主题行的三个场景没有用**该主题配套**的强调色"
                                                  "（`theme.accent`）—— 预览会拿当前主题的色去画别人的场景"))
        # ③ 推导值：逐条标注（不许把推导值当实际值卖）
        sites += 2
        if "isDerivedDraft" not in row:
            issues.append(Issue(APPEARANCE_SWIFT, "主题行没有问 `isDerivedDraft`"
                                                  " —— 待值的主题混在列表里、用户看不出来"))
        if DERIVED_MARKER_KEY not in row:
            issues.append(Issue(APPEARANCE_SWIFT, f"主题行没有画出推导标记（缺 `{DERIVED_MARKER_KEY}`）"))
        localization = (root / LOCALIZATION_SWIFT).read_text(encoding="utf-8")
        sites += 1
        if not re.search(rf"\.{DERIVED_LKEY}: \[\.simplifiedChinese: \"推导草案\"", localization):
            issues.append(Issue(LOCALIZATION_SWIFT, f"语言表里没有 `.{DERIVED_LKEY}` 的中文条目「推导草案」"
                                                    f" —— 界面上那句话无处可取"))

    # ④ 强调色入口不许**静默**消失（FR-STD-WS-UI-009 原文的「强调色可配置」是已交付能力）
    sites += 1
    if "AccentTheme.all" not in panel:
        issues.append(Issue(APPEARANCE_SWIFT, "面板不再逐个列出强调色（`AccentTheme.all`）"
                                              " —— 加了主题不等于可以删掉已交付的「强调色可配置」；"
                                              "真要收掉，得先改 SRS 与判据、并把理由写进台账"))

    # ⑤ 宿主覆盖（快照用）不落盘：拍一张图不许改用户偏好
    manager_path = root / THEME_MANAGER_SWIFT
    sites += 1
    if not manager_path.exists():
        issues.append(Issue(THEME_MANAGER_SWIFT, "主题运行时对象不存在"))
    else:
        manager = _strip_comments(manager_path.read_text(encoding="utf-8"))
        sites += 2
        if "func beginHostTheme(" not in manager or "func endHostTheme(" not in manager:
            issues.append(Issue(THEME_MANAGER_SWIFT, "没有宿主语境的进入 / 退出接口"
                                                    "（`beginHostTheme` / `endHostTheme`）—— 快照只能靠改用户偏好"))
        body = _type_slice(manager, "func beginHostTheme(", closing="\n    }") or ""
        sites += 1
        if "UserDefaults" in body:
            issues.append(Issue(THEME_MANAGER_SWIFT, "宿主语境覆盖里写了 `UserDefaults`"
                                                    " —— 拍一张快照就把用户的偏好改了（语言那条路定过这个口径）"))
        sites += 1
        if "UserDefaults.standard.set" not in manager:
            issues.append(Issue(THEME_MANAGER_SWIFT, "选主题没有落盘 （缺 `UserDefaults.standard.set`）"
                                                    " —— 重启就丢"))
    return issues, sites


def check_two_axis(root: pathlib.Path) -> tuple[list[Issue], int]:
    """外观的**两轴正交**：深浅轴（三态）× 配色轴（四主题）。队列 L-85。

    与判据 C / G 的分工：C 管「值对不对」（独立复算门槛）、G 管「配色轴的入口在不在界面上」，
    H 管的是**两轴之间**的规矩。四条都是「不做就是没做」：
      ① 深浅轴三态齐全 + 真值表逐格 + 未知值回落「跟随系统」；
      ② 两轴**互不读取**：两个落盘键分开，且各自的写盘点里不许出现对方的键
         —— 串轴的表现是「切了主题，深浅档被顺手重置」，用户看不出原因（串轴检查**先剥注释**：
         注释里提一句键名不算串轴；原单 `T-20261010-068` ㈣）；
      ③ 组合**可达**：3 态 × 2 系统态 × 5 主题 = 30 组，且「跟随系统」在系统深浅两态下都有值
         （只测一态时，另一态可能落在看不清的颜色上 —— 这正是「随系统主题」的全部风险）；组合数按**真断言形状**判（注释里写 30 不算 —— 原单 ㈤）；
      ④ 组合**到像素**：快照角像素（铺的 `window` 底）必须等于该主题该档的 `window` 值 ——
         要有取色口子、有断言、有**实测出来的**容差（PNG 往返偏移 ≤4 ⇒ 8；不是拍脑袋定的）。
    """
    issues: list[Issue] = []
    sites = 0
    # ① 深浅轴：三态齐全 + 真值表逐格 + 未知值回落
    pref_path = root / APPEARANCE_PREF_SWIFT
    if not pref_path.exists():
        issues.append(Issue(APPEARANCE_PREF_SWIFT, "深浅轴的类型不存在 —— 判据 H 的前提没了"))
        return issues, sites
    pref = pref_path.read_text(encoding="utf-8")

    states = re.findall(r"^\s*case (followSystem|alwaysDark|alwaysLight)\s*$", pref, re.M)
    sites += 1
    for state in AXIS_STATES:
        sites += 1
        if state not in states:
            issues.append(Issue(APPEARANCE_PREF_SWIFT, f"深浅轴少了一态 `{state}` —— 三态（跟随系统 /"
                                                     f" 总是深色 / 总是浅色）是 FR-STD-WS-UI-008 的原话"))
    sites += 1
    if len(states) != len(AXIS_STATES):
        issues.append(Issue(APPEARANCE_PREF_SWIFT,
                            f"深浅轴有 {len(states)} 态，台账是 {len(AXIS_STATES)} 态 —— 多出来的态没有判据管"))

    truth = _type_slice(pref, "func resolvesToDark(", closing="\n    }") or ""
    sites += 1
    if not truth:
        issues.append(Issue(APPEARANCE_PREF_SWIFT, "找不到真值表 `resolvesToDark` —— 判据 H 的前提没了"))
    for state, expected in AXIS_TRUTH_TABLE:
        sites += 1
        if not re.search(rf"case \.{state}: return {expected}", truth):
            issues.append(Issue(APPEARANCE_PREF_SWIFT,
                                f"真值表里 `{state}` 的落点不是 `{expected}` —— 这一格取不到值"))

    sites += 1
    if AXIS_FALLBACK not in pref:
        issues.append(Issue(APPEARANCE_PREF_SWIFT, f"未知偏好值没有回落「跟随系统」（找不到 `{AXIS_FALLBACK}`）"
                                                 f" —— 偏好文件被手改 / 版本降级后界面起不来"))
    sites += 1
    if "public var forcedDark: Bool?" not in pref:
        issues.append(Issue(APPEARANCE_PREF_SWIFT, "少了给 SwiftUI 的出口 `forcedDark` ——"
                                                 " 视图会自己再写一次 switch（写错就成「选跟随却锁死浅色」）"))
    # ② 两轴互不读取：键分开 + 各自的写盘点里不许出现对方的键
    themes_text = (root / THEMES_SWIFT).read_text(encoding="utf-8")
    sites += 2
    if f'public static let appKey = "{AXIS_APPEARANCE_KEY}"' not in pref:
        issues.append(Issue(APPEARANCE_PREF_SWIFT, f"深浅轴的落盘键不是 `{AXIS_APPEARANCE_KEY}`"
                                                  f" —— 键名是契约（改了等于让老用户的偏好失效）"))
    if f'public static let key = "{AXIS_THEME_KEY}"' not in themes_text:
        issues.append(Issue(THEMES_SWIFT, f"配色轴的落盘键不是 `{AXIS_THEME_KEY}`"))
    sites += 1
    if AXIS_APPEARANCE_KEY == AXIS_THEME_KEY:
        issues.append(Issue(APPEARANCE_PREF_SWIFT, "两轴共用一个落盘键 —— 切一轴必然重置另一轴"))

    manager_path = root / THEME_MANAGER_SWIFT
    sites += 1
    if not manager_path.exists():
        issues.append(Issue(THEME_MANAGER_SWIFT, "配色轴的运行时对象不存在"))
    else:
        # 判定物**先剥注释**（原单 `T-20261010-068` ㈣：先前是裸子串 —— 一句说明注释里提一下
        # `appearance.mode` 就把绿变红，而「两轴不许串」这句话本身也顶数）。
        manager = _strip_comments(manager_path.read_text(encoding="utf-8"))
        sites += 1
        for leak in (AXIS_APPEARANCE_KEY, AXIS_APPEARANCE_TERMINAL_KEY):
            if leak in manager:
                issues.append(Issue(THEME_MANAGER_SWIFT, f"配色轴的运行时对象里出现了深浅轴的键 `{leak}`"
                                                        f" —— 两轴串了：切主题会顺手改外观"))

    app_state_path = root / APP_STATE_SWIFT
    sites += 1
    if not app_state_path.exists():
        issues.append(Issue(APP_STATE_SWIFT, "根状态不存在 —— 判据 H 的前提没了"))
    else:
        app_state = _strip_comments(app_state_path.read_text(encoding="utf-8"))
        sites += 2
        if "Storage.appKey" not in app_state:
            issues.append(Issue(APP_STATE_SWIFT, "深浅档没有落盘（找不到 `AppearancePreference.Storage.appKey`）"
                                               " —— 重启就丢"))
        if AXIS_THEME_KEY in app_state:
            issues.append(Issue(APP_STATE_SWIFT, f"深浅档的写盘路径里出现了配色轴的键 `{AXIS_THEME_KEY}` —— 两轴串了"))
    # ③ 组合可达：3 态 × 2 系统态 × 5 主题 = 30 组（「跟随系统」两态都要走一遍）
    combos = len(AXIS_STATES) * len(AXIS_SYSTEM_STATES) * len(THEME_IDS)
    axes_tests_path = root / AXES_TESTS_SWIFT
    sites += 1
    if not axes_tests_path.exists():
        issues.append(Issue(AXES_TESTS_SWIFT, "两轴组合的单测不存在 —— 30 组组合无人走"))
    else:
        axes_tests = axes_tests_path.read_text(encoding="utf-8")
        for anchor, why in (
            ("AppearancePreference.allCases", "深浅轴的三态"),
            ("DesignTheme.all", "配色轴的五个主题"),
            ("systemStates", "系统当前深浅两态"),
        ):
            sites += 1
            if anchor not in axes_tests:
                issues.append(Issue(AXES_TESTS_SWIFT, f"组合枚举里少了{why}（找不到 `{anchor}`）—— 30 组走不全"))
        sites += 1
        # 组合数必须是**真断言形状**（原单 `T-20261010-068` ㈤：先前只认子串 `24`，而该文件
        # 三处**注释**里都写着「24」⇒ 两条真断言删掉仍绿）；判定物先剥注释。
        axes_code = _strip_comments(axes_tests)
        counted = re.findall(r"XCTAssertEqual\([^,\n]*\.count,\s*(\d+)", axes_code)
        combos_asserts = [value for value in counted if int(value) == combos]
        if not counted:
            issues.append(Issue(AXES_TESTS_SWIFT,
                                f"单测里没有「组合数」的真断言（形如 `XCTAssertEqual(….count, {combos})`）"
                                f" —— 注释里写着 {combos} 不算数"))
        elif len(combos_asserts) < AXIS_COMBO_ASSERTIONS:
            issues.append(Issue(AXES_TESTS_SWIFT,
                                f"组合数 {combos} 的真断言只有 {len(combos_asserts)} 条"
                                f"（下限 {AXIS_COMBO_ASSERTIONS}：`combinations.count` 与"
                                f" `Set(combinations).count` 各一条）—— 少一条就少了一种「重复组合」判法"))
        for name, why in AXIS_TEST_CASES.items():
            sites += 1
            if f"func {name}(" not in axes_tests:
                issues.append(Issue(AXES_TESTS_SWIFT, f"少了这条单测：`{name}`（{why}）"))

    # ④ 组合到像素：取色口子 + 角像素断言 + 实测容差
    kit_path = root / SNAPSHOT_KIT_SWIFT
    sites += 1
    if not kit_path.exists() or AXIS_PIXEL_HOOK not in kit_path.read_text(encoding="utf-8"):
        issues.append(Issue(SNAPSHOT_KIT_SWIFT, f"快照套件里没有取色口子（`{AXIS_PIXEL_HOOK}`）——"
                                              f" 「令牌到像素」只能靠人读图"))
    panels_path = root / PANELS_TESTS_SWIFT
    sites += 1
    if not panels_path.exists():
        issues.append(Issue(PANELS_TESTS_SWIFT, "面板快照用例不存在"))
    else:
        panels = panels_path.read_text(encoding="utf-8")
        sites += 2
        if AXIS_PIXEL_HOOK not in panels:
            issues.append(Issue(PANELS_TESTS_SWIFT, "主题面板快照用例没有取角像素 ——"
                                                  " 三个主题画成一样也照样绿"))
        if f"let encodeTolerance = {AXIS_PIXEL_TOLERANCE}" not in panels:
            issues.append(Issue(PANELS_TESTS_SWIFT, f"像素容差不是实测出来的那个值（{AXIS_PIXEL_TOLERANCE}）"
                                                  f" —— 容差拍大了等于没判"))
    probe_path = root / AXES_PROBE_SWIFT
    sites += 1
    if not probe_path.exists():
        issues.append(Issue(AXES_PROBE_SWIFT, "两轴的 App 侧探针不存在 ——「切一轴不重置另一轴」"
                                            " 只有在真管理器 + 真 UserDefaults 上才算数"))
    else:
        probe = probe_path.read_text(encoding="utf-8")
        sites += 1
        if AXIS_PROBE_CASE not in probe:
            issues.append(Issue(AXES_PROBE_SWIFT, f"探针里没有「{AXIS_PROBE_CASE}」这一条"))

    # ⑤ 文档登记：两轴的口径 + 两个落盘键（没有登记 = 下一个人不知道有两轴）
    doc_path = root / DESIGN_DOC
    sites += 1
    if not doc_path.exists():
        issues.append(Issue(DESIGN_DOC, "外观方案文档不存在"))
    else:
        doc = doc_path.read_text(encoding="utf-8")
        for needle, why in ((AXIS_DOC_HEADING, "两轴正交这一节"),
                            (AXIS_APPEARANCE_KEY, "深浅轴的落盘键"),
                            (AXIS_THEME_KEY, "配色轴的落盘键")):
            sites += 1
            if needle not in doc:
                issues.append(Issue(DESIGN_DOC, f"外观方案里没有登记{why}（找不到 `{needle}`）"))

    # ⑤ 面板必须**显示当前深浅档**（L-85 判据 ④）：双向绑定 = 既显示当下这一档、又改得动。
    #    只做「能改」是不够的 —— 用户打开面板要能看见现在是哪一档（跟系统还是被我锁死了）。
    appearance_path = root / APPEARANCE_SWIFT
    sites += 1
    if not appearance_path.exists():
        issues.append(Issue(APPEARANCE_SWIFT, "外观面板不存在 —— 判据 H 的前提没了"))
    else:
        appearance = appearance_path.read_text(encoding="utf-8")
        for anchor, why in (
            ("$appState.appearanceMode", "深浅档的双向绑定（绑上去才既显示又改得动）"),
            ("ForEach(AppearancePreference.allCases", "三档逐个列出（少一档 = 有个档位选不到）"),
        ):
            sites += 1
            if anchor not in appearance:
                issues.append(Issue(APPEARANCE_SWIFT, f"外观面板少了{why}（找不到 `{anchor}`）"))

    sites += 1
    if sites < MIN_AXIS_SITES:
        issues.append(Issue(APPEARANCE_PREF_SWIFT, f"判据 H 只判了 {sites} 处（下限 {MIN_AXIS_SITES}）"
                                                  f" —— 扫描面被削过，不许通过"))
    return issues, sites

# ---------------------------------------------------------------- 面对账（与 `Package.swift`）

def package_targets(root: pathlib.Path) -> list[dict]:
    """从 `Package.swift` **现读**出每个 target 的 `path:` 与 `sources:`（判据面逐条与它对账）。

    为什么要对账（原单 `T-20261010-068` ㈥ 现场）：判据 I ② 自称「键字面量**全仓**只许一处」，
    而面原先写死四根目录 —— `Tools/LicenseTool/`（`Package.swift` 的**生产 target**）落在面外，
    在那里抄一份键字面量判据看不见。**新 target / 新源码目录落在面外 ⇒ 判红**，面不许静默变窄。
    """
    lines = (root / PACKAGE_SWIFT).read_text(encoding="utf-8").splitlines()
    targets: list[dict] = []
    current: dict | None = None
    for line in lines:
        stripped = line.strip()
        if current is None:
            if re.match(r"^\.(?:executableTarget|target|testTarget)\(", stripped):
                current = {"path": None, "sources": []}
            continue
        if re.match(r"^\),?$", stripped):
            targets.append(current)
            current = None
            continue
        match = re.match(r'^path:\s*"([^"]+)"', stripped)
        if match:
            current["path"] = match.group(1)
        match = re.match(r"^sources:\s*\[(.*)\]", stripped)
        if match:
            current["sources"] = [item.strip().strip('"') for item in match.group(1).split(",")
                                  if item.strip()]
    return targets


def package_source_dirs(root: pathlib.Path) -> set[str]:
    """会被编进产品的 Swift 源码目录集合（有 `sources:` 的就是那一列，否则 `path` 本身）。

    `path: "."` = 仓根，那种 target 一定带 `sources:`（本仓两份都是）；真没有的话不进面，
    由 `face_vs_package_issues` 的「没有对应 target 的根」那一半兜住。
    """
    dirs: set[str] = set()
    for target in package_targets(root):
        if target["sources"]:
            dirs.update(target["sources"])
        elif target["path"] and target["path"] != ".":
            dirs.add(target["path"])
    return dirs


def host_source_dirs(root: pathlib.Path) -> list[str]:
    """**宿主界面 target**（含 `App` 的那份）的 `sources:` —— 判据 I ④ 的面。

    为什么不再写死 `App/`：那样 `Plugins/Notes/Views/`（2026-10-13 起编进宿主模块的笔记视图）
    整体在面外 —— 在那里再铺一层星云，判据看不见。读不出 ⇒ 空表，调用侧判红。
    """
    for target in package_targets(root):
        if "App" in target["sources"]:
            return list(target["sources"])
    return []


def face_vs_package_issues(source_dirs, face_roots, registered_non_target) -> list[Issue]:
    """判据面 ↔ `Package.swift` 源码目录的**双向**对账（纯函数：自检直接喂合成集合）。"""
    issues: list[Issue] = []
    for source in sorted(source_dirs):
        if not any(source == face_root or source.startswith(face_root + "/") for face_root in face_roots):
            issues.append(Issue(PACKAGE_SWIFT, f"`Package.swift` 的源码目录 `{source}` 落在判据面外"
                                               f" —— 面里没有覆盖它的根（面 = {sorted(face_roots)}）："
                                               f"在那个目录里抄一份键字面量，判据看不见"))
    for face_root in sorted(face_roots):
        if any(source == face_root or source.startswith(face_root + "/") for source in source_dirs):
            continue
        reason = (registered_non_target or {}).get(face_root, "")
        if not reason.strip():
            issues.append(Issue(PACKAGE_SWIFT, f"面里的根 `{face_root}` 既不是任何 target 的源码目录、"
                                               f"也没登记理由 —— 面与 `Package.swift` 对不上账"
                                               f"（要留在面里就得写进 `FACE_ROOTS_NOT_A_TARGET`）"))
    return issues


# ---------------------------------------------------------------- 判据 I

def _face_files(root: pathlib.Path) -> tuple[list[pathlib.Path], dict[str, int]]:
    """判据 I ②／③ 的扫描面（**现读**）：`SWIFT_FACE_ROOTS` 各根 rglob `*.swift` + 仓根 `*.swift`。

    同一份源码被两根同时收进来时**去重**（否则一处字面量会被数成两处）。
    """
    files: list[pathlib.Path] = []
    counts: dict[str, int] = {}
    for folder in SWIFT_FACE_ROOTS:
        path = root / folder
        found = sorted(path.rglob("*.swift")) if path.is_dir() else []
        counts[folder] = len(found)
        files += found
    if SWIFT_FACE_ROOT_GLOB:
        files += sorted(root.glob("*.swift"))
    unique: list[pathlib.Path] = []
    seen: set[str] = set()
    for path in files:
        key = path.resolve().as_posix()
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique, counts


def key_face_snapshot(root: pathlib.Path) -> dict:
    """面对账快照（现读）：根表各根的文件数 + 面内文件数 + 持有点（`文件:行`）。"""
    files, counts = _face_files(root)
    literal = re.compile(re.escape(KEY_LITERAL))
    holders: list[dict] = []
    for path in files:
        text = _strip_comments(path.read_text(encoding="utf-8"))
        hits = [index for index, line in enumerate(text.splitlines(), 1) if literal.search(line)]
        if hits:
            holders.append({"path": path.relative_to(root).as_posix(), "lines": hits})
    return {"roots": counts, "scannedFiles": len(files), "rootGlob": SWIFT_FACE_ROOT_GLOB,
            "holders": sorted(holders, key=lambda item: item["path"])}


def load_key_baseline(root: pathlib.Path) -> tuple[dict | None, list[Issue]]:
    """读面对账台账（不在盘 / 读不出 / 形状不对 ⇒ 红；面没有钉就不许通过）。"""
    path = root / KEY_BASELINE
    if not path.exists():
        return None, [Issue(KEY_BASELINE, "面对账台账不在盘上 —— 面没有钉（先落台账再判）")]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        return None, [Issue(KEY_BASELINE, f"面对账台账读不出来：{exc}")]
    if not isinstance(data, dict):
        return None, [Issue(KEY_BASELINE, "面对账台账的形状不对（要一个对象）")]
    return data, []


def key_face_issues(snapshot: dict, baseline: dict | None) -> list[Issue]:
    """面对账（**纯函数**：自检直接喂合成快照，不必搬整棵树）。

    三样都判：根表增减（现读 ↔ 台账）/ 任一根为空（那一块面被削）/ 面内文件数低于台账（棘轮）。
    """
    if not baseline:
        return [Issue(KEY_BASELINE, "面对账台账缺失 —— 面没有钉，不许通过")]
    issues: list[Issue] = []
    now, base = snapshot["roots"], baseline.get("roots") or {}
    # 只比**根名**：某根里多出一个 `.swift` 属正常开发（与同族判据的棘轮口径一致 ——
    # 缩面才是攻击面）。根表增减 / 任一根为空 / 面内文件数少于台账，三样都判红。
    if sorted(now) != sorted(base):
        issues.append(Issue(KEY_BASELINE, f"扫描面的根表明细 现读 {sorted(now)} / 台账 {sorted(base)}"
                                           f" —— 面的增减都要跟版（改 {KEY_BASELINE} 并写明理由）"))
    empty = sorted(folder for folder, count in now.items() if count < 1)
    if empty:
        issues.append(Issue(KEY_BASELINE, f"面里的根 {empty} 一份 `.swift` 都没有 —— 那一块面被削了，不许通过"))
    floor = int(baseline.get("scannedFiles") or 0)
    if snapshot["scannedFiles"] < floor:
        issues.append(Issue(KEY_BASELINE, f"只扫到 {snapshot['scannedFiles']} 份 `.swift`（台账 {floor}）"
                                           f" —— 削面：棘轮只许涨不许跌"))
    return issues


def nebula_key_holder_issues(holders: list[dict], baseline: dict | None) -> list[Issue]:
    """持有点 / 允许清单三态（**纯函数**）：未登记 ⇒ 红；登记了却不在盘 ⇒ 红；理由为空 ⇒ 红。"""
    allowed = (baseline or {}).get("allowedKeyHolders") or {}
    found = {item["path"] for item in holders}
    issues: list[Issue] = []
    for item in holders:
        if item["path"] not in allowed:
            where = "、".join(f"{item['path']}:{line}" for line in item["lines"])
            issues.append(Issue(item["path"],
                                f"`{NEBULA_TOGGLE_KEY}` 这个**字面量**也出现在 {where}"
                                f" —— 未登记的持有点（键写两处，改一处就让老用户的开关选择静默失效）；"
                                f"确属正当第二份要登记进 `{KEY_BASELINE}` 并写明理由"))
    for path, reason in sorted(allowed.items()):
        if not str(reason).strip():
            issues.append(Issue(KEY_BASELINE, f"台账里 `{path}` 的允许理由为空 —— 无理由的豁免不许留"))
        if path not in found:
            issues.append(Issue(KEY_BASELINE, f"台账登记 `{path}` 是正当持有点，但它不在盘上 / 不含那个字面量"
                                              f" —— 陈旧豁免（改台账并写明理由）"))
    if not found:
        issues.append(Issue(NEBULA_PREF_SWIFT, f"面内没有任何文件写出 `{NEBULA_TOGGLE_KEY}`"
                                               f" —— 规则的唯一出处或面被削了，不许通过"))
    return issues



def check_nebula_skin(root: pathlib.Path) -> tuple[list[Issue], int, dict]:
    """「星云皮肤」的存在 / 开关 / 三层表面（队列 `L-155`；2026-10-16 起星云由主题声明，不再专属星空紫）。

    与像素探针的分工：这里判**结构上的事实**（规则在哪、条件写没写对、落点在不在、开关接没接上、
    探针有没有被挂进跑法）；「真的画了 / 关了真回纯色 / 别的主题不画」由
    `TestsUISnapshot/NebulaSkinProbeTests.swift` 逐像素判。两条都不能省：
    静态判据看不见"画出来是空的"，像素判据看不见"还有第二处条件在别处等着分叉"。
    """
    issues: list[Issue] = []
    sites = 0

    # 判据 I ② 的面对账（`T-20261010-036` 扩面）：快照与台账先取，后面几条都用它
    snapshot = key_face_snapshot(root)
    baseline, baseline_issues = load_key_baseline(root)

    # ① 规则的唯一出处：键 / 缺省值 / 读法 / 生效条件
    pref_path = root / NEBULA_PREF_SWIFT
    if not pref_path.exists():
        return [Issue(NEBULA_PREF_SWIFT, "皮肤偏好的规则不存在 —— 判据 I 的前提没了"
                                         "（键 / 缺省值 / 读法 / 生效条件都应当只在这里写一次）")], sites, snapshot
    pref = _strip_comments(pref_path.read_text(encoding="utf-8"))

    sites += 1
    if NEBULA_KEY_DECL not in pref:
        issues.append(Issue(NEBULA_PREF_SWIFT, f"落盘键不是台账登记的那一个（缺 `{NEBULA_KEY_DECL}`）"
                                              f" —— 改键 = 老用户的开关选择静默失效"))
    sites += 1
    if NEBULA_DEFAULT_DECL not in pref:
        issues.append(Issue(NEBULA_PREF_SWIFT, "缺省值不是「开」"
                                              " —— 需求提出者 2026-10-01 要的就是新装直接看到皮肤"))
    sites += 1
    if NEBULA_READ_BODY not in pref:
        issues.append(Issue(NEBULA_PREF_SWIFT,
                            f"读法不是 `{NEBULA_READ_BODY}` —— 退回 `bool(forKey:)` 会把缺省从「开」改成「关」"
                            f"（「新装看不到皮肤」的经典坑）"))
    effect = _type_slice(pref, "func paintsNebula(", closing="\n    }") or ""
    sites += 1
    if NEBULA_EFFECT_BODY not in effect:
        issues.append(Issue(NEBULA_PREF_SWIFT,
                            f"生效条件不是「主题**声明要星云** 且 开关开」（缺 `{NEBULA_EFFECT_BODY}`）"
                            " —— 少前半是「别的主题也长星星」，少后半是「关不掉」"))

    # ② 键字面量：在**入库源码面**上只许出现在登记过的落点 + 面与台账对账
    #    （2026-10-13 · `T-20261010-036`：面从 4 根扩到入库源码面；扩面前 `Tests/` 里那份看不见）
    sites += 1
    issues += baseline_issues
    issues += key_face_issues(snapshot, baseline)
    issues += nebula_key_holder_issues(snapshot["holders"], baseline)

    # ③ 绘制侧只许调用那一条规则，不许自己再写一遍主题判断
    nebula_path = root / NEBULA_SWIFT
    sites += 1
    if not nebula_path.exists():
        issues.append(Issue(NEBULA_SWIFT, "星云皮肤的绘制视图不存在 —— 三层表面就没人铺了"))
    else:
        nebula = _strip_comments(nebula_path.read_text(encoding="utf-8"))
        body = _type_slice(nebula, "var body: some View {", closing="\n    }") or ""
        sites += 1
        if not body:
            issues.append(Issue(NEBULA_SWIFT, "取不到绘制视图的 `body` 切片 —— 判据 I 的前提没了"))
        sites += 1
        if NEBULA_EFFECT_CALL not in body:
            issues.append(Issue(NEBULA_SWIFT,
                                f"绘制视图的生效条件没有走唯一出处（缺 `{NEBULA_EFFECT_CALL}`）"
                                f" —— 条件写在两处，迟早分叉"))
        sites += 1
        if ".stardust" in body:
            issues.append(Issue(NEBULA_SWIFT,
                                "绘制视图的 `body` 里又写了一遍主题判断（出现 `.stardust`）"
                                " —— 生效条件只许有一处出处（判据 I ②）"))

    # ④ 三层表面各自**恰有一处**落点
    #    面 = **宿主 target 的 `sources:` 现读**（原单 `T-20261010-068` ㈥ 的另一半：先前写死
    #    `App/`，于是 `Plugins/Notes/Views/` 那一片整体在面外 —— 在那里再铺一层星云判据看不见）。
    host_dirs = host_source_dirs(root)
    sites += 1
    if not host_dirs:
        issues.append(Issue(PACKAGE_SWIFT, "读不出宿主 target 的源码目录"
                                          "（`Package.swift` 里含 `App` 的那份 `sources:`）"
                                          " —— 判据 I ④ 的面无从对账"))
    app_files: list[pathlib.Path] = []
    for folder in host_dirs:
        folder_path = root / folder
        if not folder_path.is_dir():
            issues.append(Issue(PACKAGE_SWIFT, f"宿主 target 的源码目录 `{folder}` 不在盘 —— 面缺一块"))
            continue
        app_files += sorted(folder_path.rglob("*.swift"))
    for label, (expected_file, marker) in NEBULA_LAYER_SITES.items():
        hits: list[str] = []
        for path in app_files:
            count = _strip_comments(path.read_text(encoding="utf-8")).count(marker)
            if count:
                hits += [path.relative_to(root).as_posix()] * count
        sites += 1
        if hits != [expected_file]:
            issues.append(Issue(expected_file,
                                f"{label} 那一层的星云落点是 {hits or '没有'}（应当**恰有一处**，在 `{expected_file}`）"
                                f" —— 少了那层没皮肤、多了那层重复铺"))

    # ⑤ 界面那个开关：绑唯一写入口 + 只在声明要星云的主题下露面
    sheet_path = root / APPEARANCE_SWIFT
    sites += 1
    if not sheet_path.exists():
        issues.append(Issue(APPEARANCE_SWIFT, "外观面板不存在 —— 皮肤开关没有入口"))
    else:
        sheet = _strip_comments(sheet_path.read_text(encoding="utf-8"))
        sites += 1
        if NEBULA_SHEET_BINDING not in sheet:
            issues.append(Issue(APPEARANCE_SWIFT,
                                f"皮肤开关没有接到唯一写入口（缺 `{NEBULA_SHEET_BINDING}`）"
                                f" —— 绑到本地 `@State` 上就落不了盘（重启又打开）"))
        sites += 1
        if NEBULA_SHEET_CONDITION not in sheet:
            issues.append(Issue(APPEARANCE_SWIFT,
                                f"皮肤开关不再只在**声明要星云的主题**下出现（缺 `{NEBULA_SHEET_CONDITION}`）"
                                " —— 别的主题下摆一个点了没反应的开关是把用户绕晕"))

    # ⑥ 规则的单测（默认开 / 读法 / 重开仍关 / 真值表）——"重开"这一态 App 侧做不到，只能在 Core
    tests_path = root / NEBULA_TESTS_SWIFT
    sites += 1
    if not tests_path.exists():
        issues.append(Issue(NEBULA_TESTS_SWIFT, "规则的单测不存在"
                                               " —— 「默认开 / 重开仍关」这两态会没有机器判据"))
    else:
        tests = _strip_comments(tests_path.read_text(encoding="utf-8"))
        for name, why in NEBULA_TEST_CASES.items():
            sites += 1
            if f"func {name}(" not in tests:
                issues.append(Issue(NEBULA_TESTS_SWIFT, f"少了这条单测：`{name}`（{why}）"))

    # ⑦ 像素探针必须在场，且**挂进过滤清单**（不挂进 FILTER 的这一族一个都跑不到 —— §9 第 104 条）
    probe_path = root / NEBULA_PROBE_SWIFT
    sites += 1
    if not probe_path.exists():
        issues.append(Issue(NEBULA_PROBE_SWIFT,
                            "像素探针不存在 —— 「真的画了 / 关了真回纯色 / 别的主题不画」又只能靠人读图"))
    else:
        probe = _strip_comments(probe_path.read_text(encoding="utf-8"))
        for marker in NEBULA_PROBE_MARKERS:
            sites += 1
            if marker not in probe:
                issues.append(Issue(NEBULA_PROBE_SWIFT, f"像素探针里缺 `{marker}`"))
        runner_path = root / PROBE_RUNNER_SH
        sites += 1
        if not runner_path.exists():
            issues.append(Issue(PROBE_RUNNER_SH, "探针跑法脚本不存在 —— 这一族没有入口"))
        elif "NebulaSkinProbeTests" not in _strip_comments(runner_path.read_text(encoding="utf-8")):
            issues.append(Issue(PROBE_RUNNER_SH,
                                "像素探针没挂进 `--filter` 的 FILTER 清单"
                                " —— 不挂进 FILTER 的这一族一个都跑不到（AGENT-SPEC §9 第 104 条）"))

    sites += 1
    if sites < MIN_NEBULA_SITES:
        issues.append(Issue(NEBULA_PREF_SWIFT, f"判据 I 只判了 {sites} 处（下限 {MIN_NEBULA_SITES}）"
                                              f" —— 扫描面被削过，不许通过"))
    return issues, sites, snapshot


# ---------------------------------------------------------------- 自检

def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fixture(base: pathlib.Path) -> pathlib.Path:
    """把判据要看的文件复制到临时目录（夹具一律在临时目录里写坏）。"""
    for relative in (THEMES_SWIFT, TOKENS_SWIFT, LOCALIZATION_SWIFT, DESIGN_DOC, RELEASE_PLAN,
                     APPEARANCE_SWIFT, THEME_MANAGER_SWIFT, APPEARANCE_PREF_SWIFT, APP_STATE_SWIFT,
                     AXES_TESTS_SWIFT, AXES_PROBE_SWIFT, SNAPSHOT_KIT_SWIFT, PANELS_TESTS_SWIFT,
                     NEBULA_SWIFT, NEBULA_PREF_SWIFT, MAIN_WINDOW_SWIFT, LOWER_PANE_SWIFT,
                     NEBULA_PROBE_SWIFT, NEBULA_TESTS_SWIFT, PROBE_RUNNER_SH, PACKAGE_SWIFT):
        target = base / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / relative, target)
    # 判据 I ④ 要**扫** `App/` 下的所有 `.swift`（判"三层表面各自恰有一处落点"），
    # 所以 `App/Views/` 里的其它视图也要一起搬进夹具 —— 只搬"判据直接点名的那几份"的话，
    # 复制一份落点到别的视图上时夹具根本看不见（那样负例就是假绿）。
    for path in sorted((ROOT / "App").rglob("*.swift")):
        relative = path.relative_to(ROOT)
        target = base / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            shutil.copy(path, target)
    # 判据 I ② 的扫描面（`T-20261010-036` 扩面后）要求**十根都在、都不空**：
    # 夹具缺哪一根就补一个替身 —— 真仓的那一根不在夹具里，替身只为了让「面钉」这一格可判。
    for folder in SWIFT_FACE_ROOTS:
        target = base / folder
        target.mkdir(parents=True, exist_ok=True)
        if not sorted(target.rglob("*.swift")):
            (target / "__face_stub.swift").write_text("import Foundation\n", encoding="utf-8")

    # 判据 I ④ 的面 = **宿主 target 的 `sources:`**（`Package.swift` 现读；见 `host_source_dirs`）
    # ⇒ 那几根也要有替身，否则夹具里「宿主面缺一块」会替真仓判红。
    for folder in host_source_dirs(ROOT) or ["App"]:
        target = base / folder
        target.mkdir(parents=True, exist_ok=True)
        if not sorted(target.rglob("*.swift")):
            (target / "__host_face_stub.swift").write_text("import Foundation\n", encoding="utf-8")
    # 夹具自己的面对账台账：**按夹具现读写**（根表 / 文件数自洽），
    # 允许持有点照抄真仓那两条（相对路径在夹具里逐字相同 ⇒ 未登记的第二份照样判红）。
    fixture_baseline = json.loads((ROOT / KEY_BASELINE).read_text(encoding="utf-8"))
    fixture_snapshot = key_face_snapshot(base)
    fixture_baseline["roots"] = fixture_snapshot["roots"]
    fixture_baseline["scannedFiles"] = fixture_snapshot["scannedFiles"]
    (base / KEY_BASELINE).parent.mkdir(parents=True, exist_ok=True)
    (base / KEY_BASELINE).write_text(json.dumps(fixture_baseline, ensure_ascii=False, indent=2),
                                     encoding="utf-8")
    return base


def _patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具锚点失效：{old[:60]}"
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def self_test() -> int:
    cases: list[tuple[str, bool, list[Issue]]] = []
    watched = (THEMES_SWIFT, TOKENS_SWIFT, LOCALIZATION_SWIFT, DESIGN_DOC, RELEASE_PLAN,
               APPEARANCE_SWIFT, THEME_MANAGER_SWIFT, APPEARANCE_PREF_SWIFT, APP_STATE_SWIFT,
               AXES_TESTS_SWIFT, AXES_PROBE_SWIFT, SNAPSHOT_KIT_SWIFT, PANELS_TESTS_SWIFT,
               NEBULA_SWIFT, NEBULA_PREF_SWIFT, MAIN_WINDOW_SWIFT, LOWER_PANE_SWIFT,
               NEBULA_PROBE_SWIFT, NEBULA_TESTS_SWIFT, PROBE_RUNNER_SH, PACKAGE_SWIFT)
    before = {name: _sha(ROOT / name) for name in watched}

    def static_issues(fixture: pathlib.Path) -> list[Issue]:
        issues = check_theme_set(fixture)
        issues += check_palette_shape(fixture)[0]
        issues += check_thresholds(fixture)[0]
        issues += check_syntax_binding(fixture)
        issues += check_names_and_pending(fixture)[0]
        issues += check_ui_entry(fixture)[0]
        issues += check_two_axis(fixture)[0]
        issues += check_nebula_skin(fixture)[0]
        return issues

    with tempfile.TemporaryDirectory(prefix="doyah-themes-selftest-") as tmp:
        base = _fixture(pathlib.Path(tmp) / "green")
        base_snapshot = key_face_snapshot(base)
        base_baseline, _ = load_key_baseline(base)
        # ① 绿：好情况
        cases.append(("好情况（绿）", False, static_issues(base)))

        # ② 红：少一个色角色（复制粘贴新主题时漏一行）
        missing = _fixture(pathlib.Path(tmp) / "bad-missing-role")
        _patch(missing / THEMES_SWIFT, "        textDisabled: ThemeColor(light: 0xA9C3B1, dark: 0x3E6B4E),\n", "")
        cases.append(("值表少一个色角色", True, check_palette_shape(missing)[0]))

        # ③ 红：正文被改成几乎与底同色（低对比）
        low = _fixture(pathlib.Path(tmp) / "bad-contrast")
        _patch(low / THEMES_SWIFT,
               "textPrimary: ThemeColor(light: 0x12301E, dark: 0xC6D9CB)",
               "textPrimary: ThemeColor(light: 0x12301E, dark: 0x112218)")
        cases.append(("正文对比度不足", True, check_thresholds(low)[0]))

        # ④ 红：window 与 content 同色（表面分不开）
        same = _fixture(pathlib.Path(tmp) / "bad-surface")
        _patch(same / THEMES_SWIFT,
               "window: ThemeColor(light: 0xF2F8F3, dark: 0x04120A)",
               "window: ThemeColor(light: 0xFFFFFF, dark: 0x0F2418)")
        cases.append(("window 与 content 同色", True, check_thresholds(same)[0]))

        # ⑤ 红：深色五档明度不递增
        flat = _fixture(pathlib.Path(tmp) / "bad-order")
        _patch(flat / THEMES_SWIFT,
               "content: ThemeColor(light: 0xFFFFFF, dark: 0x0F2418)",
               "content: ThemeColor(light: 0xFFFFFF, dark: 0x081109)")
        cases.append(("深色五档明度不递增", True, check_thresholds(flat)[0]))

        # ⑥ 红：强调家族某档掉到图标线以下（并且语法 keyword 跟着掉）
        weak_accent = _fixture(pathlib.Path(tmp) / "bad-accent")
        _patch(weak_accent / THEMES_SWIFT,
               "accentGlow: ThemeColor(light: 0x1B7A4A, dark: 0xA8E6BB)",
               "accentGlow: ThemeColor(light: 0x1B7A4A, dark: 0x1D2A1D)")
        cases.append(("强调家族掉到门槛以下", True, check_thresholds(weak_accent)[0]))

        # ⑦ 红：浅色发丝线不比 content 暗
        hairline = _fixture(pathlib.Path(tmp) / "bad-hairline")
        _patch(hairline / THEMES_SWIFT, "hairlineLight: 0xD5E3D9,", "hairlineLight: 0xFFFFFF,")
        cases.append(("浅色发丝线不比 content 暗", True, check_thresholds(hairline)[0]))

        # ⑧ 红：主题名与 Linux 侧的名对不上
        renamed = _fixture(pathlib.Path(tmp) / "bad-name")
        _patch(renamed / LOCALIZATION_SWIFT,
               '.designThemeBeanGreen: [.simplifiedChinese: "豆芽绿"',
               '.designThemeBeanGreen: [.simplifiedChinese: "嫩芽绿"')
        cases.append(("主题名与 Linux 侧不一致", True, check_names_and_pending(renamed)[0]))

        # ⑨ 红：§9 的主题表少一行（文档没跟上）
        doc_short = _fixture(pathlib.Path(tmp) / "bad-doc")
        _patch(doc_short / DESIGN_DOC, "| 3 | 玫瑰金 |", "| 3 | 晚霞红 |")
        cases.append(("§9 主题表与枚举对不上", True, check_names_and_pending(doc_short)[0]))

        # ⑩ 红：待值登记被删（推导值静默当实际值）
        no_pending = _fixture(pathlib.Path(tmp) / "bad-pending")
        _patch(no_pending / RELEASE_PLAN, "豆芽绿 / 玫瑰金 色值（Linux 侧）", "（已到位）")
        cases.append(("待值登记被删", True, check_names_and_pending(no_pending)[0]))

        # ⑪ 红：语法色与家族脱钩（keyword 改回硬编码色）
        unhooked = _fixture(pathlib.Path(tmp) / "bad-syntax")
        _patch(unhooked / TOKENS_SWIFT,
               "case .keyword: return AccentFamily.accentGlow.color(in: theme)",
               "case .keyword: return ThemeColor(light: 0x9BA8FF, dark: 0x9BA8FF)")
        cases.append(("语法色与家族脱钩", True, check_syntax_binding(unhooked)))

        # ⑫ 红：空跑防护 —— 主题集被掏空
        hollow = _fixture(pathlib.Path(tmp) / "bad-empty")
        text = (hollow / THEMES_SWIFT).read_text(encoding="utf-8")
        text = re.sub(r'^\s*case \w+ = "[a-z-]+"$', "", text, flags=re.M)
        (hollow / THEMES_SWIFT).write_text(text, encoding="utf-8")
        cases.append(("主题集被掏空（空跑）", True, check_theme_set(hollow)))

        # ⑮ 红：推导标注被抹掉（把推导值当实际值卖）
        unmarked = _fixture(pathlib.Path(tmp) / "bad-derived")
        _patch(unmarked / THEMES_SWIFT,
               "    // MARK: 豆芽绿（**推导草案** —— Linux 侧实际色值到位后整表替换，不留两套）",
               "    // MARK: 豆芽绿")
        cases.append(("推导标注被抹掉", True, check_names_and_pending(unmarked)[0]))

        # ⑬ 红：`.all` 漏列一个主题
        short_all = _fixture(pathlib.Path(tmp) / "bad-all")
        _patch(short_all / THEMES_SWIFT,
               "public static let all: [DesignTheme] = [.techBlue, .stardust, .deepSpace, .beanGreen, .roseGold]",
               "public static let all: [DesignTheme] = [.techBlue, .beanGreen]")
        cases.append(("`.all` 漏列主题", True, check_theme_set(short_all)))

        # ⑭ 红：空跑防护 —— 值表被删光
        no_palette = _fixture(pathlib.Path(tmp) / "bad-nopalette")
        text = (no_palette / THEMES_SWIFT).read_text(encoding="utf-8")
        text = re.sub(r"public static let \w+ = ThemePalette\(.*?\n    \)", "", text, flags=re.S)
        (no_palette / THEMES_SWIFT).write_text(text, encoding="utf-8")
        cases.append(("值表被删光（空跑）", True, check_palette_shape(no_palette)[0]))

        # ⑯ 红：面板不再逐个列出主题集（有人选不到）
        no_entry = _fixture(pathlib.Path(tmp) / "bad-entry")
        _patch(no_entry / APPEARANCE_SWIFT,
               "ForEach(DesignTheme.all) { candidate in",
               "ForEach(DesignTheme.all.prefix(1)) { candidate in")
        cases.append(("面板不再列出主题集", True, check_ui_entry(no_entry)[0]))

        # ⑰ 红：主题行少一个真实场景（只给一块色卡 —— 界面退化成"凭想象选"）
        weak_row = _fixture(pathlib.Path(tmp) / "bad-row-scene")
        _patch(weak_row / APPEARANCE_SWIFT,
               "白字（该主题配套的压暗档）\n            Text(L(theme.nameKey).prefix(2))\n"
               "                .font(Theme.font(.caption))\n                .foregroundStyle(.white)",
               "白字（该主题配套的压暗档，场景被删）\n            Text(L(theme.nameKey).prefix(2))\n"
               "                .font(Theme.font(.caption))\n                .foregroundStyle(.primary)")
        cases.append(("主题行少一个真实场景", True, check_ui_entry(weak_row)[0]))

        # ⑱ 红：推导主题在界面上不再标注（推导值当实际值卖）
        unlabeled = _fixture(pathlib.Path(tmp) / "bad-label")
        _patch(unlabeled / APPEARANCE_SWIFT, "if theme.isDerivedDraft {", "if false {")
        cases.append(("推导主题在界面上不标注", True, check_ui_entry(unlabeled)[0]))

        # ⑲ 红：加了主题就把已交付的「强调色可配置」删掉（静默收功能）
        accent_gone = _fixture(pathlib.Path(tmp) / "bad-accent-entry")
        _patch(accent_gone / APPEARANCE_SWIFT,
               "ForEach(AccentTheme.all) { theme in", "ForEach([]) { theme in")
        cases.append(("强调色入口被静默删除", True, check_ui_entry(accent_gone)[0]))

        # ⑳ 红：宿主语境的覆盖写了盘（拍一张快照就改了用户的偏好）
        persists = _fixture(pathlib.Path(tmp) / "bad-host-persist")
        _patch(persists / THEME_MANAGER_SWIFT,
               "    func beginHostTheme(_ theme: DesignTheme) -> DesignTheme? {\n        let previous = hostOverride",
               "    func beginHostTheme(_ theme: DesignTheme) -> DesignTheme? {\n"
               "        UserDefaults.standard.set(theme.id, forKey: DesignTheme.Storage.key)\n"
               "        let previous = hostOverride")
        cases.append(("宿主语境覆盖写了盘", True, check_ui_entry(persists)[0]))

        # ㉑ 红：主题行整块被删（空跑）
        no_row = _fixture(pathlib.Path(tmp) / "bad-no-row")
        _patch(no_row / APPEARANCE_SWIFT,
               "private struct DesignThemeOptionRow: View {",
               "private struct ThemeRowPlaceholder: View {")
        cases.append(("主题行整块被删（空跑）", True, check_ui_entry(no_row)[0]))


        # ⑯ 红：深浅轴少一态（三态变两态 ⇒ 真值表里总有一格取不到值）
        two_state = _fixture(pathlib.Path(tmp) / "bad-axis-two-states")
        _patch(two_state / APPEARANCE_PREF_SWIFT, "    case alwaysLight\n", "")
        cases.append(("两轴：深浅轴少一态（红）", True, static_issues(two_state)))

        # ⑰ 红：两轴串了（配色轴的运行时对象里出现深浅轴的键 ⇒ 切主题会顺手改外观）
        crossed = _fixture(pathlib.Path(tmp) / "bad-axis-crossed")
        leak = crossed / THEME_MANAGER_SWIFT
        leak.write_text(leak.read_text(encoding="utf-8")
                        + '\n// 串轴演示：配色轴的对象里出现深浅轴的键\nlet axisLeak = "appearance.mode"\n',
                        encoding="utf-8")
        cases.append(("两轴：串轴（红）", True, static_issues(crossed)))

        # ⑱ 红：组合没到像素（面板快照不再取角像素 ⇒ 三个主题画成一样也绿）
        no_pixel = _fixture(pathlib.Path(tmp) / "bad-axis-no-pixel")
        _patch(no_pixel / PANELS_TESTS_SWIFT,
               "UISnapshot.sampledRGB(ofPNGAt: record.file",
               "UISnapshot.sampledRGBBROKEN(ofPNGAt: record.file")
        cases.append(("两轴：组合没到像素（红）", True, static_issues(no_pixel)))

        # ⑲ 红：星云皮肤的生效条件少了一半（去掉「主题声明要星云」那一半）
        #      —— 少这一半 = 别的主题也长星星，而界面上看不出任何异常。
        #      （2026-10-16 泛化后，前半段的实体从 `theme == .stardust` 变成 `theme.paintsNebula`。）
        half_effect = _fixture(pathlib.Path(tmp) / "bad-nebula-effect-half")
        _patch(half_effect / NEBULA_PREF_SWIFT,
               "theme.paintsNebula && isSkinEnabled", "isSkinEnabled")
        cases.append(("皮肤：生效条件少一半（红）", True, static_issues(half_effect)))

        # ⑳ 红：开关的读法退回 `bool(forKey:)`（"从未设过"被读成关 ⇒ 缺省值静默改成关）
        bool_read = _fixture(pathlib.Path(tmp) / "bad-nebula-read")
        _patch(bool_read / NEBULA_PREF_SWIFT,
               "defaults.object(forKey: key) as? Bool ?? defaultEnabled",
               "defaults.bool(forKey: key)")
        cases.append(("皮肤：读法退回 bool(forKey:)（红）", True, static_issues(bool_read)))

        # ㉑ 红：键的字面量被抄了第二份（改一处就让老用户的选择静默失效）
        duplicate_key = _fixture(pathlib.Path(tmp) / "bad-nebula-key")
        key_file = duplicate_key / THEME_MANAGER_SWIFT
        key_file.write_text(key_file.read_text(encoding="utf-8")
                            + '\n// 抄一份键字面量（负例）\nlet duplicateNebulaKey = "ui.nebulaSkin"\n',
                            encoding="utf-8")
        cases.append(("皮肤：键字面量抄了第二份（红）", True, static_issues(duplicate_key)))

        # ㉒ 红：绘制视图的 body 里又写了一遍主题判断（条件两处出处 ⇒ 迟早分叉）
        inline_effect = _fixture(pathlib.Path(tmp) / "bad-nebula-inline")
        _patch(inline_effect / NEBULA_SWIFT,
               "        if NebulaSkinPreference.paintsNebula(",
               "        if themeManager.theme == .stardust, themeManager.isNebulaSkinEnabled, false || (")
        cases.append(("皮肤：绘制视图又写一遍主题判断（红）", True, static_issues(inline_effect)))

        # ㉓ 红：某一层的落点被删（下方面板那一层没皮肤）
        missing_layer = _fixture(pathlib.Path(tmp) / "bad-nebula-layer-missing")
        _patch(missing_layer / LOWER_PANE_SWIFT,
               "                NebulaBackground(layer: .panel)\n", "")
        cases.append(("皮肤：某一层落点被删（红）", True, static_issues(missing_layer)))

        # ㉔ 红：某一层的落点被抄了第二份（重复铺 —— 先铺表面再叠星云，铺两遍是两倍的绘制）
        duplicate_layer = _fixture(pathlib.Path(tmp) / "bad-nebula-layer-dup")
        layer_file = duplicate_layer / MAIN_WINDOW_SWIFT
        layer_file.write_text(layer_file.read_text(encoding="utf-8")
                              + "\n// 重复铺一层（负例）\nlet duplicateNebulaLayer = NebulaBackground(layer: .content)\n",
                              encoding="utf-8")
        cases.append(("皮肤：某一层落点抄了第二份（红）", True, static_issues(duplicate_layer)))

        # ㉕ 红：界面那个开关绑到本地 `@State`（点了不落盘 ⇒ 重启又变回开）
        local_state = _fixture(pathlib.Path(tmp) / "bad-nebula-binding")
        _patch(local_state / APPEARANCE_SWIFT,
               "            set: { designTheme.setNebulaSkinEnabled($0) }",
               "            set: { _ = $0 }")
        cases.append(("皮肤：开关绑到本地 @State（红）", True, static_issues(local_state)))

        # ㉖ 红：规则的单测少一条（"关掉之后重开仍是关"没了 —— 那一态只能在这里判）
        missing_case = _fixture(pathlib.Path(tmp) / "bad-nebula-test-case")
        _patch(missing_case / NEBULA_TESTS_SWIFT,
               "    func testOffIsPersistedAndSurvivesReopen() {",
               "    func removedReopenCase() {")
        cases.append(("皮肤：单测少一条（红）", True, static_issues(missing_case)))

        # ㉗ 红：像素探针没挂进 FILTER（这一族一个都跑不到 —— §9 第 104 条那条教训）
        unfiltered = _fixture(pathlib.Path(tmp) / "bad-nebula-filter")
        _patch(unfiltered / PROBE_RUNNER_SH, "|NebulaSkinProbeTests", "")
        cases.append(("皮肤：探针没挂进 FILTER（红）", True, static_issues(unfiltered)))

        # ㉘ 红：像素探针里"逐像素比对"的口子被删（三张主角还在，但没人比像素了）
        no_compare = _fixture(pathlib.Path(tmp) / "bad-nebula-probe")
        _patch(no_compare / NEBULA_PROBE_SWIFT,
               "let count = UISnapshot.differingPixels(left, right)",
               "let count = 0")
        cases.append(("皮肤：探针不再比像素（红）", True, static_issues(no_compare)))

        # ㉙ 红：同一个键字面量被抄进 `Tests/` 的新文件 ⇒ **未登记** ⇒ 红
        #     （由头 = `T-20261010-036`：扩面前这条路整体在面外 ⇒ 静默绿）
        key_dup = _fixture(pathlib.Path(tmp) / "bad-nebula-key-tests")
        (key_dup / "Tests" / "ProbeNebulaKey.swift").write_text(
            'import Foundation\nlet duplicatedKey = "ui.nebulaSkin"\n', encoding="utf-8")
        cases.append(("皮肤：键字面量第二份抄进 Tests/（红）", True, static_issues(key_dup)))

        # ㉚ 红：面被削到单根（`T-20261010-036` 验收 2）—— 合成快照喂纯函数，不必搬整棵树
        shaved = dict(base_snapshot, roots={"Core": base_snapshot["roots"]["Core"]})
        cases.append(("皮肤：扫描面被削到单根（红）", True, key_face_issues(shaved, base_baseline)))

        # ㉛ 红：面内文件数低于台账（棘轮只许涨不许跌）
        fewer = dict(base_snapshot, scannedFiles=base_snapshot["scannedFiles"] - 1)
        cases.append(("皮肤：面内文件数低于台账（红）", True, key_face_issues(fewer, base_baseline)))

        # ㉜ 红：面对账台账不在盘（面没有钉）
        cases.append(("皮肤：面对账台账不在盘（红）", True,
                      load_key_baseline(pathlib.Path(tmp) / "no-baseline-here")[1]))

        # ㉝ 红：台账登记了却不在盘（陈旧豁免）
        dead = {"allowedKeyHolders": {NEBULA_PREF_SWIFT: "规则的唯一出处",
                                      "Tests/Gone.swift": "登记过但文件没了"}}
        cases.append(("皮肤：台账里的持有点不在盘（红）", True,
                      nebula_key_holder_issues([{"path": NEBULA_PREF_SWIFT, "lines": [28]}], dead)))

        # ㉞ 红：台账里的允许理由为空（无理由的豁免不许留）
        blank = {"allowedKeyHolders": {NEBULA_TESTS_SWIFT: "   "}}
        cases.append(("皮肤：允许清单的理由为空（红）", True,
                      nebula_key_holder_issues([{"path": NEBULA_TESTS_SWIFT, "lines": [44]}], blank)))

        # ㉟ 绿（对手臂）：扩面后真仓那两处持有点都已在台账里登记
        cases.append(("皮肤：面内持有点都已登记（绿）", False,
                      nebula_key_holder_issues(base_snapshot["holders"], base_baseline)))

        # ㊱ 红（判据 D）：六条真映射**整行注释掉** ⇒ 红
        #     （原单 `T-20261010-068` ㈠：旧版拿整份文件 `re.findall` ⇒ 注释掉仍绿）
        syntax_commented = _fixture(pathlib.Path(tmp) / "bad-syntax-commented")
        _patch(syntax_commented / TOKENS_SWIFT,
               "        case .keyword: return AccentFamily.accentGlow.color(in: theme)",
               "        // case .keyword: return AccentFamily.accentGlow.color(in: theme)")
        cases.append(("语法映射整行注释掉（红）", True, check_syntax_binding(syntax_commented)))

        # ㊲ 红（判据 D）：映射**搬到 `switch` 块外** ⇒ 红（判定物只在块内找）
        syntax_moved = _fixture(pathlib.Path(tmp) / "bad-syntax-moved")
        moved_path = syntax_moved / TOKENS_SWIFT
        moved_text = moved_path.read_text(encoding="utf-8")
        moved_line = "        case .comment: return TextTone.tertiary.color(in: theme)\n"
        assert moved_line in moved_text
        moved_path.write_text(moved_text.replace(moved_line, "", 1)
                              + "\n// 映射搬到块外（负例）\n" + moved_line, encoding="utf-8")
        cases.append(("语法映射搬到 switch 块外（红）", True, check_syntax_binding(syntax_moved)))
        # ㊳ 红（判据 A）：`DesignTheme.all` 顺序倒置 ⇒ 红（判的是身份与顺序，不是数个数）
        reordered = _fixture(pathlib.Path(tmp) / "bad-ui-order")
        _patch(reordered / THEMES_SWIFT,
               "public static let all: [DesignTheme] = [.techBlue, .stardust, .deepSpace, .beanGreen, .roseGold]",
               "public static let all: [DesignTheme] = [.stardust, .roseGold, .beanGreen, .techBlue]")
        cases.append(("界面顺序倒置（红）", True, check_theme_set(reordered)))

        # ㊴ 红（判据 A）：`of(_:)` 某一支取错值表（星空紫取到科技蓝的表）⇒ 红
        of_block = "        case .techBlue: return .techBlue\n        case .beanGreen: return .beanGreen\n        case .roseGold: return .roseGold\n        case .stardust: return .stardust\n        case .deepSpace: return .deepSpace\n"
        wrong_table = _fixture(pathlib.Path(tmp) / "bad-of-table")
        _patch(wrong_table / THEMES_SWIFT, of_block,
               of_block.replace("case .stardust: return .stardust", "case .stardust: return .techBlue"))
        cases.append(("of(_:) 取错值表（红）", True, check_theme_set(wrong_table)))

        # ㊵ 红（判据 A · 空跑）：`of(_:)` 被掏空 ⇒ 条目数低于下限 ⇒ 红
        hollow_of = _fixture(pathlib.Path(tmp) / "bad-of-hollow")
        _patch(hollow_of / THEMES_SWIFT, of_block, "")
        cases.append(("of(_:) 被掏空（空跑，红）", True, check_theme_set(hollow_of)))
        # ㊶ 红（判据 G）：主题列表与强调色入口两处**真用法改成注释** ⇒ 红
        #     （原单 `T-20261010-068` ㈢：旧版是裸子串 ⇒ 注释里留一句就算「入口还在」）
        commented_entry = _fixture(pathlib.Path(tmp) / "bad-entry-commented")
        _patch(commented_entry / APPEARANCE_SWIFT,
               "            ForEach(DesignTheme.all) { candidate in",
               "            // ForEach(DesignTheme.all) { candidate in")
        _patch(commented_entry / APPEARANCE_SWIFT,
               "            ForEach(AccentTheme.all) { theme in",
               "            // ForEach(AccentTheme.all) { theme in")
        cases.append(("界面入口改成注释（红）", True, check_ui_entry(commented_entry)[0]))

        # ㊷ 绿（判据 H · 假阳已消 —— 成对臂）：配色轴对象里**注释**提一句 `appearance.mode` ⇒ 绿
        comment_only = _fixture(pathlib.Path(tmp) / "ok-axis-comment")
        leak_file = comment_only / THEME_MANAGER_SWIFT
        leak_file.write_text(leak_file.read_text(encoding="utf-8")
                            + "\n// 说明注释：这里绝不许出现 appearance.mode 这个键\n", encoding="utf-8")
        cases.append(("串轴检查：注释里提键名（绿）", False, check_two_axis(comment_only)[0]))
        # ㊸ 红（判据 H）：删掉 `30` 组的两条真断言（注释里仍有「30」）⇒ 红
        weak_combo = _fixture(pathlib.Path(tmp) / "bad-combo-assert")
        _patch(weak_combo / AXES_TESTS_SWIFT,
               'XCTAssertEqual(combinations.count, 30, "3 态 × 2 系统态 × 5 主题 = 30")',
               "XCTAssertTrue(combinations.count > 0)")
        _patch(weak_combo / AXES_TESTS_SWIFT,
               'XCTAssertEqual(Set(combinations).count, 30, "组合有重复")',
               "XCTAssertTrue(Set(combinations).count > 0)")
        cases.append(("组合数真断言被删（红）", True, check_two_axis(weak_combo)[0]))

        # ㊹ 绿（注释扫描守卫）：字符串里的 `/*` 不许吞掉后面的真代码
        #     （本仓 14 处 `/*` 落在字符串里，如 `head.hasPrefix("/*")`）
        string_guard = _fixture(pathlib.Path(tmp) / "ok-string-block-comment")
        _patch(string_guard / APPEARANCE_SWIFT,
               "            ForEach(DesignTheme.all) { candidate in",
               '            let probePrefix = "/*"\n'
               "            ForEach(DesignTheme.all) { candidate in")
        cases.append(("注释扫描：字符串里的块注释起点（绿）", False, check_ui_entry(string_guard)[0]))
        # ㊺ 红（面对账）：`Package.swift` 的源码目录落在判据面外 ⇒ 红
        cases.append(("面对账：源码目录落在面外（红）", True,
                      face_vs_package_issues({"Tools/LicenseTool", "Widgets/Extra"},
                                             {"Tools": "工具 target", "Scripts": "脚本面"},
                                             {"Scripts": "脚本面"})))

        # ㊻ 红（面对账）：面里多一根既不是 target、又没登记理由的根 ⇒ 红
        cases.append(("面对账：面里多一根没理由的根（红）", True,
                      face_vs_package_issues({"Core"}, {"Core": "核心层", "Ghost": "没有 target"}, {})))

        # ㊼ 绿（面对账 · 对手臂）：真仓的 target 源码目录与面逐条对得上
        cases.append(("面对账：真仓 target 目录与面一致（绿）", False,
                      face_vs_package_issues(package_source_dirs(ROOT), SWIFT_FACE_ROOTS,
                                             FACE_ROOTS_NOT_A_TARGET)))

    failures = 0
    # 迭代**副本**：这个循环体里将来若有人再 `cases.append(...)`，迭代列表会一直变长
    # ⇒ 自检永不结束（第 83 轮实测：3 例被重复打印 809 次、进程挂住）。
    for name, expect_red, issues in list(cases):
        ok = bool(issues) == expect_red
        if not ok:
            failures += 1
        print(f"{'✅' if ok else '❌'} {name}：{'报红' if issues else '绿'}"
              f"（期望{'报红' if expect_red else '绿'}）"
              + (f" —— {issues[0]}" if issues and not expect_red else ""))


    after = {name: _sha(ROOT / name) for name in watched}
    unchanged = before == after
    if not unchanged:
        failures += 1
    print(f"{'✅' if unchanged else '❌'} 真仓库二十一份文件逐字节未变")
    total = len(cases) + 1
    print(f"自测通过（{total} 例）" if failures == 0 else f"自测失败：{failures}/{total} 例不符")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------- 主流程

def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    issues: list[Issue] = []
    issues += check_theme_set(ROOT)
    shape_issues, role_total = check_palette_shape(ROOT)
    issues += shape_issues
    threshold_issues, checks = check_thresholds(ROOT)
    issues += threshold_issues
    issues += check_syntax_binding(ROOT)
    name_issues, sites = check_names_and_pending(ROOT)
    issues += name_issues
    entry_issues, entry_sites = check_ui_entry(ROOT)
    issues += entry_issues
    axis_issues, axis_sites = check_two_axis(ROOT)
    issues += axis_issues
    nebula_issues, nebula_sites, nebula_snapshot = check_nebula_skin(ROOT)
    issues += nebula_issues
    issues += face_vs_package_issues(package_source_dirs(ROOT), SWIFT_FACE_ROOTS,
                                     FACE_ROOTS_NOT_A_TARGET)

    print("==> 主题集（配色方案，队列 L-80 ㈠ ㈡）")
    print(f"    ① 主题集：{len(theme_ids_in_source(ROOT))} 个（台账 {len(THEME_IDS)} 个：{', '.join(THEME_IDS)}）")
    print(f"    ② 值表角色：{role_total} 个字段（下限 {MIN_ROLES * MIN_THEMES}）")
    print(f"    ③ 独立复算：{checks} 条门槛（下限 {MIN_CHECKS}；本脚本自己实现 WCAG，与 Swift 单测互补）")
    print(f"    ④ 语法六档 ↔ 家族角色：{len(SYNTAX_BINDING)} 条映射对账")
    print(f"    ⑤ 名对齐 / 待值登记：{sites} 处文档落点")
    print(f"    ⑥ 界面入口：{entry_sites} 处落点（主题列表 / 三个真实场景 / 推导逐条标注 /"
          f" 强调色入口 / 宿主覆盖不落盘）")
    print(f"    ⑦ 两轴正交：{axis_sites} 处落点（深浅轴三态 / 两轴互不读取 / "
          f"{len(AXIS_STATES) * len(AXIS_SYSTEM_STATES) * len(THEME_IDS)} 组组合可达 / 组合到像素 / "
          f"面板显示当前深浅档）")
    print(f"    ⑧ 星云皮肤（队列 L-155）：{nebula_sites} 处落点（规则的唯一出处 / 键字面量在入库源码面"
          f"（{len(SWIFT_FACE_ROOTS)} 根 + 仓根）里只许出现在登记过的落点 —— 扫 "
          f"{nebula_snapshot['scannedFiles']} 份 / 命中 {len(nebula_snapshot['holders'])} 处"
          f"（{', '.join(h['path'] for h in nebula_snapshot['holders'])}）/ "
          f"生效条件两半都在且绘制侧只许调用 / 三层表面各自恰有一处 / 开关绑唯一写入口且只在**声明要星云的主题**下露面 / "
          f"规则单测与像素探针的落点都在位，探针还挂着 FILTER）")

    print(f"    ⑨ 面对账（`Package.swift` 现读）：{len(package_source_dirs(ROOT))} 个 target 源码目录"
          f" ↔ 面 {len(SWIFT_FACE_ROOTS)} 根（宿主面 = {', '.join(host_source_dirs(ROOT))}；"
          f"非 target 的根已登记 {len(FACE_ROOTS_NOT_A_TARGET)} 条理由）")

    if len(theme_ids_in_source(ROOT)) < MIN_THEMES:
        issues.append(Issue(THEMES_SWIFT, f"主题数 {len(theme_ids_in_source(ROOT))} < 下限 {MIN_THEMES}"))
    if role_total < MIN_ROLES * MIN_THEMES:
        issues.append(Issue(THEMES_SWIFT, f"值表字段合计 {role_total} < 下限 {MIN_ROLES * MIN_THEMES}"
                                         f" —— 扫描面被削过，不许通过"))
    if checks < MIN_CHECKS:
        issues.append(Issue("复算", f"只跑了 {checks} 条门槛（下限 {MIN_CHECKS}）—— 空跑不许通过"))
    if entry_sites < MIN_ENTRY_SITES:
        issues.append(Issue(APPEARANCE_SWIFT, f"界面入口只判了 {entry_sites} 处（下限 {MIN_ENTRY_SITES}）"
                                             f" —— 扫描面被削过，不许通过"))
    if nebula_sites < MIN_NEBULA_SITES:
        issues.append(Issue(NEBULA_PREF_SWIFT, f"判据 I 只判了 {nebula_sites} 处（下限 {MIN_NEBULA_SITES}）"
                                               f" —— 扫描面被削过，不许通过"))

    if issues:
        print(f"\n❌ {len(issues)} 处未过：")
        for issue in issues:
            print(f"   · {issue}")
        return 1
    print("\n✅ 主题集三选一：三套值表角色齐全、逐主题 × 深浅两态过门槛、名与 Linux 侧对齐、待值登记在位；"
          "界面入口（主题列表 + 每主题三个真实场景 + 推导逐条标注）已接上；"
          "两轴正交（深浅三态 × 配色五主题 = 30 组组合、跟随系统两态都过门槛、组合已到像素上）；"
          "星云皮肤（队列 L-155：规则唯一出处 + 三层表面各一处落点 + 开关绑唯一写入口且只在声明要星云的主题下露面 + "
          "规则单测与像素探针的落点都在位 + 判据面与 `Package.swift` 的 target 源码目录双向对账）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
