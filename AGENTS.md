# Setting up SYCLONE CLOUD — for AI assistants

You are helping a person install SYCLONE CLOUD: a server they control and its program on their
Mac, called COMBIND. Work through this file in order. Every command runs on the person's Mac, in this
repository's folder, unless it says **on the server**. The person-facing guides are in `docs/`;
link to them when you explain a step.

The examples use placeholders: the server **203.0.113.10**, the sign-in name **alex**. Always use
the person's own values instead.

## Rules — follow all of them

1. **Never handle the person's COMBIND password, authenticator codes, recovery codes or recovery
   key.** They type those themselves, in their browser or Terminal. Do not ask for them.
2. **Secrets never go into this repository or into files you show.** A server root password goes
   into a private file outside the repository (`chmod 600`), used through `COMBIND_SSHPASS_FILE`.
   The Google client secret goes only into `/etc/combind/hub.toml` on the server.
3. **The server may run other websites and services. Change nothing that is not COMBIND's.**
   The scripts touch only `/opt/combind`, `/etc/combind`, `/var/lib/combind`, the unit
   `combind-hub.service`, the nginx site `zzz-combind` and `snippets/combind-proxy.conf`, and the
   certificate named `combind`. They test nginx before every reload, never restart it, and compare
   every other site's answers before and after each change, restoring on any difference. Do not
   edit other nginx sites, the firewall, SSH or other services yourself. If `preflight` warns,
   stop and explain the warning to the person.
4. **Ask before anything that costs money or cannot be undone** (buying a domain or a server,
   deleting data). COMBIND itself needs no payment.
5. **Check each step before the next** — every section below ends with how.

## 0. Ask the person

- **The server**: its IP address, and root SSH access — an SSH key is best; otherwise the root
  password, which you put in a private file (rule 2). It should run Ubuntu 22.04/24.04 or
  Debian 12, on x86_64 or arm64.
- **A domain?** Without one, use nip.io names: for 203.0.113.10 they are
  `cloud.203-0-113-10.nip.io` and `admin.203-0-113-10.nip.io`. With a domain, two names
  (e.g. `cloud.example.com`, `admin.example.com`) pointing at the server.
- **A sign-in name** for them: lowercase letters, digits, `.`, `_` or `-` (e.g. `alex`).
- **Which Google account** creates the Google client (any of theirs).

## 1. The Mac

- Needs: macOS with Terminal (curl and ssh are built in). For a password login to the server
  only: `brew install sshpass` (Homebrew: <https://brew.sh>).
- This repository: `git clone https://github.com/SyCLoNEwoRLD/SYCLONE-CLOUD.git && cd SYCLONE-CLOUD`.

## 2. The server's settings

```sh
cp deploy/site.example.env deploy/site.env
```

Edit `deploy/site.env`:

```sh
COMBIND_SSH=root@203.0.113.10
COMBIND_USER_HOST=cloud.203-0-113-10.nip.io
COMBIND_ADMIN_HOST=admin.203-0-113-10.nip.io
COMBIND_USER_PORT=7401
COMBIND_ADMIN_PORT=7402
```

For a password login: `export COMBIND_SSHPASS_FILE=/path/outside/the/repo/server-password` (the
file holds only the password, `chmod 600`).

## 3. Preflight (changes nothing)

On the server, nginx and certbot must be installed. If they are missing and **nothing else**
serves the web on that server (ports 80/443 free), install them **on the server**:
`apt-get update && apt-get install -y nginx certbot`. If another web server uses ports 80/443,
stop and ask the person.

```sh
deploy/deploy.sh preflight
```

**Check:** it ends without warnings. Explain any warning to the person and resolve it first.

## 4. Install

```sh
deploy/deploy.sh install
```

It downloads the release for the server's processor, checks its SHA-256, installs the service,
gets a free Let's Encrypt certificate and adds the nginx site.

**Check:** `curl -s -o /dev/null -w '%{http_code}\n' https://cloud.203-0-113-10.nip.io/readyz`
prints `200` (also for the admin host).

## 5. The owner's account

```sh
deploy/deploy.sh invite owner alex
```

Give the printed link to the person. **They** open it in their browser, choose a password, add the
authenticator to their phone, and save the recovery codes and recovery key.

**Check:** they can sign in at `https://cloud.203-0-113-10.nip.io`.

## 6. Google

Walk the person through [docs/google.md](docs/google.md): they create the free OAuth client in
their Google account. Then put its ID and secret into `/etc/combind/hub.toml` **on the server**:

```toml
[google]
client_id = "123456789012-abc.apps.googleusercontent.com"
client_secret = "GOCSPX-…"
```

and restart **on the server**: `systemctl restart combind-hub`.

**Check:** in the web app, *Google accounts → Connect account* opens Google's sign-in. The person
connects each Google account they want in the pool.

## 7. The Mac program and the drive

```sh
curl -fsSL https://raw.githubusercontent.com/SyCLoNEwoRLD/SYCLONE-CLOUD/main/scripts/install-mac.sh | sh
```

Then, in a new Terminal window (the person types the password and the code):

```sh
combind login --hub https://cloud.203-0-113-10.nip.io alex
combind drive install
```

macOS asks once whether `combind` may use the Keychain: the person chooses **Always Allow**.
Optional, with the person's agreement: `combind drive move-in` (Desktop, Documents and Downloads
live in the drive) and `combind backup install` (apps' data backed up daily).

**Check:** `combind status` shows them signed in, the pool, and the drive mounted at `~/COMBIND`;
COMBIND appears in Finder.

## 8. Hand over

Tell the person:

- Keep the recovery codes and the recovery key somewhere safe and offline.
- Copy the server's database off it from time to time: `deploy/deploy.sh backup`
  (see [docs/operations.md](docs/operations.md)).
- Updates: `git pull`, then `deploy/deploy.sh update` for the server, and the install command of
  step 7 again for the Mac, followed by `combind repair`.

## When something is wrong

[docs/operations.md](docs/operations.md) lists symptoms and fixes. Useful commands:
`deploy/deploy.sh status` (server), `combind status` and `combind repair` (Mac). The server's
log: **on the server** `journalctl -u combind-hub --since '-1 hour'`.
