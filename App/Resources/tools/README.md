# `App/Resources/tools/` —— 随包的命令行小程序

放这里的文件由 `Scripts/build-app.sh` **整目录**拷进
`DoyahStudio.app/Contents/Resources/tools/`，逐个做 ad-hoc 签名并 `codesign -v` 验过才出包。

## ripgrep 15.2.0（`rg`）

| 项 | 值 |
|---|---|
| 版本 | `ripgrep 15.2.0`（`rg --version` 首行） |
| 来源 | Homebrew `ripgrep` 15.2.0 的真身 `/opt/homebrew/Cellar/ripgrep/15.2.0/bin/rg` |
| 架构 | **仅 macOS arm64**（`lipo -info` ⇒ `Non-fat file … arm64`） |
| 大小 | 6,514,928 字节（约 6.2 MB） |
| sha256（**仓内来源文件**） | `468681470b3ed6291dc85691e83c5d2f8fc6c6ec25b164ffa66248713a7e28a3` |
| 许可 | Unlicense（`COPYING`）/ MIT（`LICENSE-MIT`），两份原文就在本目录 |
| 用途 | `Core/AgentWorkspaceTools.searchStructured` 的**首选**执行器；取不到就回落 `Core/WorkspaceSearch.swift` 的 Swift 实现 |

**为什么是随包而不是「让用户自己装」**：`search` 是智能体最常调的工具，走 Swift 实现时
一次全仓扫盘 1.4–1.8 秒（同一查询 `rg` 约 0.04–0.06 秒）；而且「用户机器上有没有 ripgrep」
不该变成一个功能在不在的开关。

### 包内那一份的哈希**与仓内不同**（签名改的，不是被掉包）

`build-app.sh` 会对包内那份做一次 ad-hoc 重签（`codesign --force --sign -`）。arm64 的
可执行文件本来就有签名槽，重签会换掉它 ⇒ 字节数与 sha256 都变。本机一次读数：

| | 字节 | sha256 |
|---|---|---|
| 仓内 `App/Resources/tools/rg` | 6,514,928 | `468681470b3ed6291dc85691e83c5d2f8fc6c6ec25b164ffa66248713a7e28a3` |
| 包内 `Contents/Resources/tools/rg`（重签后） | 6,477,056 | `35ac582b4bd7897de22234f78de14723a4c2e6a60eb5c889bf92073cab542f53` |

所以：**验来源**比仓内那份的哈希；**验可用**跑 `codesign -v` + `rg --version`。
判据 `Tests/AgentRipgrepSearchTests.testBundledRipgrepIsTheDeclaredBinary` 钉的是仓内那份。

### 只放 macOS arm64 这一份

* **Windows 侧不在本次范围**：`Platform/windows` 那条 Node/Electron 线要自己提供
  `rg.exe`（ripgrep 官方发 x86_64-pc-windows-msvc 包），随它自己的安装器发，
  许可声明也由它自己的第三方声明文件承担。本目录**不**放 `rg.exe`。
* **Intel Mac / universal 包**：这里只有 arm64 一份，`DOYAH_ARCH=x86_64|universal`
  打出来的包里 `rg` 是 arm64 二进制 ⇒ 在 Intel 机上 `posix_spawn` 失败（EBADARCH），
  引擎**如实回落** Swift 实现（`AgentRipgrep.search` 返回 nil），功能不消失、只是慢。
  要做 Intel 包就照下面的「升级」补一份 x86_64 并改成 `lipo -create` 合成。

### 升级步骤（换版本时四处一起改，缺一处就是静默失效）

1. 拷新二进制到本目录，`chmod 755`；
2. 更新本文件里的版本 / 大小 / sha256；
3. 更新 `THIRD-PARTY-NOTICES.md` 的 ripgrep 段（版本号与许可）；
4. `Core/AgentRipgrep.swift` 的 `expectedVersion` 若写成钉版本要同步（现为「不钉」，见该文件注释）；
5. 跑 `Scripts/build-app.sh --no-install --label <tag>`，看它打印的
   「随包命令行工具」小节的版本与签名验证结果。
