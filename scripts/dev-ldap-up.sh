#!/usr/bin/env bash
#
# Brings up the dev Vikunja with an lldap directory behind it, for work on
# issue #156. Everything here is throwaway: never point it at a real Vikunja
# or a real directory.
#
#   ./scripts/dev-ldap-up.sh                  local auth on  + LDAP
#   ./scripts/dev-ldap-up.sh --no-local-auth  local auth off + LDAP (LDAP-only)
#
# Creates one directory user, ldapuser / ldappassword, then proves the login
# end to end with curl against /api/v2/login. Sign in to the dev app with the
# same pair at http://localhost:3457, which runs beside the plain dev server.
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

command -v jq >/dev/null || { echo "jq not found: brew install jq" >&2; exit 1; }

VIKUNJA_URL="http://localhost:3457"
LLDAP_URL="http://localhost:17170"
LLDAP_ADMIN_PASS="devadminpassword"   # matches docker-compose.ldap.yml
LDAP_USER="ldapuser"
LDAP_PASS="ldappassword"

echo "==> local auth: ${LOCAL_AUTH}"
mkdir -p vikunja-dev-data/ldap/lldap vikunja-dev-data/ldap/files

export VIKUNJA_LOCAL_AUTH="$LOCAL_AUTH"
COMPOSE=(docker compose -f docker-compose.ldap.yml)
"${COMPOSE[@]}" up -d --force-recreate

echo "==> waiting for lldap"
for _ in $(seq 1 60); do
    curl -sf -m 2 "${LLDAP_URL}/health" >/dev/null 2>&1 && break
    sleep 1
done

echo "==> waiting for Vikunja"
for _ in $(seq 1 60); do
    curl -sf -m 2 "${VIKUNJA_URL}/api/v1/info" >/dev/null 2>&1 && break
    sleep 1
done

# lldap's GraphQL API creates the user; passwords go through OPAQUE, which
# GraphQL cannot do, so the image's own lldap_set_password sets it.
ADMIN_TOKEN=$(curl -sf -X POST "${LLDAP_URL}/auth/simple/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"${LLDAP_ADMIN_PASS}\"}" | jq -r .token)
[ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != null ] || { echo "lldap admin login failed" >&2; exit 1; }

echo "==> creating directory user ${LDAP_USER} (no-op if it exists)"
curl -sf -X POST "${LLDAP_URL}/api/graphql" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" -H 'Content-Type: application/json' \
    -d "{\"query\":\"mutation { createUser(user: {id: \\\"${LDAP_USER}\\\", email: \\\"${LDAP_USER}@ldap.dev.local\\\", displayName: \\\"LDAP Dev User\\\"}) { id } }\"}" \
    >/dev/null || true
docker exec mdone-lldap-dev /app/lldap_set_password \
    --base-url http://localhost:17170 \
    --admin-username admin --admin-password "${LLDAP_ADMIN_PASS}" \
    --username "${LDAP_USER}" --password "${LDAP_PASS}" >/dev/null

echo
echo "==> /api/v1/info"
curl -s "${VIKUNJA_URL}/api/v1/info" | jq '{version, auth}'

echo "==> POST /api/v2/login as ${LDAP_USER}"
curl -s -X POST "${VIKUNJA_URL}/api/v2/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${LDAP_USER}\",\"password\":\"${LDAP_PASS}\"}" \
    | jq 'with_entries(if (.value|type)=="string" and (.value|length)>24 then .value=(.value[:12]+"...") else . end)'

echo
echo "Vikunja:  ${VIKUNJA_URL}   (sign in as ${LDAP_USER} / ${LDAP_PASS})"
echo "lldap UI: ${LLDAP_URL}   (admin / ${LLDAP_ADMIN_PASS})"
echo "Down:     docker compose -f docker-compose.ldap.yml down   (data in vikunja-dev-data/ldap/)"
