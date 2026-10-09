# 云E · 互验前置《格式自证》（**macOS 侧**）· 派单 `T-20261009-120`

| 项 | 内容 |
|---|---|
| 片号 / 片名 | `云E` ｜ 互验前置 · 《格式自证》（`content` JSON 原文 + 元数据字段对照 + 序列化往返读数） |
| 目标仓 | **DoyahStudio**（一仓一片） |
| 交付面（文件级） | `cloud-sync/格式自证-macOS.md`（**新增 · 本片唯一新文件**） |
| 归属 dev | `macos-dev`（macOS 机组） |
| 判据读数 | 见 §六（逐条成对留档） |
| 停手线 → 收口 | **曾命中第 ② 条**（往返**字节面**不一致 2 处）；**前门已裁**（派单 `T-20261009-134` §二 · 收本片停手；契约落笔 `DoyahNotes 15afd80` · SRS **v3.91**）⇒ **本片按新口径收口**：**语义面 0 处不一致 = 通过**；**字节面 2 处 = 登记为已知问题**（按 §6.4.2「序列化确定性」行，见 §三.5）；本片**未自改产品代码 / 未自改契约** |
| 本片改动 | 只新增本文件一个；**零产品代码改动**（探针源只住在 `.build/` 下，不入库） |

---

## 〇 口径与来源（先钉清楚「本侧真序列化」是哪一条调用）

- **契约**：`DoyahNotes fefb09a` · SRS **v3.88** §6.4「互验前置 · 格式自证」行（`Docs/需求规范书.md:831`）+ §6.4.1（`notes` 表列）/ §6.4.2（`IR-15`~`IR-22`）；
  **收口裁定源** = 前门裁（派单 `T-20261009-134` §二 · 收本片停手）+ 契约 **v3.91**（`DoyahNotes 15afd80`）§6.4.2「**序列化确定性**」行 —— 该版本本侧**不可得**（本片禁 `fetch`），故本文对裁定**逐字引用**（见 §三.0），不复述看不见的条文；
  本地格式的权威面另见 `DoyahNotes Docs/核心契约.md` §2.1（`Inspiration` 字段表）/ §2.4（富文本文档与**交换形态**）/ §2.11（`uid`）/ §2.12（两层归属）。
- **本侧代码（本文所有读数的出处）**：
  - 工作树 `/Users/alex/dev/doyah/lead/studio/.worktrees/t_571c7e65` · 分支 `wt/cloud-e` · 基线 `de642b0`（= `origin/master` 同步带入的 HEAD）；
  - 正文类型 `NoteBody` / `NoteSpan` = `Core/NoteBody.swift`；笔记元数据 `Note` = `Core/Note.swift`；笔记本 `Notebook` = `Core/Notebook.swift`；
    同步记录 `SyncRecord` = `Core/NoteSync/SyncCore.swift`（**云B 提交 `347b74c`**，尚未并入本基线，探针按该提交的文件编进来）；
    落库列 = `Core/NoteStorage/NoteDatabase.swift`。
- **序列化调用只此一条**（本侧**没有**第二套序列化 —— 代码注释原话「`NoteBody` 的编解码面 = 交换面，**不另起一套序列化**」）：

  ```
  App/AppState.swift:6916   private static func encodedSpans(_ spans: [NoteSpan]) throws -> String {
  App/AppState.swift:6917       let data = try JSONEncoder().encode(NoteBody(spans: spans))
  App/AppState.swift:7102   let spansJSON = try Self.encodedSpans(snapshot.spans)   // → NoteDatabase.setNoteSpans → note.spans 列
  ```

  即：**默认 `JSONEncoder()`，无 `.sortedKeys`、无 `.prettyPrinted`、无 `.iso8601`**（键序与日期表示都由它默认决定）。

---

## 一 `content` JSON 原文（一条样例笔记）

### 1.1 样例（本次取证用的那一条）

一条笔记的**正文权威源** = `NoteBody{version: 2, spans: [...]}`，13 个 span，逐档覆盖本侧交换面认得的全部形状：
纯文本、`bold` / `italic` / `underline` / `code` 四个行内样式、行内 `color`（`#E53935`）、`size`（18）、`link`（`https://example.com/a`）、
`backgroundColor`（荧光笔淡黄 `#FFF3B0`，值出自 `NoteHighlight.backgroundColorHex`）、三档块级 `LIST_ORDERED` / `LIST_UNORDERED` / `LIST_CHECKBOX`（勾 / 未勾各一）。

### 1.2 ① 默认编码面（**写入口那一条**）· 逐字节贴出

```
{"spans":[{"text":"普通文字 "},{"text":"粗体","styles":["bold"]},{"text":"斜体","styles":["italic"]},{"text":"下划线","styles":["underline"]},{"text":"代码","styles":["code"]},{"styles":["color"],"color":"#E53935","text":"红字"},{"text":"大字","size":18,"styles":["size"]},{"link":"https:\/\/example.com\/a","text":"链接"},{"backgroundColor":"#FFF3B0","text":"荧光"},{"type":"LIST_ORDERED","text":"第一条"},{"type":"LIST_UNORDERED","text":"圆点"},{"type":"LIST_CHECKBOX","checked":true,"text":"带勾任务"},{"type":"LIST_CHECKBOX","checked":false,"text":"未勾任务"}],"version":2}
```

> ⚠️ **这一行的键序不保证复现**：它是本次运行（RUN A）的字节；同一条笔记下一次编码会给出**不同键序**的字节（RUN B 的 `seg1` 与它不同 —— 见 §三）。
> 逐字节比对请用下面 §1.3 那一面。

### 1.3 ①-b `.sortedKeys` 面（键序固定 ⇒ 可作跨端逐字节比对的基准）

```
{"spans":[{"text":"普通文字 "},{"styles":["bold"],"text":"粗体"},{"styles":["italic"],"text":"斜体"},{"styles":["underline"],"text":"下划线"},{"styles":["code"],"text":"代码"},{"color":"#E53935","styles":["color"],"text":"红字"},{"size":18,"styles":["size"],"text":"大字"},{"link":"https:\/\/example.com\/a","text":"链接"},{"backgroundColor":"#FFF3B0","text":"荧光"},{"text":"第一条","type":"LIST_ORDERED"},{"text":"圆点","type":"LIST_UNORDERED"},{"checked":true,"text":"带勾任务","type":"LIST_CHECKBOX"},{"checked":false,"text":"未勾任务","type":"LIST_CHECKBOX"}],"version":2}
```

- 字节数 **611** · `sha256 = 1819153e3158adc141104bf1ee21d482cc698f292302af0722d13d56949d1a34`（RUN A 与 RUN B **同一个值** ⇒ 这一面是字节稳定的）。

### 1.4 本侧键名 → 契约 §2.4 字段的对照（**只报差异，不自改**）

