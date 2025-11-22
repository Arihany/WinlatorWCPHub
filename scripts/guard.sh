#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# 0. Environment & Configuration
# -----------------------------------------------------------------------------
UNI_KIND="${UNI_KIND:?UNI_KIND is not set}"
UPSTREAM_REPO="${UPSTREAM_REPO:?UPSTREAM_REPO is not set}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

REL_TAG_STABLE="${REL_TAG_STABLE:?REL_TAG_STABLE is not set}"
REL_TAG_NIGHTLY="${REL_TAG_NIGHTLY:-}"

IN_CHANNEL="${IN_CHANNEL:-stable}"
IN_VERSION="${IN_VERSION:-}"
IS_SCHEDULE="${IS_SCHEDULE:-false}"

echo "::group::Configuration"
echo "UNI_KIND   : $UNI_KIND"
echo "IN_CHANNEL : $IN_CHANNEL"
echo "IS_SCHEDULE: $IS_SCHEDULE"
echo "::endgroup::"

# -----------------------------------------------------------------------------
# 1. API Helpers (Optimized)
# -----------------------------------------------------------------------------

# 최신 태그 조회 (Regex 필터링 + 버전 정렬)
fetch_latest_tag() {
  local regex="$1" sub_pat="$2"
  
  # DXVK 스타일 (sort -V)
  if [[ "$sub_pat" == "sort-v" ]]; then
    gh api "repos/$UPSTREAM_REPO/tags?per_page=100" --paginate --jq '.[].name' \
      | grep -E "$regex" | sort -V | tail -n 1
  else
    # Box64/FEX 스타일 (Semantic Versioning)
    gh api "repos/$UPSTREAM_REPO/tags?per_page=100" --paginate --jq \
      "[.[] | .name | select(test(\"$regex\"))]
       | sort_by(sub(\"$sub_pat\";\"\") | split(\".\") | map(tonumber))
       | last"
  fi
}

get_head_sha() {
  gh api "repos/$UPSTREAM_REPO/commits/HEAD" --jq .sha
}

get_datecode() {
  date -u +%y%m%d
}

# 특정 태그 존재 여부 확인 (O(1) Cost)
check_tag_exists() {
  local tag="$1"
  # 404 if not found, so we suppress error output and check exit code
  gh api "repos/$UPSTREAM_REPO/git/ref/tags/$tag" --silent >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# 2. Asset Cache (Lazy Loading)
# -----------------------------------------------------------------------------
declare -A ASSET_CACHE

get_assets_cached() {
  local channel="$1" tag_var="REL_TAG_${channel^^}"
  local release_tag="${!tag_var}"

  if [[ -z "${ASSET_CACHE[$channel]:-}" ]]; then
    echo "Fetching assets for $release_tag..." >&2
    ASSET_CACHE[$channel]="$(gh release view "$release_tag" --repo "$GITHUB_REPOSITORY" \
      --json assets --jq '.assets[].name' 2>/dev/null || true)"
  fi
  echo "${ASSET_CACHE[$channel]}"
}

# -----------------------------------------------------------------------------
# 3. Strategy Implementations
# -----------------------------------------------------------------------------

# Returns: "REF|VER_NAME|VER_CODE|FILENAME|SHORT"
resolve_strategy() {
  local mode="$1" # stable | nightly
  local arg="$2"  # tag (for stable) or empty (for nightly)
  local strategy="$3"

  local ref ver_name ver_code filename short="" 
  local dc; dc="$(get_datecode)"

  case "$strategy" in
    box64-bionic|wowbox64)
      local prefix="$strategy"
      if [[ "$mode" == "stable" ]]; then
        ref="$arg"
        ver_name="${arg#v}"
        ver_code="0"
        filename="${prefix}-${ver_name}.wcp"
      else
        ref="$(get_head_sha)"
        short="${ref:0:7}"
        local latest; latest="$(fetch_latest_tag "^v[0-9]+\\." "^v")"
        [[ -z "$latest" || "$latest" == "null" ]] && return 1

        # 최신 태그 기반 개발 버전 추론 (마지막 숫자 +1)
        local dev_ver
        dev_ver="$(echo "${latest#v}" | awk -F. \
          '$NF ~ /^[0-9]+$/ { $NF++; OFS="."; print $0; exit } { print $0"-dev" }')"

        ver_name="$dev_ver"
        ver_code="$dc"
        filename="${prefix}-${dev_ver}-${dc}-${short}.wcp"
      fi
      ;;

    fexcore)
      if [[ "$mode" == "stable" ]]; then
        ref="$arg"
        ver_name="${arg#FEX-}"
        ver_code="0"
        filename="FEXCore-${ver_name}.wcp"
      else
        ref="$(get_head_sha)"
        short="${ref:0:7}"
        local latest; latest="$(fetch_latest_tag "^FEX-[0-9]+" "^FEX-")"
        [[ -z "$latest" || "$latest" == "null" ]] && return 1
        
        ver_name="${latest#FEX-}"
        ver_code="$dc"
        filename="FEXCore-${ver_name}-${dc}-${short}.wcp"
      fi
      ;;

    dxvk*|vkd3d*)
      # DXVK/VKD3D Style (No Nightly, sort -V)
      if [[ "$mode" == "nightly" ]]; then
        echo "::error::Nightly not supported for $strategy" >&2
        return 1
      fi

      ref="$arg"
      # 숫자 외의 접두사 제거 (예: v1.0 -> 1.0, dxvk-1.0 -> 1.0)
      local base
      if [[ "$arg" =~ ^v[0-9] ]]; then
        base="${arg#v}"
      else
        base="$(sed -E 's/^[^0-9]+//' <<< "$arg")"
        [[ -z "$base" ]] && base="$arg"
      fi

      # 파일명 접두사 처리 (dxvk -> dxvk-, dxvk-async -> dxvk-async-)
      local file_prefix="$strategy"
      [[ "$file_prefix" != *- ]] && file_prefix="${file_prefix}-"

      ver_name="$base"
      ver_code="0"
      filename="${file_prefix}${base}.wcp"
      ;;
    *)
      echo "::error::Unknown strategy: $strategy" >&2
      return 1
      ;;
  esac

  echo "${ref}|${ver_name}|${ver_code}|${filename}|${short}"
}

