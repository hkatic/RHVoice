#!/bin/bash
# Archive, sign with Developer ID, notarize and package RHVoice.app as a disk image.
#
# Requirements:
#   - a "Developer ID Application" certificate in the keychain
#   - a notarytool keychain profile: xcrun notarytool store-credentials RHVoice --apple-id ... --team-id ... --password ...
#   - Config/Local.xcconfig with DEVELOPMENT_TEAM set
#
#   scripts/notarize.sh [output directory]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/dist}"
PROFILE="${NOTARY_PROFILE:-RHVoice}"
VERSION=$(sed -n 's/^RHVOICE_VERSION = //p' Config/Version.xcconfig | tr -d ' ')
mkdir -p "$OUT"

echo "Archiving RHVoice $VERSION…"
xcodebuild -project RHVoice.xcodeproj -scheme RHVoice -configuration Release \
  -archivePath "$OUT/RHVoice.xcarchive" archive -quiet \
  CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/RHVoice.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet

APP="$OUT/export/RHVoice.app"
DMG="$OUT/RHVoice-$VERSION.dmg"
rm -f "$DMG"
echo "Creating $DMG…"
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "RHVoice $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

echo "Notarizing…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true
echo "Done: $DMG"
