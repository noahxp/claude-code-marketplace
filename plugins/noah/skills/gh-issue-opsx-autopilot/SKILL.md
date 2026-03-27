---
name: gh-issue-opsx-autopilot
description: 從 GitHub Issue 一貫執行到 Draft PR（含 spec 撰寫、品質把關、實作、review、測試、收尾）
model: opus
allowed-tools: Bash(gh *:*), Bash(git *:*), Bash(mkdir *:*), Bash(gradle *:*), Bash(npm *:*), Bash(pkill *:*), Bash(date *:*), Read, Write, Edit, Grep, Glob, Agent, Skill, TodoWrite
---

# GH Issue Autopilot

從 GitHub Issue 自動執行完整開發流程到 Draft PR。含 spec 撰寫、雙重品質把關、實作、Code Review、測試與 PR 建立。

本 Skill 為通用自動化引擎，專案特定的命名慣例、分支策略、spec 格式、實作工作流、審查規則、測試方式、歸檔流程等，皆委派至 `[WORKFLOW]` 定義。`[WORKFLOW]` 指的是專案根目錄下的 `.autopilot-workflow.md`，該檔案定義了專案層級的客製化規則。本 Skill 在各步驟中會引用 `[WORKFLOW]` 的對應章節，若該章節未定義則使用預設行為。

**輸入**：`$ARGUMENTS` = GitHub Issue 編號（如 `100`）

---

## 執行流程

> **自動化規則**：本 Skill 為全自動流程，所有步驟必須連續執行直到完成或遇到把關點不通過。
> - 不得在步驟之間停下來等待使用者指示（除非把關點明確要求中止）
> - 調用其他 Skill 時，**必須透過 Agent tool（general-purpose）包裝**，確保完成後控制權回到本流程
> - 不得直接使用 Skill tool 調用其他 skill（Skill tool 會將控制權轉移至內層 skill，無法自動返回）

### Commit Message Convention

若 `[WORKFLOW]` `Commit Convention` 有定義，以 `[WORKFLOW]` 為準；未定義時使用以下預設格式：

> **預設格式**：

```bash
git add <相關檔案>
git commit -m "$(cat <<'EOF'
<type>: <繁體中文描述>

<Why — 說明變更動機與背景>
EOF
)"
```

- **type**：執行 `git diff --cached` 判斷變更內容，據此選擇適當的 Conventional Commits type（`feat:` / `fix:` / `refactor:` / `docs:` / `perf:` / `test:` / `style:` / `chore:` 等）
- **Subject**（What）：繁體中文描述
- **Body**（Why）：說明「為什麼」需要這個變更——問題的背景、動機、與變更前行為的對比。不要重複 diff 已能看到的內容
- Subject 與 Body 之間隔一行空行

---

### Phase 0: 初始化與重入偵測

0. **記錄開始時間**

   ```bash
   START_TIME=$(date +%s)
   ORIGINAL_BRANCH=$(git branch --show-current)
   ```

1. **讀取 `[WORKFLOW]` 並檢核必要章節**

   讀取專案根目錄下的 `.autopilot-workflow.md`。若檔案不存在，中止流程並回報「缺少 `.autopilot-workflow.md`，無法執行」。

   檔案存在時，檢核以下必要章節（以 `## 章節名稱` 標題判定）是否皆存在：

   `Naming`、`Branch Strategy`、`Spec Reference`、`Spec Authoring`、`Implementation`、`Review`、`Testing`、`Archive`

   若有缺少，中止流程並回報缺少的章節清單：「`[WORKFLOW]` 缺少必要章節：<章節列表>，無法執行」。

2. **讀取 GH Issue**

   ```bash
   gh issue view $ARGUMENTS --json title,body,assignees,labels,comments,author
   ```

   提取：title、body（需求內容）、assignees（用於 tag）、author（Issue 建立者，用於 tag）、comments（補充與定案）。

   **需求來源優先順序**：Issue body 為原始需求，comments 為補充與定案。若 body 與 comments 有衝突，以 comments 為準。

   若 `[WORKFLOW]` 定義了 `Issue 前置檢查`，於此執行。不通過則執行「中止流程」。

