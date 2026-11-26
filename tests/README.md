# tests

skill 內 shell script 的回歸測試。

**刻意放在 repo 根層而非 `plugins/` 底下**：`marketplace.json` 的 `source` 指向整個
`./plugins/noah-tools`，放在那裡的檔案會隨 plugin 安裝到每位使用者的機器上。
測試只對維護者有意義，不該進入分發物。

## 執行

```bash
bash tests/run-all.sh
```

或單獨執行（測試接收被測 script 的路徑當參數）：

```bash
bash tests/codex-delegate/test-init.sh  plugins/noah-tools/skills/codex-delegate/scripts/init.sh
bash tests/codex-delegate/test-codex.sh plugins/noah-tools/skills/codex-delegate/scripts/codex.sh
```

**必須以 `bash` 執行**：`codex.sh` 的 `lib/common.sh` 用 `${BASH_SOURCE[0]}` 定位
`refusal-patterns.txt`，在 zsh 下 source 會解析成錯誤路徑，health check 的規則 A 會被靜默跳過。

## 涵蓋範圍

| 檔案 | 對象 | 案數 |
|------|------|------|
| `codex-delegate/test-init.sh` | `init.sh` 的切分契約、可疑切分偵測、破壞性動作偵測、NO_SPLIT、殘留檢查 | 30 |
| `codex-delegate/test-codex.sh` | `codex.sh` 的 model 參數、`--ephemeral`、rc 傳遞、health check A/B/C、額度分類、後處理指示不得進入 prompt、STATUS 契約、`safe_rm` 路徑防護 | 39 |
| `dev-council/test-init.sh` | `init.sh` 的工作目錄位置、權限與唯一性 | 6 |
| `dev-council/test-common.sh` | `lib/common.sh` 的登入／額度／其他失敗分類（含兩方登出時的實測訊息，以及兩個 cli 執行檔內的 token 過期訊息）、brief 五段檢查（含舊版除錯段落不被接受）、health check、成功檔與 `.failed.md` 命名、其他方成功檔清單 | 48 |
| `dev-council/test-codex.sh` | `codex.sh` 的 preflight 各回傳碼、唯讀沙箱與 `--ephemeral`、rc=137 冷卻重試、登出時的實測錯誤事件、回覆內容不誤判為登入失效、第二輪只列成功的其他方、中途終止仍清掉暫存目錄、prompt 的唯讀指令提示 | 41 |
| `dev-council/test-agy.sh` | `agy.sh` 的 preflight 各回傳碼、`--mode plan`、`--settings` 唯讀指令允許清單（須完全相符，不含有寫檔或執行參數的指令）且與 prompt 列出的一致、在 repo 內執行與 `--add-dir`、sentinel 擷取、截斷回覆不誤判為登入失效、第二輪只列成功的其他方、中途終止仍清掉暫存目錄、預設時間上限 600s 與新版逾時訊息的提示、登出時的實測訊息（stdout 為空時不印誤導的標籤） | 48 |
| `dev-council/test-claude.sh` | `claude.sh` 的派工 prompt（以「答案」回應 brief 的問題、需求類先查 spec）與 health check、失敗改名 | 20 |

各 skill 目錄下的 `helpers.sh` 是該 skill 測試共用的函式（`safe_rm`、`field_of` 等）。

`dev-council/smoke-agy-allowlist.sh` 是手動冒煙測試：呼叫真實 agy，確認指令允許清單擋得下 `;`、`&&` 串接、輸出重導向與指令替換。它會消耗 agy 額度且需已登入，所以不在 `run-all.sh` 內；agy 升級後執行 `bash tests/dev-council/smoke-agy-allowlist.sh`。
