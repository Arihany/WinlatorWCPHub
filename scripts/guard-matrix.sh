#!/usr/bin/env bash
set -Eeuo pipefail

ROWS="${ROWS:-}"
MISSING="${MISSING:-}"

if [[ "$MISSING" != "true" || -z "$ROWS" ]]; then
  echo 'matrix={"include":[]}' >> "$GITHUB_OUTPUT"
  exit 0
fi

matrix_json=$(
  printf '%s' "$ROWS" | jq -R -s -c '
    split("\n")
    | map(select(length > 0))
    | map(
        (split("|")) as $cols
        | {
            kind:      $cols[0],
            channel:   $cols[1],
            ref:       $cols[2],
            ver_name:  $cols[3],
            ver_code:  $cols[4],
            rel_tag:   $cols[5],
            filename:  $cols[6],
            short:     $cols[7]
          }
      )
    | { include: . }
  '
)

printf "matrix=%s\n" "$matrix_json" >> "$GITHUB_OUTPUT"