| 本侧 JSON 键（真类型声明） | 契约 §2.4 交换形态 | 差异 |
|---|---|---|
| `version`（`NoteBody.version`，实测 **2**） | `RichTextDocument.version`，契约写「当前 **1**」 | **取值不同**（本侧的 2 是「权威源 v1→v2」的版本号，不是同一个版本轴） |
| `spans`（数组） | `spans`（数组） | 一致 |
| `text`（`NoteSpan.text`，`NoteBody.swift:250`） | `RichTextSpan.content` | **键名不同**（`text` vs `content`） |
| `styles`（**字符串数组**，如 `["bold"]`） | `RichTextStyles` **对象**（`bold` / `italic` / `underline` / `fontSize` / `color` / `code` / `backgroundColor`） | **形状不同**（数组 vs 对象） |
| `color`（span 平铺，`#RRGGBB`） | `styles.color` | **位置不同**（契约在 `styles` 内） |
| `size`（span 平铺，整数） | `styles.fontSize` | **键名 + 位置都不同** |
| `backgroundColor`（span 平铺） | `styles.backgroundColor` | **位置不同** |
| `link`（`NoteSpan.link`） | `RichTextSpan.link` | 一致 |
| `type` + `checked`（**只在这三档块级出现**，值为契约字面量 `LIST_ORDERED` / `LIST_UNORDERED` / `LIST_CHECKBOX`，`NoteBody.swift:182-189`、`366-386`） | `RichTextSpan.type` + `checked` | **一致**（这一条本侧**逐字合契约**，含 `checked` 显式写出） |
| `meta`（`src` / `width` / `height` / `fileName`） | `RichTextSpan.meta` | **本侧无此键**（附件地基未落） |
| 未知键（前向兼容，原样留住再写回，`NoteBody.swift:271-275`、`384-386`） | —— | 本侧**留得住**契约将来加的键（往返不丢，见 §三.3） |

**结论（口径缺口，报前门裁，本片不自改）**：正文的**块级 `type` 面**本侧与 §2.4 逐字同形，但**行内面（`text` / `styles` 形状 / `color` / `size` / `backgroundColor`）与 §2.4 的交换形态不同形**，
而契约 §2.4 不变量④要求「写进交换面 / 备份 / 跨端传输的形态必须与本节字段同形」。⇒ **两侧互验之前必须先裁这一条**（改哪一侧、改哪些键，属契约层 / 产品层，不在本片）。

---

## 二 元数据字段对照（8 项）

取值样例来自本次探针构造的同一条样例笔记；「本侧字段名」逐条引自真声明，「空值 / 缺省表示」是本侧**实测**行为。

| 契约字段（§6.4.1 `notes`） | 本侧实现（真类型 · 位置） | 本侧字段名 | 取值样例 | 类型 | 空值 / 缺省表示（实测） |
|---|---|---|---|---|---|
| `uid` | `SyncRecord.uid`（`Core/NoteSync/SyncCore.swift:43`）；本地身份 = `Note.id: UUID` → 列 `note.uuid TEXT NOT NULL UNIQUE`（`NoteDatabase.swift:57`） | `uid`（同步面）/ `id`（Swift）/ `uuid`（列） | `"8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48"` | String（36 字符 UUID 串） | **非空**：列 `NOT NULL`、Swift 非可选，无缺省 |
| `rev` | **只有**同步面 `SyncRecord.rev`（`SyncCore.swift:45`）；本地 `note` 表**没有** `rev` 列 | `rev` | `3` | Int（JSON 整数） | 无 `null`；**首次落库初始值本侧尚未装配**（装配面 = 云D） |
| `updated_at` | `Note.updatedAt: Date`（`Note.swift:48`）→ 列 `note.updated_at REAL NOT NULL`，写入 `.real(note.updatedAt.timeIntervalSince1970)`（`NoteDatabase.swift:679`）；同步面 `SyncRecord.updatedAt: Date`（`SyncCore.swift:46`） | `updatedAt`（Swift）/ `updated_at`（列） | 列值 `1790000000.0`（REAL）；默认 JSON 面 `811692800`；`.iso8601` 面 `"2026-09-21T14:13:20Z"` | **三种表示并存**：REAL（Unix 秒）/ JSON 数值（Apple 参考日 2001-01-01 起的秒）/ ISO8601 字符串 | **非空**：列 `NOT NULL` |
| `deleted_at` | **只有**同步面 `SyncRecord.deletedAt: Date?`（`SyncCore.swift:48`）；本地 `note` 表**没有** `deleted_at` 列 —— 本地删除是**物理删**（`DELETE FROM note WHERE uuid = ?`，`NoteDatabase.swift:760`） | `deletedAt` | 非墓碑 `nil`；墓碑样例 `"deletedAt":811692800` | `Date?`（可空） | **`nil` 时 JSON 键缺失**（实测非墓碑编码面里**没有** `deletedAt` 这个键，不是 `null`） |
| `title` | `Note.title: String`（`Note.swift:43`）→ 列 `note.title TEXT NOT NULL` | `title` | `"同步格式样例"` | String | **空串 `""`**（契约：允许空串），不是 `null` |
| `notebook_uid` | 列 `note.notebook_uid TEXT`（`NoteDatabase.swift:181`，schema v2 **可空列**）+ `Notebook.uid: String`（`Notebook.swift:53` 起） | `notebookUid`（Swift）/ `notebook_uid`（列） | `"3F2A6C1D-0B47-4E9A-9C55-7A1E4D2B8F30"` | String | **列可空（允许 `NULL`）**；「每条笔记必有归属」这条不变量由**写入 / 迁移**保证（`upsert` 落默认笔记本），不由 `NOT NULL` 保证 |
| `tags` | `Note.tags: [String]`（`Note.swift:45`）；库里是**多行表** `note_tag(note_id, tag)`（`NoteDatabase.swift:73-78`），不是一列 | `tags` | `["同步","格式"]` | `[String]`（JSON 数组） | **空数组 `[]`** |
| `pinned` | `Note.isPinned: Bool`（`Note.swift:60`）→ 列 `note.pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1))`（`NoteDatabase.swift:222`） | `isPinned`（Swift）/ `pinned`（列） | `true`（库里 `1`） | Bool（JSON 布尔）/ INTEGER 0\|1（库） | 无空值；缺省 `0` / `false` |

### 2.1 本侧元数据**编码面**读数（真类型 · 默认与 `.iso8601` 两种策略）

`Note`（默认 `JSONEncoder()`，键序实测不固定）：

```
{"id":"8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48","isFavorite":true,"tags":["同步","格式"],"source":{"kind":"manual","capturedAt":811692800},"isPinned":true,"updatedAt":811692800,"title":"同步格式样例","createdAt":811692800,"containsRowData":false,"body":"普通文字 **粗体***斜体*下划线`代码`红字大字[链接](https:\/\/example.com\/a)荧光第一条圆点带勾任务未勾任务"}
```

`Note`（`NoteStore.save` 用的 `.iso8601` 策略面）：

```
{"title":"同步格式样例","isFavorite":true,"body":"...","updatedAt":"2026-09-21T14:13:20Z","containsRowData":false,"id":"8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48","createdAt":"2026-09-21T14:13:20Z","isPinned":true,"source":{"kind":"manual","capturedAt":"2026-09-21T14:13:20Z"},"tags":["同步","格式"]}
```

`SyncRecord`（云B 面，默认 `JSONEncoder()`；`payload` 里那一段就是 §1.2 的 `content` 原文再转义一层）：

```
{"uid":"8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48","payload":"{\"spans\":[...],\"version\":2}","rev":3,"updatedAt":811692800}
```

`SyncRecord`（墓碑样例，`deletedAt` 非空时才多出这一个键）：

```
{"uid":"8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48","payload":"{\"spans\":[...],\"version\":2}","rev":3,"updatedAt":811692800,"deletedAt":811692800}
```

