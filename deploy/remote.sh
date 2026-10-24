#!/usr/bin/env bash
# COMBIND ULTRA CLOUD — server-side installer. deploy/deploy.sh runs it as root over SSH, with the
# installation's settings in the environment (COMBIND_USER_HOST, COMBIND_ADMIN_HOST,
# COMBIND_USER_PORT, COMBIND_ADMIN_PORT); a release directory carries its own deploy/site.env.
#
#   remote.sh preflight                 read-only report; changes nothing
#   remote.sh install  <stage-dir>      first installation: user, directories, unit, release,
#                                       certificate, nginx site
#   remote.sh activate <stage-dir>      install a new release and switch to it (rolls back when
#                                       the new release is unhealthy)
#   remote.sh rollback                  switch back to the previous release
#   remote.sh status                    service state, health and recent log
#   remote.sh invite <role> [handle]    print a single-use invitation link
#   remote.sh uninstall                 remove the service and the nginx site; keeps data,
#                                       configuration and certificate
#
# The golden rule: nothing outside COMBIND's own files changes. nginx is reloaded (never
# restarted) only after `nginx -t` passes, and every existing site is checked before and after;
# any difference restores the previous configuration. sshd, the firewall, fail2ban and every
# other service are never touched.

set -Eeuo pipefail
umask 022

readonly PREFIX=/opt/combind
readonly RELEASES=$PREFIX/releases
readonly CURRENT=$PREFIX/current
readonly CONFIG_DIR=/etc/combind
readonly DATA_DIR=/var/lib/combind
readonly ACME_ROOT=/var/www/combind-acme
# Named to sort after every existing site: without an explicit `default_server`, nginx makes the
# first server it reads for a port that port's default, and COMBIND must never become it.
readonly SITE_AVAILABLE=/etc/nginx/sites-available/zzz-combind
readonly SITE_ENABLED=/etc/nginx/sites-enabled/zzz-combind
readonly PROXY_SNIPPET=/etc/nginx/snippets/combind-proxy.conf
readonly UNIT=/etc/systemd/system/combind-hub.service
readonly CERT_NAME=combind
# The active release and the one before it, for rollback.
readonly KEEP_RELEASES=2

