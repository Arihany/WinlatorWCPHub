set -Eeuo pipefail
export LC_ALL=C

if [[ "$#" -lt 1 ]]; then
  echo "::error::Usage: log-summarize.sh <log_files...> [output_file]"
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
    echo "  Reading: $f" >&2
    {
      echo "----------------------------------------------------------------"
      echo ">>> SOURCE: $(basename "$f")"
      echo "----------------------------------------------------------------"
      cat "$f"
      echo
    } >> "$TMP_COMBINED"
  else
    if [[ "$f" != *"*"* ]]; then
      echo "::warning::Log file not found: $f" >&2
    fi
  fi
done

if [ "$FOUND_LOGS" = false ]; then
  echo "::warning::No valid log files found. Creating empty summary."
  echo "No logs found." > "$OUT"
  exit 0
fi

filter_logs() {
  awk '!seen[$0]++' | head -n 200
}

emit_section() {
  local title="$1"
  local regex="$2"

  {
    echo "========================================"
    echo " $title"
    echo "========================================"
  } >> "$OUT"

  if grep -qiaE "$regex" "$TMP_COMBINED"; then
    grep -iaE "$regex" "$TMP_COMBINED" | filter_logs >> "$OUT"
  else
    echo "(none)" >> "$OUT"
  fi

  echo -e "\n" >> "$OUT"
}

{
  echo "########################################"
  echo "  BUILD LOG SUMMARY"
  echo "  Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo "########################################"
  echo
} > "$OUT"

# 1. Errors
emit_section "ERRORS & FAILURES" \
  '(^|[[:space:]])error[: ]|failed with exit code|ninja: build stopped|collect2: error|undefined reference|LINK : fatal error|CMAKE Error|MSB[0-9]+: error|recipe for target.*failed|FAILED|Failure|Assertion.*failed|Test suite failed|AddressSanitizer|UBSan|TSAN'

# 2. Warnings
emit_section "WARNINGS" \
  'warning[: ]|deprecated|may be uninitialized|possibly uninitialized|C4[0-9]{3}: warning|D9[0-9]{3}: warning'

# 3. Notices
emit_section "NOTICES & GENERAL INFO" \
  '::notice::|Current version:|Already exists|Skipping\.|Selected channel:|Auto-detected latest (tag|version)|Prune Old Assets|Deleting old asset|Pruned asset|Packed WCP|Checking for old assets'

echo "::notice::Log summary created at $OUT"
