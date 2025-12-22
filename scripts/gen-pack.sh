set -Eeuo pipefail

infer_repo_from_git() {
  local url
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$url" ]] || return 1

  if [[ "$url" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
    return 0
  fi

  if [[ "$url" =~ ^git@[^:]+:([^/]+)/([^/]+)(\.git)?$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
    return 0
  fi

  return 1
}

REPO="${1:-${GITHUB_REPOSITORY:-}}"
OUT="${2:-content.json}"

if [[ -z "$REPO" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REPO="$(infer_repo_from_git || true)"
  fi
fi

if [[ -z "$REPO" ]]; then
  echo "Usage: $0 owner/repo [output_path]" >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "Missing dependency: curl" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "Missing dependency: jq" >&2; exit 1; }

AUTH_HEADERS=()
if [[ -n "${GH_TOKEN:-}" ]]; then
  AUTH_HEADERS=(-H "Authorization: Bearer ${GH_TOKEN}")
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH_HEADERS=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

TMP_ITEMS="$(mktemp)"
FILTER_FILE="$(mktemp)"
trap 'rm -f "$TMP_ITEMS" "$FILTER_FILE"' EXIT

cat > "$FILTER_FILE" <<'JQ'
def strip_ext:
  sub("\\.wcp\\.xz$";"")
  | sub("\\.wcp$";"")
  | sub("\\.xz$";"");

def norm:
  gsub("[-_]+"; "-")
  | gsub("^-+"; "")
  | gsub("-+$"; "");

def version_first:
  . as $s
  | ($s | norm) as $n
  | ($n | split("-")) as $t
  | (
      [range(0; ($t|length))
        | select($t[.] | test("^[0-9]+(\\.[0-9]+)*[A-Za-z]*$"))
      ] | .[0]?
    ) as $i
  | if $i == null then
      $n
    else
      ($t[$i]) as $v0
      | if ($i + 1 < ($t|length))
           and ($t[$i+1] | test("^[0-9]+$"))
           and ( ($v0 | test("\\.")) or ($v0 | test("[A-Za-z]")) )
        then
          ($v0 + "-" + $t[$i+1]) as $ver
          | ([ $t[0:$i][], $t[($i+2):][] ]) as $rest
          | ([$ver] + $rest) | join("-")
        else
          ($v0) as $ver
          | ([ $t[0:$i][], $t[($i+1):][] ]) as $rest
          | ([$ver] + $rest) | join("-")
        end
    end;

def mk($type; $re; $extra; $base):
  {
    type: $type,
    verName: (
      $base
      | sub($re; "")
      | (if $extra == null then . else sub($extra; "") end)
      | version_first
    ),
    verCode: "0",
    remoteUrl: .browser_download_url
  };

.[]?
| .assets[]?
| (.name | strip_ext) as $base
| if   ($base | test("(?i)^wine[-_]"))     then mk("Wine";     "(?i)^wine[-_]";     null;                 $base)
  elif ($base | test("(?i)^box64[-_]"))    then mk("Box64";    "(?i)^box64[-_]";    "(?i)^bionic[-_]";    $base)
  elif ($base | test("(?i)^wowbox64[-_]")) then mk("WOWBox64"; "(?i)^wowbox64[-_]"; null;                 $base)
  elif ($base | test("(?i)^dxvk[-_]"))     then mk("DXVK";     "(?i)^dxvk[-_]";     null;                 $base)
  elif ($base | test("(?i)^fexcore[-_]"))  then mk("FEXCore";  "(?i)^fexcore[-_]";  null;                 $base)
  elif ($base | test("(?i)^vkd3d[-_]"))    then mk("VKD3D";    "(?i)^vkd3d[-_]";    "(?i)^proton[-_]";    $base)
  else empty end
JQ

page=1
while :; do
  api="https://api.github.com/repos/${REPO}/releases?per_page=100&page=${page}"
  json="$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${AUTH_HEADERS[@]}" \
    "$api")"

  if [[ "$(jq 'length' <<<"$json")" -eq 0 ]]; then
    break
  fi

  jq -c -f "$FILTER_FILE" <<<"$json" >> "$TMP_ITEMS"
  page=$((page + 1))
done

if [[ ! -s "$TMP_ITEMS" ]]; then
  echo "[]" > "$OUT"
  echo "No matching assets found. Wrote empty array to: $OUT" >&2
  exit 0
fi

jq -s 'sort_by(.remoteUrl) | unique_by(.remoteUrl) | sort_by(.type, .verName)' \
  "$TMP_ITEMS" > "$OUT"

echo "Wrote: $OUT"
