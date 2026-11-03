# 笔记源文件补登 + 无台账行（队列已空 · 存量红逐族清）· 2026-11-03

条目：无（`plan-batches --check` = 0 条待办；台账行一字未改）
判据：
$ python3 Scripts/check-notes-offline.py
修前 rc=1，**22 处**（13 个文件 × 两条清单各点名一次）：`Core/License{DeviceStore,Highlights,Scope,StatusLine}.swift`
+ `Plugins/Notes/Sources/{NoteArchive,NoteAttachmentStore,NoteCapture,NoteLandingPage,NotePrivacy,NoteTrash,NoteVersion,TodoNoteLink}.swift`
+ `Plugins/Notes/Sources/NoteSync/SyncConflictResolution.swift`
修后 rc=0：范围 51 个源文件 × 令牌表 18 项 **命中 0 处**；与解耦门禁 Core 侧 52 个文件双方一致（8 个超范围登记、4 个 outOfScope）

$ python3 Scripts/test-notes-offline-gate.py
修前 16/20（干净副本假红：夹具副本没带这 13 件 ⇒「台账写了、盘上没有」）
修后 **20/20**（`minFiles` 36 → 51 之后仍全过）

$ python3 Scripts/test-cli-failure-readability.py
修前 32/34（`CLI/AgentIMCommand.swift` 在台账 `outputScan.files` 里、夹具副本没带 ⇒「扫描目标不存在」+ 入口 61 < 62）
修后 **34/34**

$ ./Scripts/verify-all.sh --keep-going    （日志 `.build/verify-20261103-081136.log`，本跳实跑）
合计：项块 19 个 · 失败 4 项（共 5 处）· 平台跳过 0 项 · 未执行项 = 无
  第 3 项：check-format-arguments（230 > 预算 190）· check-button-icon-only（NotesPanel 7 处文案 + 8 处未登记）
  第 4 项：check-self-test-counts（唯一红族 = `cli-failure-readability`，本跳已修）
  第 11 项：check-menu-language（真启动两档等不到 dump）
  第 16 项：check-path-ownership（本跳工作树未提交 ⇒「共享面未登记」，提交信息带 `shared-surface:` 即转绿）

$ python3 Scripts/check-self-test-counts.py     （修后单跑，日志 `.build/selftest-rerun.log`）
修前：`❌ 判红 1 处：[cli-failure-readability] runner 退出码 1`（族 56 / 例 1077 / 锚点 86）
修后：**✅ 全部通过**（族 56 / 例数合计 1077 / 锚点命中 86 处 / 无锚点但写了理由的族 14 个）

未验证（≠ 通过）：
- **全量未在修后重跑**（本跳两次修完都在 08:11 那趟之后）：`check-self-test-counts` 单跑结果见上，`check-notes-offline` /
  `test-notes-offline-gate` / `test-cli-failure-readability` 三条已单跑 rc=0（见上）。第 3 / 11 项两处红本跳未动。
- 第 16 项的红按判据原文「提交信息里独占一行 `shared-surface:`」处理，未逐条比对新增行（提交后单跑复核）。
- 13 件「零网络」判的是**源码里不出现网络 API**（门禁口径 ④），运行时不出网仍未验（台账 `knownGaps` ①）。
- `NoteSync/SyncConflictResolution.swift` 落在 `scope`，同目录真 HTTP 客户端（`CloudAuth` / `CloudSyncService`）仍在 `outOfScope` 并每次打 ⚠️；
  「同步层是否属笔记模块零网络范围」这条定性仍待主人拍板（`knownGaps` ④ 原文）。
- `treeFloors` 未跟版（Core ≥8 / Sources ≥21 而实测 12 / 32）：夹具副本的枚举面比真仓小，抬到实测值会假红；只抬了 `minFiles`。
提交：
