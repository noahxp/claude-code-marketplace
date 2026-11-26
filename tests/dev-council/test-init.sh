#!/usr/bin/env bash
# init.sh 契約測試
# 用法：test-init.sh <init.sh 路徑>
INIT_SH="${1:?用法: test-init.sh <init.sh 路徑>}"

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "-- 建立工作目錄"
OUT=$(bash "$INIT_SH" 2>&1); RC=$?
W=$(field_of WORKDIR "$OUT")
check "A 成功時 rc=0 並印出 WORKDIR=" "$([ "$RC" -eq 0 ] && [ -n "$W" ] && echo 1 || echo 0)" "rc=$RC out=$OUT"
check "B 目錄存在" "$([ -d "$W" ] && echo 1 || echo 0)" "$W"
case "$W" in /tmp/dev-council-*) r=1 ;; *) r=0 ;; esac
check "C 目錄位於 /tmp/dev-council- 底下" "$r" "$W"
check "D 權限為 700" "$(is "$(stat -f '%Lp' "$W" 2>/dev/null)" 700)" "$(stat -f '%Lp' "$W" 2>/dev/null)"
check "E 目錄為空（brief 由 host 撰寫）" "$(is "$(ls -A "$W" 2>/dev/null | wc -l | tr -d ' ')" 0)"
safe_rm "$W"

OUT2=$(bash "$INIT_SH" 2>&1); W2=$(field_of WORKDIR "$OUT2")
check "F 每次建立不同目錄" "$([ -n "$W2" ] && [ "$W2" != "$W" ] && echo 1 || echo 0)" "$W2"
safe_rm "$W2"

summary
