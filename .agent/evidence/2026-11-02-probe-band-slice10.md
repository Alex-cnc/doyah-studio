# 判据维护第十片 · 2026-11-02（探针量法：顶栏那条带的下界）

条目：无台账行（队列空 ⇒ 脚本级维护）。清 `run-manual-verification-probes.sh` 上两族红。

## 根因（两条红是**同一个坏量法**，不是产品缺陷也不是夹具漂移）
两份探针都按「宿主上缘往下 60pt」挑「左区顶部操作行」—— 而**内容区**（三栏 `NSSplitView`）
就在上缘往下 37pt 起：右栏编辑器标题输入框实测 y=58…76（占位 `Untitled`）、左栏列表自己
那一排命中区实测 y=45…73。于是收起态永远读出 1 个输入框、三枚增删查入口永远读出 4 枚
（间距 −28 / 4 / 4、方差 227.6pt²）。修法：下界取**分栏面自己的上缘**（`UISnapshot.LiveHost.contentTop`），
顶栏 = 分栏面之上那一格（实测 y=0…37）。

## 判据
$ DOYAH_UI_SNAPSHOT=1 DOYAH_NOTES_DIR=<临时目录> swift test --filter "NotesSearchRevealProbeTests|NotesCrudIconSpacingProbeTests"
Executed 7 tests, with 0 failures (0 unexpected) in 9.235 seconds
NOTEUI-21 ① 入口 3 件（x=8/40/72 · y=4…32 · 28×28）｜间距 4.0/4.0pt ｜方差 0.000pt²
NOTES-SEARCH-REVEAL ① 收起态输入框 0 ｜③ 收起后 0 ｜② 展开态 1（占位 = notesSearchPlaceholder）
$ ./Scripts/run-manual-verification-probes.sh
Executed 418 tests, with 4 tests skipped and 5 failures —— 4 个红用例：`NotesEditorSave` / `PaletteWiring` /
`QueryHistoryPane`（单跑 4/4 全绿 ⇒ 同进程共用一份笔记库的串扰，非本片引入）/ `RetroHost`（夹具钉真用户目录）
（修前 8 failures：本片那两族占 3 条）
$ env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh
Executed 5078 tests, with 13 tests skipped and 0 failures
$ python3 Scripts/check-self-test-counts.py（全跑，本片开工先复跑）
族 54 / 例 1054 / 锚点 86 · 判红 8 处（`cli-failure-readability` `core-localization` `design-tokens`
`language-registry` `network-egress` `release-version` `terminal-tabs` `tri-repo-parity`）—— 与上一片推算一致
文档门禁五道 rc=0（tables 74 文件 · numbers 三向 · plan-coverage · status 471 · version-scope 471）

## 负例（同一套量法必须判红）
`contentTop` 临时改回「宿主整高」⇒ `Executed 7 tests, with 4 failures`：`NotesCrudIconSpacing` 测到 4 枚
（dump 含 y=45…73 那一枚）· 方差 227.556pt² · `NotesSearchReveal` 收起态 1 个（占位 `Untitled`）。
还原后 sha256 `320e3e87f6932571c2285f9b5b5ff283a3a677d17bbc118ba184294745f8f132` 与改前逐字节一致。

## 未验证
真鼠标点图标 / ESC（离屏宿主里 SwiftUI 手势不响应合成事件，归真机点验）；`QueryHistoryPane`
在全量脚本里的红为何只在同进程出现，根因未判（下一项）。
