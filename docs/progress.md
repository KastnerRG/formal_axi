# AXI Formal VIP: C6 2x2 crossbar handoff

## Latest update: C6 implementation complete, proof closure open

The 2x2 crossbar now follows the same aggregate structure as the FIFO: four
standalone endpoint FVIPs prove role-independent protocol and transaction
safety, and an optional role FVIP consumes only their public views. The role
proof formalizes address decode, `{source, id}` prefix/removal, local DECERR,
same-ID ordering, arbitrary request/beat tracking, W-before-AW, route
conservation, and response return. Required contention, independent
destination, error, backpressure, and different-ID-reordering scenarios are
covered.

The role proof now selects exactly one arbitrary DUT input port and one
transaction occurrence. A single route tracker covers either AW or AR and
exports the selected output handshake to the mutually exclusive read/write
end-to-end trackers, eliminating duplicated per-source/per-destination and
route-rank state. The role directly reuses the selected input protocol
view's ID/beat selector, occurrence pulse, response rank/completion, and the
universal endpoint AW/completed-W skew. This removes the duplicate role input
R/B accounting and six role skew counters. The selected output protocol view
now also supplies same-ID read/write occupancy after an arbitrary output watch
ID is matched to `{source, input_watch_id}`; this removes the remaining four
role-local output occupancy counters without adding an assumption. The input
protocol view also supplies the selected write's W-pending/rank/completion,
removing the role's last duplicate input W lifecycle counter and state bits.
In the latest focused run, all 15 role assertions are nonvacuous and clean and
all 11 role covers complete; the assertions remain inconclusive in the
60-second budget.

ZIPCPU wrapper/core issues exposed by the proof were fixed at their source,
including address masks, output ID width, output-channel skid buffering, and
pending local-error write IDs. Outstanding depths 1, 2, and 4 currently have
zero fired assertions, but time-limited runs still have inconclusive proof
targets. Request-READY and response-READY progress controls are split so the
bounded role proof assumes only environment-owned readiness; its depth-1
smoke also has zero fired assertions and reaches every required C6 scenario
cover. C6's full-proof gate is therefore not yet closed. Commands, counts, and
artifact directories are in [`c6_execution.md`](c6_execution.md).

## Pre-C6 update: bounded endpoint and role architecture closed

The pre-C6 architecture refactor now implements this structure:

```text
per_role_fvip
|-- axi_fvip for every exposed AXI endpoint
|   |-- link safety
|   |-- transaction safety
|   |-- bounded progress/capacity profile
|   `-- public selected-transaction observation view
`-- cross-interface role properties
```

`axi_fvip` must stand alone and completely prove the selected bounded AXI4
normal-transaction profile. It must not know that the DUT is a FIFO, crossbar,
or another role. Assume environment-driven behavior and assert DUT-driven
behavior according to AXI signal ownership; do not switch DUT properties into
assumptions based on a presumed-correct IP role.

The endpoint checker owns reset/VALID rules, stability while stalled, legal
encodings, burst geometry, WSTRB, exact LAST, IDs, AW/W association, AR-to-R,
completed-write-to-B, no orphan/duplicate/early/wrong-ID response, and same-ID
ordering. It also owns the declared bounded profile:

- `MAX_STALL` bounds READY after VALID. Assume it for environment-owned READY
  and assert it for DUT-owned READY.
- `MAX_RESPONSE_DELAY` bounds every required R beat after an accepted AR and B
  after a completed AW+W request. Assume it for environment-owned subordinate
  responses and assert it for DUT-owned subordinate responses. First RVALID is
  not full burst completion.
- `MAX_WRITE_DATA_DELAY` separately bounds AW-to-W completion; AW/W skew limits
  and `MAX_OUTSTANDING` remain capacity bounds, not time bounds.

This is a bounded profile layered on AXI4 protocol safety, not a claim of
unrestricted liveness or universal/full AXI5 compliance. `MAX_STALL` now
follows READY ownership symmetrically. `MAX_RESPONSE_DELAY` is per response
beat, and the distinct `MAX_WRITE_DATA_DELAY` covers elapsed AW-to-W progress.
Deterministic environment lifecycle contracts prevent selector-dependent
assumptions from avoiding illegal occurrences.

Role FVIPs prove what AXI cannot define across independent interfaces. A
silently dropped input followed by a correctly shaped fabricated response can
be AXI-clean but must fail the FIFO role proof. The same applies to unrelated
legal output traffic, wrong crossbar routing, legal `SLVERR` policy, and data
substitution: generic AXI checks structure and bounded progress, while the role
checker proves origin, conservation, transformation, and destination.

For FIFO, choose an arbitrary accepted input occurrence and prove exactly one
matching output in FIFO order with preserved metadata/payload and the correctly
returned response. Also prove inverse conservation/no injection so a
forward-only selected-input proof cannot miss phantom or duplicate outputs.
For crossbar, select an arbitrary input port, ID, destination, occurrence, and
beat/bit; prove unique correct output routing and ID mapping, W ownership
through WLAST, unique response return with restored ID, and no wrong-port copy,
phantom, duplicate, or ordering violation. C6 implements this selection now.

### PULP interface and tracker reuse

Use PULP's existing `AXI_BUS.Monitor` as the common checker signal boundary.
All current vendor wrappers already normalize to `AXI_BUS`, so this still
supports ZIPCPU, Taxi, PULP, and later vendors. Define packed channel types with
PULP's `axi/typedef.svh` macros and use `axi/assign.svh` helpers where useful.
PULP request/response structs are live wire bundles, not replacements for
formal transaction lifecycle state.

