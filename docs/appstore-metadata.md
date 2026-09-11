# App Store Metadata

## App Name

mDone

## Subtitle

Task manager for Vikunja

## Description

Take control of your tasks with mDone — a beautifully designed task manager built for your self-hosted Vikunja server.

If you run your own Vikunja instance and want a polished, native iOS experience to manage your tasks, mDone is made for you. A thoughtful, focused interface for your self-hosted productivity setup.

KEY FEATURES

Smart Lists
Stay on top of what matters. mDone organizes your tasks into smart views — Today, Upcoming, and Overdue — so you always know what to focus on next.

Current Tasks
Keep long-running work top of mind. Mark a task as Current and it stays pinned to its own section at the top of your list, above Today, with a progress bar you can update and a gentle idle nudge when it has sat untouched for too long. Perfect for slow-burn projects that would otherwise slip out of sight.

Projects & Favorites
Organize tasks into projects and mark the ones you use most as favorites for quick access from the sidebar.

Home Screen & Lock Screen Widgets
See your tasks at a glance without opening the app. Widgets show your upcoming tasks, today's agenda, and overdue items right on your home screen or lock screen.

Focus Timer with Live Activities
Use the built-in focus timer to work through your tasks with purpose. Live Activities keep your current timer visible on your lock screen and Dynamic Island.

Repeating Tasks
Set tasks to repeat on your schedule — daily, weekly, monthly, or custom intervals. Completed repeating tasks automatically generate their next occurrence.

Calendar View
Visualize your tasks across days and weeks with an integrated calendar view. Spot gaps, plan ahead, and stay balanced.

Offline Support
mDone caches your tasks locally so you can view and work with them even when you are offline. Changes sync back to your Vikunja server when connectivity is restored.

Privacy First
mDone contains zero analytics, zero tracking, and zero third-party SDKs. The app talks only to your Vikunja server — nothing else. Your data stays entirely under your control.

REQUIREMENTS
- A self-hosted Vikunja server (vikunja.io)
- An account on that server

mDone is open source. Visit the GitHub repository to report issues, request features, or contribute.

## Keywords

task,todo,vikunja,self-hosted,productivity,gtd,planner,widgets,focus,organizer

## Category

Productivity

## App Review Notes

mDone connects to a user-provided Vikunja server (an open-source, self-hosted task management platform). To test the app, you will need access to a Vikunja instance.

**Test server for review:**

- Server URL: https://vikunja-test.marcuslab.uk
- Username: applereview
- Password: AppReview2026!

Steps to test:

1. Launch the app. You will see a login screen.
2. Enter the server URL above and tap Connect.
3. Enter the username and password, then tap Log In.
4. You will see the main task list. You can:
   - Tap the + button to create a new task.
   - Swipe a task to complete or delete it.
   - Use the sidebar to navigate between projects and smart lists (Today, Upcoming, Overdue).
   - Open a task to edit its details, set a due date, or configure repeating.
   - Long-press a task (or open it) and choose "Mark as Current" to pin it to the new Current section at the top of the list, then update its progress from the task's detail view.
   - Try the focus timer from a task's detail view.
   - In a task's Labels section, tap "Add Labels" to put labels on it or take them off.
   - Sort a project by "Manual" (sort menu) and drag the handles to reorder tasks.
   - Add a widget from the home screen (long press > Edit Home Screen > tap +).
   - Say "Hey Siri, add a task in mDone" (the app can be closed). Siri asks for the task, adds it to the first project, and reads back where it went and when it is due. On a Mac, use the Shortcuts app's "Add Task" action for mDone.

This is a private test server maintained by the developer for App Store review purposes.

## What's New (v1.16.0)

Labels, manual ordering, two-factor login and an iPad detail pane.

- Add labels to a task and take them off again from the task's Labels section. Pick from every label on your server, or type a new name to create one and put it straight on the task.
- Sort a project by "Manual" and drag tasks into whatever order you like, on iPhone, iPad and Mac. It is the same order Vikunja's web app shows, and it leaves due dates alone.
- Drag Kanban cards up and down a column or into another column. Drop on the top half of a card to go above it, the bottom half to go below.
- Each project opens in the view you left it in, list or board, and a new setting picks the default for projects you have not switched.
- Sign in with a username and password on an account that uses two-factor authentication. A code field appears beside the password when your server supports it.
- On iPad, tasks open in a panel beside the list instead of a sheet. Escape cancels and Cmd-S saves from a hardware keyboard.
- Fixed single sign-on crashing the Mac app the moment your identity provider handed back to it.
- Fixed API tokens created without every permission being logged out on launch. The app now keeps you signed in and says which action the token cannot do.
- Fixed a wrong username or password showing a generic error instead of saying so.
- Fixed a task moved to another project sitting at the bottom of its new list until you came back.
- Available on both iPhone and Mac.

