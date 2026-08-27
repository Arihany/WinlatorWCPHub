DXVK_PRE_REG_REF="4c0cbbef6abe2b1a9e8c358be0caf207c907a5d2"
DXVK_PRE_REG_SHORT="4c0cbbe"

# Follows the dxvk submodule gitlink of Proton default branch
DXVK_PROTON_REPO="${DXVK_PROTON_REPO:-ValveSoftware/Proton}"
DXVK_PROTON_SUBMODULE="${DXVK_PROTON_SUBMODULE:-dxvk}"
DXVK_PROTON_UPSTREAM_REPO="${DXVK_PROTON_UPSTREAM_REPO:-doitsujin/dxvk}"
DXVK_PROTON_TOKEN="proton"

# Filled in by dxvk_proton_resolve.
DXVK_PROTON_BRANCH=""
DXVK_PROTON_MAJOR=""
DXVK_PROTON_REF=""
DXVK_PROTON_SHORT=""
DXVK_PROTON_BASE=""
DXVK_PROTON_VERSION=""
_DXVK_PROTON_RESOLVED=0

_dxvk_proton_curl() {
  local auth=()

  if [[ -n "${GH_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer ${GH_TOKEN}")
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  curl -fsSL -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "${auth[@]}" "${1:?url is required}"
}

# Once per process. Returns 1 on failure
dxvk_proton_resolve() {
  (( _DXVK_PROTON_RESOLVED )) && return 0

  local branch major sha base quote
  quote=$'\047'

  branch="$(_dxvk_proton_curl "https://api.github.com/repos/$DXVK_PROTON_REPO" \
            | jq -r '.default_branch // empty')" || true
  [[ -n "$branch" ]] || {
    echo "::error::Could not resolve the default branch of $DXVK_PROTON_REPO" >&2
    return 1
  }

  if [[ "$branch" =~ ^proton_([0-9]+) ]]; then
    major="${BASH_REMATCH[1]}"
  else
    echo "::error::Unexpected Proton default branch '$branch'; cannot derive a major" >&2
    return 1
  fi

  sha="$(_dxvk_proton_curl \
          "https://api.github.com/repos/$DXVK_PROTON_REPO/contents/$DXVK_PROTON_SUBMODULE?ref=$branch" \
          | jq -r 'select(.type == "submodule") | .sha // empty')" || true
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || {
    echo "::error::Could not read the '$DXVK_PROTON_SUBMODULE' gitlink on $DXVK_PROTON_REPO@$branch" >&2
    return 1
  }

  base="$(curl -fsSL "https://raw.githubusercontent.com/$DXVK_PROTON_UPSTREAM_REPO/$sha/meson.build" \
          | grep -oE "version *: *${quote}[0-9][^${quote}]*${quote}" \
          | head -n1 | tr -d "$quote" | awk '{print $NF}')" || true
  [[ -n "$base" ]] || {
    echo "::error::Could not read the dxvk version from $DXVK_PROTON_UPSTREAM_REPO@$sha" >&2
    return 1
  }

  DXVK_PROTON_BRANCH="$branch"
  DXVK_PROTON_MAJOR="$major"
  DXVK_PROTON_REF="$sha"
  DXVK_PROTON_SHORT="${sha:0:7}"
  DXVK_PROTON_BASE="$base"
  DXVK_PROTON_VERSION="${base}-proton${major}-${DXVK_PROTON_SHORT}"
  _DXVK_PROTON_RESOLVED=1

  echo "::notice::Proton line: $DXVK_PROTON_REPO@$branch -> dxvk $base ($DXVK_PROTON_SHORT)" >&2
  return 0
}

# DXVK 1.x splits by compiler, not by age
DXVK_LEGACY_VERSIONS=("1.5.5" "1.7.2" "1.7.3")
# Build clean on clang
DXVK_MODERN_X86_ONLY_VERSIONS=("1.9.4" "1.10.3")
DXVK_X86_X64_ONLY_VERSIONS=("${DXVK_LEGACY_VERSIONS[@]}" "${DXVK_MODERN_X86_ONLY_VERSIONS[@]}")
# One rung per minor line, at its last patch release.
DXVK_STABLE_VERSIONS=("2.4.1-pre-reg" "2.4.1" "2.6.2" "2.7.1" "3.0.2")
# gplasync rungs are the dxvk base its own tags carry
GPLASYNC_STABLE_VERSIONS=("2.4.1-1-pre-reg" "2.4.1" "2.6.2" "2.7.1" "3.0")
VKD3D_PROTON_STABLE_VERSIONS=("2.14.1" "3.0.1")
SAREK_MIN_VERSION="1.13.0"
SAREK_STABLE_VERSIONS=("$SAREK_MIN_VERSION")

