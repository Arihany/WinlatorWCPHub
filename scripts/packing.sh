#  /\_/\
# (=•ᆽ•=)づ📦

set -Eeuo pipefail
shopt -s nullglob

# -----------------------------------------------------------------------------
# 1. Validation & Setup
# -----------------------------------------------------------------------------
required_commands=("jq" "tar" "zstd")
for cmd in "${required_commands[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "::error::Command '$cmd' is required but not installed."
    exit 1
  fi
done

# llvm-strip availability (optional)
if command -v llvm-strip &> /dev/null; then
  HAVE_LLVM_STRIP=1
  echo "llvm-strip found; symbols will be stripped during packing."
else
  HAVE_LLVM_STRIP=0
  echo "::warning::llvm-strip not found; skipping symbol stripping."
fi

# Arguments
SRC_64="${1:?SRC_64 (64-bit / ARM64EC dir) is required}"
SRC_32="${2:?SRC_32 (32-bit dir) is required}"
WCP_DIR="${3:?WCP_DIR is required}"
VERSION_NAME="${4:?versionName is required}"
OUT_PATH="${5:?output_wcp_path is required}"
PROFILE_SH="${PROFILE_SH:?PROFILE_SH env var is required}"

# Load Profile
# shellcheck source=/dev/null
source "$PROFILE_SH"

: "${WCP_TYPE:?WCP_TYPE not set in profile}"
: "${WCP_DESC:?WCP_DESC not set in profile}"

# Resolve Version Code (keep it numeric for jq --argjson)
# -> Only profile decides; workflow envs
if [[ -n "${WCP_VERSION_CODE:-}" ]]; then
  FINAL_VER_CODE="$WCP_VERSION_CODE"
else
  FINAL_VER_CODE="${WCP_VERSION_CODE_DEFAULT:-0}"
fi

# Guard against non-numeric values leaking into --argjson
if ! [[ "$FINAL_VER_CODE" =~ ^[0-9]+$ ]]; then
  echo "::warning::WCP FINAL_VER_CODE='$FINAL_VER_CODE' is not numeric, forcing 0." >&2
  FINAL_VER_CODE=0
fi

# Resolve Version Name
WCP_VERSION_PREFIX="${WCP_VERSION_PREFIX:-}"
WCP_VERSION_SUFFIX="${WCP_VERSION_SUFFIX:-}"

if declare -F wcp_version_name >/dev/null 2>&1; then
  FINAL_VER_NAME="$(wcp_version_name "$VERSION_NAME")"
else
  FINAL_VER_NAME="${WCP_VERSION_PREFIX}${VERSION_NAME}${WCP_VERSION_SUFFIX}"
fi

# WCP DEBUG: profile & version resolution =====
{
  echo "====[WCP DEBUG] PROFILE_SH='${PROFILE_SH}'"
  echo "====[WCP DEBUG] Profile vars after source:"
  declare -p WCP_SINGLE_BIN_NAME WCP_SINGLE_BIN_TARGET WCP_TYPE WCP_DESC \
            WCP_VERSION_CODE WCP_VERSION_CODE_DEFAULT \
            WCP_VERSION_PREFIX WCP_VERSION_SUFFIX 2>/dev/null || true
  echo "====[WCP DEBUG] Version inputs:"
  echo "    VERSION_NAME='${VERSION_NAME}'"
  echo "====[WCP DEBUG] Resolved:"
  echo "    FINAL_VER_NAME='${FINAL_VER_NAME}' FINAL_VER_CODE='${FINAL_VER_CODE}'"
} >&2

# -----------------------------------------------------------------------------
# 2. Helpers
# -----------------------------------------------------------------------------
pack_wcp_archive() {
  local src_dir="$1"
  local out_file="$2"
  shift 2
  local contents=("$@") # Files/Dirs to include relative to src_dir

  mkdir -p "$(dirname "$out_file")"
  
  echo "Packing WCP: $out_file"
  tar --zstd -C "$src_dir" \
    --format=gnu --owner=0 --group=0 --sort=name \
    -cf "$out_file" "${contents[@]}"
}

generate_file_list_json() {
  local dir="$1"

  find "$dir" -maxdepth 1 -name "*.dll" -printf '%P\n' | \
    jq -R -s 'split("\n") | map(select(length > 0))'
}

