# 判据维护跳 · 2026-11-02 · 闭环第 16 项侧名词表 + 自检例数台账三处存量

条目：无台账行（队列 `batches.yaml` 0 条 todo ⇒ 判据维护）。范围 = 判据脚本与台账，不碰 App/Core/Tests/台账行。

## 1 真错：同一处改动，两道门禁相反判定（闭环第 16 项）
`verify-all.sh` 把**平台名** `macos,watchos` 传给 `check-exclusive-sections.py`；而契约层一轴自 2026-10-15（基本法第四十八条 / 派单 `T-20261015-005`）起判的是**演员名 `hugehippo`**，判据按收紧口径要求同名 ⇒ 把**契约所有者本人**改三书算成越界。pre-commit 用的是 `--mine hugehippo` ⇒ 钩子绿、全量验收红。

反例/正例（同一处契约层改动：`Docs/Doyah产品概要设计说明书.md` `## 13.` 标题加「（夹具）」，基线 HEAD）：
```
$ DOYAH_SIDE=macos,watchos python3 Scripts/check-exclusive-sections.py --base HEAD
❌ 契约层锁定不通过：2 处改动落在契约层（只允许 hugehippo 侧修改，本侧=macos,watchos）      → rc=1
$ python3 Scripts/check-exclusive-sections.py --mine hugehippo --base HEAD
✅ 越界检查通过：受检改动 2 行（含契约层），均合法（本侧=hugehippo，契约层属 hugehippo）      → rc=0
```
修法：第 16 项按 `uname` 显式给**演员名**（Darwin=`hugehippo` · Linux/其它=`babyhippo`）；路径归属那道照旧传**树 id**（它认盘上子树，不认演员名）。

六格矩阵（`.build/fx/` 夹具 + `--diff-file`，矩阵见表末判据块）：
| 本侧 | 契约层节 | `[独占:windows]` 节 | `[独占:macos]` 节 |
|---|---|---|---|
| `hugehippo` | ✅ rc=0 | ❌ rc=1 | ✅ rc=0 |
| `babyhippo` | ❌ rc=1 | ✅ rc=0 | ❌ rc=1 |
| `macos,watchos`（旧口径） | ❌ rc=1 ← 假红 | ❌ rc=1 | ✅ rc=0 |

修后第 16 项块实跑（三书夹具在场，基线 origin/master）：越界 `--mine hugehippo` ✅ 受检 2 行 · `--self-test` 44/44 · 路径归属 `macos,watchos` PASS · 其 `--self-test` 38/38 · `check-tri-repo-parity` rc=0（2 份比成 / 4 处不在盘 ⇒ 跳过 ≠ 通过）。

## 2 护栏（例数不变，仍 8 例）
桩件原先不记 argv ⇒ 「传给判据的名字对不对」这一类桩测试**永远看不见**。现在桩把 argv 写进 `.stub-argv`，例 1 追加断言：越界判据每次调用都必须带 `--mine hugehippo`。
红绿成对：把第 16 项临时改回 `--mine "$DOYAH_PLATFORM_SIDE"` ⇒ 例 1 ❌（`side_ok=False`，argv=`… --mine macos,watchos`）、夹具 7/8、rc=1；还原 ⇒ 8/8 rc=0。

## 3 另三处存量（进场即红，非本片引入）
1. `check-shell-locale-safety` rc=1 → 0：`Scripts/hooks/install.sh:17` 裸写 `$SRC（` —— bash 3.2 把多字节括号并进变量名 ⇒ 提示语里路径丢值。改 `${SRC}`。
2. `check-self-test-counts --no-run` 3 处红 → 0：① `doc-versions` 锚点失配 —— 2026-10-26 废止「变更记录」时 `self_test()` 整段重写，尾巴只剩「自检通过」，`countRegex` 从此读不到数，台账却还留着旧版 **28 例**（实际 8 个样本：7 文件样本 + 「999 已冻结」）⇒ runner 收尾自己报 `负例 N/N 达到预期`、脚本头补锚点句、台账 28 → 8；② `sidebar-collapse` 台账 23 → **24**（runner 实跑 24/24，verify-all 第 9 项注释早已写 24）；③ 空跑下限 `totalCases` 1073 → **1055**（−20 +1，同因 ① 与 ②）；下限是实测值，旧值含 20 例不存在的样本，反把真值判红）。
3. `--no-run` 原本仍打印「每一族的负例都真跑了一遍」—— 未执行说成通过。现改为「`--no-run` 没有真跑 ⇒ 未执行 ≠ 通过」。

## 判据读数（全部实跑）
```
check-doc-tables 74 文件 rc=0 · check-doc-numbers 三向一致 rc=0 · check-plan-coverage rc=0
check-status-consistency 471 rc=0 · check-version-scope 471 rc=0 · check-doc-versions 17 份 rc=0
check-agents-index 15 条 rc=0 · check-doc-layout 三书九轮全清 rc=0 · check-doc-invariants 5/5 rc=0
check-req-index 488 条 rc=0 · check-script-portability rc=0 · check-copy-emphasis rc=0 · check-doc-q-series rc=0
check-shell-locale-safety 无命中 rc=0（修前 :17 一处）
check-self-test-counts --no-run：族 54 / 例数 1055 / 锚点 86 处 ⇒ rc=0（修前 3 处红）
test-verify-all-gate 8/8 rc=0 · check-exclusive-sections --self-test 44/44 · check-path-ownership --self-test 38/38
check-doc-versions --self-test 负例 8/8 rc=0 · test-sidebar-collapse-state 24/24 rc=0
```

提交：`cff49c6c`（改动）+ `6baa2c52`（检查点/决定）
未验证：① `check-self-test-counts` **不带 `--no-run` 的全跑未完成** —— 卡在某族 runner 的 `subprocess.communicate`（faulthandler 栈：`selectors.select` ← `subprocess.run` ← `run_family:242`，`timeout` 默认 900s），实测 8 分钟 0% CPU 无子进程 ⇒ 记「未知」，不记「通过」；② 同一探针（各族 20s 上限）显示**大量族存量红**（夹具锚点失效 / 干净副本判红），与本片无关，见 `.agent/decisions.md` 一行；③ 第 16 项 Linux/Windows 分支只经桩件（`test-verify-all-gate` 例 4 用 `platform=linux`），未在真机跑；真机点验 0 次 · 217 真库 0 次。
