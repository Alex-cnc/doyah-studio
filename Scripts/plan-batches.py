#!/usr/bin/env python3
"""按台账/队列重出「批次队列」`.agent/batches.yaml`（v0.4.0 起连 `.agent/plan.yaml` 一起重出）。

为什么要有这个脚本：批次划分是**派生件**，台账一改（某条收口了）批次就得跟着改。
手改一定会漂，所以划分规则写在这里、文件由脚本产出。

用法：
    python3 Scripts/plan-batches.py --check                 # 只比对，不写盘；不一致 rc=1（默认按 0.7.0 对账）
    python3 Scripts/plan-batches.py --write                 # 重出 batches.yaml
    python3 Scripts/plan-batches.py --emit-plan --write     # 先按台账重出 plan.yaml，再重出批次
    python3 Scripts/plan-batches.py --version 0.4.0 --check # 历史版（只比 batches.yaml ↔ plan.yaml）

覆盖声明（**分版本，别混**）：
- `--version 0.7.0`（默认，当前版）**读台账**。范围 = 台账里「未闭但不在 §4.2 任何里程碑队列里」的 17 条
  **全号**（笔记 10 / 工作区 3 / 发布门槛 3 / 数据库 1；派生依据见 `.agent/next-version.md` §v0.7.0），
  且状态未 ✅。卡点由 `BLOCKED_V070` 写死（10 条：嵌入端点 / 真云 / 人工点验 / 主人拍板 / 无真 PG / GBase 挂起 / 另两端）。
- `--version 0.6.0`（历史）**读台账**。范围 = 台账 §4.2 v0.6.0 那一行点名的 21 条**全号**
  （授权 6 / 插件 2 / 性能 4 / 兼容 5 / 界面·可用性·安全·国际化 4），且状态未 ✅；
  卡点由 `BLOCKED_V060` 写死（5 条卡实例：Linux 端归小河马、PG 12–18 / GBase / MySQL 版本窗 / 局域网 DB）。
- `--version 0.5.0`（历史）**读台账**。范围 = 台账 §4.2 那一行点名的前缀与具名条目
  （`FR-AGT-TOOL-*` / `FR-AGT-UX-*` / `FR-AGT-LINK-EXT-*` + `OPS-OBS-002` / `PLAN-PLAN-001` /
  `LINK-CHAN-003` / `KNOW-MEM-003` / `NFR-ALL-GATE-AI-004·006·007` / `AC-ALL-GATE-AI-001·004`），
  且状态未 ✅。卡点由 `BLOCKED_V050` **写死在规则表里**（台账 §7.1 的十条外部卡点），
  `--emit-plan` 重出时保留 `status: blocked` + `next_try`，不刷回 todo；上一版遗留卡点跨版本携带、只列表可见。
- `--version 0.4.0`（历史，需把 `plan.yaml` 切回那一版）范围 = `FR-NTS-NOTE-*` / `FR-NTS-TODO-*` 未 ✅。
  `--check` 做两件事：① `plan.yaml` 的 todo 集合 == 台账复算集合（缺一条 / 多一条 / 台账已闭而队列仍 todo，都判红）；
  ② `batches.yaml` == 按 `plan.yaml` 重出的结果，且没有条目掉进「未归堆」。
- `--version 0.3.0`（历史）只认 `plan.yaml` 的 `- id:` / `status:` 两列，**不读台账** ——
  那一版队列 35 条与台账 111 条 DB 行不是同一集合，拿台账复算会误报；要复算它得先切回历史的 `plan.yaml`。
"""

from __future__ import annotations

import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / ".agent" / "plan.yaml"
OUT = ROOT / ".agent" / "batches.yaml"
LEDGER = ROOT / "Docs" / "Doyah产品开发计划任务清单-macOS.md"

# --------------------------------------------------------------------------- #
# v0.3.0（历史）：数据库运维面，B1–B7
# --------------------------------------------------------------------------- #
BATCHES_V030: list[dict] = [
    dict(
        id="B1",
        title="快速收口：老底子齐了的 5 条（第一片 TASK-003 已收口，余 4 条）",
        est_min=35,
        match=["FR-STD-DB-TASK-001", "FR-STD-DB-TASK-002", "FR-STD-DB-TASK-003",
               "FR-STD-DB-IO-002", "FR-STD-DB-META-006"],
        why="Core + 测试 + App 引用三件已齐（TASK 三条）或只有测试差接线（IO-002 / META-006）"
            " ⇒ 只补点验与接线，不重写功能。**第一片实测纠正了这句的一半**：TASK 三条的入口"
            "（工具栏菜单 / 审批单 / 回执页三枚动作）是 SwiftUI 控件，离屏宿主里不落 `NSButton`、"
            "无障碍树也不构建 ⇒ 点不到就量不到，收口前得先把入口换成真 AppKit 控件"
            "（TASK-003 已按 `PanelIconButton` 办完）；IO-002 的入口是生产右键菜单（AppKit，已有探针），"
            "META-006 的「重试」还是 SwiftUI 文字按钮",
        exit="余 4 行两列全 ✅；证据一段式（第一片：`.agent/evidence/2026-11-01-B1-TASK-003.md`）",
    ),
    dict(
        id="B2",
        title="结果面收尾：分页 / 筛选 / 流式落盘 / 导出 Excel",
        est_min=50,
        match=["FR-STD-DB-RES-"],
        why="同属 ResultView 一族，探针共用同一套视图夹具，一起改一次跑；"
            "RES-006/007/008 刚在这条线上做过，上下文还热",
        exit="4 行两列全 ✅；结果面视图探针一批跑完",
    ),
    dict(
        id="B3",
        title="元数据面：跨库浏览 / 分组视图 / 对象搜索 / 查看 DDL",
        est_min=60,
        match=["FR-STD-DB-META-"],
        why="五条都在对象树上（层级 / 分组 / 搜索 / 下钻 / 取 DDL），同一棵树改一次比拆五次省一半",
        exit="5 行两列全 ✅；对象树探针一批跑完",
    ),
    dict(
        id="B4",
        title="导入导出：pg_dump/restore / 恢复到指定库 / CSV·JSON 导入 / xlsx 向导",
        est_min=50,
        match=["FR-STD-DB-IO-"],
        why="四条共用 IO 执行器与进度回执，命令拼装可一次写完",
        exit="4 行两列全 ✅；含一条「命令拼错必判红」反例",
    ),
    dict(
        id="B5",
        title="会话与诊断：会话列表 / 取消终止 / 服务器级对象 / 慢查询 / 统计面板 / DIAG-006",
        est_min=70,
        match=["FR-STD-DB-SESS-", "FR-STD-DB-DIAG-"],
        why="全部走 pg_stat_* / pg_cancel_backend 一类系统视图，查询层同构；"
            "DIAG-006 是唯一 ⬜，同批补需求定义",
        exit="6 行两列全 ✅；DIAG-006 先补定义行再判",
    ),
    dict(
        id="B6",
        title="数据编辑与表结构：count(*) / 单元格编辑器 / 外键导航 / 结构编辑器 / Schema 对比",
        est_min=60,
        match=["FR-STD-DB-DATA-", "FR-STD-DB-DDL-"],
        why="都围绕表/列的元数据读写，DDL 生成器一条链；DDL-003 与 DDL-004 共用同一份差异模型",
        exit="5 行两列全 ✅；DDL 生成用例含「不许猜列类型」反例",
    ),
    dict(
        id="B7",
        title="连接与驱动：连接分组 / SSH 隧道 / GBase 8a 驱动",
        est_min=45,
        match=["FR-STD-DB-CONN-", "FR-STD-DB-DRV-"],
        why="连接层同一处改：分组是配置结构、SSH 隧道是连接前段、GBase 是协议族复用",
        exit="3 行两列全 ✅；SSH 隧道允许只落「本机无跳板机」的如实未知",
    ),
]

