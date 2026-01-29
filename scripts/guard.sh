#  /\_/\
# (=•ᆽ•=)づ︻╦╤─
# TODO: Move guard logic to py, integrate the pre-reg into the core strategy
set -Eeuo pipefail


: "${UNI_KIND:?UNI_KIND is not set}"
: "${UPSTREAM_REPO:?UPSTREAM_REPO is not set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
: "${REL_TAG_STABLE:?REL_TAG_STABLE is not set}"

REL_TAG_NIGHTLY="${REL_TAG_NIGHTLY:-}"
IN_CHANNEL="${IN_CHANNEL:-stable}"
IN_VERSION="${IN_VERSION:-}"
IS_SCHEDULE="${IS_SCHEDULE:-false}"
GITLAB_REPO="${GITLAB_REPO:-}"

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

ensure_base_tools() {

  if command -v jq >/dev/null 2>&1 &&
     command -v curl >/dev/null 2>&1 &&
     command -v gh >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "::error::Missing required tools (need: jq curl gh) and no apt-get available." >&2
    exit 1
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo "::error::Missing required tool: gh (GitHub CLI). Install it on the runner." >&2
    exit 1
  fi

  echo "Installing required tools (jq/curl)..." >&2

  run_as_root() {
    if command -v sudo >/dev/null 2>&1; then sudo "$@"; else "$@"; fi
  }

  run_as_root apt-get -yq update
  run_as_root apt-get -yq install --no-install-recommends jq curl ca-certificates
}

ensure_base_tools

echo "::group::Configuration"
echo "UNI_KIND    : $UNI_KIND"
echo "IN_CHANNEL  : $IN_CHANNEL"
echo "IS_SCHEDULE : $IS_SCHEDULE"
echo "::endgroup::"

declare -A ASSET_CACHE

get_assets_cached() {
  local channel="$1"
  local __outvar="${2:-}"
  local tag_var="REL_TAG_${channel^^}"
  local release_tag="${!tag_var:-}"

  if [[ -z "$release_tag" ]]; then
    ASSET_CACHE[$channel]=""
    [[ -n "$__outvar" ]] && printf -v "$__outvar" '%s' "" || true
    return 0
  fi

  if [[ -v ASSET_CACHE[$channel] ]]; then
    if [[ -n "$__outvar" ]]; then
      printf -v "$__outvar" '%s' "${ASSET_CACHE[$channel]}"
    else
      printf '%s\n' "${ASSET_CACHE[$channel]}"
    fi
    return 0
  fi

  local out err err_file
  err_file="$TMP_DIR/gh_assets_${channel}.err"
  if ! out="$(gh release view "$release_tag" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name' 2>"$err_file")"; then
    err="$(<"$err_file" 2>/dev/null || true)"
    if grep -qiE "release not found|could not resolve|404" <<<"$err"; then
      echo "::notice::Release '$release_tag' not found (treating as empty)." >&2
      out=""
    else
      echo "::warning::Failed to fetch assets for '$release_tag'." >&2
      [[ -n "$err" ]] && echo "$err" >&2
      out=""
    fi
  fi

  ASSET_CACHE[$channel]="$out"
  if [[ -n "$__outvar" ]]; then
    printf -v "$__outvar" '%s' "$out"
  else
    printf '%s\n' "$out"
  fi
}

fetch_github_tags() {
  gh api "repos/$UPSTREAM_REPO/tags?per_page=100" --paginate --jq '.[].name' 2>/dev/null || true
}

get_upstream_head_sha() {
  local sha
  sha="$(gh api "repos/$UPSTREAM_REPO/commits/HEAD" --jq .sha 2>/dev/null || true)"
  [[ -z "$sha" ]] && { echo "::error::Failed to fetch HEAD SHA for $UPSTREAM_REPO" >&2; exit 1; }
  echo "$sha"
}

get_datecode() { date -u +%y%m%d; }

check_github_tag_exists() {
  local tag="$1"
  local err_file="$TMP_DIR/tag_check.err"
  if gh api "repos/$UPSTREAM_REPO/git/ref/tags/$tag" --silent >/dev/null 2> "$err_file"; then
    return 0
  fi
  
  local err
  err="$(<"$err_file" 2>/dev/null || true)"
  if grep -qi "Not Found" <<< "$err"; then
    echo "::error::Tag '$tag' not found in '$UPSTREAM_REPO'" >&2
    return 1
  fi
  echo "::error::Failed to verify tag '$tag' (API error)" >&2
  [[ -n "$err" ]] && echo "$err" >&2
  exit 1
}

