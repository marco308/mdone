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

## OIDC / SSO dev stack (issue #153)

The plain dev server has no identity provider. For OIDC work there is a second
stack that puts **Authelia** in front of the same Vikunja, chosen because it is
what the maintainer's homelab runs, so dev and production behave the same.

```bash
./scripts/dev-oidc-up.sh                  # local auth on  + OIDC
./scripts/dev-oidc-up.sh --no-local-auth  # local auth off + OIDC
```

The second form is the one that exercises "hide the username and password
fields when the server has local auth disabled". Log in as `devuser` /
`devpassword`, same as the plain stack.

Tear down with the command the script prints when it finishes.

### Why it looks more complicated than the plain stack

Three constraints shape it, and all three are easy to rediscover the hard way.

**One hostname, three vantage points.** The same host has to resolve
identically from the Mac, from the iOS Simulator, and from inside the Vikunja
container doing the server-side token exchange. `localhost` cannot do that,
because inside a container it means that container. The script uses
`<lan-ip>.nip.io`, public wildcard DNS that maps the embedded IP straight back,
so all three agree without touching `/etc/hosts`. It does need working public
DNS, and a few resolvers block nip.io as DNS rebinding.

**Everything is HTTPS.** Authelia refuses a plaintext `authelia_url`, and iOS
App Transport Security would block a cleartext identity provider, so an HTTP
stack would need an ATS exception we do not want to ship. Caddy terminates TLS
for both hosts with one mkcert wildcard certificate. Vikunja trusts that CA via
`SSL_CERT_FILE`; the Simulator gets it from `simctl keychain add-root-cert`,
which the script runs for you if a Simulator is booted. Nothing needs
`mkcert -install`, so nothing needs your password.

**Vikunja wants a map of providers, not a list.** This one costs an hour if you
follow the older docs:

```yaml
# WRONG on v2.4.0, and fails almost silently
providers:
  - name: Authelia
    authurl: ...

# RIGHT
providers:
  authelia:
    name: Authelia
    authurl: ...
```

The list form logs only `It looks like your openid configuration is in the
wrong format` and leaves `"providers": null` in `/api/v1/info`, with
`"enabled": true` right next to it, so it looks like a discovery or networking
problem rather than a parse error. The map key becomes the provider `key` in
that payload and the last path segment of both the redirect URI and the
callback endpoint.

### Testing SSO on macOS

```bash
./scripts/dev-macos-oidc.sh            # build and launch
./scripts/dev-macos-oidc.sh --cleanup  # quit it, remove every trace
```

**Do not just build and run `mDone-macOS` for this.** It shares the bundle
identifier `com.mdone.app` with the copy in `/Applications`, so it reads the
same keychain and the same sandbox container. It will sign you straight into
whatever server your real app uses and never show the setup screen, and signing
in to a test server from it overwrites the credentials your real app depends on.

The script overrides `PRODUCT_BUNDLE_IDENTIFIER`, which gives the build its own
keychain access group and container, so nothing it does can reach the real app.

Two macOS behaviours to expect, neither of which happens on iOS:

- **The sign-in opens in your default browser**, not an in-app Safari sheet,
  unless Safari *is* your default. `prefersEphemeralWebBrowserSession` is a
  Safari feature, so in a third-party browser the flow probably uses your normal
  profile and whatever provider session it already holds.
- **If it hangs on the spinner** after you sign in, the callback is not getting
  back to the app. The first thing to check is whether `mdone://oidc-callback`
  is registered as a redirect URI on that server's identity provider.

### Proving the flow works

```bash
./scripts/dev-oidc-smoke.sh
```

Walks the whole leg the app has to perform, against the running dev stack:
authorization request, Authelia login, authorization code, Vikunja callback,
JWT, then a real API call with that JWT. It asserts the two security
properties #153 calls out, that `state` round-trips unchanged and that an
authorization code cannot be replayed, and it verifies TLS against the mkcert
root rather than skipping verification, so a broken certificate chain fails the
run instead of hiding.

Run it after any change to the stack, and against your own server before
trusting a build there. It does not exercise `ASWebAuthenticationSession`,
which is system UI and still has to be checked by hand.

One behaviour worth knowing, because it decides how wrong the UI can afford to
be: with local auth disabled, `POST /api/v1/login` returns **404**, not 401 or
403. The endpoint is gone rather than refusing. So a build that shows the
username and password fields on an SSO-only server does not produce a helpful
"local login is disabled" message, it produces "Not Found".

### What /api/v1/info actually returns

With a provider configured, the block the app decodes looks like this. Note
that `auth_url` is the fully resolved authorization endpoint, which Vikunja
gets from the provider's discovery document, so the app never builds it:

```json
"auth": {
  "local":          { "enabled": true, "registration_enabled": true },
  "ldap":           { "enabled": false },
  "openid_connect": {
    "enabled": true,
    "providers": [
      {
        "name": "Authelia",
        "key": "authelia",
        "auth_url": "https://auth.<host>:8443/api/oidc/authorization",
        "logout_url": "",
        "client_id": "vikunja",
        "scope": "openid profile email",
        "email_fallback": false,
        "username_fallback": false,
        "force_user_info": false
      }
    ]
  }
}
```

With no provider configured, `providers` is `null` rather than `[]`, so decode
it as an optional array.

## Vikunja version pinning

`docker-compose.dev.yml` currently uses `vikunja/vikunja:latest`. When you start noticing odd behaviour after a `docker compose pull`, check the [Vikunja release notes](https://kolaente.dev/vikunja/vikunja/-/releases) and pin to a known-good tag.

If you're chasing a bug that may be Vikunja-side, pin your dev compose file to the same version your prod instance runs to ensure the API shape matches.

## When to update the Apple Review test server

Almost never. Only when:

- The data shape Apple Review depends on changes (e.g. a new demo flow needs a specific seeded task).
- The token expires — store the credentials in a password manager (1Password, Keychain, or equivalent) outside this repo, and rotate the test-server token before the previous one expires.

For everything else, dev is the right environment.
