#!/usr/bin/env bash
# Dev Council — agy cli（Antigravity CLI）執行器
# 子命令：preflight / r1 <workdir> / r2 <workdir>
# 回傳碼見 lib/common.sh 的 RC_* 與 SKILL.md〈回傳碼〉
# 設計重點：
#   - 一律 --mode plan：headless -p 預設為 Auto mode，實測會不經詢問直接改寫 git repo 內的檔案；
#     plan mode 實測可讀檔作答、不會寫入。--sandbox 只限制 terminal，擋不住檔案編輯工具
#   - headless 無法詢問權限：清單外的 terminal 指令一律被拒，且被拒後整輪沒有任何輸出（實測）。
#     以 --settings 只放行唯讀查詢指令，並在 prompt 列出清單。規則以指令開頭的字詞比對，
#     `git -C <路徑> blame` 比對不到 `git blame`，所以 agy 在 repo 內執行，workdir 以 --add-dir 加入
#   - agy 沒有結構化輸出，以 <council-report> sentinel 擷取回覆；缺閉合標籤即失敗
#     （實測逾時與 headless 權限拒絕都以 rc=0 結束）
#   - 錯誤分類只看 stderr 與 stdout 中以 Error 開頭的行：stdout 其餘部分是模型的敘述與回覆，
#     問題本身常與登入或 401 有關，出現這些字樣不代表 agy 自己登入失效

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

LOGIN_HOW="執行 agy，依畫面完成登入後離開"
# 第二輪要讀三份報告再查證，實測 300s 會逾時
AGY_PRINT_TIMEOUT="${DEV_COUNCIL_AGY_PRINT_TIMEOUT:-600s}"
AGY_PREFLIGHT_TIMEOUT="${DEV_COUNCIL_AGY_PREFLIGHT_TIMEOUT:-90s}"
SENTINEL_OPEN="<council-report>"
SENTINEL_CLOSE="</council-report>"

validate_timeout() {
  [[ "$1" =~ ^[0-9]+(s|m|h)$ ]] || die "$2 格式錯誤（須如 90s / 5m / 1h）：$1"
}
validate_timeout "$AGY_PRINT_TIMEOUT" DEV_COUNCIL_AGY_PRINT_TIMEOUT
validate_timeout "$AGY_PREFLIGHT_TIMEOUT" DEV_COUNCIL_AGY_PREFLIGHT_TIMEOUT

# 允許規則只比對指令開頭、不檢查參數，只能放行沒有寫檔或執行參數的指令：
# rg --pre 與 git grep -O 會執行任意指令，git log/diff/show --output 會寫檔，所以都不放行
READONLY_COMMANDS=("git blame" "git status" "git ls-files" "grep" "ls")

agy_settings() {
  local c rules="" sep=""
  for c in "${READONLY_COMMANDS[@]}"; do
    rules="$rules$sep\"command($c)\""
    sep=","
  done
  printf '{"permissions":{"allow":[%s]}}' "$rules"
}

agy_suffix() {
  local c list="" sep=""
  for c in "${READONLY_COMMANDS[@]}"; do
    list="$list$sep$c"
    sep="、"
  done
  cat <<EOF

[指令限制] 你只能執行這些唯讀指令：${list}。直接在你目前的工作目錄（即 repo）執行，不要加 git -C、cd ... && 之類的前綴，也不要用管線或分號串接其他指令；讀檔請用你的讀檔工具。清單外的指令會被自動拒絕，並讓這一輪沒有任何輸出。

[輸出包覆] 把上述格式的完整回覆放在獨立一行的 ${SENTINEL_OPEN} 與獨立一行的 ${SENTINEL_CLOSE} 之間，標籤外不要輸出任何文字。
EOF
}

# agy_exec <prompt> <raw> <err> <cwd> <timeout> [--add-dir <dir>]
agy_exec() {
  local prompt="$1" raw="$2" err="$3" cwd="$4" timeout="$5"; shift 5
  local model_arg=()
  [ -n "${DEV_COUNCIL_AGY_MODEL:-}" ] && model_arg=(--model "$DEV_COUNCIL_AGY_MODEL")
  ( cd "$cwd" && agy --sandbox --mode plan --settings "$(agy_settings)" ${model_arg[@]+"${model_arg[@]}"} "$@" \
      --print-timeout "$timeout" -p "$prompt" </dev/null ) >"$raw" 2>"$err"
}

