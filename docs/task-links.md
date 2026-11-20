# Open an existing task

The public link contract is `mdone://task/{id}?server={encoded-server-base-URL}`.
For example: `mdone://task/42?server=https%3A%2F%2Ftasks.example.com%2Fvikunja`.
Encode the complete server URL as one query value, including a subpath when the
Vikunja installation uses one. IDs are positive decimal signed-64-bit integers
without leading zeros. No task title, credentials, prompt or notification ID is
accepted. The only supported new destination is an existing task. Existing
`mdone://create` and `mdone://focus` behavior is unchanged.

The app compares the link's server with its configured connection (scheme, host,
effective port and complete base path). Host case, default ports, a trailing
slash and equivalent path escaping are normalized. Credentials, queries,
fragments, dot segments and ambiguous path separators are rejected. HTTP remains
available for explicitly configured local/self-hosted servers; links never switch
servers or choose where authentication credentials are sent.

A link received before sign-in stays pending until sign-in succeeds. It then
fetches the task through the existing authenticated client, even when the task
is absent from loaded lists. A new link supersedes an older pending request;
cancelled or late responses cannot replace the current destination. Deleted or
inaccessible tasks and connection failures are shown explicitly with retry/cancel.
Task links require a successful current read rather than silently opening stale
cached data. Merely opening a link performs no task mutation. Editing and explicit
completion use the existing detail interface and update/sync behavior.

The route is shared by iOS and macOS. Projects, labels, calendars, notification
records and projected recurrence occurrences have no new incoming routes.

Separate distributions may set the `MDoneURLScheme` Info.plist value and register
that same scheme in `CFBundleURLTypes`. The default remains `mdone`. A fork must
use its own scheme if it coexists with the official app; URL scheme dispatch
cannot distinguish two apps registering the same scheme.

## Verification

`TaskDeepLinkTests`, `TaskLinkRouterTests` and `LinkedTaskReadTests` cover:

- Canonical task IDs, invalid URLs and alternate app schemes.
- Server matching, including ports, installation base paths and escaped paths.
- Waiting for sign-in and rejecting a different server without a request.
- Superseded/cancelled reads, uncached tasks and deleted/inaccessible tasks.
- Read-only navigation through the configured authenticated client.

These tests share the existing iOS and macOS unit test targets. For example,
after generating the project with XcodeGen:

```sh
xcodebuild -project mDone.xcodeproj -scheme mDone-macOS \
  -destination 'platform=macOS' \
  -only-testing:mDoneMacTests/TaskDeepLinkTests \
  -only-testing:mDoneMacTests/TaskLinkRouterTests \
  -only-testing:mDoneMacTests/LinkedTaskReadTests test
```

`TaskLinkUITests` is an opt-in iOS test against the loopback development Vikunja
only. Start and seed it using [the development setup](dev-setup.md), then run on
a disposable simulator with `TEST_RUNNER_MDONE_TASK_LINK_UI=1` in the
`xcodebuild` environment and `-only-testing:mDoneUITests/TaskLinkUITests`.
Disable parallel testing for this shared local fixture. Keep simulator signing
and its App Group entitlements enabled so saved authentication works on relaunch.

The defaults are `com.mdone.app.dev` and the `mdone` scheme. An isolated build can
set `TEST_RUNNER_MDONE_APP_ID` and `TEST_RUNNER_MDONE_LINK_SCHEME`. The test targets
that app explicitly rather than relying on OS scheme selection between installed
Debug and Release copies. It creates and removes its own disposable project
through the local v2 API and signs the test app into the seeded development
account. Never run it with personal app data or against a production server.

The UI scenario covers cold launch and sign-in, opening the exact task, a task
created after backgrounding, no completion merely from opening, editing and
saving, explicit completion confirmed by the server, reopening from closed,
wrong-server/malformed/deleted links, and the existing create action.

## Current limits

- A pending link survives sign-in in the running app, but is not persisted across
  process termination. Reopen the link to resume.
- Opening a task requires a current server read. An offline error offers Retry
  and Cancel rather than silently presenting cached data.
- Task completion is disabled while its editor has unsaved changes. Save edits
  before changing completion.
- This adds an incoming app-link route. It does not add a share-link button,
  universal HTTPS links, or automatic conversion of Vikunja web URLs.
