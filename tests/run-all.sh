#!/usr/bin/env bash
# 跑全部 skill script 的回歸測試
# 用法：bash tests/run-all.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CD_SCRIPTS=plugins/noah-tools/skills/codex-delegate/scripts
TOTAL_FAIL=0

run_suite() {
  local name="$1"; shift
  echo "=== $name ==="
  local out
  out=$(bash "$@" 2>&1)
  printf '%s\n' "$out" | tail -n +1
  printf '%s\n' "$out" | grep -q 'FAIL=0' || TOTAL_FAIL=$((TOTAL_FAIL + 1))
  echo
}

run_suite "codex-delegate / init.sh"  tests/codex-delegate/test-init.sh  "$CD_SCRIPTS/init.sh"
run_suite "codex-delegate / codex.sh" tests/codex-delegate/test-codex.sh "$CD_SCRIPTS/codex.sh"

DC_SCRIPTS=plugins/noah-tools/skills/dev-council/scripts
run_suite "dev-council / init.sh"       tests/dev-council/test-init.sh   "$DC_SCRIPTS/init.sh"
run_suite "dev-council / lib/common.sh" tests/dev-council/test-common.sh "$DC_SCRIPTS"
run_suite "dev-council / codex.sh"      tests/dev-council/test-codex.sh  "$DC_SCRIPTS/codex.sh"
run_suite "dev-council / agy.sh"        tests/dev-council/test-agy.sh    "$DC_SCRIPTS/agy.sh"
run_suite "dev-council / claude.sh"     tests/dev-council/test-claude.sh "$DC_SCRIPTS/claude.sh"

if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "所有測試套件通過"
else
  echo "有 $TOTAL_FAIL 個套件失敗"
  exit 1
fi
