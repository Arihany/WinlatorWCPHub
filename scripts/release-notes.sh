
declare -A REL_NOTE=(
  [general]="- General-purpose x64/x86 build"
  [fexonly]="- For FEX only"
  [common]="- Common: Uses Valve-style build flags. Compatibility may be reduced."
  [prereg]="- pre-reg: Last version before the performance drop on Turnip driver."
  [binsem]="- binsem: Avoids Turnip performance loss without env vars. May be unstable."
  [dyasync]="- For adjusting various parameters, please refer to the upstream release notes."
)

render_notes() {
  local key
  for key in "$@"; do
    if [[ -n "${REL_NOTE[$key]+x}" ]]; then
      printf '%s\n' "${REL_NOTE[$key]}"
    else
      echo "::warning::unknown release-note key: $key" >&2
    fi
  done
}
