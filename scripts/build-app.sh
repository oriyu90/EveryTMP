#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds the EveryTMP.app bundle (release) and an optional DMG.
#
# Usage:
#   scripts/build-app.sh              # app bundle only
#   BUILD_DMG=1 scripts/build-app.sh  # app bundle + DMG + .sha256
#
# The app is ad-hoc signed (codesign --sign -). No Apple Developer Program
# certificate is required, and the app is not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="EveryTMP"
BUNDLE_ID="dev.studiorizi.everytmp"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
DEPLOYMENT_TARGET="13.0"

echo "==> Building release binary"
swift build -c release --arch arm64

BIN="$(swift build -c release --arch arm64 --show-bin-path)/EveryTMP"

APP_DIR="dist/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

echo "==> Assembling ${APP_DIR}"
rm -rf dist
mkdir -p "${MACOS_DIR}" "${RES_DIR}"
cp "${BIN}" "${MACOS_DIR}/${APP_NAME}"

cp -R Resources/ja.lproj Resources/en.lproj "${RES_DIR}/"

# App icon: build the icns once and reuse it.
if [ ! -f "Resources/AppIcon.icns" ]; then
    echo "==> Generating app icon"
    swift scripts/make-icon.swift Resources/AppIcon.iconset
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
    rm -rf Resources/AppIcon.iconset
fi
cp Resources/AppIcon.icns "${RES_DIR}/AppIcon.icns"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja</string>
    <key>LSMinimumSystemVersion</key>
    <string>${DEPLOYMENT_TARGET}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (c) 2026 Yuki_Orita</string>
</dict>
</plist>
PLIST

cat > "${CONTENTS}/PkgInfo" <<'EOF'
APPL????
EOF

echo "==> Ad-hoc code signing"
codesign --force --sign - --timestamp=none "${APP_DIR}"
codesign --verify --strict "${APP_DIR}"

if [ "${BUILD_DMG:-0}" = "1" ]; then
    DMG_NAME="EveryTMP-${VERSION}.dmg"
    echo "==> Creating ${DMG_NAME}"
    STAGING="dist/dmg-staging"
    mkdir -p "${STAGING}"
    cp -R "${APP_DIR}" "${STAGING}/"
    ln -s /Applications "${STAGING}/Applications"
    hdiutil create -volname "EveryTMP" \
        -srcfolder "${STAGING}" \
        -ov -format UDZO \
        "dist/${DMG_NAME}"
    rm -rf "${STAGING}"
    echo "==> Verifying DMG and writing checksum"
    hdiutil verify "dist/${DMG_NAME}"
    (cd dist && shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256")
    cat "dist/${DMG_NAME}.sha256"
fi

echo "==> Done: ${APP_DIR}"
