# 2x2 crossbar role FVIP

This directory proves a 2x2 AXI crossbar in the same endpoint-plus-role
structure used by the FIFO FVIP. The standalone endpoint FVIP proves AXI
channel and transaction behavior without knowing the DUT role. The crossbar
role layer then relates the four public endpoint views.

## Files

- [`axi_xbar_fvip.sv`](axi_xbar_fvip.sv) is the public aggregate. It creates
  two input endpoint FVIPs and two output endpoint FVIPs with explicit,
  endpoint-local capacity parameters, and optionally instantiates the role
  checker. Output limits are never inferred from the number of input ports.
- [`axi_xbar_role_fvip.sv`](axi_xbar_role_fvip.sv) defines the 2x2 decode and
  source-prefix contract, selects one arbitrary input/source, and contains the
  contention, independent-destination, decode-error, backpressure, and
  different-ID-reordering covers.
- [`stream_trackers.sv`](../../axi_sva/our/stream_trackers.sv) defines
  `fv_xbar_stream_tracker`, which is instantiated once. An arbitrary read/write
  selector makes that one instance prove ordered AW or AR routing for the
  chosen source, destination, ID, and occurrence.
- [`xbar_read_tracker.sv`](xbar_read_tracker.sv) follows an arbitrary AR and
  selected R beat through its decoded output and back to the originating
  input, including the local DECERR path.
- [`xbar_write_tracker.sv`](xbar_write_tracker.sv) follows AW routing, W
  ownership through WLAST, and B return. It handles either AW-before-W or
  W-before-AW at both sides of the crossbar.

## Contract

The output ID is `{source_port, input_id}` and the response ID presented at
the input has the source prefix removed. `ADDR0_BASE`, `ADDR1_BASE`, and
`ADDR_MASK` define the two mappings. `DEFAULT_ENABLE` and `DEFAULT_DEST`
select an optional per-source default destination; otherwise unmapped
requests receive DECERR locally. Region/user preservation and error read data
are explicit wrapper-profile parameters.

Same-ID ordering is proven with arbitrary-ID rank trackers. Different IDs may
reorder, and a cover demonstrates a non-last response beat followed within
eight cycles by a different response ID. No role checker references DUT
hierarchy or endpoint checker internals; it consumes only
`axi_fvip_txn_view_if.Consumer` ports.

The role checker has one `watch_source`, one `watch_route`, and one
`watch_write`. The selected input endpoint's protocol view supplies the
arbitrary ID, beat, occurrence-selector pulse, input response rank, and input
completion state. For a write it also supplies the selected AW's W-pending,
W-rank, and W-completion state; the role retains only the arbitrary W payload
sample needed for integrity. Together these fields choose one input-side
transaction occurrence; the route choice includes output 0, output 1, and the
local-error path. The read and write end-to-end trackers are mutually
exclusive, so only one selected transaction kind accumulates role state.
Separate read and write state machines remain because AXI read return and
AW/W/B lifecycles are structurally different; duplicating them per source or
per destination is unnecessary.

The single stream tracker exports the exact output handshake of the selected
request after its rank reaches zero. Read/write response tracking consumes
that pulse instead of maintaining another copy of route occupancy and rank.
The role also consumes the protocol view's universal signed AW/completed-W
skew, rather than maintaining three duplicate counter pairs. It filters the
one selected occurrence until the chosen output endpoint's arbitrary watch ID
matches `{source, input_watch_id}`, then reuses that endpoint's read/write
outstanding count as well. This filter is eligibility logic, not an
assumption: every output ID remains an arbitrary proof choice. Only the
response-order ranks and W ranks needed to recognize the selected occurrence
among same-ID responses and untagged bursts remain; no array of selected
transaction payloads is stored. Beat counters use the width implied by
`MAX_BURST_LEN` and saturate at the explicit overflow state.

`ENABLE_INPUT_MAX_STALL` is a separate, optional input-READY performance
contract. It defaults off because AXI permits W before AW and does not require
the crossbar to accept that W within a fixed independent deadline.
`ENABLE_MAX_STALL` controls downstream-environment READY fairness, which can
be enabled together with response, W-data, and role progress for a bounded
functional proof.

The input endpoints use `MAX_OUTSTANDING`, `MAX_AW_AHEAD`, and
`MAX_W_AHEAD`. The output endpoints independently use
`MAX_OUTPUT_OUTSTANDING`, `MAX_OUTPUT_AW_AHEAD`, and
`MAX_OUTPUT_W_AHEAD`. This keeps the protocol checker parameter-exact and
role-agnostic: the wrapper/harness declares the capacity of each exposed
endpoint; the protocol checker does not derive it from 2x2 topology.

## Checking levels

For a crossbar, `LEVEL=protocol` enables the complete channel and transaction
endpoint contract on all four interfaces and disables the crossbar role
instance. `LEVEL=full` adds the route, transformation, and response-return
proofs.

```sh
make qverify ROLE=xbar VENDOR=zipcpu IMPL=axixbar LEVEL=protocol
make qverify ROLE=xbar VENDOR=zipcpu IMPL=axixbar LEVEL=full
```

The current execution evidence and open solver-closure status are recorded in
[`docs/c6_execution.md`](../../docs/c6_execution.md).
