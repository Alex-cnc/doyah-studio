# windows/ —— Doyah Studio 的 Windows 侧（另一平台）实现落点

对应设计：`Docs/概要设计.md` **§8.2**（仓库结构：同仓 `windows/` 块）与 **§8.5 契约 → Windows 实现 `[独占:windows]`**。
本目录 = **实现层**：可以替换实现，**不得改变 §3 的契约与不变量**；要改契约走 `Docs/proposals/`。

## 现在有什么

只有**闸门**（`Tools/`）—— 口径是「先有闸门再有功能」（§8.5.3 / §8.3.1）。
实现本体（`Core/` `App/` `Cli/` `Platform/Windows/` `Tests/`）**尚未开工**：

| 目录 | 层 | 现状 |
|---|---|---|
| `Tools/` | 闸门（§8.3.1 六项必需项） | ✅ 已建（见 `Tools/README.md`） |
| `Core/` | 领域层（C# / .NET 8 类库，零 UI 依赖） | ⬜ 未建 |
| `App/` | 表示层（WPF，`net8.0-windows`） | ⬜ 未建 |
| `Cli/` | 无界面验证入口（.NET 控制台） | ⬜ 未建 |
| `Platform/Windows/` | 平台适配层（凭据 / ConPTY / 通知，唯一允许 P/Invoke 处） | ⬜ 未建 |
| `Tests/` | xUnit | ⬜ 未建 |

## 先跑闸门

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tools\verify-all.ps1
```

收尾行会如实报「跑了哪些 / 跳过哪些」——**跳过不是「已通过」**（§8.3.2）。用法、判据归属、实测坑见 `Tools/README.md`。
