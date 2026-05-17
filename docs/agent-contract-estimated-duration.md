# mDone estimated duration — Vikunja API contract

The mDone iOS/macOS app stores each task's **optional estimated duration** inside the task's standard Vikunja `description` field as an HTML-comment marker. Read or set it via the normal Vikunja REST API — there is no special endpoint.

## Marker format

```
<!-- mdone:estimate=NNN -->
```

- `NNN` is the estimated duration in **whole seconds**, positive integer.
- Placed at the **end of the description**, separated from any body text by one blank line.
- A description may consist of *only* the marker (no body) — that's valid.

## Reading the estimate

Fetch the task (`GET /api/v1/tasks/{id}`) and scan the `description` field with this regex:

```
<!--\s*mdone:estimate=(\d+)\s*-->
```

- First match wins.
- If no match, the task has **no estimate** — treat as unknown, don't guess.
- Capture group 1 is the seconds value.

## Setting or updating the estimate

When you `PUT /api/v1/projects/{projectId}/tasks` (create) or `POST /api/v1/tasks/{id}` (update), build the `description` field as:

1. Start from the existing description (for updates) or empty string (for creates).
2. **Strip any existing marker(s)** matching the regex above.
3. Trim trailing whitespace from the remaining body.
4. Append the new marker:
   - If there's body text: `"{body}\n\n<!-- mdone:estimate=NNN -->"`
   - If body is empty: `"<!-- mdone:estimate=NNN -->"`
5. Send the result as the `description` field in the request body.

## Clearing the estimate

Strip the marker (step 2 above), trim, and send the body alone — or send `null` / empty string if no body remains.

## Examples

**Read** — task description as returned by Vikunja:

```
Pull metrics from the dashboard.

<!-- mdone:estimate=1800 -->
```

→ Estimate = 1800 seconds (30 minutes). Visible body = `"Pull metrics from the dashboard."`

**Create a 45-minute task with no description body:**

```http
PUT /api/v1/projects/12/tasks
Content-Type: application/json

{
  "title": "Review pull request #88",
  "description": "<!-- mdone:estimate=2700 -->"
}
```

**Update an existing task to add a 25-minute estimate while preserving its body:**

```http
POST /api/v1/tasks/4471
Content-Type: application/json

{
  "description": "Original notes about the task.\n\n<!-- mdone:estimate=1500 -->"
}
```

**Change the estimate from 25m → 1h** (strip old marker, append new):

```http
POST /api/v1/tasks/4471
Content-Type: application/json

{
  "description": "Original notes about the task.\n\n<!-- mdone:estimate=3600 -->"
}
```

## Rules of the road

- **Seconds only.** No `30m`, no decimals. Convert before writing: 30 minutes = 1800, 1 hour = 3600, 2.5 hours = 9000.
- **Don't write `estimate=0` or negative values** — those are treated as "no estimate". To clear, just omit the marker.
- **One marker per description.** If you see multiple, the first wins on read; always dedupe on write (strip all, append one).
- **Don't render the marker in user-facing output.** Treat the body (description with marker stripped + trailing whitespace trimmed) as what the user sees.
- The marker is **opaque to Vikunja** — it's stored as raw text in the description, won't appear in Vikunja's web UI rendering as anything visible, and survives round-trips intact.
- The marker is **case-sensitive**: `mdone:estimate=` exactly, no spaces around the `=`.

## When to suggest setting an estimate

If you're planning the user's day, suggesting what to do at lunch, or creating tasks on their behalf, **include an estimate when you can make a reasonable guess** from the task title (e.g. "reply to email" → 300s, "write quarterly review" → 7200s). Today the value shows up in mDone's Task Detail screen and feeds the Quick Add bar's "similar tasks took ~Xm" suggestion; future work in mDone may use it to filter tasks that fit available time windows, but you should also use it yourself when planning the user's day from outside the app.
