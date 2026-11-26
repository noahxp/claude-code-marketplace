#!/usr/bin/env bash
# dev-council — 測試共用函式
# 由各 test-*.sh 透過 `source` 載入；不可直接執行

[ "${BASH_SOURCE[0]}" = "${0}" ] \
  && { echo "ERR: helpers.sh 應由測試腳本 source 載入，不可直接執行" >&2; exit 1; }

PASS=0; FAIL=0

check() {
  local desc="$1" cond="$2" detail="${3:-}"
  if [ "$cond" = "1" ]; then printf '  ok   %s\n' "$desc"; PASS=$((PASS + 1))
  else printf '  FAIL %s%s\n' "$desc" "${detail:+ -> $detail}"; FAIL=$((FAIL + 1)); fi
}

# is <實際值> <期望值>：相等印 1，否則印 0，供 check 的第二個參數使用
is() { [ "$1" = "$2" ] && echo 1 || echo 0; }

# has <檔案> <ERE>：檔案存在且內容匹配印 1
has() { [ -f "$1" ] && grep -qE -- "$2" "$1" && echo 1 || echo 0; }

# lacks <檔案> <ERE>：檔案存在且內容不匹配印 1
lacks() { [ -f "$1" ] && ! grep -qE -- "$2" "$1" && echo 1 || echo 0; }

summary() {
  printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

field_of() { printf '%s' "$2" | sed -n "s/^$1=//p"; }

# 只刪 mktemp 直接產生的工作目錄根：/tmp/dev-council-XXXXXX，不得有額外路徑元件或符號連結
safe_rm() {
  local p="${1:-}"
  [ -n "$p" ] || return 0
  case "$p" in
    /tmp/dev-council-*) : ;;
    *) printf '  WARN 拒絕刪除非預期路徑: %s\n' "$p"; return 0 ;;
  esac
  case "${p#/tmp/}" in
    */*) printf '  WARN 路徑含額外元件 拒絕刪除: %s\n' "$p"; return 0 ;;
  esac
  [ -L "$p" ] && { printf '  WARN 路徑為符號連結 拒絕刪除: %s\n' "$p"; return 0; }
  rm -rf "$p"
}

# 背景啟動 preflight，等它建立暫存目錄後送 TERM；目錄有出現且最後被清掉才印 1
# 用法：interrupted_preflight_is_clean <腳本> <環境變數 k=v...>（stub 須以 STUB_SLEEP 拉長執行時間）
interrupted_preflight_is_clean() {
  local script="$1"; shift
  local before after pid i seen=0
  before=$(ls -d /tmp/dev-council-preflight.* 2>/dev/null | sort)
  env "$@" /bin/bash "$script" preflight >/dev/null 2>&1 &
  pid=$!
  for i in $(seq 50); do
    after=$(ls -d /tmp/dev-council-preflight.* 2>/dev/null | sort)
    if [ "$after" != "$before" ]; then seen=1; break; fi
    sleep 0.1
  done
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  after=$(ls -d /tmp/dev-council-preflight.* 2>/dev/null | sort)
  [ "$seen" = 1 ] && [ "$after" = "$before" ] && echo 1 || echo 0
}

write_brief() {
  cat > "$1/brief.md" <<'EOF'
## 目標
- 讓 test_login 通過
## 問題
- KeyError: 'token' 該在序列化層修，還是改呼叫端讀取的欄位名稱？
## 已知事實
- 錯誤出現在 src/auth.py:42；確認環境變數已設定，錯誤不變
## 限制
- 不能改對外 API 契約
## 相關位置
- src/auth.py
EOF
}

# 寫一份通過 health check 的報告
write_report() {
  printf '## 結論\n- 答案：%s\n- 理由：序列化層把欄位改名，呼叫端讀不到\n' "${2:-在序列化層修正 token 欄位名稱}" > "$1"
}