# Below this there is no unixLib
FEXCORE_MIN_VERSION="2607"
FEXCORE_STABLE_VERSIONS=("2607")

join_csv() {
  local IFS=","
  printf '%s' "$*"
}

default_versions_for_kind() {
  local kind="$1"

  case "$kind" in
    dxvk)
      join_csv "${DXVK_MODERN_X86_ONLY_VERSIONS[@]}" "${DXVK_STABLE_VERSIONS[@]}" \
        "$DXVK_PROTON_TOKEN" "latest"
      ;;
    dxvk-legacy)
      # No "latest"
      join_csv "${DXVK_LEGACY_VERSIONS[@]}"
      ;;
    dxvk-arm64ec)
      join_csv "${DXVK_STABLE_VERSIONS[@]}" "$DXVK_PROTON_TOKEN" "latest"
      ;;
    dxvk-gplasync|dxvk-gplasync-arm64ec)
      join_csv "${GPLASYNC_STABLE_VERSIONS[@]}" "latest"
      ;;
    vkd3d-proton*)
      join_csv "${VKD3D_PROTON_STABLE_VERSIONS[@]}" "latest"
      ;;
    dxvk-sarek-dyasync*)
      join_csv "${SAREK_STABLE_VERSIONS[@]}" "latest"
      ;;
    fexcore|fexcore-unixlib)
      join_csv "${FEXCORE_STABLE_VERSIONS[@]}" "latest"
      ;;
    *)
      return 1
      ;;
  esac
}

# dxvk-legacy only selects a compiler
artifact_prefix_for_kind() {
  case "$1" in
    dxvk-legacy) printf 'dxvk\n' ;;
    *)           printf '%s\n' "$1" ;;
  esac
}

dxvk_version_is_legacy() {
  local base="${1#v}"
  local version

  for version in "${DXVK_LEGACY_VERSIONS[@]}"; do
    [[ "$base" == "$version" ]] && return 0
  done
  return 1
}

dxvk_version_is_x86_x64_only() {
  local base="${1#v}"
  local version

  for version in "${DXVK_X86_X64_ONLY_VERSIONS[@]}"; do
    [[ "$base" == "$version" ]] && return 0
  done
  return 1
}

fexcore_version_supported() {
  local base="${1#FEX-}"

  [[ "$base" =~ ^[0-9]+$ ]] || return 1
  (( base >= FEXCORE_MIN_VERSION ))
}

# unixlib is optional
fexcore_kind_has_unixlib() {
  [[ "$1" == "fexcore-unixlib" ]]
}

is_latest_token() {
  [[ "$1" == "latest" || "$1" == "latest-stable" || "$1" == "latest stable" ]]
}

is_dxvk_prereg_token() {
  [[ "$1" == "2.4.1-pre-reg" || "$1" == "v2.4.1-pre-reg" ]]
}

is_gplasync_prereg_token() {
  [[ "$1" == "2.4.1-1-pre-reg" || "$1" == "v2.4.1-1-pre-reg" ]]
}

is_dxvk_proton_token() {
  local token="${1,,}"

  [[ "$token" == "proton" || "$token" =~ ^proton[0-9]+$ ]]
}

dxvk_proton_requested_major() {
  local token="${1,,}"

  [[ "$token" =~ ^proton([0-9]+)$ ]] && printf '%s\n' "${BASH_REMATCH[1]}"
  return 0
}

# Proton-shaped but nooooo
is_stale_dxvk_proton_token() {
  local token="${1,,}"

  is_dxvk_proton_token "$token" && return 1
  [[ "$token" =~ ^proton([0-9]+)?(-.*)?$ ]] || [[ "$token" =~ ^[0-9][^-]*-proton[0-9]+ ]]
}

