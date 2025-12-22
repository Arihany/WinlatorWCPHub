set -Eeuo pipefail

: "${MESA_BASELINE_SHA:?MESA_BASELINE_SHA is required}"

WORKDIR="${WORKDIR:-$(pwd)/turnip_workdir}"
NDK_VERSION="${NDK_VERSION:-android-ndk-r29}"
SDK_VERSION="${SDK_VERSION:-31}"

MESA_REPO="${MESA_REPO:-https://gitlab.freedesktop.org/mesa/mesa.git}"
MESA_BRANCH="${MESA_BRANCH:-main}"

NDK_ZIP="${NDK_VERSION}-linux.zip"
NDK_DIR="${WORKDIR}/${NDK_VERSION}"
NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin"

OUT_DIR="${WORKDIR}/out"
LOG_DIR="${WORKDIR}/.logs"

DEPS=(git curl unzip ninja zip python3 patchelf)

die() { echo "::error::$*" >&2; exit 1; }

runq() {
  local label="$1"; shift
  mkdir -p "${LOG_DIR}"
  local safe="${label//[^a-zA-Z0-9_.-]/_}"
  local log="${LOG_DIR}/${safe}.log"

  if "$@" >"${log}" 2>&1; then
    rm -f "${log}" || true
    return 0
  fi

  echo "::error::Failed: ${label}" >&2

  tail -n 200 "${log}" >&2 || true
  exit 1
}

check_deps() {
  local bin
  for bin in "${DEPS[@]}"; do
    command -v "${bin}" >/dev/null 2>&1 || die "Missing dependency: ${bin}"
  done
}

setup_python_env() {
  mkdir -p "${WORKDIR}"
  local venv="${WORKDIR}/.venv"

  rm -rf "${venv}" || true
  runq "python-venv" python3 -m venv "${venv}"

  source "${venv}/bin/activate"

  runq "pip-upgrade" python -m pip -q install --upgrade pip
  runq "pip-deps" python -m pip -q install --upgrade \
    "meson>=1.4.0" "mako>=1.0.0" "packaging" "PyYAML"
}

prepare_ndk() {
  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"

  if [[ -x "${NDK_DIR}/ndk-build" ]]; then
    return 0
  fi

  if [[ ! -f "${NDK_ZIP}" ]]; then
    runq "ndk-download" curl --http1.1 -fL \
      --retry 10 --retry-all-errors --retry-delay 2 \
      -C - \
      "https://dl.google.com/android/repository/${NDK_ZIP}" \
      -o "${NDK_ZIP}"
  fi

  rm -rf "${NDK_DIR}" || true
  runq "ndk-unzip" unzip -q -o "${NDK_ZIP}"

  [[ -x "${NDK_DIR}/ndk-build" ]] || die "NDK install failed: ${NDK_DIR}"
}

prepare_mesa() {
  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"

  rm -rf mesa || true
  runq "mesa-clone" git clone --filter=blob:none --depth=80 --single-branch -b "${MESA_BRANCH}" "${MESA_REPO}" mesa
  cd mesa
  if ! git checkout -f "${MESA_BASELINE_SHA}" >/dev/null 2>&1; then
    runq "mesa-fetch-sha" git fetch --depth=200 origin "${MESA_BASELINE_SHA}"
    runq "mesa-checkout" git checkout -f "${MESA_BASELINE_SHA}"
  fi
}

write_cross_files() {
  cd "${WORKDIR}/mesa"

  cat > android-aarch64.txt <<EOF
[binaries]
c = ['${NDK_BIN}/aarch64-linux-android${SDK_VERSION}-clang']
cpp = ['${NDK_BIN}/aarch64-linux-android${SDK_VERSION}-clang++']
ar = '${NDK_BIN}/llvm-ar'
strip = '${NDK_BIN}/llvm-strip'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF
}

