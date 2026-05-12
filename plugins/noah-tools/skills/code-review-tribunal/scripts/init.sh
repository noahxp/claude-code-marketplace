#!/usr/bin/env bash
# Code Review Tribunal — 初始化執行器
# 用途：解析 target 字串、建立工作目錄、dump target 內容
# 參數：$1 = target_arg（單一字串，可為空、含空格、含 `..` 等）
# 輸出：stdout 印出 "WORKDIR=<absolute_path>" 一行
# 設計：shebang 強制 bash 執行，避開 zsh 不 word-split 的差異

set -euo pipefail

die() { echo "ERR: $*" >&2; exit 1; }

TARGET_ARG="${1:-}"

# 以 mktemp 建立工作目錄，由 OS 保證唯一性與 0700 權限
# 避免 PID + epoch 在同秒內碰撞、亦避免可預測路徑的攻擊面
WORKDIR=$(mktemp -d "/tmp/code-review-tribunal-XXXXXX")

# 失敗安全網：init 階段任一錯誤（含 set -e 觸發、外部訊號）皆自動清理工作目錄
# 成功路徑會在尾段顯式解除此 trap，避免後續階段需要時誤刪
# 覆蓋 ERR INT TERM HUP QUIT：避免 host timeout / parent kill / SIGHUP 時殘留 /tmp 目錄
trap '[ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"' ERR INT TERM HUP QUIT

# 解析 target 型別並 dump 為 target.diff 或 target.md
# 順序設計：先處理「明確可辨識」者（空、純數字、git range、路徑），再處理「可能誤觸」者（多 ref 含空白、單一 ref、自由文字）
if [ -z "$TARGET_ARG" ]; then
  # 無參數：working tree
  git diff HEAD > "$WORKDIR/target.diff"

elif [[ "$TARGET_ARG" =~ ^[0-9]+$ ]]; then
  # 純數字：GitHub PR；PR 型 target 需要 gh cli
  command -v gh >/dev/null || die "gh cli 未安裝（PR 型 target 必需；brew install gh）"
  gh pr diff "$TARGET_ARG" > "$WORKDIR/target.diff"

elif [[ "$TARGET_ARG" == *..* ]] && {
  # Git range（兩點 .. 或三點 ...，超過三點視為無效），驗證兩端皆為有效 ref
  R_LEFT="${TARGET_ARG%%..*}"
  R_RIGHT="${TARGET_ARG##*..}"
  R_RIGHT="${R_RIGHT#.}"
  git rev-parse --verify "$R_LEFT" >/dev/null 2>&1 \
    && git rev-parse --verify "$R_RIGHT" >/dev/null 2>&1
}; then
  git log -p --reverse "$TARGET_ARG" > "$WORKDIR/target.diff"

elif [ -e "$TARGET_ARG" ]; then
  # 路徑（檔案或目錄）：提前於「多 commit ref」判定，避免含空白合法路徑被誤觸 git rev-parse
  if git ls-files --error-unmatch "$TARGET_ARG" >/dev/null 2>&1; then
    git diff -- "$TARGET_ARG" > "$WORKDIR/target.diff"
    # tracked 且 working tree 乾淨時 diff 為空，fallback 至檔案內容快照
    # 支援「審查既有檔案內容」這種常見使用情境
    if [ ! -s "$WORKDIR/target.diff" ]; then
      rm "$WORKDIR/target.diff"
      if [ -d "$TARGET_ARG" ]; then
        # 目錄 fallback：列出目錄下所有 tracked 檔案內容並串接
        # 先把檔案清單落到暫存檔再消費，避免 process substitution 吞掉 git ls-files 的 rc
        # （process substitution 內 git ls-files rc 不受 set -e / pipefail 約束，rc≠0 時靜默產出空檔）
        FILES_LIST="$WORKDIR/_files-tracked.txt"
        git ls-files -- "$TARGET_ARG" > "$FILES_LIST"
        [ -s "$FILES_LIST" ] || { rm -f "$FILES_LIST"; die "tracked 目錄無檔案或 git ls-files 失敗: $TARGET_ARG"; }
        while IFS= read -r f; do
          echo "=== $f ==="
          git show "HEAD:$f"
          echo
        done < "$FILES_LIST" > "$WORKDIR/target.diff"
        rm -f "$FILES_LIST"
      else
        git show "HEAD:$TARGET_ARG" > "$WORKDIR/target.diff"
      fi
    fi
  else
    # 未追蹤路徑：支援檔案與目錄
    # 目錄分支須序列化為單一 markdown 檔（避免 cp -R 把 target.md 變成目錄，
    # 導致下游 `[ -s target.md ]` / `head -n 1 target.md` 全壞並誤報「target 內容為空」）
    if [ -d "$TARGET_ARG" ]; then
      FILES_LIST="$WORKDIR/_files-untracked.txt"
      # 排除 .git/ 與 node_modules/ 避免使用者誤指 repo root 時把 object 庫與依賴炸 token
      find "$TARGET_ARG" -type f \
        -not -path '*/.git/*' -not -path '*/node_modules/*' \
        > "$FILES_LIST"
      [ -s "$FILES_LIST" ] || { rm -f "$FILES_LIST"; die "未追蹤目錄無檔案: $TARGET_ARG"; }
      : > "$WORKDIR/target.md"
      while IFS= read -r f; do
        # grep -I 自動判定 binary 並 rc=1，配合 || continue 跳過避免 prompt 噪音
        grep -Iq . "$f" 2>/dev/null || continue
        {
          echo "=== $f ==="
          cat "$f"
          echo
        } >> "$WORKDIR/target.md"
      done < "$FILES_LIST"
      rm -f "$FILES_LIST"
    else
      cp "$TARGET_ARG" "$WORKDIR/target.md"
    fi
  fi

elif [[ "$TARGET_ARG" == *" "* ]] && {
  # 多 commit ref（空格分隔），用 read -ra 強制 split 為陣列
  IFS=' ' read -ra _REFS <<< "$TARGET_ARG"
  ALL_REFS=true
  for ref in "${_REFS[@]}"; do
    git rev-parse --verify "$ref" >/dev/null 2>&1 || { ALL_REFS=false; break; }
  done
  $ALL_REFS
}; then
  IFS=' ' read -ra _REFS <<< "$TARGET_ARG"
  git show "${_REFS[@]}" > "$WORKDIR/target.diff"

elif git rev-parse --verify "$TARGET_ARG" >/dev/null 2>&1; then
  # 單一 commit ref / branch / tag
  git show "$TARGET_ARG" > "$WORKDIR/target.diff"

else
  # 自由文字：寫入 prompt 與機械可讀狀態
  # 狀態欄位 STATUS: pending → host 在進入第二階段前用 Glob/Grep/Read 蒐集素材後 append 並改為 ready
  # cli 腳本第一輪會檢查 STATUS 必須為 ready，否則視為「素材未就緒」失敗
  cat > "$WORKDIR/target.md" <<EOF
STATUS: pending
FREE_TEXT_TARGET: $TARGET_ARG
EOF
fi

# 驗證非空，否則清理並中止
if [ ! -s "$WORKDIR/target.diff" ] && [ ! -s "$WORKDIR/target.md" ]; then
  rm -rf "$WORKDIR"
  die "target 內容為空: $TARGET_ARG"
fi

# 成功路徑解除 trap，避免後續階段失敗時誤刪 host 仍在使用的工作目錄
trap - ERR INT TERM HUP QUIT

echo "WORKDIR=$WORKDIR"
