#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

die()  { echo "::error::$*" >&2; exit 1; }
warn() { echo "::warning::$*" >&2; }

[[ $# -ge 1 ]] || die "Usage: log.sh <log_files...> [output_file]"

OUT_DEFAULT="_logs/build-summary.log"
OUT="$OUT_DEFAULT"

ARGS=("$@")
LAST_IDX=$((${#ARGS[@]} - 1))
LAST_ARG="${ARGS[$LAST_IDX]}"

if [[ $# -ge 2 && ! -e "$LAST_ARG" && "$LAST_ARG" != *"*"* ]]; then
  OUT="$LAST_ARG"
  unset "ARGS[$LAST_IDX]"
fi

LOG_FILES=("${ARGS[@]}")
mkdir -p -- "$(dirname -- "$OUT")"

TMP_COMBINED="$(mktemp)"
trap 'rm -f "$TMP_COMBINED"' EXIT

echo "Summarizing logs to: $OUT" >&2

FOUND_LOGS=false
for f in "${LOG_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    FOUND_LOGS=true
    base="$(basename -- "$f")"
    echo "  Reading: $f" >&2

    awk -v base="$base" '{ print base " | " $0 } END { print "" }' "$f" >> "$TMP_COMBINED"
  else
    [[ "$f" == *"*"* ]] || warn "Log file not found: $f"
  fi
done

if [[ "$FOUND_LOGS" == false ]]; then
  warn "No valid log files found. Creating empty summary."
  printf 'No logs found.\n' > "$OUT"
  exit 0
fi

dedup_lines() { awk '!seen[$0]++'; }

emit_section() {
  local title="$1"
  local regex="$2"

  {
    echo "========================================"
    echo " $title"
    echo "========================================"
  } >> "$OUT"

  if grep -iaE "$regex" "$TMP_COMBINED" | dedup_lines >> "$OUT"; then
    :
  else
    echo "(none)" >> "$OUT"
  fi

  echo >> "$OUT"
  echo >> "$OUT"
}

{
  echo "########################################"
  echo "  BUILD LOG SUMMARY"
  echo "  Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo "########################################"
  echo
} > "$OUT"

emit_section "ERRORS & FAILURES" \
  '(^|[[:space:]])error[: ]|failed with exit code|ninja: build stopped|collect2: error|undefined reference|LINK : fatal error|CMAKE Error|MSB[0-9]+: error|recipe for target.*failed|FAILED|Failure|Assertion.*failed|Test suite failed|AddressSanitizer|UBSan|TSAN'

emit_section "WARNINGS" \
  'warning[: ]|deprecated|may be uninitialized|possibly uninitialized|C4[0-9]{3}: warning|D9[0-9]{3}: warning'

emit_section "NOTICES & GENERAL INFO" \
  '::notice::|Current version:|Already exists|Skipping\.|Selected channel:|Auto-detected latest (tag|version)|Prune Old Assets|Deleting old asset|Pruned asset|Packed WCP|Checking for old assets'

echo "::notice::Log summary created at $OUT"
