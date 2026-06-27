set -Eeuo pipefail

SRC="${1:-pack.json}"
OUT="${2:-pack-caskade.json}"

command -v jq >/dev/null 2>&1 || { echo "Missing dependency: jq" >&2; exit 1; }
[[ -f "$SRC" ]] || { echo "Source not found: $SRC" >&2; exit 1; }

jq '
  map(
    (.remoteUrl | split("/")[-2]) as $tag
    | select(
        ($tag | test("(?i)-arm64ec$"))
        or ($tag | test("(?i)^fexcore$"))
      )
  )
' "$SRC" > "$OUT"

echo "Wrote: $OUT"
