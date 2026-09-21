#!/bin/sh
# Assembles DumSim.app from the SwiftPM products.
#
# Usage: Scripts/bundle.sh [debug|release]
set -eu

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DumSim.app"
VERSION="0.1.0"
BUNDLE_ID="io.github.ricsantos.dum-sim"

cd "$ROOT"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG" --product DumSimApp
swift build -c "$CONFIG" --product dum-sim
swift build -c "$CONFIG" --product make-icon

BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/DumSimApp" "$APP/Contents/MacOS/DumSim"
# The CLI rides along, so one bundle installs both.
cp "$BIN/dum-sim" "$APP/Contents/MacOS/dum-sim"

# Resources/AppIcon.png is masked into the macOS icon shape. Without that file
# the tool draws the steamer glyph instead.
"$BIN/make-icon" "$APP/Contents/Resources" --source "$ROOT/Resources/AppIcon.png"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>DumSim</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>DumSim</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>MIT licence</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature. A release build replaces this with a Developer ID.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
	echo "warning: ad-hoc signing failed; the app still runs locally"

echo "Built $APP"
