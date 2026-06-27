set -Eeuo pipefail

src_root="${1:?source root is required}"
wcp_dir="${2:?WCP dir is required}"
version_name="${3:?version name is required}"
out_path="${4:?output path is required}"
profile_sh="${5:?profile path is required}"

src_64="$src_root/x64"
src_32="$src_root/x32"

if [[ -d "$src_root/x64/bin" ]]; then
  src_64="$src_root/x64/bin"
fi

if [[ -d "$src_root/x32/bin" ]]; then
  src_32="$src_root/x32/bin"
elif [[ -d "$src_root/x86" ]]; then
  src_32="$src_root/x86"
fi

rm -rf "$wcp_dir"

PROFILE_SH="$profile_sh" \
bash "$(dirname "${BASH_SOURCE[0]}")/packing.sh" \
  "$src_64" \
  "$src_32" \
  "$wcp_dir" \
  "$version_name" \
  "$out_path"
