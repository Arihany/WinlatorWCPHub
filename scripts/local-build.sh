set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/build-targets.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/local-build.sh --kind KIND [--versions CSV] [--setup]

Kinds:
  dxvk
  dxvk-legacy
  dxvk-arm64ec
  dxvk-gplasync
  dxvk-gplasync-arm64ec
  dxvk-sarek-dyasync
  dxvk-sarek-dyasync-arm64ec
  vkd3d-proton
  vkd3d-proton-arm64ec
  fexcore
  fexcore-unixlib

Versions:
  Empty means the preset list plus latest stable.
EOF
  local _k _label
  while read -r _k _label; do
    printf '  %-22s %s\n' "$_label" "$(default_versions_for_kind "$_k")"
  done <<'KINDS'
dxvk DXVK-x86/x64:
dxvk-legacy DXVK-legacy:
dxvk-arm64ec DXVK-ARM64EC:
dxvk-gplasync GPLAsync:
dxvk-sarek-dyasync Sarek:
vkd3d-proton VKD3D:
fexcore FEXCore:
fexcore-unixlib FEXCore-unixlib:
KINDS
  cat <<'EOF'
  (FEX tags accept a bare number or FEX-####. Below FEX-2607 is not built.)
  (fexcore = 2 PE DLLs; fexcore-unixlib = same DLLs plus 2 Android UnixLib SOs.)
  (DXVK 'proton' follows Valve's current dxvk gitlink; 'proton<major>' also asserts the major.)
  (dxvk-legacy builds the pre-1.9 releases with mingw-gcc; no clang release
   compiles them. Its packages are named and released exactly like dxvk.)

Examples:
  scripts/local-build.sh --setup --kind dxvk-arm64ec --versions 3.0
  scripts/local-build.sh --kind dxvk --versions 2.4.1-pre-reg
  scripts/local-build.sh --kind vkd3d-proton
  scripts/local-build.sh --kind dxvk-gplasync --versions 2.4.1-1-pre-reg,2.7.1,latest
  scripts/local-build.sh --kind dxvk-sarek-dyasync --versions 1.13.0,latest
  scripts/local-build.sh --kind dxvk-legacy --versions 1.5.5
  scripts/local-build.sh --kind fexcore --versions 2608
  scripts/local-build.sh --kind fexcore-unixlib --versions 2608
EOF
}

die() {
  echo "::error::$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

kind=""
versions=""
do_setup=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind)
      kind="${2:-}"
      shift 2
      ;;
    --versions|--version)
      versions="${2:-}"
      shift 2
      ;;
    --setup)
      do_setup=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$kind" ]] || { usage; die "--kind is required"; }

case "$kind" in
  dxvk|dxvk-legacy|dxvk-arm64ec|dxvk-gplasync|dxvk-gplasync-arm64ec|dxvk-sarek-dyasync|dxvk-sarek-dyasync-arm64ec|vkd3d-proton|vkd3d-proton-arm64ec|fexcore|fexcore-unixlib)
    ;;
  *)
    die "Unsupported kind: $kind"
    ;;
esac

source "$ROOT/scripts/toolchain-lock.sh"
export UNI_KIND="$kind"
TOOLCHAIN_PROFILE="$(wcp_toolchain_profile_for_kind "$kind")"

uses_rootcellar_toolchain() {
  [[ "$kind" == *-arm64ec || "$kind" == fexcore* ]]
}

