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

# Finder 自动化需要「自动化」权限，先快速探测一下，避免白等
if ! osascript -e 'tell application "Finder" to get name of startup disk' > /dev/null 2>&1; then
  echo "  ⚠︎ 没有「控制访达」的自动化权限，跳过窗口美化"
  echo "     （授权路径：系统设置 → 隐私与安全性 → 自动化 → 允许终端控制「访达」）"
  SKIP_STYLING=1
else
  SKIP_STYLING=0
fi

# Finder 自动化：成功则得到带背景和图标位置的窗口，失败/无权限则保持朴素样式
if [ "${SKIP_STYLING}" = "0" ]; then
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
( sleep 25; kill $OSA_PID 2>/dev/null ) &
WATCHDOG=$!
wait $OSA_PID 2>/dev/null || true
kill $WATCHDOG 2>/dev/null || true
fi

# 设置卷宗自定义图标标志（FinderInfo 32 字节里的 kHasCustomIcon = 0x0400）
# 注意：macOS 自带 Python 没有 os.setxattr，这里用 xattr 命令写十六进制值
if [ -f "$MOUNT_POINT/.VolumeIcon.icns" ]; then
  FI_HEX="00000000000000000400$(printf '0%.0s' {1..44})"
  if xattr -wx com.apple.FinderInfo "$FI_HEX" "$MOUNT_POINT" 2>/dev/null; then
    echo "  卷宗图标已设置"
  else
    echo "  （卷宗图标设置跳过）"
  fi
fi

sync
echo "▸ 卸载并压缩…"
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
rm -f "$DMG"

# 卷宗图标必须放在 Finder 美化「之后」补：Finder 打开卷时会吃掉 .VolumeIcon.icns。
# 所以这里再挂载一次（完全不经过 Finder），写入图标文件与 kHasCustomIcon 标志。
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  M2=$(hdiutil attach "$TMP_DMG" -nobrowse -readwrite | grep -o '/Volumes/.*' | head -1)
  if [ -n "${M2:-}" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$M2/.VolumeIcon.icns" 2>/dev/null || true
    # FinderInfo 32 字节：偏移 8 处的 0x0400 = kHasCustomIcon
    xattr -wx com.apple.FinderInfo "00000000000000000400$(printf '0%.0s' {1..44})" "$M2" 2>/dev/null || true
    sync
    if [ -f "$M2/.VolumeIcon.icns" ] && xattr "$M2" 2>/dev/null | grep -q FinderInfo; then
      echo "  卷宗图标已设置"
    else
      echo "  （卷宗图标设置跳过）"
    fi
    hdiutil detach "$M2" -quiet 2>/dev/null || hdiutil detach "$M2" -force -quiet 2>/dev/null || true
  fi
fi

hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" > /dev/null

rm -rf "$WORK"

echo
echo "✓ 安装包已生成：$DMG"
echo "  大小: $(du -h "$DMG" | cut -f1)"
echo "  校验: $(shasum -a 256 "$DMG" | awk '{print substr($1,1,16)}')…"
echo "  发布: gh release upload v$VERSION \"$DMG\" --repo vex67-cyber/iris-macos"
