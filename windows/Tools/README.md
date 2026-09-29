# windows/Tools —— Windows 侧的闭环闸门（§8.3.1 / §8.5.3 的等价物）

**状态**：🟡 实现本体**首片已落地**（`Core/`〔Rust〕+ `Bench/grid/`，2026-09-28 第 24 轮开工令换栈后）；**闸门 14 项已就位**（2026-09-27 第 21 轮起，第 24 轮由 12 项扩、第 27 轮 13 → 14 项）—— 口径是「先有闸门再有功能」。
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
| ① 构建入口 | `build.ps1` | ✅ 跑（`cargo build --release --workspace --features doyah-studio-shell/custom-protocol` + 两个前端 `vite build`；**第 28 轮补一条衍生判据**：前端产物的文件名必须出现在二进制里 ⇒ 拦「产出了 dev 形态、跑不起来的产物」，注入自证见 `Docs/概要设计.md` §8.5.7） |
| ② 单测 | `test.ps1` | ✅ 跑（`cargo test --workspace`；前端 `vitest` 同链路） |
| ③ 文档计数 | `check-doc-tables.ps1` | ✅ 跑（共享判据 + `--require-all` 透传） |
| ④ 独占节越界 | `check-exclusive-sections.ps1` | ✅ 跑（显式 `--mine windows`，默认基线 `origin/master`） |
| ⑤ 平台矩阵 | `check-platform-parity.ps1` | ✅ 跑（共享判据 + **本侧如实性判据**：未开工时台账不许有 overrides） |
| （契约侧 L-45，第 22 轮新增）| `check-p-parity.ps1` | ✅ 跑（共享判据 `Scripts/check-p-parity.py`：`P-*` 双向覆盖 / 同号同物 / **§8.5.5 已落条未并入即判红**；`-SelfTest` = 8/8） |
（本端本地化层在 Rust 侧、尚未落地）
| ⑥ 一条命令跑全 | `verify-all.ps1` | ✅ 跑（**14 项**，第 22 轮由 11 项扩、第 24 轮 12 → 13 项、第 27 轮 13 → 14 项） |
| （§8.5.6-3 结果网格压力基准，2026-09-28 开工令）| `check-grid-bench.ps1` | ✅ 跑（4 万行缩规模实跑 `grid-bench` + **空跑不许通过**；全量读数见概要设计 §8.5.7 与 `Bench/grid/README.md`） |
| （§8.3 平台中立性）| `check-platform-neutrality.ps1`
| （§8.3 设计令牌棘轮）| `check-design-tokens.ps1` | ✅ 跑（**2026-09-28 第 26 轮起三项都真跑**）：① 六条规则名与 mac 基线同名；② 令牌源 `Core/DesignTokens.swift` 在盘；③ 表示层自己的 node 判据 —— `windows/App/tools/gen-tokens.mjs --check`（**令牌生成物 ⇄ 源逐字一致**；分组条数写死在期望值里，对侧改名 / 删项 / 加项即非零退出）+ `windows/App/tools/token-ratchet.mjs`（**六条同名规则**的裸值棘轮，基线 `windows/Tools/design-token-baseline.json` 只降不升、**扫描集为空即判红**，外加**引用面 ⊆ 定义面**）。**本项自此没有「跳过」档**。**第 30 轮**：生成物**两件**（CSS 变量 + 主题集 TS）、取值源**两件**（`Core/DesignTheme.swift` 值表 + `Core/DesignTokens.swift` 角色）—— 对侧把值表按主题分组后本侧生成器同步改双源；另有**单测项补 `tsc --noEmit`**（`vite build` 不做类型检查、`vitest` 只跑被 import 到的用例 ⇒ 类型错误此前能绕过 ① 与 ②）与**两处假绿修复**（子闸门抛异常后工作目录没还 ⇒ `verify-all.ps1` 在 `finally` 里还原并打印泄露路径；共享判据在受检输入不在盘上时整批跳过却 `exit 0` ⇒ 本侧包装补盘上检查、缺失即判红）。 |
| （领域层边界）| `check-core-boundary.ps1` | ✅ 跑（**2026-09-28 第 25 轮按 Rust 形态重建** —— 旧判据只认 C# 形态，此前一直如实跳过）：`Core/Cargo.toml` 依赖面 + `Core/**/*.rs` 源码面（GUI / 平台 crate、平台专有 std、FFI 形状）+ **空跑不许通过**；**判据与它的 7 例自测在同一次调用里都真跑**（`-SkipSelfTest` 只给手工快跑）|
| （§8.3 生成物一致性，契约侧 L-70，2026-09-28 第 27 轮落）| `check-release-version.ps1` | ✅ 跑（发布产物版本号「一个值、三处逐字一致」+ **与 mac 侧发布台账同源**；台账 `release-version.json`）：权威处 = `App/src-tauri/tauri.conf.json` 的 `version`（Tauri bundler 写进 MSI / NSIS 元数据），镜像 = `App/package.json` 与 `App/src-tauri/Cargo.toml` 的 `[package] version` —— **缺键 / 同一处第二个同名键 / 任一处值不同**都判红并点名；另判与 `Scripts/release-version.json` 同源（`policy = equal`，不等即判红；对侧 `buildVersion` 不跟随）；**判据自测 11 例**（基线 / 三处各改一处 / 缺键 / 同名键第二处 / 跨端不等 / 跨端独立策略放行 / 锚点写错 / 判据面缺失 / 末例核对真仓库逐字节未变）。**本项没有「跳过」档** |

