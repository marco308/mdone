# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

mDone is a native iOS/macOS task management app that connects to a self-hosted **Vikunja** server via its **v1** REST API (`/api/v1`, verified against Vikunja v2.5.0). Pure Swift with SwiftUI, no external dependencies. Vikunja 2.4.0 added a parallel `/api/v2` that upstream recommends for new clients; mDone has not migrated. See `docs/vikunja-api-inventory.md`.

Beyond plain task CRUD the app also covers: focus sessions with a Live Activity, Kanban boards, subtasks and task relations, calendar (EventKit) overlay, home/lock screen widgets, Shortcuts and Siri actions, and offline caching with a pending-operation queue.

## Repository Layout

| Path | What lives there |
|---|---|
| `mDone/App/` | `AppState`, `AppDependencies` (SwiftData container + network monitor), App Intents, preference types |
| `mDone/Models/` | API models: `VTask`, `Project`, `Label`, `Bucket`, `TaskRelation`, `CalendarEvent`, `VNotification`, `ProjectHierarchy` |
| `mDone/Services/` | Actors and managers: API, auth, sync, cache, labels, notifications, calendar, focus |
| `mDone/Views/` | SwiftUI views, split by feature (`Tasks`, `Projects`, `Calendar`, `Focus`, `Settings`, `Notifications`, `Setup`, `Components`) plus `Mac/` for the macOS-only UI |
| `mDoneShared/` | Sources compiled into **both** the app and the widget extension: `WidgetDataProvider`, `WidgetModels`, `FocusSession`, `SharedTokenStore`, `SharedConstants` |
| `mDoneWidgets/` | WidgetKit extension: Today/Upcoming/QuickAdd/lock screen widgets and the focus Live Activity |
| `mDoneTests/` | Unit tests (iOS, hosted by the app) |
| `mDoneUITests/`, `mDoneMacUITests/` | XCUITests, including the App Store screenshot runs |
| `mDoneWidgetRenderTests/` | Unhosted logic tests that render widget views to PNGs for the marketing site |
| `docs/` | Dev setup, App Store metadata, Vikunja API inventory, research notes |
| `scripts/` | `seed-dev-vikunja.sh`, `reset-dev-vikunja.sh` for the local dev server |
| `website/` | The GitHub Pages site (deployed by `.github/workflows/deploy-pages.yml`) |

## Build & Development

The project uses **XcodeGen** to generate the Xcode project from `project.yml`. The `.xcodeproj` is not committed, so generate it after any clone or target/settings change.

```bash
# Regenerate Xcode project after changing targets/settings
xcodegen generate

# Build iOS app
xcodebuild -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build

# Build macOS app
xcodebuild -project mDone.xcodeproj -scheme mDone-macOS build

# Run unit tests only (what CI runs)
xcodebuild -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:mDoneTests test

# Run the same unit tests against the macOS app
xcodebuild -project mDone.xcodeproj -scheme mDone-macOS -destination 'platform=macOS' -only-testing:mDoneMacTests test

# Run a single test class
xcodebuild -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:mDoneTests/TaskServiceTests test

# Lint
swiftlint lint --quiet

# Format
swiftformat .
```

**Simulator destinations:** build-only invocations use `generic/platform=iOS Simulator`, which needs no simulator by that name to exist. Test runs have to name a concrete device, so they use the same one CI pins in `.github/workflows/ios-tests.yml` (`iPhone 17`). If you change one, change the other, and check `xcrun simctl list devices available` when a destination stops resolving after an Xcode update.

**Deployment targets:** iOS 18.0+, macOS 15.0+. Swift 5.9. Version and build number live in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`), not in an Info.plist.

### Targets and schemes

- `mDone` (iOS app, embeds `mDoneWidgets`); its scheme runs `mDoneTests`, `mDoneUITests`, `mDoneWidgetRenderTests`.
- `mDone-macOS` (macOS app); its scheme runs `mDoneMacTests` and `mDoneMacUITests`.
- `mDoneWidgets` (app extension), `mDoneTests`, `mDoneUITests`, `mDoneMacTests`, `mDoneMacUITests`, `mDoneWidgetRenderTests`.

`mDoneTests` and `mDoneMacTests` compile the **same** `mDoneTests/` sources against the iOS and macOS app respectively, so a shared service or model is covered on both platforms from one set of files. Cases that only make sense on iOS (Live Activity, focus outbox) guard themselves with `#if os(iOS)`. `mDone-macOS` pins `PRODUCT_MODULE_NAME: mDone` so the shared `@testable import mDone` resolves there too; without it the module would be `mDone_macOS` and every test file would fail to compile.

