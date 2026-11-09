#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Entry point: prepare /data, register MCP servers, then hand over to the watchdog.
set -euo pipefail

mkdir -p "$CLAUDE_CONFIG_DIR" /data/workspace

# Frontend path of this app's ingress page (sign-in), for notifications and the sensor.
# Not `export`: with-contenv gives every script the s6 container environment only.
printf '/app/%s' "$(bashio::app.slug)" >/run/s6/container_environment/LOGIN_URL

# Names this app registered last time, so the app options stay the single source of truth.
NAMES_FILE=/data/mcp-servers.txt

if [[ -f "$NAMES_FILE" ]]; then
    while read -r name; do
        claude mcp remove -s user "$name" >/dev/null 2>&1 || true
    done <"$NAMES_FILE"
fi
: >"$NAMES_FILE"

register_mcp() {
    if claude mcp add-json -s user "$1" "$2" >/dev/null; then
        echo "$1" >>"$NAMES_FILE"
        bashio::log.info "MCP server '$1' registered"
    else
        bashio::log.warning "Could not register MCP server '$1'"
    fi
}

if bashio::config.true 'enable_ha_mcp'; then
    if [[ "$(bashio::config 'ha_mcp_transport')" == stdio ]]; then
        register_mcp home-assistant '{"type":"stdio","command":"ha-mcp"}'
    else
        register_mcp home-assistant '{"type":"http","url":"http://127.0.0.1:8086/mcp"}'
    fi
fi

while read -r server; do
    register_mcp "$(jq -r .name <<<"$server")" "$(jq -r .json <<<"$server")"
done < <(jq -c '.extra_mcp_servers[]' /data/options.json)

exec watchdog.sh