---

## 三 序列化往返读数（序列化 → 反序列化 → 再序列化）

### 3.0 收口裁定（**逐字引用** · 派单 `T-20261009-134` §二；本侧禁 `fetch` 看不到 v3.91 条文，故引裁定原文）

> 1. **比对口径 = 归一化后的字段级比对**（键集合 / 类型 / 取值语义）；**键序差异先归一化再比**，**不作为交付阻断** ⇒ 你实测的「字节面不一致 2 处 / 语义面 0 处」**不再是退回理由**；
> 2. **但要求确定性序列化**：`content` 富文本 JSON 与元数据**必须键序稳定**（同一输入在不同进程 / 不同次运行产出**同一字节**），数字与时间格式固定 —— 跨端互验与附件 `sha256` / 冲突判定的前提；
> 3. **跨进程字节不稳 ⇒ 如实登记为已知问题**（现象 / 根因 `App/AppState.swift:6916-6917` 默认 `JSONEncoder()` / 已实测 `.sortedKeys` 可稳 / 修点片另立）；
> 4. 归一化规则（键排序方式 / 时间精度）**两端同源**，写进**本侧实现笔记**，互验前对齐。

### 3.1 复现命令（**本仓可跑**，不改产品代码）

```bash
WORKTREE=/Users/alex/dev/doyah/lead/studio/.worktrees/t_571c7e65
SYNC=/Users/alex/dev/doyah/lead/studio/.worktrees/t_3d5bceb1/Core/NoteSync/SyncCore.swift   # 云B 347b74c 的同一份；并入 master 后改为 $WORKTREE/Core/NoteSync/SyncCore.swift
mkdir -p "$WORKTREE/.build/format-self-attest"
cp <本文件 §附 的探针源> "$WORKTREE/.build/format-self-attest/main.swift"
swiftc -O \
  "$WORKTREE/Core/NoteBody.swift" "$WORKTREE/Core/Localization.swift" \
  "$WORKTREE/Core/Note.swift" "$WORKTREE/Core/DoyahIdentity.swift" \
  "$WORKTREE/Core/Notebook.swift" "$SYNC" \
  "$WORKTREE/.build/format-self-attest/main.swift" \
  -o "$WORKTREE/.build/format-self-attest/probe"
"$WORKTREE/.build/format-self-attest/probe"     # 跑两遍：两遍的读数一起看（跨进程稳定性就在这两遍之间判）
```

编进来的都是**本仓真类型**（`NoteBody` / `NoteSpan` / `Note` / `Notebook` / `SyncRecord`），序列化调用与写入口 `App/AppState.swift:6917` 逐字同一条。
探针源见 §附（157 行，逐字节给出，可原样重放）。

### 3.2 打印原文（RUN A）

```
=== ② 三段读数 ===
seg1 字节数 = 611  sha256 = 285b25f4a7fc7a6f50906d9bdcdd27fce0069ba7c1c7b3f4fa2495f1e9730f25
seg2 字节数 = 611  sha256 = 7a1030d2180327c845c15f6f76f7b2728f6d1def0e43ad11c03e7e6e1aaaf7f2
seg3 字节数 = 611  sha256 = 7a1030d2180327c845c15f6f76f7b2728f6d1def0e43ad11c03e7e6e1aaaf7f2
seg1 == seg2 逐字节: false
seg2 == seg3 逐字节: true
seg1 == seg3 逐字节: false
不一致处数 = 2

=== ③ 逐字段（语义面）===
back1.spans == spans : true
back2.spans == spans : true
back1.version = 2  back2.version = 2
span 条数 : 原 13 / 回 13 / 再回 13
  [0] text=普通文字  ... 一致=true
  [1] text=粗体 styles=["bold"] ... 一致=true
  [2] text=斜体 styles=["italic"] ... 一致=true
  [3] text=下划线 styles=["underline"] ... 一致=true
  [4] text=代码 styles=["code"] ... 一致=true
  [5] text=红字 styles=["color"] color=#E53935 ... 一致=true
  [6] text=大字 styles=["size"] size=18 ... 一致=true
  [7] text=链接 styles=[] link=https://example.com/a ... 一致=true
  [8] text=荧光 styles=[] backgroundColor=#FFF3B0 ... 一致=true
  [9] text=第一条 block=Optional(probe.NoteSpan.Block.ordered) 一致=true
  [10] text=圆点 block=Optional(probe.NoteSpan.Block.bullet) 一致=true
  [11] text=带勾任务 block=Optional(probe.NoteSpan.Block.task(checked: true)) 一致=true
  [12] text=未勾任务 block=Optional(probe.NoteSpan.Block.task(checked: false)) 一致=true
投影 body = 普通文字 **粗体***斜体*下划线`代码`红字大字[链接](https://example.com/a)荧光第一条圆点带勾任务未勾任务

=== ③-b 同一份内容、同一编码器重复编码 ===
默认 JSONEncoder 第1/2/3 次 sha = 7a1030d2180327c845c15f6f76f7b2728f6d1def0e43ad11c03e7e6e1aaaf7f2 / 7a1030d2180327c845c15f6f76f7b2728f6d1def0e43ad11c03e7e6e1aaaf7f2 / 7a1030d2180327c845c15f6f76f7b2728f6d1def0e43ad11c03e7e6e1aaaf7f2
默认 JSONEncoder 1==2: true  2==3: true  1==3: true
.sortedKeys 第1/2/3 次 sha = 1819153e3158adc141104bf1ee21d482cc698f292302af0722d13d56949d1a34 / 1819153e3158adc141104bf1ee21d482cc698f292302af0722d13d56949d1a34 / 1819153e3158adc141104bf1ee21d482cc698f292302af0722d13d56949d1a34
.sortedKeys 1==2: true  2==3: true  1==3: true
```

**RUN B（新进程，同一命令再跑一遍）**：

```
seg1 字节数 = 611  sha256 = c14d62f1e8dbaccaec764068d7242b75e614e2535bea51ddc3724dcc15a753fb
默认 JSONEncoder 第1/2/3 次 sha = a1f4d1c6eef0681e861995e095f60f1eb85249f505f4c9cebe726b79b8847c87 / a1f4d1c6eef0681e861995e095f60f1eb85249f505f4c9cebe726b79b8847c87 / a1f4d1c6eef0681e861995e095f60f1eb85249f505f4c9cebe726b79b8847c87
canon 字节数 = 611  sha256 = 1819153e3158adc141104bf1ee21d482cc698f292302af0722d13d56949d1a34（与 RUN A 相同）
```

### 3.3 读数表（**收口新口径**：比对 = 归一化后的字段级比对；键序差异先归一化再比）

| 面 | 读数 | 新口径下的判定 |
|---|---|---|
| **语义面**（解码回来的 span 树 / JSON 对象；= 归一化后的字段级比对） | `back1.spans == spans` ✅、`back2.spans == spans` ✅、13/13/13 条**逐字段全一致**、`version` 2↔2（**键集合 / 类型 / 取值语义全同**） | ✅ **不一致 0 处 ⇒ 通过** |
| **`.sortedKeys` 面**（键序固定；= 归一化到键排序后的字节面） | `canon1 == canon2` ✅，RUN A / RUN B 同一个 `sha256`（1819153e…），同进程三次重复亦逐字节相同 | ✅ **不一致 0 处 ⇒ 通过** |
| **未归一化字节面**（默认编码器 = 写入口那一条） | `seg1≠seg2`、`seg1≠seg3` ⇒ 不一致 **2 处**；RUN A 的 `seg1`(285b25f4…) 与 RUN B 的 `seg1`(c14d62f1…) **不同**，重复编码三次读数亦随进程变 | ⚠️ **不等于语义面失败**：只是**键序**随进程变，归一化（键排序）后即与 `.sortedKeys` 面**同字节** ⇒ **登记为已知问题**（§三.5），**不作交付阻断** |

