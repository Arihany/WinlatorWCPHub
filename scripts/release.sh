#  /\_/\
# (=•ᆽ•=)づ✈

set -Eeuo pipefail

REL_TAG="${REL_TAG:?REL_TAG not set}"
REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY must be set}}"
ARTIFACT_GLOB="${ARTIFACT_GLOB:?ARTIFACT_GLOB not set}"
VERSION_PREFIX="${VERSION_PREFIX:-}"

# Optional
REL_TAG_NIGHTLY="${REL_TAG_NIGHTLY:-}"
UPSTREAM_REPO="${UPSTREAM_REPO:-}"
REF="${REF:-}"

# Optional fallback = REL_TAG
REL_TITLE="${REL_TITLE:-$REL_TAG}"

NOTES="${NOTES:-RELEASE_NOTES.md}"
BODY="${BODY:-}"

: > "$NOTES"

if [[ -n "$BODY" ]]; then
  printf "%s\n" "$BODY" > "$NOTES"
fi

if compgen -G "$ARTIFACT_GLOB" > /dev/null; then
  LATEST=$(ls $ARTIFACT_GLOB | sort -V | tail -n1)
  VER="${LATEST##*/}"
  if [[ -n "$VERSION_PREFIX" ]]; then
    VER="${VER#${VERSION_PREFIX}}"
  fi
  VER="${VER%.wcp}"

  CURRENT_LINE="- Current version: $VER"

  if [[ -n "$REL_TAG_NIGHTLY" && "$REL_TAG" == "$REL_TAG_NIGHTLY" && -n "$UPSTREAM_REPO" && -n "$REF" ]]; then
    SHORT="${REF:0:7}"

    BASE="$VER"
    DATECODE=""

    if [[ "$VER" == *"-"* ]]; then
      local_rest="${VER%-*}"          # BASE-DATECODE
      if [[ "$local_rest" == *"-"* ]]; then
        DATECODE="${local_rest##*-}"  # DATECODE
        BASE="${local_rest%-*}"       # BASE
      fi
    fi

    if [[ -n "$DATECODE" ]]; then
      CURRENT_LINE="- Current version: ${BASE}-${DATECODE}-[${SHORT}](https://github.com/${UPSTREAM_REPO}/commit/${REF})"
    else
      CURRENT_LINE="- Current version: ${VER}-[${SHORT}](https://github.com/${UPSTREAM_REPO}/commit/${REF})"
    fi
  fi

  echo "$CURRENT_LINE" >> "$NOTES"

  if ! gh release view "$REL_TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "$REL_TAG" --repo "$REPO" -t "$REL_TITLE" -F "$NOTES"
  else
    gh release edit "$REL_TAG" --repo "$REPO" -t "$REL_TITLE" -F "$NOTES"
  fi

  gh release upload "$REL_TAG" $ARTIFACT_GLOB --repo "$REPO" --clobber
else
  echo "No artifacts."
fi
