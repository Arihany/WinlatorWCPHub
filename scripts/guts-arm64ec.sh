set -Eeuo pipefail

: "${UNI_KIND:?UNI_KIND is required}"
: "${REL_TAG_STABLE:?REL_TAG_STABLE is required}"

ref="${1:?ref is required}"
ver_name="${2:?ver_name is required}"
filename="${3:?filename is required}"

../.venv/bin/meson --version || true

PKG_ROOT="../pkg_temp/${UNI_KIND}-${ref}"
rm -rf "${PKG_ROOT}"
mkdir -p "${PKG_ROOT}"

rm -rf build_x86 build_ec

echo "Compiling x86 (32-bit)..."
meson setup build_x86 \
  --cross-file build-win32.txt \
  --buildtype release \
  --prefix "$PWD/${PKG_ROOT}/x32"
ninja -C build_x86 install

echo "Compiling ARM64EC..."

ARGS_FLAGS=""

if [[ -n "${MOCK_DIR:-}" ]]; then
  echo "Using ARM64EC shim from MOCK_DIR=$MOCK_DIR"
  ARGS_FLAGS="-I${MOCK_DIR} -include sarek_all_in_one.h"
elif [[ -n "${ARM64EC_CPP_ARGS:-}" ]]; then
  echo "Using custom ARM64EC cpp_args: ${ARM64EC_CPP_ARGS}"
  ARGS_FLAGS="${ARM64EC_CPP_ARGS}"
fi

_orig_cflags="${CFLAGS:-}"
_orig_cxxflags="${CXXFLAGS:-}"

CFLAGS="${_orig_cflags}" \
CXXFLAGS="${_orig_cxxflags:+${_orig_cxxflags} }${ARGS_FLAGS}" \
meson setup build_ec \
  --cross-file ../toolchains/arm64ec.meson.ini \
  --buildtype release \
  --prefix "$PWD/${PKG_ROOT}/arm64ec" \
  -Dcpp_args="${ARGS_FLAGS}"

ninja -C build_ec install

WCP_DIR="../${REL_TAG_STABLE}_WCP"
rm -rf "$WCP_DIR"

SRC_EC="${PKG_ROOT}/arm64ec"
SRC_32="${PKG_ROOT}/x32"

if [[ -d "$SRC_EC/bin" ]]; then
  SRC_EC="$SRC_EC/bin"
fi

if [[ -d "$SRC_32/bin" ]]; then
  SRC_32="$SRC_32/bin"
fi

PROFILE_SH="../scripts/profiles/${UNI_KIND}.sh" \
bash ../scripts/packing.sh \
  "$SRC_EC" \
  "$SRC_32" \
  "$WCP_DIR" \
  "$ver_name" \
  "../out/${filename}"
