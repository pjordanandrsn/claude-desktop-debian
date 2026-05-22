# Hands-free auto-updates (systemd)

Keeps Claude Desktop current automatically: an hourly `systemd` timer checks this
repo's [Releases](../../../releases) and installs a newer RPM when one appears.
Built for Fedora / Fedora Asahi (`aarch64`); see the notes for other setups.

## Install

```bash
# 1. updater script
sudo install -m 0755 auto-update/claude-desktop-update.sh /usr/local/bin/

# 2. systemd units
sudo install -m 0644 auto-update/claude-desktop-update.service /etc/systemd/system/
sudo install -m 0644 auto-update/claude-desktop-update.timer   /etc/systemd/system/

# 3. enable + start the hourly timer
sudo systemctl daemon-reload
sudo systemctl enable --now claude-desktop-update.timer

# (optional) pull the latest right now instead of waiting for the next tick
sudo systemctl start claude-desktop-update.service
journalctl -u claude-desktop-update.service -n 20 --no-pager
```

## Checking on it

```bash
systemctl list-timers claude-desktop-update.timer   # alive + next run
rpm -q claude-desktop                               # current version
```

## Notes

- Installs with `--nogpgcheck`: these Release RPMs are **unsigned** (built in CI
  from Anthropic's official, SHA-256-pinned Windows installer). Claude Desktop is
  Anthropic's proprietary app; this repo only repackages it for Linux.
- **Different source repo:** set `CLAUDE_DESKTOP_REPO=owner/name` (e.g. in the
  service's `Environment=`).
- **`x86_64`:** set `CLAUDE_DESKTOP_ARCH=x86_64`.
- Comparison is by Claude Desktop version (the `…+claudeX.Y.Z` part of the release
  tag) vs. the installed RPM's `%{VERSION}`; it only ever upgrades, never downgrades.
