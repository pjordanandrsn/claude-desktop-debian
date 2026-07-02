#!/usr/bin/env bash
#
# Update Claude Desktop from this repository's latest GitHub Release.
#
# Intended for fleet machines (NAS containers, VMs, workstations) that
# install the .deb build. Queries the latest release, downloads the
# .deb for this CPU architecture, verifies the asset digest when the
# API provides one, and installs it with apt-get. Idempotent: exits 0
# without downloading when the installed version already matches.
#
# Usage (as root):
#     ./update-claude-desktop.sh [owner/repo]
#
# owner/repo defaults to pjordanandrsn/claude-desktop-debian.

repo="${1:-pjordanandrsn/claude-desktop-debian}"
api_url="https://api.github.com/repos/${repo}/releases/latest"

err() {
	echo "update-claude-desktop: $*" >&2
}

detect_arch() {
	case "$(uname -m)" in
		x86_64) echo 'amd64' ;;
		aarch64) echo 'arm64' ;;
		*)
			err "unsupported architecture: $(uname -m)"
			return 1
			;;
	esac
}

main() {
	if (( EUID != 0 )); then
		err 'must run as root (apt-get install); re-run with sudo'
		return 1
	fi

	# Claude Desktop installs into a Debian-style userland. A NAS
	# host shell (QNAP QTS, Synology DSM) has neither apt nor dpkg —
	# run this inside the container or VM that hosts the app instead.
	if ! command -v apt-get > /dev/null 2>&1 ||
		! command -v dpkg-deb > /dev/null 2>&1; then
		err 'apt-get/dpkg not found: this looks like a NAS host'
		err 'shell, not the Debian environment Claude Desktop is'
		err 'installed in. Run this script inside that container or'
		err 'VM (e.g. docker exec <container> ... on Container'
		err 'Station).'
		return 1
	fi

	local arch
	arch=$(detect_arch) || return 1

	local json
	json=$(curl -fsSL "$api_url") || {
		err "failed to query ${api_url}"
		return 1
	}

	# BusyBox-safe extraction (no grep -P): isolate the download-url
	# fields, keep the one whose asset name matches this arch's .deb,
	# then strip down to the bare URL between the value quotes.
	local deb_url
	deb_url=$(printf '%s\n' "$json" |
		grep -oE '"browser_download_url" *: *"[^"]*"' |
		grep -- "_${arch}\.deb\"" |
		head -n 1 |
		cut -d'"' -f4)
	if [[ -z $deb_url ]]; then
		err "no .deb asset for ${arch} in the latest release"
		return 1
	fi

	# Debian version is embedded in the asset name:
	# claude-desktop_<claudeVer>-<repoVer>_<arch>.deb
	local new_version current_version asset_file
	asset_file=$(basename "$deb_url")
	new_version=${asset_file#claude-desktop_}
	new_version=${new_version%%_*}
	current_version=$(dpkg-query -W -f='${Version}' \
		claude-desktop 2>/dev/null)
	if [[ -n $current_version && $current_version == "$new_version" ]]; then
		echo "Already up to date (${current_version})"
		return 0
	fi

	local tmp_dir
	tmp_dir=$(mktemp -d) || return 1
	trap 'rm -rf "$tmp_dir"' EXIT

	local deb_path
	deb_path="$tmp_dir/$(basename "$deb_url")"
	echo "Downloading $(basename "$deb_url")..."
	curl -fSL -o "$deb_path" "$deb_url" || {
		err "download failed: ${deb_url}"
		return 1
	}

	# Verify against the release asset digest when jq is available;
	# otherwise TLS to github.com is the integrity boundary and the
	# dpkg sanity check below still catches truncation.
	if command -v jq > /dev/null 2>&1; then
		local digest
		digest=$(printf '%s' "$json" | jq -r --arg u "$deb_url" \
			'.assets[] | select(.browser_download_url==$u)
				| .digest // empty')
		if [[ $digest == sha256:* ]]; then
			local actual _
			read -r actual _ < <(sha256sum "$deb_path")
			if [[ "sha256:$actual" != "$digest" ]]; then
				err 'sha256 mismatch on downloaded package'
				err "  expected: $digest"
				err "  actual:   sha256:$actual"
				return 1
			fi
			echo 'sha256 verified'
		fi
	fi

	dpkg-deb --info "$deb_path" > /dev/null || {
		err 'downloaded file is not a valid Debian package'
		return 1
	}

	echo "Installing claude-desktop ${new_version}..."
	apt-get install -y "$deb_path" || {
		err 'apt-get install failed'
		return 1
	}

	echo "Updated claude-desktop to ${new_version}"
	echo 'Restart the app on this machine to pick up the new version.'
}

main "$@"
