#!/usr/bin/env bash
# codex.sh 契約測試（以 stub codex 取代真實 cli，不消耗額度）
# 用法：test-codex.sh <codex.sh 路徑>
CODEX_SH="${1:?用法: test-codex.sh <codex.sh 路徑>}"
PASS=0; FAIL=0

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SANDBOX=$(mktemp -d /tmp/codex-delegate-testcx.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# stub codex：把收到的參數寫進 ARG_LOG，依 STUB_RC 決定退出碼
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/codex" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$ARG_LOG"
[ "${STUB_RC:-0}" -ne 0 ] && exit "$STUB_RC"
if [ -n "${STUB_MULTI_ERROR:-}" ]; then
  printf '%s\n' '{"type":"thread.started","thread_id":"x"}'
  printf '%s\n' '{"type":"error","message":"Internal server error while streaming."}'
  printf '%s\n' '{"type":"error","message":"Your workspace is out of credits."}'
  exit 1
fi
if [ -n "${STUB_ERROR:-}" ]; then
  printf '%s\n' '{"type":"thread.started","thread_id":"x"}'
  printf '{"type":"error","message":"%s"}\n' "$STUB_ERROR"
  exit 1
fi
case "$*" in
  *--json*) printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"## 結論\n- 這是 stub 產生的回覆內容，長度足夠通過 health check\n"}}' ;;
  *)        printf 'ok\n' ;;
esac
STUB
chmod +x "$SANDBOX/bin/codex"

check() {
  local desc="$1" cond="$2" detail="${3:-}"
  if [ "$cond" = "1" ]; then printf '  ok   %s\n' "$desc"; ((PASS++))
  else printf '  FAIL %s%s\n' "$desc" "${detail:+ -> $detail}"; ((FAIL++)); fi
}

new_wd() {
  local d; d=$(mktemp -d "$SANDBOX/wd.XXXXXX")
  printf 'STATUS: pending\nTASK: 測試任務\n' > "$d/task.md"
  printf '%s' "$d"
}

run() { PATH="$SANDBOX/bin:$PATH" ARG_LOG="$ARG_LOG" bash "$CODEX_SH" "$@"; }

echo "-- model 參數傳遞"
ARG_LOG="$SANDBOX/args1.log"; : > "$ARG_LOG"
run preflight >/dev/null 2>&1
grep -q -- '--model' "$ARG_LOG" && r=0 || r=1
check "A 未設環境變數時 preflight 不帶 --model" "$r"

ARG_LOG="$SANDBOX/args2.log"; : > "$ARG_LOG"
CODEX_DELEGATE_MODEL=test-model run preflight >/dev/null 2>&1
grep -q -- '--model test-model' "$ARG_LOG" && r=1 || r=0
check "B 設定後 preflight 帶 --model test-model" "$r" "$(cat "$ARG_LOG")"

ARG_LOG="$SANDBOX/args3.log"; : > "$ARG_LOG"
W=$(new_wd); run ready "$W" >/dev/null 2>&1
CODEX_DELEGATE_MODEL=test-model run ask "$W" >/dev/null 2>&1
grep -q -- '--model test-model' "$ARG_LOG" && r=1 || r=0
check "C 設定後 ask 帶同一 --model（與 preflight 一致）" "$r" "$(cat "$ARG_LOG")"

echo "-- session 不落地（--ephemeral）"
ARG_LOG="$SANDBOX/args_eph1.log"; : > "$ARG_LOG"
run preflight >/dev/null 2>&1
grep -q -- '--ephemeral' "$ARG_LOG" && r=1 || r=0
check "N preflight 帶 --ephemeral" "$r" "$(cat "$ARG_LOG")"

ARG_LOG="$SANDBOX/args_eph2.log"; : > "$ARG_LOG"
W=$(new_wd); run ready "$W" >/dev/null 2>&1; run ask "$W" >/dev/null 2>&1
grep -q -- '--ephemeral' "$ARG_LOG" && r=1 || r=0
check "N2 ask 帶 --ephemeral" "$r" "$(cat "$ARG_LOG")"

echo "-- rc 傳遞與 report 執行"
ARG_LOG="$SANDBOX/args4.log"; : > "$ARG_LOG"
W=$(new_wd); run ready "$W" >/dev/null 2>&1
OUT=$(run ask "$W" 2>&1); RC=$?
check "D 成功路徑 rc=0" "$([ "$RC" -eq 0 ] && echo 1 || echo 0)" "rc=$RC"
check "D2 產出 codex-answer.md" "$([ -s "$W/codex-answer.md" ] && echo 1 || echo 0)"

