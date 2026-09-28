# Doyah Studio · v0.2.0-alpha 发布说明（macOS · 三模块）

> 需求提出者 2026-09-28 拍板**方案 B**：**不等人工点验** —— 把三模块的机器可验部分推到全绿后发布，
> 待点验 / 需环境项**显式标注**（不假装验过）。
> 本文件是这一版的**范围口径**：能做什么、明确不做什么、怎么装、证据在哪。

| 项 | 值 |
| --- | --- |
| 版本 | **v0.2.0-alpha**（上一版 `v0.1.0-alpha` —— **只覆盖数据库模块**；本版**三模块**） |
| 日期 | 2026-09-28 |
| 构建产物 | `dist/DoyahStudio.app`，**release 构建**（`./Scripts/build-app.sh release`，**109 s** 编完），`CFBundleShortVersionString` = **0.2.0** / `CFBundleVersion` = **2**（构建脚本 `Scripts/build-app.sh` 的数值版本；发布标签 `v0.2.0-alpha` 是它的 alpha 标记） |
| 目标端 | macOS（沙箱构建 `dist/DoyahStudio.app`；非沙箱构建用 `DOYAH_NO_SANDBOX=1`）。架构 arm64（`lipo -info` 实测 `Non-fat file … arm64`）；Intel / 通用二进制见 `Docs/发布方案.md` §6 |
| 范围 | **三模块** —— 工作区 + 数据库 + 笔记（**Linux 端不在本机范围**：三书继续出、源码在公司机器） |
| 判定口径 | `./Scripts/alpha-main-chain-v0.2.sh` **本机段全绿 ⇒ alpha 功能面达成**（三档制：本机段判红绿 / 预期红只登记 / 环境段只登记，与 v1 逐字一致） |
| 本轮判定（2026-09-28 18:27–18:35 CST） | **达成** —— 本机段 **38 段全绿 / 红 0**（工作区 5 / 笔记 8 / **数据库模块委托 v1** 25） |
| 发布提交（tag 指向） | **`b9247d2`** —— 标签 **`v0.2.0-alpha`** 指向它（`git ls-remote --tags` 已核）。本文件里「发布提交」这一行是**发布后**回填的（提交里写不进自己的 sha），此后的小修不移动标签 |

## 一、这一版能做什么（三条主链，均已在真库 / 真进程上跑过）

**A 工作区模块**

1. **代码编辑器**：行号列（列宽按当前等宽字体实量）、行终止符认 `\n` / `\r\n` / `\r` / `U+2028` / `U+2029` / `U+0085`、末尾空行也给号
2. **多页签**：切换保留各自状态；语言层与文件类型识别
3. **内嵌终端**：输入编码（UTF-8 / GBK 等）、配色三态（跟随主题）与配色门禁
4. **命令面板（⌘K）**：清单 ↔ 分派器 ↔ 视图绑定三者对账（接线门禁）

**B 数据库模块**（与 `v0.1.0-alpha` 同一条主链，本版**委托** v1 持有 25 段清单）

1. **连接**：本机 / 远程 PostgreSQL，失败态给可读原因（不是裸驱动码）
2. **对象树**：服务器 → 库 → schema → 表 → 列（含类型）逐层钻取；对象 DDL
3. **写与执行 SQL**：参数化查询、执行计划、结果集
4. **结果集**：客户端排序 / 筛选 / 分页、复制为多格式、行详情、外键跳转
5. **导出**：整表导出、结果集导出 xlsx（产物用另一份实现拆开核对）
6. **表结构**：表设计器改列并实时预览 DDL、索引 / 外键 / 约束
7. **写回**：结果集内联编辑（主键定位、一批一事务、提交前预览 DML）
8. **导入**：CSV / JSON / Excel（.xlsx）
9. **事务与合成数据**：失败不留半截状态；同 seed 可复现
10. **服务器对象 / 会话 / 锁 / 统计 / 维护任务 / ER 图 / SSH 隧道 / MySQL 方言**

**C 笔记模块**

