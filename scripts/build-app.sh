#!/bin/bash
#
# 明目（Iris）构建脚本
#   编译 → 生成图标 → 组装 .app Bundle → 临时签名
#
# 用法：  ./scripts/build-app.sh [debug|release]     （默认 release）
# 环境变量：IRIS_SDK 指定 SDK 路径（默认使用 26.5 SDK，见下）
#
set -euo pipefail

# 为什么固定用 26.5 SDK：
#  macOS 27 SDK 把 SwiftUI 的 @State 等改成了宏，而宏插件只随 Xcode 分发；
#  本机只有 Command Line Tools，因此改用仍以 property wrapper 实现 @State 的 26.5 SDK。
SDK="${IRIS_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [ ! -d "$SDK" ]; then
  SDK="$(xcrun --show-sdk-path)"
  echo "⚠︎  未找到 26.5 SDK，改用：${SDK}（若编译失败请安装 Xcode 或指定 IRIS_SDK）"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="明目"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

cd "$ROOT"

echo "▸ 编译（${CONFIG}，SDK: $(basename "$SDK")）…"
swift build -c "$CONFIG" --sdk "$SDK"
BIN_DIR="$(swift build -c "$CONFIG" --sdk "$SDK" --show-bin-path)"

echo "▸ 生成 App 图标…"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET_DIR" > /dev/null
mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET_DIR" -o "$ROOT/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "▸ 组装 App Bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Iris" "$APP/Contents/MacOS/Iris"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/Iris"

echo "▸ 代码签名（ad-hoc）…"
codesign --force --sign - "$APP" 2>/dev/null || {
  echo "⚠︎  签名失败（不影响本机使用，但开机自启动可能需要在系统设置里手动允许）"
}

echo
echo "✓ 构建完成：$APP"
echo "  安装到「应用程序」：  ./scripts/install.sh"
echo "  直接运行：            open \"$APP\""
