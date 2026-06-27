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
  dxvk-arm64ec
  dxvk-gplasync
  dxvk-gplasync-arm64ec
  dxvk-sarek-dyasync
  dxvk-sarek-dyasync-arm64ec
  vkd3d-proton
  vkd3d-proton-arm64ec
  fexcore

Versions:
  Empty means the preset list plus latest stable.
  DXVK presets:          2.4.1-pre-reg,2.4.1,2.5.3,2.6.2,2.7.1,3.0,latest
  GPLAsync presets:      2.4.1-1-pre-reg,2.4.1,2.5.3,2.6.2,2.7.1,3.0,latest
  Sarek presets:         1.12.0,latest
  VKD3D presets:         2.14.1,3.0.1,latest
  FEXCore presets:       2605,latest   (FEX tags; bare number or FEX-#### accepted)

  DXVK, DXVK-ARM64EC, GPLAsync, and GPLAsync-ARM64EC builds also emit
  -binsem artifacts for supported DXVK 2.7.1+ targets. Sarek is excluded.

Examples:
  scripts/local-build.sh --setup --kind dxvk-arm64ec --versions 3.0
  scripts/local-build.sh --kind dxvk --versions 2.4.1-pre-reg
  scripts/local-build.sh --kind vkd3d-proton
  scripts/local-build.sh --kind dxvk-gplasync --versions 2.4.1-1-pre-reg,2.7.1,latest
  scripts/local-build.sh --kind dxvk-sarek-dyasync --versions 1.12.0,latest
  scripts/local-build.sh --kind fexcore --versions 2605,latest
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
  dxvk|dxvk-arm64ec|dxvk-gplasync|dxvk-gplasync-arm64ec|dxvk-sarek-dyasync|dxvk-sarek-dyasync-arm64ec|vkd3d-proton|vkd3d-proton-arm64ec|fexcore)
    ;;
  *)
    die "Unsupported kind: $kind"
    ;;
esac

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
    ( cd "$work" && bash scripts/setup-local-llvm-meson.sh )
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

if $do_setup; then
  bash "$ROOT/scripts/install-deps-ubuntu.sh"
  bash "$ROOT/scripts/setup-local-llvm-meson.sh"
fi

if [[ -d "$ROOT/.venv/bin" ]]; then
  export PATH="$ROOT/.venv/bin:$PATH"
fi

if [[ -n "${TOOLCHAIN_DIR:-}" && -d "$TOOLCHAIN_DIR/bin" ]]; then
  export PATH="$TOOLCHAIN_DIR/bin:$PATH"
elif [[ -d "$ROOT/.toolchains" ]]; then
  latest_toolchain="$(find "$ROOT/.toolchains" -maxdepth 1 -type d -name 'llvm-mingw-*' | sort -V | tail -n1 || true)"
  if [[ -n "$latest_toolchain" && -d "$latest_toolchain/bin" ]]; then
    export TOOLCHAIN_DIR="$latest_toolchain"
    export PATH="$latest_toolchain/bin:$PATH"
  fi
elif [[ -d /opt/llvm-mingw/bin ]]; then
  export TOOLCHAIN_DIR="/opt/llvm-mingw"
  export PATH="/opt/llvm-mingw/bin:$PATH"
fi

need_cmd git
need_cmd curl
need_cmd jq
need_cmd meson
need_cmd ninja

repo_url_for_kind() {
  case "$1" in
    dxvk|dxvk-arm64ec|dxvk-gplasync|dxvk-gplasync-arm64ec)
      printf '%s\n' "https://github.com/doitsujin/dxvk.git"
      ;;
    dxvk-sarek-dyasync|dxvk-sarek-dyasync-arm64ec)
      printf '%s\n' "https://github.com/pythonlover02/DXVK-Sarek.git"
      ;;
    vkd3d-proton|vkd3d-proton-arm64ec)
      printf '%s\n' "https://github.com/HansKristian-Work/vkd3d-proton.git"
      ;;
    fexcore)
      printf '%s\n' "https://github.com/FEX-Emu/FEX.git"
      ;;
  esac
}

