set -Eeuo pipefail

die() { echo "::error::$*" >&2; exit 1; }

stage="${1:?staged FEX root is required}"
shift
build_dirs=("$@")

# 1 = full Proton layout (2 PE DLLs + 2 Android UnixLib)
# 0 = DLL-only (FEX release predates Source/Windows/UnixLib)
expect_unixlib="${FEX_EXPECT_UNIXLIB:-1}"

arm64ec_dll="$stage/wine/aarch64-windows/libarm64ecfex.dll"
wow64_dll="$stage/wine/aarch64-windows/libwow64fex.dll"
arm64ec_so="$stage/wine/aarch64-unix/libarm64ecfex.so"
wow64_so="$stage/wine/aarch64-unix/libwow64fex.so"

expected=("$arm64ec_dll" "$wow64_dll")
expected_count=2
if [[ "$expect_unixlib" == "1" ]]; then
  expected+=("$arm64ec_so" "$wow64_so")
  expected_count=4
fi

for artifact in "${expected[@]}"; do
  [[ -s "$artifact" ]] || die "Missing or empty FEX artifact: $artifact"
done

mapfile -t actual < <(find "$stage/wine" -type f | LC_ALL=C sort)
[[ "${#actual[@]}" -eq "$expected_count" ]] \
  || die "FEX stage must contain exactly $expected_count binaries, found ${#actual[@]}"

arm64ec_headers="$(llvm-readobj --file-headers "$arm64ec_dll")"
grep -q 'Format: COFF-ARM64EC' <<< "$arm64ec_headers" \
  || die "libarm64ecfex.dll is not ARM64EC"
arm64ec_load_config="$(llvm-readobj --coff-load-config "$arm64ec_dll")"
grep -q 'CHPEMetadataPointer: 0x[1-9A-Fa-f]' <<< "$arm64ec_load_config" \
  || die "libarm64ecfex.dll has no CHPE metadata pointer"
grep -q 'CodeMap \[' <<< "$arm64ec_load_config" \
  || die "libarm64ecfex.dll has no ARM64EC code map"

llvm-readobj --file-headers "$wow64_dll" | grep -q 'Format: COFF-ARM64$' \
  || die "libwow64fex.dll is not AArch64 PE"

if [[ "$expect_unixlib" == "1" ]]; then
  for elf in "$arm64ec_so" "$wow64_so"; do
    readelf -h "$elf" | grep -q 'Machine:.*AArch64' || die "$(basename "$elf") is not AArch64 ELF"
    if readelf --version-info "$elf" 2>/dev/null | grep -q 'GLIBC_'; then
      die "$(basename "$elf") references glibc"
    fi
    while read -r align; do
      (( align >= 0x4000 )) || die "$(basename "$elf") has PT_LOAD alignment below 16 KiB: $align"
    done < <(readelf -lW "$elf" | awk '$1 == "LOAD" {print $NF}')
  done
fi

for build_dir in "${build_dirs[@]}"; do
  cache="$build_dir/CMakeCache.txt"
  [[ -f "$cache" ]] || die "Missing CMake cache: $cache"
  grep -q '^RANGES_NATIVE:.*=OFF$' "$cache" || die "RANGES_NATIVE is not OFF in $build_dir"
done

if [[ "$expect_unixlib" == "1" ]]; then
  echo "::notice::FEX artifact guard passed: ARM64EC DLL, AArch64 DLL, and two 16 KiB AArch64 Android SOs."
else
  echo "::notice::FEX artifact guard passed (DLL-only): ARM64EC DLL and AArch64 DLL."
fi
