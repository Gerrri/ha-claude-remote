#!/usr/bin/env bash
# Self-check for the pure helpers in watchdog.sh. Runs with GNU and BusyBox tools.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export CLAUDE_CONFIG_DIR="$tmp"

# shellcheck source=claude_remote/rootfs/usr/local/bin/watchdog.sh
source "$(dirname "$0")/../claude_remote/rootfs/usr/local/bin/watchdog.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ "$(last_activity 100)" == 100 ]] || fail "no projects dir -> start time"

mkdir -p "$tmp/projects/a" "$tmp/projects/b"
touch -d @5000 "$tmp/projects/a/one.jsonl"
touch -d @3000 "$tmp/projects/b/two.jsonl"
touch -d @9999 "$tmp/projects/b/ignored.txt"
[[ "$(last_activity 100)" == 5000 ]] || fail "newest transcript wins over start time"
[[ "$(last_activity 7000)" == 7000 ]] || fail "start time wins over older transcripts"

(($(container_rss_mb) > 0)) || fail "container RSS is positive"
(($(mem_available_mb) > 0)) || fail "MemAvailable is positive"

echo "watchdog_test: ok"