3. **推導命名**

   依 `[WORKFLOW]` `Naming` 推導分支名、spec 路徑等命名。

4. **偵測已有產物，判斷接續點**

   | 偵測條件 | 接續點 |
   |---------|--------|
   | 無 feature branch | 從頭開始（Phase 1） |
   | 已有 Draft PR | 回報「已有 Draft PR，中止」 |

   其他中間狀態依 `[WORKFLOW]` `Implementation` 的重入偵測補充判斷。

   **重入時讀取釐清結果**：解析 Issue comments，找出先前由本 Skill 留下的「自動處理中止」留言，以及後續 assignee 的回覆，作為 spec 更新的輸入。

   顯示：「Issue #$ARGUMENTS: <title>，接續點：<phase/step>」

---

### Phase 1: 需求分析與品質把關

5. **建立 feature branch（關聯 Issue）**

   依 `[WORKFLOW]` `Branch Strategy` 建立分支並關聯 Issue。若 branch 已存在（重入情境），直接 checkout。

6. **閱讀相關規格文件**

   依 `[WORKFLOW]` `Spec Reference` 的查找規則，讀取與本 Issue 相關的既有規格文件。涉及跨模組修改時，應交叉查閱相關模組的規格。

7. **把關點 0：Issue 健康度檢核（維度感知）**

   根據前面步驟取得的 Issue 內容、既有規格文件與現有程式碼，執行以下三個子步驟。

   **7a. 識別變更特徵**

   分析 Issue 實際涉及的變更特徵，標注適用的標籤（與 `gh-issue-triage` Step 3.1 相同，可複選）：

   | 變更特徵標籤 | 判定依據 |
   |-------------|---------|
   | `user-facing` | 涉及使用者可見的行為、UI、操作流程、權限變更 |
   | `data-model` | 涉及 Entity/Table/Schema 新增或修改、資料驗證規則、持久化邏輯 |
   | `interface` | 涉及 API 端點、CLI 參數、Public API、前後端互動介面的新增或變更 |
   | `stateful` | 涉及物件狀態轉移、工作流程、審批流程、排程、非同步處理 |

   不確定時預設適用（寧可多檢核，不可遺漏）。

   **7b. 決定適用維度**

   依變更特徵標籤決定適用維度（與 `gh-issue-triage` Step 3.2 相同）：

   | 維度 | 類型 | 適用規則 |
   |------|------|---------|
   | D1 需求釐清 | 恆適用 | — |
   | D2 使用者情境 | 條件適用 | 具有 `user-facing` 標籤時適用 |
   | D3 資料模型 | 條件適用 | 具有 `data-model` 標籤時適用 |
   | D4 介面契約 | 條件適用 | 具有 `interface` 標籤時適用 |
   | D5 狀態與流程 | 條件適用 | 具有 `stateful` 標籤時適用 |
   | D6 非功能需求 | 恆適用 | — |
   | D7 影響分析 | 恆適用 | — |
   | D8 可實作性驗證 | 恆適用 | — |

   產出 `APPLICABLE_DIMENSIONS` 清單，供 Step 8 與 Step 9 消費。

   **7c. 維度級健康度檢核**

   對每個適用維度，評估「能否進入 spec 撰寫」：

   - **D1 需求釐清**：Scope 可辨識？AC 可提煉？body/comments 無矛盾？充分到可轉 spec？
   - **D2 使用者情境**（若適用）：角色可識別？主要流程可描述？
   - **D3 資料模型**（若適用）：受影響 Entity 可識別？關聯清楚？
   - **D4 介面契約**（若適用）：介面端點/簽名可識別？輸入輸出可推導？
   - **D5 狀態與流程**（若適用）：狀態可列舉？轉移條件已定義？
   - **D6 非功能需求**：效能/安全/可用性是否有需事前考量的面向？
   - **D7 影響分析**：問題仍存在？影響範圍已識別？與既有功能無衝突？資料遷移需求已識別？向後相容已評估？
   - **D8 可實作性驗證**：技術可行？可拆分？可測試？適合 autopilot？無阻塞前置作業？

   | 結論 | 後續動作 |
   |------|---------|
   | ✅ 所有適用維度通過 | 攜帶 `APPLICABLE_DIMENSIONS` 繼續至步驟 8 |
   | ❌ 任一適用維度不通過 | 執行「中止流程」，處理階段標為「Issue 健康度檢核（維度分析）」，留言含維度摘要表 |

