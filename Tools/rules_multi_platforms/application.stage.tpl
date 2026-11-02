#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo "usage: $0 <application folder>" >&2
  exit 2
fi
here="$(cd "$(dirname "$0")" && pwd)"
target="$1"
manifests="$target/{MANIFESTS}"
mkdir -p "$manifests"
found="$(mktemp)"
needed="$(mktemp)"
trap 'rm -f "$found" "$needed"' EXIT
cat "$here/{MANIFESTS}/{NAME}.placed" > "$found"
cat "$here/{MANIFESTS}/{NAME}.requires" > "$needed"
for manifest in "$manifests"/*.placed "$manifests"/*.requires; do
  [ -f "$manifest" ] || continue
  case "$(basename "$manifest")" in
    {NAME}.placed|{NAME}.requires) ;;
    *.placed) cat "$manifest" >> "$found" ;;
    *.requires) cat "$manifest" >> "$needed" ;;
  esac
done
missing="$(grep -Fxv -f "$found" "$needed" || true)"
if [ -n "$missing" ]; then
  echo "staging {NAME} would leave $(printf '%s\n' "$missing" | wc -l | tr -d ' ') required files missing from $target:" >&2
  printf '%s\n' "$missing" | sed -n 1,20p >&2
  exit 1
fi
chmod -R u+w "$target"
if [ -f "$manifests/{NAME}.placed" ]; then
  while IFS="$(printf '\t')" read -r path source; do
    rm -f "$target/$path"
  done < "$manifests/{NAME}.placed"
fi
(cd "$here" && tar -cf - --exclude=./{STAGE} .) | (cd "$target" && tar -xf -)
chmod -R u+w "$target"
