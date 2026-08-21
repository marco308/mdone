# OIDC callback shape (issue #153)

**Decision: a custom URL scheme, one fixed callback URI, `mdone://oidc-callback`,
delivered through `ASWebAuthenticationSession`.**

Issue #153 asks for this to be settled before any UI is written, because it
decides the rest. This is the write-up behind that choice. Everything in the
evidence table was measured against a real Vikunja v2.4.0 with Authelia in front
of it, using the dev stack in [dev-setup.md](dev-setup.md), not inferred from
documentation.

## What we measured

| Question | Answer | How we know |
|---|---|---|
| Does Vikunja force its own configured `redirecturl`? | **No.** It honours the `redirect_url` the client sends to the callback. | Authorized with `mdone://oidc-callback` while the server stayed configured with its https frontend URL, and still got a JWT. |
| Is the redirect URI binding enforced at token exchange? | **Yes.** | Authorizing with one URI and exchanging with another returns `invalid_grant`. |
| Will an IdP register a custom scheme for a confidential client? | **Yes**, Authelia does. | Registered `mdone://oidc-callback`, code was issued to it. |
| Can an unregistered URI be used to leak a code? | **No.** | Authelia returns the error to its own page and never redirects to the supplied URI. |
| Is there a minimum entropy requirement on `nonce`? | **Yes.** | A short `nonce` is rejected with `insufficient_entropy`. |

The first row is the one that decides everything. Because Vikunja accepts a
client-supplied `redirect_url`, **the app can use its own callback URI without
the server's `auth.openid.redirecturl` changing at all**, so adopting a custom
scheme does not break the Vikunja web frontend for the same instance. Had that
gone the other way, every option below would have been considerably worse.

## Option A: custom scheme (chosen)

`ASWebAuthenticationSession(url:callback:.customScheme("mdone"))`.

**In favour**

- No entitlement, no hosted files, no developer-controlled infrastructure.
- Explicitly sanctioned for native apps by RFC 8252.
- Works for every self-hosted deployment identically, whatever the user's domain.
- The server needs no reconfiguration, per the evidence above.

**Cost**

The self-hoster must add one redirect URI at their identity provider. That is
unavoidable for any native app, and it is one line in their IdP config. Using a
single fixed `mdone://oidc-callback` rather than a per-provider
`mdone://auth/openid/{key}` keeps that instruction identical no matter how many
providers they run. The app already knows which provider it started, so it can
still POST to the right `/auth/openid/{key}/callback`.

**The security caveat, stated plainly**

Custom schemes can in principle be claimed by another app on the device. Two
things limit that here, and one thing does not help at all:

- `ASWebAuthenticationSession` hands the callback URL straight to its completion
  handler. It does not route through the system URL dispatcher, so a second app
  registering the same scheme cannot intercept a callback belonging to a live
  session.
- `state` validation, already implemented and tested, rejects any callback the
  app did not initiate.
- **PKCE is not available to us.** mDone is not the OAuth client, Vikunja is: it
  holds the client secret and performs the exchange. So the app cannot bind the
  code to itself with a verifier. If a code did escape to a hostile app, that app
  could exchange it at Vikunja's unauthenticated callback endpoint, because it
  would know both the code and the redirect URI.

The residual risk is therefore real but narrow, and it is bounded by codes being
single use and short lived, which the smoke test asserts. It is worth revisiting
if Vikunja ever exposes a public-client OIDC flow with PKCE.

## macOS behaves differently, and it weakens two claims above

Tested on macOS 15 with a sandboxed build against the dev stack. What works:
the setup screen renders, the `/api/v1/info` probe succeeds (confirmed in the
server log as `user_agent="mDone-macOS/..."`), the SSO button appears, and
`ASWebAuthenticationSession` starts without a presentation-anchor error and
sends a correct authorization request that reaches the provider.

What is different: **macOS hands the session to the default browser when that
browser is not Safari.** On a machine defaulting to Brave, the authorization
request opened in Brave, not in an in-app Safari sheet. Two consequences.

**`prefersEphemeralWebBrowserSession` is a Safari guarantee, and probably does
nothing here.** Cookie isolation is provided by Safari's ephemeral mode. Handed
to a third-party browser, the flow almost certainly runs in the user's ordinary
profile, with whatever identity-provider session they already have. So the
claim that this matches the isolation PR #103 wanted from
`WKWebsiteDataStore.nonPersistent()` holds on iOS but should not be relied on
for macOS.

**The "callback never touches the system URL dispatcher" claim is unverified on
macOS.** With an external browser the redirect leaves that browser and is
brokered by `AuthenticationServicesAgent`. That is very likely still a direct
hand-off to the waiting session, but it was not possible to prove here, so it
should not be stated as fact. Treat the scheme-squatting mitigation as verified
on iOS and unproven on macOS.

