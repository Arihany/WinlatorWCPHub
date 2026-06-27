set -Eeuo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/build-targets.sh"

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

gplasync_patch_available() {
  local base="$1"
  local rev="$2"
  local base_url="${GPLASYNC_BASE_URL:-https://gitlab.com/Ph42oN/dxvk-gplasync/-/raw/main/patches}"
  local patch_name="dxvk-gplasync-${base}-${rev}.patch"

  if curl -fsI "${base_url}/${patch_name}" >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$base" == "2.4.1" && "$rev" == "1" ]] &&
     curl -fsI "${base_url}/dxvk-gplasync-2.4-1.patch" >/dev/null 2>&1; then
    return 0
  fi

  return 1
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
    fexcore)
      # FEX is stable-only (nightly dropped).
      [[ "$channel" == "stable" ]] || { echo "::error::Nightly not supported for $strategy" >&2; return 1; }
      [[ -z "$input_arg" ]] && return 1
      ref="$input_arg"
      ver_name="${input_arg#FEX-}"
      filename="FEXCore-${ver_name}.wcp"
      ;;

    dxvk*|vkd3d*)
      [[ "$channel" == "nightly" ]] && { echo "::error::Nightly not supported for $strategy" >&2; return 1; }
      [[ -z "$input_arg" ]] && return 1
      
      ref="$input_arg"
      local base
      base="$(version_base_from_ref "$ref")"

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

  local requested_versions="${IN_VERSION:-}"
  if [[ -z "$requested_versions" ]]; then
    requested_versions="$(default_versions_for_kind "$UNI_KIND")"
  fi

  IFS=',' read -ra reqs <<< "$requested_versions"
  for raw in "${reqs[@]}"; do
    local req tag_line base rev
    req="$(echo "$raw" | xargs)"
    [[ -z "$req" ]] && continue

    if is_gplasync_prereg_token "$req"; then
      local pre_reg_entry
      pre_reg_entry="$(pre_reg_queue_entry "$UNI_KIND" "$req")"
      add_to_queue "stable" "$pre_reg_entry"
      continue
    elif is_latest_token "$req"; then
      tag_line="$(
        grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9]+$' "$tags_file" \
          | sed -E 's/^v([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$/\1 \3/' \
          | sort -k1,1V -k2,2n \
          | tail -n1 || true
      )"
    elif [[ "$req" =~ ^v?([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$ ]]; then
      base="${BASH_REMATCH[1]}"
      rev="${BASH_REMATCH[3]}"
      tag_line="${base} ${rev}"
      if ! grep -Fxq "v${base}-${rev}" "$tags_file"; then
        echo "::warning::GPLAsync tag 'v${base}-${rev}' not found; skipping." >&2
        continue
      fi
    elif [[ "$req" =~ ^v?([0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
      base="${BASH_REMATCH[1]}"
      tag_line="$(
        grep -E "^v${base}-[0-9]+$" "$tags_file" \
          | sed -E 's/^v([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$/\1 \3/' \
          | sort -k1,1V -k2,2n \
          | tail -n1 || true
      )"
      if [[ -z "$tag_line" ]]; then
        echo "::warning::No GPLAsync tag found for DXVK ${base}; skipping." >&2
        continue
      fi
    else
      echo "::warning::Invalid GPLAsync version '$req'; expected X.Y[.Z], X.Y[.Z]-R, or latest. Skipping." >&2
      continue
    fi

    [[ -n "$tag_line" ]] || continue
    read -r base rev <<< "$tag_line"
    if ! gplasync_patch_available "$base" "$rev"; then
      echo "::warning::GPLAsync patch not found for ${base}-${rev}; skipping." >&2
      continue
    fi
    echo "${base} ${rev}" >> "$targets_file"
  done

  while read -r base rev; do
    [[ -z "$base" ]] && continue
    if grep -Fq "${base} ${rev}" "$existing_pairs_file"; then
      echo "  -> Skipped (Already exists: ${base}-${rev})" >&2
    else
      add_to_queue "stable" "v${base}-${rev}|${base}-${rev}|${prefix}-${base}-${rev}.wcp|"
    fi

    if dxvk_binsem_kind_supported "$UNI_KIND" && dxvk_binsem_supported_base "$base"; then
      add_to_queue "stable" "v${base}-${rev}|${base}-${rev}|${prefix}-${base}-${rev}-binsem.wcp|"
    fi
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

  if grep -Fq "|$filename|" <<< "$QUEUE"; then
    echo "  -> Skipped (Already queued: $filename)" >&2
    return
  fi

  echo "  -> Queued: $filename" >&2
  QUEUE+="${UNI_KIND}|${channel}|${ref}|${ver_name}|${rel_tag}|${filename}|${short}"$'\n'
  HAS_WORK=true
}

queue_stable_versions() {
  local csv="$1"
  local raw ref res

  IFS=',' read -ra _stable_reqs <<< "$csv"
  for raw in "${_stable_reqs[@]}"; do
    raw="$(echo "$raw" | xargs)"
    [[ -z "$raw" ]] && continue

    if pre_reg_entry="$(pre_reg_queue_entry "$UNI_KIND" "$raw" 2>/dev/null)"; then
      add_to_queue "stable" "$pre_reg_entry"
      continue
    elif is_latest_token "$raw"; then
      ref="$(get_latest_stable)"
      [[ -n "$ref" ]] || { echo "::warning::No stable tag found for $UNI_KIND"; continue; }
    else
      ref="$(normalize_github_version_ref "$UNI_KIND" "$raw")"
      check_github_tag_exists "$ref"
    fi

    res="$(resolve_standard_strategy "stable" "$ref")"
    [[ -n "$res" ]] && add_to_queue "stable" "$res"

    if dxvk_binsem_kind_supported "$UNI_KIND"; then
      local base prefix
      base="$(version_base_from_ref "$ref")"
      if dxvk_binsem_supported_base "$base"; then
        prefix="$UNI_KIND"
        [[ "$prefix" != *- ]] && prefix="${prefix}-"
        add_to_queue "stable" "${ref}|${base}|${prefix}${base}-binsem.wcp|"
      fi
    fi
  done
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

    local requested_versions=""
    if default_versions_for_kind "$UNI_KIND" >/dev/null 2>&1; then
      requested_versions="$(default_versions_for_kind "$UNI_KIND")"
    else
      requested_versions="latest"
    fi

    queue_stable_versions "$requested_versions"

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
        local requested_versions="${IN_VERSION:-}"
        if [[ -z "$requested_versions" ]] && default_versions_for_kind "$UNI_KIND" >/dev/null 2>&1; then
          requested_versions="$(default_versions_for_kind "$UNI_KIND")"
        fi

        if [[ -z "$requested_versions" ]]; then
          requested_versions="latest"
        fi

        queue_stable_versions "$requested_versions"
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
