set -Eeuo pipefail
export LC_ALL=C

if [[ "$#" -lt 1 ]]; then
  echo "::error::Usage: log.sh <log_files...> [output_file]" >&2
  exit 1
fi

OUT_DEFAULT="_logs/build-summary.log"
OUT="$OUT_DEFAULT"

ARGS=("$@")
LAST_IDX=$((${#ARGS[@]} - 1))
LAST_ARG="${ARGS[$LAST_IDX]}"

if [[ "$#" -ge 2 && ! -e "$LAST_ARG" && "$LAST_ARG" != *"*"* ]]; then
  OUT="$LAST_ARG"
  unset 'ARGS[LAST_IDX]'
fi

LOG_FILES=("${ARGS[@]}")

mkdir -p "$(dirname "$OUT")"

TMP_COMBINED="$(mktemp)"
trap 'rm -f "$TMP_COMBINED"' EXIT

echo "Summarizing logs to: $OUT" >&2

FOUND_LOGS=false
for f in "${LOG_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    FOUND_LOGS=true
    base="$(basename "$f")"
    echo "  Reading: $f" >&2

    while IFS= read -r line; do
      printf '%s | %s\n' "$base" "$line"
    done < "$f" >> "$TMP_COMBINED"

    echo >> "$TMP_COMBINED"
  else
    if [[ "$f" != *"*"* ]]; then
      echo "::warning::Log file not found: $f" >&2
    fi
  fi
done

if [[ "$FOUND_LOGS" != "true" ]]; then
  echo "::warning::No valid log files found. Creating empty summary." >&2
  echo "No logs found." > "$OUT"
  exit 0
fi

filter_logs() {
  if [[ "${LOG_COUNT:-0}" == "1" ]]; then
    awk '
      {
        if (!seen[$0]++) order[++n] = $0
        c[$0]++
      }
      END {
        for (i = 1; i <= n; i++) {
          k = order[i]
          if (c[k] > 1) printf "[x%d] %s\n", c[k], k
          else print k
        }
      }
    '
  else
    awk '!seen[$0]++'
  fi
}

emit_section() {
  local title="$1"
  local regex="$2"
  local tmp_sec
  tmp_sec="$(mktemp)"

  {
    echo "========================================"
    echo " $title"
    echo "========================================"
  } >> "$OUT"

  if grep -iaE "$regex" "$TMP_COMBINED" > "$tmp_sec"; then
    filter_logs < "$tmp_sec" >> "$OUT"
  else
    echo "(none)" >> "$OUT"
  fi

  rm -f "$tmp_sec"
  echo >> "$OUT"
  echo >> "$OUT"
}

{
  echo "########################################"
  echo "  BUILD LOG LANDMINE SUMMARY"
  echo "  Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo "########################################"
  echo
} > "$OUT"

emit_section "RISKY WARNINGS (compiler/linker/static analysis)" \
  'warning[: ]|deprecated|may be uninitialized|possibly uninitialized|ignored|incompatible pointer|int conversion|format( |-).*|sign-compare|strict-aliasing|array-bounds|stringop-overflow|maybe-uninitialized|returns address|use of uninitialized|overflow|truncat|loss of data|relocation|textrel|DT_TEXTREL|lto|unsafe|undefined behavior|UBSan|ASan|TSan|AddressSanitizer|LeakSanitizer|runtime error:'

emit_section "FALLBACKS & DISABLED FEATURES (silent performance/compat hits)" \
  'fallback|falling back|using fallback|disabled|disable(d)? by|not enabled|without (support|feature)|feature.*unavailable|unsupported|not supported|will not be used|skipping (feature|opt|accel)|slow path|scalar fallback|generic fallback|no(ne)?on|no sse|neon.*not|sse.*not|simd.*not|using builtin|using system|prefer.*but'

emit_section "DEPS & TOOLCHAIN NOTES (missing tools, partial builds, env drift)" \
  'not found|could not find|unable to find|missing (dependency|tool|package)|pkg-config|cmake.*(could not|not find)|meson.*(not found|failed)|ninja: warning|python.*warning|llvm-strip not found|skipping symbol stripping|strip.*skipping|submodule.*(not|missing)|git.*detached|shallow|fetch-depth|rate limit|token|auth|permission|denied'

emit_section "ARTIFACT / PACKAGING / VERIFICATION (what actually got produced)" \
  'Packed WCP|Packing WCP|profile\.json|Merge mode|conflict|refusing to overwrite|Machine:|AARCH64|ARM64|PE32\+?|ELF|Unexpected MACHINE|not found.*\.dll|dll.*not found|version(Name|Code)|Selected channel:|Auto-detected latest|Current version:|Already exists|Prune Old Assets|Deleting old asset|Pruned asset|Queued:|-> Queued:|Skipped|-> Skipped|Strategy:|Configuration'

emit_section "GENERAL INFO (useful breadcrumbs)" \
  '::notice::|::warning::|::group::|::endgroup::|Using cached|cache hit|cache miss|download|extract|install|configure|cmake -S|meson setup|ninja -C|strip-all|strip-unneeded'

echo "::notice::Log summary created at $OUT"