# --------------------------------------------------------------------------- #
# v0.4.0：笔记与任务闭环，N1–N3（原计划 N1–N4，实测 14 条的分布后合成 3 批，见 why）
# --------------------------------------------------------------------------- #
BATCHES_V040: list[dict] = [
    dict(
        id="N1",
        title="笔记面收尾：采集 / 附件 / 笔记本归属 / 同步冲突",
        est_min=70,
        match=["FR-NTS-NOTE-CAPTURE-001", "FR-NTS-NOTE-ATTACH-001",
               "FR-NTS-NOTE-ORG-002", "FR-NTS-NOTE-SYNC-002"],
        why="剩下四条都在笔记这本身上（一个动作记下 / 附件引用 / 笔记本归属 / 记录级 LWW 留两版），"
            "共用 `NotesLibrary` + 同一份检索与同步口径 ⇒ 一次改到位比一条一跳省手续费。"
            "2026-11-02 第一片已收 `VERSION-001`（历史版本）与 `PRIVACY-001`（私密保护），"
            "所以 N1 从 6 条降到 4 条；其中 `ORG-002` 是**判据互斥**（需求书 §3.5 要单层、"
            "契约 §2.12 与已上盘的两层结构是架→笔记本）⇒ 标 blocked 等契约所有者裁决，"
            "不许在本批里自己拆表。",
        exit="4 行里能动的 3 条两列全 ✅（`ORG-002` 记 blocked + 理由 + next_try）；"
             "每条的证据必须是探针或单测读数（`ledger-row.py <ID>` 出现 ✅ 只算抽查）",
    ),
    dict(
        id="N2",
        title="待办条目：本体 / 清单视图 / 组织检索 / 与笔记双向转化",
        est_min=70,
        match=["FR-NTS-TODO-LIST-001", "FR-NTS-TODO-LIST-002", "FR-NTS-TODO-LIST-003",
               "FR-NTS-TODO-LINK-001"],
        why="四条都是「一条待办记录本身」的读写（字段 / 列表增删改排序 / 分组筛选排序 / 与笔记互转带回指），"
            "同一个模型与同一套同步，拆开做会重复写迁移",
        exit="4 行两列全 ✅；含一条「任务与笔记互转后回指可撤销」的反例",
    ),
    dict(
        id="N3",
        title="待办日历与状态一致性：月/周视图 / 当天详情 / 完成与改期同一事务 / 单一事实源",
        est_min=60,
        match=["FR-NTS-TODO-CALENDAR-001", "FR-NTS-TODO-CALENDAR-002",
               "FR-NTS-TODO-STATE-001", "FR-NTS-TODO-STATE-002"],
        why="四条互相咬：日历只是同一份任务的第二种视图，所以「完成 / 改期同一事务」与「日历不另存」"
            "必须同批落地，否则先做日历就会做出第二套状态",
        exit="4 行两列全 ✅；含一条「日历另存一份 ⇒ 必须判红」的反例",
    ),
]

# --------------------------------------------------------------------------- #
# v0.5.0：智能体进阶层，A1–A2（16 条未闭里只有 6 条是「自己能开工」的，见 BLOCKED_V050）
# --------------------------------------------------------------------------- #
BATCHES_V050: list[dict] = [
    dict(
        id="A1",
        title="智能体闸门：总开关零外发 / 提示注入不执行 / 配额与超时",
        est_min=70,
        match=["AC-ALL-GATE-AI-001", "AC-ALL-GATE-AI-004", "NFR-ALL-GATE-AI-004"],
        why="三条都是「拦住它别乱来」的同一族：外发口、指令来源、花费上限 —— 判据都要在一个"
            "外发/执行收口处读手数，分开做会把同一根探针写三遍",
        exit="3 行两列全 ✅；每条配一条「故意违规必须判红」的负例（关总开关仍发 / 注入内容被当指令 / 超配额仍发）",
    ),
    dict(
        id="A2",
        title="上下文与端点：记忆可检视删解释 / 本地 OpenAI 兼容端点 / 会话持久化与长上下文",
        est_min=70,
        match=["FR-AGT-KNOW-MEM-003", "NFR-ALL-GATE-AI-006", "NFR-ALL-GATE-AI-007"],
        why="三条都在「一次对话前后用什么上下文、连谁」这一层：记忆写入与界面、端点预填与本地档、"
            "超限压缩与续跑位置；共用 `AgentMemoryStore` / `AgentModelPresets` / 压缩那条路",
        exit="3 行两列全 ✅；记忆写入要有真调用点（不是只有测试调）",
    ),
]

