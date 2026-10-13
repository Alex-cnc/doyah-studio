#!/bin/bash
set -uo pipefail

# Plugin assembly probe (design doc section 8, criteria 1 & 3):
# turns "installed / removed / absent => degrade" into re-runnable readings.
#
# Why it exists: assembly is exactly the kind of thing that degrades into "looks right":
#   - "plugin present => mount point appears" gets eyeballed;
#   - "plugin absent => feature disappears with zero errors" is never checked;
#   - "broken manifest => only that plugin degrades" is never tried.
# This script drives the project's own CLI (.build/debug/DoyahCLI) through all three
# shapes and prints one reading per assertion; any failed assertion exits non-zero.
#
# NOTE: this script is deliberately ASCII-only. /bin/bash here is 3.2 and mis-parses
# multibyte characters next to variable names when the locale is not UTF-8 (observed:
# "label: unbound variable" on a CJK echo). Machine-facing CLI labels are ASCII too;
# the Chinese diagnostic line still ships in the app log.
#
# Usage:
#   ./Scripts/plugin-manifest-dump.sh          # use the already-built CLI
#   BUILD=1 ./Scripts/plugin-manifest-dump.sh  # build the CLI first (repo toolchain)

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CLI="${ROOT}/.build/debug/DoyahCLI"
PROBE_DIR="${TMPDIR:-/tmp}/doyah-plugin-probe-$$"
FAILURES=0

cleanup() { rm -rf "$PROBE_DIR"; }
trap cleanup EXIT

if [ "${BUILD:-0}" = "1" ]; then
  echo "== build CLI (repo toolchain) =="
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    swift build --disable-sandbox \
      --cache-path "$ROOT/.build-cache" --scratch-path "$ROOT/.build" \
      --product DoyahCLI
fi

if [ ! -x "$CLI" ]; then
  echo "FAIL: CLI not found at $CLI (run with BUILD=1 first)" >&2
  exit 1
fi

