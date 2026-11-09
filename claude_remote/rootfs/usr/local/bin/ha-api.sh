#!/usr/bin/env bash
# Usage: ha-api.sh <path below /api/> <json>
# POST to Home Assistant Core through the Supervisor proxy.
set -euo pipefail

exec curl -fsS -m 10 -o /dev/null -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$2" "http://supervisor/core/api/$1"