Add a separate parameterized public interface, tentatively
`axi_fvip_txn_view_if`, between each `axi_fvip` and its role checker. Give it
producer/consumer modports and expose selected/pending/completed/rank and
outstanding state, the selected packed AR/AW record, an arbitrary selected
W/R beat index and data/strb/resp sample, and response completion. This permits
clean dot notation without coupling the role checker to private hierarchy.
Direct hierarchy is possible only if the exposed names are deliberately kept
under a stable public `view` namespace.

Keep full metadata for only one arbitrary selected transaction, not arrays of
all outstanding transaction payloads or all burst beats. The selector must be
unconstrained and stable so any occurrence can be chosen; selector-dependent
assumptions must not be the only legality checks. Unused observation logic
should fall outside the standalone proof cone, provided it has no `keep`
attributes or covers that retain it.

### Ordered work and acceptance gate

1. [x] Freeze exact ownership and timing definitions for `MAX_STALL`, per-beat
   `MAX_RESPONSE_DELAY`, and optional `MAX_WRITE_DATA_DELAY`.
2. [x] Add `axi_fvip_txn_view_if` using PULP packed channel records.
3. [x] Refactor `axi_fvip` to take `AXI_BUS.Monitor` and expose the read/write
   transaction views; retain only thin polarity wrappers if they add value.
4. [x] Move generic bounded endpoint assumptions/assertions out of the FIFO
   harness and remove the obsolete `tb/fifo_response_env.sv`.
5. [x] Create the `per_role_fvip` structure and rewrite FIFO properties to consume
   endpoint views, adding forward and inverse conservation, uniqueness,
   ordering, payload, and response checks.
6. [x] Re-run endpoint polarity/progress mutations and FIFO role mutations. Seed
   no-READY/no-response, drop-with-fabricated-response, unrelated/phantom,
   duplicate, corrupt, reorder, and response-misassociation cases.
7. [x] Start C6 only when standalone AXI proves without role modules; protocol and
   bounded-progress faults fail at the endpoint; role-only faults remain
   AXI-clean but fail the FIFO role checker; required covers are reached; and
   no unexplained failures, inconclusives, or vacuity remain.

The architecture gate closes at depth 2 with `MAX_STALL=0`, one outstanding
transaction, outer response/write-data delays of 16 cycles, and a 16-cycle
role bound. `work/runs/20260901_arch_fifo_formal_05` resolved all 231 targets: all
163 assertions proved, 53 covers were reached, and the remaining 15 covers
were classified uncoverable for this profile. Endpoint polarity mutations are
in `work/runs/20260901_arch_link_04`; transaction mutations are in
`work/runs/20260901_arch_txn_mut_02`; FIFO role mutations are in
`work/runs/20260901_arch_fifo_mut_02`.

The 45 vacuous assertions in that closure run are all reset/under-stall link
properties whose antecedents are excluded by the zero-stall profile. The link
mutation suite activates the relevant stalls in both ownership polarities and
demonstrates that the properties fire. The 15 uncoverable covers are the
corresponding valid-before-ready cases, rank-greater-than-zero cases excluded
by one outstanding transaction, and selected-behind-data cases excluded by
the always-ready depth-2 configuration; they are not required closure covers.

Keep exact reference models validation-only under `fvip_validation/`. The
detailed contract, implementation sequence, and gate are also recorded in
`docs/plan.md` under "Immediate architecture refactor before C6." The historical
sections below describe the superseded pre-refactor implementation and its
evidence.

## Historical pre-refactor record: smart-only FVIP and validation split

This section records the C0-C5 state before the architecture refactor above.
Its file placement and progress-policy statements are historical; the
selected-occurrence design rationale and old run evidence remain useful.

- The split transaction sources (`axi_read_tracker.sv`, `axi_pair_tracker.sv`,
  `axi_write_tracker.sv`, and `axi_transaction_fvip.sv`) contain no arrays
  indexed by outstanding transactions. Production state consists of selected AR/R,
  selected AW/completed-W, selected AW/B rank trackers, scalar global
  read/write outstanding counts, scalar W beat counts, and one arbitrary
  WSTRB beat sample.
- `per_role_fvip/fifo/` contains only the selected-occurrence
  production FIFO tracker and role integration. The exact FIFO queue remains
  validation-only.
- All verifier-verification material is now under `fvip_validation/`:
  exact bounded models in `reference_models/`, mutation harnesses in `tb/`,
  Questa files in `qverify/`, and runners in `tools/`.
- Exact reference models are
  `fvip_validation/reference_models/fifo_oracle.sv` and
  `fvip_validation/reference_models/axi_transaction_oracle.sv`. They are
  validation-only and absent from production FIFO closure file lists.
- `MAX_OUTSTANDING` remains a typed AXI FVIP parameter and is enforced by
  scalar global counters. `MAX_STALL` also remains inside the link FVIP.
  `MAX_RESPONSE_DELAY` remains outside it, in the FIFO-role environment.
- `TRACK_RESPONSE_AGE`, `ENABLE_FIFO_ORACLE`, and
  `ENABLE_TRANSACTION_ORACLE` were removed from the production path. The
  production enable is now `ENABLE_TRANSACTION_FVIP` /
  `AXI_ENABLE_TRANSACTION_FVIP`.

Latest proof/validation artifacts:

- Smart-only ZIPCPU C5 closure:
  `work/runs/20260901T_smart_c5_tight_skew_fifo_zipcpu_sfifo_d2_ft0` — all 150
  assertions proven (103 nonvacuous, 47 vacuous), zero fire/inconclusive,
  51 covers reached, 17 uncoverable; 174-second proof time.
- Dual-model transaction validation:
  `work/runs/20260901T_smart_final_transaction_transaction_mutations` — all 13
  scenarios reached, nine protocol mutations detected by both exact and smart
  models, bounded deadlock detected by the smart/environment policy, good and
  rank-compaction cases clean, zero inconclusive.
