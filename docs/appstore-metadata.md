# App Store Metadata

## App Name

mDone

## Subtitle

Task manager for Vikunja

## Description

Take control of your tasks with mDone, a native task manager for iPhone, iPad and Mac, built for your self-hosted Vikunja server.

If you run your own Vikunja instance and want a polished, native way to manage your tasks, mDone is made for you: a thoughtful, focused interface for your self-hosted productivity setup.

KEY FEATURES

Quick Add That Understands You
Type "Buy milk tomorrow at 5pm +Home !2 *shopping" and mDone files it in the right project, with the due date, priority and label already set. Everything it picks up shows as a chip before you add the task, so nothing happens by surprise. Switch it on in Settings.

Smart Lists
Stay on top of what matters. Today, Upcoming and Overdue views organise your tasks, so you always know what to focus on next.

Current Tasks
Keep long-running work top of mind. Mark a task as Current and it stays pinned above Today, with a progress bar you can update and a gentle nudge when it has sat untouched for too long.

Kanban Boards
Open any project as a board. Drag cards between columns and reorder them, exactly as they appear in Vikunja's web app.

Subtasks, Checklists and Labels
Break big tasks into subtasks, link related tasks, tick off checklists written in a task's description, and add or create labels without leaving the app.

Projects and Favorites
Organise tasks into projects and sub-projects, sort them by date, priority or your own manual order, and keep the ones you use most one tap away.

Siri, Hands-Free
Say "Add a task in mDone" and Siri adds it without opening the app. Works over CarPlay, on AirPods and on Apple Watch.

Home Screen and Lock Screen Widgets
See your tasks at a glance: today's agenda, what is coming up, and anything overdue.

Focus Timer with Live Activities
Work through a task with purpose. Live Activities keep the timer on your Lock Screen and in the Dynamic Island.

Repeating Tasks
Daily, weekly, monthly or custom intervals. Completing a repeating task schedules its next occurrence.

Calendar View
See your tasks across days and weeks alongside your calendar events. Spot the gaps and plan ahead.

Offline Support
mDone caches your tasks so you can keep working without a connection. Changes sync back to your server when you are online again.

Privacy First
Zero analytics, zero tracking, zero third-party SDKs. mDone talks only to your Vikunja server, and your data stays entirely under your control.

Available in English and Simplified Chinese.

REQUIREMENTS
- A self-hosted Vikunja server (vikunja.io)
- An account on that server

mDone is open source. Visit the GitHub repository to report issues, request features, or contribute.

## Promotional Text

New: type a task the way you would say it. "Call Mum tomorrow at 6pm +Home !2" lands in the right project with the date and priority already set.

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
   - Open Settings > Tasks and set "Default project", then add a task from the Inbox to see it land there.
   - Turn on Settings > Tasks > "Smart parsing in quick add", then type "Call the dentist tomorrow at 3pm !3" in the Inbox's add-task field. Chips for the date and priority appear under the field before you add it.
   - Say "Hey Siri, add a task in mDone" (the app can be closed). Siri asks for the task, adds it to the first project, and reads back where it went and when it is due. On a Mac, use the Shortcuts app's "Add Task" action for mDone.

This is a private test server maintained by the developer for App Store review purposes.

## What's New (v1.19.0)

Type a task the way you would say it.

- New smart parsing for quick add. Type "Buy milk tomorrow at 5pm +Home !2 *shopping" and mDone files "Buy milk" in Home, due tomorrow at 5:00 PM, priority 2, labelled shopping.
- Each part mDone picks up shows as a chip under the field before you add the task. Tap a chip's X to keep those words in the title instead.
- Off by default: switch it on in Settings > Tasks > "Smart parsing in quick add".
- On the Mac, the New Task window fills in the project, due date and priority as you type.
- Siri and Shortcuts understand it too: say a date, a project or a priority and the task lands where you meant.
- Understands Chinese dates as well, such as 明天下午3点 or 下周.
- Available on both iPhone and Mac.

## What's New (v1.18.0)

Simplified Chinese, and a say in where new tasks land.

- mDone is now available in Simplified Chinese (简体中文), including the widgets and the system permission prompts. It follows your device language, so there is nothing to switch on.
- A new "Default project" setting picks where a task goes when you add it from the Inbox, ask Siri, or use the Mac's New Task window, instead of whichever project happened to be listed first.
- "Inbox adds tasks due" sets whether a task typed into the Inbox is due today, tomorrow, or not at all.
- Projects you have not given a colour now show a hollow marker in the Projects tab and the Mac sidebar, so they no longer look like projects you deliberately coloured blue.
- Each event dot on the calendar's month view now uses its own calendar's colour, so days with events from different calendars are easy to tell apart.
- Fixed a saved filter opened from the Projects tab coming back empty in the list view. Its matching tasks now show there as well as on the board.
- Available on both iPhone and Mac.

## What's New (v1.17.0)

Checklists inside task descriptions.

- A description written in Vikunja's web editor can hold a list of checkboxes, for the steps of a task that is not one and done. They used to show as plain bullets with no sign of what was ticked. Each item now has a checkbox you can tap to tick or untick, saved straight away as in the web app, with a "2 of 3 done" line and progress bar above the list.
- Task rows and Kanban cards show the same count, so you can see how far along a task is without opening it.
- A tick the server refuses to save goes back to unticked, with the usual error message, so a tick you can see is a tick that was saved.
- Available on both iPhone and Mac.

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
