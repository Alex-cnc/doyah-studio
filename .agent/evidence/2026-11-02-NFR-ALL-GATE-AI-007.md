# NFR-ALL-GATE-AI-007 · 2026-11-02

条目：NFR-ALL-GATE-AI-007（会话持久化与长上下文（压缩 / 检查点）；密钥 / 审计 / 配额同一条口径）
判据：
$ swift test --filter "AgentSessionDurabilityTests|AgentSecretStorageContractTests"
  Executed 8 tests, with 0 failures（Core）/ Executed 3 tests, with 0 failures（Platform）
$ env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh
  Executed 5259 tests, with 13 tests skipped and 0 failures（5251 → +8）
$ ./Scripts/verify-ui-interactions.sh
  Executed 116 tests, with 0 failures · 源锚点都在（rc=0）
$ python3 Scripts/check-doc-numbers.py → ✅ 三向一致（5259）
  doc-tables 74 文件 / plan-coverage 471 空壳 0 / status 471 / version-scope 471 rc=0
$ python3 Scripts/plan-batches.py --version 0.5.0 --check → ✅ 0 条待办
$ python3 Scripts/ledger-row.py NFR-ALL-GATE-AI-007 | grep -q '✅' → OK
提交：cf4e4643（代码 + 测试 + 台账 + 派生队列 + 本证据一次提交）
未验证：真机重启未点（重启 = 新实例读同一目录）· 密钥住 0600 文件而非系统钥匙串（主人 2026-10-30 令；钥匙串那条记未覆盖）· 真鼠标存 / 删 Key 未点 · verify-all.sh 第 11 / 18 项未执行

改动：
- `Core/AgentLoop.swift`：`recordTurn` 补 `toolName` / `toolCallID`，五个工具跳调用点传入（此前白名单有键、无调用点）
- `App/AppState.swift`：循环审计口 `AgentAuditLog.shared` → `agentAuditLog`（本类唯一取用点）
- 新 `Tests/AgentSessionDurabilityTests.swift`（8）+ `TestsPlatform/AgentSecretStorageContractTests.swift`（3）
反例四段（判红后 sha256 逐字节还原）：
- 审计口改回 `.shared` ⇒ 3 断言红（58146410…）
- 工具跳不写 `toolName` ⇒ 1 红（ed453541…）
- 写入不脱敏 ⇒ 1 红（102081e9…）
- 密钥文件 0600 → 0644 ⇒ 1 红（346c28ac…）
