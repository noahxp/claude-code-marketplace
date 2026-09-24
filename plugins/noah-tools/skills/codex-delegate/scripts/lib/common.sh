#!/usr/bin/env bash
# Codex Delegate — codex cli 端共用函式
# 由 codex.sh 透過 `source` 載入；不可直接執行
# refusal-patterns.txt 與本檔同目錄（scripts/lib/），由 ${BASH_SOURCE[0]} 解析自身路徑

[ "${BASH_SOURCE[0]}" = "${0}" ] \
  && { echo "ERR: common.sh 應由 codex.sh source 載入，不可直接執行" >&2; exit 1; }

die() { printf 'ERR: %s\n' "$*" >&2; exit 1; }

REFUSAL_PATTERNS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/refusal-patterns.txt"

# stderr tail 截取（30 行 + 單行 200 字元截斷）
print_err_tail() {
  local err="$1"
  if [ ! -s "$err" ]; then
    echo "[無 stderr 紀錄]"
    return
  fi
  tail -30 "$err" | awk '{if(length>200)print substr($0,1,200)"…[truncated]";else print}'
}

# 報告結果（含語意失敗 health check）
# 偵測順序：A（首 200 字元拒答強訊號）、B（無 H2 結構）、C（無 list bullet 內容）
report() {
  local label="$1" out="$2" err="$3" rc="$4"
  # 先判存在再取大小：`wc -c < "$out" 2>/dev/null` 擋不住重導向本身的失敗訊息，
  # cli 早夭而輸出檔未建立時會漏出 "No such file or directory"
  local size=0
  [ -f "$out" ] && size=$(wc -c < "$out")
  echo "$label rc=$rc, output=$size bytes"
  if [ ! -s "$out" ]; then
    echo "--- $label stderr tail ---"
    print_err_tail "$err"
    return 2
  fi
  local h2_count bullet_count
  h2_count=$(grep -c '^## ' "$out" || true)
  bullet_count=$(grep -cE '^[-*] .{10,}' "$out" || true)
  # grep -f 不把 `#` 開頭行當註解，需用 process substitution 先濾掉註解與空行才能避免
  # bare `#` pattern 誤匹配 cli 必輸出之 `## Critical Issues` markdown header（A 規則 false positive）
  # A/B/C 命中即 return 2，讓 caller 能把語意失敗反映進 exit code，落實 SKILL.md fail-fast 契約
  if [ -f "$REFUSAL_PATTERNS" ] \
     && head -c 200 "$out" \
        | grep -qiEf <(grep -v '^[[:space:]]*\(#\|$\)' "$REFUSAL_PATTERNS"); then
    echo "--- $label health check 警告 ---"
    echo "[語意失敗:A] 檔案首 200 字元命中整段拒答強訊號，下游須比照失敗檔處理"
    return 2
  elif [ "$h2_count" -eq 0 ]; then
    echo "--- $label health check 警告 ---"
    echo "[語意失敗:B] 檔案無 H2 結構，下游須比照失敗檔處理"
    return 2
  elif [ "$bullet_count" -eq 0 ]; then
    echo "--- $label health check 警告 ---"
    echo "[語意失敗:C] 檔案無 list bullet 內容（H2 框架空殼），下游須比照失敗檔處理"
    return 2
  fi
  return 0
}
