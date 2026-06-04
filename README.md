# Claude Code Marketplace

Noah 的個人 Claude Code Plugin Marketplace。

## 可用 Plugins

| Plugin | 說明 | 版本 |
|--------|------|------|
| [noah:gh-issue-opsx-autopilot](./plugins/noah/skills/gh-issue-opsx-autopilot) | 從 GitHub Issue 一貫執行到 Draft PR（含八維度 spec 撰寫、品質把關、實作、review、測試、收尾） | 2.2.1 |
| [noah:gh-issue-scan](./plugins/noah/skills/gh-issue-scan) | 搜尋 open 且未指派的 GitHub Issue，分析並篩選出可直接交由 gh-issue-opsx-autopilot 處理的 Issue | 1.1.0 |
| [noah:gh-issue-triage](./plugins/noah/skills/gh-issue-triage) | 八維度分析 GitHub Issue，評估是否可直接執行 gh-issue-opsx-autopilot | 2.1.0 |
| [noah:gh-issue-e2e-test](./plugins/noah/skills/gh-issue-e2e-test) | 使用 Chrome DevTools 執行 E2E 測試，結果整理為 PR Comment 格式 | 1.1.0 |
| [noah:ai-perf-record](./plugins/noah/skills/ai-perf-record) | 透過 Chrome DevTools 自動填寫 AI 效率提升紀錄表單 | 2.4.0 |
| [noah:agent-design](./plugins/noah/skills/agent-design) | Agent 設計顧問：幫助 PM 判斷 Agent 類型、理解架構設計、產出需求規格 | 2.4.0 |
| [noah-tools:visual-preview](./plugins/noah-tools/skills/visual-preview) | 瀏覽器即時預覽：啟動本地 HTTP server 監看目錄並自動渲染最新 HTML，支援點擊選取互動 | 1.3.0 |
| [noah-tools:code-review-tribunal](./plugins/noah-tools/skills/code-review-tribunal) | 三方仲裁式 code review：Claude Code、codex cli、agy cli 各自評審後互讀辯論三回合，Claude Code 依共識度仲裁產出最終定稿；含語意失敗 health check、NEW-CRITICAL 隔離、cli fail-fast；target 支援 PR / 路徑 / commit ref / git range / multi-ref / 自由文字 | 1.4.0 |

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
