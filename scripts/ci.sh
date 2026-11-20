#!/usr/bin/env bash
# NetCove CI：静态自检 → 生成工程 → 编译 → 单测
# 需要 macOS + Xcode 15+，以及 xcodegen（brew install xcodegen）
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> 1/5 静态自检"
python3 tools/verify.py

echo "==> 1b/5 一致性审计"
python3 tools/audit.py

echo "==> 2/5 模块包校验"
python3 tools/verify_module.py examples/dist/tv.netcove.example.hello-1.0.0.rexmod --pub Config/dev-signing/module-signing.pub

echo "==> 3/5 调参矩阵一致性"
python3 tools/tuning_matrix.py generate >/dev/null && echo "matrix ok"

echo "==> 4/5 生成 Xcode 工程"
xcodegen generate

echo "==> 5/5 编译 + 单测（模拟器）"
xcodebuild test \
  -project NetCove.xcodeproj \
  -scheme NetCove \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify 2>/dev/null || true

echo "CI done."
