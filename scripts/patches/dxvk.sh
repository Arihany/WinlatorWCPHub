set -Eeuo pipefail

SRC_DIR="${1:-.}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-/opt/llvm-mingw}"

cd "$SRC_DIR"

echo "== DXVK compatibility patches =="

# 1. Toolchain inspection
HAS_DEVINFO=false
if compgen -G "$TOOLCHAIN_DIR"/*-w64-mingw32/include/d3d9types.h > /dev/null; then
  if grep -q "_D3DDEVINFO_RESOURCEMANAGER" "$TOOLCHAIN_DIR"/*-w64-mingw32/include/d3d9types.h; then
    HAS_DEVINFO=true
    echo "::notice::Toolchain has D3DDEVINFO_RESOURCEMANAGER; will patch d3d9_include.h if needed."
  fi
fi

# Patch A - D3DDEVINFO Redefinition Fix
INC="src/d3d9/d3d9_include.h"
if [ "$HAS_DEVINFO" = true ] && [[ -f "$INC" ]] && grep -q "typedef struct _D3DDEVINFO_RESOURCEMANAGER" "$INC"; then
  echo "Patching D3DDEVINFO_RESOURCEMANAGER redefinition in $INC..."
  perl -i -0777 -pe 's/typedef\s+struct\s+_D3DDEVINFO_RESOURCEMANAGER\s*\{.*?\}\s*D3DDEVINFO_RESOURCEMANAGER[^;]*;//s' "$INC"
fi

# Patch B - UnmappedSubresource Fix
TEX="src/d3d11/d3d11_texture.h"
if [[ -f "$TEX" ]] && grep -q "UnmappedSubresource" "$TEX"; then
  echo "Patching UnmappedSubresource in $TEX..."
  perl -i -pe 's/static\s+(?:constexpr\s+)?D3D11_MAP\s+UnmappedSubresource\s*=.*/inline static const D3D11_MAP UnmappedSubresource = static_cast<D3D11_MAP>(-1);/' "$TEX"
fi

echo "== DXVK compatibility patches done =="