rel_tag_for_kind() {
  case "$1" in
    dxvk) printf '%s\n' "DXVK" ;;
    dxvk-arm64ec) printf '%s\n' "DXVK-ARM64EC" ;;
    dxvk-gplasync) printf '%s\n' "DXVK-GPLASYNC" ;;
    dxvk-gplasync-arm64ec) printf '%s\n' "DXVK-GPLASYNC-ARM64EC" ;;
    dxvk-sarek-dyasync) printf '%s\n' "DXVK-SAREK-ASYNC" ;;
    dxvk-sarek-dyasync-arm64ec) printf '%s\n' "DXVK-SAREK-ASYNC-ARM64EC" ;;
    vkd3d-proton) printf '%s\n' "VKD3D-PROTON" ;;
    vkd3d-proton-arm64ec) printf '%s\n' "VKD3D-PROTON-ARM64EC" ;;
    fexcore) printf '%s\n' "FEXCore" ;;
  esac
}

is_binsem_artifact() {
  [[ "$1" == *-binsem.wcp ]]
}

filter_queue() {
  awk -F'|' -v only_binsem="${WCP_ONLY_BINSEM:-0}" '
    !seen[$3]++ {
      if (only_binsem == "1" && $3 !~ /-binsem\.wcp$/) next
      print
    }
  '
}

profile_for_artifact() {
  local kind="$1"
  local filename="$2"
  local suffix=""

  if is_binsem_artifact "$filename"; then
    suffix="-binsem"
  fi

  printf '%s\n' "../scripts/profiles/${kind}${suffix}.sh"
}

apply_binsem_patch_if_needed() {
  local filename="$1"

  if is_binsem_artifact "$filename"; then
    echo "Applying DXVK binary semaphore fallback patch..."
    patch -p1 < ../scripts/patches/dxvk_binsem.patch
  fi
}

latest_github_tag() {
  local repo_url="$1"
  git ls-remote --tags --refs "$repo_url" 'refs/tags/v*' \
    | awk -F/ '{print $NF}' \
    | grep -E '^v?[0-9]' \
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

    local pre_reg_entry
    if pre_reg_entry="$(pre_reg_queue_entry "$kind" "$req" 2>/dev/null)"; then
      IFS='|' read -r ref base filename _short <<< "$pre_reg_entry"
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
    filename="${kind}-${base}.wcp"
    printf '%s|%s|%s\n' "$ref" "$base" "$filename"

    if dxvk_binsem_kind_supported "$kind" && dxvk_binsem_supported_base "$base"; then
      printf '%s|%s|%s-binsem.wcp\n' "$ref" "$base" "${kind}-${base}"
    fi
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
  local dirty_suffix="$3"
  local patch_dir="$ROOT/patches"
  local base_url="${GPLASYNC_BASE_URL:-https://gitlab.com/Ph42oN/dxvk-gplasync/-/raw/main/patches}"
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

  sed -i "s/--dirty=-[^']*gplasync'/--dirty=-${dirty_suffix}'/g" "$patch_local" || true
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

    if dxvk_binsem_kind_supported "$kind" && dxvk_binsem_supported_base "$base"; then
      printf 'v%s-%s|%s-%s|%s-binsem.wcp|%s|%s\n' "$base" "$rev" "$base" "$rev" "${kind}-${base}-${rev}" "$base" "$rev"
    fi
  done | filter_queue
}

