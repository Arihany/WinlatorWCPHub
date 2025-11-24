#!/usr/bin/env bash
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

echo "== Sarek ARM64EC patch start (Hard-Fail Mode) =="
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

if '__builtin_ctz' in text:
    print("[OK] util_bit.h: already uses __builtin_ctz; no patch needed")
    sys.exit(0)

if old in text:
    text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    print("Patched util_bit.h: tzcnt GNU/Clang asm -> builtin")
    sys.exit(0)

if 'asm' in text and 'bsf' in text:
    print("::error::[CRITICAL] util_bit.h: x86 asm present but pattern not matched; manual fix required")
    sys.exit(1)

print("[OK] util_bit.h: no x86 asm / no patch required")
PY
else
  echo "::error::util_bit.h not found!"
  exit 1
fi

# ---------------------------------------------------------------------------
# 3) d3d9_device.cpp: initialize FPU control word
# ---------------------------------------------------------------------------
D3D9_FILE="$ROOT/src/d3d9/d3d9_device.cpp"
if [[ -f "$D3D9_FILE" ]]; then
  "$PYTHON" - "$D3D9_FILE" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")

check_pattern = r'uint16_t\s+control\s*=\s*0\s*;'
if re.search(check_pattern, text):
    print("[OK] d3d9_device.cpp: already initialized (control = 0)")
    sys.exit(0)

pattern = r'(\s*)uint16_t\s+control\s*;'
replacement = r'\1uint16_t control = 0;'

new_text, n = re.subn(pattern, replacement, text, count=1)

if n > 0:
    path.write_text(new_text, encoding="utf-8")
    print("Patched d3d9_device.cpp: initialized FPU control word")
else:
    print("::error::[CRITICAL] d3d9_device.cpp: 'control' variable declaration not found; FPU patch failed")
    sys.exit(1)
PY
else
  echo "::error::d3d9_device.cpp not found!"
  exit 1
fi

# ---------------------------------------------------------------------------
# 4) dxvk_pipecompiler.h: fix struct/class mismatched-tags
# ---------------------------------------------------------------------------
PIPE_FILE="$ROOT/src/dxvk/dxvk_pipecompiler.h"
if [[ -f "$PIPE_FILE" ]]; then
  "$PYTHON" - "$PIPE_FILE" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")

has_class = ('class DxvkGraphicsPipelineStateInfo' in text) or ('class DxvkComputePipelineStateInfo' in text)
has_struct = ('struct DxvkGraphicsPipelineStateInfo' in text) or ('struct DxvkComputePipelineStateInfo' in text)

if not has_class and has_struct:
    print("[OK] dxvk_pipecompiler.h: already uses struct forward decls; no patch needed")
    sys.exit(0)

patterns = [
    (r'\bclass\s+DxvkGraphicsPipelineStateInfo\s*;', 'struct DxvkGraphicsPipelineStateInfo;'),
    (r'\bclass\s+DxvkComputePipelineStateInfo\s*;', 'struct DxvkComputePipelineStateInfo;'),
]

changed_count = 0
for pat, repl in patterns:
    new_text, n = re.subn(pat, repl, text)
    if n:
        changed_count += n
        text = new_text

if changed_count > 0:
    path.write_text(text, encoding="utf-8")
    print(f"[OK] dxvk_pipecompiler.h: forward decls switched to struct ({changed_count} changes)")
    sys.exit(0)

if has_class:
    print("::error::[CRITICAL] dxvk_pipecompiler.h: class forward decls still present; patch pattern mismatch")
    sys.exit(1)

print("[OK] dxvk_pipecompiler.h: no matching class forward decls; no patch needed")
PY
else
  echo "::error::dxvk_pipecompiler.h not found!"
  exit 1
fi

# ---------------------------------------------------------------------------
# 5) meson.build Tagging
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
    print("[OK] meson.build: vcs_tag suffix updated")
else:
    print("::warning::meson.build: vcs_tag pattern not found")
PY
fi

# ---------------------------------------------------------------------------
# 7) export
# ---------------------------------------------------------------------------
export MOCK_DIR
export SHIM_FILE="$FINAL_HEADER"

echo "== Sarek ARM64EC patch completed successfully =="
