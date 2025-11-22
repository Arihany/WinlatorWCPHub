set -Eeuo pipefail

shopt -s nullglob

# Args
SRC_64="${1:?SRC_64 (64-bit / ARM64EC dir) is required}"
SRC_32="${2:?SRC_32 (32-bit dir) is required}"
WCP_DIR="${3:?WCP_DIR is required}"
VERSION_NAME="${4:?versionName is required}"   # base
OUT_PATH="${5:?output_wcp_path is required}"

PROFILE_SH="${PROFILE_SH:?PROFILE_SH not set (profile .sh required)}"

# 0. Profile load
# shellcheck source=/dev/null
. "$PROFILE_SH"

: "${WCP_TYPE:?WCP_TYPE not set in profile}"
: "${WCP_DESC:?WCP_DESC not set in profile}"
WCP_VERSION_CODE="${WCP_VERSION_CODE:-${WCP_VERSION_CODE_DEFAULT:-0}}"

WCP_VERSION_PREFIX="${WCP_VERSION_PREFIX:-}"
WCP_VERSION_SUFFIX="${WCP_VERSION_SUFFIX:-}"

if declare -F wcp_version_name >/dev/null 2>&1; then
  EFFECTIVE_VER="$(wcp_version_name "$VERSION_NAME")"
else
  EFFECTIVE_VER="${WCP_VERSION_PREFIX}${VERSION_NAME}${WCP_VERSION_SUFFIX}"
fi

# 1. Layout / mount
WCP_DIR_64="${WCP_DIR_64:-system32}"
WCP_DIR_32="${WCP_DIR_32:-syswow64}"

WCP_MOUNT_64="${WCP_MOUNT_64:-\${system32}}"
WCP_MOUNT_32="${WCP_MOUNT_32:-\${syswow64}}"

echo "WCP pack (graphics):"
echo "  SRC_64    : $SRC_64"
echo "  SRC_32    : $SRC_32"
echo "  WCP       : $WCP_DIR"
echo "  OUT       : $OUT_PATH"
echo "  TYPE      : $WCP_TYPE"
echo "  VER(base) : $VERSION_NAME"
echo "  VER(final): $EFFECTIVE_VER"

# 2. Sanity check
[[ -d "$SRC_64" ]] || { echo "::error::SRC_64 not found: $SRC_64"; exit 1; }
[[ -d "$SRC_32" ]] || { echo "::error::SRC_32 not found: $SRC_32"; exit 1; }

# 3. WCP reset
rm -rf "$WCP_DIR"
mkdir -p "$WCP_DIR/$WCP_DIR_64" "$WCP_DIR/$WCP_DIR_32"

# 4. /bin
[[ -d "$SRC_64/bin" ]] && SRC_64="$SRC_64/bin"
[[ -d "$SRC_32/bin" ]] && SRC_32="$SRC_32/bin"

# 5. Copy DLL
echo "Copying 64-bit / ARM64EC DLLs into $WCP_DIR/$WCP_DIR_64..."
cp -v "$SRC_64"/*.dll "$WCP_DIR/$WCP_DIR_64/" 2>/dev/null || true

echo "Copying 32-bit DLLs into $WCP_DIR/$WCP_DIR_32..."
cp -v "$SRC_32"/*.dll "$WCP_DIR/$WCP_DIR_32/" 2>/dev/null || true

# 6. Verification
count_64=( "$WCP_DIR/$WCP_DIR_64"/*.dll )
count_32=( "$WCP_DIR/$WCP_DIR_32"/*.dll )

if [[ ${#count_64[@]} -eq 0 ]]; then
  echo "::error::No DLLs found in $WCP_DIR/$WCP_DIR_64 (64-bit/ARM64EC source was empty?)"
  exit 1
fi

if [[ ${#count_32[@]} -eq 0 ]]; then
  echo "::error::No DLLs found in $WCP_DIR/$WCP_DIR_32 (32-bit source was empty?)"
  exit 1
fi

# 7. Strip
echo "Stripping symbols (llvm-strip --strip-all)..."
find "$WCP_DIR" -name '*.dll' -print0 | xargs -0 -r llvm-strip --strip-all

# 8. profile.json
PROFILE_JSON="$WCP_DIR/profile.json"

generate_file_list() {
  local dir="$1"
  find "$dir" -maxdepth 1 -name "*.dll" -printf '%P\n' | \
    jq -R -s 'split("\n") | map(select(length > 0))'
}

jq -n \
  --arg TYPE   "$WCP_TYPE" \
  --arg VER    "$EFFECTIVE_VER" \
  --argjson VC "$WCP_VERSION_CODE" \
  --arg DESC   "$WCP_DESC" \
  --arg DIR64  "$WCP_DIR_64" \
  --arg DIR32  "$WCP_DIR_32" \
  --arg M64    "$WCP_MOUNT_64" \
  --arg M32    "$WCP_MOUNT_32" \
  --argjson X64 "$(generate_file_list "$WCP_DIR/$WCP_DIR_64")" \
  --argjson X32 "$(generate_file_list "$WCP_DIR/$WCP_DIR_32")" \
  '
  {
    type: $TYPE,
    versionName: $VER,
    versionCode: $VC,
    description: $DESC,
    files: (
      ($X64 | map({source: ($DIR64 + "/" + .), target: ($M64 + "/" + .)})) +
      ($X32 | map({source: ($DIR32 + "/" + .), target: ($M32 + "/" + .)}))
    )
  }
  ' > "$PROFILE_JSON"

echo "Generated profile.json at $PROFILE_JSON"

# 9. Packing
mkdir -p "$(dirname "$OUT_PATH")"

tar --zstd -C "$WCP_DIR" --format=gnu --owner=0 --group=0 --sort=name \
  -cf "$OUT_PATH" profile.json "$WCP_DIR_64" "$WCP_DIR_32"

echo "Packed WCP: $OUT_PATH"
