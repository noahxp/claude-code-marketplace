# Claude Code Marketplace

Noah 的個人 Claude Code Plugin Marketplace。

## 可用 Plugins

| Plugin | 說明 | 版本 |
|--------|------|------|
| [noah:ai-perf-record](./plugins/noah/skills/ai-perf-record) | 透過 Chrome DevTools 自動填寫 AI 效率提升紀錄表單 | 2.7.1 |
| [noah-tools:visual-preview](./plugins/noah-tools/skills/visual-preview) | 瀏覽器即時預覽：啟動本地 HTTP server 監看目錄並自動渲染最新 HTML，支援點擊選取互動 | 1.3.0 |
| [noah-tools:code-review-tribunal](./plugins/noah-tools/skills/code-review-tribunal) | 三方仲裁式 code review：Claude Code、codex cli、agy cli 各自評審後互讀辯論三回合，Claude Code 依共識度仲裁產出最終定稿；含語意失敗 health check、NEW-CRITICAL 隔離、cli fail-fast；target 支援 PR / 路徑 / commit ref / git range / multi-ref / 自由文字 | 1.7.1 |
| [noah-tools:pr-merge-message-draft](./plugins/noah-tools/skills/pr-merge-message-draft) | 為 PR 擬定 merge 用的 Commit Message（標題）與 Extended Description（內文）：以最終 diff 為事實依據，PR 描述／commit／review 討論與程式註解僅作待驗證主張，修正是否成立對照 base sha 判定、PR 已合併時先告知，未驗證的 why 於草稿逐句標註；格式先依專案文件規範（CONTRIBUTING／commitlint／CLAUDE.md），不從既有 git log 歸納，未規範處依 OSS／業界最佳實踐（Conventional Commits、標題 50/72、footer 與 git trailer 分段），內文不硬換行；預設英文 type/scope + 繁中，只摘「為何改 + 主要影響」、不照抄 PR description；只寫通過刪除檢驗的必要內容並濃縮（每件事只寫一次、只寫變化、影響寫成可觀察的結果，影響範圍以程式確認），導言預設一句；`!` 只標下游須跟著改的變更（含請求條件收緊），`BREAKING CHANGE` 逐項列出介面、變化與遷移方式，本服務的佈建與上線步驟不寫進 message；標題預設保留 `(#N)`，僅 squash merge 時由 commit 作者推導 `Co-authored-by`；target 支援當前 repo 的 PR 編號 / URL / 當前分支 / commit ref；僅輸出文字供確認後定稿 | 1.9.0 |
| [noah-tools:codex-delegate](./plugins/noah-tools/skills/codex-delegate) | 把一件事委派給 codex cli 在唯讀沙箱執行，Claude Code 覆核其產出後接手：一句指令以獨立 ` -- ` token 機械切分為「給 codex 的任務」與「給 Claude Code 的後處理指示」，後者絕不進入 codex prompt；含可疑切分偵測、四段輸出契約與語意 health check；覆核要求逐點標註採信／存疑／引用不符／未驗證並抽驗 [file:line] | 1.7.1 |
| [noah-tools:review-loop](./plugins/noah-tools/skills/review-loop) | 分支審查迴圈：以 `/code-review` xhigh 起手、medium 追到清零，再由獨立 subagent 判定是否從 xhigh 再審一輪（外圈至多 3 輪、每輪 medium 至多 3 次）；每項事實主張由唯讀 subagent 盲審複查，成立與誤報皆須附 `file:line` 證據，兩方不一致以測試裁定，修正前須紅燈；判定記入各 worktree 的審查記錄，跨審查與 `/clear` 略過已判定項目；需要討論的項目於修正前停下詢問，依答覆修正、記入 ADR 或另開 issue 後才續跑；收尾跑一次兩軸審查並同步設計紀錄 | 1.8.1 |

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
|-- .claude-plugin/
|   `-- marketplace.json        # Marketplace 索引
`-- plugins/
    `-- <plugin-name>/
        |-- .claude-plugin/
        |   `-- plugin.json     # Plugin 元資料
        |-- agents/             # 供 skill 派工的 subagent 定義（選用）
        `-- skills/
            `-- <skill-name>/
                `-- SKILL.md    # Skill 定義
```

## 新增 Plugin

1. 在 `plugins/` 下建立新目錄
2. 建立 `.claude-plugin/plugin.json` 描述 plugin 元資料
3. 在 `skills/` 下建立 skill 目錄與 `SKILL.md`
4. 於根目錄 `.claude-plugin/marketplace.json` 的 `plugins` 陣列中註冊新 plugin
