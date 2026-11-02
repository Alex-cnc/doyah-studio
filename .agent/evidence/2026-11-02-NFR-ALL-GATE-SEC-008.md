# NFR-ALL-GATE-SEC-008 · 2026-11-02（v0.6.0 C4 第一片：统一外发日志）

条目：NFR-ALL-GATE-SEC-008（两列全 ✅）

## 判据

$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter EgressUnifiedLogTests
Executed 11 tests, with 0 failures (0 unexpected) in 0.279 (0.280) seconds

$ env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh
Executed 5312 tests, with 13 tests skipped and 0 failures (0 unexpected) in 33.124 (33.498) seconds
ℹ️ Core 单测 5312 项（已写入 .build/core-test-count.txt）

$ ./Scripts/verify-ui-interactions.sh        → EXIT=0（116 条全跑 / 无跳过 / 源锚点全在）

$ python3 Scripts/check-network-egress.py
命中令牌 109 处（白名单面 23 · 装配缝注入 7 · 非白名单面已登记 18 份）；违规 0 处（本片前 = 9 处）

$ python3 Scripts/test-network-egress-gate.py
结果：30 项达到预期，0 项不符

$ python3 Scripts/check-doc-numbers.py
core-tests 三向 5312 ✅；仅 checkScriptParity 一项红（check-status-gap 未接进 verify-all.sh，HEAD 存量）

$ python3 Scripts/plan-batches.py --version 0.6.0 --check
✅ 批次队列一致（3 条待办，台账复算一致）

## 反例（判红后 sha256 逐字节还原：EgressLog.swift `fc785c4f…` / SSHTunnelProcess.swift `b1b47c47…`）

1. 流式「发出前先记」挪到 `wrapped.stream` 之后 ⇒ 2 红（先记后发那条盘上读出 0 行）
2. 删掉进程装饰器「起进程前先记」 ⇒ 10 红（三类一一对应与逐档失败全塌）
3. 删掉流式装饰器的封条守卫 ⇒ 3 红（`denied` 变 `allowed`，请求真的往下发）
4. 删掉隧道的 `ssh://` 记录 ⇒ 3 红（隧道起进程那条记录消失）

## 未验证（≠ 通过）

浏览器子资源仍不逐条记（引擎不暴露）· 流式建流后断流不另记 · 更新检查产品里无入口（`updateCheck` 0 条）· 真抓包未做 · IM socket 与笔记云同步各有开关 · `verify-all.sh` 第 11 / 18 项未执行 · `check-status-gap` 16 行存量红未动。

提交：<见 git log>
