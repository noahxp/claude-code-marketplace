# dev-council

向使用者提問前的三方會診。main agent 原本要問你的問題，先由 Claude subagent、codex cli、agy cli 各自獨立回答再互評；證據足以定案的直接照做，只把需要你仲裁的帶回來。

本文件說明安裝後要做的設定。會診流程、回傳碼與安全設計見 [SKILL.md](./SKILL.md)。

## 前置需求

| 工具 | 用途 | 安裝與登入 |
|---|---|---|
| codex cli | 參與者之一 | `npm i -g @openai/codex`，再執行 `codex login` |
| jq | 解析 codex 的 JSON 輸出 | `brew install jq` |
| agy cli（Antigravity CLI） | 參與者之一 | 依 Antigravity CLI 官方指引安裝後執行 `agy install`；登入時執行 `agy`，依畫面完成後離開 |

少了某個 cli，會診照樣進行，該方記為缺席。兩個都沒有時只剩 Claude subagent，不足兩方，會診中止，main agent 直接問你原本的問題。

## 安裝與更新

1. 安裝 plugin（需 `noah-tools` 1.10.0 以上）：

   ```
   /plugin install noah-tools@noah-marketplace
   ```

   已安裝舊版時，執行 `/plugin` 從管理介面更新 `noah-tools`。

2. 重啟 Claude Code，讓新版載入。
3. 確認可用：手動呼叫一次，看三方是否都通過檢查。

   ```
   /noah-tools:dev-council [問題]
   ```

## 觸發設定（CLAUDE.md）

### 為什麼需要

frontmatter 沒有設 `disable-model-invocation`，所以 Claude 可以依 description 自動呼叫這個 skill，但這樣不可靠：

- Claude 通常拿使用者交代的任務去比對 skill 清單，而這個 skill 的觸發時機是任務進行到一半、Claude 自己準備提問的那一刻。
- AskUserQuestion 工具本身的說明會直接引導 Claude 去問你，沒有提到要先會診。
- SKILL.md 的〈何時啟動〉要等 skill 被呼叫後才會載入，無法讓 Claude 在提問前想到要呼叫它。

CLAUDE.md 每一輪都在 context 裡，作為觸發點比 description 穩定。

### 要加的內容

把下面這段加進 CLAUDE.md：

```markdown
## Asking the User

- Before asking the user a question or for a decision (via AskUserQuestion or in plain text),
  invoke the `noah-tools:dev-council` skill first.
- Ask directly, without the council, for: authorization to act (commit, push, delete, publish),
  information only the user has (accounts, credentials, outside context), actions the user
  must perform, questions raised by dev-council itself (login wait, arbitration), and
  questions asked by a skill whose purpose is to interview the user, such as
  `mattpocock-skills:grilling` (also run by `grill-me` and `grill-with-docs`).
```

第二條列出不必會診的情況：

- **授權、只有你知道的資訊、需要你親手做的事**：會診也答不了。在 CLAUDE.md 先排除，這類問題就不會白白載入 SKILL.md。
- **dev-council 自己的提問**：〈等待登入〉與〈仲裁〉這兩步本身會用 AskUserQuestion。不排除的話，第一條規則會要求這些提問也先會診。
- **訪談型 skill 的提問**：`mattpocock-skills:grilling` 這類 skill 的用意是讓你自己釐清想法、逐題做決定，由會診代答就失去意義。`grill-me` 與 `grill-with-docs` 都是呼叫 `grilling` 來提問，排除 `grilling` 就涵蓋三者。

### 放在哪個 CLAUDE.md

| 位置 | 效果 | 適合 |
|---|---|---|
| `~/.claude/CLAUDE.md` | 所有專案的提問都先會診 | 多數專案都裝得了 codex 與 agy，也願意每次提問多等幾分鐘 |
| 專案根目錄的 `CLAUDE.md` | 只在該專案會診 | 只想在特定專案使用，或要控制額度 |

想停用自動會診時，刪掉這段即可；手動呼叫 `/noah-tools:dev-council` 不受影響。

## 成本

每次會診約 3 到 10 分鐘：codex 與 agy 各呼叫 2 到 3 次，Claude subagent 1 到 2 次。每次呼叫都會消耗 codex 與 agy 的額度。

## 選用設定（環境變數）

| 變數 | 預設 | 用途 |
|---|---|---|
| `DEV_COUNCIL_CODEX_MODEL` | codex 自己的預設 | 指定 codex 使用的 model |
| `DEV_COUNCIL_AGY_MODEL` | agy 自己的預設 | 指定 agy 使用的 model |
| `DEV_COUNCIL_AGY_PRINT_TIMEOUT` | `600s` | agy 每一輪的時間上限，格式如 `90s`、`5m`、`1h` |
| `DEV_COUNCIL_AGY_PREFLIGHT_TIMEOUT` | `90s` | agy 啟動檢查的時間上限，格式同上 |
| `DEV_COUNCIL_COOLDOWN_WAIT` | `90` | codex 啟動即被終止（rc=137）時，重試前等待的秒數 |

可在 shell profile 以 `export` 設定，或寫進 `~/.claude/settings.json` 的 `env` 欄位。

## 安全提醒

- codex 從 repo 根目錄啟動，會把 repo 內的 `AGENTS.md` 當指令載入。會診對象是不可信的 repo 時，先讀過它的 `AGENTS.md`。
- Claude subagent 的唯讀是靠 agent 定義的指示維持，不是沙箱。

完整說明見 SKILL.md〈安全性〉。

## 疑難排解

| 狀況 | 可能原因與處理 |
|---|---|
| 該先會診時 Claude 直接提問 | 確認 CLAUDE.md 有上面那段，且 `noah-tools` 已更新到 1.10.0 以上並重啟 |
| 登入已失效，卻被當成一般失敗（rc=2）而非暫停等待登入 | 登入的判定字樣（`scripts/lib/common.sh` 的 `AUTH_RE`）已用登出時的實測訊息，以及 codex 0.172.0、agy 1.5.18 內建的 token 過期訊息驗證；cli 改版可能改變訊息。額度上限（`QUOTA_RE`）的訊息還沒實測。把腳本印出的 stderr 原文補進字樣與 `tests/dev-council/` 的測試 |
| 啟動檢查卡住約 1 分鐘 | agy 未登入時會先等 60 秒的 OAuth 登入才判定失敗，屬正常。之後會提示你在另一個視窗執行 `agy` 登入 |
| agy 每輪都沒有輸出（rc=2） | agy 執行了唯讀允許清單外的指令而被拒，或回覆超過時間上限被截斷。後者可調高 `DEV_COUNCIL_AGY_PRINT_TIMEOUT` |
