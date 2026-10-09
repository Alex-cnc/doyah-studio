import Foundation

// 笔记存储层（`FR-PLUG-08` / Q23 拍板：桌面各端笔记存储统一到本地 SQLite）。
//
// 这一层坐在 `SQLiteKit`（C 绑定）之上，做三件事：
//   ① **schema v1 与升级**：版本号写进 `PRAGMA user_version`，打开即幂等升到最新版；
//   ② **笔记 ↔ 表的映射**：`note` / `note_tag` / `note_timeline` / `note_attachment` + `note_fts`（FTS5）；
//   ③ **快照备份**：`VACUUM INTO` 出一份**自洽的副本**（不是把活跃库文件拷走 —— 那在 WAL 下会拿到半份数据）。
//
// 三条口径值得写在前面（都是别处踩过的坑）：
//   · **时间存 REAL 秒**（`Date.timeIntervalSince1970`），不存 ISO8601 字符串。字符串排序是字典序、
//     跨时区还要解析；而 `ORDER BY updated_at DESC` 这种排序是数值语义。JSON 里的 ISO8601 是**旧格式**，
//     由迁移器换算一次（见 `NoteLibraryMigration`）。
//   · **NULL 与空串不是一回事**：`source_connection_name` 为 NULL 表示「这条笔记没有连接来源」，
//     空串表示「有来源、但名字是空的」。取值一律走 `SQLiteValue`，不做 Swift 类型推断。
//   · **不认识的枚举值不许降级**：`source_kind` 存 TEXT；读到表里没有的 kind 时**抛错**，
//     不默默当成 `.manual`（静默降级会让「这条是怎么来的」永久失真）。
//
// 全文检索（FTS5）的口径来自第 18 轮实测：默认分词器 `unicode61` **不切中文**
// （`MATCH '骑行'` 命中 0），所以 `note_fts` 用 `tokenize='trigram'`；而 trigram **要求查询串 ≥3 字**
// （`'洞庭湖'` 命中、2 字的 `'骑行'` 不命中）。因此 `search(_:)` 对 1~2 字的查询**走 LIKE 兜底**并
// 在返回值里如实标注走了哪条路 —— 「检索不到」与「分词器不切中文」是两件事，不能让用户面对前者。

/// 笔记库的 schema **v1**（`FR-PLUG-08`）。
///
/// DDL 写成一份**有序的语句清单**而不是一坨字符串：迁移器按顺序执行、门禁（与单测）按名单核对
/// 「说要建的表 / 索引 / 触发器，库里是不是真有」——「我以为建过了」是这类代码最贵的缺陷。
public enum NoteSchemaV1 {

    /// 版本号（写进 `PRAGMA user_version`，随事务原子生效）。
    public static let version: Int32 = 1

    /// 表与虚拟表（含 FTS5 的 `note_fts`）。
    public static let tables: [String] = ["note", "note_tag", "note_timeline", "note_attachment", "note_fts"]

    /// 触发器：`note_fts` 与 `note` **结构性同步**（不给「忘了更新索引」留窗口）。
    public static let triggers: [String] = [
        "note_fts_after_insert",
        "note_fts_after_delete",
        "note_fts_after_update"
    ]

    /// 索引（把「按条件查」要用的列先备好：更新时间倒序 / 标签 / 时间线 / 附件）。
    public static let indexes: [String] = [
        "note_updated_at_index",
        "note_source_kind_index",
        "note_tag_tag_index",
        "note_timeline_note_index",
        "note_attachment_note_index"
    ]

    /// 建库语句（顺序即依赖顺序：`note` 先，触发器最后）。
    public static let ddl: [String] = [
        """
        CREATE TABLE note (
            id INTEGER PRIMARY KEY,
            uuid TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            body TEXT NOT NULL DEFAULT '',
            source_kind TEXT NOT NULL,
            source_connection_name TEXT,
            source_fingerprint TEXT,
            source_captured_at REAL NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            contains_row_data INTEGER NOT NULL DEFAULT 0 CHECK (contains_row_data IN (0, 1)),
            storage_version INTEGER NOT NULL DEFAULT 1
        );
        """,
        "CREATE INDEX note_updated_at_index ON note (updated_at DESC);",
        "CREATE INDEX note_source_kind_index ON note (source_kind);",
        """
        CREATE TABLE note_tag (
            note_id INTEGER NOT NULL REFERENCES note (id) ON DELETE CASCADE,
            tag TEXT NOT NULL,
            PRIMARY KEY (note_id, tag)
        );
        """,
        "CREATE INDEX note_tag_tag_index ON note_tag (tag);",
        """
        CREATE TABLE note_timeline (
            id INTEGER PRIMARY KEY,
            note_id INTEGER NOT NULL REFERENCES note (id) ON DELETE CASCADE,
            at REAL NOT NULL,
            kind TEXT NOT NULL,
            detail TEXT
        );
        """,
        "CREATE INDEX note_timeline_note_index ON note_timeline (note_id, at);",
        """
        CREATE TABLE note_attachment (
            id INTEGER PRIMARY KEY,
            uuid TEXT NOT NULL UNIQUE,
            note_id INTEGER NOT NULL REFERENCES note (id) ON DELETE CASCADE,
            path TEXT NOT NULL,
            byte_count INTEGER,
            added_at REAL NOT NULL
        );
        """,
        "CREATE INDEX note_attachment_note_index ON note_attachment (note_id);",
        // FTS5 外部内容表：正文存在 `note` 里，索引只存倒排表（省一份正文拷贝），
        // 同步由触发器负责。`tokenize='trigram'` 是中文能检索的前提（见文件头）。
        """
        CREATE VIRTUAL TABLE note_fts USING fts5 (
            title,
            body,
            content = 'note',
            content_rowid = 'id',
            tokenize = 'trigram'
        );
        """,
        """
        CREATE TRIGGER note_fts_after_insert AFTER INSERT ON note BEGIN
            INSERT INTO note_fts (rowid, title, body) VALUES (new.id, new.title, new.body);
        END;
        """,
        // 外部内容表的删除必须把**旧值**喂给 FTS5（这是官方口径，不是可省的一步）。
        """
        CREATE TRIGGER note_fts_after_delete AFTER DELETE ON note BEGIN
            INSERT INTO note_fts (note_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
        END;
        """,
        """
        CREATE TRIGGER note_fts_after_update AFTER UPDATE ON note BEGIN
            INSERT INTO note_fts (note_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
            INSERT INTO note_fts (rowid, title, body) VALUES (new.id, new.title, new.body);
        END;
        """
    ]
}

/// 笔记库的 schema **v2**（队列 `L-97` 第二片）：**两层归属落库**（笔记本架 / 笔记本）。
///
/// 契约出处：`DoyahNotes/Docs/核心契约.md` **§2.12 两层归属**（`shelf` / `notebook` 实体 +
/// `Inspiration.notebookUid` 非空）。本侧只引用不复制 —— 表名 / 列名与契约同形。
///
/// 三条口径写在前面（都是这一片真正的取舍）：
///   · **`note.notebook_uid` 刻意不加外键**：加了 `ON DELETE CASCADE` 之后「删一个笔记本」会**静默删掉**
///     里面的笔记，而契约 §2.12 要求删容器时二选一（一并删 / **移到默认笔记本**，默认取后者）。
///     归属策略归 `NotebookDirectory`（Core 半）算，库这一层只存值。
///   · **列可空**：v1 的存量笔记没有归属 ⇒ 补列这一句只能加可空列。而「没有无归属笔记」这条不变量
///     由**写入与迁移**保证（`upsert(_ note:)` 落默认笔记本、`ensureDefaultContainers` 兜底回填），
///     不由 `NOT NULL` 保证 —— 那会让 `ALTER TABLE` 在存量库上直接失败。
///   · **改列不动数据**：`upsert(_ note:)` 的 `ON CONFLICT DO UPDATE` **不含 `notebook_uid`** ——
///     否则「改几个字再保存」会把这条笔记的归属抹回默认（静默的数据损坏）。
public enum NoteSchemaV2 {

    public static let version: Int32 = 2

    /// 新增的表。
    public static let tables: [String] = ["shelf", "notebook"]

    /// 新增的索引。
    public static let indexes: [String] = ["notebook_shelf_index", "note_notebook_index"]

    /// 升级语句（顺序即依赖顺序：`shelf` 先于 `notebook`，补列在两张表之后）。
    public static let ddl: [String] = [
        """
        CREATE TABLE shelf (
            id INTEGER PRIMARY KEY,
            uid TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1))
        );
        """,
        """
        CREATE TABLE notebook (
            id INTEGER PRIMARY KEY,
            uid TEXT NOT NULL UNIQUE,
            shelf_uid TEXT NOT NULL REFERENCES shelf (uid) ON DELETE CASCADE,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1))
        );
        """,
        "CREATE INDEX notebook_shelf_index ON notebook (shelf_uid, sort_order);",
        // 存量笔记补列：v1 的笔记一开始没有归属 ⇒ 可空列（回填见 `ensureDefaultContainers`）。
        "ALTER TABLE note ADD COLUMN notebook_uid TEXT;",
        "CREATE INDEX note_notebook_index ON note (notebook_uid);"
    ]
}

/// **schema v3**（队列 `L-184` 第三片）：给 `note` 补一列 **`favorite`** —— 收藏。
///
/// 为什么是「补列」而不是「新表」：收藏是笔记自己的一个布尔状态（契约 §2.1 `favorite`），
/// 不是另一件东西；判据与列表都要按它筛 / 按它排。**没有新表、没有新索引** —— 收藏量级与笔记同级，
/// 单独建索引在这个规模上只是多一处要维护的东西。
/// 为什么默认 `0` 且 `NOT NULL`：`ADD COLUMN` 要能在一张已有几百行的表上当场成立 ——
/// 没有默认值的老列在 SQLite 上必须可空，而「可空」会把「没收藏」与「不知道」混成一件事。
/// 存量笔记的语义本来就是「没收藏」⇒ 默认 `0` 是**如实**的，不是填充。
public enum NoteSchemaV3 {

    public static let version: Int32 = 3

    /// 这一版**不新增表 / 不新增索引**（只补一列）。
    public static let tables: [String] = []
    public static let indexes: [String] = []

    public static let ddl: [String] = [
        "ALTER TABLE note ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1));"
    ]
}

/// **schema v4**（队列 `L-184` 第四片）：给 `note` 补一列 **`pinned`** —— 置顶。
///
/// 与 v3 的 `favorite` 是同一形态、同一理由（契约 §2.1 `pinned`「排序第一关键字」）：
/// 它是笔记自己的一个布尔状态，不是另一件东西 ⇒ **补列、不新表、不新索引**。
/// 默认 `0` + `NOT NULL`：`ADD COLUMN` 要能在一张已有几百行的表上当场成立，而存量笔记的语义
/// 本来就是「没置顶」⇒ 默认值是**如实**的，不是填充（同 v3 那一条）。
public enum NoteSchemaV4 {

    public static let version: Int32 = 4

    /// 这一版**不新增表 / 不新增索引**（只补一列）。
    public static let tables: [String] = []
    public static let indexes: [String] = []

    public static let ddl: [String] = [
        "ALTER TABLE note ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1));"
    ]
}

