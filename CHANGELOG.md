# Changelog

All notable changes to mDone will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.4.0] - 2026-05-29

### Added
- Shake your iPhone right after completing a task to undo it. mDone shows a confirmation prompt naming the task ("Undo completing "…"?") so an accidental shake never silently reverses anything, and only the most recent completion can be undone (#82).

## [1.3.1] - 2026-05-24

### Added
- Settings → Calendar → "Calendars in mDone" lets you choose which device calendars contribute events to mDone's Calendar and Today views. Turn off shared family or work calendars you don't want cluttering your task context; new calendars show by default until you hide them (#69).
- Settings → Tasks: "Default due time" picks the time of day applied to tasks you add to Today without typing a time (9 AM / noon / 5 PM / 6 PM / 9 PM / End of day). Defaults to 6 PM, matching Vikunja's web client (#81).

### Fixed
- Quick-adding a task on the Today list no longer makes it instantly overdue. Tasks added without an explicit time now use the configured default due time (6 PM by default) instead of midnight (#81).
- Date-only tasks (existing ones synced from Vikunja's web client at 00:00, or any task where the time wasn't specified) no longer render with the red overdue style on the day they're due. They count as overdue only after the end of that day, matching how a paper diary works (#81).
- Logging in with a Vikunja username and password no longer kicks you out after ~10 minutes. mDone now uses Vikunja 2.0's refresh-token cookie to renew your session in the background and only sends you back to the login screen if the refresh itself fails (#80). When that does happen, your server URL stays prefilled so you only have to re-enter your password.

### Fixed
- Edits to a task's description (and other fields) now appear immediately. Previously the task detail sheet would still show the old value until the app was force-quit and reopened, because `VTask` equality only compared by ID — SwiftUI saw "no change" and skipped re-rendering. The local SwiftData cache is also now written on every task mutation, so cold launches see the latest data even before the first refresh completes (#84).

## [1.3.0] - 2026-05-17

### Added
- Optional estimated duration for tasks. Add a quick estimate (15m / 30m / 1h / 2h / 4h presets, or a custom hours+minutes value) when creating a task in the Quick Add bar or later from the task detail screen (iOS and macOS). The estimate is stored inside the task's Vikunja description as an `<!-- mdone:estimate=N -->` marker, so AI agents and other API clients can read and set it directly without any mDone-specific endpoint. mDone hides the marker from previews and editors.
- As you type a new task title, mDone can suggest an estimate from how long similar tasks you've focused on actually took ("Similar tasks took ~25m"). The hint is offline, never auto-fills, and only fills the field if you tap it.
- Task detail screen shows total focus time and session count for tasks you've used the Focus Timer on (#61).
- Focus History Sync (Settings → iOS only): configure a focus-service URL and bearer token to sync completed focus sessions to your homelab service for cross-task analysis (#62). Blank URL keeps everything on-device. Pre-existing focus history is backfilled on first activation.
- Widget customisation: long-press the Today's Tasks or Upcoming widget and tap Edit Widget to choose font size (Compact / Standard / Large), pick what to show (Today + Overdue / Today only / Overdue only), toggle the tap-to-complete button, and toggle the "+" Add Task shortcut (#66).
- Small (1×1) and Extra Large (iPad) layouts for the Today's Tasks and Upcoming widgets (#66).
- "+" Add Task shortcut in the Today's Tasks and Upcoming widget headers — opens the app on the Inbox tab with the "Add a task…" field already focused so you can start typing immediately (#66). The Quick Add widget's tap behaviour follows the same flow.
- Settings → Appearance: "Start week on" lets you override the calendar's first day (System / Sunday / Monday / Saturday) (#60).

### Changed
- "Due This Week" filter chip is now labelled "Due in 7 Days" to match its actual behaviour (a rolling 7-day window from now).

### Fixed
- Widget: tasks whose due time has passed but were due today no longer appear twice — once in the overdue (red) section and once in the today list (#64).
- Widget: the "Today" header no longer creeps off the top of the medium widget when several tasks are showing — visible row counts are now tuned per widget size, and accessibility text sizes are capped so the layout stays inside the widget canvas (#66).
- Settings now displays the actual app version and build number instead of a hardcoded "1.0.0" (#65).
- Swiping a task left for +24h now updates the displayed due date instantly instead of waiting for the server to respond.
- Calendar: weekday header row (Mon/Tue/…) now correctly rotates to match the configured first day of the week (#60).
- Advanced Filter: applying a date range of Today / This Week / This Month no longer fails with "Something went wrong with that request" — the filter is now sent as an absolute date instead of a relative expression that the server mis-parsed.

## [1.1.2] - 2026-05-13

### Added
- Sort tasks by due date, priority, or title with ascending/descending toggle on iOS and macOS (#48)
- Expanded unit test coverage for APIClient, TaskService, ProjectService, and SyncService
- MockURLProtocol test helper for network request testing without real API calls
- Tests for network error handling, token expiry, pagination, date decoding edge cases
- Tests for all VTask computed properties (isOverdue, isDueToday, isDueTomorrow, isDueThisWeek, repeatDescription)
- Tests for cached model round-trips, updates, and label preservation
- Automatic retry with exponential backoff for transient API failures (timeouts, rate limits, server errors)

### Changed
- Error messages are now user-friendly with clear guidance instead of technical details
- Added error banner component that displays contextual icons, recovery suggestions, and retry actions
- Network, auth, and server errors are mapped to actionable messages (e.g., "You're offline. Your changes will sync when you're back online.")

### Fixed
- Task descriptions created in Vikunja's web UI now render as formatted text (lists, links, bold) instead of raw HTML markup; description preview is shown by default when a description is present (#56)
- Crash when opening a project whose tasks have duplicate `task_positions` rows on the Vikunja server; the duplicates are now ignored on the client (#54)
- macOS: Clicking a task in the Inbox now opens the detail view
- iOS: App no longer drops server connections when briefly switching to another app; in-flight requests now finish in the background (#49)
- App automatically refreshes data when returning to the foreground
- macOS: Calendar permission prompt now appears immediately after login instead of only when navigating to the Calendar tab
- Improved calendar privacy purpose string with a specific usage example per App Store guidelines
- macOS: Added missing calendars entitlement required for App Store sandbox compliance
- VoiceOver accessibility across all screens: added descriptive labels to interactive controls, task rows, calendar cells, focus timer, and notification bell
- Added accessibility grouping to task rows, project rows, notification rows, and empty states so VoiceOver reads them as coherent elements
- Added header traits to section headers and calendar month title
- Marked decorative elements (priority color bars, status dots, icons) as hidden from accessibility
- Replaced hardcoded font sizes with @ScaledMetric for Dynamic Type support in focus timer, empty states, and setup screen
- Replaced hardcoded notification badge font size with semantic .caption2 for Dynamic Type scaling
- Added toggle trait to task completion checkbox buttons
- Added selected trait to active filter chips and calendar day cells

## [1.1.0] - 2026-03-23

### Added
- Calendar integration: device calendar events shown alongside tasks in Inbox and Calendar views via EventKit
- Calendar events appear in the Calendar tab with colored accent bars, time ranges, and calendar names
- Calendar grid shows green dots on days with events
- macOS sidebar shows today's calendar event count badge
- Task list sections: Overdue, Today, Tomorrow, This Week, Upcoming, No Date
- Tasks added from Inbox default to today's due date
- Postpone +24h swipe action on task rows

### Changed
- Inbox uses compact inline navigation title to reduce wasted vertical space

### Fixed
- Project task cache staleness
- Live Activity black screen and switch race condition
- Hardcoded test credentials removed from screenshot tests (now uses .env.screenshot)

## [1.0.0] - 2026-03-15

### Added
- Native iOS and macOS app for Vikunja task management
- Home screen and lock screen widgets
- Repeating task support
- Search, offline sync, and drag-drop reordering
- Markdown rendering in task descriptions
- Notification support
- JWT login and token-based auth
- Live Activity for active tasks
- Quick add bar for fast task creation
- Task filtering (priority, due date, completion)
- Project-based task organization with color coding
- macOS app with NavigationSplitView sidebar layout
