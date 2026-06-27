set -Eeuo pipefail

LLVM_MINGW_TAG="${LLVM_MINGW_TAG:-20260407}"
LLVM_MINGW_REPO="${LLVM_MINGW_REPO:-mstorsjo/llvm-mingw}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$PWD/.toolchains/llvm-mingw-${LLVM_MINGW_TAG}}"

SUDO=""
if command -v sudo >/dev/null 2>&1 && [[ "$TOOLCHAIN_DIR" == /opt/* ]]; then
  SUDO="sudo"
fi

python3 -m venv .venv
.venv/bin/python -m pip install "meson==1.2.3" "ninja==1.11.1"

mkdir -p "$(dirname "$TOOLCHAIN_DIR")"

archive="llvm-mingw-${LLVM_MINGW_TAG}-ucrt-ubuntu-22.04-x86_64.tar.xz"
url="https://github.com/${LLVM_MINGW_REPO}/releases/download/${LLVM_MINGW_TAG}/${archive}"

if [[ ! -x "$TOOLCHAIN_DIR/bin/x86_64-w64-mingw32-g++" ]]; then
  curl -fL "$url" -o llvm.tar.xz
  $SUDO rm -rf "$TOOLCHAIN_DIR"
  $SUDO mkdir -p "$TOOLCHAIN_DIR"
  $SUDO tar -C "$TOOLCHAIN_DIR" --strip-components=1 -xJf llvm.tar.xz
fi

SPIRV_DEST="$TOOLCHAIN_DIR/generic-w64-mingw32/include"
[[ -d "$SPIRV_DEST" ]] || SPIRV_DEST="$TOOLCHAIN_DIR/x86_64-w64-mingw32/include"

if [[ -d "$SPIRV_DEST" && ! -f "$SPIRV_DEST/spirv/unified1/spirv.hpp" ]]; then
  spv_tmp="$(mktemp -d)"
  cleanup_spv_tmp() { rm -rf "$spv_tmp"; }
  trap cleanup_spv_tmp EXIT

  git clone --depth=1 https://github.com/KhronosGroup/SPIRV-Headers.git "$spv_tmp/SPIRV-Headers"
  echo "Installing SPIRV-Headers into $SPIRV_DEST/spirv (shared across all triples) ..."
  $SUDO mkdir -p "$SPIRV_DEST/spirv"
  $SUDO cp -r "$spv_tmp/SPIRV-Headers/include/spirv/"* "$SPIRV_DEST/spirv/"
fi

cat <<EOF
Local build tools are ready.

Add these to your shell before building:
  export PATH="$PWD/.venv/bin:$TOOLCHAIN_DIR/bin:\$PATH"
  export TOOLCHAIN_DIR="$TOOLCHAIN_DIR"
EOF
