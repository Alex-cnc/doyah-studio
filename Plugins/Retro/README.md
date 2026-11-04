# 复盘（Retro）· macOS 实现（本仓 `Plugins/Retro/`）

> **2026-11-03 人类主人拍板**：Retro 的 macOS 代码与 Notes 同构，**也进 Studio 仓**。
> 本目录即其**唯一落点** —— 从 `DoyahRetro` 仓的 `platform/macos/` 整体迁入，
> 那边**只留一页指向说明**（`platform/macos/README.md`），**不再有第二份源码**。

| 项 | 值 |
|---|---|
| 迁入日期 | 2026-11-03（Studio 仓提交见 `git log -- Plugins/Retro`） |
| 原位置 | `DoyahRetro/platform/macos/{Sources,Tests,Fixtures,Tools,Package.swift}` |
| 插件清单 | `Plugins/Retro/plugin.json`（`entryTarget` = `DoyahRetroUI`） |
| 依赖口径 | **零第三方依赖**（只 Foundation + GUI 框架）；**不再是对 Studio 的本地路径包** |

## 目录与层次（与 `Plugins/Notes` 同构：`Sources` + `Views`）

| 路径 | 编进哪个 target | 层 | 规矩 |
|---|---|---|---|
| `Sources/` | `DoyahRetroCore` | 领域层：周报包模型 / 解析 / 扫描（`IR-05`）+ 只读块模型与纯函数渲染 + 媒体策略与解析 + 触发面 + 缺期记账 | **只碰 Foundation**，不 import 任何 GUI 框架 |
| `Views/` | `DoyahRetroUI` | 视图层：左期次卡片列表 + 右只读渲染 + 本地视频内联 + 外链按钮 | **只有这一层可以 import GUI 框架**；**只读**（对包目录的写调用 0 命中） |
| `CLI/` | `DoyahRetroCLI` | 命令入口：扫一个根 ⇒ 逐期读数打成确定性 JSON 到 stdout | 只依赖领域层；只读（只写 stdout） |
| `Tests/DoyahRetroCoreTests/` | `DoyahRetroCoreTests` | 领域层单测 | `@testable import DoyahRetroCore` |
| `Tests/DoyahRetroUITests/` | `DoyahRetroUITests` | 视图层「不崩」自检 | —— |
| `Fixtures/` | （不进任何 target） | 端到端样例包 + 五个负例包 | 由 `Tools/make-sample-package.sh` 逐字节复算 |
| `Tools/` | （不进任何 target） | `check-readonly.py`（只读机械证明）· `make-sample-package.sh`（样例包生成） | 判据本体，跑而不改 |

### 为什么 Retro 是三个 target，而 Notes 直接并进 `DoyahCore`

文件布局与 Notes 完全同构（`Sources` 放实现、`Views` 放视图）；差别只在「**谁编译它**」：

1. **模块名不许碎**：`DoyahRetroCore` 被同包的 `DoyahRetroUI`、两套测试、命令入口直接
   `import`，`plugin.json` 的装配面又认 `DoyahRetroUI`。并进 `DoyahCore` 要改十来处 import，
   收益为零 —— 与「迁移」这件事无关。
2. **有一处真冲突**：Retro 的 `MarkdownBlock`（周报正文块，`Sources/MarkdownBlockModel.swift`）
   与 Core 的 `MarkdownBlock`（笔记 Markdown AST，`Core/MarkdownDocument.swift`）**同名同形不同义**，
   同模块编译当场红。改名属于「顺手改产品 API」，**迁移不该夹带**。

## 跑法（仓根执行；本机需 Xcode 工具链 —— `xcode-select` 指向 CLT 时没有 `XCTest`）

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift build                                        # 全部目标
swift test --filter "Retro"                        # 两套 Retro 测试（16 类 / 116 例）
python3 Plugins/Retro/Tools/check-readonly.py      # 只读机械证明（视图层 5 + 领域层 11 = 16 个 .swift）
python3 Plugins/Retro/Tools/check-readonly.py --self-test   # 判据自己不自假的负例（7/7）
bash Plugins/Retro/Tools/make-sample-package.sh    # 样例包逐字节重建（sha256 见下）

