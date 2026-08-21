#!/usr/bin/env bash
#
# Builds and launches a throwaway macOS build for testing SSO login, isolated
# from your installed mDone.
#
#   ./scripts/dev-macos-oidc.sh            build and launch
#   ./scripts/dev-macos-oidc.sh --cleanup  quit it and remove every trace
#
# Why the isolation matters: the normal macOS build shares bundle identifier
# com.mdone.app with the copy in /Applications, so it reads the same keychain
# and the same sandbox container. Running it would sign you straight into your
# real server without ever showing the setup screen, and signing in to a test
# server would overwrite the credentials your real app is using.
#
# Overriding PRODUCT_BUNDLE_IDENTIFIER gives the build its own keychain access
# group and its own container, so nothing it does can touch the real app.
#
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_BUNDLE_ID="com.mdone.app.oidctest"
BUILD_DIR=".build/macos-oidc"
APP="${BUILD_DIR}/Build/Products/Debug/mDone-macOS.app"

if [ "${1:-}" = "--cleanup" ]; then
    pkill -f "macos-oidc/Build" 2>/dev/null || true
    sleep 1
    if [ -d "$APP" ]; then
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -u "$(pwd)/$APP" 2>/dev/null || true
    fi
    rm -rf "$BUILD_DIR"
    # macOS guards the container's metadata, so this usually cannot be deleted
    # outright. It is an empty sandbox belonging to a bundle id that no longer
    # exists on disk, so leaving it costs nothing.
    CONTAINER="$HOME/Library/Containers/${TEST_BUNDLE_ID}"
    if [ -d "$CONTAINER" ]; then
        rm -rf "$CONTAINER" 2>/dev/null || true
        [ -d "$CONTAINER" ] && echo "==> note: macOS would not let us delete ${CONTAINER}. It is empty and harmless."
    fi
    echo "==> cleaned up. Your installed mDone was never touched."
    exit 0
fi

echo "==> building an isolated macOS build (${TEST_BUNDLE_ID})"
xcodebuild -project mDone.xcodeproj -scheme mDone-macOS \
    -derivedDataPath "$BUILD_DIR" \
    PRODUCT_BUNDLE_IDENTIFIER="$TEST_BUNDLE_ID" \
    build >/dev/null 2>&1 || { echo "build failed, rerun without >/dev/null to see why" >&2; exit 1; }

# Prove the isolation rather than assume it.
BUNDLE=$(defaults read "$(pwd)/${APP}/Contents/Info.plist" CFBundleIdentifier)
[ "$BUNDLE" = "$TEST_BUNDLE_ID" ] || { echo "bundle id override did not take: $BUNDLE" >&2; exit 1; }

echo "==> launching"
open -a "$(pwd)/$APP"

cat <<EOF

Isolated build running. Your installed mDone keeps its own login.

  1. Paste your server URL into Server URL.
  2. Wait a beat. If that server advertises an OIDC provider, a
     "Continue with <provider>" button appears under Connect.
  3. Click it. macOS opens your DEFAULT BROWSER, not an in-app sheet.
  4. Sign in there.

The thing to watch for is step 4's return: does the browser hand you back
to mDone, and does mDone land on the task list? That is the one leg of
this flow still unverified on macOS.

If it hangs on the spinner instead, the callback is not reaching the app,
and mdone://oidc-callback almost certainly needs registering as a redirect
URI on the identity provider for that server.

When done:  ./scripts/dev-macos-oidc.sh --cleanup
EOF
