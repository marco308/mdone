#!/usr/bin/env bash
#
# Refresh the String Catalogs from the source, without needing the Xcode IDE.
#
# Builds every target that ships strings, then merges the compiler-extracted
# `.stringsdata` into the matching `.xcstrings`. Existing translations survive;
# see scripts/merge-stringsdata.py for the merge rules.
#
# Both platforms get built on purpose. The app and macOS targets compile the
# same sources, but each `#if os(...)` branch is only visible to the platform
# that compiles it, so a single-platform run would silently drop the other
# platform's strings and mark them stale.
#
# Usage: ./scripts/update-string-catalogs.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED=$(mktemp -d)
trap 'rm -rf "$DERIVED"' EXIT

if [ ! -d mDone.xcodeproj ]; then
    echo "Generating Xcode project..."
    xcodegen generate
fi

echo "Building iOS app (extracts app + widget strings)..."
xcodebuild -project mDone.xcodeproj -scheme mDone \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" build > "$DERIVED/ios.log" 2>&1 \
    || { echo "iOS build failed:"; tail -40 "$DERIVED/ios.log"; exit 1; }

echo "Building macOS app (extracts the macOS side of every #if os(...))..."
xcodebuild -project mDone.xcodeproj -scheme mDone-macOS \
    -derivedDataPath "$DERIVED" build > "$DERIVED/macos.log" 2>&1 \
    || { echo "macOS build failed:"; tail -40 "$DERIVED/macos.log"; exit 1; }

INTERMEDIATES="$DERIVED/Build/Intermediates.noindex/mDone.build"

echo
./scripts/merge-stringsdata.py mDone/Localizable.xcstrings \
    "$INTERMEDIATES"/*/mDone.build \
    "$INTERMEDIATES"/*/mDone-macOS.build

./scripts/merge-stringsdata.py mDoneWidgets/Localizable.xcstrings \
    "$INTERMEDIATES"/*/mDoneWidgets.build

echo
echo "Done. Review the diff before committing:  git diff -- '*.xcstrings'"