# Lists every HTTP site nginx serves as "scheme port host" lines, plus one probe per listening
# port with a name no server claims — which shows that port's default server. Used before and
# after any nginx change; COMBIND's own names (variable `skip`) are left out.
# shellcheck disable=SC2016 # an awk program: its $ fields are awk's, not the shell's
readonly DISCOVER_SITES='
function emit(scheme, port, host,   key) {
  key = scheme " " port " " host
  if (!(key in seen)) { seen[key] = 1; print key }
}
function flush(   i, n, name, names, p, parts) {
  n = split(server_names, names, " ")
  for (p in ports) {
    split(p, parts, " ")
    emit(parts[1], parts[2], "unknown-host.invalid")
    for (i = 1; i <= n; i++) {
      name = names[i]
      if (name == "" || name == "_" || name ~ /^~/ || index(" " skip " ", " " name " ")) continue
      if (name ~ /^\*\./) name = "probe-combind." substr(name, 3)
      else if (name ~ /^\./) name = "probe-combind" name
      else if (name ~ /[*"]/) continue
      emit(parts[1], parts[2], name)
    }
  }
  split("", ports)
  server_names = ""
  in_server = 0
}
{
  line = $0
  sub(/#.*/, "", line)
  if (!in_server && line ~ /^[ \t]*server[ \t]*\{/) {
    in_server = 1; depth = 0; server_names = ""; split("", ports)
  }
  if (!in_server) next
  if (depth == 1 && line ~ /^[ \t]*listen[ \t]/) {
    spec = line
    sub(/^[ \t]*listen[ \t]+/, "", spec); sub(/;.*/, "", spec)
    split(spec, words, /[ \t]+/)
    address = words[1]; port = ""
    if (address ~ /\]:[0-9]+$/) { port = address; sub(/.*\]:/, "", port) }
    else if (address ~ /:[0-9]+$/ && address !~ /^unix:/) { port = address; sub(/.*:/, "", port) }
    else if (address ~ /^[0-9]+$/) port = address
    else if (address !~ /^unix:/) port = "80"
    if (port != "") ports[((" " spec " ") ~ /[ \t]ssl[ \t]/ ? "https" : "http") " " port] = 1
  }
  if (depth == 1 && line ~ /^[ \t]*server_name[ \t]/) {
    names = line
    sub(/^[ \t]*server_name[ \t]+/, "", names); sub(/;.*/, "", names)
    server_names = server_names " " names
  }
  depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
  if (depth <= 0) flush()
}
'

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "run as root"

USER_HOST="" ADMIN_HOST="" USER_PORT="" ADMIN_PORT=""
load_settings() {
  # From a release's deploy/site.env when one is given, otherwise from the environment.
  if [[ -n ${1:-} ]]; then
    # shellcheck source=/dev/null
    source "$1"
  fi
  USER_HOST=${COMBIND_USER_HOST:-} ADMIN_HOST=${COMBIND_ADMIN_HOST:-}
  USER_PORT=${COMBIND_USER_PORT:-} ADMIN_PORT=${COMBIND_ADMIN_PORT:-}
  local host_re='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'
  [[ $USER_HOST =~ $host_re && $ADMIN_HOST =~ $host_re && $USER_HOST != "$ADMIN_HOST" ]] ||
    die "COMBIND_USER_HOST and COMBIND_ADMIN_HOST must be two different host names"
  [[ $USER_PORT =~ ^[0-9]{4,5}$ && $ADMIN_PORT =~ ^[0-9]{4,5}$ && $USER_PORT != "$ADMIN_PORT" ]] ||
    die "COMBIND_USER_PORT and COMBIND_ADMIN_PORT must be two different ports"
}

STAGE=""
require_stage() {
  STAGE=${1:-}
  [[ -n $STAGE && -f $STAGE/VERSION && -x $STAGE/bin/combind-hub && -f $STAGE/deploy/site.env ]] ||
    die "not a COMBIND release directory: '$STAGE'"
  load_settings "$STAGE/deploy/site.env"
}

# -- Checks ---------------------------------------------------------------------------------------

discover_sites() {
  nginx -T 2>/dev/null | awk -v skip="$USER_HOST $ADMIN_HOST" "$DISCOVER_SITES" | LC_ALL=C sort
}

snapshot_sites() {
  # The answer of every existing site, through the local nginx (SNI and Host as on the internet).
  local scheme port host code
  while read -r scheme port host; do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 \
      --resolve "$host:$port:127.0.0.1" "$scheme://$host:$port/" </dev/null || true)
    printf '%s://%s:%s %s\n' "$scheme" "$host" "$port" "${code:-000}"
  done < <(discover_sites)
}

# Checks capture command output before matching it: under pipefail, `cmd | grep -q` can fail when
# grep stops reading early and cmd is killed by SIGPIPE.

nginx_layout_ok() {
  local config
  config=$(nginx -T 2>/dev/null || true)
  grep -qE '^\s*include\s+/etc/nginx/sites-enabled/\*;' <<<"$config"
}

last_site_ok() {
  # COMBIND's site must be the last one nginx reads (see SITE_AVAILABLE).
  local last
  last=$(find /etc/nginx/sites-enabled -mindepth 1 -maxdepth 1 ! -name "$(basename "$SITE_ENABLED")" -printf '%f\n' | LC_ALL=C sort | tail -n 1)
  [[ -z $last || $(printf '%s\n%s\n' "$last" "$(basename "$SITE_ENABLED")" | LC_ALL=C sort | tail -n 1) == "$(basename "$SITE_ENABLED")" ]]
}

host_names_taken() {
  # Another server block already claiming a COMBIND name (or a wildcard covering it). COMBIND's
  # own server blocks, from an earlier installation, do not count.
  local user_re=${USER_HOST//./\\.} admin_re=${ADMIN_HOST//./\\.} parent_re=${USER_HOST#*.}
  parent_re=${parent_re//./\\.}
  local names others
  names=$(nginx -T 2>/dev/null | grep -E '^\s*server_name\s' || true)
  others=$(grep -vE "^\s*server_name\s+$user_re\s+$admin_re;|^\s*server_name\s+($user_re|$admin_re);" <<<"$names" || true)
  grep -qE "(^|\s)($user_re|$admin_re|\*\.$parent_re|\.$parent_re)(\s|;)" <<<"$others"
}

loopback_ports_busy() {
  # Busy with something other than COMBIND itself.
  local listeners
  listeners=$(ss -Hltnp "( sport = :$USER_PORT or sport = :$ADMIN_PORT )" 2>/dev/null || true)
  grep -v 'combind-hub' <<<"$listeners" | grep -q .
}

healthy() {
  local _
  for _ in $(seq 1 30); do
    if curl -sf --max-time 2 "http://127.0.0.1:$USER_PORT/readyz" >/dev/null &&
      curl -sf --max-time 2 "http://127.0.0.1:$ADMIN_PORT/readyz" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

preflight() {
  # shellcheck source=/dev/null
  log "system: $(. /etc/os-release && echo "$PRETTY_NAME"), $(nproc) CPUs"
  free -h | awk '/^Mem:/ { print "    memory: " $2 " total, " $7 " available" }'
  df -h / | awk 'NR == 2 { print "    disk /: " $4 " free of " $2 }'
  log "nginx: $(nginx -v 2>&1 | sed 's/^nginx version: //')"
  if nginx -t >/dev/null 2>&1; then echo "    configuration test passes"; else warn "nginx -t fails right now"; fi
  if nginx_layout_ok; then echo "    sites-enabled layout: yes"; else warn "nginx does not include /etc/nginx/sites-enabled/*"; fi
  echo "    enabled sites (read in this order): $(find /etc/nginx/sites-enabled -mindepth 1 -maxdepth 1 -printf '%f ' | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ')"
  if last_site_ok; then echo "    $(basename "$SITE_ENABLED") will be read last"; else warn "a site sorts after $(basename "$SITE_ENABLED")"; fi
  echo "    explicit default servers: $(nginx -T 2>/dev/null | grep -cE '^\s*listen\s.*default_server')"
  echo "    listen directives in use:"
  nginx -T 2>/dev/null | grep -E '^\s*listen\s' | sed -E 's/^\s+//' | sort | uniq -c | sed 's/^/      /'
  if host_names_taken; then
    warn "a COMBIND host name (or a wildcard covering it) is already configured"
  else
    echo "    $USER_HOST and $ADMIN_HOST are free"
  fi
  if loopback_ports_busy; then warn "127.0.0.1:$USER_PORT or :$ADMIN_PORT is in use by another program"; else echo "    loopback ports $USER_PORT/$ADMIN_PORT are free"; fi
  if command -v certbot >/dev/null; then
    log "certbot: $(certbot --version 2>&1)"
    [[ -d /etc/letsencrypt/live/$CERT_NAME ]] && echo "    certificate '$CERT_NAME' exists"
  else
    warn "certbot is not installed"
  fi
  log "existing sites, discovered from nginx -T (status codes through local nginx):"
  snapshot_sites | sed 's/^/    /'
  if [[ -L $CURRENT ]]; then
    log "COMBIND release: $(basename "$(readlink -f "$CURRENT")"), service $(systemctl is-active combind-hub || true)"
  else
    log "COMBIND: not installed"
  fi
}

# -- nginx ----------------------------------------------------------------------------------------

restore_nginx() {
  local backup_site=$1 backup_snippet=$2
  if [[ -n $backup_site ]]; then
    cp -a "$backup_site" "$SITE_AVAILABLE"
    ln -sfn "$SITE_AVAILABLE" "$SITE_ENABLED"
  else
    rm -f "$SITE_ENABLED" "$SITE_AVAILABLE"
  fi
  if [[ -n $backup_snippet ]]; then
    cp -a "$backup_snippet" "$PROXY_SNIPPET"
  elif [[ ! -f $SITE_AVAILABLE ]]; then
    rm -f "$PROXY_SNIPPET"
  fi
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx
  else
    warn "nginx -t fails after restoring; inspect /etc/nginx by hand"
  fi
  rm -f "$backup_site" "$backup_snippet"
}

# Installs $1 as COMBIND's site, reloads nginx, and checks that every other site — and each
# port's default server — still answers exactly as before; otherwise restores the previous state
# and stops.
apply_nginx_site() {
  local source=$1 before after backup_site="" backup_snippet=""
  nginx -t >/dev/null 2>&1 || die "nginx -t fails before any change; leaving nginx alone"
  nginx_layout_ok || die "nginx does not include /etc/nginx/sites-enabled/*; leaving nginx alone"
  last_site_ok || die "another site sorts after $(basename "$SITE_ENABLED"); refusing to change nginx"
  if [[ -f $SITE_AVAILABLE ]] && cmp -s "$source" "$SITE_AVAILABLE" &&
    [[ -f $PROXY_SNIPPET ]] && cmp -s "$STAGE/deploy/nginx/combind-proxy.conf" "$PROXY_SNIPPET" &&
    [[ -L $SITE_ENABLED ]]; then
    log "nginx: COMBIND site already up to date"
    return
  fi
  before=$(snapshot_sites)
  if [[ -f $SITE_AVAILABLE ]]; then
    backup_site=$(mktemp)
    cp -a "$SITE_AVAILABLE" "$backup_site"
  fi
  if [[ -f $PROXY_SNIPPET ]]; then
    backup_snippet=$(mktemp)
    cp -a "$PROXY_SNIPPET" "$backup_snippet"
  fi
  install -d -m 0755 /etc/nginx/snippets
  install -m 0644 "$STAGE/deploy/nginx/combind-proxy.conf" "$PROXY_SNIPPET"
  install -m 0644 "$source" "$SITE_AVAILABLE"
  ln -sfn "$SITE_AVAILABLE" "$SITE_ENABLED"
  if ! nginx -t; then
    restore_nginx "$backup_site" "$backup_snippet"
    die "the COMBIND site does not pass nginx -t; previous configuration restored"
  fi
  systemctl reload nginx
  sleep 2
  after=$(snapshot_sites)
  if [[ $before != "$after" ]]; then
    warn "existing sites answer differently after the change:"
    diff <(echo "$before") <(echo "$after") >&2 || true
    restore_nginx "$backup_site" "$backup_snippet"
    die "nginx change reverted; no other site was left changed"
  fi
  rm -f "$backup_site" "$backup_snippet"
  log "nginx: COMBIND site active; every existing site answers as before"
}

obtain_certificate() {
  if [[ -f /etc/letsencrypt/live/$CERT_NAME/fullchain.pem ]]; then
    log "certificate '$CERT_NAME' already exists"
    return
  fi
  command -v certbot >/dev/null || die "certbot is not installed"
  install -d -m 0755 "$ACME_ROOT/.well-known/acme-challenge"
  apply_nginx_site "$STAGE/deploy/nginx/combind-acme.conf"

  # Prove the challenge path works through public DNS before asking Let's Encrypt, so a
  # mistake never spends the rate limit.
  local probe host
  probe=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  echo "$probe" >"$ACME_ROOT/.well-known/acme-challenge/combind-probe"
  for host in "$USER_HOST" "$ADMIN_HOST"; do
    if [[ $(curl -s --max-time 10 "http://$host/.well-known/acme-challenge/combind-probe") != "$probe" ]]; then
      rm -f "$ACME_ROOT/.well-known/acme-challenge/combind-probe"
      die "http://$host does not reach this server's challenge directory"
    fi
  done
  rm -f "$ACME_ROOT/.well-known/acme-challenge/combind-probe"

  local account=()
  compgen -G "/etc/letsencrypt/accounts/*/directory/*" >/dev/null || account=(--register-unsafely-without-email)
  certbot certonly --webroot -w "$ACME_ROOT" --cert-name "$CERT_NAME" \
    -d "$USER_HOST" -d "$ADMIN_HOST" --non-interactive --agree-tos --keep-until-expiring \
    --deploy-hook "systemctl reload nginx" "${account[@]}"
  log "certificate '$CERT_NAME' issued; certbot's timer renews it"
}

# -- Releases -------------------------------------------------------------------------------------

install_base() {
  getent group combind >/dev/null || groupadd --system combind
  id -u combind >/dev/null 2>&1 ||
    useradd --system --gid combind --home-dir "$DATA_DIR" --no-create-home \
      --shell /usr/sbin/nologin combind
  install -d -m 0755 "$PREFIX" "$RELEASES"
  install -d -m 0750 -o root -g combind "$CONFIG_DIR"
  install -d -m 0700 -o combind -g combind "$DATA_DIR"
  if [[ -f $CONFIG_DIR/hub.toml ]]; then
    log "keeping the existing $CONFIG_DIR/hub.toml"
  else
    install -m 0640 -o root -g combind "$STAGE/deploy/hub.toml" "$CONFIG_DIR/hub.toml"
  fi
  install_unit
  systemctl enable combind-hub >/dev/null
}

install_unit() {
  if ! cmp -s "$STAGE/deploy/systemd/combind-hub.service" "$UNIT"; then
    install -m 0644 "$STAGE/deploy/systemd/combind-hub.service" "$UNIT"
    systemctl daemon-reload
    log "systemd unit installed"
  fi
}

install_release() {
  local version dest
  version=$(<"$STAGE/VERSION")
  [[ $version =~ ^[0-9]{14}$ ]] || die "unexpected release version '$version'"
  dest=$RELEASES/$version
  [[ -e $dest ]] && die "release $version is already installed"
  install -d -m 0755 "$RELEASES"
  mkdir "$dest"
  cp -R "$STAGE/bin" "$STAGE/web" "$STAGE/deploy" "$STAGE/VERSION" "$dest/"
  rm -f "$dest/deploy/hub.toml"  # the configuration lives in /etc/combind, never in a release
  chown -R root:root "$dest"
  find "$dest" -type d -exec chmod 0755 {} +
  find "$dest" -type f -exec chmod 0644 {} +
  chmod 0755 "$dest/bin/combind-hub" "$dest/deploy/remote.sh"
  "$dest/bin/combind-hub" --version >/dev/null || die "the new hub binary does not run on this server"
  echo "$dest"
}

switch_to() {
  ln -sfn "$1" "$CURRENT.next"
  mv -T "$CURRENT.next" "$CURRENT"
}

prune_releases() {
  local current release
  current=$(readlink -f "$CURRENT")
  find "$RELEASES" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r |
    tail -n +$((KEEP_RELEASES + 1)) | while read -r release; do
      [[ $RELEASES/$release == "$current" ]] || rm -rf "${RELEASES:?}/$release"
    done
  # The databases saved before releases that are gone.
  find "$DATA_DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'before-*' -printf '%f\n' |
    sort -r | tail -n +$((KEEP_RELEASES + 1)) | while read -r saved; do
      rm -rf "${DATA_DIR:?}/backups/$saved"
    done
}

# Copies the stopped hub's database before release $1 starts (it may migrate it); prints where.
save_database() {
  local dir=$DATA_DIR/backups/before-$1 file
  install -d -m 0700 -o combind -g combind "$DATA_DIR/backups" "$dir"
  for file in "$DATA_DIR"/hub.sqlite3 "$DATA_DIR"/hub.sqlite3-wal "$DATA_DIR"/hub.sqlite3-shm; do
    [[ -e $file ]] && cp -a "$file" "$dir/"
  done
  echo "$dir"
}

# Puts back the database saved in $1 (the hub is stopped).
restore_database() {
  local dir=$1 file
  [[ -e $dir/hub.sqlite3 ]] || return 0
  rm -f "$DATA_DIR"/hub.sqlite3-wal "$DATA_DIR"/hub.sqlite3-shm
  for file in "$dir"/hub.sqlite3*; do
    cp -a "$file" "$DATA_DIR/"
  done
}

activate() {
  local previous="" dest saved
  [[ -L $CURRENT ]] && previous=$(readlink -f "$CURRENT")
  install_unit
  dest=$(install_release)
  # The database as the running release leaves it: the new release may migrate it, and the
  # previous one must find it as it was if the new one fails.
  systemctl stop combind-hub || true
  saved=$(save_database "$(basename "$dest")")
  switch_to "$dest"
  systemctl restart combind-hub
  if healthy; then
    log "release $(basename "$dest") is live"
    prune_releases
    return
  fi
  journalctl -u combind-hub -n 40 --no-pager >&2 || true
  if [[ -n $previous ]]; then
    warn "the new release is unhealthy; switching back to $(basename "$previous")"
    systemctl stop combind-hub || true
    restore_database "$saved"
    switch_to "$previous"
    systemctl restart combind-hub
    healthy || warn "the previous release is unhealthy too"
  else
    systemctl stop combind-hub
  fi
  die "activation failed"
}

rollback() {
  [[ -L $CURRENT ]] || die "COMBIND is not installed"
  local current previous
  current=$(basename "$(readlink -f "$CURRENT")")
  previous=$(find "$RELEASES" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r |
    awk -v current="$current" 'found { print; exit } $0 == current { found = 1 }')
  [[ -n $previous ]] || die "no release older than $current to roll back to"
  switch_to "$RELEASES/$previous"
  systemctl restart combind-hub
  healthy || die "release $previous did not become healthy"
  log "rolled back from $current to $previous"
}

# -- Operations -----------------------------------------------------------------------------------

public_check() {
  local host path
  for pair in "$USER_HOST /v1/meta" "$ADMIN_HOST /admin/v1/meta"; do
    read -r host path <<<"$pair"
    if curl -sf --max-time 10 "https://$host$path" >/dev/null; then
      log "https://$host is up"
    else
      warn "https://$host$path does not answer yet"
    fi
  done
}

install_all() {
  require_stage "${1:-}"
  nginx -t >/dev/null 2>&1 || die "nginx -t fails right now; fix that before installing anything"
  nginx_layout_ok || die "nginx does not include /etc/nginx/sites-enabled/*"
  host_names_taken && die "a COMBIND host name is already configured in nginx"
  loopback_ports_busy && die "127.0.0.1:$USER_PORT or :$ADMIN_PORT is already in use"
  last_site_ok || die "another site sorts after $(basename "$SITE_ENABLED")"
  install_base
  activate
  obtain_certificate
  apply_nginx_site "$STAGE/deploy/nginx/combind.conf"
  public_check
}

status() {
  systemctl --no-pager --lines=0 status combind-hub || true
  [[ -L $CURRENT ]] && log "release: $(basename "$(readlink -f "$CURRENT")")"
  if healthy; then log "hub: both portals ready on loopback"; else warn "hub: not ready"; fi
  public_check
  journalctl -u combind-hub -n 20 --no-pager || true
}

invite() {
  local role=${1:-} handle=${2:-}
  [[ $role =~ ^(owner|admin|member)$ ]] || die "role must be owner, admin or member"
  [[ -z $handle || $handle =~ ^[a-z0-9][a-z0-9._-]{2,31}$ ]] || die "invalid account name '$handle'"
  [[ -x $CURRENT/bin/combind-hub ]] || die "COMBIND is not installed"
  local args=(--config "$CONFIG_DIR/hub.toml" invite --role "$role")
  [[ -n $handle ]] && args+=(--handle "$handle")
  runuser -u combind -- "$CURRENT/bin/combind-hub" "${args[@]}"
}

uninstall() {
  systemctl disable --now combind-hub 2>/dev/null || true
  rm -f "$UNIT"
  systemctl daemon-reload
  if [[ -e $SITE_AVAILABLE || -L $SITE_ENABLED ]]; then
    local before after
    before=$(snapshot_sites)
    rm -f "$SITE_ENABLED" "$SITE_AVAILABLE" "$PROXY_SNIPPET"
    if nginx -t >/dev/null 2>&1; then systemctl reload nginx; else warn "nginx -t fails; inspect /etc/nginx"; fi
    after=$(snapshot_sites)
    [[ $before == "$after" ]] || warn "existing sites answer differently after removing COMBIND's site"
  fi
  log "removed the service and the nginx site; kept $DATA_DIR, $CONFIG_DIR, $PREFIX and the certificate"
}

case ${1:-} in
  preflight | rollback | status | invite | uninstall) load_settings ;;
esac

case ${1:-} in
  preflight) preflight ;;
  install) install_all "${2:-}" ;;
  activate)
    require_stage "${2:-}"
    activate
    apply_nginx_site "$STAGE/deploy/nginx/combind.conf"
    ;;
  rollback) rollback ;;
  status) status ;;
  invite) invite "${2:-}" "${3:-}" ;;
  uninstall) uninstall ;;
  *) die "usage: remote.sh preflight | install <stage> | activate <stage> | rollback | status | invite <role> [handle] | uninstall" ;;
esac