第 81 轮实测（合入对侧 `b4cd5c2` / `08e6069` 后）：**14 项中跑 13 / 跳过 0 / 失败 1** —— 唯一失败项 = ③（对侧两条「受检清单自洽」判据在 Windows 上恒假红，见下节「已知既有红」）。
本机实测（Windows 11 / Windows PowerShell 5.1.26100.9549 / `python` 探得 `py -3`）：
`verify-all.ps1` = **14 项中跑 14 / 跳过 0 / 失败 0**（第 27 轮实测，读数同时记在 `Docs/概要设计.md` §8.5.7）：**设计令牌棘轮不再跳过**（`windows\App` 落地后 ③ 交给表示层自己的两个 node 判据，见上表）—— 本侧自此**没有「跳过」档**。加 `-RequireAll` = 跳过即红（现无跳过项）。
更早的读数（第 26 轮 = 13 项中跑 13 / 跳过 0 / 失败 0；第 25 轮 = 13 项中跑 12 / 跳过 1 / 失败 0）留痕在此：**跳过 1 项 = 设计令牌棘轮**（等 `windows\App` 表示层落地；规则名对齐与令牌源两项已 ✅）。
第 24 轮换栈后的那一次读数（13 项中跑 10 / 跳过 2 / 失败 1）留痕在此：判红那一项 = 本地落后远端、merge 尚未提交时的独占节越界，合并后即绿；跳过第 2 项 = 领域层边界，第 25 轮已按 Rust 形态重建。
第 22 轮另存一对前后证据：**修复前第 ③ 项假红**（判据 `rc 0` 但 stderr 有 `SyntaxWarning`）→ `_common.ps1` 加「只认退出码」护栏后 **跑 8 / 跳过 4 / 失败 0**（见坑 6）。

## 注入自证（2026-09-27，逐例：注入 → 红 → 还原 → 逐字节一致 → 绿）

