# Day to day

Commands run on your Mac in this repository's folder unless they say **on the server**. The
examples use the server 203.0.113.10 and the cloud `cloud.203-0-113-10.nip.io`.

## Is everything all right?

| | |
|---|---|
| The server | `deploy/deploy.sh status` — the service, its health, and its recent log |
| The Mac | `combind status` — "everything is in the cloud" when nothing waits to be sent |
| The server's log | **on the server**: `journalctl -u combind-hub --since '-1 hour'` |

After a reboot or a power cut the server starts COMBIND by itself; if it ever stops, it is
restarted within seconds. The Mac mounts the drive again at every login.

## Updates

```sh
git pull                    # this repository's newest scripts and guides
deploy/deploy.sh update     # the server: the newest release, checked against its SHA-256
```

`update` keeps the previous release; `deploy/deploy.sh rollback` goes back to it at once. To install
a given release instead of the latest: `COMBIND_VERSION=1.0.0 deploy/deploy.sh update`.

The Mac: run the [install command](mac.md#install) again, then `combind repair`, and choose
**Always Allow** when macOS asks about the Keychain.

## Backups — please do this

Which encrypted pieces make which file lives only in the server's database. The server snapshots
it every day (the last seven are kept), but keep copies **off** the server too:

```sh
deploy/deploy.sh backup     # → ~/COMBIND-backups/<time>/
```

It copies the newest snapshot, the *hub key* and the configuration. Keep that folder private: the
hub key opens the server's stored Google connections.

## Moving to another server

1. `deploy/deploy.sh backup` for a safety copy.
2. **On the old server**: `systemctl stop combind-hub`, then copy `/var/lib/combind/hub.sqlite3`
   (with `hub.sqlite3-wal` if it is there), `/var/lib/combind/hub.key` and
   `/etc/combind/hub.toml` to your Mac.
3. Point `deploy/site.env` at the new server (and new host names if they change), then
   `deploy/deploy.sh preflight` and `deploy/deploy.sh install`.
4. **On the new server**: `systemctl stop combind-hub`; replace `/var/lib/combind/hub.sqlite3*` and
   `hub.key` with your copies (owner `combind`, mode 0600); in `/etc/combind/hub.toml` keep the
   new host names but take the `[google]` section from the old file; `systemctl start
   combind-hub`.
5. If the host names changed, add the new redirect URI to your Google client
   (`https://<new cloud host>/v1/sources/google/callback`).
6. On each Mac: `combind login --hub https://<new cloud host> alex` — your files on the Mac stay.
   On phones: open the new address and sign in.

## A new Mac

Install, `combind login`, `combind drive install` — see [the Mac guide](mac.md). Your apps' data
from the old Mac, if it was backed up:
`combind get --space "Mac app data" "/<old Mac's name>/Application Support/<app>" ~/Desktop/restore`.

## When something is wrong

| What you see | What to do |
|---|---|
| COMBIND is missing from Finder | Open the COMBIND app, or `combind repair`. After an update, choose Always Allow when macOS asks about the Keychain. |
| The web app keeps loading | `deploy/deploy.sh status`. If a new release misbehaves: `deploy/deploy.sh rollback`. |
| "This is protected" when deleting | Protected folders (your Mac's backup) need your authenticator's code; the web app and `combind rm` ask for it. |
| Files or the trash look empty | Another Space is open: switch with the Space button beside the page title. |
| A Google account says "Needs reconnect" | *Google accounts* → the account → **Reconnect**. |
| The Mac's backup stopped | It tries again within the hour; `combind backup now` runs it at once. |
| Lost the phone with your authenticator | Sign in with a recovery code → *Security* → **Replace authenticator**. No codes left: an admin resets your two-factor sign-in in the admin portal. |
| Forgot your password | *Forgot password* on the sign-in page, with your recovery key. |

## Who keeps which secret

| Secret | Where | If it is lost |
|---|---|---|
| Your password and authenticator | you | your recovery codes or recovery key get you back in |
| Your recovery key | you, on paper | with the password lost too, nobody can open your files — by design |
| The hub key | the server, and your `deploy/deploy.sh backup` copies | nobody can sign in and no Google account can be reached |
| The Google client secret | `/etc/combind/hub.toml` on the server | create a new one in Google Cloud |
