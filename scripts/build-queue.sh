#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${UNI_KIND:?UNI_KIND is required}"
: "${TO_BUILD:?TO_BUILD is required}"

versions=()
expected=()

while IFS='|' read -r kind _ref ver_name _rel_tag filename _short; do
  [[ -n "$kind" ]] || continue
  [[ "$kind" == "$UNI_KIND" ]] || {
    echo "::error::Queue kind '$kind' does not match UNI_KIND '$UNI_KIND'" >&2
    exit 1
  }
  if [[ "$ver_name" =~ -proton([0-9]+)- ]]; then
    versions+=("proton${BASH_REMATCH[1]}")
  else
    versions+=("$ver_name")
  fi
  expected+=("$filename")
done <<< "$TO_BUILD"

((${#versions[@]} > 0)) || {
  echo "::error::Build queue is empty" >&2
  exit 1
}

version_csv="$(IFS=,; printf '%s' "${versions[*]}")"
for filename in "${expected[@]}"; do
  rm -f -- "$ROOT/out/$filename"
done

WCP_NO_NATIVE=1 bash "$ROOT/scripts/local-build.sh" \
  --kind "$UNI_KIND" \
  --versions "$version_csv"

for filename in "${expected[@]}"; do
  [[ -s "$ROOT/out/$filename" ]] || {
    echo "::error::Expected artifact was not produced: out/$filename" >&2
    exit 1
  }
done
