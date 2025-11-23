#  /\_/\
# (=•ᆽ•=)づ︻╦╤─

set -Eeuo pipefail

# =============================================================================
# 0. Configuration & Environment
# =============================================================================

# Required Inputs
UNI_KIND="${UNI_KIND:?UNI_KIND is not set}"
UPSTREAM_REPO="${UPSTREAM_REPO:?UPSTREAM_REPO is not set}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
REL_TAG_STABLE="${REL_TAG_STABLE:?REL_TAG_STABLE is not set}"

# Optional / Defaults
REL_TAG_NIGHTLY="${REL_TAG_NIGHTLY:-}"
IN_CHANNEL="${IN_CHANNEL:-stable}"
IN_VERSION="${IN_VERSION:-}"
IS_SCHEDULE="${IS_SCHEDULE:-false}"
GITLAB_REPO="${GITLAB_REPO:-}"

# Temp File Management
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# -----------------------------------------------------------------------------
# 0.5 Ensure required tools (jq, curl)
# -----------------------------------------------------------------------------
ensure_base_tools() {
  local need_jq=false
  local need_curl=false

  command -v jq >/dev/null 2>&1   || need_jq=true
  command -v curl >/dev/null 2>&1 || need_curl=true

  if ! $need_jq && ! $need_curl; then
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "::error::Missing required tools (jq/curl) and no apt-get available on this runner." >&2
    exit 1
  fi

  echo "Installing required tools (jq/curl)..." >&2

  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get -yq update
    if $need_jq;   then sudo apt-get -yq install --no-install-recommends jq;   fi
    if $need_curl; then sudo apt-get -yq install --no-install-recommends curl; fi
    sudo apt-get -yq install --no-install-recommends ca-certificates
  else
    apt-get -yq update
    if $need_jq;   then apt-get -yq install --no-install-recommends jq;   fi
    if $need_curl; then apt-get -yq install --no-install-recommends curl; fi
    apt-get -yq install --no-install-recommends ca-certificates
  fi
}

ensure_base_tools

echo "::group::Configuration"
echo "UNI_KIND    : $UNI_KIND"
echo "IN_CHANNEL  : $IN_CHANNEL"
echo "IS_SCHEDULE : $IS_SCHEDULE"
echo "::endgroup::"

# =============================================================================
# 1. API Helpers (Network & Cache)
# =============================================================================

declare -A ASSET_CACHE

get_assets_cached() {
  local channel="$1"
  local tag_var="REL_TAG_${channel^^}"
  local release_tag="${!tag_var:-}"

  if [[ -z "$release_tag" ]]; then
    ASSET_CACHE[$channel]=""
    return 0
  fi

  if [[ ! -v 'ASSET_CACHE[$channel]' ]]; then
    local out err_file="$TMP_DIR/gh_assets_${channel}.err"
    if ! out="$(gh release view "$release_tag" --repo "$GITHUB_REPOSITORY" \
              --json assets --jq '.assets[].name' 2> "$err_file")"; then
      local err
      err="$(<"$err_file" 2>/dev/null || true)"

      if grep -qiE "release not found|could not resolve to a release|404" <<< "$err"; then
        echo "::notice::Release '$release_tag' not found on $GITHUB_REPOSITORY (treating as empty asset set)" >&2
        out=""
      else
        echo "::warning::Failed to fetch assets for '$release_tag' on $GITHUB_REPOSITORY; assuming no assets exist." >&2
        [[ -n "$err" ]] && echo "$err" >&2
        out=""
      fi
    fi

    ASSET_CACHE[$channel]="$out"
  fi

  printf '%s\n' "${ASSET_CACHE[$channel]}"
}

# Generic GitHub Tag Fetcher
fetch_github_tags() {
  # Returns list of tags line by line
  gh api "repos/$UPSTREAM_REPO/tags?per_page=100" --paginate --jq '.[].name' 2>/dev/null || true
}

get_upstream_head_sha() {
  local sha
  sha="$(gh api "repos/$UPSTREAM_REPO/commits/HEAD" --jq .sha 2>/dev/null || true)"
  if [[ -z "$sha" ]]; then
    echo "::error::Failed to fetch HEAD SHA for $UPSTREAM_REPO" >&2
    exit 1
  fi
  echo "$sha"
}

