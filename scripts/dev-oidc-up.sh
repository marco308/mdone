#!/usr/bin/env bash
#
# Brings up the dev Vikunja behind TLS with an Authelia OIDC provider, for work
# on issue #153. Everything here is throwaway: never point it at a real Vikunja
# or a real identity provider.
#
#   ./scripts/dev-oidc-up.sh                  local auth on  + OIDC
#   ./scripts/dev-oidc-up.sh --no-local-auth  local auth off + OIDC
#
# The second form is what exercises "hide the username and password fields when
# the server has local auth disabled".
#
set -euo pipefail
cd "$(dirname "$0")/.."

LOCAL_AUTH=true
for arg in "$@"; do
    case "$arg" in
        --no-local-auth) LOCAL_AUTH=false ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

command -v mkcert >/dev/null || { echo "mkcert not found: brew install mkcert" >&2; exit 1; }

# One hostname has to resolve the same from the Mac, the Simulator and inside
# the containers. See the header of docker-compose.oidc.yml. nip.io maps
# <ip>.nip.io, and anything.<ip>.nip.io, straight back to <ip>.
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
[ -n "$IP" ] || { echo "No LAN IP on en0 or en1. Are you on a network?" >&2; exit 1; }
DEV_BASE="${IP}.nip.io"

if ! dig +short "vikunja.${DEV_BASE}" | grep -q .; then
    echo "DNS cannot resolve vikunja.${DEV_BASE}." >&2
    echo "nip.io needs working public DNS, and some resolvers block it as DNS rebinding." >&2
    exit 1
fi

echo "==> dev host: ${DEV_BASE} (local auth: ${LOCAL_AUTH})"

mkdir -p vikunja-dev-data/authelia dev/certs

# Authelia's OIDC signing key. Generated on first run and gitignored: a private
# key does not belong in the repo even when it is throwaway, and this one would
# trip secret scanning.
if [ ! -f dev/authelia/oidc.key ]; then
    echo "==> generating Authelia OIDC signing key"
    openssl genrsa -out dev/authelia/oidc.key 2048 2>/dev/null
    chmod 600 dev/authelia/oidc.key
fi

# Wildcard leaf for both vikunja.* and auth.*. mkcert's CA already exists in
# $(mkcert -CAROOT); we deliberately do not run `mkcert -install`, which would
# need your password to touch the system trust store. Nothing here requires it:
# Vikunja trusts the CA through SSL_CERT_FILE and the Simulator through
# `simctl keychain add-root-cert` below.
echo "==> issuing certificate for *.${DEV_BASE}"
mkcert -cert-file dev/certs/cert.pem -key-file dev/certs/key.pem \
    "*.${DEV_BASE}" "${DEV_BASE}" >/dev/null 2>&1

# Vikunja's Go HTTP client needs the mkcert root to verify Authelia. Build a
# bundle of the image's own roots plus that CA, rather than replacing the pool.
CAROOT="$(mkcert -CAROOT)"
docker run --rm vikunja/vikunja:latest cat /etc/ssl/certs/ca-certificates.crt \
    > dev/certs/ca-bundle.crt 2>/dev/null || : > dev/certs/ca-bundle.crt
cat "${CAROOT}/rootCA.pem" >> dev/certs/ca-bundle.crt
chmod 644 dev/certs/cert.pem dev/certs/ca-bundle.crt
chmod 640 dev/certs/key.pem

export DEV_BASE VIKUNJA_LOCAL_AUTH="$LOCAL_AUTH"
# shellcheck disable=SC2016
envsubst '${DEV_BASE} ${VIKUNJA_LOCAL_AUTH}' \
    < dev/vikunja/config.yml.template > dev/vikunja/config.yml

printf 'DEV_BASE=%s\n' "$DEV_BASE" > .env.oidc

COMPOSE=(docker compose --env-file .env.oidc -f docker-compose.dev.yml -f docker-compose.oidc.yml)
"${COMPOSE[@]}" up -d --force-recreate

echo "==> waiting for Authelia discovery"
for _ in $(seq 1 60); do
    curl -sf -m 2 "https://auth.${DEV_BASE}:8443/.well-known/openid-configuration" >/dev/null 2>&1 && break
    sleep 1
done

echo "==> waiting for Vikunja"
for _ in $(seq 1 60); do
    curl -sf -m 2 "https://vikunja.${DEV_BASE}:8443/api/v1/info" >/dev/null 2>&1 && break
    sleep 1
done

# The Simulator has its own trust store, separate from the Mac's.
if xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
    xcrun simctl keychain booted add-root-cert "${CAROOT}/rootCA.pem" 2>/dev/null \
        && echo "==> added mkcert root to the booted Simulator"
else
    echo "==> no booted Simulator. After booting one, run:"
    echo "    xcrun simctl keychain booted add-root-cert \"${CAROOT}/rootCA.pem\""
fi

echo
echo "==> /api/v1/info auth block"
curl -s "https://vikunja.${DEV_BASE}:8443/api/v1/info" \
    | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["auth"], indent=2))'
echo
echo "Vikunja:  https://vikunja.${DEV_BASE}:8443"
echo "Authelia: https://auth.${DEV_BASE}:8443   (devuser / devpassword)"
echo "Down:     docker compose --env-file .env.oidc -f docker-compose.dev.yml -f docker-compose.oidc.yml down"
