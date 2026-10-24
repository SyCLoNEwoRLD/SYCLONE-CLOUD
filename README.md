# SYCLONE CLOUD

**Your own iCloud-style drive for the Mac — built from storage you already have.**
Its program and its drive are called **COMBIND**.

SYCLONE CLOUD joins the free storage of several Google accounts — yours, your family's — into one
private, end-to-end-encrypted pool, and puts it in Finder as an ordinary drive. A small server you
run keeps it in order; your files travel between your devices and Google already encrypted.

- **One drive from many accounts.** Files are split, compressed and encrypted on your device,
  then spread over the accounts by their free space. 6 GB stays free in every account, so Gmail
  and Google Photos keep working.
- **Nobody else can read it** — not Google, not your server, not whoever runs it. Your password
  never leaves your device, and every sign-in also needs your authenticator app.
- **A real drive in Finder.** Open, save and organise files as on any disk. Desktop, Documents
  and Downloads can live in it. It works offline with what your Mac keeps and catches up later.
- **In the browser and on phones too.** Files and Photos in a web app you can add to your home
  screen — on any computer or phone.
- **Survives losing an account.** A Space can keep a second copy, or parity, across accounts.

> [!IMPORTANT]
> Pooling several free Google accounts may go against Google's policies. You use SYCLONE CLOUD at your
> own risk — keep a second copy of anything you cannot afford to lose.

## What you need

| | |
|---|---|
| **A Mac** | macOS 11 or later, Apple silicon or Intel. |
| **A server** | A Linux VPS — Ubuntu 22.04/24.04 or Debian 12, x86_64 or arm64 — with root SSH, nginx and certbot. A free one is enough. |
| **An address** | A domain, or none at all: the free `nip.io` names work (`cloud.203-0-113-10.nip.io` for the server 203.0.113.10). |
| **Google** | Your Google accounts, and a free Google Cloud OAuth client (about 10 minutes, no review). |

The drive in Finder is for macOS only. The web app works in any modern browser, so Windows,
Linux, Android and iPhone users can still use Files and Photos.

## Set it up

**With an AI assistant** (Claude Code, Codex, Cursor, Gemini CLI, …): open this repository in it
and say *"Set up SYCLONE CLOUD for me."* [`AGENTS.md`](AGENTS.md) gives it every step and every safety
rule; it asks you only for what only you can give.

**Yourself** — about 30 minutes:

1. **[Server](docs/server.md)** — install it from your Mac with one command.
2. **[Google](docs/google.md)** — create the free OAuth client and connect your accounts.
3. **[Mac](docs/mac.md)** — install the COMBIND program and sign in; the drive appears in Finder.

Afterwards: **[day to day](docs/operations.md)** — updates, backups, moving to another server,
and what to do when something is wrong.

## Security

- Everything is encrypted on your device before it leaves it — file contents and file names. The
  server and Google only ever hold ciphertext.
- Sign-in uses OPAQUE: your password is never sent anywhere, not even to your own server. Every
  sign-in also asks for your authenticator app's code.
- Recovery codes and a recovery key get you back in after losing your phone or your password.
  Keep them safe: without them nobody — not even the server's owner — can restore access.

Found a security problem? Please report it privately — see [SECURITY.md](SECURITY.md).

## Licence

SYCLONE CLOUD is free to use, but not open source — see [LICENSE](LICENSE). It is built
with open-source components, credited with their licences in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

© 2026 [SyCLoNEwoRLD](https://github.com/SyCLoNEwoRLD)
