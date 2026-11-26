#!/usr/bin/env bash
# Dev Council — 建立本次會診的工作目錄
# 輸出：stdout 印出 WORKDIR=<絕對路徑>
# 目錄內不預先建立任何檔案：brief.md 由 host 以 Write 新建（Write 覆寫既有檔前須先 Read）

set -euo pipefail

# mktemp 由 OS 保證唯一性與 0700 權限
WORKDIR=$(mktemp -d "/tmp/dev-council-XXXXXX")
printf 'WORKDIR=%s\n' "$WORKDIR" || { rm -rf "$WORKDIR"; exit 1; }
