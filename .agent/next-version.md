# 下一版：v0.4.0 笔记与任务闭环（交接说明）

> 由组长代写（人类主人 2026-11-02 07:55 令：主人暂时接触不到循环）。事实源仍是台账 §3 / §4.2，本文件只做排序与前置条件。

## 一、开工前必须先补壳（否则会翻出假绿）

台账里 `FR-NTS-*` 共 26 行，未双 ✅ 24 行，但其中**一大批是空壳行**：`一句话` 列与 `判据` 列都是 `—`。
2026-11-02 实算的空壳（12 条）：

```
FR-NTS-NOTE-CAPTURE-001  FR-NTS-NOTE-FORMAT-001   FR-NTS-NOTE-ATTACH-001   FR-NTS-NOTE-SEARCH-001
FR-NTS-NOTE-ORG-001      FR-NTS-NOTE-ORG-002      FR-NTS-NOTE-VERSION-001  FR-NTS-NOTE-TRASH-001
FR-NTS-NOTE-SYNC-001     FR-NTS-NOTE-SYNC-002     FR-NTS-TODO-*（8 条中多数）
```

**空壳行不许翻 ✅** —— 没有一句话就没有「做成什么样」的标准，翻绿等于自己给自己判对（违反红线条 3）。
开工第一件事：按 L0《需求规格说明书》§3.5 的 `FR-NTS-*` 条文（含 `[产品特有]` 三条）把每条的一句话与判据补齐，
**只补台账的空格，不许新造需求**。

## 二、v0.4.0 的范围（§4.2 原文）

14 条（12🟡 / 2⬜）：采集 / 附件 / 版本 / 同步 `NTS-NOTE-*`、待办 `NTS-TODO-*`、组织与私密 `NTS-NOTE-ORG-002` / `PRIVACY-001`。
出口：该 14 条双 ✅；**离线装配与同步两路各跑通一次**。

## 三、建议批次（沿用 `.agent/rules.md` v2：每批 3–6 条，批末一次验证）

| 批 | 条目 | 条数 |
|---|---|---:|
| N1 | `NOTE-CAPTURE-001` · `NOTE-FORMAT-001` · `NOTE-ATTACH-001` | 3 |
| N2 | `NOTE-SEARCH-001` · `NOTE-ORG-001` · `NOTE-ORG-002` · `NOTE-TRASH-001` | 4 |
| N3 | `NOTE-VERSION-001` · `NOTE-SYNC-001` · `NOTE-SYNC-002` | 3 |
| N4 | `PRIVACY-001` + 待办里 §4.2 点名的那几条（补齐后按台账实算） | 3–4 |

`NOTE-EXPORT-001` 与 `ALL-*` 三条（`DIST` / `PARITY` / `LIC`）不在 §4.2 的 v0.4.0 里，别顺手带进来。

## 四、队列怎么来

不许手写批次到手改：按台账派生。`Scripts/plan-batches.py` 现在只认 DB 面，
要么给它加 `--version 0.4.0` 的规则表，要么照它写 `.agent/plan-notes.yaml`，**两者都要 `--check` 能对着台账复算**。

## 五、边界

判据维护跳按 `.agent/rules.md`「判据维护跳的出口」收尾（最多再 2 跳、净减红 ≤ 0 就停、剩余红三分标注），
标注完当跳转本文件开工。**不许停在「维护」上等指令。**
