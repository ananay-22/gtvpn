#!/bin/sh
set -eu
name='{NAME}'
payload='{PAYLOAD}'
environment='{ENVIRONMENT}'
root="${GTVPN_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/gtvpn}"
apps="$root/apps/$name"
app="$apps/$payload"
complete="$app/.complete"

discard() {
  if [ -e "$1" ]; then
    chmod -R u+w "$1"
    rm -rf "$1"
  fi
}

usage() {
  echo "usage: $name --app-cache info | clear [apps|envs|packages|all]" >&2
  exit 2
}

measured() {
  if [ -e "$1" ]; then
    printf '%-9s %-8s %s\n' "$2" "$(du -sh "$1" | cut -f1)" "$1"
  else
    printf '%-9s %-8s %s\n' "$2" "-" "$1"
  fi
}

cache_info() {
  printf '%-9s %s\n' root "$root"
  measured "$root/apps" apps
  measured "$root/envs" envs
  measured "$root/packages" packages
  measured "$app" app
  [ -z "$environment" ] || measured "$root/envs/$environment" env
}

cache_clear() {
  case "$1" in
    apps|envs|packages) categories="$1" ;;
    all) categories="apps envs packages" ;;
    *) usage ;;
  esac
  for category in $categories; do
    discard "$root/$category"
    echo "cleared $root/$category"
  done
}

if [ "${1:-}" = "--app-cache" ]; then
  case "${2:-}" in
    info)
      [ "$#" -eq 2 ] || usage
      cache_info
      ;;
    clear)
      [ "$#" -le 3 ] || usage
      cache_clear "${3:-all}"
      ;;
    *) usage ;;
  esac
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  {UNAME_S}-{UNAME_M}) ;;
  *)
    echo "$name runs on {PLATFORM_LABEL}, not $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac

if [ ! -f "$complete" ]; then
  mkdir -p "$apps"
  exec 9>"$app.lock"
  flock 9
  if [ ! -f "$complete" ]; then
    found="$(tail -c +{OFFSET} "$0" | {SHA} | cut -d' ' -f1)"
    if [ "$found" != "$payload" ]; then
      echo "$name: $0 is corrupt: its payload hashes to $found, not $payload; download it again" >&2
      exit 65
    fi
    discard "$app"
    trap 'discard "$app"' EXIT
    echo "$name: unpacking into $app" >&2
    mkdir "$app"
    tail -c +{OFFSET} "$0" | gzip -dc | tar -xf - -C "$app"
    : >"$complete"
    trap - EXIT
  fi
  exec 9>&-
fi

exec "$app/{PROGRAM}" "$@"
exit 1
