# 2026-11-02 判据维护跳（无台账行 · 脚本级 · 第九片）：32 份探针「写了用例却没接进 FILTER=`」

## 形状（不是夹具漂移，是真仓库红）

`check-result-scroll-ledger.py` ⑤ 判「`TestsUISnapshot/` 每份 `*ProbeTests.swift` 都得在
`Scripts/run-manual-verification-probes.sh` 的 `FILTER=` 清单里」。盘上 **79 份**，清单只有 **47 条**
⇒ **32 份逐条点名判红**（`AgentApprovalDecision` / `AgentBatchRevert` / `AppearanceAxes` /
`CommentToggle` / `DebugPanel` / `DialogActionRow` / `EditAssist` / `ExecutionReceiptPane` /
`GhostCompletion` / `GitReadOnly` / `HTMLPreview` / `IndentProfile` / `ObjectDiagnosis` /
`ObjectTreeRetry` / `Result{Copy,Filter,Paging,Sort,StreamExport,XLSXExport}` / `SQLTaskMenu` /
`SessionDiagnostics` / `SnippetTemplate` / `SymbolHover` / `TableEditDDL` / `TableExportStream` /
`TextFileFormat` / `Workspace{Close,ExplorerMoveTerminal,ExternalChange,FileCreateRename,FileTrashUndo}`）。

为什么一直绿着没人管：这 32 份自己写着「`DOYAH_UI_SNAPSHOT=1` 才跑」，而**唯一**会设这个变量的入口
就是那份取证脚本 —— 没进清单 = 一次都没跑过；`swift test`（每轮门禁）里它们全体 `XCTSkip`，
所以 5078 例的读数里从来没有它们。

修前读数：

```
python3 Scripts/check-result-scroll-ledger.py            ⇒ 32 条 ✗（上面逐个点名）
python3 Scripts/check-result-scroll-ledger.py --self-test ⇒ 18 例，15 例符合预期
   01 ✗ 真台账（应当绿）  16 ✗ 注释里提无关名字（不许误报）  18 ✗ 真仓库台账未变且真跑 0 错
```

## 做了什么

1. 逐份核上下文（要真库的走本脚本已起的集群；要落盘的走临时目录；`AppearanceAxes` 要写真
   `UserDefaults` ⇒ **留在豁免表**不进清单）后，把 **31 份**接进 `FILTER=`：47 → 78 条。
2. `PROBE_FLOOR` 40 → 78（面下限跟版，删文件即判红）。
3. 取证脚本头补「第十批（补接线）」一段，写明这批是怎么漏的、读数是多少；
   判据 docstring 记下 `2026-11-02 补接线` 一句。

## 判据读数（修后）

```
python3 Scripts/check-result-scroll-ledger.py
  ✓ 台账自洽 … 取证脚本挂载：FILTER= 清单 78 条 / 盘上 79 份探针（面下限 78），豁免 1 份
  rc=0
python3 Scripts/check-result-scroll-ledger.py --self-test
  自检：18 例，18 例符合预期，0 例不符合        rc=0
```

负例（撤掉清单里一条 ⇒ 必须判红，还原后逐字节一致）：

```
✗ 探针 TestsUISnapshot/ResultFilterProbeTests.swift 没挂在 … 的 `FILTER=` 清单里 …
before=sha256 dadd1e41…9277   after=sha256 dadd1e4104d342976861d534acd08610fd405d95b8afa901962fe2040bb49277
```

## 接线不是目的 —— 接进来的探针真跑过（否则只是把「没跑」换成「跑了但跳过」）

```
./Scripts/run-manual-verification-probes.sh --filter "<32 份名 + ManualVerificationProbeTests>"
  plain   Executed 192 tests, with 0 failures (0 unexpected) in 93.200 (93.254) seconds
  sandbox Executed 192 tests, with 0 failures (0 unexpected) in 92.358 (92.411) seconds
  Test Case … (failed|skipped) 计数 = 0        （tail 的 rc=1 来自脚本尾「证据文件核对」：
  被 --filter 排除的那几族没产出证据文件，与本节结论无关）
```

接后全量（两遍，真集群 + 临时目录）：

```
./Scripts/run-manual-verification-probes.sh
  Executed 418 tests, with 4 tests skipped and 8 failures (0 unexpected) in 304.467 s
  修前同一棵树：230 tests / 3 skipped / 8 failures
```

**8 failures 全是既有红，与本片无关**（都在早就挂着的族里，一个都不是新接的 31 份）：

| 用例 | 读数 | 性质 |
|---|---|---|
| `NotesCrudIconSpacingProbeTests.testCrudEntryIconsAreEquidistant…` | 实测 4 枚入口不是 3 枚（多出的一枚在 y=45 那行）+ 间距 -28/4/4 | 量法带挑宽了（把下一行算进来）或界面多了一枚 |
| `NotesSearchRevealProbeTests.testNoteSearchIsAnIconUntilClicked` | 收起后那一条带里还剩 1 个输入框 | **疑似真缺陷**：ESC/点外部没真收 |
| `NotesEditorSaveProbeTests.testN24FailureIsVisibleAndNeverAPopup` | 自动保存失败弹了框（`errorMessage` 有值） | 该条判据④「全程无弹窗」不成立 |
| `PaletteWiringProbeTests.testEveryCommandHasARegisteredLanding` | 6 条笔记命令无落点（`newNote`/`newNotebook`/…） | 既有 6 条缺口（上一片已记） |
| `RetroHostProbeTests.testRetroHostModelReallyReadsTheFixedScanRoot` | `~/.dsh/notes/geopolitics-weekly/packages` 实测 5 包、夹具写死 2 包 | 夹具钉真用户数据 ⇒ 环境漂移 |

⇒ 取证脚本仍是 rc=1（修前也是 rc=1，失败集不变）。**本片不改它们**：一张片只清一族门禁，
这五条要么是产品改动、要么是夹具钉错了真实数据，留给下一片逐条判。

## 覆盖边界

- 真机点验 0 次；217 真库 0 次（本片只用 `Scripts/lib/test-env.sh` 的本机临时集群）。
- `swift test` 未执行（本片未碰 `App/` `Core/` `Tests/` 的 Swift 源码；判据面变更由上面两份真跑覆盖）
  ⇒ 记「未执行」，不是「通过」。
- `check-self-test-counts` 全跑未执行（只跑 `--no-run`：54 族 / 1054 例 / 86 锚点 rc=0），
  本族绿由族 runner `--self-test` 18/18 直证。
