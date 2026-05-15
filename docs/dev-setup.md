# Dev Setup

The goal of this doc is to give you a Vikunja you can **break, reset, and reseed at will** — so the iteration loop on new features doesn't risk your real Vikunja.

## Three environments — never mix them up

| Environment | URL | Purpose | Safe to break? |
|---|---|---|---|
| **Dev** | `http://localhost:3456` | Local Docker. Yours to nuke. | ✅ Yes |
| **Apple Review test** | `https://vikunja-test.marcuslab.uk` | Stable seeded data the App Store reviewer logs into. | ⚠️ No — Apple Review depends on it |
| **Prod** | (your real instance) | Your actual tasks. | ❌ NO |

When you're developing, **always** point the app at `http://localhost:3456`. The Settings screen shows the active server URL — glance at it before you start work to confirm which environment you're touching.

## Prerequisites

- Docker Desktop (or compatible)
- `jq` — `brew install jq` (used by the seed script)
- Xcode + XcodeGen (see [CONTRIBUTING.md](../CONTRIBUTING.md) for the iOS build setup)

## Quickstart

From the repo root:

```bash
# 1. Start a local Vikunja (SQLite, ~5s to come up)
docker compose -f docker-compose.dev.yml up -d

# 2. Seed sample data (registers devuser, creates projects/labels/tasks)
./scripts/seed-dev-vikunja.sh

# 3. Build & run mDone in the Simulator
xcodegen generate
open mDone.xcodeproj
# Run mDone → in the login screen, enter:
#   Server URL: http://localhost:3456
#   Username:   devuser
#   Password:   devpassword
```

The Vikunja web UI is at the same `http://localhost:3456` if you want to verify what the app wrote.

## Reset / reseed

```bash
./scripts/reset-dev-vikunja.sh   # wipes the SQLite volume, restarts the container
./scripts/seed-dev-vikunja.sh    # repopulate sample data
```

The reset script deletes `vikunja-dev-data/` (gitignored). It does **not** touch your prod or test instances — it only operates on the `docker-compose.dev.yml` stack.

## Switching mDone between environments

The server URL is stored in `UserDefaults` ([mDone/Services/AuthService.swift:13](../mDone/Services/AuthService.swift:13)). To switch:

1. Settings → Log Out
2. Re-enter the new server URL on the login screen
3. Log in with that environment's credentials

For the Simulator the dev URL is `http://localhost:3456`. For a physical iPhone on your LAN, use your Mac's LAN IP (`http://192.168.x.x:3456`); for off-LAN testing, use your Tailscale IP. **Don't expose the dev Vikunja to the public internet** — it's running with a hardcoded dev JWT secret.

## What the seed script gives you

After `./scripts/seed-dev-vikunja.sh`:

- **3 projects**: Work, Home, Side projects
- **3 labels**: urgent, waiting, deep-work
- **A mix of tasks** — different priorities, some with due dates (today/tomorrow/next week/yesterday/overdue), one already completed (`Send invoice — March`) so the "completed tasks" surface has something in it
- **Login**: `devuser` / `devpassword`

The script is idempotent on the user (won't re-create) but **not** on the data — each run adds another set of projects/tasks. Reset first if you want a clean slate.

## Testing

### Unit tests — fast, no Vikunja needed

Already comprehensive. Mocked via `MockURLProtocol` ([mDoneTests/Helpers/MockURLProtocol.swift](../mDoneTests/Helpers/MockURLProtocol.swift)):

```bash
xcodebuild -project mDone.xcodeproj -scheme mDone \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# Single test target
xcodebuild ... -only-testing:mDoneTests/TaskServiceTests test
```

Add new unit tests in `mDoneTests/` following the existing pattern: inject a `URLSession` configured with `MockURLProtocol`, set `MockURLProtocol.requestHandler` per test, assert against `MockURLProtocol.capturedRequests`.

### Manual integration — against dev Vikunja

After `docker compose up -d` and the seed script, run the app and exercise the path you're changing. The Vikunja web UI is the ground-truth view: open it side-by-side with the Simulator to confirm what landed server-side.

### Common scenarios

- **First-run / onboarding** — reset Vikunja, skip the seed, install the app fresh (Simulator → Device → Erase All Content and Settings).
- **Server-side changes the app must pick up** — make the edit in Vikunja's web UI, pull-to-refresh in mDone.
- **Offline / sync** — Simulator → Settings → Developer → Network Link Conditioner → 100% Loss; make changes; restore network; verify the pending operations in [mDone/Services/SyncService.swift](../mDone/Services/SyncService.swift) flush.
- **Edge dates** — the seed includes overdue and zero-date cases ([APIClient.swift](../mDone/Services/APIClient.swift) handles Vikunja's `0001-01-01T00:00:00Z` → `Date.distantPast`).

## Vikunja version pinning

`docker-compose.dev.yml` currently uses `vikunja/vikunja:latest`. When you start noticing odd behaviour after a `docker compose pull`, check the [Vikunja release notes](https://kolaente.dev/vikunja/vikunja/-/releases) and pin to a known-good tag.

If you're chasing a bug that may be Vikunja-side, pin your dev compose file to the same version your prod instance runs to ensure the API shape matches.

## When to update the Apple Review test server

Almost never. Only when:

- The data shape Apple Review depends on changes (e.g. a new demo flow needs a specific seeded task).
- The token expires — credentials are in the memory note `reference_vikunja_review.md`.

For everything else, dev is the right environment.