ARG_LOG="$SANDBOX/args5.log"; : > "$ARG_LOG"
W=$(new_wd); run ready "$W" >/dev/null 2>&1
OUT=$(STUB_RC=137 run ask "$W" 2>&1); RC=$?
check "E cli 非零時 rc 原樣傳遞" "$([ "$RC" -eq 137 ] && echo 1 || echo 0)" "rc=$RC"
# 迴歸鎖：run_codex_call 曾在函式內 set -e，覆蓋呼叫端 set +e 而使 report 完全不執行
printf '%s' "$OUT" | grep -q 'rc=137, output=0 bytes' && r=1 || r=0
check "E2 report 仍執行（set -e 未覆蓋呼叫端）" "$r" "$(printf '%s' "$OUT" | head -1)"

echo "-- health check A/B/C（common.sh report）"
# 必須以 bash 執行本檔：common.sh 用 ${BASH_SOURCE[0]} 定位 refusal-patterns.txt，
# 在 zsh 下 source 會解析成錯誤路徑，A 規則被靜默跳過而測不出東西
source "$(dirname "$CODEX_SH")/lib/common.sh"
check "P refusal-patterns.txt 定位正確" "$([ -f "$REFUSAL_PATTERNS" ] && echo 1 || echo 0)" "$REFUSAL_PATTERNS"

hc() {
  local desc="$1" content="$2" want="$3"
  printf '%b' "$content" > "$SANDBOX/hc.md"
  local rc=0
  report "hc" "$SANDBOX/hc.md" /dev/null 0 >/dev/null 2>&1 || rc=$?
  check "$desc" "$([ "$rc" = "$want" ] && echo 1 || echo 0)" "rc=$rc want=$want"
}
hc "Q A 行首中文拒答"        '抱歉，我無法完成此項任務，因為超出範圍\n' 2
hc "Q2 A bullet 內中文拒答"  '## 結論\n- 抱歉，我無法完成此項任務，因為素材涉及我不能處理的範圍\n' 2
hc "Q3 A bullet 內英文拒答"  '## Conclusion\n* I cannot help with this request because it is out of scope\n' 2
hc "R B 無 H2 結構"          '這是一段沒有標題的純文字回覆內容，長度足夠\n' 2
hc "S C H2 空殼無 bullet"    '## 結論\n## 依據\n' 2
hc "Q4 A + 號 bullet 拒答"     '## 結論\n+ 抱歉，我無法完成此項任務，因為素材涉及我不能處理的範圍\n' 2
hc "Q5 A 縮排 bullet 拒答"    '## 結論\n  - 抱歉，我無法完成此項任務，因為素材涉及我不能處理的範圍\n' 2
hc "T 正常四段不誤殺"        '## 結論\n- 這份文件的結構完整，但有兩處需要補強說明\n## 依據\n- 無\n' 0

echo "-- 額度／用量上限（重試無效，須與一般失敗區分）"
ARG_LOG="$SANDBOX/args6.log"; : > "$ARG_LOG"
W=$(new_wd); run ready "$W" >/dev/null 2>&1
OUT=$(STUB_ERROR="Your workspace is out of credits. Ask your workspace owner to refill in order to continue." run ask "$W" 2>&1); RC=$?
printf '%s' "$OUT" | grep -q 'Codex Quota.*out of credits' && r=1 || r=0
check "J ask 額度錯誤標記為 [Codex Quota]" "$r" "$(printf '%s' "$OUT" | tail -1)"
check "J2 ask 額度錯誤回傳 rc=3" "$([ "$RC" -eq 3 ] && echo 1 || echo 0)" "rc=$RC"

ARG_LOG="$SANDBOX/args7.log"; : > "$ARG_LOG"
OUT=$(STUB_ERROR="You have hit your usage limit for this session." run preflight 2>&1); RC=$?
check "K preflight 也攔得到額度問題（rc=3）" "$([ "$RC" -eq 3 ] && echo 1 || echo 0)" "rc=$RC"
printf '%s' "$OUT" | grep -q '重試無效' && r=1 || r=0
check "K2 preflight 訊息明說重試無效" "$r" "$(printf '%s' "$OUT" | head -1)"

ARG_LOG="$SANDBOX/args_multi.log"; : > "$ARG_LOG"
W=$(new_wd); run ready "$W" >/dev/null 2>&1
OUT=$(STUB_MULTI_ERROR=1 run ask "$W" 2>&1); RC=$?
printf '%s' "$OUT" | grep -q 'Codex Quota' && r=1 || r=0
check "O quota 排在一般錯誤之後仍被辨識" "$r" "$(printf '%s' "$OUT" | tail -1)"
check "O2 多錯誤事件仍回傳 rc=3" "$([ "$RC" -eq 3 ] && echo 1 || echo 0)" "rc=$RC"

ARG_LOG="$SANDBOX/args8.log"; : > "$ARG_LOG"
W=$(new_wd); run ready "$W" >/dev/null 2>&1
OUT=$(STUB_ERROR="Internal server error while streaming." run ask "$W" 2>&1); RC=$?
printf '%s' "$OUT" | grep -q 'Codex Error.*Internal server' && r=1 || r=0
check "L 非額度錯誤標記為 [Codex Error]（不誤判為 Quota）" "$r" "$(printf '%s' "$OUT" | tail -1)"
printf '%s' "$OUT" | grep -q 'Codex Quota' && r=0 || r=1
check "L2 一般錯誤不含 Quota 標記" "$r"

