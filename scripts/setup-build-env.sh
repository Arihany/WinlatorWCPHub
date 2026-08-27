#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/toolchain-lock.sh"

MODE="${1:-local}"
case "$MODE" in
  github|local) ;;
  *) echo "Usage: $0 [github|local]" >&2; exit 2 ;;
esac

PROFILE="${WCP_TOOLCHAIN_PROFILE:-}"
if [[ -z "$PROFILE" ]]; then
  PROFILE="$(wcp_toolchain_profile_for_kind "${UNI_KIND:?UNI_KIND or WCP_TOOLCHAIN_PROFILE is required}")"
fi
wcp_validate_toolchain_profile "$PROFILE"
TOOLCHAIN_ID="$(wcp_toolchain_id_for_profile "$PROFILE")"

if [[ "$MODE" == github ]]; then
  : "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE not set}"
  : "${GITHUB_PATH:?GITHUB_PATH not set}"
  : "${GITHUB_ENV:?GITHUB_ENV not set}"
  ROOT="$GITHUB_WORKSPACE"
  TOOLCHAIN_DIR="$(wcp_default_toolchain_dir "$ROOT" "$PROFILE")"
  rm -rf "$ROOT/src" "$ROOT/pkg_temp" "$ROOT/out" "$ROOT/.venv" "$ROOT"/*_WCP
else
  case "$PROFILE" in
    rootcellar)
      TOOLCHAIN_DIR="${ROOTCELLAR_TOOLCHAIN_DIR:-$(wcp_default_toolchain_dir "$ROOT" "$PROFILE")}"
      ;;
    upstream)
      TOOLCHAIN_DIR="${UPSTREAM_TOOLCHAIN_DIR:-$(wcp_default_toolchain_dir "$ROOT" "$PROFILE")}"
      ;;
    mingw-gcc)
      TOOLCHAIN_DIR="${MINGW_GCC_TOOLCHAIN_DIR:-$(wcp_default_toolchain_dir "$ROOT" "$PROFILE")}"
      ;;
  esac
fi

SUDO=()
if [[ "$TOOLCHAIN_DIR" == /opt/* ]] && command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
fi

die() {
  echo "setup-build-env: $*" >&2
  exit 1
}

download() {
  local url="${1:?url is required}"
  local output="${2:?output is required}"
  curl --fail --location --retry 3 --output "$output" "$url"
}

validate_tools() {
  local tool
  local tools=(x86_64-w64-mingw32-g++ i686-w64-mingw32-g++ llvm-readobj)

  # No LLVM binutils and no archive hash. Only the GCC identity is enforced
  if [[ "$PROFILE" == mingw-gcc ]]; then
    local driver version
    for driver in x86_64-w64-mingw32-g++ i686-w64-mingw32-g++ \
                  x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc; do
      [[ -x "$TOOLCHAIN_DIR/bin/$driver" ]] || die "missing $driver in $TOOLCHAIN_DIR"
    done
    for driver in x86_64-w64-mingw32-g++ i686-w64-mingw32-g++; do
      version="$("$TOOLCHAIN_DIR/bin/$driver" --version 2>/dev/null | head -n1)"
      [[ "$version" == *"(GCC)"* ]] ||
        die "$driver is not GCC (got: ${version:-<none>}); mingw-gcc refuses to fall back to another compiler"
    done
    echo "mingw-gcc toolchain (unpinned by design): $version"
    return 0
  fi

  if [[ "$PROFILE" == rootcellar ]]; then
    tools+=(
      arm64ec-w64-mingw32-gcc
      arm64ec-w64-mingw32-g++
      arm64ec-w64-mingw32-ar
      arm64ec-w64-mingw32-windres
      aarch64-w64-mingw32-g++
      i686-w64-mingw32-gcc
      i686-w64-mingw32-ar
      i686-w64-mingw32-windres
    )
  fi

  for tool in "${tools[@]}"; do
    [[ -x "$TOOLCHAIN_DIR/bin/$tool" ]] || die "missing $tool in $TOOLCHAIN_DIR"
  done

  if [[ "$PROFILE" == upstream ]]; then
    local marker="$TOOLCHAIN_DIR/.wcp-toolchain-id"
    [[ -f "$marker" && "$(<"$marker")" == "$WCP_UPSTREAM_TOOLCHAIN_ID" ]] ||
      die "upstream toolchain identity marker mismatch: $marker"
  else
    local manifest="$TOOLCHAIN_DIR/rootcellar-toolchain-manifest.json"
    local actual_manifest_sha256
    [[ -f "$manifest" ]] || die "missing RootCellar manifest: $manifest"
    actual_manifest_sha256="$(sha256sum "$manifest" | awk '{print $1}')"
    [[ "$actual_manifest_sha256" == "$WCP_ROOTCELLAR_TOOLCHAIN_MANIFEST_SHA256" ]] ||
      die "RootCellar manifest mismatch: expected $WCP_ROOTCELLAR_TOOLCHAIN_MANIFEST_SHA256, got $actual_manifest_sha256"
  fi
}

install_toolchain() {
  local temp_dir archive archive_sha256 archive_url checksum_url

  # nothing to download here.
  if [[ "$PROFILE" == mingw-gcc ]]; then
    validate_tools
    return
  fi

  if [[ -d "$TOOLCHAIN_DIR/bin" ]]; then
    validate_tools
    return
  fi

  [[ ! -e "$TOOLCHAIN_DIR" ]] || die "refusing to replace incomplete toolchain directory: $TOOLCHAIN_DIR"
  temp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temp_dir"' EXIT

  if [[ "$PROFILE" == upstream ]]; then
    archive="$temp_dir/$WCP_UPSTREAM_TOOLCHAIN_ARCHIVE"
    archive_url="https://github.com/$WCP_UPSTREAM_TOOLCHAIN_REPO/releases/download/$WCP_UPSTREAM_TOOLCHAIN_TAG/$WCP_UPSTREAM_TOOLCHAIN_ARCHIVE"
    download "$archive_url" "$archive"
    archive_sha256="$(sha256sum "$archive" | awk '{print $1}')"
    [[ "$archive_sha256" == "$WCP_UPSTREAM_TOOLCHAIN_SHA256" ]] ||
      die "upstream archive mismatch: expected $WCP_UPSTREAM_TOOLCHAIN_SHA256, got $archive_sha256"
  else
    archive="$temp_dir/$WCP_ROOTCELLAR_TOOLCHAIN_ARCHIVE"
    archive_url="https://github.com/$WCP_ROOTCELLAR_TOOLCHAIN_RELEASE_REPO/releases/download/$WCP_ROOTCELLAR_TOOLCHAIN_RELEASE_TAG/$WCP_ROOTCELLAR_TOOLCHAIN_ARCHIVE"
    checksum_url="https://github.com/$WCP_ROOTCELLAR_TOOLCHAIN_RELEASE_REPO/releases/download/$WCP_ROOTCELLAR_TOOLCHAIN_RELEASE_TAG/$WCP_ROOTCELLAR_TOOLCHAIN_CHECKSUM"
    download "$archive_url" "$archive"
    archive_sha256="$(sha256sum "$archive" | awk '{print $1}')"
    [[ "$archive_sha256" == "$WCP_ROOTCELLAR_TOOLCHAIN_SHA256" ]] ||
      die "RootCellar archive mismatch: expected $WCP_ROOTCELLAR_TOOLCHAIN_SHA256, got $archive_sha256"
    download "$checksum_url" "$temp_dir/$WCP_ROOTCELLAR_TOOLCHAIN_CHECKSUM"
    (cd "$temp_dir" && sha256sum --check "$WCP_ROOTCELLAR_TOOLCHAIN_CHECKSUM")
  fi

  "${SUDO[@]}" mkdir -p "$TOOLCHAIN_DIR"
  "${SUDO[@]}" tar -C "$TOOLCHAIN_DIR" --strip-components=1 -xJf "$archive"
  if [[ "$PROFILE" == upstream ]]; then
    printf '%s\n' "$WCP_UPSTREAM_TOOLCHAIN_ID" | "${SUDO[@]}" tee "$TOOLCHAIN_DIR/.wcp-toolchain-id" >/dev/null
  fi
  validate_tools
  rm -rf -- "$temp_dir"
  trap - EXIT
}

setup_python_tools() {
  python3 -m venv "$ROOT/.venv"
  "$ROOT/.venv/bin/python" -m pip install \
    "meson==$WCP_MESON_VERSION" \
    "ninja==$WCP_NINJA_VERSION"
}

setup_android_ndk() {
  # Only the kind that ships the Android UnixLib SOs needs the NDK.
  [[ "${UNI_KIND:-}" == fexcore-unixlib ]] || return 0

  local archive actual_sha256 parent
  if [[ "$MODE" == github ]]; then
    FEX_ANDROID_NDK_ROOT="$(wcp_default_android_ndk_dir "$ROOT")"
  else
    FEX_ANDROID_NDK_ROOT="${FEX_ANDROID_NDK_ROOT:-${ANDROID_NDK_ROOT:-$(wcp_default_android_ndk_dir "$ROOT")}}"
  fi

  if [[ ! -f "$FEX_ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" ]]; then
    [[ ! -e "$FEX_ANDROID_NDK_ROOT" ]] || die "refusing to replace incomplete Android NDK: $FEX_ANDROID_NDK_ROOT"
    archive="$(mktemp)"
    trap 'rm -f -- "$archive"' EXIT
    download "$WCP_ANDROID_NDK_URL" "$archive"
    actual_sha256="$(sha256sum "$archive" | awk '{print $1}')"
    [[ "$actual_sha256" == "$WCP_ANDROID_NDK_SHA256" ]] ||
      die "Android NDK archive mismatch: expected $WCP_ANDROID_NDK_SHA256, got $actual_sha256"
    parent="$(dirname "$FEX_ANDROID_NDK_ROOT")"
    "${SUDO[@]}" mkdir -p "$parent"
    "${SUDO[@]}" unzip -q "$archive" -d "$parent"
    rm -f -- "$archive"
    trap - EXIT
  fi

  [[ -x "$FEX_ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" ]] ||
    die "Android NDK r29 validation failed: $FEX_ANDROID_NDK_ROOT"
}

setup_python_tools
install_toolchain
setup_android_ndk

if [[ "$MODE" == github ]]; then
  printf '%s\n' "$ROOT/.venv/bin" "$TOOLCHAIN_DIR/bin" >> "$GITHUB_PATH"
  printf 'TOOLCHAIN_DIR=%s\n' "$TOOLCHAIN_DIR" >> "$GITHUB_ENV"
  case "$PROFILE" in
    rootcellar) printf 'ROOTCELLAR_TOOLCHAIN_DIR=%s\n' "$TOOLCHAIN_DIR" >> "$GITHUB_ENV" ;;
    mingw-gcc)  printf 'MINGW_GCC_TOOLCHAIN_DIR=%s\n' "$TOOLCHAIN_DIR" >> "$GITHUB_ENV" ;;
    *)          printf 'UPSTREAM_TOOLCHAIN_DIR=%s\n' "$TOOLCHAIN_DIR" >> "$GITHUB_ENV" ;;
  esac
  if [[ "${UNI_KIND:-}" == fexcore-unixlib ]]; then
    printf 'FEX_ANDROID_NDK_ROOT=%s\n' "$FEX_ANDROID_NDK_ROOT" >> "$GITHUB_ENV"
  fi
fi

printf 'Toolchain profile: %s\nToolchain ID: %s\nToolchain directory: %s\n' \
  "$PROFILE" "$TOOLCHAIN_ID" "$TOOLCHAIN_DIR"
