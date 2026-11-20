#!/usr/bin/env bash
# 把本地仓库推到 GitHub。
#
# 用法：
#   scripts/push_to_github.sh <owner/repo>              # 用已登录的 gh（先 gh auth login）
#   scripts/push_to_github.sh <owner/repo> <TOKEN>       # 用 PAT（需 repo 权限）
#
# 例：scripts/push_to_github.sh yourname/netcove
set -euo pipefail

REPO="${1:-}"
TOKEN="${2:-}"
if [[ -z "$REPO" ]]; then
  echo "用法: scripts/push_to_github.sh <owner/repo> [TOKEN]" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

# 私钥绝不入库
if git ls-files | grep -q '\.key$'; then
  echo "!! 检测到 .key 文件被跟踪，已中止" >&2
  exit 1
fi

if [[ -n "$TOKEN" ]]; then
  echo "==> 用 token 创建仓库并推送"
  curl -sS -X POST https://api.github.com/user/repos \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"${REPO##*/}\",\"private\":true,\"description\":\"NetCove — local/cloud media player (no paywall)\"}" \
    | head -c 200; echo
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://x-access-token:${TOKEN}@github.com/${REPO}.git"
else
  echo "==> 用已登录的 gh CLI"
  gh repo create "$REPO" --private --source=. --remote=origin --push && exit 0
fi

git push -u origin HEAD:main
echo "==> 完成: https://github.com/$REPO"