8. **撰寫 spec（維度補充）**

   分兩階段撰寫。

   **8a. 依 `[WORKFLOW]` 撰寫**

   依 `[WORKFLOW]` `Spec Authoring` 定義的產出路徑與必要章節撰寫 spec。
   - 若為首次執行：根據 Issue body + 既有規格文件撰寫
   - 若為重入：根據 Issue comments 中的釐清結果更新既有 spec
   - 若 `[WORKFLOW]` Spec Authoring 定義了條件章節，依其適用規則與 Step 7 的變更特徵標籤決定是否展開。不適用的條件章節標注「不適用：<原因>」一行

   **8b. 維度缺口補充**

   撰寫完畢後，對照 Step 7 的 `APPLICABLE_DIMENSIONS`，以語意評估 spec 是否已涵蓋各適用維度的關注點。對未被 `[WORKFLOW]` 章節涵蓋的維度，於 spec 末尾 `## 維度補充分析` 區塊下補充對應章節：

   | 維度 | 補充章節標題 | 必要子項 |
   |------|------------|---------|
   | D1 | 範圍界定與驗收條件 | Scope、Out of Scope、Acceptance Criteria |
   | D2 | 使用者情境 | 涉及角色、主要流程（Happy Path）、例外流程（Edge Cases）、權限模型 |
   | D3 | 資料模型變更 | Entity 設計（欄位/型別）、關聯關係、資料驗證規則、資料生命週期 |
   | D4 | 介面契約 | 介面定義（端點/簽名）、輸入輸出格式、錯誤處理、向後相容 |
   | D5 | 狀態與流程 | 狀態列舉、轉移條件、併發處理、回滾機制 |
   | D6 | 非功能需求 | 效能考量、安全性考量、可用性考量 |
   | D7 | 影響分析補充 | 資料遷移策略、向後相容評估 |
   | D8 | 實作規劃補充 | 工作單元拆分、依賴排序 |

   若 `[WORKFLOW]` 某章節已實質涵蓋該維度的所有子項，不重複補充。僅補充確實缺失的子項。

9. **把關點 1：Spec 自審**

   **審查定位**：純文件品質審查，確保 spec 忠實且完整地反映 Issue 需求，不涉及程式碼層面（程式碼交給 Step 10 Explore）。

   **參照來源**：
   - Issue 原始需求：Issue body + comments 中的補充說明
   - `[WORKFLOW]` `Spec Authoring` 定義的章節
   - Step 7 產出的 `APPLICABLE_DIMENSIONS`

   **五項檢查標準**：

   | # | 檢查項目 | 檢查方法 | 不通過範例 |
   |---|---------|---------|-----------|
   | 1 | **需求覆蓋度** | 逐條比對 Issue 需求點，確認 spec 每項都有對應的修正規格 | Issue 提了三個修正點，spec 只寫了兩個 |
   | 2 | **無過度需求** | 確認 spec 的修正規格沒有超出 Issue 要求的範圍 | Issue 只要修 filter，spec 卻順便重構整個查詢模組 |
   | 3 | **章節完整性** | 確認 `[WORKFLOW]` `Spec Authoring` 定義的章節與維度補充章節皆有實質內容（非空或佔位文字） | 「測試規格」章節只寫「待補」 |
   | 4 | **內部一致性** | 修正規格、影響範圍、測試規格三者之間邏輯自洽 | 修正規格改了 A 和 B，但影響範圍只列了 A |
   | 5 | **維度覆蓋度** | 比對 `APPLICABLE_DIMENSIONS`，確認 spec 全文（`[WORKFLOW]` 章節 + 補充章節合計）對每個適用維度皆有實質內容 | D4（介面契約）適用，但 spec 無任何 API 端點定義或 Request/Response 結構 |

   **審查結果分流**：

   | 審查結果 | 處理方式 |
   |---------|---------|
   | **全數通過** | 繼續至步驟 10 |
   | **可自行修正**（缺漏或不一致處有明確的正確答案，如：漏列影響範圍、維度章節不完整） | 直接修正 spec，修正後繼續至步驟 10 |
   | **需要釐清**（Issue 需求本身模糊、存在多種合理解讀、或需求覆蓋度無法自行判定） | 執行「中止流程」（見下方） |