/// **schema v5**（队列 `N-11` 的 **macOS 核心层半**）：新增 **`todo`**（待办任务）与
/// **`todo_tag`** 两张表。
///
/// 契约出处：`DoyahNotes/Docs/核心契约.md` 的 `Todo` 实体（提案 `0004` **已采纳裁决**；
/// 需求条文 `FR-NOTE-36~39`）。本侧只引用不复制 —— 列名与契约字段同义（`dueAt` → `due_at`）。
///
/// 四条取舍：
///   · **`todo` 与 `note` 同库同库文件**（`notes.sqlite3`）：契约 `FR-NOTE-39` 的硬约束是
///     「清单是**唯一事实源**、日历只是视图」，而「同一次事务」只有**同一个连接**才做得到
///     （跨库/跨文件就没有事务了）⇒ **不新开库**，只升 schema。
///   · **`todo_tag` 与 `note_tag` 同形**（主键 `(todo_id, tag)` + `ON DELETE CASCADE`）：
///     标签是任务的**多值属性**，不是另一件东西；删一条任务时它的标签必须跟着走。
///   · **`priority` 存串、默认 `'normal'`、不加 `CHECK`**：取值「只增不改」且**认不出的当没给**
///     （见 `TodoPriority`）—— 加 `CHECK` 等于让「别端多一档」变成写入失败，与那条口径相抵。
///   · **`due_at` / `completed_at` 可空** = 语义本身（无截止 / 没完成过），不是「不知道」；
///     而 `done` **`NOT NULL` + 默认 0**（同 v3 的 `favorite`：存量语义就是「没完成」）。
public enum NoteSchemaV5 {

    public static let version: Int32 = 5

    /// 新增的表。
    public static let tables: [String] = ["todo", "todo_tag"]

    /// 新增的索引（只有标签那一张：`todo` 的量级与笔记同级，按截止时间排的索引在这一档规模上
    /// 只是多一处要维护的东西 —— 与 v3 / v4「补列不建索引」同一条理由）。
    public static let indexes: [String] = ["todo_tag_tag_index"]

    /// 升级语句（顺序即依赖顺序：`todo` 先于 `todo_tag`）。
    public static let ddl: [String] = [
        """
        CREATE TABLE todo (
            id INTEGER PRIMARY KEY,
            uuid TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL DEFAULT '',
            due_at REAL,
            done INTEGER NOT NULL DEFAULT 0 CHECK (done IN (0, 1)),
            completed_at REAL,
            priority TEXT NOT NULL DEFAULT 'normal',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """,
        """
        CREATE TABLE todo_tag (
            todo_id INTEGER NOT NULL REFERENCES todo (id) ON DELETE CASCADE,
            tag TEXT NOT NULL,
            PRIMARY KEY (todo_id, tag)
        );
        """,
        "CREATE INDEX todo_tag_tag_index ON todo_tag (tag);"
    ]
}

/// **schema v6**（队列 `L-100` 落法 ④ 的**存储半**）：新增 **`reminder`**（提醒）一张表。
///
/// 契约出处：`DoyahNotes/Docs/核心契约.md` **§2.10 提醒规则与到点**（`ReminderSpec` 的字段
/// 就是本表的规格列）+ **§3.12 调度语义**（`Core/Reminder.swift`，第 188 轮已落）。
/// 本侧只引用不复制 —— 列名与契约字段同义（`anchorDate` → `anchor_date`）。
///
/// 五条取舍：
///   · **与笔记 / 任务同库同连接**（`notes.sqlite3`）：「一条任务与它的提醒」要是**同一次事务**，
///     而事务只有同一个连接才做得到（与 `NoteSchemaV5` 把 `todo` 放同一个库同一条理由）。
///   · **归属二选一**（`note_id` / `todo_id`，`CHECK` 保证恰有一个非空）：契约 §2.10 目前只把
///     提醒描述成挂在笔记上的规则；「可否挂待办」的条文归契约所有者（对侧提案 `0011` 在办）
///     ⇒ 本侧按与对侧**同一份默认口径**落，**裁决若不同即改**（改点 = 这条 `CHECK` + 映射一处）。
///   · **两个归属列都带 `ON DELETE CASCADE`**：人工测试清单（macOS 半 · Alpha 3）**第 7 条**
///     写明「任务真删后它的提醒一并清」⇒ 用**形状**保证（而不是在删除路径上记得多写一句）：
///     孤儿提醒的害处是它到点会弹，而用户在界面上找不到它。
///   · **规格逐列落库**（不是一列 JSON 装下）：这一层要能按「谁的提醒」查（`reminder_note_index` /
///     `reminder_todo_index`），而契约 §2.10 的规格本来就是**具名数据**。
///   · **`weekdays` 存归一后的文本**（`1,3,5`：去重 + 只留 1~7 + 升序）：写与读共用
///     `ReminderSpec.weekdays(from:)` / `weekdaysText`，不让「库里一个顺序、界面另一个顺序」。
///     `interval_unit` 存空串 = 「没给」（缺省 `day` 由调度那一层解释，与 `priority`「认不出当没给」同形）。
public enum NoteSchemaV6 {

    public static let version: Int32 = 6

    /// 新增的表。
    public static let tables: [String] = ["reminder"]

    /// 新增的索引（两个归属列各一：查「这条任务的提醒」是这一层的唯一新查询面）。
    public static let indexes: [String] = ["reminder_note_index", "reminder_todo_index"]

    /// 升级语句（顺序即依赖顺序：表先于索引）。
    public static let ddl: [String] = [
        """
        CREATE TABLE reminder (
            id INTEGER PRIMARY KEY,
            uuid TEXT NOT NULL UNIQUE,
            note_id INTEGER REFERENCES note (id) ON DELETE CASCADE,
            todo_id INTEGER REFERENCES todo (id) ON DELETE CASCADE,
            rule TEXT NOT NULL DEFAULT '',
            anchor_date TEXT NOT NULL DEFAULT '',
            minute_of_day INTEGER NOT NULL DEFAULT -1,
            interval_count INTEGER NOT NULL DEFAULT 0,
            interval_unit TEXT NOT NULL DEFAULT '',
            weekdays TEXT NOT NULL DEFAULT '',
            until_date TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            CHECK ((note_id IS NULL) <> (todo_id IS NULL))
        );
        """,
        "CREATE INDEX reminder_note_index ON reminder (note_id);",
        "CREATE INDEX reminder_todo_index ON reminder (todo_id);"
    ]
}

/// **schema v7**（队列 `HIST-1` · 契约 `DR-02` 由「内存态」改判为**持久化**）：新增
/// **`query_history`** 一张表 —— 查询历史的落盘。
///
/// 契约出处：`DR-02`（v3.327：「本机数据库 / 本地 only / 上限 500 条或 90 天 / 可清空 + 单条删」）
/// + `FR-EDIT-10`（「历史」页签 = 与工具条时钟菜单**同一份**历史源）。本侧只引用不复制 ——
/// 列名与 `QueryHistory` 字段同义（`connectionID` → `connection_id`）。
///
/// 五条取舍：
///   · **与笔记同库同连接**（`notes.sqlite3`）：一次执行 = **一次写**，不新开第二个 SQLite 文件
///     ——「单一写入口」的前提是「只有一处拿得到连接」（与 v5 把 `todo` 放同库同一条理由）。
///   · **`id TEXT PRIMARY KEY` 存 `QueryHistory.id.uuidString`**：写入走「按 id 覆盖」
///     （`ON CONFLICT`），于是「连续重复执行同一条 SQL 只刷新最新一条」不必再开一条更新写路。
///   · **时间戳 `REAL`（`timeIntervalSince1970`）**：与 `note` / `todo` / `reminder` 三表同一口径。
///   · **上限（500 条 / 90 天）不在库这一层**：库只管存与取，裁剪由 `QueryHistoryStore`
///     **同一处**做（判据要能指着那一处说「先到者为准」，两处各裁一次就会各说各话）。
///   · **与 `SQLArchive` 分工不覆盖**（`DR-02` 明文）：归档 = 用户**主动收藏**、长期保留
///     （磁盘上的 `*.sql` 文件）；这里 = 会话历史、有上限、可清空。两者互不读写对方的存储。
///   · **不建索引**：表自己最多 500 行（上限就写在那句裁剪里），`ORDER BY executed_at DESC`
///     在几百行上是内存排序 —— 与 v3 / v4「补列不建索引」同一条理由（不为规模不成立的问题加东西）。
public enum NoteSchemaV7 {

    public static let version: Int32 = 7

    /// 新增的表。
    public static let tables: [String] = ["query_history"]

    /// 这一版**不新增索引**（理由见上）。
    public static let indexes: [String] = []

    public static let ddl: [String] = [
        """
        CREATE TABLE query_history (
            id TEXT PRIMARY KEY,
            connection_id TEXT NOT NULL DEFAULT '',
            sql TEXT NOT NULL DEFAULT '',
            executed_at REAL NOT NULL,
            duration REAL NOT NULL DEFAULT 0,
            succeeded INTEGER NOT NULL DEFAULT 0 CHECK (succeeded IN (0, 1))
        );
        """
    ]
}

/// **schema v8**（片 `WY-1a` · 派单 `T-20261009-029` / `T-20261008-050`）：给 `note` 补一列
/// **`spans`** —— 笔记正文的**权威源**（span 树的 JSON）。
///
/// 契约出处与口径：片 `WY-1a` 的「`NoteBody` 权威源改 `{version: 2, spans[]}`」——
/// `note` 表新增 `spans` 列（schema +1），`body` 列**降为 spans 的单向投影**
/// （由 `NoteBody.body` 派生 · **不反向回写** · 正文的**单一写入口** = `setNoteSpans`）。
///
/// 四条取舍：
///   · **补列、不新表、不新索引**：正文本来就是 `note` 自己的一个状态（与 v3 `favorite` /
///     v4 `pinned` 同形）；检索（`note_fts`）读的仍是 `body` 投影，不需要给 spans 建索引。
///   · **列可空**：v1 存量笔记还没有 spans ⇒ 补列只能加可空列。「每条都有 spans」这条不变量
///     由**库内一次性迁移**保证（= 片 `WY-2`，**单独出包**），不由 `NOT NULL` 保证 ——
///     那会让 `ALTER TABLE` 在存量库上直接失败（同 v2 的 `notebook_uid`）。
///   · **不在这里回填**：本片**只动 Core 模型 + schema**，不做历史迁移，也不删用户正文
///     （`body` 列一个字节不改）。
///   · **写入口唯一**：只有 `setNoteSpans(_:body:id:)` 一处写 `spans`（并把它的投影写进 `body`）——
///     「改正文」这条路只有一条，且它**不改** `updated_at` 之外的任何列（与 `setFavorite` 同纪律）。
public enum NoteSchemaV8 {

    public static let version: Int32 = 8

    /// 这一版**不新增表 / 不新增索引**（只补一列）。
    public static let tables: [String] = []
    public static let indexes: [String] = []

    public static let ddl: [String] = [
        "ALTER TABLE note ADD COLUMN spans TEXT;"
    ]
}

/// **schema v9**（片 `TD-NOTE` · 派单 `T-20261009-042` ②）：给 `todo` 补一列
/// **`note`** —— 待办的**备注正文**（纯文本）。
///
/// 契约出处：`DoyahNotes/Docs/核心契约.md` §2.13 `Todo` 实体新增 `note` 字段（契约 **v1.28**，
/// 前门 `T-20261009-050` 落笔）—— 本侧只引用不复制，列名与契约字段同义（`note` → `note`）。
///
/// 四条取舍（与 v8 给 `note` 表补 `spans` 同形）：
///   · **补列、不新表、不新索引**：备注是任务自己的一个状态（与 v3 `favorite` / v4 `pinned` 同形）；
///     契约明写**不进搜索索引** ⇒ 不给它建索引，也不进 FTS。
///   · **`NOT NULL DEFAULT ''` 而不是可空**：契约把「空串」定为「没有备注」（与 `title` 同口径），
///     没有「不知道」这个第三态 ⇒ 用**形状**保证读回来永远是 `String`，行映射不必再拆一层可选。
///   · **存量行落默认值**：`ALTER TABLE ADD COLUMN ... DEFAULT ''` 让老行当场就有值（`''` = 空备注）
///     —— 一个字节的用户数据都不改（与 v8 补 `spans` 的 `ALTER` 同一条纪律）。
///   · **不动既有写路**：`upsert(_ todo:)` 是这一列**唯一**的写入口（编辑走的是同一条任务写路，
///     不新开第二处「改备注」的口径）。
public enum NoteSchemaV9 {

    public static let version: Int32 = 9

