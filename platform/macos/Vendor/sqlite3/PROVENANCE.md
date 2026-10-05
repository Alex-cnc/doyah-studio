# Vendor/sqlite3 —— 来源、版本与升级方式

笔记存储换成 SQLite 之后（需求规范书 `FR-PLUG-08`，2026-09-27 拍板 Q23），这个目录就是
**三端唯一的 SQLite 来源**：macOS / Windows / Linux 编的是**同一份 `sqlite3.c`**，
所以「平台间行为一致」不再是承诺，而是「同一份源码 + 同一组编译宏」的结果。

## 一、这一份是什么

| 项 | 值 |
|---|---|
| 组件 | SQLite amalgamation（可交付源码，公有领域） |
| 版本 | **3.53.4**（`SQLITE_VERSION_NUMBER` = 3053004） |
| `SQLITE_SOURCE_ID` | `2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc` |
| 下载地址 | `https://sqlite.org/2026/sqlite-amalgamation-3530400.zip`（取自 <https://sqlite.org/download.html>） |
| 归档 SHA-256 | `1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d` |
| 取回日期 | 2026-09-27 |
| 许可 | 公有领域（见同目录 `LICENSE.txt`） |

带进仓库的**只有编译需要的两个文件**（字节与官方归档逐字节一致）：

| 文件 | 字节数 | SHA-256 |
|---|---|---|
| `sqlite3.c` | 9515341 | `b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189` |
| `sqlite3.h` | 690838 | `919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d` |

归档里另外两个文件**刻意不带进来**（不是漏了）：

- `shell.c` —— SQLite 自己的命令行工具，不是库的一部分，产品里用不到（我们的命令行是 `DoyahCLI`）；
- `sqlite3ext.h` —— 只有写「可加载扩展」才需要，而本工程的编译宏里**关掉了扩展加载**
  （`SQLITE_OMIT_LOAD_EXTENSION=1`）。

`Scripts/check-vendored-sqlite.py` 会对**文件集合**对账：这个目录里多出任何一个文件都会报红
（否则「顺手放一份别的版本的 sqlite3.c 进来」就是绕过版本对账的暗道）。

## 二、编译宏（写在 `Package.swift` 的 `CSQLite3` 目标上）

| 宏 | 为什么 |
|---|---|
| `SQLITE_THREADSAFE=1` | 序列化模式：连接可能被多个线程碰到（宿主是多线程的），这一档不靠调用方自觉 |
| `SQLITE_ENABLE_FTS5=1` | `FR-PLUG-08` 的四条判据之一就是「要按条件查与全文检索」，FTS5 不在默认编译里 |
| `SQLITE_OMIT_LOAD_EXTENSION=1` | 不需要动态扩展加载（少一个 `dlopen` 面），也就不用带 `sqlite3ext.h` |
| `SQLITE_DQS=0` | 双引号不许当字符串字面量：把「列名写错」从**静默当成字符串**变成**当场报错** |

这四条被门禁逐个钉住（`requiredCompileOptions`）—— 少一条都报红，因为「宏掉了」这件事
在编译、打包、单测里**都不会有症状**，只有行为悄悄变掉（DQS 那条尤其典型：不报错、只是查询结果变得莫名其妙）。

## 三、怎么升级（换版本时照这个来）

```bash
# 1) 取源（脚本自己会校验归档 SHA-256、打印新文件的 SHA-256）
./Scripts/vendor-sqlite3.sh --version 3530500        # 例：换成 3.53.5
# 2) 把新版本号 / 归档哈希 / 各文件哈希 / SOURCE_ID 写进台账
#    Scripts/vendored-sqlite.json（门禁拿它逐字节对账，不更新就报红）
python3 Scripts/check-vendored-sqlite.py
# 3) 复跑单测与闭环
./Scripts/verify-core.sh && ./Scripts/verify-all.sh
```

**升级前先想清楚**：`3.x` 之间偶有行为变化（例如 `PRAGMA` 默认值、`UPSERT` 细节）。
笔记库是用户数据，升版本要连带跑一遍 `Tests/SQLiteTests.swift` 的往返与事务用例，
以及 `FR-PLUG-08` 的迁移用例（把老库读一遍）。
