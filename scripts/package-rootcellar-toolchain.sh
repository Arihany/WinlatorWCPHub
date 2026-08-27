#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/toolchain-lock.sh"

SOURCE_DIR="${1:?validated RootCellar toolchain directory is required}"
OUTPUT_DIR="${2:?output directory is required}"
MANIFEST="$SOURCE_DIR/rootcellar-toolchain-manifest.json"
ARCHIVE="$OUTPUT_DIR/$WCP_ROOTCELLAR_TOOLCHAIN_ARCHIVE"
CHECKSUM="$OUTPUT_DIR/$WCP_ROOTCELLAR_TOOLCHAIN_CHECKSUM"

[[ -d "$SOURCE_DIR/bin" ]] || { echo "Missing toolchain bin directory: $SOURCE_DIR" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "Missing RootCellar manifest: $MANIFEST" >&2; exit 1; }

actual_manifest_sha256="$(sha256sum "$MANIFEST" | awk '{print $1}')"
if [[ "$actual_manifest_sha256" != "$WCP_ROOTCELLAR_TOOLCHAIN_MANIFEST_SHA256" ]]; then
  echo "RootCellar manifest mismatch: expected $WCP_ROOTCELLAR_TOOLCHAIN_MANIFEST_SHA256, got $actual_manifest_sha256" >&2
  exit 1
fi

for tool in \
  arm64ec-w64-mingw32-g++ \
  aarch64-w64-mingw32-g++ \
  i686-w64-mingw32-g++ \
  x86_64-w64-mingw32-g++ \
  llvm-readobj; do
  [[ -x "$SOURCE_DIR/bin/$tool" ]] || { echo "Missing tool: $tool" >&2; exit 1; }
done

mkdir -p "$OUTPUT_DIR"
[[ ! -e "$ARCHIVE" && ! -e "$CHECKSUM" ]] || {
  echo "Refusing to overwrite an existing release asset in $OUTPUT_DIR" >&2
  exit 1
}

STAGE="$(mktemp -d)"
cleanup() { rm -rf -- "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/$WCP_ROOTCELLAR_TOOLCHAIN_ID"
cp -a "$SOURCE_DIR/." "$STAGE/$WCP_ROOTCELLAR_TOOLCHAIN_ID/"

tar --sort=name \
  --mtime='UTC 2026-06-02' \
  --owner=0 --group=0 --numeric-owner \
  -C "$STAGE" \
  -cJf "$ARCHIVE" \
  "$WCP_ROOTCELLAR_TOOLCHAIN_ID"

(
  cd "$OUTPUT_DIR"
  sha256sum "$WCP_ROOTCELLAR_TOOLCHAIN_ARCHIVE" > "$WCP_ROOTCELLAR_TOOLCHAIN_CHECKSUM"
)

printf 'Created %s\nCreated %s\n' "$ARCHIVE" "$CHECKSUM"