1. **装配**：同进程装配 + 笔记侧与数据库 / Ultra 侧**解耦**（两条门禁：隔离 / 装配链）
2. **本地库**：数据家在工程数据家**之外**、迁移留备份、坏文件绝不覆盖；存储引擎 = vendored SQLite（台账对账 + 现编现跑自证）
3. **检索**：走库（唯一生产点），走的哪条路（全文 / 子串兜底 / 检索没跑成）**如实标注**；**零网络出口**（笔记数据不外发）

## 二、alpha **明确不含**（不是缺陷，是范围）

**逐条理由与证据指针**见 **`Docs/design/alpha-0.2.0-FR判定.md`**（本说明**引用它**，不另抄一份）。
`python3 Scripts/report-requirements.py` 盘点的 **FR 🟡 52 条**，判定分布：

| 档位 | 条数 | 含义 |
| --- | --- | --- |
| `ui-click` | **37** | 界面点击 / 观感只能人工（清单：`Docs/design/待人工验收清单.md`、`Docs/人工点验-单击清单-macOS-20260927.md`） |
| `environment` | **6** | 本机物理不可能（下述编号） |
| `device-instance` | **5** | 需真机 / 外部实例 / 外部软件（真实模型端点、GBase 真机、Excel/Numbers 打开 xlsx、大表基准） |
| `not-implemented` | **2** | 本 alpha 明确不含的未做功能（`FR-AI-10` 的 `resources/read` 与 host 方向、`FR-PLUG-05` 的 ①③④） |
| `needs-decision` | **1** | 等需求提出者拍板（`FR-IO-04` 沙箱起子进程，队列 `L-10`） |
| `open-defect` | **1** | 点验发现的缺陷：`FR-CONN-15` 侧边栏折叠状态活不过一次活动栏切换（已开队列 **`L-59`**，修完复验） |

**环境档 6 条**（`FR-EDIT-29` 归此档并写明两因）：`FR-META-02` / `FR-DRV-08`（无 GBase 8a 实例）、
`FR-DIAG-03`（本机 pgserver 精简构建无扩展目录 ⇒ `pg_stat_statements` 装不上）、`FR-CONN-18`（沙箱下起不了 ssh 子进程）、
`FR-IO-02`（vendored 驱动只实现 `CopyFrom`，缺 `COPY … TO STDOUT`）、`FR-EDIT-29`（沙箱下 `^C` / 作业控制不可靠 +
多会话与图形协议未做）。**`FR-DRV-09`（MySQL 真机）已 ✅，不再计入本档。**

**状态口径**：以上条目在需求书里**仍是 🟡，不改成 ✅**（`v3.252` 给 6 条、`v3.262` 给 47 条状态格追加 `**[alpha 不含]**（原因）`）
—— 只把「未验证」与「已验」分开，**不假装已验**。判定**不碰状态位**：`report-requirements.py` 计数与判定前一致（**176：124 ✅ / 52 🟡 / 0 ⬜**）。

## 三、怎么装怎么跑

```bash
cd ~/.dsh/projects/DoyahStudio
./Scripts/build-app.sh                 # 沙箱构建（默认）→ dist/DoyahStudio.app
DOYAH_NO_SANDBOX=1 ./Scripts/build-app.sh   # 本机自用非沙箱构建（内嵌终端才是完整 shell）
open dist/DoyahStudio.app
```

**许可证**（三档呈现）：沙箱构建的数据目录在容器里，许可证要放这里 ——
`~/Library/Containers/studio.doyah.DoyahStudio/Data/Library/Application Support/DoyahStudio/license.doyahlicense`
（非沙箱构建则是 `~/Library/Application Support/DoyahStudio/license.doyahlicense`）。
换档一行命令：`bash ~/.doyah-license/换档.sh ultra|pro|standard|tampered|none`，再点菜单「Doyah Studio → 版本与许可证…」→「重新读取许可证」（不用重启）。
**没放许可证 = Standard（只剩笔记）**，这是设计行为。自查：`tail -3 <数据目录>/startup.log`。

## 四、证据在哪

