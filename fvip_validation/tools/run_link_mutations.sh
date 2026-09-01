#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
license_setup=${AXI_LICENSE_SETUP:-$HOME/bashrc-new}
if [[ -z "${AXI_FORMAL_LICENSE_READY:-}" ]]; then
  export AXI_FORMAL_LICENSE_READY=1 AXI_LICENSE_SETUP="$license_setup"
  export AXI_LINK_RUNNER="$script_dir/run_link_mutations.sh"
  exec bash -ic 'source "$AXI_LICENSE_SETUP" >/dev/null 2>&1; exec "$AXI_LINK_RUNNER"'
fi
export PATH="/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin:$PATH"
stamp=${RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
run_dir=${ODIR:-$repo_dir/work/runs/${stamp}_link_mutations}
[[ ! -e "$run_dir" ]] || { echo "Refusing to overwrite $run_dir" >&2; exit 2; }
nix-shell "$repo_dir/shell.nix" --run \
  "WORKDIR='$run_dir' qverify -c -od '$run_dir' -do '$repo_dir/fvip_validation/qverify/run_link_mutation.do'"
nix-shell "$repo_dir/shell.nix" --run \
  "python3 '$repo_dir/tools/formal_report.py' '$run_dir/formal_verify.rpt' --output-dir '$run_dir'" \
  || true
awk -F, '
  $2=="fired" {fired++}
  $1 ~ /bad_manager.u_channel.*a_aw_payload_stall_stable/ && $2=="fired" {manager=1}
  $1 ~ /bad_subordinate.u_channel.*a_b_payload_stall_stable/ && $2=="fired" {subordinate=1}
  $1 ~ /bad_manager.u_channel.*a_r_max_ready_after_valid/ && $2=="fired" {manager_ready=1}
  $1 ~ /bad_subordinate.u_channel.*a_aw_max_ready_after_valid/ && $2=="fired" {subordinate_ready=1}
  END {exit !(fired == 4 && manager && subordinate && manager_ready && subordinate_ready)}
' "$run_dir/property_status.csv"