| 注入 | 期望 | 实测 |
|---|---|---|
| 台账给 Windows 登记 1 条 overrides（工程未建）| 如实性判据点名判红 | ❌「未开工却登记了 1 条 overrides ⇒ 不如实」→ 还原后 RESULT: PASS |
| `check-doc-tables.ps1 -RequireAll`（缺 5 份本地文档）| 跳过即红 | RESULT: FAIL |
| 子闸门 `check-doc-tables.ps1` 去掉 UTF-8 BOM | verify-all 第 1 项判红 | 跑 5 / 跳过 4 / 失败 2 → RESULT: FAIL |
| 第 25 轮（真仓库三例）：① `windows/Core/Cargo.toml` 的 `[dependencies]` 加 `tauri = "2"`；② `Core/src/lib.rs` 加 `use windows::core::*;`；③ 同文件加 `extern "C" { fn probe(); }` | 领域层边界判红并点名 `文件:行号` | 三例全中：`Cargo.toml:8 依赖面命中 GUI / 平台 crate：tauri` / `windows\Core\src\lib.rs:13 出现 use GUI / 平台 crate`（同行的 crate 路径规则亦命中）/ `lib.rs:13 出现 FFI：extern "C"` ⇒ 逐例**按原始字节还原**（sha256 一致）后净跑 `RESULT: PASS (exit 0)` |
| 往 §8.5.5 加一条只在本节出现的 `P-26`（不写进 §4 / §10.9）| 第 11 项（`P-*` 对账）判红并点名该行 | ❌ `Docs/概要设计.md:1039：§8.5.5 已落条目 P-26，但它还没进 §10.9 / §4`、`RESULT: FAIL (exit 1)` ⇒ `git checkout HEAD --` 还原后**逐字节一致**、转绿 RC 0 |
| （第 27 轮，真仓库三例）`windows/App/package.json` 的 `version` → `9.9.9`；`windows/App/src-tauri/tauri.conf.json` 的 `version` → `9.9.9`；`windows/App/src-tauri/Cargo.toml` 的 `[package] version` → `9.9.9` | 第 13 项判红并点名 `文件:行号` | ❌ 三例全中：`镜像处：windows/App/package.json:4 的值 = \`9.9.9\`，台账 = \`0.2.0\`` / `权威处：windows/App/src-tauri/tauri.conf.json:4 …` / `镜像处：windows/App/src-tauri/Cargo.toml:3 …` ⇒ 逐例按**原始字节**还原（sha256 一致）+ 净跑 `RESULT: PASS (exit 0)` |

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

- **换栈 / 换形态时，「跳过」不算完成**：判据形态对不上工程时（先例 = 第 24 轮换栈后 `check-core-boundary.ps1` 仍只认 C# 形态）必须**按新形态重建**，并把「已跳过 ⇒ 已重建」这一步同步进本文件与 `windows/README.md` 的未接网清单 —— 跳过只是**如实**，不是**已覆盖**。

## 已知既有红（对侧共享设施 · Windows 平台特有）

**第 ③ 项自合入对侧 `b4cd5c2`（L-88 判据 D）/ `08e6069`（L-89 判据 E）起恒红 —— 缺陷在对侧判据、不在本侧**（2026-09-29 第 81 轮实测）。

- 现象：两条「受检清单自洽」判据在 Windows 上把**清单里本就有**的文档全报成「不在受检清单里」——
  `check-doc-tables.py` 判据 E 报 26 处（`Docs\README.md` / `Docs\概要设计.md` / `Docs\proposals\*.md` …）、
  `check-doc-versions.py` 判据 D 报 6 处（`Docs\需求规范书.md` / `Docs\概要设计.md` / `Docs\发布计划.md` …）。
  同脚本的表格列数档与 A/B/C 三档对同一批文档全绿（`✅ Docs/需求规范书.md —— 变更 293 行 / 最高 v3.277 / 头部 v3.28`）。
- 根因：两条判据取相对路径都用 `str(...)`（D 用 `path.relative_to(root)`、E 用 `path.relative_to(".")`），
  Windows 上给**反斜杠**，而三处清单（`VERSION_DOCS` / `DEFAULT_TARGETS` / `COVERAGE_EXEMPT`）写的是**正斜杠**
  ⇒ 集合匹配恒 False（macOS 上 `os.sep` 就是 `/` ⇒ 对侧看不到，`--self-test` 也在 macOS 上跑）。
  本侧探针实测：判据 D 的 raw 比较判红 6 处 / 改 `as_posix()` 判红 0 处。
- 修法：两条各一行 —— `.as_posix()`（+ 各一条在 Windows 上会红的自测例）。`Scripts/` 属对侧共享设施
  ⇒ 本侧不动手，已挂提案 **`Docs/proposals/0005`**（待采纳）。
- 本侧处置：**不**在本目录的包装脚本里放行该项 —— 放行等于让这两条判据的真实回归（新文档溜出受检清单）
  在本侧静默失效。该提案销账前，Studio 侧按「不绿不推」办（本轮本侧提交即按「既有红如实登记」的姿势落，见该提交信息）。
