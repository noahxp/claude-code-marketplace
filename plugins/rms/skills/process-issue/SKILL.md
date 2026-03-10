---
name: process-issue
description: 從 GitHub Issue 一貫執行到 Draft PR（含 spec 撰寫、審查、OpenSpec 工作流、review、e2e、歸檔）
allowed-tools: Bash(gh *:*), Bash(git *:*), Bash(openspec *:*), Bash(cd *:*), Bash(mkdir *:*), Bash(mv *:*), Bash(gradle *:*), Bash(npm *:*), Read, Write, Edit, Grep, Glob, Agent, Skill, TodoWrite
---

# RMS: Process Issue

從 GitHub Issue 自動執行完整開發流程到 Draft PR。含 SA spec 撰寫、雙重品質把關、OpenSpec 工作流、Code Review、E2E 測試、歸檔與 PR 建立。

**輸入**：`$ARGUMENTS` = GitHub Issue 編號（如 `38`）

---

## 執行流程

> **自動化規則**：本 Skill 為全自動流程，所有步驟必須連續執行直到完成或遇到把關點不通過。
> - 不得在步驟之間停下來等待使用者指示（除非把關點明確要求中止）
> - 調用其他 Skill（如 `/opsx:propose`、`/opsx:apply`、`/opsx:verify`、`/opsx:archive`）時，**必須透過 Agent tool（general-purpose）包裝**，確保完成後控制權回到本流程
> - 不得直接使用 Skill tool 調用其他 skill（Skill tool 會將控制權轉移至內層 skill，無法自動返回）

### Phase 0: 初始化與重入偵測

1. **讀取 GH Issue**

   ```bash
   gh issue view $ARGUMENTS --json title,body,assignees,labels,comments,author
   ```

   提取：title、body（需求內容）、assignees（用於 tag）、author（Issue 建立者，用於 tag）、comments（用於重入時讀取釐清結果）。

2. **推導命名**

   從 issue number + title 推導：
   - Issue 編號補零至三碼：`NNN`（如 Issue #5 → `005`）
   - 功能英文名稱：從 title 提取，kebab-case，最多三個單字
   - 分支名：`feature/NNN-kebab-name`
   - Spec 路徑：`sa/spec/NNN-kebab-name/`
   - OpenSpec change 名：由 `/opsx:propose` 自動決定，無需預先指定

3. **偵測已有產物，判斷接續點**

   | 偵測條件 | 接續點 |
   |---------|--------|
   | 無 feature branch、無 spec | 從頭開始（Phase 1） |
   | 有 branch + spec，但無 OpenSpec change | 讀取 Issue comments 取得釐清結果 → Phase 1 步驟 4（Spec 審查） |
   | 有 branch + spec + OpenSpec change（tasks 未完成）| Phase 2 步驟 2（apply） |
   | 有 branch + spec + OpenSpec change（tasks 全完成）| Phase 2 步驟 3（verify） |
   | 已有 Draft PR | 回報「Issue #NNN 已有 Draft PR，中止」 |

   **重入時讀取釐清結果**：解析 Issue comments，找出先前由本 Skill 留下的「自動處理中止」留言，以及後續 assignee 的回覆，作為 spec 更新的輸入。

   顯示：「Issue #NNN: <title>，接續點：<phase/step>」

---

### Phase 1: 需求分析與品質把關

4. **建立 feature branch**

   從 **dev** 分支建立（若 branch 已存在則 checkout）：
   ```bash
   git checkout dev && git pull
   git checkout -b feature/NNN-kebab-name
   ```

5. **閱讀相關原始需求規格**

   根據 CLAUDE.md §規格文件 的檔案對應關係，讀取 `spec-ag-opus45/` 中對應的規格文件。涉及跨模組時一併閱讀 `00-系統總覽.md`。

6. **撰寫 SA spec**

   寫入 `sa/spec/NNN-xxx/spec.md`。
   - 若為首次執行：根據 Issue body + 原始需求規格撰寫
   - 若為重入：根據 Issue comments 中的釐清結果更新既有 spec

   Spec 內容須包含：業務背景、規格書依據、現狀分析、修正規格、影響範圍、測試規格。

7. **把關點 1：Spec 自審**

   檢查四項標準：
   1. 無邏輯衝突
   2. 需求定義完整
   3. 無遺漏必要欄位
   4. 與既有架構一致

   **通過** → 繼續至步驟 8
   **不通過** → 執行「中止流程」（見下方）

