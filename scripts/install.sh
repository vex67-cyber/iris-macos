#!/bin/bash
#
# 把「明目」安装到 /Applications
#
# 用法：  ./scripts/install.sh [--open]
#   --open   安装完成后立即启动
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/dist/明目.app"
TARGET="/Applications/明目.app"

if [ ! -d "$SOURCE" ]; then
  echo "✗ 还没构建，先运行：./scripts/build-app.sh"
  exit 1
fi

if pgrep -f "$TARGET/Contents/MacOS/Iris" > /dev/null 2>&1; then
  echo "▸ 先退出正在运行的「明目」…"
  osascript -e 'quit app "明目"' 2>/dev/null || pkill -f "$TARGET/Contents/MacOS/Iris" || true
  sleep 1
fi

echo "▸ 安装到 $TARGET …"
rm -rf "$TARGET"
cp -R "$SOURCE" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

# 重新签名：拷贝后路径变了，签名里的路径信息会失配
codesign --force --sign - "$TARGET" 2>/dev/null || true

echo "✓ 已安装：$TARGET"

if [ "${1:-}" = "--open" ]; then
  echo "▸ 启动…"
  open "$TARGET"
fi
