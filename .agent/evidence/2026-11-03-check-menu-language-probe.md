# 2026-11-03 · `check-menu-language` 探针收口（`verify-all` 第 11 项）

条目：无台账行 —— 队列仍是 **0 todo / 21 blocked**（`plan-batches.py --version 0.7.0 --check` rc=0），本跳收的是 `verify-all` 第 11 项**最后一处机器面存量红**（`check-menu-language`），台账状态列一个字未动。

判据：

```
$ python3 Scripts/check-menu-language.py            # 修复前：两档 × 三次 × 120 s 都等不到 dump
      A：条目 80 / 识别 76 / 认不出 4 / 停启动语言 0 / 未覆盖 0     ← 修复后（--timeout 45）
      C：条目 117 / 识别 113 / 认不出 4 / 停启动语言 0 / 未覆盖 0
  ✅ 两档三段的每一项都跟当前界面语言同语；认不出的项都在豁免里；展开族一条不少   rc=0
$ python3 Scripts/check-menu-language.py --self-test   → 自检 19 例：19 通过 / 0 失败
$ swift test --filter MainMenuProbeWiringTests         → Executed 2 tests, with 0 failures
$ ./Scripts/verify-core.sh                             → Core 单测 5368 项（0 失败）
```

根因（不是判据松了，是探针挂住）：主线程卡在 `-[NSMenu popUpMenuPositioningItem:atLocation:inView:appearance:]` **40 分钟**（`sample` 调用栈，pid 46075 自 12:26 起），收起器排的是 `DispatchQueue.main.asyncAfter`，而菜单跟踪期间 run loop 走 `NSEventTracking` 模式 ⇒ 主队列那一路一次没被抽 ⇒ `cancelTracking()` 从未触发 ⇒ 两档都「等了 120 秒没等到 dump」，台账只能记「未执行」。

改法：收起器改挂 `RunLoop.main.add(timer, forMode: .common)`（含 `NSEventTracking`）+ `popUp` 前后各写一行 stderr 点名菜单（下次挂住直接看日志是哪一项，不必再 `sample`）。判据 `Tests/MainMenuProbeWiringTests` 2 例钉住：真源码合规 + 负例夹具（旧写法必须判红、注释里的历史记录不许判红）。

反例（真源码注入，非夹具）：把 `.common` 定时器换回 `DispatchQueue.main.asyncAfter` ⇒ 判红两条（「收起器又用回了 DispatchQueue…」「收起器没挂 .common 模式」）；还原后 `sha256` **04587f88…** 逐字节一致、2/2 复绿。

提交：286c073e（已推送，local == origin/master）
未验证：真鼠标在别人手势下点菜单未做（本判据靠 `popUp` 程序化展开，等价于用户展开那一刻的样子）；条件族「显示标签页栏 / 所有标签页」仍随窗口标签页状态浮动（两档都出现，但这是 AppKit 条件插入，不是本跳保证）；`verify-all` 全量读数见 checkpoint 的收尾行。
