#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/RxBurn"

echo "Building RxBurn..."
swift build 2>&1

# Create .app bundle
APP_DIR="../RxBurn.app/Contents/MacOS"
mkdir -p "$APP_DIR"
cp .build/debug/RxBurn "$APP_DIR/RxBurn"
cp Info.plist ../RxBurn.app/Contents/Info.plist

echo ""
echo "Built: RxBurn.app"
echo "Run:   open RxBurn.app"