# 端到端：CLI 读样例包 / 负例包（都 exit 0 —— 坏包是「逐条报告」不是失败）
.build/debug/DoyahRetroCLI Plugins/Retro/Fixtures/sample
.build/debug/DoyahRetroCLI Plugins/Retro/Fixtures/negative
```

## 端到端样例包与负例包（`Fixtures/`）

**唯一生成入口** = `bash Plugins/Retro/Tools/make-sample-package.sh`（三个二进制内嵌为 base64 常量；
零外部依赖、不碰网络、无 `rm`、幂等）⇒ **逐字节复算** = 下表 `sha256`（2026-11-03 迁移后实测一致）。

| 文件（`Fixtures/` 下） | 字节数 | sha256 |
|---|---|---|
| `sample/2026-W40/index.json` | 239 | `b91e543cd48768da26cc927c8bd11b89377ae539fec456929485e46073777fdd` |
| `sample/2026-W40/report.md` | 460 | `3d6c01a6b5cb79e081ac250e04fb29d4ef70254b0b1b1e3a142c5f4136594ab3` |
| `sample/2026-W40/assets/trend-01.png` | 177 | `f2edf28d21d65aaa103bdee8b29784124ea47f11475ac2953ab0f13b575d0a23` |
| `sample/2026-W40/assets/trend-02.png` | 177 | `10eaa369e8efb6b418e9dac96778ffee6fccde67bf075515df39f929603a6491` |
| `sample/2026-W40/assets/clip.mp4` | 2480 | `30700dc84128e2c8f3c7918fc0a2bf96812ea0ac5a127ca9f568770a63d1d5fb` |
| `negative/2026-W41/index.json` | 196 | `d733f598c8f431f36422b2a37ed03e6f715feec823251a134a667b7ae7d3b3ec` |
| `negative/2026-W41/report.md` | 238 | `8ff82868e954e70ed5efe125e46b58f22d0fe94fc71265e52cd51d3c26776a82` |
| `negative/2026-W41/assets/raw.avi` | 133 | `6848f1c9222fddc93db114b050b67ba8cbfc74cd3bbad21169998b19f35ee473` |
| `negative/2026-W41/assets/raw.mov` | 62 | `bcd688e043028c01a71037602bee4cd243566842b5f7112a93d4f94f727da1b0` |
| `negative/2026-W42/index.json` | 213 | `916e2a7a0909efc6f136a7518b574cb1a18ded5f77ce8d3c58bfed14ccab2a6e` |
| `negative/2026-W42/report.md` | 182 | `3e24b478f37804b0aa997b408844ae9d1fc44903fa222673004902d3963f278d` |
| `negative/2026-W43/index.json` | 188 | `70d23b7647ca6d98ac8071d34020e69b30ff703aefcf898cba95089708422b6a` |
| `negative/2026-W43/report.md` | 191 | `131762d228c64d036ec844d3546d0e9166eb5dfec85496ea6ac0ee50e45b38c9` |
| `negative/2026-W45/index.json` | 67 | `3f8e37d5f218b28edd5bd37205347f0c66f59fe44bba13cc04d79c503360abfd` |
| `negative/2026-W45/report.md` | 164 | `914db5e9f907fa9480250f11137b3f360d60999967f1b5b6925a1703bfdd8df7` |

`negative/2026-W44/` 是**空目录**（`git` 不跟踪空目录）⇒ 只由生成脚本 `mkdir` 出来；重建它跑一次脚本即可。

样例包逐条读数（`DoyahRetroCLI Fixtures/sample` ⇒ exit 0）：2 张图**内联** + 1 个 `mp4`
**内联可播** + 1 条 `https` **外链**（交系统默认处理，不是错）。
负例包逐条读数（`… Fixtures/negative` ⇒ exit 0，**不崩**）：`avi`/`mov` ⇒ 占位 + 各一条报告 ·
媒体缺失 ⇒ 缺失 + 一条 · `../` 越界 ⇒ 拒绝并原位占位 · 空目录 ⇒ 目录级报告 · 坏 `index.json` ⇒ 一条报告。

**如实登记**：JSON 里的 `mediaCount` 取自 `index.json` 的 `media_count`（本地媒体件数 **3**），
而 `media` 数组是**扫出来的引用清单**（含外链，**4 条**）—— 两者口径不同，数值不同不算漂。

## 已知边界（不假装没有）

- **Xcode 工程（`project.yml` / `DoyahStudio.xcodeproj`）没有接 Retro 的三个 target** ——
  该工程自 2026-09-29 起就**不参与发布链**（只作 IDE 打开入口，与 `Package.swift` 的差异是
  登记过的已知边界，见 `Docs/发布方案.md` §2）。发布与回归一律走 `Package.swift` 这条线。
- **`Tests/DoyahRetroUITests/ReportReaderFixedRootTests` 吃真数据**：它断言前门投放的
  `/Users/alex/.dsh/notes/geopolitics-weekly/packages` 里恰好两包（`2026-W40` / `2026-W41`）。
  该目录随周报积攒（2026-11-04 实测已有 6 期）⇒ 这一例会**如实红**，与本次迁移无关
  （原仓同一提交同一条红，已双向比对）。
- **只读判据的扫描面 = 视图层 + 领域层**，命令入口（`CLI/`）不在内 —— 它的只读性靠源码面自证
  （全文件只有读探 + stdout，没有任何写 API）。