# --------------------------------------------------------------------------- #
# v0.6.0：横切面收口，C1–C4（21 条未闭里 14 条机器面能做，7 条卡外部实例 / 契约口径，见 BLOCKED_V060）
# --------------------------------------------------------------------------- #
BATCHES_V060: list[dict] = [
    dict(
        id="C1",
        title="授权与版本呈现：解析 / 能力位 / 版本页 / 到期降级 / 范围口径 / 设备 / 工作区入口",
        est_min=80,
        match=["FR-STD-ALL-LIC-001", "FR-STD-ALL-LIC-002", "FR-STD-ALL-LIC-003",
               "FR-STD-ALL-LIC-004", "FR-STD-ALL-LIC-005", "FR-STD-WS-LIC-001"],
        why="六条读的是同一份 `License` 模型与同一张能力位表：解析（001）/ 按位呈现（002）/ 到期降级（003）/"
            "范围口径（004）/ 设备配额（005）/ 工作区里的授权呈现（WS-LIC-001）。拆开做会把同一份能力位"
            "写六遍，而且 001 与 004 的「哪些算一套」如果各写一份，`WS-LIC-001` 必然与它们对不上。",
        exit="6 行两列全 ✅；每条配一条「故意违规必须判红」的负例"
             "（坏签名被认 / 未授权入口仍出现 / 到期把数据锁住 / 移动端被纳入管辖 / 第 6 台仍激活 / 工作区越权入口可点）",
    ),
    dict(
        id="C2",
        title="性能读数表：冷启动 ≤ 2 s / 1 万行 × 20 列不卡 / 10 万行不 OOM",
        est_min=70,
        match=["NFR-ALL-GATE-PERF-001", "NFR-ALL-GATE-PERF-002", "NFR-ALL-GATE-PERF-003"],
        why="三条都是「本机能量出来的量化门槛」，共用一套采样与阈值台账"
            "（先例 = `Scripts/result-scroll-baseline.json` + `check-result-scroll-ledger.py`：阈值只有一处，"
            "探针读它、不写魔数）。分开做会写三份魔数、三台仪器。",
        exit="3 行两列全 ✅ + 一份性能读数表（阈值 / 实测值 / 基准环境）；"
             "每条配负例（人为拖慢 ⇒ 必须判红），未达阈值的如实记实测值而不是改成通过",
    ),
    dict(
        id="C3",
        title="平台兼容与笔记存储统一：部署目标 14.0 / arm64 + x86_64 / 桌面各端一条 SQLite",
        est_min=70,
        match=["NFR-ALL-GATE-COMP-004", "NFR-ALL-GATE-COMP-005", "FR-STD-ALL-PLUG-008"],
        why="三条问的是同一件事的两面：「同一份代码换台机器还得成立」。部署目标（14.0，`project.yml` 与 "
            "`Package.swift` 已有）与双架构（arm64 + x86_64 同一条构建）是编译期可判的；"
            "`PLUG-008` 是「桌面各端只落一条本地 SQLite」——判的是存储面唯一，不是界面。",
        exit="3 行两列全 ✅；真 macOS 14 / 15、真 Intel 机、Windows / Linux 端**单列未知**（不许折算成通过）",
    ),
    dict(
        id="C4",
        title="横切口径：统一外发日志 / 走不动的动作三选一 / 简体中文界面 / 设计语言统一",
        est_min=80,
        match=["NFR-ALL-GATE-SEC-008", "NFR-ALL-GATE-USE-005",
               "NFR-ALL-GATE-LANG-001", "NFR-ALL-GATE-UI-001"],
        why="四条都不是某一块功能，而是「所有面上都得守的同一条规矩」：出网必留痕、走不动必须挑一种处置、"
            "界面中文、设计语言同一套令牌。判据形状也同构 —— 静态对账 + 一份全量读数表（扫全仓，不是抽一处）。",
        exit="4 行两列全 ✅；每条配「故意违反必判红」的负例（出网不留痕 / 满亮可点且静默 / 英文漏到界面 / "
             "硬编码颜色绕过令牌）；跨端那部分（Windows / iOS / 安卓）单列未知",
    ),
]

# --------------------------------------------------------------------------- #
# v0.7.0：余账收口，D1–D2
#
# 为什么会有这一版：§4.2 六个里程碑的**条数**是 2026-11-01 的读数，之后没跟版。
# 2026-11-02 按台账逐行复算（脚本见 `Scripts/check-plan-coverage.py` 口径，本跳手算并留读数）：
# 本仓未闭 35 条，而六个里程碑行加起来写 46 条 —— v0.3.0 写 22（实算 1，DB 域 136 行里 134 ✅ +
# 1 `✅（` + 1 ➖）、v0.4.0 写 1（实算 7）、v0.2.0 写 0（实算 3）、`FR-NTS-ALL-HOME-001`（未排期）1 条
# 没有任何里程碑收它。⇒ 这 17 条**已经在台账里、只是不在任何队列里**；本版只把它们归堆，
# **不新增需求**（不许自己发明）。
# --------------------------------------------------------------------------- #
BATCHES_V070: list[dict] = [
    dict(
        id="D1",
        title="笔记的撤与删：撤销粒度 / 批量删可撤 / 回收站与彻底清除",
        est_min=80,
        match=["FR-NTS-NOTE-FORMAT-001", "FR-NTS-NOTE-ORG-001", "FR-NTS-NOTE-TRASH-001"],
        why="三条落在同一条线上：格式条缺的是**撤销粒度**（`NotesRichTextEditor` 只 `allowsUndo`，"
            "没有 `breakUndoCoalescing` ⇒ 撤销按引擎默认而不是按段落）、整理条缺的是**批量删除的撤销栈**、"
            "删除条缺的是**回收站 / 恢复 / 到期彻底清除**。三条共用同一个 undo 栈与同一套墓碑存储，"
            "拆开做会写两份撤销记账（一份按段、一份按操作）。",
        exit="3 行两列全 ✅；每条配负例（一次 ⌘Z 只回退一段 / 批量删 100 条后 ⌘Z 必须回到删前 / "
             "恢复后正文逐字一致 / 到期清除必须真删且墓碑不外泄）",
    ),
    dict(
        id="D2",
        title="笔记的入口与出口 + 不设付费墙的判据 + 工作区文件按类别呈现",
        est_min=80,
        match=["FR-NTS-ALL-HOME-001", "FR-NTS-NOTE-EXPORT-001", "FR-NTS-ALL-LIC-001",
               "FR-STD-WS-FS-008"],
        why="四条都是「边界处的一条规矩」而不是新功能：默认落页（入口由用户显式二选一）、"
            "备份包与导入还原（出口要能把自己带回来，且包里有格式版本号）、"
            "不设付费墙（把「无内购 / 无订阅 / 无许可证校验」从口头事实变成脚本判据）、"
            "按文件类别呈现（图片等走各自视图，不再一律 `openAsText` 当二进制拒绝）。"
            "四条互不依赖，但都是「小口径 + 一条判据」的形状，合在一批省手续费。",
        exit="4 行两列全 ✅；每条配负例（未设置时落待办不许落笔记 / 导入导出的包必须逐字还原、"
             "少一条笔记就判红 / 塞一行 `StoreKit` 或 `BillingClient` 必须判红 / "
             "图片再走 `openAsText` 必须判红）",
    ),
]

