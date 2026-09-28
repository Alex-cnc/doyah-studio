#!/usr/bin/env python3
"""队列 L-50 的负例：`Scripts/check-empty-action-buttons.py` 自己的证据。

判据写完不对已知改动报红，等于没有（第 33 起的老规矩）。11 例全部在**临时夹具仓**上写坏
（只拷 `App/` + 台账 + 脚本本身；整仓 16 GB，不能整份拷），末例核对真仓库逐字节未变。

    python3 Scripts/test-empty-action-buttons.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "check-empty-action-buttons.py"


def main() -> int:
    # 判据的 `--self-test` 就是这一份负例（11 例 + 末例真仓库未变），这里只做入口与转述 ——
    # 负例与判据同源，避免"两份夹具各自漂"。
    process = subprocess.run(
        [sys.executable, str(TARGET), "--self-test"],
        cwd=str(HERE.parent),
        text=True,
    )
    if process.returncode != 0:
        print("❌ L-50 负例未全过（详见上面的逐条输出）")
        return 1
    print("✅ L-50 负例 11/11（判据自己的 --self-test）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
