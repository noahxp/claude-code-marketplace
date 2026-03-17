---
name: gh-issue-autopilot
description: 從 GitHub Issue 一貫執行到 Draft PR（含 spec 撰寫、審查、OpenSpec 工作流、review、e2e、歸檔）
allowed-tools: Bash(gh *:*), Bash(git *:*), Bash(mkdir *:*), Bash(gradle *:*), Bash(npm *:*), Bash(pkill *:*), Bash(curl *:*), Bash(date *:*), Read, Write, Edit, Grep, Glob, Agent, Skill, TodoWrite
---

# GH Issue Autopilot

從 GitHub Issue 自動執行完整開發流程到 Draft PR。含 SA spec 撰寫、雙重品質把關、OpenSpec 工作流、Code Review、E2E 測試、歸檔與 PR 建立。

**輸入**：`$ARGUMENTS` = GitHub Issue 編號（如 `38`）

---

## 執行流程

> **自動化規則**：本 Skill 為全自動流程，所有步驟必須連續執行直到完成或遇到把關點不通過。
> - 不得在步驟之間停下來等待使用者指示（除非把關點明確要求中止）
> - 調用其他 Skill（如 `/opsx:propose`、`/opsx:apply`、`/opsx:verify`、`/opsx:archive`）時，**必須透過 Agent tool（general-purpose）包裝**，確保完成後控制權回到本流程
> - 不得直接使用 Skill tool 調用其他 skill（Skill tool 會將控制權轉移至內層 skill，無法自動返回）

### Commit Message Convention

流程中有多個 commit 時間點（步驟 11、14、17、20），皆遵循以下規範：

```bash
git add <相關檔案>
git commit -m "$(cat <<'EOF'
<type>: <繁體中文描述> (#NNN)

<Why — 說明變更動機與背景>

Refs #NNN
EOF
)"
```

- **type**：執行 `git diff --cached` 判斷變更內容，據此選擇適當的 Conventional Commits type（`feat:` / `fix:` / `refactor:` / `docs:` / `perf:` / `test:` / `style:` / `chore:` 等）
- **Subject**（What）：繁體中文描述，結尾附 `(#NNN)`
- **Body**（Why）：說明「為什麼」需要這個變更——問題的背景、動機、與變更前行為的對比。不要重複 diff 已能看到的內容
- **Footer**：中間 commit 使用 `Refs #NNN`，最終 commit 使用 `Closes #NNN`
- Subject、Body、Footer 之間各隔一行空行
- 若有「額外修正（既有問題）」，以獨立 commit 提交

---

### Phase 0: 初始化與重入偵測

0. **記錄開始時間**

   ```bash
   START_TIME=$(date +%s)
   ORIGINAL_BRANCH=$(git branch --show-current)
   ```

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
   | 有 branch + spec，但無 OpenSpec change | 讀取 Issue comments 取得釐清結果 → Phase 1 步驟 5（Spec 審查） |
   | 有 branch + spec + OpenSpec change（tasks 未完成）| Phase 2 步驟 12（apply） |
   | 有 branch + spec + OpenSpec change（tasks 全完成）| Phase 2 步驟 13（verify） |
   | 已有 Draft PR | 回報「Issue #NNN 已有 Draft PR，中止」 |

   **重入時讀取釐清結果**：解析 Issue comments，找出先前由本 Skill 留下的「自動處理中止」留言，以及後續 assignee 的回覆，作為 spec 更新的輸入。

   顯示：「Issue #NNN: <title>，接續點：<phase/step>」

---

### Phase 1: 需求分析與品質把關

4. **建立 feature branch（關聯 Issue）**

   從 **dev** 分支建立，並透過 `gh issue develop` 將分支關聯至 Issue（使 PR 自動出現在 Issue 的 Development 區塊）：
   ```bash
   git checkout dev && git pull
   gh issue develop $ARGUMENTS --base dev --name feature/NNN-kebab-name --checkout
   ```

   若 branch 已存在（重入情境），`gh issue develop` 會失敗，改為直接 checkout：
   ```bash
   git checkout feature/NNN-kebab-name
   ```

5. **閱讀相關原始需求規格**

   根據 CLAUDE.md §規格文件 的檔案對應關係，讀取 `spec-ag-opus45/` 中對應的規格文件。涉及跨模組時一併閱讀 `00-系統總覽.md`。