get_datecode() {
  date -u +%y%m%d
}

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

  echo "::error::Failed to verify tag '$tag' in '$UPSTREAM_REPO' (API error)" >&2
  [[ -n "$err" ]] && echo "$err" >&2
  exit 1
}

# =============================================================================
# 2. GitLab Helpers (Specific for GPLAsync)
# =============================================================================

fetch_gitlab_tags_all() {
  [[ -z "$GITLAB_REPO" ]] && { echo "::error::GITLAB_REPO is not set"; exit 1; }
  
  local enc page HTTP next
  enc="$(jq -rn --arg s "$GITLAB_REPO" '$s|@uri')"
  local out_file="$TMP_DIR/gitlab_tags_raw.txt"
  : > "$out_file"

  echo "Fetching GitLab tags..." >&2
  page=1
  while :; do
    HTTP="$(curl -fsS -L --retry 3 --retry-connrefused \
      -D "$TMP_DIR/headers" \
      -w '%{http_code}' \
      "https://gitlab.com/api/v4/projects/${enc}/repository/tags?per_page=100&page=${page}" \
      -o "$TMP_DIR/page.json" || echo "FAIL")"

    if [[ "$HTTP" != "200" ]]; then
      echo "::error::GitLab API failed with status $HTTP" >&2
      return 1
    fi

    jq -r '.[].name // empty' "$TMP_DIR/page.json" >> "$out_file"

    next="$(awk 'tolower($1)=="x-next-page:"{print $2}' "$TMP_DIR/headers" | tr -d '\r')"
    [[ -z "${next:-}" ]] && break
    page="$next"
  done
}

# =============================================================================
# 3. Strategy Implementations
# =============================================================================

# Helper: Find latest tag matching regex
find_latest_tag() {
  local raw_tags="$1"
  local regex="$2"
  local strip_pat="$3"

  local filtered
  filtered="$(grep -E "$regex" <<< "$raw_tags" || true)"
  # No match → empty string, but do NOT fail the script
  [[ -z "$filtered" ]] && return 0

  if [[ "$strip_pat" == "sort-v" ]]; then
    sort -V <<< "$filtered" | tail -n1
  else
    # Sophisticated sort: strip prefix, sort version, print original
    echo "$filtered" | awk -v pat="$strip_pat" '{
      key = $0; gsub(pat, "", key); print key " " $0
    }' | sort -k1,1V | tail -n1 | awk '{print $2}'
  fi
}

