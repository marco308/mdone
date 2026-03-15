# mDone — Feature Roadmap

27 open issues prioritized by impact. All tracked at [github.com/marco308/mdone/issues](https://github.com/marco308/mdone/issues).

---

## P1 — High / Must Have

| # | Issue | Description |
|---|-------|-------------|
| [#6](https://github.com/marco308/mdone/issues/6) | Add search and advanced filtering | Vikunja filter syntax with 9 operators, 26+ fields, date math, saved filters |
| [#8](https://github.com/marco308/mdone/issues/8) | Complete offline sync with pending operations | `PendingOperation` model defined but queue/replay not wired up |
| [#9](https://github.com/marco308/mdone/issues/9) | Add repeat task creation and editing | Display works but can't create/edit — need `repeat_after` and `repeat_mode` UI |
| [#12](https://github.com/marco308/mdone/issues/12) | Add markdown rendering for descriptions | Vikunja descriptions support markdown — currently plain text |
| [#14](https://github.com/marco308/mdone/issues/14) | Add task reminders (per-task) | `reminders` array with absolute/relative times — currently app-level only |
| [#15](https://github.com/marco308/mdone/issues/15) | Add in-app notifications display | `GET /notifications` endpoint exists — add bell icon with badge |
| [#23](https://github.com/marco308/mdone/issues/23) | Add drag-and-drop task reordering | `POST /tasks/{id}/position` with per-view positions |

## P2 — Medium / Important

| # | Issue | Description |
|---|-------|-------------|
| [#1](https://github.com/marco308/mdone/issues/1) | Add subtasks and task relations | 12 relation kinds (subtask, blocking, related, etc.) — fundamental to task workflows |
| [#2](https://github.com/marco308/mdone/issues/2) | Add task comments | Threaded comments with author, timestamps, `expand[]=comments` |
| [#3](https://github.com/marco308/mdone/issues/3) | Add file attachments | Upload/download files, cover images via `cover_image_attachment_id` |
| [#4](https://github.com/marco308/mdone/issues/4) | Add label assignment UI | Labels display but can't be assigned — requires dedicated endpoints |
| [#5](https://github.com/marco308/mdone/issues/5) | Add assignee display and assignment | `assignees` field fetched but never shown; add picker and avatars |
| [#7](https://github.com/marco308/mdone/issues/7) | Add Kanban board view | Buckets API exists; horizontal board with drag-and-drop |
| [#10](https://github.com/marco308/mdone/issues/10) | Add bulk task operations | Multi-select + `POST /tasks/bulk` for batch done/delete/move |
| [#11](https://github.com/marco308/mdone/issues/11) | Add progress/percent done display | `percentDone` field exists (0.0–1.0) — add progress bar |
| [#13](https://github.com/marco308/mdone/issues/13) | Add project hierarchy (nested projects) | `parentProjectId` exists — show collapsible groups in sidebar |
| [#16](https://github.com/marco308/mdone/issues/16) | Add task favorites | `isFavorite` field exists — add star toggle and Favorites smart list |
| [#17](https://github.com/marco308/mdone/issues/17) | Show start/end dates and date ranges | `startDate`/`endDate` fields exist — display in detail and calendar |

## P3 — Low / Nice to Have

| # | Issue | Description |
|---|-------|-------------|
| [#18](https://github.com/marco308/mdone/issues/18) | Add CalDAV integration | Sync with Apple Calendar/Reminders via `/dav/` |
| [#19](https://github.com/marco308/mdone/issues/19) | Add saved filters as virtual projects | Custom smart lists via `PUT /filters` (negative ID projects) |
| [#20](https://github.com/marco308/mdone/issues/20) | Add data import from other task apps | Import from Todoist, Trello, TickTick, Microsoft Todo |
| [#21](https://github.com/marco308/mdone/issues/21) | Add project backgrounds | Custom and Unsplash backgrounds |
| [#22](https://github.com/marco308/mdone/issues/22) | Add task duplicate | `PUT /tasks/{id}/duplicate` |
| [#24](https://github.com/marco308/mdone/issues/24) | Add project sharing | Share with users, teams, and link shares |
| [#25](https://github.com/marco308/mdone/issues/25) | Add webhook management | 22 event types, HMAC-SHA256 signing |
| [#26](https://github.com/marco308/mdone/issues/26) | Add task subscriptions (watch/unwatch) | Subscribe for notifications on task/project changes |
| [#27](https://github.com/marco308/mdone/issues/27) | Add emoji reactions | Reactions on tasks and comments |
