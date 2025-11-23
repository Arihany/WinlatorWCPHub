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
        split("|")
        | {
            kind:      .[0],
            channel:   .[1],
            ref:       .[2],
            ver_name:  .[3],
            ver_code:  .[4],
            rel_tag:   .[5],
            rel_title: .[6],
            filename:  .[7],
            short:     .[8]
          }
      )
    | {include: .}
  '
)

printf "matrix=%s\n" "$matrix_json" >> "$GITHUB_OUTPUT"
