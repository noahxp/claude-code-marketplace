---
name: writing-spec
description: Use when a set of independently verifiable behavior changes has just completed and verification has passed, and the canonical specs at specs/<capability>/spec.md need to reflect reality before commit. Not for bug fixes that do not change specified behavior, nor for exploratory spikes.
allowed-tools: Bash(git *:*), Bash(find *:*), Bash(ls *:*), Read, Write, Edit, Grep, Glob, TodoWrite
model: sonnet
---

# Writing Spec

## Overview

將「已完成且已驗證」之行為變更，凝練為 `specs/<capability>/spec.md` canonical spec。本 skill 為**後置記錄**，非前置預言：spec 反映實作真相，而非預設未來。

**核心原則**：Spec 是實作之後置記錄，非前置預言。實作未完、測試未綠，不得寫 spec。

---

## When to Use

**使用時機**：
- 一組可獨立驗證之行為變更已完成
- 測試通過、驗證完畢
- 即將 commit 之前（或於功能 commit 之後補記）

**不適用情境（逃生艙）**：
- **Bug 修復無行為變更**：既有 spec 已涵蓋該行為，修 bug 僅還原，不需改 spec
- **探索性 spike**：尚未收斂為穩定行為，不落 spec
- **純重構**：行為未變，不需改 spec
- **樣式/格式調整**：不影響 capability 行為
- **實作或驗證未完成**：停。先完成，再回來

---

## Preconditions Check

呼叫本 skill 前，必先通過：

1. `git status` / `git diff` 顯示有實質變更（或最近已 commit）
2. 測試已綠燈（執行過測試指令、或 `verification-before-completion` 已通過）
3. 專案根有 `specs/` 目錄（若無則本 skill 會建立）

**若任一未達**：回報缺失，中止執行。

---

## Execution Flow

### Phase 1：情境蒐集

```bash
# 取得實作脈絡
git diff HEAD~1..HEAD --stat
git diff HEAD~1..HEAD
git log --oneline -n 10

# 列現行 canonical specs
find specs -name "spec.md" 2>/dev/null
```

同時掃描當前對話 context：
- 若有 plan.md（Superpowers 產出）→ 讀之
- 若對話中有 brainstorm 結論 → 萃取需求要點

**Ground Truth 順位**：git diff > 已通過之測試 > 對話結論 > 記憶

**Bash 受限時之降級路徑**：若沙盒或權限配置禁用 Bash，改以 Read / Glob 取得等效證據：

| 受限指令 | 降級替代 |
|---|---|
| `git diff HEAD~1..HEAD` | Read 最近變動之實作檔 + Read 既有 spec，比對推導差異 |
| `git log` | Read `.git/COMMIT_EDITMSG` 或最近 commit 之訊息檔 |
| `find specs -name "spec.md"` | Glob `specs/**/spec.md` |

**注意**：降級僅為取得等效證據，**不放寬紀律**。Ground Truth 順位不變；若連降級路徑亦無可用證據，依 Red Flags 中止執行。

### Phase 2：Capability 判定

依變更影響之能力邊界，判定對應 `<capability>`：

- **新能力**：建立 `specs/<new-capability>/spec.md`（首建，用完整模板）
- **既有能力**：準備 delta 合併至 `specs/<capability>/spec.md`
- **跨多能力**：列出所有受影響 capability，逐一處理

**命名規則**：kebab-case，名詞性，描述能力本質（如 `authentication`、`payment-processing`、`user-profile`），非技術實作（避免 `auth-service`、`login-api`）。

### Phase 3：Delta 心算（不落檔）

此為推理鷹架，僅於心中整理，不寫入檔案：

```
## ADDED Requirements
<新增之行為需求>

## MODIFIED Requirements
<既有條目之修改，附前後對照>

## REMOVED Requirements
<廢棄條目及其廢棄理由>
```

### Phase 4：Canonical 合併

**首建場景**（新 capability）：使用 Write 產出完整 spec.md：

```markdown
# <Capability Name> Specification

## Purpose

<1-3 句說明此能力為何存在、解決誰的什麼問題>

## Requirements

### Requirement: <需求名稱>

The system MUST/SHALL <行為描述>.

#### Scenario: <情境名稱>

- **GIVEN** <前提條件>
- **WHEN** <觸發動作>
- **THEN** <預期結果>
- **AND** <附加結果>

#### Scenario: <另一情境>

- **GIVEN** ...
- **WHEN** ...
- **THEN** ...

### Requirement: <下一需求>
...
```

**既有場景**（更新）：使用 Edit 就地修改 `specs/<capability>/spec.md`：

- **ADDED**：Edit 追加新 Requirement 段落（通常置於檔尾最後一條 Requirement 之後）
- **MODIFIED**：Edit 定點取代既有條目（含其 Scenario），前後對照後再行修改
- **REMOVED**：Edit 刪除整段 Requirement，**連同其前導或尾隨空行一併清除**，避免殘留雙空行。**若刪除區塊位於檔尾**，確保檔案以單一換行結束（不留空白行）

**硬性契約**：**非目標 Requirement 段落為逐字保留契約，一字不可動**。Edit 僅得作用於本次 delta 所涉之 Requirement；順序、標點、空行、大小寫、語法皆須保持原貌。此為硬規則，不容彈性。

