# 云G · 账号面实证 + 出可测包（**macOS `.app`**）· 派单 `T-20261009-124` ③④

| 项 | 内容 |
|---|---|
| 片号 / 片名 | `云G` ｜ 账号面实证 + 出可测包（macOS `.app`，含上云最小闭环 + 注册/登录） |
| 目标仓 | **DoyahStudio**（一仓一片） |
| 交付面（文件级） | `cloud-sync/云G-出包与账号面实证-macOS.md`（**新增 · 本片唯一新文件**）+ **`dist/` 出包实物**（`dist/` 在 `.gitignore` 内，**不进库**；身份 = 带版本号的那份 `.app` 自身） |
| 归属 dev | `macos-dev`（macOS 机组） |
| 判据读数 | 见 §一~§五（逐条成对留档） |
| 停手线 | **未命中**（① 号码可用 —— 本侧自备 `~/.dsh/private/cloud-sync-test-phone.txt`；② 前置 `云D` `a8fb2bc` + `云F-缺口` `61a2a9e` 均在 HEAD 历史内；③ 出包无依赖冲突） |
| 本片改动 | 只新增本文件一个；**零产品代码改动**（纯出包 + 取证片）；`dist/` 产物不入库 |

---

## 〇 口径与来源

- **契约**：`DoyahNotes a2919f0` · SRS **v3.89** §6.4「账号与同步界面（最小集）」（`Docs/需求规范书.md:832`）。
- **派单**：`T-20261009-124` 第 5 / 6 条 +【验收】②③。
- **本侧基线（本文所有读数的出处）**：
  - 工作树 `/Users/alex/dev/doyah/lead/studio/.worktrees/t_f9af8cf6` · 分支 `wt/cloud-g` · HEAD = `8eedf07`（= `origin/master 632262d` + 合入 `云D` `a8fb2bc` + 合入 `云F-缺口` `61a2a9e` 等）；
  - **前置两条逐条在位**（`git merge-base --is-ancestor`）：`a8fb2bc`（云D · 端到端最小闭环）= YES · `61a2a9e`（云F-缺口 · 注册页接官方 `signUp` 面）= YES。
  - 出包路径 = `Scripts/build-app.sh`（**ad-hoc / 稳定身份**两条路都在，本机走稳定身份 `DoyahStudio Local Dev`）。
- **工具链**：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` · Xcode **27.0 (27A266a)** · `xcodegen 2.46.0`。

---

## 一 判据① `ls dist/` ⇒ `.app` 在盘（**绝对路径 + 构建读数 + `sha256`**）

### 1.1 产物实物

```
ls dist/
  DoyahStudio-alpha3.1.app          （目录 · 身份 = 带版本号的实物）
  DoyahStudio.app -> DoyahStudio-alpha3.1.app   （软链 · 只是方便入口）
