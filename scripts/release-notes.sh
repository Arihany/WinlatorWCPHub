
declare -A REL_NOTE=(
  [general]="- General-purpose x64/x86 build"
  [fexonly]="- For use with FEX only"
  [common]="- Common: Uses Valve-style build flags. Compatibility may be reduced."
  [prereg]="- Pre-reg: Last version before the performance regression on the Turnip driver."
  [dyasync]="- Dyasync: See upstream documentation for configuration variables."
  [proton]="- Proton: Pinned build for Proton."
  [dxvk]="- DXVK: Newer versions do not necessarily provide better performance. In particular, compatibility may be significantly reduced with version 2.7.x and later."
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
