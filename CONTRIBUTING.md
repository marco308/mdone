# Contributing to mDone

Thanks for your interest in contributing to mDone! This is a native iOS/macOS task management app that connects to self-hosted [Vikunja](https://vikunja.io) servers.

## Reporting Bugs

Please open an issue on [GitHub Issues](https://github.com/marco308/mdone/issues) with as much detail as possible. Use the bug report template when available.

## Development Setup

**Requirements:**

- Xcode (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Deployment targets: iOS 18.0+ / macOS 15.0+
- No external dependencies

**Build steps:**

```bash
# Generate the Xcode project
xcodegen generate

# Build for iOS
xcodebuild -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build for macOS
xcodebuild -project mDone.xcodeproj -scheme mDone-macOS build

# Run tests
xcodebuild -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Code Style

This project uses **SwiftLint** and **SwiftFormat** to enforce consistent code style. Configs are in `.swiftlint.yml` and `.swiftformat` respectively.

```bash
swiftlint lint --quiet
swiftformat .
```

Please run both before submitting a PR.

## Pull Requests

- Keep PRs focused on a single change.
- Describe what your PR does and why.
- Link any related issues (e.g., `Fixes #123`).
- Make sure the project builds and tests pass on both iOS and macOS.

## Questions?

Open a [discussion or issue](https://github.com/marco308/mdone/issues) and we'll be happy to help.
