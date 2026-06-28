ARM64EC_CPU_FLAGS=("-march=armv8.2-a" "-mtune=cortex-x3")
ARM64EC_MESON_FLAGS=("${ARM64EC_CPU_FLAGS[@]}" "-O2" "-fwrapv" "-fno-strict-aliasing")

arm64ec_join_flags() {
  local IFS=" "
  printf '%s' "$*"
}

arm64ec_cpu_flags() {
  arm64ec_join_flags "${ARM64EC_CPU_FLAGS[@]}"
}

arm64ec_meson_flags() {
  arm64ec_join_flags "${ARM64EC_MESON_FLAGS[@]}"
}

arm64ec_meson_array() {
  local flag
  local sep=""

  printf '['
  for flag in "$@"; do
    printf "%s'%s'" "$sep" "$flag"
    sep=", "
  done
  printf ']'
}

arm64ec_write_meson_cross_file() {
  local template="${1:?template cross file is required}"
  local output="${2:?output cross file is required}"

  cp "$template" "$output"
  {
    printf '\n[built-in options]\n'
    printf 'c_args   = '
    arm64ec_meson_array "${ARM64EC_MESON_FLAGS[@]}"
    printf '\n'
    printf 'cpp_args = '
    arm64ec_meson_array "${ARM64EC_MESON_FLAGS[@]}"
    printf '\n'
  } >> "$output"
}

arm64ec_verify_compile_flags() {
  local compile_commands="${1:?compile_commands.json path is required}"
  local flag

  for flag in "${ARM64EC_MESON_FLAGS[@]}"; do
    if ! grep -q -- "$flag" "$compile_commands"; then
      echo "::error::ARM64EC Meson compile_commands.json is missing $flag" >&2
      return 1
    fi
  done
}
