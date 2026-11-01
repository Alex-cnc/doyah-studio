# 判据维护第十一片 · 2026-11-02

条目：无台账行（队列 0 todo / 1 blocked）—— 脚本级维护，清取证脚本一族红。

## 做了什么

`TestsUISnapshot/RetroHostProbeTests.swift` 判据 ④-a 的期望值原来**写死在用户数据上**：
断言固定扫描目录里「恰好两包」`["2026-W41","2026-W40"]`。那个目录由前门**按周投放**，
盘上现在已经是 `W40…W44` 五包 ⇒ 这条判据每多投放一期就以「用户数据变了」为由判红，
红的原因不是产品坏了。改成**期望值从盘上现取**（`FileManager` 列直接子目录，
成包契约 = 有 `index.json` + `report.md` + 期号形状 `YYYY-Www`；顺序按每包 `index.json`
里的 `published` 降序、同日按目录名降序），**不经过被测的扫描器** —— 被测那一半仍是模型的读数，
期望那一半是盘上的事实。产品代码一行未动。

## 判据

$ DEVELOPER_DIR=… DOYAH_UI_SNAPSHOT=1 swift test --filter RetroHostProbeTests
READING retro fixedRoot=/Users/alex/.dsh/notes/geopolitics-weekly/packages
  disk=["2026-W44","2026-W43","2026-W42","2026-W41","2026-W40"]
  model=["2026-W44","2026-W43","2026-W42","2026-W41","2026-W40"] issues=[]
Executed 6 tests, with 0 failures (0 unexpected)

负例（两段，各自判红后还原，sha256 `19365318…` 逐字节一致）：
① 期望排序改升序 ⇒ `1 failure`（模型倒序 vs 期望正序，两条读数都在消息里）；
② 期望集合 dropLast ⇒ `1 failure`（盘上 4 条 vs 模型 5 条）。

全量取证脚本：**418 例 / 4 skipped / 1 failure**（本片入场时 418/4/5、复跑 418/4/3）
`verify-core.sh`：**5078 例 / 13 skipped / 1 failure**（`SSHTunnelRuntimeTests` 抖动，见下）
文档门禁五道：`check-doc-tables` 74 文件 · `check-doc-numbers` 三向 · `plan-coverage` · `status-consistency` · `version-scope` 全 rc=0

提交：本片单次提交（探针改动 + 本文件同提交）
剩余红（本片实测，逐条判过）：
· 取证脚本 1 条确定性红 —— `PaletteWiringProbeTests` 6 条笔记命令无落点（`newNote` / `newNotebook` /
  `noteAllNotes` / `noteFavorites` / `noteSearchScope{All,Current}`）
· 取证脚本 2 处**抖动**（三遍全量里只出现一遍）—— `NotesEditorSaveProbeTests` 那次弹的是
  `.notesFileUnreadable`（后台 `reloadNotes()` 在读不到库时设 `errorMessage`），夹具把库改成只读
  连带把**读**也弄坏了；`NotesLayoutProbeTests` 删一条后是 10 != 9
· `QueryHistoryPaneProbeTests` 那次串扰三遍全量都未复现
· `verify-core.sh` 1 处**抖动**（3 次单跑：红 1 / 绿 2）—— `SSHTunnelRuntimeTests
  .testBusyPortFailsFastWithoutStartingAnything` 实测 `processExited("ssh 已退出：… Address already in use")`
  与期望 `portInUse(53830)` 不符（端口占用被当成子进程退出，属归因口径不稳，非本片引入）
未验证：真机点验 0 次 · 217 真库 0 次（本片只动一个探针文件，不涉及这两条覆盖面）
