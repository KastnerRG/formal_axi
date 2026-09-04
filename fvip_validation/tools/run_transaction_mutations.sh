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

names=(good early_r early_rlast early_b wrong_wlast wrong_wstrb wrong_rid wrong_bid repeated_id_reorder deadlock duplicate_b read_rank_compaction write_rank_compaction write_data_deadlock write_response_deadlock legal_b_join_reorder per_id_early_b legal_per_id_tag_pop_push legal_w_before_aw same_edge_w_before_aw_b legal_stalled_parity bad_stalled_parity_wstrb bad_stalled_parity_wlast bad_late_aw_partial_prefix bad_late_aw_completed_length bad_late_aw_completed_wstrb legal_stalled_mapped_r bad_stalled_mapped_r_data bad_stalled_mapped_r_completion bad_stalled_error_rresp bad_stalled_error_rdata wrong_id_r_isolation legal_stalled_mapped_b bad_stalled_mapped_b same_edge_output_wlast_b bad_stalled_error_bresp wrong_id_b_isolation public_view_wrong_rid public_view_wrong_bid public_view_early_b)
expected=('' 'x_r_has_ar|x_no_orphan_response' 'x_r_last_exact' 'x_b_has_completed_write|x_no_orphan_response' 'x_w_last_exact|x_[ab]_selected_match' 'x_wstrb' 'x_r_has_ar|x_no_orphan_response' 'x_b_has_completed_write|x_no_orphan_response' 'x_r_last_exact' 'x_read_response_progress' 'x_b_has_completed_write|x_no_orphan_response' '' '' 'x_write_data_progress' 'x_write_response_progress' '' 'x_b_has_per_id_completed_write' '' '' 'x_b_has_per_id_completed_write' '' 'x_wstrb_live_select_aw' 'x_w_last_offer_select_aw' 'x_wstrb_live_select_aw' 'x_w_last_exact_after_w' 'x_wstrb_after_w' '' 'a_selected_mapped_response_data' 'a_selected_mapped_response_completion' 'a_selected_error_response' 'a_selected_error_response' 'a_selected_mapped_response_occurrence' '' 'a_selected_mapped_b' 'a_selected_mapped_b_occurrence' 'a_selected_error_b' 'a_selected_mapped_b_occurrence' '' '' 'x_b_has_completed_write|x_b_has_per_id_completed_write')
printf 'mutation,name,oracle_detected,smart_detected,intended_detected,unexpected_fired,inconclusive,sequence_reached,guards_proven,ready_low_reached\n' > "$root/mutation_score.csv"

