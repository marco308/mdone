# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

mDone is a native iOS/macOS task management app that connects to a self-hosted **Vikunja** server via its **v1** REST API (`/api/v1`, verified against Vikunja v2.5.0). Pure Swift with SwiftUI, no external dependencies. Vikunja 2.4.0 added a parallel `/api/v2` that upstream recommends for new clients; mDone has not migrated. See `docs/vikunja-api-inventory.md`.

Beyond plain task CRUD the app also covers: focus sessions with a Live Activity, Kanban boards, subtasks and task relations, calendar (EventKit) overlay, home/lock screen widgets, Shortcuts and Siri actions, and offline caching with a pending-operation queue.

## Build & Development

The project uses **XcodeGen** to generate the Xcode project from `project.yml`. The `.xcodeproj` is not committed, so generate it after any clone or target/settings change.

**Simulator destinations:** build-only invocations use `generic/platform=iOS Simulator`, which needs no simulator by that name to exist. Test runs have to name a concrete device, so they use the same one CI pins in `.github/workflows/ios-tests.yml` (`iPhone 17`). If you change one, change the other, and check `xcrun simctl list devices available` when a destination stops resolving after an Xcode update.

### Targets and schemes

`mDoneTests` and `mDoneMacTests` compile the **same** `mDoneTests/` sources against the iOS and macOS app respectively, so a shared service or model is covered on both platforms from one set of files. Cases that only make sense on iOS (Live Activity, focus outbox) guard themselves with `#if os(iOS)`. `mDone-macOS` pins `PRODUCT_MODULE_NAME: mDone` so the shared `@testable import mDone` resolves there too; without it the module would be `mDone_macOS` and every test file would fail to compile.

The iOS and macOS app targets compile the **same** `mDone/` + `mDoneShared/` sources, so anything platform-specific needs `#if os(iOS)` / `#if os(macOS)`.

`project.yml` pins a few settings that XcodeGen 2.45.4 stopped emitting (`PRODUCT_NAME`, `ENABLE_TESTABILITY` for Debug, `SDKROOT` for the iOS app). Do not remove them: builds and `@testable import mDone` break without them. The comments in the file explain each one.

### Local dev server

Never develop against a real Vikunja. Bring up a throwaway one on `http://localhost:3456`:

```bash
docker compose -f docker-compose.dev.yml up -d && ./scripts/seed-dev-vikunja.sh
```

Log in with `devuser` / `devpassword`. `./scripts/reset-dev-vikunja.sh` nukes and reseeds it. Full walkthrough, including the environments table (dev vs Apple Review test server vs prod), in [docs/dev-setup.md](docs/dev-setup.md).

- CI workflows and release tagging: see the `ci-release` skill.

## Architecture

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
- **Siri adds tasks in the background**: `AddTaskIntent` (`App/AddTaskIntent.swift`) has no `openAppWhenRun`, which is what lets it run over CarPlay, AirPods and the Watch, where there is no screen to hand to. It calls `AppState.createTaskFromIntent`, which signs in from the Keychain on a cold launch, reads projects from the cache, and queues the create when offline. The UI deliberately does not queue creates (#146); the intent does, because its caller cannot see the list and losing the task is worse. `ProjectEntity` gives Siri the project names; `refreshAll` calls `updateAppShortcutParameters()` after every project fetch so that vocabulary stays current. A CarPlay app proper is off the table: Apple only grants the entitlement to fixed categories that exclude task managers.

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

- Coverage targets and the xccov verification workflow: see the `test-coverage` skill.
