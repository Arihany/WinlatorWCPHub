set -Eeuo pipefail

SRC="${1:-content-full.json}"
OUT="${2:-pack-caskade.json}"

command -v jq >/dev/null 2>&1 || { echo "Missing dependency: jq" >&2; exit 1; }
[[ -f "$SRC" ]] || { echo "Source not found: $SRC" >&2; exit 1; }

jq '
  [
    "fexcore",
    "fexcore-unixlib",
    "dxvk-gplasync-arm64ec",
    "dxvk-gplasync",
    "vkd3d-proton",
    "vkd3d-proton-arm64ec",
    "dxvk-sarek-async"
  ] as $tags
  | map(
      (.remoteUrl | split("/")[-2] | ascii_downcase) as $tag
      | select($tags | index($tag))
    )
' "$SRC" > "$OUT"

echo "Wrote: $OUT"