build_turnip() {
  cd "${WORKDIR}/mesa"

  rm -rf build-android-aarch64 || true

  runq "meson-setup" meson setup build-android-aarch64 \
    --cross-file android-aarch64.txt \
    --buildtype=release \
    -Db_ndebug=true \
    -Db_lto=true \
    -Dplatforms=android \
    -Dplatform-sdk-version="${SDK_VERSION}" \
    -Dandroid-stub=true \
    -Dandroid-libbacktrace=disabled \
    -Degl=disabled \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl

  runq "meson-compile" meson compile -C build-android-aarch64

  mkdir -p "${OUT_DIR}"

  local src="build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so"
  [[ -f "${src}" ]] || die "Missing build output: ${src}"

  cp -f "${src}" "${OUT_DIR}/libvulkan_freedreno.so"
  cp -f "${OUT_DIR}/libvulkan_freedreno.so" "${OUT_DIR}/vulkan.ad07xx.so"

  "${NDK_BIN}/llvm-strip" --strip-all "${OUT_DIR}/vulkan.ad07xx.so" >/dev/null 2>&1 || true
  patchelf --set-soname "vulkan.ad07xx.so" "${OUT_DIR}/vulkan.ad07xx.so" >/dev/null 2>&1 || true
}

write_meta_json() {
  cd "${WORKDIR}/mesa"

  local mesa_sha mesa_branch
  mesa_sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  mesa_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "${MESA_BRANCH}")"

  local vulkan_core="${WORKDIR}/mesa/include/vulkan/vulkan_core.h"
  local vk_major=1 vk_minor=0 vk_header_ver=0

  if [[ -f "${vulkan_core}" ]]; then
    vk_header_ver="$(
      grep -E '^#define[[:space:]]+VK_HEADER_VERSION[[:space:]]+' "${vulkan_core}" \
        | awk '{print $3}' | tr -d 'U' || echo 0
    )"

    local line major minor
    line="$(
      grep -E 'VK_HEADER_VERSION_COMPLETE[[:space:]]+VK_MAKE_API_VERSION' "${vulkan_core}" \
        | head -n1 || true
    )"

    if [[ -n "${line}" ]]; then
      major="$(printf '%s\n' "${line}" | sed -n 's/.*VK_MAKE_API_VERSION(0,[[:space:]]*\([0-9]\+\),[[:space:]]*\([0-9]\+\),.*/\1/p')"
      minor="$(printf '%s\n' "${line}" | sed -n 's/.*VK_MAKE_API_VERSION(0,[[:space:]]*\([0-9]\+\),[[:space:]]*\([0-9]\+\),.*/\2/p')"
      [[ -n "${major}" ]] && vk_major="${major}"
      [[ -n "${minor}" ]] && vk_minor="${minor}"
    fi
  fi

  local vk_version_str="Vulkan ${vk_major}.${vk_minor}.${vk_header_ver}"
  local name_str="Mesa Turnip dev ${mesa_sha}"

  cat > "${OUT_DIR}/meta.json" <<EOF
{
  "schemaVersion": 1,
  "name": "${name_str}",
  "description": "${mesa_branch}",
  "author": "Ari",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "${vk_version_str}",
  "minApi": ${SDK_VERSION},
  "libraryName": "vulkan.ad07xx.so"
}
EOF
}

pack_artifact() {
  cd "${WORKDIR}/mesa"

  local short datecode name
  short="${MESA_BASELINE_SHA:0:7}"
  datecode="$(date -u +%y%m%d)"
  name="Turnip-dev-${datecode}-${short}.zip"

  cd "${OUT_DIR}"
  runq "zip" zip -q -9 "${name}" \
    "vulkan.ad07xx.so" \
    "meta.json"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "ARTIFACT_NAME=${name}"
      echo "ARTIFACT_PATH=${OUT_DIR}/${name}"
    } >> "${GITHUB_OUTPUT}"
  else
    printf '%s\n' "${OUT_DIR}/${name}"
  fi
}

main() {
  check_deps
  setup_python_env
  prepare_ndk
  prepare_mesa
  write_cross_files
  build_turnip
  write_meta_json
  pack_artifact
}

main "$@"
