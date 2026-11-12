# Changelog

## 0.5.3

- Fix: Home Assistant showed the app as failed after every stop (exit code 143). The
  watchdog, the app's main process, now exits cleanly when the app stops.

## 0.5.2

- Fix: Home Assistant tools (ha-mcp) were missing in the fixed session after a start.
  The session connected before the ha-mcp server was up (about 9 s on amd64, longer
  on a Pi). Remote Control now waits for ha-mcp, at most 2 minutes.

## 0.5.1

- Fix: chats did not survive a restart. Remote Control now keeps one fixed session
  (Claude Code's default), resumes it after a restart and shows it as offline while
  the app is stopped. Before, `--no-create-session-in-dir` made Remote Control skip
  its saved environment, so every start began from scratch.

## 0.5.0

- Chats survive app restarts, also after more than 4 hours: the app keeps Claude Code's
  pointer to the Remote Control environment fresh, so the next start reconnects it.
- **Sign out** button on the page when signed in. It stops Remote Control gracefully,
  then removes the login.
- README: new Installation, Setup and Daily use sections.

## 0.4.1

- App icon and logo.

## 0.4.0

- Renamed to "Claude Remote Control for Home Assistant (unofficial)". The sidebar keeps
  the short title "Claude Remote".
- The sign-in page shows that the login is being set up after you send the code.
- Stopping the app (also before an uninstall) now ends Remote Control gracefully: it
  stops its sessions and marks the machine offline in the Claude app instead of
  leaving a dead entry. The next start reuses the same entry.

## 0.3.0

- New option `language`: the language Claude answers in, for example `german`.
- New option `enable_rtk` (on by default): [rtk](https://github.com/rtk-ai/rtk) 1.2.0
  (Apache-2.0 edition) shortens shell command output to save tokens.
- Removed option `notify_service`. Notifications appear as persistent notifications in
  Home Assistant.

## 0.2.2

- The Claude app shows this machine under the Home Assistant host name (default
  `homeassistant`) instead of the random container name.

## 0.2.1

- Fix: Remote Control did not start after the first sign-in. The link to the sign-in
  page did not reach the scripts, and the Remote Control loop crashed while waiting
  for the sign-in.
- Claude Code's first-run setup is skipped, also for `claude` in the terminal.

## 0.2.0

- Sign-in page instead of the terminal login: open the link, paste the code, done.
  The workspace trust and Remote Control questions are answered automatically.
- New `binary_sensor.claude_remote_signed_in` with a link to the sign-in page.
- Notifications link to the app page (also on the mobile app).
- Watchdog counts only private memory; dependencies of ha-mcp are pinned.

## 0.1.0

- Initial release: Claude Code Remote Control (Claude Code 2.1.319), ha-mcp 9.1.2,
  login terminal via ingress, idle/runtime/memory watchdog.
