# 检查点

updated: 2026-10-24T20:20

## 现状

- 计划已落 `.agent/plan.yaml`：13 项任务，4 个里程碑（M1 待写用例 5 项 / M2 未实现位点 5 项 / M3 六态 / M4 收口 3 项）。
- 基线读数：核心用例 **3632**（`.build/core-test-count.txt`）；`verify-all.sh` 与 `build-app.sh` 本次尚未跑，读数待 T4.2 / T4.3 回填。
- 详设来源：`Docs/Doyah产品详细设计说明书-macOS.md` v1.1 —— §9.2 列 5 条待写用例、§6 列 21 码里 5 族「未实现」、§10.1 同五族、§5.3 六态表。

## 下一项

`T1.2` —— 连接状态机正例 + 反例用例（`Tests/ConnectionStateTests.swift`：未连接→连接中→已连接；失败态不可直跳已连接）。

## 已完成的片

- `T0.1`（2026-10-24 20:20）—— 棘轮 B 存量红清零：`No commits yet on` 登记为 `parseToken`（git 输出前缀，非展示文案）。读数：两档均 ✅（73 文件 / 747 行；白名单外 0、陈旧 0）。
- `T1.1`（2026-10-24 20:05）—— `AppError.emptySQL` + `ExecutionScope.preflightError` + `ErrorPresenter` 接线 + 用例 `testEmptySQLMapsToEmptySQLError`。
  读数：`swift test --filter ExecutionScopeTests` = **11 tests / 0 failures**；反例注入后 = **4 failures**（判据成对成立）；`swift build --target DoyahStudioApp` = Build complete (15.57s)。

## 证据

（尚无；落 `.agent/evidence/<日期>-<task-id>.md`）

## 未验证项

- 核心总数仍以 3632 为基线（新增 1 条用例后应为 3633，待 T4.1 `verify-core.sh` 复读）。
- ~~存量红：本地化棘轮 B~~ ⇒ 已由 `T0.1` 清零。
- 本地化棘轮 A 已显式上调 730 → 747（+1 本片文案，+16 存量漂移），理由已写进台账 `comment`。
- `verify-all.sh` 当前 rc 未知（59 个 check 脚本，耗时未测）。
- `build-app.sh` 是否能出包未知（依赖 Xcode 工程与签名）。
- 六态（§5.3）中「权限不足 / 提交中 / 部分失败」三态是否有现成落点未核对。
