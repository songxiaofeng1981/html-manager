#!/bin/bash
# Remove the helper, its settings and the installed extension files.
# Your library (Manager_Files, the .manager index, thumbnails) and your HTML files are not touched.
# 删除本机助手、它的设置和已安装的插件文件。不会动你的资料库（Manager_Files、.manager 索引、缩略图）和 HTML 文件。
HOST_NAME="com.songxiaofeng.managerhtml"
AS="$HOME/Library/Application Support"
for browser in "Google/Chrome" "Google/Chrome Beta" "Google/Chrome Dev" "Google/Chrome Canary" "Chromium" \
               "Microsoft Edge" "BraveSoftware/Brave-Browser" "Vivaldi" "Arc/User Data"; do
  rm -f "$AS/$browser/NativeMessagingHosts/$HOST_NAME.json"
done
rm -rf "$AS/Manager HTML" "$HOME/Applications/Manager HTML"
echo "Removed the helper and extension files. Your documents are untouched. / 已删除本机助手和插件文件，你的资料没有改动。"
echo "Last step: remove Manager in chrome://extensions. / 最后一步：在 chrome://extensions 里移除 Manager。"
