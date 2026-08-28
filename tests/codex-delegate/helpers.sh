#!/usr/bin/env bash
# Codex Delegate — 測試共用函式
# 由 test-init.sh / test-codex.sh 透過 `source` 載入；不可直接執行

[ "${BASH_SOURCE[0]}" = "${0}" ] \
  && { echo "ERR: test-helpers.sh 應由測試腳本 source 載入，不可直接執行" >&2; exit 1; }

# 只刪 mktemp 直接產生的工作目錄根：/tmp/codex-delegate-XXXXXX，不得有任何額外路徑元件。
# 「前綴比對 + 最終路徑 -L 檢查」擋不住中間元件是符號連結的情況——
# /tmp/codex-delegate-x/link/file 之中 link 指向 /etc 時，最終路徑不是連結卻已逸出，
# 前綴仍然吻合，rm -rf 就會作用在 /etc 上。限定「不含額外元件」可一併擋掉 .. 與巢狀逃逸。
safe_rm() {
  local p="${1:-}"
  [ -n "$p" ] || return 0
  case "$p" in
    /tmp/codex-delegate-*) : ;;
    *) printf '  WARN 拒絕刪除非預期路徑: %s\n' "$p"; return 0 ;;
  esac
  case "${p#/tmp/}" in
    */*) printf '  WARN 路徑含額外元件 拒絕刪除: %s\n' "$p"; return 0 ;;
  esac
  if [ -L "$p" ]; then
    printf '  WARN 路徑為符號連結 拒絕刪除: %s\n' "$p"; return 0
  fi
  rm -rf "$p"
}

# 解析 init.sh 的 stdout 欄位：field_of ROOT "$out" / field_of WORKDIR "$out"
field_of() { printf '%s' "$2" | sed -n "s/^$1=//p"; }