6. **把關點 0：Issue 健康度檢核**

   根據前面步驟取得的 Issue 內容、原始需求規格與現有程式碼，檢核以下五項：

   1. **問題是否仍存在？** — 檢查 dev 分支最新程式碼與 commit 歷史，確認問題未被其他 PR 修復
   2. **需求是否明確？** — Issue 描述是否完整，有無模糊或缺漏的需求定義
   3. **影響範圍預估** — 涉及哪些檔案與模組，是否跨模組
   4. **是否適合 autopilot？** — 需求邊界清晰、不涉及架構大改、影響範圍可控
   5. **前置作業** — 有無相依 Issue 未完成，或與其他進行中的工作衝突

   | 結論 | 後續動作 |
   |------|---------|
   | ✅ 通過 | 繼續至步驟 7（撰寫 SA spec） |
   | ❌ 不通過 | 執行「中止流程」，處理階段標為「Issue 健康度檢核」 |

7. **撰寫 SA spec**

   寫入 `sa/spec/NNN-xxx/spec.md`。
   - 若為首次執行：根據 Issue body + 原始需求規格撰寫
   - 若為重入：根據 Issue comments 中的釐清結果更新既有 spec

   Spec 內容須包含：業務背景、規格書依據、現狀分析、修正規格、影響範圍、測試規格。

8. **把關點 1：Spec 自審**

   **審查定位**：純文件品質審查，確保 spec.md 忠實且完整地反映 Issue 需求，不涉及程式碼層面（程式碼交給 Step 9 Explore）。

   **參照來源**：
   - Issue 原始需求：Issue body + comments 中的補充說明
   - Step 7 規定的 spec 章節：業務背景、規格書依據、現狀分析、修正規格、影響範圍、測試規格

   **四項檢查標準**：

   | # | 檢查項目 | 檢查方法 | 不通過範例 |
   |---|---------|---------|-----------|
   | 1 | **需求覆蓋度** | 逐條比對 Issue 需求點，確認 spec 每項都有對應的修正規格 | Issue 提了三個修正點，spec 只寫了兩個 |
   | 2 | **無過度需求** | 確認 spec 的修正規格沒有超出 Issue 要求的範圍 | Issue 只要修 filter，spec 卻順便重構整個查詢模組 |
   | 3 | **章節完整性** | 確認 Step 7 要求的六個章節皆有實質內容（非空或佔位文字） | 「測試規格」章節只寫「待補」 |
   | 4 | **內部一致性** | 修正規格、影響範圍、測試規格三者之間邏輯自洽 | 修正規格改了 A 和 B，但影響範圍只列了 A |

   **審查結果分流**：

   | 審查結果 | 處理方式 |
   |---------|---------|
   | **全數通過** | 繼續至步驟 9 |
   | **可自行修正**（缺漏或不一致處有明確的正確答案，如：漏列影響範圍、測試規格不完整） | 直接修正 spec.md，修正後繼續至步驟 9 |
   | **需要釐清**（Issue 需求本身模糊、存在多種合理解讀、或需求覆蓋度無法自行判定） | 執行「中止流程」（見下方） |

9. **把關點 2：Explore**

   以 `/opsx:explore` 的思維模式，深入探索 spec 與現有程式碼的交互：
   - 讀取相關的現有程式碼（Controller、Service、Entity、前端元件等）
   - 確認影響範圍是否完整
   - 發現隱藏的邊界情況或技術風險
   - 確認與現有設計模式的一致性

   **通過**（無隱藏問題）→ 繼續至 Phase 2
   **不通過**（發現需要釐清的問題）→ 執行「中止流程」（見下方）

---

### Phase 2: 實作與驗證

10. **OpenSpec propose**

    從 SA spec + Issue 內容推導 change name（kebab-case + NNN 編號後綴，如 `filter-options-null-023`）。

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `opsx:propose`，參數為以下描述：
    > 「<從 SA spec 整理的 change 描述，含 Issue 編號、變更內容、影響範圍>」
    > Change name 為 `<change-name>`。
    > SA spec 位於 `sa/spec/NNN-xxx/spec.md`。

    Agent 完成後，讀取回傳結果確認 artifacts 已建立，**立即繼續步驟 11**。

11. **Git Commit（需求分析產物）**

    將 SA spec 與 OpenSpec propose 產物提交，固定需求分析階段的產出。依「Commit Message Convention」提交。**立即繼續步驟 12**。

