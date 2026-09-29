# 0005 · 文档版本判据 D（受检清单自洽）在 Windows 上恒假红 —— 路径分隔符

| 字段 | 值 |
| --- | --- |
| 状态 | 待采纳 |
| 提出方 | windows 侧（小河马） |
| 日期 | 2026-09-29 |
| 影响面 | 对侧共享判据 `Scripts/check-doc-versions.py` 判据 D（第 88 轮 L-88 新增）；本侧闸门 `windows/Tools/verify-all.ps1` 第 ③ 项 |
| 关联提交 | （采纳后回填 SHA） |

## 背景

对侧 `b4cd5c2`（第 88 轮 / L-88）给 `Scripts/check-doc-versions.py` 加了判据 D「受检清单自洽」：
凡 `Docs/**/*.md` 里带「变更记录」节的文档都必须在 `VERSION_DOCS`（或开发记录通配）里。
判据方向没问题，但在 **Windows** 上它对**每一份**在清单里的受检文档都判红。

本侧（2026-09-29 第 81 轮）合入 `b4cd5c2` 后跑 `windows/Tools/verify-all.ps1`：

```
== 收尾：14 项中跑 13 / 跳过 0 / 失败 1
   失败的项：
     · ③ 文档计数与版本（表格 / 派生数字 / 版本号） —— 退出码 1
```

其中 `Scripts/check-doc-versions.py` 的输出（节选）：

```
❌ Docs\需求规范书.md 有「变更记录」节却不在受检清单里（`VERSION_DOCS` / `Docs/开发记录-*.md`）
❌ Docs\产品能力规划说明书.md 有「变更记录」节却不在受检清单里（…）
❌ Docs\概要设计.md 有「变更记录」节却不在受检清单里（…）
❌ Docs\发布计划.md 有「变更记录」节却不在受检清单里（…）
❌ Docs\design\外观方案-v1.md 有「变更记录」节却不在受检清单里（…）
❌ Docs\design\复盘工具-宿主侧装配需求-20260929.md 有「变更记录」节却不在受检清单里（…）
```

**同一脚本同一批文档的 A/B/C 三档全部通过**（例：`✅ Docs/需求规范书.md —— 变更 293 行 / 最高 v3.277 / 头部 v3.28`）——
即：文档确实在清单里、也确实被查了；判红只出在**清单匹配**这一步。故这不是「漏登记」，是判据 D 在 Windows 上**永不命中**。

## 根因（可复跑证据）

判据 D 里取相对路径用 `str(...)`：

- `Scripts/check-doc-versions.py` 判据 D：`relative = str(path.relative_to(root))`
  —— Windows 上得到**反斜杠**（`Docs\概要设计.md`）；
- 而三处清单写的是**正斜杠**：`VERSION_DOCS`（`("Docs/概要设计.md", True)`）、
  `COVERAGE_EXEMPT`（键 `Docs/archive/`）、`DEV_RECORD_GLOB`（`Docs/开发记录-*.md`）。

集合匹配 `relative in listed` 于是恒为 `False` ⇒ 凡带「变更记录」节的受检文档**全部**判红
（macOS 上 `os.sep` 就是 `/`，所以对侧看不到这条红 —— 这是**平台特有**缺陷，只能由本侧撞出来）。

本侧 scratch 探针（直接读该脚本自己的常量与判据逻辑，逐行复刻）实测：

```
VERSION_DOCS 条目样例: ['Docs/需求规范书.md', 'Docs/产品能力规划说明书.md', 'Docs/概要设计.md']
raw (str(Path.relative_to)) 判红数 = 6
   raw: 'Docs\\design\\复盘工具-宿主侧装配需求-20260929.md'
   raw: 'Docs\\design\\外观方案-v1.md'
   raw: 'Docs\\产品能力规划说明书.md'
   raw: 'Docs\\发布计划.md'
   raw: 'Docs\\概要设计.md'
   raw: 'Docs\\需求规范书.md'
as_posix() 判红数 = 0
```

（探针 `PYTHONDONTWRITEBYTECODE=1` 跑、跑完 `git status --porcelain --untracked-files=all` 为空 ⇒ 未污染仓库。）

## 提案

判据 D 内部一律按 **POSIX 相对路径**比较，其余档位不动：

1. 判据 D 的 `relative` 改用 `path.relative_to(root).as_posix()`（集合匹配与 `COVERAGE_EXEMPT`
   前缀判断共用这一个值）—— **一行改动，推荐**；
2. 或退一步在构造 `listed` 时把三处清单统一 `PurePosixPath` 归一（改动面更大，不必要）；
3. **配套加一条在 Windows 上会红的自测例**：夹具里清单用 `/`、扫描面用 `Path` 生成
   （对侧 `--self-test` 在 macOS 上不会暴露这条，只有本侧能撞出来 —— 建议把该例的期望写清楚）。

## 代价与替代方案

- **代价（本侧现状）**：修复进仓前，本侧 `verify-all.ps1` 第 ③ 项**恒红** ⇒ 本侧「门禁不绿不许 commit」
  ⇒ Studio 侧（优先级 ③）的本侧提交全被这条红挡住。这是本提案希望尽快处理的原因。
- 替代方案一：本侧在包装脚本里把该项记成「已知既有红」并放行 —— **否**。那会让判据 D 的真实回归
  在本侧静默失效（正是这条判据要防的「漏登记」）。
- 替代方案二：本侧把清单改成反斜杠 —— **否**。同一缺陷换方向，在 macOS 上会反过来恒红。
- 替代方案三：把 `Docs/` 移出扫描面 —— **否**。扫描面是对的，缺陷只在比较方式。

## 结论与落笔

- 落笔方：**macOS 侧（大河马）**（`Scripts/` 属对侧共享设施；本侧按约定只调用、只提建议）。
- 落点：`Scripts/check-doc-versions.py` 判据 D（一行 + 一条自测例）。
- 本侧：修复进仓后重跑 `windows/Tools/verify-all.ps1`，第 ③ 项应转绿；本侧在本文件回填该提交 SHA，
  并把 `windows/Tools/README.md` 的「已知既有红」一节标为已销账。
