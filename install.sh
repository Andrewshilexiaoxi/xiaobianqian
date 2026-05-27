#!/bin/zsh
set -euo pipefail

TARGET="${1:-$HOME/.codex/skills/xiaobianqian}"
mkdir -p "$(dirname "$TARGET")"
rm -rf "$TARGET"
cp -R "$(cd "$(dirname "$0")" && pwd)" "$TARGET"
chmod +x "$TARGET/scripts/smallnote"
echo "已安装到 $TARGET"
echo "试试：$TARGET/scripts/smallnote add \"第一条小便签\""