- Relocated FIFO validation:
  `work/runs/20260831T_relocated_fifo_final_mutations` — six mutations detected by
  both exact and smart models, good case clean, zero inconclusive.
- Relocated link validation: `work/runs/20260901T062117Z_link_mutations` — intended
  manager and subordinate stability mutations detected.

## Start here in a new session

Workspace requested by the user:

`/home/a.gnaneswaran.251/scratch/formal_veri/formal_axi`

That path resolves to:

`/scratch/krg/a.gnaneswaran.251/formal_veri/formal_axi`

Repository state when this handoff was written:

- Root branch: `aba-mvp`
- Root HEAD: `f51e2fad50b13199e881287b7585dc64b90729a1`
- `soc-testbed` gitlink: `1bf3fcfebb5ce17740f251658b0e045331d02902`
- The worktree/index contains the C0-C5 implementation, documentation, formal
  artifacts, and generated databases. `docs/progress.md` was newly created after
  the other changes were staged.
- Do not reset, clean, delete, or blindly restage the worktree. Existing
  changes and generated results must be preserved. Review `git status` and
  exclude `work/`, `modelsim.ini`, and `vish_stacktrace.vstf` when a concise
  source-only diff is needed.
- `axi4.txt` and `axi4_issue_d.txt` are ignored by the repository's `*.txt`
  rule, so their absence from `git status` does not mean they are absent.

Read these files first:

1. `docs/progress.md` — this handoff.
2. `docs/plan.md` — milestones, gates, and remaining C6-C8 plan.
3. `docs/c0_c5_execution.md` — exact C0-C5 results and artifact directories.
4. `docs/axi4_mvp_profile.md` — supported protocol and property classes.
5. `docs/formal_runs.md` — run parameters and artifact semantics.
6. `axi_sva/our/axi_fvip.sv`, the split transaction tracker sources, and
   `per_role_fvip/fifo/` — checker implementation.
7. `tb/tb_fifo.sv` and `tb/tb_xbar.sv` — completed FIFO harness and current
   crossbar smoke harness.

Current milestone status: C0-C5 and the bounded-AXI/per-role architecture
refactor are implemented and exercised under their explicitly declared
bounds. The standalone endpoint and FIFO-role validation gate is closed; C6 is
the next milestone.

Suggested new-session request:

> Read `docs/progress.md` and `docs/plan.md`, preserve the dirty worktree and existing
> formal artifacts, then begin C6 by reusing the closed standalone endpoint
> FVIP and public transaction views in the 2x2 crossbar role aggregate.

## Project goal and architectural direction

The project is building a small reusable AXI formal VIP for SoC IP in
`soc-testbed`, beginning with transparent FIFOs and then moving to crossbars,
converters, RAM-like blocks, firewalls, and eventually DMA-specific functional
models.

The checker is intentionally split into four layers:

1. **Link checker:** local AXI channel rules such as reset, VALID stability,
   payload stability while stalled, encodings, burst geometry, LAST, WSTRB,
   IDs, and responses.
2. **Transaction checker:** cross-channel AR/R, AW/W, and completed-write/B
   association and ordering under explicit capacity bounds.
3. **Role adapter/checker:** the DUT-specific transformation. For a FIFO this
   is identity and ordering; for a crossbar it will be address routing, ID
   transformation, and response return routing.
4. **Profiles:** AXI4 normal transactions are enabled now. Exclusives, ATOP,
   richer AXI5 features, and performance/progress policies are separate
   profiles and must never be counted as base protocol proofs.

The core modeling principle is selected-occurrence tracking plus bounded
relative rank. No counter counts transactions since reset. Exact bounded
queues exist only as executable small-depth references under
`fvip_validation/`.

## Supported protocol profile

The current profile is:

- AMBA AXI4 Full, Issue H.c.
- Five-channel VALID/READY transport.
- Normal transactions only.
- `AxLOCK=0`; exclusives and `EXOKAY` are disabled.
- `AWATOP=0`; there is no AXI4+ATOP or full AXI5 claim.
- The reusable transaction FVIP defaults to four outstanding reads/writes and
  AW/W skew of four in either direction. The bounded FIFO runner defaults to
  one outstanding transaction in each of the read and write directions for C5
  closure. The default maximum burst length is eight beats.
- `MAX_OUTSTANDING`, `MAX_AW_AHEAD`, `MAX_W_AHEAD`, and `MAX_BURST_LEN` are
  verification-model capacity contracts, not architectural AXI limits.
- `MAX_STALL` and `MAX_RESPONSE_DELAY` are opt-in bounded-environment/progress
  contracts, not AXI compliance rules.

The AXI4 inventories contain 53 rule rows: 36 implemented, 15 not applicable
to the selected MVP, and 2 partial. The recommendation inventory contains one
implemented and two policy-only rows. The AXI5 Issue L inventory records one
implemented transport item, one disabled item, and twelve missing feature
areas rather than implying AXI5 coverage.

Relevant files:

- Official source: `papers/IHI0022H_c_amba_axi_protocol_spec.pdf`
- Extracted source: `axi4.txt`
- Archived older source: `axi4_issue_d.txt`
- AXI4 status: `docs/axi4_our_status.csv`
- AXI4 comparison inventories: `docs/axi4_rule_coverage.csv` and
  `docs/axi4_recommendation_coverage.csv`
- AXI5 inventory: `docs/axi5_issue_l_inventory.csv`

Property naming/classification:

| Prefix/context | Meaning |
|---|---|
| `a_` on an environment source | Assumption about the external agent |
| `a_` on a DUT source | Interface guarantee/assertion |
| `x_` | Cross-channel role-dependent assumption or guarantee |
| `c_profile_`, `c_max_` | Configuration/profile assumption |
| `p_` | Optional bounded-progress policy |
| Other `c_` | Reachability cover |

