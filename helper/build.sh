#!/bin/bash
# Build the helper app (needs Xcode Command Line Tools: xcode-select --install)
# 编译本机助手（需要 Xcode 命令行工具：xcode-select --install）
#   bash helper/build.sh            # this Mac's architecture / 只编译本机架构
#   bash helper/build.sh universal  # Apple silicon + Intel, used for releases / 发布用的通用版本
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/build/ManagerHelper.app"
SRC="$HERE/ManagerHost.swift"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"
cp -R "$HERE/zh-Hans.lproj" "$APP/Contents/Resources/"
BIN="$APP/Contents/MacOS/manager-host"
if [ "${1:-}" = "universal" ]; then
  swiftc -O -target arm64-apple-macos13 "$SRC" -o "$HERE/build/helper-arm64"
  swiftc -O -target x86_64-apple-macos13 "$SRC" -o "$HERE/build/helper-x86_64"
  lipo -create "$HERE/build/helper-arm64" "$HERE/build/helper-x86_64" -output "$BIN"
  rm -f "$HERE/build/helper-arm64" "$HERE/build/helper-x86_64"
else
  swiftc -O -target "$(uname -m)-apple-macos13" "$SRC" -o "$BIN"
fi
codesign --force --sign - --identifier com.songxiaofeng.managerhtml.helper "$APP"
echo "Built / 已编译: $APP"