# classify_agy <raw> <err> <all|errors>：回傳 RC_AUTH / RC_QUOTA / RC_FAIL，分類結果附加到 err
# all 用於 preflight（回覆只有 ok，整份 stdout 都能比對）；errors 用於正式輪次
classify_agy() {
  local raw="$1" err="$2" scope="$3" text
  text="$(cat "$err" 2>/dev/null || true)"
  if [ "$scope" = all ]; then
    text="$text"$'\n'"$(cat "$raw" 2>/dev/null || true)"
  else
    text="$text"$'\n'"$(grep -iE '^[[:space:]]*(error|fatal)([^[:alnum:]]|$)' "$raw" 2>/dev/null || true)"
  fi
  case "$(classify_failure "$text")" in
    auth)
      printf '[Agy Auth] %s\n' "$(printf '%s\n' "$text" | grep -iE "$AUTH_RE" | head -1)" >> "$err"
      return "$RC_AUTH" ;;
    quota)
      printf '[Agy Quota] %s\n' "$(printf '%s\n' "$text" | grep -iE "$QUOTA_RE" | head -1)" >> "$err"
      return "$RC_QUOTA" ;;
  esac
  # 舊版 agy 在 stdout 印 "timed out"；新版在 stderr 印 "print timeout" 與 DEADLINE_EXCEEDED
  if cat "$raw" "$err" 2>/dev/null | grep -qiE 'timed out|print timeout|deadline_exceeded'; then
    if [ "$scope" = all ]; then
      echo "[Timeout] agy 試跑逾時；可調大 DEV_COUNCIL_AGY_PREFLIGHT_TIMEOUT（目前 ${AGY_PREFLIGHT_TIMEOUT}）後重試" >> "$err"
    else
      echo "[Timeout] agy print 逾時；可調大 DEV_COUNCIL_AGY_PRINT_TIMEOUT（目前 ${AGY_PRINT_TIMEOUT}）後重試" >> "$err"
    fi
  fi
  return "$RC_FAIL"
}

run_agy_call() {
  local prompt="$1" out="$2" err="$3" workdir="$4" repo="$5"
  local raw="${out%.md}.raw.txt" rc=0
  agy_exec "$prompt" "$raw" "$err" "$repo" "$AGY_PRINT_TIMEOUT" --add-dir "$workdir" || rc=$?
  if [ "$rc" -eq 0 ] && grep -qF "$SENTINEL_CLOSE" "$raw"; then
    awk -v o="$SENTINEL_OPEN" -v c="$SENTINEL_CLOSE" '
      index($0,o){grab=1; next}
      index($0,c){grab=0; next}
      grab{print}
    ' "$raw" > "$out"
    [ -s "$out" ] && return 0
    echo "[Empty Report] sentinel 標籤內沒有內容" >> "$err"
    return "$RC_FAIL"
  fi
  [ "$rc" -eq 0 ] && echo "[Sentinel Missing] 輸出缺 $SENTINEL_CLOSE 閉合標籤（逾時截斷、權限拒絕或未遵守格式）" >> "$err"
  classify_agy "$raw" "$err" errors
}

cmd_preflight() {
  command -v agy >/dev/null || missing "agy cli 未安裝（請依 Antigravity CLI 官方指引安裝後執行 agy install）"
  # 在暫存目錄試跑：preflight 早於 workdir 建立，避免在 repo 留下 agy 的 cache
  make_preflight_tmp
  local tmp="$PREFLIGHT_TMP" rc=0
  agy_exec "Reply only with: ok" "$tmp/out" "$tmp/err" "$tmp" "$AGY_PREFLIGHT_TIMEOUT" || rc=$?
  if [ "$rc" -eq 0 ] && grep -qiw 'ok' "$tmp/out"; then
    echo "agy ready"
    return 0
  fi
  classify_agy "$tmp/out" "$tmp/err" all || rc=$?
  echo "ERR: agy 試跑失敗（rc=${rc}）。輸出與 stderr tail：" >&2
  [ -s "$tmp/out" ] && print_err_tail "$tmp/out" >&2
  print_err_tail "$tmp/err" >&2
  explain_rc agy "$rc" "$LOGIN_HOW"
  return "$rc"
}

cmd_round() {
  local round="$1" workdir="${2:-}"
  require_workdir "$workdir"
  require_brief "$workdir"
  [ "$round" = r2 ] && require_r2_inputs "$workdir" agy
  local n="${round#r}" label
  label="agy $(round_name "$round")"
  local out="$workdir/round${n}-agy.md" err="$workdir/round${n}-agy.err"
  local prompt
  prompt="$(build_prompt "$round" agy "$workdir" "$PWD" "（只限文末 [指令限制] 列出的指令）")$(agy_suffix)"
  prepare_out "$out"

  local rc=0 report_rc=0
  run_agy_call "$prompt" "$out" "$err" "$workdir" "$PWD" || rc=$?
  report "$label" "$out" "$err" "$rc" || report_rc=$?
  [ "$rc" -ne 0 ] || rc=$report_rc
  finalize_out "$out" "$rc"
  explain_rc agy "$rc" "$LOGIN_HOW"
  return "$rc"
}

[ $# -ge 1 ] || die "用法: $0 {preflight|r1|r2} [workdir]"
cmd="$1"; shift
case "$cmd" in
  preflight) cmd_preflight ;;
  r1|r2)     cmd_round "$cmd" "$@" ;;
  *)         die "未知子命令: $cmd" ;;
esac
