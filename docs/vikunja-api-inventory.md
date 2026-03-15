# Vikunja v2.1.0 REST API -- Complete Inventory

> Compiled 2026-03-15 from OpenAPI spec, source code (routes.go, models/*.go, events.go), and official documentation.
> Base path: `/api/v1`
> Auth: `Authorization: Bearer <token>` (API token or JWT)
> Pagination headers: `x-pagination-total-pages`, `x-pagination-result-count`
> Permission header: `x-max-permission` (0=Read, 1=Read&Write, 2=Admin) on single-item responses

---

## 1. Tasks

### 1.1 Task CRUD

| Method | Path | Description |
|--------|------|-------------|
| PUT | `/projects/:project/tasks` | Create a task in a project |
| GET | `/tasks/:projecttask` | Get a single task by ID |
| POST | `/tasks/:projecttask` | Update a task |
| DELETE | `/tasks/:projecttask` | Delete a task |
| GET | `/tasks` | Get ALL tasks across all projects (with filtering) |
| GET | `/projects/:project/views/:view/tasks` | Get tasks in a project view (supports filtering, sorting, pagination) |
| GET | `/projects/:project/tasks` | Get tasks in a project (without view context) |
| POST | `/tasks/bulk` | Bulk update multiple tasks |
| PUT | `/tasks/:projecttask/duplicate` | Duplicate a task |

### 1.2 Task Model Fields

All JSON field names (snake_case):

| Field | Type | Description |
|-------|------|-------------|
| `id` | int64 | Unique numeric ID |
| `title` | string | Task title (required, min 1 char) |
| `description` | string | Task description (longtext, supports markdown) |
| `done` | bool | Whether task is completed |
| `done_at` | datetime | When task was marked done (system-controlled) |
| `due_date` | datetime | When the task is due |
| `start_date` | datetime | When the task starts |
| `end_date` | datetime | When the task ends |
| `priority` | int64 | Priority level (arbitrary integer) |
| `percent_done` | float64 | Progress 0.0-1.0 |
| `hex_color` | string | Color in hex (max 7 chars) |
| `repeat_after` | int64 | Recurrence interval in seconds |
| `repeat_mode` | int | 0=fixed interval, 1=monthly, 2=from current date |
| `project_id` | int64 | Parent project ID |
| `index` | int64 | Sequential index within project |
| `identifier` | string | Human-readable identifier (computed: project-prefix + index) |
| `position` | float64 | Sort position (per view) |
| `bucket_id` | int64 | Current kanban bucket (only when accessed via view) |
| `cover_image_attachment_id` | int64 | Attachment ID used as cover image |
| `is_favorite` | bool | Whether user has favorited this task |
| `is_unread` | bool (optional) | Unread status (only with expand=is_unread) |
| `assignees` | [User] | Array of assigned users |
| `labels` | [Label] | Array of labels (read-only on task; use label endpoints) |
| `reminders` | [TaskReminder] | Array of reminders |
| `related_tasks` | map[RelationKind][Task] | Related tasks grouped by relation kind |
| `attachments` | [TaskAttachment] | File attachments (read-only on task; use attachment endpoints) |
| `buckets` | [Bucket] (optional) | Buckets across views (only with expand=buckets) |
| `comments` | [TaskComment] (optional) | Comments (only with expand=comments) |
| `comment_count` | int64 (optional) | Comment count (only with expand=comment_count) |
| `reactions` | ReactionMap | Emoji reactions |
| `subscription` | Subscription (optional) | User's subscription to this task |
| `created_by` | User | Creator user object |
| `created` | datetime | Creation timestamp |
| `updated` | datetime | Last update timestamp |

### 1.3 Task Query Parameters (for list endpoints)

| Parameter | Type | Description |
|-----------|------|-------------|
| `s` | string | Text search (incompatible with `filter`) |
| `sort_by` / `sort_by[]` | string | Field(s) to sort by (comma-separated or array) |
| `order_by` / `order_by[]` | string | `asc` or `desc` per sort field |
| `filter` | string | Filter query string (see Section 14) |
| `filter_timezone` | string | Timezone for date comparisons |
| `filter_include_nulls` | bool | Include null values in filter results |
| `expand[]` | string | Expand related data. Values: `subtasks`, `buckets`, `reactions`, `comments`, `comment_count`, `is_unread` |
| `page` | int | Page number |
| `per_page` | int | Items per page |

### 1.4 Task Comments

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tasks/:task/comments` | List all comments on a task |
| PUT | `/tasks/:task/comments` | Create a comment |
| GET | `/tasks/:task/comments/:commentid` | Get a specific comment |
| POST | `/tasks/:task/comments/:commentid` | Update a comment |
| DELETE | `/tasks/:task/comments/:commentid` | Delete a comment |

**TaskComment fields:** `id`, `comment` (text), `author` (User), `reactions` (ReactionMap), `created`, `updated`

### 1.5 Task Attachments

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tasks/:task/attachments` | List all attachments |
| PUT | `/tasks/:task/attachments` | Upload attachment (multipart form) |
| GET | `/tasks/:task/attachments/:attachment` | Download an attachment |
| DELETE | `/tasks/:task/attachments/:attachment` | Delete an attachment |

**TaskAttachment fields:** `id`, `task_id`, `file` (File object with `name`, `size`, `mime`, etc.), `created_by` (User), `created`

Cover image: Set via `cover_image_attachment_id` on the task update endpoint.

### 1.6 Task Relations

| Method | Path | Description |
|--------|------|-------------|
| PUT | `/tasks/:task/relations` | Create a task relation |
| DELETE | `/tasks/:task/relations/:relationKind/:otherTask` | Delete a relation |

**TaskRelation fields:** `task_id`, `other_task_id`, `relation_kind`, `created_by` (User), `created`

**Available Relation Kinds:**
- `subtask` / `parenttask` -- parent-child hierarchy
- `related` -- general relation
- `duplicateof` / `duplicates` -- duplicate tracking
- `blocking` / `blocked` -- dependency blocking
- `precedes` / `follows` -- sequential ordering
- `copiedfrom` / `copiedto` -- copy tracking

Relations are bidirectional: creating subtask(A->B) also creates parenttask(B->A).

### 1.7 Task Positions

| Method | Path | Description |
|--------|------|-------------|
| POST | `/tasks/:task/position` | Update task position within a view |

**TaskPosition fields:** `position` (float64), `project_view_id` (int64)

Positions are per-view. When sorting by position, you must be within a view context.

### 1.8 Task Bucket Assignment (Kanban)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/projects/:project/views/:view/buckets/:bucket/tasks` | Move a task to a bucket in a view |

**TaskBucket fields:** `task_id`, `bucket_id`, `project_view_id`

### 1.9 Task Unread Status

| Method | Path | Description |
|--------|------|-------------|
| POST | `/tasks/:projecttask/read` | Mark task as read/unread |

---

## 2. Projects

### 2.1 Project CRUD

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects` | List all projects user has access to |
| PUT | `/projects` | Create a new project |
| GET | `/projects/:project` | Get a single project |
| POST | `/projects/:project` | Update a project |
| DELETE | `/projects/:project` | Delete a project |
| PUT | `/projects/:projectid/duplicate` | Duplicate a project |

Query params for listing: `page`, `per_page`, `s` (search), `is_archived` (bool), `expand` (`permissions`)

### 2.2 Project Model Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | int64 | Unique ID |
| `title` | string | Project title (required, max 250) |
| `description` | string | Project description |
| `identifier` | string | Short identifier for task prefixes (max 10) |
| `hex_color` | string | Color in hex |
| `parent_project_id` | int64 | Parent project ID (for hierarchy) |
| `owner` | User | Project owner |
| `is_archived` | bool | Whether archived |
| `is_favorite` | bool | Whether user has favorited |
| `position` | float64 | Sort position |
| `views` | [ProjectView] | Array of views (list, kanban, gantt, table) |
| `background_information` | object | Background metadata (if set) |
| `background_blur_hash` | string | BlurHash preview of background |
| `subscription` | Subscription | User's subscription status |
| `max_permission` | int | Permission level on this project |
| `created` | datetime | Creation timestamp |
| `updated` | datetime | Last update timestamp |

### 2.3 Project Views

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/:project/views` | List all views for a project |
| GET | `/projects/:project/views/:view` | Get a single view |
| PUT | `/projects/:project/views` | Create a new view |
| POST | `/projects/:project/views/:view` | Update a view |
| DELETE | `/projects/:project/views/:view` | Delete a view |

**ProjectView fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | int64 | Unique ID |
| `title` | string | View title |
| `project_id` | int64 | Parent project |
| `view_kind` | string | `list`, `gantt`, `table`, or `kanban` |
| `filter` | TaskCollection | Filter query for this view |
| `position` | float64 | Sort position among views |
| `bucket_configuration_mode` | string | `none`, `manual`, or `filter` |
| `bucket_configuration` | [BucketConfig] | Config when mode is `filter` |
| `default_bucket_id` | int64 | Bucket for new tasks |
| `done_bucket_id` | int64 | Bucket for completed tasks |
| `created` | datetime | Creation timestamp |
| `updated` | datetime | Last update timestamp |

### 2.4 Project Sharing -- Users

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/:project/users` | List users with access |
| PUT | `/projects/:project/users` | Share project with a user |
| POST | `/projects/:project/users/:user` | Update user permission |
| DELETE | `/projects/:project/users/:user` | Remove user access |
| GET | `/projects/:project/projectusers` | List users (without emails, for autocomplete) |

**ProjectUser fields:** `id`, `user_id`, `project_id`, `permission` (0=Read, 1=Read&Write, 2=Admin), `created`, `updated`

### 2.5 Project Sharing -- Teams

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/:project/teams` | List teams with access |
| PUT | `/projects/:project/teams` | Share project with a team |
| POST | `/projects/:project/teams/:team` | Update team permission |
| DELETE | `/projects/:project/teams/:team` | Remove team access |

**TeamProject fields:** `id`, `team_id`, `project_id`, `permission` (0/1/2), `created`, `updated`

### 2.6 Project Sharing -- Link Shares

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/:project/shares` | List all link shares |
| GET | `/projects/:project/shares/:share` | Get a specific link share |
| PUT | `/projects/:project/shares` | Create a link share |
| DELETE | `/projects/:project/shares/:share` | Delete a link share |
| POST | `/shares/:share/auth` | Authenticate with a link share (unauthenticated) |

**LinkSharing fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | int64 | Unique ID |
| `hash` | string | Public share hash (40 chars) |
| `name` | string | Display name for the link share |
| `permission` | int | 0=Read, 1=Read&Write, 2=Admin |
| `sharing_type` | int | 0=undefined, 1=without password, 2=with password |
| `password` | string | Password (write-only) |
| `shared_by` | User | User who created the share |
| `created` | datetime | Creation timestamp |
| `updated` | datetime | Last update timestamp |

### 2.7 Project Backgrounds

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/:project/background` | Get project background image |
| DELETE | `/projects/:project/background` | Remove project background |
| PUT | `/projects/:project/backgrounds/upload` | Upload a custom background |
| POST | `/projects/:project/backgrounds/unsplash` | Set an Unsplash photo as background |
| GET | `/backgrounds/unsplash/search` | Search Unsplash for backgrounds (params: `s`, `p`) |
| GET | `/backgrounds/unsplash/images/:image` | Proxy an Unsplash image |
| GET | `/backgrounds/unsplash/images/:image/thumb` | Proxy an Unsplash thumbnail |

---

## 3. Labels

### 3.1 Label CRUD

| Method | Path | Description |
|--------|------|-------------|
| GET | `/labels` | List all labels user has access to |
| PUT | `/labels` | Create a label |
| GET | `/labels/:label` | Get a single label |
| POST | `/labels/:label` | Update a label |
| DELETE | `/labels/:label` | Delete a label |

Query params: `page`, `per_page`, `s` (search)

**Label fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | int64 | Unique ID |
| `title` | string | Label title (required, max 250) |
| `description` | string | Label description |
| `hex_color` | string | Color in hex |
| `created_by` | User | Creator |
| `created` | datetime | Creation timestamp |
| `updated` | datetime | Last update timestamp |

### 3.2 Task-Label Associations

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tasks/:projecttask/labels` | List labels on a task |
| PUT | `/tasks/:projecttask/labels` | Add a label to a task (body: `{"label_id": 1}`) |
| DELETE | `/tasks/:projecttask/labels/:label` | Remove a label from a task |
| POST | `/tasks/:projecttask/labels/bulk` | Bulk set labels on a task |

NOTE: Labels cannot be added/removed via the task update endpoint. You MUST use these dedicated endpoints.

Bulk label body: `{"labels": [{"id": 1}, {"id": 2}]}` -- replaces all labels on the task.

---

## 4. Buckets / Kanban

### 4.1 Bucket CRUD

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/:project/views/:view/buckets` | List buckets in a view |
| PUT | `/projects/:project/views/:view/buckets` | Create a bucket |
| POST | `/projects/:project/views/:view/buckets/:bucket` | Update a bucket |
| DELETE | `/projects/:project/views/:view/buckets/:bucket` | Delete a bucket |

**Bucket fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | int64 | Unique ID |
| `title` | string | Bucket title (required) |
| `project_view_id` | int64 | View this bucket belongs to |
| `limit` | int64 | Max tasks allowed (0 = unlimited) |
| `count` | int64 | Current task count (read-only) |
| `position` | float64 | Sort position |
| `created_by` | User | Creator |
| `created` | datetime | Creation timestamp |
| `updated` | datetime | Last update timestamp |

### 4.2 Moving Tasks Between Buckets

| Method | Path | Description |
|--------|------|-------------|
| POST | `/projects/:project/views/:view/buckets/:bucket/tasks` | Move a task into this bucket |

Body: `{"task_id": 123}` -- moves the task from its current bucket to the specified bucket within the same view.

### 4.3 Bucket Configuration on Views

Views with `bucket_configuration_mode` = `manual` allow drag-and-drop between buckets. Views with `bucket_configuration_mode` = `filter` auto-create buckets from filter expressions (configured in `bucket_configuration` array).

The `default_bucket_id` on a view determines where new tasks go. The `done_bucket_id` determines which bucket tasks move to when marked done (and vice versa).

---

## 5. Filters / Saved Views

### 5.1 Saved Filter CRUD

| Method | Path | Description |
|--------|------|-------------|
| PUT | `/filters` | Create a saved filter |
| GET | `/filters/:filter` | Get a saved filter |
| POST | `/filters/:filter` | Update a saved filter |
| DELETE | `/filters/:filter` | Delete a saved filter |

**SavedFilter fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | int64 | Unique ID |
| `title` | string | Filter title (required, max 250) |
| `description` | string | Filter description |
| `filters` | TaskCollection | The filter/sort/search configuration |
| `is_favorite` | bool | Whether favorited |
| `owner` | User | Creator |
| `created` | datetime | Creation timestamp |
| `updated` | datetime | Last update timestamp |

Saved filters appear as virtual projects with negative IDs (calculated as `-(filterID + 1)`). They can be used anywhere a project ID is expected for task listing.

---

## 6. Users

### 6.1 User Profile & Settings

| Method | Path | Description |
|--------|------|-------------|
| GET | `/user` | Get current user profile |
| GET | `/users` | Search/list users |
| POST | `/user/password` | Change password |
| POST | `/user/settings/email` | Update email address |
| POST | `/user/settings/general` | Update general settings |
| GET | `/user/settings/avatar` | Get avatar provider setting |
| POST | `/user/settings/avatar` | Change avatar provider |
| PUT | `/user/settings/avatar/upload` | Upload custom avatar image |
| GET | `/avatar/:username` | Get user's avatar image |

**User settings include:** `email_reminders_enabled`, `discoverable_by_name`, `discoverable_by_email`, `overdue_tasks_reminders_enabled`, `overdue_tasks_reminders_time`, `default_project_id`, `week_start`, `timezone`, `language`, `frontend_settings` (JSON blob for UI preferences)

**Avatar providers:** `gravatar`, `upload`, `initials`, `marble`

### 6.2 Authentication

| Method | Path | Description |
|--------|------|-------------|
| POST | `/login` | Login with username/password, returns JWT |
| POST | `/user/token` | Renew JWT token |
| POST | `/user/token/refresh` | Refresh token (uses cookie, unauthenticated) |
| POST | `/user/logout` | Logout / invalidate session |
| GET | `/token/test` | Test if token is valid |
| POST | `/token/test` | Check token validity |
| POST | `/register` | Register a new user |
| POST | `/user/confirm` | Confirm email address |
| POST | `/user/password/token` | Request password reset token |
| POST | `/user/password/reset` | Reset password with token |
| POST | `/auth/openid/:provider/callback` | OpenID Connect callback |

### 6.3 Two-Factor Authentication (TOTP)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/user/settings/totp` | Get TOTP status |
| POST | `/user/settings/totp/enroll` | Enroll in TOTP |
| POST | `/user/settings/totp/enable` | Enable TOTP (with passcode verification) |
| POST | `/user/settings/totp/disable` | Disable TOTP |
| GET | `/user/settings/totp/qrcode` | Get TOTP QR code image |

### 6.4 CalDAV Tokens

| Method | Path | Description |
|--------|------|-------------|
| GET | `/user/settings/token/caldav` | List CalDAV tokens |
| PUT | `/user/settings/token/caldav` | Generate a new CalDAV token |
| DELETE | `/user/settings/token/caldav/:id` | Delete a CalDAV token |

### 6.5 Sessions

| Method | Path | Description |
|--------|------|-------------|
| GET | `/user/sessions` | List active sessions |
| DELETE | `/user/sessions/:session` | Revoke a session |

### 6.6 API Tokens

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tokens` | List all API tokens |
| PUT | `/tokens` | Create a new API token |
| DELETE | `/tokens/:token` | Delete an API token |

**APIToken fields:** `id`, `title`, `permissions` (map of route groups to allowed methods), `expires_at`, `last_used_at`, `created`

### 6.7 Account Deletion

| Method | Path | Description |
|--------|------|-------------|
| POST | `/user/deletion/request` | Request account deletion |
| POST | `/user/deletion/confirm` | Confirm deletion |
| POST | `/user/deletion/cancel` | Cancel pending deletion |

### 6.8 Data Export

| Method | Path | Description |
|--------|------|-------------|
| POST | `/user/export/request` | Request a full data export |
| POST | `/user/export/download` | Download the export |
| GET | `/user/export` | Get export status |

### 6.9 Teams

| Method | Path | Description |
|--------|------|-------------|
| GET | `/teams` | List all teams |
| PUT | `/teams` | Create a team |
| GET | `/teams/:team` | Get a single team |
| POST | `/teams/:team` | Update a team |
| DELETE | `/teams/:team` | Delete a team |
| PUT | `/teams/:team/members` | Add a member to a team |
| DELETE | `/teams/:team/members/:user` | Remove a member |
| POST | `/teams/:team/members/:user/admin` | Toggle admin status for a member |

---

## 7. Notifications

| Method | Path | Description |
|--------|------|-------------|
| GET | `/notifications` | Get all notifications (paginated) |
| POST | `/notifications/:notificationid` | Mark a notification as read/unread |
| POST | `/notifications` | Mark ALL notifications as read |

Query params: `page`, `per_page`

**DatabaseNotification fields:** `id`, `name` (event name), `notification` (payload), `read`, `read_at`, `created`

---

## 8. Subscriptions

| Method | Path | Description |
|--------|------|-------------|
| PUT | `/subscriptions/:entity/:entityID` | Subscribe to an entity |
| DELETE | `/subscriptions/:entity/:entityID` | Unsubscribe from an entity |

**Entity types:** `project`, `task`

When subscribed, you receive notifications for changes to that entity. Project subscriptions are inherited by tasks within the project unless overridden.

**Subscription fields:** `id`, `entity` (string), `entity_id`, `created`

---

## 9. Webhooks

### 9.1 Project-Level Webhooks

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/:project/webhooks` | List webhooks for a project |
| PUT | `/projects/:project/webhooks` | Create a webhook |
| POST | `/projects/:project/webhooks/:webhook` | Update a webhook (events only) |
| DELETE | `/projects/:project/webhooks/:webhook` | Delete a webhook |

### 9.2 User-Level Webhooks

| Method | Path | Description |
|--------|------|-------------|
| GET | `/user/settings/webhooks` | List user-level webhooks |
| PUT | `/user/settings/webhooks` | Create a user-level webhook |
| POST | `/user/settings/webhooks/:webhook` | Update a user-level webhook |
| DELETE | `/user/settings/webhooks/:webhook` | Delete a user-level webhook |
| GET | `/user/settings/webhooks/events` | List available user-directed events |

### 9.3 Available Events Endpoint

| Method | Path | Description |
|--------|------|-------------|
| GET | `/webhooks/events` | List ALL available webhook event names |

### 9.4 Webhook Model Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | int64 | Unique ID |
| `target_url` | string | POST target URL (required) |
| `events` | [string] | Array of event names to listen for (required) |
| `project_id` | int64 | Project scope (null for user-level) |
| `user_id` | int64 | User scope (null for project-level) |
| `secret` | string | HMAC-SHA256 signing secret (optional) |
| `basic_auth_user` | string | Basic Auth username (optional) |
| `basic_auth_password` | string | Basic Auth password (optional) |
| `created_by` | User | Creator |
| `created` | datetime | Creation timestamp |
| `updated` | datetime | Last update timestamp |

### 9.5 All Webhook Events (from source: events.go)

**Task Events:**
- `task.created` -- Task created (payload: task, doer)
- `task.updated` -- Task updated (payload: task, doer)
- `task.deleted` -- Task deleted (payload: task, doer)
- `task.assignee.created` -- User assigned to task (payload: task, assignee, doer)
- `task.assignee.deleted` -- User unassigned (payload: task, assignee, doer)
- `task.comment.created` -- Comment added (payload: task, comment, doer)
- `task.comment.edited` -- Comment edited (payload: task, comment, doer)
- `task.comment.deleted` -- Comment deleted (payload: task, comment, doer)
- `task.attachment.created` -- Attachment uploaded (payload: task, attachment, doer)
- `task.attachment.deleted` -- Attachment removed (payload: task, attachment, doer)
- `task.relation.created` -- Relation added (payload: task, relation, doer)
- `task.relation.deleted` -- Relation removed (payload: task, relation, doer)

**Project Events:**
- `project.created` -- Project created (payload: project, doer)
- `project.updated` -- Project updated (payload: project, doer)
- `project.deleted` -- Project deleted (payload: project, doer)
- `project.shared.user` -- Project shared with user (payload: project, user, doer)
- `project.shared.team` -- Project shared with team (payload: project, team, doer)

**Team Events:**
- `team.created` -- Team created (payload: team, doer)
- `team.deleted` -- Team deleted (payload: team, doer)
- `team.member.added` -- Member added to team (payload: team, member, doer)
- `team.member.removed` -- Member removed from team (payload: team, member, doer)

**Webhook Payload Format:**
```json
{
  "event_name": "task.created",
  "time": "2024-01-01T00:00:00Z",
  "data": {
    "task": { ... },
    "doer": { ... }
  }
}
```

Signing: When a `secret` is set, the `X-Vikunja-Signature` header contains HMAC-SHA256 of the raw JSON body.

Delivery: Webhooks are delivered once via POST. Failed deliveries (HTTP >= 400 or timeout) are NOT retried.

---

## 10. CalDAV

CalDAV is accessed via Basic Authentication at separate endpoints (NOT the `/api/v1` prefix):

| Path | Description |
|------|-------------|
| `/.well-known/caldav` | CalDAV discovery endpoint |
| `/dav/` | CalDAV entry point |
| `/dav/principals/*/` | Principal handler (user discovery) |
| `/dav/projects/` | List all projects as calendars |
| `/dav/projects/:project/` | Single project as calendar |
| `/dav/projects/:project/:task` | Single task as VTODO |

**Supported VTODO Properties:** `UID`, `SUMMARY`, `DESCRIPTION`, `PRIORITY`, `CATEGORIES`, `COMPLETED`, `DUE`, `DURATION`, `DTSTAMP`, `DTSTART`, `VALARM` (reminders), `RELATED-TO` (relations), `RRULE` (recurrence, one-way only)

**Unsupported:** `ATTACH`, `CLASS`, `COMMENT`, `CONTACT`, `GEO`, `LOCATION`, `ORGANIZER`, `PERCENT-COMPLETE`, `RECURRENCE-ID`, `RESOURCES`, `SEQUENCE`, `URL`

**Compatible clients:** DAVx5, Tasks.org (Android), OpenTasks, Evolution, Korganizer
**Known incompatible:** Thunderbird (older), iOS CalDAV (partial -- iOS Reminders may work via DAVx5)

CalDAV tokens are managed via `/user/settings/token/caldav` endpoints (see Section 6.4).

---

## 11. Reminders

Reminders are set as part of the task object when creating/updating tasks. They are an array on the `reminders` field.

**TaskReminder fields:**

| Field | Type | Description |
|-------|------|-------------|
| `reminder` | datetime | Absolute reminder time |
| `relative_period` | int64 | Seconds relative to a date field. Negative = before. |
| `relative_to` | string | Which date field: `due_date`, `start_date`, or `end_date` |

**Two modes:**
1. **Absolute:** Set `reminder` to a specific datetime. `relative_period` and `relative_to` are null.
2. **Relative:** Set `relative_period` (e.g., -3600 for 1 hour before) and `relative_to` (e.g., `due_date`). The `reminder` field is auto-computed and updated when the referenced date changes.

When a repeating task is completed, all relative reminders are recalculated based on the new dates.

Internal events: `task.reminder.fired` (used for notifications)

---

## 12. Assignees

### 12.1 Task Assignee Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tasks/:projecttask/assignees` | List assignees on a task |
| PUT | `/tasks/:projecttask/assignees` | Add an assignee (body: `{"user_id": 1}`) |
| DELETE | `/tasks/:projecttask/assignees/:user` | Remove an assignee |
| POST | `/tasks/:projecttask/assignees/bulk` | Bulk set assignees |

Bulk assignee body: `{"assignees": [{"id": 1}, {"id": 2}]}` -- replaces all assignees.

---

## 13. Attachments

See Section 1.5 for task attachment endpoints.

**File upload:** `PUT /tasks/:task/attachments` with `multipart/form-data`, field name: `files`

**File download:** `GET /tasks/:task/attachments/:attachment` returns the file directly.

**Cover image:** Set `cover_image_attachment_id` on the task to use an attachment as the task's cover/featured image.

**Storage:** Files are stored on local filesystem or S3-compatible object storage (configured server-side).

**Size limit:** Configured server-side via `service.maxavatarsize` / body limit settings.

---

## 14. Search / Filter

### 14.1 Text Search

Use `s` query parameter on any list endpoint. Searches task titles. Incompatible with `filter` parameter.

### 14.2 Filter Syntax

Use `filter` query parameter. Syntax: `field comparator value` joined with `&&` (AND) or `||` (OR).

**Filterable Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `id` | int | Task ID |
| `title` | text | Task title |
| `description` | text | Task description |
| `done` | bool | `true` / `false` |
| `done_at` | date | When completed |
| `due_date` | date | Due date |
| `start_date` | date | Start date |
| `end_date` | date | End date |
| `priority` | int | Priority level |
| `percent_done` | float | Progress |
| `repeat_after` | int | Repeat interval |
| `created` | date | Creation date |
| `updated` | date | Last update date |
| `project_id` | int | Project ID |
| `created_by_id` | int | Creator user ID |
| `index` | int | Task index |
| `hex_color` | text | Color |
| `position` | float | Position |
| `bucket_id` | int | Bucket ID (in view context) |
| `assignees` | text/list | Filter by assignee username |
| `labels` | int/list | Filter by label ID |
| `label_id` | int/list | Alias for labels |
| `reminders` | date/list | Filter by reminder date |
| `parent_project` | int | Filter by parent project ID |
| `parent_project_id` | int | Alias for parent_project |

**Comparators:**

| Operator | Description |
|----------|-------------|
| `=` | Equals |
| `!=` | Not equals |
| `>` | Greater than |
| `>=` | Greater or equal |
| `<` | Less than |
| `<=` | Less or equal |
| `like` | Pattern match (use `%` as wildcard) |
| `in` | In a set of values |
| `not in` | Not in a set |

**Logical Operators:** `&&` (AND), `||` (OR). Parentheses `()` for grouping.

**Date Math:** Anchor + operations.
- Anchors: `now`, or a fixed date followed by `||` (e.g., `2024-03-11||`)
- Operations: `+`, `-`, `/` with units: `s`(seconds), `m`(minutes), `h`(hours), `d`(days), `w`(weeks), `M`(months), `y`(years)
- Examples: `now+7d`, `now-1M`, `now/d` (round down to start of day), `2024-03-11||+1w`

**Example Filters:**
```
done = false && priority >= 3
due_date < now+7d && due_date > now
assignees = "john" && labels in [1, 2, 3]
done = false && (priority = 5 || due_date < now)
```

---

## 15. Sorting / Pagination

### 15.1 Sortable Fields

All these fields can be used with `sort_by` parameter:

`id`, `title`, `description`, `done`, `done_at`, `due_date`, `created_by_id`, `project_id`, `repeat_after`, `priority`, `start_date`, `end_date`, `hex_color`, `percent_done`, `uid`, `created`, `updated`, `position`, `bucket_id`, `index`

**Additionally filterable (but not sortable):** `assignees`, `labels`, `reminders`

### 15.2 Sort Order

Use `order_by` parameter: `asc` (default) or `desc`. Can specify multiple: `sort_by[]=priority&sort_by[]=due_date&order_by[]=desc&order_by[]=asc`

### 15.3 Pagination

| Parameter | Description |
|-----------|-------------|
| `page` | Page number (1-based) |
| `per_page` | Items per page |

**Response headers:**
- `x-pagination-total-pages` -- Total number of pages
- `x-pagination-result-count` -- Number of items in this response

---

## 16. Migration

### 16.1 OAuth-Based Migrations

These require a two-step OAuth flow (get auth URL, then migrate with code):

**Todoist:**
| Method | Path | Description |
|--------|------|-------------|
| GET | `/migration/todoist/auth` | Get Todoist OAuth URL |
| POST | `/migration/todoist/migrate` | Execute migration with auth code |
| GET | `/migration/todoist/status` | Check migration status |

**Trello:**
| Method | Path | Description |
|--------|------|-------------|
| GET | `/migration/trello/auth` | Get Trello OAuth URL |
| POST | `/migration/trello/migrate` | Execute migration with auth code |
| GET | `/migration/trello/status` | Check migration status |

**Microsoft To Do:**
| Method | Path | Description |
|--------|------|-------------|
| GET | `/migration/microsoft-todo/auth` | Get Microsoft OAuth URL |
| POST | `/migration/microsoft-todo/migrate` | Execute migration with auth code |
| GET | `/migration/microsoft-todo/status` | Check migration status |

### 16.2 File-Based Migrations

These accept file uploads directly:

**TickTick:**
| Method | Path | Description |
|--------|------|-------------|
| POST | `/migration/ticktick/migrate` | Import from TickTick CSV backup |
| GET | `/migration/ticktick/status` | Check migration status |

**Vikunja (data export):**
| Method | Path | Description |
|--------|------|-------------|
| POST | `/migration/vikunja-file/migrate` | Import from Vikunja ZIP export |
| GET | `/migration/vikunja-file/status` | Check migration status |

---

## 17. Reactions

| Method | Path | Description |
|--------|------|-------------|
| GET | `/:entitykind/:entityid/reactions` | Get reactions on an entity |
| PUT | `/:entitykind/:entityid/reactions` | Add a reaction |
| POST | `/:entitykind/:entityid/reactions/delete` | Remove a reaction |

Entity kinds: `tasks`, `comments` (task comments)

Reaction body: `{"value": "emoji_string"}` -- the emoji character or shortcode.

---

## 18. System / Info

| Method | Path | Description |
|--------|------|-------------|
| GET | `/info` | Get instance info (version, features, auth methods, motd) |
| GET | `/routes` | List all available API routes (for API token permission scoping) |
| GET | `/user/timezones` | List available timezones |
| GET | `/docs.json` | OpenAPI/Swagger specification (JSON) |
| GET | `/docs` | Interactive API documentation (ReDoc UI) |
| GET | `/health` | Health check (outside /api/v1, at root) |

---

## Key Implementation Notes for iOS/macOS App

### Authentication
- Prefer API tokens over JWT for long-lived sessions
- API tokens are created in the web UI under Settings > API Tokens
- JWT tokens expire and need renewal via `/user/token` or `/user/token/refresh`
- Link share authentication via `/shares/:share/auth` returns a limited JWT

### Pagination Strategy
- Always check `x-pagination-total-pages` and `x-pagination-result-count` headers
- Default page size varies; explicitly set `per_page` for consistent behavior

### Task Operations
- Labels MUST be managed via `/tasks/:id/labels` endpoints, not via task update
- Assignees MUST be managed via `/tasks/:id/assignees` endpoints
- Bucket assignment MUST use `/projects/:p/views/:v/buckets/:b/tasks`, not task update
- Position updates use `/tasks/:task/position` with a `project_view_id`
- Use `expand[]=subtasks` to get hierarchical task trees
- Use `expand[]=buckets` to get bucket assignments across views
- Use `expand[]=comments` or `expand[]=comment_count` for comment data

### Offline Sync Considerations
- `updated` timestamps on all models enable last-write-wins conflict resolution
- CalDAV provides an alternative sync mechanism with established offline patterns
- Task `uid` field maps to CalDAV UID for cross-protocol identification
- Webhook events provide real-time push for server-side changes

### Kanban/Views
- Views are per-project; each view has its own type (list/kanban/gantt/table)
- Buckets belong to views, not directly to projects
- `done_bucket_id` and `default_bucket_id` on views control automatic bucket placement
- Bucket configuration mode `filter` enables dynamic/computed buckets

### Repeating Tasks
- Three modes: 0=fixed interval (repeat_after seconds), 1=monthly, 2=from-current-date
- When a repeating task is marked done, it auto-resets to undone with updated dates
- Relative reminders are recalculated on repeat

### Saved Filters
- Saved filters masquerade as projects with negative IDs: `project_id = -(filter_id + 1)`
- They can be favorited and appear alongside projects in the navigation
