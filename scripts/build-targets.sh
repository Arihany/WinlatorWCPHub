DXVK_PRE_REG_REF="4c0cbbef6abe2b1a9e8c358be0caf207c907a5d2"
DXVK_PRE_REG_SHORT="4c0cbbe"

DXVK_STABLE_VERSIONS=("2.4.1-pre-reg" "2.4.1" "2.5.3" "2.6.2" "2.7.1" "3.0")
GPLASYNC_STABLE_VERSIONS=("2.4.1-1-pre-reg" "2.4.1" "2.5.3" "2.6.2" "2.7.1" "3.0")
VKD3D_PROTON_STABLE_VERSIONS=("2.14.1" "3.0.1")
SAREK_STABLE_VERSIONS=("1.12.0")
FEXCORE_STABLE_VERSIONS=("2605")
DXVK_BINSEM_MIN_VERSION="2.7.1"

join_csv() {
  local IFS=","
  printf '%s' "$*"
}

default_versions_for_kind() {
  local kind="$1"

  case "$kind" in
    dxvk|dxvk-arm64ec)
      join_csv "${DXVK_STABLE_VERSIONS[@]}" "latest"
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
    fexcore)
      join_csv "${FEXCORE_STABLE_VERSIONS[@]}" "latest"
      ;;
    *)
      return 1
      ;;
  esac
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

normalize_github_version_ref() {
  local kind="$1"
  local raw="$2"

  case "$kind" in
    dxvk|dxvk-arm64ec|dxvk-sarek-dyasync*|vkd3d-proton*)
      if [[ "$raw" =~ ^[0-9] ]]; then
        printf 'v%s\n' "$raw"
      else
        printf '%s\n' "$raw"
      fi
      ;;
    fexcore)
      # FEX tags look like FEX-2605; accept bare "2605" too.
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

dxvk_binsem_supported_base() {
  local base="${1#v}"
  local first

  [[ "$base" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  first="$(printf '%s\n%s\n' "$DXVK_BINSEM_MIN_VERSION" "$base" | sort -V | head -n1 || true)"
  [[ "$first" == "$DXVK_BINSEM_MIN_VERSION" ]]
}

dxvk_binsem_kind_supported() {
  case "$1" in
    dxvk|dxvk-arm64ec|dxvk-gplasync|dxvk-gplasync-arm64ec)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
