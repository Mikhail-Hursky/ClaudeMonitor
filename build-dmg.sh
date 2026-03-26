#!/bin/bash
set -e

APP_NAME="ClaudeMonitor"
BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"           # arm64 или x86_64
TARGET="${ARCH}-apple-macos12.0"
OUT_DIR="dist"

echo "▶ Compiling (${TARGET})..."
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/${BUNDLE}/Contents/MacOS"
mkdir -p "${OUT_DIR}/${BUNDLE}/Contents/Resources"

swiftc \
    -sdk     "${SDK}" \
    -target  "${TARGET}" \
    -O \
    -framework AppKit \
    -framework Foundation \
    -framework Security \
    -o "${OUT_DIR}/${BUNDLE}/Contents/MacOS/${APP_NAME}" \
    ClaudeMonitor/main.swift \
    ClaudeMonitor/AppDelegate.swift \
    ClaudeMonitor/UsageAPI.swift \
    ClaudeMonitor/StatusBarController.swift

echo "▶ Copying Info.plist..."
# Подставляем переменные вручную
sed \
    -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.user.ClaudeMonitor/g" \
    -e "s/\$(PRODUCT_NAME)/${APP_NAME}/g" \
    -e "s/\$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/12.0/g" \
    ClaudeMonitor/Info.plist > "${OUT_DIR}/${BUNDLE}/Contents/Info.plist"

echo "▶ Ad-hoc signing..."
codesign --force --deep --sign - "${OUT_DIR}/${BUNDLE}"

echo "▶ Creating DMG..."
rm -f "${DMG_NAME}"
hdiutil create \
    -volname   "${APP_NAME}" \
    -srcfolder "${OUT_DIR}/${BUNDLE}" \
    -ov \
    -format    UDZO \
    "${DMG_NAME}"

echo ""
echo "✓ Готово: ${DMG_NAME}"
echo "  Установка: открой ${DMG_NAME} → перетащи ${BUNDLE} в /Applications"