The iOS and macOS app targets compile the **same** `mDone/` + `mDoneShared/` sources, so anything platform-specific needs `#if os(iOS)` / `#if os(macOS)`.

`project.yml` pins a few settings that XcodeGen 2.45.4 stopped emitting (`PRODUCT_NAME`, `ENABLE_TESTABILITY` for Debug, `SDKROOT` for the iOS app). Do not remove them: builds and `@testable import mDone` break without them. The comments in the file explain each one.

### Local dev server

Never develop against a real Vikunja. Bring up a throwaway one on `http://localhost:3456`:

```bash
docker compose -f docker-compose.dev.yml up -d && ./scripts/seed-dev-vikunja.sh
```

Log in with `devuser` / `devpassword`. `./scripts/reset-dev-vikunja.sh` nukes and reseeds it. Full walkthrough, including the environments table (dev vs Apple Review test server vs prod), in [docs/dev-setup.md](docs/dev-setup.md).

### CI

- `.github/workflows/ios-tests.yml` runs `mDoneTests` on the iOS Simulator for every PR to `main`, pinned to `-destination 'platform=iOS Simulator,name=iPhone 17'`. UI and snapshot targets are excluded: they need a booted app and are flaky on CI.
- `.github/workflows/macos-tests.yml` runs `mDoneMacTests` on `-destination 'platform=macOS'` for every PR to `main`. It signs ad-hoc (`CODE_SIGN_IDENTITY=-`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGN_STYLE=Manual`, empty `DEVELOPMENT_TEAM`) because runners have no Apple Development identity and, unlike the simulator, a real macOS bundle has to be signed to launch. Ad-hoc still applies the sandbox entitlements, so the Keychain-backed tests pass. `mDoneMacUITests` is excluded: it is the App Store screenshot run and needs a live server plus credentials.
- `.github/workflows/vikunja-integration.yml` runs `mDoneIntegrationTests` nightly (and on demand) against a real Vikunja server: the latest release plus the pinned version the API inventory was verified against. It runs the native macOS release binary straight on the runner, never Docker, because the hosted arm64 macOS runners cannot boot a Linux VM. It never runs on a PR and cannot block a merge.
- `.github/workflows/codeql.yml` runs CodeQL (build-only, so it uses `generic/platform=iOS Simulator`); `.github/workflows/deploy-pages.yml` publishes `website/`.

## Architecture

### Data Flow
```
View → AppState (method call) → Service (TaskService/ProjectService)
→ APIClient (singleton actor) → Vikunja REST API → decode response → update AppState → SwiftUI re-renders
```

### Key Patterns
- **AppState** (`App/AppState.swift`): Single `@Observable` class holding all app state: tasks, projects, labels, notifications, auth status, filters. All mutating async methods are `@MainActor`. A weak `AppState.shared` exists purely so App Intents can reach the live instance.
- **Services are actors**: `APIClient`, `TaskService`, `ProjectService`, `AuthService`, `NotificationService`, `SyncService`, `LabelService`, `CalendarService` are actors for thread safety. The exceptions are `FocusManager` and `FocusOutboxService`, which are `@MainActor @Observable` classes because they own SwiftData reads/writes on the main context and drive UI directly.
- **APIClient** (`Services/APIClient.swift`): Singleton actor. Uses `convertFromSnakeCase`/`convertToSnakeCase` key strategies. Custom date decoding handles ISO8601 with and without fractional seconds, plus Vikunja's zero-date (`0001-01-01T00:00:00Z` → `Date.distantPast`). It also owns JWT refresh: `setOnTokensUpdated` persists rotated tokens, `setOnSessionExpired` bounces the user to login.
- **Endpoint** (`Services/Endpoint.swift`): Static factory methods returning `Endpoint` structs with path, HTTP method, and query items. Vikunja API base path: `/api/v1/`. Add new endpoints here rather than building URLs inline.
- **Platform split**: iOS uses `MainTabView` (tab bar), macOS uses `MacContentView` (NavigationSplitView sidebar). Conditional compilation via `#if os(iOS)` / `#if os(macOS)`.
- **Auth**: Vikunja token in the Keychain (`AuthService`), server URL in UserDefaults. Login validates by fetching projects.
- **Offline support**: SwiftData models in `CacheService.swift` (`CachedTask`, `CachedProject`, `CachedLabel`, `FocusRecord`, `PendingOperation`), container built in `AppDependencies`, reconciled by `SyncService` when `NetworkMonitor` reports connectivity. Mutations made offline become `PendingOperation` rows and replay on reconnect.
- **Widgets**: the extension reads through `WidgetDataProvider` in `mDoneShared/`. Non-sensitive state goes in the app group's UserDefaults; the API token goes in `SharedTokenStore`, a keychain item shared via the app group ID (`group.com.mdone.app`) on iOS. Never put the token back in UserDefaults, which is cleartext on disk.
- **Focus**: `FocusManager` runs the session and its Live Activity, writing a `FocusRecord` per session. `FocusOutboxService` delivers undelivered records to an optional external focus service; `deliveredAt == nil` is the pending marker, so there is no separate queue table. `EstimateSuggester` turns past `FocusRecord` rows into "similar tasks took ~25m" suggestions and is deliberately pure and DB-free so it stays unit-testable.
- **Focus-service credentials are separate from Vikunja's**: `FocusSyncConfig` keeps its own URL (UserDefaults) and token (Keychain). Keep them apart so a leak of one cannot touch the other. A blank URL means the feature is off.
- **App Intents live in the app target** (`App/AppIntents.swift`). An intent with `openAppWhenRun = true` cannot run from an app extension: when these lived in the widget extension, every Shortcuts run failed with "an internal error occurred" (#121).

### Vikunja API Notes
- Task creation uses `PUT /api/v1/projects/{id}/tasks` (not POST)
- Task update uses `POST /api/v1/tasks/{id}` (not PUT)
- Vikunja's PUT/POST split is general: creates are `PUT`, updates are `POST`, for projects and labels too
- Per-project task and bucket reads go through a **view**: fetch `/projects/{id}/views` first, then `/projects/{id}/views/{viewId}/tasks` or `.../buckets`. The buckets response embeds each bucket's tasks, so one fetch renders a whole board.
- Relations: `PUT /api/v1/tasks/{id}/relations` to create, `DELETE /api/v1/tasks/{id}/relations/{kind}/{otherId}` to remove. Kinds are lowercase with no underscores (`parenttask`, `duplicateof`, ...) so they survive snake-case key conversion untouched.
- Filtering uses Vikunja DSL syntax, e.g. `"priority = 3 && due_date > now && done = false"`
- All IDs are `Int64`
- `docs/vikunja-api-inventory.md` lists what the API offers and what the app already uses. Check it before adding an endpoint.

## Changelog

Update `CHANGELOG.md` whenever making user-facing changes (features, fixes, UI changes). Add entries under the `[Unreleased]` section using Keep a Changelog categories: Added, Changed, Fixed, Removed. Keep entries concise and written from the user's perspective, and reference the issue number where there is one.

## Writing Style

No em-dashes anywhere: user-facing copy, changelog entries, code comments, docs, or PR descriptions. Use a comma, colon, or a separate sentence instead. Everything else follows the surrounding prose.

## Test Coverage

Code coverage is gathered by default: `gatherCoverageData: true` is set on both schemes in `project.yml`. Read coverage from any test run with `xcrun xccov view --report <path-to-.xcresult>`.

Apply tiered coverage targets by layer rather than chasing a single overall percentage:

| Layer | Target |
|---|---|
| Services (`mDone/Services/`) | 85%+ (never drop a service below 70% without a reason) |
| Models with logic (e.g. `VTask`) | 90%+ |
| `AppState` | 75%+ |
| Widgets (`mDoneShared/`, `mDoneWidgets/`) | 70%+ |
| SwiftUI views | no line-coverage target, use snapshot tests |

Rules of practice:
- New code in services, models, or `AppState` ships with tests in the same PR. Coverage-of-the-diff matters more than overall %.
- Verify a test file actually exercises its target with `xccov`: a file's existence isn't proof of coverage. `SyncServiceTests` once had 12 tests but only hit 3.78% of `SyncService` because it mocked the wrong layer.
- Don't pad the overall % with shallow view tests. SwiftUI view files at 0% line coverage are normal.
- If a service in a diff is below 70%, flag it as a good moment to add tests.

## Linting & Formatting

SwiftLint runs as a post-build script (configured in `project.yml`). Config in `.swiftlint.yml`, which notably disables `line_length`, `trailing_whitespace`, `type_body_length`, `file_length`, `function_body_length`, and `cyclomatic_complexity`.

SwiftFormat config in `.swiftformat`: 4-space indent, 120 max width, semicolons never.