## Common checker implementation

### Compile-time polarity

`axi_sva/our/axi_switch_fvip.svh` compiles the shared source twice:

- `m_axi_fvip` checks an AXI Manager agent. Manager request-channel rules are
  assumptions and subordinate response-channel rules are assertions.
- `s_axi_fvip` checks an AXI Subordinate agent. DUT request outputs are
  assertions and external response inputs are assumptions.
- `TXN_SOURCE` and `TXN_DEST` apply the same polarity to cross-channel rules.

`axi_sva/m_sva_wrap.sv` and `axi_sva/s_sva_wrap.sv` pass `AXI_BUS.Monitor`
directly to the endpoint checker. Disabled third-party ARM, Yosys, and ZipCPU
checker wrappers remain commented out; the active implementation is `u_our`.

For a pass-through FIFO:

- `i_slv_fvip` is the upstream Manager checker.
- `i_mst_fvip` is the downstream Subordinate checker.
- The FIFO role checker compares upstream and downstream handshakes/payloads.

### Link checker

The link checker is `axi_sva/our/axi_channel_fvip.sv`. It consumes the complete
`AXI_BUS.Monitor` directly, groups properties by AXI rule in specification
order, and selects assume/assert polarity from signal ownership. Common
functions remain in `axi_sva/our/pkg_axi_fvip.sv`; endpoint integration and
reset assumptions remain in `axi_sva/our/axi_fvip.sv`.

The module implements reset/VALID rules, unknown checks, all payload fields
stable while stalled, burst size/type/length/alignment/4KB rules, response
encoding, and explicit exclusion of exclusives, EXOKAY, and ATOP. Legal FIXED
and WRAP burst covers are separate. WSTRB legality, exact WLAST/RLAST placement,
and request/response association remain in the cross-channel transaction
checker.

Reset is modeled as clock-aligned and non-reasserting after release. Checker
state and FIFO models use asynchronous reset so a reset pulse cannot leave stale
modeled transactions.

`MAX_STALL` is a typed parameter of the common FVIP. When enabled its polarity
follows ownership:

- Downstream environment: `AWREADY`, `ARREADY`, `WREADY`.
- Upstream environment: `RREADY`, `BREADY`.
- Environment-driven READY is assumed; DUT-driven READY is asserted.

The unified-channel regression is
`work/runs/20260901_unified_channel_fifo_formal_01`: all 89 assertions and 68 covers
resolved, with 53 covers reached. The 10 vacuous assertions are exactly the
five VALID-stall and five bundled payload-stall rules expected under the
closure profile's `MAX_STALL=0`; the reset-low rules are nonvacuous. Companion
artifacts are `work/runs/20260901_unified_channel_link_mut_02` (exactly four
intended fires), `work/runs/20260901_unified_channel_txn_mut_01` (15/15 scenarios),
and `work/runs/20260901_unified_channel_fifo_mut_01` (7/7 scenarios).

### Per-channel FIFO selected tracker

`per_role_fvip/fifo/` is production-only. It contains separate
sources for:

- `fv_fifo_tracker`: a selected-occurrence tracker with scalar occupancy and
  relative rank.
- `fv_axi_fifo_fvip`: packs all fields for AW, W, B, AR, and R and instantiates
  one tracker independently for each channel.

The tracker checks no phantom output, no overflow, order, payload preservation,
simultaneous push/pop, optional bypass, and optional bounded progress. Duplicate
payload values are legal; no uniqueness assumption is used. The exact bounded
shadow queue is now only
`fvip_validation/reference_models/fifo_oracle.sv`; mutation validation compares
it with the production tracker at small depth.

Important optimization status:

- The five channels are already proved separately.
- The selected tracker currently captures the **full packed channel payload**
  in `watched_data`, not one arbitrary payload bit. Arbitrary-bit tracking is a
  possible future state-space reduction but has not been implemented.
- `a_watched_integrity` is safety only: if the selected item emerges at rank
  zero, the payload must match. It does not itself guarantee eventual output.

### Cross-channel transaction checker

The split transaction checker sources implement three relations:

1. **AR to R:** one arbitrary stable ID and one selected AR occurrence are
   tracked by relative same-ID rank, captured ARLEN, and current response beat.
2. **AW to completed W burst:** a signed scalar skew and selected occurrence
   pair AW and completed-W streams in either arrival order. WLAST uses scalar
   beat counts; WSTRB legality samples one arbitrary beat, covering every beat
   without an array or one generated proof target per beat.
3. **AW/W to B:** one selected AW is tracked through its W pairing and ordered
   same-ID B response. An arbitrary-ID scalar count rejects phantom,
   duplicate, wrong-ID, and early B responses.

Global scalar read/write counters enforce `MAX_OUTSTANDING` for every
transaction. This is separate from selected-occurrence state because a
selector-dependent assumption would not universally constrain a formal
environment.

That distinction also applies to transaction legality. Selected-occurrence
properties are sound universal assertions: a DUT fault can be exposed by
choosing the faulty occurrence. They are not sound as universal environment
assumptions, because the solver could choose a different occurrence. The
bounded FIFO C5 harness therefore supplies deterministic scalar source and
subordinate contracts in `tb/fifo_response_env.sv`; other role harnesses must
provide an equivalent legal environment for their declared capacity profile.

The reusable symbolic helpers are:

- `*_axi_read_tracker` and `*_axi_write_tracker`: select one request for one
  arbitrary ID and track its bounded rank. Questa 2023.2 did not reliably
  preserve `anyconst` as constant, so `s_watch_id_constant` explicitly assumes
  `$stable(watch_id)`.