## What's New (v1.15.0)

Add tasks with Siri, hands-free.

- Say "Add a task in mDone" and Siri asks what the task is, adds it, and reads back where it went and when it is due, without opening the app. It works wherever Siri does, including in the car over CarPlay, on AirPods and on Apple Watch. Say "Add a task to Home in mDone" to choose a project. With no connection the task is kept and sent when you reconnect.
- Tasks added by voice are due today at your default due time (6:00 PM unless you change it). A new setting switches that to tomorrow or to no due date.
- On iPad the tab bar can expand into a sidebar, and hardware keyboards get shortcuts: Cmd-N for a new task, Cmd-R to refresh, Cmd-1 to Cmd-4 to switch sections.
- Notifications you have read now stay read after a restart.
- A damaged local database no longer stops the app from opening. Your unsynced edits and focus history are rescued and the cached tasks are rebuilt from your server.
- Groundwork for translations: all of the app's text is ready for its first languages.
- Available on both iPhone and Mac.

## What's New (v1.12.2)

Offline mode that actually works, plus an important data-loss fix.

- Your tasks, projects and labels are saved as you sync and appear the moment you open the app, even with no connection. mDone previously showed a loading spinner and then an empty list.
- When your server cannot be reached, mDone now says so clearly and shows your last synced tasks, instead of a generic error and a misleading empty list.
- Fixed a bug where completing, postponing or rescheduling a task, or changing its progress, could clear that task's description, priority and progress on your server.
- Available on both iPhone and Mac.

## What's New (v1.12.0)

Task date ranges, plus fixes for busy accounts.

- Give a task an optional start and end date from its detail view. Tasks spanning several days now appear on every included day in the calendar, so multi-day work stays visible.
- All of your projects and labels now load, not just the first 50. Larger accounts previously lost projects from the sidebar and pickers with no explanation.
- Kanban columns now show every card, and long project lists keep their order all the way down. Columns with more than 50 tasks previously stopped at 50.
- Available on both iPhone and Mac.

## What's New (v1.11.0)

Hide all-day calendar events, plus a Kanban fix.

- New setting to hide all-day calendar events: Settings > Calendar > "Show all-day events". Turn it off to keep day-long events out of your Calendar and Today views. It stays on by default, so nothing changes unless you flip it.
- The Kanban board shows your tasks again on current Vikunja servers (v0.24 and later). Columns previously loaded but sat empty.
- Available on both iPhone and Mac.

## What's New (v1.10.0)

Subtasks: break big tasks into steps.

- Tasks now show their subtasks nested underneath in every list, with a progress badge on the parent (e.g. 2/5 done).
- Add subtasks from a task's detail view, or link any existing task from any project as a subtask, with search.
- Tick subtasks off right from the parent task's detail view; the progress badge updates instantly.
- Relations created in Vikunja on the web (Blocked By, Precedes, Duplicates and more) now show on the task and can be removed.
- Available on both iPhone and Mac.

## What's New (v1.9.0)

Task row sizes, plus Shortcuts and Siri fixes.

- Choose how big tasks appear in your lists: Settings > Appearance > Task row size offers Compact, Standard, and Large.
- The "Quick Add Task" action in the Shortcuts app now works: it opens mDone with the quick-add bar ready to type. It previously failed with an internal error.
- Quick Add Task is now a proper App Shortcut, so it appears in the Shortcuts app automatically and works with Siri: just say "Add a task in mDone".
- Removed the broken "Open Task" action.
- Available on both iPhone and Mac.

## What's New (v1.8.0)

Project hierarchy: organise your projects into folders.

- Sub-projects now nest under their parent, indented and sorted, matching Vikunja on the web.
- Expand or collapse any project with a tap; it stays that way next time you open the app.
- Set a parent when creating or editing a project, or use "Move to…" to reorganise your hierarchy.
- Available on both iPhone and Mac.

## What's New (v1.7.0)

Current tasks: keep long-running work from slipping out of sight.

- Mark any task as Current to pin it to a dedicated section at the top of your list, above Today.
- Track momentum with a progress bar you can update from the task's detail view or a quick menu.
- An idle badge appears when a Current task has not been touched for a while, so slow-burn projects do not stall silently. Set the idle threshold in Settings.
- Available on both iPhone and Mac.

## What's New (v1.0.0)

Introducing mDone — a native iOS client for your self-hosted Vikunja server.

- Connect to any Vikunja server with your credentials
- Browse tasks with smart lists: Today, Upcoming, and Overdue
- Organize tasks into projects with favorites support
- Create, edit, complete, and delete tasks
- Set due dates and configure repeating tasks
- Focus timer with Live Activities and Dynamic Island support
- Home screen and lock screen widgets
- Calendar view for visualizing your schedule
- Offline support with automatic sync
- Secure authentication with Keychain storage
