#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
license_setup=${AXI_LICENSE_SETUP:-$HOME/bashrc-new}

if [[ -z "${AXI_FORMAL_LICENSE_READY:-}" ]]; then
  export AXI_FORMAL_LICENSE_READY=1 AXI_LICENSE_SETUP="$license_setup"
  export AXI_TXN_MUTATION_RUNNER="$script_dir/run_transaction_mutations.sh"
  exec bash -ic 'source "$AXI_LICENSE_SETUP" >/dev/null 2>&1; exec "$AXI_TXN_MUTATION_RUNNER"'
fi

export PATH="/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin:$PATH"
stamp=${RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
root=${ODIR:-$repo_dir/work/runs/${stamp}_transaction_mutations}
[[ ! -e "$root" ]] || { echo "Refusing to overwrite $root" >&2; exit 2; }
mkdir -p "$root"

names=(good early_r early_rlast early_b wrong_wlast wrong_wstrb wrong_rid wrong_bid repeated_id_reorder deadlock duplicate_b read_rank_compaction write_rank_compaction write_data_deadlock write_response_deadlock)
expected=('' 'x_r_has_ar|x_no_orphan_response' 'x_r_last_exact' 'x_b_has_completed_write|x_no_orphan_response' 'x_w_last_exact|x_[ab]_selected_match' 'x_wstrb' 'x_r_has_ar|x_no_orphan_response' 'x_b_has_completed_write|x_no_orphan_response' 'x_r_last_exact' 'x_read_response_progress' 'x_b_has_completed_write|x_no_orphan_response' '' '' 'x_write_data_progress' 'x_write_response_progress')
printf 'mutation,name,oracle_detected,smart_detected,intended_detected,unexpected_fired,inconclusive,sequence_reached\n' > "$root/mutation_score.csv"

for mutation in ${MUTATIONS:-$(seq 0 14)}; do
  run_dir="$root/${mutation}_${names[$mutation]}"
  mkdir -p "$run_dir"
  set +e
  MUTATION=$mutation FLIST="$repo_dir/fvip_validation/qverify/transaction_mutation.f" WORKDIR="$run_dir" \
    nix-shell "$repo_dir/shell.nix" --run \
      "qverify -c -od '$run_dir' -do '$repo_dir/fvip_validation/qverify/run_transaction_mutation.do'" \
      > "$run_dir/run.log" 2>&1
  command_rc=$?
  set -e
  (( command_rc == 0 )) || { echo "Transaction mutation $mutation failed to run" >&2; exit 1; }
  report="$run_dir/formal_verify.rpt"
  [[ -f "$report" ]] || { echo "Transaction mutation $mutation did not produce a report" >&2; exit 1; }
  nix-shell "$repo_dir/shell.nix" --run \
    "python3 '$repo_dir/tools/formal_report.py' '$report' --output-dir '$run_dir'" \
    >/dev/null 2>&1 || true
  fired=$(awk -F, '$2=="fired"{print $1}' "$run_dir/property_status.csv")
  oracle=0 smart=0 intended=0 unexpected=0
  grep -q '^i_oracle\..*,fired$' "$run_dir/property_status.csv" && oracle=1 || true
  grep -Eq '^(g_source|g_response)\.i_txn\..*,fired$|^g_response\.g_response_delay\.p_read_bounded,fired$' \
    "$run_dir/property_status.csv" && smart=1 || true
  if (( mutation == 0 || mutation == 11 || mutation == 12 )); then
    [[ -z "$fired" ]] || unexpected=1
  elif grep -Eq "${expected[$mutation]}" <<<"$fired"; then
    intended=1
  fi
  inconclusive=$(awk -F, '$2=="inconclusive"{n++} END{print n+0}' "$run_dir/property_status.csv")
  sequence_reached=0
  grep -q '^cover__0,covered$' "$run_dir/property_status.csv" && sequence_reached=1 || true
  printf '%d,%s,%d,%d,%d,%d,%d,%d\n' "$mutation" "${names[$mutation]}" \
    "$oracle" "$smart" "$intended" "$unexpected" "$inconclusive" \
    "$sequence_reached" >> "$root/mutation_score.csv"
  printf 'command_exit=%d\n' "$command_rc" > "$run_dir/manifest.env"
done

awk -F, 'NR>1 && (($1>0 && $1<11) || $1>=13) && ($4!=1 || $5!=1 || $7!=0 || $8!=1){bad=1}
           NR>1 && $1>0 && $1<11 && $1!=9 && $3!=1{bad=1}
           NR>1 && ($1==0 || $1==11 || $1==12) && ($6!=0 || $7!=0 || $8!=1){bad=1}
           END{exit bad}' "$root/mutation_score.csv"
