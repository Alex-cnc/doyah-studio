#!/bin/bash
# 端点判定三档的脚本取证（NFR-ALL-GATE-AI-006 ①②③）。
#
# 为什么单开这一条：原有证据 `Scripts/test-local-endpoint.sh` 证的是「指到本地端点 ⇒ 免 Key、
# 零外发、流程通」；它只用了 127.0.0.1 一个形状，也**没有**判「地址写错时说的是什么话」。
# 而这一条需求的后半句正是「端点判定失败时给出可读原因」—— 那半句在图形界面里只能靠眼睛，
# 在单测里脚本侧拿不到。于是给一条**不碰网**的出口（`.build/debug/DoyahCLI agent-endpoint`），
# 把「什么算本地 / 什么算远端 / 什么算不可用、原因指到哪一步」逐条读出来。
#
# 判据：
#   ① 四类本地地址（localhost / *.local / 私网 / ::1）判「本地（免 API Key）」，且
#      走真 HTTP 时请求**不带** Authorization（第 2 节：localhost 主机名 + 本地假端点）；
#   ② 远端地址判「远端（需 API Key）」（标准兼容接口那一面由 `AgentEndpointDiagnosisTests`
#      的请求形状用例守：`/v1/chat/completions` + `Authorization: Bearer`）；
#   ③ 五种不可用形状各给**不同**的可读原因，结论行说「不可用」而不是「需要 Key」；
#      有不可用 ⇒ 退出码 3（全部可用 ⇒ 0）。
#
# 用法：`./Scripts/test-endpoint-modes.sh`（需先 `swift build --product DoyahCLI`）
set -uo pipefail

cd "$(dirname "$0")/.."
CLI=".build/debug/DoyahCLI"
PORT=18136

fail=0
check() { if [ "$2" -eq 0 ]; then echo "  PASS ${1}"; else echo "  FAIL ${1}"; fail=1; fi; }

if [ ! -x "$CLI" ]; then
    echo "缺 ${CLI}：先跑 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --product DoyahCLI"
    exit 1
fi

echo "== 1) 三档判定：本地 / 远端 / 不可用（不碰网）=="
OUT="$("$CLI" agent-endpoint \
    "http://localhost:11434/v1" \
    "http://ollama.local:11434/v1" \
    "http://127.0.0.1:11434/v1" \
    "http://192.168.1.50:8000/v1" \
    "http://[::1]:8080/v1" \
    "https://api.example.com/v1" 2>&1)"
CODE=$?
echo "$OUT" | sed 's/^/  /'
[ "$CODE" -eq 0 ] && check "六条可用端点 ⇒ 退出码 0" 0 || check "可用端点退出码应为 0（实得 ${CODE}）" 1
for shape in "localhost:11434/v1" "ollama.local:11434/v1" "127.0.0.1:11434/v1" "192.168.1.50:8000/v1" "[::1]:8080/v1"; do
    echo "$OUT" | grep -qF "${shape} → 本地端点（免 API Key）" \
        && check "本地形状 ${shape} 判为「本地 · 免 Key」" 0 \
        || check "本地形状 ${shape} 判定不对" 1
done
echo "$OUT" | grep -qF "→ 远端端点（需 API Key）· api.example.com" \
    && check "远端形状判为「远端 · 需 Key」" 0 || check "远端形状判定不对" 1
echo "$OUT" | grep -q "本地端点（免 API Key）· 127.0.0.1$" \
    && check "结论行带上主机名（不是一句泛泛的话）" 0 || check "结论行缺主机名" 1

echo ""
echo "== 2) 不可用：五种形状各给一句不同的原因，且退出码 3 =="
BAD="$("$CLI" agent-endpoint \
    "" \
    "localhost:11434/v1" \
    "ftp://127.0.0.1:11434/v1" \
    "http://" \
    "http://a b/v1" 2>&1)"