# v0.7.0 的 10 条卡点：逐条都是本机读不出来的（实例 / 端点 / 另两端 / 主人拍板），
# 与 v0.6.0 同一纪律 —— blocked 必须带 next_try，不许用「做不了」三个字交差。
BLOCKED_V070: dict[str, str] = {
    "FR-NTS-NOTE-SEARCH-001": "① 语义检索要嵌入模型：本机无端点、无本地模型"
                             "（2026-11-02 实测 `grep -rn 'embedding|语义检索|向量' Plugins/Notes App Core` = 0 命中；"
                             "`agent.json` 有模型名 `deepseek-v4-flash` 但 apiKey 为空）⇒ 「两种检索并列」无从成立；"
                             "③ 万条检索性能读数要等 ① 的路定了才有意义",
    "FR-NTS-NOTE-SYNC-001": "⑥ 云端全量还原要可连的云同步服务（本机无账号；`NoteSyncE2ETests` 11 例要真云端，"
                           "历轮记「未执行」）；⑦「关掉同步后本机功能一个不少」可单出读数，"
                           "但本条判据要求 ①–⑦ 全 ✅ ⇒ 只能停在 ⑥",
    "FR-STD-WS-TOOL-001": "剩两处且都不是代码：sixel / kitty 图形按口径未做、多会话页签的界面待人工点验"
                         "（2026-11-02 复读台账状态原值）⇒ 机器面读不出「观感对」",
    "FR-STD-WS-AI-002": "许愿模式「先出改动后生效」要不要另设（不再逐条批）要主人拍板；`WishStaging` 暂存面未接线",
    "AC-ALL-GATE-REL-004": "要真实 PostgreSQL 端到端：本机无 pg 系（`command -v postgres` 空）、"
                          "217 主机不在线（2026-11-03 用 Python socket 复测：5432 超时 5 s / 3306 `No route to host` / 22 `Host is down`、ARP 无条目，而同网段网关 443 0.00 s 可连 ⇒ 那台机器没开，不是网段或凭据问题；可达性只认 TCP 握手，`ping`/`nc` 在本 shell 有假阴性，不作判据）",
    "AC-ALL-GATE-REL-005": "同上：错误密码 / 错误端口 / 不存在表 / 不合法 SQL 都要真服务器给回执，桩件回执不算",
    "AC-ALL-GATE-REL-006": "同上：崩溃零容忍要在真实全流程上跑，没真库就没有这条流程",
    "FR-STD-DB-META-002": "GBase 8a 按 2026-11-02 主人令挂起（台账记 ➖）：无法安装部署、暂不支持；"
                         "解挂条件 = 主人给出可连的 GBase 实例",
    "FR-NTS-ALL-DIST-001": "三端（安卓 / iOS / 鸿蒙）各要独立应用包与商店材料，本机只有 macOS ⇒ 分发与签名口径要主人定",
    "FR-NTS-ALL-PARITY-001": "「安卓为基准端」是端间承诺：差异要逐条登记进《平台对齐-移动端-以安卓为基准》，"
                            "另两端不在场 ⇒ 登记表核不了，标「等价」也没人对着看",
}

# v0.6.0 的 7 条卡点：5 条卡的是**实例**（2026-11-02 起跳逐条实测过本机），
# 另 2 条（LANG-001 / UI-001）卡的是**契约口径 / 判据口径**，见各自 next_try。
BLOCKED_V060: dict[str, str] = {
    "FR-STD-ALL-PLUG-005": "Linux 端按平台口径归小河马（2026-10-22 令：Linux 归 babyhippo，WSL 能直接编）；"
                           "本机是 macOS，装配与验收要点 ①③④ 不在这台机上做",
    "NFR-ALL-GATE-COMP-001": "等可连的 PostgreSQL 12–18 实例：本机无 postgres / pg_ctl / initdb / docker"
                             "（2026-11-02 实测 `/opt/homebrew/bin` 无 pg 系、`command -v postgres` 空），"
                             "217 主机不在线（2026-11-03 TCP 复测：5432 超时 5 s、22 `Host is down`，同网段网关 443 0.00 s 可连）⇒ 多版本回归无从跑",
    "NFR-ALL-GATE-COMP-002": "等 GBase 最新版 + GBase 8a 实例：与 `FR-STD-DB-META-002` 同一个卡点"
                             "（217 无 GBase，2026-11-02 复测整机不通）",
    "NFR-ALL-GATE-COMP-003": "口令在钥匙串但那条目的 ACL 只放行 DoyahStudio 本体（外部进程 `-w` 弹系统授权、实测挂住 180 s）："
                             "要主人终端亲跑一次 `DOYAH_MYSQL_CONNECTION=DemoMySQL DOYAH_MYSQL_DATABASE=doyah_test ./Scripts/test-mysql-real.sh` 并点「允许」；"
                             "或把这条自检搬进应用进程（ACL 天然放行，属代码活、须先排进队列）。实例本身在 192.168.5.26:3306（握手 8.4.10）",
    "NFR-ALL-GATE-PERF-004": "等可连的局域网数据库：本条量的是「元数据单层懒加载在局域网内 ≤ 1 s」，"
                             "本机无局域网 DB（217 主机不在线：2026-11-03 TCP 复测 5432 超时 5 s、22 `Host is down`、ARP 无条目，同网段网关 443 0.00 s 可连）⇒ 只能量回环，不报通过",
    # 卡的是**契约口径**与**判据口径**，不是判断力：两条的机器面读数都已在盘（见台账判据列），
    # 差的都不是「再写点代码」，分别要主人一句话 / 要一个跨端产物面。列 blocked 而不是留 todo，
    # 免得每一跳都把同一句「做不了」重跑一遍。
    "NFR-ALL-GATE-LANG-001": "① 与 `NFR-ALL-GATE-LANG-003` ② 互斥（前者要「首次启动默认简体中文」，后者要「默认跟随系统语言」，"
                             "系统语言是英文的机器上两条不能同真）⇒ 要主人拍一句哪条算数；②③④ 已有机器读数（`LanguagePreferenceTests` 5 例、"
                             "两档棘轮、菜单语言门禁），改口只需动 `Core/LanguagePreference.resolve` 一处",
    "NFR-ALL-GATE-UI-001": "①③ 已有读数（图标 + `.help` 89/89 · a 类文字按钮 11 → 0），缺的是 ② 与 ④ 的判据口径："
                           "②「同一呈现函数（禁止第二套）」要先把「什么算第二套」写成可扫的判据（现只有「同一动作 ⇒ 同一图标」间接承担）；"
                           "④「平台间对照表（逐行含成对截图）」要各端都能出图（Windows / iOS / 安卓 / 鸿蒙 / Linux 不在本机）⇒ 本侧只出得了 macOS 一侧",
}