8. **把關點 2：Explore**

   以 `/opsx:explore` 的思維模式，深入探索 spec 與現有程式碼的交互：
   - 讀取相關的現有程式碼（Controller、Service、Entity、前端元件等）
   - 確認影響範圍是否完整
   - 發現隱藏的邊界情況或技術風險
   - 確認與現有設計模式的一致性

   **通過**（無隱藏問題）→ 繼續至 Phase 2
   **不通過**（發現需要釐清的問題）→ 執行「中止流程」（見下方）

---

### Phase 2: 實作與驗證

9. **OpenSpec propose**

   從 SA spec + Issue 內容推導 change name（kebab-case + NNN 編號後綴，如 `filter-options-null-023`）。

   使用 **Agent tool**（general-purpose）執行：
   > 使用 Skill tool 調用 `opsx:propose`，參數為以下描述：
   > 「<從 SA spec 整理的 change 描述，含 Issue 編號、變更內容、影響範圍>」
   > Change name 為 `<change-name>`。
   > SA spec 位於 `sa/spec/NNN-xxx/spec.md`。

   Agent 完成後，讀取回傳結果確認 artifacts 已建立，**立即繼續步驟 10**。

10. **OpenSpec apply**

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `opsx:apply`，參數為 change name `<change-name>`。
    > 遵循 TDD 流程（Red → Green → Refactor）實作所有 tasks。
    > 後端必須撰寫測試（單元 + 整合），前端不撰寫測試。

    Agent 完成後，讀取回傳結果確認所有 tasks 已完成，**立即繼續步驟 11**。

11. **OpenSpec verify**

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `opsx:verify`，參數為 change name `<change-name>`。
    > 驗證三個維度：Completeness、Correctness、Coherence。
    > 回傳驗證報告。

    若回傳結果包含 CRITICAL issues → 在主流程中修復，再次用 Agent 執行 verify，直到全部通過。
    通過後**立即繼續 Phase 3**。

---

### Phase 3: 品質審查

12. **Code Review（平行 subagent）**

    使用 Agent tool 同時啟動三個 subagent：
    - `pr-review-toolkit:code-reviewer` — 程式碼品質、邏輯錯誤、安全漏洞
    - `pr-review-toolkit:pr-test-analyzer` — 測試覆蓋率與測試品質
    - `pr-review-toolkit:silent-failure-hunter` — 靜默失敗與錯誤處理

    規格參考：`sa/spec/NNN-xxx/spec.md` 與 Phase 2 產出的 OpenSpec change 目錄

    審查結果分為兩類：

    **A. 本次變更引入的問題**：
    - 若有 CRITICAL/HIGH 發現 → 在主流程中修復，再重新審查直到通過

    **B. 既有程式碼的預存問題**（reviewer 掃描相關檔案時順帶發現的非本次變更引入的問題）：

    依問題性質分流處理：

    | 判斷條件 | 處理方式 |
    |---------|---------|
    | **不需討論**：修正方式明確、風險低、不涉及架構決策（如：缺少 try-catch、缺少 console.warn、空 catch block） | 直接在本次 PR 中一併修復，commit message 以 `fix:` 或 `refactor:` 獨立提交（與主要修正分開 commit），並在 PR body 的「額外修正」區塊列出 |
    | **需要討論**：涉及架構決策、影響範圍大、需求不明確、或可能改變既有行為（如：型別設計變更、API 契約調整、跨模組重構） | 在 GH Issue 上留言通知 assignees 與 author，格式見下方 |

    **既有問題需討論時的留言格式**：

    ```bash
    gh issue comment $ARGUMENTS --body "$(cat <<'EOF'
    ## 🔍 審查發現：既有程式碼問題

    在處理本 Issue 時，Code Review 發現以下既有問題，建議另開 Issue 追蹤：

    ### [SEVERITY] 問題標題
    - **位置**：`檔案路徑:行號`
    - **問題**：具體描述
    - **建議**：修正方向

    ---

    @ASSIGNEE @AUTHOR 以上為既有問題（非本次變更引入），建議評估是否需要處理。
    EOF
    )"
    ```

