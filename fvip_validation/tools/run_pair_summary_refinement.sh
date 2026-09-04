#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
license_setup=${AXI_LICENSE_SETUP:-$HOME/bashrc-new}

if [[ -z "${AXI_FORMAL_LICENSE_READY:-}" ]]; then
  export AXI_FORMAL_LICENSE_READY=1 AXI_LICENSE_SETUP="$license_setup"
  export AXI_PAIR_SUMMARY_RUNNER="$script_dir/run_pair_summary_refinement.sh"
  exec bash -ic 'source "$AXI_LICENSE_SETUP" >/dev/null 2>&1; exec "$AXI_PAIR_SUMMARY_RUNNER"'
fi

export PATH="/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin:$PATH"
stamp=${RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
run_dir=${ODIR:-$repo_dir/work/runs/${stamp}_pair_summary_refinement}
[[ ! -e "$run_dir" ]] || {
  echo "Refusing to overwrite $run_dir" >&2
  exit 2
}
mkdir -p "$run_dir"

FLIST="$repo_dir/fvip_validation/qverify/pair_summary_refinement.f" \
WORKDIR="$run_dir" \
  nix-shell "$repo_dir/shell.nix" --run \
    "qverify -c -od '$run_dir' -do '$repo_dir/fvip_validation/qverify/run_pair_summary_refinement.do'" \
    > "$run_dir/run.log" 2>&1

[[ -f "$run_dir/formal_verify.rpt" ]] || {
  echo "Pair-summary refinement did not produce a report" >&2
  exit 1
}
nix-shell "$repo_dir/shell.nix" --run \
  "python3 '$repo_dir/tools/formal_report.py' '$run_dir/formal_verify.rpt' --output-dir '$run_dir'" \
  >/dev/null 2>&1

status_file="$run_dir/property_status.csv"
proven=(
  a_refine_count_algebra
  a_refine_lane_factorization
  a_refine_position_algebra
  a_refine_raw_and_summary_freeze
  a_refine_raw_capture_pending_w_join
  a_refine_raw_capture_select_aw
  a_refine_raw_capture_select_w_join
  a_refine_reference_length_summary
  a_refine_reference_valid_state
  a_refine_terminal_algebra
  i_tracker.a_tracker_aw_summary_capture_pending_w_join
  i_tracker.a_tracker_aw_summary_capture_select_aw
  i_tracker.a_tracker_aw_summary_capture_select_w_join
)
covered=(
  c_refine_awlen_255
  c_refine_lane_one
  c_refine_lane_zero
  i_tracker.c_aw_summary_capture_pending_w_join
  i_tracker.c_aw_summary_capture_select_aw
  i_tracker.c_aw_summary_capture_select_w_join
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

printf 'artifact=%s\n' "$run_dir"
