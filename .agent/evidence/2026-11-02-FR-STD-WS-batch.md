# 判据债第二片（工作区 / 主题 6 条）· 2026-11-02

条目：`FR-STD-WS-UI-008` / `FR-STD-WS-EDIT-016` / `FR-STD-WS-WEB-001` / `FR-STD-WS-FS-001` / `FR-STD-WS-NAV-002`（判据翻 ✅）· `FR-STD-WS-FS-008`（实现 + 判据同降 🟡）

判据：

```
$ for id in FR-STD-WS-UI-008 FR-STD-WS-EDIT-016 FR-STD-WS-WEB-001 FR-STD-WS-FS-001 FR-STD-WS-FS-008 FR-STD-WS-NAV-002; do python3 Scripts/ledger-row.py $id | head -1; done
FR-STD-WS-UI-008 ✅
FR-STD-WS-EDIT-016 ✅
FR-STD-WS-WEB-001 ✅
FR-STD-WS-FS-001 ✅
FR-STD-WS-FS-008 🟡 ｜ 2026-11-02 复核降级：① 的「图片等按各自视图」没有落地 …
FR-STD-WS-NAV-002 ✅

$ ./Scripts/verify-core.sh
ℹ️ Core 单测 5319 项（已写入 .build/core-test-count.txt）
# 收尾：Executed 5319 tests, with 13 tests skipped and 0 failures … rc=0

$ ./Scripts/verify-ui-interactions.sh
✓ 116 条都真跑过（十七批）、都以 passed 收尾、没有跳过      rc=0

$ python3 Scripts/check-status-gap.py
❌ 有 2 行实现已 ✅、判据还没跟上：
   FR-STD-WS-NAV-014 / FR-STD-WS-AI-001        （本片前 8 行）

$ python3 Scripts/check-doc-numbers.py
❌ 1 项：[checkScriptParity] check-status-gap.py 没被 verify-all.sh 引用（存量，非本片）

$ python3 Scripts/check-language-registry.py
✅ 语言登记形状通过：20 种语言 / 61 条扩展名 / 身份分支 0 处 / 取色锚点 12 处 / 默认视图消费者 1 个文件
```

族读数（本片新增 / 触及）：

```
WebKitBrowserEngineTests      12 例 0 失败（+3：页签存储不是同一对象 / 同 id 重建拿回同一套 / 显式注入优先）
MultiCursorTests              23 例 0 失败（+2：相邻两处不合并 / 真重叠必须合并）
WorkspaceHomeProbeTests        6 例 0 失败（新族：Home 开局 / 欢迎语·版本·版权 / 三栏最近打开各接真动作 / 与数据库页签互不持有）
WorkspaceFileOpenGuardProbeTests 5 例 0 失败（新族：超限两数 / 二进制 / GB18030 / 缺文件 / 目录）
AppearanceAxesTests 9 · FontPreferencesTests（9–20 夹取）· AppearanceFontProbeTests 2 · AppearanceAxesProbeTests 1
BrowserContractTests 20 · BrowserDownloadTests 12 · BrowserIdentityTests 10 · BrowserTabStoreTests 6
CodeLanguageRegistryTests 19 · TextLanguageTests 6 · WorkspaceTabTests 5 · WorkspaceHistoryTests 6
```

反例六段（改坏 ⇒ 判红 ⇒ `sha256` 逐字节还原）：

| 反例 | 读数 | 还原 |
| --- | --- | --- |
| 站点存储退回共用 `.default()` | 判红 1 例 | `4cbfa3ed…` 一致 |
| 相邻选区被合并（`<` → `<=`） | 判红 1 例 | `840dcddb…` 一致 |
| 删首页版本行 | 判红 1 例 | `a2678dc3…` 一致 |
| 拿掉大文件上限 | 判红 1 例 | `437024b0…` 一致 |
| `followSystem` 改成恒深色 | 判红 1 例 | `8d64ac29…` 一致 |
| 给回落语言塞一条关键字 | 判红 3 例 | `7d03c5ab…` 一致 |

提交：`cae61520`（已推送，local = remote）

未验证（≠ 通过）：
- 真鼠标点验一条都没点（首页三栏、切主题 / 切深浅、⌥ 拖一列、浏览器页签点开与下载）
- 观感（首页三栏排布 / 字体字号观感）未看
- `FR-STD-WS-FS-008` ① 的「图片等按各自视图」**没有实现**（无图片视图），实现列与判据列都留 🟡
- `WEB-001` ⑤ 已知边界：`WKWebView` 不暴露子资源请求 ⇒ 只判导航级 + 下载级
- 真许可证 / 真云端 / 真站点 Cookie 跨重启均未实测（只判到「按页签 id 取到不同存储对象」）
- `verify-all.sh` 第 11（打包）/ 18（生成物一致性）项未执行
- 全量 `swift test` 本跳出现 2 例存量抖动（`AgentIMTransportTests.testHeartbeatSendsPingFrames` / `SSHTunnelRuntimeTests.testBusyPortFailsFastWithoutStartingAnything`），单族复跑 **14 例 0 失败**；与本片改动面无交集
- 本跳期间工作区出现别家写者的在途改动（`ActivityBarView` / `EgressLogSheet` / `PrivilegePanel` 编译报错），复跑即绿 —— 多写者共用同一克隆的既有现象，记一笔