# -----------------------------------------------------------------------------
# Strategy A: Standard GitHub (Box64, FEX, DXVK, VKD3D)
# -----------------------------------------------------------------------------
resolve_standard_strategy() {
  local channel="$1" input_arg="$2"
  local strategy="$UNI_KIND"
  
  local ref ver_name ver_code filename short=""
  local dc; dc="$(get_datecode)"

  case "$strategy" in
    # --- Box64 Family ---
    box64-bionic|wowbox64)
      if [[ "$channel" == "stable" ]]; then
        [[ -z "$input_arg" ]] && return 1
        ref="$input_arg"
        ver_name="${input_arg#v}"
        ver_code="0"
        filename="${strategy}-${ver_name}.wcp"
      else
        # Nightly Logic (unified: <dev_ver>-YYMMDD-sha)
        ref="$(get_upstream_head_sha)"
        [[ -z "$ref" ]] && return 1
        short="${ref:0:7}"

        local all_tags latest latest_base dev_ver nightly_name
        all_tags="$(fetch_github_tags)"
        latest="$(find_latest_tag "$all_tags" '^v[0-9]+\.' '^v')"
        
        [[ -z "$latest" ]] && latest="v0.0.0"
        latest_base="${latest#v}"

        # Bump patch version logic (simple heuristic)
        local v1 v2 v3 rest
        IFS='.' read -r v1 v2 v3 rest <<< "$latest_base"
        if [[ -z "$rest" && "$v3" =~ ^[0-9]+$ ]]; then
          dev_ver="${v1}.${v2}.$((v3 + 1))"
        else
          dev_ver="${latest_base}-dev"
        fi

        nightly_name="${dev_ver}-${dc}-${short}"

        ver_name="$nightly_name"
        ver_code="0"
        filename="${strategy}-${nightly_name}.wcp"
      fi
      ;;

    # --- FEXCore ---
    fexcore)
      if [[ "$channel" == "stable" ]]; then
        [[ -z "$input_arg" ]] && return 1
        ref="$input_arg"
        ver_name="${input_arg#FEX-}"
        ver_code="0"
        filename="FEXCore-${ver_name}.wcp"
      else
        ref="$(get_upstream_head_sha)"
        [[ -z "$ref" ]] && return 1
        short="${ref:0:7}"
        
        local all_tags latest base nightly_name
        all_tags="$(fetch_github_tags)"
        latest="$(find_latest_tag "$all_tags" '^FEX-[0-9]+' '^FEX-')"
        [[ -z "$latest" ]] && latest="FEX-0"
        
        base="${latest#FEX-}"
        nightly_name="${base}-${dc}-${short}"

        ver_name="$nightly_name"
        ver_code="0"
        filename="FEXCore-${nightly_name}.wcp"
      fi
      ;;

    # --- DXVK / VKD3D (Stable Only usually) ---
    dxvk*|vkd3d*)
      if [[ "$channel" == "nightly" ]]; then
         echo "::error::Nightly not supported for $strategy" >&2
         return 1
      fi
      [[ -z "$input_arg" ]] && return 1
      
      ref="$input_arg"
      local base
      if [[ "$ref" =~ ^v[0-9] ]]; then
        base="${ref#v}"
      else
        base="$(sed -E 's/^[^0-9]+//' <<< "$ref")"
        [[ -z "$base" ]] && base="$ref"
      fi

      local prefix="$strategy"
      [[ "$prefix" != *- ]] && prefix="${prefix}-"
      
      ver_name="$base"
      ver_code="0"
      filename="${prefix}${base}.wcp"
      ;;
      
    *)
      echo "::error::Unknown standard strategy: $strategy" >&2
      return 1
      ;;
  esac

  echo "${ref}|${ver_name}|${ver_code}|${filename}|${short}"
}

