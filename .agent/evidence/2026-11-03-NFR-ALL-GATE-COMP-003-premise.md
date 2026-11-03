# NFR-ALL-GATE-COMP-003 卡点量测（2026-11-03）

**结论**：状态列**未动**（仍 ⬜ / ⬜）。本跳只把「卡在谁」量清楚，并改口一条走不通的指路。
队列本轮 0 todo / 17 blocked（`plan-batches.py --version 0.7.0 --check` rc=0）。

## 1 钥匙串条目与 ACL 原文

```
$ security find-generic-password -s studio.doyah.DoyahStudio -a B0A37FC3-4F87-4D84-820D-A41921A6E5B6
rc=0   （元数据可读：svce=studio.doyah.DoyahStudio / acct=B0A37FC3-… / cdat=20261030142451Z）

$ security dump-keychain -a | （定位到该条目）
access: 5 entries
    entry 0:
        authorizations (6): decrypt derive export_clear export_wrapped mac sign
        don't-require-password
        applications (1):
            0: /Users/alex/Applications/DoyahStudio-beta1.0.app (OK)
                requirement: identifier "studio.doyah.DoyahStudio" and certificate root = H"e55d8fe2319889c35f86633f00f38f3de2a9d2d4"
```

```
$ codesign -d --verbose=4 -r- /Users/alex/Applications/DoyahStudio-beta1.0.app
Identifier=studio.doyah.DoyahStudio
designated => identifier "studio.doyah.DoyahStudio" and certificate root = H"e55d8fe2319889c35f86633f00f38f3de2a9d2d4"
（与上一段 ACL 里那条 requirement 逐字相同）

$ security find-identity -p codesigning
  1) 5096FF79… "DoyahStudio Local Dev"
  2) E55D8FE2… "Doyah Local Dev"      ← ACL 要求的那条根证书
```

连接档（`~/Library/Application Support/DoyahStudio/connections.json`）：
`DemoMySQL` = `B0A37FC3-4F87-4D84-820D-A41921A6E5B6` · mysql · `192.168.5.26:3306` · user `dsh_test` · db `dsh_db`。

## 2 CLI 侧根本不读钥匙串（旧 next_try ① 作废的读数）

```
$ .build/debug/DoyahCLI mysql --connection DemoMySQL --json --sql "SELECT CURRENT_USER() AS u"
rc=1
{"ok":false,"error":"MySQL error: Server error: Access denied for user 'dsh_test'@'192.168.5.28' (using password: YES)"}
提示：连接 DemoMySQL 没有已保存的口令。如果它需要口令，请先在界面上编辑该连接并输入一次（留空 = 不改动已存口令）。
```

源码定位：`CLI/main.swift:1770` `let password = (try? FileSecretStore().password(for: config.id)) ?? nil`
—— 走**文件存储**，不是 `KeychainSecretStore`。实测该文件里没有这条：
```
$ python3 -c "import json;d=json.load(open('.secrets/credentials.json'));print(list(d['entries'].keys()))"
['agent.api-key', '4B9697A4-…', 'D264B21B-…']   （两条 PG + agent key，无 B0A37FC3）
```
⇒ 「主人跑到 `test-mysql-real.sh` 并点一次『允许』」**按现码不会成立**：脚本走 `--connection`，取不到口令，只能空口令连。

## 3 冒名外壳两条启动方式都挂授权弹窗（勿再试）

做法：把 `DoyahCLI` 与一枚 5 行 `SecItemCopyMatching` 探针分别装进 `CFBundleIdentifier=studio.doyah.DoyahStudio` 的 .app，用 `Doyah Local Dev` 签名：

```
$ codesign -d --verbose=4 -r- MySQLProbe.app/Contents/MacOS/DoyahCLI
Identifier=studio.doyah.DoyahStudio      DR 与 ACL 那条 requirement 逐字相同
$ MySQLProbe.app/Contents/MacOS/DoyahCLI mysql --connection DemoMySQL …
rc=1  → 与裸 CLI 同一句话（证明它没碰钥匙串）
$ ./KCProbe.app/Contents/MacOS/kcprobe B0A37FC3-…            → 45 s 未返回（超时杀）
$ open -n -W KCProbe2.app --args <out> B0A37FC3-…            → 45 s 未返回（超时杀），out 文件未生成
$ ps aux | grep SecurityAgent → /System/Library/.../SecurityAgent.bundle/Contents/MacOS/SecurityAgent 在场
```
⇒ 外部进程/冒名外壳读这条口令必弹系统授权；**只有本体进程**能读。

## 4 覆盖范围（红线 13）

- 判到：ACL 原文、CLI 取口令的代码路径、冒名外壳两种启动方式、`.secrets` 内容、服务端拒绝原话。
- **判不到**：口令本身对不对（取不出来 ⇒ 读不了）；界面「测试连接」当前是否成功（未点）；MySQL 端 `doyah_test` 库是否存在（未连上，无从查）。
- 只这一台机、这一份钥匙串；换机器 / 重装签名身份会让 ACL 结论变化。

## 5 门禁读数（本片）

```
check-doc-invariants rc=0 · check-doc-tables rc=0 · check-doc-numbers rc=0
check-plan-coverage rc=0 · check-doc-versions rc=0 · check-doc-layout rc=0
check-agents-index rc=0 · check-status-gap rc=0 · check-blocker-table rc=0
check-version-scope rc=0 · plan-batches --version 0.7.0 --check rc=0（0 todo / 17 blocked，判据 F 17/17）
```

**反例（判据 F 真的会红）**：改规则表时先把 requirement 原文带双引号写进 Python 串（`\"`）⇒
`plan-batches --check` rc=1 并点名 `next_try 与规则表不一致：NFR-ALL-GATE-COMP-003`；去掉内层双引号后复绿。