BAD_CODE=$?
echo "$BAD" | sed 's/^/  /'
[ "$BAD_CODE" -eq 3 ] && check "有不可用 ⇒ 退出码 3" 0 || check "退出码应为 3（实得 ${BAD_CODE}）" 1
echo "$BAD" | grep -q "还没填端点" && check "空端点：说「还没填」" 0 || check "空端点缺原因" 1
echo "$BAD" | grep -q "缺少协议头" && check "少协议头：指出要 http(s)://" 0 || check "少协议头缺原因" 1
echo "$BAD" | grep -q "只支持 http 与 https（当前是 ftp）" && check "协议不对：指名当前协议" 0 || check "协议不对外缺原因" 1
echo "$BAD" | grep -q "缺少主机名" && check "缺主机名：给出示例" 0 || check "缺主机名缺原因" 1
echo "$BAD" | grep -q "解析不了" && check "其余形状：说「解析不了」" 0 || check "解析失败缺原因" 1
echo "$BAD" | grep -q "需要 API Key" \
    && check "不可用被误说成「需要 API Key」（这句不许出现）" 1 \
    || check "不可用没有被说成「需要 API Key」" 0
DISTINCT=$(echo "$BAD" | sed 's/^.*端点不可用：//' | sort -u | wc -l | tr -d ' ')
[ "$DISTINCT" -eq 5 ] && check "五条原因互不相同（实得 ${DISTINCT} 种）" 0 || check "原因有重复（只有 ${DISTINCT} 种）" 1

echo ""
echo "== 3) 切到英文：那一行有译文（不是空白、不是键名）=="
EN="$("$CLI" agent-endpoint --language en "http://127.0.0.1:11434/v1" "ftp://x/v1" 2>&1)"
echo "$EN" | sed 's/^/  /'
echo "$EN" | grep -q "Local endpoint (no API key) · 127.0.0.1" \
    && check "英文：本地那一行有译文" 0 || check "英文：本地那一行没译文" 1
echo "$EN" | grep -q "Only http and https are supported (got ftp)" \
    && check "英文：原因那一行有译文" 0 || check "英文：原因没译文" 1

echo ""
echo "== 4) 本地端点走真 HTTP：localhost 主机名 + 请求不带 Authorization =="
STUB=$(mktemp -t doyah-endpoint-stub)
export DOYAH_EGRESS_LOG_DIR="$(mktemp -d -t doyah-egress)"
cleanup() { [ -n "${STUB_PID:-}" ] && { kill "$STUB_PID" 2>/dev/null; wait "$STUB_PID" 2>/dev/null; }; rm -f "$STUB" "$STUB.log"; }
trap cleanup EXIT

cat > "$STUB" <<'PY'
#!/usr/bin/env python3
"""本地假 OpenAI 兼容端点：只回固定响应，用来核对「本地端点免 Key」在真 HTTP 上成立。"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        sys.stderr.write("STUB_REQ path=%s auth=%s\n" % (self.path, self.headers.get("Authorization")))
        sys.stderr.flush()
        body = {
            "choices": [{"message": {"role": "assistant", "content": "SELECT 1"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        }
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY

python3 "$STUB" "$PORT" 2>"$STUB.log" &
STUB_PID=$!
sleep 1
kill -0 "$STUB_PID" 2>/dev/null && check "假端点已监听 127.0.0.1:${PORT}" 0 || check "假端点没起来" 1

SQL_OUT="$("$CLI" agent-sql --endpoint "http://localhost:${PORT}/v1" --model "qwen2.5:7b" "找出一行" 2>&1)"
echo "$SQL_OUT" | sed 's/^/  /'
echo "$SQL_OUT" | grep -q "本地端点判定：是（免 API Key）" \
    && check "localhost 主机名判为本地、免 Key" 0 || check "localhost 判定不对" 1
echo "$SQL_OUT" | grep -q "SELECT 1" && check "真 HTTP 上取到了回复" 0 || check "没取到回复" 1
grep -q "STUB_REQ path=/v1/chat/completions auth=None" "$STUB.log" \
    && check "请求走 /v1/chat/completions，且没有 Authorization 头" 0 \
    || { check "请求形状或免 Key 不对"; head -2 "$STUB.log"; }

echo ""
if [ "$fail" -eq 0 ]; then
    echo "通过：三档判定齐全、不可用各给不同原因、本地端点免 Key 在真 HTTP 上也成立"
else
    echo "有失败项，见上"
fi
exit "$fail"
