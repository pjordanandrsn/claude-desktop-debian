#!/usr/bin/env bash
#
# claude-desktop-update.sh
#
# Installs newer Claude Desktop RPMs from this project's GitHub Releases.
#
# Reads the latest release, parses the Claude Desktop version from the
# "vX.Y.Z+claudeA.B.C" tag, and if it is newer than the installed package,
# downloads the matching .rpm asset and installs it with dnf. Built for
# Fedora / Fedora Asahi; run as root from the accompanying systemd timer.
#
#   Override the source repo:  CLAUDE_DESKTOP_REPO=owner/name
#   Override the arch:         CLAUDE_DESKTOP_ARCH=x86_64
#
set -euo pipefail

REPO="${CLAUDE_DESKTOP_REPO:-pjordanandrsn/claude-desktop-asahi}"
ARCH="${CLAUDE_DESKTOP_ARCH:-aarch64}"
PKG="claude-desktop"
API="https://api.github.com/repos/${REPO}/releases/latest"

log() { printf '%s  %s\n' "$(date -Is)" "$*"; }

# Serialize against overlapping runs (timer firing during a manual run).
exec 9>/run/claude-desktop-update.lock
flock -n 9 || { log "another run is in progress; exiting"; exit 0; }

# A 404 here means "no releases yet", which is not an error -- nothing to do.
resp=$(curl -sSL --max-time 30 -H "Accept: application/vnd.github+json" \
  -w $'\n%{http_code}' "$API" || true)
http_code=${resp##*$'\n'}
release_json=${resp%$'\n'*}
case "$http_code" in
  200) : ;;
  404) log "No releases published yet on ${REPO}. Nothing to do."; exit 0 ;;
  *)   log "ERROR: GitHub API returned HTTP ${http_code:-none} for ${REPO}"; exit 1 ;;
esac

tag=$(jq -r '.tag_name // empty' <<<"$release_json")
asset_url=$(jq -r --arg a "$ARCH" \
  'first(.assets[] | select(.name | endswith($a + ".rpm")) | .browser_download_url) // empty' \
  <<<"$release_json")
asset_name=$(jq -r --arg a "$ARCH" \
  'first(.assets[] | select(.name | endswith($a + ".rpm")) | .name) // empty' \
  <<<"$release_json")

if [[ -z "$tag" || -z "$asset_url" ]]; then
  log "No ${ARCH} .rpm in the latest release (tag='${tag:-none}'). Nothing to do."
  exit 0
fi

# Tag form: v2.0.12+claude1.8555.0  ->  Claude Desktop version 1.8555.0
latest_ver="${tag##*+claude}"
installed_ver=$(rpm -q --qf '%{VERSION}' "$PKG" 2>/dev/null || true)
log "installed=${installed_ver:-none}  latest=${latest_ver}  (release ${tag})"

# Only upgrade when the release is strictly newer than what's installed.
if [[ -n "$installed_ver" ]]; then
  newest=$(printf '%s\n%s\n' "$installed_ver" "$latest_ver" | sort -V | tail -1)
  if [[ "$latest_ver" == "$installed_ver" || "$newest" == "$installed_ver" ]]; then
    log "Already on the newest published version. Nothing to do."
    exit 0
  fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
log "Downloading ${asset_name} ..."
curl -fsSL --max-time 600 -o "$tmp/$asset_name" "$asset_url"

# Release RPMs are unsigned (built in CI from Anthropic's official, SHA-256-pinned
# Windows installer), so signature checking is disabled for this local file.
log "Installing ${asset_name} ..."
dnf install -y --nogpgcheck "$tmp/$asset_name"

log "Updated: ${PKG} is now $(rpm -q --qf '%{VERSION}-%{RELEASE}' "$PKG")"
