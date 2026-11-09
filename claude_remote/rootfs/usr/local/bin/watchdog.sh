#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Every 30 s: keep the tmux session alive, enforce idle timeout,
# maximum runtime and memory limits.
set -euo pipefail

PROJECTS_DIR="${CLAUDE_CONFIG_DIR}/projects"
WORKSPACE=/data/workspace

# Epoch of the newest transcript write, but not older than $1.
# Transcripts change on every prompt and every Claude action.
last_activity() {
    local newest
    newest=$(find "$PROJECTS_DIR" -name '*.jsonl' -exec stat -c %Y {} + 2>/dev/null \
        | sort -n | tail -n 1) || true
    newest=${newest:-0}
    echo $((newest > $1 ? newest : $1))
}

# Sum of private (anonymous) RSS of all processes in this container, in MB.
# Not VmRSS: it counts shared pages, like the claude binary, once per process.
container_rss_mb() {
    { cat /proc/[0-9]*/status 2>/dev/null || true; } \
        | awk '/^RssAnon:/ { s += $2 } END { print int(s / 1024) }'
}

# MemAvailable of the host (/proc/meminfo is not namespaced), in MB.
mem_available_mb() {
    awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo
}

ensure_session() {
    if ! tmux has-session -t claude 2>/dev/null; then
        tmux new-session -d -s claude -n remote -c "$WORKSPACE" remote-loop.sh
        tmux new-window -d -t claude -n shell -c "$WORKSPACE"
    elif ! tmux list-windows -t claude -F '#W' | grep -x remote >/dev/null; then
        tmux new-window -d -t claude -n remote -c "$WORKSPACE" remote-loop.sh
    fi
}

stop_app() {
    notify.sh "Claude Remote stopped" "$1 Start it again from Home Assistant."
    bashio::app.stop
    exit 0
}

main() {
    local start now idle max_runtime max_mem min_free rss avail last_mem_notify=0
    start=$(date +%s)
    idle=$(bashio::config 'idle_timeout_min')
    max_runtime=$(bashio::config 'max_runtime_min')
    max_mem=$(bashio::config 'max_memory_mb')
    min_free=$(bashio::config 'min_free_mb')

    while true; do
        ensure_session
        now=$(date +%s)

        if ((max_runtime > 0 && now - start >= max_runtime * 60)); then
            stop_app "Maximum runtime of ${max_runtime} min reached."
        fi
        if ((idle > 0 && now - $(last_activity "$start") >= idle * 60)); then
            stop_app "No activity for ${idle} min."
        fi

        rss=$(container_rss_mb)
        avail=$(mem_available_mb)
        if ((rss > max_mem || avail < min_free)) && pgrep -x claude >/dev/null; then
            bashio::log.warning "Memory: app ${rss} MB, host free ${avail} MB. Stopping Claude."
            pkill -x claude || true
            if ((now - last_mem_notify > 3600)); then
                notify.sh "Claude Remote: memory limit" \
                    "Claude was stopped (app ${rss} MB, host free ${avail} MB). It restarts automatically."
                last_mem_notify=$now
            fi
        fi

        sleep 30
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
