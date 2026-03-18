---
name: gh-issue-e2e-test
description: 使用 Chrome DevTools 執行 E2E 測試，結果整理為 PR Comment 格式
allowed-tools: Bash(git *:*), Read, Grep, Glob, Agent, mcp__plugin_chrome-devtools-mcp_chrome-devtools__*
---

# GH Issue E2E Test

使用 Chrome DevTools 對當前 feature branch 執行 E2E 測試，依據 SA spec 中的測試案例逐一驗證，測試通過後整理複驗結果為 Pull Request Comment 格式。

**輸入**：`$ARGUMENTS`（選填，無參數時自動以當前 branch 推導）

**限制**：測試結果整理完成後，必須先交由使用者確認，不得自行發佈 Comment。

---

## 執行流程

### 步驟 1：取得當前 Branch

```bash
BRANCH_NAME=$(git branch --show-current)
```

### 步驟 2：讀取測試案例

1. 讀取測試案例文件：`sa/spec/${BRANCH_NAME}/e2e.md`
2. 若對 e2e.md 內容有疑慮（不完整、不明確、與預期不符），讀取原始規格 `sa/spec/${BRANCH_NAME}/spec.md` 進行對照

### 步驟 3：文件衝突檢查

若 `e2e.md` 與 `spec.md` 之間存在以下情況，**必須停下與使用者討論**，不得自行判斷：

- 測試案例與規格描述有矛盾
- 測試案例涵蓋範圍與規格不一致
- 任何不明確或有歧義的測試條件

### 步驟 4：執行 E2E 測試

使用 Chrome DevTools MCP 工具，依 `e2e.md` 中定義的測試案例逐一執行：

1. 依測試案例順序操作頁面（導航、點擊、輸入、等待等）
2. 每個測試案例執行後截圖記錄結果
3. 驗證實際行為是否符合預期結果
4. 若測試失敗，記錄失敗原因與截圖，繼續執行剩餘案例

### 步驟 5：整理複驗報告

測試 ALL PASS 時，將複驗結果整理為 Pull Request Comment 格式：

```markdown
## E2E 測試複驗結果

### 測試環境
- Branch: `${BRANCH_NAME}`
- 測試時間: YYYY-MM-DD HH:MM

### 測試結果

| # | 測試案例 | 結果 |
|---|---------|------|
| 1 | <案例描述> | ✅ PASS |
| 2 | <案例描述> | ✅ PASS |
...

### 備註
<如有需要補充的觀察或建議>

---
🤖 Generated with Claude Code
```

### 步驟 6：交付確認

將整理好的 Comment 內容呈交使用者確認，**不得自行執行發佈**。
