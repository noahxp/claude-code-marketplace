---
name: ai-perf-record
description: 透過 Chrome DevTools 自動填寫 AI 效率提升紀錄表單
allowed-tools: Bash(gh *:*), mcp__plugin_chrome-devtools-mcp_chrome-devtools__*
---

# AI 效率提升紀錄填寫

透過 Chrome DevTools MCP 自動填寫 https://ai-performance.fp.104-dev.com.tw/input 的效率提升紀錄表單。

支援兩種模式：

- **單筆模式**：針對單一 Issue 或 PR 填一筆紀錄。
- **批次模式**：對當前 repo 所有已 merged 的 PR 逐筆填寫。

**最重要的硬規則**：每一筆表單填妥後，**一律交付使用者確認，嚴禁自行點擊「儲存紀錄」按鈕**。

---

## 模式與參數判斷

從 `$ARGUMENTS` 判斷模式：

- 能解析出「編號 + 兩個分鐘數」三參數 → **單筆模式**，格式 `<Issue或PR編號> <導入AI前分鐘> <導入AI後分鐘>`（例：`181 180 25`）。
- `$ARGUMENTS` 為空，或僅指示「所有 merged PR」而未帶分鐘數 → **批次模式**。

---

## 共用：表單欄位實況（填寫時對照）

實際 a11y 結構與易錯點：

- **任務類型**（combobox）選項：`程式開發 / 文件註解 / 測試撰寫 / 問題除錯 / 解析說明 / 優化重構 / 其它`。
- **任務項目**（combobox，需選完任務類型才會由 disabled 啟用；「程式開發」下的選項）：`程式碼生成 / Infra. 架構開發 / 自動化與 CI/CD / 資料與數據處理`。
- **導入 AI 前 / 導入 AI 後**：spinbutton，直接 `fill` 數字；填妥後系統會即時顯示「效率提升 %」與「節省分鐘」。
- **功能 / 專案名稱**：textbox，上限 100 字（計數器顯示 `n / 100`）。
- **使用的 AI 工具**：可輸入 combobox —— `fill` 後會浮出比中的選項，**必須再 `click` 該 option** 才算選定。
- **使用情境與實作方式**：multiline textbox，上限 1000 字（計數器 `n / 1000`）。
- 所有必填欄位齊全後，「儲存紀錄」按鈕才由 disabled 轉為可按。

下拉操作模式皆為：`click` 展開 → `take_snapshot` 取得選項 uid → `click` 選擇目標選項。

---

## 共用：環境與登入檢查

1. 使用 `list_pages` 確認瀏覽器已開啟。
2. 使用 `navigate_page` 導航至 `https://ai-performance.fp.104-dev.com.tw/input`。
3. 使用 `take_snapshot` 檢查頁面狀態：
   - **若 URL 包含 `/login`**：表示未登入或 O365 登入已過期。**立即停止**，提示使用者：
     > 「O365 登入已過期，請在瀏覽器中手動點擊『使用 Microsoft 帳號登入』完成登入後，再重新執行此 Skill。」
   - **若 URL 為 `/input` 且表單已載入**：繼續填寫。

---

## 共用：填寫單筆紀錄的子流程

備妥（編號、導入前分鐘、導入後分鐘、功能名稱、摘要）後，依序操作：

1. **任務類型**：展開 → 選「程式開發」。
2. **任務項目**：展開 → 選「程式碼生成」。
3. **導入 AI 前**：`fill` 導入前分鐘。
4. **導入 AI 後**：`fill` 導入後分鐘。
5. **功能 / 專案名稱**：`fill` 功能名稱。
6. **使用的 AI 工具**：`fill` `Claude Code` → **`click` 比中的 option** 確認選取。
7. **使用情境與實作方式**：`fill` 摘要（**≤150 中文字**）。
8. `take_snapshot` 截圖，向使用者呈現完整確認表（含系統計算的效率提升 % 與節省分鐘），交付確認。**嚴禁自行點擊「儲存紀錄」。**

> 任務類型/項目固定填「程式開發 / 程式碼生成」；若某筆性質不符（如純文件、bugfix），使用者可於儲存前自行於下拉微調。

---

## 單筆模式流程

1. 解析三參數；不足三個則停止並提示正確格式：
   > 格式：`/noah:ai-perf-record <Issue或PR編號> <導入AI前分鐘> <導入AI後分鐘>`
   > 範例：`/noah:ai-perf-record 181 180 25`
2. 蒐集資料：
   ```bash
   gh issue view {編號} --json title,body      # 若為 PR 則改用 gh pr view
   gh repo view --json name --jq '.name'
   gh pr list --search "#{編號}" --state all --json number,title,body
   ```
3. 功能名稱 = `({repo-name}){標題} #{編號}`（例：`(mis-rms)外部連線 Proxy 設定 #181`）。
4. 依需求描述與實際變更生成摘要（**≤150 中文字**），描述「AI 如何完成此項工作」。
5. 走「環境與登入檢查」+「填寫單筆紀錄的子流程」，交付使用者確認儲存。

---

## 批次模式流程

1. 取得 repo 名稱：
   ```bash
   gh repo view --json name --jq '.name'
   ```
2. 取得**所有已 merged** 的 PR（**排除未 merge / 直接關閉**的）：
   ```bash
   gh pr list --state merged --limit 100 --json number,title,mergedAt
   ```
3. 逐一取得各 PR 的內容與變更規模：
   ```bash
   gh pr view {編號} --json title,body,additions,deletions,changedFiles
   ```
4. 對每個 PR 準備填寫資料：
   - 若使用者未提供分鐘數，**依複雜度（檔案數、增減行數、功能範疇）估算**合理的導入前/後分鐘；
   - 功能名稱 = `({repo-name}){PR標題} #{PR編號}`（repo 無對應 issue 時。若該 PR 有關聯 issue，亦可改用 issue 標題/編號）；
   - 生成摘要（**≤150 中文字**）。
5. 逐筆執行：`navigate_page` 至 `/input` → 走「填寫單筆紀錄的子流程」→ 呈確認表（**估算的分鐘數一併標示，供使用者調整**）→ 由使用者按「儲存紀錄」。
6. **儲存後頁面會跳轉至 `/records`**，故填下一筆前**必須重新 `navigate_page` 回 `/input`**，並以新的 `take_snapshot` 取得 uid（不可沿用前一筆的舊 uid）。
7. 全數完成後，回報總覽（已填筆數、各筆功能名稱與效率提升摘要）。

> 建議在開始填寫前，先將估算好的「各 PR 前/後分鐘 + 摘要」整理成一張總表呈報使用者，便於其在逐筆儲存過程中核對與調整。