10. **把關點 2：Explore（平行 subagent）**

    使用多個平行 subagent 深入探索 spec 與現有程式碼的交互：
    - 讀取相關的現有程式碼
    - 確認影響範圍是否完整
    - 發現隱藏的邊界情況或技術風險
    - 確認與現有設計模式的一致性

    涉及多模組時，應以平行 subagent 分別探索各模組，再彙整結果。

    **通過**（無隱藏問題）→ 繼續至 Phase 2
    **不通過**（發現需要釐清的問題）→ 執行「中止流程」（見下方）

---

### Phase 2: 實作與驗證

11. **依 `[WORKFLOW]` `Implementation` 逐步執行**

    依 `[WORKFLOW]` `Implementation` 定義的實作流程逐步執行。每個步驟須透過 **Agent tool（general-purpose）** 包裝執行，確保完成後控制權回到主流程。可獨立的步驟應以平行 subagent 同時執行。

    實作過程中遇到 CRITICAL issues 應在主流程中修復後繼續。

12. **Git Commit（實作產物）**

    依 `[WORKFLOW]` `Implementation` 定義的 commit 時間點提交。各 commit 點的內容由 `[WORKFLOW]` 定義，SKILL 負責在每個 commit 點執行「Commit Message Convention」。若 `[WORKFLOW]` 未定義 commit 時間點，則在實作完成後統一提交一次。

    `[WORKFLOW]` `Implementation` 內嵌的 `**Commit**` 標記為 commit 時間點指示，實際 commit 操作由本步驟統一執行。

    **立即繼續 Phase 3**。

---

### Phase 3: 品質審查

13. **Code Review（平行 subagent）**

    依 `[WORKFLOW]` `Review` 定義的審查工具，以平行 subagent 執行。

    **執行規則**：
    - **前景執行**：所有審查 agent 一律以前景（foreground）模式執行，確保每個審查結果都顯示在使用者畫面上。
    - **調用數量回報**：發送審查 agent 前，先向使用者回報「正在調用 N 個審查工具：<工具名稱列表>」；全部完成後，回報「N 個審查工具全部完成」並逐一摘要結果。

    審查結果分為兩類：

    **A. 本次變更引入的問題**：
    - 若有 CRITICAL/HIGH 發現 → 在主流程中修復，再重新審查直到通過

    **B. 既有程式碼的預存問題**（reviewer 掃描相關檔案時順帶發現的非本次變更引入的問題）：

    依 `[WORKFLOW]` `Review` 定義的分流規則處理。若 `[WORKFLOW]` 未定義，則記錄發現並在 PR body 中列出，不做額外處理。

    **既有問題需討論時的留言流程**：

    對每一項「需要討論」的問題，先執行「Issue 留言去重檢查」（見下方共用子程序），僅將未被追蹤的項目納入留言。

    留言格式依 `[WORKFLOW]` `Review` 定義。若 `[WORKFLOW]` 未定義，使用以下預設格式：

    > **預設格式**：

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

14. **Code Simplify**

    使用 **Agent tool**（general-purpose）執行 `[WORKFLOW]` `Code Simplify` 定義的工具與參照來源。

    Agent 完成後，讀取回傳結果。若有修正建議，在主流程中處理。
    **立即繼續步驟 15**。

15. **Git Commit（審查修正）**

    將 Code Review 與 Code Simplify 的修正提交。依「Commit Message Convention」提交。若無任何審查修正，跳過此 commit。**立即繼續 Phase 4**。

---

### Phase 4: 測試與收尾