### 3.4 结论（**本片只报，不自改**）

- 本侧**内容语义往返是干净的**（字段级 0 处不一致；未知键也留得住 —— 既有单测 `Tests/NoteBodyTests.swift` 的 `testSpansRoundTripThroughJSON` / `testBlockSpansRoundTripThroughJSON` / `testUnknownSpanFieldsSurviveRoundTrip` 是同一结论的独立证据）⇒ 按前门裁定的新比对口径 **通过**（键序差异先归一化再比）。
- **但字节面尚未确定**：写入口用的是**默认 `JSONEncoder()`**，其键序不保证保序 —— 实测同一份内容（a）**跨进程**给出不同字节，（b）**同进程首次编码与前几次也未必相同**（`RUN A`：首编码 `285b25f4…`，其后 `7a1030d2…`；`RUN B`：`c14d62f1…` / `a1f4d1c6…`）。⇒ `content` JSON **不能**作「未归一化逐字节一致」的载体（归一化 / 加 `.sortedKeys` 后可以）。

### 3.5 已知问题登记（按 §6.4.2「序列化确定性」行 · **本片只登记，不改**）

| 项 | 内容 |
|---|---|
| 现象 | 同一份 `content` 富文本 / 元数据，**不同进程**（乃至同进程的非首次编码）产出**不同字节**；键序不保序 |
| 根因（机械判住） | 写入口 `App/AppState.swift:6916-6917`（`note.spans` 列的**唯一写路**）用的是**默认 `JSONEncoder()`**，未设 `outputFormatting` |
| 已实测可稳 | 该调用加 **`.sortedKeys`** 后，**同进程三次与跨进程两次给出同一个 `sha256`**（`1819153e3158adc141104bf1ee21d482cc698f292302af0722d13d56949d1a34`，611 B） |
| 为何算问题 | 确定性序列化（同一输入在不同进程 / 不同次运行产出**同一字节**，数字与时间格式固定）是**跨端互验**与**附件 `sha256` / 冲突判定**的前提（裁定原文，见 §三.0） |
| 修点 | **产品代码** `App/AppState.swift` 的编码调用（加 `.sortedKeys` + 定 `/` 是否转义 + 定 `Date` 表示）—— **不在本片可改范围**；已**另立片**「云-编码canonical」（与 `云D` / `云G` 串行，排在 `云D` 之后） |

## 四 归一化规则（**两端同源** · 互验前对齐）

> 目的：把裁定第 1 条那半句「**归一化后的字段级比对**」写成**两端各跑一遍、结果对得上**的可执行规则；并把裁定第 4 条要求的「归一化规则两端同源」固化在本节。分两层：**A 层 = 比对用（语义级，互验当场执行）**；**B 层 = 字节用（确定性序列化，交付 / 校验用）**。

### 4.1 A 层 · 比对用（字段级，**键序无关**）

| 步 | 规则 | 本侧现状 / 依据 |
|---|---|---|
| A1 | **键集合**：键名逐字比较（**不换名 / 不加键 / 不减键**）；两侧键集合必须相等 | 本侧键集见 §1.4 / §二；已列差异须先由前门裁掉（§五清单） |
| A2 | **值类型**：同名字段类型必须一致（String / Int / Bool / 数组 / 对象 …） | §二 表「类型」列 |
| A3 | **取值语义**：按类型语义比较（数按数值、布尔按真假、数组按**有序**逐元素、对象递归）—— **不按字面串比** | `13/13/13` 逐字段比对即此层（§三.3 语义面） |
| A4 | **可选值**：本侧 Swift 合成 `Codable` 的 `nil` = **键缺失**（非 `null`）；等比时若两端对「缺键 ↔ `null`」是否等价未裁，**先按「缺键 ≡ `null`」比** | `SyncRecord.deletedAt` 实测（§五清单 #8 待前门一句话） |
| A5 | **键序**：**不参与** A 层比对（键序差异先归一化再比 —— 裁定原文） | 裁定第 1 条 |

### 4.2 B 层 · 字节用（确定性序列化：键序 / 数字 / 时间固定）

| 项 | 规则 | 本侧实测 |
|---|---|---|
| B1 **键排序** | JSON 对象键按**升序**序列化（Swift `JSONEncoder.OutputFormatting.sortedKeys` 的键序） | 实测该键序**跨进程、跨重复编码同一字节**（`sha256 1819153e…`）⇒ 可作基准 |
| B2 **空白** | **紧凑输出**：无缩进 / 无换行 / 无多余空格（不加 `.prettyPrinted`） | 实测输出即紧凑 |
| B3 **数字** | 整数按整数写（`18`、`rev:3`），浮点按最短往返表示，**不补尾零** | `size=18` 等（§一.2） |
| B4 **时间** | 契约要求**固定**。本侧现状**三种表示并存**：库列 REAL（**Unix 秒**）/ 默认 JSON（**Apple 参考日 2001-01-01 起的秒**）/ `NoteStore.save` 的 `.iso8601`（`2026-09-21T14:13:20Z`）。**交换面建议归一到 UTC ISO8601 秒精度**（`yyyy-MM-dd'T'HH:mm:ss'Z'`），跨端比大小 / 比相等前先归一 | §二 `updated_at` / `deleted_at` 行 |
| B5 **`/` 转义** | Swift 默认把 `/` 转义为 `\/`；`.withoutEscapingSlashes` 会改字节。**两端必须择一（同源）** | §一.2 实测 `https:\/\/example.com\/a` |
| B6 **时间字段名** | 列名 `updated_at` / `deleted_at` 与 Swift 属性名 `updatedAt` / `deletedAt` 的映射（`convertToSnakeCase` 与否）须两端一致 | §二 表 |

> **B 层状态**：B1 已实测**可做到**（加 `.sortedKeys` 即稳定）；**B4 / B5 / B6 的选择属契约 / 产品层，本片不裁**，连同「写入口加 `.sortedKeys`」一并**归修点片**（云-编码canonical，见 §三.5）。**本节 A 层 = 本片可交付的比对口径；B 层 = 待装配目标 + 建议值**，均标「两端同源」供前门对齐。

---

## 五 与契约口径的差异清单（一律**报前门**，本片不自解）

