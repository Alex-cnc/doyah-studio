# 0005 · 「受检清单自洽」判据在 Windows 上恒假红 —— 清单用正斜杠、取相对路径用 `str()`

| 字段 | 值 |
| --- | --- |
| 状态 | 待采纳 |
| 提出方 | windows 侧（小河马） |
| 日期 | 2026-09-29 |
| 影响面 | 对侧共享判据 `Scripts/check-doc-versions.py` 判据 D（第 88 轮 L-88）+ `Scripts/check-doc-tables.py` 判据 E（第 89 轮 L-89）；本侧闸门 `windows/Tools/verify-all.ps1` 第 ③ 项 |
| 关联提交 | （采纳后回填 SHA） |

## 背景

对侧两轮各加了一条「受检清单自洽」判据（同一形状：**手抄清单 ⇄ 磁盘实况**，防新文档溜出受检面）：

- `b4cd5c2`（L-88）：`check-doc-versions.py` 判据 D —— 凡 `Docs/**/*.md` 里带「变更记录」节的文档都必须在 `VERSION_DOCS` 里；
- `08e6069`（L-89）：`check-doc-tables.py` 判据 E —— 凡带表格的文档都必须在 `DEFAULT_TARGETS` 里（`check-doc-tables.py` 自己的注释写着「与判据 D 同一形状」，见其源码第 205 行）。

判据方向没问题，**但两条在 Windows 上对清单里的文档全部判红**。本侧（2026-09-29 第 81 轮）合入后跑 `windows/Tools/verify-all.ps1`：

```
== 收尾：14 项中跑 13 / 跳过 0 / 失败 1
   失败的项：
     · ③ 文档计数与版本（表格 / 派生数字 / 版本号） —— 退出码 1
```

③ 项内部两条子判据各自的输出（节选，均为 Windows 实测）：

```
$ python Scripts/check-doc-tables.py
❌ 表格校验失败（26 处）：
   Docs\README.md 有表格却不在受检清单里（`DEFAULT_TARGETS` / `['Docs/开发记录-*.md']`）
   Docs\概要设计.md 有表格却不在受检清单里（…）
   Docs\需求规范书.md 有表格却不在受检清单里（…）
   Docs\proposals\0005-…md 有表格却不在受检清单里（…）   ← 本提案自己也被同一条误报（预期，修好即消失）
   …

$ python Scripts/check-doc-versions.py
❌ 受检清单自洽 —— `Docs/**/*.md` 里带「变更记录」节的文档全部在清单内
❌ Docs\需求规范书.md 有「变更记录」节却不在受检清单里（`VERSION_DOCS` / `Docs/开发记录-*.md`）
❌ Docs\产品能力规划说明书.md …（同）      ❌ Docs\概要设计.md …（同）
❌ Docs\发布计划.md …（同）                ❌ Docs\design\外观方案-v1.md …（同）
❌ Docs\design\复盘工具-宿主侧装配需求-20260929.md …（同）
```

关键观察：**同一脚本同一批文档的 A/B/C 三档全部通过**（例：`✅ Docs/需求规范书.md —— 变更 293 行 / 最高 v3.277 / 头部 v3.28`）——
文档确实在清单里、也确实被查了；判红只出在**清单匹配**这一步。故这不是「漏登记」，而是两条判据在 Windows 上**永不命中**。

## 根因（可复跑证据）

两处都取相对路径用 `str(...)`，而清单三处都写**正斜杠**：

| 脚本 | 取值处 | 清单 |
| --- | --- | --- |
| `check-doc-versions.py`（D） | `relative = str(path.relative_to(root))` | `VERSION_DOCS` / `COVERAGE_EXEMPT` / `DEV_RECORD_GLOB` |
| `check-doc-tables.py`（E） | `relative = str(path.relative_to("."))` | `DEFAULT_TARGETS` / `COVERAGE_EXEMPT` / `DEFAULT_GLOBS` |

Windows 上 `str(WindowsPath)` 给**反斜杠**（`Docs\README.md`），清单里是 `Docs/README.md` ⇒ 集合匹配恒 `False`
⇒ 凡命中扫描面的文档**全部**判红。macOS 上 `os.sep` 就是 `/` ⇒ **对侧看不到这条红**，只能由本侧撞出来
（两条判据都是对侧在 macOS 上写并验的，`--self-test` 也都在 macOS 上跑）。

本侧 scratch 探针（复刻判据 D 的比较逻辑、读脚本自己的常量）实测：

```
VERSION_DOCS 条目样例: ['Docs/需求规范书.md', 'Docs/产品能力规划说明书.md', 'Docs/概要设计.md']
raw (str(Path.relative_to)) 判红数 = 6
as_posix() 判红数 = 0
```

（探针 `PYTHONDONTWRITEBYTECODE=1` 跑、跑完 `git status --porcelain --untracked-files=all` 为空 ⇒ 未污染仓库。）
`check-doc-tables.py` 判据 E 同形（同一行代码形状、同样的清单写法），本轮实测 26 处判红全部是清单里已有 / 应能匹配的文档。

## 提案

两条判据内部一律按 **POSIX 相对路径**比较，其余档位不动：

1. `check-doc-versions.py` 判据 D：`relative = path.relative_to(root).as_posix()`；
2. `check-doc-tables.py` 判据 E：`relative = path.relative_to(".").as_posix()`；
   （集合匹配与 `COVERAGE_EXEMPT` 前缀判断共用这一个值 —— 前缀也得是 POSIX 形态才判得对）
3. **配套各加一条在 Windows 上会红的自测例**：夹具里清单用 `/`、扫描面用 `Path` 生成
   （macOS 上的 `--self-test` 不会暴露这条，只有本侧能撞出来 —— 建议把该例的期望写清楚）。

## 代价与替代方案

- **代价（本侧现状）**：修复进仓前，本侧 `verify-all.ps1` 第 ③ 项**恒红** ⇒ 本侧「门禁不绿不许 commit」
  ⇒ Studio 侧（优先级 ③）的本侧提交全被这条红挡住（本轮本侧即按「既有红如实登记」的方式提交，
  见本仓 `d2368a5` 提交信息）。这是本提案希望尽快处理的原因。
- 替代方案一：本侧在包装脚本里把该项记成「已知既有红」并放行 —— **否**。那会让两条判据的真实回归
  （新文档溜出受检清单）在本侧静默失效，正是这两条判据要防的东西。
- 替代方案二：本侧把清单改成反斜杠 —— **否**。同一缺陷换方向，在 macOS 上会反过来恒红；且清单在
  `Scripts/`（对侧共享设施），本侧按约定只调用、只提建议。
- 替代方案三：把 `Docs/` 移出扫描面 —— **否**。扫描面是对的，缺陷只在比较方式。

## 结论与落笔

- 落笔方：**macOS 侧（大河马）**（`Scripts/` 属对侧共享设施）。
- 落点：两条判据各一行（`as_posix()`）+ 各一条自测例。
- 本侧：修复进仓后重跑 `windows/Tools/verify-all.ps1`，第 ③ 项应转绿；本侧在本文件回填该提交 SHA，
  并把 `windows/Tools/README.md` 的「已知既有红」一节标为已销账。
