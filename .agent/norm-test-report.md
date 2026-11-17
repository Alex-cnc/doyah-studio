
# 规范自测报告（2026-11-16 22:20）

**被测对象**：《通用开发规范》v1.0.26（56 条）+《项目管理规范》v1.0.9（35 条）= **91 条**，27 个开发环节，`Scripts/rule-sections.json` 为环节唯一出处（`enforce=true`）。

## 一 判据自检（规范自己能不能判自己）

| 项 | 读数 | 结论 |
|---|---|---|
| `check-rule-schema.py --self-test` | **9/9** | ✅ 含新增 3 例：写错环节⇒红 / 合法⇒绿 / 收紧期缺环节⇒红 |
| `check-doc-q-series.py --self-test` | **8/8** | ✅ 表迁 `.agent/` 后修好（原 8 例因新路径缺失全崩） |
| `check-queue-needs-user.py --self-test` | **11/11** | ✅ 同上 |

## 二 反证（判据真会红吗，5 条）

| 编号 | 破坏方式 | 期望 | 实测 | 还原 |
|---|---|---|---|---|
| R1 | 删掉一整条条文（B6） | 红 | rc=1 | sha256 一致 |
| R2 | 归属环节写 `ZZ9` | 红 | rc=1 | sha256 一致 |
| R3 | 收紧期删掉「归属环节」行 | 红 | rc=1 | sha256 一致 |
| R4 | 改条文标题一个字 | 红（46 条用例键） | rc=1 | sha256 一致 |
| R5 | 环节表删掉 `B1` 定义 | 红 | rc=1 | sha256 一致 |

**5/5 通过，全部字节级还原。**

## 三 覆盖读数（27 环节 × 条文 × 判据）

- 环节内有条文 **75 条** + 横切 16 条 = 91；**27/27 环节全部有条文**
- 机判 **48 条** · 人判 **27 条**（人判集中在 B3/B5/B6/C2/C4/D5/E3/F1–F4 等「本仓没有判据物」的环节，条文里已声明覆盖范围）
- 通用册 56 条：完整 56 / 缺字段 0；项目册 35 条：完整 35 / 缺字段 0

## 四 全量门禁（`verify-all.sh --keep-going`）

- 项块 **19 个**，**7 项红 / 19 处**，其余 12 项全绿；`swift test` **5789 例 0 失败（19 skip）**
- **本次搬家弄坏 2 处（已修）**：`check-doc-q-series --self-test`、`check-queue-needs-user --self-test` —— 自测夹具只建 `Docs/`、没建新的 `.agent/` 层
- **早前遗留 1 处（已修）**：`check-blocker-table` 判「漏登」`FR-AGT-CORE-LOOP-012` / `FR-AGT-PLAN-PLAN-007` —— 两条新需求只进了 §3 台账、没进 §7.1 卡点表
- **其余 16 处在 `origin/master` 干净 worktree 上同样红**（实测 rc=1）：`test-rule-negatives`（2 条 `baseline-red`）、`check-self-test-counts`、`check-version-scope`、`plan-batches --check`、`gen-platform-parity/win-align/board`、`check-board-parity`、`check-result-scroll-ledger`、`check-agent-provider-presets`、`check-path-ownership`、`check-release-version`

## 五 结论

- **规范能不能答「这事归哪个环节、凭哪条、怎么判」：能，27/27。** 27 个环节里 21 个有机判，6 个只有人判且已声明覆盖范围。
- **判据会不会真红：会，5 条反证全中，字节级还原。**
- **还欠的**：`verify-all` 第 4 项因 2 条 `baseline-red` 处置未登记而红（`check-release-version` / `check-book-subset`），连带 `check-self-test-counts`；这一批不是本次引入，但要真绿必须补处置登记。
