#!/usr/bin/env bash
# Installs and runs COMBIND ULTRA CLOUD, from this Mac, on the server named in deploy/site.env (or
# the file in $COMBIND_SITE). See deploy/README.md for the whole procedure.
#
#   deploy/deploy.sh preflight              read-only report from the server
#   deploy/deploy.sh install                first installation
#   deploy/deploy.sh update                 switch to a new release
#   deploy/deploy.sh rollback               switch back to the previous release
#   deploy/deploy.sh status                 service state, health and recent log
#   deploy/deploy.sh invite ROLE [HANDLE]   create a single-use invitation link
#   deploy/deploy.sh backup                 copy the newest database snapshot, the hub key and
#                                           the configuration to $COMBIND_BACKUP_DIR
#                                           (default ~/COMBIND-backups)
#   deploy/deploy.sh uninstall              remove service and nginx site (keeps data)
#
# What install and update ship, for the server's processor (x86_64 or arm64): the bundle in
# $COMBIND_BUNDLE (its SHA-256 in the .sha256 file beside it), else one built here by package.sh
# (where the source is), else the published release — $COMBIND_VERSION, default the latest —
# checked against its published SHA-256 (COMBIND_DOWNLOAD_BASE: another place to download from).
#
# SSH: keys by default. For a password login, put the password in a file (chmod 600, outside the
# repository) and set COMBIND_SSHPASS_FILE to its path; sshpass then supplies it.

set -Eeuo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=site.sh
source "$here/site.sh"
combind_load_site

# The GitHub repository (owner/name) whose releases install and update download: from the
# environment, else from deploy/release.env in a published copy of these scripts.
releases=${COMBIND_RELEASES:-}
if [[ -z $releases && -r $here/release.env ]]; then
  releases=$(sed -n 's/^COMBIND_RELEASES=//p' "$here/release.env")
fi

target=$COMBIND_SSH
ssh_options=(-o ConnectTimeout=20 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new)
if [[ -n ${COMBIND_SSHPASS_FILE:-} ]]; then
  [[ -r $COMBIND_SSHPASS_FILE ]] || { echo "error: cannot read $COMBIND_SSHPASS_FILE" >&2; exit 1; }
  ssh_options+=(-o PubkeyAuthentication=no)
fi
settings=(
  "COMBIND_USER_HOST=$COMBIND_USER_HOST" "COMBIND_ADMIN_HOST=$COMBIND_ADMIN_HOST"
  "COMBIND_USER_PORT=$COMBIND_USER_PORT" "COMBIND_ADMIN_PORT=$COMBIND_ADMIN_PORT"
)

over_ssh() {
  # ssh or scp ($1) with the installation's options — through sshpass when a password file is
  # set. (No empty array is expanded: macOS's bash 3.2 rejects that under `set -u`.)
  local tool=$1
  shift
  if [[ -n ${COMBIND_SSHPASS_FILE:-} ]]; then
    sshpass -f "$COMBIND_SSHPASS_FILE" "$tool" "${ssh_options[@]}" "$@"
  else
    "$tool" "${ssh_options[@]}" "$@"
  fi
}

remote() {
  # Runs the local remote.sh on the server with the installation's settings and the arguments.
  over_ssh ssh "$target" \
    "env $(printf '%q ' "${settings[@]}") bash -s -- $(printf '%q ' "$@")" <"$here/remote.sh"
}

server_arch() {
  # The server's processor, as bundles are named.
  local machine
  machine=$(over_ssh ssh "$target" uname -m)
  case $machine in
    x86_64 | amd64) echo x86_64 ;;
    aarch64 | arm64) echo arm64 ;;
    *)
      echo "error: the server's processor ($machine) is not supported: x86_64 or arm64 only" >&2
      return 1
      ;;
  esac
}

check_sum() {
  # Fails unless file $1 has the SHA-256 $2.
  local actual
  actual=$(shasum -a 256 "$1" | cut -d' ' -f1)
  [[ -n $2 && $actual == "$2" ]] || {
    echo "error: $1 does not match its published SHA-256" >&2
    return 1
  }
}