| # | 差异 | 位置 | 影响 |
|---|---|---|---|
| 1 | `content` JSON **键序不保序** ⇒ 未归一化字节不稳定 | §三.5 | **已登记为已知问题**（按 §6.4.2「序列化确定性」行）；**归一化后即稳定、不作交付阻断**（裁定第 1 条）；修点片另立（云-编码canonical） |
| 2 | 行内面交换形态与 §2.4 不同形（`text` vs `content`；`styles` 数组 vs 对象；`color`/`size`/`backgroundColor` 平铺 vs 收在 `styles` 内） | §1.4 | 跨端读到对方的正文会**解不出样式**（块级 `type` 面已同形） |
| 3 | `version`：本侧 `NoteBody.version = 2`；§2.4 写「当前 1」 | §1.4 | 版本轴不同 ⇒ 需裁「同一根版本轴还是各自版本轴」 |
| 4 | 时间表示三种并存：库 REAL（Unix 秒）/ 默认 JSON（Apple 参考日秒）/ `.iso8601` 字符串；契约 §2.1 写「毫秒时间戳」 | §二 | `updated_at` / `deleted_at` 跨端比大小、比相等会错 |
| 5 | `uid` / `rev` / `deleted_at` 本侧**只有同步面**（`SyncRecord`）；本地 `note` 表无 `rev` / `deleted_at` 列，笔记身份列名是 `uuid`（不是 `uid`） | §二 | 本地 → 上行的装配点本侧尚未存在（云D 片） |
| 6 | 契约 §2.4 的 `meta`（附件地基）本侧**无此键** | §1.4 | 附件单列（`IR-19/20` 不在本片），登记待办即可 |
| 7 | `content_type`：本侧无该字段（契约 §6.4.1 `notes.content_type` / §2.1 `contentType` 恒为文本） | §二 | 上行时需装配（或前门裁定留空） |
| 8 | 可选值 `nil` 的表示：本侧 Swift 合成 Codable 是**键缺失**（非 `null`） | §二（`deletedAt`） | 「缺键」与「null」是否等价，需前门一句话（本侧现状：缺键） |
| 9 | 一整行 `notes`（8 字段同体 + `content`）在本侧**尚无装配点**：`Note`（本地）/ `SyncRecord`（同步面）两个类型目前各管一半 | §二 | 互验前需云D 落装配（本片只是把两侧现状固化成读数） |

---

## 六 判据读数（逐条成对留档）

1. **目录**：`ls cloud-sync/` 改前 ⇒ `ls: cloud-sync/: No such file or directory`（退出码 1，改前**不存在**）；改后 ⇒ 本文件在盘（新增 1 个文件）。
2. **三段结构在位**：§一（`content` JSON 原文，`json` 块逐字节贴出）· §二（八字段对照表：字段 / 取值样例 / 类型 / 空值·缺省表示 四列齐）· §三（进 → 出 → 再进，逐字段标「一致 / 不一致：哪一项」）· §四（**归一化规则**：A 比对层 / B 字节层）。
3. **往返读数可复现**：命令与探针源见 §3.1 / §附；打印原文见 §3.2。读数 = **语义面不一致 0 处（⇒ 通过）**、`.sortedKeys` 面不一致 0 处、**未归一化字节面不一致 2 处（登记为已知问题，见 §三.5）** —— 按收口新口径（裁定第 1 条）**不作交付阻断**。
4. **`bash Scripts/verify-core.sh`** ⇒ 读数见 §6.1（本片**零产品代码改动**，应与改前**同读数**）。
5. **边界自查**：未碰 `Docs/**`（本文只引用契约）· **零 `tcb` 写操作** · 未装全局包 · 未提交任何 secret / key / token / 口令（本文与探针里没有任何凭据；样例值全是本地造的字面量）· 只本地 `git commit`，**未 push / 未 fetch / 未 rebase** · 只新增 `cloud-sync/格式自证-macOS.md` 一个文件。

### 6.1 `verify-core.sh` 读数（**收口重跑一次** · 见下）

```
$ cd /Users/alex/dev/doyah/lead/studio/.worktrees/t_571c7e65
$ bash Scripts/verify-core.sh            # ← 收口重跑（2026-10-09 · 判据 4）
ℹ️ 工具链证据: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer · Xcode 27.0 Build version 27A266a
（SwiftPM 依赖已缓存 ⇒ 直接 [Using on-disk description] 进构建，无网络抓取）
...
	 Executed 2871 tests, with 2 tests skipped and 0 failures (0 unexpected) in 5.951 (6.110) seconds
ℹ️ Core 单测 2871 项（已写入 .build/core-test-count.txt，供 Scripts/check-doc-numbers.py 对账）
VERIFY_CORE_EXIT=0
```

| 项 | 读数 |
|---|---|
| 收口重跑 | **exit 0** · **2871 项 · 0 failures**（2 项 skip 为既有）—— 与改前那一轮 **同读数**；本片**零产品代码改动**（只新增本文件），与基线 `de642b0` 一致 —— 云B 的交付记录里那条基线读数也是 2871 |
| 唯一允许红 | `Scripts/check-doc-numbers.py` 的 `[core-tests]` **实测 2871 vs 台账 2832** —— 台账陈旧红，归前门 `T-20261009-040`；本片**未碰** `Docs/**` 与台账（`verify-core.sh` 本身不跑该判据，此处照实登记） |
| 日志落点 | `.build/verify-core-rerun.log`（**收口重跑**的完整日志）；`.build/core-test.log`（`xctest` 同一套原始日志） |

---

## 七 机器面

| 项 | 值 |
|---|---|
| 工作树 | `/Users/alex/dev/doyah/lead/studio/.worktrees/t_571c7e65` |
| 分支 | `wt/cloud-e` |
| 基线 | `de642b0`（本仓 HEAD，与 `origin/master` 同步带入的那一笔） |
| 探针源（仓外，只落到 `.build/`） | 见 §附；跑完的产物：`.build/format-self-attest/`、`.build/stability/`、`.build/determinism/`（皆在 gitignore 的 `.build/` 下，不入库） |
| 工具链 | Apple Swift 6.4（`swift-driver version 1.168.6`；`/usr/bin/swift` 与 Xcode 内置 `XcodeDefault.xctoolchain/usr/bin/swift` 同一版本）· 与 `Scripts/verify-core.sh` 用的 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 同一套 |

---

## 附 探针源（逐字节，可原样重放）

