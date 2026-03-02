#!/bin/bash
set -euo pipefail

# Usage: ./release.sh v0.2.0

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version>"
    echo "Example: ./release.sh v0.2.0"
    exit 1
fi

PLIST_VERSION="${VERSION#v}"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "Releasing RxBurn $VERSION"

# Ensure clean working tree
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: dirty working tree. Commit or stash first."
    exit 1
fi

# Update version in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${PLIST_VERSION}" RxBurn/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${PLIST_VERSION}" RxBurn/Info.plist

# Build
echo "Building..."
cd RxBurn && swift build 2>&1 && cd ..

# Bundle .app
mkdir -p RxBurn.app/Contents/MacOS
cp RxBurn/.build/debug/RxBurn RxBurn.app/Contents/MacOS/RxBurn
cp RxBurn/Info.plist RxBurn.app/Contents/Info.plist
codesign --force --deep --sign - RxBurn.app

# Zip
ZIP_NAME="RxBurn-${VERSION}.zip"
rm -f "$ZIP_NAME"
zip -r "$ZIP_NAME" RxBurn.app
echo "Created $ZIP_NAME"

# Commit, tag, release
git add RxBurn/Info.plist
git commit -m "release ${VERSION}"
git tag "$VERSION"
git push origin main --tags

gh release create "$VERSION" "$ZIP_NAME" \
    --title "RxBurn $VERSION" \
    --generate-notes

echo ""
echo "Released: https://github.com/manzanita-research/rxburn/releases/tag/$VERSION"
