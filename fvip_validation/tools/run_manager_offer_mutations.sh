#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
license_setup=${AXI_LICENSE_SETUP:-$HOME/bashrc-new}

if [[ -z "${AXI_FORMAL_LICENSE_READY:-}" ]]; then
  export AXI_FORMAL_LICENSE_READY=1 AXI_LICENSE_SETUP="$license_setup"
  export AXI_MANAGER_OFFER_RUNNER="$script_dir/run_manager_offer_mutations.sh"
  exec bash -ic 'source "$AXI_LICENSE_SETUP" >/dev/null 2>&1; exec "$AXI_MANAGER_OFFER_RUNNER"'
fi

export PATH="/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin:$PATH"
stamp=${RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
root=${ODIR:-$repo_dir/work/runs/${stamp}_manager_offer_mutations}
[[ ! -e "$root" ]] || { echo "Refusing to overwrite $root" >&2; exit 2; }
mkdir -p "$root"

names=(
  legal_live_parity legal_queued_aw legal_partial_w_before_aw
  legal_completed_w_before_aw bad_live_wstrb bad_live_wlast
  bad_queued_wstrb bad_queued_wlast bad_partial_position
  bad_partial_prefix bad_completed_length bad_completed_wstrb
)

printf 'mutation,name,setup_reached,bad_setup,terminal_status,expected_status,legal_escape,guard_status,inconclusive_or_fired,compile_clean,pass\n' \
  > "$root/mutation_score.csv"

for mutation in ${MUTATIONS:-$(seq 0 11)}; do
  run_dir="$root/${mutation}_${names[$mutation]}"
  mkdir -p "$run_dir"
  set +e
  MUTATION=$mutation WORKDIR="$run_dir" \
    nix-shell "$repo_dir/shell.nix" --run \
      "qverify -c -od '$run_dir' -do '$repo_dir/fvip_validation/qverify/run_manager_offer_mutation.do'" \
      > "$run_dir/run.log" 2>&1
  command_rc=$?
  set -e
  (( command_rc == 0 )) || {
    echo "Manager-offer mutation $mutation failed to run" >&2
    exit 1
  }
  report="$run_dir/formal_verify.rpt"
  [[ -f "$report" ]] || {
    echo "Manager-offer mutation $mutation did not produce a report" >&2
    exit 1
  }
  nix-shell "$repo_dir/shell.nix" --run \
    "python3 '$repo_dir/tools/formal_report.py' '$report' --output-dir '$run_dir'" \
    >/dev/null 2>&1 || true

  setup=0
  grep -q '^c_setup,covered$' "$run_dir/property_status.csv" && setup=1 || true
  terminal=$(awk -F, '$1 ~ /c_terminal$/{print $2}' \
    "$run_dir/property_status.csv")
  if (( mutation < 4 )); then
    expected=covered
    bad_setup=not_applicable
    escape=not_applicable
    guard=not_applicable
  else
    expected=uncoverable
    bad_setup=$(awk -F, '$1=="g_bad_offer.c_bad_setup"{print $2}' \
      "$run_dir/property_status.csv")
    escape=$(awk -F, '$1=="g_bad_offer.c_legal_escape"{print $2}' \
      "$run_dir/property_status.csv")
    guard=$(awk -F, '$1=="g_bad_offer.a_bad_offer_blocked"{print $2}' \
      "$run_dir/property_status.csv")
  fi
  bad_status=$(awk -F, '$2=="inconclusive" || $2=="fired"{n++} END{print n+0}' \
    "$run_dir/property_status.csv")
  compile_clean=0
  grep -q '# Errors: 0, Warnings: 0' "$run_dir/run.log" && compile_clean=1 || true
  pass=0
  if [[ $setup == 1 && $terminal == "$expected" && $bad_status == 0 &&
        $compile_clean == 1 &&
        ($mutation -lt 4 || ($bad_setup == covered &&
         $escape == covered && $guard == proven)) ]]; then
    pass=1
  fi
  printf '%d,%s,%d,%s,%s,%s,%s,%s,%d,%d,%d\n' \
    "$mutation" "${names[$mutation]}" "$setup" "$bad_setup" \
    "$terminal" "$expected" "$escape" "$guard" "$bad_status" \
    "$compile_clean" "$pass" \
    >> "$root/mutation_score.csv"
  printf 'command_exit=%d\n' "$command_rc" > "$run_dir/manifest.env"
done

awk -F, 'NR>1 && $11!=1{bad=1} END{exit bad}' "$root/mutation_score.csv"
