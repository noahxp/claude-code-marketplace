#!/usr/bin/env bash
# Codex Delegate — 初始化執行器
# 用途：機械切分「給 codex 的任務」與「給 host 的後處理指示」、建立工作目錄
# 參數：$1 = 使用者輸入的完整參數字串（單一字串，可含空格）
# 輸出：stdout 印出 ROOT= / WORKDIR= / SPLIT_SUSPICIOUS= 三行
# 設計：切分交由字串比對執行而非 LLM 語意判斷，杜絕分派錯誤；
#       shebang 強制 bash 執行，避開 zsh 不 word-split 的差異

set -euo pipefail

# 刻意自帶而不 source lib/common.sh：init.sh 不呼叫 codex，也用不到 report / REFUSAL_PATTERNS，
# 保持零依賴讓它能單獨執行與測試。兩處 die 的實作須一致（皆用 printf，避免 echo 把 -n/-e 當旗標）
die() { printf 'ERR: %s\n' "$*" >&2; exit 1; }

# 去除前後空白（含 tab）；分隔符本身只認 ASCII 空格，見下方切分契約
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 清理安全網：EXIT trap 涵蓋所有退出路徑（含 set -e 觸發的非零退出），較 ERR trap 完整。
# 訊號 handler 必須顯式 exit——bash 執行完 handler 會繼續往下跑，
# 否則目錄已被刪除，腳本卻仍會印出該路徑交給 host。
CLEANUP=1
ROOT=""
cleanup() {
  if [ "$CLEANUP" = "1" ] && [ -n "$ROOT" ]; then
    rm -rf "$ROOT"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'exit 131' QUIT

RAW_ARG=$(trim "${1:-}")
[ -n "$RAW_ARG" ] || die "缺少任務敘述；用法: init.sh \"<給 codex 的任務> [-- <給 host 的後處理指示>]\""

# 分隔符契約：只認前後皆為 ASCII 空格的獨立 ` -- ` token（不接受 tab / 換行），只切第一個出現處。
# 故 `--sandbox`、`--model=x` 這類旗標不會被誤切；後半段內若再出現 `--` 整段歸 host。
#
# CODEX_DELEGATE_NO_SPLIT=1：完全不切分，去除前後空白後整串歸 codex（內部 ` -- ` 原樣保留），後處理走預設。
# 這是「任務正文本身含獨立 ` -- `」時唯一可執行的逃生口——沒有它，可疑切分的
# 「整串都給 codex」選項無法實現：原樣重跑必然切在同一位置。
if [ "${CODEX_DELEGATE_NO_SPLIT:-}" = "1" ]; then
  TASK_PART="$RAW_ARG"
  FOLLOWUP_PART=""
elif [ "$RAW_ARG" = "--" ] || [[ "$RAW_ARG" == "-- "* ]]; then
  die "任務段為空：分隔符 -- 之前必須有給 codex 的任務敘述"
elif [[ "$RAW_ARG" == *" -- "* ]]; then
  TASK_PART=$(trim "${RAW_ARG%%" -- "*}")
  FOLLOWUP_PART=$(trim "${RAW_ARG#*" -- "}")
elif [[ "$RAW_ARG" == *" --" ]]; then
  # 第一個分隔符恰位於尾端、其後無內容：後處理走預設。
  # 不可預先剝除尾端 ` --`，否則 `a -- b --` 會遺失原屬 host 的最後一個 --
  TASK_PART=$(trim "${RAW_ARG% --}")
  FOLLOWUP_PART=""
else
  TASK_PART="$RAW_ARG"
  FOLLOWUP_PART=""
fi

[ -n "$TASK_PART" ] || die "任務段為空：分隔符 -- 之前必須有給 codex 的任務敘述"

# 目錄分層：codex/ 是交給 codex.sh 的 workdir，host-followup.md 留在其父層。
# 這降低 codex 順手讀到後處理指示的機率，但 read-only sandbox 不限制讀取範圍，
# 因此**不構成讀取隔離**；真正的保證是該檔從不出現在任何 codex prompt 中。
# mktemp 由 OS 保證唯一性與 0700 權限
ROOT=$(mktemp -d "/tmp/codex-delegate-XXXXXX")
WORKDIR="$ROOT/codex"
mkdir -p "$WORKDIR"

# task.md：codex 的唯一輸入。
# 初始為 STATUS: pending，host 界定範圍（必要時 append 少量素材）後以 `codex.sh ready` 翻轉；ask 會檢查，未就緒即 die
# 一律用 printf 而非 echo：followup 內容可能為 `-n` / `-e`，會被 echo 當旗標吞掉
{
  printf 'STATUS: pending\n'
  printf 'TASK: %s\n' "$TASK_PART"
} > "$WORKDIR/task.md"

# host-followup.md：只給 host 讀，其內容不得併入任何 codex prompt
# MODE 欄位讓 host 以機械方式判定走預設或使用者指定，不需再解讀語意
if [ -n "$FOLLOWUP_PART" ]; then
  printf 'MODE: user-specified\n%s\n' "$FOLLOWUP_PART" > "$ROOT/host-followup.md"
else
  printf 'MODE: default\n%s\n' "覆核 codex 回覆並產出摘要與行動建議；不修改任何檔案。" \
    > "$ROOT/host-followup.md"
fi

# 可疑切分偵測：任務正文本身含獨立 ` -- ` 時會被誤切，此處以機械規則標記供 host 攔截。
# 判定限 user-specified（未切分時無此風險）；四條規則皆為啟發式，寧可誤報也不漏報。
SUSPICIOUS="no"
if [ -n "$FOLLOWUP_PART" ]; then
  # 中文動詞直接匹配；英文詞需前後邊界，避免 warm/format 之類誤中。
  # 一律用 [[:space:]] 而非字面空格，tab 分隔的 `rm	-rf` 才擋得住。
  if printf '%s' "$FOLLOWUP_PART" | grep -qE \
       '(刪除|刪掉|刪光|刪檔|移除|移掉|清空|清掉|清除|覆寫|覆蓋|蓋掉|重置|還原|截斷|抹除|強制推送|強制覆蓋)' \
     || printf '%s' "$FOLLOWUP_PART" | grep -qiE \
       '(^|[[:space:]])(rm|rmdir|unlink|truncate|delete|destroy|wipe|purge|drop|shred|remove|erase|overwrite)([[:space:]]|$)' \
     || printf '%s' "$FOLLOWUP_PART" | grep -qiE \
       '(git[[:space:]]+clean|reset[[:space:]]+--hard|checkout[[:space:]]+--[[:space:]]|push[[:space:]]+(-f|--force)|force[[:space:]-]*push|drop[[:space:]]+(table|database)|delete[[:space:]]+from)'; then
    # 破壞性動作最優先攔截：誤切的後半段一旦被當成後處理指示執行，後果不可逆
    SUSPICIOUS="yes:followup-has-destructive-verb"
  elif [ "${#FOLLOWUP_PART}" -gt "${#TASK_PART}" ]; then
    # 後處理指示照理應短於任務敘述；反之通常代表切點落在任務正文中間
    SUSPICIOUS="yes:followup-longer-than-task"
  elif printf '%s' "$FOLLOWUP_PART" | grep -qE '^(的|是|並|且|與|及|以|而|或|了|中|時|後|前|之)'; then
    # 以助詞或連接詞開頭：這是被攔腰切斷的句子，不會是一句完整的後處理指示
    SUSPICIOUS="yes:followup-starts-mid-sentence"
  elif printf '%s' "$TASK_PART" | grep -qE '[：，、,:;（(]$'; then
    # 任務段以未完結標點收尾：句子顯然還沒說完
    SUSPICIOUS="yes:task-ends-abruptly"
  fi
fi

# 路徑輸出成功後才交棒，讓 stdout 寫入失敗仍能落入 EXIT trap 清理。
# 輸出與交棒之間須為臨界區：訊號若插在兩者之間，host 已收到路徑、EXIT trap 卻仍會刪除它。
# 此處腳本即將結束，遮蔽後無須恢復；printf 失敗仍會經 set -e 落入 EXIT trap 清理。
trap '' INT TERM HUP QUIT
printf 'ROOT=%s\n' "$ROOT"
printf 'WORKDIR=%s\n' "$WORKDIR"
printf 'SPLIT_SUSPICIOUS=%s\n' "$SUSPICIOUS"
CLEANUP=0
