#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)

role=${ROLE:-fifo}
vendor=${VENDOR:-zipcpu}
impl=${IMPL:-sfifo}
level=${LEVEL:-full}
fifo_depth=${FIFO_DEPTH:-2}
fifo_track_depth=${FIFO_TRACK_DEPTH:-$fifo_depth}
fall_through=${FIFO_FALL_THROUGH:-0}
allow_bypass=${FIFO_ALLOW_BYPASS:-$fall_through}
max_stall=${MAX_STALL:-8}
max_outstanding=${MAX_OUTSTANDING:-1}
max_response_delay=${MAX_RESPONSE_DELAY:-16}
max_write_data_delay=${MAX_WRITE_DATA_DELAY:-16}
max_role_delay=${MAX_ROLE_DELAY:-100}
enable_bounded_env=${ENABLE_BOUNDED_ENV:-1}
formal_timeout=${FORMAL_TIMEOUT:-}
formal_jobs=${FORMAL_JOBS:-32}
run_stamp=${RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
output_dir=${ODIR:-$repo_dir/work/runs/${run_stamp}_${role}_${vendor}_${impl}_${level}_d${fifo_depth}_ft${fall_through}}
license_setup=${AXI_LICENSE_SETUP:-$HOME/bashrc-new}

require_uint() {
  local name=$1
  local value=$2
  if [[ ! $value =~ ^[0-9]+$ ]]; then
    echo "$name must be an unsigned integer (got: $value)" >&2
    exit 2
  fi
}

require_range() {
  local name=$1
  local value=$2
  local minimum=$3
  local maximum=$4
  require_uint "$name" "$value"
  local number=$((10#$value))
  if (( number < minimum || number > maximum )); then
    echo "$name must be in the range $minimum..$maximum (got: $value)" >&2
    exit 2
  fi
}

require_uint FIFO_DEPTH "$fifo_depth"
require_uint FIFO_TRACK_DEPTH "$fifo_track_depth"
require_uint MAX_STALL "$max_stall"
require_range MAX_OUTSTANDING "$max_outstanding" 1 255
require_range MAX_RESPONSE_DELAY "$max_response_delay" 1 255
require_range MAX_WRITE_DATA_DELAY "$max_write_data_delay" 1 255
require_range MAX_ROLE_DELAY "$max_role_delay" 1 65535
require_range FIFO_FALL_THROUGH "$fall_through" 0 1
require_range FIFO_ALLOW_BYPASS "$allow_bypass" 0 1
require_range ENABLE_BOUNDED_ENV "$enable_bounded_env" 0 1
if [[ -n $formal_timeout && ! $formal_timeout =~ ^[1-9][0-9]*[smhd]?$ ]]; then
  echo "FORMAL_TIMEOUT must be a positive duration such as 300, 5m, or 1h (got: $formal_timeout)" >&2
  exit 2
fi
if [[ -n $formal_jobs ]]; then
  require_range FORMAL_JOBS "$formal_jobs" 1 256
fi

case "$role/$vendor/$impl/$fifo_depth/$fall_through" in
  *[!A-Za-z0-9_./-]*) echo "Unsupported character in run selection" >&2; exit 2 ;;
esac
case "$level" in
  protocol) transaction_fvip=0 ;;
  full) transaction_fvip=1 ;;
  *) echo "LEVEL must be protocol or full (got: $level)" >&2; exit 2 ;;
esac

if [[ ! -r "$license_setup" ]]; then
  echo "License setup file is not readable: $license_setup" >&2
  exit 2
fi

# bashrc-new intentionally returns before its tool/license setup in a
# non-interactive shell.  Re-enter this script once through interactive Bash;
# values stay in the environment and are never echoed or written to artifacts.
if [[ -z "${AXI_FORMAL_LICENSE_READY:-}" ]]; then
  export AXI_FORMAL_LICENSE_READY=1
  export AXI_LICENSE_SETUP="$license_setup"
  export AXI_FORMAL_RUNNER="$script_dir/run_formal.sh"
  exec bash -ic 'source "$AXI_LICENSE_SETUP" >/dev/null 2>&1; exec "$AXI_FORMAL_RUNNER"'
fi
if [[ -e "$output_dir" ]]; then
  echo "Refusing to overwrite existing run directory: $output_dir" >&2
  exit 2
fi

# The setup script supplies only the vendor license environment.  Nix supplies
# libXau and a csh compatibility executable required by Questa.
questa_static_dir=/tools/Siemens/2023.2/questa_static_formal/linux_x86_64
export PATH="$questa_static_dir/share/modeltech/linux_x86_64:$questa_static_dir/bin:$PATH"

