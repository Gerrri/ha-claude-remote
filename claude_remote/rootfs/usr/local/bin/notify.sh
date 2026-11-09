#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Usage: notify.sh <title> <message>
# Always creates a persistent notification; also calls notify_service if set.
set -euo pipefail

title="$1"
message="$2"

call_service() {
    curl -fsS -m 10 -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$3" "http://supervisor/core/api/services/$1/$2" >/dev/null \
        || bashio::log.warning "Notification via $1.$2 failed"
}

bashio::log.info "${title}: ${message}"
call_service persistent_notification create \
    "$(jq -nc --arg t "$title" --arg m "$message" \
        '{notification_id: "claude_remote", title: $t, message: $m}')"

if bashio::config.has_value 'notify_service'; then
    service="$(bashio::config 'notify_service')"
    call_service notify "${service#notify.}" \
        "$(jq -nc --arg t "$title" --arg m "$message" '{title: $t, message: $m}')"
fi