**禁止**：整檔重寫（會沖掉無關變動之歷史），必須逐條 Edit。

### Phase 5：自我驗證

逐項核對：

- [ ] 每條 Requirement 可獨立測試（非抽象空話）
- [ ] 每條 Requirement 至少一個 Scenario（GIVEN/WHEN/THEN 完備）
- [ ] 使用 RFC 2119 語氣（MUST / SHALL / SHOULD / MAY）
- [ ] 無未定義術語
- [ ] 無互相矛盾之條款
- [ ] 涵蓋 happy path 與主要 error path
- [ ] 與專案 CLAUDE.md / 現行 spec 無衝突
- [ ] spec 內容源於 git diff 之真實變更，非憑空想像
- [ ] **Requirement 之行為範圍不逾測試已斷言之範圍**（實作細節如加密演算法、內部資料結構，除非測試有斷言其外部可觀察行為，否則不入 spec）

### Phase 6：收尾提示

完成後回報主公：

1. 列出本次受影響之 spec 檔案清單
2. **呈現差異**：
   - 若 Bash 可用且檔案已 tracked，**主動執行** `git diff specs/` 並附其結果
   - 若為**首建（untracked）新檔**，`git diff` 無輸出；改以 `git diff --no-index /dev/null <file>` 或 `git add -N <file> && git diff` 產出可視差異
   - 若 **Bash 全拒**，以 Edit 前後對照片段呈現等效差異（old/new 格式），明示「Bash 受限，以 Edit 變更等效呈現」
3. 建議 commit message：
   - 若併入功能 commit：`<type>(<scope>): <描述>`（依原功能 type）
   - 若獨立 spec commit：`docs(spec): <capability> — <簡述變動>`

**不**自動執行 commit——交付主公判斷。

---

## Spec Authoring Rules

### 語氣

| 關鍵字 | 語義 | 使用時機 |
|---|---|---|
| MUST / SHALL | 強制必須 | 核心不可違反之行為 |
| SHOULD | 建議應該 | 推薦行為，例外情境可不遵循 |
| MAY | 可選 | 允許但非必要 |
| MUST NOT | 強制禁止 | 不可發生之行為 |

### Scenario 格式

- GIVEN：**前提條件**（系統狀態、使用者身份、資料前置）
- WHEN：**觸發動作**（使用者操作、事件發生、時間流逝）
- THEN：**預期結果**（可觀察、可驗證）
- AND：**附加子句**（接於 GIVEN/WHEN/THEN 之後）

### 分檔規則

- **一個 capability 一個資料夾**：`specs/authentication/spec.md`
- **單檔超過 500 行**：考慮拆分 capability，或重新審視能力邊界
- **不使用跨檔 include**：每個 spec.md 為自足單元

---

## Delta Reasoning Cheatsheet

```
變更類型           對應操作                       檔案動作
─────────────────  ─────────────────────────────  ────────────
新增行為            ADDED Requirement             Edit 追加
修改既有行為        MODIFIED Requirement          Edit 取代
廢棄行為            REMOVED Requirement           Edit 刪除
新能力              全新 spec.md                  Write 首建
```

---

## Red Flags（遇之即止）

以下徵兆代表**不應繼續**，停下，回報主公：

- ❌ 實作尚未完成（有未處理之 TODO、測試未寫）
- ❌ 測試未綠燈（red light 時不寫 spec）
- ❌ Spec 內容憑記憶或推測，非源於 git diff
- ❌ 整檔重寫既有 spec.md（應逐條 Edit）
- ❌ 改動非本次 delta 所涉之既有 Requirement（逐字保留契約）
- ❌ Requirement 逾越測試已斷言之範圍（由實作細節外推出測試未驗之行為）
- ❌ 單一 spec.md 已超 500 行仍持續膨脹（應拆 capability）
- ❌ Capability 命名用技術實作（如 `auth-service`）而非能力本質

---

## Common Mistakes

| 錯誤 | 修正 |
|---|---|
| 於實作途中呼叫本 skill | 等實作完成、驗證通過再呼叫 |
| 以 Write 整檔覆蓋既有 spec | 改用 Edit 逐條修改，保留無關歷史 |
| Requirement 寫成實作細節 | 提升至行為層次（「系統必須支援 X」而非「用 JWT 儲 token」） |
| Requirement 逾越測試斷言範圍 | 僅涵蓋測試已驗之行為；實作細節除非測試斷言其外部可觀察行為，否則不入 spec |
| Scenario 只有 GIVEN/THEN | 補上 WHEN（必有觸發動作） |
| 單一 spec.md 混多 capability | 拆分為獨立資料夾 |
| REMOVED 後 spec 留雙空行 | 刪除 Requirement 時連同前導或尾隨空行一併清除 |
| 自動執行 commit | 停手，交付主公判斷 |

---

## Scope Boundary

本 skill **僅負責 spec 撰寫**，不做：

- ❌ 呼叫其他 skill（避免排擠既有 Superpowers 生態）
- ❌ 自動執行 commit
- ❌ 修改實作程式碼
- ❌ 跑測試、跑 lint

控制權於 Phase 6 交還主公。
