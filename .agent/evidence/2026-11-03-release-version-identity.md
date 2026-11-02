# 发布身份两半：派生值收进台账模型（判据维护跳 · 无台账行）· 2026-11-03

**这一片没有台账行**（不改任何需求状态）。由来 = 上一跳点名的机器面下一族 `check-release-version`：
① `--self-test` **rc=2**（例 4 的夹具锚点 `<string>3</string>` 在 `build-app.sh` 里已不存在）；
② 更重的真红：**发布身份早改成派生值，台账没跟**。

## 两个真问题（不是阈值问题，是台账模型缺一档）

1. **判据把写对的脚本读成错**：`shell_assignments()` 只认 `NAME="字面量"`，而
   `MARKETING_VERSION="$(printf … | sed … | awk …)"` 的值里**必然带引号** ⇒ 正则整行不认 ⇒
   报「`${MARKETING_VERSION}` 这个变量在本脚本里有 **0 处定义**」。同一处导致自检例 4 的锚点
   `<string>3</string>` 找不到（模板早就不写这个字面量了）⇒ **rc=2 夹具错误**。
2. **真红：身份两半里有一半是每次构建都变的**。`RELEASE_LABEL=beta1.0` ⇒ `MARKETING_VERSION=1.0.0`；
   `BUILD_COUNT=$(git rev-list --count HEAD)` ⇒ 产物 `CFBundleVersion=2257`。而台账还写着
   `0.3.0` / `3`，`project.yml` + 生成物也停在旧字面量。**判据是把「每次提交都变的数」当字面量比**
   —— 这种模型注定下一秒过期（写死再久也追不上提交）。

## 落法

- **判据侧**：`read_shell_value()` 逐字符扫赋值右侧（认 `$(…)` 嵌套与内层引号）；`derivations` 认两种规则
  （`label-strip-milestone-pad3` / `git-commit-count`），**认不出的 kind 判红不猜**；派生式由
  `assignmentAnchor` **逐字**钉住 —— 退回字面量或换写法都判红（否则脚本与判据各算各的）。
- **台账侧**（`release-version.json` v2）：`marketingVersion` 存**快照**（判据复算后比对，标签换了没跟 ⇒ 红）；
  `buildVersion` **不存字面量**，只存派生规则 + `productCheck: shape`（产物那一处只判纯数字）。
- **镜像侧**：`mirrors[].keys` 支持 `{key, enforcement, why}` —— `CURRENT_PROJECT_VERSION` 在
  `project.yml` / 生成物里只解析、**不逐字比**（Xcode 路线不参与发布链；拿每次提交都变的数倒逼源文件只会天天红），
  每次实跑把它打印出来（覆盖不全只报「未知」，不静默放过）。
- **锚点侧**：两条锚原来指着 `Docs/发布方案.md` / `发布计划.md` —— 两份文件 2026-10-26 已**归档**
  （`Docs/` 根只许四书一单 + 3 件工程件）。锚归档件 = 逼人去改历史档案，方向错了 ⇒ 改锚活文档
  `AGENT-SPEC.md` 三处（两处「本版 `x`」逐字 + 两处「构建号 = 提交数」**只判这句话还在**的全新无捕获锚点）。
  归档件两处旧声明写进 `notInScope` 并说明理由。
- **构建那一刻自证**：`build-app.sh` 写完 Info.plist 立刻 `PlistBuddy` 读回三值比对（`CFBundleShortVersionString`
  / `CFBundleVersion` / `DoyahReleaseLabel`），不一致直接失败。判据脚本判不到「这一次构建」，
  这一步只能在构建现场做。
- **工程重生成**：`xcodegen generate`（C3 过期 12 个 `.swift` + 版本号旧字面量一并跟上）。

## 读数（本跳实跑）

```
$ python3 Scripts/check-release-version.py
✅ 发布产物版本号三处逐字一致 + 生成物与 `project.yml` 不漂移（比对点 17 处）
RESULT: OK                       # 修前：❌ 9 处

$ python3 Scripts/check-release-version.py --self-test
自测通过（19 例）                 # 修前：rc=2「夹具锚点失效：找不到 '<string>3</string>'」；16 → 19 例

$ bash /tmp/plist_readback_test.sh 1.0.0 2257 beta1.0   # 真产物三值
读回三值一致  (rc=0)
$ bash /tmp/plist_readback_test.sh 1.0.0 2258 beta1.0   # 反例：构建号差一
错误：产物 Info.plist 的 CFBundleVersion 读回 = 2257，期望 2258   (rc=1)
```

**反例（判红后逐字节还原）**：例 17 把 `BUILD_COUNT` 退回字面量 `2258` ⇒ 判红「是**字面量**…」；
例 18 删掉一处「构建号 = 提交数」声明 ⇒ 判红「现状声明被删了」；例 19 产物构建号写成 `abc` ⇒ 判红「不是纯数字」；
例 4 把 `<string>${MARKETING_VERSION}</string>` 手抄成 `9.9.9` ⇒ 判红；例 3 只改生成物版本号 ⇒ 判红；例 9 文档锚点写错 ⇒ 判红。

**文档门禁**：`invariants 5/5` · `tables 74` · `numbers` 三向 · `plan-coverage` · `status-consistency 471` ·
`version-scope 471` · `doc-layout` · `doc-versions 17` · `agents-index 15` · `check-self-test-counts --no-run`
（族 56 / 例 1077 / 锚点 86）全 rc=0；`plan-batches --check` rc=0（0 条待办）。

## 未验证（≠ 通过）

- **真产物没重建**：`dist/DoyahStudio-beta1.0.app` 仍是上一次的（`CFBundleVersion=2257`）；
  新加的三值读回自证**没在真构建里跑过**（只在产物与注入值上验过逻辑；`build-app.sh` 只做了 `bash -n`）。
- **产物那一处的 `buildVersion` 只判形状**（`2257` 是不是「当时那次构建的提交数」判不了 —— 那要重出包）。
- `project.yml` 的 `CURRENT_PROJECT_VERSION` 仍是 `3`（Xcode 路线的值，不参与发布身份；已在台账里声明不比）。
- 归档件里 `0.3.0` / `3` 两处旧声明**没改**（冻结快照，`notInScope` 里写明理由）。
- `Docs/发布方案.md` / `发布计划.md` 已不在 `Docs/` 根，但 `AGENT-SPEC.md` / 需求书里仍有若干处**引用它们的路径**
  （不是版本号）—— 属另一族的文档漂移，本片未动。

## 下一项

队列仍 **0 todo / 28 blocked**（全卡外部）。机器面按族继续清：下一族 = **自检「绿对照」族**
（真仓库红 ⇒ 自检跟着红的那 5 处：`editor-surface-tokens` / `agent-provider-presets` / `terminal-tabs` /
`tri-repo-parity` / `plugin-assembly` 例 20）—— 本片清掉的 `release-version` 正是这一族的第 6 个成员，可照着同一手法收。
