#!/bin/bash
# Install Manager's helper and extension files. Safe to run again to update.
# 安装 Manager 的本机助手和插件文件。可以重复运行，用来更新。
set -euo pipefail

HOST_NAME="com.songxiaofeng.managerhtml"
EXT_ID="jpencbldoocakpdbgolffgemckpimnph"
HERE="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="$HOME/Library/Application Support/Manager HTML"
APP="$SUPPORT/ManagerHelper.app"
EXT_DIR="$HOME/Applications/Manager HTML/extension"

say() { printf '%s\n' "$@"; }

if [ "$(uname)" != "Darwin" ]; then
  say "This only works on macOS. / 只支持 macOS。"
  exit 1
fi

say "== 1/4 Preparing the helper / 准备本机助手"
if [ -d "$HERE/helper/ManagerHelper.app" ]; then
  SRC_APP="$HERE/helper/ManagerHelper.app"                         # from a release zip / 来自发布的压缩包
elif command -v swiftc >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; then
  bash "$HERE/helper/build.sh" >/dev/null                           # from source / 从源码编译
  SRC_APP="$HERE/helper/build/ManagerHelper.app"
else
  say ""
  say "No ready-made helper in this folder, and no Swift compiler to build one."
  say "这个文件夹里没有现成的本机助手，也没有可以编译它的 Swift 编译器。"
  say ""
  say "Easiest fix: download the release zip (not the source code) from"
  say "最简单的办法：从下面的地址下载发布版压缩包（不是源代码）："
  say "  https://github.com/songxiaofeng1981/html-manager/releases/latest"
  say "Developers can also install the Xcode Command Line Tools: xcode-select --install"
  say "开发者也可以安装 Xcode 命令行工具：xcode-select --install"
  exit 1
fi

say "== 2/4 Installing the helper / 安装本机助手"
mkdir -p "$SUPPORT"
rm -rf "$APP"
ditto "$SRC_APP" "$APP"
# A downloaded zip marks files as "from the internet"; clear that so Chrome can start the helper,
# then sign it on this Mac (ad-hoc) so macOS can remember the folder permissions you give it.
# 下载的压缩包会把文件标记为“来自互联网”；去掉标记，Chrome 才能启动助手；再在本机签名，macOS 才能记住你给它的文件夹权限。
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --sign - --identifier com.songxiaofeng.managerhtml.helper "$APP" >/dev/null 2>&1
cp "$HERE/uninstall.sh" "$SUPPORT/uninstall.sh"
cp "$HERE/selftest.sh" "$SUPPORT/selftest.sh"
say "   $APP"
# Trial versions (1.3–1.4) used this name. Your folder settings (settings.json) are kept.
# 试用版（1.3–1.4）用的是这个名字。资料库位置设置（settings.json）会保留。
if [ -d "$SUPPORT/Manager本机助手.app" ]; then
  rm -rf "$SUPPORT/Manager本机助手.app"
  say "   Removed the trial helper / 已删除试用版助手"
fi

say "== 3/4 Copying the extension / 复制插件文件"
mkdir -p "$EXT_DIR"
rsync -a --delete --exclude '.DS_Store' "$HERE/extension/" "$EXT_DIR/"
xattr -dr com.apple.quarantine "$EXT_DIR" 2>/dev/null || true
say "   $EXT_DIR"
# The trial version was loaded from this folder. Update it in place so Chrome keeps the same extension:
# you only need to click reload.
# 试用版从这个文件夹加载。原地更新它，Chrome 里还是同一个插件，只需点刷新。
OLD_EXT="$HOME/Applications/Manager HTML/扩展"
UPGRADE=0
if [ -f "$OLD_EXT/manifest.json" ]; then
  rsync -a --delete --exclude '.DS_Store' "$HERE/extension/" "$OLD_EXT/"
  xattr -dr com.apple.quarantine "$OLD_EXT" 2>/dev/null || true
  UPGRADE=1
  say "   Updated the trial extension folder too / 同时更新了试用版的插件文件夹: $OLD_EXT"
fi

say "== 4/4 Registering the helper with your browsers / 向浏览器登记本机助手"
manifest() {
  cat <<JSON
{
  "name": "$HOST_NAME",
  "description": "Manager helper: reads and files the HTML documents in your library",
  "path": "$APP/Contents/MacOS/manager-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
JSON
}
AS="$HOME/Library/Application Support"
registered=0
for browser in "Google/Chrome" "Google/Chrome Beta" "Google/Chrome Dev" "Google/Chrome Canary" "Chromium" \
               "Microsoft Edge" "BraveSoftware/Brave-Browser" "Vivaldi" "Arc/User Data"; do
  if [ -d "$AS/$browser" ] || { [ "$browser" = "Google/Chrome" ] && [ $registered -eq 0 ]; }; then
    mkdir -p "$AS/$browser/NativeMessagingHosts"
    manifest > "$AS/$browser/NativeMessagingHosts/$HOST_NAME.json"
    say "   $browser"
    registered=$((registered + 1))
  fi
done

if [ $UPGRADE -eq 1 ]; then
  say ""
  say "Done! You had the trial version. In chrome://extensions, click the reload icon (↻) on the Manager card."
  say "完成！你装过试用版。在 chrome://extensions 里点 Manager 卡片上的刷新图标（↻）即可。"
  open -a "Google Chrome" "chrome://extensions" >/dev/null 2>&1 || true
  exit 0
fi

printf '%s' "$EXT_DIR" | pbcopy 2>/dev/null || true
say ""
say "Done! One last step in Chrome / 完成！最后在 Chrome 里做一步："
say "  1. Open chrome://extensions and turn on Developer mode (top right)."
say "     打开 chrome://extensions，打开右上角的“开发者模式”。"
say "  2. Click \"Load unpacked\". In the window that opens, press ⌘⇧G, then ⌘V, then Return, then click Select."
say "     The folder path is already copied for you:"
say "     点“加载已解压的扩展程序”。在弹出的窗口里按 ⌘⇧G，再按 ⌘V，回车，然后点“选择”。"
say "     文件夹路径已经帮你复制好了："
say "       $EXT_DIR"
say "  3. Click the puzzle icon in the toolbar and pin Manager."
say "     点工具栏的拼图图标，把 Manager 固定到工具栏。"
say ""
say "Updating? Click the reload icon on the Manager card in chrome://extensions instead."
say "如果是更新：在 chrome://extensions 里点 Manager 卡片上的刷新图标即可。"
say ""
say "You can now delete the folder you downloaded. / 现在可以删掉下载的这个文件夹了。"
open -a "Google Chrome" "chrome://extensions" >/dev/null 2>&1 || true