13. **Code Simplify**

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `simplify`。
    > 審查本次變更的所有程式碼，參照 `sa/spec/NNN-xxx/spec.md` 與 OpenSpec change 目錄作為需求規格。

    Agent 完成後，讀取回傳結果。若有修正建議，在主流程中處理。
    **立即繼續 Phase 4**。

---

### Phase 4: E2E 測試與收尾

14. **E2E 測試**

    1. 撰寫 `sa/spec/NNN-xxx/e2e.md`（E2E 測試腳本）
    2. 使用 Chrome DevTools MCP 執行測試
    3. 將測試結果記錄回 `e2e.md`

15. **OpenSpec archive**

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `opsx:archive`，參數為 change name `<change-name>`。
    > 歸檔變更並同步 delta specs 至 main specs。
    > 遇到確認提示時一律選擇「同步並歸檔」。

    Agent 完成後，讀取回傳結果確認歸檔完成，**立即繼續步驟 16**。

16. **Git Commit**

    將所有變更提交。Commit message **必須包含 subject + body + footer**，格式如下：

    ```bash
    git add <相關檔案>
    git commit -m "$(cat <<'EOF'
    <type>: <繁體中文描述> (#NNN)

    <Why — 說明變更動機與背景>

    Closes #NNN
    EOF
    )"
    ```

    **規則**：
    - **Subject**（What）：遵循 Conventional Commits（`feat:` / `fix:` / `refactor:` / `docs:` 等），繁體中文描述，結尾附 `(#NNN)`
    - **Body**（Why）：說明「為什麼」需要這個變更——問題的背景、動機、與變更前行為的對比。不要重複 diff 已能看到的內容（改了哪些檔案、加了哪些程式碼）
    - **Footer**：`Closes #NNN` 關聯 Issue
    - Subject、Body、Footer 之間各隔一行空行
    - 若有「額外修正（既有問題）」，以獨立 commit 提交，subject 使用對應的 type

17. **開 Draft PR**

    ```bash
    gh pr create --draft --base dev \
      --title "<type>: <繁體中文描述> (#NNN)" \
      --body "$(cat <<'EOF'
    ## 功能概述

    <一句話說明>

    ## 變更內容

    - <主要改動列點>

    ## 額外修正（既有問題）

    > 若無額外修正則移除此區塊

    - <審查時發現的既有問題修正列點>

    ## 測試結果

    - Backend 單元測試：X/Y 通過
    - Backend 整合測試：通過
    - E2E 測試：N/N 通過
    - Frontend 類型檢查：通過

    ## 相關文件

    - `sa/spec/NNN-xxx/spec.md` — SA 規格
    - `sa/spec/NNN-xxx/e2e.md` — E2E 測試腳本與結果
    - `openspec/changes/archive/YYYY-MM-DD-xxx-NNN/` — OpenSpec 歸檔

    Closes #NNN
    EOF
    )"
    ```

    顯示 PR URL，流程完成。

---

## 中止流程

在把關點 1 或 2 不通過時：

1. 將發現的問題整理為結構化留言
2. 在 GH Issue 上留言並 tag assignees

```bash
gh issue comment $ARGUMENTS --body "$(cat <<'EOF'
## 🤖 自動處理中止：需要討論

**處理階段**：[Spec 審查 / Explore 探索]

以下問題需要釐清後才能繼續：

1. [具體問題描述]
2. [具體問題描述]

---

@ASSIGNEE 請確認上述問題。確認後可重新執行 `/rms:process-issue $ARGUMENTS` 接續處理。
EOF
)"
```

3. 向使用者回報中止原因與 Issue comment 連結

---

## 進度回報格式

每完成一個 Phase 時，回報進度：

```
## Issue #NNN: <title>

### 進度
- [x] Phase 0: 初始化
- [x] Phase 1: 需求分析與品質把關
- [ ] Phase 2: 實作與驗證（進行中：apply 4/7 tasks）
- [ ] Phase 3: 品質審查
- [ ] Phase 4: E2E 測試與收尾
```

---

## Guardrails

- 所有程式碼變更遵循 TDD（Red → Green → Refactor）
- 後端必須撰寫測試（單元 + 整合），前端不撰寫測試
- 繁體中文：程式碼註解、文件、Git commit（Conventional Commits）
- 禁止硬編碼密鑰
- 修改權限相關程式碼前，先分析現有安全模式
- 各步驟中可獨立執行的工作，應以平行 subagent 處理

---

Issue Number: $ARGUMENTS