# -----------------------------------------------------------------------------
# Strategy B: GitLab DXVK-GPLASYNC Family
# -----------------------------------------------------------------------------
resolve_gplasync_strategy() {
  local channel="$1" 
  # Note: GPLAsync logic handles its own iteration/queueing because it processes
  # multiple tags at once (the revision system), unlike the standard 1-tag logic.
  
  local prefix
  case "$UNI_KIND" in
    dxvk-gplasync) prefix="dxvk-gplasync" ;;
    dxvk-gplasync-arm64ec) prefix="dxvk-gplasync-arm64ec" ;;
    *) return 1 ;;
  esac

  # 1. Get cached assets to find what we already have
  local assets existing_pairs_file
  if ! assets="$(get_assets_cached "stable")"; then
    echo "::error::Cannot resolve existing GPLAsync assets (asset cache failed)." >&2
    return 1
  fi

  assets="$(get_assets_cached "stable")"
  existing_pairs_file="$TMP_DIR/exist_gplasync.txt"
  : > "$existing_pairs_file"

  if [[ -n "$assets" ]]; then
    while IFS= read -r name; do
      # Regex: prefix-VERSION-REV.wcp
      if [[ "$name" =~ ^${prefix}-([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)\.wcp$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[3]}" >> "$existing_pairs_file"
      fi
    done <<< "$assets"
  fi

  # 2. Fetch GitLab Tags
  if ! fetch_gitlab_tags_all; then
    return 1
  fi
  local tags_file="$TMP_DIR/gitlab_tags_raw.txt"

  # 3. Determine Targets
  local targets_file="$TMP_DIR/gplasync_targets.txt"
  : > "$targets_file"

  if [[ -n "$IN_VERSION" ]]; then
    # Manual Mode: "v2.7.1-1, v2.6-2"
    IFS=',' read -ra reqs <<< "$IN_VERSION"
    for raw in "${reqs[@]}"; do
      local tag; tag="$(echo "$raw" | xargs)"
      [[ -z "$tag" ]] && continue
      
      # Check regex vBase-Rev
      if [[ ! "$tag" =~ ^v([0-9]+\.[0-9]+(\.[0-9]+)?)\-([0-9]+)$ ]]; then
        echo "::error::Invalid tag format '$tag' (expect vX.Y-R)" >&2
        continue
      fi
      
      # Validate against fetched tags
      if ! grep -Fxq "$tag" "$tags_file"; then
         echo "::error::Tag '$tag' not found on GitLab." >&2
         continue
      fi
      
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[3]}" >> "$targets_file"
    done
  else
    # Auto Mode: Find Max Rev per Base
    jq -rRn '
      (input | split("\n") | map(select(length>0))) as $lines |
      $lines
      | map(capture("^v(?<base>[0-9]+\\.[0-9]+(?:\\.[0-9]+)?)\\-(?<rev>[0-9]+)$")?)
      | map(select(. != null))
      | group_by(.base)
      | map({ base: .[0].base, rev: (map(.rev | tonumber) | max) })
      | .[] | "\(.base) \(.rev)"
    ' < "$tags_file" > "$targets_file"

    if [[ ! -s "$targets_file" ]]; then
      echo "::error::No valid vX.Y[.Z]-R tags found in GitLab for $GITLAB_REPO" >&2
      return 1
    fi
  fi

  # 4. Process Targets & Enqueue
  while read -r base rev; do
    [[ -z "$base" ]] && continue
    
    if grep -Fq "${base} ${rev}" "$existing_pairs_file"; then
      echo "  -> Skipped (Already exists: ${base}-${rev})" >&2
      continue
    fi
    
    # Construct Build Item
    # Format: ref|ver_name|ver_code|filename|short
    local ref="v${base}-${rev}" # GitLab tag
    local ver_name="${base}-${rev}"
    local filename="${prefix}-${base}-${rev}.wcp"
    
    # For GPLAsync, we pass 'rev' as ver_code
    add_to_queue "stable" "${ref}|${ver_name}|0|${filename}|"
    
  done < "$targets_file"
}

# =============================================================================
# 4. Queue Management
# =============================================================================

QUEUE=""
HAS_WORK=false

add_to_queue() {
  local channel="$1" raw_data="$2"
  IFS='|' read -r ref ver_name ver_code filename short <<< "$raw_data"

  local assets
  assets="$(get_assets_cached "$channel")"

  local rel_tag
  [[ "$channel" == "stable" ]] && rel_tag="$REL_TAG_STABLE" || rel_tag="$REL_TAG_NIGHTLY"

  if [[ -n "$assets" ]] && grep -Fxq "$filename" <<< "$assets"; then
    echo "  -> Skipped (Asset Exists: $filename)" >&2
    return
  fi

  if [[ "$channel" == "nightly" && -n "$short" && -n "$assets" ]]; then
    if grep -Eq -- "\-${short}\.wcp$" <<< "$assets"; then
       echo "  -> Skipped (SHA $short already built)" >&2
       return
    fi
  fi

  echo "  -> Queued: $filename" >&2
  QUEUE+="${UNI_KIND}|${channel}|${ref}|${ver_name}|${ver_code}|${rel_tag}|${rel_tag}|${filename}|${short}"$'\n'
  HAS_WORK=true
}

# =============================================================================
# 5. Main Execution Flow
# =============================================================================

