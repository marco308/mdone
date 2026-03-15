# Self-Hosted TickTick Alternatives — Research

## Top Open Source Options

### 1. Vikunja — Closest TickTick Replacement

| Attribute | Details |
|---|---|
| **Tech Stack** | Go backend, Vue 3 + TypeScript frontend |
| **License** | AGPL-3.0 |
| **GitHub Stars** | ~3.6k |
| **Latest Release** | v2.1.0 (Feb 2026) |
| **Deploy** | Docker, native binaries, or Vikunja Cloud |

**Features:**
- Tasks with due dates, priorities, labels, reminders, subtasks
- Recurring tasks
- Multiple views: list, kanban, gantt, table
- CalDAV calendar integration
- REST API with Swagger docs (`/api/v1/docs`)
- Natural language quick-add
- Import from Todoist, Trello, Microsoft To-Do, TickTick
- Sharing via users, teams, or public links

**Missing:** No habit tracking, no built-in time tracking.

**Mobile:** No official native app, but CalDAV syncs to Tasks.org (Android) / Apple Reminders (iOS). See iOS section below.

---

### 2. Super Productivity — Best for Time Tracking + Native Mobile

| Attribute | Details |
|---|---|
| **Tech Stack** | Angular, Electron (desktop), Capacitor (mobile) |
| **License** | MIT |
| **GitHub Stars** | ~17.9k |
| **Deploy** | Docker with WebDAV backend |

**Features:**
- Tasks with due dates, priorities, tags, subtasks, recurring tasks
- Built-in Pomodoro timer and timeboxing
- Integrations: Jira, GitHub, GitLab, Trello, Linear
- Native Android + iOS apps
- Offline-first, no telemetry

**Missing:** No team features, no formal REST API, DIY sync (WebDAV/Dropbox).

---

### 3. Huly — Best All-in-One Team Platform

| Attribute | Details |
|---|---|
| **Tech Stack** | Svelte + TypeScript, Node.js, MongoDB |
| **License** | EPL-2.0 |
| **GitHub Stars** | ~25k |
| **Deploy** | Docker Compose (~35GB disk) |

**Features:**
- Replaces Linear + Slack + Notion + TickTick in one
- Tasks, chat, video calls, docs, CRM
- GitHub bidirectional sync
- Google Calendar integration

**Missing:** No mobile app, heavy resource requirements, overkill for personal use.

---

### Other Notable Options

| Project | Best For | Notes |
|---|---|---|
| **AppFlowy** | Notion alternative | 68.6k stars, Flutter + Rust, native mobile apps. Task management is secondary to docs. |
| **Planka** | Kanban boards | 11.7k stars, Trello replacement. Kanban only, no list view. |
| **Tasks.md** | Minimalists | 2.1k stars, Markdown-based. Intentionally barebones. |
| **Focalboard** | — | **Deprecated.** Mattermost abandoned it. Do not use. |
| **Nextcloud Tasks** | Nextcloud users | CalDAV-based, requires full Nextcloud instance. |
| **Taskwarrior** | CLI power users | Plain-text CLI, extremely scriptable. No GUI. |

---

## Feature Comparison Matrix

| Feature | Vikunja | Super Productivity | Huly | AppFlowy |
|---|---|---|---|---|
| Due Dates | Yes | Yes | Yes | Yes |
| Priorities | Yes | Yes | Yes | Yes |
| Tags/Labels | Yes | Yes | Yes | Yes |
| Recurring Tasks | Yes | Yes | Yes | Limited |
| Subtasks | Yes | Yes | Yes | Yes |
| Kanban Board | Yes | Yes | Yes | Yes |
| List View | Yes | Yes | Yes | Yes |
| Gantt Chart | Yes | No | Yes | No |
| Calendar Integration | CalDAV | CalDAV + Google | Google Cal | Yes |
| Time Tracking | No | Yes | Yes | No |
| REST API | Yes (Swagger) | Limited | Yes | Limited |
| Native Mobile App | No* | Yes | No | Yes |
| Offline Support | Via CalDAV | Yes | No | Yes |
| Docker Deploy | Yes | Yes | Yes | Yes |

*See iOS app section below.

---

## Recommendation: Vikunja

Vikunja is the clear winner for a self-hosted TickTick replacement. It covers ~85% of TickTick's core feature set, has a comprehensive REST API for CLI/automation integration, and is lightweight and easy to deploy.

---

## Vikunja iOS App Options

There is no official Vikunja iOS app, but three options exist:

### Existing Apps

1. **"Vikunja" by Noel Mayr** (App Store)
   - Closed-source, free, rated 4.6/5
   - Task CRUD, push notifications, offline mode, widgets, dark mode
   - Requires iOS 26+

2. **"Kuna"** (Open Source, GPL-3)
   - GitHub: `github.com/trykuna/app`
   - 97.5% Swift/SwiftUI
   - Bidirectional iOS Calendar sync via EventKit
   - Widget support, requires iOS 18.4+

3. **Official Flutter App** (Alpha)
   - GitHub: `github.com/go-vikunja/app`
   - MIT license, cross-platform
   - Alpha quality — "expect things to not work"

### Building a Custom iOS App

Vikunja's REST API (60+ endpoints, full OpenAPI/Swagger spec) makes building a native app very feasible.

**Architecture:**
- **API client**: Auto-generate from OpenAPI spec at `/api/v1/docs.json` using Apple's Swift OpenAPI Generator
- **Auth**: API tokens (`tk_` prefix, simplest) or JWT + refresh tokens for login flow. OIDC via `ASWebAuthenticationSession` for SSO.
- **Offline**: SwiftData or Core Data for local caching, sync via REST API
- **Notifications**: Poll `GET /api/v1/notifications` via BGTaskScheduler, or webhook-to-APNs relay for real-time push
- **Calendar**: EventKit for iOS Calendar sync (REST API, not CalDAV — CalDAV doesn't work on iOS with Vikunja)
- **Widgets**: WidgetKit for today/upcoming tasks

**Key API Endpoints:**
- `PUT /projects/{id}/tasks` — Create task
- `GET /tasks/all` — Get all tasks
- `POST /tasks/{id}` — Update task
- `GET /api/v1/notifications` — Poll notifications
- `PUT /projects` — Create project
- `GET /labels` — List labels
- Webhooks available for 20+ event types (task.created, task.updated, etc.)

**Recommendation:** Try Kuna first — it's open source Swift/SwiftUI and handles the hard parts (API integration, EventKit sync, widgets). Fork and customize if it's close. Build from scratch only if requirements diverge significantly.

---

## Gaps to Address

- **Habit tracking**: No open-source task manager has this. Consider BeaverHabits or HabitTrove as a companion tool, or build it as a custom feature.
- **Focus mode**: Not available in Vikunja. Would need to be built as part of the iOS app or as a separate feature.
- **CLI**: Vikunja has no official CLI. Would need to build one against the REST API, or use the community MCP server (`github.com/democratize-technology/vikunja-mcp`).