```swift
import Foundation
import CryptoKit

// 《格式自证》取证探针（云E · 派单 T-20261009-120 · macOS 机组）
//
// 用法（在出片工作树里跑，**不改产品代码**：探针源只住在 `.build/` 下）：
//   WORKTREE=/Users/alex/dev/doyah/lead/studio/.worktrees/t_571c7e65
//   SYNC=<云B 提交 347b74c 的 Core/NoteSync/SyncCore.swift>
//   mkdir -p "$WORKTREE/.build/format-self-attest"
//   cp <本源> "$WORKTREE/.build/format-self-attest/main.swift"
//   swiftc -O \
//     "$WORKTREE/Core/NoteBody.swift" "$WORKTREE/Core/Localization.swift" \
//     "$WORKTREE/Core/Note.swift" "$WORKTREE/Core/DoyahIdentity.swift" \
//     "$WORKTREE/Core/Notebook.swift" "$SYNC" \
//     "$WORKTREE/.build/format-self-attest/main.swift" \
//     -o "$WORKTREE/.build/format-self-attest/probe"
//   "$WORKTREE/.build/format-self-attest/probe"
//
// 编进来的都是**本仓真类型**：`NoteBody` / `NoteSpan`（Core/NoteBody.swift）、
// `Note`（Core/Note.swift）、`Notebook` / `Shelf`（Core/Notebook.swift）、
// `SyncRecord`（Core/NoteSync/SyncCore.swift，云B 提交 347b74c）。
// 序列化调用与写入口同一条：`JSONEncoder().encode(NoteBody(spans:))`
//（App/AppState.swift:6917 —— 落库 `note.spans` 列用的就是这一句）。

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func hexBytes(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

// MARK: - 一、样例笔记（一条）的正文 span 树

let spans: [NoteSpan] = [
    NoteSpan(text: "普通文字 "),
    NoteSpan(text: "粗体", styles: [.bold]),
    NoteSpan(text: "斜体", styles: [.italic]),
    NoteSpan(text: "下划线", styles: [.underline]),
    NoteSpan(text: "代码", styles: [.code]),
    NoteSpan(text: "红字", styles: [.color], color: "#E53935"),
    NoteSpan(text: "大字", styles: [.size], size: 18),
    NoteSpan(text: "链接", link: "https://example.com/a"),
    NoteSpan(text: "荧光", backgroundColor: NoteHighlight.backgroundColorHex),
    NoteSpan(text: "第一条", block: .ordered),
    NoteSpan(text: "圆点", block: .bullet),
    NoteSpan(text: "带勾任务", block: .task(checked: true)),
    NoteSpan(text: "未勾任务", block: .task(checked: false))
]

let body = NoteBody(spans: spans)

// MARK: - 二、三段序列化（序列化 → 反序列化 → 再序列化）

let seg1 = try JSONEncoder().encode(body)
let back1 = try JSONDecoder().decode(NoteBody.self, from: seg1)
let seg2 = try JSONEncoder().encode(back1)
let back2 = try JSONDecoder().decode(NoteBody.self, from: seg2)
let seg3 = try JSONEncoder().encode(back2)

print("=== ① content JSON 原文（逐字节贴出；不美化 / 不重排 / 不换字段序）===")
print(hexBytes(seg1))
print("")
print("=== ①-b content JSON（.sortedKeys 面：键序固定，供跨端逐字节比对当基准）===")
let canonical = JSONEncoder()
canonical.outputFormatting = [.sortedKeys]
let canon1 = try canonical.encode(body)
let canonBack = try JSONDecoder().decode(NoteBody.self, from: canon1)
let canon2 = try canonical.encode(canonBack)
print(hexBytes(canon1))
print("canon 字节数 = \(canon1.count)  sha256 = \(sha256Hex(canon1))")
print("canon1 == canon2 逐字节: \(canon1 == canon2)")
print("")
print("=== ② 三段读数 ===")
print("seg1 字节数 = \(seg1.count)  sha256 = \(sha256Hex(seg1))")
print("seg2 字节数 = \(seg2.count)  sha256 = \(sha256Hex(seg2))")
print("seg3 字节数 = \(seg3.count)  sha256 = \(sha256Hex(seg3))")
print("seg1 == seg2 逐字节: \(seg1 == seg2)")
print("seg2 == seg3 逐字节: \(seg2 == seg3)")
print("seg1 == seg3 逐字节: \(seg1 == seg3)")
print("不一致处数 = \([seg1 == seg2, seg2 == seg3, seg1 == seg3].filter { !$0 }.count)")

// 逐字段（语义面）对照：三段解回来的 span 树是否等价 + 各字段
print("")
print("=== ③ 逐字段（语义面）===")
print("back1.spans == spans : \(back1.spans == spans)")
print("back2.spans == spans : \(back2.spans == spans)")
print("back1.version = \(back1.version)  back2.version = \(back2.version)")
print("span 条数 : 原 \(spans.count) / 回 \(back1.spans.count) / 再回 \(back2.spans.count)")
for (index, span) in spans.enumerated() {
    let a = back1.spans[index]
    let b = back2.spans[index]
    let same = (a == span) && (b == span)
    print("  [\(index)] text=\(span.text) styles=\(span.styles.map(\.rawValue).sorted()) color=\(span.color ?? "null") size=\(span.size.map(String.init) ?? "null") link=\(span.link ?? "null") backgroundColor=\(span.backgroundColor ?? "null") block=\(String(describing: span.block)) 一致=\(same)")
}
print("投影 body = \(body.body)")

// MARK: - 二-b、编码器字节稳定性（同进程三次 / 跨进程两次）

print("")
print("=== ③-b 同一份内容、同一编码器重复编码 ===")
let rep1 = try JSONEncoder().encode(body)
let rep2 = try JSONEncoder().encode(body)
let rep3 = try JSONEncoder().encode(body)
print("默认 JSONEncoder 第1/2/3 次 sha = \(sha256Hex(rep1)) / \(sha256Hex(rep2)) / \(sha256Hex(rep3))")
print("默认 JSONEncoder 1==2: \(rep1 == rep2)  2==3: \(rep2 == rep3)  1==3: \(rep1 == rep3)")
let srt1 = try canonical.encode(body)
let srt2 = try canonical.encode(body)
let srt3 = try canonical.encode(body)
print(".sortedKeys 第1/2/3 次 sha = \(sha256Hex(srt1)) / \(sha256Hex(srt2)) / \(sha256Hex(srt3))")
print(".sortedKeys 1==2: \(srt1 == srt2)  2==3: \(srt2 == srt3)  1==3: \(srt1 == srt3)")

// MARK: - 三、元数据字段（8 项）：本侧真类型的取值样例与编码面

let when = Date(timeIntervalSince1970: 1_790_000_000)

let notebook = Notebook(uid: "3F2A6C1D-0B47-4E9A-9C55-7A1E4D2B8F30", shelfUid: "5C7B1E90-3D24-4A6F-B0C8-2E9F5A7D4311", name: "默认笔记本", sortOrder: 0, createdAt: when, isDefault: true)
let note = Note(
    id: UUID(uuidString: "8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48")!,
    title: "同步格式样例",
    body: body.body,
    tags: ["同步", "格式"],
    source: NoteSource(kind: .manual, capturedAt: when),
    createdAt: when,
    updatedAt: when,
    isFavorite: true,
    isPinned: true
)
let record = SyncRecord(
    uid: note.id.uuidString,
    rev: 3,
    updatedAt: when,
    deletedAt: nil,
    deviceId: nil,
    payload: hexBytes(seg1)
)

print("")
print("=== ④ 元数据字段对照（本侧真类型）===")
print("note.id (本机 uuid 列) = \(note.id.uuidString)")
print("Note 编码面（Core/Note.swift，默认 JSONEncoder）=")
print(hexBytes(try JSONEncoder().encode(note)))
print("Note 编码面（NoteStore.save 的 .iso8601 策略）=")
let isoEncoder = JSONEncoder()
isoEncoder.dateEncodingStrategy = .iso8601
print(hexBytes(try isoEncoder.encode(note)))
print("Notebook.uid (notebook.uid 列) = \(notebook.uid)")
print("SyncRecord 编码面（Core/NoteSync/SyncCore.swift，默认 JSONEncoder）=")
print(hexBytes(try JSONEncoder().encode(record)))
print("SyncRecord 编码面（.iso8601 策略）=")
print(hexBytes(try isoEncoder.encode(record)))
print("SyncRecord.deletedAt 非墓碑 = \(record.deletedAt.map(String.init(describing:)) ?? "null")；墓碑样例（deleted_at 非 null）=")
var tombstone = record
tombstone.deletedAt = when
print(hexBytes(try JSONEncoder().encode(tombstone)))
print("")
print("=== ⑤ 判据读数 ===")
print("清单一：本侧 content 编码面（供前门与安卓侧逐字段比对）")
print("清单二：不一致处 = \([seg1 == seg2, seg2 == seg3, seg1 == seg3].filter { !$0 }.count)（期望 0）")
```