- `*_axi_pair_tracker`: selects one side of two ordered streams, stores its
  payload summary, and tracks signed A-ahead/B-ahead skew. A previous one-bit
  signed literal bug inverted the skew update and was fixed during mutation
  validation.

No production array dimension depends on `MAX_OUTSTANDING`. The old exact
bounded queues live in
`fvip_validation/reference_models/axi_transaction_oracle.sv`, where they are
used only beside mutation harnesses. `ENABLE_TRANSACTION` compiles the smart
transaction checker in or out.

## FIFO-role implementation and bounded progress

### Typed DUT/wrapper parameters

`tb/tb_fifo.sv` has typed top-level parameters for:

- `AXI_FIFO_DEPTH`
- `AXI_FIFO_FALL_THROUGH`
- `AXI_FIFO_TRACK_DEPTH`
- `AXI_FIFO_ALLOW_BYPASS`
- `AXI_MAX_STALL`
- `AXI_MAX_OUTSTANDING`
- `AXI_MAX_RESPONSE_DELAY`
- `AXI_ENABLE_BOUNDED_ENV`

The common harness passes depth/fall-through to each role wrapper. The three
wrappers now expose `AXI_FIFO_DEPTH` and `AXI_FIFO_FALL_THROUGH` parameters
instead of consuming macros:

- `soc-testbed/axi/ip/zipcpu/impl_wrappers/fifo/sfifo/wrapper.sv`
- `soc-testbed/axi/ip/pulp/impl_wrappers/fifo/axi_fifo/wrapper.sv`
- `soc-testbed/axi/ip/taxi/impl_wrappers/fifo/taxi_axi_fifo/wrapper.sv`

These wrapper changes are in the clean `soc-testbed` commit named above; the
root repository records the updated submodule gitlink.

Taxi contains extra elastic storage relative to the requested FIFO depth. Its
checker profile therefore uses `FIFO_TRACK_DEPTH=FIFO_DEPTH+2` and
`FIFO_ALLOW_BYPASS=1`.

### `MAX_RESPONSE_DELAY` placement and semantics

AXI itself permits an arbitrary subordinate response delay, so
`MAX_RESPONSE_DELAY` is intentionally **not** an AXI FVIP policy parameter. It
is a FIFO-role environment assumption in `tb/tb_fifo.sv`.

`tb/fifo_response_env.sv` implements the bounded FIFO environment. A property
local variable captures each AR ID and completed AW+W ID, so the response-start
deadline applies to every complete request without an explicit outstanding array. The same file
supplies deterministic scalar legality assumptions for the
one-outstanding-per-direction closure profile: AW precedes W at the source,
WLAST/WSTRB match the captured AW geometry, RID/RLAST match the pending AR, and
B is allowed only after both AW and W completion.

`MAX_RESPONSE_DELAY` bounds the first matching `RVALID`/`BVALID` after the
corresponding request; READY may still be low. `tools/run_formal.sh` validates
the delay in `1..255`. The legal transaction mutation cases now check selected
read/write **rank compaction**, not removed response-age arrays.

`ENABLE_BOUNDED_ENV=0` disables both READY-delay and subordinate-response-delay
assumptions. The FIFO checker's older `ENABLE_PROGRESS` mechanism is explicitly
off in `tb_fifo`; the external role policy is the sole response-progress bound.

## Reproducible formal infrastructure

Tool/runtime:

- Questa Static Verification 2023.2_2:
  `/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin/qverify`
- Source `~/bashrc-new` from interactive Bash for license variables. Never
  print or save license-server values.
- `shell.nix` supplies host `libXau` and `csh` compatibility dependencies.
- The runner re-enters interactive Bash once, sources the license setup
  silently, and then uses `nix-shell`.

Primary flow files:

- `Makefile`: selects `ROLE/VENDOR/IMPL`, builds the generated file list, and
  passes common profile values.
- `qverify/flist.f`: common checker sources.
- `qverify/run_formal.do`: compiles, applies FIFO top parameters through `-G`,
  runs `formal verify`, honors `FORMAL_TIMEOUT`, and generates waveforms.
- `tools/run_formal.sh`: validates parameters, creates a never-overwritten run,
  captures exact command/tool/source/profile metadata, parses reports, and
  validates exported VCDs.
- `tools/formal_report.py`: writes `property_status.csv`,
  `vacuity_status.csv`, and `summary.json`; it returns nonzero for fired,
  inconclusive, skipped, unsupported, or incompletely audited properties.
- `tools/inspect_vcd.py`: non-GUI structural inspection of generated VCDs.
- `tools/run_fifo_matrix.sh`: curated FIFO matrix.

Every normal run contains `manifest.env`, `command.txt`, generated `flist.f`,
raw logs/reports, `property_status.csv`, `vacuity_status.csv`, `summary.json`, and
`vcd_inventory.csv`. A timeout is handled through QVerify's own `-timeout` so a
complete inconclusive report is still produced. Never reuse an existing output
directory; the scripts intentionally refuse to overwrite one.

Useful commands:

```sh
# One default FIFO run (runner defaults, not the Makefile's xbar default)
tools/run_formal.sh

# Curated bounded C5 matrix
tools/run_fifo_matrix.sh

# Validation suites
fvip_validation/tools/run_link_mutations.sh
fvip_validation/tools/run_fifo_mutations.sh
fvip_validation/tools/run_transaction_mutations.sh
```

The closed combined FIFO profile can be reproduced with fresh timestamps:

