# Changelog

All notable changes to mDone will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
