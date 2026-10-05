# platform/macos/ —— macOS 端（DoyahStudio macOS 格） [独占:macos]

> **标题行的 `[独占:macos]` 是给门禁看的**：本文件整篇判归 macOS 侧 —— 对侧改本文件会被
> `Scripts/check-exclusive-sections.py` 判红；本侧改它一律合法。
>
> **维护者**：**铁皮大河马**（macOS 机组组长 · `bighippo`）→ 组员 **`macos-dev`** ——
> 本文件 = `DoyahStudio` **macOS 端实现落点**的目录声明 + **本格目录约定** +
> **本格与仓级回归入口 `Scripts/verify-all.sh` 的关系** + **本格边界**。
>
> **状态（2026-10-05 实读）**：**落点已建、工程本体已在格内** —— 本仓与兄弟仓（DoyahNotes / DoyahRetro）
> 的同类格不同：macOS 端**不是空落点**，而是把**仓根 Swift 族整体前移**进来（13 条落点，884 条 `git mv`）。

**落点定案**：本目录 = **macOS 端的实现目录**（与 `platform/{windows,ios,android,harmony,linux}/` 并列），
**不另开独立仓**。技术栈（清单口径）= **Swift + SwiftUI / AppKit**（`Scripts/path-ownership.json` 的 `macos` 树）；
契约的**单一事实源**是 `Docs/` 三书 —— **本目录不得另写一份契约**（改契约走 `Docs/proposals/`，归前门 `bluewhale`）。

**为什么搬迁是「macOS 侧先搬」**（人类主人令 · 派活单 `T-20261005-053`）：本机盘不区分大小写 ——
仓根原先就有一份受版本控制的 `Platform/macOS/*.swift`，而目标结构是 `platform/<平台>/`，
两者在不区分大小写的盘上是**同一个目录** ⇒ 必须 macOS 侧先把仓根 Swift 树搬进新结构，
对侧（Windows 机组）才可能落 `platform/windows/`。

## 归属与协作（本格边界）

- **归属**：组员 **`macos-dev`**（组长 铁皮大河马 / `bighippo`）—— 独占口径 = **`DoyahStudio/platform/macos/**`**。
- **清单口径**（`Scripts/path-ownership.json`）：`id = macos` · `owner = macos` · `hosts = [darwin]` · `actor = bighippo`。
- **禁区**（本格一字不写）：其它平台目录（`platform/windows/**` 等，归 Windows 机组 `fatshark`）·
  `Docs/**` 契约层（归前门 `bluewhale`）· 技能共享仓 · 对侧机组的任何目录。
- **共享面**（不算越界，但要声明）：`Scripts/**` · `AGENT-SPEC.md` —— 判据本体**只跑不改**；
  清单 / 台账跟版走声明式台账（`shared-surface: 理由`）。
- **协作方式**：**不经派单信箱**、无信箱代号 —— **从组长领单、向组长回单**，走 **Hermes 内部 kanban**；
  产出要**可机械复核**（构建 / 闸门 / 提交号）。人类主人不直接指挥组员。
- **提交纪律**：先 `git fetch` 与远端对账（push 被拒就 `rebase` 重放，不 force push、不改历史）；
  **提交用显式路径，禁 `git add -A`**。

## 本格目录约定（写什么 · 不写什么）

| 路径 | 是什么 | 谁守它 |
|---|---|---|
| `README.md`（本文件） | 本格的一页声明：目录约定 + 边界 + 与仓级回归入口的关系；**只此一页** | 人读 + 越界判据（独占节） |
| `Package.swift` · `Package.resolved` · `project.yml` | 包根与工程定义（SwiftPM / XcodeGen 源） | 本格 + 第 1 项单测、第 18 项生成物一致性 |
| `DoyahStudio.xcodeproj/` | **生成物**（由 `project.yml` 生成）—— 与源双向不许漂移 | 第 18 项（生成物一致性） |
| `App/` | SwiftUI 界面层（视图 / 状态模型 / 资源） | 本格 + 设计令牌与界面接线各项 |
| `Core/` | 领域层 —— **不得出现平台专属依赖**（否则主机侧之外编译不过） | 本格 + 第 2 项平台中立性 |
| `CLI/` | 命令行入口 | 本格 |
| `Platform/macOS/` | 平台适配层（钥匙串 / 目录授权 / 沙箱书签 / 浏览器引擎）—— **注意**：这是**适配层目录**，与仓根那个 `platform/` 新结构**不是一回事**（搬迁时先临时改名再落位，绕开不区分大小写的盘） | 本格 |
| `Tests/` · `TestsPlatform/` · `TestsUISnapshot/` | 单测 / 平台适配层单测 / 界面快照 | 本格 + 第 1 项 |
| `Tools/` · `Vendor/` | 许可工具 + vendored 依赖（sqlite3 / mysql-nio / postgres-nio；包根相对路径引用，故必须与包根同搬） | 本格 + 第 17 项 vendored SQLite |

约定三条（与兄弟格同形）：

- **只放 macOS 端实现层**：工程 / 源码 / 本端构建与自检入口 / 本端实现笔记。**契约条文不在这里**。
- **不建空文件 / 空目录**：没有内容的落点就让它空着 ——「看起来开工了」的占位会进受检集合，变成假进度。
- **一页 + 变更记录**：本格的状态陈述只在本文件写一处；改了就在文末变更记录补一行，不另开一份。

## 与 `Scripts/verify-all.sh` 的关系（本格怎么机检）

`Scripts/` 在**仓根**（共享面，不在本格内）—— 它是**两侧共同调用**的仓级回归入口，
本格只被它判，不复制一份。本机（`uname -s` = `Darwin`）跑法：

