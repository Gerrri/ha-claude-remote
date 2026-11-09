#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Keeps `claude remote-control` running inside tmux window "remote".
# Runs the interactive login here when needed, backs off on repeated failures.
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
    remote-control
    --no-create-session-in-dir
    --capacity "$(bashio::config 'max_sessions')"
    --permission-mode "$(bashio::config 'permission_mode')"
    --remote-control-session-name-prefix "$(bashio::config 'session_name')"
)

delay=5
login_notified=false
failure_notified=false

while true; do
    if ! claude auth status >/dev/null 2>&1; then
        if ! $login_notified; then
            notify.sh "Claude Remote: sign-in required" \
                "Open Claude Remote in the Home Assistant sidebar and follow the login prompt."
            login_notified=true
        fi
        echo "Not signed in. Open the URL below, sign in, then paste the code here."
        claude auth login || sleep 30
        continue
    fi
    login_notified=false

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
            "Open Claude Remote in the sidebar or check the app log (often the memory limit)."
        failure_notified=true
    fi
    echo "Remote Control stopped. Restarting in ${delay}s (Ctrl-C to skip the wait)."
    sleep "$delay" || true
done
