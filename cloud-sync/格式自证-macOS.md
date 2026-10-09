# 云E · 互验前置《格式自证》（**macOS 侧**）· 派单 `T-20261009-120`

| 项 | 内容 |
|---|---|
| 片号 / 片名 | `云E` ｜ 互验前置 · 《格式自证》（`content` JSON 原文 + 元数据字段对照 + 序列化往返读数） |
| 目标仓 | **DoyahStudio**（一仓一片） |
| 交付面（文件级） | `cloud-sync/格式自证-macOS.md`（**新增 · 本片唯一新文件**） |
| 归属 dev | `macos-dev`（macOS 机组） |
| 判据读数 | 见 §五（逐条成对留档） |
| **停手线** | **命中第 ② 条**：往返读数 **不一致 2 处**（§三.4），根因 = 写入口的默认 `JSONEncoder` **键序不保序**，修点在**产品代码**、不在本片可改范围 ⇒ 本片**只出证据、只报口径缺口**，**未自改产品代码 / 未自改契约**；已在卡上 comment + 标 `needs_input` |
| 本片改动 | 只新增本文件一个；**零产品代码改动**（探针源只住在 `.build/` 下，不入库） |

---

## 〇 口径与来源（先钉清楚「本侧真序列化」是哪一条调用）

- **契约**：`DoyahNotes fefb09a` · SRS **v3.88** §6.4「互验前置 · 格式自证」行（`Docs/需求规范书.md:831`）+ §6.4.1（`notes` 表列）/ §6.4.2（`IR-15`~`IR-22`）；
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

### 3.3 读数表

| 面 | 读数 | 与判据 3 的期望（三段逐字节一致 / 不一致 0 处） |
|---|---|---|
| **字节面**（默认编码器 = 写入口那一条） | `seg1≠seg2`、`seg1≠seg3` ⇒ **不一致 2 处**；且 RUN A 的 `seg1`(285b25f4…) 与 RUN B 的 `seg1`(c14d62f1…) **不同**，重复编码的三次读数也随进程而变 | ❌ **不成立** |
| **语义面**（解码回来的 span 树 / JSON 对象） | `back1.spans == spans` ✅、`back2.spans == spans` ✅、13/13/13 条**逐字段全一致**、`version` 2↔2 | ✅ 不一致 **0 处** |
| **`.sortedKeys` 面**（键序固定） | `canon1 == canon2` ✅，RUN A / RUN B 同一个 `sha256`（1819153e…），同进程三次重复亦逐字节相同 | ✅ 不一致 **0 处** |

### 3.4 结论与根因（**本片只报，不自改**）

- 本侧**内容语义往返是干净的**（字段级 0 处不一致，未知键也留得住 —— 既有单测 `Tests/NoteBodyTests.swift` 的 `testSpansRoundTripThroughJSON` / `testBlockSpansRoundTripThroughJSON` / `testUnknownSpanFieldsSurviveRoundTrip` 是同一结论的独立证据）。
- **但字节面不是稳定的**：写入口用的是**默认 `JSONEncoder()`**，其键序不保证保序 —— 实测同一份内容（a）**跨进程**给出不同字节，（b）**同进程首次编码与前几次也未必相同**（`RUN A`：首编码 `285b25f4…`，其后 `7a1030d2…`；`RUN B`：`c14d62f1…` / `a1f4d1c6…`）。⇒ `content` JSON **不能**作「逐字节一致」的载体。
- 这与契约 §6.4「跨端互验」那一行明文的判据 **直接相抵**：其①要求「macOS 写 → 安卓读（含富文本正文 / 标签 / 笔记本归属，**正文 JSON 逐字节一致**）」。
- **修点在产品代码**（`App/AppState.swift:6916` 的编码调用加 `.sortedKeys`，实测即可字节稳定；`/` 是否转义、`Date` 用哪种表示也需一并定），**不在本片可改范围** ⇒ 按派单**停手线第 ② 条**处理：本片出证据 + 报口径缺口 + 标 `needs_input`，**未自改产品代码、未自改契约**。

---

## 四 与契约口径的差异清单（一律**报前门**，本片不自解）