12. **OpenSpec apply**

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `opsx:apply`，參數為 change name `<change-name>`。
    > 遵循 TDD 流程（Red → Green → Refactor）實作所有 tasks。
    > 後端必須撰寫測試（單元 + 整合），前端不撰寫測試。

    Agent 完成後，讀取回傳結果確認所有 tasks 已完成，**立即繼續步驟 13**。

13. **OpenSpec verify**

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `opsx:verify`，參數為 change name `<change-name>`。
    > 驗證三個維度：Completeness、Correctness、Coherence。
    > 回傳驗證報告。

    若回傳結果包含 CRITICAL issues → 在主流程中修復，再次用 Agent 執行 verify，直到全部通過。
    通過後**立即繼續步驟 14**。

14. **Git Commit（實作產物）**

    將 apply 實作的所有程式碼變更提交，與後續審查修正分開。依「Commit Message Convention」提交。**立即繼續 Phase 3**。

---

### Phase 3: 品質審查

15. **Code Review（平行 subagent）**

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
    | **不需討論**：修正方式明確、風險低、不涉及架構決策（如：缺少 try-catch、缺少 console.warn、空 catch block） | 直接修正，與主要變更合併 commit |
    | **可直接修正**：雖涉及較大變更，但確認 (1) 不影響 `sa/spec/NNN-xxx/spec.md` 定義的需求規格，且 (2) 無其他 GH Issue 列管 | 直接修正，依「Commit Message Convention」以**獨立 commit** 提交，並列入 PR body「額外修正」區塊 |
    | **需要討論**：修正會改變 SA spec 定義的需求規格、需求不明確、或影響範圍無法自行判定 | 在 GH Issue 上留言通知 assignees 與 author，格式見下方 |

    **既有問題分流判定流程**：

    對每一項「既有程式碼問題」，依序執行：

    1. **Issue 列管檢查**（「Issue 留言去重檢查」共用子程序）— 已有 Issue 追蹤的項目直接跳過，不做任何處理
    2. **SA Spec 影響度判定** — 讀取 `sa/spec/NNN-xxx/spec.md`，比對該問題的修正是否會改變 spec 定義的需求規格（含業務邏輯、API 契約、資料模型等）
    3. 分流：
       - 修正方式明確且風險低 → 歸入「不需討論」
       - 不影響 spec 定義的需求規格 → 歸入「可直接修正」，在本次 PR 中以獨立 commit 修復
       - 影響 spec 定義的需求規格、需求不明確、或影響範圍無法自行判定 → 歸入「需要討論」，走下方留言流程

    **既有問題需討論時的留言流程**：

    對每一項「需要討論」的問題，先執行「Issue 留言去重檢查」（見上方共用子程序），僅將未被追蹤的項目納入留言。

    留言格式：

    ```bash
    gh issue comment $ARGUMENTS --body "$(cat <<'EOF'
    ## 🔍 審查發現：既有程式碼問題

    在處理本 Issue 時，Code Review 發現以下既有問題，建議另開 Issue 追蹤：

    ### [SEVERITY] 問題標題
    - **位置**：`檔案路徑:行號`
    - **問題**：具體描述
    - **建議**：修正方向

    ---

    > 以下問題已有 Issue 追蹤，不再重複列出：#XX, #YY
    > _(此行僅在有被過濾項目時顯示)_

    @ASSIGNEE @AUTHOR 以上為既有問題（非本次變更引入），建議評估是否需要處理。

    > 🤖 Generated with Claude Code
    EOF
    )"
    ```

16. **Code Simplify**

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `simplify`。
    > 審查本次變更的所有程式碼，參照 `sa/spec/NNN-xxx/spec.md` 與 OpenSpec change 目錄作為需求規格。

    Agent 完成後，讀取回傳結果。若有修正建議，在主流程中處理。
    **立即繼續步驟 17**。

17. **Git Commit（審查修正）**

    將 Code Review 與 Code Simplify 的修正提交。依「Commit Message Convention」提交。若無任何審查修正，跳過此 commit。**立即繼續 Phase 4**。

---

### Phase 4: E2E 測試與收尾

