#!/bin/sh
# Installs or updates COMBIND's program on this Mac from the published releases, checking its
# SHA-256 checksum:
#
#   curl -fsSL https://raw.githubusercontent.com/SyCLoNEwoRLD/SYCLONE-CLOUD/main/scripts/install-mac.sh | sh
#
#   COMBIND_VERSION=1.0.0    a given release instead of the latest
#   COMBIND_BIN_DIR=<dir>    where the program goes (default: ~/.local/bin)

set -eu

repository=SyCLoNEwoRLD/SYCLONE-CLOUD
file=combind-macos-universal.tar.gz

if [ "$(uname -s)" != Darwin ]; then
  echo "error: COMBIND's program is for macOS" >&2
  exit 1
fi
version=${COMBIND_VERSION:-latest}
if [ -n "${COMBIND_DOWNLOAD_BASE:-}" ]; then
  base=$COMBIND_DOWNLOAD_BASE # a mirror, or a local copy while testing a release
elif [ "$version" = latest ]; then
  base=https://github.com/$repository/releases/latest/download
else
  base=https://github.com/$repository/releases/download/v${version#v}
fi
dir=${COMBIND_BIN_DIR:-$HOME/.local/bin}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "Downloading COMBIND ($version)…"
curl -fsSL --retry 3 -o "$work/$file" "$base/$file"
curl -fsSL --retry 3 -o "$work/SHA256SUMS" "$base/SHA256SUMS"
expected=$(awk -v name="$file" '$2 == name || $2 == "*" name { print $1 }' "$work/SHA256SUMS")
actual=$(shasum -a 256 "$work/$file" | cut -d' ' -f1)
if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
  echo "error: the download does not match its published SHA-256 checksum" >&2
  exit 1
fi
tar -xzf "$work/$file" -C "$work"

updating=false
[ -x "$dir/combind" ] && updating=true
mkdir -p "$dir"
install -m 0755 "$work/combind/combind" "$dir/combind"
echo "Installed $("$dir/combind" --version) at $dir/combind"

case ":$PATH:" in
  *":$dir:"*) ;;
  *)
    profile=$HOME/.zprofile
    if ! grep -qs "$dir" "$profile"; then
      # $PATH stays literal: the shell expands it when the profile runs.
      # shellcheck disable=SC2016
      printf '\nexport PATH="%s:$PATH"\n' "$dir" >>"$profile"
    fi
    echo "Added $dir to your PATH in $profile: open a new Terminal window to use \`combind\`."
    ;;
esac

if [ "$updating" = true ]; then
  echo "Updated. Now run: combind repair"
  echo "(macOS asks whether combind may use your Keychain: choose Always Allow.)"
else
  echo "Next: combind login --hub https://<your cloud address> <your sign-in name>"
  echo "Then: combind drive install"
fi