dispatch_logic() {
  # A. Special Handling: GPLAsync
  if [[ "$UNI_KIND" == dxvk-gplasync* ]]; then
    echo "::group::Strategy: GPLAsync ($UNI_KIND)"
    resolve_gplasync_strategy "stable"
    echo "::endgroup::"
    return
  fi

  # B. Standard Handling
  local has_nightly=false
  case "$UNI_KIND" in
    box64*|wowbox64|fexcore) has_nightly=true ;;
  esac

  if [[ "$has_nightly" == "true" && -z "$REL_TAG_NIGHTLY" ]]; then
    echo "::error::REL_TAG_NIGHTLY is required for $UNI_KIND but is not set" >&2
    exit 1
  fi

  if [[ "$IS_SCHEDULE" == "true" || "$IN_CHANNEL" == "auto" ]]; then
    # Auto Mode
    echo "::group::Strategy: Auto/Schedule ($UNI_KIND)"
    
    # 1. Stable
    local all_tags; all_tags="$(fetch_github_tags)"
    local latest=""
    
    case "$UNI_KIND" in
      box64*|wowbox64) latest="$(find_latest_tag "$all_tags" '^v[0-9]+\.' '^v')" ;;
      fexcore)         latest="$(find_latest_tag "$all_tags" '^FEX-[0-9]+' '^FEX-')" ;;
      dxvk*|vkd3d*)    latest="$(find_latest_tag "$all_tags" '^(v)?[0-9]' 'sort-v')" ;;
      *)
        echo "::error::Unknown UNI_KIND: $UNI_KIND" >&2
        exit 1
        ;;
    esac

    if [[ -n "$latest" ]]; then
       local res; res="$(resolve_standard_strategy "stable" "$latest")"
       [[ -n "$res" ]] && add_to_queue "stable" "$res"
    else
       echo "::warning::No stable tag found for $UNI_KIND"
    fi

    # 2. Nightly
    if [[ "$has_nightly" == "true" ]]; then
       local res_n; res_n="$(resolve_standard_strategy "nightly" "")"
       [[ -n "$res_n" ]] && add_to_queue "nightly" "$res_n"
    fi
    echo "::endgroup::"

  else
    # Manual Mode
    echo "::group::Strategy: Manual ($IN_CHANNEL / $IN_VERSION)"
    case "$IN_CHANNEL" in
      stable)
        if [[ -z "$IN_VERSION" ]]; then
           # Manual trigger but no version -> Latest stable
           local all_tags; all_tags="$(fetch_github_tags)"
           local latest=""

           case "$UNI_KIND" in
             box64*|wowbox64) latest="$(find_latest_tag "$all_tags" '^v[0-9]+\.' '^v')" ;;
             fexcore)         latest="$(find_latest_tag "$all_tags" '^FEX-[0-9]+' '^FEX-')" ;;
             dxvk*|vkd3d*)    latest="$(find_latest_tag "$all_tags" '^(v)?[0-9]' 'sort-v')" ;;
             *)
               echo "::error::Unknown UNI_KIND: $UNI_KIND" >&2
               exit 1
               ;;
           esac

           if [[ -n "$latest" ]]; then
             local res; res="$(resolve_standard_strategy "stable" "$latest")"
             [[ -n "$res" ]] && add_to_queue "stable" "$res"
           else
             echo "::error::No stable tag found for $UNI_KIND" >&2
             exit 1
           fi
        else
           IFS=',' read -ra vers <<< "$IN_VERSION"
           for raw in "${vers[@]}"; do
             raw="$(echo "$raw" | xargs)"
             [[ -z "$raw" ]] && continue
             if ! check_github_tag_exists "$raw"; then
                exit 1
             fi
             local res; res="$(resolve_standard_strategy "stable" "$raw")"
             [[ -n "$res" ]] && add_to_queue "stable" "$res"
           done
        fi
        ;;
      nightly)
        [[ "$has_nightly" != "true" ]] && { echo "::error::Nightly not supported"; exit 1; }
        local res; res="$(resolve_standard_strategy "nightly" "")"
        [[ -n "$res" ]] && add_to_queue "nightly" "$res"
        ;;
    esac
    echo "::endgroup::"
  fi
}

# Run
dispatch_logic

# Output
if $HAS_WORK; then
  echo "missing=true" >> "$GITHUB_OUTPUT"
  {
    echo "list<<EOF"
    printf '%s' "$QUEUE"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
  echo "::notice::Build queue populated."
else
  echo "missing=false" >> "$GITHUB_OUTPUT"
  echo "list=" >> "$GITHUB_OUTPUT"
  echo "::notice::Nothing to build."
fi
