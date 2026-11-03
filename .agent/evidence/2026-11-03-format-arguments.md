# 队列空 · `check-format-arguments` 收口（判据 D 口径归正 + 19 处新形状登记）· 2026-11-03

条目：无（`plan.yaml` / `batches.yaml` = 0 todo / 21 blocked；本跳是 `verify-all` 第 3 项最后一处存量红的收口）
判据：
$ python3 Scripts/check-format-arguments.py        # rc=0
✅ 语言表占位符 ↔ 调用点实参对账通过（带占位符键的调用点 548 处；类型不明实参 126 处已在台账逐条登记形状）
$ python3 Scripts/check-format-arguments.py --report | head -5
无据的类型不明实参 126 处（预算 126；未登记 0 + 登记为 unverified 126）；有据登记的形状实参 104 处（进判据 A/A′ 槽位检查）；已登记形状 122 个
$ python3 Scripts/check-format-arguments.py --self-test
✅ 自检 16/16 全过
$ bash /tmp/item3.sh     # verify-all.sh 第 3 项全部命令（3/19 → 4/19 之间 12 条），set -e
RC=0（末行：全部 48 例达到预期（自检 exit 0））
$ python3 Scripts/check-self-test-counts.py --no-run
族 57 个 / 例数合计 1084 / 锚点命中 86 处 / 无锚点但写了理由的族 15 个（rc=0）

反例三段（各判红后 `sha256` 逐字节还原 `ddb59193…` / `39d052bb…`）：
① `.agentQuotaUsage` 中英模板 `%d` 改 `%@` ⇒ `[A] App/Views/AgentSettingsSheet.swift:947 模板第 1/2 位是 %@，实参是数字` ×2（新登记的 `<requests>` / `<tokens>` 真进了 A 检查，不是放行）
② 删掉 `<renderedPageCount>` 登记 ⇒ `[C] App/Views/ResultPagerBar.swift:175 形状未登记`
③ `unknownBudget` 126 → 125 ⇒ `[D] 无据的类型不明实参共 127 处，超预算 125`
还原后两文件 `sha256sum -c` 均 OK、门禁 rc=0。

改了什么：
- `Scripts/check-format-arguments.py`：判据 D 的计数口径按脚本文档**原有字面**（"全局未登记总量"）归正 —— 旧实现把「已登记成 text/number、带出处、且已进 A/A′ 交叉检查」的实参也算进预算（`unknown_total` 在登记判定之前自增），历史上只能靠反复抬预算消红（116→…→190）。现只量**无据**量（未登记 + unverified）；未登记仍判 [C]、每形状处数仍判 [D]、unverified 仍占预算。同批修一处夹具缺陷：`--self-test` 空跑例原来按**序号 8** 定位语言表改动，插例后会挪到隔壁用例上 ⇒ 改按用例标题定位。
- `Scripts/format-argument-dispositions.json`：补登记 15 个形状（导出三形态 9 个 / 笔记回收站 2 / 配额行 2 / 分页读数 / 图片页），`<path>`、`<line>`、`.line`、`<loadedRowCount>` 按出处改 kind=text/number（进 A/A′ 交叉检查），`<reason>` 17 → 20；预算 190 → **126**（较 190 收紧 64）。
- 跟版：`AGENT-SPEC.md` §6 行、`Scripts/verify-all.sh` 第 3 项注释（14 → 16 例 + 预算口径）、`Scripts/self-test-counts.json`（`format-arguments` 14 → 16 例、`totalCases` 1082 → 1084）。

未验证：`verify-all.sh` 全量未跑（约 35 分钟）⇒ 第 11 项 `check-menu-language` 真启动取证、打包项未执行；`swift test` 本跳未跑（无 `App/**` `Core/**` 改动，改的是判据脚本与台账）；`self-test-counts` 用的是 `--no-run`（没真跑 57 族）。