maybe_relocate_to_native() {
  [[ "${WCP_NATIVE_ACTIVE:-}" == 1 ]] && return 0
  [[ "${WCP_NO_NATIVE:-}" == 1 ]] && return 0
  [[ "$ROOT" == /mnt/* ]] || return 0

  if ! command -v rsync >/dev/null 2>&1; then
    echo "::warning::rsync not found; building in place on slow mount $ROOT." >&2
    return 0
  fi

  local work="${WCP_WORK_DIR:-$HOME/.cache/wcphub-build}"
  echo "::notice::Slow mount detected ($ROOT)."
  echo "::notice::Relocating build to native fs: $work  (WCP_NO_NATIVE=1 to disable)"
  mkdir -p "$work"

  rsync -a --delete \
    --exclude='/src' --exclude='/pkg_temp' --exclude='/out' \
    --exclude='/.toolchains' --exclude='/.venv' --exclude='/*_WCP' \
    --exclude='/stage-*' --exclude='/patches' --exclude='/.git' \
    "$ROOT"/ "$work"/

  if ! $do_setup && [[ ! -x "$work/.venv/bin/meson" ]]; then
    echo "::notice::Initializing native toolchain/venv in $work (one-time)..."
    (cd "$work" && WCP_TOOLCHAIN_PROFILE="$TOOLCHAIN_PROFILE" bash scripts/setup-local-llvm-meson.sh)
  fi

  local child_args=(--kind "$kind")
  [[ -n "$versions" ]] && child_args+=(--versions "$versions")
  $do_setup && child_args+=(--setup)

  rm -rf "$work/out"

  WCP_NATIVE_ACTIVE=1 bash "$work/scripts/local-build.sh" "${child_args[@]}"
  local rc=$?

  if compgen -G "$work/out/*.wcp" >/dev/null 2>&1; then
    mkdir -p "$ROOT/out"
    cp -f "$work"/out/*.wcp "$ROOT/out/"
    echo "::notice::Copied .wcp artifacts back to $ROOT/out"
  fi
  exit $rc
}
maybe_relocate_to_native

# After relocation, so project-relative caches belong to the workspace that actually builds.
# Environment overrides still win
ROOTCELLAR_TOOLCHAIN_DIR="${ROOTCELLAR_TOOLCHAIN_DIR:-$(wcp_default_toolchain_dir "$ROOT" rootcellar)}"
UPSTREAM_TOOLCHAIN_DIR="${UPSTREAM_TOOLCHAIN_DIR:-$(wcp_default_toolchain_dir "$ROOT" upstream)}"
MINGW_GCC_TOOLCHAIN_DIR="${MINGW_GCC_TOOLCHAIN_DIR:-$(wcp_default_toolchain_dir "$ROOT" mingw-gcc)}"
FEX_TOOLCHAIN_DIR="${FEX_TOOLCHAIN_DIR:-$ROOTCELLAR_TOOLCHAIN_DIR}"
FEX_ANDROID_NDK_ROOT="${FEX_ANDROID_NDK_ROOT:-${ANDROID_NDK_ROOT:-$(wcp_default_android_ndk_dir "$ROOT")}}"
FEX_TOOLCHAIN_MANIFEST_SHA256="${FEX_TOOLCHAIN_MANIFEST_SHA256:-$WCP_ROOTCELLAR_TOOLCHAIN_MANIFEST_SHA256}"
ARM64EC_TOOLCHAIN_DIR="${ARM64EC_TOOLCHAIN_DIR:-$FEX_TOOLCHAIN_DIR}"
ARM64EC_TOOLCHAIN_MANIFEST_SHA256="${ARM64EC_TOOLCHAIN_MANIFEST_SHA256:-$FEX_TOOLCHAIN_MANIFEST_SHA256}"
export ROOTCELLAR_TOOLCHAIN_DIR UPSTREAM_TOOLCHAIN_DIR MINGW_GCC_TOOLCHAIN_DIR
export FEX_TOOLCHAIN_DIR FEX_ANDROID_NDK_ROOT FEX_TOOLCHAIN_MANIFEST_SHA256
export ARM64EC_TOOLCHAIN_DIR ARM64EC_TOOLCHAIN_MANIFEST_SHA256

if $do_setup; then
  bash "$ROOT/scripts/install-deps-ubuntu.sh"
  WCP_TOOLCHAIN_PROFILE="$TOOLCHAIN_PROFILE" bash "$ROOT/scripts/setup-local-llvm-meson.sh"
fi

if [[ -d "$ROOT/.venv/bin" ]]; then
  export PATH="$ROOT/.venv/bin:$PATH"
fi

if uses_rootcellar_toolchain; then
  export TOOLCHAIN_DIR="$ARM64EC_TOOLCHAIN_DIR"
elif [[ "$kind" == dxvk-legacy ]]; then
  export TOOLCHAIN_DIR="$MINGW_GCC_TOOLCHAIN_DIR"
else
  export TOOLCHAIN_DIR="$UPSTREAM_TOOLCHAIN_DIR"
fi
[[ -d "$TOOLCHAIN_DIR/bin" ]] ||
  die "Pinned $TOOLCHAIN_PROFILE toolchain is missing: $TOOLCHAIN_DIR (run with --setup)"
export PATH="$TOOLCHAIN_DIR/bin:$PATH"

if [[ "$kind" == fexcore* && "${TOOLCHAIN_DIR:-}" != "$FEX_TOOLCHAIN_DIR" ]]; then
  die "FEX requires the selected Proton-lineage toolchain '$FEX_TOOLCHAIN_DIR', active toolchain is '${TOOLCHAIN_DIR:-<none>}'"
fi

validate_arm64ec_toolchain() {
  local manifest="$ARM64EC_TOOLCHAIN_DIR/rootcellar-toolchain-manifest.json"
  local actual_sha256
  local tool

  command -v sha256sum >/dev/null 2>&1 || die "Missing command: sha256sum"
  [[ -f "$manifest" ]] || die "Missing RootCellar toolchain manifest: $manifest"

  actual_sha256="$(sha256sum "$manifest" | awk '{print $1}')"
  [[ "$actual_sha256" == "$ARM64EC_TOOLCHAIN_MANIFEST_SHA256" ]] \
    || die "ARM64EC toolchain manifest SHA-256 mismatch: expected $ARM64EC_TOOLCHAIN_MANIFEST_SHA256, got $actual_sha256"

  for tool in \
    arm64ec-w64-mingw32-gcc \
    arm64ec-w64-mingw32-g++ \
    arm64ec-w64-mingw32-ar \
    arm64ec-w64-mingw32-windres \
    i686-w64-mingw32-gcc \
    i686-w64-mingw32-g++ \
    i686-w64-mingw32-ar \
    i686-w64-mingw32-windres \
    llvm-readobj; do
    [[ -x "$ARM64EC_TOOLCHAIN_DIR/bin/$tool" ]] \
      || die "Missing $tool in RootCellar toolchain: $ARM64EC_TOOLCHAIN_DIR"
  done

  echo "::notice::Using RootCellar ARM64EC toolchain: $ARM64EC_TOOLCHAIN_DIR"
}

validate_mingw_gcc_toolchain() {
  local driver version

  for driver in x86_64-w64-mingw32-g++ i686-w64-mingw32-g++ \
                x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc; do
    [[ -x "$TOOLCHAIN_DIR/bin/$driver" ]] \
      || die "Missing $driver in mingw-gcc toolchain: $TOOLCHAIN_DIR (run with --setup)"
  done

  # Unpinned, these only compile under GCC.
  for driver in x86_64-w64-mingw32-g++ i686-w64-mingw32-g++; do
    version="$("$TOOLCHAIN_DIR/bin/$driver" --version 2>/dev/null | head -n1)"
    [[ "$version" == *"(GCC)"* ]] \
      || die "$driver is not GCC (got: ${version:-<none>}); dxvk-legacy refuses to fall back to another compiler"
  done

  MINGW_GCC_VERSION="$version"
  export MINGW_GCC_VERSION
  echo "::notice::Using mingw-gcc (unpinned by design): $MINGW_GCC_VERSION"
}

if [[ "$kind" == *-arm64ec ]]; then
  validate_arm64ec_toolchain
elif [[ "$kind" == dxvk-legacy ]]; then
  validate_mingw_gcc_toolchain
fi

need_cmd git
need_cmd curl
need_cmd jq
need_cmd meson
need_cmd ninja

# DXVK HUD string
dxvk_hud_version() {
  local profile_sh="$1" ver_name="$2"

  (
    WCP_VERSION_PREFIX=""
    WCP_VERSION_SUFFIX=""
    # shellcheck disable=SC1090
    source "$profile_sh"
    if declare -F wcp_version_name >/dev/null 2>&1; then
      printf 'v%s\n' "$(wcp_version_name "$ver_name")"
    else
      printf 'v%s%s%s\n' "$WCP_VERSION_PREFIX" "$ver_name" "$WCP_VERSION_SUFFIX"
    fi
  )
}

dxvk_stamp_version() {
  local version="$1"

  if [[ -f version.h.in ]] && ! grep -q '@VCS_TAG@' version.h.in; then
    sed -i "s/#define DXVK_VERSION \"[^\"]*\"/#define DXVK_VERSION \"${version}\"/" version.h.in
    echo "::notice::DXVK version stamped in version.h.in: $version"
    return 0
  fi

  # Drop --dirty
  if [[ -f meson.build ]]; then
    sed -i "s/\('git',[[:space:]]*'describe'\),[[:space:]]*'--dirty=[^']*'/\1/" meson.build
  fi

  git add -u
  git diff-index --quiet HEAD -- || git commit -qm "WCPHub build stamp"
  git tag --points-at HEAD | xargs -r git tag -d >/dev/null
  git tag -f -a "$version" -m "$version" >/dev/null
  echo "::notice::DXVK version stamped via git describe: $version"
}

repo_url_for_kind() {
  case "$1" in
    dxvk|dxvk-legacy|dxvk-arm64ec|dxvk-gplasync|dxvk-gplasync-arm64ec)
      printf '%s\n' "https://github.com/doitsujin/dxvk.git"
      ;;
    dxvk-sarek-dyasync|dxvk-sarek-dyasync-arm64ec)
      printf '%s\n' "https://github.com/pythonlover02/DXVK-Sarek.git"
      ;;
    vkd3d-proton|vkd3d-proton-arm64ec)
      printf '%s\n' "https://github.com/HansKristian-Work/vkd3d-proton.git"
      ;;
    fexcore|fexcore-unixlib)
      printf '%s\n' "https://github.com/FEX-Emu/FEX.git"
      ;;
  esac
}

rel_tag_for_kind() {
  case "$1" in
    dxvk|dxvk-legacy) printf '%s\n' "DXVK" ;;
    dxvk-arm64ec) printf '%s\n' "DXVK-ARM64EC" ;;
    dxvk-gplasync) printf '%s\n' "DXVK-GPLASYNC" ;;
    dxvk-gplasync-arm64ec) printf '%s\n' "DXVK-GPLASYNC-ARM64EC" ;;
    dxvk-sarek-dyasync) printf '%s\n' "DXVK-SAREK-ASYNC" ;;
    dxvk-sarek-dyasync-arm64ec) printf '%s\n' "DXVK-SAREK-ASYNC-ARM64EC" ;;
    vkd3d-proton) printf '%s\n' "VKD3D-PROTON" ;;
    vkd3d-proton-arm64ec) printf '%s\n' "VKD3D-PROTON-ARM64EC" ;;
    fexcore) printf '%s\n' "FEXCore" ;;
    fexcore-unixlib) printf '%s\n' "FEXCore-unixlib" ;;
  esac
}

filter_queue() {
  awk -F'|' '!seen[$3]++'
}

profile_for_artifact() {
  local kind="$1"
  # dxvk-legacy reuses the dxvk profile
  printf '%s\n' "../scripts/profiles/$(artifact_prefix_for_kind "$kind").sh"
}

latest_github_tag() {
  local repo_url="$1"
  git ls-remote --tags --refs "$repo_url" 'refs/tags/v*' \
    | awk -F/ '{print $NF}' \
    | grep -E '^v?[0-9]+(\.[0-9]+)*$' \
    | sort -V \
    | tail -n1
}

prepare_source() {
  local repo_url="$1"

  if [[ -d src/.git ]]; then
    local current
    current="$(git -C src config --get remote.origin.url || true)"
    if [[ "$current" != "$repo_url" ]]; then
      rm -rf src
    fi
  fi

  if [[ ! -d src/.git ]]; then
    rm -rf src
    git clone "$repo_url" src
    git -C src config user.name "Local Builder"
    git -C src config user.email "local@noreply"
  fi

  git -C src fetch --tags --force

  local stale
  stale="$(git -C src tag -l | grep -E '^[0-9a-f]{40}(-|$)' || true)"
  [[ -n "$stale" ]] && xargs -r git -C src tag -d <<<"$stale" >/dev/null
  return 0
}

standard_queue() {
  local kind="$1"
  local repo_url="$2"
  local requested="${versions:-}"

  if [[ -z "$requested" ]]; then
    requested="$(default_versions_for_kind "$kind")"
  fi

  IFS=',' read -ra reqs <<< "$requested"
  for raw in "${reqs[@]}"; do
    local req ref base filename
    req="$(echo "$raw" | xargs)"
    [[ -z "$req" ]] && continue

    local pre_reg_entry proton_entry
    if pre_reg_entry="$(pre_reg_queue_entry "$kind" "$req" 2>/dev/null)"; then
      IFS='|' read -r ref base filename _short <<< "$pre_reg_entry"
      printf '%s|%s|%s\n' "$ref" "$base" "$filename"
      continue
    elif proton_entry="$(proton_queue_entry "$kind" "$req")"; then
      IFS='|' read -r ref base filename _short <<< "$proton_entry"
      printf '%s|%s|%s\n' "$ref" "$base" "$filename"
      continue
    elif is_latest_token "$req"; then
      ref="$(latest_github_tag "$repo_url")"
      [[ -n "$ref" ]] || { echo "::warning::No latest stable tag found; skipping." >&2; continue; }
    else
      ref="$(normalize_github_version_ref "$kind" "$req")"
    fi

    if ! git -C src rev-parse -q --verify "refs/tags/$ref" >/dev/null; then
      echo "::warning::Tag '$ref' not found; skipping." >&2
      continue
    fi

    base="$(version_base_from_ref "$ref")"
    if [[ "$kind" == "dxvk-arm64ec" ]] && dxvk_version_is_x86_x64_only "$base"; then
      echo "::warning::DXVK $base is an x86/x64-only target in WCPHub; skipping ARM64EC." >&2
      continue
    fi
    if [[ "$kind" == dxvk-sarek-dyasync* ]] && ! sarek_version_supported "$base"; then
      echo "::warning::DXVK-Sarek $base is below the supported baseline $SAREK_MIN_VERSION; skipping." >&2
      continue
    fi
    # Compiler lines, not version ranges: keep each target on its own side.
    if [[ "$kind" == dxvk-legacy ]] && ! dxvk_version_is_legacy "$base"; then
      echo "::warning::DXVK $base is not a legacy target; build it with --kind dxvk." >&2
      continue
    fi
    if [[ "$kind" == dxvk ]] && dxvk_version_is_legacy "$base"; then
      echo "::warning::DXVK $base does not compile under clang; build it with --kind dxvk-legacy." >&2
      continue
    fi
    filename="$(artifact_prefix_for_kind "$kind")-${base}.wcp"
    printf '%s|%s|%s\n' "$ref" "$base" "$filename"
  done | filter_queue
}

gitlab_tags_file() {
  local out="$1"
  local page=1
  : > "$out"

  while :; do
    local json
    json="$(curl -fsSL "https://gitlab.com/api/v4/projects/Ph42oN%2Fdxvk-gplasync/repository/tags?per_page=100&page=${page}")"
    [[ "$(jq 'length' <<<"$json")" -eq 0 ]] && break
    jq -r '.[].name // empty' <<<"$json" >> "$out"
    page=$((page + 1))
  done
}

download_gplasync_patch() {
  local base="$1"
  local rev="$2"
  local patch_dir="$ROOT/patches"
  local base_url="${GPLASYNC_BASE_URL:-https://gitlab.com/Ph42oN/dxvk-gplasync/-/raw/v${base}-${rev}/patches}"
  local patch_name="dxvk-gplasync-${base}-${rev}.patch"
  local patch_local="$patch_dir/$patch_name"

  mkdir -p "$patch_dir"

  if ! curl -fsSL "${base_url}/${patch_name}" -o "$patch_local"; then
    if [[ "$base" == "2.4.1" && "$rev" == "1" ]]; then
      patch_name="dxvk-gplasync-2.4-1.patch"
      patch_local="$patch_dir/$patch_name"
      if ! curl -fsSL "${base_url}/${patch_name}" -o "$patch_local"; then
        return 1
      fi
    else
      return 1
    fi
  fi

  printf '%s\n' "$patch_local"
}

gplasync_queue() {
  local tags_file="$ROOT/.local-gplasync-tags.txt"
  local requested="${versions:-}"

  if [[ -z "$requested" ]]; then
    requested="$(default_versions_for_kind "$kind")"
  fi

  gitlab_tags_file "$tags_file"

  IFS=',' read -ra reqs <<< "$requested"
  for raw in "${reqs[@]}"; do
    local req tag_line base rev filename
    req="$(echo "$raw" | xargs)"
    [[ -z "$req" ]] && continue

    if is_gplasync_prereg_token "$req"; then
      filename="${kind}-2.4.1-1-pre-reg.wcp"
      printf '%s|2.4.1-1-pre-reg|%s|2.4.1|1\n' "$DXVK_PRE_REG_REF" "$filename"
      continue
    elif is_latest_token "$req"; then
      tag_line="$(
        grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9]+$' "$tags_file" \
          | sed -E 's/^v([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$/\1 \3/' \
          | sort -k1,1V -k2,2n \
          | tail -n1 || true
      )"
    elif [[ "$req" =~ ^v?([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$ ]]; then
      base="${BASH_REMATCH[1]}"
      rev="${BASH_REMATCH[3]}"
      tag_line="${base} ${rev}"
      grep -Fxq "v${base}-${rev}" "$tags_file" || {
        echo "::warning::GPLAsync tag v${base}-${rev} not found; skipping." >&2
        continue
      }
    elif [[ "$req" =~ ^v?([0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
      base="${BASH_REMATCH[1]}"
      tag_line="$(
        grep -E "^v${base}-[0-9]+$" "$tags_file" \
          | sed -E 's/^v([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$/\1 \3/' \
          | sort -k1,1V -k2,2n \
          | tail -n1 || true
      )"
    else
      echo "::warning::Invalid GPLAsync version '$req'; skipping." >&2
      continue
    fi

    [[ -n "$tag_line" ]] || { echo "::warning::No GPLAsync tag for '$req'; skipping." >&2; continue; }
    read -r base rev <<< "$tag_line"

    filename="${kind}-${base}-${rev}.wcp"
    printf 'v%s-%s|%s-%s|%s|%s|%s\n' "$base" "$rev" "$base" "$rev" "$filename" "$base" "$rev"
  done | filter_queue
}

prepare_dxvk_legacy_source() {
  local ref="$1"
  local inc="src/d3d11/d3d11_include.h"
  local cross_cpp="'-include','cstdint','-include','utility','-include','algorithm','-include','cstring','-include','limits'"

  # __MINGW64_VERSION_MAJOR guard
  if [[ -f "$inc" ]] && grep -q 'typedef enum D3D11_FORMAT_SUPPORT2' "$inc"; then
    echo "Removing unguarded D3D11_FORMAT_SUPPORT2 in $inc..."
    perl -i -0777 -pe 's/^\s*typedef\s+enum\s+D3D11_FORMAT_SUPPORT2\s*\{.*?\}\s*D3D11_FORMAT_SUPPORT2\s*;//ms' "$inc"
  fi

  # meson stopped reading compiler flags from [properties] after 0.56
  local f
  for f in build-win64.txt build-win32.txt; do
    [[ -f "$f" ]] || continue
    sed -i '/^\[built-in options\]/,$d' "$f"
    if [[ "$f" == build-win32.txt ]]; then
      printf '\n[built-in options]\ncpp_args = [%s,%s]\nc_args = [%s]\n' \
        "'-msse','-msse2'" "$cross_cpp" "'-msse','-msse2','-include','stdint.h'" >> "$f"
    else
      printf '\n[built-in options]\ncpp_args = [%s]\nc_args = [%s]\n' \
        "$cross_cpp" "'-include','stdint.h'" >> "$f"
    fi
  done

  echo "::notice::Prepared DXVK legacy source $ref for mingw-gcc."
}

# Validated before the queue is built
dxvk_validate_proton_requests() {
  local kind="$1"
  local requested="${versions:-}"
  local -a _preqs
  local raw req

  [[ "$kind" == dxvk || "$kind" == dxvk-arm64ec ]] || return 0
  [[ -n "$requested" ]] || requested="$(default_versions_for_kind "$kind")"

  IFS=',' read -ra _preqs <<< "$requested"
  for raw in "${_preqs[@]}"; do
    req="$(echo "$raw" | xargs)"
    [[ -z "$req" ]] && continue

    if is_dxvk_proton_token "$req"; then
      dxvk_proton_resolve || die "Could not resolve the DXVK Proton line; refusing to build"
      dxvk_proton_selfcheck || die "Resolved DXVK Proton line is inconsistent; refusing to build"

      local _want
      _want="$(dxvk_proton_requested_major "$req")"
      [[ -z "$_want" || "$_want" == "$DXVK_PROTON_MAJOR" ]] \
        || die "Requested proton${_want}, but $DXVK_PROTON_REPO now defaults to $DXVK_PROTON_BRANCH (proton${DXVK_PROTON_MAJOR}). Use 'proton' to follow the current line."
    elif is_stale_dxvk_proton_token "$req"; then
      die "DXVK Proton token '$req' pins a specific commit, which this line no longer supports. Use 'proton' (or 'proton<major>' to assert the major)."
    fi
  done
}

# Cross-checks
verify_dxvk_proton_pin() {
  local branch="proton-${DXVK_PROTON_MAJOR}"
  local actual_base ahead

  if [[ -f RELEASE ]]; then
    actual_base="$(tr -d ' \t\r\n' < RELEASE)"
  else
    actual_base="$(sed -n "s/^project('dxvk'.*version[[:space:]]*:[[:space:]]*'\([^']*\)'.*/\1/p" meson.build | head -n1)"
  fi

  [[ "$actual_base" == "$DXVK_PROTON_BASE" ]] \
    || die "Resolved Proton base '$DXVK_PROTON_BASE' but the checked-out tree reports '$actual_base' (ref $DXVK_PROTON_SHORT)"

  if git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
    git merge-base --is-ancestor "$DXVK_PROTON_REF" "refs/remotes/origin/$branch" \
      || die "Resolved gitlink $DXVK_PROTON_SHORT is not contained in origin/$branch; the major derived from $DXVK_PROTON_BRANCH does not describe it"

    # Not a bump signal: the rule follows Valve's gitlink, not this branch tip.
    ahead="$(git rev-list --count "${DXVK_PROTON_REF}..refs/remotes/origin/$branch")"
    if [[ "$ahead" != "0" ]]; then
      echo "::notice::origin/$branch is $ahead commits ahead of the pin; check whether Valve moved the Proton gitlink." >&2
    fi
  else
    echo "::warning::Branch origin/$branch not found; skipped the DXVK_PROTON_MAJOR containment check." >&2
  fi

  echo "::notice::DXVK Proton line verified against the tree: $DXVK_PROTON_BASE @ $DXVK_PROTON_SHORT on $branch"
}

build_standard() {
  local kind="$1"
  local repo_url="$2"
  local rel_tag="$3"
  local arm64ec=false

  [[ "$kind" == *-arm64ec ]] && arm64ec=true

  dxvk_validate_proton_requests "$kind"

  prepare_source "$repo_url"
  mapfile -t queue < <(standard_queue "$kind" "$repo_url")
  [[ "${#queue[@]}" -gt 0 ]] || die "Nothing to build."

  mkdir -p out src/out

  cd src
  while IFS='|' read -r ref ver_name filename; do
    [[ -n "$ref" ]] || continue
    echo "::group::Building $kind $ref"

    git clean -fdx
    git checkout -f "$ref"
    git submodule sync --recursive
    git submodule update --init --recursive

    if [[ "$ref" == "$DXVK_PROTON_REF" ]]; then
      verify_dxvk_proton_pin
    fi

    if [[ "$kind" == dxvk* ]]; then
      if [[ "$kind" == dxvk-legacy ]]; then
        prepare_dxvk_legacy_source "$ref"
      else
        bash ../scripts/patches/dxvk.sh .
      fi
    fi

    if [[ "$kind" == dxvk* ]]; then
      dxvk_stamp_version "$(dxvk_hud_version "$(profile_for_artifact "$kind")" "$ver_name")"
    fi

    if $arm64ec; then
      UNI_KIND="$kind" REL_TAG_STABLE="$rel_tag" PROFILE_SH="$(profile_for_artifact "$kind" "$filename")" \
      bash ../scripts/guts-arm64ec.sh "$ref" "$ver_name" "$filename"
    else
      local pkg_root="../pkg_temp"
      local pkg_name="$(artifact_prefix_for_kind "$kind")-${ref}"
      rm -rf "${pkg_root}/${pkg_name}"
      mkdir -p "$pkg_root"

      ./package-release.sh "$ref" "$pkg_root" --no-package

      local src_root="${pkg_root}/${pkg_name}"
      bash ../scripts/pack-release-tree.sh \
        "$src_root" \
        "../${rel_tag}_WCP" \
        "$ver_name" \
        "../out/${filename}" \
        "$(profile_for_artifact "$kind" "$filename")"
    fi

    echo "::endgroup::"
  done < <(printf '%s\n' "${queue[@]}")
}

build_gplasync() {
  local kind="$1"
  local repo_url="$2"
  local rel_tag="$3"
  local arm64ec=false

  [[ "$kind" == *-arm64ec ]] && arm64ec=true

  prepare_source "$repo_url"
  mapfile -t queue < <(gplasync_queue)
  [[ "${#queue[@]}" -gt 0 ]] || die "Nothing to build."

  mkdir -p out src/out patches

  cd src
  while IFS='|' read -r gpl_tag ver_name filename base rev; do
    [[ -n "$gpl_tag" ]] || continue
    local dxvk_ref="v${base}"
    local patch_local

    if [[ "$ver_name" == *-pre-reg ]]; then
      dxvk_ref="$DXVK_PRE_REG_REF"
      if [[ -f "$ROOT/scripts/patches/dxvk-gplasync-2.4.1-1-pre-reg.patch" ]]; then
        patch_local="$ROOT/scripts/patches/dxvk-gplasync-2.4.1-1-pre-reg.patch"
      else
        patch_local=""
      fi
    else
      patch_local="$(download_gplasync_patch "$base" "$rev" || true)"
    fi
    if [[ -z "$patch_local" ]]; then
      echo "::warning::GPLAsync patch not found for ${base}-${rev}; skipping." >&2
      continue
    fi

    echo "::group::Building $kind $gpl_tag"

    git clean -fdx
    git checkout -f "$dxvk_ref"
    git submodule sync --recursive
    git submodule update --init --recursive

    bash ../scripts/patches/dxvk.sh .
    patch -p1 < "$patch_local"

    dxvk_stamp_version "$(dxvk_hud_version "$(profile_for_artifact "$kind")" "$ver_name")"

    if $arm64ec; then
      UNI_KIND="$kind" REL_TAG_STABLE="$rel_tag" PROFILE_SH="$(profile_for_artifact "$kind" "$filename")" \
      bash ../scripts/guts-arm64ec.sh "$gpl_tag" "$ver_name" "$filename"
    else
      local pkg_root="../pkg_temp"
      rm -rf "$pkg_root"
      mkdir -p "$pkg_root"

      local pkg_version="gplasync-${gpl_tag}"
      ./package-release.sh "$pkg_version" "$pkg_root" --no-package

      local src_root="${pkg_root}/dxvk-${pkg_version}"
      bash ../scripts/pack-release-tree.sh \
        "$src_root" \
        "../${rel_tag}_WCP" \
        "$ver_name" \
        "../out/${filename}" \
        "$(profile_for_artifact "$kind" "$filename")"
    fi

    echo "::endgroup::"
  done < <(printf '%s\n' "${queue[@]}")
}

build_sarek() {
  local kind="$1"
  local repo_url="$2"
  local rel_tag="$3"
  local arm64ec=false

  [[ "$kind" == *-arm64ec ]] && arm64ec=true

  prepare_source "$repo_url"
  need_cmd make
  local upstream_branch="${UPSTREAM_BRANCH:-main}"
  git -C src fetch origin "$upstream_branch" --force
  mapfile -t queue < <(standard_queue "$kind" "$repo_url")
  [[ "${#queue[@]}" -gt 0 ]] || die "Nothing to build."

  mkdir -p out src/out

  cd src
  while IFS='|' read -r ref ver_name filename; do
    [[ -n "$ref" ]] || continue
    echo "::group::Building $kind $ref"

    local tag_sha
    tag_sha="$(git rev-parse "$ref^{commit}")"
    git merge-base --is-ancestor "$tag_sha" "origin/$upstream_branch" \
      || die "DXVK-Sarek ref '$ref' is not contained in origin/$upstream_branch"

    git clean -fdx
    git checkout -f "$tag_sha"
    git submodule sync --recursive
    git submodule update --init --recursive
    [[ -f Makefile ]] || die "DXVK-Sarek $ref does not provide the 1.13.0+ Makefile build contract"

    bash ../scripts/patches/dxvk.sh .

    if [[ -f meson_options.txt ]]; then
      sed -i "/option('enable_ddraw'/s/value : true/value : false/" meson_options.txt
    fi
    dxvk_stamp_version "$(dxvk_hud_version "$(profile_for_artifact "$kind")" "$ver_name")"

    if $arm64ec; then
      UNI_KIND="$kind" REL_TAG_STABLE="$rel_tag" \
      bash ../scripts/guts-arm64ec.sh "$ref" "$ver_name" "$filename"
    else
      local src_root="build"
      make

      [[ -d "$src_root/x64" && -d "$src_root/x32" ]] \
        || die "DXVK-Sarek $ref did not produce x64/x32 release trees under $src_root"
      bash ../scripts/pack-release-tree.sh \
        "$src_root" \
        "../${rel_tag}_WCP" \
        "$ver_name" \
        "../out/${filename}" \
        "../scripts/profiles/${kind}.sh"
    fi

    echo "::endgroup::"
  done < <(printf '%s\n' "${queue[@]}")
}

fexcore_latest_tag() {
  local repo_url="$1"
  git ls-remote --tags --refs "$repo_url" 'refs/tags/FEX-*' \
    | awk -F/ '{print $NF}' \
    | grep -E '^FEX-[0-9]+$' \
    | sort -V \
    | tail -n1
}

fexcore_queue() {
  local kind="$1" repo_url="$2"
  local requested="${versions:-}"
  [[ -z "$requested" ]] && requested="$(default_versions_for_kind "$kind")"

  IFS=',' read -ra reqs <<< "$requested"
  for raw in "${reqs[@]}"; do
    local req ref base filename
    req="$(echo "$raw" | xargs)"
    [[ -z "$req" ]] && continue

    if is_latest_token "$req"; then
      ref="$(fexcore_latest_tag "$repo_url")"
      [[ -n "$ref" ]] || { echo "::warning::No latest FEX tag found; skipping." >&2; continue; }
    else
      ref="$(normalize_github_version_ref "$kind" "$req")"   # 2605 -> FEX-2605
    fi

    if ! git -C src rev-parse -q --verify "refs/tags/$ref" >/dev/null; then
      echo "::warning::Tag '$ref' not found; skipping." >&2
      continue
    fi

    if ! fexcore_version_supported "$ref"; then
      echo "::warning::FEX ${ref#FEX-} is below the supported baseline $FEXCORE_MIN_VERSION; skipping." >&2
      continue
    fi

    base="${ref#FEX-}"
    if fexcore_kind_has_unixlib "$kind"; then
      filename="FEXCore-unixlib-${base}.wcp"
    else
      filename="FEXCore-${base}.wcp"
    fi
    printf '%s|%s|%s\n' "$ref" "$base" "$filename"
  done | awk -F'|' '!seen[$3]++'
}

build_fexcore() {
  local kind="$1"
  local repo_url="$2"
  local rel_tag="$3"

  need_cmd cmake
  need_cmd sha256sum
  source "$ROOT/scripts/arm64ec-common.sh"

  local toolchain_manifest="$FEX_TOOLCHAIN_DIR/rootcellar-toolchain-manifest.json"
  local toolchain_manifest_sha256

  [[ -f "$toolchain_manifest" ]] \
    || die "Missing Proton-lineage toolchain manifest: $toolchain_manifest"
  toolchain_manifest_sha256="$(sha256sum "$toolchain_manifest" | awk '{print $1}')"
  [[ "$toolchain_manifest_sha256" == "$FEX_TOOLCHAIN_MANIFEST_SHA256" ]] \
    || die "FEX toolchain manifest SHA-256 mismatch: expected $FEX_TOOLCHAIN_MANIFEST_SHA256, got $toolchain_manifest_sha256"

  [[ -x "$TOOLCHAIN_DIR/bin/arm64ec-w64-mingw32-clang++" ]] \
    || die "Missing ARM64EC compiler in $TOOLCHAIN_DIR"
  [[ -x "$TOOLCHAIN_DIR/bin/aarch64-w64-mingw32-clang++" ]] \
    || die "Missing AArch64 MinGW compiler in $TOOLCHAIN_DIR"
  # The NDK only feeds the UnixLib so, a DLL-only build must not require it
  if fexcore_kind_has_unixlib "$kind"; then
    [[ -f "$FEX_ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" ]] \
      || die "Android NDK toolchain not found: $FEX_ANDROID_NDK_ROOT"
  fi

  prepare_source "$repo_url"
  mapfile -t queue < <(fexcore_queue "$kind" "$repo_url")
  [[ "${#queue[@]}" -gt 0 ]] || die "Nothing to build."

  mkdir -p out

  local arch_flags
  arch_flags="$(arm64ec_cmake_flags)"

  fex_build_arch() {
    local triple="$1" dest="$2"
    local bdir="src/build-${triple}"
    rm -rf "$bdir"
    mkdir -p "$bdir"
    ( cd "$bdir"
      cmake -GNinja -Wno-dev \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=../Data/CMake/toolchain_mingw.cmake \
        -DCMAKE_C_FLAGS="${arch_flags}" \
        -DCMAKE_CXX_FLAGS="${arch_flags}" \
        -DCMAKE_INSTALL_LIBDIR=/usr/lib/wine/aarch64-windows \
        -DENABLE_JEMALLOC_GLIBC_ALLOC=False \
        -DENABLE_FEXCORE_PROFILER=True \
        -DENABLE_LTO=False \
        -DTUNE_CPU=none \
        -DRANGES_NATIVE=OFF \
        -DOVERRIDE_VERSION="${ref}" \
        -DOVERRIDE_HASH="$(git -C "$ROOT/src" rev-parse --short=7 HEAD)" \
        -DMINGW_TRIPLE="${triple}-w64-mingw32" \
        -DBUILD_TESTING=False \
        -DCMAKE_INSTALL_PREFIX=/usr ..
      ninja
      DESTDIR="$dest" ninja install
    )
  }

  fex_build_unixlib() {
    local dest="$1"
    local bdir="src/build-android-aarch64-unixlib"
    rm -rf "$bdir"
    cmake -S src/Source/Windows/UnixLib -B "$bdir" -GNinja -Wno-dev \
      -DCMAKE_TOOLCHAIN_FILE="$FEX_ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DCMAKE_CXX_FLAGS="${arch_flags} -include $ROOT/scripts/fex-android-shm-compat.h -g0 -ffile-prefix-map=$ROOT=/usr/src/wcphub -fdebug-prefix-map=$ROOT=/usr/src/wcphub" \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=/usr/lib/wine/aarch64-unix \
      -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM=android-35 \
      -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
      -DENABLE_FEXCORE_PROFILER=True \
      -DENABLE_LTO=False \
      -DBUILD_TESTING=False \
      -DTUNE_CPU=none \
      -DRANGES_NATIVE=OFF \
      -DOVERRIDE_VERSION="${ref}" \
      -DOVERRIDE_HASH="$(git -C "$ROOT/src" rev-parse --short=7 HEAD)"
    ninja -C "$bdir"
    DESTDIR="$dest" ninja -C "$bdir" install
  }

  while IFS='|' read -r ref ver_name filename; do
    [[ -n "$ref" ]] || continue

    # The kinds differ only in whether the UnixLib soo are built and packed
    # profile.json is identical for both.
    local with_unixlib=false
    if fexcore_kind_has_unixlib "$kind"; then
      with_unixlib=true
      echo "::group::Building $kind $ref (2 PE DLLs + 2 Android UnixLib SOs)"
    else
      echo "::group::Building $kind $ref (2 PE DLLs, DLL-only)"
    fi

    ( cd src
      git clean -fdx
      git checkout -f "$ref"
      git submodule sync --recursive
      git submodule update --init --recursive
      if [[ "$with_unixlib" == true ]]; then
        git apply "$ROOT/scripts/patches/fex-android-unixlib.patch"
      fi
    )

    rm -rf stage-ec stage-wo stage-unix stage-wcp
    mkdir -p stage-wcp/wine/aarch64-windows

    fex_build_arch "arm64ec" "$ROOT/stage-ec"
    fex_build_arch "aarch64" "$ROOT/stage-wo"

    cp "$ROOT/stage-ec/usr/lib/wine/aarch64-windows/libarm64ecfex.dll" \
      "$ROOT/stage-wcp/wine/aarch64-windows/"
    cp "$ROOT/stage-wo/usr/lib/wine/aarch64-windows/libwow64fex.dll" \
      "$ROOT/stage-wcp/wine/aarch64-windows/"

    local guard_dirs=("$ROOT/src/build-arm64ec" "$ROOT/src/build-aarch64")

    if $with_unixlib; then
      mkdir -p stage-wcp/wine/aarch64-unix
      fex_build_unixlib "$ROOT/stage-unix"

      local ndk_strip
      ndk_strip="$FEX_ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
      [[ -x "$ndk_strip" ]] || die "Android NDK llvm-strip not found: $ndk_strip"
      "$ndk_strip" --strip-unneeded \
        "$ROOT/stage-unix/usr/lib/wine/aarch64-unix/libarm64ecfex.so" \
        "$ROOT/stage-unix/usr/lib/wine/aarch64-unix/libwow64fex.so"

      cp "$ROOT/stage-unix/usr/lib/wine/aarch64-unix/libarm64ecfex.so" \
        "$ROOT/stage-wcp/wine/aarch64-unix/"
      cp "$ROOT/stage-unix/usr/lib/wine/aarch64-unix/libwow64fex.so" \
        "$ROOT/stage-wcp/wine/aarch64-unix/"

      guard_dirs+=("$ROOT/src/build-android-aarch64-unixlib")
    fi

    FEX_EXPECT_UNIXLIB="$($with_unixlib && echo 1 || echo 0)" \
    bash "$ROOT/scripts/fex-artifact-guard.sh" \
      "$ROOT/stage-wcp" \
      "${guard_dirs[@]}"

    local source_commit submodules_json files_json toolchain_version ndk_revision shim_sha256 patch_sha256
    source_commit="$(git -C "$ROOT/src" rev-parse HEAD)"
    submodules_json="$(git -C "$ROOT/src" submodule status --recursive | jq -Rsc '
      split("\n") | map(select(length > 0)) |
      map(capture("^[ +\\-U]?(?<commit>[0-9a-f]+) (?<path>[^ ]+)") | {path, commit})')"
    files_json="$(find "$ROOT/stage-wcp/wine" -type f -print0 | LC_ALL=C sort -z |
      while IFS= read -r -d '' artifact; do
        jq -n --arg path "${artifact#"$ROOT/stage-wcp/"}" \
          --arg sha256 "$(sha256sum "$artifact" | awk '{print $1}')" \
          --argjson size "$(stat -c %s "$artifact")" '{path: $path, size: $size, sha256: $sha256}'
      done | jq -sc '.')"
    toolchain_version="$("$TOOLCHAIN_DIR/bin/clang" --version | head -n1)"
    if $with_unixlib; then
      ndk_revision="$(sed -n 's/^Pkg\.Revision = //p' "$FEX_ANDROID_NDK_ROOT/source.properties" | tr -d '\r')"
      [[ -n "$ndk_revision" ]] || die "Could not resolve Android NDK revision"
      shim_sha256="$(sha256sum "$ROOT/scripts/fex-android-shm-compat.h" | awk '{print $1}')"
      patch_sha256="$(sha256sum "$ROOT/scripts/patches/fex-android-unixlib.patch" | awk '{print $1}')"
    else
      ndk_revision=""
      shim_sha256=""
      patch_sha256=""
    fi

    jq -n \
      --arg version "$ver_name" \
      --arg ref "$ref" \
      --arg commit "$source_commit" \
      --arg toolchainId "$WCP_ROOTCELLAR_TOOLCHAIN_ID" \
      --arg toolchainVersion "$toolchain_version" \
      --arg toolchainManifestSha256 "$toolchain_manifest_sha256" \
      --arg archFlags "$arch_flags" \
      --arg ndkRevision "$ndk_revision" \
      --arg shimSha256 "$shim_sha256" \
      --arg patchSha256 "$patch_sha256" \
      --argjson unixLib "$with_unixlib" \
      --argjson submodules "$submodules_json" \
      --argjson files "$files_json" \
      '{schemaVersion: 1, version: $version, source: {ref: $ref, commit: $commit, submodules: $submodules},
        toolchain: {id: $toolchainId, family: "proton-llvm-mingw", version: $toolchainVersion,
          manifestSha256: $toolchainManifestSha256},
        android: (if $unixLib then
            {unixLib: true, ndkRevision: $ndkRevision, abi: "arm64-v8a", api: 35,
             maxPageSize: 16384, shmCompatibility: "memfd-owner",
             shimSha256: $shimSha256, unixLibPatchSha256: $patchSha256}
          else {unixLib: false} end),
        cmake: {buildType: "Release", enableFEXCoreProfiler: true, enableLTO: false,
          buildTesting: false, tuneCPU: "none", rangesNative: false, archFlags: $archFlags}, files: $files}' \
      > "$ROOT/stage-wcp/build-manifest.json"

    PROFILE_SH="$ROOT/scripts/profiles/${kind}.sh" \
    bash "$ROOT/scripts/packing.sh" \
      "$ROOT/stage-wcp" \
      "-" \
      "$ROOT/pkg_temp/${kind}" \
      "$ver_name" \
      "$ROOT/out/${filename}"

    echo "::endgroup::"
  done < <(printf '%s\n' "${queue[@]}")
}

repo_url="$(repo_url_for_kind "$kind")"
rel_tag="$(rel_tag_for_kind "$kind")"

case "$kind" in
  dxvk-gplasync|dxvk-gplasync-arm64ec)
    build_gplasync "$kind" "$repo_url" "$rel_tag"
    ;;
  dxvk-sarek-dyasync|dxvk-sarek-dyasync-arm64ec)
    build_sarek "$kind" "$repo_url" "$rel_tag"
    ;;
  fexcore|fexcore-unixlib)
    build_fexcore "$kind" "$repo_url" "$rel_tag"
    ;;
  *)
    build_standard "$kind" "$repo_url" "$rel_tag"
    ;;
esac

echo "Local artifacts are in: $ROOT/out"
