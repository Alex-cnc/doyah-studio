# Scripts/archive —— 退场脚本（不删，只挪）

> 规则：**删脚本先看有没有条文指着它**（`check-rule-schema.py` 现在会判红悬空引用）。
> 没有活引用、也没有条文点名的，挪到这里而不是 `rm` —— 一次 `git mv` 能还原，`rm` 不能。

## 2026-11-10 归档（4 个）

判定口径：全仓（排除 `.git` / `.build` / `.worktrees` / `.agent` / `Docs/archive` / 本文件）
grep 文件名 = **0 活引用**，且不属于任何门禁、不在 `verify-all.sh` / `action-router.py` /
`self-test-counts.json` 清单里，条文正文也没点名。

| 文件 | 原本干什么 | 为什么退 |
|---|---|---|
| `apply-patch-fragment.py` | 把一段 diff 片段补进目标文件（一次性打补丁工具） | 用 git 后不再需要；最后改动 2026-10-22 |
| `plugin-manifest-dump.sh` | 导出插件清单快照 | 插件的清单现在由 `Package.swift` 与 `check-plugin-assembly.py` 判；最后改动 2026-10-13 |
| `outcome-fingerprint.py` | 记一次验收结果的指纹 | 只被 `Docs/archive/` 里的旧手册提到，活文档不再用 |
| `manual-acceptance-helpers.sh` | 手工验收的辅助函数 | 同上，只被旧手册提到；现行点验清单走 `test-*.sh` 逐个跑 |

还原：

```bash
git mv Scripts/archive/2026-11-10/<文件名> Scripts/<文件名>
```

## 那天**差点误删**的（记录在此，别再删）

| 文件 | 为什么看着像死的 | 实际 |
|---|---|---|
| `gen-notes-fascicles.py` | 本仓 0 引用 | `../notes` 仓三本书头写着「生成器 `doyah-studio/Scripts/gen-notes-fascicles.py`」—— **跨仓引用，本仓扫不到** |
| `agent-lock.sh` | 本仓 0 引用 | 派单锁，`.agent/decisions.md` 记着用过（接管孤儿锁） |
| `test-connection-*.sh` / `test-diagnosis.sh` 等 12 个手测脚本 | 不在任何门禁里 | `Docs/design/待人工验收清单.md` 与 `alpha-0.2.0-FR判定.md` 逐个点名 → **是活的人工点验步骤** |
| `check-doc-chain.py` | 不在 `verify-all.sh` | 自己头行写着「只读 · 不入闸」的普查工具，留着 |
| `doc_index.py` | 本仓 grep 文件名 0 命中 | **被 `check-doc-tables.py` 以 `import doc_index` 当模块用** —— 文件名不提 `.py`，grep 扫不到。归档后 `check-doc-tables` 当场崩（`ModuleNotFoundError`），已还原 |

**结论：本仓「零引用」不等于「死」。** 四种 grep 看不见的活引用：
① 跨仓（`../notes` 点本仓的生成器）；② 运行时（派单锁）；③ 人工点验清单点名；④ **`import 模块名`（不带 `.py`）**。
所以清理的正确姿势是：先加「条文点名脚本必须存在」的判据 → 挪（不是删）→ **把全量门禁跑一遍**，让门禁替你抓第 ④ 类。