for mutation in ${MUTATIONS:-$(seq 0 39)}; do
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
  grep -Eq '^(g_source|g_response)\.i_txn\..*,fired$|^g_response\.g_response_delay\.p_read_bounded,fired$|^g_role_response\.i_role_case\.i_role\.i_(read|write)\..*,fired$|^g_endpoint_view\.i_view_case\.i_endpoint\.g_txn\..*,fired$' \
    "$run_dir/property_status.csv" && smart=1 || true
  if (( mutation == 0 || mutation == 11 || mutation == 12 || mutation == 15 ||
        mutation == 17 || mutation == 18 || mutation == 20 ||
        mutation == 26 || mutation == 32 || mutation == 37 ||
        mutation == 38 )); then
    [[ -z "$fired" ]] || unexpected=1
  elif grep -Eq "${expected[$mutation]}" <<<"$fired"; then
    intended=1
  fi
  inconclusive=$(awk -F, '$2=="inconclusive"{n++} END{print n+0}' "$run_dir/property_status.csv")
  sequence_reached=0 guards_proven=1 ready_low_reached=1
  if (( mutation >= 26 && mutation <= 36 )); then
    grep -q '^g_role_response\.i_role_case\.c_role_sequence_reached,covered$' \
      "$run_dir/property_status.csv" && sequence_reached=1 || true
    ready_low_reached=0
    grep -Eq '^g_role_response\.i_role_case\.c_ready_low_(read|write)_offer,covered$' \
      "$run_dir/property_status.csv" && ready_low_reached=1 || true
    if (( mutation == 34 )); then
      grep -q '^g_role_response\.i_role_case\.c_same_edge_wlast_b_offer,covered$' \
        "$run_dir/property_status.csv" || ready_low_reached=0
    fi
    if (( mutation == 31 )); then
      grep -q '^g_role_response\.i_role_case\.g_wrong_r_guard\.a_wrong_r_offer_is_not_selected,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
      grep -q '^g_role_response\.i_role_case\.g_wrong_r_guard\.a_wrong_r_handshake_preserves_target,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
    elif (( mutation == 36 )); then
      grep -q '^g_role_response\.i_role_case\.g_wrong_b_guard\.a_wrong_b_offer_is_not_selected,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
      grep -q '^g_role_response\.i_role_case\.g_wrong_b_guard\.a_wrong_b_handshake_preserves_target,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
    fi
  elif (( mutation >= 37 && mutation <= 39 )); then
    grep -q '^g_endpoint_view\.i_view_case\.c_view_sequence_reached,covered$' \
      "$run_dir/property_status.csv" && sequence_reached=1 || true
    if (( mutation == 37 )); then
      grep -q '^g_endpoint_view\.i_view_case\.g_read_view_guard\.a_wrong_r_does_not_complete_view,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
      grep -q '^g_endpoint_view\.i_view_case\.g_read_view_guard\.a_wrong_r_does_not_capture_view,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
      grep -q '^g_endpoint_view\.i_view_case\.c_view_wrong_r_handshake,covered$' \
        "$run_dir/property_status.csv" || guards_proven=0
    elif (( mutation == 38 )); then
      grep -q '^g_endpoint_view\.i_view_case\.g_write_id_view_guard\.a_wrong_b_does_not_complete_view,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
      grep -q '^g_endpoint_view\.i_view_case\.g_write_id_view_guard\.a_wrong_b_does_not_capture_view,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
      grep -q '^g_endpoint_view\.i_view_case\.c_view_wrong_b_handshake,covered$' \
        "$run_dir/property_status.csv" || guards_proven=0
    else
      grep -q '^g_endpoint_view\.i_view_case\.g_write_data_view_guard\.a_early_b_does_not_complete_view,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
      grep -q '^g_endpoint_view\.i_view_case\.g_write_data_view_guard\.a_early_b_does_not_capture_view,proven$' \
        "$run_dir/property_status.csv" || guards_proven=0
      grep -q '^g_endpoint_view\.i_view_case\.c_view_early_b_handshake,covered$' \
        "$run_dir/property_status.csv" || guards_proven=0
    fi
  else
    grep -q '^cover__0,covered$' "$run_dir/property_status.csv" && sequence_reached=1 || true
  fi
  printf '%d,%s,%d,%d,%d,%d,%d,%d,%d,%d\n' "$mutation" "${names[$mutation]}" \
    "$oracle" "$smart" "$intended" "$unexpected" "$inconclusive" \
    "$sequence_reached" "$guards_proven" "$ready_low_reached" \
    >> "$root/mutation_score.csv"
  printf 'command_exit=%d\n' "$command_rc" > "$run_dir/manifest.env"
done

awk -F, 'NR>1 && (($1>0 && $1<11) || ($1>=13 && $1<=14) || $1==16 || $1==19 || ($1>=21 && $1<=25)) && ($4!=1 || $5!=1 || $7!=0 || $8!=1){bad=1}
           NR>1 && (($1>0 && $1<11 && $1!=9) || $1==16 || $1==19) && $3!=1{bad=1}
           NR>1 && ($1==0 || $1==11 || $1==12 || $1==15 || $1==17 || $1==18 || $1==20) && ($6!=0 || $7!=0 || $8!=1){bad=1}
           NR>1 && (($1>=27 && $1<=31) || ($1>=33 && $1<=36)) && ($4!=1 || $5!=1 || $7!=0 || $8!=1 || $9!=1 || $10!=1){bad=1}
           NR>1 && ($1==26 || $1==32) && ($6!=0 || $7!=0 || $8!=1 || $9!=1 || $10!=1){bad=1}
           NR>1 && ($1==37 || $1==38) && ($6!=0 || $7!=0 || $8!=1 || $9!=1){bad=1}
           NR>1 && $1==39 && ($4!=1 || $5!=1 || $7!=0 || $8!=1 || $9!=1){bad=1}
           END{exit bad}' "$root/mutation_score.csv"
