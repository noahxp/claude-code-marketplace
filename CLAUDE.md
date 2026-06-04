# CLAUDE.md — Claude Code Plugin Marketplace

## 專案性質

此為 **specification-only repository**，僅含 JSON metadata 與 Markdown skill 定義。
**禁止執行** `npm`、`pip`、`gradle`、`docker` 等建構或執行指令。

---

## 目錄結構

```
claude-code-marketplace/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace 註冊表（plugin 清單）
├── plugins/
│   └── <plugin-name>/            # 每個 plugin 一個目錄（kebab-case）
│       ├── .claude-plugin/
│       │   └── plugin.json       # Plugin metadata
│       └── skills/
│           └── <skill-name>/     # 每個 skill 一個目錄（kebab-case）
│               └── SKILL.md      # Skill 定義（YAML frontmatter + Markdown body）
├── CLAUDE.md
└── README.md
```

**重點**：`.claude-plugin/` 資料夾僅放 `plugin.json`（或根層級的 `marketplace.json`），skills 放在 plugin root 下的 `skills/` 目錄。

---

## 命名與路徑規則

| 項目 | 規則 | 範例 |
|------|------|------|
| Plugin 目錄名 | kebab-case（或專案代號） | `noah` |
| Skill 目錄名 | kebab-case | `gh-issue-opsx-autopilot`、`agent-design` |
| `marketplace.json` 的 `source` | 相對路徑 `./plugins/<name>` | `./plugins/noah` |
| Plugin name 一致性 | 目錄名 = `plugin.json` 的 `name` = `marketplace.json` 內的 `name` | 三處皆為 `noah` |

---

## 檔案格式模板

### marketplace.json（根層級 `.claude-plugin/`）

```jsonc
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "noah-marketplace",
  "description": "Noah's personal Claude Code plugin marketplace",
  "owner": { "name": "Noah" },
  "plugins": [
    {
      "name": "<plugin-name>",
      "description": "<一行描述>",
      "author": { "name": "Noah" },
      "source": "./plugins/<plugin-name>",
      "category": "Development",
      "version": "1.0.0",
      "tags": ["<tag1>", "<tag2>"]
    }
  ]
}
```

### plugin.json（`plugins/<name>/.claude-plugin/`）

```jsonc
{
  "name": "<plugin-name>",
  "description": "<一行描述>",
  "version": "1.0.0",
  "author": { "name": "Noah" }
}
```

### SKILL.md（`plugins/<name>/skills/<skill>/`）

```markdown
---
name: <skill-name>
description: <一行描述，供 /skill 選單顯示>
allowed-tools: <逗號分隔的工具清單>
---

（Markdown body：skill 的完整指令與流程定義）
```

---

## 新增 Plugin Checklist

1. **建立目錄結構**

   ```
   plugins/<plugin-name>/.claude-plugin/plugin.json
   plugins/<plugin-name>/skills/<skill-name>/SKILL.md
   ```

2. **撰寫 `plugin.json`**：填入 name、description、version、author

3. **撰寫 `SKILL.md`**：含 YAML frontmatter（name、description、allowed-tools）與 Markdown body

4. **註冊至 `marketplace.json`**：在 `plugins` 陣列新增一筆，確保 `source` 路徑正確

5. **驗證檢查**
   - [ ] Plugin 目錄名、`plugin.json` name、`marketplace.json` name 三者一致
   - [ ] `marketplace.json` 的 `source` 指向正確相對路徑
   - [ ] SKILL.md frontmatter 包含 name、description、allowed-tools
   - [ ] 所有 name 皆為 kebab-case

---

## 版號管理規則

當任何 plugin 內容變更需升版時，以下三處版號必須同步更新：

1. `plugins/<plugin-name>/.claude-plugin/plugin.json` 的 `version`
2. `.claude-plugin/marketplace.json` 對應 plugin 的 `version`
3. `README.md` 可用 Plugins 表格中對應 plugin 的版本欄位

三處版號必須一致，缺一不可。

---

## Git Commit Scope 慣例

遵循 Conventional Commits，scope 規則：

| 變更範圍 | scope | 範例 |
|----------|-------|------|
| 特定 plugin | plugin 名稱 | `feat: 新增 gh-issue-opsx-autopilot 流程` |
| marketplace.json 或跨 plugin | `marketplace` | `feat(marketplace): 新增 noah 插件註冊` |
| 專案層級設定 | 省略或自訂 | `chore: 更新 CLAUDE.md` |

---

## 參考文件

- [Claude Code Plugins 官方文件](https://docs.anthropic.com/en/docs/claude-code/plugins)
- [SKILL.md 格式說明](https://docs.anthropic.com/en/docs/claude-code/skills)
