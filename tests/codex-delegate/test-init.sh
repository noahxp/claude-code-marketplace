#!/usr/bin/env bash
# init.sh 切分契約回歸測試
# 用法：test-init.sh <init.sh 路徑>
INIT="${1:?用法: test-init.sh <init.sh 路徑>}"
PASS=0; FAIL=0

# 快照既有工作目錄，殘留檢查只認測試自己建立的（避免被併行流程干擾）
PRE_EXISTING=$(mktemp /tmp/codex-delegate-testpre.XXXXXX)
ls -d /tmp/codex-delegate-* 2>/dev/null | sort > "$PRE_EXISTING"
trap 'rm -f "$PRE_EXISTING"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# expect_ok <案例> <輸入> <期望task> <期望MODE> <期望followup|*> <期望SUSPICIOUS|*>
expect_ok() {
  local desc="$1" arg="$2" want_task="$3" want_mode="$4" want_fu="$5" want_susp="${6:-*}"
  local out
  if ! out=$(bash "$INIT" "$arg" 2>&1); then
    printf '  FAIL %s -> 非預期 die: %s\n' "$desc" "$out"; ((FAIL++)); return
  fi
  local root wd got_task got_mode got_fu got_susp
  root=$(field_of ROOT "$out"); wd=$(field_of WORKDIR "$out"); got_susp=$(field_of SPLIT_SUSPICIOUS "$out")
  got_task=$(sed -n '2p' "$wd/task.md"); got_task="${got_task#TASK: }"
  got_mode=$(sed -n '1p' "$root/host-followup.md"); got_mode="${got_mode#MODE: }"
  got_fu=$(sed -n '2p' "$root/host-followup.md")
  # host-followup.md 必須留在 codex workdir 之外
  local isolated="yes"; [ -e "$wd/host-followup.md" ] && isolated="no"
  safe_rm "$root"
  if [ "$got_task" = "$want_task" ] && [ "$got_mode" = "$want_mode" ] && [ "$isolated" = "yes" ] \
     && { [ "$want_fu" = "*" ] || [ "$got_fu" = "$want_fu" ]; } \
     && { [ "$want_susp" = "*" ] || [ "$got_susp" = "$want_susp" ]; }; then
    printf '  ok   %s\n' "$desc"; ((PASS++))
  else
    printf '  FAIL %s\n' "$desc"
    printf '         task want=[%s] got=[%s]\n' "$want_task" "$got_task"
    printf '         mode want=[%s] got=[%s]\n' "$want_mode" "$got_mode"
    [ "$isolated"  = "yes" ] || printf '         host-followup.md 落在 codex workdir 內\n'
    [ "$want_fu"   = "*" ] || printf '         followup   want=[%s] got=[%s]\n' "$want_fu" "$got_fu"
    [ "$want_susp" = "*" ] || printf '         suspicious want=[%s] got=[%s]\n' "$want_susp" "$got_susp"
    ((FAIL++))
  fi
}

expect_die() {
  local desc="$1" arg="$2" out
  if out=$(bash "$INIT" "$arg" 2>&1); then
    safe_rm "$(field_of ROOT "$out")"
    printf '  FAIL %s -> 應 die 但成功\n' "$desc"; ((FAIL++))
  else
    printf '  ok   %s (die: %s)\n' "$desc" "${out#ERR: }"; ((PASS++))
  fi
}

echo "-- 基本切分"
expect_ok  "A 正常切分"          "a -- b"                 "a" "user-specified" "b"  "no"
expect_ok  "B 無分隔符走預設"     "a"                      "a" "default"        "*"  "no"
expect_ok  "C 旗標不誤切"         "看 --sandbox 用法 -- b"  "看 --sandbox 用法" "user-specified" "b" "no"
expect_ok  "I 尾端單一 --"       "a --"                   "a" "default"        "*"  "no"

echo "-- 邊界（第一輪 codex review 指出）"
expect_ok  "D followup 尾端含 --" "a -- b --"              "a" "user-specified" "b --" "*"
expect_ok  "E followup 就是 --"   "a -- --"                "a" "user-specified" "--"   "*"
expect_ok  "G 分隔後純空白走預設"  "a --  "                 "a" "default"        "*"    "no"
expect_ok  "H followup 為 -n"     "a -- -n"                "a" "user-specified" "-n"   "*"
expect_ok  "H2 followup 為 -e"    "a -- -e"                "a" "user-specified" "-e"   "*"
expect_die "F 前導空白後空任務"    "  -- b"
expect_die "K 純空白任務"         "   "
expect_die "L 空參數"             ""
expect_die "M 開頭即分隔符"       "-- b"

echo "-- 可疑切分偵測"
expect_ok "N 後處理比任務長"   "請覆驗 (1) 尾端 -- 的剝除是否還會讓 a -- b -- 遺失 followup 內容" \
          "請覆驗 (1) 尾端" "user-specified" "*" "yes:followup-longer-than-task"
expect_ok "O 後處理以助詞開頭" "請檢查這份很長很長很長很長的規格文件的邊界情境是否完整 -- 的部分" \
          "請檢查這份很長很長很長很長的規格文件的邊界情境是否完整" "user-specified" "*" "yes:followup-starts-mid-sentence"
