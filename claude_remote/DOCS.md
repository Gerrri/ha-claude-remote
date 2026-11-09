# Claude Remote

Runs [Claude Code](https://code.claude.com/docs) with
[Remote Control](https://code.claude.com/docs/en/remote-control) inside Home Assistant,
so you can steer it from the Claude app or claude.ai/code. Claude reaches Home Assistant
through [ha-mcp](https://github.com/homeassistant-ai/ha-mcp).

> **Warning:** Claude gets administrator-level control over Home Assistant and a root
> shell inside this app. AI actions can be wrong or destructive. Create a full backup
> first and read the risks in the repository README.

## First login

1. Start the app, then open **Claude Remote** in the sidebar (or click the link in the
   "sign-in required" notification).
2. Click **Open Claude sign-in** and sign in with your Claude account (Pro, Max, Ultra,
   Team or Enterprise). Copy the code shown at the end.
3. Paste the code into the field on the page and click **Sign in**.
4. In the Claude app or at claude.ai/code, open Claude Code and start a session on
   this machine. It is listed under the host name of Home Assistant (default
   `homeassistant`, change it under **Settings → System → Network**).

The app answers the workspace trust and Remote Control questions by itself. When the
sign-in expires, you get the same notification and use the same page.

The page links to a terminal with two tmux windows: `remote` (the Remote Control
server) and `shell`. Switch with `Ctrl-b n`. Selecting text works with the mouse as
usual.

## Options

| Option | Default | Description |
|---|---|---|
| `session_name` | `home-assistant` | Prefix of session names in the Claude app. |
| `idle_timeout_min` | `60` | Stop the app after this many minutes without a prompt or Claude activity. `0` = never. *Experimental:* activity is the modification time of the session transcripts. |
| `max_runtime_min` | `0` | Stop the app after this many minutes. `0` = unlimited. |
| `permission_mode` | `default` | `default` asks before every change, `plan` only plans, `acceptEdits` applies file edits without asking. |
| `model` | (empty) | Optional model or alias, for example `sonnet`. |
| `language` | (empty) | Language Claude answers in, for example `german`. Empty = Claude decides. Written to Claude Code's `language` setting at every start. |
| `max_sessions` | `1` | Concurrent sessions. Each one is its own Claude process. |
| `max_memory_mb` | `1024` | Stop Claude if all processes of this app together use more private memory (RSS without shared pages). |
| `min_free_mb` | `150` | Stop Claude if the host has less free memory, so Home Assistant keeps running. `0` = off. |
| `enable_ha_mcp` | `true` | Give Claude access to Home Assistant through ha-mcp. |
| `ha_mcp_transport` | `http` | `http` or `stdio`, see below. |
| `enable_rtk` | `true` | Save tokens: [rtk](https://github.com/rtk-ai/rtk) shortens the output of shell commands (git, ls, test runners, ...) before Claude reads it. Turn off if a command behaves differently than expected. |
| `extra_mcp_servers` | `[]` | List of `name` + `json`, as accepted by `claude mcp add-json`. |

Example for `extra_mcp_servers`:

```yaml
- name: my-server
  json: '{"type":"http","url":"http://my-mcp-server.example:8080/mcp"}'
```

The ha-mcp server is pre-configured as `home-assistant`. If you already run the official
ha-mcp app or integration, set `enable_ha_mcp: false` and add it here instead. Do not
connect both, which ha-mcp says can cause hangs.

### `ha_mcp_transport`: memory versus reliability

| | `http` (default) | `stdio` |
|---|---|---|
| How ha-mcp runs | one server, always on, loopback only | started by Claude inside each session |
| RAM while idle (no session) | ~130 MB for ha-mcp | 0 MB for ha-mcp |
| RAM with one session | ~130 MB | ~130 MB |
| Reliability | recommended by ha-mcp | ha-mcp reports known stdio connection issues |

`stdio` saves about **130 MB while no session is open**. The figure was measured on
amd64 with ha-mcp 9.1.2 while idle. Actual usage grows with your setup.

### Memory overview

Measured on amd64 while idle, before login:

| Process | RSS |
|---|---|
| Claude Code (Remote Control server) | ~180 MB, peak ~210 MB |
| ha-mcp (`http`) | ~130 MB |
| ttyd, nginx, tmux, sign-in page | ~45 MB |
| **Whole app** | **~325 MB** |

A running session adds another Claude process. Estimated at 200–300 MB, not measured.
Large tasks can push the app above 1 GB.

Home Assistant apps cannot set Docker memory limits through their configuration.
This app protects the host in other ways instead:

- Claude, ha-mcp, ttyd and nginx run with `oom_score_adj=1000`, so the kernel's OOM
  killer ends them first, before Home Assistant.
- Claude and ha-mcp run with lower CPU priority (`nice`).
- The watchdog stops Claude when the app's private memory exceeds `max_memory_mb`, or
  when the host's free memory drops below `min_free_mb`. Claude restarts automatically
  once memory is available again.

## Starting and stopping

The app does not start on boot by default. Turn on **Start on boot** on the app's Info
tab if you want that. Use `hassio.addon_start` and `hassio.addon_stop` in scripts or
automations, or enable the app's switch in the Supervisor integration. The app also
provides `binary_sensor.claude_remote_signed_in`. A dashboard card with both and a
sign-in button is in the repository README. When the idle timeout or `max_runtime_min` stops the app, you get a
notification. The app cannot be started from the Claude app, so start it from Home
Assistant.

## Data and backups

Login, settings and transcripts are stored in `/data/claude`. That folder is excluded
from Home Assistant backups. After restoring a backup you must sign in again.
