#!/bin/bash
# Check the helper without Chrome: where the library is, how many documents it finds, and what is waiting to import.
# 不经过 Chrome 检查本机助手：资料库在哪里、找得到多少资料、有多少待收录。
#   bash selftest.sh                                      # your settings / 按你的设置
#   bash selftest.sh --root /path [--inbox /path]         # other folders / 其他文件夹
HELPER="$HOME/Library/Application Support/Manager HTML/ManagerHelper.app/Contents/MacOS/manager-host"
if [ ! -x "$HELPER" ]; then
  echo "The helper is not installed yet. Run: bash install.sh / 还没安装本机助手，请先运行：bash install.sh"
  exit 1
fi
echo "If macOS asks whether Terminal may access a folder, click Allow. / 如果 macOS 询问终端能否访问某个文件夹，请点“允许”。"
"$HELPER" --selftest "$@"
