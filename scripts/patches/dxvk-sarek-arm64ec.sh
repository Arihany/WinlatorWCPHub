set -Eeuo pipefail

SRC_DIR="${1:-.}"
SRC_ABS="$(cd "$SRC_DIR" && pwd)"
MOCK_DIR="${2:-$SRC_ABS/../mock_inc}"

mkdir -p "$MOCK_DIR"
MOCK_DIR="$(cd "$MOCK_DIR" && pwd)"

ROOT="$SRC_ABS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SHIM_SRC="$SCRIPT_DIR/shims/sarek-sse-shim.h"

PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "::error::python3 (or \$PYTHON) not found in PATH"
  exit 1
fi

echo "== Sarek ARM64EC patch start =="
echo "Target MOCK_DIR: $MOCK_DIR"

if [[ ! -f "$REAL_SHIM_SRC" ]]; then
  echo "::error::NEON shim implementation not found at $REAL_SHIM_SRC"
  exit 1
fi

FINAL_HEADER="$MOCK_DIR/sarek_all_in_one.h"

# ---------------------------------------------------------------------------
# 1) shim header
# ---------------------------------------------------------------------------
cat > "$FINAL_HEADER" <<'EOF'
#pragma once

#ifndef __CRT__NO_INLINE
  #define __CRT__NO_INLINE 1
#endif

#if (defined(__arm64ec__) || defined(_M_ARM64EC)) && !defined(_ARM64EC_)
  #define _ARM64EC_ 1
#endif

#ifdef __cplusplus
  #define SAREK_ARM64EC 1
  #define _mm_pause _mm_pause_renamed_ignore
#endif
EOF

# merge NEON SSE shim
cat "$REAL_SHIM_SRC" >> "$FINAL_HEADER"

cat >> "$FINAL_HEADER" <<'EOF'
#ifdef __cplusplus
  #ifdef _mm_pause
    #undef _mm_pause
  #endif
  static inline void _mm_pause(void) {
    __asm__ __volatile__("yield" ::: "memory");
  }

  #if defined(__arm64ec__) || defined(_M_ARM64EC) || defined(SAREK_ARM64EC)
    #include <intrin.h>
    #ifndef bitScanForward
      #define bitScanForward  _BitScanForward
    #endif
    #ifndef bitScanReverse
      #define bitScanReverse  _BitScanReverse
    #endif
    #ifndef popcnt
      #define popcnt          __popcnt
    #endif
  #endif
#endif // __cplusplus
EOF

HEADERS=(
  "x86intrin.h" "immintrin.h" "emmintrin.h"
  "xmmintrin.h" "smmintrin.h" "tmmintrin.h"
  "pmmintrin.h" "nmmintrin.h" "wmmintrin.h"
  "ia32intrin.h" "hresetintrin.h" "uintrintrin.h" "usermsrintrin.h"
)

for hdr in "${HEADERS[@]}"; do
  printf '#include "sarek_all_in_one.h"\n' > "$MOCK_DIR/$hdr"
done

# ---------------------------------------------------------------------------
# 2) util_bit.h: x86 GNU asm tzcnt -> portable builtin
# ---------------------------------------------------------------------------
BIT_HEADER="$ROOT/src/util/util_bit.h"
if [[ -f "$BIT_HEADER" ]]; then
  "$PYTHON" - "$BIT_HEADER" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")

old = '''    #elif defined(__GNUC__) || defined(__clang__)
    uint32_t res;
    uint32_t tmp;
    asm (
      "mov  $32, %1;"
      "bsf   %2, %0;"
      "cmovz %1, %0;"
      : "=&r" (res), "=&r" (tmp)
      : "r" (n));
    return res;'''

new = '''    #elif defined(__GNUC__) || defined(__clang__)
    return n ? __builtin_ctz(n) : 32;'''

if old in text:
    text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    print("Patched util_bit.h: tzcnt GNU/Clang asm -> builtin")
else:
    print("::warning::tzcnt GNU/Clang asm pattern not found in util_bit.h")
