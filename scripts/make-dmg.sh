#!/bin/bash
#
# 把 dist/明目.app 打包成可分发的 DMG
#   - 内含「明目.app」+「应用程序」快捷方式（拖拽安装）
#   - 品牌风格的窗口背景与图标位置（需要 Finder 自动化权限；拿不到就退回朴素版）
#
# 用法：./scripts/make-dmg.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="明目"
APP="$ROOT/dist/$APP_NAME.app"

if [ ! -d "$APP" ]; then
  echo "✗ 还没有构建 App，先运行：./scripts/build-app.sh"
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
VOLUME_NAME="$APP_NAME $VERSION"
DMG="$ROOT/dist/Mingmu-$VERSION.dmg"

echo "▸ 准备安装包内容…"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▸ 生成窗口背景图…"
mkdir -p "$STAGE/.background"
swift "$ROOT/scripts/make-dmg-background.swift" "$STAGE/.background" > /dev/null

TMP_DMG="$WORK/temp.dmg"
echo "▸ 创建临时镜像…"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -ov -format UDRW "$TMP_DMG" > /dev/null

echo "▸ 挂载并美化窗口…"
MOUNT_POINT=$(hdiutil attach "$TMP_DMG" -nobrowse -readwrite | grep -o '/Volumes/.*' | head -1)
sleep 2

# Finder 自动化：成功则得到带背景和图标位置的窗口，失败/无权限则保持朴素样式
osascript > /dev/null 2>&1 <<APPLESCRIPT &
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {120, 120, 780, 540}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 120
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {170, 200}
        set position of item "Applications" of container window to {490, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
OSA_PID=$!
( sleep 15; kill $OSA_PID 2>/dev/null ) &
WATCHDOG=$!
wait $OSA_PID 2>/dev/null || true
kill $WATCHDOG 2>/dev/null || true

sync
echo "▸ 卸载并压缩…"
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
rm -f "$DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" > /dev/null

rm -rf "$WORK"

echo
echo "✓ 安装包已生成：$DMG"
echo "  大小: $(du -h "$DMG" | cut -f1)"
echo "  校验: $(shasum -a 256 "$DMG" | awk '{print substr($1,1,16)}')…"
echo "  发布: gh release upload v$VERSION \"$DMG\" --repo vex67-cyber/iris-macos"