| # | 差异 | 位置 | 影响 |
|---|---|---|---|
| 1 | `content` JSON **键序不保序** ⇒ 字节不稳定 | §三.4 | **挡着 §6.4「正文 JSON 逐字节一致」这一条判据** |
| 2 | 行内面交换形态与 §2.4 不同形（`text` vs `content`；`styles` 数组 vs 对象；`color`/`size`/`backgroundColor` 平铺 vs 收在 `styles` 内） | §1.4 | 跨端读到对方的正文会**解不出样式**（块级 `type` 面已同形） |
| 3 | `version`：本侧 `NoteBody.version = 2`；§2.4 写「当前 1」 | §1.4 | 版本轴不同 ⇒ 需裁「同一根版本轴还是各自版本轴」 |
| 4 | 时间表示三种并存：库 REAL（Unix 秒）/ 默认 JSON（Apple 参考日秒）/ `.iso8601` 字符串；契约 §2.1 写「毫秒时间戳」 | §二 | `updated_at` / `deleted_at` 跨端比大小、比相等会错 |
| 5 | `uid` / `rev` / `deleted_at` 本侧**只有同步面**（`SyncRecord`）；本地 `note` 表无 `rev` / `deleted_at` 列，笔记身份列名是 `uuid`（不是 `uid`） | §二 | 本地 → 上行的装配点本侧尚未存在（云D 片） |
| 6 | 契约 §2.4 的 `meta`（附件地基）本侧**无此键** | §1.4 | 附件单列（`IR-19/20` 不在本片），登记待办即可 |
| 7 | `content_type`：本侧无该字段（契约 §6.4.1 `notes.content_type` / §2.1 `contentType` 恒为文本） | §二 | 上行时需装配（或前门裁定留空） |
| 8 | 可选值 `nil` 的表示：本侧 Swift 合成 Codable 是**键缺失**（非 `null`） | §二（`deletedAt`） | 「缺键」与「null」是否等价，需前门一句话（本侧现状：缺键） |
| 9 | 一整行 `notes`（8 字段同体 + `content`）在本侧**尚无装配点**：`Note`（本地）/ `SyncRecord`（同步面）两个类型目前各管一半 | §二 | 互验前需云D 落装配（本片只是把两侧现状固化成读数） |

---

## 五 判据读数（逐条成对留档）

1. **目录**：`ls cloud-sync/` 改前 ⇒ `ls: cloud-sync/: No such file or directory`（退出码 1，改前**不存在**）；改后 ⇒ 本文件在盘（新增 1 个文件）。
2. **三段结构在位**：§一（`content` JSON 原文，`json` 块逐字节贴出）· §二（八字段对照表：字段 / 取值样例 / 类型 / 空值·缺省表示 四列齐）· §三（进 → 出 → 再进，逐字段标「一致 / 不一致：哪一项」）。
3. **往返读数可复现**：命令与探针源见 §3.1 / §附；打印原文见 §3.2。读数 = **字节面不一致 2 处**、语义面不一致 0 处、`.sortedKeys` 面不一致 0 处（⇒ 命中停手线第 ② 条，见 §三.4）。
4. **`bash Scripts/verify-core.sh`** ⇒ 读数见 §5.1（本片**零产品代码改动**，应与改前**同读数**）。
5. **边界自查**：未碰 `Docs/**`（本文只引用契约）· **零 `tcb` 写操作** · 未装全局包 · 未提交任何 secret / key / token / 口令（本文与探针里没有任何凭据；样例值全是本地造的字面量）· 只本地 `git commit`，**未 push / 未 fetch / 未 rebase** · 只新增 `cloud-sync/格式自证-macOS.md` 一个文件。

### 5.1 `verify-core.sh` 读数

```
$ cd /Users/alex/dev/doyah/lead/studio/.worktrees/t_571c7e65
$ bash Scripts/verify-core.sh
ℹ️ 工具链证据: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer · Xcode 27.0 Build version 27A266a
（SwiftPM 依赖解析：抓取 swift-nio / swift-crypto / … 期间出现过 2 次 `error: RPC failed; curl 18 Transferred a partial file` 的重试 —— **随即重连成功**，解析完成，不影响下面的读数）
...
	 Executed 2871 tests, with 2 tests skipped and 0 failures (0 unexpected) in 5.743 (5.918) seconds
ℹ️ Core 单测 2871 项（已写入 .build/core-test-count.txt，供 Scripts/check-doc-numbers.py 对账）
EXIT=0
```

| 项 | 读数 |
|---|---|
| 退出码 | **0** |
| 单测 | **2871 项 · 0 failures**（2 项 skip 为既有） |
| 改前 / 改后 | **同读数**（本片**零产品代码改动**，只新增本文件；与基线 `de642b0` 一致 —— 云B 的交付记录里那条基线读数也是 2871） |
| 唯一允许红 | `Scripts/check-doc-numbers.py` 的 `[core-tests]` **实测 2871 vs 台账 2832** —— 台账陈旧红，归前门 `T-20261009-040`；本片**未碰** `Docs/**` 与台账（`verify-core.sh` 本身不跑该判据，此处照实登记） |
| 日志落点 | `.build/core-test.log`（同一次运行的原始日志） |

---

## 六 机器面

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