PY
else
  echo "::warning::util_bit.h not found, skipping bitops patch"
fi

# ---------------------------------------------------------------------------
# 3) d3d9_device.cpp: x87 fnstcw/fldcw asm -> x86
# ---------------------------------------------------------------------------
D3D9_FILE="$ROOT/src/d3d9/d3d9_device.cpp"
if [[ -f "$D3D9_FILE" ]]; then
  "$PYTHON" - "$D3D9_FILE" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")

old_fnstcw = '    __asm__ __volatile__("fnstcw %0" : "=m" (*&control));'
old_fldcw  = '    __asm__ __volatile__("fldcw %0" : : "m" (*&control));'

new_fnstcw = '''#if defined(__i386__) || defined(_M_IX86)
    __asm__ __volatile__("fnstcw %0" : "=m" (*&control));
#else
    (void)control;
#endif'''

new_fldcw = '''#if defined(__i386__) || defined(_M_IX86)
    __asm__ __volatile__("fldcw %0" : : "m" (*&control));
#endif'''

changed = False

if old_fnstcw in text:
    text = text.replace(old_fnstcw, new_fnstcw)
    changed = True
else:
    print("::warning::fnstcw pattern not found in d3d9_device.cpp")

if old_fldcw in text:
    text = text.replace(old_fldcw, new_fldcw)
    changed = True
else:
    print("::warning::fldcw pattern not found in d3d9_device.cpp")

if changed:
    path.write_text(text, encoding="utf-8")
    print("Patched d3d9_device.cpp: guarded x87 asm with x86-only #if")
PY
else
  echo "::warning::d3d9_device.cpp not found, skipping D3D9 FPU patch"
fi

# ---------------------------------------------------------------------------
# 4) meson.build: dxvk_version vcs_tag dirty suffix -> -async-Arm64EC
# ---------------------------------------------------------------------------
MESON_FILE="$ROOT/meson.build"
if [[ -f "$MESON_FILE" ]]; then
  "$PYTHON" - "$MESON_FILE" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")

needle = "--dirty=-async'"
replacement = "--dirty=-async-Arm64EC'"

if needle in text:
    text = text.replace(needle, replacement, 1)
    path.write_text(text, encoding="utf-8")
    print("[OK] meson.build: vcs_tag dirty suffix -> -async-Arm64EC")
else:
    print("::warning::meson.build: vcs_tag --dirty=-async pattern not found; skip Arm64EC suffix patch")
PY
else
  echo "::warning::meson.build not found, skipping vcs_tag Arm64EC patch"
fi

# ---------------------------------------------------------------------------
# 5) version.h.in: legacy HUD tag '-arm64ec' (may be overridden by vcs_tag)
# ---------------------------------------------------------------------------
VER_IN="$ROOT/version.h.in"
if [[ -f "$VER_IN" ]]; then
  "$PYTHON" - "$VER_IN" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")

m = re.search(r'(#define\s+DXVK_VERSION\s+")([^"]*)(")', text)
if not m:
    print("::warning::version.h.in: DXVK_VERSION literal not found; skip HUD tag patch")
    sys.exit(0)

prefix, body, suffix = m.groups()

if 'arm64ec' in body.lower():
    print("[SKIP] version.h.in: DXVK_VERSION already contains arm64ec")
    sys.exit(0)

new_body = body + '-Arm64EC'
new_line = f'{prefix}{new_body}{suffix}'
new_text = text[:m.start()] + new_line + text[m.end():]
path.write_text(new_text, encoding="utf-8")
print(f"[OK] version.h.in: DXVK_VERSION -> \"{new_body}\"")
PY
else
  echo "::warning::version.h.in not found, skip HUD tag patch"
fi

# ---------------------------------------------------------------------------
# 5) export
# ---------------------------------------------------------------------------
export MOCK_DIR
export SHIM_FILE="$FINAL_HEADER"

echo "== Sarek ARM64EC patch done =="
