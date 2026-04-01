---
name: ai-perf-record
description: 透過 Chrome DevTools 自動填寫 AI 效率提升紀錄表單
allowed-tools: Bash(gh *:*), mcp__plugin_chrome-devtools-mcp_chrome-devtools__*
---

# AI 效率提升紀錄填寫

透過 Chrome DevTools MCP 自動填寫 https://ai-performance.fp.104-dev.com.tw/input 的效率提升紀錄表單。

**輸入**：`$ARGUMENTS`，格式為 `<ISSUE編號> <導入AI前分鐘> <導入AI後分鐘>`

**範例**：`/noah:ai-perf-record 181 180 25`

**限制**：表單填寫完成後，必須交由使用者確認，不得自行點擊「儲存紀錄」。

---

## 執行流程

### 步驟 1：解析參數

從 `$ARGUMENTS` 解析三個參數：

- 第一個：ISSUE 編號（例如 `181`）
- 第二個：導入 AI 前時間（分鐘）
- 第三個：導入 AI 後時間（分鐘）

若參數不足三個，停止執行並提示使用者正確格式：

> 格式：`/noah:ai-perf-record <ISSUE編號> <導入AI前分鐘> <導入AI後分鐘>`
> 範例：`/noah:ai-perf-record 181 180 25`

### 步驟 2：蒐集資料並生成摘要

1. 取得 Issue 標題與描述，以及當前 repo 名稱：

```bash
gh issue view {ISSUE編號} --json title,body
gh repo view --json name --jq '.name'
```

2. 取得對應 PR 的標題與變更內容：

```bash
gh pr list --search "#{ISSUE編號}" --state all --json number,title,body
```

3. 根據 Issue 需求描述與 PR 實際變更內容，生成一段描述「AI 如何完成此 ISSUE」的摘要，不超過 100 個中英文字。

4. 記錄 repo 名稱與 Issue 標題，後續用於「功能 / 專案名稱」欄位，格式為 `({repo-name}){Issue Title} #{ISSUE編號}`。

### 步驟 3：確認瀏覽器狀態

使用 `list_pages` 確認瀏覽器已開啟。

### 步驟 4：導航至新增紀錄頁面

使用 `navigate_page` 導航至 `https://ai-performance.fp.104-dev.com.tw/input`。

### 步驟 5：登入檢查

使用 `take_snapshot` 檢查頁面狀態：

- **若 URL 包含 `/login`**：表示未登入或 O365 登入已過期。**立即停止**，提示使用者：
  > 「O365 登入已過期，請在瀏覽器中手動點擊『使用 Microsoft 帳號登入』完成登入後，再重新執行此 Skill。」
- **若 URL 為 `/input` 且表單已載入**：繼續執行下一步。

### 步驟 6：填寫表單

依以下順序操作。每個下拉選單的操作模式為：`click` 展開 → `take_snapshot` 取得選項 uid → `click` 選擇目標選項。

#### 6.1 任務類型（combobox）

1. `click` 「任務類型」的 combobox 元素
2. `take_snapshot` 取得展開後的選項列表
3. `click` 選擇「程式開發」選項

#### 6.2 任務項目（combobox，依賴任務類型選擇後才啟用）

1. `click` 「任務項目」的 combobox 元素（選完任務類型後即啟用，若仍為 disabled 則先 `take_snapshot` 等待）
2. `take_snapshot` 取得展開後的選項列表
3. `click` 選擇「程式碼生成」選項

#### 6.3 導入 AI 前（spinbutton）

1. `fill` 「導入 AI 前」的 spinbutton，值為 `$ARGUMENTS` 第二個參數

#### 6.4 導入 AI 後（spinbutton）

1. `fill` 「導入 AI 後」的 spinbutton，值為 `$ARGUMENTS` 第三個參數

#### 6.5 功能 / 專案名稱（textbox）

1. `fill` 「功能 / 專案名稱」的 textbox，值為 `({repo-name}){Issue Title} #{ISSUE編號}`（從步驟 2 取得，例如 `(mis-rms)外部連線 Proxy 設定 #181`）

#### 6.6 使用的 AI 工具（可輸入 combobox）

1. `fill` 「使用的 AI 工具」的 combobox 元素，值為 `Claude Code`

#### 6.7 使用情境與實作方式（multiline textbox）

1. `fill` 「使用情境與實作方式」的 textbox，值為步驟 2 生成的摘要

### 步驟 7：確認填寫結果

使用 `take_snapshot` 截取填寫完成的表單，向使用者呈現所有已填入的值。

### 步驟 8：交付使用者確認

將填寫結果呈交使用者確認。**嚴禁自行點擊「儲存紀錄」按鈕**。