# 台账 §7.1（2026-10-27 逐条核验）+ 各行备注已把卡点写死：这 10 条机器面做不了，
# 卡在主人 / 外部实例。队列里必须**看得见**它们 ⇒ 落 blocked + next_try（不是删掉）。
BLOCKED_V050: dict[str, str] = {
    "FR-AGT-UX-CONV-001": "端点与密钥已可用（`agent.json` = `deepseek-v4-flash` + `https://api.deepseek.com/v1`，本跳真调一次 HTTP 200 / total_tokens 44）⇒ 旧话「端点未配」作废；仍差真模型跑一段诊断（执行计划 / 慢查询 / 锁阻塞）+ 界面入口人工点一次",
    "FR-AGT-PLAN-PLAN-001": "端点与密钥已可用（同 `FR-AGT-UX-CONV-001` 那次真调，HTTP 200）：仍差真模型生成一份维护计划的端到端读数 + 界面入口人工点一次",
    "FR-AGT-LINK-EXT-001": "等主人给一个可连的 MCP server（命令或 URL）：`resources/read` 仍 0 命中、host 方向仍批处理式，无真对端可验",
    "FR-AGT-LINK-EXT-002": "等主人装一个真 MCP server 并把配置面板点一遍：判据四族 8+20+15+23 例已全绿，余「真 server 端到端 + 面板观感」",
    "FR-AGT-LINK-CHAN-003": "等真 QQ 凭据 + 官方网关：配置面 / 入站任务 / 官方 REST 外发三段已在盘，真 WS 握手与「手机派活→手机收结论」要真账号",
    "FR-AGT-TOOL-MEDIA-001": "等主人改口径或给替代入口：麦克风按令不做（录音采集面 0 命中），可选的替代 = 「音频文件入口」",
    "FR-AGT-TOOL-SYS-002": "等人工点验：执行器与来源标注已在盘（13 例），余「对话侧当工具调起的观感」；异步入口按台账留到下一轮",
    "FR-AGT-OPS-OBS-002": "等人工点验：六项配置 + 四条生效面 10 例全绿（含并发上限真限流），余「改配置到下一次派活的观感」",
    "FR-AGT-UX-SYNC-001": "等主人定端云同步传输面（§7 阻塞 2）：语义面 19 例已绿，App 侧 0 调用点，且无第二端可对",
    "FR-AGT-UX-SESS-001": "等人工点验：8+10+6 例全绿（含删除真删的文件面），余「归档→恢复 / 导出再导入 / 删一条看盘」三下",
}

# 卡点措辞的**唯一源**：所有版本规则表按「旧 → 新」合并，同 id 以新表为准。
# 为什么要合并：`--emit-plan` 按本版范围重出时，范围外的卡点靠「上一次 plan.yaml」携带，
# 于是同一句 `next_try` 在派生件里另存了一份 —— 规则表改了，派生件仍说旧话
# （2026-11-03 实测：三处还写着「217 ping 全丢」，而 `ping` 在本 shell 有假阴性、
# 按 skill `doyah-real-db-verification` 不许作判据）。合并后 `next_try` 只认表。
ALL_BLOCKED: dict[str, str] = {}
for _table in (BLOCKED_V050, BLOCKED_V060, BLOCKED_V070):
    ALL_BLOCKED.update(_table)
del _table

VERSION_SPECS: dict[str, dict] = {
    "0.7.0": dict(
        title="v0.7.0 余账收口",
        rest_id="D9",
        # 派生依据 = 台账逐行复算出的「未闭但不在任何里程碑队列里」的 17 条**全号**（2026-11-02 手算，
        # 见 .agent/next-version.md §v0.7.0 与 evidence）。这里逐条照抄，不自己扩：一旦某条收口，
        # `--emit-plan` 会按台账状态自动把它剔出 todo，不需要改这张表。
        ledger_scope=("FR-NTS-NOTE-FORMAT-001", "FR-NTS-NOTE-SEARCH-001",
                      "FR-NTS-NOTE-ORG-001", "FR-NTS-NOTE-TRASH-001",
                      "FR-NTS-NOTE-SYNC-001", "FR-NTS-NOTE-EXPORT-001",
                      "FR-NTS-ALL-HOME-001", "FR-NTS-ALL-LIC-001",
                      "FR-NTS-ALL-DIST-001", "FR-NTS-ALL-PARITY-001",
                      "FR-STD-WS-FS-008", "FR-STD-WS-TOOL-001", "FR-STD-WS-AI-002",
                      "AC-ALL-GATE-REL-004", "AC-ALL-GATE-REL-005", "AC-ALL-GATE-REL-006",
                      "FR-STD-DB-META-002"),
        batches=BATCHES_V070,
        blocked=BLOCKED_V070,
    ),
    "0.6.0": dict(
        title="v0.6.0 横切面收口",
        rest_id="C9",
        # 台账 §4.2 那一行点名的 21 条，逐条照抄**全号**（不用前缀：`NFR-ALL-GATE-PERF-` 会连
        # `PERF-005` / `006` 一起捞进来，而它们早已 ✅、不在本版范围）。
        ledger_scope=("FR-STD-ALL-LIC-001", "FR-STD-ALL-LIC-002", "FR-STD-ALL-LIC-003",
                      "FR-STD-ALL-LIC-004", "FR-STD-ALL-LIC-005", "FR-STD-WS-LIC-001",
                      "FR-STD-ALL-PLUG-005", "FR-STD-ALL-PLUG-008",
                      "NFR-ALL-GATE-PERF-001", "NFR-ALL-GATE-PERF-002",
                      "NFR-ALL-GATE-PERF-003", "NFR-ALL-GATE-PERF-004",
                      "NFR-ALL-GATE-COMP-001", "NFR-ALL-GATE-COMP-002",
                      "NFR-ALL-GATE-COMP-003", "NFR-ALL-GATE-COMP-004",
                      "NFR-ALL-GATE-COMP-005",
                      "NFR-ALL-GATE-UI-001", "NFR-ALL-GATE-USE-005",
                      "NFR-ALL-GATE-SEC-008", "NFR-ALL-GATE-LANG-001"),
        batches=BATCHES_V060,
        blocked=BLOCKED_V060,
    ),
    "0.5.0": dict(
        title="v0.5.0 智能体进阶层",
        rest_id="A9",
        # 台账 §4.2 那一行点名的范围（含跨前缀的 8 条具名条目），逐项照抄，不自己扩。
        ledger_scope=("FR-AGT-TOOL-", "FR-AGT-OPS-OBS-002", "FR-AGT-UX-",
                      "FR-AGT-PLAN-PLAN-001", "FR-AGT-LINK-EXT-", "FR-AGT-LINK-CHAN-003",
                      "FR-AGT-KNOW-MEM-003", "NFR-ALL-GATE-AI-004", "NFR-ALL-GATE-AI-006",
                      "NFR-ALL-GATE-AI-007", "AC-ALL-GATE-AI-001", "AC-ALL-GATE-AI-004"),
        batches=BATCHES_V050,
        blocked=BLOCKED_V050,
    ),
    "0.4.0": dict(
        title="v0.4.0 笔记与任务闭环",
        rest_id="N9",
        ledger_scope=("FR-NTS-NOTE-", "FR-NTS-TODO-"),
        batches=BATCHES_V040,
    ),
    "0.3.0": dict(
        title="v0.3.0 数据库运维面",
        rest_id="B8",
        ledger_scope=None,
        batches=BATCHES_V030,
    ),
}
DEFAULT_VERSION = "0.7.0"
EVIDENCE_CMD = "cd ~/dev/doyah/lead/studio && python3 Scripts/ledger-row.py {id} | grep -q '✅'"


