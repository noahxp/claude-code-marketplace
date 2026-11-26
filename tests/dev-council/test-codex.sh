#!/usr/bin/env bash
# codex.sh 契約測試（以 stub codex 取代真實 cli，不消耗額度）
# 用法：test-codex.sh <codex.sh 路徑>
CODEX_SH="${1:?用法: test-codex.sh <codex.sh 路徑>}"
CODEX_SH="$(cd "$(dirname "$CODEX_SH")" && pwd)/$(basename "$CODEX_SH")"

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SANDBOX=$(mktemp -d /tmp/dev-council-testcx.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# stub codex：
#   login status → 依 STUB_LOGIN_RC
#   exec        → 參數寫入 ARG_LOG；依 STUB_FAIL_ONCE_RC / STUB_RC / STUB_ERROR / STUB_STDERR / STUB_TEXT 決定輸出
mkdir -p "$SANDBOX/bin" "$SANDBOX/nobin" "$SANDBOX/repo"
cat > "$SANDBOX/bin/codex" <<'STUB'
#!/bin/bash
if [ "$1" = "login" ]; then
  if [ "${STUB_LOGIN_RC:-0}" -ne 0 ]; then echo "Not logged in"; exit "$STUB_LOGIN_RC"; fi
  echo "Logged in using ChatGPT"; exit 0
fi
printf '%s\n' "$*" >> "$ARG_LOG"
echo x >> "$CALL_LOG"
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
if [ -n "${STUB_FAIL_ONCE_RC:-}" ] && [ ! -e "$STUB_STATE" ]; then : > "$STUB_STATE"; exit "$STUB_FAIL_ONCE_RC"; fi
[ -n "${STUB_STDERR:-}" ] && printf '%s\n' "$STUB_STDERR" >&2
[ "${STUB_RC:-0}" -ne 0 ] && exit "$STUB_RC"
if [ -n "${STUB_ERROR:-}" ]; then
  printf '%s\n' '{"type":"thread.started","thread_id":"x"}'
  jq -cn --arg m "$STUB_ERROR" '{type:"error",message:$m}'
  exit 1
fi
TEXT="${STUB_TEXT:-## 結論
- 根因：stub 產生的根因說明，長度足夠通過 health check}"
jq -cn --arg t "$TEXT" '{type:"item.completed",item:{type:"agent_message",text:$t}}'
STUB
chmod +x "$SANDBOX/bin/codex"