# Helper
get_tag_regex_for_kind() {
  local kind="$1"
  case "$kind" in
    box64*|wowbox64)
      printf '%s\t%s\n' '^v[0-9]+\.[0-9]+\.[0-9]*[02468]$' '^v'
      ;;
    fexcore)
      printf '%s\t%s\n' '^FEX-[0-9]+' '^FEX-'
      ;;
    dxvk*|vkd3d*)
      printf '%s\t%s\n' '^(v)?[0-9]' ''
      ;;
    *)
      return 1
      ;;
  esac
}

get_latest_stable() {
  local kind="${1:-$UNI_KIND}"
  local regex strip_pat all_tags

  if ! read -r regex strip_pat <<< "$(get_tag_regex_for_kind "$kind")"; then
    echo "::error::Unknown UNI_KIND for stable resolution: $kind" >&2
    exit 1
  fi

  all_tags="$(fetch_github_tags)"
  find_latest_tag "$all_tags" "$regex" "$strip_pat"
}

fetch_gitlab_tags_all() {
  [[ -z "$GITLAB_REPO" ]] && { echo "::error::GITLAB_REPO is not set"; exit 1; }
  
  local enc page HTTP next out_file="$TMP_DIR/gitlab_tags_raw.txt"
  enc="$(jq -rn --arg s "$GITLAB_REPO" '$s|@uri')"
  : > "$out_file"

  echo "Fetching GitLab tags..." >&2
  page=1
  while :; do
    HTTP="$(curl -fsS -L --retry 3 --retry-connrefused \
      -D "$TMP_DIR/headers" \
      -w '%{http_code}' \
      "https://gitlab.com/api/v4/projects/${enc}/repository/tags?per_page=100&page=${page}" \
      -o "$TMP_DIR/page.json" || echo "FAIL")"

    [[ "$HTTP" != "200" ]] && { echo "::error::GitLab API failed with status $HTTP" >&2; return 1; }

    jq -r '.[].name // empty' "$TMP_DIR/page.json" >> "$out_file"

    next="$(awk 'tolower($1)=="x-next-page:"{print $2}' "$TMP_DIR/headers" | tr -d '\r')"
    [[ -z "${next:-}" ]] && break
    page="$next"
  done
}

find_latest_tag() {
  local raw_tags="$1" regex="$2" strip_pat="$3"
  local filtered
  filtered="$(grep -E "$regex" <<< "$raw_tags" || true)"
  [[ -z "$filtered" ]] && return 0

  if [[ -z "$strip_pat" ]]; then
    sort -V <<< "$filtered" | tail -n1
  else
    awk -v pat="$strip_pat" '{
      key = $0; gsub(pat, "", key); print key " " $0
    }' <<<"$filtered" | sort -k1,1V | tail -n1 | awk '{print $2}'
  fi
}

