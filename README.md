# Claude Remote for Home Assistant

A Home Assistant app (formerly called add-on) that runs
[Claude Code](https://code.claude.com/docs) with
[Remote Control](https://code.claude.com/docs/en/remote-control) on your Home Assistant
machine. You steer it from the Claude mobile app or claude.ai/code, and it controls
Home Assistant through [ha-mcp](https://github.com/homeassistant-ai/ha-mcp).

> **Unofficial project.** It is not affiliated with, endorsed by or supported by
> Anthropic or Home Assistant / Open Home Foundation.

**Status: experimental.** Parts marked *experimental* below could not be tested without
a real Home Assistant instance and a Claude account.

<!-- TODO: replace GITHUB_USER/REPO_NAME once the repository is public -->
[![Open your Home Assistant instance and show the add app repository dialog with this repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FGITHUB_USER%2FREPO_NAME)

Manual: **Settings → Apps → App store → ⋮ (top right) → Repositories**, then add
`https://github.com/GITHUB_USER/REPO_NAME`. Older Home Assistant versions call this
**Settings → Add-ons → Add-on store**.

## What it does

```text
Claude app / claude.ai  ⇄  Anthropic servers  ⇄  Claude Remote app  →  ha-mcp  →  Home Assistant
   (your phone)              (HTTPS relay)        (claude remote-control,   (loopback)   (Supervisor API)
                                                   outbound HTTPS only)
```

- `claude remote-control` runs permanently and only makes outbound HTTPS connections.
  No ports are opened.
- ha-mcp connects to Home Assistant through the Supervisor proxy
  (`http://supervisor/core`) with the app's automatic token. No long-lived access token
  is needed.
- A web terminal (ttyd behind nginx, Home Assistant ingress only) is used for the
  one-time login and to watch the Remote Control server.
- A watchdog stops the app after an idle timeout or a maximum runtime, and stops Claude
  when memory runs low.

## Disclaimer / risks

**Read this before installing.**

- **Claude controls your home.** Through ha-mcp, Claude acts as a Home Assistant
  administrator: devices, automations, scripts, configuration. There is no per-entity
  allow-list in this app. Claude also gets a root shell inside the app container, which
  holds the Supervisor token.
- **AI actions can be wrong**, including destructive ones: deleted automations, broken
  configuration, devices switched at the wrong time.
- **Locks, alarm systems, garage doors and similar:** if you cannot accept Claude
  operating them by mistake, do not use this app on that installation. At least keep
  `permission_mode` at `default` (Claude asks before every action) or `plan`.
- **Your Claude credentials** are stored in the app's storage (`/data/claude`). That
  folder is excluded from Home Assistant backups. Anyone with administrator access to
  your Home Assistant can open the terminal and use your Claude account.
- **Remote Control is a new Claude Code feature.** Anthropic can change or restrict it
  at any time, which may break this app.
- **Usage counts against your Claude subscription limits.**
- **No warranty. Use at your own risk** (see [License](#license)).

## Backup first

Before the first use, create a full backup: **Settings → System → Backups → Back up
now**. Ideally make it encrypted and store it off the device (for example on a NAS or
in the cloud).

## Memory (RAM)

Check free memory before installing (**Settings → System → Hardware**, or a system
monitor app).

| Situation | RAM used by this app |
|---|---|
| Idle, no session open (measured on amd64) | ~310 MB, or ~180 MB with `ha_mcp_transport: stdio` |
| One active session (estimate, not measured) | ~500–700 MB |
| Peaks during large tasks (estimate) | over 1 GB |

- Raspberry Pi 3 (1 GB): **not recommended.**
- Raspberry Pi 4/5 with 4 GB: workable with the defaults (`max_sessions: 1`).
- 8 GB: comfortable.

Home Assistant apps cannot set Docker memory limits through their configuration.
This app protects the host in other ways instead:

- All of its processes run with `oom_score_adj=1000`, so the kernel's OOM killer
  ends them first, before Home Assistant.
- Claude and ha-mcp run with lower CPU priority (`nice`).
- The watchdog stops Claude when the app's total RSS exceeds `max_memory_mb`, or when
  the host's free memory drops below `min_free_mb`. Claude restarts automatically
  once memory is available again.

## Requirements

- Home Assistant OS or Supervised (apps are needed), on aarch64 or amd64.
- A Claude **Pro, Max, Ultra, Team or Enterprise** subscription. On Team and
  Enterprise an owner must enable Remote Control in the Claude Code admin settings.
- An API key is **not** enough. `claude setup-token` / `CLAUDE_CODE_OAUTH_TOKEN` do
  not work with Remote Control either.
- Claude Code 2.1.319 is bundled. The app pins this version and disables Claude Code's
  auto-updater. New versions arrive with app updates.

## Installation

1. Add this repository (button or manual steps above).
2. Install **Claude Remote**. The image is built on your device, which takes several
   minutes on a Raspberry Pi.
3. Review the options (see below), then start the app.

## First login

1. Open **Claude Remote** in the sidebar (or **Open Web UI**).
2. The terminal shows a sign-in URL. Open it in your browser, sign in, copy the code and
   paste it into the terminal. If the URL is split across several lines, paste it into
   the browser address bar anyway: browsers remove the line breaks there.
3. Answer `y` to `Trust /data/workspace?` and `y` to `Enable Remote Control?`.
   Both questions are asked once.
4. Open the Claude app or claude.ai/code → Claude Code and start a session on this
   machine. Session names start with `session_name`.

*Experimental:* the login flow was tested up to the code prompt. Everything after a
successful sign-in could not be tested without a Claude account.

The terminal is a tmux session with the windows `remote` (Remote Control server) and
`shell`. Switch with `Ctrl-b n`.

## Configuration

| Option | Default | Description |
|---|---|---|
| `session_name` | `home-assistant` | Prefix of session names shown in the Claude app. |
| `idle_timeout_min` | `60` | Stop the app after this many minutes without a prompt or Claude activity. `0` = never. *Experimental:* activity is the modification time of the session transcripts. |
| `max_runtime_min` | `0` | Stop the app after this many minutes. `0` = unlimited. |
| `permission_mode` | `default` | `default`, `acceptEdits` or `plan`. |
| `model` | (empty) | Optional model or alias, for example `sonnet`. |
| `max_sessions` | `1` | Concurrent sessions. Each open session is its own Claude process (~200–300 MB, estimate). |
| `max_memory_mb` | `1024` | Stop Claude when the app's total RSS exceeds this. |
| `min_free_mb` | `150` | Stop Claude when the host has less free memory. `0` = off. |
| `enable_ha_mcp` | `true` | Connect ha-mcp. |
| `ha_mcp_transport` | `http` | `http`: one shared ha-mcp server on loopback (~130 MB always). `stdio`: ha-mcp runs only inside a session, saving ~130 MB while idle, but ha-mcp reports known stdio issues. |
| `extra_mcp_servers` | `[]` | List of `{name, json}`. `json` is passed to `claude mcp add-json`. |
| `notify_service` | (empty) | For example `notify.mobile_app_my_phone`. A persistent notification is always created. |

Example for `extra_mcp_servers`:

```yaml
- name: my-server
  json: '{"type":"http","url":"http://my-mcp-server.example:8080/mcp"}'
```

The ha-mcp server is pre-configured as `home-assistant`. If you already run the official
ha-mcp app or integration, set `enable_ha_mcp: false` and add it here instead. Do not
connect both, which ha-mcp says can cause hangs.

## Start and stop

The app does not start on boot. Turn on **Start on boot** on the app's Info tab if you
want that. The Claude app cannot start a stopped app, so start it from Home Assistant.
The slug looks like `xxxxxxxx_claude_remote`; copy it from the app page URL.

Script with start and stop buttons:

```yaml
script:
  claude_remote_start:
    alias: Start Claude Remote
    sequence:
      - action: hassio.addon_start
        data:
          addon: xxxxxxxx_claude_remote
  claude_remote_stop:
    alias: Stop Claude Remote
    sequence:
      - action: hassio.addon_stop
        data:
          addon: xxxxxxxx_claude_remote
```

Automation that stops it every night:

```yaml
automation:
  - alias: Stop Claude Remote at night
    triggers:
      - trigger: time
        at: "02:00:00"
    actions:
      - action: hassio.addon_stop
        data:
          addon: xxxxxxxx_claude_remote
```

## Troubleshooting

- **"sign-in required" notification / login expired:** open the terminal and repeat the
  login. `claude auth status` in the `shell` window shows the current state.
- **Session does not appear in the Claude app:** look at the `remote` window.
  - Unanswered trust or confirmation questions block the start.
  - On Team or Enterprise, Remote Control must be enabled by an owner.
  - Plain API keys do not work.
  - After a network outage of more than ~10 minutes the server exits and restarts by
    itself.
- **"Remote Control keeps failing" notification:** the server exits within a minute
  repeatedly. The `remote` window and the app log show the reason.
- **Not enough RAM / "memory limit" notification:** keep `max_sessions: 1`, switch to
  `ha_mcp_transport: stdio`, or raise `max_memory_mb` if the host has room.
- **The app stopped by itself:** the idle timeout or `max_runtime_min` was reached.
  The notification says which one.

## Credits

- [ha-mcp](https://github.com/homeassistant-ai/ha-mcp) by the homeassistant-ai
  contributors. Thank you for the MCP server that makes Home Assistant usable for Claude.
- [Claude Code](https://code.claude.com/docs) and
  [Remote Control](https://code.claude.com/docs/en/remote-control) by Anthropic.
- [Home Assistant community app base image](https://github.com/hassio-addons/app-base),
  [ttyd](https://github.com/tsl0922/ttyd), tmux and nginx.

## AI notice

This app was created with the help of AI (Claude). The code was not manually reviewed in
every detail. Please review it yourself before use.

## License

[MIT](LICENSE)
