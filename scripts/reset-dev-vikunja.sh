#!/usr/bin/env bash
# Nuke the local dev Vikunja and start fresh.
# Stops the container, deletes the volume, brings it back up. Does NOT re-seed — run seed-dev-vikunja.sh after.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f docker-compose.dev.yml ]; then
  echo "docker-compose.dev.yml not found in $(pwd). Run this from the repo root." >&2
  exit 1
fi

echo "→ Stopping dev Vikunja"
docker compose -f docker-compose.dev.yml down -v

echo "→ Deleting volume data (vikunja-dev-data/)"
rm -rf vikunja-dev-data/

echo "→ Starting fresh"
docker compose -f docker-compose.dev.yml up -d

echo ""
echo "✓ Dev Vikunja reset."
echo "  Run scripts/seed-dev-vikunja.sh to populate sample data."
