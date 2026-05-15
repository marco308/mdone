#!/usr/bin/env bash
# Seed the local dev Vikunja with sample projects, labels, and tasks.
# Idempotent: safe to run multiple times — re-registers user as no-op, but creates duplicate projects/tasks each run.
# For a clean slate, run scripts/reset-dev-vikunja.sh first.
#
# Refuses to run against anything other than localhost by default — override with VIKUNJA_URL only if you know what you're doing.

set -euo pipefail

VIKUNJA_URL="${VIKUNJA_URL:-http://localhost:3456}"
USERNAME="${VIKUNJA_USER:-devuser}"
PASSWORD="${VIKUNJA_PASSWORD:-devpassword}"
EMAIL="${VIKUNJA_EMAIL:-devuser@dev.local}"

# Safety: only allow localhost / 127.0.0.1 unless explicitly overridden
if [[ "$VIKUNJA_URL" != http://localhost:* && "$VIKUNJA_URL" != http://127.0.0.1:* ]]; then
  if [[ "${ALLOW_NON_LOCAL:-}" != "1" ]]; then
    echo "Refusing to seed against $VIKUNJA_URL (not localhost). Set ALLOW_NON_LOCAL=1 to override." >&2
    exit 1
  fi
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install with: brew install jq" >&2
  exit 1
fi

echo "→ Seeding $VIKUNJA_URL"

# Wait for Vikunja to be ready
for i in {1..30}; do
  if curl -fsS "$VIKUNJA_URL/api/v1/info" >/dev/null 2>&1; then
    break
  fi
  if [ "$i" = "30" ]; then
    echo "Vikunja never became ready at $VIKUNJA_URL. Is it running?" >&2
    exit 1
  fi
  sleep 1
done

# Register user (ignore failure — user may already exist)
curl -fsS -X POST "$VIKUNJA_URL/api/v1/register" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"email\":\"$EMAIL\"}" \
  >/dev/null 2>&1 || true

# Log in
TOKEN=$(curl -fsS -X POST "$VIKUNJA_URL/api/v1/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" | jq -r .token)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Login failed for $USERNAME. If you reset the volume, the user may need re-registering — re-run this script." >&2
  exit 1
fi

auth=(-H "Authorization: Bearer $TOKEN")

put_project() {
  local title="$1" desc="$2"
  curl -fsS -X PUT "$VIKUNJA_URL/api/v1/projects" "${auth[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"title\":\"$title\",\"description\":\"$desc\"}" | jq -r .id
}

put_task() {
  local project_id="$1" body="$2"
  curl -fsS -X PUT "$VIKUNJA_URL/api/v1/projects/$project_id/tasks" "${auth[@]}" \
    -H 'Content-Type: application/json' \
    -d "$body" | jq -r .id
}

put_label() {
  local title="$1" color="$2"
  curl -fsS -X PUT "$VIKUNJA_URL/api/v1/labels" "${auth[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"title\":\"$title\",\"hex_color\":\"$color\"}" | jq -r .id
}

complete_task() {
  # Vikunja's POST /tasks/{id} is a full replace, not a patch — fetch first, merge done=true, POST back.
  local task_id="$1"
  local merged
  merged=$(curl -fsS "$VIKUNJA_URL/api/v1/tasks/$task_id" "${auth[@]}" | jq '.done = true')
  curl -fsS -X POST "$VIKUNJA_URL/api/v1/tasks/$task_id" "${auth[@]}" \
    -H 'Content-Type: application/json' \
    -d "$merged" >/dev/null
}

echo "→ Creating projects"
WORK=$(put_project "Work" "Day job tasks")
HOME=$(put_project "Home" "Personal stuff")
SIDE=$(put_project "Side projects" "Tinkering")

echo "→ Creating labels"
URGENT=$(put_label "urgent" "ff4d4f")
WAITING=$(put_label "waiting" "fadb14")
DEEP=$(put_label "deep-work" "1890ff")

echo "→ Creating tasks"
# Mix of: due dates, priorities, descriptions, and completed tasks for testing filters/history.
TOMORROW=$(date -u -v+1d +"%Y-%m-%dT09:00:00Z" 2>/dev/null || date -u -d "+1 day" +"%Y-%m-%dT09:00:00Z")
NEXT_WEEK=$(date -u -v+7d +"%Y-%m-%dT09:00:00Z" 2>/dev/null || date -u -d "+7 days" +"%Y-%m-%dT09:00:00Z")
YESTERDAY=$(date -u -v-1d +"%Y-%m-%dT09:00:00Z" 2>/dev/null || date -u -d "-1 day" +"%Y-%m-%dT09:00:00Z")

put_task "$WORK" "{\"title\":\"Write quarterly report\",\"priority\":3,\"due_date\":\"$TOMORROW\",\"description\":\"Focus on Q1 wins and Q2 plan.\"}" >/dev/null
put_task "$WORK" "{\"title\":\"Review PR #847\",\"priority\":2,\"due_date\":\"$TOMORROW\"}" >/dev/null
put_task "$WORK" "{\"title\":\"1:1 prep — manager\",\"priority\":2,\"due_date\":\"$NEXT_WEEK\"}" >/dev/null
DONE_ID=$(put_task "$WORK" "{\"title\":\"Send invoice — March\",\"priority\":1,\"due_date\":\"$YESTERDAY\"}")
complete_task "$DONE_ID"

put_task "$HOME" "{\"title\":\"Book dentist\",\"priority\":1}" >/dev/null
put_task "$HOME" "{\"title\":\"Renew passport\",\"priority\":4,\"due_date\":\"$NEXT_WEEK\",\"description\":\"Photos already in the Drive folder.\"}" >/dev/null

put_task "$SIDE" "{\"title\":\"Try the focus-time outbox (#62)\",\"priority\":2,\"description\":\"Local SwiftData → homelab service.\"}" >/dev/null
put_task "$SIDE" "{\"title\":\"Polish onboarding copy\",\"priority\":1}" >/dev/null

echo ""
echo "✓ Done."
echo ""
echo "  URL:      $VIKUNJA_URL"
echo "  Web UI:   $VIKUNJA_URL"
echo "  Login:    $USERNAME / $PASSWORD"
echo ""
echo "Point mDone at $VIKUNJA_URL in the login screen."