# Standard
resolve_standard_strategy() {
  local channel="$1" input_arg="$2"
  local strategy="$UNI_KIND"
  local ref ver_name filename short=""
  local dc=""

  if [[ "$channel" == "nightly" ]]; then
    dc="$(get_datecode)"
  fi

  case "$strategy" in
    box64-bionic|wowbox64)
      if [[ "$channel" == "stable" ]]; then
        [[ -z "$input_arg" ]] && return 1
        ref="$input_arg"
        ver_name="${input_arg#v}"
        filename="${strategy}-${ver_name}.wcp"
      else
        ref="$(get_upstream_head_sha)"
        short="${ref:0:7}"
        local latest latest_base dev_ver
        latest="$(get_latest_stable "$strategy")"
        [[ -z "$latest" ]] && latest="v0.0.0"
        latest_base="${latest#v}"

        # Heuristic: Bump patch version
        local v1 v2 v3 rest
        IFS='.' read -r v1 v2 v3 rest <<< "$latest_base"
        if [[ -z "$rest" && "$v3" =~ ^[0-9]+$ ]]; then
          dev_ver="${v1}.${v2}.$((v3 + 1))"
        else
          dev_ver="${latest_base}-dev"
        fi

        ver_name="${dev_ver}-${dc}-${short}"
        filename="${strategy}-${ver_name}.wcp"
      fi
      ;;

    fexcore)
      if [[ "$channel" == "stable" ]]; then
        [[ -z "$input_arg" ]] && return 1
        ref="$input_arg"
        ver_name="${input_arg#FEX-}"
        filename="FEXCore-${ver_name}.wcp"
      else
        ref="$(get_upstream_head_sha)"
        short="${ref:0:7}"
        
        local latest base
        latest="$(find_latest_tag "$(fetch_github_tags)" '^FEX-[0-9]+' '^FEX-')"
        [[ -z "$latest" ]] && latest="FEX-0"
        base="${latest#FEX-}"
        
        ver_name="${base}-${dc}-${short}"
        filename="FEXCore-${ver_name}.wcp"
      fi
      ;;

    dxvk*|vkd3d*)
      [[ "$channel" == "nightly" ]] && { echo "::error::Nightly not supported for $strategy" >&2; return 1; }
      [[ -z "$input_arg" ]] && return 1
      
      ref="$input_arg"
      local base
      if [[ "$ref" =~ ^v[0-9] ]]; then
        base="${ref#v}"
      else
        base="$(sed -E 's/^[^0-9]+//' <<<"$ref")"
      fi
      [[ -z "$base" ]] && base="$ref"

      local prefix="$strategy"
      [[ "$prefix" != *- ]] && prefix="${prefix}-"
      
      ver_name="$base"
      filename="${prefix}${base}.wcp"
      ;;
      
    *)
      echo "::error::Unknown standard strategy: $strategy" >&2
      return 1
      ;;
  esac
  echo "${ref}|${ver_name}|${filename}|${short}"
}