One thing that did check out: `mDoneApp`'s `onOpenURL` is `#if os(iOS)`, so a
`mdone://` URL arriving on macOS through LaunchServices is inert. A callback
that escapes the session cannot be consumed by accident.

### Still to verify on macOS

Completing a sign-in in an external default browser and confirming the code
reaches the app. Everything up to the provider's login page is confirmed; the
return leg is not.

## Option B: https callback via Associated Domains (not viable)

`ASWebAuthenticationSession.Callback.https(host:path:)` exists on our deployment
target and is the better shape in the abstract, since https URIs cannot be
claimed by another app.

It cannot work for a self-hosted app. It requires the Associated Domains
entitlement, which lists domains **compiled into the app at build time**, and an
`apple-app-site-association` file served from each of those domains. mDone's
users each run their own server on their own domain. There is no wildcard for
"whatever host the user typed into the setup screen", and there is no way to
enumerate them in advance.

The only way to force it would be to route every user's OIDC redirect through a
domain we control. That would insert us into other people's authentication flow,
where we would see their authorization codes, and would require us to run and
secure that infrastructure indefinitely. Both are disqualifying for an app whose
whole premise is that the user hosts their own data.

## Option C: embedded WKWebView (rejected, as PR #103 had it)

Already rejected in the issue on anti-phishing grounds, since an embedded web
view shows no URL bar and the host app can read what the user types into the
identity provider's page. Two further reasons found while investigating:

- Google refuses OAuth in embedded web views outright, returning
  `disallowed_useragent`. Any user whose Vikunja federates to Google Workspace
  would simply be unable to log in.
- `prefersEphemeralWebBrowserSession` gives the cookie isolation that #103 was
  reaching for with `WKWebsiteDataStore.nonPersistent()`, so nothing is lost.

## Consequences for the implementation

1. **The scheme is already registered, and must stay in the plist.** `mdone` is
   in `CFBundleURLTypes` in `mDone/Info.plist`, which both app targets share via
   `INFOPLIST_FILE` (`project.yml:45` and `project.yml:81`). It has been there
   since the widget deep links `mdone://focus` and `mdone://create` were added,
   so `mdone://oidc-callback` is a third host on an existing scheme and needs no
   new registration.

   **Do not move it into `project.yml`.** An earlier draft of this document said
   to, which was wrong. XcodeGen's `info:` block *generates* a plist rather than
   merging into one, so adding it for these targets would rewrite
   `mDone/Info.plist` from scratch and silently drop the hand-written keys,
   including `NSSupportsLiveActivities`, `NSCalendarsFullAccessUsageDescription`
   and `NSLocalNetworkUsageDescription`, and would replace the
   `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` wiring with literal
   `1.0` / `1`. That last one ships every build as version 1.0 and gets rejected
   at upload.

   This is a different case from the `PRODUCT_NAME`, `ENABLE_TESTABILITY` and
   `SDKROOT` pins that `project.yml` already carries. Those add back settings
   XcodeGen stopped emitting. An `info:` block instead takes ownership of a
   git-tracked file that is currently hand-maintained.

   Guard: `xcodegen generate` must leave `mDone/Info.plist` byte-identical, and
   `plutil -p mDone/Info.plist | grep -c '^  "'` must still report 22 keys.

2. **Leave `mdone://oidc-callback` unhandled in `onOpenURL`.**
   `mDoneApp.swift:120` switches on `url.host` with `default: break`, so a
   callback arriving through the system URL dispatcher is already ignored. That
   is the behaviour we want and it should be made explicit with a comment rather
   than left incidental: `ASWebAuthenticationSession` delivers the callback to
   its own completion handler, and a code arriving by any other route did not
   come from a session this app started.
3. **The app builds the authorization URL.** Vikunja supplies only the resolved
   `auth_url`; the app appends `client_id`, `redirect_uri`, `response_type`,
   `scope`, `state` and `nonce`.
4. **`nonce` needs real entropy**, per the evidence table. Done:
   `OIDCLogin.generateNonce()` sits alongside `generateState()`, both drawing 32
   bytes from the same CSPRNG helper but as independent values. Reusing the
   generator is fine; reusing the same *value* for both is not, and there is a
   test asserting they differ.
5. **Send `redirect_url` on the callback**, matching the authorize request byte
   for byte, or the exchange fails with `invalid_grant`.
6. **Document the IdP step for self-hosters:** add `mdone://oidc-callback` to the
   Vikunja client's redirect URIs. Without it the provider refuses the request,
   correctly and unhelpfully.
7. **Known limitation to carry forward from the #103 review:** Vikunja derives
   its own default redirect URL from the API server URL, which assumes the API
   and the frontend share an origin. That assumption is now only load-bearing for
   the web frontend, not for us.