def read_plan() -> list[tuple[str, str]]:
    text = PLAN.read_text(encoding="utf-8")
    ids = re.findall(r"- id: (\S+)", text)
    status = re.findall(r"status: (\w+)", text)
    if len(ids) != len(status):
        raise SystemExit(f"plan.yaml 形状异常：id {len(ids)} 个 / status {len(status)} 个")
    return list(zip(ids, status))


def read_blocked() -> dict[str, str]:
    """plan.yaml 里 `status: blocked` 的条目 **且带非空 next_try** ⇒ {id: next_try}。

    为什么 blocked 要单独一条口子（而不是「非 todo 一律算对」）：`blocked` 是**声明一个卡点**，
    没有 `next_try` 的 blocked 等于「我不想做」—— 那种必须判红，否则队列里少一条没人看得见
    （2026-11-02 实测：`ORG-002` 是需求书 §3.5 与契约 §2.12 的判据互斥，next_try 写的是
    「等契约所有者裁决」，这才是 blocked 该有的样子）。
    """
    text = PLAN.read_text(encoding="utf-8")
    blocks = re.split(r"\n(?=  - id: )", text)
    out: dict[str, str] = {}
    for block in blocks:
        ident = re.search(r"- id: (\S+)", block)
        status = re.search(r"status: (\w+)", block)
        if not ident or not status or status.group(1) != "blocked":
            continue
        nxt = re.search(r"next_try: \"?([^\"\n]*)\"?", block)
        value = (nxt.group(1).strip() if nxt else "")
        if value:
            out[ident.group(1)] = value
    return out


def read_ledger() -> list[dict]:
    """台账逐行：只取 `编号` / `一句话` / `层次` / `优先级` / `状态` 五格（第 6 格起是证据，可能含 `|`）。"""
    rows: list[dict] = []
    for line in LEDGER.read_text(encoding="utf-8").splitlines():
        if not re.match(r"\|\s*(FR|AC|NFR)-", line):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6:
            continue
        rows.append(dict(id=cells[0], goal=cells[1], layer=cells[3],
                         prio=cells[4], status=cells[5]))
    return rows


def ledger_open(scope: tuple[str, ...] | None) -> list[dict]:
    rows = read_ledger()
    if scope is not None:
        rows = [r for r in rows if matches(r["id"], list(scope))]
    return [r for r in rows if r["status"] != "✅"]


def matches(item: str, patterns: list[str]) -> bool:
    return any(item == p if not p.endswith("-") else item.startswith(p) for p in patterns)


def assign(todos: list[str], spec_version: dict) -> list[tuple[dict, list[str]]]:
    """把 todo 按规则分堆；已收口（非 todo）的条目不出现在批次里。"""
    taken: set[str] = set()
    batches = []
    for spec in spec_version["batches"]:
        items = [i for i in todos if i not in taken and matches(i, spec["match"])]
        taken.update(items)
        batches.append((spec, items))
    rest = [i for i in todos if i not in taken]
    if rest:
        batches.append((dict(id=spec_version["rest_id"], title="未归堆（划分规则漏了）", est_min=40,
                             why="plan.yaml 里出现了不属于任何批次的条目 ⇒ 补规则，不许手工硬塞",
                             exit="归堆后再跑"), rest))
    return batches