check() {
  local expected="$2"
  local actual="$3"
  local label="$1"
  if [ "$expected" = "$actual" ]; then
    echo "  ok   $label = $actual"
  else
    echo "  FAIL $label: expected $expected, got $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "== case 1: in-repo Plugins/ (expect 2 active — Notes / Retro, 0 degraded) =="
set +e
OUT="$("$CLI" plugins dump --dir "$ROOT/Plugins" 2>&1)"
RC=$?
set -e
printf '%s\n' "$OUT" | sed 's/^/  | /'
check "exit code (zero degraded => 0)" "0" "$RC"
check "manifest id found" "1" "$(printf '%s\n' "$OUT" | grep -c 'id=Retro')"
FIELDS=0
for f in displayName version entryTarget apiVersion storage capabilities contributions; do
  if printf '%s\n' "$OUT" | grep -q "$f="; then FIELDS=$((FIELDS + 1)); fi
done
check "seven manifest fields printed" "7" "$FIELDS"
check "degraded entries" "0" "$(printf '%s\n' "$OUT" | grep -c 'degraded: id=')"
check "activity mounts complete (nothing unmounted)" "1" "$(printf '%s\n' "$OUT" | grep -c 'mounts: unmounted=\[\]')"

echo "== case 2: broken manifest (apiVersion mismatch) => only that one degrades =="
mkdir -p "$PROBE_DIR/Bad"
cat > "$PROBE_DIR/Bad/plugin.json" <<'JSON'
{ "id": "Bad", "displayName": "Broken Plugin", "version": "0.0.1", "entryTarget": "DoyahStudio", "apiVersion": 999,
  "capabilities": [], "contributions": [{ "point": "menu" }], "storage": "pluginOwned" }
JSON
set +e
OUT2="$("$CLI" plugins dump --dir "$PROBE_DIR" 2>&1)"
RC2=$?
set -e
printf '%s\n' "$OUT2" | sed 's/^/  | /'
check "exit code (degraded present => 1)" "1" "$RC2"
check "degrade reason names apiVersion" "1" "$(printf '%s\n' "$OUT2" | grep -c 'degraded: id=Bad | reason=apiVersion mismatch')"
check "degraded list names the plugin" "1" "$(printf '%s\n' "$OUT2" | grep -c 'degraded: id=Bad')"

echo "== case 2b: manifest missing a contract field (entryTarget) => parse failure named, not silent =="
mkdir -p "$PROBE_DIR/Incomplete"
cat > "$PROBE_DIR/Incomplete/plugin.json" <<'JSON'
{ "id": "Incomplete", "displayName": "Incomplete Plugin", "version": "0.0.1", "apiVersion": 1,
  "capabilities": [], "contributions": [{ "point": "menu" }], "storage": "pluginOwned" }
JSON
set +e
OUT2B="$("$CLI" plugins dump --dir "$PROBE_DIR" 2>&1)"
RC2B=$?
set -e
check "exit code (degraded present => 1)" "1" "$RC2B"
check "missing field is named (entryTarget)" "1" "$(printf '%s\n' "$OUT2B" | grep -c 'degraded: id=Incomplete | reason=manifest parse failed')"

echo "== case 3: plugin absent (empty dir) => 0 active / 0 degraded / no error output =="
mkdir -p "$PROBE_DIR/empty"
set +e
OUT3="$("$CLI" plugins dump --dir "$PROBE_DIR/empty" 2>"$PROBE_DIR/empty.stderr")"
RC3=$?
set -e
printf '%s\n' "$OUT3" | sed 's/^/  | /'
check "exit code (no plugin => 1, not an error)" "1" "$RC3"
check "readings line" "1" "$(printf '%s\n' "$OUT3" | grep -c 'readings: active 0')"
check "stderr error lines" "0" "$(grep -ci 'error' "$PROBE_DIR/empty.stderr" || true)"

echo "== case 5: plugin removed (Retro) => its activity-bar mount disappears, zero errors =="
mkdir -p "$PROBE_DIR/uninstall"
cp -R "$ROOT/Plugins/." "$PROBE_DIR/uninstall/"
rm -rf "$PROBE_DIR/uninstall/Retro"
set +e
OUT5="$("$CLI" plugins dump --dir "$PROBE_DIR/uninstall" 2>&1)"
RC5=$?
set -e
printf '%s\n' "$OUT5" | sed 's/^/  | /'
check "exit code (remaining plugin active => 0)" "0" "$RC5"
check "Retro reported as unmounted" "1" "$(printf '%s\n' "$OUT5" | grep -c 'mounts: unmounted=\[Retro\]')"
check "no error wording in output" "0" "$(printf '%s\n' "$OUT5" | grep -ci 'error' || true)"

echo "== case 4: contract guards (no IPC, no licence judgement in the plugin surface) =="
# 只算**代码命中**；注意 macOS 的 grep 要 -n 才带行号，否则 "file:content" 无法按行号剔注释：注释里提到 LicensePresentation 是在解释边界（"能力位只有那一处判据"），
# 把它算作越界会让守卫变成"不许讨论" —— 守卫要挡的是判断，不是文字。
noncomment_hits() {
  local pattern="$1"
  shift
  grep -rnE "$pattern" "$@" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*//' | wc -l | tr -d ' '
}
check "IPC tokens (NSXPC/xpc_) under plugin surface" "0" \
  "$(noncomment_hits 'NSXPC|xpc_' "$ROOT/Core/Plugin" "$ROOT/CLI/PluginCommands.swift")"
check "licence judgement (LicensePresentation) in plugin surface" "0" \
  "$(noncomment_hits 'LicensePresentation' "$ROOT/Core/Plugin")"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "OK: plugin assembly probe, all assertions hold"
  exit 0
fi
echo "FAIL: plugin assembly probe, $FAILURES assertion(s) failed"
exit 1
