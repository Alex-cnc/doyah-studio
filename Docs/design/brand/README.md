# 品牌资产 · Doyah Studio

| 件 | 用途 | 来源 |
|---|---|---|
| `doyah-studio-mascot.png` | **原图（存档）** 2048×2048 · 1.5 MB —— 法斗（French Bulldog）幼犬，奶油身 + 深棕口鼻/耳朵，厚描边扁平矢量风，米色圆底 | 仓库所有者给定（人类主人 2026-10-15 交办），按原图入库，**未改色、未裁切** |
| `doyah-studio-mascot-512.png` | **展示件** 512×512 —— README 首屏用（显示 148px）；由原图机械缩出（`sips -Z 512`） | 同上，缩图不改内容 |

**用法**：README 首屏（中英各一处）以 148px 宽展示；纯展示资产，**不参与 App 打包**（App 图标族仍在 `App/Resources/`）。

**口径**：本目录下的件都是**派生展示件**（非契约）—— 真值 = 本表 + 原图文件；若要换图，**替换同名文件 + 在本表记一行**，不要另起新名（避免引用漂移）。

## 应用图标（2026-10-15 同批）

同一幅画**同时用作应用图标**（人类主人 2026-10-15 令）：

| 项 | 值 |
|---|---|
| 源画 | `App/Resources/AppIcon-source.png`（= 本目录 `doyah-studio-mascot.png`，2048×2048） |
| 生成命令 | `ICON_WATERMARK_CROP=0 swift Scripts/make-app-icon.swift` → `iconutil -c icns .build/AppIcon.iconset -o App/Resources/AppIcon.icns` |
| macOS | `App/Resources/AppIcon.icns`（10 档，16~1024）+ `AppIcon-1024.png`（1024 合成母版，圆角 824@1024） |
| Linux | `App/Resources/icons/hicolor/`（8 档，16~512；`Scripts/make-linux-icons.sh --source …`） |
| 客观检查 | `swift Scripts/icon-sanity-check.swift App/Resources/AppIcon-1024.png` ⇒ 有居中主体 + 圆角遮罩生效 |

**为什么用 `ICON_WATERMARK_CROP=0`**：脚本默认裁底部 180px 去 Seedream 水印，而本图**无水印**（实测底部 300px 无文字/签名）⇒ 硬裁会切歪构图。该开关 2026-10-15 加入 `make-app-icon.swift`（**默认值仍为 180，向后兼容**）。

> 换图标 = 换 `AppIcon-source.png` 后重跑上面两条命令；`dist/` 里已构建的包要**重新构建**才会带上新图标。