# Sanity of the resolved fields
dxvk_proton_selfcheck() {
  local err=""

  if [[ ! "$DXVK_PROTON_REF" =~ ^[0-9a-f]{40}$ ]]; then
    err="DXVK_PROTON_REF is not a full 40-hex commit id: '$DXVK_PROTON_REF'"
  elif [[ "$DXVK_PROTON_REF" != "$DXVK_PROTON_SHORT"* ]]; then
    err="DXVK_PROTON_SHORT='$DXVK_PROTON_SHORT' is not a prefix of DXVK_PROTON_REF"
  elif [[ ! "$DXVK_PROTON_MAJOR" =~ ^[0-9]+$ ]]; then
    err="DXVK_PROTON_MAJOR is not numeric: '$DXVK_PROTON_MAJOR'"
  elif [[ ! "$DXVK_PROTON_BASE" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    err="DXVK_PROTON_BASE is not a version string: '$DXVK_PROTON_BASE'"
  fi

  [[ -z "$err" ]] && return 0

  echo "::error::Resolved DXVK Proton line is inconsistent: $err" >&2
  echo "::error::Source: $DXVK_PROTON_REPO@${DXVK_PROTON_BRANCH:-<unresolved>} submodule '$DXVK_PROTON_SUBMODULE'" >&2
  return 1
}

pre_reg_queue_entry() {
  local kind="$1"
  local raw="$2"

  case "$kind" in
    dxvk|dxvk-arm64ec)
      is_dxvk_prereg_token "$raw" || return 1
      printf '%s|2.4.1-pre-reg|%s-2.4.1-pre-reg.wcp|%s\n' \
        "$DXVK_PRE_REG_REF" "$kind" "$DXVK_PRE_REG_SHORT"
      ;;
    dxvk-gplasync|dxvk-gplasync-arm64ec)
      is_gplasync_prereg_token "$raw" || return 1
      printf '%s|2.4.1-1-pre-reg|%s-2.4.1-1-pre-reg.wcp|%s\n' \
        "$DXVK_PRE_REG_REF" "$kind" "$DXVK_PRE_REG_SHORT"
      ;;
    *)
      return 1
      ;;
  esac
}

# 0 = entry, 1 = not a proton request, 2 = requested but unresolvable
proton_queue_entry() {
  local kind="$1"
  local raw="$2"
  local want

  case "$kind" in
    dxvk|dxvk-arm64ec) ;;
    *) return 1 ;;
  esac

  is_dxvk_proton_token "$raw" || return 1
  dxvk_proton_resolve || return 2

  want="$(dxvk_proton_requested_major "$raw")"
  if [[ -n "$want" && "$want" != "$DXVK_PROTON_MAJOR" ]]; then
    echo "::error::Requested proton${want}, but $DXVK_PROTON_REPO now defaults to $DXVK_PROTON_BRANCH (proton${DXVK_PROTON_MAJOR}). Use 'proton' to follow the current line." >&2
    return 2
  fi

  printf '%s|%s|%s-%s.wcp|%s\n' \
    "$DXVK_PROTON_REF" "$DXVK_PROTON_VERSION" \
    "$(artifact_prefix_for_kind "$kind")" "$DXVK_PROTON_VERSION" "$DXVK_PROTON_SHORT"
}

normalize_github_version_ref() {
  local kind="$1"
  local raw="$2"

  case "$kind" in
    dxvk|dxvk-legacy|dxvk-arm64ec|dxvk-sarek-dyasync*|vkd3d-proton*)
      if [[ "$raw" =~ ^[0-9] ]]; then
        printf 'v%s\n' "$raw"
      else
        printf '%s\n' "$raw"
      fi
      ;;
    fexcore|fexcore-unixlib)
      if [[ "$raw" =~ ^[0-9] ]]; then
        printf 'FEX-%s\n' "$raw"
      else
        printf '%s\n' "$raw"
      fi
      ;;
    *)
      printf '%s\n' "$raw"
      ;;
  esac
}

version_base_from_ref() {
  local ref="$1"
  local base

  if [[ "$ref" =~ ^v[0-9] ]]; then
    base="${ref#v}"
  else
    base="$(sed -E 's/^[^0-9]+//' <<<"$ref")"
  fi

  [[ -n "$base" ]] && printf '%s\n' "$base" || printf '%s\n' "$ref"
}

sarek_version_supported() {
  local base="${1#v}"
  local first

  [[ "$base" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  first="$(printf '%s\n%s\n' "$SAREK_MIN_VERSION" "$base" | sort -V | head -n1)"
  [[ "$first" == "$SAREK_MIN_VERSION" ]]
}
