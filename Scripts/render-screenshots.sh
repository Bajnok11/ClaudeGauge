#!/usr/bin/env bash
#
# Regenerates the images used in README.md. Run from the repo root:
#
#     ./Scripts/render-screenshots.sh
#
# Two mechanisms, because no single one covers the whole app:
#
#   * Popover and widgets are drawn offscreen with `ImageRenderer`
#     (ClaudeGauge/ScreenshotRenderer.swift). A menu bar popover belongs to
#     an LSUIElement agent app — there's no window to capture and no Dock
#     icon to click — and widgets live inside Notification Center.
#
#   * History and Settings are captured as real windows, because they're
#     built from AppKit-backed SwiftUI (Table, Form, TabView) that
#     `ImageRenderer` can only draw as a placeholder. Rewriting them in
#     hand-rolled SwiftUI just to satisfy the renderer would mean shipping a
#     less native app to serve the README, so they get screencaptured
#     instead.
#
# Screen Recording permission is required for the window captures (System
# Settings → Privacy & Security → Screen Recording) — without it macOS
# refuses and you'll see "could not create image from display".

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

OUTPUT_DIR="$(pwd)/docs/images"
# Build outside the repo: an iCloud-synced Desktop injects metadata mid-build
# that makes codesign fail. Same reasoning as Scripts/build-dmg.sh.
DERIVED_DATA="${TMPDIR:-/tmp}/claudegauge-screenshots"

command -v xcodegen >/dev/null 2>&1 || { echo "==> Installing XcodeGen"; brew install xcodegen; }

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building (Debug)"
xcodebuild \
  -project ClaudeGauge.xcodeproj \
  -scheme ClaudeGauge \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build >/dev/null

APP="$DERIVED_DATA/Build/Products/Debug/ClaudeGauge.app"
BINARY="$APP/Contents/MacOS/ClaudeGauge"
if [ ! -x "$BINARY" ]; then
  echo "Build succeeded but $BINARY is missing — aborting." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Force en_US for the captures. Number formatting is locale-aware (a
# Hungarian machine renders "4,8M" where most README readers expect
# "4.8M"), and images in a shared repo shouldn't change depending on who
# regenerated them.
LOCALE_ARGS=(-AppleLanguages "(en)" -AppleLocale "en_US")

echo "==> Rendering popover and widgets offscreen"
"$BINARY" "${LOCALE_ARGS[@]}" --render-screenshots "$OUTPUT_DIR"

echo "==> Capturing History and Settings windows"
# Stop any copy already running so the capture targets this build.
pkill -f "ClaudeGauge.app/Contents/MacOS/ClaudeGauge" 2>/dev/null || true
sleep 1

"$BINARY" "${LOCALE_ARGS[@]}" --open-windows &
CAPTURE_PID=$!
# Give SwiftUI time to lay the windows out; capturing mid-animation
# produces half-drawn chrome.
sleep 5

capture_window() {
  local outfile="$1"; shift
  local id
  # Callers pass a grep pipeline as remaining args, because a tabbed macOS
  # Settings window is titled after its *selected tab* ("General"), not
  # "Settings" — so it's identified by exclusion rather than by name.
  id=$(swift Scripts/window-capture.swift ClaudeGauge 2>/dev/null | "$@" | head -1 | cut -f1)
  if [ -z "$id" ]; then
    echo "    ! no matching window — skipped $(basename "$outfile")" >&2
    return 1
  fi
  screencapture -x -o -l"$id" "$outfile"
  echo "    captured $(basename "$outfile")"
}

capture_window "$OUTPUT_DIR/history.png" grep -i "History" || true
capture_window "$OUTPUT_DIR/settings.png" grep -iv "History" || true

kill "$CAPTURE_PID" 2>/dev/null || true
wait "$CAPTURE_PID" 2>/dev/null || true

echo "==> Done"
ls -la "$OUTPUT_DIR"