tool_version=$(nix-shell "$repo_dir/shell.nix" --run 'qverify -version' 2>&1 |
  awk '/Version/{print $2, $3; exit}')
dut_commit=$(git -C "$repo_dir" submodule status soc-testbed | awk '{gsub(/^[+-]/, "", $1); print $1}')
repo_commit=$(git -C "$repo_dir" rev-parse HEAD)

make_cmd=(make -C "$repo_dir" qverify
  "ROLE=$role" "VENDOR=$vendor" "IMPL=$impl" "LEVEL=$level" "ODIR=$output_dir"
  "FIFO_DEPTH=$fifo_depth" "FIFO_FALL_THROUGH=$fall_through"
  "FIFO_TRACK_DEPTH=$fifo_track_depth"
  "FIFO_ALLOW_BYPASS=$allow_bypass"
  "MAX_STALL=$max_stall"
  "MAX_OUTSTANDING=$max_outstanding"
  "MAX_AW_AHEAD=${MAX_AW_AHEAD:-4}" "MAX_W_AHEAD=${MAX_W_AHEAD:-4}"
  "MAX_BURST_LEN=${MAX_BURST_LEN:-8}"
  "MAX_RESPONSE_DELAY=$max_response_delay"
  "MAX_WRITE_DATA_DELAY=$max_write_data_delay"
  "MAX_ROLE_DELAY=$max_role_delay"
  "ENABLE_BOUNDED_ENV=$enable_bounded_env"
  "FORMAL_TIMEOUT=$formal_timeout"
  "FORMAL_JOBS=$formal_jobs"
  "COVER_VCD=${COVER_VCD:-1}")

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT
printf '%q ' "${make_cmd[@]}" > "$temporary_dir/command.txt"
printf '\n' >> "$temporary_dir/command.txt"

set +e
nix-shell "$repo_dir/shell.nix" --run "${make_cmd[*]}" 2>&1 | tee "$temporary_dir/run.log"
run_rc=${PIPESTATUS[0]}
set -e

mkdir -p "$output_dir"
mv "$temporary_dir/command.txt" "$temporary_dir/run.log" "$output_dir/"
{
  printf 'run_utc=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'tool=%q\n' "$tool_version"
  printf 'repo_commit=%q\n' "$repo_commit"
  printf 'dut_commit=%q\n' "$dut_commit"
  printf 'role=%q\n' "$role"
  printf 'vendor=%q\n' "$vendor"
  printf 'implementation=%q\n' "$impl"
  printf 'level=%q\n' "$level"
  printf 'fifo_depth=%q\n' "$fifo_depth"
  printf 'fifo_track_depth=%q\n' "$fifo_track_depth"
  printf 'fall_through=%q\n' "$fall_through"
  printf 'allow_bypass=%q\n' "$allow_bypass"
  printf 'max_stall=%q\n' "$max_stall"
  printf 'max_outstanding=%q\n' "$max_outstanding"
  printf 'max_aw_ahead=%q\n' "${MAX_AW_AHEAD:-4}"
  printf 'max_w_ahead=%q\n' "${MAX_W_AHEAD:-4}"
  printf 'max_burst_len=%q\n' "${MAX_BURST_LEN:-8}"
  printf 'bounded_environment_enabled=%q\n' "$enable_bounded_env"
  printf 'transaction_fvip_enabled=%q\n' "$transaction_fvip"
  printf 'max_response_delay=%q\n' "$max_response_delay"
  printf 'max_write_data_delay=%q\n' "$max_write_data_delay"
  printf 'max_role_delay=%q\n' "$max_role_delay"
  printf 'formal_timeout=%q\n' "$formal_timeout"
  printf 'formal_jobs=%q\n' "$formal_jobs"
} > "$output_dir/manifest.env"

if [[ -f "$output_dir/formal_verify.rpt" ]]; then
  nix-shell "$repo_dir/shell.nix" --run \
    "python3 '$script_dir/formal_report.py' '$output_dir/formal_verify.rpt' --output-dir '$output_dir'" \
    || report_rc=$?
  nix-shell "$repo_dir/shell.nix" --run \
    "python3 '$script_dir/inspect_vcd.py' '$output_dir' --output '$output_dir/vcd_inventory.csv'" \
    || vcd_rc=$?
else
  report_rc=1
fi

printf 'command_exit=%d\nreport_exit=%d\nvcd_exit=%d\n' \
  "$run_rc" "${report_rc:-0}" "${vcd_rc:-0}" >> "$output_dir/manifest.env"

if (( run_rc != 0 || ${report_rc:-0} != 0 || ${vcd_rc:-0} != 0 )); then
  exit 1
fi
