#!/usr/bin/env bash
#
# End-to-end check of the OIDC leg the app has to perform, against the dev
# stack from scripts/dev-oidc-up.sh:
#
#   authorize -> Authelia login -> code -> Vikunja callback -> JWT -> API call
#
# It also asserts the two security properties issue #153 calls out: that the
# `state` round-trips unchanged, and that an authorization code is single use.
#
# This is the scripted stand-in for the browser flow. It does not exercise
# ASWebAuthenticationSession, which is system UI and has to be checked by hand.
#
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env.oidc ] || { echo "run scripts/dev-oidc-up.sh first" >&2; exit 1; }
# shellcheck disable=SC1091
. .env.oidc

CAROOT="$(mkcert -CAROOT)"
CURL=(curl -sS --cacert "${CAROOT}/rootCA.pem")
JAR="$(mktemp)"
trap 'rm -f "$JAR"' EXIT

VIK_HOST="https://vikunja.${DEV_BASE}:8443"

# The app's own callback URI. See docs/oidc-callback-decision.md.
REDIRECT="mdone://oidc-callback"

# state and nonce are independent values, and providers enforce a floor on
# nonce entropy: a short one is rejected with `insufficient_entropy` at the
# token exchange, long after the user has finished logging in.
STATE=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
NONCE=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "==> 0. discover the provider from /api/v1/info"
# Read the provider exactly as the app does, rather than hardcoding it, so this
# exercises the same data path: info -> provider -> authorization URL.
eval "$("${CURL[@]}" "${VIK_HOST}/api/v1/info" | python3 -c '
import json, sys
auth = json.load(sys.stdin)["auth"]["openid_connect"]
providers = auth.get("providers") or []
if not auth.get("enabled") or not providers:
    print("PROVIDER_KEY=")
    sys.exit(0)
p = providers[0]
print("PROVIDER_KEY=%s" % p["key"])
print("AUTH_URL=%s" % p["auth_url"])
print("CLIENT_ID=%s" % (p.get("client_id") or ""))
print("SCOPE=%s" % ((p.get("scope") or "openid profile email").replace(" ", "+")))
')"
[ -n "${PROVIDER_KEY:-}" ] || fail "no OIDC provider advertised by ${VIK_HOST}"
AUTH_HOST="https://auth.${DEV_BASE}:8443"
ok "provider '${PROVIDER_KEY}', client '${CLIENT_ID}', scope '${SCOPE//+/ }'"

echo "==> 1. authorization request"
LOC=$("${CURL[@]}" -c "$JAR" -D- -o /dev/null \
    "${AUTH_URL}?client_id=${CLIENT_ID}&response_type=code&redirect_uri=${REDIRECT}&scope=${SCOPE}&state=${STATE}&nonce=${NONCE}" \
    | grep -i '^location:' | tr -d '\r' | cut -d' ' -f2-)
FLOW_ID=$(printf '%s' "$LOC" | sed -n 's/.*flow_id=\([0-9a-f-]*\).*/\1/p')
[ -n "$FLOW_ID" ] || fail "no flow_id in redirect: $LOC"
ok "redirected to the login portal (flow ${FLOW_ID:0:8}...)"

echo "==> 2. first factor"
REDIR=$("${CURL[@]}" -b "$JAR" -c "$JAR" -X POST "${AUTH_HOST}/api/firstfactor" \
    -H 'Content-Type: application/json' -H "Origin: ${AUTH_HOST}" \
    -d "{\"username\":\"devuser\",\"password\":\"devpassword\",\"keepMeLoggedIn\":false,\"flowID\":\"${FLOW_ID}\",\"flow\":\"openid_connect\"}" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit("status "+d.get("status","?")) if d.get("status")!="OK" else print(d["data"]["redirect"])')
ok "authenticated as devuser"

echo "==> 3. consent and code issue"
LOC=$("${CURL[@]}" -b "$JAR" -c "$JAR" -D- -o /dev/null "$REDIR" \
    | grep -i '^location:' | tr -d '\r' | cut -d' ' -f2-)
eval "$(printf '%s' "$LOC" | python3 -c '
import sys, urllib.parse as u
q = u.parse_qs(u.urlparse(sys.stdin.read().strip()).query)
print("CODE=%s" % u.quote(q.get("code",[""])[0]))
print("GOT_STATE=%s" % q.get("state",[""])[0])
print("ERR=%s" % q.get("error",[""])[0])
')"
[ -z "${ERR:-}" ] || fail "provider returned error=${ERR}"
[ -n "${CODE:-}" ] || fail "no code in callback: $LOC"
ok "received an authorization code"

echo "==> 4. state validation"
[ "$GOT_STATE" = "$STATE" ] || fail "state mismatch: sent '$STATE', got '$GOT_STATE'"
ok "state round-tripped unchanged"

echo "==> 5. code exchange at Vikunja"
TOKEN=$("${CURL[@]}" -X POST "${VIK_HOST}/api/v1/auth/openid/${PROVIDER_KEY}/callback" \
    -H 'Content-Type: application/json' \
    -d "{\"code\":\"${CODE}\",\"redirect_url\":\"${REDIRECT}\"}" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("token",""))')
[ -n "$TOKEN" ] || fail "no token returned"
ok "exchanged for a Vikunja JWT"

echo "==> 6. the JWT is a working session"
COUNT=$("${CURL[@]}" -H "Authorization: Bearer ${TOKEN}" "${VIK_HOST}/api/v1/projects" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else -1)')
[ "$COUNT" -ge 0 ] || fail "the JWT did not authenticate against /projects"
ok "GET /api/v1/projects returned ${COUNT} projects"

echo "==> 7. the code is single use"
REPLAY=$("${CURL[@]}" -o /dev/null -w '%{http_code}' -X POST "${VIK_HOST}/api/v1/auth/openid/${PROVIDER_KEY}/callback" \
    -H 'Content-Type: application/json' \
    -d "{\"code\":\"${CODE}\",\"redirect_url\":\"${REDIRECT}\"}")
[ "$REPLAY" != "200" ] || fail "replaying the code succeeded, it should not"
ok "replaying the same code is rejected (HTTP ${REPLAY})"

echo
echo "PASS: code-to-JWT leg works end to end"
