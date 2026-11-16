#!/bin/zsh
# Use Apple Development for a personal installer, Developer ID Application for distribution.
# Never silently fall back to ad-hoc signing: macOS permissions follow code identity.
set -eu
project_dir="${0:A:h:h}"
: "${KLIP_SIGNING_IDENTITY:?Set KLIP_SIGNING_IDENTITY to your signing certificate name or SHA-1.}"
if [[ "$KLIP_SIGNING_IDENTITY" == "-" ]]; then
    print -u2 "Ad-hoc signing changes Klip’s identity between builds and can invalidate paste permission."
    exit 1
fi
output_path="${1:-$HOME/Desktop/Klip.dmg}"
output_path="${output_path:a}"
if [[ -e "$output_path" ]]; then
    print -u2 "Output already exists: $output_path"
    exit 1
fi
package_dir="$(mktemp -d /tmp/klip-package.XXXXXX)"
trap 'rm -rf "$package_dir"' EXIT
xcodebuild -project "$project_dir/Klip.xcodeproj" -scheme Klip -configuration Release \
    -derivedDataPath "$package_dir/build" -destination 'generic/platform=macOS' \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$KLIP_SIGNING_IDENTITY" build
app_path="$package_dir/build/Build/Products/Release/Klip.app"
codesign --verify --deep --strict "$app_path"
signature_info="$(codesign -dv "$app_path" 2>&1)"
if [[ "$signature_info" == *"Signature=adhoc"* || "$signature_info" == *"TeamIdentifier=not set"* ]]; then
    print -u2 "The app lacks a certificate-backed signing identity. Refusing to package it."
    exit 1
fi
mkdir "$package_dir/staging"
ditto "$app_path" "$package_dir/staging/Klip.app"
ln -s /Applications "$package_dir/staging/Applications"
hdiutil create -volname Klip -srcfolder "$package_dir/staging" -format UDZO "$output_path"
hdiutil verify "$output_path"
shasum -a 256 "$output_path"
print "Created $output_path"
print "Developer ID distribution also requires notarization; this script does not notarize."