18. **E2E 測試**

    1. 撰寫 `sa/spec/NNN-xxx/e2e.md`（E2E 測試腳本）
    2. 啟動後端與前端開發伺服器（使用 Bash tool 的 `run_in_background: true`），等待就緒後執行測試
    3. 將測試結果記錄回 `e2e.md`

    **測試方式**（依可用工具選擇）：
    - 若有 Chrome DevTools MCP → 使用瀏覽器自動化執行 UI 測試
    - 若無 → 透過 API 直接呼叫 + 原始碼確認驗證，並在 `e2e.md` 註明驗證方式

19. **OpenSpec archive**

    使用 **Agent tool**（general-purpose）執行：
    > 使用 Skill tool 調用 `opsx:archive`，參數為 change name `<change-name>`。
    > 歸檔變更並同步 delta specs 至 main specs。
    > 遇到確認提示時一律選擇「同步並歸檔」。

    Agent 完成後，讀取回傳結果確認歸檔完成，**立即繼續步驟 20**。

20. **Git Commit（最終提交）**

    將剩餘變更（E2E 測試、OpenSpec 歸檔等）提交。依「Commit Message Convention」提交，Footer 使用 `Closes #NNN`。

21. **開 Draft PR**

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

    顯示 PR URL。

22. **清場**

    關閉流程中啟動的所有資源：
    1. 以 `pkill` 終止步驟 18 啟動的後端（`bootRun`）與前端（`vite`）dev server
    2. 若有 Chrome DevTools MCP 開啟的瀏覽器實例，一併關閉
    3. **等待背景任務通知到達**：`pkill` 後會收到 `run_in_background` 的 task-notification（status=failed），這是主動終止的預期行為。**必須在 skill 流程內收到並確認這些通知**，不可在通知到達前就結束流程，否則通知會漏到 skill 結束後，造成使用者困惑。
    4. 切回原始 branch：`git checkout $ORIGINAL_BRANCH`

23. **完成回報**

    計算並顯示總執行時間：
    ```bash
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    MINUTES=$((ELAPSED / 60))
    SECONDS=$((ELAPSED % 60))
    ```

    顯示：「Issue #NNN 流程完成（branch: `feature/NNN-kebab-name`），總執行時間：M 分 S 秒」，流程結束。

---

## Issue 留言去重檢查（共用子程序）

在留言至 GH Issue 之前，對每一項問題逐項執行以下去重檢查：

### 搜尋策略

由 LLM 根據每項問題的內容，自行決定最有效的搜尋策略：
- 自行判斷需要幾輪搜尋、使用哪些關鍵字，確保充分覆蓋不同表述方式（中英文、同義詞、相關元件名稱等）
- 使用 `gh issue list --search "<查詢>" --json number,title,body --limit 10` 搜尋 open issues
- 由 LLM 語意比對搜尋結果的 title 與 body，判斷是否已有 Issue 追蹤相同問題
- 判斷標準：「該既有 Issue 明確描述了相同的問題，或涵蓋此問題的上層 Issue」即為匹配

### 分流處理

| 情境 | 處理方式 |
|------|---------|
| **所有項目皆已追蹤** | 不留言，僅在流程日誌中記錄「已追蹤於 #XX, #YY」 |
| **部分已追蹤** | 僅留言未追蹤項目，底部附註「其餘問題已追蹤於 #XX, #YY」 |
| **無匹配** | 正常留言（所有項目） |

---

## 中止流程

在把關點 0、1 或 2 不通過時：

1. 將發現的問題整理為結構化留言
2. 對每項問題執行「Issue 留言去重檢查」（見上方共用子程序）。若所有問題皆已追蹤，跳過留言，直接向使用者回報對應 Issue 編號，然後執行步驟 4（清場）
3. 在 GH Issue 上留言並 tag assignees（僅包含未被追蹤的項目）

```bash
gh issue comment $ARGUMENTS --body "$(cat <<'EOF'
## 🤖 自動處理中止：需要討論

**處理階段**：[Issue 健康度檢核 / Spec 審查 / Explore 探索]

以下問題需要釐清後才能繼續：

1. [具體問題描述]
2. [具體問題描述]

---

> 以下問題已有 Issue 追蹤，不再重複列出：#XX, #YY
> _(此行僅在有被過濾項目時顯示)_

@ASSIGNEE 請確認上述問題。確認後可重新執行 `/noah:gh-issue-autopilot $ARGUMENTS` 接續處理。

> 🤖 Generated with Claude Code
EOF
)"
```

4. 向使用者回報中止原因與 Issue comment 連結

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
