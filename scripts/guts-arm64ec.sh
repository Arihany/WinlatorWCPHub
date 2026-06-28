set -Eeuo pipefail

: "${UNI_KIND:?UNI_KIND is required}"
: "${REL_TAG_STABLE:?REL_TAG_STABLE is required}"

source ../scripts/arm64ec-common.sh

ref="${1:?ref is required}"
ver_name="${2:?ver_name is required}"
filename="${3:?filename is required}"

../.venv/bin/meson --version || true

PKG_ROOT="../pkg_temp/${UNI_KIND}-${ref}"
rm -rf "${PKG_ROOT}"
mkdir -p "${PKG_ROOT}"

rm -rf build_x86 build_ec build_ec.cross.txt

echo "Compiling x86 (32-bit)..."
meson setup build_x86 \
  --cross-file build-win32.txt \
  --buildtype release \
  --prefix "$PWD/${PKG_ROOT}/x32"
ninja -C build_x86 install

echo "Compiling ARM64EC..."

ARGS_FLAGS=""

if [[ -n "${ARM64EC_CPP_ARGS:-}" ]]; then
  echo "Using custom ARM64EC cpp_args: ${ARM64EC_CPP_ARGS}"
  ARGS_FLAGS="${ARM64EC_CPP_ARGS}"
fi

arm64ec_write_meson_cross_file \
  ../toolchains/arm64ec.meson.ini \
  build_ec.cross.txt

_orig_cflags="${CFLAGS:-}"
_orig_cxxflags="${CXXFLAGS:-}"
meson_env=()

if [[ -n "${_orig_cflags}" ]]; then
  meson_env+=("CFLAGS=${_orig_cflags}")
fi

if [[ -n "${_orig_cxxflags}${ARGS_FLAGS}" ]]; then
  meson_env+=("CXXFLAGS=${_orig_cxxflags:+${_orig_cxxflags} }${ARGS_FLAGS}")
fi

env "${meson_env[@]}" \
meson setup build_ec \
  --cross-file build_ec.cross.txt \
  --buildtype=plain \
  --prefix "$PWD/${PKG_ROOT}/arm64ec"

arm64ec_verify_compile_flags build_ec/compile_commands.json

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

PROFILE_SH="${PROFILE_SH:-../scripts/profiles/${UNI_KIND}.sh}" \
bash ../scripts/packing.sh \
  "$SRC_EC" \
  "$SRC_32" \
  "$WCP_DIR" \
  "$ver_name" \
  "../out/${filename}"
