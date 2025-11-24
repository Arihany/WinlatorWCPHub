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

echo "== Sarek ARM64EC patch start (Precision Mode) =="

if [[ ! -f "$REAL_SHIM_SRC" ]]; then
  echo "::error::NEON shim implementation not found at $REAL_SHIM_SRC"
  exit 1
fi

FINAL_HEADER="$MOCK_DIR/sarek_all_in_one.h"

# ---------------------------------------------------------------------------
# 1) Shim Header Setup
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
#endif
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

if "inline uint32_t tzcnt(uint32_t n)" in text and "return n ? __builtin_ctz(n) : 32;" in text:
    print("[OK] util_bit.h: tzcnt already uses __builtin_ctz")
    sys.exit(0)

lines = text.splitlines(True)
out = []

inside_tzcnt = False
patched = False
i = 0

while i < len(lines):
    line = lines[i]

    # tzcnt 함수 시작 감지
    if "inline uint32_t tzcnt(uint32_t n)" in line:
        inside_tzcnt = True
        out.append(line)
        i += 1
        continue

    if inside_tzcnt and "#elif defined(__GNUC__) || defined(__clang__)" in line and not patched:
        out.append("    #elif defined(__GNUC__) || defined(__clang__)\n")
        out.append("    return n ? __builtin_ctz(n) : 32;\n")
        i += 1

        while i < len(lines) and "#else" not in lines[i]:
            i += 1

        patched = True
        continue

    out.append(line)

    if inside_tzcnt and "#endif" in line:
        inside_tzcnt = False

    i += 1

if not patched:
    if 'bsf   %2, %0;' in text:
        print("::error::[util_bit.h] tzcnt GNU inline asm still present; patch did not match structure.")
        sys.exit(1)
    else:
        print("[OK] util_bit.h: no GNU tzcnt asm to patch (probably updated upstream).")
        sys.exit(0)

path.write_text("".join(out), encoding="utf-8")
print("[OK] util_bit.h: replaced GNU/Clang tzcnt asm with __builtin_ctz")
PY
else
  echo "::warning::util_bit.h not found, skipping bitops patch"
fi

# ---------------------------------------------------------------------------
# 3) d3d9_device.cpp: ARM64EC-safe FPU setup + control init
# ---------------------------------------------------------------------------
D3D9_FILE="$ROOT/src/d3d9/d3d9_device.cpp"
if [[ -f "$D3D9_FILE" ]]; then
  "$PYTHON" - "$D3D9_FILE" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")

changed = False

old_cond = '#elif (defined(__GNUC__) || defined(__MINGW32__)) && (defined(__i386__) || defined(__x86_64__) || defined(__ia64))'
new_cond = old_cond + ' && !defined(__arm64ec__) && !defined(_M_ARM64EC)'

if old_cond in text and new_cond not in text:
    text = text.replace(old_cond, new_cond)
    print("[OK] d3d9_device.cpp: guarded GNU FPU asm against __arm64ec__")
    changed = True
elif new_cond in text:
    print("[OK] d3d9_device.cpp: FPU asm guard already applied")
else:
    print("::warning::d3d9_device.cpp: FPU asm #elif condition not found; layout may have changed")

if re.search(r'uint16_t\s+control\s*=\s*0\s*;', text):
    print("[OK] d3d9_device.cpp: control already initialized")
else:
    new_text, n = re.subn(r'(\s*)uint16_t\s+control\s*;', r'\1uint16_t control = 0;', text, count=1)
    if n > 0:
        text = new_text
        print("[OK] d3d9_device.cpp: initialized 'control' to 0")
        changed = True
    else:
        print("::warning::d3d9_device.cpp: 'uint16_t control;' declaration not found (layout changed?)")

if changed:
    path.write_text(text, encoding="utf-8")
PY
else
  echo "::error::d3d9_device.cpp not found!"
  exit 1
fi

# ---------------------------------------------------------------------------
# 4) dxvk_pipecompiler.h: Fix struct/class mismatch
# ---------------------------------------------------------------------------
PIPE_FILE="$ROOT/src/dxvk/dxvk_pipecompiler.h"
if [[ -f "$PIPE_FILE" ]]; then
  "$PYTHON" - "$PIPE_FILE" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")

has_class = ('class DxvkGraphicsPipelineStateInfo' in text)
has_struct = ('struct DxvkGraphicsPipelineStateInfo' in text)

if not has_class and has_struct:
    print("[OK] dxvk_pipecompiler.h: clean")
    sys.exit(0)

patterns = [
    (r'\bclass\s+DxvkGraphicsPipelineStateInfo\s*;', 'struct DxvkGraphicsPipelineStateInfo;'),
    (r'\bclass\s+DxvkComputePipelineStateInfo\s*;', 'struct DxvkComputePipelineStateInfo;'),
]

changed_count = 0
for pat, repl in patterns:
    new_text, n = re.subn(pat, repl, text)
    if n: changed_count += n; text = new_text

if changed_count > 0:
    path.write_text(text, encoding="utf-8")
    print(f"[OK] dxvk_pipecompiler.h: fixed {changed_count} declarations")
    sys.exit(0)

if has_class:
    print("::error::[CRITICAL] dxvk_pipecompiler.h: class forward decls persist!")
    sys.exit(1)

print("[OK] dxvk_pipecompiler.h: clean")
PY
else
  echo "::error::dxvk_pipecompiler.h not found!"
  exit 1
fi

# ---------------------------------------------------------------------------
# 5) meson.build & version.h.in (Tagging)
# ---------------------------------------------------------------------------
MESON_FILE="$ROOT/meson.build"
if [[ -f "$MESON_FILE" ]]; then
  "$PYTHON" - "$MESON_FILE" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")
if "--dirty=-async'" in text:
    text = text.replace("--dirty=-async'", "--dirty=-async-Arm64EC'")
    path.write_text(text, encoding="utf-8")
    print("[OK] meson.build updated")
PY
fi

VER_IN="$ROOT/version.h.in"
if [[ -f "$VER_IN" ]]; then
  "$PYTHON" - "$VER_IN" <<'PY'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")
m = re.search(r'(#define\s+DXVK_VERSION\s+")([^"]*)(")', text)
if m and 'arm64ec' not in m.group(2).lower():
    new_body = m.group(2) + '-Arm64EC'
    new_text = text[:m.start()] + f'{m.group(1)}{new_body}{m.group(3)}' + text[m.end():]
    path.write_text(new_text, encoding="utf-8")
    print(f"[OK] version.h.in -> {new_body}")
PY
fi

export MOCK_DIR
export SHIM_FILE="$FINAL_HEADER"
echo "== Sarek ARM64EC patch completed successfully =="