---

## 八 收口：写入面 canonical 编码（片 `云-编码canonical` · 前置 `云D` `t_806b2f9f`）

> 本节是 **§三.5「已知问题 / 修点」的收口**：把 `云E` 登记的那条「跨进程字节不稳」修掉，并把
> §四 B 层那几项「待装配目标 / 建议值」落成**实现口径**（**两端同源**）。
> 裁定源 = **前门 ⑲**（SRS **v3.93** `2bfe63b` §6.4.1.1）+ **`T-20261009-134` §二**；读数出处 = 本文件 §一~§三。

### 8.1 改了哪几处（文件级 · **现有文件** · 零新增 `.swift`）

| # | 文件 | 改什么 | 为什么在**这一处** |
|---|---|---|---|
| 1 | `Core/NoteBody.swift` | 新增 `enum NoteBodyCanonical`（`encoder()` / `json(_:)`）—— **正文 canonical 编码的唯一出处** | 本文件头部原话「`NoteBody` 的编解码面 = 交换面，**不另起一套序列化**」：写入口 / 单测 / 探针取的都该是**这一条** |
| 2 | `App/AppState.swift` | `encodedSpans`（`note.spans` 列的**唯一写路**，§〇 实测 `:6916-6917`）改调 `NoteBodyCanonical.json(…)` | **修点原位**；不再就地 `JSONEncoder()`（那样写入口 / 单测 / 探针＝三份配置） |
| 3 | `Core/NoteSync/CloudSyncService.swift` | `CloudSyncCoding`：**写入**用本机时区 + 毫秒 3 位；**读取**归一到 UTC 毫秒；装配点 `NoteLibraryCloudSource.cloudRow` 把本地 `updatedAt` 归一到毫秒 | 同步面的**时间写入口**（裁定 ⑲ ②） |

`Tests/`：**新增 2 例** ——
`Tests/NoteBodyTests.swift::testCanonicalSerializationKeepsContentAndMetadataByteStable`（正文面 + 元数据面）·
`Tests/NoteSyncE2ETests.swift::testTimestampWriteReadFollowsCanonicalMillisecondRule`（时间口径）。
`Core/NoteSync/SyncCore.swift` **未改**（它**没有**任何编解码调用 —— 卡面写的「同步行编码 · 若涉」= 不涉）。

### 8.2 canonical 规则逐条落位（§四 B 层 → 实现 · **两端同源**）

| 项 | 规则 | 落位 / 现状 |
|---|---|---|
| **B1 键排序** | 字典序**升序** | `NoteBodyCanonical.encoder()` 与 `CloudSyncCoding.encoder()` 都是 `.sortedKeys` |
| **B2 空白** | 交换面**紧凑**（无缩进 / 换行 / 冗余空白）；本地 `notes.json` 仍 `.prettyPrinted`（那是**给人读的落盘文件**，不是交换载体） | 同上；`NoteStore.save` 不变 |
| **B3 数字** | 整数写整数、浮点按**最短往返**表示、不补尾零 | `JSONEncoder` 默认（§8.3 实测 `size":18` / `rev":3`） |
| **B4 时间** | **写入** = ISO8601 **毫秒 3 位 + 时区偏移**（`…T22:40:00.000+08:00`）；**读取 / 比对** = 先**归一到 UTC 毫秒**再比，**禁止时间字段字符串比较** | `CloudSyncCoding.writer()` / `.parseDate` / `.normalizedToMilliseconds` |
| **B5 `/` 转义** | **一律不转义** | 两处编码器都带 `.withoutEscapingSlashes`（裁定 ⑲ ③） |
| **B6 字段名** | 各自 `CodingKeys`；**content 内部一律不做 snake 化**（`version` / `spans` / `styles` / `…` 原样） | **未改**（裁定 ⑲ ①；行级 12 项映射表属契约 §6.4.1.1，本片不碰） |
| **null** | 只在**行级** `deleted_at`（可选字段 `nil` = 键缺失） | 未改（裁定 ⑲ ③） |

### 8.3 判据读数（**改前 / 改后 成对** · 跨进程 · 可复跑）

复现（探针源逐字节见 §8.6；**只落 `.build/`，不入库**）：

```bash
WORKTREE=/Users/alex/dev/doyah/lead/studio/.worktrees/t_fc43a8c2
"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -O \
  -sdk "$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" \
  "$WORKTREE/Core/NoteBody.swift" "$WORKTREE/Core/Localization.swift" \
  "$WORKTREE/Core/Note.swift" "$WORKTREE/Core/DoyahIdentity.swift" \
  "$WORKTREE/Core/Notebook.swift" "$WORKTREE/.build/canon-probe/main.swift" \
  -o "$WORKTREE/.build/canon-probe/probe"
"$WORKTREE/.build/canon-probe/probe"     # ← 跑**两遍**（跨进程稳定性在这两遍之间判）
```

**判据 ①（同进程两次编码同一内容 ⇒ 两串 `sha256` 相同）**

| 面 | 改前（默认 `JSONEncoder()`） | 改后（canonical） |
|---|---|---|
| RUN A | `d1`=3897e917… · `d2`=311349ae… ⇒ **不同** | `c1` == `c2` = `c49b9045…` ⇒ **相同** ✅ |
| RUN B | `d1`=89ac015d… · `d2`=e202338c… ⇒ **不同** | `c1` == `c2` = `c49b9045…` ⇒ **相同** ✅ |

**判据 ②（跨进程各跑一次 ⇒ 四次 `sha` 全同）**

| 面 | 字节数 | `sha256`（RUN A / RUN B） |
|---|---|---|
| 改前（默认） | 611 | `3897e917…` / `311349ae…` / `89ac015d…` / `e202338c…` ⇒ **四个全不同** |
| **改后（canonical）** | **608** | **`c49b90457cdc8e530928134ce6e4549d061f26ae30f77573dfd8a235cf47d7c9`（四次全同）** ✅ |

> 608 vs 611 = `.withoutEscapingSlashes` 少掉的三颗反斜杠（`https:\/\/example.com\/a` → `https://example.com/a`）。
> 与 `云E` §1.3 的 `.sortedKeys` 面（611 B / `1819153e…`，**仍转义**）不是同一个口径 —— 本片按裁定 ⑲ ③ 取**不转义**。

**判据 ③（canonical 生效面覆盖 `content` 与元数据）**

| 面 | 读数 | 判定 |
|---|---|---|
| `content`（`note.spans` 列 / 上行 `content`） | `c1 == c2`（608 B）· 跨进程同一 `sha256` | ✅ 生效 |
| 元数据（`title` / `tags` / 时间，`NoteStore.save` 的落库面） | `m1 == m2`（519 B · `dc712851ab1f74f414afade11aab8a62e303782284a0a50d05bab0b99ea69f43`）· 跨进程同一 `sha256` | ✅ 生效 |
| 云端行（`CloudSyncCoding.encoder()`） | 与 #1 #2 **同一套两条 flag**（`.sortedKeys` + `.withoutEscapingSlashes`）+ ISO8601 写入口径 | ✅ 同源 |

**canonical 原文（608 B · 逐字节，键序即字典序）**

