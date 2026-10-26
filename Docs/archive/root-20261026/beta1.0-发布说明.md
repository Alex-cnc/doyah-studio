# DoyahStudio `beta1.0` 发布说明（Beta 1 · 全量功能 · 2026-10-21）

> **由头**：前门催办「出包齐套（beta1 收口最后一公里）」= 派单 `T-20261021-001`（`origin: agent`）。四项要求：tag / 发布说明 / 包身份四项 / 装包终判。
> **本文件是发布说明的权威落点**（入库）；构建脚本读的那份在 `dist/发布说明-beta1.0.md`（`dist/` 被 `.gitignore` 忽略 ⇒ 不入库，只作构建输入与随交付目录的副本）。

## 一、本版交付面

Beta 1 = **全量功能**：工作区（多页签 / 编辑器 / 终端 / 外部程序 / 插件目录）· 数据库（PG / MySQL / GBase 连接 + SQL 编辑器）· 笔记（笔记本两层 + 待办清单 + 待办日历 + 冲突合并按「记录级 LWW · 留两版」）· AI 助手（对话面 + 智能体循环 + 记忆 + 灵魂 L0 + 外发日志）三模块齐；另有深空苍穹主题、壁纸皮肤。

**含 2026-10-18 人类主人四条人工点验的修复**：`FR-EDIT-29` 终端面板可拖拽高度 · `FR-EDIT-46` 关闭未保存页签三选（保存 / 丢弃 / 取消）· `FR-EDIT-48` ⌘L 勾选任务框 · `FR-EDIT-49` 括号 / 引号自动配对（含全角 `（［｛`）。

**相对上一份带身份卡的正式交付**（`包10` · `688f7ab8…` · 构建树 `db8c820`）：`git rev-list --count db8c820..HEAD` = **619 笔**（含合并）。

## 二、本版不做

1. 笔记正文 WYSIWYG 改造（`FR-RT-10/11`，派单 `T-20261008-050` 挂着未开工）。
2. MCP 写操作（只读优先口径）。
3. 长上下文压缩 / 检查点（`NFR-AI-07` 后置项）。
4. 对话式助手剩余条目（`FR-AI-32~51`，缺口已登记，不在本版）。
5. iOS / Windows / Linux 版（平台面归对侧；iOS Notes 规划到年底）。

## 三、包身份四项

| 项 | 值 |
|---|---|
| **目录或标识** | 交付 `/Users/alex/dev/doyah/交付-20261021-beta1.0/`（app + 身份卡 + sha256.txt）；构建出厂处 `~/.dsh/projects/DoyahStudio/dist/DoyahStudio-beta1.0.app` |
| **标签** | `beta1.0` —— 包内 `Info.plist` `DoyahReleaseLabel` 实测 `beta1.0`（`CFBundleShortVersionString=0.3.0` / `CFBundleVersion=3`）；Git tag `beta1.0`（打在 `17bfe49d`，注释含 sha256；**已推远端**，`git ls-remote --tags origin` 实测 `refs/tags/beta1.0` → `17bfe49d`） |
| **sha256（全 64 位）** | `10ac6bfe60d082d6d8270bdc24e45123f4719e2ba588bf819352da35a56e1c8d`（`Contents/MacOS/DoyahStudio` · `89283440` 字节 · arm64 单架构 · 非沙箱 · 签名 `DoyahStudio Local Dev`） |
| **构建时刻** | `2026-10-21T09:34:15+0800`（UTC `2026-10-21T01:34:16Z`） |

**构建树**：构建那一刻的工作树 = `6d835913` ＋ 本单改动（`RELEASE_LABEL` → `beta1.0` / 三处文档 / `project.pbxproj` 重生成）；同一份改动落为提交 **`45d84bab`**（rebase 到 `origin/master` 之后 · tag `beta1.0` 打在这笔上）。**本单 App / Core 零改动**（`git diff --stat -- App Core` 为空）；`origin/master` 在 `6d835913` 之后另有 **2 处 App/Core 改动，均非行为**（`Core/MenuLocalization.swift` 一行 doc 注释里的文档名写法 · `App/Resources/icons/README.md` 一行）⇒ 二进制与实际落地的 App/Core **行为等价**。

## 四、装包终判

- 装：用户级 `~/Applications/DoyahStudio-beta1.0.app`（`ditto` 自交付目录；装后二进制 sha256 = `10ac6bfe…` 一致）。
- 跑：进程起（pid 37921）、20 秒后仍在；`~/Library/Application Support/DoyahStudio/startup.log` 末三行 = `正常启动 pid=37921` / `许可证：ultra · 活动栏 [workspace,database,notes,retro] · License is valid` / `菜单栏自愈：1 项 → en`（顶栏 = `Doyah Studio File Edit View AI Agent Language Window Help`）；同刻 `workspace-history.json` 被重写 ⇒ 工作区主链读写通；`DiagnosticReports` 无本包崩溃记录。
- 退：`osascript quit` 正常退出。
- **结论**：装得上、起得来、四面活动栏齐、许可证与工作区状态正常落盘。**四条人工点验（29/46/48/49）需人在键盘前复验，本单不代人签字。**

## 五、验法（三步，人眼 / 机器均可）

1. `shasum -a 256 "<交付目录>/DoyahStudio-beta1.0.app/Contents/MacOS/DoyahStudio"` ⇒ `10ac6bfe60d082d6d8270bdc24e45123f4719e2ba588bf819352da35a56e1c8d`。
2. `/usr/libexec/PlistBuddy -c 'Print :DoyahReleaseLabel' "<…>/Contents/Info.plist"` ⇒ `beta1.0`。
3. `git tag -l beta1.0` ⇒ 有；`git tag -n1 beta1.0` 的注释含同一 sha256。

## 六、已知问题

1. 真机整屏截图未取（需人在场）。
2. 启动日志出现 `菜单栏自愈：1 项 → en` —— 有 1 个菜单项缺英文名被自愈补上，不影响启动，成因未追。
3. 盘上 `alpha3.1` 历史包共 10 份交付目录、身份互不相同 —— **旧包一律作废**，复测只认 `beta1.0` 与本文件第三节的 sha256。
4. 非沙箱包（交付口径）；上架所需沙箱版需 `DOYAH_SANDBOX=1` 另出，未做。
