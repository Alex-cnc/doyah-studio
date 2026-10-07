# Windows 侧 · 第三方依赖许可台账（platform/windows/THIRD-PARTY-NOTICES.md）

本文件登记 **Windows 侧（`platform/windows/**`）** 用到的第三方依赖的许可。
逐条写「名字 / 版本 / 许可 / 出处 / 用途 / 证据」——**用列表写，不排表格**（表格在跨端对账里
容易被当成"另一种真相来源"，这里只需要一份可逐条引用的记录）。

## 本片（`S-9a` 内置终端·起真 shell）新登记的依赖

- **portable-pty** · 0.9.0
  - **许可：MIT**（许可正文首行 `MIT License`，版权行 `Copyright (c) 2018 Wez Furlong`）
  - 出处：`https://github.com/wezterm/wezterm`（wezterm 出品；Windows 侧覆盖 ConPTY）
  - 用途：内置终端（W-C 底部终端 · 段 2.7）起真交互式 shell。
    **全部 PTY 代码落在 `platform/windows/App/src-tauri/src/pty.rs` 这一个文件**，其它文件只经 `pty::` 接口调用。
  - 证据（本机 `cargo` registry 实测，版本 0.9.0）：
    - crate 自带 `Cargo.toml` 的清单字段 `license = "MIT"`；
    - crate 自带 `LICENSE.md` 正文首行为 `MIT License`。
  - **如实更正**：本片卡面与前门裁决 `T-20261007-031` 记的许可是 **`BSD-2`**，
    与本 crate 的实际声明（MIT）**不符**。以 crate 自带声明为准，此处登记为 **MIT**；
    上面这行同时留下 `BSD-2` 这个提法的出处，免得下次有人照卡面抄一遍。

## 既有缺口（本片如实登记，不在本片收口）

- **Windows 侧既有 Rust 依赖面尚未逐条登记 = 既有缺口，另案。**
  本侧已在盘并用着的依赖（`App/src-tauri` 的 `tauri` / `serde` / `serde_json` / `tokio` /
  `tokio-postgres` / `futures-util` / `tauri-plugin-dialog`，以及 `Core` / `Db` / `Cli` 三包各自的依赖）
  **没有**同类台账；`Cargo.lock` 只是机器记录，不等于许可声明。
  本片**只登记本片新增的那一条**，不假装这一面已经齐全 —— 补齐属另案。
