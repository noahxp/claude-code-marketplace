#!/usr/bin/env bash
# agy.sh 契約測試（以 stub agy 取代真實 cli，不消耗額度）
# 用法：test-agy.sh <agy.sh 路徑>
AGY_SH="${1:?用法: test-agy.sh <agy.sh 路徑>}"
AGY_SH="$(cd "$(dirname "$AGY_SH")" && pwd)/$(basename "$AGY_SH")"

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SANDBOX=$(mktemp -d /tmp/dev-council-testag.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# stub agy：參數與實際 cwd 寫入 ARG_LOG；STUB_OUT 有設定時原樣輸出，否則依 prompt 回覆 ok 或 sentinel 包覆的報告
mkdir -p "$SANDBOX/bin" "$SANDBOX/nobin" "$SANDBOX/repo"
cat > "$SANDBOX/bin/agy" <<'STUB'
#!/bin/bash
{ printf 'ARGS: %s\n' "$*"; printf 'PWD: %s\n' "$(pwd -P)"; } >> "$ARG_LOG"
echo x >> "$CALL_LOG"
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
[ -n "${STUB_STDERR:-}" ] && printf '%s\n' "$STUB_STDERR" >&2
if [ -n "${STUB_OUT+x}" ]; then [ -n "$STUB_OUT" ] && printf '%s\n' "$STUB_OUT"; exit "${STUB_RC:-0}"; fi
[ "${STUB_RC:-0}" -ne 0 ] && exit "$STUB_RC"
case "$*" in
  *"Reply only with: ok"*) echo ok ;;
  *) printf '思考中的雜訊\n<council-report>\n## 結論\n- 根因：stub 產生的根因說明，長度足夠通過 health check\n</council-report>\n' ;;
esac
STUB
chmod +x "$SANDBOX/bin/agy"

