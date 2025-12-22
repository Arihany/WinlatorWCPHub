set -Eeuo pipefail

die() { echo "::error::$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing tool: $1"; }

REPO="${1:-}"
README_FILE="${2:-}"

[ -n "$REPO" ] || die "Usage: $0 <owner/repo> <readme_path>"
[ -n "$README_FILE" ] || die "Usage: $0 <owner/repo> <readme_path>"
[ -f "$README_FILE" ] || die "README not found: $README_FILE"

need jq
need perl
need gh

default_map_json() {
  cat <<'JSON'
{
  "fex":      "FEXCore",
  "dxvk":     "DXVK",
  "sarek":    "DXVK-SAREK-ASYNC",
  "gplasync": "DXVK-GPLASYNC",
  "vkd3d":    "VKD3D-PROTON",
  "box64":    "BOX64-BIONIC"
}
JSON
}

MAP_FILE="$(mktemp)"
cleanup() { rm -f "$MAP_FILE" 2>/dev/null || true; }
trap cleanup EXIT

if [ -n "${MAP_JSON_PATH:-}" ]; then
  [ -f "$MAP_JSON_PATH" ] || die "MAP_JSON_PATH not found: $MAP_JSON_PATH"
  cp "$MAP_JSON_PATH" "$MAP_FILE"
else
  default_map_json > "$MAP_FILE"
fi

echo "::group::Validating README placeholders"
missing=0
while read -r key; do
  if ! grep -q "<!--${key}-->" "$README_FILE"; then
    echo "::error file=${README_FILE}::Placeholder <!--${key}--> not found"
    missing=1
    continue
  fi
  count="$(grep -o "<!--${key}-->" "$README_FILE" | wc -l | tr -d ' ')"
  echo "✅ <!--${key}--> found (${count} occurrence(s))"
done < <(jq -r 'keys[]' "$MAP_FILE")
[ "$missing" -eq 0 ] || exit 1
echo "::endgroup::"

parse_version_from_body() {
  perl -0777 -ne '
    if (m/^\s*-\s*Current\s+version:\s*([0-9]+(?:\.[0-9]+){0,2}[0-9A-Za-z]*(?:[-+][0-9A-Za-z().-]+)*)/mi) {
      print $1;
    }
  '
}

is_valid_version() {
  local tag="$1" ver="$2"
  if [ "$tag" = "FEXCore" ]; then
    perl -e 'exit((shift)=~/^\d{2,6}(\.\d+)?$/ ? 0 : 1)' "$ver"
  else
    perl -e 'exit((shift)=~/^(?:\d+\.\d+\.\d+(?:[-+][\w().-]+)*|\d+\.\d+[0-9A-Za-z]*(?:\.\w+)*(?:[-+][\w().-]+)*|\d{4}[-.]\d{2}[-.]\d{2}|\d{8})$/ ? 0 : 1)' "$ver"
  fi
}

format_final() {
  local key="$1" ver="$2"

  if [ "$ver" = "⛔BRRR" ]; then
    printf "%s" "$ver"
    return 0
  fi

  if [ "$key" = "box64" ]; then
    local base maj min pat next
    base="$(perl -ne 'print "$1.$2.$3" if /^(\d+)\.(\d+)\.(\d+)/' <<<"$ver")"
    if [ -n "$base" ]; then
      maj="${base%%.*}"
      base="${base#*.}"
      min="${base%%.*}"
      pat="${base#*.}"
      next="$((pat + 1))"
      printf "\`%s.%s.%s\` \`%s.%s.%s\`" "$maj" "$min" "$pat" "$maj" "$min" "$next"
    else
      printf "\`%s\`" "$ver"
    fi
    return 0
  fi

  printf "\`%s\`" "$ver"
}

apply_placeholder() {
  local key="$1" final="$2" file="$3"
  KEY="$key" FINAL="$final" perl -0777 -i -pe '
    my $k = $ENV{KEY};
    my $v = $ENV{FINAL};
    s/(<!--\Q$k\E-->)(?:[^\|\n]*)?(?=\s*\|)/$1 $v/g;
  ' "$file"
}

before="$(mktemp)"
tmp="$(mktemp)"
cp "$README_FILE" "$before"
cp "$README_FILE" "$tmp"

echo "::group::Fetching release info"
while IFS=$'\t' read -r key tag; do
  printf "%-10s : " "$key"

  body=""
  ver_raw=""
  if body="$(gh release view "$tag" --repo "$REPO" --json body --jq '.body' 2>/dev/null)"; then
    ver_raw="$(printf '%s' "$body" | parse_version_from_body || true)"
  fi

  if [ -z "$ver_raw" ]; then
    ver="⛔BRRR"
    echo "⛔ failed to parse version, setting to $ver"
    echo "::notice::Release body head (first 20 lines) for $tag:"
    printf '%s\n' "$body" | sed -n '1,20p'
  else
    if is_valid_version "$tag" "$ver_raw"; then
      ver="$ver_raw"
    else
      ver="⛔BRRR"
      echo "⛔ suspicious format '$ver_raw', setting to $ver"
    fi
  fi

  final_ver="$(format_final "$key" "$ver")"
  apply_placeholder "$key" "$final_ver" "$tmp"

  echo "→ $final_ver"
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$MAP_FILE")
echo "::endgroup::"

changed=false
if cmp -s "$before" "$tmp"; then
  echo "No changes in README."
else
  mv "$tmp" "$README_FILE"
  changed=true
  echo "README updated."
fi

rm -f "$before" "$tmp" 2>/dev/null || true

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "readme_changed=$changed" >> "$GITHUB_OUTPUT"
fi
