#!/bin/zsh
# Builds "Haari Player.app" (universal: Apple Silicon + Intel) next to this script.
# Usage: ./build.sh            build the app
#        ./build.sh --zip      also make dist/HaariPlayer-<version>-mac.zip
set -e
cd "$(dirname "$0")"

APP="Haari Player.app"
BUILD=".build"
VLCKIT_VERSION="3.7.3"
VLCKIT_URL="https://download.videolan.org/pub/cocoapods/prod/VLCKit-3.7.3-319ed2c0-79128878.tar.xz"
VLCKIT_SHA256="019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

# 1. Fetch VLCKit (the playback engine) from VideoLAN once, and verify it.
if [ ! -d Vendor/VLCKit.framework ]; then
  echo "Downloading VLCKit $VLCKIT_VERSION from videolan.org…"
  mkdir -p Vendor "$BUILD"
  curl -fL --progress-bar -o "$BUILD/vlckit.tar.xz" "$VLCKIT_URL"
  echo "$VLCKIT_SHA256  $BUILD/vlckit.tar.xz" | shasum -a 256 -c -
  tar -xf "$BUILD/vlckit.tar.xz" -C "$BUILD"
  mv "$BUILD/VLCKit - binary package/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework" Vendor/
  cp "$BUILD/VLCKit - binary package/COPYING.txt" Vendor/VLCKit-COPYING.txt
  rm -rf "$BUILD/VLCKit - binary package" "$BUILD/vlckit.tar.xz"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$BUILD"

# 2. Compile for both architectures and merge.
for ARCH in arm64 x86_64; do
  swiftc -swift-version 5 -O -target $ARCH-apple-macos13.0 \
    -F Vendor -framework VLCKit \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$BUILD/HaariPlayer-$ARCH" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/HaariPlayer" "$BUILD/HaariPlayer-arm64" "$BUILD/HaariPlayer-x86_64"

# 3. Bundle resources.
cp Info.plist "$APP/Contents/Info.plist"
ditto Vendor/VLCKit.framework "$APP/Contents/Frameworks/VLCKit.framework"
mkdir -p "$APP/Contents/Resources/Licenses"
cp LICENSE "$APP/Contents/Resources/Licenses/HaariPlayer-LICENSE.txt"
cp Vendor/VLCKit-COPYING.txt "$APP/Contents/Resources/Licenses/VLCKit-LGPL-2.1.txt"
if [ -f Assets/AppIcon.icns ]; then
  cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  swift Tools/render_svg.swift Assets/icon.svg "$BUILD/AppIcon.iconset"
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# 4. Ad-hoc sign so it runs on Apple Silicon.
codesign --force --sign - "$APP/Contents/Frameworks/VLCKit.framework"
codesign --force --sign - "$APP"
echo "Built: $(pwd)/$APP"

if [ "$1" = "--zip" ]; then
  mkdir -p dist
  ZIP="dist/HaariPlayer-$VERSION-mac.zip"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "Zipped: $(pwd)/$ZIP"
fi
