# 3. The Mac

The `combind` program puts your cloud in Finder as a drive, at `~/COMBIND`. It runs on macOS 11 or
later, on Apple silicon and Intel Macs.

The example continues with **Alex**, whose cloud is at `cloud.203-0-113-10.nip.io`.

## Install

In Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/SyCLoNEwoRLD/SYCLONE-CLOUD/main/scripts/install-mac.sh | sh
```

It downloads the latest release, checks its SHA-256 checksum, and puts the program in
`~/.local/bin` (adding that folder to your `PATH` if needed — open a new Terminal window
afterwards). Check: `combind --version`.

## Sign in and mount the drive

```sh
combind login --hub https://cloud.203-0-113-10.nip.io alex
combind drive install
```

`login` asks for your password and your authenticator's code. `drive install` mounts the drive at
`~/COMBIND` now and at every login, saves screenshots into `~/COMBIND/Screenshots`, and adds a
**COMBIND** app to your Applications (it opens the drive, and repairs it first if needed).

macOS asks once whether `combind` may use your Keychain — choose **Always Allow**. It keeps your
session and keys there.

## Optional

```sh
combind drive move-in              # Desktop, Documents and Downloads live in the drive
combind backup install             # your apps' data (~/Library) backed up daily, apart from your files
combind pin ~/COMBIND/Documents    # kept whole on this Mac: opens at once, even offline
```

`move-in` moves those folders' files into the drive and leaves a link in their place, so whatever
you save there goes to your cloud. `combind drive move-out` brings them back.

## Every day

- **Offline**, everything your Mac keeps — recent, pinned and newly saved files — opens as usual,
  and changes wait to be sent; files only in the cloud open again once you are online.
- `combind status` — your account, the pool, the cache, the drive, pins and the backup.
- COMBIND missing from Finder? Open the **COMBIND** app, or run `combind repair`.
- The cache keeps 10 GB of recent files by default (`combind cache --limit 20` for 20 GB), and
  shrinks by itself when your disk gets full. Files not yet sent are never removed.

## Update

Run the install command again, then:

```sh
combind repair
```

and choose **Always Allow** when macOS asks about the Keychain again — it asks after every update.

## Remove

```sh
combind drive move-out      # if you used move-in
combind backup uninstall    # if you used backup install
combind drive uninstall
combind logout
rm ~/.local/bin/combind
```

Your files stay in your cloud. Everything COMBIND kept on this Mac is in
`~/Library/Application Support/COMBIND ULTRA CLOUD/` — delete that folder to remove it all.