    /// 这一版**不新增表 / 不新增索引**（只补一列；契约明写备注不进搜索索引）。
    public static let tables: [String] = []
    public static let indexes: [String] = []

    public static let ddl: [String] = [
        "ALTER TABLE todo ADD COLUMN note TEXT NOT NULL DEFAULT '';"
    ]
}

/// 附件索引的一条（`FR-PLUG-08`：**附件二进制留在文件系统，库里只存路径**）。
public struct NoteAttachment: Equatable, Sendable {
    public var id: UUID
    public var path: String
    /// 记录时的字节数（**只是元信息**，不据此校验文件；文件可能已被外部改动）。
    public var byteCount: Int64?
    public var addedAt: Date

    public init(id: UUID = UUID(), path: String, byteCount: Int64? = nil, addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.byteCount = byteCount
        self.addedAt = addedAt
    }
}

/// 时间线的一条（谁在什么时候因为什么动了这条笔记）。
public struct NoteTimelineEntry: Equatable, Sendable {
    public var at: Date
    public var kind: String
    public var detail: String?

    public init(at: Date, kind: String, detail: String? = nil) {
        self.at = at
        self.kind = kind
        self.detail = detail
    }
}

/// 存储层的失败。**机器可读**的出口（界面文案由语言表按类别组织，这一层不产文案）。
public enum NoteStorageFailure: Error, Equatable, CustomStringConvertible {
    /// 表里出现了这一版不认识的 `source_kind` —— 不降级、不猜（见文件头第三条口径）。
    case unknownSourceKind(String)
    /// 库的 schema 版本比这一版代码更新（将来回退 App 版本时会遇到）：**拒绝写入**而不是继续用。
    case unsupportedSchemaVersion(found: Int32, supported: Int32)
    /// 快照目标已存在：**不覆盖**（备份不许把上一次的备份顶掉）。
    case snapshotTargetExists(String)
    /// 快照写出来了，但读回来不对（行数或完整性检查不过）。
    case snapshotMismatch(String)

    public var description: String {
        switch self {
        case .unknownSourceKind(let raw):
            return "unknown note source kind in the database: \(raw)"
        case .unsupportedSchemaVersion(let found, let supported):
            return "database schema version \(found) is newer than supported \(supported)"
        case .snapshotTargetExists(let path):
            return "snapshot target already exists: \(path)"
        case .snapshotMismatch(let reason):
            return "snapshot verification failed: \(reason)"
        }
    }
}

/// 一次快照的结果（`VACUUM INTO`）。
public struct NoteSnapshot: Equatable, Sendable {
    public var url: URL
    public var byteCount: Int64
    /// 快照里的笔记条数（与源库**当场核对过**）。
    public var noteCount: Int
    /// 快照自带的 `PRAGMA user_version`。
    public var schemaVersion: Int32
    /// `PRAGMA integrity_check` 的原话（正常是 `ok`）。
    public var integrity: String

    public init(url: URL, byteCount: Int64, noteCount: Int, schemaVersion: Int32, integrity: String) {
        self.url = url
        self.byteCount = byteCount
        self.noteCount = noteCount
        self.schemaVersion = schemaVersion
        self.integrity = integrity
    }
}

/// 笔记库（SQLite）。
///
/// **线程口径**：连接自身串行化（`SQLiteKit` 内是递归锁 + `FULLMUTEX`），语义上的并发由调用方
/// （`NoteStore` 是 actor）负责。这里不做第二套队列 —— 两层锁解决不了任何问题，只会多一处死锁面。
public final class NoteDatabase {

    /// 库文件名。**与旧格式 `notes.json` 不同名**：迁移要靠「目标不在」判定要不要搬（L-03 的纪律）。
    public static let fileName = "notes.sqlite3"

    /// 这一版代码支持的 schema 版本（v1 → v2 补两层归属、v2 → v3 补收藏、v3 → v4 补置顶、
    /// v4 → v5 补待办任务清单、v5 → v6 补提醒、v6 → v7 补查询历史、v7 → v8 补正文 spans 列、
    /// v8 → v9 补待办备注 `note` 列）。
    public static let supportedVersion = NoteSchemaV9.version

    private let connection: SQLiteConnection

    /// 打开（必要时新建）并**升到最新 schema**。幂等：已经是最新版的库再打开不会动任何数据。
    public init(path: String) throws {
        let connection = try SQLiteConnection(path: path)
        self.connection = connection
        try configure(connection)
        try applySchemaIfNeeded()
    }

    /// 连接参数（每一条都有理由，别省）：
    ///   · `journal_mode = WAL` —— 「并发写 + 多进程读」是 `FR-PLUG-08` 的判据之一；
    ///   · `foreign_keys = ON` —— SQLite 默认**不**开外键；不开的话 `ON DELETE CASCADE` 是装饰品，
    ///     删一条笔记会留下孤儿标签 / 时间线 / 附件行；
    ///   · `synchronous = NORMAL` —— WAL 下的常规档：崩溃不坏库（可能丢最后若干事务，不丢一致性）。
    ///     刻意**不用** `OFF`：笔记库的价值就在「崩溃不坏数据」这条判据上。
    private func configure(_ connection: SQLiteConnection) throws {
        try connection.setPragma("journal_mode = WAL")
        try connection.setPragma("foreign_keys = ON")
        try connection.setPragma("synchronous = NORMAL")
    }

    deinit { try? connection.close() }

    public var path: String { connection.path }

    public func close() throws { try connection.close() }

    // MARK: - schema

    /// 库头里的 `user_version`。
    public var userVersion: Int32 {
        (try? connection.scalarInt("PRAGMA user_version")).flatMap { $0 } .map(Int32.init) ?? 0
    }

    /// 库里的 `journal_mode`（自证 WAL 真的生效，而不是"我以为设了"）。
    public var journalMode: String {
        (try? connection.scalarText("PRAGMA journal_mode")) ?? ""
    }

    /// 外键开关真的开着吗（同上）。
    public var foreignKeysEnabled: Bool {
        (try? connection.scalarInt("PRAGMA foreign_keys")).flatMap { $0 } == 1
    }