# run [env...] -- <子命令與參數>：以 repo 為 cwd、stub 優先於真實 codex 執行
run() {
  ( cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" ARG_LOG="$ARG_LOG" CALL_LOG="$CALL_LOG" \
      STUB_STATE="$SANDBOX/state" DEV_COUNCIL_COOLDOWN_WAIT=0 /bin/bash "$CODEX_SH" "$@" )
}
fresh() {
  ARG_LOG="$SANDBOX/args.$1.log"; CALL_LOG="$SANDBOX/calls.$1.log"
  : > "$ARG_LOG"; : > "$CALL_LOG"; rm -f "$SANDBOX/state"
}
calls() { wc -l < "$CALL_LOG" | tr -d ' '; }
new_wd() { local d; d=$(mktemp -d "$SANDBOX/wd.XXXXXX"); write_brief "$d"; printf '%s' "$d"; }

echo "-- preflight"
fresh p1
OUT=$( cd "$SANDBOX/repo" && PATH="$SANDBOX/nobin:/usr/bin:/bin" /bin/bash "$CODEX_SH" preflight 2>&1 ); RC=$?
check "P1 codex 未安裝 → rc=5" "$(is "$RC" 5)" "rc=$RC $OUT"

fresh p2
OUT=$(STUB_LOGIN_RC=1 run preflight 2>&1); RC=$?
check "P2 login status 失敗 → rc=4" "$(is "$RC" 4)" "rc=$RC"
check "P2b 提示在另一個視窗執行 codex login" \
  "$(printf '%s' "$OUT" | grep -q '另一個.*codex login' && echo 1 || echo 0)" "$OUT"
check "P2c 未登入時不試跑（不耗額度）" "$(is "$(calls)" 0)"

fresh p3
OUT=$(STUB_ERROR="Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again." run preflight 2>&1); RC=$?
check "P3 試跑回報登入失效 → rc=4" "$(is "$RC" 4)" "rc=$RC $OUT"

fresh p4
OUT=$(STUB_ERROR="Your workspace is out of credits." run preflight 2>&1); RC=$?
check "P4 試跑回報額度 → rc=3" "$(is "$RC" 3)" "rc=$RC"

fresh p5
OUT=$(STUB_ERROR="Internal server error while streaming." run preflight 2>&1); RC=$?
check "P5 試跑一般錯誤 → rc=2" "$(is "$RC" 2)" "rc=$RC"

fresh p6
OUT=$(STUB_RC=1 STUB_STDERR="Error: 401 Unauthorized" run preflight 2>&1); RC=$?
check "P6 只有 stderr 的登入失效也辨識 → rc=4" "$(is "$RC" 4)" "rc=$RC $OUT"

fresh p7
OUT=$(run preflight 2>&1); RC=$?
check "P7 正常 → rc=0" "$(is "$RC" 0)" "rc=$RC $OUT"
check "P7b 試跑帶 --sandbox read-only" "$(has "$ARG_LOG" '--sandbox read-only')" "$(cat "$ARG_LOG")"
check "P7c 試跑帶 --ephemeral" "$(has "$ARG_LOG" '--ephemeral')"

fresh p8
check "P8 preflight 中途被終止仍清掉暫存目錄" "$(interrupted_preflight_is_clean "$CODEX_SH" \
  PATH="$SANDBOX/bin:$PATH" ARG_LOG="$ARG_LOG" CALL_LOG="$CALL_LOG" STUB_STATE="$SANDBOX/state" STUB_SLEEP=2)"

echo "-- r1"
fresh r1
W=$(mktemp -d "$SANDBOX/wd.XXXXXX")
OUT=$(run r1 "$W" 2>&1); RC=$?
check "R1 brief 不合法 → rc=1 且未呼叫 codex" "$([ "$RC" -eq 1 ] && [ "$(calls)" -eq 0 ] && echo 1 || echo 0)" "rc=$RC calls=$(calls)"

fresh r2
W=$(new_wd)
OUT=$(run r1 "$W" 2>&1); RC=$?
check "R2 成功 → rc=0 並產出 round1-codex.md" "$([ "$RC" -eq 0 ] && [ -s "$W/round1-codex.md" ] && echo 1 || echo 0)" "rc=$RC $OUT"
check "R3 prompt 指向 brief 路徑" "$(has "$ARG_LOG" "$W/brief.md")"
check "R3b prompt 含第一輪輸出格式" "$(has "$ARG_LOG" '## 需要人決定的取捨')"
check "R3c 帶 --sandbox read-only" "$(has "$ARG_LOG" '--sandbox read-only')"
check "R3d 帶 --ephemeral" "$(has "$ARG_LOG" '--ephemeral')"
check "R3e prompt 寫明工作目錄為呼叫時的 cwd" "$(has "$ARG_LOG" "$SANDBOX/repo")"
check "R3f prompt 提示可用 git log 等唯讀指令（只有 agy 受允許清單限制）" "$(has "$ARG_LOG" '唯讀指令（git log、git diff、git blame、grep 等）')"

fresh r4
W=$(new_wd)
OUT=$(STUB_ERROR="unexpected status 401 Unauthorized" run r1 "$W" 2>&1); RC=$?
check "R4 登入失效 → rc=4" "$(is "$RC" 4)" "rc=$RC"
check "R4b 不留成功檔" "$([ ! -e "$W/round1-codex.md" ] && echo 1 || echo 0)"
check "R4c 提示在另一個視窗執行 codex login" \
  "$(printf '%s' "$OUT" | grep -q '另一個.*codex login' && echo 1 || echo 0)" "$OUT"

fresh r5
W=$(new_wd)
OUT=$(STUB_ERROR="You have hit your usage limit." run r1 "$W" 2>&1); RC=$?
check "R5 額度 → rc=3" "$(is "$RC" 3)" "rc=$RC"

fresh r6
W=$(new_wd)
OUT=$(STUB_TEXT="這是一段沒有標題的純文字回覆內容，長度足夠" run r1 "$W" 2>&1); RC=$?
check "R6 health check 不過 → rc=2" "$(is "$RC" 2)" "rc=$RC"
check "R6b 改名為 .failed.md，不留成功檔" \
  "$([ -s "$W/round1-codex.failed.md" ] && [ ! -e "$W/round1-codex.md" ] && echo 1 || echo 0)"

fresh r7
W=$(new_wd)
OUT=$(STUB_FAIL_ONCE_RC=137 run r1 "$W" 2>&1); RC=$?
check "R7 啟動即被終止（rc=137）→ 等待後重試一次並成功" \
  "$([ "$RC" -eq 0 ] && [ "$(calls)" -eq 2 ] && [ -s "$W/round1-codex.md" ] && echo 1 || echo 0)" "rc=$RC calls=$(calls)"

fresh r8
W=$(new_wd)
OUT=$(STUB_RC=137 run r1 "$W" 2>&1); RC=$?
check "R8 連續兩次 rc=137 → rc=2，只重試一次" \
  "$([ "$RC" -eq 2 ] && [ "$(calls)" -eq 2 ] && echo 1 || echo 0)" "rc=$RC calls=$(calls)"

fresh r9
W=$(new_wd)
DEV_COUNCIL_CODEX_MODEL=test-model run r1 "$W" >/dev/null 2>&1
check "R9 DEV_COUNCIL_CODEX_MODEL 帶入 --model" "$(has "$ARG_LOG" '--model test-model')"

fresh r10
W=$(new_wd); write_report "$W/round1-codex.failed.md"
run r1 "$W" >/dev/null 2>&1
check "R10 重跑成功後清掉上次的 .failed.md" "$([ ! -e "$W/round1-codex.failed.md" ] && echo 1 || echo 0)"

fresh r11
W=$(new_wd)
OUT=$(STUB_TEXT=$'## 結論\n- 根因：API 回 401 Unauthorized，因為 refresh token 已過期卻沒有重新取得' run r1 "$W" 2>&1); RC=$?
check "R11 回覆內容談到 401 與 refresh token 不誤判為登入失效" "$(is "$RC" 0)" "rc=$RC"

fresh r12
W=$(new_wd)
OUT=$(STUB_ERROR="Reconnecting... 2/5 (unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: wss://api.openai.com/v1/responses, cf-ray: a606d7df3fa8b2fe-TPE)" run r1 "$W" 2>&1); RC=$?
check "R12 登出時的實測錯誤事件 → rc=4" "$(is "$RC" 4)" "rc=$RC"

echo "-- r2"
fresh s1
W=$(new_wd); write_report "$W/round1-claude.md"
OUT=$(run r2 "$W" 2>&1); RC=$?
check "S1 自己的第一輪不存在 → rc=1" "$(is "$RC" 1)" "rc=$RC"

fresh s2
W=$(new_wd); write_report "$W/round1-codex.md"; write_report "$W/round1-agy.failed.md"
OUT=$(run r2 "$W" 2>&1); RC=$?
check "S2 沒有其他方的成功檔 → rc=1" "$(is "$RC" 1)" "rc=$RC"

fresh s3
W=$(new_wd); write_report "$W/round1-codex.md"; write_report "$W/round1-claude.md"; write_report "$W/round1-agy.failed.md"
OUT=$(run r2 "$W" 2>&1); RC=$?
check "S3 成功 → round2-codex.md" "$([ "$RC" -eq 0 ] && [ -s "$W/round2-codex.md" ] && echo 1 || echo 0)" "rc=$RC $OUT"
check "S3b prompt 列出成功的其他方" "$(has "$ARG_LOG" "$W/round1-claude.md")"
check "S3c prompt 不列失敗的一方" "$(lacks "$ARG_LOG" 'round1-agy')"
check "S3d prompt 含自己的第一輪" "$(has "$ARG_LOG" "$W/round1-codex.md")"
check "S3e prompt 含第二輪輸出格式" "$(has "$ARG_LOG" '## 最終立場')"

echo "-- 用法錯誤"
OUT=$(run nope 2>&1); RC=$?
check "U1 未知子命令 → rc=1" "$(is "$RC" 1)"
OUT=$(run r1 "$SANDBOX/does-not-exist" 2>&1); RC=$?
check "U2 workdir 不存在 → rc=1" "$(is "$RC" 1)"

summary