get_strategy_latest_tag() {
  case "$1" in
    box64*|wowbox64) fetch_latest_tag "^v[0-9]+\\." "^v" ;;
    fexcore)         fetch_latest_tag "^FEX-[0-9]+" "^FEX-" ;;
    dxvk*|vkd3d*)    fetch_latest_tag "^(v)?[0-9]" "sort-v" ;; # Unified regex for dxvk/vkd3d
  esac
}

# -----------------------------------------------------------------------------
# 4. Queue & Execution Logic
# -----------------------------------------------------------------------------
QUEUE=""
HAS_WORK=false

add_to_queue() {
  local channel="$1" raw_data="$2"
  
  IFS='|' read -r ref ver_name ver_code filename short <<< "$raw_data"
  
  local rel_tag rel_title
  if [[ "$channel" == "stable" ]]; then
    rel_tag="$REL_TAG_STABLE"
    rel_title="$REL_TAG_STABLE"
  else
    rel_tag="$REL_TAG_NIGHTLY"
    rel_title="$REL_TAG_NIGHTLY"
  fi

  # Check duplication
  local assets; assets="$(get_assets_cached "$channel")"
  
  # 1. Filename match
  if [[ -n "$assets" ]] && grep -Fxq "$filename" <<< "$assets"; then
    echo "  -> Skipped (Exists: $filename)"
    return
  fi

  # 2. Commit hash match (Nightly only)
  # 파일명 끝부분의 -sha.wcp 패턴을 검사하여 날짜가 달라도 커밋이 같으면 스킵
  if [[ "$channel" == "nightly" && -n "$short" && -n "$assets" ]]; then
    if grep -Eq "\-${short}\.wcp$" <<< "$assets"; then
      echo "  -> Skipped (Commit $short already built)"
      return
    fi
  fi

  echo "  -> Queued ($filename)"
  # Format: kind channel ref ver_name ver_code rel_tag rel_title filename short
  QUEUE+="${UNI_KIND} ${channel} ${ref} ${ver_name} ${ver_code} ${rel_tag} ${rel_title} ${filename} ${short}"$'\n'
  HAS_WORK=true
}