    /// 按需建/升级到最新 schema（当前 v9）。**一个事务里做完**：DDL 与版本号一起生效，
    /// 不会出现「表建了一半、版本已记 2」。
    ///
    /// 逐版升级（不是「按最新版直接建」）：存量库要真的走 v1 → v2 这两步，
    /// 判据（与单测）才有机会证明「老库升得上来」—— 一条只在新库上跑通的路是假绿。
    public func applySchemaIfNeeded() throws {
        let current = userVersion
        if current > Self.supportedVersion {
            // 比代码更新的库（用户回退过 App 版本）：**拒绝动它**，让人来处理，而不是拿旧代码去改新库。
            throw NoteStorageFailure.unsupportedSchemaVersion(found: current, supported: Self.supportedVersion)
        }
        guard current < Self.supportedVersion else { return }
        try connection.transaction {
            if current < NoteSchemaV1.version {
                for statement in NoteSchemaV1.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV1.version)")
            }
            if current < NoteSchemaV2.version {
                for statement in NoteSchemaV2.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV2.version)")
            }
            if current < NoteSchemaV3.version {
                for statement in NoteSchemaV3.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV3.version)")
            }
            if current < NoteSchemaV4.version {
                for statement in NoteSchemaV4.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV4.version)")
            }
            if current < NoteSchemaV5.version {
                for statement in NoteSchemaV5.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV5.version)")
            }
            if current < NoteSchemaV6.version {
                for statement in NoteSchemaV6.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV6.version)")
            }
            if current < NoteSchemaV7.version {
                for statement in NoteSchemaV7.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV7.version)")
            }
            if current < NoteSchemaV8.version {
                for statement in NoteSchemaV8.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV8.version)")
            }
            if current < NoteSchemaV9.version {
                for statement in NoteSchemaV9.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV9.version)")
            }
        }
    }

    /// 把库切成「单文件日志」（`journal_mode = DELETE`）：迁移器在**换名之前**用它 —— 换名只搬主库文件，
    /// WAL 的 `-wal` / `-shm` 侧车会留在原地，那样交出去的库会少半份已提交数据。
    /// 交付之后由 `NoteDatabase` 打开时再切回 WAL（开关记在库头，只写一次）。
    func switchToSingleFileJournal() throws {
        try connection.setPragma("journal_mode = DELETE")
    }

    /// 库里实际存在的表 / 虚拟表（门禁与单测按 `NoteSchemaV1.tables` + `NoteSchemaV2.tables` 对账）。
    public func tableNames() throws -> [String] {
        try connection.schemaObjects(kind: "table")
    }

    /// 库里实际存在的触发器。
    public func triggerNames() throws -> [String] {
        try connection.schemaObjects(kind: "trigger")
    }

    /// `PRAGMA integrity_check` 的原话（正常是 `ok`）。
    public func integrityCheck() throws -> String {
        try connection.scalarText("PRAGMA integrity_check") ?? "no result"
    }

    // MARK: - 写

    /// 写入或按 uuid 覆盖一条笔记，返回它的 rowid。
    ///
    /// 一条笔记的三块（本体 + 标签 + 时间线）在**一个事务**里落库：半个笔记（正文进去了、标签没进去）
    /// 是最难查的一类不一致。附件不在这里动 —— 附件是**独立动作**（加附件不该顺带重写正文）。
    @discardableResult
    public func upsert(_ note: Note) throws -> Int64 {
        try connection.transaction {
            try connection.execute(
                """
                INSERT INTO note (
                    uuid, title, body, source_kind, source_connection_name, source_fingerprint,
                    source_captured_at, created_at, updated_at, contains_row_data, storage_version,
                    favorite, pinned
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (uuid) DO UPDATE SET
                    title = excluded.title,
                    body = excluded.body,
                    source_kind = excluded.source_kind,
                    source_connection_name = excluded.source_connection_name,
                    source_fingerprint = excluded.source_fingerprint,
                    source_captured_at = excluded.source_captured_at,
                    updated_at = excluded.updated_at,
                    contains_row_data = excluded.contains_row_data,
                    storage_version = excluded.storage_version;
                """,
                [
                    .text(note.id.uuidString),
                    .text(note.title),
                    .text(note.body),
                    .text(note.source.kind.rawValue),
                    note.source.connectionName.map { SQLiteValue.text($0) } ?? .null,
                    note.source.fingerprint.map { SQLiteValue.text($0) } ?? .null,
                    .real(note.source.capturedAt.timeIntervalSince1970),
                    .real(note.createdAt.timeIntervalSince1970),
                    .real(note.updatedAt.timeIntervalSince1970),
                    .integer(note.containsRowData ? 1 : 0),
                    .integer(Int64(NoteSchemaV1.version)),
                    // **`favorite` 只在这一句的 INSERT 分支里出现**（`ON CONFLICT` 段刻意不含它）：
                    // 与 `notebook_uid` 同一条教训 —— 否则「打开一条收藏过的笔记、改几个字、保存」
                    // 会把它**静默取消收藏**。改收藏只有 `setFavorite` 一条路。
                    .integer(note.isFavorite ? 1 : 0),
                    // **`pinned` 同理**：只在 INSERT 分支出现，`ON CONFLICT` 段绝不含它 ——
                    // 「打开一条置顶过的笔记、改几个字、保存」不许把它静默取消置顶（改置顶只有 `setPinned`）。
                    .integer(note.isPinned ? 1 : 0)
                ]
            )
            // **按 uuid 反查 rowid**，而不是读 `last_insert_rowid()`：走的是 upsert 的 UPDATE 分支时，
            // 那个值可能是上一句话留下的 —— 静默指向另一条笔记，而且不会有任何症状。
            let rowID = try requireRowID(of: note.id)
            // 归属补缺（schema v2）：**新笔记**落默认笔记本；已有归属的**一字不动**
            // （`ON CONFLICT` 那一段不含 `notebook_uid`，这里也只管 NULL / 空串）。
            // 默认容器还没建（首次运行、且调用方还没走过 `ensureDefaultContainers`）时这条 UPDATE
            // 不匹配任何行、也不写入 NULL —— 交给迁移那一步兜底。
            try connection.execute(
                """
                UPDATE note SET notebook_uid = (SELECT uid FROM notebook WHERE is_default = 1 LIMIT 1)
                WHERE uuid = ? AND (notebook_uid IS NULL OR notebook_uid = '');
                """,
                [.text(note.id.uuidString)]
            )
            // 标签是**全量替换**语义（`Note.tags` 是完整集合）：先清后插，省掉「差集算法写错」这类缺陷。
            try connection.execute("DELETE FROM note_tag WHERE note_id = ?", [.integer(rowID)])
            for tag in Set(note.tags).sorted() {
                try connection.execute(
                    "INSERT INTO note_tag (note_id, tag) VALUES (?, ?)",
                    [.integer(rowID), .text(tag)]
                )
            }
            try connection.execute(
                "INSERT INTO note_timeline (note_id, at, kind, detail) VALUES (?, ?, ?, ?)",
                [
                    .integer(rowID),
                    .real(note.updatedAt.timeIntervalSince1970),
                    .text(NoteTimelineKind.upsert),
                    .null
                ]
            )
            return rowID
        }
    }

    /// 追加一条附件索引（**只存路径**）。
    public func addAttachment(_ attachment: NoteAttachment, to id: UUID) throws {
        try connection.transaction {
            let rowID = try requireRowID(of: id)
            try connection.execute(
                "INSERT OR REPLACE INTO note_attachment (uuid, note_id, path, byte_count, added_at) VALUES (?, ?, ?, ?, ?)",
                [
                    .text(attachment.id.uuidString),
                    .integer(rowID),
                    .text(attachment.path),
                    attachment.byteCount.map { SQLiteValue.integer($0) } ?? .null,
                    .real(attachment.addedAt.timeIntervalSince1970)
                ]
            )
        }
    }

    /// 追加一条时间线（保真：**只增不改**，时间线是流水）。
    public func recordTimeline(_ entry: NoteTimelineEntry, for id: UUID) throws {
        try connection.transaction {
            let rowID = try requireRowID(of: id)
            try connection.execute(
                "INSERT INTO note_timeline (note_id, at, kind, detail) VALUES (?, ?, ?, ?)",
                [
                    .integer(rowID),
                    .real(entry.at.timeIntervalSince1970),
                    .text(entry.kind),
                    entry.detail.map { SQLiteValue.text($0) } ?? .null
                ]
            )
        }
    }

    /// 删一条笔记（标签 / 时间线 / 附件索引靠外键级联一起走，`foreign_keys = ON` 是前提）。
    public func delete(id: UUID) throws {
        try connection.execute("DELETE FROM note WHERE uuid = ?", [.text(id.uuidString)])
    }

    /// **收藏 / 取消收藏**（队列 `L-184` 第三片；`FR-NOTE-18`、契约 §2.1 `favorite`）。
    ///
    /// 一条纪律：**不碰 `updated_at`** —— 收藏是组织行为，不是一次内容更新（与跨笔记本移动同口径；
    /// 否则收藏一下，列表按更新时间排的次序就整体错乱）。
    /// 为什么不做成 `upsert` 的一部分：`upsert` 的 `ON CONFLICT` 段刻意**不含这一列**
    /// （与 `notebook_uid` 同一条教训）—— 改收藏只有这一条路，且这条路只改这一列。
    /// 认不出的 id ⇒ 一行都不匹配（静默无操作），由调用方按返回值如实处置。
    @discardableResult
    public func setFavorite(_ favorite: Bool, id: UUID) throws -> Int {
        try connection.execute(
            "UPDATE note SET favorite = ? WHERE uuid = ?",
            [.integer(favorite ? 1 : 0), .text(id.uuidString)]
        )
        return connection.changeCount
    }

    /// 一条笔记是不是收藏（`nil` = 库里没有这条笔记）。判据与迁移用它读回事实，不靠内存里的值。
    public func isFavorite(id: UUID) throws -> Bool? {
        try connection
            .scalarInt("SELECT favorite FROM note WHERE uuid = ?", [.text(id.uuidString)])
            .map { $0 == 1 }
    }

    /// **置顶 / 取消置顶**（队列 `L-184` 第四片；`FR-NOTE-18`、契约 §2.1 `pinned`）。
    ///
    /// 与 `setFavorite` 逐条同口径：**不碰 `updated_at`**（置顶是组织行为，不是一次内容更新；否则
    /// 置顶一下，列表按更新时间排的那一段次序就整体错乱）；**只改这一列**（`upsert` 的 `ON CONFLICT`
    /// 段不含 `pinned`，所以改正文保存不会把它抹掉）；认不出的 id ⇒ 一行都不匹配，
    /// 由调用方按返回值如实处置（返回 0 就是「库里没有这条」，不是「已经改好了」）。
    @discardableResult
    public func setPinned(_ pinned: Bool, id: UUID) throws -> Int {
        try connection.execute(
            "UPDATE note SET pinned = ? WHERE uuid = ?",
            [.integer(pinned ? 1 : 0), .text(id.uuidString)]
        )
        return connection.changeCount
    }

    /// 一条笔记是不是置顶（`nil` = 库里没有这条笔记）。判据与迁移用它读回事实，不靠内存里的值。
    public func isPinned(id: UUID) throws -> Bool? {
        try connection
            .scalarInt("SELECT pinned FROM note WHERE uuid = ?", [.text(id.uuidString)])
            .map { $0 == 1 }
    }

    // MARK: - 正文 spans（schema v8 · 片 `WY-1a`）

    /// **写一条笔记的正文权威源 `spans`（JSON）—— 这里是唯一一处写 `spans` 的路径。**
    ///
    /// 三条口径：
    ///   · **`spans` 是权威源，`body` 是它的单向投影**：所以同一条语句把**投影**（`body`）一并写下去
    ///     —— 落库的 `body` 因此恒等于 `spans` 的投影，不会有「权威源换了、文本列还是旧的」这种半新半旧。
    ///   · **不反向回写**：没有任何一条路从 `body` 反推 `spans`（v1 → v2 的一次性迁移归片 `WY-2`）。
    ///   · **不碰 `updated_at` 之外的列**：调用方若要刷新时间，自己给；这里只动正文这两列
    ///     （与 `setFavorite` / `setPinned` 的「只改这一件」同纪律 —— 改正文不该顺带动归属 / 收藏 / 置顶）。
    /// 认不出的 id ⇒ 一行都不匹配（静默无操作），由调用方按返回值如实处置。
    @discardableResult
    public func setNoteSpans(_ spans: String, body: String, id: UUID) throws -> Int {
        try connection.execute(
            "UPDATE note SET spans = ?, body = ? WHERE uuid = ?",
            [.text(spans), .text(body), .text(id.uuidString)]
        )
        return connection.changeCount
    }

    /// 一条笔记的正文 spans（JSON 原样；`nil` = 库里没有这条笔记 **或** 该列还是 `NULL`（v1 存量，未迁移））。
    /// 这两种「`nil`」对读的人是同一件事（这条还没有 v2 权威源），与 `isFavorite` 的 `nil` 同形。
    public func noteSpans(id: UUID) throws -> String? {
        try connection.scalarText("SELECT spans FROM note WHERE uuid = ?", [.text(id.uuidString)])
    }

    // MARK: - 读

    public func noteCount() throws -> Int {
        Int(try connection.scalarInt("SELECT count(*) FROM note") ?? 0)
    }

    /// 全部笔记（更新时间倒序、同时间按标题 —— **稳定有序**，界面不必自己再排一遍）。
    public func notes() throws -> [Note] {
        try notes(from: "SELECT * FROM note ORDER BY updated_at DESC, title ASC")
    }

    public func note(id: UUID) throws -> Note? {
        try notes(from: "SELECT * FROM note WHERE uuid = ?", [.text(id.uuidString)]).first
    }

    /// 时间线（按时间正序 —— 读流水要顺着读）。
    public func timeline(of id: UUID) throws -> [NoteTimelineEntry] {
        let rowID = try requireRowID(of: id)
        return try connection
            .query("SELECT at, kind, detail FROM note_timeline WHERE note_id = ? ORDER BY at ASC, id ASC", [.integer(rowID)])
            .map { row in
                NoteTimelineEntry(
                    at: Date(timeIntervalSince1970: row["at"].doubleValue ?? 0),
                    kind: row.text("kind") ?? "",
                    detail: row.text("detail")
                )
            }
    }

    /// 附件索引（按加入时间正序）。
    public func attachments(of id: UUID) throws -> [NoteAttachment] {
        let rowID = try requireRowID(of: id)
        return try connection
            .query(
                "SELECT uuid, path, byte_count, added_at FROM note_attachment WHERE note_id = ? ORDER BY added_at ASC",
                [.integer(rowID)]
            )
            .compactMap { row in
                guard let uuid = row.text("uuid"), let identifier = UUID(uuidString: uuid) else { return nil }
                return NoteAttachment(
                    id: identifier,
                    path: row.text("path") ?? "",
                    byteCount: row["byte_count"].intValue,
                    addedAt: Date(timeIntervalSince1970: row["added_at"].doubleValue ?? 0)
                )
            }
    }

    /// 检索结果 + **走的是哪条路**（trigram 全文检索还是 LIKE 兜底）。
    ///
    /// 为什么要把路径一起返回：trigram 要求查询串 ≥3 字，1~2 字的查询（中文里很常见）只能兜底；
    /// 调用方需要能如实告诉用户"这两条是按子串匹配找的"。
    public struct SearchResult: Equatable, Sendable {
        public enum Route: String, Equatable, Sendable {
            /// FTS5 trigram 命中（查询串 ≥3 字且短语在标题 / 正文里出现）。
            /// **标签命中在这条路里作为补充一并并入**（`note_fts` 只索引标题与正文）——
            /// 路线说的是「这次查询有没有走成全文检索」，不是「每条结果的每一个命中来源」。
            case fullText
            /// 子串扫描兜底：全文索引**没命中**（查询串 < 3 字 —— trigram 不产出 token；
            /// 或 ≥3 字的短语落了空），整条按子串扫标题 / 正文 / 标签。
            case substring
        }
        public var route: Route
        public var notes: [Note]
    }

    /// 检索**标题 / 正文 / 标签**（`FR-PLUG-08` 的「按条件查与全文检索」）。
    ///
    /// **三个字段都要查**：界面搜索框的占位符写着「搜索标题 / 正文 / 标签」，而 `note_fts`
    /// 只索引标题与正文 ⇒ 标签那一半必须在两条路里各补一次（队列 L-44 收口时实测到的
    /// 「差一点」：界面检索从内存过滤改走库，标签命中会**静默丢掉**，占位符当场变成一句假话）。
    /// 合并后的顺序按 `updated_at DESC, title ASC` **重排**（两次查询拼起来的数组不能各排各的），
    /// 与 `notes()` 同一个口径。
    public func search(_ query: String, limit: Int = 200) throws -> SearchResult {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return SearchResult(route: .fullText, notes: try notes()) }

        // `LIKE` 的模式串（`%` 包住的子串；转义见 `escapeLike`）—— 两条路都要用它，所以先算出来。
        let pattern = "%" + Self.escapeLike(needle) + "%"

        // 口径：查询串按**字符**数（不是字节）判定 —— 中文一个字符三个字节，按字节判会让 1 个汉字过关、
        // 而 trigram 实际切不出 token，于是"检索得到但什么都没找到"。
        if needle.count >= 3 {
            // FTS5 的 MATCH 需要**字面量**串（`?` 绑定在 FTS5 的查询语法里不被接受为短语），
            // 所以这里显式转义双引号并整体包成短语 —— 用户输入里的 `-` / `*` 因此不会被当成查询运算符。
            let phrase = "\"" + needle.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let rows = try connection.query(
                """
                SELECT note.* FROM note
                JOIN note_fts ON note_fts.rowid = note.id
                WHERE note_fts MATCH ?
                ORDER BY note.updated_at DESC, note.title ASC
                LIMIT ?;
                """,
                [.text(phrase), .integer(Int64(limit))]
            )
            // 兜底判据：trigram 只覆盖 ≥3 字的**连续子串**，若查询串里含空格（"关于 骑行" 这类），
            // 短语匹配会空手而归 —— 这时退回子串扫描，宁可慢一点也不假装"没有"。
            if !rows.isEmpty {
                // 标签补充：`note_fts` 里没有标签这一列，所以「只有标签命中」的那些要单独捞一次，
                // 已经在全文结果里的不重复算（`id NOT IN (… MATCH …)`）。
                let tagRows = try connection.query(
                    """
                    SELECT * FROM note
                    WHERE id NOT IN (SELECT rowid FROM note_fts WHERE note_fts MATCH ?)
                      AND EXISTS (
                        SELECT 1 FROM note_tag
                        WHERE note_tag.note_id = note.id AND note_tag.tag LIKE ? ESCAPE '\\'
                      )
                    ORDER BY updated_at DESC, title ASC
                    LIMIT ?;
                    """,
                    [.text(phrase), .text(pattern), .integer(Int64(limit))]
                )
                let merged = try materialize(rows) + (try materialize(tagRows))
                return SearchResult(route: .fullText, notes: Self.byRecency(merged))
            }
        }
        let rows = try connection.query(
            """
            SELECT * FROM note
            WHERE title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\'
               OR EXISTS (
                 SELECT 1 FROM note_tag
                 WHERE note_tag.note_id = note.id AND note_tag.tag LIKE ? ESCAPE '\\'
               )
            ORDER BY updated_at DESC, title ASC
            LIMIT ?;
            """,
            [.text(pattern), .text(pattern), .text(pattern), .integer(Int64(limit))]
        )
        return SearchResult(route: .substring, notes: try materialize(rows))
    }

    /// 合并结果的定序（与 `notes()` 同口径）：最近更新在前，同一时刻按标题。
    private static func byRecency(_ notes: [Note]) -> [Note] {
        notes.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.title < right.title
        }
    }

    /// `LIKE` 的转义（`%` / `_` / `\` 都要转，否则用户搜 `100%` 会匹配到一切）。
    static func escapeLike(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    // MARK: - 待办任务清单（schema v5 · 队列 `N-11` 的 macOS 核心层半）

    /// 写入或按 uuid 覆盖一条任务，返回它的 rowid。
    ///
    /// 与 `upsert(_ note:)` 逐条同纪律：本体与标签**在一个事务**里落库（半个任务是最难查的一类
    /// 不一致）；`due_at` 与 `done` **各写各的**（契约裁决 ①：完成不清截止时间；
    /// 「已完成」这件事由 `setDone` 改，不由重写正文顺带改）；`priority` 认不出的取值
    /// **当没给**（`TodoPriority(raw:)` 已归一，这里只管把归一后的那个串存下去）。
    /// `note`（备注正文，schema v9）与标题同档 —— 它就是任务自己的一个内容列，**写的路只有这一条**
    /// （`ON CONFLICT` 段跟着更新它，改备注与改标题走的是同一次 `upsert`）。
    @discardableResult
    public func upsert(_ todo: Todo) throws -> Int64 {
        try connection.transaction {
            try connection.execute(
                """
                INSERT INTO todo (
                    uuid, title, note, due_at, done, completed_at, priority, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (uuid) DO UPDATE SET
                    title = excluded.title,
                    note = excluded.note,
                    due_at = excluded.due_at,
                    done = excluded.done,
                    completed_at = excluded.completed_at,
                    priority = excluded.priority,
                    updated_at = excluded.updated_at;
                """,
                [
                    .text(todo.id.uuidString),
                    .text(todo.title),
                    .text(todo.note),
                    todo.dueAt.map { SQLiteValue.real($0.timeIntervalSince1970) } ?? .null,
                    .integer(todo.done ? 1 : 0),
                    todo.completedAt.map { SQLiteValue.real($0.timeIntervalSince1970) } ?? .null,
                    .text(todo.priority.raw),
                    .real(todo.createdAt.timeIntervalSince1970),
                    .real(todo.updatedAt.timeIntervalSince1970)
                ]
            )
            // 按 uuid 反查 rowid（与 `upsert(_ note:)` 同一个理由：走 UPDATE 分支时
            // `last_insert_rowid()` 是上一句话留下的值，静默指向另一条任务且没有症状）。
            let rowID = try requireTodoRowID(of: todo.id)
            // 标签是**全量替换**语义（`Todo.tags` 是完整集合）：先清后插，省掉差集算法那类缺陷。
            try connection.execute("DELETE FROM todo_tag WHERE todo_id = ?", [.integer(rowID)])
            for tag in Set(todo.tags).sorted() {
                try connection.execute(
                    "INSERT INTO todo_tag (todo_id, tag) VALUES (?, ?)",
                    [.integer(rowID), .text(tag)]
                )
            }
            return rowID
        }
    }

    /// **完成 / 重开**一条任务（`FR-NOTE-36`、契约裁决 ①）：
    /// 只动 `done` / `completed_at` / `updated_at`，**一个字节都不碰 `due_at`** ——
    /// 「完成态切换不丢原始截止时间」在这条路上是**形状**而不是纪律（碰不到那一列）。
    /// 认不出的 id ⇒ 一行都不匹配，由调用方按返回值如实处置（返回 0 就是「库里没有这条」）。
    @discardableResult
    public func setDone(_ done: Bool, id: UUID, at moment: Date = Date()) throws -> Int {
        try connection.execute(
            "UPDATE todo SET done = ?, completed_at = ?, updated_at = ? WHERE uuid = ?",
            [
                .integer(done ? 1 : 0),
                done ? .real(moment.timeIntervalSince1970) : .null,
                .real(moment.timeIntervalSince1970),
                .text(id.uuidString)
            ]
        )
        return connection.changeCount
    }

    /// 删一条任务（它的标签靠外键级联一起走，`foreign_keys = ON` 是前提）。
    public func deleteTodo(id: UUID) throws {
        try connection.execute("DELETE FROM todo WHERE uuid = ?", [.text(id.uuidString)])
    }

    /// 一条任务（`nil` = 库里没有这一条）。
    public func todo(id: UUID) throws -> Todo? {
        try todos(from: "SELECT * FROM todo WHERE uuid = ?", [.text(id.uuidString)]).first
    }

    /// 全部任务（**创建时间正序、同时间按 uuid 兜底** —— 稳定有序）。
    ///
    /// **边界（如实登记）**：「按截止时间 / 优先级 / 创建时间三档排」的**排序口径**与
    /// 「无截止排哪一端」「逾期是否影响排序」属**契约半**（`DoyahNotes/Docs/核心契约.md`）
    /// —— 契约落笔前**不在这里自造**（提案 `0004` 末尾明写）⇒ 本片只给一个确定的稳定次序。
    public func todos() throws -> [Todo] {
        try todos(from: "SELECT * FROM todo ORDER BY created_at ASC, uuid ASC")
    }

    public func todoCount() throws -> Int {
        Int(try connection.scalarInt("SELECT count(*) FROM todo") ?? 0)
    }

    // MARK: - 提醒（schema v6 · 队列 `L-100` 落法 ④ 的存储半）

    /// 写入或按 uuid 覆盖一条提醒，返回它的 rowid。
    ///
    /// 三条口径：
    ///   · **归属必须真的存在**：挂到一条库里没有的笔记 / 任务上 ⇒ 抛错（`requireRowID` /
    ///     `requireTodoRowID`）—— 不落一条谁也找不到的提醒（它会到点弹出，而界面上没有它）。
    ///   · **归属面只在这里落一次**：`note_id` / `todo_id` 由 `ReminderOwner` 决定，
    ///     「恰有一个非空」由 schema v6 的 `CHECK` 保证（**形状**，不是纪律）。
    ///   · **规格逐列走**：`rule` / `anchor_date` / `minute_of_day` / `interval_count` /
    ///     `interval_unit` / `weekdays`（归一文本） / `until_date` —— 入库前不再做第二次解释，
    ///     认不出的取值由调度那一层按契约判非法（这一层不挡、也不改）。
    @discardableResult
    public func upsert(_ reminder: Reminder) throws -> Int64 {
        let noteRowID = try reminder.owner.noteID.map { try requireRowID(of: $0) }
        let todoRowID = try reminder.owner.todoID.map { try requireTodoRowID(of: $0) }
        try connection.execute(
            """
            INSERT INTO reminder (
                uuid, note_id, todo_id, rule, anchor_date, minute_of_day, interval_count,
                interval_unit, weekdays, until_date, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (uuid) DO UPDATE SET
                note_id = excluded.note_id,
                todo_id = excluded.todo_id,
                rule = excluded.rule,
                anchor_date = excluded.anchor_date,
                minute_of_day = excluded.minute_of_day,
                interval_count = excluded.interval_count,
                interval_unit = excluded.interval_unit,
                weekdays = excluded.weekdays,
                until_date = excluded.until_date,
                updated_at = excluded.updated_at;
            """,
            [
                .text(reminder.id.uuidString),
                noteRowID.map { SQLiteValue.integer($0) } ?? .null,
                todoRowID.map { SQLiteValue.integer($0) } ?? .null,
                .text(reminder.spec.rule),
                .text(reminder.spec.anchorDate),
                .integer(Int64(reminder.spec.minuteOfDay)),
                .integer(Int64(reminder.spec.intervalCount)),
                .text(reminder.spec.intervalUnit),
                .text(reminder.spec.weekdaysText),
                .text(reminder.spec.untilDate),
                .real(reminder.createdAt.timeIntervalSince1970),
                .real(reminder.updatedAt.timeIntervalSince1970)
            ]
        )
        // 按 uuid 反查 rowid（与笔记 / 待办那两处同一个理由：走 UPDATE 分支时
        // `last_insert_rowid()` 是上一句话留下的值，静默指向另一条提醒且没有症状）。
        return try requireReminderRowID(of: reminder.id)
    }

    /// 一条提醒（`nil` = 库里没有这一条）。
    public func reminder(id: UUID) throws -> Reminder? {
        try reminders(from: Self.reminderSelect + " WHERE r.uuid = ?", [.text(id.uuidString)]).first
    }

    /// 某个归属（一条笔记 / 一条任务）的提醒（**创建时间正序、同时间按 uuid 兜底** —— 稳定有序）。
    ///
    /// **认不出的归属如实回空表、不抛错**：查询不是写入 —— 问「这条任务还有没有提醒」时，
    /// 「库里没有这条任务」与「这条任务没有提醒」对调用方是同一个答案（`[]`），
    /// 不该让界面为了问一句话先做一次存在性判断。
    public func reminders(of owner: ReminderOwner) throws -> [Reminder] {
        if let noteID = owner.noteID {
            return try reminders(
                from: Self.reminderSelect
                    + " WHERE r.note_id = (SELECT id FROM note WHERE uuid = ?)"
                    + " ORDER BY r.created_at ASC, r.uuid ASC",
                [.text(noteID.uuidString)]
            )
        }
        if let todoID = owner.todoID {
            return try reminders(
                from: Self.reminderSelect
                    + " WHERE r.todo_id = (SELECT id FROM todo WHERE uuid = ?)"
                    + " ORDER BY r.created_at ASC, r.uuid ASC",
                [.text(todoID.uuidString)]
            )
        }
        return []
    }

    /// 全部提醒（**同上**：创建时间正序、同时间按 uuid 兜底）。
    public func reminders() throws -> [Reminder] {
        try reminders(from: Self.reminderSelect + " ORDER BY r.created_at ASC, r.uuid ASC")
    }

    public func reminderCount() throws -> Int {
        Int(try connection.scalarInt("SELECT count(*) FROM reminder") ?? 0)
    }

    /// 删一条提醒（认不出的 id ⇒ 一行都不动 —— 与 `deleteTodo` 同形：删是幂等的，不抛错）。
    public func deleteReminder(id: UUID) throws {
        try connection.execute("DELETE FROM reminder WHERE uuid = ?", [.text(id.uuidString)])
    }

    // MARK: - 查询历史（schema v7 · 队列 HIST-1）

    /// 库里的全部查询历史（**执行时间倒序** = 界面「最新在上」；同刻按 `rowid` 倒序，
    /// 同一批写入里后写的那条在前 —— 读数稳定，不靠「碰巧的插入顺序」）。
    ///
    /// 上限（500 条 / 90 天）**不在这一层裁**：库只管存与取，裁剪收在 `QueryHistoryStore.prune`
    /// 一处（`DR-02` 的「先到者为准」只有一处说得清）。
    public func queryHistory() throws -> [QueryHistory] {
        try connection
            .query(
                """
                SELECT id, connection_id, sql, executed_at, duration, succeeded
                FROM query_history
                ORDER BY executed_at DESC, rowid DESC;
                """
            )
            .compactMap { row in
                // 认不出的行**不装作读出来了**（与 `attachments(of:)` 同一条纪律）：
                // id / connection_id 不是 UUID 的行走 compactMap 丢掉，而不是拿默认值糊一条出来。
                guard
                    let rawID = row.text("id"), let id = UUID(uuidString: rawID),
                    let rawConnection = row.text("connection_id"),
                    let connectionID = UUID(uuidString: rawConnection)
                else { return nil }
                return QueryHistory(
                    id: id,
                    connectionID: connectionID,
                    sql: row.text("sql") ?? "",
                    executedAt: Date(timeIntervalSince1970: row["executed_at"].doubleValue ?? 0),
                    duration: row["duration"].doubleValue ?? 0,
                    succeeded: row["succeeded"].boolValue ?? false
                )
            }
    }

    /// 写一条历史：**按 id 覆盖**（同 id 再写 = 刷新 `executed_at` / `duration` / `succeeded`）。
    ///
    /// 「连续重复执行同一条 SQL 只刷新最新一条」由调用方复用最新那一条的 `id` 实现
    /// —— 库里因此**不需要**第二条更新写路（单一写入口的推论）。
    public func upsertQueryHistory(_ entry: QueryHistory) throws {
        try connection.execute(
            """
            INSERT INTO query_history (id, connection_id, sql, executed_at, duration, succeeded)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                connection_id = excluded.connection_id,
                sql = excluded.sql,
                executed_at = excluded.executed_at,
                duration = excluded.duration,
                succeeded = excluded.succeeded;
            """,
            [
                .text(entry.id.uuidString),
                .text(entry.connectionID.uuidString),
                .text(entry.sql),
                .real(entry.executedAt.timeIntervalSince1970),
                .real(entry.duration),
                .integer(entry.succeeded ? 1 : 0)
            ]
        )
    }

    /// 裁掉超出上限的行（**唯一一处裁剪**，`QueryHistoryStore` 只调它）：
    /// 只保留「最新 `maxEntries` 条」∩「不早于 `maxAge` 秒前」—— 两个上限**先到者为准**。
    /// 换句话说：一条行留下来，必须**同时**还在前 `maxEntries` 名内、且比 `now - maxAge` 新。
    ///
    /// `maxEntries <= 0` 判成「不留」而不是「不裁」：上限写成 0 的含义是清空，
    /// 而把 0 读成「无上限」会把一条保护性配置变成反方向的危险默认。
    public func pruneQueryHistory(keepingMax maxEntries: Int, maxAge: TimeInterval, now: Date = Date()) throws {
        guard maxEntries > 0 else {
            try clearQueryHistory()
            return
        }
        try connection.execute(
            """
            DELETE FROM query_history
            WHERE executed_at < ?
               OR id NOT IN (
                    SELECT id FROM query_history ORDER BY executed_at DESC, rowid DESC LIMIT ?
               );
            """,
            [.real(now.addingTimeInterval(-maxAge).timeIntervalSince1970), .integer(Int64(maxEntries))]
        )
    }

    /// 清空全部历史，返回**真的删了几行**（调用方按这个数如实处置，不假装删了）。
    @discardableResult
    public func clearQueryHistory() throws -> Int {
        let before = try queryHistoryCount()
        try connection.execute("DELETE FROM query_history;")
        return before
    }

    /// 删一条历史（认不出的 id ⇒ 一行都不动 —— 删是幂等的，不抛错，与 `deleteReminder` 同形）。
    public func deleteQueryHistory(id: UUID) throws {
        try connection.execute("DELETE FROM query_history WHERE id = ?", [.text(id.uuidString)])
    }

    /// 历史条数（`snapshot` 的元信息与证据脚本用它把「库里真有东西」说成数）。
    public func queryHistoryCount() throws -> Int {
        Int(try connection.scalarInt("SELECT count(*) FROM query_history") ?? 0)
    }

    // MARK: - 两层归属（schema v2 · 队列 L-97 第二片）

    /// 库里的两层结构（架 + 笔记本）。结构本身**不兜底**：库里一条都没有就如实返回空
    /// （兜底落点在 `NotebookDirectory` 的那几个 `resolved*` 与 `ensureDefaultContainers`）。
    public func notebookDirectory() throws -> NotebookDirectory {
        NotebookDirectory(shelves: try shelves(), notebooks: try notebooks())
    }

    /// 全部笔记本架（稳定排序与界面同口径：排序位 → 创建时刻 → uid）。
    public func shelves() throws -> [Shelf] {
        try connection
            .query("SELECT uid, name, sort_order, created_at, is_default FROM shelf ORDER BY sort_order ASC, created_at ASC, uid ASC")
            .map { row in
                Shelf(
                    uid: row.text("uid") ?? "",
                    name: row.text("name") ?? "",
                    sortOrder: Int(row.int("sort_order") ?? 0),
                    createdAt: Date(timeIntervalSince1970: row["created_at"].doubleValue ?? 0),
                    isDefault: row.int("is_default") == 1
                )
            }
    }

    /// 全部笔记本（同一条稳定排序）。
    public func notebooks() throws -> [Notebook] {
        try connection
            .query(
                "SELECT uid, shelf_uid, name, sort_order, created_at, is_default FROM notebook ORDER BY sort_order ASC, created_at ASC, uid ASC"
            )
            .map { row in
                Notebook(
                    uid: row.text("uid") ?? "",
                    shelfUid: row.text("shelf_uid") ?? "",
                    name: row.text("name") ?? "",
                    sortOrder: Int(row.int("sort_order") ?? 0),
                    createdAt: Date(timeIntervalSince1970: row["created_at"].doubleValue ?? 0),
                    isDefault: row.int("is_default") == 1
                )
            }
    }

    /// 写一个笔记本架（按 `uid` 覆盖；`is_default` 由调用方定）。
    public func upsert(_ shelf: Shelf) throws {
        try connection.execute(
            """
            INSERT INTO shelf (uid, name, sort_order, created_at, is_default) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (uid) DO UPDATE SET
                name = excluded.name, sort_order = excluded.sort_order, is_default = excluded.is_default;
            """,
            [
                .text(shelf.uid),
                .text(shelf.name),
                .integer(Int64(shelf.sortOrder)),
                .real(shelf.createdAt.timeIntervalSince1970),
                .integer(shelf.isDefault ? 1 : 0)
            ]
        )
    }

    /// 写一个笔记本（按 `uid` 覆盖）。`shelfUid` 指向不存在的架时**外键会拦下来**
    /// （`shelf_uid` 有 `REFERENCES shelf (uid)`，而 `foreign_keys = ON`）—— 这正是「不存在无归属笔记本」。
    public func upsert(_ notebook: Notebook) throws {
        try connection.execute(
            """
            INSERT INTO notebook (uid, shelf_uid, name, sort_order, created_at, is_default) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (uid) DO UPDATE SET
                shelf_uid = excluded.shelf_uid, name = excluded.name,
                sort_order = excluded.sort_order, is_default = excluded.is_default;
            """,
            [
                .text(notebook.uid),
                .text(notebook.shelfUid),
                .text(notebook.name),
                .integer(Int64(notebook.sortOrder)),
                .real(notebook.createdAt.timeIntervalSince1970),
                .integer(notebook.isDefault ? 1 : 0)
            ]
        )
    }

    /// 删一个笔记本架（里面的笔记本靠外键级联走）。
    ///
    /// **刻意只做「删这一行」**：里面的笔记怎么办是 `ContainerRemovalPlan`（Core 半）算出来的策略
    /// （一并删 / 移到默认笔记本），调用方先落那个计划、再调这里 —— 库这一层不替上层做决定。
    public func deleteShelf(uid: String) throws {
        try connection.execute("DELETE FROM shelf WHERE uid = ?", [.text(uid)])
    }

    /// 删一个笔记本（同一条纪律：笔记的处置归调用方）。
    public func deleteNotebook(uid: String) throws {
        try connection.execute("DELETE FROM notebook WHERE uid = ?", [.text(uid)])
    }

    // MARK: - 删除处置落库（队列 L-97 第三片）

    /// 算「删这个笔记本」的处置计划：读一次库里的结构与归属，交给 `NotebookDirectory`（纯逻辑）裁决。
    /// 默认笔记本认不出来的容器 ⇒ `nil`（不可删）。
    public func removalPlan(
        forNotebook notebookUid: String,
        policy: ContainerRemovalPolicy = .default
    ) throws -> ContainerRemovalPlan? {
        try notebookDirectory().removalPlan(forNotebook: notebookUid, policy: policy, placements: try placements())
    }

    /// 算「删这个架」的处置计划（同一条路）。
    public func removalPlan(
        forShelf shelfUid: String,
        policy: ContainerRemovalPolicy = .default
    ) throws -> ContainerRemovalPlan? {
        try notebookDirectory().removalPlan(forShelf: shelfUid, policy: policy, placements: try placements())
    }

    /// **把处置计划真正落库** —— 一个计划 = **一个事务**。
    ///
    /// 为什么必须是同一个事务：删笔记本与改挂它的笔记是两件事，中途失败会留下
    /// 「笔记还挂着一个已经不存在的 `notebook_uid`」—— 它不违反任何外键
    /// （`note.notebook_uid` 刻意没加外键，理由见 `NoteSchemaV2` 那段注释），
    /// 却正好是契约 §2.12 要挡掉的「无归属笔记」。所以要么两件都成、要么都不动。
    @discardableResult
    public func applyRemovalPlan(_ plan: ContainerRemovalPlan) throws -> ContainerRemovalPlan {
        try connection.transaction {
            switch plan.policy {
            case .deleteTogether:
                // ① 先删该删的笔记（标签 / 时间线 / 附件索引靠外键级联一起走）。
                try deleteNotes(uuids: plan.deletedNoteIDs)
                // ② 再给「不可删的笔记本」换架 —— **必须排在删架之前**：删架会级联带走架里的笔记本，
                //    而默认笔记本是不可删的（契约 §2.12 第 3 条）。
                try rehome(notebookUids: plan.movedNotebookUids, toShelf: plan.targetContainerUid)
                // ③ 删该删的笔记本。
                for uid in plan.removedNotebookUids { try deleteNotebook(uid: uid) }
                // ④ 删容器本身（删架时剩下的笔记本已在 ③ 清空）。
                try deleteContainer(uid: plan.removedContainerUid, kind: plan.removedContainerKind)

            case .moveToDefault:
                // ① 笔记改挂默认笔记本。按**归属列**整批扫（而不只认计划里那份名单）：
                //    名单是「谁会受影响」的账，扫列才是「不留无归属」的保证，两条并用不重不漏。
                if let destination = plan.targetContainerUid {
                    try moveNotes(ownedBy: plan.removedContainerUid, also: plan.movedNoteIDs, toNotebook: destination)
                }
                // ② 笔记本改挂默认架 + 排序位顺延到目标架现有条数之后（删架档才有内容）。
                try rehome(notebookUids: plan.movedNotebookUids, toShelf: plan.targetContainerUid)
                // ③ 删容器本身。
                try deleteContainer(uid: plan.removedContainerUid, kind: plan.removedContainerKind)
            }
        }
        return plan
    }

    /// 绑定量分块：`uuid IN (?, ?, …)` 的占位符个数会撞 SQLite 的变量上限
    /// （编译期 `SQLITE_MAX_VARIABLE_NUMBER`，旧版本只有 999）——
    /// 而「一个笔记本里有多少条笔记」是用户数据，不能假定它小。分块是这件事**不靠自觉**的做法。
    private static let bindingChunkSize = 500

    private static func chunks<T>(_ items: [T]) -> [[T]] {
        guard items.count > bindingChunkSize else { return items.isEmpty ? [] : [items] }
        return stride(from: 0, to: items.count, by: bindingChunkSize).map {
            Array(items[$0 ..< min($0 + bindingChunkSize, items.count)])
        }
    }

    private func deleteNotes(uuids: [String]) throws {
        for chunk in Self.chunks(uuids) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            try connection.execute(
                "DELETE FROM note WHERE uuid IN (\(placeholders))",
                chunk.map { SQLiteValue.text($0) }
            )
        }
    }

    /// 把若干条笔记改挂到别处。**只动 `notebook_uid`** —— 不碰 `updated_at`（契约 §2.12 第 4 条）。
    private func moveNotes(ownedBy containerUid: String, also noteIDs: [String], toNotebook target: String) throws {
        try connection.execute(
            "UPDATE note SET notebook_uid = ? WHERE notebook_uid = ?",
            [.text(target), .text(containerUid)]
        )
        for chunk in Self.chunks(noteIDs) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            var bindings: [SQLiteValue] = [.text(target)]
            bindings.append(contentsOf: chunk.map { SQLiteValue.text($0) })
            try connection.execute(
                "UPDATE note SET notebook_uid = ? WHERE uuid IN (\(placeholders))",
                bindings
            )
        }
    }

    /// 把若干笔记本改挂到目标架，排序位**顺延**到目标架现有条数之后（不重号、不跳号）。
    /// 顺序按传进来的名单（计划里那份是排好序的），目标架为空 / 名单为空 ⇒ 什么都不做。
    private func rehome(notebookUids: [String], toShelf shelfUid: String?) throws {
        guard let shelfUid, !notebookUids.isEmpty else { return }
        var next = try notebookDirectory().notebooks(inShelf: shelfUid).count
        for uid in notebookUids {
            try connection.execute(
                "UPDATE notebook SET shelf_uid = ?, sort_order = ? WHERE uid = ?",
                [.text(shelfUid), .integer(Int64(next)), .text(uid)]
            )
            next += 1
        }
    }

    private func deleteContainer(uid: String, kind: NotebookContainerKind) throws {
        switch kind {
        case .notebook: try deleteNotebook(uid: uid)
        case .shelf: try deleteShelf(uid: uid)
        }
    }

    // MARK: - 容器编辑落库（队列 L-97 界面半第四片：新建 / 重命名 / 排序）

    /// **新建一个笔记本**：落进某个架、排序位由调用方给（`NotebookCreation.sortOrder` 算的那一个）。
    /// `shelf_uid` 指向不存在的架时**外键会拦下来**（`notebook.shelf_uid REFERENCES shelf (uid)`）——
    /// 这正是契约 §2.12 那条「不存在无归属笔记本」在库这一层的落点。
    /// 新笔记本**永远不是默认容器**（默认笔记本由一次性迁移建、且不随界面动作易主）。
    @discardableResult
    public func createNotebook(
        shelfUid: String,
        name: String,
        sortOrder: Int,
        uid: String = UUID().uuidString,
        now: Date = Date()
    ) throws -> Notebook {
        let notebook = Notebook(
            uid: uid,
            shelfUid: shelfUid,
            name: name,
            sortOrder: sortOrder,
            createdAt: now,
            isDefault: false
        )
        try upsert(notebook)
        return notebook
    }

    /// **改一个架的名字**：只改 `name` —— 其余三格原样带回（`upsert` 的 `ON CONFLICT` 不含
    /// `created_at`，但**含** `sort_order` 与 `is_default` ⇒ 必须先把它们读出来再写，
    /// 否则一次改名会顺手把排序位抹成 0、把默认位丢掉）。
    /// 认不出的 uid ⇒ `nil`（库一个字节不动）。
    @discardableResult
    public func rename(shelfUid: String, name: String) throws -> Shelf? {
        guard var shelf = try notebookDirectory().shelf(uid: shelfUid) else { return nil }
        shelf.name = name
        try upsert(shelf)
        return shelf
    }

    /// **改一个笔记本的名字**（同一条）。默认笔记本**也可以改名**（契约 §2.12 第 2 条：
    /// 不可删、可改名）—— 这里刻意不判 `isDefault`。
    /// 认不出的 uid ⇒ `nil`。
    @discardableResult
    public func rename(notebookUid: String, name: String) throws -> Notebook? {
        guard var notebook = try notebookDirectory().notebook(uid: notebookUid) else { return nil }
        notebook.name = name
        try upsert(notebook)
        return notebook
    }

    /// **写一批排序位**（一个事务）：`ContainerReorder.plan` 算出来的整层次序一次写完。
    /// 为什么必须同事务：半写会让界面上两条挤在同一个位置（次序退回「按创建时刻兜底」），
    /// 而用户刚做的那一步在屏幕上就**看不见**了 —— 「点了上移没反应」的另一种写法。
    public func applySortOrders(_ orders: [ContainerSortOrder], kind: NotebookContainerKind) throws {
        guard !orders.isEmpty else { return }
        try connection.transaction {
            for order in orders {
                switch kind {
                case .shelf:
                    try connection.execute(
                        "UPDATE shelf SET sort_order = ? WHERE uid = ?",
                        [.integer(Int64(order.sortOrder)), .text(order.uid)]
                    )
                case .notebook:
                    try connection.execute(
                        "UPDATE notebook SET sort_order = ? WHERE uid = ?",
                        [.integer(Int64(order.sortOrder)), .text(order.uid)]
                    )
                }
            }
        }
    }

    /// **把一个笔记本挪到另一个架**（跨架移动 —— 队列 `L-97` 落法 ① 的第四格）。
    ///
    /// 只改两格：`shelf_uid` + 排序位（**顺延到目标架现有条数之后**，不重号、不跳号）。
    /// **不碰** `created_at` / `is_default` —— 挪架不是改名、也不是删（契约 §2.12 第 2 条：
    /// 默认容器不可删、可改名）。也**不碰**里面的笔记：笔记跟着自己的笔记本走。
    ///
    /// 三处认不出 / 空操作一律 `nil`（库一个字节不动）—— 判定与 `NotebookShelfMovePrompt.moveDestination`
    /// 同一条口径：**认不出的笔记本** / **认不出的目标架**（**不兜底到默认架**）/ **已经在该架**。
    @discardableResult
    public func move(notebookUid: String, toShelf shelfUid: String) throws -> Notebook? {
        let directory = try notebookDirectory()
        guard let notebook = directory.notebook(uid: notebookUid),
              directory.shelf(uid: shelfUid) != nil,
              notebook.shelfUid != shelfUid else { return nil }
        var moved = notebook
        moved.shelfUid = shelfUid
        moved.sortOrder = directory.nextSortOrder(inShelf: shelfUid)
        try upsert(moved)
        return moved
    }

    /// 归属对（`uuid` ↔ `notebook_uid`）。顺序与 `notes()` 同口径（最近更新在前），
    /// 这样「按笔记本过滤」的结果与不过滤时的相对次序一致。
    public func placements() throws -> [NotebookPlacement] {
        try connection
            .query("SELECT uuid, notebook_uid FROM note ORDER BY updated_at DESC, title ASC")
            .compactMap { row in
                guard let uuid = row.text("uuid") else { return nil }
                return NotebookPlacement(noteID: uuid, notebookUid: row.text("notebook_uid"))
            }
    }

    /// 一条笔记的归属（缺归属 = `nil`）。
    public func notebookUid(of id: UUID) throws -> String? {
        try connection.scalarText("SELECT notebook_uid FROM note WHERE uuid = ?", [.text(id.uuidString)])
    }

    /// **缺归属**的笔记条数（`NULL` / 空串）。迁移与判据用它自证「没有无归属笔记」——
    /// 这一条是可量的事实，不是「我以为回填过了」。
    public func unassignedNoteCount() throws -> Int {
        Int(try connection.scalarInt("SELECT count(*) FROM note WHERE notebook_uid IS NULL OR notebook_uid = ''") ?? 0)
    }

    /// 把若干条笔记移到目标笔记本。返回**真正被改动**的行数。
    ///
    /// 两条纪律：① 目标 uid **认不出就落默认笔记本**（走 `NotebookDirectory.resolvedNotebookUid`，
    /// 与列表 / 过滤同一处兜底）；② **不碰 `updated_at`** —— 契约 §2.12 第 4 条：
    /// 移动不属于「编辑正文」，不构成一次内容更新。
    @discardableResult
    public func move(noteIDs: [UUID], toNotebook notebookUid: String) throws -> Int {
        guard !noteIDs.isEmpty else { return 0 }
        let target = try notebookDirectory().resolvedNotebookUid(notebookUid)
        let placeholders = Array(repeating: "?", count: noteIDs.count).joined(separator: ", ")
        var bindings: [SQLiteValue] = [.text(target)]
        bindings.append(contentsOf: noteIDs.map { SQLiteValue.text($0.uuidString) })
        try connection.execute(
            "UPDATE note SET notebook_uid = ? WHERE uuid IN (\(placeholders))",
            bindings
        )
        return noteIDs.count
    }

    /// **一次性归属迁移 + 幂等补缺**（队列 `L-97` 第二片的「旧数据迁移」那一半）。
    ///
    /// 三件事，全在一个事务里：① 没有默认架 ⇒ 建一个；② 没有默认笔记本 ⇒ 建一个（挂在默认架上）；
    /// ③ 缺归属（`NULL` / 空串 / **认不出的 uid**）的笔记一律落默认笔记本。
    ///
    /// 名字由**调用方给**（Core 不许写死文案 —— 默认容器的名字是要落库、要显示给用户的**数据**）。
    /// 幂等：第二次调用时三条都不匹配任何行 ⇒ 库一个字节都不变（单测按 `uid` 与条数逐项对账）。
    @discardableResult
    public func ensureDefaultContainers(
        shelfName: String,
        notebookName: String,
        now: Date = Date()
    ) throws -> NotebookDirectory {
        try connection.transaction {
            var directory = try notebookDirectory()
            if directory.defaultShelf == nil {
                try upsert(Shelf(name: shelfName, sortOrder: directory.shelves.count, createdAt: now, isDefault: true))
                directory = try notebookDirectory()
            }
            if directory.defaultNotebook == nil {
                let shelfUid = directory.defaultShelf!.uid
                try upsert(
                    Notebook(
                        shelfUid: shelfUid,
                        name: notebookName,
                        sortOrder: directory.notebooks(inShelf: shelfUid).count,
                        createdAt: now,
                        isDefault: true
                    )
                )
                directory = try notebookDirectory()
            }
            let defaultNotebookUid = directory.defaultNotebook!.uid
            try connection.execute(
                """
                UPDATE note SET notebook_uid = ?
                WHERE notebook_uid IS NULL OR notebook_uid = ''
                   OR notebook_uid NOT IN (SELECT uid FROM notebook);
                """,
                [.text(defaultNotebookUid)]
            )
        }
        return try notebookDirectory()
    }

    // MARK: - 快照备份

    /// 生成时间戳命名的快照文件名（`notes-20260927T143000.sqlite3`）—— 不覆盖上一次的备份。
    public static func snapshotFileName(at date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0) ?? .gmt, from: date)
        components.calendar = calendar
        let stamp = String(
            format: "%04d%02d%02dT%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
        return "notes-\(stamp).sqlite3"
    }

    /// **快照备份**（`FR-PLUG-08`：备份口径 = 快照，不是同步活跃库文件）。
    ///
    /// 为什么必须是 `VACUUM INTO` 而不是"拷一份库文件"：WAL 模式下已提交的数据可能还只在 `-wal` 里，
    /// 裸拷 `notes.sqlite3` 会拿到**缺最后若干事务**的一份；而云同步盘在文件写到一半时抓到的更是半份。
    /// `VACUUM INTO` 由 SQLite 自己产出一份**事务一致、已压缩、单文件**的副本。
    ///
    /// 三步都是硬要求：① 先 `wal_checkpoint(TRUNCATE)`（把 WAL 并回主库，快照读的就是全部已提交数据）；
    /// ② 写到 `.partial` 再改名（**中途失败不留半个"备份"** —— 比没有备份更危险的是以为有）；
    /// ③ 写完**读回来核对**（行数 + `integrity_check`），核对不过就当没成功。
    @discardableResult
    public func snapshot(to url: URL, fileManager: FileManager = .default) throws -> NoteSnapshot {
        guard !fileManager.fileExists(atPath: url.path) else {
            throw NoteStorageFailure.snapshotTargetExists(url.path)
        }
        try connection.setPragma("wal_checkpoint(TRUNCATE)")

        let partial = url.appendingPathExtension("partial")
        if fileManager.fileExists(atPath: partial.path) {
            // `.partial` 是我们自己的中间件（上次失败留下的），删掉不涉及用户数据。
            try? fileManager.removeItem(at: partial)
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // `VACUUM INTO` 的目标路径**不能用参数绑定**（不是普通表达式位置），所以只能是字面量；
        // 于是这里的转义是安全边界：单引号翻倍，路径里的 `'` 不会截断语句。
        let literal = partial.path.replacingOccurrences(of: "'", with: "''")
        try connection.execute("VACUUM INTO '\(literal)'")

        // 读回来核对：备份没人验过就等于没有备份。
        let expectedCount = try noteCount()
        let restored = try NoteDatabase(path: partial.path)
        let restoredCount = try restored.noteCount()
        let integrity = try restored.integrityCheck()
        let restoredVersion = restored.userVersion
        try restored.close()
        guard restoredCount == expectedCount, integrity == "ok" else {
            try? fileManager.removeItem(at: partial)
            throw NoteStorageFailure.snapshotMismatch(
                "expected \(expectedCount) note(s) and integrity ok, got \(restoredCount) and \(integrity)"
            )
        }

        try fileManager.moveItem(at: partial, to: url)
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return NoteSnapshot(
            url: url,
            byteCount: size,
            noteCount: restoredCount,
            schemaVersion: restoredVersion,
            integrity: integrity
        )
    }

    // MARK: - 内部

    private func requireRowID(of id: UUID) throws -> Int64 {
        guard let rowID = try connection.scalarInt("SELECT id FROM note WHERE uuid = ?", [.text(id.uuidString)]) else {
            // 调用方自己的前置条件被破坏（先写后取、或删了还在用）：这是程序错误，用断言式的失败说清楚。
            throw SQLiteFailure(
                code: SQLiteResultCode.error,
                message: "no note row for uuid \(id.uuidString)",
                operation: .step,
                sql: "SELECT id FROM note WHERE uuid = ?"
            )
        }
        return rowID
    }

    /// 任务表的 rowid（与 `requireRowID(of:)` 同一条纪律：拿不到就是程序错误，断言式失败）。
    private func requireTodoRowID(of id: UUID) throws -> Int64 {
        guard let rowID = try connection.scalarInt("SELECT id FROM todo WHERE uuid = ?", [.text(id.uuidString)]) else {
            throw SQLiteFailure(
                code: SQLiteResultCode.error,
                message: "no todo row for uuid \(id.uuidString)",
                operation: .step,
                sql: "SELECT id FROM todo WHERE uuid = ?"
            )
        }
        return rowID
    }

    /// 提醒表的 rowid（同上：拿不到就是程序错误，断言式失败）。
    private func requireReminderRowID(of id: UUID) throws -> Int64 {
        guard let rowID = try connection.scalarInt("SELECT id FROM reminder WHERE uuid = ?", [.text(id.uuidString)]) else {
            throw SQLiteFailure(
                code: SQLiteResultCode.error,
                message: "no reminder row for uuid \(id.uuidString)",
                operation: .step,
                sql: "SELECT id FROM reminder WHERE uuid = ?"
            )
        }
        return rowID
    }

    /// 提醒的取行语句（**一处**）：两个归属列各自 LEFT JOIN 出 uuid —— 归属那一行的 uuid
    /// 才是调用方认的东西（`note_id` / `todo_id` 是本端的 rowid，出了这一层没有意义）。
    private static let reminderSelect = """
        SELECT r.uuid AS uuid, r.rule AS rule, r.anchor_date AS anchor_date,
               r.minute_of_day AS minute_of_day, r.interval_count AS interval_count,
               r.interval_unit AS interval_unit, r.weekdays AS weekdays, r.until_date AS until_date,
               r.created_at AS created_at, r.updated_at AS updated_at,
               n.uuid AS note_uuid, t.uuid AS todo_uuid
        FROM reminder r
        LEFT JOIN note n ON n.id = r.note_id
        LEFT JOIN todo t ON t.id = r.todo_id
        """

    /// 行 → `Reminder`（每一列都在这里被读一次；归属那一行没了的行**抛错不降级**）。
    private func reminders(from sql: String, _ bindings: [SQLiteValue] = []) throws -> [Reminder] {
        try connection.query(sql, bindings).map { row in
            guard let uuidText = row.text("uuid"), let uuid = UUID(uuidString: uuidText) else {
                throw SQLiteFailure(
                    code: SQLiteResultCode.mismatch,
                    message: "reminder row has no usable uuid",
                    operation: .step
                )
            }
            let owner: ReminderOwner
            if let noteText = row.text("note_uuid"), let noteID = UUID(uuidString: noteText) {
                owner = .note(noteID)
            } else if let todoText = row.text("todo_uuid"), let todoID = UUID(uuidString: todoText) {
                owner = .todo(todoID)
            } else {
                // 归属那一行没了（本该被 `ON DELETE CASCADE` 拦住）：**抛错不降级** ——
                // 一条「没有主人」的提醒到点会弹，而用户在界面上找不到它。
                throw SQLiteFailure(
                    code: SQLiteResultCode.mismatch,
                    message: "reminder row has no live owner",
                    operation: .step
                )
            }
            return Reminder(
                id: uuid,
                owner: owner,
                spec: ReminderSpec(
                    rule: row.text("rule") ?? "",
                    anchorDate: row.text("anchor_date") ?? "",
                    minuteOfDay: Int(row["minute_of_day"].intValue ?? -1),
                    intervalCount: Int(row["interval_count"].intValue ?? 0),
                    intervalUnit: row.text("interval_unit") ?? "",
                    weekdays: ReminderSpec.weekdays(from: row.text("weekdays") ?? ""),
                    untilDate: row.text("until_date") ?? ""
                ),
                createdAt: Date(timeIntervalSince1970: row["created_at"].doubleValue ?? 0),
                updatedAt: Date(timeIntervalSince1970: row["updated_at"].doubleValue ?? 0)
            )
        }
    }

    private func todos(from sql: String, _ bindings: [SQLiteValue] = []) throws -> [Todo] {
        let rows = try connection.query(sql, bindings)
        guard !rows.isEmpty else { return [] }
        let rowIDs = rows.compactMap { $0.int("id") }
        var tagsByRow: [Int64: [String]] = [:]
        if !rowIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: rowIDs.count).joined(separator: ", ")
            let tagRows = try connection.query(
                "SELECT todo_id, tag FROM todo_tag WHERE todo_id IN (\(placeholders)) ORDER BY tag ASC",
                rowIDs.map { SQLiteValue.integer($0) }
            )
            for row in tagRows {
                guard let todoID = row.int("todo_id") else { continue }
                tagsByRow[todoID, default: []].append(row.text("tag") ?? "")
            }
        }
        return try rows.map { row in
            guard let uuidText = row.text("uuid"), let uuid = UUID(uuidString: uuidText) else {
                throw SQLiteFailure(
                    code: SQLiteResultCode.mismatch,
                    message: "todo row has no usable uuid",
                    operation: .step
                )
            }
            // **`priority` 认不出不抛错**：`TodoPriority(raw:)` 归一成 `.normal`（「当没给」）——
            // 与 `materialize` 里 `source_kind` 认不出就抛刻意不同（那一处是数据损坏，这一处是别端多一档）。
            return Todo(
                id: uuid,
                title: row.text("title") ?? "",
                dueAt: row["due_at"].doubleValue.map { Date(timeIntervalSince1970: $0) },
                done: row["done"].intValue == 1,
                completedAt: row["completed_at"].doubleValue.map { Date(timeIntervalSince1970: $0) },
                priority: TodoPriority(raw: row.text("priority") ?? ""),
                tags: tagsByRow[row.int("id") ?? 0] ?? [],
                note: row.text("note") ?? "",
                createdAt: Date(timeIntervalSince1970: row["created_at"].doubleValue ?? 0),
                updatedAt: Date(timeIntervalSince1970: row["updated_at"].doubleValue ?? 0)
            )
        }
    }

    private func notes(from sql: String, _ bindings: [SQLiteValue] = []) throws -> [Note] {
        try materialize(try connection.query(sql, bindings))
    }

    /// 行 → `Note`（**一行的所有列都在这里被读一次**；读不认识的值时抛错，不降级）。
    ///
    /// 标签单独一句查（`IN` 列表按 rowid 批量取），避免每行一条 `SELECT` 的 N+1。
    private func materialize(_ rows: [SQLiteRow]) throws -> [Note] {
        guard !rows.isEmpty else { return [] }
        let rowIDs = rows.compactMap { $0.int("id") }
        var tagsByRow: [Int64: [String]] = [:]
        if !rowIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: rowIDs.count).joined(separator: ", ")
            let tagRows = try connection.query(
                "SELECT note_id, tag FROM note_tag WHERE note_id IN (\(placeholders)) ORDER BY tag ASC",
                rowIDs.map { SQLiteValue.integer($0) }
            )
            for row in tagRows {
                guard let noteID = row.int("note_id") else { continue }
                tagsByRow[noteID, default: []].append(row.text("tag") ?? "")
            }
        }
        return try rows.map { row in
            guard let uuidText = row.text("uuid"), let uuid = UUID(uuidString: uuidText) else {
                throw SQLiteFailure(
                    code: SQLiteResultCode.mismatch,
                    message: "note row has no usable uuid",
                    operation: .step
                )
            }
            let kindText = row.text("source_kind") ?? ""
            guard let rawKind = NoteSource.Kind(rawValue: kindText) else {
                throw NoteStorageFailure.unknownSourceKind(kindText)
            }
            return Note(
                id: uuid,
                title: row.text("title") ?? "",
                body: row.text("body") ?? "",
                tags: tagsByRow[row.int("id") ?? 0] ?? [],
                source: NoteSource(
                    kind: rawKind,
                    connectionName: row.text("source_connection_name"),
                    fingerprint: row.text("source_fingerprint"),
                    capturedAt: Date(timeIntervalSince1970: row["source_captured_at"].doubleValue ?? 0)
                ),
                createdAt: Date(timeIntervalSince1970: row["created_at"].doubleValue ?? 0),
                updatedAt: Date(timeIntervalSince1970: row["updated_at"].doubleValue ?? 0),
                containsRowData: row["contains_row_data"].intValue == 1,
                isFavorite: row["favorite"].intValue == 1,
                isPinned: row["pinned"].intValue == 1
            )
        }
    }
}

/// 时间线上这类动作的 `kind` 取值（写成常量而不是散在调用点的字面量 —— 检索与展示都要按它筛）。
public enum NoteTimelineKind {
    public static let upsert = "upsert"
    public static let delete = "delete"
    public static let attachment = "attachment"
    public static let migrate = "migrate"
}