echo "-- 核心安全契約：後處理指示不得進入 codex prompt"
INIT_SH="$(dirname "$CODEX_SH")/init.sh"
if [ -f "$INIT_SH" ]; then
  MARKER="SENTINEL_FOLLOWUP_MUST_NOT_LEAK_9271"
  IOUT=$(bash "$INIT_SH" "分析這份規格文件的完整性 -- $MARKER")
  IROOT=$(field_of ROOT "$IOUT")
  IW=$(field_of WORKDIR "$IOUT")
  ARG_LOG="$SANDBOX/args9.log"; : > "$ARG_LOG"
  run ready "$IW" >/dev/null 2>&1
  run ask "$IW" >/dev/null 2>&1
  grep -q "$MARKER" "$ARG_LOG" && r=0 || r=1
  check "M followup 內容未出現在 codex 收到的參數中" "$r"
  grep -q "$MARKER" "$IROOT/host-followup.md" && r=1 || r=0
  check "M2 followup 確實有寫入 host-followup.md（確認測試有效）" "$r"
  [ -e "$IW/host-followup.md" ] && r=0 || r=1
  check "M3 host-followup.md 不在 codex workdir 內" "$r"
  safe_rm "$IROOT"
else
  printf '  SKIP M 找不到 init.sh，略過契約測試\n'
fi

echo "-- ready 只改首行"
W=$(new_wd)
{ printf '=== material.sh ===\n'; printf "printf 'STATUS: pending'\n"; printf 'STATUS: pending\n'; } >> "$W/task.md"
BEFORE=$(grep -c 'STATUS: pending' "$W/task.md")
run ready "$W" >/dev/null 2>&1
AFTER=$(grep -c 'STATUS: pending' "$W/task.md")
check "F 首行翻轉為 ready" "$([ "$(head -1 "$W/task.md")" = "STATUS: ready" ] && echo 1 || echo 0)"
check "G 素材內同名字串不被污染（${BEFORE} -> ${AFTER}，應少 1）" \
      "$([ "$AFTER" -eq "$((BEFORE - 1))" ] && echo 1 || echo 0)"

echo "-- fail-fast 路徑"
W=$(new_wd); printf 'NOT-A-STATUS\n' > "$W/task.md"
run ready "$W" >/dev/null 2>&1 && r=0 || r=1
check "H 首行非 STATUS 時 ready 拒絕改寫" "$r"

W=$(new_wd)
run ask "$W" >/dev/null 2>&1 && r=0 || r=1
check "I STATUS: pending 時 ask fail-fast" "$r"

echo "-- STATUS 契約精確性"
status_case() {
  local desc="$1" val="$2" want_ready="$3" want_ask="$4"
  local w; w=$(mktemp -d "$SANDBOX/st.XXXXXX")
  printf '%s\nTASK: x\n' "$val" > "$w/task.md"
  local gr ga
  run ready "$w" >/dev/null 2>&1 && gr=accept || gr=reject
  printf '%s\nTASK: x\n' "$val" > "$w/task.md"
  run ask "$w" 2>&1 | grep -q '尚未就緒' && ga=reject || ga=accept
  check "$desc" "$([ "$gr" = "$want_ready" ] && [ "$ga" = "$want_ask" ] && echo 1 || echo 0)" \
        "ready=$gr(want $want_ready) ask=$ga(want $want_ask)"
}
status_case "U ready 後綴不得矇混"  "STATUS: ready-but-not-really" reject reject
status_case "U2 pending 後綴不得矇混" "STATUS: pending-junk"        reject reject
status_case "U3 ready 重複呼叫為冪等" "STATUS: ready"               accept accept

echo "-- safe_rm 路徑防護"
VICTIM=$(mktemp -d "$SANDBOX/victim.XXXXXX"); : > "$VICTIM/keep.txt"
ESCAPE=$(mktemp -d /tmp/codex-delegate-esc.XXXXXX); ln -s "$VICTIM" "$ESCAPE/link"
safe_rm "$ESCAPE/link/keep.txt" >/dev/null 2>&1
check "V 中間元件為 symlink 時不刪" "$([ -f "$VICTIM/keep.txt" ] && echo 1 || echo 0)"
safe_rm "/tmp/codex-delegate-x/../../../etc/passwd" >/dev/null 2>&1
check "V2 含 .. 的路徑不刪" "$([ -f /etc/passwd ] && echo 1 || echo 0)"
safe_rm "$ESCAPE" >/dev/null 2>&1
check "V3 合法根目錄仍會刪除" "$([ -d "$ESCAPE" ] && echo 0 || echo 1)"
rm -rf "$VICTIM" "$ESCAPE"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
