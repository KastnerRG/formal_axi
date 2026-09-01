#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
license_setup=${AXI_LICENSE_SETUP:-$HOME/bashrc-new}

if [[ -z "${AXI_FORMAL_LICENSE_READY:-}" ]]; then
  export AXI_FORMAL_LICENSE_READY=1 AXI_LICENSE_SETUP="$license_setup"
  export AXI_MUTATION_RUNNER="$script_dir/run_fifo_mutations.sh"
  exec bash -ic 'source "$AXI_LICENSE_SETUP" >/dev/null 2>&1; exec "$AXI_MUTATION_RUNNER"'
fi

export PATH="/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin:$PATH"
stamp=${RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
root=${ODIR:-$repo_dir/work/runs/${stamp}_fifo_mutations}
[[ ! -e "$root" ]] || { echo "Refusing to overwrite $root" >&2; exit 2; }
mkdir -p "$root"

printf 'mutation,name,oracle_detected,tracker_detected,unexpected_fired,inconclusive\n' > "$root/mutation_score.csv"
names=(good phantom drop duplicate corrupt reorder deadlock)
for mutation in 0 1 2 3 4 5 6; do
  run_dir="$root/${mutation}_${names[$mutation]}"
  mkdir -p "$run_dir"
  set +e
  MUTATION=$mutation FLIST="$repo_dir/fvip_validation/qverify/fifo_mutation.f" WORKDIR="$run_dir" \
    nix-shell "$repo_dir/shell.nix" --run \
      "qverify -c -od '$run_dir' -do '$repo_dir/fvip_validation/qverify/run_fifo_mutation.do'" \
      > "$run_dir/run.log" 2>&1
  command_rc=$?
  set -e
  report="$run_dir/formal_verify.rpt"
  [[ -f "$report" ]] || { echo "Mutation $mutation did not produce a report" >&2; exit 1; }
  nix-shell "$repo_dir/shell.nix" --run \
    "python3 '$repo_dir/tools/formal_report.py' '$report' --output-dir '$run_dir'" \
    >/dev/null 2>&1 || true
  fired=$(awk -F, '{gsub(/\r/, "", $2)} $2=="fired"{print $1}' "$run_dir/property_status.csv")
  oracle=0 tracker=0 unexpected=0 inconclusive=0
  grep -q '^i_oracle\..*,fired$' "$run_dir/property_status.csv" && oracle=1 || true
  grep -q '^i_tracker\..*,fired$' "$run_dir/property_status.csv" && tracker=1 || true
  if (( mutation == 0 )); then
    [[ -z "$fired" ]] || unexpected=1
  fi
  inconclusive=$(awk -F, '{gsub(/\r/, "", $2)} $2=="inconclusive"{n++} END{print n+0}' "$run_dir/property_status.csv")
  printf '%d,%s,%d,%d,%d,%d\n' "$mutation" "${names[$mutation]}" \
    "$oracle" "$tracker" "$unexpected" "$inconclusive" >> "$root/mutation_score.csv"
  printf 'command_exit=%d\n' "$command_rc" > "$run_dir/manifest.env"
done

awk -F, 'NR>1 && $1>0 && ($3!=1 || $4!=1 || $6!=0){bad=1}
           NR>1 && $1==0 && ($5!=0 || $6!=0){bad=1}
           END{exit bad}' "$root/mutation_score.csv"
