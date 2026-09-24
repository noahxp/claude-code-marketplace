# Claude Code Marketplace

Noah 的個人 Claude Code Plugin Marketplace。

## 可用 Plugins

| Plugin | 說明 | 版本 |
|--------|------|------|
| [noah:ai-perf-record](./plugins/noah/skills/ai-perf-record) | 透過 Chrome DevTools 自動填寫 AI 效率提升紀錄表單 | 2.4.0 |
| [noah-tools:visual-preview](./plugins/noah-tools/skills/visual-preview) | 瀏覽器即時預覽：啟動本地 HTTP server 監看目錄並自動渲染最新 HTML，支援點擊選取互動 | 1.3.0 |
| [noah-tools:code-review-tribunal](./plugins/noah-tools/skills/code-review-tribunal) | 三方仲裁式 code review：Claude Code、codex cli、agy cli 各自評審後互讀辯論三回合，Claude Code 依共識度仲裁產出最終定稿；含語意失敗 health check、NEW-CRITICAL 隔離、cli fail-fast；target 支援 PR / 路徑 / commit ref / git range / multi-ref / 自由文字 | 1.4.0 |
| [noah-tools:pr-merge-message-draft](./plugins/noah-tools/skills/pr-merge-message-draft) | 為 PR 擬定 merge 用的 Commit Message（標題）與 Extended Description（內文）：以最終 diff 為事實依據，PR 描述／commit／review 討論僅作待驗證主張，未驗證的 why 於草稿逐句標註；格式固定依循 OSS／業界最佳實踐（Conventional Commits、標題 50/72、內文 72 欄換行、單一 trailer 區塊），英文 type/scope + 繁中，只摘「為何改 + 主要影響」、不照抄 PR description；標題保留 `(#N)`、由 commit 作者推導 `Co-authored-by`；target 支援 PR 編號 / URL / 當前分支 / commit ref；僅輸出文字供確認後定稿 | 1.7.0 |
| [noah-tools:codex-delegate](./plugins/noah-tools/skills/codex-delegate) | 把一件事委派給 codex cli 在唯讀沙箱執行，Claude Code 覆核其產出後接手：一句指令以獨立 ` -- ` token 機械切分為「給 codex 的任務」與「給 Claude Code 的後處理指示」，後者絕不進入 codex prompt；含可疑切分偵測、四段輸出契約與語意 health check；覆核要求逐點標註採信／存疑／引用不符／未驗證並抽驗 [file:line] | 1.6.0 |

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