16. **測試**

    依 `[WORKFLOW]` `Testing` 定義的測試方式、環境準備與記錄格式執行。

    測試完成後記錄結果。若有失敗項目，修正後重新測試直到通過。

17. **Archive**

    使用 **Agent tool**（general-purpose）執行 `[WORKFLOW]` `Archive` 定義的歸檔流程。

18. **Git Commit（最終提交）**

    將剩餘變更提交。依「Commit Message Convention」提交。最終 commit 的 footer 依 `[WORKFLOW]` `Commit Convention` 定義。

19. **開 Draft PR**

    依 `[WORKFLOW]` `PR Template` 建立 Draft PR。若 `[WORKFLOW]` 未定義，使用以下預設格式：

    > **預設格式**：

    ```bash
    gh pr create --draft \
      --title "<type>: <繁體中文描述>" \
      --body "$(cat <<'EOF'
    ## 功能概述

    <一句話說明>

    ## 變更內容

    - <主要改動列點>

    ## 額外修正（既有問題）

    > 若無額外修正則移除此區塊

    - <審查時發現的既有問題修正列點>

    ## 測試結果

    - 測試通過狀況摘要

    EOF
    )"
    ```

    顯示 PR URL。

20. **Cleanup**

    依 `[WORKFLOW]` `Cleanup` 定義的指令，關閉流程中啟動的所有資源。

    資源關閉後：
    1. **等待背景任務通知到達**：終止背景程序後會收到 `run_in_background` 的 task-notification（status=failed），這是主動終止的預期行為。**必須在 skill 流程內收到並確認這些通知**，不可在通知到達前就結束流程，否則通知會漏到 skill 結束後，造成使用者困惑。
    2. 切回原始 branch：`git checkout $ORIGINAL_BRANCH`

21. **完成回報**

    計算並顯示總執行時間：
    ```bash
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    MINUTES=$((ELAPSED / 60))
    SECONDS=$((ELAPSED % 60))
    ```

    顯示：「Issue #$ARGUMENTS 流程完成（branch: `<feature-branch>`），總執行時間：M 分 S 秒」，流程結束。

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
2. 對每項問題執行「Issue 留言去重檢查」（見上方共用子程序）。若所有問題皆已追蹤，跳過留言，直接向使用者回報對應 Issue 編號，然後執行主流程 Step 20（Cleanup）
3. 在 GH Issue 上留言並 tag assignees（僅包含未被追蹤的項目）

留言格式依 `[WORKFLOW]` `Halt Comment Template` 定義。若 `[WORKFLOW]` 未定義，使用以下預設格式：

> **預設格式**：

```bash
gh issue comment $ARGUMENTS --body "$(cat <<'EOF'
## 🤖 自動處理中止：需要討論

**處理階段**：[把關點名稱]

以下問題需要釐清後才能繼續：

1. [具體問題描述]
2. [具體問題描述]

---

> 以下問題已有 Issue 追蹤，不再重複列出：#XX, #YY
> _(此行僅在有被過濾項目時顯示)_

@ASSIGNEE 請確認上述問題。確認後可重新執行 `/noah:gh-issue-opsx-autopilot $ARGUMENTS` 接續處理。

> 🤖 Generated with Claude Code
EOF
)"
```

4. 向使用者回報中止原因與 Issue comment 連結

中止流程結束後，執行主流程 Step 20（Cleanup）。

---

## 進度回報格式

可由 `[WORKFLOW]` `Progress Format` 自訂 Phase 名稱與格式。預設格式：

每完成一個 Phase 時，回報進度：

```
## Issue #$ARGUMENTS: <title>

### 進度
- [x] Phase 0: 初始化
- [x] Phase 1: 需求分析與品質把關
- [ ] Phase 2: 實作與驗證（進行中）
- [ ] Phase 3: 品質審查
- [ ] Phase 4: 測試與收尾
```

---

## Guardrails

- 各步驟中可獨立執行的工作，應以平行 subagent 處理
- 專案特異的 Guardrails 由 `[WORKFLOW]` `Guardrails` 定義

---

Issue Number: $ARGUMENTS
