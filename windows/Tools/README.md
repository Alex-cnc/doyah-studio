# windows/Tools —— Windows 侧的闭环闸门（§8.3.1 / §8.5.3 的等价物）

**状态**：🟡 实现本体**首片已落地**（`Core/`〔Rust〕+ `Bench/grid/`，2026-09-28 第 24 轮开工令换栈后）；**闸门 13 项已就位**（2026-09-27 第 21 轮起，第 24 轮由 12 项扩）—— 口径是「先有闸门再有功能」。
本目录只放闸门；实现代码（`Cargo.toml` / `Core/`〔Rust〕/ `App/`〔Tauri 2 + Vue 3〕/ `Cli/` / `Platform/Windows/` / `Bench/`）按 §8.5.1 另建。

## 一条命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tools\verify-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tools\verify-all.ps1 -RequireAll   # 跳过即红
pwsh -File windows\Tools\verify-all.ps1 -Base HEAD~1                                           # 越界判据换基线
```

（也可在 PowerShell 会话里 `.\windows\Tools\verify-all.ps1`；执行策略 RemoteSigned 即可，脚本是本地文件、未签名也能跑。）

## 判据归属：判据不重写，只编排

| 事项 | 归属 |
|---|---|
| 文档表格 / 派生数字 / 版本号 / 取号 | 契约层 `Scripts/*.py`（本侧**调用**，不重写 —— §8.4 文档单一来源） |
| 平台中立性、独占节越界、平台等价矩阵 | 同上（`Scripts/*.py`） |
| 领域层边界 / 设计令牌棘轮 / 构建 / 单测 / 一条命令跑全 | **本侧实现**（Swift 专用判据无法在 Windows 跑，按同规则名重建） |

「另一平台再写一份表格解析器」等于造第二份判据，迟早两边不一致 —— 故 PowerShell 只管：探测解释器、传本侧姿势的参数、记「跑了 / 跳过」、汇总退出码。

## 退出码协议（与 §8.3.2 的「跳过 ≠ 通过」对齐）

| 码 | 含义 |
|---|---|
| 0 | 跑过且通过 |
| 1 | 判红 |
| 2 | **跳过**（平台不适用 / 依赖未就位）—— 跳过必须逐条列出，`-RequireAll` 时判红 |

`verify-all.ps1` 收尾行如实写「N 项中跑 X / 跳过 Y / 失败 Z」并逐条列出跳过的项：**等价物可以缺席，但缺席必须可见**。

## 文件 ↔ §8.3.1 六项必需项

| §8.3.1 | 本目录文件 | 现状（2026-09-27 实测） |
|---|---|---|
| ① 构建入口 | `build.ps1` | ✅ 跑（`cargo build --release` 工作区；前端 `vite build` 待 `windows\App` 落地） |
| ② 单测 | `test.ps1` | ✅ 跑（`cargo test --workspace`；前端 `vitest` 同链路） |
| ③ 文档计数 | `check-doc-tables.ps1` | ✅ 跑（共享判据 + `--require-all` 透传） |
| ④ 独占节越界 | `check-exclusive-sections.ps1` | ✅ 跑（显式 `--mine windows`，默认基线 `origin/master`） |
| ⑤ 平台矩阵 | `check-platform-parity.ps1` | ✅ 跑（共享判据 + **本侧如实性判据**：未开工时台账不许有 overrides） |
| （契约侧 L-45，第 22 轮新增）| `check-p-parity.ps1` | ✅ 跑（共享判据 `Scripts/check-p-parity.py`：`P-*` 双向覆盖 / 同号同物 / **§8.5.5 已落条未并入即判红**；`-SelfTest` = 8/8） |
（本端本地化层在 Rust 侧、尚未落地）
| ⑥ 一条命令跑全 | `verify-all.ps1` | ✅ 跑（**13 项**，第 22 轮由 11 项扩、第 24 轮 12 → 13 项） |
| （§8.5.6-3 结果网格压力基准，2026-09-28 开工令）| `check-grid-bench.ps1` | ✅ 跑（4 万行缩规模实跑 `grid-bench` + **空跑不许通过**；全量读数见概要设计 §8.5.7 与 `Bench/grid/README.md`） |
| （§8.3 平台中立性）| `check-platform-neutrality.ps1`
| （§8.3 设计令牌棘轮）| `check-design-tokens.ps1` | ⚠ 判据①规则名对齐 + ②令牌源在盘 = ✅；③Windows 侧棘轮 ⏭ 跳过（`windows\App` 未建） |
| （领域层边界）| `check-core-boundary.ps1` | ⏭ 跳过 —— **判据现只认 C# 形态**（`.csproj` / `DllImport`），而本侧已换栈为 Rust ⇒ **等价判据待按 Rust 形态改写**（登记在 `windows/README.md` 的未接网清单）|

本机实测（Windows 11 / Windows PowerShell 5.1.26100.9549 / `python` 探得 `py -3`）：
`verify-all.ps1` = **13 项中跑 10 / 跳过 2 / 失败 1**（第 24 轮换栈后；**唯一判红 = 第 9 项独占节越界，原因是本地落后远端且尚未合并** ⇒ 合并后复跑见提交信息）；跳过 2 项 = 领域层边界 / 设计令牌棘轮（都因判据尚未按 Rust / 表示层形态改写）；加 `-RequireAll` = **判红（跳过即红）**。
第 22 轮另存一对前后证据：**修复前第 ③ 项假红**（判据 `rc 0` 但 stderr 有 `SyntaxWarning`）→ `_common.ps1` 加「只认退出码」护栏后 **跑 8 / 跳过 4 / 失败 0**（见坑 6）。

## 注入自证（2026-09-27，逐例：注入 → 红 → 还原 → 逐字节一致 → 绿）

| 注入 | 期望 | 实测 |
|---|---|---|
| 台账给 Windows 登记 1 条 overrides（工程未建）| 如实性判据点名判红 | ❌「未开工却登记了 1 条 overrides ⇒ 不如实」→ 还原后 RESULT: PASS |
| `check-doc-tables.ps1 -RequireAll`（缺 5 份本地文档）| 跳过即红 | RESULT: FAIL |
| 子闸门 `check-doc-tables.ps1` 去掉 UTF-8 BOM | verify-all 第 1 项判红 | 跑 5 / 跳过 4 / 失败 2 → RESULT: FAIL |
| 夹具 `windows/Core` 开 `UseWPF` + 写 `DllImport` | 领域层边界判红并点名 | 两条都点名 → 还原后转绿 |
| 往 §8.5.5 加一条只在本节出现的 `P-26`（不写进 §4 / §10.9）| 第 11 项（`P-*` 对账）判红并点名该行 | ❌ `Docs/概要设计.md:1039：§8.5.5 已落条目 P-26，但它还没进 §10.9 / §4`、`RESULT: FAIL (exit 1)` ⇒ `git checkout HEAD --` 还原后**逐字节一致**、转绿 RC 0 |

## 六条实测坑（别重踩）

1. **本目录 `.ps1` 一律 UTF-8 带 BOM**。PowerShell 5.1 读**无 BOM** 的中文脚本时按 ANSI(GBK) 解码 ⇒ 字符串终止符报错、**整脚本一行都不执行**。`verify-all.ps1` 第 1 项机械判它（守同目录其它脚本）。
   **边界（如实）**：入口脚本**自身**丢 BOM 时 PowerShell 在**解析期**就失败，护栏来不及跑（实测无 RESULT 行）—— 护栏只能尽早发现，修法只有「另存为 UTF-8 带 BOM」。
2. **中文输出要在脚本开头设 `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`**，否则输出被重定向后是乱码（`_common.ps1` 已设）。
3. **找 Python 不能只看 `Get-Command`**：Windows 上 `python3` 是应用商店占位符（`…\WindowsApps\python3.exe`，实跑即退出码 49）⇒ 必须**实跑一句** Python 3 再认（`_common.ps1` 的 `Find-DoyahPython`：`PYTHON` → `py -3` → `python` → `python3`）。
4. **从 MSYS bash 以路径直接调用 PowerShell 时，任意非零退出码会被压成 1**（实测 `exit 7` → `$?` = 1）⇒ 在那种调用方式下**别据退出码判强度**，看脚本的 `RESULT:` 行；PowerShell 会话内 / `-File` 形式下退出码正常，脚本内的父子汇总（`$LASTEXITCODE`）实测正常。
   **同族陷阱（第 22 轮实测）**：经 `.cmd` 包装调用时退出码也会丢 —— 包装脚本最后一条 `echo GATE_EXIT=%ERRORLEVEL%` 自己成功返回 ⇒ **cmd 的退出码恒为 0**。**判强度一律看脚本的 `RESULT:` 行**，不要看外层 shell 的 `$?`。
5. **`-Base HEAD` 只在「没有待提交的 merge」时可信**：刚 merge 完对侧提交、merge 还没提交时，对侧刚合进来的契约层改动会被整批算成「本侧越界」（mac 侧实测 76 处假红）⇒ 推前姿势一律 `-Base origin/master`（本目录默认值）。
6. **原生命令的 stderr 会把「退出码 0」的判据变成假红**（第 22 轮实测）：PowerShell 5.1 在 `$ErrorActionPreference = 'Stop'` 下，把**原生命令写到 stderr 的任意一行**当**终止错误**（`NativeCommandError`）⇒ 子闸门整项判红，而判据其实 `rc 0`。现场 = 对侧 `Scripts/check-doc-tables.py` 的 docstring 里一处无效转义（`\|`）每次运行都往 stderr 打 `SyntaxWarning`，本侧第 ③ 项于是报 `抛异常：…SyntaxWarning…`（判据真判是 `✅ 表格校验通过`）。
   **口径**：**判红与否只由退出码决定**，stderr 照原样打印（不吞、不静默）—— `_common.ps1` 的 `Invoke-DoyahSharedGate` 已在调用原生命令时临时把 `$ErrorActionPreference` 降为 `Continue`。

## 维护

- 新增 `.ps1` 后**必须**带 UTF-8 BOM，并把它挂进 `verify-all.ps1` 的项列表（否则它等于不在闭环里）；挂进去时**同步 `$total` 与每条 `Write-DoyahStep "N/$total"` 的步号**（第 22 轮实测：只改注释不改步号 ⇒ 打印出 `11/12`）。
- 表示层（`windows\App`）落地时同时落 `windows\Tools\design-token-baseline.json`（棘轮基线，形态同 mac 侧 `Scripts/design-token-baseline.json`：`files → 文件 → 规则 → 上限`）。
- 判据侧（`Scripts/`）属对侧共享设施：本侧只调用、只提建议，不自己改。
