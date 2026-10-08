# 应用图标资产（法斗 Doyah）

同一幅画在两套桌面环境里需要**两种容器**，这个目录负责把「Linux 那一半」备齐。
需求提出者 2026-09-24 问：「应用图标能用在 Linux 版吗？如果可以，看下这个文件有没有上传 GitHub，
我同步到 Linux 版本上去。」

**2026-10-08 统一默认图标**（人类主人：「设置这张图片为产品所有平台版本的默认图标」）：全平台改由
派单仓 `assets/product-icon/icon-1024.png` 母版**等比**重生 —— macOS 侧换源 + 重出 `.icns`，
Linux 侧八档 hicolor 同源重出。本目录四份资产的现状见下表。

**2026-10-09 底衬改正**（人类主人令 `T-20261008-056`：图标底衬 = **② 透明底**）：四份资产全部改由
派单仓 `assets/product-icon/icon-transparent-1024.png`（sha256 `b42a81f9…` · 1024² · RGBA · 四角 alpha=0）
母版**等比**重生 —— 两处 1024 逐字节副本、`.icns` 十档、hicolor 八档，**不再有米白圆底、也没有白角**。

## 目录里有什么

| 文件 | 平台 | 在 Git 里 | 说明 |
|---|---|---|---|
| `AppIcon-source.png` | 通用（源画） | ✅ 已提交 | **1024×1024 母版**（2026-10-09 起：派单仓 `assets/product-icon/icon-transparent-1024.png` 的**逐字节副本**，sha256 `b42a81f9…`；**透明底** —— 四角与四边中点读数 alpha=0，真 PNG / RGBA）。Linux 侧要出任何尺寸都从这份派生 |
| `AppIcon.icns` | 仅 macOS | ✅ 已提交 | Apple 专用容器（内部 10 档 16…1024，**由母版等比派生**；2026-10-09 起由透明底母版重出），装进 `.app` 供 Dock / 访达用。**Linux 桌面不认这个格式** |
| `AppIcon-1024.png` | macOS / 通用 | ✅ 已提交（走 `git add -f`；`.gitignore` 第 49 行仍排除该路径） | **= 母版逐字节副本**（与 `AppIcon-source.png` 同 sha256 `b42a81f9…`）。2026-10-08 统一图标后它**不再是**「824 内缩的 macOS 成品」；2026-10-09 起母版本身即透明底 |
| `icons/hicolor/**/doyahstudio.png` | 仅 Linux | ✅ 已提交 | 8 档尺寸（16/24/32/48/64/128/256/512），真 PNG，**由母版等比重生**（2026-10-09 透明底母版重出；`Scripts/make-linux-icons.sh` 默认源），直接可装进图标主题 |

## 为什么不能直接把 `.icns` 拷到 Linux

macOS 的应用图标是 `.icns`（Apple 专用容器，内部按尺寸分档存放 16…1024 的位图），GNOME / KDE / XFCE
找图标时**只看** `hicolor/<N>x<N>/apps/` 下的 PNG 或矢量图。把 `.icns` 放进
`~/.local/share/icons/` 的结果是：桌面拿不到图标，回退成一个默认方块 —— 不报错，但也没效果。
另外 macOS 侧过去那版成品图标按系统观感做了 10% 留白 + 圆角（2026-10-08 统一图标后**母版是米白圆底 + 白角、无留白**；2026-10-09 起**母版换成透明底**），Linux 侧通常要**方形全出血**，
由桌面环境自己决定要不要加形状；所以这里是从源画重新出，不是从 `.icns` 转换。

## 在 Linux 上安装

用户级（无需 root，重建图标缓存即可生效）：

```bash
# 把 hicolor 目录整体拷进用户的图标主题目录
cp -R App/Resources/icons/hicolor ~/.local/share/icons/
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true
```

系统级则拷到 `/usr/share/icons/`（多数发行包会把这份资产直接装到那里）。

`.desktop` 里按名字引用，**不需要写绝对路径**：

```ini
[Desktop Entry]
Type=Application
Name=DoyahStudio
Exec=/path/to/doyahstudio
Icon=doyahstudio
Categories=Development;Database;
```