```

| 项 | 读数 |
|---|---|
| **绝对路径** | `/Users/alex/dev/doyah/lead/studio/.worktrees/t_f9af8cf6/dist/DoyahStudio-alpha3.1.app` |
| 可执行文件 | `Contents/MacOS/DoyahStudio` |
| **构建时间** | `2026-10-09T23:13:01+0800`（UTC `2026-10-09T15:13:01Z`） |
| 架构 | `Non-fat file … is architecture: arm64` |
| 二进制字节数 | `81452368` |
| **`shasum -a 256`** | `5475f13ec99d5ec43912296882c37aa48d3243665f3af38a7f5f0260751bfb1b` |
| `Info.plist` → `DoyahReleaseLabel` | `alpha3.1` |
| `Info.plist` → `CFBundleShortVersionString` / `CFBundleVersion` | `0.3.0` / `3` |
| `codesign -dv` | `Identifier=studio.doyah.DoyahStudio` · `Format=app bundle with Mach-O thin (arm64)` · `Signature size=1807` · `TeamIdentifier=not set` |

### 1.2 交付回执（脚本固定四项）

```
产物名：DoyahStudio-alpha3.1.app
构建时间：2026-10-09T23:13:01+0800（UTC 2026-10-09T15:13:01Z）
sha256（前 8 位）：5475f13e（二进制 DoyahStudio · 81452368 字节）
目录里的历史包：1 个（含本次）
```

### 1.3 复现命令（逐字）

```bash
cd /Users/alex/dev/doyah/lead/studio/.worktrees/t_f9af8cf6
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash Scripts/build-app.sh
ls dist/ && shasum -a 256 dist/DoyahStudio-alpha3.1.app/Contents/MacOS/DoyahStudio
```

> 备注（如实登记）：`dist/发布说明-alpha3.1.md` 未在盘，回执第 4 行照脚本口径写「未登记」——那是脚本既有分支，不是本片改的。

---

## 二 判据② 包**内**命中新界面符号（注册 / 登录 / 同步开关）⇒ 改前 **0** → 改后 **≥1**

### 2.1 方法与两个被测体

- **改前** = 锚仓 `/Users/alex/dev/doyah/lead/studio/dist/DoyahStudio-alpha3.1.app`（**2026-10-09T15:04:42 构建**，早于 `云F` 合入）· 二进制 `80053648` 字节 · sha256 `c00d97cdae49a96db4e8a0113c7d45e063534fde8331ae655b580617283b58d9`。
- **改后** = 本片 §1.1 的那份（`23:13:01` 构建 · `81452368` 字节 · sha256 `5475f13e…`）。
- **口径纪律（本片实测踩到的坑，写下来免得下一个人再踩）**：`grep -a -o '<中文>'` 在这类 80MB Mach-O 上**命中恒为 0**（同一份二进制里 `关闭`=28 / `笔记`=51，`grep` 数不出来 ⇒ 是它的多字节处理，不是字符串不在）。因此**主口径 = 原始字节计数**（UTF-8 子串在二进制里的出现次数，`bytes.count`），`strings -a` 只作 **ASCII 面旁证**。

### 2.2 成对读数（主口径 · 原始字节）

| 新界面符号（文案键） | 改前 | 改后 | 判定 |
|---|---|---|---|
| `账户与同步`（`.accountSyncTitle`） | **0** | **2** | 0 → ≥1 ✓ |
| `注册`（`.accountSignUpAction`） | **0** | **3** | 0 → ≥1 ✓ |
| `同步到云端`（`.accountSyncToggle`） | **0** | **1** | 0 → ≥1 ✓ |
| `验证码`（`.accountCodeLabel`） | **0** | **8** | 0 → ≥1 ✓ |
| `当前不是端到端加密`（`.accountSyncNotice` · `S4` 逐字） | **0** | **1** | 0 → ≥1 ✓ |
| `找回 / 重置口令`（`.accountRecoveryEntry`） | **0** | **1** | 0 → ≥1 ✓ |
| `已登录`（`.accountSignedInLabel`） | **0** | **1** | 0 → ≥1 ✓ |
| `登录`（`.accountSignInAction`） | 11 | 18 | 既有基线 11 ⇒ 本片净增 **+7**（不是 0 起步，单列如实） |

### 2.3 旁证（`strings -a` · ASCII 面）

| 英文文案 | 改前 | 改后 |
|---|---|---|
| `Account & Sync` | 0 | **2** |
| `Create account` | 0 | **1** |
| `Sign in` | 0 | **2** |
| `Sync to the cloud` | 0 | **1** |

复现：

```bash
BIN=dist/DoyahStudio-alpha3.1.app/Contents/MacOS/DoyahStudio
python3 -c 'import sys;d=open(sys.argv[1],"rb").read();print(d.count("账户与同步".encode()))' "$BIN"
strings -a "$BIN" | grep -c -F 'Account & Sync'
```

---

## 三 判据③ 真实短信验证码实证（**只写结论 + 时间**）

> ⚠️ **号码与验证码一律不入仓 / 不入单据 / 不入清单 / 不入截图**。本文只出现「结论 + 时间」。
> 号码来源 = **仓外私有** `~/.dsh/private/cloud-sync-test-phone.txt`（`0600`，只读使用）；环境 ID 取自入库件 `.cloudbase/project.json`。

### 3.1 发码面（**实测**）

| # | 时间（本地） | 动作 | 结论 |
|---|---|---|---|
| ① | `2026-10-09T23:01:19+0800` | `POST /auth/v1/verification`，体 `{"phone_number":"+86 <1 个空格><11 位>","target":"ANY"}` | **HTTP 200** · 应答含 `verification_id`（非空 · JWT 形状三段）· `is_user=true` · `expires_in=300` ⇒ **真实短信已下发** |
| ② | `2026-10-09T23:01:45+0800` | 同端点 · 60 秒内第二次 | **HTTP 429** · `code=rate_limit_exceeded` ⇒ **服务端频控在位**（`IR-18` ⑥ 那一档的真实来源） |

> 端点路径逐字取 `Core/NoteSync/CloudAuth.swift::CloudAuthEndpoints.verificationURL()`（`/auth/v1/verification`，`:157`），区号+空格前缀由 `CloudAuthPhoneNumber.callingPrefix` 唯一一处补 —— 本片**未**自己拼第二份。

### 3.2 收码面（**结论：本机不可机械观测**）

- 本机读短信的**唯一**机械通道是 Messages 库（`~/Library/Messages/chat.db`），实测 **TCC 拒绝**：
  `ls: /Users/alex/Library/Messages/: Operation not permitted` · `sqlite3 … "authorization denied"`。
- 本片为**无人在场的批处理运行**，无「当场转达」，⇒ **收码 → 校验（`/verification/verify`）→ 注册（`/signup`）那一段本片跑不出机械读数**。
- **据实登记**：本片**未编造实证、未用假号充数、未猜码**。号码可用 ⇒ **不触发停手线①**；收码闭环按组长第 362 轮口径**另挂**（等 `前门` / 人类主人当场转达验证码一次即可闭合），本片**不为它空转**。

---

## 四 判据④ `bash Scripts/verify-core.sh` ⇒ **exit 0**

```
ℹ️ 工具链证据: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer · Xcode 27.0 Build version 27A266a
Executed 2913 tests, with 3 tests skipped and 0 failures (0 unexpected)
ℹ️ Core 单测 2913 项（已写入 .build/core-test-count.txt，供 Scripts/check-doc-numbers.py 对账）
EXIT=0
```

| 项 | 读数 |
|---|---|
| `verify-core.sh` 退出码 | **0** |
| 单测 | **2913 例 · 3 skipped · 0 失败** |
| 台账对账 | `Scripts/check-doc-numbers.py` ⇒ **✅ 三向一致**（台账 `core-tests=2913` ↔ 实测 `2913` ↔ 文档）· `rc=0` |

> **本轮「唯一允许红」没出现**：前门已把台账 `core-tests` 落笔到 `2913`（`632262d`），而本片基线（`云D`+`云F`，**不含** `云-编码canonical`）实测正是 `2913` ⇒ `check-doc-numbers [core-tests]` **绿**。（换算：`2906`（云F-缺口）+ `7`（云D）= `2913`；`云-编码canonical` 的 `+2` 属 `wt/cloud-canon`，不在本分支。）

### 4.1 同批跑的相关闸门（本片 +0 或 PASS）

| 闸门 | 读数 |
|---|---|
| `check-path-ownership.py` | **RESULT: PASS (exit 0)** · 受检 5 条：共享面 0 / 本侧 5 / 对侧 0 / 未登记 0 |
| `check-release-version.py` | **RESULT: OK (exit 0)** · 三处逐字一致 + 生成物不漂移（比对点 22 处）· `dist/` 里带版本号的包 1 个 |

---

## 五 判据⑤ 越界与「号码 / 口令不入仓」声明（逐条）

| # | 声明 | 实测读数 |
|---|---|---|
| 1 | **不碰 `Docs/**`** | `git status --porcelain` 无 `Docs/` 项；`check-path-ownership` 受检集零 `Docs/` |
| 2 | **不改云端配置** | 零 `tcb` 写操作；零建表 / RLS / key / 触发器改动；本片只**读** `.cloudbase/project.json`（入库件）与**读**仓外私有号码 |
| 3 | **不装全局包** | 本片未执行任何 `brew` / `npm -g` / `pip install` |
| 4 | **不改判据本体** | `Scripts/**`（`check-*.py` / `verify-*.sh` / `build-app.sh`）**一字节未动**（`git status` 无 `Scripts/` 项） |
| 5 | **不扩范围** | 未动 `Core/NoteSync/*.swift` `App/**` `Tests/**`（出包只读源码）；`云-编码canonical` (`wt/cloud-canon`)、`IR-17/19/20/22` 等**不在本片** |
| 6 | **不删用户数据** | 无 `rm` 作用于用户数据；`dist/` 历史包只增不删（脚本结构保证） |
| 7 | **只本机 `git commit`，不 push / fetch / rebase** | 见 §5.1 提交号；本片全程未 `push` / `fetch` / `rebase` |
| 8 | **对外发布 / 发给人类主人须人类主人点头** | 本片只出包 + 取证，**未对外发布、未发给人类主人** |
| 9 | **号码 / 口令 / 验证码 / token 一律不入仓** | `grep -rnE '1[3-9][0-9]{9}\|\+86 ' App/ Core/ Tests/` ⇒ **2 命中，均** `App/Views/NebulaBackground.swift:124` / `:151` 的星云 LCG 常数（既有、与号码无关，基线同两行）；**真号 / 真码 / 口令 / token 零入仓**（本文只写结论+时间） |

### 5.1 提交号

- 提交 = **`<COMMIT>`**（本文件新增 · 见卡上回帖的最终值）· 分支 `wt/cloud-g` · **本地未 push** · 工作树干净。

---

## 六 已知缺口（如实登记，非阻塞）

1. **收码 → 校验 → 注册 的端到端真跑未做**：见 §3.2（本机 TCC 拒访 Messages 库 + 无人在场转达）⇒ 另挂（等信号转达）。已跑的**发码**面为真。
2. **未做真机启动取证**：本片**未** `open` 该 `.app`、未截图（判据 ①~⑤ 均不要求；且 `边界` 明写「不扩范围」）。构建通过 ⊅ 真机可跑 —— 如实登记。
3. **`dist/` 不进库**：产物身份靠本文 §1.1 的路径 + sha256 留档；换机、换工作树后该路径即失效（`dist/` 在 `.gitignore` 内）。
4. **`云-编码canonical`（`134e1a7`）不在本分支**：本片基线按卡片 `前置` = `云D` + `云F`（两条均在位）；canonical 的 `+2` 例与 canonical 编码合入后需**重出包**（本片 `.app` 不含该修）。
5. **`grep -a` 对多字节不可靠**（§2.1）：判据②若日后要机械复核，请用**字节计数**，不要用 `grep '<中文>'`（会假绿：恒 0）。

---

## 七 边界逐条自查

- ✅ 零 `Docs/**` · ✅ 零云端配置改动 · ✅ 零全局包 · ✅ 零判据本体改动 · ✅ 未扩范围 · ✅ 未删用户数据
- ✅ 只本机 `git commit`（未 push / fetch / rebase）· ✅ 号码 / 口令 / 验证码 / token 零入仓 / 零入单 / 零入截图
- ⚠️ 对外发布 / 发给人类主人：本片**未做**（须人类主人点头）
