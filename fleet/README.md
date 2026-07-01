# claude-desktop-fleet

Private distribution point for Claude Desktop packages built by
[pjordanandrsn/claude-desktop-debian](https://github.com/pjordanandrsn/claude-desktop-debian),
plus the updater script the fleet machines run. Only this account can
read it; each machine authenticates with a fine-grained PAT scoped to
this one repository.

## How it works

```
claude-desktop-debian (public fork)          claude-desktop-fleet (this repo, private)
  tag v*+claude* → CI builds packages   →      mirror-release.yml copies the release
  and publishes a GitHub Release        →      assets into a private release here
                                                        ↓
                                         fleet machines run update-claude-desktop.sh
                                         (token-authenticated download + apt install)
```

## One-time setup

1. **Publish a release on the public fork** (if none exists yet):
   Releases → Draft a new release → tag `v2.0.21+claude1.17377.1`
   targeting `main` → Publish. CI attaches the packages (~8 min).
2. **Run the mirror**: this repo → Actions → Mirror Release →
   Run workflow. It copies the release + packages here. (It also runs
   every 6 hours on its own.)
3. **Create the fleet token**: Settings → Developer settings →
   Fine-grained personal access tokens → Generate. Repository access:
   *Only select repositories* → `claude-desktop-fleet`. Permissions:
   *Contents: Read-only*. Nothing else.

## Per-machine setup (each seat)

```bash
# store the token (once per machine)
sudo install -m 0600 /dev/null /etc/claude-desktop-fleet.token
echo 'github_pat_XXXX' | sudo tee /etc/claude-desktop-fleet.token > /dev/null

# dependencies
sudo apt-get install -y curl jq

# fetch the updater (token-authenticated raw download) and run it
curl -fsSL \
  -H "Authorization: Bearer $(sudo cat /etc/claude-desktop-fleet.token)" \
  -H 'Accept: application/vnd.github.raw+json' \
  https://api.github.com/repos/pjordanandrsn/claude-desktop-fleet/contents/update-claude-desktop.sh \
  | sudo tee /usr/local/sbin/update-claude-desktop > /dev/null
sudo chmod 0755 /usr/local/sbin/update-claude-desktop

sudo update-claude-desktop
```

The script is idempotent — machines that are already current exit
immediately — so a daily cron keeps every seat up to date:

```bash
echo '17 5 * * * root /usr/local/sbin/update-claude-desktop' \
  | sudo tee /etc/cron.d/claude-desktop-update
```

## Updating the fleet after a new version

1. New version merges on the public fork → cut a release tag there.
2. Mirror runs (or trigger it manually).
3. Every seat picks it up on its next cron run — or fan out on demand:

```bash
for h in qnap1 qnap2 qnap3; do
    ssh "$h" 'sudo update-claude-desktop'
done
```

## Security notes

- The PAT grants read-only Contents on this repository only. It cannot
  touch the public fork, other repos, or anything account-level.
- The updater sends the token only to `api.github.com`; curl drops the
  Authorization header on the cross-host redirect to the short-lived
  asset-storage URL.
- Assets are verified against the release's sha256 digest before
  install, and sanity-checked with `dpkg-deb --info`.
- The public fork's releases remain public (they contain only
  repackaged, publicly distributed Claude Desktop binaries). If you
  want package builds to happen privately end-to-end, copy the fork's
  build workflow into this repo instead of mirroring — larger setup,
  happy path documented in the fork's CLAUDE.md.
