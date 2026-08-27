set -Eeuo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/build-targets.sh"

: "${UNI_KIND:?UNI_KIND is not set}"
: "${UPSTREAM_REPO:?UPSTREAM_REPO is not set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
: "${REL_TAG_STABLE:?REL_TAG_STABLE is not set}"

IN_VERSION="${IN_VERSION:-}"
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
echo "REL_TAG     : $REL_TAG_STABLE"
echo "IN_VERSION  : ${IN_VERSION:-<presets>}"
echo "::endgroup::"

ASSET_CACHE=""
ASSET_CACHE_READY=0

get_assets_cached() {
  local __outvar="${1:-}"

  if (( ! ASSET_CACHE_READY )); then
    local out err err_file
    err_file="$TMP_DIR/gh_assets.err"
    if ! out="$(gh release view "$REL_TAG_STABLE" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name' 2>"$err_file")"; then
      err="$(<"$err_file" 2>/dev/null || true)"
      if grep -qiE "release not found|HTTP 404|status 404|Not Found" <<<"$err"; then
        echo "::notice::Release '$REL_TAG_STABLE' not found (treating as empty)." >&2
        out=""
      else
        echo "::error::Failed to fetch assets for '$REL_TAG_STABLE'." >&2
        [[ -n "$err" ]] && echo "$err" >&2
        return 1
      fi
    fi
    ASSET_CACHE="$out"
    ASSET_CACHE_READY=1
  fi

  if [[ -n "$__outvar" ]]; then
    printf -v "$__outvar" '%s' "$ASSET_CACHE"
  else
    printf '%s\n' "$ASSET_CACHE"
  fi
}

fetch_github_tags() {
  gh api "repos/$UPSTREAM_REPO/tags?per_page=100" --paginate --jq '.[].name' 2>/dev/null || true
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
  echo "::error::Failed to verify tag '$tag' (API error)" >&2
  [[ -n "$err" ]] && echo "$err" >&2
  exit 1
}

# Helper
get_tag_regex_for_kind() {
  local kind="$1"
  case "$kind" in
    fexcore|fexcore-unixlib)
      printf '%s\t%s\n' '^FEX-[0-9]+$' '^FEX-'
      ;;
    dxvk*|vkd3d*)
      printf '%s\t%s\n' '^v?[0-9]+(\.[0-9]+)*$' ''
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
  local base_url="${GPLASYNC_BASE_URL:-https://gitlab.com/Ph42oN/dxvk-gplasync/-/raw/v${base}-${rev}/patches}"
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
  local input_arg="$1"
  local strategy="$UNI_KIND"
  local ref ver_name filename short=""

  case "$strategy" in
    fexcore|fexcore-unixlib)
      [[ -z "$input_arg" ]] && return 1
      ref="$input_arg"
      ver_name="${input_arg#FEX-}"
      if fexcore_kind_has_unixlib "$strategy"; then
        filename="FEXCore-unixlib-${ver_name}.wcp"
      else
        filename="FEXCore-${ver_name}.wcp"
      fi
      ;;

    dxvk*|vkd3d*)
      [[ -z "$input_arg" ]] && return 1

      ref="$input_arg"
      local base
      base="$(version_base_from_ref "$ref")"

      local prefix
      prefix="$(artifact_prefix_for_kind "$strategy")"
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

resolve_gplasync_strategy() {
  local prefix="$UNI_KIND"
  [[ "$prefix" != dxvk-gplasync* ]] && return 1

  local assets=""
  get_assets_cached assets

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
      add_to_queue "$pre_reg_entry"
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
      add_to_queue "v${base}-${rev}|${base}-${rev}|${prefix}-${base}-${rev}.wcp|"
    fi

  done < "$targets_file"
}

QUEUE=""
HAS_WORK=false

add_to_queue() {
  local raw_data="$1"
  IFS='|' read -r ref ver_name filename short <<< "$raw_data"

  local assets=""
  get_assets_cached assets

  if [[ -n "$assets" ]] && grep -Fxq "$filename" <<< "$assets"; then
    echo "  -> Skipped (Asset Exists: $filename)" >&2
    return
  fi

  if grep -Fq "|$filename|" <<< "$QUEUE"; then
    echo "  -> Skipped (Already queued: $filename)" >&2
    return
  fi

  echo "  -> Queued: $filename" >&2
  QUEUE+="${UNI_KIND}|${ref}|${ver_name}|${REL_TAG_STABLE}|${filename}|${short}"$'\n'
  HAS_WORK=true
}

