set -Eeuo pipefail
IFS=$'\n\t'

REL_TAG="${REL_TAG:?REL_TAG not set}"
REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY must be set}}"
ARTIFACT_GLOB="${ARTIFACT_GLOB:?ARTIFACT_GLOB not set}"
VERSION_PREFIX="${VERSION_PREFIX:-}"

NOTES="${NOTES:-RELEASE_NOTES.md}"
BODY="${BODY:-}"
BODY_KEYS="${BODY_KEYS:-}"

REL_SKIP_BODY="${REL_SKIP_BODY:-0}"

if [[ "$REL_SKIP_BODY" != 1 && -z "$BODY" && -n "$BODY_KEYS" ]]; then
  source "$(dirname "$0")/release-notes.sh"
  IFS=' ' read -ra _note_keys <<<"$BODY_KEYS"
  BODY="$(render_notes "${_note_keys[@]}")"
fi

: >"$NOTES"
if [[ -n "$BODY" ]]; then
  printf '%s\n' "$BODY" >"$NOTES"
fi

mapfile -t artifacts < <(compgen -G "$ARTIFACT_GLOB" | sort -V)

if ((${#artifacts[@]} == 0)); then
  echo "No artifacts."
  exit 0
fi

latest="${artifacts[$((${#artifacts[@]} - 1))]}"
ver="${latest##*/}"

if [[ -n "$VERSION_PREFIX" ]]; then
  ver="${ver#"$VERSION_PREFIX"}"
fi
ver="${ver%.wcp}"

printf -- '- Current version: %s\n' "$ver" >>"$NOTES"

if [[ "$REL_SKIP_BODY" == 1 ]]; then
  gh release view "$REL_TAG" --repo "$REPO" >/dev/null 2>&1 \
    || gh release create "$REL_TAG" --repo "$REPO" -t "$REL_TAG" --notes ""
elif gh release view "$REL_TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release edit "$REL_TAG" --repo "$REPO" -t "$REL_TAG" -F "$NOTES"
else
  gh release create "$REL_TAG" --repo "$REPO" -t "$REL_TAG" -F "$NOTES"
fi

gh release upload "$REL_TAG" "${artifacts[@]}" --repo "$REPO" --clobber
