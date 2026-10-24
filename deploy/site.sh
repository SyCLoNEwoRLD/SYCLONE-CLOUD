# shellcheck shell=bash
# Loads and checks an installation's settings (deploy/site.env, or $COMBIND_SITE). Sourced by
# package.sh and deploy.sh; remote.sh repeats the same checks on the server.

combind_load_site() {
  local file=${COMBIND_SITE:-$(dirname "${BASH_SOURCE[0]}")/site.env}
  [[ -r $file ]] || {
    echo "error: no settings file at $file — copy deploy/site.example.env to deploy/site.env and edit it" >&2
    return 1
  }
  # shellcheck source=/dev/null
  source "$file"
  local name host_re='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'
  for name in COMBIND_USER_HOST COMBIND_ADMIN_HOST; do
    [[ ${!name:-} =~ $host_re && ${#name} -le 253 ]] || { echo "error: $name in $file is not a host name" >&2; return 1; }
  done
  for name in COMBIND_USER_PORT COMBIND_ADMIN_PORT; do
    if ! [[ ${!name:-} =~ ^[0-9]+$ ]] || ((${!name} < 1024 || ${!name} > 65535)); then
      echo "error: $name in $file must be a port from 1024 to 65535" >&2
      return 1
    fi
  done
  [[ $COMBIND_USER_HOST != "$COMBIND_ADMIN_HOST" ]] || { echo "error: the two host names must differ" >&2; return 1; }
  [[ $COMBIND_USER_PORT != "$COMBIND_ADMIN_PORT" ]] || { echo "error: the two ports must differ" >&2; return 1; }
  [[ ${COMBIND_SSH:-} =~ ^[^[:space:]]+$ ]] || { echo "error: COMBIND_SSH in $file is missing" >&2; return 1; }
  export COMBIND_SSH COMBIND_USER_HOST COMBIND_ADMIN_HOST COMBIND_USER_PORT COMBIND_ADMIN_PORT
}
