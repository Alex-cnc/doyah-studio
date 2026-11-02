# NFR-ALL-GATE-AI-006 · 2026-11-02

条目：`NFR-ALL-GATE-AI-006`（本地模型优先：支持 OpenAI 兼容的本地端点，如 Ollama / vLLM）

判据：

$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AgentEndpointDiagnosisTests
Test Suite 'Selected tests' passed
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.003 (0.004) seconds

$ env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh
ℹ️ Core 单测 5251 项（已写入 …/.build/core-test-count.txt）
Note: Some test targets reported failures: - DoyahCoreTests (XCTest)
→ 唯一失败 = `SSHTunnelRuntimeTests.testBusyPortFailsFastWithoutStartingAnything`（存量抖动；本机独跑 3 次只 1 次过，与端点判定无关）

$ ./Scripts/verify-ui-interactions.sh
	 Executed 116 tests, with 0 failures (0 unexpected) in 35.565 seconds
✓ 116 条都真跑过（十七批）、都以 passed 收尾、没有跳过
✓ 源锚点都在：路由判定在 Core、视图真的问过它、字节从 TerminalInput 出去…

$ ./Scripts/test-endpoint-modes.sh
通过：三档判定齐全、不可用各给不同原因、本地端点免 Key 在真 HTTP 上也成立
（22 条 PASS / 0 FAIL，退出码 0；含假端点侧读数 `STUB_REQ path=/v1/chat/completions auth=None`）

$ python3 Scripts/ledger-row.py NFR-ALL-GATE-AI-006
NFR-ALL-GATE-AI-006 ✅

反例（三段，判红后 `sha256` 逐字节还原 = `2c88a6098fc36eb7…`）：
1. `requiresAPIKey { isRemote }` 改回 `{ !isLocal }` ⇒ **10 例全红**（不可用被说成「需要 Key」）
2. 本地地址表删掉 `::1` 那一行 ⇒ `testLocalAddressesNeedNoAPIKey` 4 条断言红（`[::1]` 判成远端）
3. 结论行把不可用原因丢掉（`problemMessage` 恒空）⇒ 脚本 7 条 FAIL（「原因有重复（只有 1 种）」等）

提交：<见本文件落盘后的 commit>

未验证（≠ 通过）：真 Ollama / vLLM 联调未做（本机没有模型，`Scripts/test-real-endpoint.sh` 仍要人给端点）· `*.local` / `::1` 只判到判定层（真 HTTP 只跑了 `localhost` 与 `127.0.0.1`）· 设置面板那一行真鼠标未看 · `verify-all.sh` 第 11 项（打包 .app）与第 18 项（生成物一致性）本跳未执行
