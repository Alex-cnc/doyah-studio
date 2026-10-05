/*
** 模块伞头（umbrella header）—— 这一层是**给构建系统用的**，不是产品代码。
**
** 为什么需要它：SwiftPM 给 C 目标生成的模块图有两种形状：
**   · `umbrella header "<目标名>.h"` —— 当公共头目录里有**与目标同名**的头文件时；
**   · `umbrella "<目录>"`          —— 其它情况。
** 而 Swift 的 clang 导入器**不支持伞目录**：第二种形状下 `import CSQLite3` 会得到一个**空模块**
** （症状非常隐蔽：没有报错，只是所有声明都"找不到"，看起来像拼错了函数名）。
** 实测就是这么踩到的 —— 第一次构建时头文件与 `sqlite3.c` 同目录，Swift 侧 `sqlite3_open_v2`
** 一律 "cannot find in scope"。
**
** 所以：一个三行的转发头，换来「`import CSQLite3` 真能看到 sqlite3.h 的全部声明」。
** 内容只有一行 `#include`，没有任何改动语义的机会。
*/
#ifndef DOYAH_CSQLITE3_UMBRELLA_H
#define DOYAH_CSQLITE3_UMBRELLA_H

#include "sqlite3.h"

#endif /* DOYAH_CSQLITE3_UMBRELLA_H */
