#!/bin/zsh
# Builds build/Interlude.app from the Swift package and signs it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --build-path .build-release  # separate from `swift test`, whose cache the release build was breaking
APP=build/Interlude.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Fonts/*.ttf "$APP/Contents/Resources/" # Instrument Serif and DM Mono (SIL Open Font License)
cp Fonts/OFL.txt "$APP/Contents/Resources/" # the font license must ship with the fonts
cp branding/AppIcon.icns "$APP/Contents/Resources/" # made from branding/logo.svg
# A wallpaper still behind the card previews in Settings, if you have one. Not in the repo: aerial stills
# are Apple's. Without it, previews sit on a dusk gradient.
[[ -f branding/backdrop.jpg ]] && cp branding/backdrop.jpg "$APP/Contents/Resources/"
cp "$(swift build -c release --build-path .build-release --show-bin-path)/Interlude" "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Interlude</string>
  <key>CFBundleIdentifier</key><string>com.hari.Interlude</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Interlude</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>Interlude shows your reminders on its screen and lets you tick them off.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Interlude shows your next event and today's date on its screen.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Interlude reads what Music or Spotify is playing and lets you pause or skip from its screen.</string>
  <key>NSLocationUsageDescription</key>
  <string>Interlude uses your approximate location to show local weather.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Interlude uses your approximate location to show local weather.</string>
</dict>
</plist>
PLIST

# A stable local identity keeps macOS permissions across rebuilds; ad-hoc signing is the fallback.
codesign --force --sign "Ultron Local Signing" "$APP" 2>/dev/null || codesign --force --sign - "$APP"
echo "Built $APP"
