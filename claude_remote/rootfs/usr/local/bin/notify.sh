#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Usage: notify.sh <title> <message> [link]
# Always creates a persistent notification; also calls notify_service if set.
# link is a Home Assistant path, for example the sign-in page.
set -euo pipefail

title="$1"
message="$2"
link="${3:-}"

bashio::log.info "${title}: ${message}"
ha-api.sh services/persistent_notification/create \
    "$(jq -nc --arg t "$title" --arg m "$message" --arg l "$link" \
        '{notification_id: "claude_remote", title: $t,
          message: (if $l == "" then $m else "\($m)\n\n[Open Claude Remote](\($l))" end)}')" \
    || bashio::log.warning "Persistent notification failed"

if bashio::config.has_value 'notify_service'; then
    service="$(bashio::config 'notify_service')"
    ha-api.sh "services/notify/${service#notify.}" \
        "$(jq -nc --arg t "$title" --arg m "$message" --arg l "$link" \
            '{title: $t, message: $m} + (if $l == "" then {} else {data: {url: $l, clickAction: $l}} end)')" \
        || bashio::log.warning "Notification via ${service} failed"
fi