# -----------------------------------------------------------------------------
# 3. Mode: Single Binary
# -----------------------------------------------------------------------------
if [[ -n "${WCP_SINGLE_BIN_SOURCE:-}" ]]; then
  BIN_SRC="$WCP_SINGLE_BIN_SOURCE"
  [[ -f "$BIN_SRC" ]] || { echo "::error::WCP_SINGLE_BIN_SOURCE not found: $BIN_SRC"; exit 1; }

  if [[ -n "${WCP_SINGLE_BIN_NAME:-}" ]]; then
    BIN_NAME="$WCP_SINGLE_BIN_NAME"
  else
    BIN_NAME="$(basename "$BIN_SRC")"
  fi

  if [[ -n "${WCP_SINGLE_BIN_TARGET:-}" ]]; then
    BIN_TARGET="$WCP_SINGLE_BIN_TARGET"
  else
    BIN_TARGET="\${bindir}/${BIN_NAME}"
  fi

  echo "::group::WCP Pack (Single Binary)"
  echo "Source : $BIN_SRC"
  echo "Bin name   : $BIN_NAME"
  echo "Bin target : $BIN_TARGET"
  echo "WCP dir    : $WCP_DIR"
  echo "Ver        : $FINAL_VER_NAME ($FINAL_VER_CODE)"
  echo "====[WCP DEBUG] ENV snapshot (WCP_*/BIN_*/UNI_KIND/REL_TAG*):" >&2
  env | sort | grep -E '^(WCP_|UNI_KIND|REL_TAG|VER_|BIN_|PROFILE_SH)=' >&2 || true

  # Prepare Dir
  rm -rf "$WCP_DIR"
  mkdir -p "$WCP_DIR"

  # Copy & Strip
  cp "$BIN_SRC" "$WCP_DIR/$BIN_NAME"
  chmod +x "$WCP_DIR/$BIN_NAME"
  chmod u+w "$WCP_DIR/$BIN_NAME" 2>/dev/null || true

  if [[ "$HAVE_LLVM_STRIP" -eq 1 ]]; then
    llvm-strip --strip-unneeded "$WCP_DIR/$BIN_NAME" 2>/dev/null || true
  else
    echo "Skipping strip for $BIN_NAME (llvm-strip not available)."
  fi

  # Generate Profile
  jq -n \
    --arg TYPE "$WCP_TYPE" \
    --arg VER  "$FINAL_VER_NAME" \
    --argjson VC "$FINAL_VER_CODE" \
    --arg DESC "$WCP_DESC" \
    --arg SRC  "$BIN_NAME" \
    --arg TGT  "$BIN_TARGET" \
    '{
      type: $TYPE,
      versionName: $VER,
      versionCode: $VC,
      description: $DESC,
      files: [ { source: $SRC, target: $TGT } ]
    }' > "$WCP_DIR/profile.json"

  echo "====[WCP DEBUG] Generated profile.json (single-bin):" >&2
  cat "$WCP_DIR/profile.json" >&2

  pack_wcp_archive "$WCP_DIR" "$OUT_PATH" "profile.json" "$BIN_NAME"
  
  echo "::endgroup::"
  exit 0
fi

# ----------------------------------------------------------------------------- #
# 4. Mode: Graphics (DLLs)
# ----------------------------------------------------------------------------- #

# Resolve layout from profile:
# WCP_DIR_64: target dir for "64-bit" side (default: system32)
# WCP_DIR_32:
#     unset      - default "syswow64" (normal 32bit layout)
#     empty ("") - FEX-style merge mode: copy 32bit DLLs into WCP_DIR_64
WCP_DIR_64="${WCP_DIR_64:-system32}"

# WCP_DIR_32:
# - unset        -> "syswow64" (normal dual-layout)
# - set to ""    -> merge 32-bit into 64-bit dir (FEX etc)
if [[ -z "${WCP_DIR_32+x}" ]]; then
  # not set at all
  WCP_DIR_32="syswow64"
fi

if [[ -z "$WCP_DIR_64" ]]; then
  echo "::error::WCP_DIR_64 must not be empty (would produce invalid layout)" >&2
  exit 1
fi

# JSON targets (mount points)
if [[ -z "${WCP_MOUNT_64:-}" ]]; then
  WCP_MOUNT_64="\${system32}"
fi
if [[ -z "${WCP_MOUNT_32:-}" ]]; then
  WCP_MOUNT_32="\${syswow64}"
fi

USE_32=true
MERGE_32_INTO_64=false

# Special case: "-" means "no 32-bit side"
if [[ "$SRC_32" == "-" ]]; then
  USE_32=false
fi

if [[ -z "$WCP_DIR_32" ]]; then
  MERGE_32_INTO_64=true
fi

echo "::group::WCP Pack (Graphics DLLs)"
echo "SRC_64: $SRC_64"
echo "SRC_32: $SRC_32"
echo "Ver   : $FINAL_VER_NAME ($FINAL_VER_CODE)"
echo "Layout: 64='$WCP_DIR_64', 32='${WCP_DIR_32:-<merge-into-64>}' (merge_32_into_64=${MERGE_32_INTO_64})"

if $MERGE_32_INTO_64; then
  echo "::warning::Merge mode enabled: ALL DLLs (64+32) will be packaged under '$WCP_DIR_64' and mapped to $WCP_MOUNT_64 (FEX-style layout)." >&2
fi

# Sanity Check
[[ -d "$SRC_64" ]] || { echo "::error::SRC_64 dir not found: $SRC_64"; exit 1; }
if $USE_32; then
  [[ -d "$SRC_32" ]] || { echo "::error::SRC_32 dir not found: $SRC_32"; exit 1; }
