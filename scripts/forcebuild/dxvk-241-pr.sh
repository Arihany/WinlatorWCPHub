#!/usr/bin/env bash
set -Eeuo pipefail

: "${UNI_KIND:?UNI_KIND is required}"
: "${REL_TAG_STABLE:?REL_TAG_STABLE is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

echo ">> Pre-regression override enabled" >&2

ref_full="4c0cbbef6abe2b1a9e8c358be0caf207c907a5d2"
ref_short="4c0cbbe"

base_ver="2.4.1"
variant="pre-reg"

ver_name="${variant}-${base_ver}"
rel_tag="${REL_TAG_STABLE}"
filename="${UNI_KIND}-${variant}-${base_ver}.wcp"

{
  echo "missing=true"
  echo "list=${UNI_KIND}|stable|${ref_full}|${ver_name}|${rel_tag}|${filename}|${ref_short}"
} >> "$GITHUB_OUTPUT"
