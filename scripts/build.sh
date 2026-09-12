#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Grok CLI Usage Menu Bar"
BUNDLE_ID="com.local.grok-cli-usage-menu-bar"
VERSION="${VERSION:-0.1.0}"
GIT_COMMIT="${GIT_COMMIT:-$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)}"
GIT_REMOTE="${GIT_REMOTE:-$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)}"
GIT_COMMIT="${GIT_COMMIT:-unknown}"
GIT_REMOTE="${GIT_REMOTE:-https://github.com/diegocp01/grok_menu_bar.git}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/.build/release}"
FINAL_APP_DIR="$OUT_DIR/$APP_NAME.app"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/grok-cli-usage-menu-bar-build.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP_DIR="$STAGING_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY="$MACOS_DIR/GrokCLIUsageMenuBar"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$STAGING_ROOT/module-cache"

env CLANG_MODULE_CACHE_PATH="$STAGING_ROOT/module-cache" \
  clang "$ROOT_DIR/Sources/GrokCLIUsageMenuBar/main.m" \
  -I "$ROOT_DIR/Sources/GrokCLIUsageMenuBar" \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 \
  -fobjc-arc \
  -framework Cocoa \
  -framework ServiceManagement \
  -O2 \
  -o "$BINARY"

"$BINARY" --render-icon "$RESOURCES_DIR/GrokMenuBarIcon.png"
ditto --norsrc --noqtn "$ROOT_DIR/assets/grok-menu-bar-icon.svg" "$RESOURCES_DIR/GrokMenuBarIcon.svg"
ditto --norsrc --noqtn "$RESOURCES_DIR/GrokMenuBarIcon.png" "$RESOURCES_DIR/AppIcon.png"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>GrokCLIUsageMenuBar</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>GrokGitCommit</key>
  <string>$GIT_COMMIT</string>
  <key>GrokGitRemote</key>
  <string>$GIT_REMOTE</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --sign "${CODESIGN_IDENTITY:--}" --options runtime "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

mkdir -p "$OUT_DIR"
rm -rf "$FINAL_APP_DIR"
ditto --noqtn "$APP_DIR" "$FINAL_APP_DIR"
xattr -cr "$FINAL_APP_DIR" 2>/dev/null || true
codesign --force --sign "${CODESIGN_IDENTITY:--}" --options runtime "$FINAL_APP_DIR" >/dev/null
codesign --verify --deep --strict "$FINAL_APP_DIR"
echo "$FINAL_APP_DIR"
