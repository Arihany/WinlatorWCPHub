set -Eeuo pipefail

: "${REL_TAG:?REL_TAG not set}"
: "${REL_TAG_NIGHTLY:?REL_TAG_NIGHTLY not set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set}"

KEEP="${KEEP:-10}"

if [[ "$REL_TAG" != "$REL_TAG_NIGHTLY" ]]; then
  echo "Current release '$REL_TAG' is not Nightly ('$REL_TAG_NIGHTLY'). Skipping prune."
  exit 0
fi

echo "Checking for old assets in '$REL_TAG' (keeping latest $KEEP)..."

TO_DELETE=$(
  gh release view "$REL_TAG" --repo "$GITHUB_REPOSITORY" --json assets \
    --jq '.assets
          | sort_by(.createdAt)
          | reverse
          | .[$KEEP:][]?.name' \
    --argjson KEEP "$KEEP" \
  || true
)

if [[ -z "$TO_DELETE" ]]; then
  echo "No assets to prune."
  exit 0
fi

while IFS= read -r asset; do
  [[ -z "$asset" ]] && continue
  echo "Deleting old asset: $asset"
  gh release delete-asset "$REL_TAG" "$asset" --repo "$GITHUB_REPOSITORY" -y \
    || echo "Failed to delete $asset"
done <<< "$TO_DELETE"
