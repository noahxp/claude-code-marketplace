#!/usr/bin/env bash
# Dev Council — Claude subagent 端的輔助
# 子命令：
#   prompt <r1|r2> <workdir>  印出派工 prompt（與 codex、agy 共用 build_prompt 與輸出格式）
#   check  <r1|r2> <workdir>  對 host 寫入的 round<N>-claude.md 跑 health check；不合格即改名為 .failed.md
# subagent 由 host 以 Agent 工具派出，回傳文字由 host 原樣寫入 round<N>-claude.md

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

cmd_prompt() {
  local round="$1" workdir="${2:-}"
  require_workdir "$workdir"
  require_brief "$workdir"
  round_name "$round" >/dev/null
  [ "$round" = r2 ] && require_r2_inputs "$workdir" claude
  build_prompt "$round" claude "$workdir" "$PWD"
}

cmd_check() {
  local round="$1" workdir="${2:-}"
  require_workdir "$workdir"
  local label n out rc=0
  label="Claude subagent $(round_name "$round")"
  n="${round#r}"
  out="$workdir/round${n}-claude.md"
  report "$label" "$out" /dev/null 0 || rc=$?
  finalize_out "$out" "$rc"
  return "$rc"
}

[ $# -ge 2 ] || die "用法: $0 {prompt|check} {r1|r2} <workdir>"
cmd="$1"; shift
case "$cmd" in
  prompt) cmd_prompt "$@" ;;
  check)  cmd_check "$@" ;;
  *)      die "未知子命令: $cmd" ;;
esac