def yaml_str(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_batches(batches: list[tuple[dict, list[str]]], todos: list[str], spec_version: dict) -> str:
    done = [i for i, s in read_plan() if s == "done"]
    blocked = [i for i, s in read_plan() if s == "blocked"]
    total = sum(len(items) for _, items in batches)
    est = sum(spec["est_min"] for spec, items in batches if items)
    short = (lambda x: x.split("-")[-2] + "-" + x.split("-")[-1])
    lines = [
        f"# {spec_version['title']} · 批次队列（一跳 = 一批，3–6 条同类项）",
        "#",
        "# 唯一事实源 = Docs/Doyah产品开发计划任务清单-macOS.md（活书台账）。",
        "# 本文件只决定「一跳做哪几条」，不许反向改台账。",
        f"# 生成于 {datetime.date.today().isoformat()}，"
        f"源 = plan.yaml 里 {len(todos)} 条 status: todo"
        + (f"（已收口 {len(done)} 条：{', '.join(short(x) for x in done)}）" if done else "")
        + (f"（另有 {len(blocked)} 条 blocked，不在批次里：{', '.join(blocked)}）" if blocked else ""),
        "#",
        "# 生成命令：python3 Scripts/plan-batches.py --write   （--check 只比对不写盘）",
        "",
        "batches:",
        "",
    ]
    for spec, items in batches:
        if not items:
            continue
        lines += [
            f"  - id: {spec['id']}",
            f"    title: {yaml_str(spec['title'])}",
            "    status: todo",
            f"    est_min: {spec['est_min']}",
            f"    items: [{', '.join(items)}]",
            f"    why: {yaml_str(spec['why'])}",
            f"    exit: {yaml_str(spec['exit'])}",
            "",
        ]
    lines += [
        f"# 合计 {total} 条，覆盖 plan.yaml 全部 todo。",
        f"# 粗估 {est} 分钟 ≈ {est / 60:.1f} 小时（原一格一条的节奏按 20 分钟/条算）。",
    ]
    return "\n".join(lines) + "\n"


def read_previous_plan_blocked() -> dict[str, dict]:
    """上一次 `plan.yaml` 里所有 blocked（id → {goal, next_try}）。

    为什么要它：换版本时新范围以外的卡点（例：v0.4.0 的 `NOTE-ORG-002` 等契约所有者裁决）
    如果直接丢掉，队列里就「没人看得见」—— 那正是 blocked 不许静默消失的理由。
    """
    text = PLAN.read_text(encoding="utf-8") if PLAN.exists() else ""
    out: dict[str, dict] = {}
    for block in re.split(r"\n(?=  - id: )", text):
        ident = re.search(r"- id: (\S+)", block)
        status = re.search(r"status: (\w+)", block)
        if not ident or not status or status.group(1) != "blocked":
            continue
        nxt = re.search(r'next_try: "((?:[^"\\]|\\.)*)"', block)
        if not nxt or not nxt.group(1).strip():
            continue
        goal = re.search(r'goal: "((?:[^"\\]|\\.)*)"', block)
        out[ident.group(1)] = dict(goal=goal.group(1) if goal else "", next_try=nxt.group(1))
    return out


def render_plan(rows: list[dict], spec_version: dict) -> str:
    """按台账未闭行重出 plan.yaml（派生队列，不许手写）。"""
    order: dict[str, int] = {}
    for spec in spec_version["batches"]:
        for i, ident in enumerate(spec["match"]):
            order.setdefault(ident, len(order))
    rows = sorted(rows, key=lambda r: order.get(r["id"], 10_000))
    yellow = sum(1 for r in rows if r["status"].startswith("🟡"))
    white = sum(1 for r in rows if r["status"].startswith("⬜"))
    # 台账状态格不一定只有符号一个字符：有的写成 `🟡 ｜ 2026-11-02 复核降级…`、有的写 `➖`（挂起）。
    # 只数「整格 == 🟡 / ⬜」会让这类行**两个桶都不进** ⇒ 抬头写「17 条（9 🟡 / 6 ⬜）」（9+6≠17）。
    # 所以按前缀数，剩下的单列「其他」，让抬头三个数必须加得起来。
    other = len(rows) - yellow - white
    counts = f"{yellow} 🟡 / {white} ⬜" + (f" / {other} 其他（挂起或带复核注）" if other else "")
    lines = [
        f"# {spec_version['title']} · 执行队列（**派生件**）",
        "# 唯一事实源 = Docs/Doyah产品开发计划任务清单-macOS.md（活书台账）。",
        "# 本文件只做「下一跳」排序，不许反向改台账；台账一改就跑 --emit-plan 重出，别手改。",
        f"# 生成于 {datetime.date.today().isoformat()}，源 = 台账里 "
        f"{' / '.join(spec_version['ledger_scope'])} 未闭 {len(rows)} 条（{counts}）。",
        "tasks:",
    ]
    in_scope = {r["id"] for r in rows}
    # 卡点措辞的唯一源 = 本版规则表（`spec_version["blocked"]`）；上一次 plan.yaml 只**补空位**
    # （规则表没覆盖到的本版条目），不许反过来盖规则表。
    # 反过来说：这行原来是「派生件优先」（`blocked.update(read_blocked())`），实测后果是
    # 规则表里的理由改了、`--emit-plan` 重出后仍是旧话（2026-11-03 撞到：三处还在说
    # 「217 ping 全丢」，而规则表已按 TCP 复测改写）—— 派生件于是成了第二事实源。
    blocked = {k: v for k, v in ALL_BLOCKED.items() if k in in_scope}
    blocked.update({k: v for k, v in read_blocked().items()
                    if k in in_scope and k not in ALL_BLOCKED})
    blocked.update(spec_version.get("blocked") or {})
    for r in rows:
        lines += [
            f"  - id: {r['id']}",
            f"    goal: {yaml_str(r['goal'])}",
            f"    done_when: {yaml_str(EVIDENCE_CMD.format(id=r['id']))}",
            f"    layer: {yaml_str(r['layer'])}",
            f"    prio: {yaml_str(r['prio'])}",
            f"    status: {'blocked' if r['id'] in blocked else 'todo'}",
            '    evidence: ""',
        ]
        if r["id"] in blocked:
            lines.append(f"    next_try: {yaml_str(blocked[r['id']])}")
    # 跨版本携带：上一版留下的卡点（不在本版范围内）照样列出来，不许静默消失。
    # 但**已收口的不算卡点**：台账那一行已是 ✅ 就必须从队列里消失 —— 旧码只判「不在本版范围」，
    # 于是收口后的条目被搬进「上版遗留卡点」永久携带（2026-11-03 实测：PERF-004 / COMP-001 已双 ✅
    # 仍挂在队列里，队列读数永远是 28 blocked ⇒ 每跳都看着「全卡住」）。卡点从台账来，也从台账走。
    closed = {r["id"] for r in read_ledger() if r["status"].startswith("✅")}
    carry = {k: v for k, v in read_previous_plan_blocked().items()
             if k not in in_scope and k not in closed}
    if carry:
        ledger_goals = {r["id"]: r for r in read_ledger()}
        lines.insert(lines.index("tasks:") + 1,
                     f"# 另有 {len(carry)} 条上版遗留卡点（不在本版范围，仅列表可见）：{', '.join(sorted(carry))}")
        for ident in sorted(carry):
            row = ledger_goals.get(ident)
            lines += [
                f"  - id: {ident}",
                f"    goal: {yaml_str(row['goal'] if row else carry[ident]['goal'])}",
                f"    done_when: {yaml_str(EVIDENCE_CMD.format(id=ident))}",
                f"    layer: {yaml_str(row['layer'] if row else '—')}",
                f"    prio: {yaml_str(row['prio'] if row else '—')}",
                "    status: blocked",
                '    evidence: ""',
                f"    next_try: {yaml_str(ALL_BLOCKED.get(ident) or carry[ident]['next_try'])}",
            ]
    return "\n".join(lines) + "\n"


COVERAGE: list[str] = []


def check_next_try_matches_rules(spec_version: dict) -> list[str]:
    """本版范围内 blocked 的 `next_try` 必须逐字来自规则表。

    为什么要这条：`next_try` 是「卡在谁、下次试什么」的唯一交代，它一旦允许派生件自己
    留旧话，规则表改了没人知道 —— 2026-11-03 实测：规则表三处已改成 TCP 复测，
    plan.yaml 里仍是「217 ping 全丢」（`ping` 在本 shell 有假阴性，按 skill 不许作判据）。
    派生件落后或被人手改 ⇒ 判红，点名到具体 id。

    **覆盖范围（红线第 13 条，写在这里而不是只写在文档里）**：只认**规则表里有条目**的 blocked。
    跨版携带的 blocked（`BLOCKED_*` 都没写它，`next_try` 从上一次 `plan.yaml` 抄来）没有可比对的
    规则 ⇒ 如实计数并**逐条点名**打印「未经规则表核对」，不许静默当成通过。
    """
    problems: list[str] = []
    checked: list[str] = []
    unchecked: list[str] = []
    for ident, text in read_blocked().items():
        want = ALL_BLOCKED.get(ident)
        if want is None:
            unchecked.append(ident)
            continue
        if want != text:
            problems.append(
                f"next_try 与规则表不一致：{ident}（派生件落后或被手改 ⇒ 跑 --emit-plan 重出）")
        else:
            checked.append(ident)
    COVERAGE.clear()
    COVERAGE.append(
        f"判据 F 覆盖 {len(checked) + len(problems)}/{len(read_blocked())} 条 blocked"
        + (f"；未经规则表核对（跨版携带，只判非空不判逐字）：{', '.join(sorted(unchecked))}"
           if unchecked else "；无未覆盖条目"))
    return problems


def check_against_ledger(rows: list[dict], spec_version: dict) -> list[str]:
    """台账复算 ↔ plan.yaml 对账。返回错误清单（空 = 通过）。"""
    expected = {r["id"] for r in rows}
    actual = {i for i, s in read_plan() if s == "todo"}
    closed_in_plan = {i for i, s in read_plan() if s != "todo"}
    # **blocked 且带 next_try** 是合法的非 todo（卡点已声明）；没有 next_try 的 blocked 不算，
    # 于是它既落到 missing、又落到 both ⇒ 两条同时判红，点名到具体 id。
    blocked_ok = set(read_blocked())
    closed_in_plan -= blocked_ok
    problems: list[str] = []
    missing = sorted(expected - actual - blocked_ok)
    extra = sorted(actual - expected)
    if missing:
        problems.append(f"台账未闭但队列里没有（{len(missing)} 条）：{', '.join(missing)}")
    if extra:
        problems.append(f"队列仍是 todo 但台账已闭 / 不在本版范围（{len(extra)} 条）：{', '.join(extra)}")
    both = sorted(expected & closed_in_plan)
    if both:
        problems.append(f"台账未闭但队列里标成非 todo（{len(both)} 条）：{', '.join(both)}")
    return problems


def main(argv: list[str]) -> int:
    version = DEFAULT_VERSION
    if "--version" in argv:
        idx = argv.index("--version")
        if idx + 1 >= len(argv):
            print("✗ --version 后面缺版本号（0.3.0 / 0.4.0 / 0.5.0 / 0.6.0 / 0.7.0）", file=sys.stderr)
            return 2
        version = argv[idx + 1]
    if version not in VERSION_SPECS:
        print(f"✗ 未知版本 {version}（只认 {', '.join(VERSION_SPECS)}）", file=sys.stderr)
        return 2

    spec_version = VERSION_SPECS[version]
    if spec_version["ledger_scope"] is not None and "--emit-plan" in argv and "--write" in argv:
        rows = ledger_open(spec_version["ledger_scope"])
        PLAN.write_text(render_plan(rows, spec_version), encoding="utf-8")
        # 台账未闭的条目不一定都是 todo：卡点会落 blocked（含跨版携带）。
        # 这句话此前一律印「N 条 todo」—— 本版全是卡点时它会说「7 条 todo」而实际 0 条，属读数自述错。
        written = read_plan()
        n_todo = sum(1 for _, s in written if s == "todo")
        n_blocked = sum(1 for _, s in written if s == "blocked")
        print(f"✅ 已按台账重出 .agent/plan.yaml（{n_todo} 条 todo / {n_blocked} 条 blocked）")

    todos = [i for i, s in read_plan() if s == "todo"]
    batches = assign(todos, spec_version)
    text = render_batches(batches, todos, spec_version)

    if "--check" in argv:
        rc = 0
        if spec_version["ledger_scope"] is not None:
            problems = check_against_ledger(ledger_open(spec_version["ledger_scope"]), spec_version)
            problems += check_next_try_matches_rules(spec_version)
            for line in problems:
                print(f"✗ {line}")
            # 覆盖范围如实打印（红线 13）：红了也要说清「比了几条、哪几条比不了」，
            # 否则一条未覆盖的 blocked 会顶着「全绿」混过去。
            for line in COVERAGE:
                print(f"ℹ️ {line}")
            if problems:
                rc = 1
        rest = next((items for spec, items in batches if spec["id"] == spec_version["rest_id"]), [])
        if rest:
            print(f"✗ 有 {len(rest)} 条没归进任何批次：{', '.join(rest)}（补规则，不许手塞）")
            rc = 1
        old = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if old.strip() != text.strip():
            print("✗ .agent/batches.yaml 与 plan.yaml 不一致 ⇒ 跑 --write 重出")
            rc = 1
        if rc == 0:
            print(f"✅ 批次队列一致（{len(todos)} 条待办"
                  + ("，台账复算一致" if spec_version["ledger_scope"] is not None else "") + "）")
        return rc
    if "--write" in argv:
        OUT.write_text(text, encoding="utf-8")
        print(f"✅ 已重出 .agent/batches.yaml（{len(todos)} 条待办）")
        return 0
    print("用法：--check | --write [--emit-plan] [--version 0.3.0|0.4.0|0.5.0|0.6.0|0.7.0]")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
