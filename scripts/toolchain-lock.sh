WCP_UPSTREAM_TOOLCHAIN_ID="llvm-mingw-20260616-ucrt-llvm-22.1.8"
WCP_UPSTREAM_TOOLCHAIN_REPO="mstorsjo/llvm-mingw"
WCP_UPSTREAM_TOOLCHAIN_TAG="20260616"
WCP_UPSTREAM_TOOLCHAIN_ARCHIVE="llvm-mingw-20260616-ucrt-ubuntu-22.04-x86_64.tar.xz"
WCP_UPSTREAM_TOOLCHAIN_SHA256="534b92e067b22a6b4441f48ae9240a3341b17825d04d577eab0cf85c44b4deda"

WCP_ROOTCELLAR_TOOLCHAIN_ID="rootcellar-proton-llvm-mingw-20260602-llvm-22.1.8-r1"
WCP_ROOTCELLAR_TOOLCHAIN_RELEASE_REPO="Arihany/WinlatorWCPHub"

WCP_ROOTCELLAR_TOOLCHAIN_RELEASE_TAG="meowww"
WCP_ROOTCELLAR_TOOLCHAIN_ARCHIVE="${WCP_ROOTCELLAR_TOOLCHAIN_ID}-x86_64.tar.xz"
WCP_ROOTCELLAR_TOOLCHAIN_CHECKSUM="${WCP_ROOTCELLAR_TOOLCHAIN_ARCHIVE}.sha256"
WCP_ROOTCELLAR_TOOLCHAIN_SHA256="659c094e0ffd8c19ac8a0de0910261d2d92826bca4aa34b2dcbf463874d459c9"
WCP_ROOTCELLAR_TOOLCHAIN_MANIFEST_SHA256="e75aa3425fc56ad364a80e1de958fd8f946d2e9e33453b49c95c47e46e7eb45b"

WCP_MESON_VERSION="1.2.3"
WCP_NINJA_VERSION="1.11.1"
WCP_ANDROID_NDK_VERSION="r29"
WCP_ANDROID_NDK_ARCHIVE="android-ndk-r29-linux.zip"
WCP_ANDROID_NDK_SHA256="4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf"
WCP_ANDROID_NDK_URL="https://dl.google.com/android/repository/$WCP_ANDROID_NDK_ARCHIVE"

# Deliberately NOT pinned
# a newer GCC that stops compiling them fails loudly
WCP_MINGW_GCC_TOOLCHAIN_ID="system-mingw-gcc"
WCP_MINGW_GCC_TOOLCHAIN_DIR="/usr"

wcp_toolchain_profile_for_kind() {
  case "${1:?build kind is required}" in
    fexcore|fexcore-unixlib|*-arm64ec)
      printf 'rootcellar\n'
      ;;
    dxvk-legacy)
      printf 'mingw-gcc\n'
      ;;
    dxvk|dxvk-gplasync|dxvk-sarek-dyasync|vkd3d-proton)
      printf 'upstream\n'
      ;;
    *)
      echo "Unsupported toolchain build kind: $1" >&2
      return 1
      ;;
  esac
}

wcp_toolchain_id_for_profile() {
  case "${1:?toolchain profile is required}" in
    upstream)
      printf '%s\n' "$WCP_UPSTREAM_TOOLCHAIN_ID"
      ;;
    rootcellar)
      printf '%s\n' "$WCP_ROOTCELLAR_TOOLCHAIN_ID"
      ;;
    mingw-gcc)
      printf '%s\n' "$WCP_MINGW_GCC_TOOLCHAIN_ID"
      ;;
    *)
      echo "Unsupported toolchain profile: $1" >&2
      return 1
      ;;
  esac
}

wcp_default_toolchain_dir() {
  local root="${1:?workspace root is required}"
  local profile="${2:?toolchain profile is required}"

  if [[ "$profile" == mingw-gcc ]]; then
    printf '%s\n' "$WCP_MINGW_GCC_TOOLCHAIN_DIR"
    return 0
  fi

  printf '%s/.toolchains/%s\n' "$root" "$(wcp_toolchain_id_for_profile "$profile")"
}

wcp_default_android_ndk_dir() {
  local root="${1:?workspace root is required}"

  printf '%s/.toolchains/android-ndk-%s\n' "$root" "$WCP_ANDROID_NDK_VERSION"
}

wcp_validate_toolchain_profile() {
  case "${1:?toolchain profile is required}" in
    upstream|rootcellar|mingw-gcc) ;;
    *)
      echo "Unsupported toolchain profile: $1" >&2
      return 1
      ;;
  esac
}
