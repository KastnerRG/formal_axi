# C0-C5 execution record

Executed on 2026-08-31 with Siemens Questa Verify Property 2023.2_2. The
profile is AXI4 Full Issue H.c, normal VALID/READY transactions, with exclusive
accesses and ATOP disabled. Unless a row says otherwise, bounds are four read
transactions, four write transactions, AW/W skew of four in either direction,
eight beats per burst, and no bounded-progress policy.

## Outcome

| Checkpoint | Result | Evidence |
|---|---|---|
| C0 reproducible baseline | Pass | `work/runs/20260831T_c0_final_v2` |
| C1 supported profile | Pass | `docs/axi4_mvp_profile.md`, `docs/axi4_our_status.csv`, `docs/axi5_issue_l_inventory.csv` |
| C2 link checker | Pass | `work/runs/20260901_unified_channel_link_mut_02` |
| C3 bounded oracle | Pass | `work/runs/20260831T_relocated_fifo_final_mutations`, `work/runs/20260901T_smart_final_transaction_transaction_mutations` |
| C4 selected-occurrence abstraction | Pass | Same validation suites; exact and smart models detect the same nine transaction-safety mutations |
| C5 AXI FIFO | Pass, bounded environment | Three vendors close with the declared bounded assumptions; relaxed runs separately reach the required stress covers |

C0-C5 meet their declared gates. C5 is not an unrestricted-backpressure claim:
assertion closure uses zero consumer stall, one outstanding transaction per
read/write direction, and a four-cycle downstream subordinate response bound.
Relaxed runs demonstrate backpressure, queue-full, simultaneous-operation, and
nonzero-rank reachability; their capped inconclusives are not promoted to
proofs.

## C0 baseline and classifications

`tools/run_formal.sh` records the exact command, tool and source revisions,
configuration, raw reports, parsed property status, resource data, and VCD
inventory in a never-overwritten directory. The final ZIPCPU depth-2
registered run has 143 proven assertions, five vacuously proven reset-low
assertions, and 61 covered properties; it has no fired, inconclusive, skipped,
or unsupported properties. All 61 exported VCDs passed structural inspection.
Formal elapsed time was 3 seconds (25 CPU-seconds, 1.8 GB aggregate peak and
0.3 GB maximum per engine).

The five vacuities are the per-channel `a_valid_low_after` reset checks. Questa
automatically initializes the unconstrained VALID inputs low, so these
reset-low properties have no nontrivial antecedent. They are retained and
classified, not counted as active functional evidence. Compile warnings are
classified in `docs/warning_classification.csv`; the remaining warnings are
upstream PULP generic-interface folding messages with zero-width optional
fields and do not remove an enabled AXI signal or property.

## C1 profile and rule inventory

`docs/axi4_mvp_profile.md` freezes the supported profile and classifies
assumptions, guarantees, configuration constraints, progress policy, and
reachability covers. `docs/axi4_our_status.csv` maps the AXI4 Issue H.c rules to an
implementation state. Both AXI4 coverage CSVs contain an `our_status` column.
`docs/axi5_issue_l_inventory.csv` keeps unsupported AXI5 features explicit, so the
MVP makes no AXI5 or AXI4+ATOP claim.

## C2 link checker and polarity test

The link checker now covers channel stability, dependency, burst shape and
length, WSTRB legality, exact WLAST/RLAST position, ID and response encodings,
and the disabled exclusive/ATOP profile. READY timing is an opt-in environment
policy rather than a protocol rule; the common `MAX_STALL` parameter is applied
only where READY is environment-driven. Reset is aligned to the clock and
cannot reassert after release in the formal environment.

The polarity harness changes AWADDR while AW is stalled on the Manager side
and BRESP while B is stalled on the Subordinate side. It also starves DUT-owned
RREADY and AWREADY. Exactly those four unified-checker assertions fire, with no
inconclusives. Legal fixed and wrapping burst covers are separate from the
injected fault scenario; unreachable covers and vacuities in this narrow
mutation harness are therefore expected and classified.

## C3/C4 oracle and abstraction

Exact models and mutation harnesses now live under `fvip_validation/`; they are
not compiled into production closure. The channel oracle is an exact bounded
queue. The abstraction selects an
arbitrary input occurrence, captures its payload, and follows its bounded rank
without requiring unique traffic or a lifetime transaction index. Both also
maintain continuous conservation state. The cross-channel checker implements
selected AR/R accounting, two-sided selected AW/completed-W matching,
selected AW/W-to-B ordering, exact LAST placement, arbitrary-beat WSTRB
legality, and IDs. Global outstanding limits use scalar counters; no production
array is dimensioned by the outstanding limit.

Selected-occurrence properties are sound as universal DUT assertions but not
as the sole legality assumptions for an unconstrained source. The C5 harness
therefore uses deterministic scalar source/subordinate contracts for its
one-outstanding-per-direction environment profile.

Channel mutation score:

| Scenario | Exact oracle | Selected-occurrence tracker |
|---|---:|---:|
| Good | clean | clean |
| Phantom, drop, duplicate, corrupt, reorder, deadlock | 6/6 detected | 6/6 detected |

The channel score was rerun after the validation split in
`work/runs/20260831T_relocated_fifo_final_mutations`; it closed with the same score and no
inconclusive result.