`Icon=` 的值必须与本目录里的文件名（`doyahstudio.png`）以及
`Scripts/make-linux-icons.sh --name` 一致；Linux 侧若已定了别的应用 id，改名字更省事 ——
把 PNG 改名、或重跑脚本时加 `--name <新名字>`。

## 重新生成

两个平台都能跑同一个脚本（优先 ImageMagick，macOS 上退回系统自带 `sips`）：

```bash
./Scripts/make-linux-icons.sh                        # 默认 8 档到 App/Resources/icons/hicolor
./Scripts/make-linux-icons.sh --sizes 16,32,512      # 只要几档
./Scripts/make-linux-icons.sh --name doyahstudio     # 换名字
```

脚本对每个产物按 **PNG 魔数 + IHDR 宽高**逐个核对（不信缩放工具自己的说法），
实测重跑产物逐字节一致（不会每次改一点、在 diff 里制造噪音）。

不用脚本的话，Linux 侧一行 ImageMagick 也能出：

```bash
for s in 16 24 32 48 64 128 256 512; do
  mkdir -p ~/.local/share/icons/hicolor/${s}x${s}/apps
  convert App/Resources/AppIcon-source.png -resize ${s}x${s} \
    ~/.local/share/icons/hicolor/${s}x${s}/apps/doyahstudio.png
done
```

## 两个已登记的坑

1. ~~**`AppIcon-source.png` 的实际内容是 JPEG**（JFIF，后缀却是 `.png`）~~ —— **2026-10-08 统一图标后
   此坑已消失**：现源画是货真价实的 PNG（`sips -g format` ⇒ `png`）。留档的原因：
   Linux 侧若还按「源画是 JPEG」的旧认知留着校验分支，可以去掉那一支了。
   （2026-10-09 起母版换成**透明底**：`sips -g hasAlpha` ⇒ `yes`，`Image.mode` ⇒ `RGBA` —— 早先那版
   是 RGB、无 alpha 通道，若哪处代码/校验按「无 alpha」假设写的，同样要跟版。）
2. **图标名与 `.desktop` 的 `Icon=` 必须一致**，否则同样是"装了但看不见"——排查时先跑
   `gtk-update-icon-cache`，再看 `Icon=` 是否拼错。

平台差异本身已登记在 `Docs/需求规范书.md` §10.9（P-08 打包与分发）：跨平台必须一致的是
**同一品牌图形与同一个图标名**，允许不同的是**容器格式与尺寸集**。

## 直接交给 Linux 侧助手照做（可以整段照抄）

> 图标资产在 `App/Resources/icons/`，请这样处理：
>
> 1. 用 `AppIcon-source.png`（1024×1024 母版，2026-10-08 起）**向下**缩放，生成 freedesktop 尺寸集：
>    `hicolor/<N>x<N>/apps/<应用名>.png`，N 取 16 / 24 / 32 / 48 / 64 / 128 / 256 / 512；
>    `<应用名>` 必须与 `.desktop` 里的 `Icon=` 一致。
> 2. **不要**用 `AppIcon.icns`（Apple 专用容器，Linux 桌面不认）。`AppIcon-1024.png` 现在与源画
>    **逐字节相同**（同一张图），用哪个都一样（它 2026-10-08 前是 macOS 观感成品，现已作废）。
> 3. **不要把小图放大** —— 放大只会糊。需要更多尺寸，一律从 1024 的母版重出。
> 4. 源画现为**真 PNG**（2026-10-08 前它是 JPEG 套 `.png` 后缀，该坑随统一图标消失）。
> 5. 生成完**逐个断言产物的实际宽高**等于目标尺寸（别只看命令退出码）。
> 6. 仓库里其实已经生成好八档（`App/Resources/icons/hicolor/`）。尺寸与名字都合适的话，
>    直接 `cp -R App/Resources/icons/hicolor ~/.local/share/icons/` 最省事 —— 自己重出会用到
>    另一种重采样器，像素不会与仓库里的逐字节相同（**观感无差别，不必强求一致**）。
>
> 一个已知的天花板：16 / 24 这两档是"照片式缩放"的必然结果，小尺寸下细节会糊成一团。
> 想要真正锐利的 16px，得请人重画一版简化的图形（本仓没有矢量源，也没有设计稿）。