# gplasync
resolve_gplasync_strategy() {
  local prefix="$UNI_KIND"
  [[ "$prefix" != dxvk-gplasync* ]] && return 1

  local assets=""
  get_assets_cached "stable" assets

  local existing_pairs_file="$TMP_DIR/exist_gplasync.txt"
  : > "$existing_pairs_file"

  if [[ -n "$assets" ]]; then
    while IFS= read -r name; do
      if [[ "$name" =~ ^${prefix}-([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)\.wcp$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[3]}" >> "$existing_pairs_file"
      fi
    done <<< "$assets"
  fi

  fetch_gitlab_tags_all || return 1
  local tags_file="$TMP_DIR/gitlab_tags_raw.txt"
  local targets_file="$TMP_DIR/gplasync_targets.txt"
  : > "$targets_file"

  if [[ -n "$IN_VERSION" ]]; then
    # Manual
    IFS=',' read -ra reqs <<< "$IN_VERSION"
    for raw in "${reqs[@]}"; do
      local tag; tag="$(echo "$raw" | xargs)"
      [[ -z "$tag" ]] && continue
      
      if [[ ! "$tag" =~ ^v([0-9]+\.[0-9]+(\.[0-9]+)?)\-([0-9]+)$ ]]; then
        echo "::error::Invalid tag format '$tag' (expect vX.Y-R)" >&2; continue
      fi
      if ! grep -Fxq "$tag" "$tags_file"; then
         echo "::error::Tag '$tag' not found on GitLab." >&2; continue
      fi
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[3]}" >> "$targets_file"
    done
  else
    # Auto: pick the single latest tag overall
    latest_line="$(
      grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9]+$' "$tags_file" \
        | sed -E 's/^v([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$/\1 \3/' \
        | sort -k1,1V -k2,2n \
        | tail -n1
    )"
    [[ -n "$latest_line" ]] || { echo "::error::No valid vX.Y-R tags found in GitLab" >&2; return 1; }
    printf '%s\n' "$latest_line" > "$targets_file"
  fi

  while read -r base rev; do
    [[ -z "$base" ]] && continue
    if grep -Fq "${base} ${rev}" "$existing_pairs_file"; then
      echo "  -> Skipped (Already exists: ${base}-${rev})" >&2; continue
    fi

    add_to_queue "stable" "v${base}-${rev}|${base}-${rev}|${prefix}-${base}-${rev}.wcp|"
  done < "$targets_file"
}

QUEUE=""
HAS_WORK=false

add_to_queue() {
  local channel="$1" raw_data="$2"
  IFS='|' read -r ref ver_name filename short <<< "$raw_data"

  local assets=""
  get_assets_cached "$channel" assets
  local rel_tag
  [[ "$channel" == "stable" ]] && rel_tag="$REL_TAG_STABLE" || rel_tag="$REL_TAG_NIGHTLY"

  if [[ -n "$assets" ]]; then
    if grep -Fxq "$filename" <<< "$assets"; then
      echo "  -> Skipped (Asset Exists: $filename)" >&2; return
    fi
    if [[ "$channel" == "nightly" && -n "$short" ]]; then
       # Avoid rebuilding same SHA for nightly
       if grep -Eq -- "\-${short}\.wcp$" <<< "$assets"; then
          echo "  -> Skipped (SHA $short already built)" >&2; return
       fi
    fi
  fi

  echo "  -> Queued: $filename" >&2
  QUEUE+="${UNI_KIND}|${channel}|${ref}|${ver_name}|${rel_tag}|${filename}|${short}"$'\n'
  HAS_WORK=true
}

dispatch_logic() {
  # gplasync
  if [[ "$UNI_KIND" == dxvk-gplasync* ]]; then
    echo "::group::Strategy: GPLAsync ($UNI_KIND)"
    resolve_gplasync_strategy
    echo "::endgroup::"
    return
  fi

  # Standard
  local has_nightly=false
  if [[ -n "${REL_TAG_NIGHTLY:-}" ]]; then
    has_nightly=true
  fi

  # Auto / Schedule
  if [[ "$IS_SCHEDULE" == "true" || "$IN_CHANNEL" == "auto" ]]; then
    echo "::group::Strategy: Auto/Schedule ($UNI_KIND)"
    
    local latest; latest="$(get_latest_stable)"
    if [[ -n "$latest" ]]; then
       local res; res="$(resolve_standard_strategy "stable" "$latest")"
       [[ -n "$res" ]] && add_to_queue "stable" "$res"
    else
       echo "::warning::No stable tag found for $UNI_KIND"
    fi

    # Nightly
    if [[ "$has_nightly" == "true" ]]; then
       local res_n; res_n="$(resolve_standard_strategy "nightly" "")"
       [[ -n "$res_n" ]] && add_to_queue "nightly" "$res_n"
    fi
    echo "::endgroup::"

  # Manual
  else
    echo "::group::Strategy: Manual ($IN_CHANNEL / $IN_VERSION)"
    if [[ "$IN_CHANNEL" == "stable" ]]; then
        if [[ -z "$IN_VERSION" ]]; then
           # No version specified -> fetch latest
           local latest; latest="$(get_latest_stable)"
           if [[ -n "$latest" ]]; then
             local res; res="$(resolve_standard_strategy "stable" "$latest")"
             [[ -n "$res" ]] && add_to_queue "stable" "$res"
           else
             echo "::error::No stable tag found for $UNI_KIND" >&2; exit 1
           fi
        else
           # Specific versions
           IFS=',' read -ra vers <<< "$IN_VERSION"
           for raw in "${vers[@]}"; do
             raw="$(echo "$raw" | xargs)"
             [[ -z "$raw" ]] && continue
             check_github_tag_exists "$raw"
             local res; res="$(resolve_standard_strategy "stable" "$raw")"
             [[ -n "$res" ]] && add_to_queue "stable" "$res"
           done
        fi
    elif [[ "$IN_CHANNEL" == "nightly" ]]; then
        [[ "$has_nightly" != "true" ]] && { echo "::error::Nightly not supported"; exit 1; }
        local res; res="$(resolve_standard_strategy "nightly" "")"
        [[ -n "$res" ]] && add_to_queue "nightly" "$res"
    fi
    echo "::endgroup::"
  fi
}

dispatch_logic

if $HAS_WORK; then
  echo "missing=true" >> "$GITHUB_OUTPUT"
  printf 'list<<EOF\n%sEOF\n' "$QUEUE" >> "$GITHUB_OUTPUT"
  echo "::notice::Build queue populated."
else
  echo "missing=false" >> "$GITHUB_OUTPUT"
  echo "list=" >> "$GITHUB_OUTPUT"
  echo "::notice::Nothing to build."
fi
