set -Eeuo pipefail
IFS=$'\n\t'

LLVM_MINGW_TAG="${LLVM_MINGW_TAG:-20251216}"
LLVM_MINGW_REPO="${LLVM_MINGW_REPO:-mstorsjo/llvm-mingw}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-/opt/llvm-mingw}"

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE not set}"
: "${GITHUB_PATH:?GITHUB_PATH not set}"

cd "$GITHUB_WORKSPACE"

rm -rf src pkg_temp *_WCP out .venv

SUDO=""
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

python3 -m venv .venv
.venv/bin/python -m pip install "meson==1.2.3" "ninja==1.11.1"
echo "$PWD/.venv/bin" >> "$GITHUB_PATH"

gh release download "$LLVM_MINGW_TAG" -R "$LLVM_MINGW_REPO" \
  -p '*ucrt-ubuntu-22.04-x86_64.tar.xz' -O llvm.tar.xz --clobber

$SUDO rm -rf "$TOOLCHAIN_DIR"
$SUDO mkdir -p "$TOOLCHAIN_DIR"
$SUDO tar -C "$TOOLCHAIN_DIR" --strip-components=1 -xJf llvm.tar.xz
echo "$TOOLCHAIN_DIR/bin" >> "$GITHUB_PATH"

if [[ ! -f "$TOOLCHAIN_DIR/x86_64-w64-mingw32/include/spirv/unified1/spirv.hpp" ]]; then
  SPV_TMP="$(mktemp -d)"
  cleanup_spv_tmp() { rm -rf "$SPV_TMP"; }
  trap cleanup_spv_tmp RETURN

  git clone --depth=1 https://github.com/KhronosGroup/SPIRV-Headers.git "$SPV_TMP/SPIRV-Headers"

  for trip in x86_64-w64-mingw32 i686-w64-mingw32; do
    if [ -d "$TOOLCHAIN_DIR/$trip/include" ]; then
      echo "Installing SPIRV-Headers into $TOOLCHAIN_DIR/$trip/include/spirv ..."
      $SUDO mkdir -p "$TOOLCHAIN_DIR/$trip/include/spirv"
      $SUDO cp -r "$SPV_TMP/SPIRV-Headers/include/spirv/"* \
        "$TOOLCHAIN_DIR/$trip/include/spirv/"
    fi
  done
fi