```
{"spans":[{"text":"普通文字 "},{"styles":["bold"],"text":"粗体"},{"styles":["italic"],"text":"斜体"},{"styles":["underline"],"text":"下划线"},{"styles":["code"],"text":"代码"},{"color":"#E53935","styles":["color"],"text":"红字"},{"size":18,"styles":["size"],"text":"大字"},{"link":"https://example.com/a","text":"链接"},{"backgroundColor":"#FFF3B0","text":"荧光"},{"text":"第一条","type":"LIST_ORDERED"},{"text":"圆点","type":"LIST_UNORDERED"},{"checked":true,"text":"带勾任务","type":"LIST_CHECKBOX"},{"checked":false,"text":"未勾任务","type":"LIST_CHECKBOX"}],"version":2}
```

### 8.4 `bash Scripts/verify-core.sh` 读数

见 §8.7（收口重跑 · 与改前成对）。

### 8.5 边界自查

未碰 `Docs/**`（只引用契约与裁定）· 未碰 `Scripts/**`（判据本体零改动）· **零新增 `.swift`**（5 个 `.swift` 全 `M`）·
未装全局包 · 未提交任何 secret / 口令 / 令牌 · 只**本地 `git commit`**（未 `push` / 未 `fetch` / 未 `rebase`）·
未碰对侧子树 · `Scripts/path-ownership.json` 未改（`cloud-sync/` 与 `Core/NoteSync/` 已在既有登记内）。

### 8.6 探针源（逐字节 · 可原样重放 · 只落 `.build/`）

```swift
import Foundation
import CryptoKit

// 《写入面 canonical 编码 · 跨进程字节稳定》取证探针（片 `云-编码canonical` · macOS 机组）
//
// 用法（在出片工作树里跑；探针源只住在 `.build/` 下，**不改产品代码**）：
//   WORKTREE=/Users/alex/dev/doyah/lead/studio/.worktrees/t_fc43a8c2
//   mkdir -p "$WORKTREE/.build/canon-probe"
//   cp <本源> "$WORKTREE/.build/canon-probe/main.swift"
//   swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
//     "$WORKTREE/Core/NoteBody.swift" "$WORKTREE/Core/Localization.swift" \
//     "$WORKTREE/Core/Note.swift" "$WORKTREE/Core/DoyahIdentity.swift" \
//     "$WORKTREE/Core/Notebook.swift" "$WORKTREE/.build/canon-probe/main.swift" \
//     -o "$WORKTREE/.build/canon-probe/probe"
//   "$WORKTREE/.build/canon-probe/probe"    # 跑两遍（跨进程稳定性就在这两遍之间判）
//
// 「改后」那一条取的编码器 = `NoteBodyCanonical`（Core/NoteBody.swift）—— 与写入口
// `App/AppState.swift` 的 `encodedSpans` **同一条**（不是照抄一份配置）。
// 样例 span 树与 `云E`（本文件 §一.1）逐条相同，便于两片读数对齐。

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

let spans: [NoteSpan] = [
    NoteSpan(text: "普通文字 "),
    NoteSpan(text: "粗体", styles: [.bold]),
    NoteSpan(text: "斜体", styles: [.italic]),
    NoteSpan(text: "下划线", styles: [.underline]),
    NoteSpan(text: "代码", styles: [.code]),
    NoteSpan(text: "红字", styles: [.color], color: "#E53935"),
    NoteSpan(text: "大字", styles: [.size], size: 18),
    NoteSpan(text: "链接", link: "https://example.com/a"),
    NoteSpan(text: "荧光", backgroundColor: NoteHighlight.backgroundColorHex),
    NoteSpan(text: "第一条", block: .ordered),
    NoteSpan(text: "圆点", block: .bullet),
    NoteSpan(text: "带勾任务", block: .task(checked: true)),
    NoteSpan(text: "未勾任务", block: .task(checked: false))
]
let body = NoteBody(spans: spans)

print("=== ① 改前：默认 `JSONEncoder()`（`云E` §三.5 登记的根因）===")
let d1 = try JSONEncoder().encode(body)
let d2 = try JSONEncoder().encode(body)
print("d1 字节数 = \(d1.count)  sha256 = \(sha256Hex(d1))")
print("d2 字节数 = \(d2.count)  sha256 = \(sha256Hex(d2))")
print("d1 == d2 逐字节: \(d1 == d2)")

print("")
print("=== ② 改后：canonical（`NoteBodyCanonical` = 写入口 `AppState.encodedSpans` 的同一条）===")
let c1 = try NoteBodyCanonical.encoder().encode(body)
let c2 = try NoteBodyCanonical.encoder().encode(body)
print("c1 字节数 = \(c1.count)  sha256 = \(sha256Hex(c1))")
print("c2 字节数 = \(c2.count)  sha256 = \(sha256Hex(c2))")
print("c1 == c2 逐字节: \(c1 == c2)")
print("c1 原文 = \(String(decoding: c1, as: UTF8.self))")
print("写入口同一条（`NoteBodyCanonical.json`）：\(try NoteBodyCanonical.json(body) == String(decoding: c1, as: UTF8.self))")

print("")
print("=== ③ 元数据面：`Note` 按 `NoteStore.save` 同一配置（[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] + .iso8601）===")
let when = Date(timeIntervalSince1970: 1_790_000_000)
let note = Note(
    id: UUID(uuidString: "8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48")!,
    title: "同步格式样例",
    body: body.body,
    tags: ["同步", "格式"],
    source: NoteSource(kind: .manual, capturedAt: when),
    createdAt: when,
    updatedAt: when,
    isFavorite: true,
    isPinned: true
)
func metadataEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}
let m1 = try metadataEncoder().encode(note)
let m2 = try metadataEncoder().encode(note)
print("m1 字节数 = \(m1.count)  sha256 = \(sha256Hex(m1))")
print("m2 字节数 = \(m2.count)  sha256 = \(sha256Hex(m2))")
print("m1 == m2 逐字节: \(m1 == m2)")
```

### 8.7 收口重跑读数（判据 ④）

```
$ cd /Users/alex/dev/doyah/lead/studio/.worktrees/t_fc43a8c2
$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/verify-core.sh
ℹ️ 工具链证据: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer · Xcode 27.0 Build version 27A266a
...
	 Executed 2915 tests, with 3 tests skipped and 0 failures (0 unexpected) in 6.069 (6.233) seconds
ℹ️ Core 单测 2915 项（已写入 .build/core-test-count.txt，供 Scripts/check-doc-numbers.py 对账）
VERIFY_CORE_EXIT=0
```

| 项 | 读数 |
|---|---|
| 收口重跑 | **exit 0** · **2915 项 · 0 failures**（3 项 skip 为既有：`云D` 的 LIVE 真跑 + UI 快照那几条） |
| 新增 2 例在跑 | `NoteBodyTests.testCanonicalSerializationKeepsContentAndMetadataByteStable` passed · `NoteSyncE2ETests.testTimestampWriteReadFollowsCanonicalMillisecondRule` passed |
| 计数推导 | `2906`（本片基线 `e0b9d59` 合入 云F-缺口）+ `7`（父卡 云D 的 `NoteSyncE2E` 新例）+ `2`（本片）**= 2915** |
| 唯一允许红 | `check-doc-numbers` 的 `[core-tests]`（台账 2832，实测 2915）—— **陈旧红**，归前门 `T-20261009-040`；本片未碰 `Docs/**` 与台账 |