```sh
# ZIPCPU, eight beats
VENDOR=zipcpu IMPL=sfifo FIFO_DEPTH=2 FIFO_FALL_THROUGH=0 \
  MAX_STALL=0 MAX_OUTSTANDING=1 MAX_AW_AHEAD=1 MAX_W_AHEAD=1 \
  MAX_BURST_LEN=8 MAX_RESPONSE_DELAY=4 ENABLE_BOUNDED_ENV=1 \
  LEVEL=full FORMAL_TIMEOUT=3m \
  COVER_VCD=0 tools/run_formal.sh

# PULP, eight beats
VENDOR=pulp IMPL=axi_fifo FIFO_DEPTH=2 FIFO_FALL_THROUGH=0 \
  MAX_STALL=0 MAX_OUTSTANDING=1 MAX_AW_AHEAD=1 MAX_W_AHEAD=1 \
  MAX_BURST_LEN=8 MAX_RESPONSE_DELAY=4 ENABLE_BOUNDED_ENV=1 \
  LEVEL=full FORMAL_TIMEOUT=3m \
  COVER_VCD=0 tools/run_formal.sh

# Taxi combined closure, one beat
VENDOR=taxi IMPL=taxi_axi_fifo FIFO_DEPTH=2 FIFO_TRACK_DEPTH=4 \
  FIFO_FALL_THROUGH=0 FIFO_ALLOW_BYPASS=1 MAX_STALL=0 \
  MAX_OUTSTANDING=1 MAX_AW_AHEAD=1 MAX_W_AHEAD=1 MAX_BURST_LEN=1 \
  MAX_RESPONSE_DELAY=4 ENABLE_BOUNDED_ENV=1 LEVEL=full \
  FORMAL_TIMEOUT=3m COVER_VCD=0 \
  tools/run_formal.sh
```

Note that direct `make qverify` defaults to the ZIPCPU `axixbar` role, whereas
`tools/run_formal.sh` defaults to the ZIPCPU `sfifo` role. Always specify role
and implementation explicitly when ambiguity matters.

## C0-C5 results

### C0: reproducible baseline

Result: pass.

Artifact: `work/runs/20260831T_c0_final_v2`

- 143 nonvacuous assertions proven.
- 5 reset-low assertions vacuously proven.
- 61 covers reached.
- No fired, inconclusive, skipped, or unsupported target.
- All 61 exported VCDs passed structural inspection.
- Formal time: 3 s elapsed, 25 CPU-s, 1.8 GB aggregate peak, 0.3 GB maximum
  per engine, 8 engines.

The five vacuities are per-channel `a_valid_low_after` reset properties. Questa
initializes the symbolic VALID inputs low, leaving no nontrivial antecedent.
They are classified rather than silently counted as active evidence.

Remaining compile warnings are classified in
`docs/warning_classification.csv`: upstream PULP generic-interface folding for
zero-width template fields is benign, and known third-party `vlog-2892`
parameter compatibility messages are suppressed explicitly.

### C1: frozen protocol profile and inventories

Result: pass.

- Installed/audited AXI4 Issue H.c.
- Archived the prior Issue D text.
- Added `our_status` to AXI4 coverage inventories.
- Added a separate AXI5 Issue L feature inventory.
- Disabled exclusives, EXOKAY, and ATOP explicitly.
- Classified model capacity separately from protocol and progress policy.

### C2: link checker and polarity

Result: mutation gate pass.

Latest artifact: `work/runs/20260831T_c5_link_mutations`

The test deliberately changes AWADDR/drops AWVALID while stalled on a Manager
source and changes BRESP/drops BVALID while stalled on a Subordinate source.
The expected four properties fire:

- Manager AW address-stability and VALID-stability assertions.
- Subordinate B response-stability and VALID-stability assertions.

There are no inconclusive results. The narrow mutation harness has expected
vacuous/unreachable legal-burst targets.

The assertion-trigger audit is complete. Questa's conclusive vacuity result is
the default reachability evidence; a duplicate cover is not added for every
antecedent. Explicit covers remain for useful scenarios, including legal
W-before-AW behavior. Optional transaction, exclusive, and ATOP properties are
classified as feature-disabled when their profile does not elaborate them.

Post-audit FIFO artifacts:

- `work/runs/20260901_reachability_fifo_zipcpu_protocol_s8_final`: 69/69
  assertions proven and nonvacuous; 36/36 covers reached with backpressure.
- `work/runs/20260901_reachability_fifo_zipcpu_full_s0_b8`: 89/89 assertions
  proven; all 89 vacuity checks resolved. Ten stall triggers are unreachable
  by the recorded zero-stall policy.

The relaxed one-beat full `MAX_STALL=8` profile closes in one fresh 32-job run:
`work/runs/20260901_close_fifo_zipcpu_full_s8_b1_j32`. All 157 targets resolved
in 248 seconds: all 89 assertions proved, all 89 vacuity checks completed, 52
covers reached, 16 covers were proven unreachable, and there were zero fired
or inconclusive targets. The four vacuous assertions are exactly the WRAP
triggers incompatible with the one-beat profile. Peak use was 32 cores and
23.5 GB aggregate memory. Earlier 8-job runs rotated which two deep transaction
properties timed out, so their inconclusives were portfolio-resource limits,
not stable property or model failures.

### C3/C4: bounded oracle and symbolic abstraction

Result: pass.

Latest channel artifact: `work/runs/20260831T_relocated_fifo_final_mutations`

| Scenario | Exact oracle | Selected tracker |
|---|---:|---:|
| Good | clean | clean |
| Phantom | detected | detected |
| Drop | detected | detected |
| Duplicate | detected | detected |
| Corrupt | detected | detected |
| Reorder | detected | detected |
| Deadlock | detected | detected |

No result is inconclusive. The oracle and abstraction therefore have matching
7-case scores, including the good case.

Latest transaction artifact:

`work/runs/20260901T_smart_final_transaction_transaction_mutations`