| 证据 | 命令 / 位置 |
| --- | --- |
| 三模块主链（条件 ①） | `./Scripts/alpha-main-chain-v0.2.sh` → 证据 `.build/alpha-0.2.0/主链证据.md` |
| 工程闭环（条件 ②，18 项） | `./Scripts/verify-all.sh` |
| FR 🟡 逐条判定（条件 ③） | `python3 Scripts/check-alpha-fr-dispositions.py`（`--self-test` 11 例）＋ 人读表 `Docs/design/alpha-0.2.0-FR判定.md` |
| release 产物与启动（条件 ④） | 本文件 §五；`dist/DoyahStudio.app` + `codesign --verify --deep --strict` |
| 需求完成度（机械派生） | `python3 Scripts/report-requirements.py`（FR 176 条：✅124 / 🟡52 / ⬜0） |
| Core 单测 | `./Scripts/verify-core.sh`（2000+ 项） |
| 人工点验清单 | `Docs/design/待人工验收清单.md`、`Docs/人工点验-单击清单-macOS-20260927.md` |

## 五、启动实测记录（release 产物，2026-09-28 18:27 CST）

产物签名与版本自查：

```
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/DoyahStudio.app/Contents/Info.plist  → 0.2.0
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion"            dist/DoyahStudio.app/Contents/Info.plist  → 2
codesign --verify --deep --strict --verbose=2 dist/DoyahStudio.app  → valid on disk / satisfies its Designated Requirement
lipo -info dist/DoyahStudio.app/Contents/MacOS/DoyahStudio          → Non-fat file … arm64
```

**活动栏三模块 + 许可证档位**（机器可读证据 = 沙箱数据目录的 `startup.log`，无需人点）：

| 装哪一档 | `startup.log` 实测行 | 结论 |
| --- | --- | --- |
| `ultra` | `2026-09-28T10:27:25Z 许可证：ultra / 活动栏 [workspace,database,notes] / License is valid` | 三模块活动栏确实出齐 |
| `standard` | `2026-09-28T10:27:39Z 许可证：standard / 活动栏 [notes] / License is valid` | 降档只剩笔记，符合设计 |

（时间是 UTC，本机 CST = UTC+8；两档跑完已把容器里的许可证**还原为跑前的 `ultra`**，sha256 前后一致。）

## 六、已知问题

- `FR-CONN-15`：连接侧边栏分组的**折叠状态活不过一次活动栏切换**（`collapsedGroups` 是视图局部 `@State`）—— 已开队列 **`L-59`**，属「点验未过的缺陷」，本版**不含**修复（**2026-09-28 第 58 轮已在 `master` 修掉：状态上移到 `AppState` + 两层判据；**本版 tag `v0.2.0-alpha`（`b9247d2`）的产物仍含此缺陷**，修复随下一次构建生效**）
- 沙箱构建下 `^C` 打断前台作业不可靠（属分发路线，不算缺陷）
- 沙箱构建看不到 `~/.ssh` 之外的路径，SSH 隧道只在非沙箱构建可用
- 许可证篡改会降级到 Standard（设计如此，笔记数据不锁）
- `Docs/design/开发循环-任务队列.md` 与 spec 台账是**本机文件**（gitignore），不入库

## 七、下一步

1. **`L-59` 已修（2026-09-28 第 58 轮，随下一版构建生效）** —— 复验动作见 `Docs/design/待人工验收清单.md` 的 `FR-CONN-15` 那一行；**`L-50`（空编辑器「保存」可点却静默无反应）仍在等你定口径**（灰着 / 可点但给理由 / 允许落一条空笔记）
2. **界面点验批次**（37 条 `ui-click`）：照 `Docs/人工点验-单击清单-macOS-20260927.md` 走，点完把 🟡 改成 ✅
3. 把「明确不含」逐条转正：GBase / MySQL 实例、`pg_stat_statements`、**沙箱放宽（等你拍板 `FR-IO-04`）**、vendor 两处
4. 工作区模块继续补（`L-60` 合成数据纯空态 / `L-61` 面板根对齐纪律 / `L-63` 剩余 4 条旁路脚本转正）
