#!/bin/bash
# Build Vata.app with swiftc — no Xcode project required.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
APP="$ROOT/Vata.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/FileIcons"
python3 "$ROOT/gen-icons.py"
# Build gate: unit checks must pass before the app compiles.
echo "-- unit gate --"
export VATA_ICON_DIR="$ROOT/Sources/FileIcons"
swiftc -O -o /tmp/vata-unit-gate \
  "$ROOT"/UnitGate/*.swift \
  $(ls "$ROOT"/Sources/*.swift | grep -v "/main.swift") \
  -framework AppKit -framework Foundation -framework Quartz
/tmp/vata-unit-gate
swiftc -O -o "$APP/Contents/MacOS/Vata" "$ROOT"/Sources/*.swift \
  -framework AppKit -framework Foundation -framework Quartz
cp "$ROOT/Sources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Sources/FileIcons/"*.png "$APP/Contents/Resources/FileIcons/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Vata</string>
	<key>CFBundleIdentifier</key>
	<string>com.vata.app</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Vata</string>
	<key>CFBundleDisplayName</key>
	<string>Vata</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.2.2</string>
	<key>CFBundleVersion</key>
	<string>4</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.6</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST
echo 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