fi

# Resolve real source paths (handle /bin subdirectory)
REAL_SRC_64="$SRC_64"
REAL_SRC_32="$SRC_32"
[[ -d "$SRC_64/bin" ]] && REAL_SRC_64="$SRC_64/bin"
[[ -d "$SRC_32/bin" ]] && REAL_SRC_32="$SRC_32/bin"

# Prepare Layout
rm -rf "$WCP_DIR"
mkdir -p "$WCP_DIR/$WCP_DIR_64"
if $USE_32 && ! $MERGE_32_INTO_64; then
  mkdir -p "$WCP_DIR/$WCP_DIR_32"
fi

# Copy Logic
find "$REAL_SRC_64" -maxdepth 1 -name "*.dll" -exec cp -v {} "$WCP_DIR/$WCP_DIR_64/" \;
if $USE_32; then
  if $MERGE_32_INTO_64; then
    # FEX merge mode: drop 32-bit DLLs into the same dir as 64-bit
    # but NEVER overwrite an existing (likely 64-bit) DLL
    while IFS= read -r -d '' f; do
      base="$(basename "$f")"
      dest="$WCP_DIR/$WCP_DIR_64/$base"
      if [[ -e "$dest" ]]; then
        echo "::error::Merge mode conflict: $dest already exists (refusing to overwrite 64-bit DLL with 32-bit)" >&2
        exit 1
      fi
      cp -v "$f" "$dest"
    done < <(find "$REAL_SRC_32" -maxdepth 1 -name "*.dll" -print0)
  else
    find "$REAL_SRC_32" -maxdepth 1 -name "*.dll" -exec cp -v {} "$WCP_DIR/$WCP_DIR_32/" \;
  fi
fi

# Verification
count_64=( "$WCP_DIR/$WCP_DIR_64"/*.dll )
if [[ ${#count_64[@]} -eq 0 ]]; then
  echo "::error::No DLLs found in 64-bit source: $REAL_SRC_64"
  exit 1
fi

if $USE_32; then
  if $MERGE_32_INTO_64; then
    # In merge mode we still want to ensure 32-bit source isn't empty
    count_32_src=( "$REAL_SRC_32"/*.dll )
    if [[ ${#count_32_src[@]} -eq 0 ]]; then
      echo "::error::No DLLs found in 32-bit source (merge mode): $REAL_SRC_32"
      exit 1
    fi
  else
    count_32=( "$WCP_DIR/$WCP_DIR_32"/*.dll )
    if [[ ${#count_32[@]} -eq 0 ]]; then
      echo "::error::No DLLs found in 32-bit source: $REAL_SRC_32"
      exit 1
    fi
  fi
fi

# Strip Symbols
echo "Stripping symbols..."
if [[ "$HAVE_LLVM_STRIP" -eq 1 ]]; then
  find "$WCP_DIR" -name '*.dll' -print0 | xargs -0 -r chmod u+w || true
  find "$WCP_DIR" -name '*.dll' -print0 | xargs -0 -r llvm-strip --strip-all || true
else
  echo "Skipping DLL strip (llvm-strip not available)."
fi

# Generate Profile
echo "Generating profile.json..."

x64_json="$(generate_file_list_json "$WCP_DIR/$WCP_DIR_64")"
if $USE_32 && ! $MERGE_32_INTO_64; then
  x32_json="$(generate_file_list_json "$WCP_DIR/$WCP_DIR_32")"
else
  x32_json="[]"
fi

jq -n \
  --arg TYPE   "$WCP_TYPE" \
  --arg VER    "$FINAL_VER_NAME" \
  --argjson VC "$FINAL_VER_CODE" \
  --arg DESC   "$WCP_DESC" \
  --arg DIR64  "$WCP_DIR_64" \
  --arg DIR32  "$WCP_DIR_32" \
  --arg M64    "$WCP_MOUNT_64" \
  --arg M32    "$WCP_MOUNT_32" \
  --argjson X64 "$x64_json" \
  --argjson X32 "$x32_json" \
  '{
    type: $TYPE,
    versionName: $VER,
    versionCode: $VC,
    description: $DESC,
    files: (
      ($X64 | map({source: ($DIR64 + "/" + .), target: ($M64 + "/" + .)})) +
      ($X32 | map({source: ($DIR32 + "/" + .), target: ($M32 + "/" + .)}))
    )
  }' > "$WCP_DIR/profile.json"

# Pack
if $USE_32 && ! $MERGE_32_INTO_64; then
  pack_wcp_archive "$WCP_DIR" "$OUT_PATH" "profile.json" "$WCP_DIR_64" "$WCP_DIR_32"
else
  pack_wcp_archive "$WCP_DIR" "$OUT_PATH" "profile.json" "$WCP_DIR_64"
fi

echo "::endgroup:: Purrrrrrrrr"