All sequences are reachable. The good trace is clean. All ten faults are
detected by intended properties with no unexpected fire or inconclusive:

1. R before AR.
2. Early RLAST.
3. B before completed AW+W.
4. W beat count inconsistent with AWLEN.
5. Illegal WSTRB.
6. Wrong RID.
7. Wrong BID.
8. Same-ID read reorder.
9. Bounded response deadlock.
10. Duplicate B.

Scenarios 11 and 12 are legal selected-read/selected-write rank-compaction
checks; both remain assertion-clean and prove the selected younger occurrence
advances when the older response is removed.

### C5: AXI FIFO

Result: pass under a bounded environment, with a Taxi burst qualification.

Closed combined profile:

| Parameter | Value |
|---|---:|
| `ENABLE_BOUNDED_ENV` | 1 |
| `MAX_STALL` | 0 |
| `MAX_OUTSTANDING` | 1 |
| `MAX_AW_AHEAD` | 1 |
| `MAX_W_AHEAD` | 1 |
| `MAX_RESPONSE_DELAY` | 4 |
| FIFO depth | 2 |

`MAX_STALL=0` means the relevant environment-driven READY is asserted in the
same cycle as VALID. This is much stronger than unrestricted AXI behavior and
must be stated whenever these proofs are reported.

Combined results:

| Implementation | Burst | Assertions | Covers | Time |
|---|---:|---|---|---:|
| ZIPCPU `sfifo` | 8 | 175/175 proven, including 45 vacuous | 74 covered, 23 uncoverable | 142 s |
| PULP `axi_fifo` | 8 | 185/185 proven, including 50 vacuous | 74 covered, 23 uncoverable | 55 s |
| Taxi `taxi_axi_fifo` | 1 | 178/178 proven, including 62 vacuous | 63 covered, 39 uncoverable | 18 s |

Latest smart-only ZIPCPU rerun after removing the production exact arrays and
replacing per-beat WSTRB targets with one arbitrary-beat property: 150/150
assertions proven (103 nonvacuous, 47 vacuous), 51 covers reached, zero
fire/inconclusive, in 174 seconds. Artifact:
`work/runs/20260901T_smart_c5_tight_skew_fifo_zipcpu_sfifo_d2_ft0`.

No closed run has a fired or inconclusive assertion.

Artifacts:

- ZIPCPU: `work/runs/20260831T_c5_response_start_zip_fifo_zipcpu_sfifo_d2_ft0`
- PULP: `work/runs/20260831T_c5_response_start_pulp_fifo_pulp_axi_fifo_d2_ft0`
- Taxi: `work/runs/20260831T_c5_response_start_taxi_b1_fifo_taxi_taxi_axi_fifo_d2_ft0`

ZIPCPU depth-32 independent-channel closure:

| Configuration | Result | Artifact |
|---|---|---|
| Registered | 133/133 proven in 4 s | `work/runs/20260831T_c5_d32_reg_s0_fifo_zipcpu_sfifo_d32_ft0` |
| Fall-through | 138/138 proven in 14 s | `work/runs/20260831T_c5_d32_ft_s0_fifo_zipcpu_sfifo_d32_ft1` |

ZIPCPU depths 2/4/8 also have registered and fall-through channel closure in
the earlier matrix artifacts. Current production matrices use the selected
tracker at every depth; exact models are now confined to `fvip_validation/`.

### Taxi burst-8 qualification

Taxi is not architecturally limited to one-beat bursts. Burst 1 is a formal
closure concession for the combined transaction run.

The eight-beat Taxi experiment is:

`work/runs/20260831T_c5_taxi_close_fifo_taxi_taxi_axi_fifo_d2_ft0`

After the 300-second cap:

- No property fired.
- 180 assertions were proven.
- Five assertions remained inconclusive.
- The unresolved targets were downstream transaction-checker WSTRB properties
  for beats 1, 2, 3, 5, and 6.

Taxi's elastic buffering makes the AW metadata/completed-W association and
per-beat strobe proof harder. `tools/run_fifo_matrix.sh` exposes
`TAXI_TRANSACTION_MAX_BURST_LEN`, currently defaulting to 1. Channel-level
preservation remains exercised at eight beats, but an apples-to-apples combined
eight-beat claim across all three vendors has not closed.

Possible follow-up approaches are to partition WSTRB properties per beat,
prove an AW/W-pair preservation lemma compositionally, or reduce WSTRB state to
one arbitrary byte lane. Do not report the existing Taxi burst-8 run as a
failure or as a full proof; it is bounded/inconclusive.

### Stress reachability versus safety closure

The zero-stall closure profile makes some stress covers unreachable. Separate
relaxed runs retain stress evidence:

- `work/runs/20260831T_zipcpu_transactions_final_v2`: all 97 depth-2 combined covers
  reached; 20 assertions remained inconclusive after 569 s.
- `work/runs/20260831T_c5_close_d2_s1_o2_r4_fifo_zipcpu_sfifo_d2_ft0`: 164 assertions
  resolved, 11 inconclusive, 96 covers reached, 1 uncoverable after 300 s.
- `work/runs/20260831T_c5_d32_reg_s1_fifo_zipcpu_sfifo_d32_ft0`: all 36 depth-32
  covers reached, including full-queue/backpressure behavior, but 28 assertions
  remained inconclusive after 300 s.
- `work/runs/20260831T_fifo_matrix_v2_fifo_matrix`: earlier registered and
  fall-through depth-32 runs also reach all 36 channel covers.

These are reachability experiments only. There is no current assertion-closure
claim for unrestricted backpressure or for one-cycle-stall depth 32. The user
explicitly accepted that unrestricted backpressure does not need to be proved
for this C5 milestone.

## Known limitations and cautions