run() {
  ( cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" ARG_LOG="$ARG_LOG" CALL_LOG="$CALL_LOG" /bin/bash "$AGY_SH" "$@" )
}
fresh() { ARG_LOG="$SANDBOX/args.$1.log"; CALL_LOG="$SANDBOX/calls.$1.log"; : > "$ARG_LOG"; : > "$CALL_LOG"; }
calls() { wc -l < "$CALL_LOG" | tr -d ' '; }
new_wd() { local d; d=$(mktemp -d "$SANDBOX/wd.XXXXXX"); write_brief "$d"; printf '%s' "$d"; }
login_hint() { printf '%s' "$1" | grep -q '另一個.*agy' && echo 1 || echo 0; }

# 允許規則只比對指令開頭、不檢查參數：清單須完全相符，增減指令都要先改這裡
ALLOW_RE='--settings \{"permissions":\{"allow":\["command\(git blame\)","command\(git status\)","command\(git ls-files\)","command\(grep\)","command\(ls\)"\]\}\}'

echo "-- preflight"
fresh p1
OUT=$( cd "$SANDBOX/repo" && PATH="$SANDBOX/nobin:/usr/bin:/bin" /bin/bash "$AGY_SH" preflight 2>&1 ); RC=$?
check "P1 agy 未安裝 → rc=5" "$(is "$RC" 5)" "rc=$RC $OUT"

fresh p2
OUT=$(run preflight 2>&1); RC=$?
check "P2 正常 → rc=0" "$(is "$RC" 0)" "rc=$RC $OUT"
check "P2b 帶 --sandbox" "$(has "$ARG_LOG" '--sandbox')"
check "P2c 帶 --mode plan（headless 預設的 Auto mode 會直接改檔）" "$(has "$ARG_LOG" '--mode plan')"
check "P2d 不在 repo 內試跑" "$(lacks "$ARG_LOG" "PWD: $(cd "$SANDBOX/repo" && pwd -P)\$")"
check "P2e 試跑帶與正式輪次相同的 --settings（設定無效時在此攔下）" "$(has "$ARG_LOG" "$ALLOW_RE")"

fresh p3
OUT=$(STUB_RC=1 STUB_STDERR="UNAUTHENTICATED: Request had invalid authentication credentials." run preflight 2>&1); RC=$?
check "P3 stderr 登入失效 → rc=4" "$(is "$RC" 4)" "rc=$RC"
check "P3b 提示在另一個視窗登入 agy" "$(login_hint "$OUT")" "$OUT"

fresh p4
OUT=$(STUB_OUT="Error: Authentication required" run preflight 2>&1); RC=$?
check "P4 rc=0 但輸出為登入失效 → rc=4" "$(is "$RC" 4)" "rc=$RC"

fresh p5
OUT=$(STUB_RC=1 STUB_OUT="RESOURCE_EXHAUSTED: Quota exceeded" run preflight 2>&1); RC=$?
check "P5 額度 → rc=3" "$(is "$RC" 3)" "rc=$RC"

fresh p6
OUT=$(STUB_OUT="Error: timed out after 90s" run preflight 2>&1); RC=$?
check "P6 逾時 → rc=2" "$(is "$RC" 2)" "rc=$RC"

fresh p7
OUT=$(STUB_OUT="" STUB_STDERR='jetski: no output produced — a tool required the "command" permission' run preflight 2>&1); RC=$?
check "P7 rc=0 但沒回 ok → rc=2" "$(is "$RC" 2)" "rc=$RC"

fresh p8
OUT=$(DEV_COUNCIL_AGY_PREFLIGHT_TIMEOUT=abc run preflight 2>&1); RC=$?
check "P8 timeout 格式錯誤 → rc=1 且未呼叫 agy" "$([ "$RC" -eq 1 ] && [ "$(calls)" -eq 0 ] && echo 1 || echo 0)" "rc=$RC"

fresh p9
DEV_COUNCIL_AGY_MODEL=test-model run preflight >/dev/null 2>&1
check "P9 DEV_COUNCIL_AGY_MODEL 帶入 --model" "$(has "$ARG_LOG" '--model test-model')"

AGY_LOGOUT_ERR=$'Authentication required. Please visit the URL to log in:\n  https://accounts.google.com/o/oauth2/auth?access_type=offline\n\nWaiting for authentication (timeout 60s)...\nOr, paste the authorization code here and press Enter:\nError: authentication timed out.\nerror: authentication failed or timed out'

fresh p11
OUT=$(STUB_OUT="" STUB_STDERR="$AGY_LOGOUT_ERR" run preflight 2>&1); RC=$?
check "P11 登出時的實測訊息 → rc=4" "$(is "$RC" 4)" "rc=$RC"
check "P11b stdout 為空時不印誤導的「無 stderr 紀錄」" "$(printf '%s' "$OUT" | grep -q '無 stderr 紀錄' && echo 0 || echo 1)" "$OUT"
check "P11c 登入的 timed out 不附加調大時間上限的提示" "$(printf '%s' "$OUT" | grep -q 'PREFLIGHT_TIMEOUT' && echo 0 || echo 1)"

fresh p10
check "P10 preflight 中途被終止仍清掉暫存目錄" "$(interrupted_preflight_is_clean "$AGY_SH" \
  PATH="$SANDBOX/bin:$PATH" ARG_LOG="$ARG_LOG" CALL_LOG="$CALL_LOG" STUB_SLEEP=2)"

echo "-- r1"
fresh r1
W=$(mktemp -d "$SANDBOX/wd.XXXXXX")
OUT=$(run r1 "$W" 2>&1); RC=$?
check "R1 brief 不合法 → rc=1 且未呼叫 agy" "$([ "$RC" -eq 1 ] && [ "$(calls)" -eq 0 ] && echo 1 || echo 0)" "rc=$RC"

fresh r2
W=$(new_wd)
OUT=$(run r1 "$W" 2>&1); RC=$?
check "R2 成功 → rc=0 並產出 round1-agy.md" "$([ "$RC" -eq 0 ] && [ -s "$W/round1-agy.md" ] && echo 1 || echo 0)" "rc=$RC $OUT"
check "R2b 只保留 sentinel 內的內容" \
  "$([ "$(has "$W/round1-agy.md" '思考中|council-report')" = 0 ] && [ "$(has "$W/round1-agy.md" '^## 結論')" = 1 ] && echo 1 || echo 0)"
check "R3 帶 --sandbox 與 --mode plan" \
  "$([ "$(has "$ARG_LOG" '--sandbox')" = 1 ] && [ "$(has "$ARG_LOG" '--mode plan')" = 1 ] && echo 1 || echo 0)"
check "R3b 以 --add-dir 加入 workdir（brief 與各方報告所在）" "$(has "$ARG_LOG" "--add-dir $W")"
check "R3c 在 repo（呼叫時的 cwd）內執行，git 指令不需 -C 前綴" "$(has "$ARG_LOG" "PWD: $(cd "$SANDBOX/repo" && pwd -P)\$")"
check "R3d prompt 指向 brief 路徑" "$(has "$ARG_LOG" "$W/brief.md")"
check "R3e prompt 含第一輪輸出格式" "$(has "$ARG_LOG" '## 需要人決定的取捨')"
check "R3f --settings 只允許沒有寫檔或執行參數的指令（rg --pre、git grep -O、git log/diff/show --output 會繞過唯讀）" "$(has "$ARG_LOG" "$ALLOW_RE")"
check "R3g 允許清單不含會寫入的指令" "$(lacks "$ARG_LOG" 'command\((\*|git -C|git commit|sed|rm|python)')"
check "R3h prompt 列出可用指令並說明清單外會讓整輪失敗" "$(has "$ARG_LOG" '清單外的指令')"
check "R3i prompt 列出的指令與允許清單一致" "$(has "$ARG_LOG" '你只能執行這些唯讀指令：git blame、git status、git ls-files、grep、ls。')"
check "R3j prompt 不提及清單外的 git 指令（照做會被拒，整輪沒有輸出）" "$(lacks "$ARG_LOG" 'git (log|diff|show|grep)')"

fresh r4
W=$(new_wd)
OUT=$(STUB_OUT=$'<council-report>\n## 結論\n- 根因：輸出到一半就被截斷的回覆內容' run r1 "$W" 2>&1); RC=$?
check "R4 缺閉合 sentinel → rc=2 且不留成功檔" "$([ "$RC" -eq 2 ] && [ ! -e "$W/round1-agy.md" ] && echo 1 || echo 0)" "rc=$RC"

fresh r5
W=$(new_wd)
OUT=$(STUB_OUT="" STUB_STDERR="UNAUTHENTICATED: Request had invalid authentication credentials." run r1 "$W" 2>&1); RC=$?
check "R5 rc=0、無 sentinel、stderr 為登入失效 → rc=4" "$(is "$RC" 4)" "rc=$RC"
check "R5b 提示在另一個視窗登入 agy" "$(login_hint "$OUT")" "$OUT"

fresh r6
W=$(new_wd)
OUT=$(STUB_RC=1 STUB_OUT="Error: RESOURCE_EXHAUSTED: Quota exceeded" run r1 "$W" 2>&1); RC=$?
check "R6 額度 → rc=3" "$(is "$RC" 3)" "rc=$RC"

fresh r7
W=$(new_wd)
DEV_COUNCIL_AGY_MODEL=test-model run r1 "$W" >/dev/null 2>&1
check "R7 DEV_COUNCIL_AGY_MODEL 帶入 --model" "$(has "$ARG_LOG" '--model test-model')"

fresh r8
W=$(new_wd)
OUT=$(STUB_OUT=$'<council-report>\n這是一段沒有標題的純文字回覆內容，長度足夠\n</council-report>' run r1 "$W" 2>&1); RC=$?
check "R8 health check 不過 → rc=2 並改名為 .failed.md" \
  "$([ "$RC" -eq 2 ] && [ -s "$W/round1-agy.failed.md" ] && [ ! -e "$W/round1-agy.md" ] && echo 1 || echo 0)" "rc=$RC"

fresh r9
W=$(new_wd)
OUT=$(STUB_OUT=$'<council-report>\n## 結論\n- 根因：src/app.py:401 的分支沒有處理空 token 的情況\n</council-report>' run r1 "$W" 2>&1); RC=$?
check "R9 成功回覆內含 401 字樣不誤判為登入失效" "$(is "$RC" 0)" "rc=$RC"

fresh r10
W=$(new_wd)
OUT=$(STUB_OUT=$'正在檢查 refresh token 的處理流程\n<council-report>\n## 結論\n- 根因：API 回 401 Unauthorized，因為 refresh token 已過期卻沒有重新取得' run r1 "$W" 2>&1); RC=$?
check "R10 回覆被截斷且內容談到 401 與 refresh token → rc=2，不誤判為登入失效" "$(is "$RC" 2)" "rc=$RC"

fresh r11
W=$(new_wd)
run r1 "$W" >/dev/null 2>&1
check "R11 每輪預設時間上限 600s（第二輪要讀三份報告再查證，實測 300s 會逾時）" "$(has "$ARG_LOG" '--print-timeout 600s')"

fresh r12
W=$(new_wd)
OUT=$(STUB_OUT="" STUB_STDERR=$'error: print timeout after 5m0s with the turn still in progress; the response is partial\nAGY_ERROR: {"status":"DEADLINE_EXCEEDED","reason":"print_timeout"}' run r1 "$W" 2>&1); RC=$?
check "R12 新版逾時訊息（print timeout）→ rc=2" "$(is "$RC" 2)" "rc=$RC"
check "R12b 附上調大時間上限的提示" "$(printf '%s' "$OUT" | grep -q 'DEV_COUNCIL_AGY_PRINT_TIMEOUT' && echo 1 || echo 0)" "$OUT"

fresh r13
W=$(new_wd)
OUT=$(STUB_OUT="" STUB_STDERR="$AGY_LOGOUT_ERR" run r1 "$W" 2>&1); RC=$?
check "R13 第一輪遇到登出時的實測訊息 → rc=4" "$(is "$RC" 4)" "rc=$RC"

echo "-- r2"
fresh s1
W=$(new_wd); write_report "$W/round1-claude.md"
OUT=$(run r2 "$W" 2>&1); RC=$?
check "S1 自己的第一輪不存在 → rc=1" "$(is "$RC" 1)" "rc=$RC"

fresh s2
W=$(new_wd); write_report "$W/round1-agy.md"; write_report "$W/round1-claude.md"; write_report "$W/round1-codex.failed.md"
OUT=$(run r2 "$W" 2>&1); RC=$?
check "S2 成功 → round2-agy.md" "$([ "$RC" -eq 0 ] && [ -s "$W/round2-agy.md" ] && echo 1 || echo 0)" "rc=$RC $OUT"
check "S2b prompt 列出成功的其他方" "$(has "$ARG_LOG" "$W/round1-claude.md")"
check "S2c prompt 不列失敗的一方" "$(lacks "$ARG_LOG" 'round1-codex')"
check "S2d prompt 含第二輪輸出格式" "$(has "$ARG_LOG" '## 最終立場')"

summary
