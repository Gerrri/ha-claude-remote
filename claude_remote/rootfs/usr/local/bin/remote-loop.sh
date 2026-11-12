#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Keeps `claude remote-control` running inside tmux window "remote".
# Waits for the sign-in (login-server.py), backs off on repeated failures.
set -euo pipefail

# Ctrl-C stops claude, not this loop (a handler, unlike '', is not inherited).
trap 'true' INT

# Kernel OOM killer: take Claude (and ha-mcp over stdio, a child) before anything else.
{ echo 1000 >/proc/self/oom_score_adj; } 2>/dev/null || true # some kernels apply it but report EINVAL

export HOMEASSISTANT_TOKEN="${SUPERVISOR_TOKEN}"
if bashio::config.has_value 'model'; then
    ANTHROPIC_MODEL="$(bashio::config 'model')"
    export ANTHROPIC_MODEL
fi

args=(
    # Default "create session in dir": one fixed session that Remote Control resumes after a
    # restart (shown offline meanwhile). Without it, every start gets a new environment.
    remote-control
    --capacity "$(bashio::config 'max_sessions')"
    --permission-mode "$(bashio::config 'permission_mode')"
    --remote-control-session-name-prefix "$(bashio::config 'session_name')"
)

SIGNED_IN_FILE=/tmp/signed-in # read by watchdog.sh for the Home Assistant sensor
CONFIG="${CLAUDE_CONFIG_DIR}/.claude.json"

# Answer Claude Code's one-time questions ahead: first-run setup (also for `claude` in the
# terminal), workspace trust and Remote Control consent.
accept_prompts() {
    [[ -f "$CONFIG" ]] || return 0
    # shellcheck disable=SC2016 # $ws is a jq variable
    jq -e --arg ws "$PWD" \
        '.hasCompletedOnboarding and .remoteDialogSeen and .projects[$ws].hasTrustDialogAccepted' \
        "$CONFIG" >/dev/null && return 0
    # shellcheck disable=SC2016
    (umask 077 && jq --arg ws "$PWD" \
        '.hasCompletedOnboarding = true | .remoteDialogSeen = true
         | .projects[$ws].hasTrustDialogAccepted = true' \
        "$CONFIG" >"$CONFIG.tmp")
    mv "$CONFIG.tmp" "$CONFIG"
}

# The fixed session connects to its MCP servers right at start. Give the ha-mcp HTTP
# server (an s6 service, slow to boot on a Pi) time to come up first.
wait_for_ha_mcp() {
    bashio::config.true 'enable_ha_mcp' \
        && [[ "$(bashio::config 'ha_mcp_transport')" == http ]] || return 0
    for _ in $(seq 60); do
        curl -s -o /dev/null -m 2 http://127.0.0.1:8086/mcp && return 0
        sleep 2 || true
    done
    echo "ha-mcp did not answer within 2 minutes; starting Remote Control anyway."
}

delay=5
failure_notified=false

while true; do
    if ! claude auth status >/dev/null 2>&1; then
        echo off >"$SIGNED_IN_FILE"
        notify.sh "Claude Remote: sign-in required" \
            "Open Claude Remote and sign in with your Claude account." "${LOGIN_URL:-}"
        echo "Not signed in. Open Claude Remote in the Home Assistant sidebar to sign in."
        until claude auth status >/dev/null 2>&1; do
            sleep 15 || true
        done
        echo "Signed in."
    fi
    echo on >"$SIGNED_IN_FILE"
    accept_prompts
    # Keep the Remote Control environment, and with it the chats, across app restarts:
    # Claude Code drops its pointer after 4 h without a write. If the server dropped the
    # environment meanwhile, Remote Control registers a new one by itself.
    # shortcut: relies on Claude Code's internal pointer file, recheck on Claude Code updates.
    touch -c "$CLAUDE_CONFIG_DIR"/projects/*/bridge-pointer.json
    wait_for_ha_mcp

    started=$(date +%s)
    nice -n 10 claude "${args[@]}" || true

    if (($(date +%s) - started < 60)); then
        delay=$((delay * 2 > 300 ? 300 : delay * 2))
    else
        delay=5
        failure_notified=false
    fi
    if ((delay == 300)) && ! $failure_notified; then
        notify.sh "Claude Remote: Remote Control keeps failing" \
            "Open the terminal in Claude Remote or check the app log (often the memory limit)." \
            "${LOGIN_URL:-}"
        failure_notified=true
    fi
    echo "Remote Control stopped. Restarting in ${delay}s (Ctrl-C to skip the wait)."
    sleep "$delay" || true
done