- C5 closure is a bounded environment proof, not general AXI liveness.
- `MAX_OUTSTANDING` is a chosen model limit even though AXI itself has no fixed
  maximum.
- `a_watched_integrity` does not prove eventual output; response and READY
  bounds provide the relevant environmental progress.
- Selector-dependent properties are suitable as universal assertions, but not
  as the sole legality assumptions for an unconstrained source. The bounded C5
  profile therefore uses deterministic scalar source/subordinate state in
  `tb/fifo_response_env.sv`.
- The selected FIFO tracker stores the full payload vector. Arbitrary-bit
  payload tracking is not yet implemented.
- Taxi combined burst 8 is inconclusive only in five higher-beat WSTRB
  assertions; the burst-1 result must not be presented as a Taxi limitation.
- Many closed-run assertions are vacuous because of disabled features, strong
  environment bounds, or architecture-specific unreachable situations. Use
  the cover evidence and property reports rather than quoting only the total
  proven count.
- C2 trigger reachability uses the conclusive vacuity audit; explicit covers
  are required only when that audit cannot decide or when a useful scenario
  waveform is desired.
- The current `qverify/run_formal.do` applies typed top-level `-G` overrides
  only when `ROLE=fifo`. C6 will need a corresponding xbar parameter surface.
- Generated run databases are large and currently present in the repository
  state. Do not add/remove them casually in a new session.

## C6 starting point: 2x2 crossbar

This section is design input for C6, not the immediate task. Do not execute its
sequence until the bounded-AXI/per-role refactor and validation gate at the top
of this handoff have closed.

`tb/tb_xbar.sv` currently instantiates a 2x2 DUT and per-link FVIPs, but it is
only a smoke/link harness. It does **not** prove end-to-end address routing,
request preservation, W-route locking, ID transformation, or response return
routing.

Recommended first implementation: PULP `axi_xbar`, because its wrapper exposes
the intended contract clearly:

- Wrapper:
  `soc-testbed/axi/ip/pulp/impl_wrappers/xbar/axi_xbar/wrapper.sv`
- Two 64 KiB windows:
  - output 0: `[0x0000_0000, 0x0001_0000)`
  - output 1: `[0x0001_0000, 0x0002_0000)`
- Default master port is disabled, so unmapped-address behavior must be
  specified/tested rather than guessed.
- PULP widens the output ID from `MST_ID_W` to
  `MST_ID_W+$clog2(NUM_MST)` and uses the ingress port as part of response
  routing.

Do not assume every wrapper has the same ID transformation:

- PULP and Taxi expose a widened outgoing ID.
- ZIPCPU `axixbar` preserves its incoming ID internally; its wrapper
  zero-extends into the common wider `AXI_BUS` port. It tracks source routing
  internally instead of exposing a source-port prefix.

The C6 role checker therefore needs an explicit per-wrapper ID mapping contract,
not a universal hard-coded prefix rule.

Suggested implementation sequence:

1. Make `tb_xbar.sv` formal-top friendly like `tb_fifo.sv`: external formal
   clock/reset ports under `AXI_FVIP_FORMAL`, typed `NUM_MST/NUM_SLV`, bounds,
   and any address/ID-map parameters needed by the role checker.
2. Add a reusable `axi_xbar_fvip.sv` role checker. Keep it external to the DUT
   and avoid design-specific internal signal references.
3. Split proof scenarios rather than building one monolithic scoreboard:
   - AR request route and payload/ID transform.
   - R return to the selected source with original ID.
   - AW route selection.
   - W stream locked to the selected AW destination through WLAST.
   - Completed write/B return to the originating source.
4. Select an arbitrary ingress port, ID, destination, and request occurrence;
   reuse the existing selected-occurrence/rank machinery where possible.
5. Define unmapped/default/error behavior explicitly. Do not silently assume a
   DECERR path when the selected wrapper disables its default port.
6. Pass `MAX_STALL`, `MAX_OUTSTANDING`, AW/W skew, and burst bounds through the
   per-link FVIP parameters. If finite downstream response time is required for
   closure, keep that policy in the xbar role harness and reuse downstream
   role-local scalar/property state, as done for the FIFO.
7. Add crossbar mutation models before trusting closure: wrong destination,
   dropped/duplicated request, ID-prefix error, response to wrong source,
   W routed away from AW, premature route unlock, and same-ID reorder.
8. Add covers for simultaneous contention for one output, simultaneous use of
   independent outputs, both address regions, unmapped access, backpressure,
   different-ID reordering, and ranks 0/nonzero.
9. Prove the 2x2 configuration at outstanding depths 1, 2, and 4. Then repeat
   the role checker on another implementation before beginning C7 scaling.

Candidate xbar wrappers already present include PULP `axi_xbar`, Taxi
`taxi_axi_crossbar`, and ZIPCPU `axixbar`. The root Makefile defaults to
`ROLE=xbar VENDOR=zipcpu IMPL=axixbar`, but that default does not imply the
current xbar harness satisfies C6.

## C7/C8 after C6

C7 scales 2x2 to 3x3 and 6x6 while recording proof radius, time, memory, ID
width, and outstanding limits. If closure fails, add reusable structural
lemmas such as one-hot grant, route lock through WLAST, outstanding-credit
conservation, and response-route consistency. Do not weaken assumptions merely
to obtain a green result.

C8 adds role adapters in increasing semantic complexity: register, demux,
width converter, protocol bridge, RAM, firewall, and DMA. DMA correctness needs
a DMA-specific control-register and source/destination memory reference model;
protocol compliance alone is not a functional DMA proof.

For genuine DUT failures, minimize the formal trace and reproduce it in a
deterministic SystemVerilog test before preparing an upstream issue or PR.