bundle_for() {
  # Prints the path of a checked server bundle for processor $1 (see the header). It runs in a
  # command substitution, where bash 3.2 does not stop at a failing command: every step that can
  # fail returns explicitly, so nothing unchecked is ever printed.
  local arch=$1 file url cache
  file=combind-server-linux-$arch.tar.gz
  if [[ -n ${COMBIND_BUNDLE:-} ]]; then
    [[ -r $COMBIND_BUNDLE && -r $COMBIND_BUNDLE.sha256 ]] || {
      echo "error: $COMBIND_BUNDLE, or the $COMBIND_BUNDLE.sha256 beside it, is missing" >&2
      return 1
    }
    check_sum "$COMBIND_BUNDLE" "$(<"$COMBIND_BUNDLE.sha256")" || return 1
    echo "$COMBIND_BUNDLE"
  elif [[ -x $here/package.sh ]]; then
    "$here/package.sh" "$arch"
  else
    [[ $releases =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
      echo "error: set COMBIND_RELEASES to the GitHub repository (owner/name) to install from" >&2
      return 1
    }
    url=https://github.com/$releases/releases
    if [[ -n ${COMBIND_DOWNLOAD_BASE:-} ]]; then
      url=$COMBIND_DOWNLOAD_BASE # a mirror, or a local copy while testing a release
    elif [[ ${COMBIND_VERSION:-latest} == latest ]]; then
      url=$url/latest/download
    else
      url=$url/download/v${COMBIND_VERSION#v}
    fi
    cache=$(mktemp -d) || return 1
    echo "==> downloading $file" >&2
    if ! curl -fsSL --retry 3 -o "$cache/$file" "$url/$file" ||
      ! curl -fsSL --retry 3 -o "$cache/SHA256SUMS" "$url/SHA256SUMS" ||
      ! check_sum "$cache/$file" "$(awk -v name="$file" '$2 == name || $2 == "*" name { print $1 }' \
        "$cache/SHA256SUMS")"; then
      rm -rf "$cache"
      return 1
    fi
    echo "$cache/$file"
  fi
}

render() {
  # Writes template $1 with this installation's settings to $2.
  sed -e "s/@USER_HOST@/$COMBIND_USER_HOST/g" -e "s/@ADMIN_HOST@/$COMBIND_ADMIN_HOST/g" \
    -e "s/@USER_PORT@/$COMBIND_USER_PORT/g" -e "s/@ADMIN_PORT@/$COMBIND_ADMIN_PORT/g" "$1" >"$2"
  if grep -q '@[A-Z_]*@' "$2"; then
    echo "error: unrendered placeholder in $2" >&2
    return 1
  fi
}

assemble() {
  # Turns the unpacked bundle $1 into release $2 of this installation: the deployment files
  # and the configuration rendered for its host names and ports.
  local stage=$1
  mkdir -p "$stage/deploy/nginx" "$stage/deploy/systemd"
  cp "$here/remote.sh" "$stage/deploy/"
  cp "$here/nginx/combind-proxy.conf" "$stage/deploy/nginx/"
  cp "$here/systemd/combind-hub.service" "$stage/deploy/systemd/"
  render "$here/templates/hub.toml.in" "$stage/deploy/hub.toml"
  render "$here/templates/nginx-acme.conf.in" "$stage/deploy/nginx/combind-acme.conf"
  render "$here/templates/nginx-site.conf.in" "$stage/deploy/nginx/combind.conf"
  cat >"$stage/deploy/site.env" <<SETTINGS
COMBIND_USER_HOST=$COMBIND_USER_HOST
COMBIND_ADMIN_HOST=$COMBIND_ADMIN_HOST
COMBIND_USER_PORT=$COMBIND_USER_PORT
COMBIND_ADMIN_PORT=$COMBIND_ADMIN_PORT
SETTINGS
  echo "$2" >"$stage/VERSION"
}

ship() {
  # Gets the release for the server's processor, makes it this installation's, uploads it, runs
  # remote.sh $1 on it and removes everything it made, here and there.
  local mode=$1 arch bundle work stamp name sum status=0
  arch=$(server_arch) || return 1
  bundle=$(bundle_for "$arch") || return 1
  work=$(mktemp -d)
  tar -xzf "$bundle" -C "$work"
  if [[ -n ${COMBIND_BUNDLE:-} ]]; then
    : # the caller's: kept
  elif [[ -x $here/package.sh ]]; then
    rm -f "$bundle" "$bundle.sha256" # rebuilt whenever needed
  else
    rm -rf "$(dirname "$bundle")"
  fi
  stamp=$(date -u +%Y%m%d%H%M%S)
  name=combind-$stamp
  mv "$work/combind-server-linux-$arch" "$work/$name"
  assemble "$work/$name" "$stamp"
  echo "==> uploading $name ($arch) for $COMBIND_USER_HOST and $COMBIND_ADMIN_HOST" >&2
  COPYFILE_DISABLE=1 tar -C "$work" --uid 0 --gid 0 --no-mac-metadata --no-xattrs \
    -czf "$work/$name.tar.gz" "$name"
  sum=$(shasum -a 256 "$work/$name.tar.gz" | cut -d' ' -f1)
  over_ssh scp -q "$work/$name.tar.gz" "$target:/var/tmp/$name.tar.gz"
  rm -rf "$work"
  over_ssh ssh "$target" "set -e
    echo '$sum  /var/tmp/$name.tar.gz' | sha256sum -c --quiet
    rm -rf '/var/tmp/$name' && tar -xzf '/var/tmp/$name.tar.gz' -C /var/tmp && rm -f '/var/tmp/$name.tar.gz'"
  remote "$mode" "/var/tmp/$name" || status=$?
  over_ssh ssh "$target" "rm -rf '/var/tmp/$name'"
  return "$status"
}

backup() {
  # The files tree lives only in the hub's database: keep copies away from the server. The hub
  # snapshots its database daily; this fetches the newest snapshot with the hub key (which opens
  # the stored Google connections) and the configuration.
  local dest latest file
  dest=${COMBIND_BACKUP_DIR:-$HOME/COMBIND-backups}/$(date -u +%Y%m%d-%H%M%S)
  latest=$(over_ssh ssh "$target" \
    'ls -1 /var/lib/combind/backups/hub-*.sqlite3 2>/dev/null | tail -n 1')
  if [[ -z $latest ]]; then
    echo "error: no snapshot on the server yet (the hub takes the first within minutes of starting)" >&2
    exit 1
  fi
  (umask 077 && mkdir -p "$dest")
  for file in "$latest" /var/lib/combind/hub.key /etc/combind/hub.toml; do
    over_ssh scp -q "$target:$file" "$dest/"
  done
  chmod 600 "$dest"/*
  echo "==> saved to $dest — keep it private: hub.key opens the stored Google connections" >&2
}

case ${1:-} in
  preflight | rollback | status | uninstall) remote "$1" ;;
  backup) backup ;;
  invite) remote invite "${2:?role: owner, admin or member}" "${3:-}" ;;
  install) ship install ;;
  update) ship activate ;;
  *)
    sed -n '2,22p' "$0" >&2
    exit 2
    ;;
esac
