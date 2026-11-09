# Changelog

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
