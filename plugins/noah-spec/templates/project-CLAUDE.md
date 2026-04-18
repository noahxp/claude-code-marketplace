# CLAUDE.md — 本專案之 Spec-Driven Development 紀律

> 本檔為 `noah-spec` plugin 提供之專案樣板。複製至專案根後，依需求調整。

---

## 本專案採 Capability-Grained Spec

本專案以 **canonical spec** 描述系統能力，作為跨對話、跨協作者之行為契約唯一事實來源。

---

## 目錄與格式約定

```
<project-root>/
├── CLAUDE.md
└── specs/
    └── <capability>/
        └── spec.md
```

- **Capability 粒度**：一個資料夾一個能力（如 `authentication`、`payment-processing`、`user-profile`）
- **命名**：kebab-case，名詞性，描述能力本質而非技術實作
- **體例**：Requirement（RFC 2119 語氣：MUST / SHALL / SHOULD）+ Scenario（GIVEN / WHEN / THEN）
- **單檔上限參考**：500 行，超過建議拆分 capability

---

## 三段式工作流外框

```
┌──────────────────────────────────────────────┐
│ Phase 1: Plan Mode（Claude Code 原生）         │
│   規劃、對齊、產 plan.md                      │
└──────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────┐
│ Phase 2: Superpowers Workflow                 │
│   由 Claude 依任務性質，自選適用 skill         │
│   （feature / bug / refactor / spike ...）     │
│   本 template 不列舉、不指定                   │
└──────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────┐
│ Phase 3: /noah-spec:writing-spec              │
│   行為變更完成且驗證通過後                     │
│   凝練為 canonical spec                        │
└──────────────────────────────────────────────┘
```

**設計要旨**：

- **Phase 2 已知存在，但刻意不列 skill 清單**：交付 Superpowers 之情境觸發機制，由 Claude 依任務性質自行挑選（debugging、brainstorming、write-plan、execute-plan、verification-before-completion 等皆在其內）
- **三段皆非強制**：typo 修正可跳過 Phase 1/2；重構無行為變更可跳過 Phase 3
- **中段不綁工具**：未使用 Superpowers 之協作者亦可採本紀律，Phase 2 替換為任何習慣之開發流程皆可

---

## Phase 3 觸發條件

呼叫 `/noah-spec:writing-spec` 之時機（觸發條件，非流程位置）：

- 一組可**獨立驗證**之行為變更已完成
- 測試已綠燈、驗證通過
- 即將 commit 之前（或於功能 commit 之後補記 spec）

**不觸發**之情境：

- Bug 修復無行為變更（原 spec 已涵蓋）
- 純重構（行為未變）
- 探索性 spike（行為未收斂）

---

## 與 git 之分工

| 責任 | 承擔者 |
|---|---|
| 系統**做什麼**（capability 行為定義） | `specs/<capability>/spec.md` |
| 本次變更**為何做**（動機與背景） | git commit message |
| 本次變更**怎麼做**（實作細節） | 程式碼本身 + commit diff |

---

## 預設鐵則（複製後依專案調整）

以下為樣板提供之預設約定，非 spec 規範本身。請依專案語言、團隊習慣、技術棧增刪。

- **註解與文件**：繁體中文
- **開發方式**：TDD 紅綠重構
- **Commit 格式**：Conventional Commits（type/scope 英文，description 繁中）
- **檔案寫作**：專業用語，不帶口語或角色語氣

---

## Bootstrap 指引

複製本樣板至專案根 `CLAUDE.md` 後，需調整：

1. **專案名稱與定位**：於檔首補上一段專案簡介
2. **初始 capability 清單**（可選）：若已知核心能力邊界，於此條列
3. **專案特有之鐵則**：在「預設鐵則」下增刪專案特有規範（如框架、語言版本、目錄分層）

`specs/` 目錄首次可留空，首次呼叫 `/noah-spec:writing-spec` 時自動建立對應 capability 子資料夾與 spec.md。
