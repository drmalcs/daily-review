#!/bin/bash
# Builds a release .app bundle and installs it to ~/Applications/.
# Run this after any code change to update the installed app.
# Usage: bash scripts/build-app.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="DailyReview"
INSTALL_DIR="$HOME/Applications"

echo "Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release

BINARY="$PROJECT_DIR/.build/release/$APP_NAME"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Sources/$APP_NAME/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Remove quarantine flag so macOS doesn't block an unsigned local build
xattr -rd com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -r "$APP_BUNDLE" "$INSTALL_DIR/"
rm -rf "$APP_BUNDLE"

echo ""
echo "Done. To launch:  open ~/Applications/$APP_NAME.app"
echo "To auto-start:    System Settings > General > Login Items > add DailyReview"
