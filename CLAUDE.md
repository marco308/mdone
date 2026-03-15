# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

mDone is a native iOS/macOS task management app that connects to a self-hosted **Vikunja** server via its REST API (v2.1.0). Pure Swift with SwiftUI — no external dependencies.

## Build & Development

The project uses **XcodeGen** to generate the Xcode project from `project.yml`.

```bash
# Regenerate Xcode project after changing targets/settings
xcodegen generate

# Build iOS app
xcodebuild -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build macOS app
xcodebuild -project mDone.xcodeproj -scheme mDone-macOS build

# Run unit tests
xcodebuild -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test
xcodebuild -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:mDoneTests/TaskServiceTests test

# Lint
swiftlint lint --quiet

# Format
swiftformat .
```

**Deployment targets:** iOS 18.0+, macOS 15.0+. Swift 5.9.

## Architecture

### Data Flow
```
View → AppState (method call) → Service (TaskService/ProjectService)
→ APIClient (singleton actor) → Vikunja REST API → decode response → update AppState → SwiftUI re-renders
```

### Key Patterns
- **AppState** (`App/AppState.swift`): Single `@Observable` class holding all app state — tasks, projects, labels, notifications, auth status, filters. All mutating async methods are `@MainActor`.
- **Services are actors**: `APIClient`, `TaskService`, `ProjectService`, `AuthService`, `NotificationService`, `SyncService` — all actors for thread safety.
- **APIClient** (`Services/APIClient.swift`): Singleton actor. Uses `convertFromSnakeCase`/`convertToSnakeCase` key strategies. Custom date decoding handles ISO8601 with/without fractional seconds, plus Vikunja's zero-date (`0001-01-01T00:00:00Z` → `Date.distantPast`).
- **Endpoint** (`Services/Endpoint.swift`): Static factory methods returning `Endpoint` structs with path, HTTP method, and query items. Vikunja API base path: `/api/v1/`.
- **Platform split**: iOS uses `MainTabView` (tab bar), macOS uses `MacContentView` (NavigationSplitView sidebar). Conditional compilation via `#if os(iOS)` / `#if os(macOS)`.
- **Auth**: Token stored in Keychain (`AuthService`), server URL in UserDefaults. Login validates by fetching projects.
- **Offline support**: SwiftData models in `CacheService.swift` (CachedTask, CachedProject, CachedLabel, PendingOperation) synced via `SyncService`.

### Vikunja API Notes
- Task creation uses `PUT /api/v1/projects/{id}/tasks` (not POST)
- Task update uses `POST /api/v1/tasks/{id}` (not PUT)
- Filtering uses Vikunja DSL syntax, e.g. `"priority = 3 && due_date > now && done = false"`
- All IDs are `Int64`

## Linting & Formatting

SwiftLint runs as a post-build script (configured in `project.yml`). Config in `.swiftlint.yml` — notably disables `line_length`, `trailing_whitespace`, `type_body_length`, `file_length`, `function_body_length`, and `cyclomatic_complexity`.

SwiftFormat config in `.swiftformat`: 4-space indent, 120 max width, semicolons never.
