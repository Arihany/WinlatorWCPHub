#  /\_/\ 
# (=•ᆽ•=)づ✈
set -Eeuo pipefail
IFS=$'\n\t'

REL_TAG="${REL_TAG:?REL_TAG not set}"
REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY must be set}}"
ARTIFACT_GLOB="${ARTIFACT_GLOB:?ARTIFACT_GLOB not set}"
VERSION_PREFIX="${VERSION_PREFIX:-}"

REL_TAG_NIGHTLY="${REL_TAG_NIGHTLY:-}"
UPSTREAM_REPO="${UPSTREAM_REPO:-}"
REF="${REF:-}"

NOTES="${NOTES:-RELEASE_NOTES.md}"
BODY="${BODY:-}"

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

line="- Current version: $ver"

if [[ -n "$REL_TAG_NIGHTLY" &&
      "$REL_TAG" == "$REL_TAG_NIGHTLY" &&
      -n "$UPSTREAM_REPO" &&
      -n "$REF" ]]; then
  short_sha="${REF:0:7}"
  commit_link="https://github.com/${UPSTREAM_REPO}/commit/${REF}"

  core="${ver%-*}"
  if [[ "$ver" == *-* && "$core" == *-* ]]; then
    datecode="${core##*-}"
    base="${core%-*}"
    line="- Current version: ${base}-${datecode}-[${short_sha}](${commit_link})"
  else
    line="- Current version: ${ver}-[${short_sha}](${commit_link})"
  fi
fi

printf '%s\n' "$line" >>"$NOTES"

if gh release view "$REL_TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release edit "$REL_TAG" --repo "$REPO" -t "$REL_TAG" -F "$NOTES"
else
  gh release create "$REL_TAG" --repo "$REPO" -t "$REL_TAG" -F "$NOTES"
fi

gh release upload "$REL_TAG" "${artifacts[@]}" --repo "$REPO" --clobber
