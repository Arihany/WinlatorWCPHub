# Packing DIR
WCP_DIR_64="system32"
WCP_DIR_32="syswow64"

# JSON Target
WCP_MOUNT_64="\${system32}"
WCP_MOUNT_32="\${syswow64}"

WCP_TYPE="DXVK"
WCP_VERSION_CODE=0
#WCP_VERSION_CODE_DEFAULT=0
#WCP_VERSION_PREFIX="gplasync-arm64ec-"
WCP_VERSION_SUFFIX="-gplasync-arm64ec"

WCP_DESC="Built on the Winlator WCP Hub (Upstream: Philip Rebohle, Patch: Ph42oN)"

# --- custom version naming ---
wcp_version_name() {
  local v="$1"
  local prefix="${WCP_VERSION_PREFIX:-}"
  local suffix="${WCP_VERSION_SUFFIX:-}"

  if [[ -n "$suffix" && "$suffix" != -* ]]; then
    suffix="-$suffix"
  fi

  if [[ -n "$suffix" && "$v" == *-pre-reg ]]; then
    local base="${v%-pre-reg}"
    printf '%s\n' "${prefix}${base}${suffix}-pre-reg"
    return 0
  fi

  printf '%s\n' "${prefix}${v}${suffix}"
}