Transaction mutation score: the good trace is clean and reachable; all 10
mutations are detected by the smart checker with no unexpected fire or
inconclusive result: early R,
early RLAST, early B, wrong WLAST, wrong WSTRB, wrong RID, wrong BID,
repeated-ID reorder, deadlock, and duplicate B. The exact protocol oracle also
detects all nine safety mutations; bounded deadlock belongs to the external
progress policy and is intentionally absent from that oracle. The final
dual-model artifact is
`work/runs/20260901T_smart_final_transaction_transaction_mutations`.

Checker validation exposed and fixed two property bugs before the final score:
the formal tool did not hold an `anyconst` selector stable without an explicit
assumption, and a one-bit signed literal made the AW/W skew update have the
opposite sign. The final bounded-parameter refactor was rerun against the same
score in `work/runs/20260831T_c5_transaction_mutations`.

## C5 FIFO matrix

These results predate the pre-C6 architecture refactor. At the time,
`MAX_RESPONSE_DELAY` and scalar environment legality lived in
`tb/fifo_response_env.sv`. The refactor moved generic legality and symmetric
READY/response/write-data progress into each endpoint FVIP; the table below
remains historical C5 evidence and is not silently reclassified as a result
from the new architecture.

Bounded assertion-closure results:

| Implementation/configuration | Declared closure profile | Result |
|---|---|---|
| ZIPCPU depth 2, registered, combined checker | stall 0, outstanding 1, response 4, burst 8 | 175/175 assertions proven in 142 s; no fire or inconclusive |
| ZIPCPU depth 2, smart-only production rerun | stall 0, outstanding 1, response 4, burst 8 | 150/150 assertions proven in 174 s; no fire or inconclusive |
| ZIPCPU depth 32, registered, channel checker | stall 0 | 133/133 assertions proven in 4 s |
| ZIPCPU depth 32, fall-through, channel checker | stall 0 | 138/138 assertions proven in 14 s |
| PULP `axi_fifo`, depth 2, combined checker | stall 0, outstanding 1, response 4, burst 8 | 185/185 assertions proven in 55 s |
| Taxi `taxi_axi_fifo`, depth 2, combined checker | stall 0, outstanding 1, response 4, burst 1 | 178/178 assertions proven in 18 s |

The exact artifact directories, in table order, are:

- `work/runs/20260831T_c5_response_start_zip_fifo_zipcpu_sfifo_d2_ft0`
- `work/runs/20260901T_smart_c5_tight_skew_fifo_zipcpu_sfifo_d2_ft0`
- `work/runs/20260831T_c5_d32_reg_s0_fifo_zipcpu_sfifo_d32_ft0`
- `work/runs/20260831T_c5_d32_ft_s0_fifo_zipcpu_sfifo_d32_ft1`
- `work/runs/20260831T_c5_response_start_pulp_fifo_pulp_axi_fifo_d2_ft0`
- `work/runs/20260831T_c5_response_start_taxi_b1_fifo_taxi_taxi_axi_fifo_d2_ft0`

The Taxi eight-beat experiment is retained at
`work/runs/20260831T_c5_taxi_close_fifo_taxi_taxi_axi_fifo_d2_ft0`: after 300 s it
had no fire, 180 assertions proven, and only five per-beat WSTRB assertions
inconclusive. Taxi's two elastic stages are modeled with
`FIFO_TRACK_DEPTH=FIFO_DEPTH+2`, and its response path permits bypass.

Stress reachability is intentionally checked in less restrictive profiles.
The earlier ZIPCPU depth-2 combined run
`work/runs/20260831T_zipcpu_transactions_final_v2` covers all 97 targets. The
one-cycle-stall depth-32 registered run
`work/runs/20260831T_c5_d32_reg_s1_fifo_zipcpu_sfifo_d32_ft0` covers all 36 targets,
including full-queue and backpressure behavior, but leaves 28 assertions
inconclusive after its 300-second cap. The earlier registered and fall-through
depth-32 runs under `work/runs/20260831T_fifo_matrix_v2_fifo_matrix` also cover all
36 targets. These relaxed runs are reachability evidence only; the zero-stall
proofs are the bounded safety-closure evidence. No unrestricted or
one-cycle-stall depth-32 safety claim is made.

ZIPCPU depths 2/4/8 already close in registered and fall-through modes without
the new bound. PULP and Taxi retain their independent-channel reuse results and
architectural cover exclusions from the original matrix. Finally, the
post-change suites `work/runs/20260901T062117Z_link_mutations`,
`work/runs/20260831T_relocated_fifo_final_mutations`, and
`work/runs/20260901T_smart_final_transaction_transaction_mutations` pass: all six
channel mutations and all ten transaction mutations are detected by their
intended properties. Legal read- and write-rank compaction scenarios also prove
that a selected younger occurrence advances when an older response is removed.
All good traces are reachable and no mutation result is inconclusive.

## Reproduction

Use `tools/run_formal.sh` for an individual pinned run and
`tools/run_fifo_matrix.sh` for the matrix. The three mutation entry points are
`fvip_validation/tools/run_link_mutations.sh`,
`fvip_validation/tools/run_fifo_mutations.sh`, and
`fvip_validation/tools/run_transaction_mutations.sh`. See
`docs/formal_runs.md` for all configuration variables and artifact semantics.
