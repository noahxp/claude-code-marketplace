#!/usr/bin/env bash
# claude.sh 契約測試：派工 prompt 與 codex、agy 同源；host 寫入的報告走同一套 health check 與命名規則
# 用法：test-claude.sh <claude.sh 路徑>
CLAUDE_SH="${1:?用法: test-claude.sh <claude.sh 路徑>}"
CLAUDE_SH="$(cd "$(dirname "$CLAUDE_SH")" && pwd)/$(basename "$CLAUDE_SH")"

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SANDBOX=$(mktemp -d /tmp/dev-council-testcl.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/repo"

run() { ( cd "$SANDBOX/repo" && /bin/bash "$CLAUDE_SH" "$@" ); }
new_wd() { local d; d=$(mktemp -d "$SANDBOX/wd.XXXXXX"); write_brief "$d"; printf '%s' "$d"; }

echo "-- prompt"
W=$(mktemp -d "$SANDBOX/wd.XXXXXX")
OUT=$(run prompt r1 "$W" 2>&1); RC=$?
check "K1 brief 不合法 → rc=1" "$(is "$RC" 1)" "rc=$RC"

W=$(new_wd)
P="$SANDBOX/prompt.txt"
run prompt r1 "$W" > "$P" 2>&1; RC=$?
check "K2 r1 成功 → rc=0" "$(is "$RC" 0)" "rc=$RC $(cat "$P")"
check "K2b 身分為 Claude subagent" "$(has "$P" '身分是 Claude subagent')"
check "K2c 指向 brief 路徑" "$(has "$P" "$W/brief.md")"
check "K2d 含第一輪輸出格式" "$(has "$P" '## 需要人決定的取捨')"
check "K2e 工作目錄為呼叫時的 cwd" "$(has "$P" "$SANDBOX/repo")"
check "K2f 第一輪結論以「答案」回應 brief 的問題，不限於除錯的根因" \
  "$([ "$(has "$P" '^- 答案：')" = 1 ] && [ "$(lacks "$P" '^- 根因：')" = 1 ] && echo 1 || echo 0)"
check "K2g 需求類問題要先在 repo 的 spec 與文件找依據" "$(has "$P" 'spec')"

OUT=$(run prompt r2 "$W" 2>&1); RC=$?
check "K3 r2 但自己的第一輪不存在 → rc=1" "$(is "$RC" 1)" "rc=$RC"

write_report "$W/round1-claude.md"; write_report "$W/round1-agy.md"; write_report "$W/round1-codex.failed.md"
run prompt r2 "$W" > "$P" 2>&1; RC=$?
check "K4 r2 成功 → rc=0" "$(is "$RC" 0)" "rc=$RC"
check "K4b 列出成功的其他方" "$(has "$P" "agy：$W/round1-agy.md")"
check "K4c 不列失敗的一方" "$(lacks "$P" 'round1-codex')"
check "K4d 含自己的第一輪" "$(has "$P" "$W/round1-claude.md")"
check "K4e 含第二輪輸出格式" "$(has "$P" '## 最終立場')"
check "K4f 第二輪最終立場以「答案」表態" \
  "$([ "$(has "$P" '^- 答案：')" = 1 ] && [ "$(lacks "$P" '^- 根因：')" = 1 ] && echo 1 || echo 0)"

OUT=$(run prompt r3 "$W" 2>&1); RC=$?
check "K5 未知輪次 → rc=1" "$(is "$RC" 1)" "rc=$RC"

echo "-- check"
W=$(new_wd)
F="$W/round1-claude.md"
write_report "$F"
OUT=$(run check r1 "$W" 2>&1); RC=$?
check "C1 合格 → rc=0 並保留原檔" "$([ "$RC" -eq 0 ] && [ -s "$F" ] && echo 1 || echo 0)" "rc=$RC $OUT"

printf '這是一段沒有標題的純文字回覆內容，長度足夠\n' > "$F"
OUT=$(run check r1 "$W" 2>&1); RC=$?
check "C2 不合格 → rc=2 並改名為 .failed.md" \
  "$([ "$RC" -eq 2 ] && [ ! -e "$F" ] && [ -s "$W/round1-claude.failed.md" ] && echo 1 || echo 0)" "rc=$RC"

OUT=$(run check r2 "$W" 2>&1); RC=$?
check "C3 沒有輸出檔（subagent 沒回傳內容）→ rc=2" "$(is "$RC" 2)" "rc=$RC"

OUT=$(run check 2>&1); RC=$?
check "C4 參數不足 → rc=1" "$(is "$RC" 1)" "rc=$RC"

summary