process_target() {
  local channel="$1"
  local input_tag="$2" # Empty for nightly
  
  echo "::group::Processing $channel ${input_tag:+($input_tag)}"
  
  local result
  result="$(resolve_strategy "$channel" "$input_tag" "$UNI_KIND")"
  
  if [[ $? -ne 0 || -z "$result" ]]; then
    echo "::error::Failed to resolve strategy for $UNI_KIND ($channel)"
    echo "::endgroup::"
    exit 1
  fi

  add_to_queue "$channel" "$result"
  echo "::endgroup::"
}

# -----------------------------------------------------------------------------
# 5. Main Execution
# -----------------------------------------------------------------------------

# Determine Capabilities
HAS_NIGHTLY=false
case "$UNI_KIND" in
  box64-bionic|wowbox64|fexcore)
    HAS_NIGHTLY=true
    ;;
  dxvk*|vkd3d*)
    HAS_NIGHTLY=false
    ;;
  *)
    echo "::error::Unknown UNI_KIND: $UNI_KIND" >&2
    exit 1
    ;;
esac

# Nightly 지원하는 KIND인데 REL_TAG_NIGHTLY 빠진 경우 즉시 에러
if [[ "$HAS_NIGHTLY" == "true" && -z "$REL_TAG_NIGHTLY" ]]; then
  echo "::error::REL_TAG_NIGHTLY is not set for UNI_KIND=$UNI_KIND" >&2
  exit 1
fi

# Schedule Mode (Auto)
if [[ "$IS_SCHEDULE" == "true" ]]; then
  LATEST="$(get_strategy_latest_tag "$UNI_KIND")"
  [[ -n "$LATEST" && "$LATEST" != "null" ]] || { echo "::error::No latest tag found"; exit 1; }
  
  process_target "stable" "$LATEST"
  
  if [[ "$HAS_NIGHTLY" == "true" ]]; then
    process_target "nightly" ""
  fi

# Manual Mode
else
  case "$IN_CHANNEL" in
    stable)
      if [[ -z "$IN_VERSION" ]]; then
        # 입력 버전 없으면 최신 버전 1개 처리
        LATEST="$(get_strategy_latest_tag "$UNI_KIND")"
        [[ -n "$LATEST" && "$LATEST" != "null" ]] && process_target "stable" "$LATEST"
      else
        # 쉼표로 구분된 버전 목록 처리
        IFS=',' read -ra vers <<< "$IN_VERSION"
        for raw in "${vers[@]}"; do
          # Trim whitespace
          raw="${raw#"${raw%%[![:space:]]*}"}"
          raw="${raw%"${raw##*[![:space:]]}"}"
          [[ -z "$raw" ]] && continue

          if check_tag_exists "$raw"; then
             process_target "stable" "$raw"
          else
             echo "::error::Tag '$raw' not found upstream."
             exit 1
          fi
        done
      fi
      ;;
    nightly)
      [[ "$HAS_NIGHTLY" != "true" ]] && { echo "::error::Nightly not supported"; exit 1; }
      process_target "nightly" ""
      ;;
    *)
      echo "::error::Invalid IN_CHANNEL: $IN_CHANNEL"; exit 1 ;;
  esac
fi

# -----------------------------------------------------------------------------
# 6. Output Generation
# -----------------------------------------------------------------------------
if $HAS_WORK; then
  echo "missing=true" >> "$GITHUB_OUTPUT"
  # Multiline string safe handling (Here-doc)
  {
    echo "list<<EOF"
    printf '%s' "$QUEUE"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
  echo "Build queue created."
else
  echo "missing=false" >> "$GITHUB_OUTPUT"
  echo "list=" >> "$GITHUB_OUTPUT"
  echo "Nothing to build."
fi