```bash
bash Scripts/verify-all.sh              # 十八项闭环；本机 PLATFORM=macos ⇒ 十八项全跑
bash Scripts/verify-all.sh --require-all  # 把「跳过」也判红（跳过 ≠ 通过）
```

- **十八项的组成**：① Core 与平台适配层单测 ② 平台中立性 ③ 本地化（四条棘轮）④ 文档表格与派生计数
  ⑤ 需求状态一致性 ⑥ 设计令牌棘轮 ⑦ 平台等价矩阵 ⑧ 平台中立性棘轮 ⑨ 界面接线与状态归属
  ⑩ 插件装配链 ⑪ 打包 `.app` ⑫ 脚本多字节安全 ⑬ 脚本连接信息参数化 ⑭ 连接失败文案覆盖面
  ⑮ 命令行失败可读化 ⑯ **越界检查（独占节 + 路径归属）** ⑰ vendored SQLite ⑱ 生成物一致性。
- **第 1 项 = `Scripts/verify-core.sh`**：以**仓根为包根**（`swift test --package-path .`，
  工具链 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`），并把单测数写进
  `.build/core-test-count.txt` 供第 4 项的「文档数字唯一来源」台账对账。
- **与搬迁的关系（如实登记 · 必须读的一段）**：本格落点前移后，**仓根已不是包根**，而 `Scripts/**`
  里的**路径字面量尚未跟版**（机器实测：可直接机械跟版的路径字面量 **1118 处 / 91 文件** +
  裸目录名字面量 **65 处**（功能卡点，须逐文件改基准）+ **19 份构建脚本**的 cwd / `--package-path`；
  明细见派活单 `T-20261005-062` 的 `path-inventory`）。⇒ **在本分支上第 1 项即红，十八项跑不完**
  （`master` 保持旧布局，照旧绿）。这条**不是本格的功能缺陷**，是「搬迁的判据面跟版」尚未落定；
  它需要拍板「谁执行」，不并入 `master` 的原因就写在这里，不许含糊成「应该没问题」。
- **本格可单独跑的两条**（即第 16 项的两个判据本体，只跑不改）：

```bash
DOYAH_SIDE=macos python3 Scripts/check-exclusive-sections.py   # 文档独占节（标题行标记）
DOYAH_SIDE=macos python3 Scripts/check-path-ownership.py       # 盘上路径归属（清单 = Scripts/path-ownership.json）
```

- **实测读数（2026-10-05 · 本格 v1.0 提交前）**：

| 判据 | 读数 |
|---|---|
| `bash Scripts/verify-all.sh` | **exit 1（红）** —— 停在 `==> 1/18`，判词逐字：`error: Could not find Package.swift in this directory or any of its parent directories.`（根因见上：仓根已非包根、`Scripts/**` 路径字面量未跟版；`master` 上是旧布局，同一命令照旧绿） |
| `python3 Scripts/check-path-ownership.py` | **exit 0** —— 受检 886 条：共享面 1 / 本侧 885 / 对侧 0 / 白名单 0 / 未登记 0 |
| `DOYAH_SIDE=macos python3 Scripts/check-exclusive-sections.py` | **exit 0**（本文件整篇判归 macOS 侧；标题行标记生效） |

- **退出码协议**：`verify-all.sh` —— `0` = 十八项全过；非 `0` = 有项判红（脚本 `set -euo pipefail`，
  第一处失败即终止）；带 `--require-all` 时「跳过」也判红。`check-path-ownership.py` ——
  `0` 绿 / `1` 判红并点名文件 / `2` 拿不到基线（含**清单过期**、**本地落后远端**、侧名不在词表内）。
- **自检入口 ≠ 功能进度**：判据全绿证明的是「本格的目录归属与既有判据面对得上」，**不代表功能改动**；
  能力面进度以 `Docs/` 的对应状态表为准 —— **本文件不抄清单内容**（抄了就会漂）。

## 未落面（如实登记）

- **`Scripts/**` 路径字面量跟版未做** —— 这是 `verify-all.sh` 在**本分支**上判红的唯一原因，
  也是本格暂不并入 `master` 的原因；机器实测改面见派活单 `T-20261005-062`（`path-inventory`），
  卡在「由谁执行」的拍板（人类主人已放行**半径**：只改路径、不改语义）。
- **对侧 `platform/windows/` 未落** —— 归 Windows 机组 `fatshark`；本格先落位，对侧随后（急用可基于本分支动工）。
- **本格尚无自己的端上自检入口** —— 兄弟仓的格各有 `gate` 类脚本（如 `platform/windows/gate.ps1`），
  本格的机检**全部**经由仓根 `Scripts/` 闭环；如后续要开本格自检入口，另开一单，不在本页许诺。
- **本文件不重复工程细节** —— 目录内每个子树的实现口径以源码与 `Docs/` 为准。

## 变更记录

| 版本 | 日期 | 说明 |
|---|---|---|
| v1.0 | 2026-10-05 | **建立**（人类主人令 · 派活单 `T-20261005-053` 片A / 任务 `t_a68ad964`）：目录统一 `platform/<平台>/` 后补上本格一页声明 —— 本格目录约定（13 条落点逐条）、与 `Scripts/verify-all.sh` 的关系（十八项组成 + 第 1 项包根口径 + 搬迁未跟版的如实登记 + 本格可单独跑的两条判据 + 2026-10-05 实测读数）、边界与未落面；**产品代码一字未动**（本轮只新增本文件 + 清单跟版一行） |
