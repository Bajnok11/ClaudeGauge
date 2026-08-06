#!/usr/bin/env bash
#
# Builds ClaudeGauge in Release configuration and packages it into a
# drag-to-Applications .dmg under build/.
#
# Usage:
#   ./Scripts/build-dmg.sh                # signs with your local Apple ID team (same as a normal Xcode Run)
#   UNSIGNED=1 ./Scripts/build-dmg.sh      # code signing disabled entirely (what CI uses — no team available there)
#
# ClaudeGauge does not have a paid Apple Developer Program membership yet
# (see DISTRIBUTION.md), so neither mode produces a notarized build. Anyone
# who downloads the resulting DMG will see a Gatekeeper warning the first
# time they open the app — see README.md's "Installing" section for how to
# get past it.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PROJECT="ClaudeGauge.xcodeproj"
SCHEME="ClaudeGauge"
APP_NAME="ClaudeGauge"
# Deliberately OUTSIDE the project tree: if this repo lives under an
# iCloud Drive-synced Desktop/Documents folder (as it does in local dev —
# `defaults read com.apple.finder FXICloudDriveDesktop`), iCloud injects
# sync-tracking metadata into files while they're being written, and
# codesign fails mid-build with "resource fork, Finder information, or
# similar detritus not allowed" on whatever it's signing at that moment.
# Building into /tmp sidesteps that entirely. Only the finished .dmg lands
# under build/ (see DMG_PATH below), which is safe — it's a single
# completed file, not something codesign is actively operating on.
DERIVED_DATA="${TMPDIR:-/tmp}/claudegauge-build-dmg"

VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([0-9.]+)".*/\1/')
if [ -z "$VERSION" ]; then
  echo "Could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

echo "==> Building $APP_NAME $VERSION (Release)"

command -v xcodegen >/dev/null 2>&1 || { echo "==> Installing XcodeGen"; brew install xcodegen; }
command -v create-dmg >/dev/null 2>&1 || { echo "==> Installing create-dmg"; brew install create-dmg; }

echo "==> Generating Xcode project"
xcodegen generate

SIGN_ARGS=(-allowProvisioningUpdates)
if [ "${UNSIGNED:-0}" = "1" ]; then
  echo "==> Building UNSIGNED (no Apple Developer team available in this environment)"
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
else
  echo "==> Building signed with your local Apple ID team (Signing & Capabilities)"
fi

rm -rf "$DERIVED_DATA"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  "${SIGN_ARGS[@]}" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Build succeeded but $APP_PATH is missing — aborting." >&2
  exit 1
fi

mkdir -p build
DMG_PATH="build/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"

echo "==> Packaging $DMG_PATH"
# create-dmg drives Finder over AppleScript to lay out the window/icons and
# can return a non-zero exit code on benign races (e.g. Finder redrawing)
# even when it succeeds — so don't trust its exit code, verify the file.
create-dmg \
  --volname "$APP_NAME" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 140 160 \
  --app-drop-link 400 160 \
  --hide-extension "$APP_NAME.app" \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH" \
  || true

if [ ! -f "$DMG_PATH" ]; then
  echo "create-dmg did not produce $DMG_PATH — aborting." >&2
  exit 1
fi

echo "==> Done: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
