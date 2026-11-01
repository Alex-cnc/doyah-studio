# 队列空维护跳 · 2026-11-02 · 自检例数门禁不再挂死（第五片 · 脚本级）

条目：无台账行（`Scripts/check-self-test-counts.py` 自身；队列 0 条 todo）
判据：

$ python3 Scripts/check-self-test-counts.py --self-test
  PASS  例 10 runner 卡住 ⇒ 判红、及时返回、孙进程一起收
  ✅ 负例自检：12 条中 12 条达到预期

$ # 红侧（同一例 10，把 Popen+killpg 换回 `subprocess.run(capture_output, timeout=)`）
  FAIL  例 10 … [rc=1 用时 1.0s；孙进程 14014 还活着（握管道不放 ⇒ 下一次 communicate 还会挂）]
  ❌ 自检失败（11/12） ⇒ 还原后 12/12

$ python3 Scripts/check-self-test-counts.py          # 全跑（54 族逐个真跑）
❌ 判红 18 处：
   族 54 个 / 例数合计 1055 / 锚点命中 86 处 / 无锚点但写了理由的族 12 个
   红族 18 / 绿族 36（cli-failure-readability · doc-q-series · doc-tables ·
   empty-action-buttons(+neg) · literal-language · network-egress · panel-root-frames ·
   release-version · script-portability · terminal-tabs · result-scroll-ledger ·
   language-registry · editor-line-numbers · core-localization · design-tokens ·
   tri-repo-parity · palette-wiring）
   慢族（不是红）：literal-language 105.7s · vendored-sqlite 60.9s ·
   markdown-single-source 55.2s · editor-surface-tokens 50.1s · browser-tab-ownership 35.0s

$ python3 Scripts/check-self-test-counts.py --no-run
族 54 个 / 例数合计 1055 / 锚点命中 86 处 ⇒ rc=0（跳过的实跑单列，不冒充当通过）

$ 文档门禁九道 + 版本纪律：check-doc-tables 74 文件 · check-doc-numbers 三向一致 ·
check-plan-coverage · check-status-consistency 471 · check-version-scope 471 ·
check-doc-layout 三书九轮全清 · check-doc-invariants 5/5 · check-agents-index 15 条 ·
check-doc-q-series · check-doc-versions 17 份 ⇒ 十道全 rc=0

提交：9505801c
未验证：18 个红族的**内容**一个都没修（本片只把「跑不完 ⇒ 未知」变成「跑得完 ⇒ 18 红」）；
       真机点验 0 次 · 217 真库 0 次 · 全量 `verify-all.sh` 未复跑（第 16 项会吃掉本片读数，
       且其余 17 项本片未碰）。
