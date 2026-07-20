# Changelog

All notable changes to mDone will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- The "Quick Add Task" action in the Shortcuts app now works. It opens mDone with the quick-add bar focused and ready to type. Previously the action always failed with "an internal error occurred" because it ran from the widget extension instead of the app (#121).
- Rescheduling a task via the long-press "Schedule" menu no longer drops it from the **Current** section until the next refresh (the same server-response quirk fixed for other edits in 1.7.0).

### Added
- **Subtasks**: tasks with subtasks now show them indented underneath in every list (Inbox sections, project lists, and the Mac task list), with a "2/5" progress badge on the parent row showing how many are done. Checking a subtask off updates the parent's count immediately (#1).
- Manage subtasks from a task's detail view: add a new subtask by typing its title, or tap "Link Existing Task" to pick any open task — searchable, from any project, with each task's project shown — and make it a subtask. Check subtasks off or unlink them (unlinking never deletes the task). Tasks that are subtasks also show their parent, and any other relations created in Vikunja (Blocked By, Precedes, Duplicates, …) are listed and can be removed (#1).
- "Quick Add Task" is now a proper App Shortcut: it appears automatically in the Shortcuts app, can be run by voice with Siri ("Add a task in mDone"), and works on Mac as well as iPhone.

### Removed
- The "Open Task" action no longer appears in the Shortcuts app. It never worked (it failed with the same internal error as Quick Add Task) and offered no way to pick a task, so it has been removed rather than left broken.

## [1.8.0] - 2026-07-13

### Added
- You can now choose how big tasks appear in your lists: Settings > Appearance > **Task row size** offers Compact, Standard, and Large. Compact shrinks the text and tightens the rows so more tasks fit on screen, Large makes them easier to read, and Standard keeps the app's original look (and stays the default). Applies to the Inbox, project lists, the calendar's day list, and the Mac task list, matching the size options the widgets already offer (#122).
- Projects now display as a hierarchy: sub-projects nest under their parent with an indent and an expand/collapse chevron, matching Vikunja's folder structure on the web. Both the iPhone project list and the Mac sidebar are sorted by each project's position (then name), so the ordering is stable instead of showing sub-projects jumbled at the top. Collapsed projects stay collapsed across app launches (#118).
- You can now build and rearrange that hierarchy from the app: pick a **Parent Project** when creating or editing a project, and **Move to…** a project under a different parent (or back to the top level) from its right-click / long-press menu. Options that would create a loop (moving a project under itself or one of its own sub-projects) are hidden (#118).
- Tasks now show the color you assign them in Vikunja. Each colored task tints its leading accent bar and completion circle with its hex color, so color-coded contexts (work, personal, clients) are visible at a glance in every list. Uncolored tasks are unchanged (#112).
- Long-press (or right-click) a task and pick "Schedule" to reschedule it to Today, Tomorrow, Later This Week, Next Week, or Next Month. These set an absolute due date (they ignore the task's current date, unlike the +24h swipe), and "Next Week" follows your "Start week on" preference (#67).

### Fixed
- The Vikunja API token shared with the widgets is now stored in the Keychain instead of the app group preferences, where it sat in cleartext on disk. Existing installs migrate automatically the next time the app or a widget runs, and the old cleartext copy is removed.
- Editing a sub-project (renaming it, changing its color, toggling favorite) no longer risks moving it back to the top level; the app now always sends the project's parent along with the edit (#118).

## [1.7.0] - 2026-06

### Added
- **Board view**: projects with a Kanban view now offer a board layout on iPhone. Switch between the list and the board with the toolbar button on a project. The board shows one column per Kanban bucket with each task as a card, and you can move a task to another column from its long-press menu (#55).
- **Current tasks**: mark a long-running task as "Current" to pin it to a dedicated section at the top of your Inbox, above Today, so slow-burn projects stay top of mind instead of sinking out of view. Each Current task shows a progress bar you can update (from its detail view, or quickly via the right-click / long-press menu), and an "Idle" badge appears when a Current task hasn't been touched for a while. Set how many idle days trigger the badge in Settings under "Current Tasks". Mark or unmark a task as Current from its context menu or detail view, on both iPhone and Mac.

### Fixed
- A task no longer briefly disappears from the **Current** section when you change its progress (or otherwise edit it). The task stayed gone until the next refresh because the server's update response omits labels; the app now keeps the task's labels through an edit.

## [1.6.2] - 2026-06-08

### Fixed
- The in-app "Buy Me a Coffee" support link now opens the correct page. The previous link pointed to a page that no longer exists.

## [1.6.1] - 2026-06-06

### Fixed
- Widget: the Today's Tasks and Upcoming widgets no longer let their header drift off the top (or clip the bottom rows) when there are more tasks than fit. This was most noticeable with larger text sizes. The header now stays pinned in place, the visible rows always fit the widget, and a "+N more" count fills the last line (#99).

## [1.6.0] - 2026-06-03

### Added
- Settings → Tasks → "Calm Mode" (off by default). When on, overdue tasks aren't singled out: no red due dates, no separate "Overdue" list or counts, and no red highlight in the widgets. Overdue tasks simply appear in Today alongside everything else, in the app and on widgets (#68).

## [1.5.0] - 2026-06-01

### Added
- Create, edit, archive, and delete projects directly in mDone — no more switching to the Vikunja web app. Tap **+** on the Projects tab (iOS) or next to "Projects" in the sidebar (macOS, ⌘⇧N) to add a project with a title, description, color, and favorite flag. Swipe or right-click any project to edit, archive, or delete it. Deleting warns that it permanently removes the project and all of its tasks (and any sub-projects) and offers to archive instead; archived projects move to a new **Archived** view where you can restore or permanently delete them (#92).

## [1.4.1] - 2026-06-01

### Added
- Settings → "About mDone" opens an About screen (iPhone and Mac) with the app version, a link to report bugs or request features, a link to the source on GitHub, and ways to support development (GitHub Sponsors and Buy Me a Coffee).

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
