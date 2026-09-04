#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
license_setup=${AXI_LICENSE_SETUP:-$HOME/bashrc-new}

if [[ -z "${AXI_FORMAL_LICENSE_READY:-}" ]]; then
  export AXI_FORMAL_LICENSE_READY=1 AXI_LICENSE_SETUP="$license_setup"
  export AXI_C6_PUBLIC_PAIR_VIEW_RUNNER="$script_dir/run_c6_public_pair_view_refinement.sh"
  exec bash -ic 'source "$AXI_LICENSE_SETUP" >/dev/null 2>&1; exec "$AXI_C6_PUBLIC_PAIR_VIEW_RUNNER"'
fi

export PATH="/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin:$PATH"
stamp=${RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
run_dir=${ODIR:-$repo_dir/work/runs/${stamp}_c6_public_pair_view_refinement}
[[ ! -e "$run_dir" ]] || {
  echo "Refusing to overwrite $run_dir" >&2
  exit 2
}
mkdir -p "$run_dir"

FLIST="$repo_dir/fvip_validation/qverify/c6_public_pair_view_refinement.f" \
WORKDIR="$run_dir" \
  nix-shell "$repo_dir/shell.nix" --run \
    "qverify -c -od '$run_dir' -do '$repo_dir/fvip_validation/qverify/run_c6_public_pair_view_refinement.do'" \
    > "$run_dir/run.log" 2>&1

[[ -f "$run_dir/formal_verify.rpt" ]] || {
  echo "Public-pair-view refinement did not produce a report" >&2
  exit 1
}
nix-shell "$repo_dir/shell.nix" --run \
  "python3 '$repo_dir/tools/formal_report.py' '$run_dir/formal_verify.rpt' --output-dir '$run_dir'" \
  >/dev/null 2>&1

status_file="$run_dir/property_status.csv"
report_file="$run_dir/formal_verify.rpt"
proven=(
  a_refine_live_w_packing
  a_refine_pair_aw_capture_pending_w_join
  a_refine_pair_aw_capture_select_aw
  a_refine_pair_aw_capture_select_w_join
  a_refine_pair_w_complete
  a_refine_pair_w_scalar_full
  a_refine_pair_w_visible
  a_refine_payload_index_width_and_range
  dut.g_txn.a_view_pair_aw_capture_pending_w_join
  dut.g_txn.a_view_pair_aw_capture_select_aw
  dut.g_txn.a_view_pair_aw_capture_select_w_join
  dut.g_txn.a_view_pair_aw_frozen
  dut.g_txn.a_view_pair_w_completed_availability
  dut.g_txn.a_view_pair_w_complete_exact
  dut.g_txn.a_view_pair_w_completion_capture
  dut.g_txn.a_view_pair_w_live_capture
  dut.g_txn.a_view_pair_w_prefix_seed
  dut.g_txn.a_view_pair_w_rolling_scalar_capture
  dut.g_txn.a_view_pair_w_rolling_scalar_full_equiv
  dut.g_txn.a_view_pair_w_scalar_export_exact
  dut.g_txn.a_view_pair_w_scalar_frozen
  dut.g_txn.a_view_pair_w_scalar_full_equiv
  dut.g_txn.a_view_pair_w_visible_exact
)
covered=(
  c_refine_aw_handshake
  c_refine_awlen_255_select_aw
  c_refine_payload_index_high
  c_refine_payload_index_low
  c_refine_w_handshake
  dut.g_txn.c_view_pair_aw_capture_pending_w_join
  dut.g_txn.c_view_pair_aw_capture_select_aw
  dut.g_txn.c_view_pair_aw_capture_select_w_join
  dut.g_txn.c_view_pair_w_complete_pending_aw
  dut.g_txn.c_view_pair_w_complete_select_aw
  dut.g_txn.c_view_pair_w_complete_select_w
  dut.g_txn.c_view_pair_w_pending_aw_early_capture
  dut.g_txn.c_view_pair_w_pending_aw_stalled_offer
  dut.g_txn.c_view_pair_w_prefix_seed
  dut.g_txn.c_view_pair_w_select_aw_live_capture
  dut.g_txn.c_view_pair_w_select_aw_stalled_offer
  dut.g_txn.c_view_pair_w_select_w_final_capture
  dut.g_txn.c_view_pair_w_select_w_prior_capture
)

for property in "${proven[@]}"; do
  grep -Fxq "$property,proven" "$status_file" || {
    echo "Required refinement assertion did not prove: $property" >&2
    exit 1
  }
done
for property in "${covered[@]}"; do
  grep -Fxq "$property,covered" "$status_file" || {
    echo "Required refinement cover did not close: $property" >&2
    exit 1
  }
done

# Audit the named proof group's complete assumption inventory.  Only reset
# discipline and arbitrary pair-observer domains are permitted.
active_assumptions="$run_dir/active_assumptions.txt"
awk '
  /^Assumptions \([0-9]+\)$/ { inside = 1; separator = 0; next }
  inside && /^-+$/ {
    if (separator) exit
    separator = 1
    next
  }
  inside && separator && NF { print }
' "$report_file" > "$active_assumptions"
expected_assumptions=(
  a_initial_reset
  a_reset_changes_only_at_posedge
  a_reset_does_not_reassert
  a_reset_releases
  dut.g_txn.c_pair_w_payload_idx_range
  dut.g_txn.s_pair_w_payload_idx_constant
  dut.g_txn.u_txn.i_aw_w_tracker.c_watch_beat_range
  dut.g_txn.u_txn.i_aw_w_tracker.s_select_aw_occurrence
  dut.g_txn.u_txn.i_aw_w_tracker.s_select_once
  dut.g_txn.u_txn.i_aw_w_tracker.s_select_one
  dut.g_txn.u_txn.i_aw_w_tracker.s_select_w_occurrence
  dut.g_txn.u_txn.i_aw_w_tracker.s_watch_beat_constant
)
for assumption in "${expected_assumptions[@]}"; do
  grep -Fxq "$assumption" "$active_assumptions" || {
    echo "Required refinement assumption is not active: $assumption" >&2
    exit 1
  }
done
[[ $(wc -l < "$active_assumptions") -eq ${#expected_assumptions[@]} ]] || {
  echo "Unexpected active assumption in public-pair-view refinement" >&2
  cat "$active_assumptions" >&2
  exit 1
}

# Also audit the proof-dependency section and fail closed if an unrelated
# endpoint assumption was used.
used_assumptions="$run_dir/used_assumptions.txt"
awk '
  /^Assumptions Used in Proofs$/ { inside = 1; next }
  inside && /^Assumptions Used in Bounded Proofs$/ { exit }
  inside && /^\t\t/ {
    sub(/^\t\t/, ""); print
  }
' "$report_file" | sort -u > "$used_assumptions"
if grep -Ev '^($|a_(initial_reset|reset_changes_only_at_posedge|reset_does_not_reassert|reset_releases)|dut\.g_txn\.(c_pair_w_payload_idx_range|s_pair_w_payload_idx_constant)|dut\.g_txn\.u_txn\.i_aw_w_tracker\.(c_watch_beat_range|s_select_aw_occurrence|s_select_once|s_select_one|s_select_w_occurrence|s_watch_beat_constant))$' \
    "$used_assumptions" > "$run_dir/unexpected_used_assumptions.txt"; then
  echo "Unrelated assumption used by public-pair-view proof" >&2
  cat "$run_dir/unexpected_used_assumptions.txt" >&2
  exit 1
fi

printf 'artifact=%s\n' "$run_dir"