expect_ok "P 任務以未完結標點收尾" "請覆驗以下四點： -- 修掉" \
          "請覆驗以下四點：" "user-specified" "*" "yes:task-ends-abruptly"
expect_ok "Q 正常長指示不誤報"  "請 review docs/spec.md 這份規格文件的完整性 -- 覆驗後屬實就修掉" \
          "請 review docs/spec.md 這份規格文件的完整性" "user-specified" "覆驗後屬實就修掉" "no"

echo "-- 破壞性動作偵測（第二輪 codex review 指出的漏報）"
expect_ok "R 中文破壞性動詞"   "請仔細分析這份規格文件的範例 -- 刪除檔案" \
          "請仔細分析這份規格文件的範例" "user-specified" "*" "yes:followup-has-destructive-verb"
expect_ok "S rm 指令"          "請分析這份規格文件的所有範例與邊界情境 -- rm -rf 舊目錄" \
          "請分析這份規格文件的所有範例與邊界情境" "user-specified" "*" "yes:followup-has-destructive-verb"
expect_ok "T git 強制操作"     "請分析這份規格文件的所有範例與邊界情境 -- reset --hard" \
          "請分析這份規格文件的所有範例與邊界情境" "user-specified" "*" "yes:followup-has-destructive-verb"

expect_ok "U delete the file"  "分析這份規格文件的完整性與邊界 -- delete the file" \
          "分析這份規格文件的完整性與邊界" "user-specified" "*" "yes:followup-has-destructive-verb"
expect_ok "V git clean"        "分析這份規格文件的完整性與邊界 -- git clean -fd" \
          "分析這份規格文件的完整性與邊界" "user-specified" "*" "yes:followup-has-destructive-verb"
expect_ok "W 刪掉（非刪除）"    "分析這份規格文件的完整性與邊界 -- 刪掉舊檔" \
          "分析這份規格文件的完整性與邊界" "user-specified" "*" "yes:followup-has-destructive-verb"
expect_ok "X tab 分隔的 rm"    "$(printf '分析這份規格文件的完整性與邊界 -- rm\t-rf tmp')" \
          "分析這份規格文件的完整性與邊界" "user-specified" "*" "yes:followup-has-destructive-verb"

echo "-- no-split 逃生口（任務正文含獨立 -- 時）"
NS_OUT=$(CODEX_DELEGATE_NO_SPLIT=1 bash "$INIT" "請覆驗 (1) 尾端 -- 的剝除是否正確")
NS_ROOT=$(field_of ROOT "$NS_OUT"); NS_W=$(field_of WORKDIR "$NS_OUT")
NS_TASK=$(sed -n '2p' "$NS_W/task.md"); NS_TASK="${NS_TASK#TASK: }"
NS_MODE=$(sed -n '1p' "$NS_ROOT/host-followup.md"); NS_MODE="${NS_MODE#MODE: }"
safe_rm "$NS_ROOT"
if [ "$NS_TASK" = "請覆驗 (1) 尾端 -- 的剝除是否正確" ] && [ "$NS_MODE" = "default" ]; then
  printf '  ok   Y NO_SPLIT=1 時整串保留（未被 -- 切開）、後處理走預設\n'; ((PASS++))
else
  printf '  FAIL Y NO_SPLIT task=[%s] mode=[%s]\n' "$NS_TASK" "$NS_MODE"; ((FAIL++))
fi

expect_ok "Z remove"     "分析這份規格文件的完整性與邊界 -- remove the old dir" \
          "分析這份規格文件的完整性與邊界" "user-specified" "*" "yes:followup-has-destructive-verb"
expect_ok "Z2 overwrite"  "分析這份規格文件的完整性與邊界 -- overwrite config" \
          "分析這份規格文件的完整性與邊界" "user-specified" "*" "yes:followup-has-destructive-verb"
expect_ok "Z3 覆蓋"       "分析這份規格文件的完整性與邊界 -- 覆蓋設定檔" \
          "分析這份規格文件的完整性與邊界" "user-specified" "*" "yes:followup-has-destructive-verb"

echo "-- NO_SPLIT 的空白契約"
NS2_OUT=$(CODEX_DELEGATE_NO_SPLIT=1 bash "$INIT" "   前後有空白的任務含 -- 分隔符   ")
NS2_ROOT=$(field_of ROOT "$NS2_OUT"); NS2_W=$(field_of WORKDIR "$NS2_OUT")
NS2_TASK=$(sed -n '2p' "$NS2_W/task.md"); NS2_TASK="${NS2_TASK#TASK: }"
safe_rm "$NS2_ROOT"
if [ "$NS2_TASK" = "前後有空白的任務含 -- 分隔符" ]; then
  printf '  ok   Y2 NO_SPLIT 去除前後空白後完整保留（含內部 --）\n'; ((PASS++))
else
  printf '  FAIL Y2 NO_SPLIT 空白契約 got=[%s]\n' "$NS2_TASK"; ((FAIL++))
fi

echo "-- 殘留檢查"
LEAKED=$(comm -13 "$PRE_EXISTING" <(ls -d /tmp/codex-delegate-* 2>/dev/null | sort) | grep -v 'codex-delegate-testpre' || true)
if [ -n "$LEAKED" ]; then
  printf '  FAIL 測試期間殘留: %s\n' "$LEAKED"; ((FAIL++))
else
  printf '  ok   測試期間無殘留\n'; ((PASS++))
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