build_standard() {
  local kind="$1"
  local repo_url="$2"
  local rel_tag="$3"
  local arm64ec=false

  [[ "$kind" == *-arm64ec ]] && arm64ec=true

  prepare_source "$repo_url"
  mapfile -t queue < <(standard_queue "$kind" "$repo_url")
  [[ "${#queue[@]}" -gt 0 ]] || die "Nothing to build."

  mkdir -p out src/out

  cd src
  while IFS='|' read -r ref ver_name filename; do
    [[ -n "$ref" ]] || continue
    echo "::group::Building $kind $ref"

    git reset --hard
    git clean -fdx
    git checkout -f "$ref"
    git submodule sync --recursive
    git submodule update --init --recursive

    if [[ "$kind" == dxvk* ]]; then
      bash ../scripts/patches/dxvk.sh .
      apply_binsem_patch_if_needed "$filename"
      if ! git diff-index --quiet HEAD --; then
        git add -u
        git commit -m "Apply local patches for $ref"
      fi
    fi

    if $arm64ec; then
      if [[ "$kind" == dxvk* ]]; then
        local new_tag="${ref}-arm64ec"
        is_binsem_artifact "$filename" && new_tag="${new_tag}-binsem"
        git tag -a -f "$new_tag" -m "ARM64EC-Build"
      fi

      UNI_KIND="$kind" REL_TAG_STABLE="$rel_tag" PROFILE_SH="$(profile_for_artifact "$kind" "$filename")" \
      bash ../scripts/guts-arm64ec.sh "$ref" "$ver_name" "$filename"
    else
      local pkg_root="../pkg_temp"
      rm -rf "${pkg_root}/${kind}-${ref}"
      mkdir -p "$pkg_root"

      if [[ "$kind" == dxvk ]]; then
        git tag -d "$ref" 2>/dev/null || true
        git tag -a -f "$ref" -m "Clean Build"
      fi

      ./package-release.sh "$ref" "$pkg_root" --no-package

      local src_root="${pkg_root}/${kind}-${ref}"
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
  local dirty_suffix="gplasync"

  [[ "$kind" == *-arm64ec ]] && {
    arm64ec=true
    dirty_suffix="gplasync-arm64ec"
  }

  prepare_source "$repo_url"
  mapfile -t queue < <(gplasync_queue)
  [[ "${#queue[@]}" -gt 0 ]] || die "Nothing to build."

  mkdir -p out src/out patches

  cd src
  while IFS='|' read -r gpl_tag ver_name filename base rev; do
    [[ -n "$gpl_tag" ]] || continue
    local dxvk_ref="v${base}"
    local patch_local
    local artifact_dirty_suffix="$dirty_suffix"

    if is_binsem_artifact "$filename"; then
      artifact_dirty_suffix="${artifact_dirty_suffix}-binsem"
    fi

    if [[ "$ver_name" == *-pre-reg ]]; then
      dxvk_ref="$DXVK_PRE_REG_REF"
      if [[ -f "$ROOT/scripts/patches/dxvk-gplasync-2.4.1-1-pre-reg.patch" ]]; then
        patch_local="$ROOT/patches/dxvk-gplasync-2.4.1-1-pre-reg-${artifact_dirty_suffix}.patch"
        cp "$ROOT/scripts/patches/dxvk-gplasync-2.4.1-1-pre-reg.patch" "$patch_local"
        sed -i "s/--dirty=-[^']*gplasync'/--dirty=-${artifact_dirty_suffix}'/g" "$patch_local" || true
      else
        patch_local=""
      fi
    else
      patch_local="$(download_gplasync_patch "$base" "$rev" "$artifact_dirty_suffix" || true)"
    fi
    if [[ -z "$patch_local" ]]; then
      echo "::warning::GPLAsync patch not found for ${base}-${rev}; skipping." >&2
      continue
    fi

    echo "::group::Building $kind $gpl_tag"

    git reset --hard
    git clean -fdx
    git checkout -f "$dxvk_ref"
    git submodule sync --recursive
    git submodule update --init --recursive

    bash ../scripts/patches/dxvk.sh .
    patch -p1 < "$patch_local"
    apply_binsem_patch_if_needed "$filename"

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
  local ver_suffix="dyasync"

  [[ "$kind" == *-arm64ec ]] && {
    arm64ec=true
    ver_suffix="dyasync-arm64ec"
  }

  prepare_source "$repo_url"
  mapfile -t queue < <(standard_queue "$kind" "$repo_url")
  [[ "${#queue[@]}" -gt 0 ]] || die "Nothing to build."

  mkdir -p out src/out

  cd src
  while IFS='|' read -r ref ver_name filename; do
    [[ -n "$ref" ]] || continue
    echo "::group::Building $kind $ref"

    git reset --hard
    git clean -fdx
    git checkout -f "$ref"
    git submodule sync --recursive
    git submodule update --init --recursive

    bash ../scripts/patches/dxvk.sh .

    if [[ -f meson_options.txt ]]; then
      sed -i "/option('enable_ddraw'/s/value : true/value : false/" meson_options.txt
    fi
    sed -i 's/#define DXVK_VERSION "[^"]*"/#define DXVK_VERSION "'"${ref}-${ver_suffix}"'"/' version.h.in

    if $arm64ec; then
      UNI_KIND="$kind" REL_TAG_STABLE="$rel_tag" \
      bash ../scripts/guts-arm64ec.sh "$ref" "$ver_name" "$filename"
    else
      local pkg_root="../pkg_temp"
      rm -rf "$pkg_root"
      mkdir -p "$pkg_root"

      ./package-release.sh "$ref" "$pkg_root" --no-package

      local src_root="${pkg_root}/dxvk-${ref}"
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
    | grep -E '^FEX-[0-9]' \
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

    base="${ref#FEX-}"
    filename="FEXCore-${base}.wcp"
    printf '%s|%s|%s\n' "$ref" "$base" "$filename"
  done | awk -F'|' '!seen[$3]++'
}

