#!/usr/bin/env bash
# Dev Council — codex cli 執行器
# 子命令：preflight / r1 <workdir> / r2 <workdir>
# 回傳碼見 lib/common.sh 的 RC_* 與 SKILL.md〈回傳碼〉
# 設計重點：
#   - 一律 --sandbox read-only、--ephemeral，stdin 接 /dev/null 避免背景執行時 hang
#   - 以呼叫時的 cwd 作為 codex 的工作目錄（host 須先 cd 到 repo）
#   - 錯誤分類只看 codex 自報的 JSONL error 事件與 stderr，不看模型回覆內容：
#     問題本身常與登入或 401 有關，回覆裡出現這些字樣不代表 codex 自己登入失效

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

LOGIN_HOW="執行 codex login"
COOLDOWN_WAIT="${DEV_COUNCIL_COOLDOWN_WAIT:-90}"
[[ "$COOLDOWN_WAIT" =~ ^[0-9]+$ ]] || die "DEV_COUNCIL_COOLDOWN_WAIT 須為秒數：$COOLDOWN_WAIT"

codex_exec() {
  local prompt="$1" raw="$2" err="$3"
  local model_arg=()
  [ -n "${DEV_COUNCIL_CODEX_MODEL:-}" ] && model_arg=(--model "$DEV_COUNCIL_CODEX_MODEL")
  codex exec ${model_arg[@]+"${model_arg[@]}"} --sandbox read-only --ephemeral --json "$prompt" \
    </dev/null >"$raw" 2>>"$err"
}

# 回傳 0（可繼續抽取回覆）或 RC_FAIL / RC_QUOTA / RC_AUTH；分類結果附加到 err
classify_codex() {
  local raw="$1" err="$2" cli_rc="$3" msgs="" text kind
  [ -s "$raw" ] && msgs=$(jq -r 'select(.type=="error" or .type=="turn.failed")
                                 | (.message // .error.message // empty)' "$raw" 2>/dev/null || true)
  [ -z "$msgs" ] && [ "$cli_rc" -eq 0 ] && return 0
  text="$msgs"
  [ "$cli_rc" -ne 0 ] && [ -s "$err" ] && text="$text"$'\n'"$(cat "$err")"
  kind=$(classify_failure "$text")
  case "$kind" in
    auth)
      printf '[Codex Auth] %s\n' "$(printf '%s\n' "$text" | grep -iE "$AUTH_RE" | head -1)" >> "$err"
      return "$RC_AUTH" ;;
    quota)
      printf '[Codex Quota] %s\n' "$(printf '%s\n' "$text" | grep -iE "$QUOTA_RE" | head -1)" >> "$err"
      return "$RC_QUOTA" ;;
  esac
  [ -n "$msgs" ] && printf '[Codex Error] %s\n' "$(printf '%s\n' "$msgs" | head -1)" >> "$err"
  # codex 自報一般錯誤但最終 rc=0 時（例如串流中斷後自行恢復），交給後續抽取判斷有無回覆
  [ "$cli_rc" -eq 0 ] && return 0
  return "$RC_FAIL"
}

run_codex_call() {
  local prompt="$1" out="$2" err="$3"
  local raw="${out%.md}.raw.json"
  : > "$err"
  local start=$SECONDS cli_rc=0
  codex_exec "$prompt" "$raw" "$err" || cli_rc=$?
  # 啟動即被 SIGKILL 是兩次 codex 呼叫間隔太短的冷卻，與 prompt 內容無關；等待後原樣重試一次
  if [ "$cli_rc" -eq 137 ] && [ $((SECONDS - start)) -lt 10 ]; then
    printf '[Cooldown] codex 啟動即被終止（rc=137），等待 %s 秒後重試一次\n' "$COOLDOWN_WAIT" >> "$err"
    sleep "$COOLDOWN_WAIT"
    cli_rc=0
    codex_exec "$prompt" "$raw" "$err" || cli_rc=$?
  fi

  local cls=0
  classify_codex "$raw" "$err" "$cli_rc" || cls=$?
  [ "$cls" -eq 0 ] || return "$cls"

  if ! jq -r 'select(.type=="item.completed" and .item.type=="agent_message") | .item.text' \
         "$raw" > "$out" 2>>"$err"; then
    echo "[jq] 無法解析 codex 的 JSONL 輸出" >> "$err"
    return "$RC_FAIL"
  fi
  if [ ! -s "$out" ]; then
    if jq -e 'select(.type=="item.completed")' "$raw" >/dev/null 2>&1; then
      echo "[Codex Incomplete] 有 item.completed 事件但沒有 agent_message（推理未收尾），建議重試" >> "$err"
    else
      echo "[Schema Mismatch] 事件流中沒有 item.completed，codex 輸出格式可能變動或提早結束" >> "$err"
    fi
    return "$RC_FAIL"
  fi
  return 0
}

cmd_preflight() {
  command -v codex >/dev/null || missing "codex cli 未安裝（npm i -g @openai/codex）"
  command -v jq    >/dev/null || missing "jq 未安裝（brew install jq）"

  # login status 不耗額度；未登入時不必試跑
  local status_out status_rc=0
  status_out=$(codex login status 2>&1) || status_rc=$?
  if [ "$status_rc" -ne 0 ]; then
    printf '[Codex Auth] %s\n' "$status_out" >&2
    explain_rc codex "$RC_AUTH" "$LOGIN_HOW"
    return "$RC_AUTH"
  fi

  # login status 只看得出有沒有登入資料，看不出 token 是否已失效，所以仍要實際試跑一次
  make_preflight_tmp
  local tmp="$PREFLIGHT_TMP" rc=0
  run_codex_call "Reply only with: ok" "$tmp/preflight.md" "$tmp/preflight.err" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "codex ready"
  else
    echo "ERR: codex 試跑失敗（rc=${rc}）。stderr tail：" >&2
    print_err_tail "$tmp/preflight.err" >&2
    explain_rc codex "$rc" "$LOGIN_HOW"
  fi
  return "$rc"
}

cmd_round() {
  local round="$1" workdir="${2:-}"
  require_workdir "$workdir"
  require_brief "$workdir"
  [ "$round" = r2 ] && require_r2_inputs "$workdir" codex
  local n="${round#r}" label
  label="codex $(round_name "$round")"
  local out="$workdir/round${n}-codex.md" err="$workdir/round${n}-codex.err"
  local prompt
  prompt=$(build_prompt "$round" codex "$workdir" "$PWD")
  prepare_out "$out"

  local rc=0 report_rc=0
  run_codex_call "$prompt" "$out" "$err" || rc=$?
  report "$label" "$out" "$err" "$rc" || report_rc=$?
  [ "$rc" -ne 0 ] || rc=$report_rc
  finalize_out "$out" "$rc"
  explain_rc codex "$rc" "$LOGIN_HOW"
  return "$rc"
}

[ $# -ge 1 ] || die "用法: $0 {preflight|r1|r2} [workdir]"
cmd="$1"; shift
case "$cmd" in
  preflight) cmd_preflight ;;
  r1|r2)     cmd_round "$cmd" "$@" ;;
  *)         die "未知子命令: $cmd" ;;
esac
