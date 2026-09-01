#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)
stamp=${RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
matrix_root=${ODIR:-$repo_dir/work/runs/${stamp}_fifo_matrix}
max_stall=${MAX_STALL:-0}
max_outstanding=${MAX_OUTSTANDING:-1}
max_aw_ahead=${MAX_AW_AHEAD:-1}
max_w_ahead=${MAX_W_AHEAD:-1}
max_burst_len=${MAX_BURST_LEN:-8}
max_response_delay=${MAX_RESPONSE_DELAY:-16}
max_write_data_delay=${MAX_WRITE_DATA_DELAY:-16}
max_role_delay=${MAX_ROLE_DELAY:-100}
enable_bounded_env=${ENABLE_BOUNDED_ENV:-1}
formal_timeout=${FORMAL_TIMEOUT:-5m}
taxi_transaction_max_burst_len=${TAXI_TRANSACTION_MAX_BURST_LEN:-1}
[[ ! -e "$matrix_root" ]] || { echo "Refusing to overwrite $matrix_root" >&2; exit 2; }
mkdir -p "$matrix_root"
printf 'vendor,implementation,depth,track_depth,fall_through,allow_bypass,level,max_stall,max_outstanding,max_response_delay,max_write_data_delay,max_role_delay,max_burst_len,exit,summary\n' > "$matrix_root/matrix.csv"

run_one() {
  local vendor=$1 impl=$2 depth=$3 fall=$4 level=$5 burst=$6
  local track_depth=$depth
  local allow_bypass=$fall
  if [[ "$vendor" == taxi ]]; then
    track_depth=$((depth + 2))
    allow_bypass=1
  fi
  local run_dir="$matrix_root/${vendor}_${impl}_d${depth}_ft${fall}_${level}"
  set +e
  ODIR="$run_dir" VENDOR="$vendor" IMPL="$impl" FIFO_DEPTH="$depth" \
    FIFO_TRACK_DEPTH="$track_depth" \
    FIFO_ALLOW_BYPASS="$allow_bypass" \
    FIFO_FALL_THROUGH="$fall" LEVEL="$level" \
    ENABLE_BOUNDED_ENV="$enable_bounded_env" \
    MAX_STALL="$max_stall" MAX_OUTSTANDING="$max_outstanding" \
    MAX_AW_AHEAD="$max_aw_ahead" MAX_W_AHEAD="$max_w_ahead" \
    MAX_BURST_LEN="$burst" MAX_RESPONSE_DELAY="$max_response_delay" \
    MAX_WRITE_DATA_DELAY="$max_write_data_delay" MAX_ROLE_DELAY="$max_role_delay" \
    FORMAL_TIMEOUT="$formal_timeout" COVER_VCD=0 \
    "$script_dir/run_formal.sh"
  local rc=$?
  set -e
  local summary="missing"
  [[ -f "$run_dir/summary.json" ]] && summary="$run_dir/summary.json"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$vendor" "$impl" "$depth" "$track_depth" "$fall" "$allow_bypass" \
    "$level" "$max_stall" "$max_outstanding" "$max_response_delay" \
    "$max_write_data_delay" "$max_role_delay" "$burst" "$rc" "$summary" \
    >> "$matrix_root/matrix.csv"
}

# Protocol runs omit cross-channel selected-occurrence/rank tracking. Exact
# scoreboards remain isolated in fvip_validation/reference_models.
for depth in 2 4 8 32; do
  run_one zipcpu sfifo "$depth" 0 protocol "$max_burst_len"
  run_one zipcpu sfifo "$depth" 1 protocol "$max_burst_len"
done

# Reuse gate: one small configuration per additional implementation.
run_one pulp axi_fifo 2 0 protocol "$max_burst_len"
run_one taxi taxi_axi_fifo 2 0 protocol "$max_burst_len"

# Full checking adds cross-channel transaction accounting once per implementation.
run_one zipcpu sfifo 2 0 full "$max_burst_len"
run_one pulp axi_fifo 2 0 full "$max_burst_len"
run_one taxi taxi_axi_fifo 2 0 full "$taxi_transaction_max_burst_len"

awk -F, 'NR>1 && $14!=0{bad=1} END{exit bad}' "$matrix_root/matrix.csv"
