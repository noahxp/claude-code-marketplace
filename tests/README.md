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

`codex-delegate/helpers.sh` 是兩份測試共用的 `safe_rm` 與 `field_of`。
