# 1. The server

COMBIND's server — the *hub* — keeps your cloud in order: who may sign in, which encrypted pieces
are in which Google account. It never sees your files' contents. You install it from your Mac with
one command; it never builds anything on the server.

This guide follows an example: **Alex**, whose server has the address **203.0.113.10**. Use your
own values wherever you see these.

## What you need

- **A Linux server (VPS)** with Ubuntu 22.04/24.04 or Debian 12, x86_64 or arm64, and root SSH
  access. 1 GB of memory and 10 GB of disk are plenty. Many providers have free or very cheap
  plans.
- **Ports 80 and 443 open** to the internet. Some providers block them by default in their own
  firewall ("security list", "security group"): open them there.
- **Two host names** pointing at the server. Without a domain, use the free nip.io names:
  `cloud.203-0-113-10.nip.io` and `admin.203-0-113-10.nip.io` — they work at once, nothing to
  register. With a domain, create two DNS records (e.g. `cloud.example.com`, `admin.example.com`).

The server may already run other websites: COMBIND adds its own nginx site for its two names and
changes nothing else (it checks every other site answers exactly as before).

## Step by step

**1. nginx and certbot on the server.** If the server does not have them yet — and no other web
server uses ports 80/443 — install them over SSH:

```sh
ssh root@203.0.113.10 'apt-get update && apt-get install -y nginx certbot'
```

**2. This repository on your Mac:**

```sh
git clone https://github.com/SyCLoNEwoRLD/SYCLONE-CLOUD.git
cd SYCLONE-CLOUD
```

**3. Your settings.** Copy the example and edit it:

```sh
cp deploy/site.example.env deploy/site.env
open -e deploy/site.env
```

Alex's file:

```sh
COMBIND_SSH=root@203.0.113.10
COMBIND_USER_HOST=cloud.203-0-113-10.nip.io
COMBIND_ADMIN_HOST=admin.203-0-113-10.nip.io
COMBIND_USER_PORT=7401
COMBIND_ADMIN_PORT=7402
```

Nothing in it is secret. If you log in to the server with a password instead of an SSH key,
install `sshpass` (`brew install sshpass`), put the password alone in a file **outside** the
repository, and point to it:

```sh
printf '%s' 'the-root-password' > ~/.combind-server-password && chmod 600 ~/.combind-server-password
export COMBIND_SSHPASS_FILE=~/.combind-server-password
```

**4. Check the server (changes nothing):**

```sh
deploy/deploy.sh preflight
```

It reports the system, nginx, the ports and the names. Continue only when it shows no warning.

**5. Install:**

```sh
deploy/deploy.sh install
```

It downloads the release for your server's processor, checks its SHA-256 checksum, installs the
service, gets a free certificate from Let's Encrypt and adds the nginx site. Check it:

```sh
curl -s https://cloud.203-0-113-10.nip.io/readyz    # {"status":"ready"}
```

**6. Your account — the owner:**

```sh
deploy/deploy.sh invite owner alex
```

Open the printed link in your browser: choose a password, add the authenticator to your phone
(any authenticator app), and **save the recovery codes and the recovery key** somewhere safe.

Next: **[2. Google](google.md)**.

## What is where on the server

| | |
|---|---|
| `/opt/combind/releases/…`, `/opt/combind/current` | the installed releases; the previous one is kept for rollback |
| `/etc/combind/hub.toml` | the configuration (host names, the Google client) |
| `/var/lib/combind/` | the database, the hub key, daily database snapshots |
| `combind-hub.service` | the service: starts at boot, restarts by itself |
| nginx site `zzz-combind` | the two host names, TLS, and nothing else |

Inviting family members and other admins: in the web app, or `deploy/deploy.sh invite member
<name>` / `invite admin <name>`.
