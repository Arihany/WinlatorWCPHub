set -Eeuo pipefail

SUDO=""
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

export DEBIAN_FRONTEND=noninteractive

kind="${WCP_BUILD_KIND:-${UNI_KIND:-}}"
[[ -n "$kind" ]] || { echo "WCP_BUILD_KIND or UNI_KIND is required" >&2; exit 1; }

packages=(
  ca-certificates curl xz-utils jq git
  build-essential python3 python3-venv python3-pip
  zstd perl tar
)

case "$kind" in
  fexcore|fexcore-unixlib)
    packages+=(cmake unzip)
    ;;
  dxvk-legacy)
    # mingw-gcc profile: distribution cross compilers, deliberately unpinned.
    packages+=(glslang-tools pkg-config g++-mingw-w64-x86-64 g++-mingw-w64-i686)
    ;;
  dxvk-gplasync*)
    packages+=(glslang-tools pkg-config patch)
    ;;
  dxvk*|vkd3d-proton*)
    packages+=(glslang-tools pkg-config)
    ;;
  *)
    echo "Unsupported build kind: $kind" >&2
    exit 1
    ;;
esac

$SUDO apt-get -yqq update
$SUDO apt-get -yqq install --no-install-recommends "${packages[@]}"
