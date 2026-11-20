#!/usr/bin/env bash
# NetCove 出包：归档 → 导出 ipa
# 用法: scripts/release.sh <TEAM_ID>
set -euo pipefail

TEAM_ID="${1:-}"
if [[ -z "$TEAM_ID" ]]; then
  echo "用法: scripts/release.sh <TEAM_ID>" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

python3 tools/verify.py
xcodegen generate

xcodebuild -project NetCove.xcodeproj \
  -scheme NetCove \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/NetCove.xcarchive \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

xcodebuild -exportArchive \
  -archivePath build/NetCove.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist Config/ExportOptions.plist \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "ipa -> build/export/"
ls -lh build/export || true
