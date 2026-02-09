# Claude Code Marketplace

Noah 的個人 Claude Code Plugin Marketplace。

## 可用 Plugins

| Plugin | 說明 | 版本 |
|--------|------|------|
| [pr-review](./plugins/pr-review) | 分析 GitHub PR diff 並透過 GitHub API 發布 inline review comments | 1.0.0 |

## 安裝方式

1. 在 Claude Code 中新增此 marketplace：
   ```
   /plugin marketplace add <owner>/<repo>
   ```

2. 安裝 plugin：
   ```
   /plugin install <plugin-name>@<marketplace-name>
   ```

或直接執行 `/plugin` 開啟互動式 plugin 管理介面進行瀏覽與安裝。

## 資料夾結構

```
claude-code-marketplace/
├── .claude-plugin/
│   └── marketplace.json        # Marketplace 索引
└── plugins/
    └── <plugin-name>/
        ├── .claude-plugin/
        │   └── plugin.json     # Plugin 元資料
        └── skills/
            └── <skill-name>/
                └── SKILL.md    # Skill 定義
```

## 新增 Plugin

1. 在 `plugins/` 下建立新目錄
2. 建立 `.claude-plugin/plugin.json` 描述 plugin 元資料
3. 在 `skills/` 下建立 skill 目錄與 `SKILL.md`
4. 於根目錄 `.claude-plugin/marketplace.json` 的 `plugins` 陣列中註冊新 plugin