build_fexcore() {
  local kind="$1"
  local repo_url="$2"
  local rel_tag="$3"

  need_cmd cmake
  source "$ROOT/scripts/arm64ec-common.sh"

  prepare_source "$repo_url"
  mapfile -t queue < <(fexcore_queue "$kind" "$repo_url")
  [[ "${#queue[@]}" -gt 0 ]] || die "Nothing to build."

  mkdir -p out

  local arch_flags
  arch_flags="$(arm64ec_cpu_flags)"

  fex_build_arch() {
    local triple="$1" dest="$2"
    local bdir="src/build-${triple}"
    rm -rf "$bdir"
    mkdir -p "$bdir"
    ( cd "$bdir"
      cmake -GNinja -Wno-dev \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=../Data/CMake/toolchain_mingw.cmake \
        -DCMAKE_C_FLAGS="${arch_flags}" \
        -DCMAKE_CXX_FLAGS="${arch_flags}" \
        -DCMAKE_INSTALL_LIBDIR=/usr/lib/wine/aarch64-windows \
        -DENABLE_JEMALLOC_GLIBC_ALLOC=False \
        -DENABLE_LTO=False \
        -DTUNE_CPU=none \
        -DMINGW_TRIPLE="${triple}-w64-mingw32" \
        -DBUILD_TESTING=False \
        -DCMAKE_INSTALL_PREFIX=/usr ..
      ninja
      DESTDIR="$dest" ninja install
    )
  }

  while IFS='|' read -r ref ver_name filename; do
    [[ -n "$ref" ]] || continue
    echo "::group::Building $kind $ref"

    ( cd src
      git reset --hard
      git clean -fdx
      git checkout -f "$ref"
      git submodule sync --recursive
      git submodule update --init --recursive
    )

    rm -rf stage-ec stage-wo stage-wcp
    mkdir -p stage-wcp

    fex_build_arch "arm64ec" "$ROOT/stage-ec"
    fex_build_arch "aarch64" "$ROOT/stage-wo"

    # FEX layout: all arm64ec + aarch64 DLLs live together under system32.
    for st in stage-ec stage-wo; do
      [[ -d "$st" ]] && find "$st" -type f -name '*.dll' -exec cp {} stage-wcp/ \;
    done
    find stage-wcp -maxdepth 1 -type f -name '*.dll' | grep -q . \
      || die "No DLLs produced for $kind $ref"

    PROFILE_SH="$ROOT/scripts/profiles/${kind}.sh" \
    bash "$ROOT/scripts/packing.sh" \
      "$ROOT/stage-wcp" \
      "-" \
      "$ROOT/pkg_temp/fexcore" \
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
  fexcore)
    build_fexcore "$kind" "$repo_url" "$rel_tag"
    ;;
  *)
    build_standard "$kind" "$repo_url" "$rel_tag"
    ;;
esac

echo "Local artifacts are in: $ROOT/out"
