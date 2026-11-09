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

[![Open your Home Assistant instance and show the add app repository dialog with this repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FGerrri%2Fha-claude-remote)

Manual: **Settings → Apps → App store → ⋮ (top right) → Repositories**, then add
`https://github.com/Gerrri/ha-claude-remote`. Older Home Assistant versions call this
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
- A small sign-in page (Home Assistant ingress only) handles the Claude login. A web
  terminal (ttyd) next to it shows the Remote Control server.
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

## Requirements

- Home Assistant OS or Supervised (apps are needed), on aarch64 or amd64.
- Enough free RAM: the app uses ~325 MB while idle and can pass 1 GB during large tasks.
  Raspberry Pi 4/5 with 4 GB works with the defaults (`max_sessions: 1`), 8 GB is
  comfortable, a Raspberry Pi 3 (1 GB) is not recommended. Check free memory under
  **Settings → System → Hardware** before installing.
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
3. Review the options (see the [app documentation](claude_remote/DOCS.md)), then start
   the app.

## First login

1. Start the app. A notification **"Claude Remote: sign-in required"** appears.
2. Click **Open Claude Remote** in the notification, or open **Claude Remote** in the
   sidebar.
3. Click **Open Claude sign-in**, sign in with your Claude account and copy the code
   shown at the end.
4. Paste the code into the field on the page and click **Sign in**.

That is all. The app accepts the workspace trust question and the Remote Control
question by itself, and Remote Control starts within a few seconds. Open the Claude app
or claude.ai/code → Claude Code and start a session on this machine. Session names
start with `session_name`.

When the sign-in expires later, you get the same notification and use the same page.

*Experimental:* the sign-in page was tested with the real `claude auth login` up to a
rejected code. A successful sign-in could not be tested without a Claude account.

The page links to a terminal: a tmux session with the windows `remote` (Remote Control
server) and `shell`. Switch with `Ctrl-b n`.

## Options

All options, the `ha_mcp_transport` trade-off and the measured memory figures are in the
[app documentation](claude_remote/DOCS.md). Home Assistant shows the same text on the
app's **Documentation** tab.

## Start, stop and dashboard

The app does not start on boot. Turn on **Start on boot** on the app's Info tab if you
want that. The Claude app cannot start a stopped app, so start it from Home Assistant.

Three entities give you everything on a dashboard:

| Entity | What it shows / does | Source |
|---|---|---|
| `switch.claude_remote` | On while the app runs. Turn on to start, off to stop. | Home Assistant's Supervisor integration, **disabled by default** |
| `binary_sensor.claude_remote_signed_in` | On while Claude is signed in. Attribute `sign_in_url` links to the sign-in page. | This app, while it runs |
| Sign-in page | Button that opens the page from [First login](#first-login). | Dashboard card below |

Enable the switch once: **Settings → Devices & services → Supervisor → Claude Remote**
(the device), open the disabled entity and turn on **Enabled**. Its entity ID follows
the app name; if yours differs, pick it from the list in the card editor.

The sign-in sensor is set by the app every 30 seconds while it runs. After a Home
Assistant restart it is missing until the app sends it again, and it keeps its last
value while the app is stopped.

Dashboard card (**Edit dashboard → Add card → Manual**). Replace `xxxxxxxx_claude_remote`
with the app slug, which you find in the address bar when the app page is open:

```yaml
type: entities
title: Claude Remote
entities:
  - entity: switch.claude_remote
    name: Running
  - entity: binary_sensor.claude_remote_signed_in
    name: Signed in
  - type: button
    name: Sign-in page
    icon: mdi:login
    action_name: Open
    tap_action:
      action: navigate
      navigation_path: /app/xxxxxxxx_claude_remote
```

On older Home Assistant versions the page path is `/hassio/ingress/xxxxxxxx_claude_remote`.

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

- **"sign-in required" notification / login expired:** open the sign-in page and sign in
  again. `claude auth status` in the terminal's `shell` window shows the current state.
- **"That code wasn't accepted":** the code is single-use and belongs to one link. The
  page shows a new link; sign in again with it and paste the new code.
- **Session does not appear in the Claude app:** look at the `remote` window.
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
