---
name: gh-issue-triage
description: 研究 GitHub Issue，評估是否可直接執行 gh-issue-opsx-autopilot
allowed-tools: Bash(gh *:*), Bash(git *:*), Read, Grep, Glob
---

# GH Issue Triage

評估 GitHub Issue 是否適合由 `gh-issue-opsx-autopilot` 自動化處理，輸出結構化檢核報告。

**輸入**：`$ARGUMENTS` = GitHub Issue 編號（如 `100`）

---

## 執行流程

### Step 1：讀取 GH Issue

```bash
gh issue view $ARGUMENTS --json title,body,assignees,labels,comments,author
```

提取 title、body、labels、comments。

**需求來源優先順序**：Issue body 為原始需求，comments 為補充與定案。若 body 與 comments 有衝突，以 comments 為準。

**既有分析去重**：檢查 comments 中是否已有 triage 報告或技術分析。若已有，以該分析為基礎，僅驗證其結論在當前程式碼狀態下是否仍成立，避免重複分析。

若 Issue 帶有 `discussion` 標籤，**立即中止**並回報：
> Issue #$ARGUMENTS 標記為 `discussion`，尚待團隊討論，不適合進入自動化流程。

### Step 2：查閱既有規格文件

依文件層級由下游往上游查找，以最接近實作的規格為準：

1. 先查 `openspec/specs/` 是否有對應的技術規格
2. 若無，查 `sa/spec/` 是否有對應的系統分析規格
3. 若皆無，表示此 Issue 為全新需求，尚無既有規格可參照

同時讀取現有程式碼中與 Issue 相關的檔案，建立對現狀的理解。

### Step 3：五項檢核

根據 Step 1、Step 2 取得的資訊，逐項檢核：

#### 1. 問題是否仍存在？

- 檢查 dev 分支最新程式碼與近期 commit 歷史（`git log --oneline -20 dev`）
- 確認問題未被其他 PR 或 commit 修復
- 若問題已不存在，說明是哪個 commit 或 PR 解決的

#### 2. 需求是否明確？

- Issue 描述是否完整，能否直接轉化為 SA spec
- 有無模糊、矛盾或缺漏的需求定義
- 是否需要向 Issue 作者或 assignee 釐清

#### 3. 影響範圍預估

- 涉及哪些檔案與模組（前端 / 後端 / 資料庫 / 權限）
- 是否跨模組（跨模組修改風險較高）
- 預估變更量級（小 / 中 / 大）

#### 4. 是否適合 autopilot？

綜合判斷是否符合 autopilot 的適用條件：
- 需求邊界清晰，不存在多種合理解讀
- 不涉及架構大改或底層框架變更
- 影響範圍可控，不會牽動大量模組
- 不需要與外部系統整合或人工介入決策

#### 5. 前置作業

- 有無相依 Issue 未完成（檢查 Issue body 與 comments 中的引用）
- 是否與其他進行中的 feature branch 衝突（`git branch -r --list 'origin/feature/*'`）
- 有無需要先行處理的技術債或前置條件

### Step 4：輸出結論

根據五項檢核結果，給出總結論與結構化報告。

---

## 輸出格式

```markdown
## Issue #NNN Triage: <title>

### 檢核結果

| # | 檢核項目 | 結果 | 說明 |
|---|---------|------|------|
| 1 | 問題存續性 | ✅/⚠️/❌ | <一句話說明> |
| 2 | 需求明確度 | ✅/⚠️/❌ | <一句話說明> |
| 3 | 影響範圍 | ✅/⚠️/❌ | <涉及模組與量級> |
| 4 | Autopilot 適配性 | ✅/⚠️/❌ | <一句話說明> |
| 5 | 前置作業 | ✅/⚠️/❌ | <一句話說明> |

### 總結論：✅ 可直接執行 / ⚠️ 建議先處理以下事項 / ❌ 不建議自動化

<補充說明：若為 ⚠️ 或 ❌，列出具體原因與建議的後續動作>

### 影響範圍明細

- **後端**：<涉及的 Controller / Service / Entity>
- **前端**：<涉及的元件 / Store / API>
- **資料庫**：<涉及的 Entity 或 data.sql 變更>
- **權限**：<是否涉及角色權限變更>
```

### 結論三分法

| 結論 | 含義 | 建議動作 |
|------|------|---------|
| ✅ 可直接執行 | 五項檢核皆無阻礙 | 執行 `/noah:gh-issue-opsx-autopilot $ARGUMENTS` |
| ⚠️ 建議先處理 | 有可排除的障礙 | 處理完障礙後再執行 autopilot |
| ❌ 不建議自動化 | 存在根本性障礙 | 需人工介入處理或重新定義需求 |

---

## Guardrails

- 此 skill 為**純分析型**，不建立分支、不修改程式碼、不留言 Issue
- 所有判斷須基於實際程式碼與 Issue 內容，不做臆測
- 輸出使用繁體中文

---

Issue Number: $ARGUMENTS
