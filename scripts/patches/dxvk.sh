set -Eeuo pipefail

SRC_DIR="${1:-.}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-/opt/llvm-mingw}"

cd "$SRC_DIR"

echo "== DXVK compatibility patches =="

HAS_DEVINFO=false
if compgen -G "$TOOLCHAIN_DIR"/*-w64-mingw32/include/d3d9types.h >/dev/null 2>&1; then
  if grep -q "_D3DDEVINFO_RESOURCEMANAGER" "$TOOLCHAIN_DIR"/*-w64-mingw32/include/d3d9types.h; then
    HAS_DEVINFO=true
    echo "::notice::Toolchain has D3DDEVINFO_RESOURCEMANAGER."
  fi
fi

HAS_D3D10_STATEBLOCK=false
if compgen -G "$TOOLCHAIN_DIR"/*-w64-mingw32/include/d3d10*.h >/dev/null 2>&1; then
  if grep -Rqs 'ID3D10StateBlock' "$TOOLCHAIN_DIR"/*-w64-mingw32/include/d3d10* 2>/dev/null; then
    HAS_D3D10_STATEBLOCK=true
    echo "::notice::Toolchain provides ID3D10StateBlock."
  fi
fi

INC="src/d3d9/d3d9_include.h"
if [[ "$HAS_DEVINFO" == true && -f "$INC" ]]; then
  if grep -q 'typedef struct _D3DDEVINFO_RESOURCEMANAGER' "$INC"; then
    echo "Patching D3DDEVINFO_RESOURCEMANAGER in $INC..."
    perl -i -0777 -pe 's/typedef\s+struct\s+_D3DDEVINFO_RESOURCEMANAGER\s*\{.*?\}\s*D3DDEVINFO_RESOURCEMANAGER[^;]*;//s' "$INC"
  fi
fi

TEX="src/d3d11/d3d11_texture.h"
if [[ -f "$TEX" ]]; then
  if grep -q 'UnmappedSubresource' "$TEX"; then
    echo "Patching UnmappedSubresource in $TEX..."
    perl -i -pe 's/static\s+(?:constexpr\s+)?D3D11_MAP\s+UnmappedSubresource\s*=.*/inline static const D3D11_MAP UnmappedSubresource = static_cast<D3D11_MAP>(-1);/' "$TEX"
  fi
fi

D3D10_INT="src/d3d10/d3d10_interfaces.h"
if [[ "$HAS_D3D10_STATEBLOCK" == true && -f "$D3D10_INT" ]]; then
  if grep -q '__CRT_UUID_DECL(ID3D10StateBlock' "$D3D10_INT"; then
    echo "Removing duplicate ID3D10StateBlock __CRT_UUID_DECL in $D3D10_INT..."
    perl -i -pe 's@^\s*__CRT_UUID_DECL\(ID3D10StateBlock,\s*0x0803425a,0x57f5,0x4dd6,0x94,0x65,0xa8,0x75,0x70,0x83,0x4a,0x08\);\s*$@@' "$D3D10_INT"
  fi
fi

echo "== DXVK compatibility patches done =="
