# Changelog

All notable changes to mDone will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Expanded unit test coverage for APIClient, TaskService, ProjectService, and SyncService
- MockURLProtocol test helper for network request testing without real API calls
- Tests for network error handling, token expiry, pagination, date decoding edge cases
- Tests for all VTask computed properties (isOverdue, isDueToday, isDueTomorrow, isDueThisWeek, repeatDescription)
- Tests for cached model round-trips, updates, and label preservation

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
