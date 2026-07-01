#!/usr/bin/env bash
#
# Update Claude Desktop from this PRIVATE repository's latest release.
#
# Private-repo variant: release assets are not publicly downloadable,
# so every request authenticates with a fine-grained PAT (read-only
# Contents permission on this one repository). Assets are fetched via
# the asset-id endpoint; curl drops the Authorization header on the
# cross-host redirect to short-lived storage URLs, so the token never
# leaves the GitHub API host.
#
# Token sources, in order:
#     $GH_TOKEN, $GITHUB_TOKEN, /etc/claude-desktop-fleet.token
#
# Usage (as root):
#     ./update-claude-desktop.sh [owner/repo]
#
# owner/repo defaults to pjordanandrsn/claude-desktop-fleet.
#
# Requires: curl, jq (apt-get install -y jq)

repo="${1:-pjordanandrsn/claude-desktop-fleet}"
api_base="https://api.github.com/repos/${repo}"

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

load_token() {
	if [[ -n ${GH_TOKEN:-} ]]; then
		echo "$GH_TOKEN"
	elif [[ -n ${GITHUB_TOKEN:-} ]]; then
		echo "$GITHUB_TOKEN"
	elif [[ -r /etc/claude-desktop-fleet.token ]]; then
		cat /etc/claude-desktop-fleet.token
	else
		err 'no token: set GH_TOKEN or create' \
			'/etc/claude-desktop-fleet.token (mode 0600)'
		return 1
	fi
}

main() {
	if (( EUID != 0 )); then
		err 'must run as root (apt-get install); re-run with sudo'
		return 1
	fi

	command -v jq > /dev/null 2>&1 || {
		err 'jq is required: apt-get install -y jq'
		return 1
	}

	local arch token
	arch=$(detect_arch) || return 1
	token=$(load_token) || return 1

	local json
	json=$(curl -fsSL \
		-H "Authorization: Bearer ${token}" \
		-H 'Accept: application/vnd.github+json' \
		"${api_base}/releases/latest") || {
		err "failed to query ${api_base}/releases/latest" \
			'(check token permissions and that a release exists)'
		return 1
	}

	local asset_id asset_name digest
	asset_id=$(printf '%s' "$json" | jq -r --arg a "_${arch}.deb" \
		'.assets[] | select(.name | endswith($a)) | .id' | head -1)
	asset_name=$(printf '%s' "$json" | jq -r --arg a "_${arch}.deb" \
		'.assets[] | select(.name | endswith($a)) | .name' | head -1)
	digest=$(printf '%s' "$json" | jq -r --arg a "_${arch}.deb" \
		'.assets[] | select(.name | endswith($a)) | .digest // empty' |
		head -1)
	if [[ -z $asset_id || -z $asset_name ]]; then
		err "no .deb asset for ${arch} in the latest release"
		return 1
	fi

	# Debian version is embedded in the asset name:
	# claude-desktop_<claudeVer>-<repoVer>_<arch>.deb
	local new_version current_version
	new_version=$(printf '%s' "$asset_name" |
		grep -oP 'claude-desktop_\K[^_]+')
	current_version=$(dpkg-query -W -f='${Version}' \
		claude-desktop 2>/dev/null)
	if [[ -n $current_version && $current_version == "$new_version" ]]; then
		echo "Already up to date (${current_version})"
		return 0
	fi

	local tmp_dir
	tmp_dir=$(mktemp -d) || return 1
	trap 'rm -rf "$tmp_dir"' EXIT

	local deb_path="$tmp_dir/$asset_name"
	echo "Downloading ${asset_name}..."
	curl -fSL -o "$deb_path" \
		-H "Authorization: Bearer ${token}" \
		-H 'Accept: application/octet-stream' \
		"${api_base}/releases/assets/${asset_id}" || {
		err "download failed for asset ${asset_id}"
		return 1
	}

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
