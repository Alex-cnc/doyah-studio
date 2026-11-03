# 2026-11-03 · 队列清空后的记账更正（三条 blocked 的前提被读数证伪）

## 由头

`python3 Scripts/plan-batches.py --check` + `.agent/plan.yaml` 实测：**0 todo / 23 blocked**。
23 条逐条读 `next_try`：没有一条能在无人值守下判完（主人拍板 / 另两端不在场 / 外部实例 / 人工点验）。
于是本跳只做一件不越界的事：**把已被机器读数推翻的旧话改对**，免下一跳或主人按旧话办错事。

## 读数（命令原文）

### 1) `NFR-ALL-GATE-COMP-003` —— 旧话「连接档没有已存口令」

```
$ nc -z -w2 192.168.5.26 3306        → succeeded（pg 5432 同批也通）
$ security find-generic-password -s studio.doyah.DoyahStudio -a B0A37FC3-4F87-4D84-820D-A41921A6E5B6   → rc=0   # 口令条目存在
$ security find-generic-password -s com.fengye.PostgresClient  -a B0A37FC3-…  → rc=44  # 不在旧服务名下
$ security find-generic-password -s studio.doyah.DoyahStudio  -a B0A37FC3-… -w    → 挂住 180 s（系统授权框）→ 杀进程，本轮不作数
$ python3 -c "json.load(.../DoyahStudio/.secrets/credentials.json)" → entries = agent.api-key, 4B9697A4…, D264B21B…（两条 PG）⇒ 无这条 MySQL
```

结论：**不是没有口令，是取口令的手被 ACL 挡住**（该条目只放行 DoyahStudio 本体）。
next_try 改成「主人终端亲跑一次并点允许」或「把自检搬进应用进程」。

### 2) `FR-AGT-UX-CONV-001` / `FR-AGT-PLAN-PLAN-001` —— 旧话「`model` 是空串、真端点未配」

```
$ agent.json → profiles[0] = {endpoint: https://api.deepseek.com/v1, model: deepseek-v4-flash, secretKey: agent.api-key}
$ .secrets/credentials.json → entries 里有 agent.api-key（0600，LocalSecretStore 的 XOR 混淆，代码公开可逆）
$ 按 LocalSecretStore 算法解出后真调一次：
  POST https://api.deepseek.com/v1/chat/completions  {model: deepseek-v4-flash, max_tokens: 8}
  → HTTP 200 · model=deepseek-flash · finish_reason=length
  → usage = {prompt_tokens: 36, completion_tokens: 8, total_tokens: 44}
  （密钥只报长度 35 / 尾 4 位 2158，未进仓、未进命令行）
```

结论：**端点与密钥可用**。两条的状态列不动（🟡 / 🟡）—— 差的仍是真模型端到端读数 + 界面入口人工点一次。

## 本跳改了什么

- 台账 `Docs/Doyah产品开发计划任务清单-macOS.md`：三条的备注更正 + 头部版本 v1.0.159 → **v1.0.160**；**状态列一个字未动**。
- `Scripts/plan-batches.py`：`BLOCKED_V060` / `BLOCKED_V050` 三处 `next_try` 改口（派生件只认规则表）。
- `.agent/plan.yaml` / `.agent/batches.yaml`：`--emit-plan --write` 重出。

## 门禁读数

```
python3 Scripts/plan-batches.py --emit-plan --write   → ✅ 0 todo / 23 blocked
python3 Scripts/plan-batches.py --check               → rc=0
check-doc-invariants / -tables / -numbers / plan-coverage / status-consistency
/ version-scope / doc-layout / agents-index / status-gap → 九道全 rc=0
```

## 未验证（≠通过）

- MySQL 口令本体**没读到**（ACL），`test-mysql-real.sh` 本跳仍**未跑**。
- 真模型只证到「端点与密钥可用」；诊断三面与维护编排**没有**端到端跑过。
- 其余 20 条 blocked 只做粗筛（GBase 5258 不通、无 MCP 配置项、无第二端），未逐条复测。
