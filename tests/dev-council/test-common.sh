#!/usr/bin/env bash
# lib/common.sh 單元測試：失敗分類、brief 檢查、health check、輸出檔命名、其他方成功檔清單
# 用法：test-common.sh <scripts 目錄>
# 必須以 bash 執行：common.sh 以 ${BASH_SOURCE[0]} 定位同目錄的 refusal-patterns.txt
SCRIPTS="${1:?用法: test-common.sh <scripts 目錄>}"

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
# shellcheck source=/dev/null
source "$SCRIPTS/lib/common.sh"

SANDBOX=$(mktemp -d /tmp/dev-council-testcm.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

echo "-- classify_failure：登入失效"
cf() { check "$1" "$(is "$(classify_failure "$2")" "$3")" "got=$(classify_failure "$2") text=$2"; }
cf "A1 401 Unauthorized"                 "unexpected status 401 Unauthorized: Missing bearer" auth
cf "A2 refresh token 失效要求重新登入"    "Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again." auth
cf "A3 UNAUTHENTICATED"                  "UNAUTHENTICATED: Request had invalid authentication credentials." auth
cf "A4 Not logged in"                    "Not logged in" auth
cf "A5 Authentication required"          "Authentication required" auth
cf "A6 agy 要求重新登入"                  "Sign-in update needed: run /logout and sign in again" auth
cf "A7 token expired"                    "error: token has expired" auth
cf "A8 codex 登出時的實測事件"            "Reconnecting... 2/5 (unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: wss://api.openai.com/v1/responses, cf-ray: a606d7df3fa8b2fe-TPE)" auth
cf "A9 agy 登出時的實測訊息"              "Authentication required. Please visit the URL to log in:" auth

echo "-- classify_failure：token 過期（codex 0.172.0 執行檔內的固定訊息，社群回報可見 revoked、already used 兩種）"
cf "T1 codex refresh token 過期"         "Your access token could not be refreshed because your refresh token has expired. Please log out and sign in again." auth
cf "T2 codex refresh token 已被使用"     "Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again." auth
cf "T3 codex refresh token 已撤銷"       "Your access token could not be refreshed because your refresh token was revoked. Please log out and sign in again." auth
cf "T4 codex 已登出或改登其他帳號"       "Your access token could not be refreshed because you have since logged out or signed in to another account. Please sign in again." auth
cf "T5 codex 未說明原因"                 "Your access token could not be refreshed. Please log out and sign in again." auth

echo "-- classify_failure：token 過期（agy 1.5.18 執行檔內的訊息與 Google OAuth 的回應）"
cf "T6 agy 等待登入逾時（單獨出現）"      "Error: authentication timed out." auth
cf "T7 Google OAuth refresh token 失效"  "Token has been expired or revoked." auth
cf "T8 agy session 過期"                 "session expired or revoked" auth
cf "T9 agy 未登入 Antigravity"           "not logged into Antigravity." auth
cf "T10 agy 要求登入才能列出模型"         "Please sign in to view available models. Launch the CLI without arguments to sign in." auth
cf "T11 agy 無 TTY 無法互動登入"          "not logged in and no controlling terminal; cannot complete interactive login" auth
cf "T12 登入時網路失敗屬一般失敗（重試）"  "token exchange failed: Post https://oauth2.googleapis.com/token: dial tcp: connect: network is unreachable" other

echo "-- classify_failure：額度"
cf "Q1 out of credits"                   "Your workspace is out of credits." quota
cf "Q2 usage limit"                      "You have hit your usage limit for this session." quota
cf "Q3 RESOURCE_EXHAUSTED"               "RESOURCE_EXHAUSTED: Quota exceeded for model" quota
cf "Q4 429 Too Many Requests"            "429 Too Many Requests" quota

echo "-- classify_failure：其他"
cf "O1 伺服器錯誤"                        "Internal server error while streaming." other
cf "O2 檔案行號 401 不算登入失效"          "see src/app.py:401 for the failing branch" other
cf "O3 headless 權限拒絕不算登入失效"      'jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for' other
cf "O4 空字串"                            "" other

echo "-- classify_failure：同時命中時登入優先"
cf "X1 401 與 usage limit 並存"           "401 Unauthorized; also usage limit near" auth

echo "-- require_brief"
rb() { ( require_brief "$1" ) >/dev/null 2>&1; echo $?; }
D=$(mktemp -d "$SANDBOX/b.XXXXXX")
check "B1 brief 不存在 → rc=1" "$(is "$(rb "$D")" 1)"
: > "$D/brief.md"
check "B2 brief 為空 → rc=1" "$(is "$(rb "$D")" 1)"
write_brief "$D"; sed -i '' '/^## 問題$/d' "$D/brief.md"
check "B3 缺少「## 問題」→ rc=1" "$(is "$(rb "$D")" 1)"
MSG=$( ( require_brief "$D" ) 2>&1 )
check "B4 錯誤訊息點名缺少的段落" "$(printf '%s' "$MSG" | grep -q '問題' && echo 1 || echo 0)" "$MSG"
write_brief "$D"
check "B5 五段齊全 → rc=0" "$(is "$(rb "$D")" 0)"
printf '## 目標\n- x\n## 症狀\n- x\n## 已嘗試\n- x\n## 限制\n- x\n## 相關位置\n- x\n' > "$D/brief.md"
check "B6 只有除錯用的段落（症狀、已嘗試）、沒有「問題」→ rc=1" "$(is "$(rb "$D")" 1)"

echo "-- report health check"
hc() {
  printf '%b' "$2" > "$SANDBOX/hc.md"
  local rc=0
  report "hc" "$SANDBOX/hc.md" /dev/null 0 >/dev/null 2>&1 || rc=$?
  check "$1" "$(is "$rc" "$3")" "rc=$rc want=$3"
}
hc "H1 拒答"        '## 結論\n- 抱歉，我無法完成此項任務，因為素材涉及我不能處理的範圍\n' 2
hc "H2 無 H2 結構"  '這是一段沒有標題的純文字回覆內容，長度足夠\n' 2
hc "H3 H2 空殼"     '## 結論\n## 依據\n' 2
hc "H4 正常報告"    '## 結論\n- 根因：token 欄位在序列化時被改名\n' 0

echo "-- prepare_out / finalize_out"
O="$SANDBOX/round1-codex.md"
printf 'old\n' > "$O"; printf 'old\n' > "$SANDBOX/round1-codex.failed.md"
prepare_out "$O"
check "F1 prepare_out 清掉舊的成功檔與失敗檔" \
  "$([ ! -e "$O" ] && [ ! -e "$SANDBOX/round1-codex.failed.md" ] && echo 1 || echo 0)"
write_report "$O"; finalize_out "$O" 2
check "F2 失敗時改名為 .failed.md" \
  "$([ ! -e "$O" ] && [ -s "$SANDBOX/round1-codex.failed.md" ] && echo 1 || echo 0)"
prepare_out "$O"; write_report "$O"; finalize_out "$O" 0
check "F3 成功時保留原檔" "$([ -s "$O" ] && echo 1 || echo 0)"
prepare_out "$O"; finalize_out "$O" 4
check "F4 失敗但沒有輸出檔時不報錯" "$([ ! -e "$O" ] && [ ! -e "$SANDBOX/round1-codex.failed.md" ] && echo 1 || echo 0)"

echo "-- peer_files"
P=$(mktemp -d "$SANDBOX/p.XXXXXX")
write_report "$P/round1-claude.md"; write_report "$P/round1-codex.md"; write_report "$P/round1-agy.failed.md"
GOT=$(peer_files "$P" 1 codex | tr '\n' ' ')
check "G1 排除自己與失敗的一方" "$(is "$GOT" "$P/round1-claude.md ")" "$GOT"
write_report "$P/round1-agy.md"
GOT=$(peer_files "$P" 1 claude | tr '\n' ' ')
check "G2 依 claude、codex、agy 順序列出" "$(is "$GOT" "$P/round1-codex.md $P/round1-agy.md ")" "$GOT"
: > "$P/round1-codex.md"
GOT=$(peer_files "$P" 1 claude | tr '\n' ' ')
check "G3 空檔不算成功" "$(is "$GOT" "$P/round1-agy.md ")" "$GOT"

echo "-- party_label"
check "L1 三方顯示名稱" \
  "$(is "$(party_label claude)/$(party_label codex)/$(party_label agy)" "Claude subagent/codex/agy")"

summary
