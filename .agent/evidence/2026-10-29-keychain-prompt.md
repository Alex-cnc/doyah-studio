# R67 · ★00 钥匙串每次启动弹密码（2026-10-29）

主人原话：「keychain 有个问题就是每次启动都要输入密码。」

## 1 根因（源码 + 本机实测，不猜）

| 面 | 事实 | 证据 |
|---|---|---|
| 构建侧 | `build-app.sh` 身份用不了时**静默回退 ad-hoc**（旧代码第 285-291 行） | `git show HEAD:Scripts/build-app.sh` |
| 签名现状 | 现包签的确实是稳定身份 `DoyahStudio Local Dev`，但证书**未受信任** | `codesign -dvv dist/DoyahStudio-beta1.0.app` ⇒ `Authority=DoyahStudio Local Dev` / `find-identity -v` ⇒ `CSSMERR_TP_NOT_TRUSTED` |
| 条目侧 | 三处 `SecItemAdd` 不带 `kSecAttrAccessible`、不绑 ACL | `Platform/macOS/Keychain*Store.swift` |

## 2 两条实测边界（决定「能不能靠探测/属性判断」）

探针 `/tmp/kc2.swift`（`swift` 直跑，`SecItemAdd` → 回读属性 → `SecItemDelete`，用完即删）：

```
== ① 普通（登录钥匙串）==
add status=0
read: status=0 accessible=nil sync=nil
== ② 数据保护钥匙串 kSecUseDataProtectionKeychain=true ==
add status=-34018          # errSecMissingEntitlement
```

⇒ **登录钥匙串吞掉 `kSecAttrAccessible`**（带它 Add 成功、回读 `nil`）；换数据保护钥匙串要
`keychain-access-groups` 授权，自签身份给不了（`-34018`）。所以：属性常量今天不产生行为差别，
只是「换到数据保护钥匙串那天已经带上」；**弹窗只能靠记账 + 重写治**，不能靠「探一下会不会弹」
（登录钥匙串的 ACL 授权框 `kSecUseAuthenticationUIFail` 拦不住 —— 探测那一下就是会弹的那一下）。

探针 `/tmp/kc4.swift`（显式 ACL 这条装配路是通的）：

```
trustedApp status=0 app=true
SecAccessCreate status=0 access=true
add status=0
read status=0 value=hello
attrs status=0 accessible=nil      # 再次印证①
delete status=0
```

OSStatus 取值实测：`success 0 · itemNotFound -25300 · interactionNotAllowed -25308 · authFailed -25293 · duplicateItem -25299 · missingEntitlement -34018`；
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly = "cku"`。

## 3 判据读数（verify-core）

命令：`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && bash Scripts/verify-core.sh`

```
ℹ️ Core 单测 4900 项（已写入 .build/core-test-count.txt）
 Executed 4900 tests, with 12 tests skipped and 0 failures (0 unexpected) in 21.528 s
rc=0
```

新增 `Tests/CredentialItemReconciliationTests` **15 例**（4885 → 4900）。

## 4 反例三段（各判红一次后逐字节还原）

备份 `cp Core/CredentialItemReconciliation.swift /tmp/r67-core-backup.swift`；
每段前后 `shasum -a 256` 对拍 = `aac919c0dbc11ad6a5eafc5b765da14798f92bc32311a552cd2ab6a0e0414aa7`。

| 注入 | 读数 | 判红的用例 |
|---|---|---|
| ① `needsRewrite` 恒回 `false`（账本记过就永不再看） | `Executed 15 tests, with 20 failures` · rc=1 | 20 处断言（顺序 / 记账 / 签名换代） |
| ② 把「先读」挪到「先删」之后 | `Executed 15 tests, with 5 failures` · rc=1 | 顺序 · 读失败不删 · 空内容 · 删除失败 · 签名换代 |
| ③ 读失败也记账 | `Executed 15 tests, with 2 failures` · rc=1 | `testReadFailureNeverDeletesAndDoesNotAdvanceLedger` · `testOneFailureDoesNotStopTheRest` |

还原后 `diff -q` 逐字节一致。

## 5 构建侧自证（改的不只是能写，而是「真的会拦」）

| 探针 | 命令 | 读数 |
|---|---|---|
| 假身份构建 | `DOYAH_CODESIGN_IDENTITY="NoSuchIdentity-R67" bash Scripts/build-app.sh` | **rc=1**；打印「不再静默回退 ad-hoc」+ 三条修法；**不产出签名包** |
| 明确回退开关 | 同上 + `DOYAH_ALLOW_ADHOC=1` | rc=0；`codesign -dvv` ⇒ `Signature=adhoc`（无 Authority）—— 开关确实起作用 |
| 信任脚本（不存在的身份） | `DOYAH_CODESIGN_IDENTITY="NoSuchIdentity-R67" bash Scripts/make-signing-identity.sh --trust` | **rc=1**「钥匙串里找不到证书」 |
| 信任脚本（未知参数） | `bash Scripts/make-signing-identity.sh --bogus` | **rc=2**（用法） |

真构建（默认身份）：

```
==> 签名：DoyahStudio Local Dev（**证书未受信任** ⇒ 指纹虽稳定，但「始终允许」可能记不住）
    修法（要管理员密码，跑一次即可）：./Scripts/make-signing-identity.sh --trust
交付: 目录=…/dist/DoyahStudio-beta1.0.app 标签=beta1.0 sha256=ad5ca1ef8510043c3213ae9fb78a2409dba60c81a8dcb041a842e4e8fb34a29e 构建时刻=2026-10-29T07:50:51+0800
```

同标签 07:49:40 那份 `2a31a08a` 由头 = 发布说明含片补 ★00 之前先出了一次包 ⇒ 作废。

## 6 与「未受信任也照样签」的口径说明（不藏）

主人要求是「身份不存在或未受信任 ⇒ 不许静默回退 ad-hoc」。本批落成：
**身份不存在 / 签不动 ⇒ 硬报错**（回退 ad-hoc 正是症状的根因）；
**身份可用但证书未受信任 ⇒ 仍然用它签，并打一条警告 + 修法**。理由：受信任与否不影响指纹稳定性
（那只取决于证书本身），只影响「点过『始终允许』能不能记住」与「本地网络」授权；
把它合并成硬错误会让每一次构建都失败，而症状一点也不会更好。信任这一步因此**列在「要我做的事」**里。

## 7 残留（如实记）

- 「启动不再弹密码」只能主人点验 ⇒ 台账实现列保持 **🟡**。
- 首次重写要**读旧条目**，那一下可能还弹一次（卡上原口径已写明）—— 之后不再弹才是本批要证的结果。
