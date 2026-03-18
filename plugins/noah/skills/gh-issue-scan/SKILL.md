---
name: gh-issue-scan
description: 搜尋 open 且未指派的 GitHub Issue，分析並篩選出可直接交由 /gh-issue-autopilot 處理的 Issue
allowed-tools: Bash(gh *:*), Bash(git *:*), Read, Grep, Glob, Agent
---

# GH Issue Scan

搜尋 open 且未指派的 GitHub Issue，深入分析每張 Issue 與現有程式碼、規格文件的關係，篩選出可直接交由 `/noah:gh-issue-autopilot` 處理的 Issue，列出原因與建議處理順序。

**輸入**：`$ARGUMENTS`（選填，可傳入額外篩選條件如 label）

**限制**：本 Skill 僅做分析與建議，不得自行執行任何 Issue 的開發流程。

---

## 執行流程

### 步驟 1：了解專案脈絡

1. 讀取專案根目錄的 `CLAUDE.md`，掌握專案結構、開發規範與目錄慣例
2. 讀取 `/noah:gh-issue-autopilot` 的 SKILL.md，掌握 autopilot 的能力範圍與把關條件（尤其「把關點 0：Issue 健康度檢核」的五項標準）

### 步驟 2：搜尋候選 Issue

```bash
gh issue list --state open --assignee "" --json number,title,body,labels,comments,author --limit 50
```

若結果為空，回報「目前無 open 且未指派的 Issue」，流程結束。

### 步驟 3：深入分析每張 Issue

對每張候選 Issue，以平行 subagent 進行以下分析：

1. **需求明確度**：Issue body + comments 是否完整描述需求，有無模糊或缺漏
2. **需求來源優先順序**：Issue body 為原始需求，comments 為補充與定案。若有衝突以 comments 為準
3. **現有產物偵測**：檢查是否已有對應的 feature branch、SA spec、OpenSpec change、Draft PR
4. **程式碼影響範圍**：
   - 切至 `dev` branch，根據 Issue 描述定位相關程式碼
   - 讀取相關的 SA spec（`sa/spec/`）與 OpenSpec specs（`openspec/specs/`）
   - 評估變更範圍是否可控（跨模組程度、架構影響）
5. **前置相依**：是否有相依 Issue 未完成，或與其他進行中的工作衝突
6. **autopilot 適合度**：根據 `gh-issue-autopilot` 把關點 0 的五項標準綜合判定

### 步驟 4：分類與排序

將每張 Issue 歸入以下分類：

| 分類 | 定義 |
|------|------|
| ✅ **可直接處理** | 需求明確、影響範圍可控、無前置相依、適合 autopilot |
| ⚠️ **需簡單釐清** | 大致可行，但有 1-2 個小問題需確認後即可處理 |
| ❌ **不適合** | 需求模糊、架構大改、有未解決的相依、或需深度討論 |

### 步驟 5：輸出報告

依建議處理順序（優先度由高到低）列出結果，格式如下：

```
## GH Issue Scan 結果

### ✅ 可直接處理

#### 1. #NNN — Issue 標題
- **可直接處理原因**：<具體說明為何符合 autopilot 條件>
- **影響範圍**：<涉及的模組/檔案概述>
- **預估複雜度**：低 / 中
- **執行指令**：`/noah:gh-issue-autopilot NNN`

#### 2. #NNN — Issue 標題
...

### ⚠️ 需簡單釐清

#### #NNN — Issue 標題
- **待釐清事項**：<具體問題>
- **釐清後可執行**：是

### ❌ 不適合自動處理

#### #NNN — Issue 標題
- **原因**：<為何不適合>
```

---

## 排序優先度依據

1. 無前置相依的 Issue 優先
2. 影響範圍小（單一模組）的 Issue 優先
3. 已有部分產物（如已有 spec 但中止過）的 Issue 優先（重入成本低）
4. Bug fix 優先於 feature（穩定性優先）