queue_stable_versions() {
  local csv="$1"
  local raw ref res proton_entry proton_rc

  IFS=',' read -ra _stable_reqs <<< "$csv"
  for raw in "${_stable_reqs[@]}"; do
    raw="$(echo "$raw" | xargs)"
    [[ -z "$raw" ]] && continue

    if pre_reg_entry="$(pre_reg_queue_entry "$UNI_KIND" "$raw" 2>/dev/null)"; then
      add_to_queue "$pre_reg_entry"
      continue
    elif is_dxvk_proton_token "$raw" && [[ "$UNI_KIND" == dxvk || "$UNI_KIND" == dxvk-arm64ec ]]; then
      # Resolve Valve's gitlink.. command substitution would lose the result.
      # add_to_queue then detects changes by the short SHA in the filename
      dxvk_proton_resolve || exit 1
      dxvk_proton_selfcheck || exit 1
      # rc 2 must fail the guard -- a skip is reported as "nothing to build".
      proton_rc=0
      proton_entry="$(proton_queue_entry "$UNI_KIND" "$raw")" || proton_rc=$?
      (( proton_rc == 0 )) || exit 1
      add_to_queue "$proton_entry"
      continue
    elif [[ "$UNI_KIND" == dxvk || "$UNI_KIND" == dxvk-arm64ec ]] \
         && is_stale_dxvk_proton_token "$raw"; then
      echo "::error::DXVK Proton token '$raw' pins a specific commit, which this line no longer supports." >&2
      echo "::error::Use 'proton', or 'proton<major>' to assert the major." >&2
      exit 1
    elif is_latest_token "$raw"; then
      ref="$(get_latest_stable)"
      [[ -n "$ref" ]] || { echo "::warning::No stable tag found for $UNI_KIND"; continue; }
    else
      ref="$(normalize_github_version_ref "$UNI_KIND" "$raw")"
      check_github_tag_exists "$ref"
    fi

    if [[ "$UNI_KIND" == "dxvk-arm64ec" ]] && dxvk_version_is_x86_x64_only "$(version_base_from_ref "$ref")"; then
      echo "::warning::DXVK $(version_base_from_ref "$ref") is an x86/x64-only target in WCPHub; skipping ARM64EC." >&2
      continue
    fi

    if [[ "$UNI_KIND" == dxvk-sarek-dyasync* ]]; then
      local sarek_base
      sarek_base="$(version_base_from_ref "$ref")"
      if ! sarek_version_supported "$sarek_base"; then
        echo "::warning::DXVK-Sarek $sarek_base is below the supported baseline $SAREK_MIN_VERSION; skipping." >&2
        continue
      fi
    fi

    if [[ "$UNI_KIND" == fexcore* ]] && ! fexcore_version_supported "$ref"; then
      echo "::warning::FEX ${ref#FEX-} is below the supported baseline $FEXCORE_MIN_VERSION; skipping." >&2
      continue
    fi

    res="$(resolve_standard_strategy "$ref")"
    [[ -n "$res" ]] && add_to_queue "$res"
  done
}

dispatch_logic() {
  if [[ "$UNI_KIND" == dxvk-gplasync* ]]; then
    echo "::group::Strategy: GPLAsync ($UNI_KIND)"
    resolve_gplasync_strategy
    echo "::endgroup::"
    return
  fi

  echo "::group::Strategy: Standard ($UNI_KIND / ${IN_VERSION:-presets})"

  local requested_versions="${IN_VERSION:-}"
  if [[ -z "$requested_versions" ]] && default_versions_for_kind "$UNI_KIND" >/dev/null 2>&1; then
    requested_versions="$(default_versions_for_kind "$UNI_KIND")"
  fi
  [[ -n "$requested_versions" ]] || requested_versions="latest"

  queue_stable_versions "$requested_versions"
  echo "::endgroup::"
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
