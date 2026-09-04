# C6 2x2 crossbar execution record

## Status

The C6 implementation and required scenario coverage are present. The formal
gate is **open**. The finalized depth-1 bounded runs have no fired assertions,
but time-limited targets remain inconclusive. The first finalized depth-2 and
depth-4 bounded smokes correctly fired an undersized ZIPCPU output W-ahead
profile; that profile error and its correction are recorded at the live
handoff below. This document does not reclassify a clean inconclusive result
as a proof.

### Post-C6 maintainability refactor: 2026-09-04

This is the current source and proof handoff. The frozen ledger below remains
authoritative: the refactor reproduces its xbar closure, but does not convert
any of the 19 protocol, five role, or separately bounded-progress open targets
into production closures.

#### Source result and boundary

The active production checker closure is now **17 SystemVerilog files / 4731
physical lines**, down from **20 files / 5514 lines** at the frozen handoff:
three fewer files and 783 fewer lines (14.2%). Deleting the two known-dead files
outside that closure brings the complete reduction to **five files / 1005
lines**. The legacy `m_sva_wrap` and `s_sva_wrap` APIs were intentionally
removed, as permitted for this refactor.

The resulting composition is:

- `axi_sva/axi_fvip_endpoints.sv`, a five-line shell, emits both endpoint
  polarities from the shared implementation. `AXI_FVIP_MANAGER` selects the Manager
  form; its documented absence selects the Subordinate form used by direct
  refinement harnesses.
- `axi_sva/our/stream_trackers.sv` owns occurrence/rank/occupancy state and
  two-sided ordered-pair state once; FIFO, routed-stream, and AXI transaction
  trackers are policy shells around those cores.
- FIFO and xbar aggregates instantiate endpoints directly. The xbar passes its
  four public views directly into the source/read/write role modules, removing
  the former scalar proxy ports and reconstruction assignments.
- Canonical channel widths and encodings from `axi_pkg` replace the local
  duplicate enum set and duplicated public/source-role boundary formulas. The
  preserved xbar write tracker keeps only its local payload-index geometry.
  The base filelist now contains only common endpoint sources, including the
  shared stream tracker; the Makefile adds only the selected aggregate's
  role-specific sources.

The public view deliberately retains parameter-exact flat channel vectors,
separate VALID/READY scalars, and separate lifecycle fields. A packed
`rd`/`wr`/`pair` implementation was compiled and tested, but Questa Formal
2023.2 reused the 4-bit ingress-ID member offsets in the simultaneously
elaborated 5-bit egress-ID specialization. That produced false role fires.
Returning to flat interface objects removed the aliasing and reproduced the
frozen checker inventory and vacuity ledger. The later shared-core
simplification additionally turns four nonvacuous bookkeeping timeouts into
proofs. This is a tool-sound boundary, not compatibility work.

No DUT hierarchy reference, route-dependent environment assumption,
selector-dependent legality assumption, or safety-profile progress deadline
was introduced. AW/W association remains based on accepted occurrences. The
legacy xbar write queues, full payload snapshots, and B path remain because
their replacement proof gates in the frozen ledger are still open.

#### Shared transaction-tracker structure

`stream_trackers.sv` now owns two assertion-free mechanisms:
`fv_stream_occurrence_core` selects one source occurrence and follows its
relative rank to an ordered destination, while `fv_ordered_pair_core` matches
the same ordinal occurrence across two streams that may run ahead of one
another. The FIFO, routed-stream, read, pair, and write-response modules add
protocol policy around those two small state machines rather than reimplementing
their bookkeeping.

The read tracker feeds accepted same-ID AR events and accepted same-ID RLAST
events into the occurrence core. Its local circuit is only the response-beat
counter, the live ARLEN/RLAST check, and the optional response-progress timer.
Consequently the authoritative RLAST equality is checked on every relevant
RVALID offer; completion is still driven only by an accepted RLAST.

The AW/W tracker feeds accepted AW and completed-W events into the ordered-pair
core. That core maintains the global signed skew and a selected inclusive
distance which changes only when the opposite stream advances. The AXI shell
retains the beat/WLAST/WSTRB sampling, legality properties, and optional
W-progress timer.

The AW/W/B tracker initializes one inclusive `w_dist` when its arbitrary AW is
selected, then only decrements it on completed W packets. A normal occurrence
core handles ordered B completion. For a Manager endpoint at depth greater
than one, occurrence selection is delayed until the chosen AW's W packet
completes: before that join, completed-credit occupancy is the B-predecessor
rank; afterward the occurrence core's frozen rank is authoritative. The small
one-bit AW-ID tag FIFO remains necessary because AXI4 W carries no ID. It is
not a second transaction tracker and stores no payload.

The three AXI tracker files remain separate because each contains distinct AXI
and polarity-specific obligations, not forwarding-only wrapper logic. Folding
them into `axi_transaction_fvip.sv` would create a much larger aggregate without
removing meaningful code or state.

#### Formal reproduction

The current proof evidence is:

| Gate | Artifact | Result |
| --- | --- | --- |
| Xbar D1 protocol, unbounded safety | `work/runs/20260904_refactor_rw_current_xbar_protocol` | Exact frozen 286/298/186 checker inventory; 211 assertions proved and 75 timed out, a four-proof improvement consisting only of nonvacuous shared-core bookkeeping lemmas; 166 covers reached and 20 timed out; 277/285 assertion antecedents classified nonvacuous; zero fire and zero black boxes. |
| Xbar D1 full aggregate, unbounded safety | `work/runs/20260904_refactor_rw_current_xbar_full` | Exact frozen 332/315/220 checker inventory. Under four concurrent 32-engine jobs, 206 assertions proved, 126 timed out, 186 covers reached, and 34 timed out; two proved AW checks did not finish their separate vacuity jobs. There was no fire or black box. The next row reconciles every timing-displaced frozen result rather than treating these aggregate timeouts as proof loss. |
| Xbar full focused reconciliation | `work/runs/20260904_refactor_rw_current_xbar_full_focus` and `work/runs/20260904_refactor_rw_current_xbar_full_recovery_focus` | The first exact-profile job proves the historical focused assertion nonvacuously and reaches the historical source-0 interleave cover. The second proves all 13 frozen assertions and reaches all nine frozen covers displaced by aggregate contention, and reproves the two aggregate AW checks nonvacuously. Combined exact-current evidence is 219 unique assertion proofs, four more than the frozen combined 215, and 196 unique covers, exactly matching frozen combined reachability. All 216 proved assertions with an applicable antecedent are classified nonvacuous; the other three are configuration assertions. The vacuity union restores the frozen 317/329 completed ledger; zero fire and zero black boxes. |
| FIFO full aggregate | `work/runs/20260904_refactor_rw_current_fifo_full` | 171 assertions, 167 assumptions, and 109 covers: 146 proofs plus 21 classified-vacuous proofs, four clean timeouts, 86 covers reached, and 23 proved uncoverable. All 170 applicable vacuity checks complete (149 nonvacuous, 21 unreachable); zero fire and zero black boxes. Its property and vacuity ledgers are byte-identical to the frozen aggregate. |
| FIFO WSTRB focus | `work/runs/20260904_refactor_rw_current_fifo_wstrb_directionals` and `work/runs/20260904_refactor_rw_current_fifo_pair_wstrb_focus` | The four aggregate timeouts all prove nonvacuously on the identical profile. The three directionals close in 642 seconds; the final canonical pair property proves directly after 1750 seconds with no promoted assertion. Thus all 171 FIFO assertions and all 109 covers are resolved across the aggregate and focused artifacts. |

The protocol checker inventory and vacuity ledger are byte-identical to the
frozen reference. The property ledger differs in exactly four assertion status
rows, each changing from inconclusive to proven:

- `property_status.csv` SHA-256:
  `6cd3db911c0c376a283691bb337876c6cc63546890a4f4538684c93466153292`;
- `vacuity_status.csv` SHA-256:
  `b9adb5636630abd5d99f3e724207ac8e5f6ea43f604c15a740f927775da4f600`.

The default and non-default-burst DMA compile gates are
`work/build/20260904_refactor_rw_current_dma_burst8_compile` and
`work/build/20260904_refactor_rw_current_dma_burst4_compile`. Both compile the two endpoint
polarities and all transaction trackers with zero errors, zero warnings, and
the two expected suppressed diagnostics, retained in each artifact's
`compile.log`. The burst-four gate specifically checks that the DMA endpoint
and public view receive the same non-default `MAX_BURST_LEN`. Exact-current-tree
full xbar and FIFO compile transcripts are retained at
`work/build/20260904_refactor_rw_current_xbar_full_compile/compile.log` and
`work/build/20260904_refactor_rw_current_fifo_full_compile/compile.log`; both have the
same clean diagnostic counts.

#### Semantic validation

The following exact-current-source gates are clean:

- `work/runs/20260904_refactor_rw_current_pair_summary`: 13/13
  assertions proved nonvacuously and 6/6 covers reached;
- `work/runs/20260904_refactor_rw_current_public_pair`:
  23/23 assertions proved nonvacuously, 18/18 covers reached, and no unexpected
  assumption used;
- `work/runs/20260904_refactor_rw_current_link_mutations`: exactly the four
  intended polarity/stability failures, with no unexpected or inconclusive
  result;
- `work/runs/20260904_refactor_rw_current_manager_offer`: all 12
  legal/bad offer-level cases pass their setup, escape, guard, terminal, and
  compile gates;
- `work/runs/20260904_refactor_rw_current_fifo_mutations`: the
  good FIFO is quiet and phantom, drop, duplicate, corrupt, reorder, and
  deadlock are detected by both the independent oracle and production tracker.

The final transaction sweep is
`work/runs/20260904_refactor_rw_current_transaction_mutations`. All 40 cases
pass: 11 legal/isolation cases are quiet, all 29 negative cases produce their
intended detections, and there are zero unexpected fires and zero inconclusive
results. Every applicable sequence, guard, and READY-low reachability gate
passes; all 40 compile with zero errors, warnings, or black boxes.

### Refactor-stop handoff: 2026-09-04

This is the frozen stopping point for the planned major refactor.  Every
formal job launched by this session has terminated, and no new proof was
started after the two final role-W diagnostics below.  The latest job was
clean/nonvacuous but inconclusive; it did not change any closure count.
`docs/c6_execution.md` itself is currently untracked, and the surrounding
worktree contains many intentional modified and untracked files.  Preserve
the worktree and this file explicitly; do not use a broad checkout, reset, or
clean as part of the refactor.

#### Frozen sign-off ledger

These are the numbers to reproduce or improve after the refactor.  Proof
closure, checker elaboration, and bounded progress are deliberately separate:

| Inventory at the stop point | Closed | Open | Notes |
| --- | ---: | ---: | --- |
| Protocol production/configuration safety | 112/131 | 19 | 107/118 retained-original, 5/5 later-added, 0/8 offer-level additions |
| Protocol induction helpers | 134/155 | 21 | helpers do not reduce the production backlog |
| Role production safety | 9/14 | 5 | mapped B plus four W-forwarding properties remain |
| Role configuration | 2/2 | 0 | prefix and non-overlap configuration |
| Role induction helpers, logical | 8/28 | 20 | two legacy/shadow B pairs make the physical open count 22 |
| Protocol bounded progress | separate | 6 | two input R, two input B, two output W |
| Role bounded progress | separate | 3 | selected route, read, and write progress |

The current exact protocol elaboration is **286 assertion, 298 assumption,
and 186 cover checkers**, or **144/149/95 directives**.  The current exact
full elaboration is **332/315/220 checkers**, or **190/166/129 directives**.
Both current compile gates have zero errors, zero warnings, and only the two
expected suppressed diagnostics.  Counts are an audit aid, not a substitute
for a property-by-property mapping: a good refactor may legitimately reduce
them.

The net retained-original protocol closures obtained from the historical
22-case backlog are eleven:

- both input `x_b_has_completed_write` instances;
- both outputs' `x_w_last_exact_after_aw`,
  `x_w_last_exact_simultaneous_aw`, and
  `x_w_last_exact_simultaneous_w` instances, six checks total;
- output 1 `c_profile_w_packet_len`; and
- both output `x_write_outstanding_bound` instances.

The gross session count was thirteen because the old handshake-level forms
of both `x_w_last_exact_after_w` instances also proved.  Their later,
READY-independent offer-level strengthening changed the functional cone, so
those two are correctly reopened; the current net is eleven.  Five
later-added protocol/configuration checks were also introduced and closed:
the aggregate transaction/role configuration invariant, both input global
completed-write checks, and both input per-ID completed-write checks.

The role phase additionally closed current-source mapped-R occurrence/data
machinery and all four fixed source/destination partitions of class-1 routed
address integrity, making class-1 a production closure.  The latest helper
push closed only reusable structure: both after-W entry-origin controls,
both post-handshake capture bridges, both output W-count capture facts, the
output-1 after-W stall hold, both pair-shadow state facts, all 20 public B
view facts, the selected-output write-observer cut, and the route
lifecycle/routed-equivalence pair.  Do not report any of the final
selected-W or role-W timeouts as closures.

#### Exact work that remains

The eleven open retained-original protocol safety cases are:

- output 0 `c_profile_w_packet_len`;
- both outputs' strengthened `x_w_last_exact_after_w`; and
- `x_wstrb_after_aw`, `x_wstrb_after_w`,
  `x_wstrb_simultaneous_aw`, and `x_wstrb_simultaneous_w` on both
  outputs, eight cases.

The eight new offer-level protocol cases are
`x_wstrb_live_after_aw`, `x_wstrb_live_select_aw`,
`x_w_last_offer_after_aw`, and `x_w_last_offer_select_aw` on both
outputs.  All 19 protocol safety targets are nonvacuous and have no known
counterexample, but all are still open.  The five open role production
properties are `a_selected_mapped_b` and the four W-forwarding properties
`a_selected_w_integrity`, `a_selected_w_completion`,
`a_selected_sampled_w_integrity`, and
`a_selected_sampled_w_completion`.  The six plus three progress targets in
the table above are also open, but only in the bounded-progress profile.
Depth-two/depth-four sign-off and the final aggregate matrices remain
separate unfinished work.

#### Architecture that the refactor must preserve

There are two modes:

- **protocol** instantiates the generic endpoint FVIP at all four AXI ports.
  It checks every DUT-owned AXI offer and transition within the configured
  finite capacity bounds.  The crossbar role hierarchy must elaborate away.
- **role/full** retains every protocol check and adds only the cross-interface
  obligations that make the DUT a crossbar: decode/routing, ID prefixing and
  removal, ordered response return, W ownership, and payload forwarding.

Safety is unbounded in time whenever possible
(`ENABLE_BOUNDED_ENV=0`).  Finite outstanding/AW-ahead/W-ahead limits are
capacity contracts, not promises that READY or a response eventually
arrives.  A hostile legal environment may hold READY low or omit a response
forever, so unconditional liveness cannot close.  Maximum stall, response
delay, W-data delay, and role delay belong only to the explicitly enabled
bounded-progress profile.  Never use one of those deadlines to close a
safety property.

Induction invariants may depend on AXI port signals and on counters,
selectors, snapshots, and state owned by this FVIP.  They must not refer to
ZIPCPU/PULP implementation hierarchy or encode the exact internal
arbitration, FIFO, or skid-buffer implementation.  Cross-port conservation is
allowed when it is stated entirely over the public ports/FVIP view.  Keep
role composition acyclic: only independently proved assertions may be
promoted, and each artifact must record the exact promoted set.

Use one arbitrary watched ingress/source (the DUT's subordinate-facing request
port), one arbitrary mapped egress/destination, one arbitrary ID, occurrence,
beat, lane or payload bit, and request class.  Those ghost choices are stable
and range constrained.  They select an occurrence from otherwise arbitrary
environment traffic; they do not replace universal traffic with one injected
transaction.  Exhaustive fixed source/destination partitions are acceptable
proof cuts because the 2x2 choices are finite, but the implementation should
still contain one shared arbitrary-source/destination machine rather than a
copy per port.

Selector alignment may flow only from the role-selected occurrence into the
corresponding endpoint ghost selector.  Do not assume the converse
`endpoint_select -> role_select`: that would suppress unrelated endpoint
protocol witnesses.  A reverse implication would require a separately
proved no-phantom/surjectivity theorem, not convenience.

#### How AR/R and AW/W/B association works

For R, select an arbitrary **accepted AR occurrence**, not merely an ID.  The
read tracker captures its ARLEN and initializes the count of older same-ID
requests.  Only an accepted same-ID RLAST retires one predecessor.  When that
rank reaches zero, each same-ID RVALID offer is owned by the selected AR:
the running beat position is compared with captured ARLEN, RLAST must occur
on exactly the terminal beat, and an arbitrary selected data bit/beat can be
compared end to end in role mode.  Correctness is checked while VALID is
offered, including under RREADY backpressure; the handshake changes rank and
capture state but is not required for live correctness.  R has no WSTRB-like
valid-lane mask.

For W, AXI4 has no WID and W may precede AW.  Association is therefore by
packet order, not by ID: the endpoint pair tracker owns the signed
`accepted_AW - completed_W` skew and an opposite-side predecessor rank.  It
may select either the arbitrary AW occurrence or the arbitrary completed W
packet and waits for their ranks to meet.  The existing channel W-beat
counter, captured one-based AWLEN+1, one arbitrary beat, and one arbitrary
strobe lane establish exact WLAST and byte-lane legality.  Role forwarding
adds one arbitrary canonical W payload bit and binds the selected input
packet to the selected output packet using route occurrence/order.  Every
owned WVALID offer must be checked; WREADY and WLAST cannot be the only
trigger.

B is tied to a completed write, not just an AW.  At an input endpoint the
global and per-ID completed-write credits prevent early/same-ID-invalid B.
Across the crossbar, the selected output ID contains the source prefix and
the input return removes it; the public endpoint B observer supplies the live
or frozen selected response for mapped-B occurrence/data.  Its shadow path
currently coexists with the legacy role B rank/sample path because mapped-B
composition has not closed.

The user's proposed sticky `matched` bit is useful only as a captured-sample
valid flag.  Checking it solely when RLAST/WLAST appears is insufficient:
READY may remain low forever and a broken producer may omit LAST forever.
The authoritative assertions must validate every currently owned VALID
offer, with rank/order deciding ownership; a sticky bit may summarize an
already checked arbitrary sample but must not replace that live check.

#### Current state-reduction boundary

The pair tracker no longer stores raw
`{AWADDR,AWLEN,AWSIZE,AWBURST}`.  Its sufficient AW summary is the full
nine-bit one-based beat count plus one arbitrary-lane legality bit.  The
standalone refinement and mutation gates authorized removal of 35 bits per
endpoint, **140 sequential observer bits across the xbar**.  Role trackers
reuse the public endpoint `pair_skew` and channel W-beat counters rather than
recounting them.

The public endpoint also has a scalar arbitrary W-payload selector and proved
capture/freeze bridges.  However, the old full W snapshot and the legacy
role-local W queues are still present beside the scalar pair-shadow path.
Similarly, legacy mapped-B state and the endpoint-backed B shadow coexist.
Do not delete either legacy path merely because its replacement elaborates:
delete only after the corresponding role occurrence/order/data assertions
close and directed mutations exercise the replacement.  The after-W
decomposition currently in `axi_pair_tracker.sv` is temporary assertion
scaffolding only and adds no design/FVIP sequential register.

#### What worked, and what is exhausted

Useful proof cuts were direct one-step capture/freeze refinement, exact
forward-time post-capture bridges, public-view proofs without a DUT,
source/destination enumeration, cross-port lifecycle conservation, and
directed legal/bad mutation pairs.  In particular, the reduced AW summary is
13/13 proved with 6/6 covers; public pair capture/visibility is 40/40 proved
with 52/52 covers; public long-lived invariants are 20/20 proved; the
DUT-free public-pair audit is 23/23 proved with 18/18 covers; and public B
helpers are 20/20 closed.

The following directions are exhausted and should not be repeated unchanged:

- asking the solver to infer a same-edge live-AW equality backward from a
  proved post-handshake register equality;
- the monolithic after-W stalled-entry target, its three AW-channel-history
  branches, or the zero-skew selected-W leaf without a new packet-provenance
  cut;
- either final source0/destination0 role-W live or stored shadow group with
  the same eleven premises;
- the monolithic/fixed-partition mapped-B rank cone and wider-premise mapped-B
  occurrence retry;
- reverse role/endpoint selector implications; and
- merely adding more rank/capacity facts when the missing fact is occurrence
  or payload provenance.

The two final role-W batches isolate the next architectural issue: first
prove source-to-output **packet occurrence and ordering**, then carry beat or
payload equality.  The protocol after-W leaf identifies the analogous
endpoint issue: the tracker transition facts close, but the output W packet
still lacks a solver-friendly provenance link to the live late AW.  These
are induction-boundary problems, not counterexamples and not evidence that a
finite 2x2 safety proof is impossible.

#### Post-refactor no-regression gate

Run the gates in this order, using fresh output directories:

1. Compile the exact D1 N1/O7/AW7/W1 protocol and full profiles.  Require zero
   errors/warnings, the two known suppressed diagnostics only, no blackbox,
   and no accidental role hierarchy in protocol mode.  The current golden
   compile artifacts are
   `work/build/20260904_c6_after_w_zero_leaf_compile_xbar_protocol` and
   `work/build/20260904_c6_after_w_zero_leaf_compile_xbar_full`.
2. Run `fvip_validation/tools/run_pair_summary_refinement.sh` and require all
   13 assertions plus six covers.  Run
   `fvip_validation/tools/run_c6_public_pair_view_refinement.sh` and require
   all 23 assertions plus 18 covers with its exact assumption audit.
3. Run the full transaction-mutation suite, cases 0--39, plus the Manager
   offer mutation suite.  At minimum, preserve the critical legal/bad W
   cases 18 and 20--25, role response cases 26--36, and endpoint public-view
   cases 37--39.  Legal cases must have no fire; each bad case must fire its
   intended checker with no unexpected or inconclusive result; sequences,
   guards, and READY-low witnesses must reach.
4. Re-run focused proofs for every closed helper consumed by a composition,
   then every closed production target.  Property renames are allowed only
   with an explicit old-to-new mapping.  No old artifact proves changed
   source or a changed functional cone.
5. Re-run the protocol/full D1 aggregates and all required covers, then the
   bounded-progress profile, then corrected D2/D4 profiles.  Keep safety and
   progress reports separate.  Compare assertion status and nonvacuity, not
   just aggregate checker counts.
6. Measure state on an unfixed aggregate model.  Record every added/deleted
   register and selector assumption.  Do not compare the fixed s0/d0 role-W
   model's 4,564 bits with the older unfixed 4,902-bit aggregate; target
   constants prune state and make that comparison invalid.

The most important golden artifacts for semantic regression are:

| Boundary | Golden artifact/result |
| --- | --- |
| Reduced pair summary | `work/runs/20260903_c6_pair_summary_reduced_64681229_v1_pair_summary_refinement`: 13 assertions, 6 covers |
| Public pair transitions | `work/runs/20260903_c6_public_pair_capture_visibility_reduced_xbar_zipcpu_axixbar_protocol_d1_ft0`: 40 assertions, 52 covers |
| Public pair invariants | `work/runs/20260903_c6_public_pair_freeze_equiv_reduced_xbar_zipcpu_axixbar_protocol_d1_ft0`: 20 assertions |
| DUT-free pair audit | `work/runs/20260903T_public_pair_view_refinement_audit5_c6_public_pair_view_refinement`: 23 assertions, 18 covers |
| Public B transitions/provenance | `work/runs/20260904_c6_public_b_a1_transition_14e7af32_xbar_zipcpu_axixbar_protocol_d1_ft0` and `work/runs/20260904_c6_public_b_a4_all_provenance_composed_14e7af32_xbar_zipcpu_axixbar_protocol_d1_ft0`: 20/20 helpers |
| Endpoint-B mutation wiring | `work/runs/20260904_c6_endpoint_b_shadow_validation_final_transaction_mutations`: cases 32--36 pass |
| Final after-W mutations | `work/runs/20260904_c6_after_w_entry_select_w_aw_offer_split_mutations18_24_25_transaction_mutations`: legal 18 quiet, bad 24/25 detected |
| Final after-W structural facts | `work/runs/20260904_c6_protocol_after_w_entry_origin_control_independent_xbar_zipcpu_axixbar_protocol_d1_ft0` plus both `...m0/m1_after_w_handshake_post_composed...` artifacts |
| Final role-W negative result | the live and stored `20260904_c6_role_w_pair_shadow_*_s0_d0_composed...` artifacts at the end of this log |

#### Frozen source fingerprints

These hashes identify the precise pre-refactor source.  Recompute them before
starting if any background edit may have landed:

| File | SHA-256 |
| --- | --- |
| `axi_sva/our/axi_pair_tracker.sv` | `9f849b56703148e74995f82b6cbfaa65c9cc5300c21064ee555be51289d55670` |
| `axi_sva/our/axi_fvip_env_contract.sv` | `f57245daea2f2c9c5d25e983aaf5ca92423a73dc88bd7f66510ef624a741b875` |
| `axi_sva/our/axi_fvip.sv` | `14e7af32a0cd911984cafcf79cf84f5b37aaae875360572577281f7e53c9cca5` |
| `axi_sva/our/axi_fvip_txn_view_if.sv` | `c1dd234bbd93f81bfd13374710690b81b39af6c8f602bb02ba27f67fe41c022e` |
| `axi_sva/our/axi_transaction_fvip.sv` | `ace4d59f098c5312b1dd6f64eabcca99c7e5c5ce71b8e8a0b6c57f1d59d00a2c` |
| `axi_sva/our/axi_read_tracker.sv` | `68457e2ed9df405ad633276adc7362c597286a02ec96f35721df5e6cfdd2109f` |
| `axi_sva/our/axi_write_tracker.sv` | `2a56db4bf46c6f459416747362bc8ec0d043acb82024996df7395e17d596fccc` |
| `per_role_fvip/xbar/axi_xbar_fvip.sv` | `7fb91a6e0a464ab8b29651f5c0d5d3bc3275d2d0026bcd3f182a0925404298d5` |
| `per_role_fvip/xbar/axi_xbar_role_fvip.sv` | `0d0ebf37e3c7efe15374e17836a3af20bf4defade8918d0c98aa93b315ef8592` |
| `per_role_fvip/xbar/xbar_stream_tracker.sv` | `769f1d9c16aa10029d33c91f018c7841abe7b7ff2d9a9afee911184a561f12db` |
| `per_role_fvip/xbar/xbar_read_tracker.sv` | `506c4abb27c2dab3110ee98d11b54f9860dccb9737267ffa076257a82f7dbee5` |
| `per_role_fvip/xbar/xbar_write_tracker.sv` | `c4d1745fd0191777dfae122bce2033bbc8ab60cafe64de5759171799362606cf` |
| `tb/tb_xbar.sv` | `a74e0608d5958889318015f3d81035cca21fd61df56db025fed139093ecbf935` |
| `fvip_validation/tb/tb_transaction_mutation.sv` | `a4f26c0051dd30db55b6d558c7d2f5314bc5b1a16647eab9130d7c20fa5b3d94` |
| `fvip_validation/tools/run_transaction_mutations.sh` | `ef20331ff01124f22e6ada1c30e1e726620f15c0c48ef4f52c1b756bc2fef5fe` |
| `tools/run_formal.sh` | `f669b53fe6b53b17da6927293963e6fe1f3d406a7da56edde1dad351b71cdc3f` |

After a successful refactor, replace this freeze with a new dated freeze;
retain this one in the history below or in version control so the property
mapping remains auditable.

### Reconciled closure ledger

This ledger is the current sign-off accounting. It distinguishes production
obligations from induction helpers even though both elaborate as assertions.
It carries forward a focused proof across a later source change only when the
property and its functional cone are unchanged; the final aggregate reruns
are still required.

The current depth-one protocol source retains 118 of the original 120 safety
properties. The two removed properties were the pair tracker's duplicate
output `x_w_burst_bound` checks; the channel-level
`c_profile_w_packet_len` remains the stronger production authority. Of those
118 retained-original properties, 107 are closed and exactly eleven remain
open. The complete changing portion of that ledger is:

| Retained-original production property | input 0 | input 1 | output 0 | output 1 |
| --- | --- | --- | --- | --- |
| `x_b_has_completed_write` | closed | closed | N/A | N/A |
| `c_profile_w_packet_len` | N/A | N/A | **open** | closed |
| `x_w_last_exact_after_aw` | N/A | N/A | closed | closed |
| `x_w_last_exact_after_w` | N/A | N/A | **open; corrected-contract retry clean/nonvacuous but inconclusive** | **open; corrected-contract retry clean/nonvacuous but inconclusive** |
| `x_w_last_exact_simultaneous_aw` | N/A | N/A | closed | closed |
| `x_w_last_exact_simultaneous_w` | N/A | N/A | closed | closed |
| `x_wstrb_after_aw` | N/A | N/A | **open** | **open** |
| `x_wstrb_after_w` | N/A | N/A | **open** | **open** |
| `x_wstrb_simultaneous_aw` | N/A | N/A | **open** | **open** |
| `x_wstrb_simultaneous_w` | N/A | N/A | **open** | **open** |
| `x_write_outstanding_bound` | N/A | N/A | closed | closed |

Every retained-original depth-one channel/read/accounting/skew/read-credit
property outside this table is closed. The current source also has five added
production checks, all closed at depth one: the aggregate transaction/role
configuration invariant, both input `x_b_has_global_completed_write`
instances, and both input `x_b_has_per_id_completed_write` instances. The
latter close compositionally from same-input, independently proved global
credit and no-orphan facts. The new cross-port
`a_xbar_global_write_lifecycle_conservation` assertion is an induction helper,
not an additional port-protocol requirement; its standalone depth-one proof
enabled the two output write-bound closures above.

The session produced 13 retained-original protocol closures from the
historical 22-case backlog: two input completed-write/B checks, all eight
output exact-WLAST directionals, output 1 packet length, and both output
write-outstanding bounds. The later AWREADY-independent strengthening changed
the functional cone of the two `x_w_last_exact_after_w` checks, so their old
handshake-level proofs are now stale and the current net ledger is
`22 - 11 = 11` closed cases with eleven open. Once the two strengthened
successors reprove, the ledger returns to the 13-newly-closed, nine-open
state. The five later production/configuration checks above were also
introduced and closed, but are deliberately kept separate from this count.

Eight additional output offer-level production checks are now present:
`x_wstrb_live_after_aw`, `x_wstrb_live_select_aw`,
`x_w_last_offer_after_aw`, and `x_w_last_offer_select_aw`, each on both
outputs. Their first run correctly exposed a deterministic input-environment
hole.  Their corrected-contract retry has now run: all eight are nonvacuous
and clean but inconclusive, so none is promoted.  As newly introduced
properties they do not themselves change the retained-original accounting.

Six bounded protocol production checks remain open: input 0/1 read-response
progress, input 0/1 write-response progress, and output 0/1 W-data progress.
Their clean bounded searches are evidence, not proofs.

The current role layer has 14 production safety properties. Nine are closed:
route `a_no_overflow`, the original handshake `a_no_phantom`, the new
offer-level `a_no_phantom_offer`, class-0 routed-address integrity,
class-1 routed-address integrity,
mapped-read completion, mapped-read data, local-error read response, and
local-error B. Five remain open: mapped B and the four W-data forwarding
properties. The corrected independent endpoint-
view and tracker-local mutation gates validate the four response closures.
The first red public-view guard
attempt did not establish a production failure: its validation-only hierarchy
omitted the `g_txn` generate scope, and Questa reported the intended
selector/ID constraints as untranslated.

The two role configuration assertions remain closed.  The logical role-helper
ledger is currently **8/28** while the six zero-state pending-B transition
lemmas are staged.  Closed helpers include the route
`a_tracker_pending_rank`, read-response credit/rank, mapped-R occurrence, both
W-shadow state facts, the selected-output write-observer cut, and the exact
route lifecycle/routed-equivalence pair.  Still open are the legacy B
credit/rank helper, both endpoint-shadow mapped-B occurrence/data helpers,
the mapped-B routed and live-return splits, pending-route/source-B exclusion,
its staged per-ID-head/base/hold transition decomposition, and the remaining
W-shadow helpers.  The two
physical legacy/new B occurrence and data checkers intentionally coexist
during migration, so physical checker count is two higher than this logical
inventory.  Thus 20 logical role helpers (22 physical checkers) remain open;
the transition lemmas are proof scaffolding rather than new role requirements.
Route, read, and write selected progress are the three separate open bounded
role checks.

The pre-B-shadow frozen depth-one protocol elaboration contains **240 assertion
checkers and 298 assumptions**.  Its sign-off inventory is 131 production or
configuration checks (118 retained-original, five later checks, and eight new
offer-level checks) plus 109 helper-only checks.  The production/configuration
ledger is 112/131 closed: 107/118 retained-original, 5/5 later, and 0/8 new
offer-level.  The helper ledger is 107/109 closed; only the two DUT-output
`a_pair_completed_wstrb` instances remain open.  The increase from the older
172-checker snapshot is fully reconciled: four obsolete lane-predicate helpers
were deleted, 12 AW-summary capture helpers and 60 public-pair refinement
helpers were added, so `172 - 4 + 12 + 60 = 240`.  All 60 public-pair helpers
are now independently proved by the focused transition and invariant gates
recorded below.  The scalar payload selector adds two assumptions per endpoint,
so the assumption count moves from 290 to 298.  These helpers and ghost-domain
assumptions do not add protocol state or inflate the production backlog.

The endpoint-backed B source adds five zero-state public response assertions
at each of the four endpoints.  All 20 instances are now independently
closed by the A1/A4 endpoint gates.  That stable checkpoint has **260
assertion checkers, 298 assumptions, and 186 covers**, with a helper ledger of
**127/129**; only the two output `a_pair_completed_wstrb` instances remain
open.  The first W-before-AW induction layer added four directives/eight
output helper checkers.  Its focused gate measured **268/298/186** and
**135/149/95** directives and closed the output-1 stall-hold instance.  The
exact three-origin entry split then measured **274/298/186** and
**138/149/95**.  The post-capture handshake bridge adds one directive/two
checkers; its first focused gate measured **276/298/186** checkers and
**139/149/95** directives.  Both physical bridge instances are now closed.
The selected-W channel-history split, output-only W-count capture, and narrow
zero-skew association leaf subsequently add ten checkers and five assert
directives.  The current protocol source is therefore **286/298/186** and
**144/149/95**.  Its temporary helper ledger is **134/155**: the stable 127
closures plus output 1's hold, both post-capture bridges, both entry-origin
control facts, and both output W-count captures.  The selected-W branches and
zero-skew leaves are not yet counted closed.  The unproductive
immediate-handshake helper was removed, and the generic capture helper was
restricted to the two output-polarity instances which consume it.  None of
these helpers adds an assumption, cover, or RTL/FVIP state, and they are not
new protocol requirements, so the 112/131 production/configuration ledger is
unchanged.

The older 193-assertion/298-assumption full snapshots below predate both the
public-pair refinement helpers and the role W shadow.  They remain valid for
properties whose functional cones are explicitly unchanged, but are no longer
the current aggregate checker count. Fresh exact-source full elaboration at
the pre-B-shadow checkpoint directly confirmed **271 assertions and 314
assumptions**: protocol
240/298 plus a role hierarchy of 31/16.  The latter consists of 14 production,
two configuration, and 15 helper assertions, plus eight preexisting and eight
new shadow-selector assumptions.  Production remains 9/14 closed,
configuration 2/2, and role helpers 5/15 after exhaustive closure of both
pair-shadow state facts; one proved fixed B-rank partition does not close the
arbitrary B-rank helper.  The confirming current-source
models have no blackboxes; their fixed B-rank targets are still reported
separately from aggregate closure.

The endpoint-B-shadow historical checkpoint directly reported **293 assertion
checkers, 315 assumptions, and 220 covers** with no blackboxes.  The 20 public
B helpers, two parallel role B-shadow assertions, and one one-way role
selector assumption account exactly for its deltas.  The later independently
proved route-lifecycle source measured **299/315/220** and **4,902 state
bits**.  The per-ID-head assertion plus base/hold and stalled/advancing splits
were then directly measured at **304/315/220** checkers and
**175/166/129** directives.  The final empty/consumed exact split adds two
assertions and no assumption, cover, or RTL state; the focused gates directly
confirm that role checkpoint at **306/315/220**, **177/166/129**, and
**4,902 state bits**.  The subsequently staged W-before-AW protocol helpers
put the pre-channel-split full source at an arithmetically reconciled
**322/315/220** and **185/166/129**: eight initial partition instances, six
exact entry-origin instances, and two post-capture handshake instances were
added to the measured role checkpoint.  The selected-W channel split, two
output capture instances, and two zero-skew leaves put the current full source
at **332/315/220** and **190/166/129**.  The first current-source role-W gate
below directly confirms those totals with no blackbox.  Both full source
compiles also pass.
No helper adds RTL/FVIP sequential state; assertion automata can still add
formal property-state bits and are not being mislabeled as free solver state.

Higher-depth results are a separate ledger. There is no current corrected-
profile protocol or full sign-off at outstanding depth two or four. At both
depths, both input per-ID strict-B targets remain directly inconclusive; the
selected strict-B proofs are conditional on that unproved premise. Both
outputs' corrected W-ahead-cap targets also remain inconclusive at each
depth. At depth two, the cross-port lifecycle helper subsequently proved as
an exact standalone instance, so the recorded one-fact composition validly
closes both output write bounds at that depth. At depth four, the same
present-state conservation inequality is insufficient for the ZIPCPU
seven-credit output profile: eight input credits can legally be live while a
saturating output observer remains at seven. Closing O7/N4 therefore needs a
separate observable ZIPCPU resource-policy theorem, or the reusable generic
profile must use the conservation-derived output bound of eight. No depth-
one production proof is automatically promoted to a higher-depth profile.

Proven helper facts which do not by themselves close a production property
include: the depth-one and depth-two cross-port write-lifecycle conservation
facts; output
completed-pair exactness; input/output pair pending-rank facts; output
after-W capture; output scalar-lane predicate equivalence and capture/freeze;
input read pending-rank; input write pending-W rank and data-phase state; the
depth-two/depth-four exact pending completed-credit/rank and selected-tag
facts; and the role route pending-rank fact. The canonical output
`a_pair_completed_wstrb` remains a current, inconclusive helper and must not
inflate either the production backlog or the closure count. The experimental
output `a_write_offer_has_capacity` helper was also inconclusive and has been
removed from the current source; it survives only as historical evidence in
the handoff log below.  The selected-output write-observer cut and the exact
route lifecycle/routed-equivalence helpers are also now proven.  The
pending-route/source-B exclusion is not proven and must not be inferred from
those structural facts alone.

## Proof composition

`fv_axi_xbar_fvip` is the public aggregate, matching the FIFO aggregate
pattern. It instantiates two Manager-side endpoint FVIPs at the crossbar
inputs and two Subordinate-side endpoint FVIPs at the outputs.

- `LEVEL=protocol` enables complete channel and transaction checking on all
  four endpoints and sets `ENABLE_ROLE=0`. Formal elaboration removes the
  entire crossbar role hierarchy; no decode, route, or implementation detail
  is in the protocol proof.
- `LEVEL=full` retains those endpoint checkers and adds
  `fv_axi_xbar_role_fvip`. The role checker receives only four public
  `axi_fvip_txn_view_if.Consumer` ports. It contains no DUT hierarchy
  reference and no endpoint-checker hierarchy reference.

The public view has parameter-exact flat live channel vectors and separate
VALID/READY scalars. These are generic endpoint outputs, not a crossbar
adapter. They avoid packed-field aliasing at a Questa Formal modport boundary
while leaving the PULP request/response records available to existing roles.
The view also exports the generic endpoint's signed AW-minus-completed-W
`pair_skew` and its parameter-exact `channel_w_beat`. The crossbar role and
the Manager environment consume that public protocol state; neither
recomputes the same conservation count or burst-position counter.
Both input views receive the input write-data delay exactly; both output views
receive the output write-data delay exactly. Formal elaboration therefore has
only the intended input and output view specializations.

Input and output endpoint capacities are also independent. The input FVIPs use
`MAX_OUTSTANDING`, `MAX_AW_AHEAD`, and `MAX_W_AHEAD`; the output FVIPs use
`MAX_OUTPUT_OUTSTANDING`, `MAX_OUTPUT_AW_AHEAD`, and
`MAX_OUTPUT_W_AHEAD`. These are explicit wrapper-profile facts, not generic
FVIP formulas derived from the number of crossbar ports. For ZIPCPU
`axixbar`, the current output profile is 7 outstanding, 7 AW-ahead, and
`min(MAX_OUTSTANDING, 2)` W-ahead (1/2/2 at input depths 1/2/4). The core's
`LGMAXBURST=3` admits seven requests on a granted Manager-facing port. Its
registered AW output plus the wrapper's one-entry AW skid can retain two AWs
while the independent W path drains; the locked write grant prevents another
input from multiplying that pipeline capacity.

## Crossbar contract

The role layer proves the following configurable contract:

- two masked address regions plus an optional per-source default destination;
- local DECERR responses for unmapped requests when no default is enabled;
- output ID `{source_port, input_id}` and prefix removal on B/R return;
- output ID width exactly one bit wider than the 2x2 input ID;
- arbitrary source, same-ID domain, decoded destination, request occurrence,
  request kind, and selected burst beat;
- ordered AW and AR routing, W ownership through WLAST in either AW/W arrival
  order, selected R data/completion, selected B return, and same-ID ordering;
- configurable REGION/USER preservation and local-error read data.

The full harness covers simultaneous same-destination contention,
independent destinations, decode errors, downstream backpressure, and
different-ID read-response interleaving. The output endpoint's transaction
checker supplies the response-interleaving witness; the role layer names the
same public-view condition rather than duplicating protocol state.

## Wrapper and implementation fixes

The proof found defects at the existing ZIPCPU implementation boundary. They
were fixed directly rather than hidden by a replacement proof wrapper:

1. The address mask now describes exact 64 KiB windows. The previous mask
   selected only address bit 16 and admitted unrelated address space.
2. The wrapper prefixes the ingress source onto AWID/ARID, instantiates the
   core at the widened ID width, exposes widened output IDs, and removes the
   prefix on input B/R responses.
3. AW, W, and AR output skid buffers hold VALID and payload stable through
   downstream backpressure and grant changes.
4. Unsupported REGION, USER, and ATOP fields are normalized to zero and are
   declared as such in the role profile.
5. The core's local-error B mux retains the saved ID/DECERR while the error
   response is pending.
6. A `berr_pending` state prevents a second unmapped AW from overwriting the
   single saved error ID before the first write reaches WLAST and enters the
   B-return skid buffer.

The scalar interfaces in `tb_xbar.sv` only work around formal-tool binding of
individual interface-array elements. They connect to the existing official
wrapper with `AXI_ASSIGN`; they do not replace or alter the DUT role boundary.

## Evidence

All rows in the first table use ZIPCPU `axixbar`, eight-beat bursts, no
DUT-internal proof references, and `ENABLE_BOUNDED_ENV=0`. The latter selects
protocol safety and capacity without a progress deadline.

| Level | Outstanding | Budget | Assertions | Covers | Vacuity | Artifact |
| --- | ---: | ---: | --- | --- | --- | --- |
| protocol | 1 | 180 s, 32 jobs | 88 proven, 32 inconclusive, 0 fired | 88 covered, 6 uncoverable, 6 inconclusive | 120/120 nonvacuous | `work/runs/20260902_c6_protocol_safety_d1_xbar_zipcpu_axixbar_protocol_d2_ft0` |
| full | 1 | 60 s, 16 jobs | 85 proven, 79 inconclusive, 0 fired | 126 covered, 13 inconclusive | 162/162 nonvacuous | `work/runs/20260902_c6_final_d1b_xbar_zipcpu_axixbar_full_d2_ft0` |
| full | 2 | 45 s, 16 jobs | 82 proven, 82 inconclusive, 0 fired | 141 covered, 6 inconclusive | 160/162 nonvacuous; 2 pending | `work/runs/20260902_c6_full_errorfix_d2_xbar_zipcpu_axixbar_full_d2_ft0` |
| full | 4 | 45 s, 16 jobs | 82 proven, 82 inconclusive, 0 fired | 142 covered, 5 inconclusive | 160/162 nonvacuous; 2 pending | `work/runs/20260902_c6_full_smoke_d4_xbar_zipcpu_axixbar_full_d2_ft0` |

The table above predates the explicit output-profile split and the
single-selected-transaction role consolidation. A fresh
role-disabled run with the exact 7/7/1 output profile is
`work/runs/20260902_c6_protocol_endpoint_caps_xbar_zipcpu_axixbar_protocol_d2_ft0`.
It proves 87 of 120 assertions, leaves 33 inconclusive, fires none, and marks
all 120 assertion targets nonvacuous in 180 seconds on 32 workers. It covers
88 scenarios, classifies four covers as uncoverable, and leaves eight cover
targets inconclusive. Its elaborated hierarchy contains the four complete
endpoint FVIPs and no role instance or role tracker.

Focused, role-free partitions have additionally closed the following current
protocol obligations nonvacuously:

- both output AW-ahead and completed-W-ahead bounds (four assertions), in
  `work/runs/20260902_c6_protocol_output_scalar_bounds_xbar_zipcpu_axixbar_protocol_d2_ft0`
  and
  `work/runs/20260902_c6_protocol_m1_skew_bounds_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- both input exact-RLAST assertions, in
  `work/runs/20260902_c6_protocol_safety_rlast_xbar_zipcpu_axixbar_protocol_d2_ft0`.

Focused proofs are composed only from separately proven assertions. The
runner exposes `FORMAL_TARGETS`, `FORMAL_ASSUMES`,
`FORMAL_ASSUME_REMOVES`, and `FORMAL_ENGINES`; each value is recorded in the
run manifest. Promoting an assertion to an assumption is valid only after its
standalone proof artifact exists. Selector assumptions unrelated to a target
are removed to avoid retaining irrelevant symbolic state. Removing an
environment assumption is a sound proof-cone reduction because it weakens,
rather than strengthens, the target's environment.

Before the single-tracker consolidation described in the handoff log, all
eight generated AR route-conservation assertions had focused proofs. The
source0/destination0 AW no-overflow and no-phantom pair was also proven
nonvacuously in
`work/runs/20260902_c6_role_awroute_conservation_xbar_zipcpu_axixbar_full_d2_ft0`.
These artifacts validate the earlier equivalent per-source/per-destination
formulation; fresh proof evidence is required for the consolidated current
source.
The composed selected-AW integrity experiment promoted those conservation
lemmas and the already-proven endpoint AW-stability rule, but remained clean
and inconclusive at radius 39; it is not counted as a proof.

For the bounded profile, request-READY and response-READY policies are
separate. `ENABLE_MAX_STALL` in the crossbar aggregate constrains only
environment-owned READY signals: BREADY/RREADY at the inputs and
AWREADY/WREADY/ARREADY at the outputs. `ENABLE_INPUT_MAX_STALL` is the
independent DUT performance contract and remains off. This avoids requiring
the DUT to accept W before AW or to accept a downstream response while its
originating input is backpressured.

| Level | Outstanding | Budget | Assertions | Covers | Vacuity | Artifact |
| --- | ---: | ---: | --- | --- | --- | --- |
| protocol, bounded | 1 | 60 s, 16 jobs | 84 proven, 42 inconclusive, 0 fired | 88 covered, 12 inconclusive | 126/126 nonvacuous | `work/runs/20260902_c6_bounded_protocol2_xbar_zipcpu_axixbar_protocol_d2_ft0` |
| full, bounded | 1 | 60 s, 16 jobs | 84 proven, 98 inconclusive, 0 fired | 127 covered, 12 inconclusive | 178/180 nonvacuous; 2 pending | `work/runs/20260902_c6_bounded_full_d1_xbar_zipcpu_axixbar_full_d2_ft0` |

The bounded full run covers all five named C6 scenarios. Its twelve route,
read, and write selected-progress assertions are enabled and inconclusive,
not silently omitted or reported as proofs.

The final short protocol regression is
`work/runs/20260902_c6_final_protocol_xbar_zipcpu_axixbar_protocol_d2_ft0`:
84/120 assertions proven, 36 inconclusive, zero fired, all 120 nonvacuous in
45 seconds. Its formal compile log processes `fv_axi_xbar_fvip` but no role or
role-tracker module, directly auditing the requested boundary.

The generic-view changes were also run against ZIPCPU `sfifo` at the closed C5
profile. `work/runs/20260902_c6_fifo_regression_fifo_zipcpu_sfifo_full_d2_ft0`
has zero fired assertions in 45 seconds; 80/88 assertions resolved and eight
remained inconclusive. Its ten unreachable vacuity checks are the known
zero-stall profile behavior.

## Reproduction

Protocol-only safety:

```sh
ROLE=xbar VENDOR=zipcpu IMPL=axixbar LEVEL=protocol \
  MAX_OUTSTANDING=1 MAX_AW_AHEAD=2 MAX_W_AHEAD=2 \
  MAX_OUTPUT_OUTSTANDING=7 MAX_OUTPUT_AW_AHEAD=7 \
  MAX_BURST_LEN=8 ENABLE_BOUNDED_ENV=0 \
  FORMAL_TIMEOUT=3m FORMAL_JOBS=32 COVER_VCD=0 \
  tools/run_formal.sh
```

Set `ENABLE_BOUNDED_ENV=1` on the same command to enable environment-owned
READY fairness, bounded subordinate responses, bounded W completion, and the
corresponding DUT protocol progress assertions. Protocol level still
elaborates no role module.

Full role smoke for each C6 depth:

```sh
for depth in 1 2 4; do
  ROLE=xbar VENDOR=zipcpu IMPL=axixbar LEVEL=full \
    MAX_OUTSTANDING="$depth" MAX_AW_AHEAD=4 MAX_W_AHEAD=4 \
    MAX_OUTPUT_OUTSTANDING=7 MAX_OUTPUT_AW_AHEAD=7 \
    MAX_BURST_LEN=8 ENABLE_BOUNDED_ENV=0 \
    FORMAL_TIMEOUT=3m FORMAL_JOBS=32 COVER_VCD=0 \
    tools/run_formal.sh
done
```

## Remaining closure work

At depth one, the current retained-original production safety backlog is
eleven protocol properties. The protocol properties
are output 0 `c_profile_w_packet_len`, all four directional WSTRB checks on
each output, and both strengthened output `x_w_last_exact_after_w` instances
whose earlier handshake-level proofs are stale. The eight newly added output
offer-level WSTRB and WLAST assertions are tracked separately. All 19 are
currently open after the clean inconclusive reruns below.

The current role production backlog is five properties: mapped B and the four
selected W-data forwarding checks.  The immediate open B helper roots are the
pending-route/source-B exclusion and its per-ID-head decomposition, mapped-B
routed/live-return, and endpoint-shadow occurrence/data; the remaining open
W helpers are tracked separately.  The reconciled ledger under **Status** is
authoritative; historical property lists later in this log describe their
own source snapshots and are not the current count.

The zero-state AWREADY-independent output strengthening and its directed
mutation gate are complete. Four frozen-source D1 unbounded proof batches then
targeted the four new live-WSTRB checks; the four new offer-WLAST checks plus
the two strengthened after-W exact checks; output 0 packet length; and all
eight retained-original WSTRB directionals. The model compiled with the
measured 172/290 checker/assumption counts and no blackboxes. All 19 targets
were nonvacuous and none fired, but every target remained inconclusive at the
five-minute limit. The respective final radii were 19 for the live-WSTRB
batch, 27--31 for the WLAST batch, 45 for packet length, and 19--21 for the
directional WSTRB batch. This is clean bounded evidence, not closure. Do not
retry either the whole batches or the unproved canonical
`a_pair_completed_wstrb` vector helper unchanged; smaller compositional cones
are required.

The implementation preserves handshake-based occurrence selection and uses
the existing signed skew in three regions: positive for an accepted AW and
current W, zero for a live AW paired with the current/partial W, and negative
for a completed W exposed by a live late AW. The selector itself must remain
handshake-based because rank and skew describe accepted order. Manager inputs
retain their selector-local protocol forms, with universal authority supplied
by the separately validated deterministic Manager contract.

The six protocol bounded-progress checks and three role bounded-progress
checks listed in the reconciled ledger also remain open. They are separate
from safety closure and require the bounded environment profile.

Higher-depth closure is also separate. The exact depth-two standalone
`a_xbar_global_write_lifecycle_conservation` proof now validates the recorded
one-fact composition and closes both depth-two output
`x_write_outstanding_bound` instances. Conservation alone cannot establish
the ZIPCPU O7 boundary at depth four; use either an independently proved,
port-observable ZIPCPU capacity theorem or the generic O8 profile. Current
corrected-profile protocol/full matrices are still required at outstanding
depths 1, 2, and 4; they must resolve every required assertion and retain the
required scenario coverage. No helper proof, conditional composition, or
clean timeout is itself production sign-off.

## Handoff log

This section is intentionally operational. It records unsuccessful proof
partitions as well as successful ones so a later session does not repeat an
unsound reduction or mistake an inconclusive result for a failure.

### 2026-09-03: parameter-exact aggregate and focused proofs

What worked:

- The aggregate now has explicit output endpoint limits:
  `MAX_OUTPUT_OUTSTANDING`, `MAX_OUTPUT_AW_AHEAD`, and
  `MAX_OUTPUT_W_AHEAD`. The previous output limit derived from input depth and
  port count was a role/topology fact in the protocol checker and has been
  removed.
- The two input transaction views both use `MAX_WRITE_DATA_DELAY`; the two
  output views both use `MAX_OUTPUT_WRITE_DATA_DELAY`. This reduced formal
  elaboration to the intended two parameter specializations.
- A fresh exact-profile protocol run is recorded as
  `20260902_c6_protocol_endpoint_caps_xbar_zipcpu_axixbar_protocol_d2_ft0`.
  It elaborates no role hierarchy, fires no assertions, and proves 87/120
  assertions in 180 seconds on 32 workers.
- Focused role-free runs proved the AW-ahead and completed-W-ahead bounds on
  both outputs. Focused role-free runs also proved exact RLAST on both inputs.
- The fresh full-level source0/destination0 AW no-overflow/no-phantom pair is
  proven nonvacuously in
  `20260902_c6_role_s0d0_aw_conservation_fresh_xbar_zipcpu_axixbar_full_d2_ft0`.

What did not close:

- The source0/destination1 and source1/destination0 AW conservation pairs
  stayed inconclusive at approximately radius 37--39 in separate 180-second,
  32-worker runs. They did not fire.
- Each output W-packet-length target stayed inconclusive at approximately
  radius 45 in a separate 180-second, 32-worker run, even after assuming the
  separately proven output AW/W skew bounds. Setting the input skew profile to
  1/1 did not materially improve this result.
- Each output write-outstanding target stayed inconclusive at approximately
  radius 53--55 in a separate 180-second, 32-worker run. No failure was found.
- A composed selected-AW integrity run, using only previously proven
  conservation and AW-stability assertions as lemmas, stayed clean but
  inconclusive at radius 39. It must not be reported as proven.

Invalid reductions and lessons learned:

- Removing all endpoint environment transaction contracts makes an output
  W-packet target fire at radius 26. This is expected: unconstrained inputs no
  longer obey AW/W lifecycle rules, so this is not a crossbar counterexample.
- Removing an entire output subordinate environment contract also makes the
  corresponding W-packet target fire at radius 26. An arbitrary early B can
  then release the crossbar's write grant in the middle of a W lifecycle. The
  downstream B-completion contract is semantically necessary, not proof
  clutter and not a role detail.
- The same all-environment removal makes the previously clean AW conservation
  partitions fire near radius 5. Those traces are outside AXI and are not DUT
  failures.
- The first selective-pruning attempt used
  `*g_wstrb.*`. Questa names generated instances `g_wstrb[0]`, with no dot
  between the generate name and index, so the pattern matched nothing and
  emitted `formal-297`. Use `*g_wstrb*` if this reduction is retried, and
  check the run log for `formal-297` before interpreting results.
- A focused assertion promoted to an assumption is usable only after that
  exact assertion has a standalone proof artifact under the same parameter
  profile. Environment assumptions may be removed to reduce a cone, but a
  target that then fires only demonstrates that the removed contract was
  necessary.
- More wall time alone has not changed the hard-target proof radii enough to
  justify serial long runs. Independent 32-worker partitions use about
  29--35 GiB each. Four at once fit this host's 128 hardware threads and
  377 GiB RAM; do not exceed four, and check available memory before each
  batch.

Current next steps:

1. Add or compose generic endpoint inductive lemmas for the remaining output
   AW/W/write-credit and input B-accounting targets. Do not add a route/decode
   relationship or DUT-internal signal reference to `LEVEL=protocol`.
2. Prove those generic protocol lemmas standalone under the exact current
   7/7/`min(MAX_OUTSTANDING,2)` ZIPCPU output profile, then promote only the
   proven set into role partitions.
3. Close the consolidated role targets and finish the depth 1/2/4 composition
   matrix. The current FIFO smoke is clean, but run the normal C5 sign-off
   profile again after the final generic tracker source is frozen.

### 2026-09-03: single selected role transaction

The first role implementation instantiated a complete source-role checker for
each of the two inputs. Each source checker then instantiated separate AW and
AR route-conservation trackers for each destination. That meant eight route
trackers plus two copies of the read and write end-to-end machinery were live
in every full proof.

The current source instead uses four arbitrary constants:

- `watch_source` chooses input 0 or input 1;
- `watch_route` chooses output 0, output 1, or the local-error path;
- `watch_id` chooses the input-side ordering domain;
- `watch_write` chooses the AW/W/B lifecycle or the AR/R lifecycle.

There is exactly one selected input-side transaction occurrence in a proof,
not one selected transaction per source, destination, ID, or channel. The
rank and occupancy counters do not select or retain multiple transaction
payloads; they count intervening same-ID traffic so the single selected
occurrence can be recognized at the output and on its response return.

One muxed source-role instance now covers both DUT input ports. One
route-conservation tracker covers AW or AR for all four source/destination
routes. That tracker exports the exact selected output request handshake after
its rank reaches zero; the read/write end-to-end trackers consume that event
instead of duplicating route occupancy and route-rank state. They receive
mutually exclusive enables, so only the lifecycle selected by `watch_write`
changes state. Read and write are not forced into one state machine because
their protocol shapes are genuinely different, but neither state machine is
duplicated per port.
This is a role-proof reduction only; the protocol level still contains four
complete, independent endpoint FVIPs and no role selector or role hierarchy.

The current shared-selector elaboration is recorded in
`20260903_c6_role_shared_selector_compile_xbar_zipcpu_axixbar_full_d2_ft0`.
It compiles with one instance each of `fv_xbar_stream_tracker`,
`fv_xbar_read_tracker`, and `fv_xbar_write_tracker`. The full design has 134
assertion checkers, down from 164 in the pre-consolidation full run. Its
focused route-overflow target was nonvacuous, clean, and inconclusive at
radius 27 after 60 seconds; this run validates elaboration and state reduction,
not proof closure. This artifact predates the later sharing of the route-rank
state described below.

The first route-rank-sharing smoke,
`20260903_c6_role_shared_route_counter_xbar_zipcpu_axixbar_full_d2_ft0`,
exposed a role-checker bug: with `watch_route` set to the local-error choice,
the stream tracker counted accepted inputs even though DECERR is intentionally
handled without an output request. Its overflow assertion fired at radius 12;
this was not a DUT counterexample. Gating both sides of route conservation off
for `DEST_ERROR` fixes the mismatch. The corrected run
`20260903_c6_role_shared_route_counter_fix_xbar_zipcpu_axixbar_full_d2_ft0`
is clean and nonvacuous for both route conservation targets through radius 27
in 60 seconds. Neither target closed in that budget.

The fixed nine-bit W-beat counters in the generic channel checker, selected
AW/W tracker, and deterministic manager environment were also replaced by
`MAX_BURST_LEN`-sized counters with one explicit overflow state. Under the
eight-beat profile this reduces each such counter from nine bits to four while
preserving the overflow assertion. The first 120-second output-W experiment
after this counter change reached radius 43 and remained clean/inconclusive,
so counter width alone is not sufficient; it did reduce that focused run's
aggregate engine memory from the previous roughly 29 GiB full-protocol run to
19.9 GiB.

The matching output1 W-packet run
`20260903_c6_protocol_m1_wpacket_compact_counter_xbar_zipcpu_axixbar_protocol_d2_ft0`
was also clean/nonvacuous and inconclusive at radius 41 after 180 seconds.
The output0 and output1 write-credit runs with compact counters both remained
clean/nonvacuous and inconclusive at radius 51 after 180 seconds, using
21.3--21.4 GiB aggregate engine memory. These are
`20260903_c6_protocol_m0_write_bound_compact_counter_xbar_zipcpu_axixbar_protocol_d2_ft0`
and
`20260903_c6_protocol_m1_write_bound_compact_counter_xbar_zipcpu_axixbar_protocol_d2_ft0`.

The role trackers now also use `MAX_BURST_LEN`-sized saturating beat counters
instead of eight-bit counters. Unused selected-length registers were removed.
These reductions preserve an explicit overflow value and rely on no DUT
internal invariant.

The generic AW/W pair tracker and selected B-response tracker previously held
two identical copies of the signed `AW - completed-W` skew. The pair tracker
now owns that state and exports it to the B tracker. The generic read beat
counter is also `MAX_BURST_LEN`-sized and saturating. This is shared endpoint
infrastructure, so both FIFO and crossbar use the same reduced tracker rather
than a crossbar-specific shortcut.

Safety-only deterministic environment models and selected transaction
trackers were still updating response/write-data age state even though their
progress properties were disabled. Those updates are now conditional on
`ENABLE_RESPONSE_PROGRESS` or `ENABLE_WRITE_DATA_PROGRESS`. This preserves
bounded-progress behavior while allowing synthesis to remove unused age
state from the base protocol proof.

The corrected selective-pruning experiment removed WSTRB legality,
output-side read-response assumptions, and irrelevant symbolic selector
assumptions while retaining every AW/W/B lifecycle contract. The pattern
`*g_wstrb*` matched correctly, no `formal-297` was emitted, and assumption
counts fell from 226 to 150 for W-packet targets and 146 for write-credit
targets. Both W-packet targets remained clean/nonvacuous and inconclusive at
radius 45 after 180 seconds, using about 22 GiB aggregate engine memory. The
output0 write-credit target remained clean/nonvacuous and inconclusive at
radius 53, using about 23 GiB. Artifacts:

- `20260903_c6_protocol_m0_wpacket_verified_prune_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_protocol_m1_wpacket_verified_prune_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_protocol_m0_write_bound_verified_prune_xbar_zipcpu_axixbar_protocol_d2_ft0`.

This pruning is valid and modestly improves radius, but does not close the
targets.

The four-way age-gated rerun applied that same verified proof cone, exact
7/7/1 output profile, 180-second timeout, and 32 workers per target. All four
targets were nonvacuous and clean but inconclusive. Output0 and output1
W-packet checks each reached radius 43 and used 20.5/21.0 GiB total peak
memory. Output0 and output1 write-credit checks each reached radius 51 and
used 21.7/19.9 GiB. Artifacts:

- `20260903_c6_protocol_m0_wpacket_age_prune_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_protocol_m1_wpacket_age_prune_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_protocol_m0_write_bound_age_prune_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_protocol_m1_write_bound_age_prune_xbar_zipcpu_axixbar_protocol_d2_ft0`.

The age gating modestly lowers retained memory but is not a proof-radius win:
the otherwise-equivalent ungated/pruned runs reached radius 45 for W packet
and 53 for write credit. Keep the gating because disabled progress state has
no safety meaning, but do not repeat this experiment expecting closure.

For a fast syntax-only check, `nix-shell shell.nix --run 'make compile ...'`
is insufficient because that shell does not add Questa's `vmap`/`vlog` path.
Prepend both
`/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/share/modeltech/linux_x86_64`
and `/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin` to `PATH`.
With that correction, the latest full-role source compiles with zero vlog
errors or warnings (apart from the two deliberately suppressed diagnostics).

Four additional current-source protocol partitions targeted obligations not
covered by the W-packet/write-credit experiments. Every assertion was
nonvacuous, no assertion fired, and none closed in 180 seconds on 32 workers:

- output0 AW/W selected association: 9 inconclusive, minimum radius 15,
  average 23.4, 19.4 GiB;
- output1 AW/W selected association: 9 inconclusive, minimum radius 17,
  average 23.7, 19.1 GiB;
- input0 completed-write/B accounting: 2 inconclusive, minimum radius 31,
  average 31.5, 16.6 GiB;
- input1 AR/R plus completed-write/B accounting: 3 inconclusive, minimum
  radius 31, average 31.7, 17.0 GiB.

The output pair groups assumed only the four separately proven output AW/W
skew bounds. The input response groups promoted no assertions. Artifacts are
`20260903_c6_protocol_m0_pair_group_xbar_zipcpu_axixbar_protocol_d2_ft0`,
`20260903_c6_protocol_m1_pair_group_xbar_zipcpu_axixbar_protocol_d2_ft0`,
`20260903_c6_protocol_s0_b_accounting_xbar_zipcpu_axixbar_protocol_d2_ft0`,
and
`20260903_c6_protocol_s1_rsp_accounting_xbar_zipcpu_axixbar_protocol_d2_ft0`.
More parallel workers exposed no failure but did not supply the missing
inductive strengthening.

After sharing the generic skew counter, current-source 120-second reruns left
both input0 B-accounting targets clean/nonvacuous and inconclusive at radius
33. On input1, `x_r_has_ar` proved nonvacuously; its two B-accounting targets
remained clean/nonvacuous and inconclusive at radius 33. Artifacts are
`20260903_c6_protocol_s0_b_shared_skew_xbar_zipcpu_axixbar_protocol_d2_ft0`
and
`20260903_c6_protocol_s1_rsp_shared_skew_xbar_zipcpu_axixbar_protocol_d2_ft0`.

The current consolidated full-role source is formally elaborated in
`20260903_c6_role_shared_all_trackers_final_xbar_zipcpu_axixbar_full_d2_ft0`.
It retains one route, one read, and one write tracker. Both focused route
conservation assertions were nonvacuous, clean, and inconclusive at radius 25
after 60 seconds. Total peak engine memory was 15.6 GiB, down from 22.4 GiB in
the otherwise similar run before all counter sharing; the state reduction is
material even though it does not by itself close the targets.

The matching ZIPCPU FIFO regression is
`20260903_c6_fifo_shared_tracker_regression_fifo_zipcpu_sfifo_full_d2_ft0`.
It has zero fired assertions in 60 seconds: 64/75 assertions proved and 11
remained inconclusive; all 75 assertion targets were nonvacuous. This is a
clean regression, not full FIFO re-sign-off.

The definitive current-source aggregate snapshots are:

- `20260903_c6_protocol_current_aggregate_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  protocol-only, 87/120 assertions proven, 33 inconclusive, zero fired, and
  120/120 nonvacuous in 180 seconds on 32 workers. It covers 88/100 targets,
  classifies one as uncoverable, and leaves 11 covers inconclusive. Its
  elaborated hierarchy contains no role module or role tracker.
- `20260903_c6_full_current_smoke_xbar_zipcpu_axixbar_full_d2_ft0`: full role,
  82/134 assertions proven, 52 inconclusive, zero fired in 60 seconds on 32
  workers. It covers 103/116 targets, including all five named C6 scenarios,
  and leaves 13 covers inconclusive. All 132 assertions with meaningful
  antecedent vacuity checks are nonvacuous; the two unconditional
  configuration assertions do not produce vacuity targets.

Focused current-source input read runs kept `x_r_has_ar` and `x_r_last_exact`
nonvacuous and clean on both inputs but left the pairs inconclusive after 120
seconds. This solver outcome does not erase the standalone input1
`x_r_has_ar` proof above or the earlier standalone exact-RLAST proofs; it
shows that grouping the two targets did not improve closure. Artifacts are
`20260903_c6_protocol_s0_read_current_xbar_zipcpu_axixbar_protocol_d2_ft0`
and
`20260903_c6_protocol_s1_read_current_xbar_zipcpu_axixbar_protocol_d2_ft0`.

### 2026-09-03: reuse protocol pair skew in the role proof

The role write tracker now consumes `pair_skew` from the selected input view
and both output views. This removes six role-local counters: AW-ahead and
completed-W-ahead at the selected input plus the same pair at each output.
The remaining counters are not additional selected transactions. They are
the bounded ranks needed to recognize the one selected occurrence among
same-ID B responses and untagged W bursts.

Using the wrapper's exact output profile also reduces each output's retained
W-before-AW payload queue from the former conservative depth 10 to depth 1.
The selected input retains depth 4 because its declared W-ahead capacity is
4. The elaborated full design contains one source, one route, one read, and
one write role tracker; it has no role-local `s_aw_pending`, `s_w_ahead`,
`m_aw_pending`, or `m_w_ahead` registers. The names that remain in the source
are combinational positive/negative decodes of the public signed skew.

Both exact-profile syntax checks completed with zero vlog errors and zero
warnings. The source then ran as four simultaneous 32-worker jobs, matching
the host's 128 hardware threads without oversubscription:

- `20260903_c6_pair_skew_shared_protocol_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  84/126 assertions proven, 42 inconclusive, zero fired, and 126/126
  nonvacuous in 60 seconds; 88 covers completed and 12 remained inconclusive;
  19.2 GiB total peak engine memory. Protocol elaboration contains no role
  hierarchy.
- `20260903_c6_pair_skew_shared_full_xbar_zipcpu_axixbar_full_d2_ft0`:
  82/143 assertions proven, 61 inconclusive, zero fired; 104/116 covers
  completed and 12 remained inconclusive. All 141 assertions with vacuity
  checks were nonvacuous; the other two are unconditional configuration
  assertions. Total peak engine memory was 18.3 GiB.
- `20260903_c6_pair_skew_shared_role_xbar_zipcpu_axixbar_full_d2_ft0`:
  all six selected-write assertions were nonvacuous and clean but
  inconclusive after 60 seconds, with proof-radius minimum 19 and average
  23.7; total peak engine memory was 15.0 GiB.
- `20260903_c6_pair_skew_shared_fifo_fifo_zipcpu_sfifo_full_d2_ft0`:
  zero fired assertions, 75/88 proven, 13 inconclusive, and 88/88
  nonvacuous; 60 covers completed and eight were classified uncoverable;
  total peak engine memory was 25.2 GiB. This is a clean regression, not a
  replacement for the final C5 sign-off run.

Lesson: sharing universal protocol conservation state is sound and reduces
role state, but it does not by itself provide the missing induction needed
for selected payload/response closure. Do not restore the duplicate counters
or interpret the focused inconclusive result as a failure.

The first protocol-lemma batch after this refactor split the two subordinate-side
read and write no-orphan obligations into four standalone jobs:

- `20260903_c6_protocol_s0_r_has_ar_pairshared_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved input0 `x_r_has_ar` nonvacuously in 125 seconds (16.8 GiB total peak
  engine memory).
- `20260903_c6_protocol_s1_r_has_ar_pairshared_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved input1 `x_r_has_ar` nonvacuously in 119 seconds (17.3 GiB).
- `20260903_c6_protocol_s0_b_no_orphan_pairshared_xbar_zipcpu_axixbar_protocol_d2_ft0`
  left input0 `x_no_orphan_response` clean and nonvacuous at radius 34 after
  180 seconds (17.9 GiB).
- `20260903_c6_protocol_s1_b_no_orphan_pairshared_xbar_zipcpu_axixbar_protocol_d2_ft0`
  left input1 `x_no_orphan_response` clean and nonvacuous at radius 33 after
  180 seconds (18.7 GiB).

The two read proofs are current-source protocol lemmas and may be promoted in
focused exact-RLAST composition runs. The two B results are not proofs and
must not be promoted. Longer standalone B runs are not the next experiment;
that lifecycle needs a stronger independently proved accounting invariant.

Promoting each newly proved `x_r_has_ar` lemma did not close its corresponding
`x_r_last_exact` target in a 180-second focused run. Input0 remained clean and
nonvacuous at radius 38 and input1 at radius 33. Artifacts are
`20260903_c6_protocol_s0_rlast_composed_pairshared_xbar_zipcpu_axixbar_protocol_d2_ft0`
and
`20260903_c6_protocol_s1_rlast_composed_pairshared_xbar_zipcpu_axixbar_protocol_d2_ft0`.
This demonstrates that response existence is necessary but is not the missing
RLAST-length induction invariant.

The same saturated four-job batch re-ran each output's two AW/W skew bounds.
All four were clean and nonvacuous but remained inconclusive after 120 seconds,
with per-output minimum radius 31 and average 37. The earlier standalone
proof artifacts remain the proof evidence; these results are solver variance,
not invalidation. Artifacts are
`20260903_c6_protocol_m0_skew_reprove_pairshared_xbar_zipcpu_axixbar_protocol_d2_ft0`
and
`20260903_c6_protocol_m1_skew_reprove_pairshared_xbar_zipcpu_axixbar_protocol_d2_ft0`.
Do not repeat the same target grouping under full machine saturation expecting
a deterministic closure result.

The next role-state reduction reuses more of the same public endpoint view.
The selected input endpoint now exports its generic read/write watch IDs in
addition to the already public selector, rank, beat, pending, and completion
state. The role muxes those fields with `watch_source` and uses them directly:

- there is no second role-local `select_now` free variable;
- there is no role-local `watch_id` or `watch_beat` free variable;
- the read role no longer keeps an input outstanding counter, response rank,
  response beat, pending bit, or completion bit;
- the write role no longer keeps an input AW/B outstanding counter, B rank,
  B-pending bit, or B-completion bit.

The one remaining source-role bit records whether the protocol selector chose
an occurrence on the arbitrarily selected route. Output-side outstanding and
rank state remains because it describes the cross-interface mapping of that
same occurrence; independently selected output endpoint trackers cannot
soundly substitute for it. Input-side W payload association also remains
because the generic AW/W pair selector is intentionally independent of the
generic AW/B selector.

Both exact-profile crossbar and FIFO syntax compiles completed with zero vlog
errors and warnings. Four parallel 60-second, 32-worker validation runs then
gave:

- `20260903_c6_protocol_state_reuse_full_xbar_zipcpu_axixbar_full_d2_ft0`:
  82/143 assertions proven, 61 inconclusive, zero fired; 104/116 covers
  completed. Of 141 vacuity jobs, 140 completed nonvacuously in the aggregate
  budget.
- `20260903_c6_protocol_state_reuse_role_xbar_zipcpu_axixbar_full_d2_ft0`:
  all 15 role assertions were nonvacuous and clean, all 11 role covers
  completed, and no assertion fired. This resolves the aggregate's one
  unfinished vacuity job as budget variance, not lost reachability.
- `20260903_c6_protocol_state_reuse_protocol_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  83/126 assertions proven, 43 inconclusive, zero fired, all 126 nonvacuous;
  87 covers completed and 13 remained inconclusive. The role hierarchy is
  absent.
- `20260903_c6_protocol_state_reuse_fifo_fifo_zipcpu_sfifo_full_d2_ft0`:
  75/88 assertions proven, 13 inconclusive, zero fired, all 88 nonvacuous;
  60 covers completed and eight were classified uncoverable.

The full aggregate used 17.8 GiB total peak engine memory, compared with
18.3 GiB immediately before this reuse. The focused role run used 21.0 GiB;
focused and aggregate memory are not directly comparable because their cones
and engine portfolios differ. The elaborated role register list confirms that
only output `m_outstanding`/response ranks and W ranks remain; the removed
input R/B counters and ranks are absent.

### 2026-09-03: reuse selected output protocol occupancy

The role no longer keeps its two read-output and two write-output outstanding
counters. Each output endpoint protocol tracker already observes one
arbitrary, stable full output ID and exports its read/write outstanding count.
The source role therefore keeps an input occurrence eligible only when the
chosen output endpoint's matching read/write watch ID equals
`{watch_source, input_watch_id}`, and then passes that endpoint's public
outstanding count to the read or write role tracker.

This is not a selector-dependent assumption and does not constrain DUT
behavior. The matching expression is only part of `select_now`; because the
output watch ID is an arbitrary proof choice, every prefixed ID is still
eligible. The focused run reaching every role cover and every assertion
antecedent is the over-constraint check for this change.

What worked:

- fixing the aggregate parameter connection directly retained the common
  wrapper boundary; no implementation-specific local wrapper was introduced;
- both exact-profile crossbar and FIFO syntax compiles completed with zero
  errors and zero warnings;
- four simultaneous 32-worker jobs used the host's 128 hardware threads
  without oversubscription;
- `formal_design.rpt` now lists only `m_rsp_rank`, `m_b_rank`, and `m_w_rank`
  in the response/W-order role state. No role-local `m_outstanding` register
  remains.

Validation artifacts:

- `20260903_c6_output_state_reuse_full_xbar_zipcpu_axixbar_full_d2_ft0`:
  82/143 assertions proven, 61 inconclusive, zero fired; 104/116 covers
  completed. All 141 assertions with vacuity jobs were nonvacuous. Total peak
  engine memory was 19.1 GiB.
- `20260903_c6_output_state_reuse_role_xbar_zipcpu_axixbar_full_d2_ft0`:
  all 15 role assertions were nonvacuous and clean but inconclusive; all 11
  role covers completed. Total peak engine memory was 19.3 GiB.
- `20260903_c6_output_state_reuse_protocol_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  81/126 assertions proven, 45 inconclusive, zero fired, and all 126
  assertions nonvacuous; 88/100 covers completed. Its elaborated design has no
  role hierarchy. Total peak engine memory was 19.0 GiB.
- `20260903_c6_output_state_reuse_fifo_fifo_zipcpu_sfifo_full_d2_ft0`:
  75/88 assertions proven, 13 inconclusive, zero fired, and all 88
  nonvacuous; 60 covers completed and eight were classified uncoverable.
  Total peak engine memory was 24.8 GiB.

What did not work: counter removal did not improve proof closure within this
60-second saturated batch. The full aggregate has the same 82 proved role and
protocol assertions as the preceding state-reuse aggregate, while protocol
proof count varied from 83 to 81. This is expected portfolio variance and is
not evidence of a regression because no assertion fired, all antecedents
remained reachable, the required role scenarios remained covered, and FIFO
results were identical.

Lesson: an endpoint's arbitrary-ID occupancy is reusable by a role tracker
when the role's selected occurrence is filtered to the same ordering domain.
Keep the remaining response and W ranks: they identify this particular routed
occurrence within that domain and are not duplicates of occupancy. Further
closure work should add independently provable lifecycle/ordering lemmas,
not restore counters or repeat the same 60-second aggregate run.

The next saturated batch split the consolidated role into four safety-only
partitions with `ENABLE_BOUNDED_ENV=0`. No endpoint assertion was promoted to
an assumption. Every target was nonvacuous and clean, but all remained
inconclusive after 180 seconds on 32 workers:

- `20260903_c6_output_state_route_safety_xbar_zipcpu_axixbar_full_d2_ft0`:
  route no-overflow/integrity reached radii 27/25, 18.6 GiB;
- `20260903_c6_output_state_read_safety_xbar_zipcpu_axixbar_full_d2_ft0`:
  error/completion/data reached radii 33/31/27, 18.0 GiB;
- `20260903_c6_output_state_write_w_safety_xbar_zipcpu_axixbar_full_d2_ft0`:
  sampled completion/integrity and live completion/integrity reached radii
  29/21/27/21, 17.9 GiB;
- `20260903_c6_output_state_write_b_safety_xbar_zipcpu_axixbar_full_d2_ft0`:
  error/mapped B reached radii 31/29, 16.3 GiB.

The route target pattern matched the two top-level route assertions, not the
nested `g_bypass_conservation.a_no_phantom`; the manifest is accurate and the
nested target still needs its own focused run or a broader pattern. Lesson:
disabling progress state and splitting by lifecycle improves radius relative
to a short aggregate but supplies no new induction. Do not repeat this exact
four-run batch. The next useful step is an independently proved generic
tracker bookkeeping lemma followed by composition.

The first generic-bookkeeping attempt added pending-rank invariants to all
read, AW/W-pair, and AW/B trackers. After 120 seconds, the two input endpoint
AW-side pair lemmas, two input endpoint W-side pair lemmas, and two input
endpoint AW/B W-rank lemmas proved. All four read-rank lemmas and the output
or response-dependent instances remained inconclusive. Artifacts are:

- `20260903_c6_tracker_read_rank_lemma_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_tracker_pair_aw_rank_lemma_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_tracker_pair_w_rank_lemma_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_tracker_write_rank_lemma_xbar_zipcpu_axixbar_protocol_d2_ft0`.

Why the broad form did not work independently: observer arithmetic wrapped
after an already-invalid capacity overflow, and a simultaneous orphan
response could cancel a newly accepted request in observer state. More
fundamentally, output instances need the still-open DUT request-capacity/skew
obligations, while input read/B instances need the still-open DUT response
existence obligations. Those dependent assertions are not valid standalone
composition lemmas merely because they describe tracker state.

Observer counters now saturate after a capacity violation, and simultaneous
response/request updates retain the new request when no older request exists.
The original protocol assertion still fires on the offending handshake, so
this does not hide a DUT violation; it only prevents unrelated observer state
from wrapping after a failure. The broad validation run
`20260903_c6_saturating_tracker_lemmas_xbar_zipcpu_axixbar_protocol_d2_ft0`
proved 6/20 candidate lemmas and left 14 inconclusive. Accordingly, the
dependent candidates were removed rather than added to C6's open target set.

The useful proven subset exposed a more direct state-sharing opportunity. The
generic input AW/B tracker selects the same AW occurrence used by the role and
already maintains that AW's completed-W rank, pending bit, and completion bit.
The public view now exports `wr_data_pending`, `wr_data_rank`, and
`wr_data_complete`; the role consumes them and no longer keeps its own
`s_w_rank`, `s_w_pending`, or `s_w_completed`. Only the input-polarity
`a_tracker_pending_w_rank` lemma remains in production, where both instances
have standalone protocol proofs.

Four-way validation after this final narrowing/state reuse:

- `20260903_c6_input_w_state_reuse_full_xbar_zipcpu_axixbar_full_d2_ft0`:
  84/145 assertions proven, 61 inconclusive, zero fired; 103/116 covers
  completed and 13 were inconclusive. All 143 applicable assertion vacuity
  jobs completed nonvacuously; total peak engine memory was 18.7 GiB.
- `20260903_c6_input_w_state_reuse_role_xbar_zipcpu_axixbar_full_d2_ft0`:
  all 15 role assertions were nonvacuous and clean but inconclusive; all 11
  role covers completed; total peak engine memory was 20.8 GiB.
- `20260903_c6_input_w_state_reuse_protocol_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  84/128 assertions proven, 44 inconclusive, zero fired, and 128/128
  nonvacuous; 88/100 covers completed and 12 were inconclusive. Both retained
  input W-rank lemmas proved. Total peak engine memory was 19.1 GiB.
- `20260903_c6_input_w_state_reuse_fifo_fifo_zipcpu_sfifo_full_d2_ft0`:
  76/89 assertions proven, 13 inconclusive, zero fired, and 89/89 nonvacuous;
  60 covers completed and eight were uncoverable. The single new input
  W-rank lemma proved, leaving the prior FIFO inconclusive count unchanged;
  total peak engine memory was 24.5 GiB.

The elaborated crossbar role now has only three order counters:
`m_rsp_rank`, `m_b_rank`, and `m_w_rank`. Lesson: keep a candidate helper only
if it proves independently, and prefer consuming its existing lifecycle state
over merely assuming it. The remaining three ranks describe output response
or untagged-W occurrence order and cannot yet be replaced by the currently
independent output endpoint selectors.

Focused composition of the two independently proved input
`a_tracker_pending_w_rank` lemmas into each of the four W-path role targets did
not close them in 180 seconds. All four targets remained clean, nonvacuous,
and inconclusive; the proof logs confirmed exactly two protocol targets were
converted to assumptions in every run:

- `20260903_c6_input_w_w_integrity_composed_xbar_zipcpu_axixbar_full_d2_ft0`:
  `a_selected_w_integrity`, radius 21, 18.1 GiB;
- `20260903_c6_input_w_w_completion_composed_xbar_zipcpu_axixbar_full_d2_ft0`:
  `a_selected_w_completion`, radius 27, 17.0 GiB;
- `20260903_c6_input_w_sampled_integrity_composed_xbar_zipcpu_axixbar_full_d2_ft0`:
  `a_selected_sampled_w_integrity`, radius 21, 16.0 GiB;
- `20260903_c6_input_w_sampled_completion_composed_xbar_zipcpu_axixbar_full_d2_ft0`:
  `a_selected_sampled_w_completion`, radius 29, 15.4 GiB.

Lesson: the reused input tracker lemma establishes only that the selected AW
still has enough completed-W rank. It does not connect the selected input W
occurrence to the selected output W occurrence or payload. Do not repeat this
composition batch. Closing these targets needs an independently proved route
or W-occurrence correspondence lemma (or further protocol-view state that
expresses that correspondence), while preserving the current single selected
transaction architecture.

The next protocol batch first caught and aborted a launch-profile mismatch:
four exact-current skew jobs were initially started with
`ENABLE_BOUNDED_ENV=1`, whereas the prior standalone skew evidence used the
weaker safety environment. They were stopped before proof and relaunched with
`ENABLE_BOUNDED_ENV=0`; do not treat the aborted directories as evidence.

The corrected batch put one output AW/W skew target in each 32-worker job for
five minutes. All antecedents were nonvacuous and no target fired. One new
exact-current protocol fact closed:

- `20260903_c6_current_m0_w_skew_safety_single_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  output 0 `x_b_ahead_bound` proved in 173 seconds with engine 10, 28.6 GiB
  total peak engine memory.

The other three remained inconclusive:

- `20260903_c6_current_m0_aw_skew_safety_single_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  output 0 `x_a_ahead_bound`, radius 49, 21.5 GiB;
- `20260903_c6_current_m1_aw_skew_safety_single_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  output 1 `x_a_ahead_bound`, radius 49, 21.7 GiB;
- `20260903_c6_current_m1_w_skew_safety_single_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  output 1 `x_b_ahead_bound`, radius 35, 23.7 GiB.

Lesson: after the observer saturation change, the former source-version skew
proofs are not reproducible as a group or merely by extending the timeout.
Only the new output-0 completed-W-ahead artifact may be promoted in an
exact-current composition. The next experiment should use it to prove the
corresponding generic pair-tracker rank invariant; do not promote the three
inconclusive bounds.

An A/B batch then restored the pair tracker's minimal arithmetic skew update
and reran the same four exact safety targets individually for 180 seconds on
32 workers. All four were clean and nonvacuous but inconclusive:

- `20260903_c6_arithmetic_m0_aw_skew_safety_single_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  output 0 `x_a_ahead_bound`, radius 45, 18.8 GiB;
- `20260903_c6_arithmetic_m0_w_skew_safety_single_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  output 0 `x_b_ahead_bound`, radius 34, 18.2 GiB;
- `20260903_c6_arithmetic_m1_aw_skew_safety_single_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  output 1 `x_a_ahead_bound`, radius 47, 20.7 GiB;
- `20260903_c6_arithmetic_m1_w_skew_safety_single_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  output 1 `x_b_ahead_bound`, radius 80, 27.0 GiB.

The arithmetic update did not by itself close a target, although output 1's
completed-W-ahead radius improved substantially. Keep it because the bound
assertion reports the first illegal handshake before the update and the
unsaturated legal transition relation is simpler; do not count this batch as
new proof closure. The exact-current output-0 W-bound proof from the preceding
batch remains the only promotable output skew result.

The channel checker and AW/completed-W pair tracker also held identical
`MAX_BURST_LEN`-sized W-packet beat counters. The channel counter is now the
single owner and is passed into the transaction/pair tracker. The pair-local
counter and its weaker duplicate packet-bound property were removed; the
channel's `c_profile_w_packet_len` is strictly stronger and remains the
single protocol-profile authority. This removes four 4-bit counters from the
2x2 elaboration and two duplicate output assertions.

The shared-counter protocol netlist confirms 4622 state bits and 620 counter
bits, versus 4638 and 636 in the preceding comparable snapshot. It also has
126 assertions instead of 128. The 60-second regression
`20260903_c6_shared_w_beat_protocol_xbar_zipcpu_axixbar_protocol_d2_ft0`
proved 86/126 assertions, left 40 inconclusive, fired none, and completed all
126 vacuity checks nonvacuously. It completed 88/100 covers. In addition to
the two removed duplicates, both previously open output 4KB-boundary checks
closed in this run. Total peak engine memory was 19.0 GiB.

The corresponding focused role run
`20260903_c6_shared_w_beat_role_xbar_zipcpu_axixbar_full_d2_ft0` left all 15
role assertions clean, nonvacuous, and inconclusive while completing all 11
role covers; total peak engine memory was 19.6 GiB. The FIFO regression
`20260903_c6_shared_w_beat_fifo_fifo_zipcpu_sfifo_full_d2_ft0` remained clean
at 75/88 proven and 13 inconclusive with all 88 assertions nonvacuous; 60
covers completed and eight were uncoverable, using 24.4 GiB. Thus the counter
merge reduced state without a protocol, role, or FIFO regression.

Most importantly, grouping all four output skew assertions on the reduced
source reproduced and completed their exact-current safety proof:
`20260903_c6_shared_w_beat_output_skew_group_xbar_zipcpu_axixbar_protocol_d2_ft0`
proved output 0/1 `x_a_ahead_bound` and `x_b_ahead_bound` nonvacuously in 132
seconds with `ENABLE_BOUNDED_ENV=0`, 32 workers, and 27.7 GiB total peak engine
memory. This supersedes the earlier single-target solver-variance caveat: all
four generic output skew bounds may now be promoted together in downstream
protocol compositions. The productive difference was the smaller shared
counter cone plus grouped targets; do not repeat the individual skew runs.

Two zero-state generic pair bookkeeping assertions were then restored in a
narrow form: while a selected AW waits for its completed-W occurrence,
`skew > rank`; while a selected completed-W occurrence waits for AW,
`skew < -rank`. They reuse the existing selector, rank, and shared skew and do
not create another transaction tracker or counter. Both assertions proved
standalone and nonvacuously on each input endpoint in 13 seconds, and both
proved nonvacuously on each output endpoint in 15 seconds after promoting
only that output's two established skew bounds. Artifacts are:

- `20260903_c6_pair_rank_s0_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_pair_rank_s1_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_pair_rank_m0_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_pair_rank_m1_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`.

The output logs each confirm exactly two assertion-to-assumption conversions,
`x_a_ahead_bound` and `x_b_ahead_bound`; no crossbar-role property or internal
DUT signal was used. These rank facts are now eligible for protocol-only
composition into the selected WLAST/WSTRB association targets.

That downstream composition was exercised as four 180-second, 32-worker
safety runs, partitioned by output and WLAST versus WSTRB. Each log confirms
exactly four promoted local protocol facts: the output's two skew bounds and
two pair-rank invariants. All 16 targets were clean and nonvacuous, but none
closed:

- `20260903_c6_pair_rank_m0_wlast_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  four exact-WLAST targets, radius 25--27, 26.4 GiB;
- `20260903_c6_pair_rank_m1_wlast_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  four exact-WLAST targets, radius 25--27, 23.6 GiB;
- `20260903_c6_pair_rank_m0_wstrb_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  four WSTRB targets, radius 17--18, 18.5 GiB;
- `20260903_c6_pair_rank_m1_wstrb_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`:
  four WSTRB targets, radius 17--18, 18.4 GiB.

The bookkeeping lemmas are proven, generic, and state-free, so retain them;
however, they establish occurrence position only and do not establish payload
or W-packet correspondence through the DUT. Do not repeat this composition.
The next protocol work must target the underlying output packet/credit and
input response lifecycles, still without importing any crossbar-role fact.

A subsequent four-part lifecycle launch used `?` to abbreviate endpoint
digits. Questa's property matcher accepts `*` here but did not match `?`; all
four jobs stopped before proof with `formal-297`/`formal-299`, so their
non-`retry` directories are not evidence. The runner now rejects `?` before
the expensive compile and documents `*` as the supported wildcard. The same
partitions were relaunched under `*_retry` artifact names with verified `*`
patterns.

The corrected five-minute retry batch completed with every target nonvacuous
and no fired assertion. It produced three new current-source protocol facts:

- `20260903_c6_shared_counter_output_credit_group_retry_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved both output `x_read_outstanding_bound` assertions. Both output
  `x_write_outstanding_bound` assertions remained inconclusive at radius 51.
  The run used 23.4 GiB total peak engine memory.
- `20260903_c6_shared_counter_input_rlast_composed_group_retry_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved input 1 `x_r_last_exact` after converting only the two already-proven
  input `x_r_has_ar` assertions to assumptions. Input 0 remained inconclusive
  at radius 34. The run used 21.9 GiB.
- `20260903_c6_shared_counter_input_b_accounting_group_retry_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved input 1 `x_no_orphan_response` without promoting any assertion.
  Input 0 no-orphan and both `x_b_has_completed_write` targets remained
  inconclusive at radius 33. The run used 21.9 GiB.
- `20260903_c6_shared_counter_output_wpacket_group_retry_xbar_zipcpu_axixbar_protocol_d2_ft0`
  left both output `c_profile_w_packet_len` targets clean and inconclusive at
  radius 41 after promoting only the four proven output skew bounds. It used
  23.8 GiB.

`property_status.csv`, `vacuity_status.csv`, and `summary.json` were recovered
from all four completed formal reports. The shell instances running this
batch read the runner while its wildcard guard was being edited and reached
an obsolete unmatched quote after formal verification, before the normal
manifest/log move. The checked-in runner now passes `bash -n`; the formal
databases, compile logs, generated Tcl, reports, exact target/assumption
commands, and recovered status files are intact. Lesson: source RTL may be
read while jobs run, but do not patch the executing runner script until its
shell processes have exited.

The next experiment restored the zero-state generic read invariant
`pending |-> outstanding > rank`. It adds no storage and no role knowledge.
Both input instances proved nonvacuously after promoting only their local,
previously proven `x_r_has_ar` facts:

- `20260903_c6_read_rank_s0_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved in 127 seconds, using 20.0 GiB total peak engine memory;
- `20260903_c6_read_rank_s1_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved in 141 seconds, using 21.6 GiB.

The matching output 0/1 jobs promoted only their local, previously proven
`x_read_outstanding_bound`. Both remained clean and nonvacuous at radius 49
after 180 seconds, using 21.1/23.8 GiB. Those artifacts are
`20260903_c6_read_rank_m0_composed_xbar_zipcpu_axixbar_protocol_d2_ft0` and
`20260903_c6_read_rank_m1_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`.
Therefore the production assertion is retained only under `AXI_FVIP_MANAGER`, matching
the selected input state consumed by the role, and the two unproved output
instances are not added to the open protocol target set. Lesson: a generic
lemma may still have materially different induction complexity by polarity;
keep only the production instances with exact proof evidence.

The following safety-only batch used the exact 7/7/1 output profile, five
minutes, and 32 workers per job. No role assertion was in any assumption set.

What worked:

- `20260903_c6_s0_rlast_rank_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved input 0 `x_r_last_exact` nonvacuously in 257 seconds after promoting
  only its proven `x_r_has_ar` and `a_tracker_pending_rank`; total peak engine
  memory was 19.0 GiB. Together with the input 1 result above, both exact
  input RLAST targets now have current-source composition proofs.
- `20260903_c6_s0_b_no_orphan_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`
  proved input 0 `x_no_orphan_response` standalone and nonvacuously in 268
  seconds, using 18.6 GiB. Together with the input 1 result above, both input
  B no-orphan targets are now independently proven.

What did not close:

- `20260903_c6_s1_b_completed_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`
  promoted only input 1's proven B no-orphan and W-rank facts, but
  `x_b_has_completed_write` remained clean/nonvacuous at radius 36 after 300
  seconds, using 19.9 GiB.
- `20260903_c6_m_write_credit_pairrank_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`
  correctly converted all eight established output skew/pair-rank facts, but
  both output write-credit targets remained clean/nonvacuous at radius 53
  after 300 seconds, using 25.0 GiB.

Lesson: the read-rank invariant was the missing induction for input 0 exact
RLAST, while B no-orphan needed only an isolated longer portfolio. The same
rank style should now be applied to the selected AW/B response order because
both no-orphan prerequisites are proven. Pair rank does not strengthen the
global output write-credit property; do not repeat that composition.

The analogous candidate AW/B invariant `pending |-> outstanding > b_rank`
compiled cleanly but did not prove. Each exact input job promoted only that
input's independently proven B no-orphan assertion; both targets were
nonvacuous and clean, but input 0 remained inconclusive at radius 33 and input
1 at radius 34 after 180 seconds. They used 21.7/19.0 GiB. Artifacts are
`20260903_c6_b_rank_s0_protocol_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`
and `20260903_c6_b_rank_s1_protocol_composed_xbar_zipcpu_axixbar_protocol_d2_ft0`.
The candidate is therefore removed from production rather than adding two
unclosed properties. Lesson: the read and write response observers look
arithmetically similar, but the write proof also crosses AW/completed-W/B
joining; do not infer proof closure from the read result.

The role read properties were then composed from the closed protocol read set
only. Both jobs verified exactly eight assertion-to-assumption conversions:
both input `x_r_has_ar`, both input exact-RLAST, both input pending-rank, and
both output read-credit facts. No write fact, role lemma, or DUT-internal
signal entered either assumption set.

- `20260903_c6_role_read_error_protocol_composed_xbar_zipcpu_axixbar_full_d2_ft0`
  proved the local-error read-response role assertion nonvacuously in 210
  seconds, using 24.2 GiB total peak engine memory.
- `20260903_c6_role_read_mapped_protocol_composed_xbar_zipcpu_axixbar_full_d2_ft0`
  left the mapped read data and mapped read completion role assertions clean,
  nonvacuous, and inconclusive at radii 33 and 48 after 300 seconds. It used
  18.0 GiB total peak engine memory.

This establishes that the protocol/role layering is functioning as intended:
the local-error role check closes using only public protocol facts. The same
fact set is not yet sufficient induction for mapped read conservation; do not
repeat this exact mapped-read composition. A new route/conservation lemma or
a smaller proof cone is needed, and any such lemma must remain in the role
layer while consuming only public endpoint views.

A zero-state selected-write phase invariant was added next:
`pending |-> w_pending || wr_data_complete`. It reuses the single generic
input AW observer and introduces no counter, selector, or transaction copy.
The exact-profile protocol source compiled with zero vlog errors/warnings and
132 protocol checkers, exactly two more than the prior 130. Both input
instances then proved standalone and nonvacuously in 12 seconds, with no
assertion promoted:

- `20260903_c6_write_data_state_s0_xbar_zipcpu_axixbar_protocol_d2_ft0`;
- `20260903_c6_write_data_state_s1_xbar_zipcpu_axixbar_protocol_d2_ft0`.

Each job used 8.5 GiB total peak engine memory. This is pure observer
bookkeeping and is retained under `AXI_FVIP_MANAGER`, alongside the already-proven
selected-W rank invariant. It is suitable for protocol-only composition into
the two remaining input `x_b_has_completed_write` checks.

The write-phase fact was composed into the two input early-B checks in
`20260903_c6_s{0,1}_b_completed_phase_composed_*`. Each job promoted exactly
three local, independently proven protocol assertions: B no-orphan, selected
W-rank, and selected write phase. Both targets remained clean and nonvacuous
after five minutes: input 0 at radius 34 using 20.8 GiB total peak engine
memory, and input 1 at radius 36 using 22.2 GiB. The new phase assertion is
valid and useful bookkeeping, but does not provide the missing crossbar
AW/W/B induction. Do not repeat this exact composition.

The isolated role request-route batch did close two of its three safety
obligations without promoting any assertion:

- `20260903_c6_role_route_overflow_isolated_xbar_zipcpu_axixbar_full_d2_ft0`
  proved `a_no_overflow` standalone and nonvacuously in 247 seconds, using
  21.9 GiB total peak engine memory;
- `20260903_c6_role_route_integrity_isolated_xbar_zipcpu_axixbar_full_d2_ft0`
  proved bypass `a_no_phantom` standalone and nonvacuously at 289 seconds.
  Selected payload integrity remained clean/nonvacuous at radius 27 when the
  five-minute job ended; the grouped run used 16.8 GiB.

Thus route capacity and no-fabrication are now established role facts. Two
selected-payload-integrity compositions were launched on the pre-split
source. The earlier
`20260903_c6_role_route_integrity_overflow_composed_*` promoted route
`a_no_overflow`; it re-proved no-phantom at 123 seconds, but selected payload
integrity remained clean/nonvacuous at radius 31 after five minutes, using
28.0 GiB total peak engine memory. The second composition, promoting both
closed route conservation facts, also left integrity clean/nonvacuous at
radius 31 after five minutes and used 16.7 GiB. Its artifact is
`20260903_c6_role_route_integrity_conservation_composed_*`. Do not repeat
either multiplexed-integrity composition.

Because a single integrity assertion still multiplexed the AW and AR proof
cones, it has now been replaced by two class-partitioned assertions driven by
the existing stable `watch_write` choice. Both assertions reuse the same
selector, occupancy/rank counter, sampled bit, and route tracker; no state or
transaction tracker was duplicated. The exact full-role source compiles with
zero vlog errors/warnings. The read/AR partition
`20260903_c6_role_route_read_integrity_split_*` promoted only the two closed
route conservation facts and remained clean/nonvacuous at radius 35 after
five minutes, using 27.6 GiB total peak engine memory. This improves the
pre-split radius of 31 but does not close. The matching write/AW partition
`20260903_c6_role_route_write_integrity_split_*` also remained clean and
nonvacuous, at radius 33 after five minutes using 22.9 GiB. Keep the
state-free property partition because it reduces each proof cone, but it is
not closure by itself.

A further zero-state stream bookkeeping candidate, `pending |-> occupancy >
rank`, proved nonvacuously in 11 seconds in
`20260903_c6_role_route_pending_rank_*`, composed only from the two closed
route conservation facts and using 8.6 GiB total peak engine memory. It
reuses the route tracker's existing occupancy and rank and adds no state. It
is retained. The two class-partitioned route integrity targets were then
retried with all three closed route facts. Neither retry closed in five
minutes: read/AR reached radius 33 and used 19.7 GiB total peak engine memory
in `20260903_c6_role_route_integrity_class0_rank_composed_*`; write/AW reached
radius 31 and used 20.5 GiB in
`20260903_c6_role_route_integrity_class1_rank_composed_*`. Both were clean and
nonvacuous. The rank property is useful independently proven bookkeeping but
is not the missing payload induction; do not repeat either three-fact
composition.

The local-error B role check
`20260903_c6_role_write_error_protocol_composed_*` promoted exactly the six
closed input write bookkeeping/accounting facts, but remained clean and
nonvacuous at radius 36 after five minutes, using 22.4 GiB total peak engine
memory. Those facts alone are insufficient; do not repeat that composition.

The mapped-read role retry consumed its eight closed protocol read facts plus
the two closed route conservation facts. In
`20260903_c6_role_read_mapped_route_composed_*`, mapped response completion
proved nonvacuously at 213 seconds. Mapped data integrity remained clean and
nonvacuous at radius 31 when the five-minute run ended; total peak engine
memory was 19.6 GiB. This is the first mapped read role closure and
demonstrates that role conservation facts can be layered over the complete
protocol proof without feeding role details back into it. The remaining data
target should next consume the read/AR route-integrity partition if that
partition proves; do not repeat the ten-fact composition alone.

Architecture checkpoint (confirmed with the user): configured outstanding
counts and AW/completed-W skew are always bounded. READY stall, response
latency, write-data latency, and role progress are explicit optional bounded-
progress contracts. Safety closure is intentionally run with
`ENABLE_BOUNDED_ENV=0` so fairness cannot mask a safety failure; the enabled
bounded profile is a separate required gate that prevents an environment from
withholding READY or responses forever.

`LEVEL=protocol` elaborates all four independent AXI endpoint FVIPs and no
crossbar role hierarchy. Protocol lemmas may mention port signals and generic
FVIP observer state only, never route/decode knowledge or DUT internals.
`LEVEL=full` retains those checks and adds crossbar functionality consuming
only the four public transaction views. The role has one stable arbitrary
`watch_source` selecting either DUT input/subordinate port, then one arbitrary route,
read/write class, ID, occurrence, beat, and bit. There is no role tracker per
input. Endpoint selected-transaction, outstanding/rank, beat/completion, and
AW/W-skew state is reused; proof-target partitioning must not duplicate state.

The temporary protocol candidate `x_b_waits_for_selected_w` split the only
not-yet-data-complete branch out of input `x_b_has_completed_write` and added
no state. In `20260903_c6_s{0,1}_b_waits_split_*`, input 0 remained
inconclusive at radius 40 after five minutes (25.0 GiB), while input 1 proved
at 232 seconds only because its antecedent was unreachable (21.0 GiB). The
negative branch being unreachable is compatible with correct DUT behavior,
but a vacuous helper cannot provide the required nonvacuous evidence. The
candidate has therefore been removed; retain the original nonvacuous early-B
targets and do not use the input 1 result as proof closure.

Another concrete state merge removed the deterministic input-manager
environment contract's private `current_w_beat` counter. That contract now
consumes the parameter-exact `channel_w_beat` already exported by
`axi_channel_fvip`, just as the pair tracker does. This removes one duplicate
counter per input endpoint without changing the environment contract or role
machinery. The exact protocol profile compiles with zero vlog errors/warnings.
The unoptimized formal-design state count fell by exactly eight bits, from
5200 to 5192, matching two removed four-bit counters; assertion/checker counts
remain 66/132.
Two focused output W-packet jobs,
`20260903_c6_shared_input_wbeat_m{0,1}_wpacket_*`, promoted only their local
proven output skew bounds. Both remained clean and nonvacuous at radius 43
after five minutes, a small depth improvement over the pre-merge grouped
radius 41 but not proof closure. Output 0 used 21.8 GiB total peak engine
memory and output 1 used 21.9 GiB. The counter merge is retained for its exact
state reduction, but it is not the missing output packet induction; do not
repeat the skew-only W-packet composition.

Current-source regressions after this interface/state change compile the
generic Manager contract with the shared channel counter and fire no
assertion:

- `20260903_c6_shared_input_wbeat_fifo_regression_*` proved 86 of 94 FIFO
  full-role assertions in 60 seconds, with the established eight hard targets
  inconclusive. All 94 vacuity checks completed; the ten vacuous properties
  are the known zero-stall profile cases. This is no behavioral regression
  from the prior FIFO result.
- `20260903_c6_shared_input_wbeat_protocol_regression_*` proved 92 of 132
  crossbar protocol assertions in 60 seconds, left 40 inconclusive, fired
  none, and completed all 132 vacuity checks as nonvacuous. It covered 88 of
  100 scenarios and left twelve cover targets inconclusive. This is the fresh
  pre-helper protocol inventory for the reduced-state source.

The combined DUT-output W-packet limit was also split experimentally into two
state-free, role-independent induction helpers: handshake counter-in-range,
and terminal beat requires WLAST. Both output instances were clean and
nonvacuous, but neither helper closed in three minutes. Counter-in-range
reached radius 45 and used 26.6 GiB total peak engine memory in
`20260903_c6_output_wpacket_counter_range_*`; terminal-WLAST reached radius 43
and used 36.1 GiB in `20260903_c6_output_wpacket_terminal_last_*`. Because no
helper produced a composable proof, both candidate assertions were removed
from production. Keep the original combined packet target and do not repeat
this split without a genuinely new public-state invariant.

The first per-output exact-WLAST compositions then promoted the four closed
local pair facts: AW-ahead bound, completed-W-ahead bound, pending-AW rank,
and pending-W rank. All targets were nonvacuous, but none closed in five
minutes. `20260903_c6_output0_wlast_pair_composed_*` left its four cases at
radii 29--31 and used 28.5 GiB total peak engine memory;
`20260903_c6_output1_wlast_pair_composed_*` left all four at radius 31 and used
29.3 GiB. Local pair conservation is insufficient to prove that the
crossbar preserves the input packet boundary; do not repeat this exact
composition.

Two short post-consolidation inventories also compiled cleanly and fired no
assertion:

- `20260903_c6_current_full_safety_d1_*` elaborated exactly 148 safety
  checkers: 132 protocol plus 16 role. In a startup-heavy 60-second run it
  proved 82, left 66 inconclusive, covered 34 of 116 scenarios, and completed
  only 44 of 146 non-configuration vacuity checks. Treat this as a hierarchy
  and smoke audit, not a closure comparison.
- `20260903_c6_current_bounded_protocol_d1_*` elaborated 138 assertions,
  confirming that the bounded protocol profile adds exactly six progress
  checks to the 132 safety checks. In 60 seconds it proved 87, possibly
  vacuously proved one pending check, left 50 inconclusive, covered 58 of 100
  scenarios, and completed 120 of 138 vacuity checks. No bounded-progress
  target is claimed closed from this aggregate run; focused evidence is still
  required.

Four focused jobs removed only unrelated arbitrary-selector assumptions from
their proof groups. Two retried each output's exact-WLAST cases with the same
four closed local pair facts; two targeted the bounded output write-data
progress property with the local AW-ahead and pending-AW-rank facts.
The removals cover read selectors, B selectors, the other endpoints' pair
selectors, and the target pair's unused arbitrary WSTRB beat. They do not
remove any deterministic Manager transaction contract, READY/response bound,
or DUT assertion.

The WLAST pruning reduced the focused assumption count from 224 to 175 and
total peak engine memory from 28.5/29.3 GiB to 22.1/24.6 GiB, but did not
increase proof depth: both
`20260903_c6_output{0,1}_wlast_selector_pruned_*` jobs left all four targets
clean/nonvacuous at radii 29--30 after five minutes. Selector pruning is a
sound resource optimization, not the missing induction; do not repeat the
WLAST case without another new fact.

Both `20260903_c6_bounded_output{0,1}_wdata_selector_pruned_*` jobs reached
radius 95 nonvacuously but remained inconclusive after five minutes. Output 0
used 30.5 GiB total peak engine memory and output 1 used 31.5 GiB. This is
useful bounded-depth evidence, not proof closure. The two output write-data
progress checks remain in the six-property bounded protocol set.

In parallel, the routed-payload integrity assertion is temporarily
partitioned by the existing stable `watch_source` as well as `watch_write`.
This produces four source/class targets but still has one arbitrary source,
one route tracker, one rank/occupancy pair, and one sampled payload bit; no
state or transaction is duplicated. Four focused jobs will retain only the
read or write endpoint selectors needed by their source/class and will use
the three closed route bookkeeping facts. If the candidate does not improve
closure, fold it back to the two class-only assertions.

The runner now also accepts comma-separated `FORMAL_CONSTANTS=signal=value`
entries, applies them before `formal compile`, and records the exact list in
`manifest.env`. This is intended for complete enumeration of existing formal
choice variables, not for constraining functional DUT inputs. In particular,
proving both `watch_source=0` and `watch_source=1` can remove the unused input
mux from each role proof while retaining the production architecture's one
arbitrary selected source and one tracker. A single constant case is never
closure for the arbitrary-source property. `bash -n tools/run_formal.sh` and
`git diff --check` pass after the runner change. The four source/class jobs
above do not use this feature; they test whether assertion partitioning alone
is sufficient before adding constant-case orchestration.

That antecedent-only experiment did not close and has been folded back to the
two class-only production assertions. All four targets were clean and
nonvacuous after five minutes on 32 workers, but source0/read, source1/read,
source0/write, and source1/write remained inconclusive at radii 35, 37, 33,
and 35, using 18.9, 19.6, 18.5, and 18.7 GiB total peak engine memory. The
artifacts are `20260903_c6_role_route_source{0,1}_class{0,1}_pruned_*`.
This gives no useful improvement over the prior class-only radii and would add
two required targets, so do not retain or repeat it.

Operational warning: `tools/run_formal.sh` was edited while those four shell
instances were blocked inside qverify. Bash had not parsed the post-qverify
tail yet, so each instance reported an unmatched-quote EOF after formal
verification finished. The formal databases and `formal_verify.rpt` files are
intact and `formal_report.py` was run manually to generate their result CSVs;
the usual runner-created `manifest.env`, `command.txt`, and captured `run.log`
are absent. This was a post-processing failure, not a formal compile or proof
failure. Never patch the runner while any invocation of it is live. The
current runner itself passes `bash -n` and its diff passes whitespace checks.

Four stronger route-integrity case proofs are now active in
`20260903_c6_role_route_const_s{0,1}_{read,write}_proofengines_*`. Each fixes
both existing formal choices (`watch_source` and `watch_write`) before formal
compile, targets the corresponding production class-only assertion, and
promotes only the three proven route facts. Formal compile confirms both
signals were replaced by the requested constants. The jobs use 32 workers
each and proof engines 5, 7, 9, 10, 12, 17, and 21--26; this adds the
non-default proof/assumption/counter strategies without wasting workers on
liveness-only or bug-hunting engines. Both source cases are required for each
class before any closure claim.

Those four constant-case/proof-engine jobs also remained clean and
nonvacuous after five minutes. Source0/read, source1/read, source0/write, and
source1/write ended at radii 35, 33, 31, and 29, using 28.9, 31.9, 24.0, and
26.8 GiB total peak engine memory. Thus source/class constant propagation and
the non-default proof engines did not improve on the class-only proof; do not
repeat this exact matrix. `FORMAL_CONSTANTS` remains useful for later complete
source/route case decomposition, and all four manifests record both constants
correctly.

The next state/cone reduction consolidates two kinds of duplicate formal
choice. Each generic endpoint now has one arbitrary ID shared by its read and
write selected-occurrence trackers, with one stability assumption at the
transaction aggregate rather than two identical child assumptions. Each
endpoint also reuses the pair tracker's arbitrary burst beat for read-data
sampling, removing the second beat choice and its duplicate stability/range
assumptions. This is sound because the read and write properties remain
separately universally quantified over every ID/beat value; independence
between two proof witnesses is not part of either contract. No selector pulse,
counter, sampled transaction payload, or tracker is merged. The consolidation
also removes the role layer's read/write ID and beat muxes after synthesis.
Fresh protocol/full compilation and FIFO regression are required before using
the reduced source for new closure evidence.

The reduced-selector source compiles with zero vlog errors/warnings. It keeps
exactly 132 protocol and 148 full assertions while reducing crossbar
assumption checkers from 220/228 to 208/216 at protocol/full level. The
60-second protocol smoke `20260903_c6_shared_id_beat_protocol_regression_*`
proved 91/132, left 41 inconclusive, fired none, completed all 132 vacuity
checks as nonvacuous, and covered 85/100 scenarios. The matching full smoke
proved 91/148, left 57 inconclusive, fired none, completed all 146
non-configuration vacuity checks as nonvacuous, and covered 104/116 scenarios.
These are clean hierarchy/regression results, not new closure claims.

The first FIFO safety-profile smoke on this source elaborated 81 assertions,
proved 68, left 13 inconclusive, fired none, and completed all 81 vacuity
checks as nonvacuous in 60 seconds. It covered 60 scenarios and classified
the other eight as unreachable. This run is not directly comparable with the
earlier 94-assertion bounded FIFO regression; an exact 0-stall, 1/1-skew,
four-cycle-response bounded rerun is active as
`20260903_c6_shared_id_beat_fifo_bounded_regression_*`.

A current-source source0/read/destination0 route-integrity proof fixed all
three existing role choices before compile and promoted only
the three closed route facts, and removes unrelated pair/write selectors, the
other input's read selector/ID, and output read occurrence selectors. The log
contains no `formal-297`; only the four expected arbitrary constants remained
in its optimized assumption cone. It proved nonvacuously with engine 12 in 148
seconds, using 27.1 GiB total peak engine memory. This is the first proof of a
routed-address payload case on the consolidated one-tracker source.

The other three read source/destination cases are active as
`20260903_c6_role_route_const_s{0,1}_read_d{0,1}_pruned_sharedsel_*`; the
read-class obligation remains open until all four are proven. The arbitrary
error-route value does not enter the routed stream tracker (`route_select_now`
is false), so the two mapped destination values are the complete nonvacuous
route partition.

The exact bounded FIFO regression on the consolidated-selector source is now
complete as `20260903_c6_shared_id_beat_fifo_bounded_regression_*`. With the
same 0-stall, outstanding-1, AW/W-skew-1/1, four-cycle-response bounded
profile used by the earlier baseline, it proved 88/94 assertions, left six
cleanly inconclusive, and fired none in 60 seconds. Vacuity completed for all
94 targets (84 nonvacuous plus the same ten known zero-stall-unreachable
checks); 53 covers were reached and 15 were classified unreachable. Peak
memory was 24.4 GiB. This is a clean behavioral regression, not new xbar
closure evidence; the two extra proofs relative to the older 86/94 aggregate
can be proof-engine/runtime variation and are not being used as a claim.

A first write-route destination case is also active as
`20260903_c6_role_route_const_s0_write_d0_pruned_sharedsel_*`. It fixes the
existing source/class/route witnesses to source 0, write, destination 0,
targets only the production write-class routed-address integrity assertion,
and promotes only the three closed route bookkeeping facts. Its compile log
confirms all three constants and has not reported an invalid assumption-removal
pattern. If it proves, the remaining three source/destination write cases must
still be run before the write-class production obligation is closed.

At this historical checkpoint, the exact closure backlog was 22 protocol-
safety properties, nine role-safety properties, six protocol bounded-
progress properties, and three role bounded-progress properties, followed by
the complete depth-1/depth-2/depth-4 matrices. Within the nine role-safety
properties, the read-route
payload obligation currently has one of four complete mapped source/route
cases proven; partial case coverage does not reduce the production-property
count until all four cases close.

The source0/read/destination1 case then proved nonvacuously with engine 10 in
292 seconds, using 26.2 GiB total peak engine memory. Together with the prior
source0/read/destination0 proof, both mapped read destinations are closed for
source 0. The two source-1 read cases stayed clean and nonvacuous but timed
out after five minutes at radii 41 (destination 0) and 43 (destination 1),
each using 25.8 GiB. They have been restarted with otherwise identical
constants, pruning, and promoted route facts under a ten-minute timeout as
`20260903_c6_role_route_const_s1_read_d{0,1}_pruned_sharedsel_retry10m_*`.
The production read-class route-payload property remains open until both
source-1 cases prove.

The source0/write/destination0 routed-address integrity case proved
nonvacuously with engine 10 in 191 seconds, using 17.3 GiB total peak engine
memory. The source0/write/destination1 case and the source1/write/destination0
case are now active with the same three route facts and source-appropriate
selector pruning. Four mapped source/destination cases are required, so the
production write-class route-payload obligation remains open.

The source0/write/destination1 case also proved nonvacuously, with engine 12
in 210 seconds and 28.2 GiB total peak engine memory. Both source-0 write
destinations are therefore closed. Both source-1 write destination cases are
now running; their completion is the remaining partition needed for the
production write-class routed-address integrity obligation.

Both ten-minute source-1 read retries proved nonvacuously: destination 0 with
engine 10 in 312 seconds and 27.6 GiB, and destination 1 with engine 10 in 262
seconds and 20.3 GiB. All four source/destination cases are now proven, so the
production read-class routed-address integrity property is closed by complete
enumeration of the existing stable source and mapped-route choices. This
reduces the open role-safety production set from nine to eight properties.

The source1/write/destination0 case also proved nonvacuously with engine 10 in
209 seconds and 17.5 GiB. Three of four write route cases are now proven; only
source1/write/destination1 remains active. No unconstrained or error-route
case is missing: source and the two mapped destinations form the complete
nonvacuous partition for each class, while error does not enter the routed
stream tracker.

Mapped read-data integrity has started as complete source/destination cases.
The first three jobs are source0/destination0, source0/destination1, and
source1/destination0 under `20260903_c6_role_read_data_const_s*_d*_composed_sharedsel_*`.
Each targets only `i_read.a_selected_mapped_response_data`, promotes the eight
closed generic read-protocol facts (input no-orphan/exact-RLAST/pending-rank
for both inputs and read-outstanding bounds for both outputs), the three route
bookkeeping facts, the now-closed read-class route-integrity assertion, and
the previously closed mapped-read completion assertion. The selector pruning
matches the proven read-route cases. These are case-local compositions under
the identical source/class/route constants; all four mapped cases are needed
before mapped read-data integrity can be claimed closed.

That first mapped-read-data composition is a genuine negative result, not an
inconclusive proof. Source0/destination0, source0/destination1, and
source1/destination0 all passed vacuity and fired the target at radius 14 in
18--19 seconds. All 13 requested closed properties were successfully promoted
and no removal pattern was invalid. Do not launch the fourth case or weaken
the target: inspect the generated counterexample first. The identical shallow
failure across sources/destinations points to shared response-beat association
or wrapper normalization rather than route-specific induction difficulty.

Waveform inspection identified the exact cause: the role read tracker now
reuses the selected input endpoint's pair-tracker beat witness, but the route
case's pruning pattern removed every pair-tracker `s_*` assumption. That was
sound for routed-address integrity, which does not consume the beat, but is
not sound for read-data integrity. In the source0/destination0 trace the beat
witness is 0 at selection/route handshake, changes to 4 when the output beat
arrives, and returns to 0 when the input beat arrives. Consequently no output
beat was sampled for the final chosen beat and the assertion fired. This is an
assumption-pruning artifact, not DUT or wrapper evidence. The corrected read
data runs remove only pair occurrence-selection assumptions, keep the selected
input pair's beat stability/range assumptions, and remove beat assumptions
only from the other input and both outputs. This dependency is an important
consequence of the state-sharing optimization; do not reuse the route pruning
list blindly for beat-sensitive role properties.

The final source1/write/destination1 route case proved nonvacuously with
engine 12 in 190 seconds and 28.5 GiB. All four write-class mapped cases are
therefore proven, closing the production write-class routed-address integrity
property by complete source/destination enumeration. The open role-safety set
is now seven properties: mapped read data plus the six write-transaction
properties.

With the selected input beat stability/range restored, the first three
mapped-read-data cases no longer fire. They are clean and nonvacuous but
remain inconclusive after five minutes at radius 35, using 20.5 GiB
(source0/destination0), 21.5 GiB (source0/destination1), and 18.4 GiB
(source1/destination0). This confirms the radius-14 failures were caused only
by unsound pruning, while also showing that full 40-bit response equality is
not closing with the current vector-sampled state. Do not repeat the same
five-minute composition.

The fourth corrected mapped-read-data case, source1/destination1, also
finished clean and nonvacuous but inconclusive after five minutes at radius
37, using 18.2 GiB total peak engine memory. Thus all four corrected mapped
cases have consistent evidence: no DUT failure, but no proof closure with the
full response vector retained in tracker state.

The next candidate reduction is to hoist the route tracker's existing
arbitrary payload-bit selector into the one selected-source role and share it
across route, R-data, W-data, and B-data integrity. Each property remains
universally quantified over its own relevant bit range, but the read/write
trackers can store only the selected bit instead of full 40-bit R, wide W,
and B payload vectors. This adds no selector state relative to the existing
route proof and removes substantial sampled-payload state. It must be applied
only after all live runner invocations finish, followed by fresh protocol/full
and FIFO regressions plus reproof of the route cases on the new source.

That reduction is now implemented. The one seven-bit `watch_payload_bit`
witness lives in `fv_axi_xbar_source_role` and is shared by the route, read,
and write trackers. The route target is guarded by its AW canonical width;
the R, W, and B integrity targets are each guarded by their own parameter-
exact canonical width. Since the stable witness is universally quantified,
proving each guarded bit property proves equality of the entire relevant
payload. Sharing the witness does not couple transaction occurrences or add
state: it replaces the route tracker's previous witness and lets the read and
write trackers retain only one sampled bit.

At the then-current depth-one profile (32-bit data, four-bit input-ID, one-bit
USER, input W-ahead 4, and output W-ahead 1), the change removes 452 sampled
state bits: 39
from the 40-bit saved R response, 407 from eleven 38-bit saved/queued W
payloads, and six from the seven-bit saved B response. The source compiles
with zero vlog errors and warnings.

Four simultaneous 32-worker, 60-second regressions then completed with no
fired assertions:

- `20260903_c6_payloadbit_protocol_regression_*`: 92/132 assertions proven,
  40 inconclusive, 132/132 nonvacuous, and 88/100 covers reached. It retains
  208 assumptions and elaborates no role hierarchy.
- `20260903_c6_payloadbit_full_regression_*`: 91/148 assertions proven, 57
  inconclusive, all 146 non-configuration targets nonvacuous, and 104/116
  covers reached. It retains 216 assumptions, confirming that the selector's
  ownership moved without adding an assumption.
- `20260903_c6_payloadbit_fifo_safety_regression_*`: 72/81 assertions proven,
  nine inconclusive, 81/81 nonvacuous; 60 covers reached and eight classified
  unreachable.
- `20260903_c6_payloadbit_fifo_bounded_regression_*`: 87/94 assertions
  resolved (77 nonvacuous and ten known unreachable), seven inconclusive, 53
  covers reached, and 15 classified unreachable. The one-proof difference
  from the prior 88/94 run is solver/runtime variation and is not used as a
  closure claim.

The read/write routed-address case proofs predate this source change. Even
though the property is semantically the same bitwise equality, reprove all
eight source/destination/class partitions before promoting either route
integrity assertion into the new payload-bit read/write compositions.

The first reproof batch consists of the four read-class mapped route cases,
`20260903_c6_payloadbit_route_s{0,1}_read_d{0,1}_*`. Each fixes only the
existing source/class/route witnesses, targets the production class-0 route
integrity assertion, promotes the three already-closed route bookkeeping
facts, and uses the previously validated source-appropriate selector pruning.
The batch uses four jobs of 32 workers with a ten-minute ceiling so the two
source-1 cases can reach their prior five-minute closure times.

All four read-route cases proved nonvacuously on the payload-bit source.
Source0/destination0, source0/destination1, source1/destination0, and
source1/destination1 completed in 334, 336, 353, and 355 seconds, using 20.0,
19.8, 22.6, and 23.1 GiB total peak engine memory. The optimized assumption
cone in every case contains the shared payload-bit stability fact plus the
selected input and two output ID constants; it contains no duplicate child
payload selector. The production read-class routed-address integrity
obligation is therefore closed again on the current source.

The next four-job batch is
`20260903_c6_payloadbit_read_data_s{0,1}_d{0,1}_*`. It targets mapped R-data
integrity, keeps the selected input's pair-tracker beat stability/range, and
uses the same eight closed endpoint read facts, three route bookkeeping
facts, current-source read-route integrity, and mapped-read completion as the
corrected full-vector experiment. The sole intended difference is the new
one-bit sampled response state.

The source1/destination0 mapped R-data case proved nonvacuously with engine
12 at 597 seconds, using 23.1 GiB total peak engine memory. This is the first
mapped R-data payload case closed. The other three cases remained clean and
nonvacuous through the ten-minute ceiling at radius 37, using 22.0 GiB
(source0/destination0), 18.2 GiB (source0/destination1), and 22.8 GiB
(source1/destination1). The one-bit change therefore did not make every case
fast, but it did produce a proof and reduced the five-minute working memory
from roughly 18--22 GiB to 14--15 GiB. Since the proof arrived three seconds
before timeout, retry the other three cases with a modest 15-minute ceiling
before designing another invariant; do not repeat the old full-vector run.

The three retries are
`20260903_c6_payloadbit_read_data_s{0,1}_d{0,1}_retry15m_*` for the still-open
cases. The fourth available 32-worker slot starts the current-source
source0/destination0 write-route reproof. Mapped R-data is not closed until
all four cases prove.

### 2026-09-03: historical payload-bit closure checkpoint

This checkpoint is superseded by the reconciled ledger under **Status**.
There were no live C6 formal jobs at this particular handoff. Do not infer
closure from any clean inconclusive result below.

Current-source closure gained in this phase:

- All four payload-bit read-route cases proved nonvacuously, as recorded
  above. The production class-0 routed-address integrity property is closed.
- All four payload-bit write-route cases also proved nonvacuously:
  source0/destination0 in 297 seconds (19.8 GiB), source0/destination1 in 183
  seconds (28.7 GiB), source1/destination0 in 137 seconds (26.5 GiB), and
  source1/destination1 in 211 seconds (18.5 GiB). Artifacts are
  `20260903_c6_payloadbit_route_s{0,1}_write_d{0,1}_*`. The production class-1
  routed-address integrity property is closed on the current source.
- The three initially inconclusive mapped R-data cases all proved on their
  15-minute retries: source0/destination0 in 663 seconds (24.1 GiB),
  source0/destination1 in 555 seconds (20.6 GiB), and source1/destination1 in
  496 seconds (20.2 GiB). Together with the original source1/destination0
  proof at 597 seconds, all four mapped cases are proven. The production
  `i_read.a_selected_mapped_response_data` property is closed by complete
  enumeration of the existing source and mapped-route choices.

At this historical checkpoint, the exact remaining safety backlog was
unchanged on the protocol side and smaller on the role side:

- 22 protocol properties: two input `x_b_has_completed_write` checks, two
  output `c_profile_w_packet_len` checks, eight output exact-WLAST cases,
  eight output WSTRB cases, and two output
  `x_write_outstanding_bound` checks;
- six role properties:
  `i_write.a_selected_w_integrity`,
  `i_write.a_selected_w_completion`,
  `i_write.a_selected_sampled_w_integrity`,
  `i_write.a_selected_sampled_w_completion`,
  `i_write.a_selected_mapped_b`, and
  `i_write.a_selected_error_b`;
- six bounded protocol properties: two input read-response progress, two
  input write-response progress, and two output W-data progress checks;
- three bounded role properties: route, read, and write selected progress;
- final protocol/full compositions at outstanding depths 1, 2, and 4, with
  all required assertions resolved and scenario coverage retained.

Local-error B result:

- Source1/error proved nonvacuously with engine 12 in 639 seconds and 23.1
  GiB in `20260903_c6_payloadbit_error_b_s1_*`.
- Source0/error remained clean and nonvacuous but inconclusive at radius 60
  after 15 minutes and 25.1 GiB in
  `20260903_c6_payloadbit_error_b_s0_*`.
- A source0 retry promoted only its three closed input write facts and removed
  unrelated selector assumptions. The optimized cone retained only the
  selected input ID witness, but it still timed out at radius 50 after 15
  minutes and 23.1 GiB, with 176 assumptions instead of 222. Its artifact is
  `20260903_c6_payloadbit_error_b_s0_pruned_retry15m_*`.

Thus local-error B remains a production obligation: one of the two complete
source cases is proven. Do not repeat the same pruning-only retry. A
meaningfully different low-risk solver experiment is to emphasize engine 12,
which closed the source1 case, but this must still produce a nonvacuous
source0 proof before the property can be marked closed.

Live selected-W payload result:

- Conservative source/destination cases source0/destination0,
  source0/destination1, and source1/destination0 all remained clean and
  nonvacuous at radius 31 after 15 minutes, using 24.4, 22.3, and 21.9 GiB.
  Artifacts are `20260903_c6_payloadbit_w_integrity_s*_d*_*`.
- Source0/destination0 and source0/destination1 were retried with only the
  selected source's three closed write facts and the four route facts. The
  selected input beat/ID and selected output ID were retained; all unrelated
  occurrence selectors were removed. Both remained clean/nonvacuous at
  radius 33 after 15 minutes, using 23.4 and 21.4 GiB with 185 assumptions.
  Artifacts are
  `20260903_c6_payloadbit_w_integrity_s0_d{0,1}_pruned_retry15m_*`.

The one-bit payload state and source/destination decomposition are worth
keeping, but selector pruning is not the missing W induction. No W-integrity
case is proven yet, and source1/destination1 has not been attempted on this
target. Do not repeat either 15-minute source0 pruning run unchanged.

Recommended proof order at that checkpoint (now superseded):

1. Keep `LEVEL=protocol` independent and attack the then-open 22 protocol safety
   properties first, especially output W packet/exact-WLAST/write-credit and
   input early-B accounting. Never promote one of these until its exact
   standalone current-profile artifact is proven.
2. On the role side, case-split and target the two payload-independent W
   occurrence properties first:
   `a_selected_w_completion` and
   `a_selected_sampled_w_completion`. Use the same complete source/destination
   constants and the proven route/input-write facts. Their cones do not need
   the payload-bit or beat witnesses, so those unrelated selector assumptions
   may be removed while retaining every AXI lifecycle/environment contract.
   These completion properties are the most direct existing statement of the
   W-occurrence association missing from the payload-integrity proofs.
3. If the W completion cases close, promote only those proven current-source
   cases into the live and sampled W-integrity partitions. Reuse the validated
   four-witness pruned cone: shared payload bit, selected input beat/ID, and
   selected output ID.
4. Retry mapped B after the protocol output write-credit facts and W
   completion association are closed. Finish source0 local-error B with a
   different solver/induction strategy, not another identical pruning run.
5. Close the nine bounded-progress properties only under
   `ENABLE_BOUNDED_ENV=1`, then run the final depth-1/depth-2/depth-4 protocol
   and full matrices. Safety remains based on `ENABLE_BOUNDED_ENV=0`.

For exact command lines, copy `command.txt` or `manifest.env` from the named
run directories. The last source change was the shared payload-bit refactor;
it already passed the zero-warning syntax compile, protocol/full regressions,
both FIFO regressions, and all eight route-case reproofs described above.

### 2026-09-03: bounded contracts, strict B timing, and higher-depth profile correction

This section supersedes the preceding fresh-session stop point. It records
both successful and unsuccessful experiments; a clean timed-out target is
still open.

#### Architecture preserved in this phase

- Outstanding transactions and AW/completed-W skew remain explicit finite
  profile capacities. Protocol safety is still checked with
  `ENABLE_BOUNDED_ENV=0` wherever possible.
- `ENABLE_BOUNDED_ENV=1` separately adds bounded environment-owned READY,
  response availability, and W-data availability. These contracts prevent a
  proof from being defeated solely because an environment can withhold READY,
  B/R, or W forever. They do not convert bounded search into unbounded proof.
- `LEVEL=protocol` now unconditionally enables the complete transaction FVIP
  on all four ports and disables only the cross-interface role hierarchy.
  `LEVEL=full` keeps exactly that protocol layer and adds the crossbar role.
  Both aggregate FVIPs assert the direct configuration invariant
  `ENABLE_ROLE -> ENABLE_TRANSACTION`.
- The role still chooses one stable arbitrary DUT input/source and reuses its
  endpoint ID, rank, AW/W pairing, completion, and burst-position state. No
  per-source role copy was introduced.
- Every new induction fact in this phase uses only AXI port signals and
  generic FVIP state. No DUT hierarchy, route decode, grant, or implementation
  signal was added to a protocol assertion or assumption.

#### Selected-W completion partitions: clean, but not closed

The four complete source/destination partitions of
`i_write.a_selected_w_completion` were run for 15 minutes each. All were
nonvacuous, none fired, and all remained inconclusive at radius 37:

| Source/destination | Elapsed | Peak memory | Artifact |
| --- | ---: | ---: | --- |
| s0/d0 | 900 s | 23.5 GB | `20260903_c6_payloadbit_w_completion_s0_d0_*` |
| s0/d1 | 901 s | 29.1 GB | `20260903_c6_payloadbit_w_completion_s0_d1_*` |
| s1/d0 | 900 s | 26.8 GB | `20260903_c6_payloadbit_w_completion_s1_d0_*` |
| s1/d1 | 901 s | 26.2 GB | `20260903_c6_payloadbit_w_completion_s1_d1_*` |

This complete partition establishes clean evidence only. Longer repetition of
the same cone is not the next step; the missing work is protocol-level
AW/W/B association induction.

#### Protocol-only experiments

The READY-free output W-packet antecedent was changed from `w_hsk` to
`w_valid`, so a DUT cannot evade packet integrity by withholding READY. In
`20260903_c6_ownership_wpacket_*`, both output packet targets were clean and
nonvacuous after 601 seconds, at radii 45 and 47 (average 46), using 24.6 GB;
neither proved.

Two state-free exact-pair facts were normalized into the existing pair
tracker registers and sticky completion state:

- `a_pair_completed_exact` proved nonvacuously on both outputs in
  `20260903_c6_ownership_pair_exact_*` (512 seconds, 25.8 GB).
- `a_pair_completed_wstrb` remained clean/nonvacuous and inconclusive on both
  outputs at radius 23 in `20260903_c6_ownership_pair_wstrb_*` (600 seconds,
  20.7 GB).

The first global completed-write credit formulation in
`20260903_c6_ownership_global_b_credit_*` proved both inputs, but it deducted
a concurrent WLAST and was therefore too weak for strict AXI B timing. It is
superseded and must not be promoted as strict evidence.

#### Bounded environment design and state reduction

Manager-side capacity assumptions are offer-level: AWVALID, WVALID/WLAST,
and WVALID are constrained before capacity is exceeded, without mentioning
DUT-owned READY. One global W-availability timer now covers the state
`completed-W count < AW count`; any WVALID resets it even while WREADY is low.
The rejected per-AW timer design duplicated ages and did not improve the
ownership argument.

The Subordinate environment now uses a deterministic global queue-head
scheduler for R and B, with one scalar age per channel and output. Pop, push,
and simultaneous pop/push are explicit next-state cases. The head remains
scheduled for an entire R burst. A matching VALID resets its timer even when
READY is low; an unrelated stalled VALID pauses the timer because the DUT
owns READY, while unrelated handshakes consume service time. B uses the
prestate `join_write` bypass, not raw same-cycle AW/W acceptance, and an older
queued same-ID write has priority. This is deliberate bounded global-FIFO
burst-service fairness; it is stricter than the full set of legal AXI
cross-ID interleavings and is enabled only in the bounded environment mode.

The first rejected Subordinate design kept per-entry eligible timers. Two
eligible entries could reach their deadlines together and jointly force
mutually incompatible DUT READY behavior. A later sticky selector removed
that collision but kept unnecessary state; the queue-head scheduler replaced
it.

At the depth-one, eight-beat profile, this phase removed 225 sequential bits:

- 15 bits by reusing endpoint-owned `channel_w_beat` counters in the role;
- 40 bits by replacing Manager per-AW W-data ages with one age per input;
- 140 bits by replacing Subordinate per-entry response ages with one R and
  one B age per output;
- 30 bits by elaborating selected R/B/W ages only for the owning polarity.

This 225-bit reduction is separate from the earlier 452-bit payload-bit
reduction. Do not add the two numbers when describing one refactor.

Exactly six bounded protocol-progress assertions elaborate for the 2x2
crossbar: R and B progress at each of the two DUT inputs, plus W-data progress
at each of the two DUT outputs. Full mode adds exactly three selected
role-progress assertions: route, read, and write.

#### Composed deadline profile

Let `N` be the per-input outstanding capacity, `O` the output capacity, `L`
the maximum burst length, `S` the READY-stall allowance, `Dr` the subordinate
response allowance, and `Dw` the Manager W-data allowance. The implemented
ZIPCPU crossbar composition is:

```text
K  = min(2*N, O)
Qr = Dr + S + 1
Qw = Dw + S + 1
F  = K * (S + 2)

Bin    = 2*F + (((K - 1)*L) + 1)*Qr
BoutW  = F   + (((N - 1)*L) + 1)*Qw
Bread  = 2*F + K*L*Qr
Bwrite = 2*F + N*L*Qw + K*Qr
Brole  = max(Bread, Bwrite, Bin, BoutW)
```

The sampled-clock `+1` is intentional. `F` is a chosen ZIPCPU DUT-profile
allowance for arbitration, skids, and return forwarding, not a theorem of a
generic AXI crossbar. With `O=7`, `L=8`, and `(S,Dr,Dw)=(8,16,16)`, the runner,
Makefile, testbench, and aggregate agree on:

| N | K | Input response | Output W data | Role |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 2 | 265 | 45 | 440 |
| 2 | 4 | 705 | 265 | 880 |
| 4 | 7 | 1365 | 695 | 1540 |

The direct testbench/aggregate default does not currently clamp an explicitly
overridden endpoint delay upward into a default role delay, while the runner
and Makefile do. Normal generated runs are consistent; harmonizing that
direct-parameter corner is a low-priority follow-up.

#### Strict B timing

Strict credit is prestate-only. A BVALID may use a write whose AW and complete
W were already accepted before the sampled edge; it may not anticipate a
concurrent WLAST or concurrent AW that consumes an older W burst. Production
therefore computes `unpaired_writes=max(write_skew,0)` without subtracting a
current W completion and requires:

```text
BVALID -> wr_outstanding > unpaired_writes
```

The corrected global property proved nonvacuously on both inputs at depth one
in `20260903_c6_strict_global_b_credit_final_*` (417 seconds, 26.4 GB). The
selected depth-one early-B properties then proved nonvacuously in 14 and 15
seconds, each using 9.9 GB, in `20260903_c6_strict_earlyb_s{0,1}_*`. Those
selected proofs composed the corrected global fact with the already-proven
tracker pending-rank and pending-data-state facts.

At outstanding depth greater than one, a global count cannot distinguish two
legal prefixes with the same total credit but different AW IDs. The minimal
self-contained extension is a FIFO of one-bit tags for unmatched AWs:
`aw_id == watch_id`. It reuses the stable arbitrary ID, the signed skew as
occupancy, and the existing per-ID outstanding count; it adds no pointer,
count, completed-credit counter, or payload. W completion pops the oldest
tag, AW appends a tag only when it remains unmatched, and simultaneous
pop/push replaces the vacated tail. The robust implementation uses
`MAX_AW_AHEAD` bits per input (four here): eight bits total at depths two and
four, and no sequential tag state at depth one. A smaller
`min(MAX_AW_AHEAD,MAX_OUTSTANDING)` queue would require the global strict
property as an induction assumption to exclude earlier bad-B histories, so
the standalone robust observer is retained for rigor.

The new unconditional DUT-input (`AXI_FVIP_MANAGER`) target is
`x_b_has_per_id_completed_write`. The zero-state bridge
was ultimately reduced to the independently inductive
`a_tracker_pending_w_credit_rank_exact`: while a selected write awaits W,
completed same-ID credit equals the number of completed same-ID predecessors.
Together with `a_tracker_pending_data_state`, the new strict target implies
the original selected/role-facing `x_b_has_completed_write`; the latter target
itself remains unchanged.

The first standalone bridge attempts were clean and nonvacuous but did not
close in five minutes. `20260903_c6_strict_selected_credit_exact_d2_*` left
both inputs at radius 31 using 13.8 GB;
`20260903_c6_strict_selected_credit_exact_d4_*` left them at radii 27 and 29
using 13.6 GB. Do not repeat that undivided target unchanged.

The first zero-state decomposition separated incomplete-write state from the
completed-credit side. In `20260903_c6_strict_rank_credit_helpers_d2_*` and
`..._d4_*`, `a_tracker_pending_data_state` and
`a_tracker_pending_w_credit_rank` proved on both inputs in 11--17 seconds.
All antecedents were nonvacuous and no target fired. The stronger
`a_tracker_completed_credit_exceeds_rank` still timed out cleanly: both
depth-two inputs reached radius 31 in 300 seconds and both depth-four inputs
reached radius 27. Total peak memory was 9.7 GB and 15.4 GB respectively.
This rules out repeating either the monolithic bridge or that undivided
completed-credit lemma.

The next split exposed the selected unmatched-AW tag and the watched-tag
prefix sum, using only combinational logic over the existing tag FIFO and
ranks. The final helper shape is generated only when
`MAX_OUTSTANDING > 1`; a synthetic depth-one tag fact was rejected because
it need not remain a valid standalone invariant after an earlier unrelated
protocol violation. In `20260903_c6_strict_prefix_nested_helpers_d{2,4}_*`,
selected-tag membership proved on both inputs in 12 seconds with nonvacuous
antecedents. The exact prefix equality remained clean but inconclusive at
radius 31 for depth two and radius 27 for depth four after 300 seconds, using
12.9 GB and 14.2 GB. Do not rerun that equality unchanged.

Directional runs isolated the equality's hard side. The no-excess (`<=`)
direction proved on both inputs at depth two in 13 seconds and at depth four
in 14 seconds, using 3.6 GB and 4.0 GB, in
`20260903_c6_strict_prefix_le_d{2,4}_*`. The coverage (`>=`) direction stayed
clean and nonvacuous but inconclusive: radius 31/31 at depth two and 29/29 at
depth four after 300 seconds, using 6.5 GB and 6.2 GB, in
`20260903_c6_strict_prefix_ge_d{2,4}_*`. The active replacement cancels the
hard prefix arithmetic: while selected W is pending, watched outstanding is
expressed directly as same-ID B predecessors plus the selected occurrence
plus watched AW tags after it.

That suffix identity was a smaller cone but did not close. Standalone
`20260903_c6_strict_suffix_exact_d{2,4}_*` was clean/nonvacuous at radius 31
for depth two and 27 for depth four after 300 seconds, using 7.6 GB and
6.3 GB. Composing it with the independently proved membership and prefix
`<=` facts made four intended assertion-to-assumption conversions but still
timed out at radius 31 for depth two and 29 for depth four, using 6.5 GB and
6.1 GB, in `20260903_c6_strict_suffix_exact_composed_d{2,4}_*`.

The equality and all prefix-count logic were then removed, leaving only the
lower suffix bound actually needed by the completed-credit argument. That
minimal form also remained clean/nonvacuous and inconclusive in
`20260903_c6_strict_suffix_ge_d{2,4}_*`: radius 31/31 at depth two and
27/29 at depth four after 300 seconds, using 7.1 GB for each run. Do not
repeat these count-difference formulations. The next implementation should
change representation without adding state: repurpose the existing per-ID
outstanding register as prestate completed credit at multi-outstanding depth,
derive outstanding from completed credit plus the existing tag popcount, and
make early B leave the observer/rank state intact after reporting the first
violation.

That state-neutral representation is now implemented. At Manager inputs with
`MAX_OUTSTANDING > 1`, the existing `COUNT_W` per-ID scalar stores completed
credit and the public `outstanding` view is derived as completed credit plus
the watched unmatched-AW tag popcount. At depth one the tag-free lifecycle
representation remains. The existing `b_rank` scalar was also repurposed at
Manager inputs to count only completed same-ID predecessors: it initializes
from prestate completed credit, increments only when a watched predecessor's
W completes, and decrements only when a valid-credit predecessor B
handshakes. `count_dec` and selected pending/rank compaction are both gated by
prestate completed credit, so an illegal early B reports immediately without
also corrupting the observer. There is no new counter or rank state.

This representation made the waiting phase inductive. In
`20260903_c6_strict_completed_rank_helpers_d{2,4}_*`, the two input instances
of `a_tracker_pending_w_credit_rank_exact` proved nonvacuously in about 12
seconds at both outstanding depths. The unneeded completion-side lemma
`a_tracker_completed_credit_exceeds_rank` remained clean/nonvacuous but
inconclusive after 300 seconds: radius 29 and 4.3 GB at depth two, radius 27
and 4.5 GB at depth four. It and the old selected-head bridge were removed;
do not spend more proof time on completion-credit-versus-rank arithmetic.

The primary selector-free target was then isolated with two workers per
depth. `20260903_c6_strict_per_id_credit_direct_rank_d{2,4}_*` remained clean
and nonvacuous but inconclusive after 300 seconds: both depth-two inputs
reached radius 27 and both depth-four inputs radius 25, using 3.5 GB per run.
This is the current direct higher-depth strict-B result, not a proof. A
selected-property run which assumes this still-unproven target is only a
conditional decomposition diagnostic and must not be reported as closure.

The corresponding final-source depth-one direct run was also clean and
nonvacuous but did not close with only two workers. In
`20260903_c6_strict_per_id_credit_final_d1_*`, both input targets passed
vacuity at radius 12 and reached proof radius 40 with no fire before the
480-second timeout. It used 3.8 GB total peak memory and at most 1.2 GB per
engine. This direct timeout is evidence, not closure, and does not supersede
the earlier independently proved global depth-one credit fact.

Depth one does close compositionally without another helper or any state.
At capacity one, the same-input proven `x_no_orphan_response` says that a
watched B ID matches the sole accepted write, while the same-input proven
`x_b_has_global_completed_write` says that the sole write is not among the
positive AW/completed-W skew. Therefore the depth-one watched completed
credit is one. `20260903_c6_strict_per_id_credit_d1_composed_final_*`
converted exactly those two facts for each input, four conversions total,
and proved both final-source `x_b_has_per_id_completed_write` targets
nonvacuously in 14 seconds. It used 2.8 GB total peak memory and 0.4 GB
maximum per-engine peak. The standalone premises are the global-credit run
`20260903_c6_strict_global_b_credit_final_*`, the source-zero no-orphan run
`20260903_c6_s0_b_no_orphan_composed_*` (despite its historical name, it used
no promoted assumptions), and the source-one result in
`20260903_c6_shared_counter_input_b_accounting_group_retry_*`.

That conditional diagnostic is
`20260903_c6_strict_selected_conditional_d{2,4}_*`. Each run made the six
intended conversions for the two input instances: per-ID strict credit,
exact pending credit/rank, and pending-data state. Both original
`x_b_has_completed_write` targets then proved nonvacuously in 19 seconds at
depth two and 20 seconds at depth four, using 2.4 GB per run. This confirms
the minimal logical composition and justifies deleting the completion-side
bridge; it does **not** close strict B because its primary per-ID premise is
the direct target which timed out above.

A read-only transition audit found no smaller selector-free state lemma to
replace that premise. The current assertion, `b_watch ->
watch_completed_credit != 0`, is already the minimal offer-level safety
statement for one arbitrary ID. Tag-head/pop and completed-credit update
lemmas can certify the observer recurrence, but they cannot constrain the
DUT-owned `BVALID/BID`; credit changes only on a handshake, so such a lemma
also says nothing about an invalid stalled B offer. Any purported
tag-head/credit replacement either restates the existing observer equations
or silently assumes the required B safety fact. Mutation 16 demonstrates why
global credit alone is insufficient when another ID owns the available
completed credit. Higher-depth closure therefore needs a stronger proof
partition through already-observed port routing/association behavior, not
another recovery bit or per-ID counter; the direct timeout must remain
visible until that composition is independently proved.

Two redundant sticky registers were then removed from every write tracker:
`completed` is exactly `selected && !pending`, and `wr_data_complete` is
exactly `selected && !w_pending`. Their public hierarchy/view semantics are
unchanged. This saves two flip-flops per write tracker. With four-bit input
tag FIFOs on the two Manager inputs, the configured multi-depth 2x2 xbar has
no net write-tracker state increase versus the pre-tag design (eight tag bits
added and eight redundant bits removed); depth one removes eight bits and
still has no tag state. Final-source zero-warning compiles are:

- protocol depth one: `/tmp/formal_axi_b_final_rank_protocol_d1.qwBHri`;
- protocol depth two: `/tmp/formal_axi_b_final_rank_protocol_d2.zSGlkr`;
- full depth two: `/tmp/formal_axi_b_final_rank_full_d2.KeMco8`.

All three report zero vlog errors, zero warnings, and two deliberately
suppressed diagnostics. The final write-tracker source hash for these runs is
`2a56db4bf46c6f459416747362bc8ec0d043acb82024996df7395e17d596fccc`.

#### Oracle validation

`fvip_validation/reference_models/axi_transaction_oracle.sv` is an exact,
validation-only bounded model; it is not instantiated in production closure.
Its B bypass uses prestate `join_write`, prioritizes an older same-ID queued
write, and permits different-ID reorder. The initial focused regression at
`/tmp/c6_oracle_b_regression.delmb2` reached the legal baseline, write-rank
compaction, and different-ID-reorder cases with no unexpected fire, and both
the oracle and production checker detected same-edge early B.

The mutation suite now also contains directed cases for: B to an ID whose AW
is still unmatched behind another ID's completed W; legal simultaneous tag
pop/push; legal W-before-AW credit; and illegal B on the edge where a later AW
consumes prior W credit. These cases are the validation gate for the new tag
observer.

The focused pre-helper run `/tmp/c6_strict_per_id_mutations` passed all four
new cases. The subsequent all-current 20-case gate is
`20260903_c6_strict_full_mutations_transaction_mutations`. Its CSV has the
header plus all 20 results: every directed sequence was reached, no target
was inconclusive, every required smart/intended/oracle detection occurred,
and no legal case fired. Mutations 16 and 19 fired both the exact oracle and
`x_b_has_per_id_completed_write` for cross-ID early B and same-edge
W-before-AW credit respectively. Legal mutation 17 exercised simultaneous
tag pop/push and legal mutation 18 exercised W-before-AW; neither fired. The
harness now drives the transaction FVIP's shared `w_beat` input with an exact
local burst-position counter instead of leaving that public input
unconnected. This gate includes the first rank-helper decomposition.

The required final-source rerun of mutations 15--19 is
`20260903_c6_strict_completed_rank_mutations_15_19_transaction_mutations`.
It passed with every sequence reached and zero inconclusive or unexpected
fires. Legal different-ID B reorder (15), simultaneous tag pop/push (17),
and W-before-AW credit (18) were clean. Cross-ID early B (16) fired the exact
oracle, the original selected early-B target, and
`x_b_has_per_id_completed_write`; same-edge W-before-AW+B (19) fired the exact
oracle, the global strict target, no-orphan, and
`x_b_has_per_id_completed_write`. Thus the state/rank repurposing and removal
of the two redundant registers preserve all directed legal histories and both
new strict-B detections.

#### Pre-observer depth-one bounded evidence

`20260903_c6_final_bounded_protocol_d1_*` selected exactly the six bounded
protocol progress targets. All six were nonvacuous, none fired, and all were
inconclusive after 300 seconds. The two output W targets reached radius 121;
the four input R/B targets reached radius 532 (average 395). The job used
54.3 GB and the finalized 265/45/440 deadlines. This run predates the per-ID
tag observer and its helper assertions; its selected progress metrics remain
exact, but a current-source aggregate smoke is still required.

`20260903_c6_final_bounded_full_d1_*` selected those six plus the three role
progress targets. All nine were nonvacuous, none fired, and all remained
inconclusive after 301 seconds. Route/read/write reached radius 882, the four
input response targets 532, and the two output W targets 123 (average 557.8).
Peak memory was 54.9 GB. This run also predates the per-ID tag observer and
helpers. These are strong clean bounded searches, not closure.

#### What failed at higher depth, and why

The first bounded full smokes reused `MAX_OUTPUT_W_AHEAD=1`. At depth two,
both output `x_b_ahead_bound` assertions fired nonvacuously at radius 12 in
`20260903_c6_final_bounded_full_smoke_d2_*`. At depth four, output 0 fired at
the same radius in `20260903_c6_final_bounded_full_smoke_d4_*`; output 1 was
nonvacuous but inconclusive, not proven. The depth-two symmetric traces are
sufficient to classify the profile error.

The counterexample is legal AXI behavior. While output AWVALID was stalled by
AWREADY=0, two consecutive one-beat WVALID/WREADY/WLAST handshakes occurred.
The public pair skew changed `0 -> -1 -> -2`. At the first completion the
wrapper AW skid was empty; by the second it held the first address while the
core's registered AW output held the second. W drained independently. The
environment stayed within `MAX_STALL=8` and did not constrain DUT-owned
VALID, so this is neither a DUT protocol bug nor an ownership leak.

For this locked-grant ZIPCPU `axixbar` implementation/wrapper the tight
profile is:

```text
MAX_OUTPUT_W_AHEAD = min(MAX_OUTSTANDING, 1 core AW stage + 1 AW skid)
```

Thus depth 1/2/4 use 1/2/2. The runner and Makefile derive this only for
`xbar/zipcpu/axixbar`; generic FVIP parameters remain explicit and
overridable. No implementation signal is used in the assertion itself.

Focused unbounded-safety reruns with the corrected cap are
`20260903_c6_output_w_ahead_cap2_d{2,4}_*`. Both outputs at both depths were
nonvacuous and had zero fires after 300 seconds. Depth two reached radius
37/37 and used 13.8 GB; depth four reached radius 42/38 and used 11.5 GB.
All four results are inconclusive. They validate well past the old radius-12
failure but do not yet prove the cap.

#### Current exact-pair composition results

The canonical completed-pair invariant materially simplified the split WLAST
checks. In
`20260903_c6_pair_exact_wlast_composed_current_xbar_zipcpu_axixbar_protocol_d2_ft0`,
exactly the two output `a_pair_completed_exact` facts were promoted to
assumptions and six of the eight directional WLAST targets proved. On both
outputs, `x_w_last_exact_after_aw`, `..._simultaneous_aw`, and
`..._simultaneous_w` closed. All eight antecedents were nonvacuous, no target
fired, and there were no matcher warnings. The two `..._after_w` targets
were initially clean and inconclusive at radii 31 and 33 after 300 seconds.
Total peak memory was 13.8 GB with 16 engines. Do not repeat that eight-target
batch unchanged.

The state-free `a_tracker_after_w_capture` bridge then proved on both outputs
in 15 seconds, nonvacuously, in
`20260903_c6_after_w_capture_helper_current_*`. A first attempt to use that
future-state fact to prove the old same-edge expression backward was uneven:
`20260903_c6_after_w_exact_composed_current_*` proved output 1 but left output
0 inconclusive after 300 seconds. The production after-W assertion was then
rewritten into its equivalent post-capture form over the sticky selected-pair
registers. In `20260903_c6_after_w_postcapture_composed_current_*`, both
outputs proved nonvacuously in 13 seconds with exactly four intended
conversions: each output's already-proven completed-pair exact fact and
after-W capture bridge. No target fired. Together with the prior six cases,
all eight output exact-WLAST association cases were compositionally closed on
that source snapshot at the corrected output profile. The later
AWVALID-level strengthening supersedes the two `x_w_last_exact_after_w`
instances, whose handshake-level proofs are now stale; the other six closures
remain current.

The analogous whole-vector WSTRB composition did not close. In
`20260903_c6_pair_wstrb_exact_composed_xbar_zipcpu_axixbar_protocol_d1_ft0`,
both output `a_pair_completed_wstrb` targets were nonvacuous and had zero
fires, but both remained inconclusive at radius 25 after 300 seconds. The run
made exactly two intended `a_pair_completed_exact` conversions and used
7.4 GB with eight engines. Do not repeat that vector target unchanged. The
next candidate is a stable arbitrary-lane scalarization, provided its
universal selector contract and state-bit accounting survive review.

That review and implementation are now complete. `axi_pair_tracker.sv` uses
independent stable arbitrary beat and byte-lane choices and one stored strobe
bit. The bit rolls before selection and while an AW-first choice is pending,
then freezes for a W-first or completed choice. Combinational one-hot
projections reuse the existing `wstrb_valid` geometry, so the AXI byte-lane
algorithm is not duplicated. The deterministic Manager environment contract
still checks every bit of every beat; the arbitrary-lane abstraction is used
only for selected-pair reasoning and DUT-output assertions. This replaces two
`DATA_W/8`-bit pair-tracker registers with one bit: seven sequential bits
saved per tracker at 32-bit data width, or 28 across the four xbar endpoints.
The two-bit `watch_lane` domain is arbitrary constant input, not sequential
state.

Focused mutation gate `20260903_c6_wstrb_scalar_mutations_transaction_mutations`
passed cases 0 and 5. The legal case reached its sequence with no fire or
inconclusive target. The wrong-WSTRB case reached its sequence and fired
exactly the scalar canonical invariant, `x_wstrb_after_aw`, and the exact
oracle; the scalar capture/freeze helpers proved. Both cases compiled with
zero errors/warnings and no blackboxes. Standalone helper and canonical
output gates have now completed.

`20260903_c6_wstrb_scalar_helpers_xbar_zipcpu_axixbar_protocol_d1_ft0`
targeted capture, freeze, and the extended after-W capture bridge on both DUT
outputs. All six assertions proved, all six vacuity checks passed, and no
target fired or remained inconclusive. The proof took 15 seconds with eight
engines, 4.0 GB total peak memory, and 0.4 GB maximum per-engine peak. This
closes the state-maintenance part of the scalar representation.

The composed canonical output check did not close within the short budget.
`20260903_c6_wstrb_scalar_m0_canonical_xbar_zipcpu_axixbar_protocol_d1_ft0`
targeted only output 0's `a_pair_completed_wstrb` and converted exactly five
same-instance facts: `a_pair_completed_exact`, `x_a_ahead_bound`,
`x_b_ahead_bound`, `a_tracker_pending_aw_rank`, and
`a_tracker_pending_w_rank`. There were no matcher warnings or blackboxes. The
target was nonvacuous at radius 12 and had no counterexample, but remained
inconclusive at proof radius 27 after 300 seconds. The run used eight engines,
6.8 GB total peak memory, and 1.1 GB maximum per-engine peak. Both standalone
jobs used the unbounded protocol profile at depth one, fall-through zero,
`MAX_OUTPUT_W_AHEAD=1`, and the finalized 265/45/440 timing values. Formal
compilation reported only the known five ignored-initialization and five
expression-folding warnings; vlog had zero errors/warnings.

Both formal jobs captured the same frozen dirty-source snapshot. SHA-256 was
`0f1e908cee1a4533c2c90704209f5b8ba69d2897557c407611dd9ea721fb5bad`
for `axi_pair_tracker.sv` and
`f812661af77b9bac3cb33c606461ce4fc4c29c12ce1118441579e26961aac264`
for `axi_write_tracker.sv`; the artifact manifests record repository commit
`92d11239551820fab25f20902327e5c3709f975d`. The protocol and full compile
gates `work/build/20260903_c6_wstrb_scalar_compile_xbar_{protocol,full}` both
completed successfully, and `git diff --check` passed for the pair tracker.
Do not change the scalar representation based only on the canonical timeout:
the next step is a reviewed predicate-level decomposition, followed by a
focused rerun.

That predicate-level decomposition is implemented and its prerequisite gates
pass. `pkg_axi_fvip.sv` now calculates the AXI legal-byte mask in one shared
`wstrb_legal_lanes` function. The pre-existing full-vector `wstrb_valid`
contract consumes that mask unchanged, while the new `wstrb_lane_valid`
predicate accepts a zero strobe bit or an asserted bit selected from the same
mask. The pair tracker calls the scalar predicate directly and no longer
constructs either one-hot `STRB_W` projection. The deterministic Manager
environment still invokes full-vector `wstrb_valid`; no assumption was
scalarized and no sequential state was added. A state-free equivalence
assertion retains an auditable comparison with the old one-hot semantics.
The before/after helper artifacts each report exactly 4960 elaborated design
register bits, confirming a zero-state-bit delta for the predicate factoring.

Both factored-source compile gates
`work/build/20260903_c6_wstrb_lane_pred_compile_xbar_{protocol,full}` passed
with zero vlog errors/warnings and the two intentionally suppressed
diagnostics. The first raw `make compile` attempt did not reach HDL compilation
because `vmap` was absent from `PATH`; rerunning through `shell.nix` with both
documented Questa directories prepended produced the passing artifacts above.
Do not interpret that environment-only failure as a source regression.

`20260903_c6_wstrb_lane_pred_equiv_xbar_zipcpu_axixbar_protocol_d1_ft0`
proved both output instances of `a_tracker_wstrb_lane_predicate_equiv`, with
both nonvacuous at radius 2. It took 14 seconds on eight engines and used
3.2 GB total peak memory, 0.3 GB maximum per engine. The corresponding helper
gate `20260903_c6_wstrb_lane_pred_helpers_xbar_zipcpu_axixbar_protocol_d1_ft0`
again proved all six output capture/freeze/after-W helpers, all nonvacuous,
in 15 seconds with 4.0 GB total peak memory and 0.4 GB maximum per engine.
Both formal compiles had no blackboxes and only the known ten frontend
warnings.

Mutation gate
`20260903_c6_wstrb_lane_pred_mutations_transaction_mutations` also passed.
Cases 0 and 5 both reached their directed sequences with no inconclusive or
unexpected fire. Legal case 0 had no fire. Wrong-WSTRB case 5 fired exactly
`a_pair_completed_wstrb`, `x_wstrb_after_aw`, and oracle lane-0 `x_wstrb`.
Both mutation cases compiled with zero vlog errors/warnings and no blackboxes.

These prerequisite jobs captured package SHA-256
`6ca2a70e7a42da25316e8a517d38b751ac5488680250188bd5689c515f711a4f`,
pair-tracker SHA-256
`84949ed5e6e32d6d3355328b9ae8fde353bb4d25126ecd4be96dd7b9fbc4ab6e`,
and write-tracker SHA-256
`f812661af77b9bac3cb33c606461ce4fc4c29c12ce1118441579e26961aac264`.
The strict-B write tracker changed after all three jobs had compiled their
sources, so these artifacts do not validate later strict-B edits. Hold the
canonical output retries until the current write-tracker derivation is frozen
and compile-clean; keep the package and pair-tracker hashes fixed across that
handoff.

The factored canonical retries are
`20260903_c6_wstrb_lane_pred_m{0,1}_canonical_xbar_zipcpu_axixbar_protocol_d1_ft0`.
Each targeted only its output instance's `a_pair_completed_wstrb` and made
exactly the same five intended local conversions listed above. Both targets
were nonvacuous at radius 12, neither fired, and both remained inconclusive
at proof radius 27 after 300 seconds on eight engines. Output 0 used 6.4 GB
total peak memory and output 1 used 7.1 GB; both had a 1.1 GB maximum
per-engine peak. There were no matcher warnings or blackboxes. These jobs
captured package/pair/write SHA-256 prefixes `6ca2a70e`/`84949ed5`/`2a56db4b`
(the full digests are recorded earlier in this handoff). Predicate factoring
therefore preserves rigor and removes the
projection, but it does not close the sticky canonical induction. Do not
repeat it unchanged; target the four production directional cases on both
outputs directly, without assuming this unproved canonical fact.

That direct grouped run is
`20260903_c6_wstrb_lane_pred_directional_xbar_zipcpu_axixbar_protocol_d1_ft0`.
It selected exactly the eight output `x_wstrb_{after_aw,after_w,
simultaneous_aw,simultaneous_w}` properties and promoted no assertion. All
eight antecedents were nonvacuous: simultaneous cases at radius 10 and
ordered cases at radius 12. No target fired, but all eight remained
inconclusive after 300 seconds on 16 engines. Both `simultaneous_aw` targets
reached proof radius 27; the other six reached radius 25, for a 25.5 average.
Total peak memory was 13.8 GB and the maximum per-engine peak was 1.1 GB.
This captured the same `6ca2a70e`/`84949ed5`/`2a56db4b` snapshot and had no
blackboxes or assumption conversions. The scalar cone alone is therefore not
enough to close an eight-way aggregate. Partition the production cases by
join shape; do not spend another run on the canonical invariant.

The first shape-partition wave also records the complete current xbar formal
source snapshot after the global-counter export/helper work. Taking sorted
SHA-256 records over the 28 HDL/flist files under `axi_sva/our`, both role
directories, the two SVA wrappers, `tb_xbar.sv`, `qverify/flist.f`, and the
exact compiled ZIPCPU/PULP DUT files gives composite digest
`8145674fb042c17adda4dec82285a5246dfb2b16972033e37f3167a8b1e69c35`.
Key individual hashes are `bf47e44c...51d531c` for
`axi_fvip_txn_view_if.sv`, `be07e933...e02d36` for
`axi_transaction_fvip.sv`, `2a56db4b...96fccc` for `axi_write_tracker.sv`,
and the package/pair hashes recorded above. This is the source closure being
used by the partition artifacts; later edits must not be attributed to them.

The first two-output shape partitions on that snapshot did not close. In
`20260903_c6_wstrb_lane_pred_after_aw_partition_xbar_zipcpu_axixbar_protocol_d1_ft0`,
both `x_wstrb_after_aw` instances were clean, nonvacuous at radius 12, and
inconclusive at proof radius 27 after 300 seconds. It used 16 engines,
13.4 GB total peak memory, and 1.0 GB maximum per-engine peak. In
`20260903_c6_wstrb_lane_pred_simultaneous_aw_partition_xbar_zipcpu_axixbar_protocol_d1_ft0`,
both `x_wstrb_simultaneous_aw` instances were clean, nonvacuous at radius 10,
and likewise inconclusive at proof radius 27 after 300 seconds. It used 16
engines, 16.7 GB total peak memory, and 1.1 GB maximum per-engine peak. Neither
job promoted an assertion or had a blackbox/matcher issue. Partitioning gave
each target substantially more portfolio capacity but no proof closure.

After those jobs compiled, `axi_transaction_fvip.sv` changed from captured
SHA-256 `be07e93358886eee96a05a473d69910d67fda08774925d7b7a56d6206ee02d36`
to `ace4d59f098c5312b1dd6f64eabcca99c7e5c5ce71b8e8a0b6c57f1d59d00a2c`.
Do not attribute the newer transaction-helper edit to either first-wave
artifact. Re-freeze and compile-audit that snapshot before the after-W and
simultaneous-W partitions.

The second wave used that confirmed `ace4d59f` transaction snapshot. Its
otherwise identical 28-file composite digest is
`aefb75e7327dbb1f23f3a0288f58b6f6df072c3e3f6519eec6f2667ba475b671`;
package/pair/write/view/transaction prefixes are respectively
`6ca2a70e`/`84949ed5`/`2a56db4b`/`bf47e44c`/`ace4d59f`. In
`20260903_c6_wstrb_lane_pred_after_w_partition_xbar_zipcpu_axixbar_protocol_d1_ft0`,
both `x_wstrb_after_w` instances were clean, nonvacuous at radius 12, and
inconclusive at proof radius 29 after 300 seconds. It used 16 engines,
14.0 GB total peak memory, and 1.1 GB maximum per-engine peak. In
`20260903_c6_wstrb_lane_pred_simultaneous_w_partition_xbar_zipcpu_axixbar_protocol_d1_ft0`,
both `x_wstrb_simultaneous_w` instances were clean, nonvacuous at radius 10,
and inconclusive at proof radius 27 after 300 seconds. It used 16 engines,
14.9 GB total peak memory, and 1.1 GB maximum per-engine peak. Neither job
promoted an assertion or reported a blackbox/matcher problem.

Thus scalarization, canonical composition, an eight-target direct run, and
four two-target shape partitions all remain clean but do not close WSTRB.
The direct-run proof cone still contains about 3002 state bits and 176521
logic gates and consumes all sixteen input full-vector WSTRB assumptions.
Those four completed shape partitions, including both second-wave jobs, are
the complete raw baseline; do not repeat another canonical or shape retry
unchanged.

The next AW-first decomposition is now implemented without new sequential
state. `x_wstrb_live_after_aw` checks the arbitrary lane whenever the selected
AW is at rank zero, its watched W beat is offered, and `WVALID` is high.
It deliberately does not require `WREADY`. The parallel
`x_wstrb_live_select_aw` covers the selection edge at `skew==0`, so the first
or current offered beat cannot disappear between selection and `pending_aw`.
The same patch preserves all four previously closed completed/handshake-level
WLAST assertions and adds `x_w_last_offer_after_aw` and
`x_w_last_offer_select_aw`. These parallel offer-level checks reject both
early and missing WLAST independently of `WREADY` once the watched AW is
accepted/selected. `select_aw` itself currently requires an AW handshake, so
an `AWREADY`-low offer still relies on the deterministic input contract and,
for a universal DUT-output theorem, needs a later output-anchored
strengthening. The rules do not replace or weaken the retrospective W-first
cases. All four new rules use source polarity, so
they are assertions at DUT Manager outputs and assumptions at external
Manager inputs. The pair tracker SHA-256 for this patch is
`eac235590a2e7cd516fd48767da424d1cc24dca72477460cb60ed4715b53dd4a`;
package/write/transaction/view hashes remained respectively
`6ca2a70e7a42da25316e8a517d38b751ac5488680250188bd5689c515f711a4f`,
`2a56db4bf46c6f459416747362bc8ec0d043acb82024996df7395e17d596fccc`,
`ace4d59f098c5312b1dd6f64eabcca99c7e5c5ce71b8e8a0b6c57f1d59d00a2c`,
and `bf47e44c43736c44d004ab07cd5ca9145a5c83e285303328e5f205b2951d531c`.
The code adds only concurrent same-cycle predicates, for an exact zero
design-FF delta.

The source-only gates
`work/build/20260903_c6_wstrb_aw_live_compile_xbar_{protocol,full}` both
passed with zero vlog errors or warnings and two intentionally suppressed
diagnostics. As in the earlier predicate gate, the first raw shell invocation
failed before HDL compilation because `vmap` was absent from `PATH`; the
passing artifacts were then generated with the two Questa directories
prepended. `git diff --check` passed. Focused transaction mutation artifact
`20260903_c6_wstrb_aw_live_mutations_transaction_mutations` also passed cases
0 and 5. Legal case 0 reached its sequence with no fire or inconclusive
target. Wrong-WSTRB case 5 reached its sequence and fired the exact oracle,
`a_pair_completed_wstrb`, `x_wstrb_after_aw`, and the new
`x_wstrb_live_after_aw`; it had no unexpected or inconclusive target. Both
mutation compiles had zero errors/warnings and no blackboxes.

The first live-only proof is
`20260903_c6_wstrb_aw_live_helpers_xbar_zipcpu_axixbar_protocol_d1_ft0`.
It targeted exactly both output instances of `x_wstrb_live_after_aw` and
`x_wstrb_live_select_aw`, promoted no assertion, and used the unbounded N1,
O7, output-W-ahead-one protocol profile with 265/45/440 timing. All four
antecedents were nonvacuous: the select-edge cases at radius 10 and pending-AW
cases at radius 12. All four targets fired by 16 seconds rather than becoming
inconclusive. The run used 16 engines, 7.2 GB total peak memory, and 0.5 GB
maximum per-engine peak; vlog was clean, formal compilation had only the ten
known frontend warnings, and there were no blackboxes. Four parseable error
VCDs are retained under the artifact.

Those traces identify an environment-contract hole, not a demonstrated DUT
WSTRB transformation bug. In the output-0 select-edge trace, input 0 accepts
an AW with address 3, size 2, FIXED burst, and length 4, then offers the first
W beat with `WSTRB=4'b0100`; only lane 3 is legal. That invalid input offer is
forwarded to output 0 while output `WREADY` is low, where the live assertion
correctly fires. The pending-AW trace is analogous: address 1, size 1, FIXED,
watched beat 1 and lane 0 asserted while stalled, although only lane 1 is
legal. At that source snapshot the deterministic Manager environment
constrained full-vector WSTRB only when `join_write` saw a completed W burst.
Payload stability eventually preserved an accepted bad beat, but a finite
trace could expose the offer through the xbar before WLAST/completion activated
that assumption. Selector-conditioned pair assumptions cannot replace the
deterministic rule: the selector can simply leave a bad input occurrence
unselected.

That next change is now implemented in the deterministic Manager contract
without new state. The current incomplete W packet maps to `aw_q[w_count]`
when `w_count < aw_count`, to the live AW offer when the counts are equal, and
a live AW maps to completed `w_q[aw_count]` when completed W is ahead. For
every association whose AW metadata is known, the contract constrains beat
position continuously and exact WLAST plus the full WSTRB vector on every
`WVALID`, independently of `WREADY`. When AW arrives late it also validates
the already captured partial prefix or completed W packet immediately on
`AWVALID`, independently of `AWREADY`. The original head-of-queue completed
checks remain as retrospective coverage. This corrects the earlier
`aw_q[0]` shorthand: ordinal pairing, not queue head alone, identifies the
current incomplete W packet. The dedicated mutation suite is the independent
gate before rerunning and composing the live output assertions.

The first complete-looking validation attempt was deliberately not accepted
at face value. In
`20260903_c6_manager_offer_mutations_v4_manager_offer_mutations`, cases 0--8
passed, but case 9 (`bad_partial_prefix`) unexpectedly reached its bad
terminal and fired the validation guard. This did **not** expose a production
prefix-check failure. The formal design report classified validation-only
`inject_bad` as an undriven wire: Questa 2023.2 did not make the signal
temporally constant from the `(* anyconst *)` attribute alone. A trace could
therefore use `inject_bad=0` while beat zero was accepted (saving legal
`WSTRB=2'b01`), then change it to one when the late AW was offered. The
production `a_current_w_prefix_live_aw` correctly accepted the saved legal
lane, while the harness incorrectly interpreted the later selector value as
evidence that an illegal lane had been saved. Separate cover targets cannot
rule this out because each target has its own trace.

The harness now states `s_inject_bad_constant` explicitly with `$stable`,
matching the repository's existing workaround for stable arbitrary domains.
No production source changed for this diagnosis. Focused rerun
`20260903_c6_manager_offer_mutations_v5_manager_offer_mutations` passed cases
9--11. The coherent artifact
`20260903_c6_manager_offer_mutations_v6_manager_offer_mutations` then passed
all 12 cases from one frozen source. All four legal association shapes reach
their terminal with no fire or inconclusive result. For all eight negative
cases, bad setup and legal escape are covered, the bad terminal is
uncoverable, the guard is proven, and compilation is clean. Cases 10 and 11
were included because they also carry the selector choice across a saved W
history boundary. This resolves the only failed v4 mechanism and completes
the deterministic Manager validation gate.

#### AWREADY-independent output pair checks

The output-only zero-state strengthening is now implemented in
`axi_pair_tracker.sv`; Manager-input forms remain unchanged and continue to
defer universal traffic constraints to the deterministic Manager contract.
The accepted-order selectors still select only `aw_hsk` or completed W
occurrences. Broadening `select_aw` itself to `AWVALID` would mix an
unaccepted offer into handshake-derived skew/rank state and is unsound.

The output assertions instead partition the existing pair state by skew:

- positive skew uses `pending_aw && rank==0`. It now checks both an already
  accepted prefix and the current `WVALID` beat against saved AW geometry;
- zero skew directly associates the live AW offer with the current/partial W
  packet before `AWREADY`. A saved-prefix comparison is enabled only for the
  allowed `!selected` ghost valuation, because the one-bit strobe sample
  freezes after another selected W/completed pair; the current live beat does
  not need that guard;
- negative skew uses `pending_w && rank==0` and compares saved completed-W
  length/strobe information with live AW metadata on `AWVALID`, without
  predicting or requiring the AW handshake.

The two AW-first WLAST properties also enforce `current_w_beat <= AWLEN`
continuously and exact `WLAST` on each offered beat. Zero-based current-beat
checks use `current_w_beat == AWLEN`; completed-packet counts retain
`watched_w_beats == AWLEN+1`. No register, queue, or checker instance was
added. Source-only protocol and full gates
`work/build/20260903_c6_pair_awready_low_compile_xbar_{protocol,full}` both
passed with zero vlog errors/warnings and the two expected suppressed
diagnostics. The broadened pair-tracker SHA-256 is
`71e62b4285d255e3f5a9b77739934f06b75b76f882aa332075934d1168c54eac`.

Directed verifier artifact
`20260903_c6_pair_awready_low_transaction_mutations` independently exercises
the new output semantics. Legal case 20 holds both AW and W stalled at count
parity and reaches its sequence with no fire or inconclusive target. Cases
21--25 respectively inject a stalled-parity bad strobe, stalled-parity missing
WLAST, bad accepted partial-W prefix exposed by a stalled late AW, wrong saved
completed-W length exposed by a stalled late AW, and bad saved completed-W
strobe exposed by a stalled late AW. Every negative sequence is reached and
fires its intended smart-checker property with no inconclusive result;
the handshake-only oracle does not detect these offer-only faults, which is
the point of this gate. Cases 24 and 25 explicitly select the completed W
occurrence before the late AW; the other parity cases require no selector.
Waveform inspection confirms the READY-independent boundary rather than only
the runner classification: cases 20--22 hold both `AWREADY` and `WREADY` low
at the live pair, while cases 23--25 expose saved W history with
`AWVALID=1` and `AWREADY=0`. The only fires are
`x_wstrb_live_select_aw` in cases 21 and 23,
`x_w_last_offer_select_aw` in case 22,
`x_w_last_exact_after_w` in case 24, and `x_wstrb_after_w` in case 25.
The legal case fires nothing, all six sequence covers close, and there are no
collateral fires. Cases 24 and 25 also cover both `c_select_b` and
`c_w_before_aw`.

The first frozen-source proof reruns against this corrected environment are:

- `20260903_c6_wstrb_live_awready_low_current_xbar_zipcpu_axixbar_protocol_d1_ft0`;
- `20260903_c6_wlast_offer_exact_awready_low_current_xbar_zipcpu_axixbar_protocol_d1_ft0`;
- `20260903_c6_output0_wpacket_post_env_current_xbar_zipcpu_axixbar_protocol_d1_ft0`;
- `20260903_c6_wstrb_directionals_post_env_current_xbar_zipcpu_axixbar_protocol_d1_ft0`.

They used the unbounded N1/O7 protocol profile, no promoted assertions, 16
engines, and five minutes each. Formal elaboration directly measured 172
assertion checkers and 290 assumptions, with no blackboxes. Every one of the
19 targets was nonvacuous and none fired, but all were inconclusive. The four
live-WSTRB targets reached radius 19; the six WLAST targets reached radii
27--31; output 0 packet length reached radius 45; and the eight directional
WSTRB targets reached radii 19--21. The corrected contract therefore removes
the prior counterexamples, but brute-force reruns do not close these cones.
No result from these four artifacts is promoted.

#### Arbitrary output-packet result

The DUT-output `c_profile_w_packet_len` check now selects an arbitrary packet
start and retains one `watching_packet` bit until its WLAST handshake. Its
antecedent remains offer-level (`WVALID`, not `WREADY`), and its free selector
makes the assertion universal over possible output packets. Manager-input
instances deliberately retain the unconditional deterministic packet
assumption; a selector-based assumption could evade an unselected bad input
packet and would be unsound.

In `20260903_c6_selected_output_packet_d1_*`, both output instances were
nonvacuous at radius 10 and neither fired. Output 1 proved with engine 12 at
271 seconds. Output 0 remained inconclusive at radius 49 after 300 seconds.
The run used 15.8 GB total peak memory with 16 engines. This closes one of the
two packet-bound obligations. The focused output-0 engine-12 retry
`20260903_c6_selected_output_packet_m0_engine12_d1_*` was also nonvacuous and
had no fire, but remained inconclusive at radius 32 after 600 seconds (2.0 GB
total peak, 0.4 GB engine peak). The engine which closed output 1 therefore
did not transfer to output 0. Do not repeat either this retry or the old
unselected packet cone unchanged.

#### Selected-packet architecture clarification

The intended abstraction is to select an arbitrary occurrence already on an
arbitrary DUT input, not to inject a second special request alongside normal
traffic. A free selector constrained only when it is asserted is universal:
the proof must hold for every legal choice of occurrence, while a separate
cover confirms that selection is reachable. Stable arbitrary source, ID,
beat, lane, and payload-bit domains avoid copies per source, ID, beat, or
lane.

For reads, the protocol tracker already implements this architecture. It
selects one AR handshake in an arbitrary ID domain, saves ARLEN, and records
the number of older same-ID requests as a rank. Other RIDs may interleave;
only a same-ID RLAST removes an older rank. At rank zero, the selected beat
counter enforces `RLAST == (beat == ARLEN)`. R has no byte-strobe signal, so
read lane legality is not a protocol check; the role separately selects one
arbitrary R payload bit and beat for end-to-end preservation.

Writes need a two-sided refinement because AXI4 W carries no ID and may
legally precede AW. The generic pair tracker may therefore select either an
AW occurrence or a completed W packet. Its signed AW/completed-W skew and
relative rank find the opposite side in global W order. Exact WLAST uses the
selected AWLEN, while independent arbitrary beat and byte-lane domains prove
all WSTRB lanes using one sampled strobe bit. A single packet-wide `matched`
bit would still need separate early/late-LAST accounting and would have to
accumulate every beat through stalls; the arbitrary beat/lane formulation is
the smaller equivalent safety proof.

More precisely, the proposed scheme contains two separable ideas. Selecting
an arbitrary existing occurrence and identifying its response/data packet by
ordinal rank is the right association proof and is already the core of these
trackers. Delaying the content verdict in a sticky `matched` accumulator until
RLAST/WLAST is not preferable for unbounded safety: the environment can hold
READY low, or a faulty source can omit LAST, so that verdict edge need never
occur. The authoritative checks must reject a bad `RVALID`/`WVALID` offer as
soon as the association metadata is known. A sticky match bit can still be a
useful derived debug summary or cover, but it should not be the only assertion.
For W-before-AW, it also cannot validate earlier strobes against unknown AW
geometry without either buffering them or using the present two-sided
prophetic selection and arbitrary beat/lane sample.

The current role-level W tracker has not yet fully adopted that refinement.
Because its selection begins at AW, it retains bounded input/output W-ahead
payload-bit queues to recover legal W-before-AW traffic. The next role-state
reduction is to align the already-exported two-sided endpoint pair selectors,
ranks, captured AW, and arbitrary W beat across the selected route. The role
should then retain only the minimum presence/match payload state needed when
the two observed beats are not simultaneous. A plain outstanding total is
not a substitute for rank: reads and B are ordered per ID, while W packets
are ordered globally.

A read-only audit confirms that this can remove the role-local payload queues,
but it is not a sound drop-in wiring change. The role currently selects its AW
with the write/B tracker, while each endpoint pair tracker makes an independent
AW-or-completed-W choice. `view.wr_w` belongs to the role-selected transaction
only after those choices are deliberately aligned. For an AW-first occurrence,
the input pair must use `pair_select_aw` on the role selection edge. For a
W-first occurrence, it must already be `pair_pending_w` at rank zero when that
AW is selected. The selected output needs the same two cases on the routed AW
edge. The input and selected-output pair trackers must also share the role's
arbitrary beat index. These restrictions are on FVIP nondeterminism only; they
must not assume any DUT payload or routing result.

With that alignment, the role can compare the two sticky captured `wr_w`
payloads once the corresponding pairs complete, while retaining an ordering
check that rejects an output W occurrence before its input occurrence is
available. The current endpoint capture already handles AW-first, W-first,
simultaneous AW/WLAST, and a selected beat earlier than WLAST. Rank/skew alone
cannot recover an earlier payload if the pair choices are not aligned, so
removing the queues before this selector ownership change would be unsound.

This forwarding lemma need not assume any of the nine open output packet or
WSTRB assertions. Its independently closed inputs can be limited to basic
AW/W handshake and payload stability; the input and output
`a_tracker_pending_aw_rank` and `a_tracker_pending_w_rank` facts; the input
Manager's configured skew contract and the proved output skew bounds; output
`a_pair_completed_exact` and `a_tracker_after_w_capture`; and the role
stream's independently proved `a_no_overflow`, `a_no_phantom`,
`a_tracker_pending_rank`, and `a_selected_integrity_class1` write-route fact.
The public
`pair_aw`, `wr_w`, and `wr_beat_sampled` registers have direct capture logic,
but no separately named full-payload capture/freeze proof yet. Add and prove
zero-state endpoint-local bridge assertions for those transitions before
using the public payload snapshots compositionally; do not turn the bridge
into an assumption. Neither B-credit/write-outstanding facts nor the
cross-port lifecycle helper are logically required for selected W
forwarding.

The input Manager's universal WLAST and WSTRB environment contracts are
needed only when the forwarding result is used to derive output packet length
or strobe legality; they are not needed merely to prove bit-for-bit selected
W forwarding. In particular, the lemma must not promote output
`c_profile_w_packet_len`, any directional output WSTRB property, the unproved
canonical `a_pair_completed_wstrb`, or one of the selected role W properties
it is intended to prove. With those exclusions the dependency is acyclic:
route/pair bookkeeping plus independently proved public-observer capture
implies selected forwarding, which then proves the role W properties.

There is a directionality caveat if this lemma is later used to close the
open output protocol properties. An input-anchored arbitrary transaction
proves that every selected input is forwarded correctly, but by itself does
not quantify over a fabricated or otherwise unmatched output W occurrence.
That use needs either an arbitrary output-pair selector matched back to the
input pair, or a separately proved reverse/no-phantom W correspondence fact.
The selected output beat and W-first packet must remain eligible in that
reverse selection. Once that surjectivity fact is independent, the same
forwarding relation may feed the output packet/WSTRB proofs without a cycle;
without it, the aligned-pair refactor closes only the input-selected role W
obligations. Because it relates ports, this remains a generic cross-interface
role/composition lemma stated over public view state, not a single-port AXI
protocol invariant.

The exact role-local payload-state opportunity is
`2*MAX_W_AHEAD + 4*MAX_OUTPUT_W_AHEAD + 10` bits: one sampled/data bit per
input W-ahead slot, one pair per slot at each of two outputs, six rolling
current sample/data bits, and four selected input/output sample/data bits. At
the depth-two profile (`MAX_W_AHEAD=4`, `MAX_OUTPUT_W_AHEAD=2`) that is 26
bits, of which the bounded queues account for 16. Reusing the selected output
pair's pending/completed/rank may save another
`2 + $clog2(MAX_OUTPUT_AW_AHEAD+1)` bits, but that should be a second step after
the payload replacement proves. No new sequential role state is required in
principle because the full pair payload and association state are already
exported.

Before deleting state, require nonvacuous covers for AW-first, W-first, and
same-edge pairing on both routes, plus a sampled-beat cover. This guards the
prophetic W-first selector alignment from silently excluding a legal history.
The smallest implementation sequence is one source/route experiment, then the
two-route generalization; no role source was changed during this audit.

#### Role response offer-level audit

A subsequent read-only audit found that both open role-B production checks
are currently gated by `selected_s_b`, which includes the input B handshake.
Thus an incorrect input BVALID payload can remain stalled under `BREADY==0`
forever without triggering the role assertion. This is the same distinction
as the protocol W fix: handshakes mutate association state, but VALID must
trigger the safety comparison. The prior source-1 local-error-B proof remains
valid only for the historical handshake-gated property and must be reproved
after strengthening.

The correction needs no new sequential state. Reuse the selected input
endpoint's existing `wr_rsp_visible` predicate, derive matching output BVALID
at `m_b_rank==0`, and retain the current B handshakes only for rank mutation
and the existing one-bit payload capture. First prove a state-free
`m_b_pending -> m_protocol_outstanding > m_b_rank` bookkeeping lemma and a
payload-independent mapped-B occurrence lemma, then compose the arbitrary
payload-bit equality. Local DECERR can be checked directly whenever the
selected input response is visible. Stalled mapped/error covers must keep
`BREADY==0` to demonstrate that the stronger antecedents are genuinely
offer-level. None of this should depend on the four open role-W properties.

The audit also found a public-observer bug in `axi_fvip.sv`:
`wr_rsp_complete` and the `wr_b` capture use selected pending/rank plus a raw
B handshake, but omit matching BID and selected-write-data eligibility. A
different-ID or early B can therefore pulse or overwrite that public selected
response view even though the write tracker's internal completion predicate
is correct. Before composing role response proofs from that view, key both to
the already-correct internal `rsp_visible && b_hsk` predicate and prove the
capture/freeze transition. This is a public FVIP-state repair, not a DUT or
implementation-specific assumption. No source was changed during this audit.

The read response has the analogous role gap. All three current role-read
checks use input `s_r_hsk`, so their existing mapped-data, mapped-completion,
and local-error closures cover accepted beats only. The endpoint's
`rd_rsp_visible` already identifies the selected rank-zero RID on RVALID
without RREADY. Passing that public predicate into the role, and deriving a
matching output RVALID at the existing `m_rsp_rank/m_rsp_beat`, permits live
comparison; the existing one-bit `m_beat_data` continues to cover an output
beat accepted earlier. Add a payload-independent selected-beat occurrence
lemma before composing the arbitrary-bit equality. No new response state is
needed, but all three stronger role-read properties require reproof.

`rd_rsp_complete` and `rd_r` have the same public-view matching omission as
the B view: their capture predicates use a raw R handshake without requiring
the selected RID. Key them to the internal `rsp_visible` predicate (plus
RLAST or the selected beat, respectively). Keep `rd_r` handshake-captured;
the offer-level role assertion must compare the live source payload so the
repair does not reintroduce READY dependence. The admissible proof chain uses
only already-closed endpoint read facts and route/read-class role facts, never
bounded progress or any write property.

The shared request-route tracker also has a DUT-output offer gap. Its proven
`a_no_phantom` and class-specific integrity properties currently trigger on
the filtered output AW/AR handshake, so a fabricated or corrupt output VALID
can remain hidden under downstream READY low. The zero-state fix is to pass
the same filtered input and output VALID bits into the one existing shared
stream tracker. Retain handshake no-phantom--only a simultaneous input
handshake may authorize an output handshake--and add offer no-phantom as
`m_valid -> occupancy != 0 || (ALLOW_BYPASS && s_valid)`. For payload, compare
an accepted rank-zero selection to the stored arbitrary bit, or an empty-queue
live fall-through directly to the live input bit. This adds two combinational
inputs, not a selector, counter, FF, or per-source instance. Do not broaden
input selection from handshake to VALID; the explicit live-bypass arm covers
legal pre-handshake propagation while accepted-order rank retains its current
meaning.

The bounded READY profile plus channel stability eventually exposes these
offers to the old handshake checks, but it does not establish unbounded safety.
After strengthening, the historical route integrity closures require reproof;
the handshake no-phantom/no-overflow and pending-rank results remain valid
dependencies. Missing output VALID remains role liveness, owned by the
separate bounded-progress property.

#### Final strict-B representation status

All prefix/suffix count-difference decompositions above are now superseded by
a state-neutral representation at `MAX_OUTSTANDING > 1`: the existing watched
count register stores completed same-ID B credit, while semantic outstanding
is derived as completed credit plus the popcount of the existing unmatched-AW
tag FIFO. No second per-ID counter was added. The direct depth-two/depth-four
proof batch completed clean/nonvacuous but inconclusive, as recorded in the
strict-timing section above. The finalized selected-occurrence and count/rank
updates consume B only when completed credit existed in the sampled prestate.
Raw early B handshakes report the protocol violation without corrupting
observer state. This is identical on legal traces and also handles the
same-edge W-completion/B case rigorously.

The first direct proof attempt with completed-credit `count_state` but the old
all-outstanding `b_rank` is
`20260903_c6_strict_credit_state_direct_d{2,4}_*`. At each depth the two
`a_tracker_pending_data_state` and two nested selected-tag properties proved;
the other twelve credit/rank, strict-B, selected-B, and no-orphan targets were
clean and nonvacuous but inconclusive after 300 seconds. Depth two reached a
minimum/average radius of 27/28.67 and depth four 25/25.33; each run used
12.9 GB. Do not repeat this representation unchanged: deriving completed
credit removed one cone, but relating it to a rank initialized from all
unpaired predecessors retained the hard prefix-popcount induction.

The final successor also repurposes the existing `b_rank`, with no
new state. On Manager inputs it counts only completed same-ID predecessors.
It initializes from completed credit, increments when a watched predecessor's
W burst completes, and decrements only when a B consumes pre-existing credit.
Global AXI4 W ordering guarantees that by the time the selected write's W
burst completes, every predecessor is in this completed rank. Thus the public
`rank == 0` response-head meaning is unchanged on legal traces, while the
intended invariants become local recurrences: pending-W implies
`completed_credit == b_rank`, and completed selected W implies
`completed_credit > b_rank`. The role only consumes the public rank through
`rank == 0`; no role logic depends on its magnitude.

#### Output write-capacity offer and cap-profile experiments

The DUT-output transaction FVIP temporarily contained the zero-state
experimental helper `a_write_offer_has_capacity`. It required an offered AW
to have local capacity unless a B actually handshook on the same edge; the
original handshake-level `x_write_outstanding_bound` remained unchanged. The
helper was only present on DUT-Manager outputs, so it did not strengthen the
external Manager environment contract.

The standalone protocol run
`20260903_c6_output_write_offer_capacity_standalone_current_xbar_zipcpu_axixbar_protocol_d2_ft0`
made no assertion-to-assumption conversions. Both output helpers were clean
and nonvacuous at radius 10, but both remained inconclusive at radius 67 after
300 seconds. The two capacity-boundary covers also remained inconclusive at
radius 61. The run used 15.1 GB total peak memory with 16 engines, with a
1.4 GB maximum per-engine peak. Because the helper did not prove
independently, it was not composed into the original bounds. Do not repeat
this offer-level decomposition unchanged. After the successful conservation
composition below, both the failed offer helper and its boundary cover were
removed from production source; this paragraph records only the experiment.

The companion full-level elaboration/smoke artifact is
`20260903_c6_output_write_offer_capacity_full_elab_current_xbar_zipcpu_axixbar_full_d2_ft0`.
It elaborated the role hierarchy with zero vlog errors or warnings and no
blackboxes; the ten expected third-party frontend warnings remained. Both
offer assertions were nonvacuous at radius 10 and clean but inconclusive at
radii 51 and 53 after 60 seconds. It used 6.4 GB total peak memory.

The default output capacity of seven comes from the ZIPCPU `axixbar`
`LGMAXBURST=3` implementation profile, which admits at most seven requests on
a granted Manager-facing port. Port-level conservation additionally suggests
the wrapper-specific profile `min(2*MAX_OUTSTANDING, 7)`, but that topology
formula must not be embedded in the generic endpoint FVIP. Its depth-one
cap-two audit,
`20260903_c6_output_write_bound_cap2_d1_current_xbar_zipcpu_axixbar_protocol_d2_ft0`,
targeted the two original output bounds and both boundary covers with no new
helper or promoted fact. The bounds were nonvacuous at radius 10 and clean
but inconclusive at radii 50 and 52; the covers were inconclusive at radii 48
and 54. No target fired and no boundary trace was found. The run reached the
300-second timeout with 13.5 GB total peak memory and a 1.2 GB maximum
per-engine peak. This is no material improvement over the cap-seven radii,
so at that checkpoint defaults remained unchanged pending an independently
proved cross-port lifecycle-conservation lemma. The next subsection records
that later proof and supersedes this experimental conclusion.

#### Closed output write-capacity bounds by global conservation

The independently proved replacement is the zero-FF aggregate helper
`a_xbar_global_write_lifecycle_conservation`:

```systemverilog
m0_global_wr + m1_global_wr <= s0_global_wr + s1_global_wr
```

The public endpoint view now exports a distinct `global_wr_outstanding`
signal directly from the transaction FVIP's all-ID lifecycle counter. Do not
substitute the pre-existing `view.wr_outstanding`: that signal belongs to the
arbitrary selected-ID tracker. The aggregate explicitly widens both sums, so
the helper adds only combinational wiring and no sequential state.

This is not a generic single-port AXI protocol rule. It is a generic xbar
composition invariant, stated only over ports and public FVIP observer state,
and is available in both protocol and full elaborations as a proof helper.
Every forwarded output AW has already consumed an input credit; a mapped
output B is consumed no later than its returned input B. An unmapped local AW
instead creates input-only slack until its local DECERR B consumes that same
credit. Same-edge AW/B events preserve the corresponding observer count.
These facts cover buffered forwarding, simultaneous mutations, and the local
error path without referring to DUT-internal signals. Keep the helper as an
assertion and promote it only after its standalone proof; treating it as an
unproved protocol assumption would be unsound.

Standalone artifact
`20260903_c6_global_wr_conservation_standalone_current_xbar_zipcpu_axixbar_protocol_d2_ft0`
used the unbounded O7/N1 protocol profile and no assertion conversions. The
conservation helper proved with engine 12 at 95 seconds and its vacuity check
passed at radius 2. The nonzero-forwarding and local-DECERR lifecycle covers
both covered at radius 12. The same-endpoint input and output simultaneous
AW/B covers were proven unreachable in this depth-one profile; in particular,
the input offer-level N1 contract cannot refill its sole credit on the same
edge as B. This does not remove simultaneous-update behavior from the counter
definition, but a deeper profile is needed for a positive same-endpoint
mutation witness. The job used 13.5 GB total peak memory and a 1.0 GB maximum
per-engine peak.

Composition artifact
`20260903_c6_global_wr_conservation_composed_current_xbar_zipcpu_axixbar_protocol_d2_ft0`
converted exactly that one proven aggregate assertion. Both original DUT
output `x_write_outstanding_bound` assertions proved at 14 seconds and their
antecedents were nonvacuous at radius 10 by 15 seconds. The report lists the
conservation assertion as the sole promoted proof fact for each target; since
both targets proved, Questa reports no residual proof radius. The run used
6.0 GB total peak memory and a 0.4 GB maximum per-engine peak. This closes the
two remaining output write-outstanding obligations without changing the O7
profile and without adding state.

The identical one-fact composition produced green targets at two credits per
input, but its first interpretation exposed a proof-chain error: the N1
standalone theorem is a different parameterized instance and could not
justify promoting the N2 assertion. The exact N2 standalone proof below was
therefore required before reclassifying these results as a valid closure.
`20260903_c6_global_wr_conservation_composed_n2_current_xbar_zipcpu_axixbar_protocol_d2_ft0`
used O7, output W-ahead two, the 705/265/880 timing profile, and the post-offer-
cleanup source. It converted exactly
`i_xbar_fvip.a_xbar_global_write_lifecycle_conservation`; the formal report
lists that as the sole promoted fact for each output target. Output 1 proved
at 13 seconds and output 0 at 14 seconds. Both antecedents were nonvacuous at
radius 10, and no residual proof radius is reported for the proven targets.
The 14-second run used 6.8 GB total peak memory and a 0.7 GB maximum
per-engine peak.

The correction run
`20260903_c6_global_wr_conservation_standalone_n2_current_xbar_zipcpu_axixbar_protocol_d2_ft0`
targeted the exact N2 conservation assertion with no conversions, together
with nonzero, local-error, and simultaneous-mutation covers. The assertion's
vacuity check passed at radius 2 and engine 12 proved it at 146 seconds. All
four covers--nonzero forwarding, local DECERR, same-input AW/B, and
same-output AW/B--covered at radius 12 by 16 seconds. The job completed at 147
seconds with 8.6 GB total peak memory and a 0.9 GB maximum per-engine peak.
This independently proved exact-parameter instance validates the N2
composition above; the audit correction and the final two-step proof chain are
both retained here deliberately.

The N2 artifact captured the following SHA-256 source digests, unchanged from
the pre-launch audit: `bf47e44c43736c44d004ab07cd5ca9145a5c83e285303328e5f205b2951d531c`
for `axi_fvip_txn_view_if.sv`,
`c3540738e9f6b6bd9fda8155ce4f945c9da79beb4c94a82a971757b0149812e1`
for `axi_fvip.sv`,
`ace4d59f098c5312b1dd6f64eabcca99c7e5c5ce71b8e8a0b6c57f1d59d00a2c`
for `axi_transaction_fvip.sv`, and
`7fb91a6e0a464ab8b29651f5c0d5d3bc3275d2d0026bcd3f182a0925404298d5`
for `axi_xbar_fvip.sv`. The concurrently active dependency hashes were
`84949ed5e6e32d6d3355328b9ae8fde353bb4d25126ecd4be96dd7b9fbc4ab6e`
for `axi_pair_tracker.sv`,
`2a56db4bf46c6f459416747362bc8ec0d043acb82024996df7395e17d596fccc`
for `axi_write_tracker.sv`, and
`6ca2a70e7a42da25316e8a517d38b751ac5488680250188bd5689c515f711a4f`
for `pkg_axi_fvip.sv`. No source changed while this proof compiled or ran.

The present-state inequality is sufficient at N1 and N2 because total input
credit is at most two or four, strictly below O7. At N4 the input sum can be
eight. In the exact residual state `m0_global_wr==7`,
`m1_global_wr==0`, and total input credit eight, the conservation assertion is
true. An eighth output-0 AW acceptance without B violates the original O7
target, but the saturating endpoint observer remains at seven, so the same
present-state assertion is still true on the next edge. Therefore no O4 run
was launched: conservation alone cannot establish the O7 boundary. A
depth-four closure needs an independently proved ZIPCPU seven-credit capacity
theorem or an equivalent unsaturated capacity-attempt/transition property;
that extra fact is necessarily stronger than topology conservation. Do not
silently infer it from the N1/N2 proofs.

This is a semantic limit, not merely a solver limit. A legal abstract 2x2
xbar may accept four destination-0 writes at each input, prefix the two source
domains in the output IDs, and forward all eight to output 0 before any B.
Every AXI port obeys protocol, both input N4 bounds and end-to-end routing hold,
and aggregate lifecycle conservation holds with equality. Therefore no
implementation-independent port/FVIP invariant can derive seven from those
contracts: it would reject a correct interleaving xbar. Local-error or
other-route credit cannot help universally because the environment may choose
all eight writes mapped to the same output.

The generic xbar output profile implied by conservation is `2*N`, hence eight
at N4. That bound can remain part of the reusable protocol composition. The
stricter seven-credit result comes from ZIPCPU `LGMAXBURST=3` plus its
grant/resource policy and should be retained, if required, as a separately
named optional ZIPCPU resource-profile obligation. An observable single-source
output-lock lemma could prove it without DUT-internal references, but it would
still encode ZIPCPU arbitration behavior and is therefore disallowed as a
generic production invariant under the implementation-independence rule. No
source or profile was changed during this audit.

After removing the failed offer experiment, final source-only compile gates
`work/build/20260903_c6_global_wr_conservation_final_compile_xbar_{protocol,full}`
both passed with zero vlog errors or warnings and the two deliberately
suppressed diagnostics. `git diff --check` also passes for the touched source
and handoff files.

### 2026-09-03: READY-independent role offers

The role audit found three distinct handshake-only holes. The public endpoint
view could mark/capture a selected R or B using rank alone without checking
the live RID/BID; the routed AW/AR integrity properties waited for the output
handshake; and the mapped/local response checks waited for source and output
response handshakes. An environment can keep READY low forever, so none of
those handshakes is an acceptable safety verdict point.

The public view now derives completion and capture from the generic
transaction tracker's existing `rsp_visible` predicate. This adds the missing
matching ID test on R, and matching ID plus completed-W eligibility on B,
without adding state. The selected source's public `rd_rsp_visible` and
`wr_rsp_visible` signals are threaded into the role trackers. Source response
safety is therefore triggered by the correct RVALID/BVALID offer while all
rank, beat, completion, and payload capture mutations remain handshake-only.

The output response trackers now split a matching-ID offer from its accepted
handshake. The read tracker compares the selected live R offer or a previously
captured beat; the write tracker does the same for B. Captured data has
priority over an unrelated later offer. Both trackers require pre-existing
output request credit. The B path additionally requires the selected output W
packet to have completed in prestate, so a same-cycle WLAST cannot authorize
or capture B. Route-edge R/B bypasses were removed: under the protocol
contract a response cannot belong to an address accepted on that same edge.
Older same-ID accepted responses may still decrement a nonzero rank.

The request-stream tracker gained only combinational `s_valid`/`m_valid`
inputs. Its existing selection, occupancy, rank, payload capture, completion,
and progress state remain handshake-driven. A new `a_no_phantom_offer`
assertion rejects a stalled output AW/AR with neither accepted input credit nor
a matching live fall-through input. The existing class-0/class-1 routed
payload properties now check both a rank-zero stored occurrence and an empty-
queue live fall-through offer; the stored captured bit has priority. This
covers wrong destination, lower ID, source prefix, and payload before READY
without encoding ZIPCPU internals.

Two zero-state response bookkeeping helpers and two response-occurrence
helpers were added: read pending/rank credit, B pending/rank credit, mapped R
occurrence, and mapped B occurrence. Six stalled-offer covers distinguish
live versus previously sampled mapped R/B and local-error R/B. The stream
tracker also has stalled selected and live-bypass offer covers. Source-only
gates `work/build/20260903_c6_role_offer_v2_compile_xbar_{protocol,full}` pass
with zero vlog errors/warnings and the two expected suppressed diagnostics;
`git diff --check` is clean. The two focused formal models directly measure
193 assertions and 298 assumptions, with no blackboxes.

The completed frozen-source proof artifacts are
`20260903_c6_role_offer_bookkeeping_current_xbar_zipcpu_axixbar_full_d1_ft0`
and
`20260903_c6_role_response_offer_production_current_xbar_zipcpu_axixbar_full_d1_ft0`.
Both used the unbounded N1/O7 full profile, 16 engines, and five minutes; all
12 targets were nonvacuous and none fired. The first proved three of seven:
read response-credit/rank at 30 seconds, route offer no-phantom at 221
seconds, and class-0 route integrity at 232 seconds. Its class-1 route
integrity, mapped-R occurrence, B credit/rank, and mapped-B occurrence targets
were clean but inconclusive at timeout, with minimum/average proof radius
35/41.2. The second proved mapped-read completion at 210 seconds, local-error
B at 211 seconds, and local-error read response at 237 seconds. Mapped-read
data and mapped B were clean but inconclusive at radius 35. Peak aggregate
memory was respectively 18.5 GB and 16.6 GB. These six proofs close five
strengthened/new role production properties and one new helper in that
compiled model. The corrected endpoint-view mutation gate below validates
the public visibility/capture boundary, so all six proofs are promotable. No
inconclusive result is promoted. Focused compositional successors are still
needed for the six residual targets from these batches.

Directed role-response cases 26--36 all validate the intended tracker-local
READY-independent semantics. Cases 26 and 32 are legal stalled mapped R/B
offers and fire nothing. Cases 27--30 isolate mapped R data, mapped R
completion, local-error RRESP, and local-error RDATA; cases 33--35 isolate
mapped B, same-edge-WLAST/B occurrence, and local-error BRESP. Case 31 proves
both wrong-RID isolation guards before firing the deliberately missing
selected occurrence; case 36 does the same for wrong BID. Every intended
READY-low/sequence cover closes, with zero inconclusive or collateral fires.

The separate public endpoint-view cases are intentionally a stricter boundary
gate. The first case-37/38 attempts are invalid negative evidence. Their
validation-only references used `i_endpoint.u_txn...` rather than
`i_endpoint.g_txn.u_txn...`; the compile log's `parser-94` diagnostics show
that the watch-ID/selector constraints and internal probes were not
translated. Consequently the arbitrary tracker could select the second-ID
request and legitimately capture the response which the harness called
"wrong ID." Artifact
`20260903_c6_public_response_view_diag_transaction_mutations` is retained as
what did not work, not as evidence of an interface alias. Corrected diagnostic
artifact `20260903_c6_public_response_view_diag_v2_transaction_mutations`
uses `i_endpoint.g_txn.u_txn...` throughout. Both 37 and 38 then pass with no
fire or inconclusive result: all driven-ID, not-watched, internal-visible,
public-visible, completion, and capture guards prove, while the wrong-ID
handshake and terminal sequence covers reach. Compilation has zero warning or
error. This clears the representation. Final coherent artifact
`20260903_c6_public_response_view_final_transaction_mutations` reruns all
three cases from one frozen source. Cases 37/38 again prove every ID/internal/
public/capture guard with no fire; case 39 produces exactly the three intended
early-B protocol fires and proves both public-view guards. Every handshake
and terminal-sequence cover reaches, with no inconclusive result, compile
diagnostic, or blackbox. Validation TB and runner SHA-256 prefixes are
respectively
`45a37b1d68fa9564028003351c86c2eb5effc2c72fac4b977692876d539a0258`
and
`ef20331ff01124f22e6ada1c30e1e726620f15c0c48ef4f52c1b756bc2fef5fe`.
Final source-only gates
`work/build/20260903_c6_role_response_mutation_final_compile_xbar_{protocol,full}`
both pass with zero errors/warnings and two expected suppressed diagnostics.
They use the exact N1/O7/OAW7/OW1 profile. No production HDL, state,
assertion, or interface field changed during the validation diagnosis.

The frozen role source hashes for those gates are:

- `axi_fvip.sv`: `c03d8a52a30ecc7d355260a7fc47fc2c446d6c550be5f6827df47db3815d483c`;
- `xbar_stream_tracker.sv`: `24de1d9c20e07bb8cedc1da6405d1ffba55a7673b5f8af308895e3fadf6cf219`;
- `xbar_read_tracker.sv`: `506c4abb27c2dab3110ee98d11b54f9860dccb9737267ffa076257a82f7dbee5`;
- `xbar_write_tracker.sv`: `dc15335b0591e78219efb1f9ca6719d2c3feb7f44919e4e355e8d3e3b3bdaff7`;
- `axi_xbar_role_fvip.sv`: `4584f52e71f0b3a1eb75417a0c4388784e56422e926925b0db6ef6b82aa3a375`.

### 2026-09-03: active compositional closure and pair-state reduction

Three ten-minute, 16-engine role decompositions were launched on independent
frozen copies of the 193-assertion/298-assumption model.  They do not consume
the subsequently staged pair-summary source:

- `20260903_c6_role_route_class1_offer_composed_direct_xbar_zipcpu_axixbar_full_d1_ft0`
  targets class-1 routed-address integrity.  Its premises are only the
  independently proved route overflow, handshake no-phantom, offer
  no-phantom, and route pending-rank facts.
- `20260903_c6_role_read_occurrence_composed_direct_xbar_zipcpu_axixbar_full_d1_ft0`
  targets mapped-R occurrence.  Its acyclic premises are the proved route
  facts, read response rank/completion, both input no-orphan/read-rank/exact-
  RLAST facts, and both output read-outstanding bounds.
- `20260903_c6_role_b_rank_composed_direct_xbar_zipcpu_axixbar_full_d1_ft0`
  targets the selected-B credit/rank helper.  Its premises are the proved
  route facts, the exact standalone global write-lifecycle conservation fact,
  and all four independently proved output AW/W skew bounds.  It does not
  assume an open role W or B property.

All three vacuity phases passed (at radii 10, 14, and 12 respectively) before
their proof phases began.  The read-occurrence job subsequently proved
`a_selected_mapped_response_occurrence` with engine 12 at 278 seconds; it was
nonvacuous at radius 14, used exactly the 15 listed independently proved
facts, and reported no fired target or tool failure.  This closes the mapped-R
occurrence helper, not by itself a production row.  Its successor
`20260903_c6_role_read_data_composed_direct_xbar_zipcpu_axixbar_full_d1_ft0`
then targeted the mapped-R data production property with the occurrence
result added as the sixteenth acyclic premise.  The target was nonvacuous at
radius 14 and proved with engine 12 at 464 seconds.  Its formal report lists
exactly those 16 promoted, independently established facts, no target fired,
and there was no blackbox or tool failure.  This closes mapped-R data and
moves the production role ledger from 7/14 to **8/14**; at that checkpoint,
the remaining six were route class-1, mapped B, and the four W-forwarding
properties.  Route class-1 and B-rank both
completed cleanly and nonvacuously but remained inconclusive after 600
seconds, at proof radii 39 and 52 respectively.  They reported zero fires,
blackboxes, launch failures, or unexpected terminations, but neither is
promoted.  These same cones should not be repeated unchanged.

The generic pair tracker is also undergoing a proof-gated state reduction.
Its raw selected-AW snapshot currently costs 45 bits per endpoint
(`ADDR+LEN+SIZE+BURST`).  The exact information consumed by the W checks is
only a 9-bit `AWLEN+1` count, which represents 1--256 beats without a profile
assumption, and one bit recording whether the arbitrary watched byte lane is
legal.  Replacing the raw snapshot with these ten sufficient-statistic bits
would save 35 observer bits per endpoint, 140 bits across the four xbar
endpoints.

The first staged source, pair-tracker SHA-256
`64cb4ac3cbc90ea6b1c2791b8313d1fded08cde18bf74c4f7e148a95512445ba`,
keeps both representations and updates the summary on all three address
capture shapes: selected AW, selected completed-W joining a same-edge AW at
zero skew, and pending selected-W joining its rank-zero AW.  Source-only gates
`work/build/20260903_c6_pair_aw_summary_stage_compile_xbar_{protocol,full}`
passed with zero errors/warnings and the two expected suppressed diagnostics.
Focused proof
`20260903_c6_pair_aw_summary_equiv_stage_xbar_zipcpu_axixbar_protocol_d1_ft0`
ran against that frozen source.  Its model contains 176 assertion checkers
and 290 assumptions and has no blackboxes.  Both environment-input instances
proved at 57 and 65 seconds and all four targets were nonvacuous.  Both DUT-
output instances were clean but inconclusive at the five-minute timeout,
with proof radii 27--29.  This partial result is useful evidence but is not a
deletion gate; the raw fields remain.

Review found no capture, reset, or width defect, but identified an additional
audit needed before deletion: the proof must state directly that the old
saved-geometry WSTRB predicate equals
`strobe_bit ? saved_lane_legal : 1`.  Merely proving that the legality bit was
captured from the old geometry does not make the later use-site rewrite a
formal artifact.  The current audit-stage source therefore adds separate
sampled/current predicate equivalences, exact one-cycle capture lemmas for
all three shapes, and covers for each shape.  Its pair-tracker SHA-256 is
`cc0c96f9df0c61ea3307d6dfa75f3e8ec8ae56ed33636e07ee7b3b3f2b173a9e`.
Both source-only gates
`work/build/20260903_c6_pair_aw_summary_audit_compile_xbar_{protocol,full}`
pass with zero errors/warnings and two suppressed diagnostics.  Focused
artifact
`20260903_c6_pair_aw_summary_capture_audit_xbar_zipcpu_axixbar_protocol_d1_ft0`
targeted all 24 summary/capture assertions plus all 12 path covers.  Every
cover reached.  All 12 exact capture assertions proved on all four endpoints,
and all six equivalence/use assertions proved on the two environment-input
endpoints.  Only the three long-lived equivalence/use assertions on each DUT
output remained clean, nonvacuous, and inconclusive at the five-minute
timeout; none fired.  A validation-only standalone output-polarity pair-
observer proof was then launched against the same pair hash to remove the
DUT/xbar state cone while leaving AWLEN fully eight-bit and port events
symbolic.  At this historical checkpoint the raw fields deliberately
remained; the later reduced-source refinement proof below supersedes this
partial gate and authorizes their deletion.

The role-W state audit reached a compatible result.  The bounded duplicate
input/output payload queues are removable only after the role-selected AW is
aligned one-way with the existing source and selected-output endpoint pair
witnesses.  Nonnegative skew selects the pair's AW on the role-selection or
routed-AW edge; negative skew requires the pair already to hold the rank-zero
pending W occurrence.  Both endpoints share the role's arbitrary beat.  This
constrains only FVIP nondeterminism and must never be reversed into
`pair_select -> role_select`, which would weaken the independent protocol
witness.  The output also needs the exact selected routed-AW offer while
AWREADY is low and a prophetic `pair_select_w` case if the corresponding W
packet completes at zero skew before that AW is accepted.

No role payload queue was deleted at this checkpoint.  The public pair view
still had to publish every address capture shape (the then-current export
missed the same-edge selected-W/AW zero-skew join) and publish/freeze the
watched W beat as soon as it was captured, including seeding an already-
passed beat when an AW was selected during an in-progress W packet.  The
later public transition, invariant, and DUT-free artifacts now prove those
bridges.  Role-side one-way selector alignment and the parallel scalar shadow
proof are the remaining deletion gate.  Once they prove,
the first queue deletion saves
`2*MAX_W_AHEAD + 4*MAX_OUTPUT_W_AHEAD + 10` role-local bits, 26 bits in the
current N1/O7/OW1 profile, with further savings available by reusing the
selected output pair's pending/completed/rank state.

The first public-view repair is now staged.  `axi_fvip.sv` mirrors all three
accepted-AW capture transitions, including the previously omitted
`pair_select_w && AW-handshake && skew==0` join, and adds separate packed-live-
boundary capture assertions plus a post-capture freeze assertion.  It neither
captures an AWVALID-only offer nor changes pair order, and adds zero state.
Protocol/full source gates
`work/build/20260903_c6_public_pair_aw_capture_compile_xbar_{protocol,full}`
pass with zero errors/warnings and two expected suppressed diagnostics.  The
staged `axi_fvip.sv` SHA-256 is
`f7a09a58ed013937fbc405c70e560ef42f61f3fa055dc38e55073f57acdd5614`.
At this checkpoint focused bridge proof and directed capture validation were
still required; the later 40-transition, 20-invariant, and DUT-free public-
view artifacts below discharge them against the superseding source hash.

A stricter state audit found that reusing the existing full public `wr_w`
snapshot should itself be only an intermediate step.  At DATA32/USER1 the
current rolling full-W payload, selected full-W payload, and valid flag cost
77 bits per endpoint.  An independent arbitrary canonical-W payload-bit
selector can retain the protocol pair's independent beat and WSTRB-lane
domains while reducing the role export first to three scalar bits, then to a
single rolling/selected payload bit plus derived availability.  The safe
migration is shadow-first: prove scalar/full capture and freeze equivalence,
align only the ghost selectors, run scalar role assertions beside the queue
implementation, delete the role queues, then delete the full snapshots.  The
one-bit final form saves 76 bits per endpoint, 304 bits over the xbar, in
addition to the 140-bit AW-summary reduction.  No full-W snapshot has been
removed at this checkpoint.

That conservative scalar shadow is now staged, still beside the full path.
Each endpoint has an independent stable/range-constrained index over
`{WDATA,WSTRB,WLAST,WUSER}`, a rolling bit, a selected bit, and a selected-
valid bit.  The protocol pair's beat and WSTRB-lane selectors remain separate.
The full and scalar paths now both publish an already-passed watched beat when
an AW is selected at zero skew, publish the selected watched handshake before
WLAST, and retain the terminal W-first fallback.  The public live-W ownership
signals also include the zero-skew selection edge; they still do not call an
unaccepted stalled beat a stored snapshot.  Capture, scalar/full equivalence,
terminal exactness, and freeze assertions plus shape covers are present as
helper-only deletion gates.

Protocol/full source gates
`work/build/20260903_c6_public_pair_w_scalar_shadow_compile_xbar_{protocol,full}`
pass with zero errors/warnings and two expected suppressed diagnostics.  The
staged hashes are
`82f74a833756e4fc548c01959632318560a0b97bd2ffc23880fad852556b480a`
for `axi_fvip.sv` and
`c1dd234bbd93f81bfd13374710690b81b39af6c8f602bb02ba27f67fe41c022e`
for `axi_fvip_txn_view_if.sv`.  The shadow temporarily adds three sequential
bits per endpoint; neither the full endpoint snapshots nor any role queue is
removed until the equivalence and role-side parallel checks prove.

The independent pair-summary deletion gate is now green.  Standalone artifact
`work/runs/20260903_c6_pair_summary_primitives_cc0c96f9_v5_pair_summary_refinement`
contains no DUT, blackbox, or promoted protocol/role premise.  It proved all
11 targeted primitive assertions in two seconds and reached all six covers:
the three raw-AW captures, the same three summary captures, joint freeze,
arbitrary-bit lane factorization, exact position/terminal/completed-count
algebra, both lane-bit values, and the full-width INCR `AWLEN=255` case.  The
argument is acyclic: both representations independently sample the same live
AW on each possible entry and freeze over the same lifetime, after which the
state-free function and arithmetic identities justify every rewritten use.

The raw `{AWADDR,AWLEN,AWSIZE,AWBURST}` registers have therefore been removed
from `axi_pair_tracker.sv`; only the nine-bit beat count and one lane-legality
bit remain.  One review did catch a real pre-compile rewrite error: the DUT-
output offer-level terminal predicate initially used the width-limited
`current_w_beats`, which can wrap for an out-of-profile counter value.  It was
corrected to the proven zero-extended `current_w_beat + 1` comparison, while
the accepted-completion and Manager-input forms deliberately retain their old
width semantics.  Reduced pair hash
`6468122998a6a84a6033e2566184e57039e6e063beb0f13a4b65fac719794413`
passes
`work/build/20260903_c6_pair_aw_summary_reduced_compile_xbar_{protocol,full}`
with zero errors/warnings and two expected suppressed diagnostics.  This is a
real reduction of 35 sequential observer bits per endpoint, 140 across the
four xbar endpoints.  Exact post-deletion artifact
`work/runs/20260903_c6_pair_summary_reduced_64681229_v1_pair_summary_refinement`
then proved all 13 reduced-source assertions and reached all six covers with
zero compile warnings/errors and no blackbox.  Its harness hash is
`522efa086c5ebb99d99e03af476f461978cce98c04f98730426b18ed74aa5df3`.
The exact-use audit confirms that the corrected output-offer form is widened
equivalently, the Manager/accepted forms preserve their prior width behavior,
and every stored WSTRB use factors through the retained lane statistic.  The
140-bit deletion is therefore promoted.  Its behavioral backstop
`work/runs/20260903_c6_pair_summary_reduced_64681229_focus_transaction_mutations`
also passed all seven focused cases with zero compile warnings/errors or
inconclusive rows: legal controls 0/20 remained quiet; accepted WLAST/WSTRB
faults 4/5, stalled-live WSTRB/WLAST faults 21/22, and late-AW partial-prefix
fault 23 were detected by the intended checks.  Every sequence and helper
guard reached.  This mutation result supports, but is not substituted for,
the exact refinement proof above.  Follow-on artifact
`work/runs/20260903_c6_pair_summary_reduced_64681229_afterw_transaction_mutations`
also passes W-before-AW completed-length and completed-WSTRB cases 24/25:
each exact intended checker fires, with no inconclusive result or compile
warning/error and with both sequences reached.

All four fixed-domain retries of class-1/write-route integrity are now proved
and nonvacuous.  Artifacts
`work/runs/20260903_c6_role_route_class1_partition_s0_d0_xbar_zipcpu_axixbar_full_d1_ft0`
and
`work/runs/20260903_c6_role_route_class1_partition_s1_d1_xbar_zipcpu_axixbar_full_d1_ft0`
closed source0/destination0 in 237 seconds and source1/destination1 in 196
seconds.  Artifacts
`work/runs/20260903_c6_role_route_class1_partition_s0_d1_reduced_xbar_zipcpu_axixbar_full_d1_ft0`
and
`work/runs/20260903_c6_role_route_class1_partition_s1_d0_reduced_xbar_zipcpu_axixbar_full_d1_ft0`
closed the cross partitions in 176 and 167 seconds.  Each run used only the
same four independently proved route facts as the monolithic attempt, reached
the target nonvacuously at radius 10, and had no fire, blackbox, launch
failure, or unexpected termination.  The four fixed values exhaust both
arbitrary source and mapped-destination domains, so class-1 route integrity is
now a production closure and the role ledger moves from 8/14 to **9/14**.

The eight-case transaction mutation sweep that was already running against
the pre-deletion shadow completed at
`work/runs/20260903_c6_public_pair_w_scalar_shadow_transaction_mutations`.
The good and legal-stalled cases have no fires; wrong ordinary WSTRB, stalled
zero-skew WSTRB, stalled zero-skew WLAST, late-AW partial-prefix, late-AW
completed-length, and late-AW completed-WSTRB mutations are each detected by
the intended checker with no unexpected fire or inconclusive result.  Every
sequence, guard, and READY-low witness reached.  This validates the protocol
pair machinery but is not yet a proof of the new public scalar payload shadow.

Review of that public shadow found no RTL transition error, but did expose
missing proof coverage.  The source now includes a long-lived rolling-scalar
versus rolling-full-payload equivalence, exact public offer/completion bridge
assertions, separate selected-AW and pending-AW `WVALID && !WREADY` covers,
and a cover for each of the three completion disjuncts.  This matters because
stored availability must remain false until a handshake while the live offer
must still be visible to role safety checks.  Updated `axi_fvip.sv` hash
`4a6f2c29ceacb9c86333269505abe1fee1672d1b6620db5f215190f9170e16c0`
also exports direct scalar identity and completed-availability lemmas.  It
passes source gates
`work/build/20260903_c6_public_pair_w_export_compile_xbar_{protocol,full}`
with zero errors/warnings and two expected suppressed diagnostics.  Those
helper obligations are discharged by the two focused artifacts below;
endpoint snapshot deletion still waits for the role-side shadow proof.

The first focused public-boundary proof is green at
`work/runs/20260903_c6_public_pair_capture_visibility_reduced_xbar_zipcpu_axixbar_protocol_d1_ft0`.
With no promoted helper assertions, all 40 one-step AW/W capture, scalar
export, offer-visibility, and completion-identity assertions proved and were
nonvacuous; all 52 path covers reached.  The covers exhaust all four
endpoints, all three AW join shapes, AW-first prefix/live and W-first
prior/final samples, every completion disjunct, and both selected-AW and
pending-AW `WVALID && !WREADY` offers.  The proof completed in 31 seconds with
no blackbox, launch failure, unexpected termination, or invalid cover trace.
The five long-lived freeze/full-equivalence/completed-availability invariants
were proved separately at
`work/runs/20260903_c6_public_pair_freeze_equiv_reduced_xbar_zipcpu_axixbar_protocol_d1_ft0`.
All 20 elaborated instances (five invariants on each of four endpoints) proved
and were nonvacuous in 90 seconds, with no promoted assertion premise, fire,
blackbox, launch failure, or unexpected termination.  Together with the
40/40 transition proof and 52/52 reached path covers above, this closes the
public scalar/full capture, visibility, completion, and freeze refinement
gate.  It does not yet authorize removal of the full endpoint snapshots: the
role-side scalar shadow must first prove against the existing role queues.

An independent, DUT-free output-polarity audit reaches the same boundary at
`work/runs/20260903T_public_pair_view_refinement_audit5_c6_public_pair_view_refinement`.
It instantiates one symbolic Subordinate-side endpoint with full AW/W and
independent AWREADY/WREADY, disables transaction-environment and bounded-
progress policies, removes every elaborated assumption, and re-adds exactly
12 ghost/reset assumptions.  All 23 assertions prove and all 18 covers reach
in one second, including AWLEN 255, low/high arbitrary payload indices, all
three AW and completion shapes, prefix/early/live/prior/final samples, and
both READY-low stalled-offer shapes.  There are zero compile warnings/errors,
blackboxes, or launch failures.  The production hashes under test are the
same current `axi_fvip.sv`, public-view, and reduced pair-tracker hashes
recorded above.  This independently rules out a hidden xbar/DUT premise in
the public scalar refinement.

The role-side W migration is now staged shadow-first, with the old queues and
all four production W assertions retained unchanged.  The stream tracker
exports the exact selected routed-AW offer, and the role wrapper threads the
source and selected-output endpoint pair skew, selector, pending/completed,
rank, watched-beat, and scalar payload observations into the write tracker.
The write tracker adds one-way selector-alignment assumptions and parallel
state/offer/sample/packet occurrence and integrity assertions.  These
assumptions constrain only the independently arbitrary FVIP selectors; they
do not assume DUT payload, routing, READY, completion, or internal state, and
the implication is never reversed into `endpoint_pair_select -> role_select`.
The important AXI4 W-before-AW cases use signed AW-minus-completed-W skew and
rank zero rather than an ID, because AXI4 has no WID.  Stalled WVALID offers
remain checked live rather than waiting for a handshake or WLAST.

The first source-only gates
`work/build/20260903_c6_role_w_pair_shadow_compile_xbar_{protocol,full}`
passed, but are explicitly stale: two audit additions landed afterward (a
cover-semantics preservation fix and the same-cycle prefix-handoff lemma).
The superseding exact-current gates are
`work/build/20260903_c6_role_w_pair_shadow_final_v2_compile_xbar_{protocol,full}`;
both exit zero with zero errors/warnings and the two expected suppressed
diagnostics.  The full formal elaboration independently measures 271 assertion,
314 assumption, and 201 cover checkers with no blackbox.  The current SHA-256
values are
`b829e02ac9e9daf2f940ce121b2b0c8a40893d0f58c27635a673ccbba7e9391e`
for `xbar_stream_tracker.sv`,
`30fc517da0d6a1dc0c9a796e3028b58ce59aaab6aeabd487c9780b8df3c71f49`
for `axi_xbar_role_fvip.sv`, and
`7a62373dfe2257d6cfdec029ce2424fb709ba69134a829834316fb1a491d57e0`
for `xbar_write_tracker.sv`.  No role queue or full endpoint payload snapshot
has been deleted, and none of the new shadow assertions is counted as a
production closure yet.  The legacy transaction-mutation harness directly
instantiates the source role and leaves these newly added shadow inputs
unconnected, so it remains useful for the retained production properties but
is not evidence for the new shadow bridge; a dedicated or wrapper-level
validation must exercise that bridge.

A second read-only end-to-end wiring audit found no polarity, source/output
mux, canonical-W packing, width, or decode-error guard defect in the scalar
path.  Input views use Manager-side FVIP polarity, output views use
Subordinate-side polarity, and asymmetric input/output skew and rank widths
remain intact.  All eight new assumptions are one-way constraints only on
ghost selector/rank/beat/index choices.  Two low-risk cleanup notes remain:
the retained legacy queue path still contains event-gated dynamic
`[watch_route]` accesses which are unreachable for decode-error route 2, and
the public watched-beat field relies on AXI4's legal 256-beat maximum rather
than a module-local static `MAX_BURST_LEN <= 256` guard.

The monolithic selected-B rank proof already ended clean and nonvacuous but
inconclusive after ten minutes at radius 52, so it is not being repeated
unchanged.  Exhaustive fixed-domain retries target the four
source/destination combinations.  They target only
`a_tracker_m_b_pending_rank` and use the independently proved route facts,
global write-lifecycle conservation, and all four endpoint pair-skew bounds.
They do not assume mapped-B occurrence or any role W production property.
The first two artifacts are
`work/runs/20260903_c6_role_b_rank_partition_s0_d0_pair_shadow_xbar_zipcpu_axixbar_full_d1_ft0`
and
`work/runs/20260903_c6_role_b_rank_partition_s1_d1_pair_shadow_xbar_zipcpu_axixbar_full_d1_ft0`.
Both are nonvacuous at radius 12 and have no fire, blackbox, launch failure,
or unexpected termination.  Source1/destination1 proved in 136 seconds;
source0/destination0 remained inconclusive after five minutes at radius 49.
The two cross partitions
`work/runs/20260903_c6_role_b_rank_partition_s0_d1_no_wshadow_xbar_zipcpu_axixbar_full_d1_ft0`
and
`work/runs/20260903_c6_role_b_rank_partition_s1_d0_no_wshadow_xbar_zipcpu_axixbar_full_d1_ft0`
ran with all eight new role W-shadow alignment assumptions explicitly
removed, preserving an acyclic B-only proof boundary.
Their fresh exact-source elaborations directly confirm the current full model
at 271 assertion checkers and 314 assumptions, with no blackboxes.  Both
cross partitions remained clean and nonvacuous but inconclusive after five
minutes at radius 49.  Thus only source1/destination1 is proved; the other
three source/destination partitions all plateau at radius 49.  The exhaustive
fixed-domain tactic does **not** close the arbitrary B-rank helper and must not
be promoted.  Repeating these cones unchanged is exhausted; the next attempt
must change the abstraction.

The failed induction was localized.  Let `O=m_protocol_outstanding` and
`R=m_b_rank`.  Routed-AW capture establishes `O'=R'+1`, and ordinary matching
AW/B events preserve `O>R`.  The sole hard edge is `O=1,R=0` with a matching
B handshake and no matching AW: the endpoint decrements `O` while the role
keeps its duplicate B transaction pending until the duplicate role-W state
says the selected W completed.  This unnecessarily drags a simple B credit
fact through the full legacy W cone.  The one proved source1/destination1
partition also retained the new W-shadow selector assumptions, so it is not
an independent escape from this architectural problem.

The chosen successor is state reduction rather than another rank lemma.
One-way align `route_hsk` with the already-public selected output
`wr_select`, then reuse that endpoint tracker's `wr_rsp_visible`,
`wr_completed`, and captured `wr_b` for mapped-B occurrence and data.  This
can delete `m_b_rank`, `m_b_pending`, `m_b_sampled`, and
`selected_m_b_data`--`MST_COUNT_W+3`, or five role-local bits in the current
profile--and removes mapped B's dependence on duplicate role-W completion
state.  Before deletion, add and independently prove zero-state public B
capture/freeze/provenance bridges plus stalled live/completed covers.  The
selector implication must remain role occurrence to endpoint ghost selector
only; no BVALID/BREADY/payload/DUT behavior may be assumed.

The first role-W shadow state partition is green at
`work/runs/20260903_c6_role_w_pair_shadow_t2_state_s0_d0_current_xbar_zipcpu_axixbar_full_d1_ft0`.
For source0/destination0, both `a_pair_shadow_source_state` and
`a_pair_shadow_output_state` prove and are nonvacuous; source/output AW-first
and W-first covers all reach at radii 4, 6, 10, and 12.  The proof completes
in 33 seconds with no fire, blackbox, launch failure, or unexpected
termination.  Its only converted premises are the selected source/output
pair pending-AW/pending-W rank facts and the four established route facts; it
uses no legacy W queue assertion, B property, progress property, or DUT-
internal invariant.  This closes only one of four fixed source/destination
partitions, so neither shadow state helper is promoted globally yet.

The matching source0/destination1 partition
`work/runs/20260903_c6_role_w_pair_shadow_t2_state_s0_d1_current_xbar_zipcpu_axixbar_full_d1_ft0`
is also green: both state assertions prove nonvacuously, all four AW/W-first
covers reach at the same radii 4/6/10/12, and the proof completes in 27
seconds with zero failures.  It substitutes only the independently proved s0
and m1 pair-rank facts in the same eight-premise DAG.  The
source1/destination0 artifact
`work/runs/20260903_c6_role_w_pair_shadow_t2_state_s1_d0_current_xbar_zipcpu_axixbar_full_d1_ft0`
is green as well: 2/2 assertions prove nonvacuously, 4/4 covers reach at
radii 4/6/10/12, and it completes in 28 seconds with zero failures using the
s1/m0 pair-rank substitution.  The final source1/destination1 artifact
`work/runs/20260904_c6_role_w_pair_shadow_t2_state_s1_d1_current_xbar_zipcpu_axixbar_full_d1_ft0`
has the identical 2/2 proved, 4/4 covered result and completes in 28 seconds
with zero failures; its report SHA-256 is
`a54efcc36d0c94be0b8e99827abb02e1cce1fc39ef3605a2025fc02c09fb2a`.
The four fixed domains exhaust both arbitrary source and mapped destination,
so `a_pair_shadow_source_state` and `a_pair_shadow_output_state` are now
globally promoted helper facts.  Role helper closure moves from 3/15 to
**5/15**; production remains 9/14.  The T3 occurrence/completion run was
deliberately held so the B-state replacement can land first and both paths
continue from one common source.

### Protocol W hard-cone audit after the corrected offer checks

The ten remaining retained-original W failures split into three materially
different cones rather than one packet proof: four WSTRB checks, four exact
WLAST checks while the matching AW is already pending or selected, and two
exact-WLAST checks after the W packet completed before its AW.  In particular,
the current live zero-skew cases are
`x_wstrb_live_select_aw` and `x_w_last_offer_select_aw` on each output; the
accepted-AW cases are `x_wstrb_live_after_aw` and
`x_w_last_offer_after_aw`; and the completed-W/live-AW case is
`x_w_last_exact_after_w`.  This classification is the next proof schedule and
prevents an easy live-offer obligation from inheriting an unrelated full
pairing cone.

The zero-state decomposition to try first is: split WSTRB after-AW and
select-AW into prefix versus current-beat facts; split exact WLAST in those
same phases into a W-position fact plus the current-WLAST comparison; and
split after-W into handshake and stalled-live-AW halves.  Existing
`a_pair_completed_exact` plus `a_tracker_after_w_capture` should cover only
the handshake half.  It is not sufficient for the stalled half because an
AW offer can remain visible with `AWREADY=0` indefinitely.

Two small endpoint facts should precede those production retries:
`a_tracker_aw_summary_frozen` and `a_tracker_wstrb_lane_hold`.  The first
states that a captured AW summary does not change while it owns the pair; the
second makes the arbitrary watched-lane accumulator explicit across a stalled
or multi-beat W packet.  Both are properties of port signals and FVIP ghost
state, not DUT internals.  The after-AW cones may then use pending rank,
summary capture/freeze, channel stall stability, and burst length.  The
after-W handshake half may use the already-proved completed-pair facts; the
stalled half should use pending-W rank plus AW stall stability.  If that half
still plateaus, the next abstraction is an output-anchored generic
correspondence lemma, not a role-specific invariant.

Cone pruning is also explicit.  WLAST proofs do not need input-side WSTRB,
read selectors/contracts, or public scalar-index assumptions.  They do still
need the output B-completion contract: removing it permits an illegal early B
response to release the write grant and destroys the intended packet
ownership.  No retry may consume the open completed-WSTRB helper, the open
packet-length helper, role-W properties, or bounded progress.  If an
arbitrary lane or beat remains expensive after the structural split, use the
finite lane0..3 and then beat0..7 partitions; do not add implementation
invariants.  A later safe micro-reduction can encode the pair phase in two
bits, saving two bits per endpoint, but it is not on the critical closure
path.

### Endpoint-backed B shadow implementation checkpoint

The shadow-first B replacement is now staged, with the legacy B rank/sample
path and both legacy production assertions deliberately left intact for
side-by-side proof.  The exact staged source hashes are `axi_fvip.sv`
`14e7af32a0cd911984cafcf79cf84f5b37aaae875360572577281f7e53c9cca5`,
`axi_xbar_role_fvip.sv`
`d76fa97a547c231e8b818db610c4b3fe8d92136d273f60ff29dc63f4417862fc`,
and `xbar_write_tracker.sv`
`0414508ed6f9997e9a43ef0cd51e1f4ab2fa0b34cc96ee7ecb81338cd5038750`.
Both exact-source compile gates are clean with zero errors/warnings and the
two expected suppressed diagnostics at
`work/build/20260904_c6_role_b_endpoint_shadow_compile_xbar_protocol` and
`work/build/20260904_c6_role_b_endpoint_shadow_compile_xbar_full`.

Each transaction endpoint now exposes and locally checks five zero-state B
view facts: selected-state entry, exact response-complete qualification,
payload capture, completion provenance, and post-completion payload freeze.
It also covers endpoint selection, a stalled live selected B offer, capture,
and stored completion.  The role checker receives only the selected output's
existing `wr_select`, `wr_completed`, `wr_rsp_visible`, and captured `wr_b`.
The sole new role assumption is the one-way ghost alignment
`route_hsk && mapped_route |-> m_protocol_wr_select`; it constrains neither
availability nor payload and has no converse.

Two parallel role assertions now express the intended replacement.
`a_endpoint_shadow_mapped_b_occurrence` requires every selected source-side
mapped B offer to have either the corresponding selected output B live or its
endpoint snapshot completed.  `a_endpoint_shadow_mapped_b` compares one
arbitrary canonical B bit against that live or stored output value, stripping
the crossbar-added source-ID prefix and honoring the existing USER-preserve
configuration.  Three role covers exercise selector alignment, stalled-live
B, and stored-B paths.  This is staged evidence only: neither new assertion
is counted closed yet, and no legacy bit may be deleted until the public
bridges plus all four source/destination partitions prove and the mutation
gate observes the new wiring.

The exact proof DAG is public state/capture/freeze first, then completion
provenance with the selector-local B-credit property removed, then all four
selector/live/stored cover partitions, mapped-B occurrence, and finally
arbitrary-bit data composition.  The intended deletion gate remains five
role-local bits at the current profile: `m_b_rank[1:0]`, `m_b_pending`,
`m_b_sampled`, and `selected_m_b_data`.

Two manual cover-launch attempts were infrastructure-only failures and are
not proof evidence.  The first raw `make qverify` stopped immediately because
`vmap` was absent from `PATH`; the second added the documented Questa paths
and reached `qverify` but stopped because the license environment was not
loaded.  The corrected run uses `tools/run_formal.sh`, which silently loads
the configured license setup, adds the Questa paths, enters `shell.nix`, and
refuses to overwrite an existing artifact directory.

### Clarification: how responses and W packets are tied to AR/AW

The chosen architecture is the arbitrary-occurrence/rank construction, but
the harness observes existing traffic rather than injecting a distinguished
request.  For reads, a stable arbitrary ID and an arbitrary accepted AR
occurrence are selected.  The read tracker captures that AR, initializes a
same-ID predecessor rank, and decrements the rank only on same-ID RLAST
handshakes.  While the selected occurrence is pending at rank zero, every
same-ID RVALID offer belongs to its packet: the running beat position is
checked against captured ARLEN and RLAST must be exact.  An arbitrary beat
may additionally be captured for end-to-end role payload comparison.  There
is no R byte-enable field analogous to WSTRB.

Writes need a different ordering token because AXI4 has no WID and permits a
W burst to complete before its AW.  The endpoint pair tracker therefore uses
the signed conservation value `accepted_AW - completed_W`, can select either
an AW occurrence or a completed-W occurrence, and uses an opposite-side rank
until the two occurrences meet.  Captured AW length/size/burst metadata, the
shared channel beat counter, an arbitrary watched beat, and an arbitrary
strobe lane establish exact WLAST and legal-byte behavior.  The public scalar
payload observer generalizes the watched lane to one arbitrary W payload bit
for the role proof without storing a full burst.

A sticky `matched` bit is safe as a diagnostic or as the validity bit for an
already captured arbitrary beat.  It cannot be the sole correctness
authority checked only at RLAST/WLAST: an environment may hold READY low
forever, or a faulty producer may omit LAST, so that delayed check need never
fire.  The safety assertions consequently compare every owned VALID offer;
handshake/completion updates rank and makes captured snapshots available but
does not gate live correctness.  This is the main refinement over a literal
"set matched, assert it at LAST" implementation.

The first public-B gate is green for every endpoint at
`work/runs/20260904_c6_public_b_a1_transition_14e7af32_xbar_zipcpu_axixbar_protocol_d1_ft0`.
All 16 selected-state, response-complete-exact, capture, and freeze instances
prove with 16/16 nonvacuity checks.  Selection, capture, and stored covers
reach on all four endpoints; stalled-live covers reach on both DUT input
interfaces.  The two DUT-output stalled-live covers remain clean and
inconclusive after 120 seconds at radius 41, so they are reachability evidence
still to resolve, not failed assertions.  The report SHA-256 is
`6e56bca66c1dd34d7e9ce01bc31fdb5a8817d8674cfefaaf7c282bdfb94ddd58`.
Completion provenance is intentionally a separate gate.

The stricter output-provenance experiment
`work/runs/20260904_c6_public_b_a2_provenance_no_selector_credit_14e7af32_xbar_zipcpu_axixbar_protocol_d1_ft0`
removed both output trackers' selector-local `x_b_has_completed_write`
assumptions while retaining the universal deterministic subordinate
contract.  Both provenance antecedents are nonvacuous, no assertion fires,
and selection/capture/stored covers reach, but both provenance targets remain
inconclusive after 180 seconds at radius 43; the two output stalled-live
covers also remain inconclusive.  This is a clean failed strengthening, not a
counterexample.  Sign-off composition will retain the already-established
selected completed-write protocol rule, while the deterministic contract
continues to constrain every environment-owned B occurrence.

The input-side provenance composition is independently green at
`work/runs/20260904_c6_public_b_a3_input_provenance_composed_14e7af32_xbar_zipcpu_axixbar_protocol_d1_ft0`.
It converts exactly the two already-proved input
`x_b_has_completed_write` instances, proves both input
`a_view_wr_b_provenance` instances nonvacuously, and reaches all eight input
selection/stalled-live/capture/stored covers in 34 seconds.  No A1 public
helper is promoted.  The report SHA-256 is
`8e8a4174c7488fa6d518936a2e40cb889317ab05dfd30268cb1249cf5d16e556`.
The final all-four checksum is green at
`work/runs/20260904_c6_public_b_a4_all_provenance_composed_14e7af32_xbar_zipcpu_axixbar_protocol_d1_ft0`.
With the native output selected completed-write contracts restored and only
the two proved input instances converted, all four provenance assertions
prove nonvacuously at radius 14.  Fourteen of sixteen covers reproduce the
A1 distances; only the two output stalled-live covers remain inconclusive at
radius 39 after 120 seconds.  The report SHA-256 is
`920941376e3415d8a25eae3182d740ea2ddd231d26359c58f6ca5b8536b4c7b7`.
Together A1 and A4 close all **20/20** newly added public B helpers.  The
current protocol helper ledger is therefore **127/129**; the only open
protocol helpers remain the two pre-existing output
`a_pair_completed_wstrb` instances.

The first fixed role-B cover partition is
`work/runs/20260904_c6_role_b_endpoint_shadow_covers_s0_d0_wrapper_xbar_zipcpu_axixbar_full_d1_ft0`.
With all eight unrelated W-shadow assumptions removed and no assertion
promoted, selector alignment reaches at radius 10 and the stored-B branch at
radius 14.  The simultaneous source-offer/output-live stalled branch remains
clean but inconclusive after 180 seconds at radius 43.  This implementation
can accept an output B into its return buffer before exposing it upstream, so
the stored branch is the expected common route; the live branch is retained
in the generic assertion and is also exercised by the deterministic role
mutation harness.  The report SHA-256 is
`5eab8fc42cf4e2e764b48f9d4b5da448e623108ba779d7e0f9363683674f655c`.

The other three fixed B-cover partitions reproduce that result exactly:
`20260904_c6_role_b_endpoint_shadow_covers_s0_d1_wrapper_*`,
`20260904_c6_role_b_endpoint_shadow_covers_s1_d0_wrapper_*`, and
`20260904_c6_role_b_endpoint_shadow_covers_s1_d1_wrapper_*` each reach
selector alignment at radius 10 and stored B at radius 14, while the
live-stalled branch is clean/inconclusive at radius 43 after 180 seconds.
Their report hashes are respectively
`1638d36c74bc71434149b1a714ce9e6058cbea375dddf72b7491efe446c7d424`,
`281ba693805154bbc2ffd827a5b51152f4d8a8ad1fc5613841303aec58467237`,
and `33b6b075065657e1b2def3b0d07c39efa931ab0aa74387d7feefe11be9d7cbd0`.
Thus selector and stored-path reachability are exhaustive over both arbitrary
source and destination choices; the intentionally retained generic live
branch has directed mutation evidence but not a production-DUT cover proof.

The endpoint-backed B mutation gate now passes at
`work/runs/20260904_c6_endpoint_b_shadow_validation_final_transaction_mutations`
for cases 32--36, with zero compile warnings/errors, zero inconclusive
targets, all directed sequences reached, and all guards proved.  Legal case
32 proves both new B assertions and reaches selector, live, and stored role
covers: the selected output B is stalled at step 4, handshakes into the
output observer at step 5, and is compared from its frozen snapshot at step
6 while the source remains stalled.  Case 33 corrupts mapped B payload while
both BREADY signals remain low and fires the new data assertion.  Cases 34
and 36 respectively expose premature and wrong-ID mapped responses and fire
the new occurrence/data checks.  Case 35 remains the local-error mutation,
where the mapped shadow is correctly vacuous.  The validation TB SHA-256 is
`a4f26c0051dd30db55b6d558c7d2f5314bc5b1a16647eab9130d7c20fa5b3d94`.

The first mutation attempt at
`work/runs/20260904_c6_endpoint_b_shadow_validation_transaction_mutations`
was not valid evidence: the older 28 public pair-view ports in that
validation-only role instantiation were still unconnected, producing 29
elaboration warnings and nine unrelated pair-shadow fires in legal case 32.
The corrected harness explicitly models those pre-existing one-beat pair
views and connects them, as well as all eight new B-view inputs.  No
production source or runner was changed for this correction.

The first endpoint-backed mapped-B occurrence composition is clean and
nonvacuous but does not close.  Artifact
`work/runs/20260904_c6_role_b_endpoint_occurrence_s0_d0_min_a1_xbar_zipcpu_axixbar_full_d1_ft0`
uses only four proved route facts, source0 completed-write, output0 write
capacity, and two A1 public facts; it removes all eight W-shadow assumptions
and promotes no legacy B or role-W assertion.  Selector and stored covers hit
at radii 10/14, while occurrence remains inconclusive at radius 39 after 180
seconds.  Its report hash is
`fec191faad74a6de8357c1c897bfbb92de1863056b2fe0cf33f524c5e4977a64`.
A single authorized wider-premise retry,
`work/runs/20260904_c6_role_b_endpoint_occurrence_s0_d0_composed_a1_protocol_xbar_zipcpu_axixbar_full_d1_ft0`,
converts 13 independently proved route/protocol/A1 facts but still remains
clean/nonvacuous and inconclusive at radius 41 after five minutes.  Its report
hash is
`ab1db544539dd526f9b333e9396fa0d07e2e1540ffc227abfd31b24db64d131b`.
Premise widening is therefore exhausted.

The missing induction cut is zero-state alignment, not another response
rank.  The output endpoint already exports sticky `wr_selected`, but the role
currently receives only its one-cycle selection pulse plus completion/live
signals.  Threading the selected bit and proving
`routed && mapped_route |-> m_protocol_wr_selected` directly captures the
permanent consequence of the existing one-way
`route_hsk -> m_protocol_wr_select` alignment.  `wr_pending` is unnecessary:
the public endpoint defines completion as selected and not pending, so
selected plus not-completed already identifies the pending branch.  Stage
this one helper, prove it independently, and split occurrence into routed and
live-return halves only if the composed target still plateaus.

Once endpoint-backed occurrence and data are proved exhaustively, the exact
legacy deletion is `m_b_rank`, `m_b_pending`, `m_b_sampled`, and
`selected_m_b_data`, plus their sole count-width localparams, dynamic
`m_b_offer/m_b_watch/m_b_data_bit` plumbing, three old assertions, two old
covers, and sequential updates.  At depth one that removes five state bits
and all four legacy-B dynamic `[watch_route]` accesses.  The old
`m_protocol_outstanding` and write-tracker `watch_id` role ports then become
unused and should be removed through the role and validation-only wrappers;
generic endpoint exports remain.  `selected_m_w_completed` must remain until
the separate W replacement is complete.  Because the new zero-state
selected-alignment assertion is being added after the original checklist,
the final checker checksum will be one assertion above the checklist's
pre-cut projection.

The first mapped-B occurrence composition did not close.  Artifact
`work/runs/20260904_c6_role_b_endpoint_occurrence_s0_d0_min_a1_xbar_zipcpu_axixbar_full_d1_ft0`
fixes source0/destination0, removes all eight W-shadow assumptions, and
converts exactly four proved route facts, source0 completed-write safety,
output0 outstanding capacity, and the output0 public selected-state and
response-complete facts.  It uses no legacy role-B assertion, role-W
assertion, progress property, DUT-internal invariant, lifecycle helper, or
payload helper.  Selector and stored covers reach at radii 10/14 and the
occurrence antecedent is nonvacuous, but the assertion remains clean and
inconclusive after 180 seconds at radius 39.  Its report SHA-256 is
`fec191faad74a6de8357c1c897bfbb92de1863056b2fe0cf33f524c5e4977a64`.
Do not repeat this cone unchanged.  The next candidate is a zero-state
alignment invariant between sticky role `routed` and the already-public
selected output endpoint `wr_selected`; it requires no new transaction
state.

### Live checkpoint: zero-state write-selection cut staged

The missing B-side alignment cut is now implemented without adding state.
`axi_xbar_role_fvip.sv` muxes the arbitrary destination's public
`wr_selected` view into the role checker, and `xbar_write_tracker.sv` adds
only
`a_endpoint_shadow_output_selected: routed && mapped_route |->
m_protocol_wr_selected`.  No `wr_pending` view was added and none of the
legacy B machinery has yet been deleted.  The staged source hashes are:

- `axi_xbar_role_fvip.sv`:
  `5d80edff8a5129f1711fd7ba0c656932eed6739b16133e8eeeaf4b1559e835f9`;
- `xbar_write_tracker.sv`:
  `290ab12d9aba8bd05d221877388622f00e1f696c7da172f5e680ad598ec74f4f`.

Both compile gates pass with zero errors, zero warnings, and only the two
expected suppressed messages:
`work/build/20260904_c6_role_b_wr_selected_cut_compile_xbar_protocol` and
`work/build/20260904_c6_role_b_wr_selected_cut_compile_xbar_full`.  The first
fixed s0/d0 helper proof is running with only the four established route
facts and output0's proved public `a_view_wr_select_state` as premises; all
eight W-shadow assumptions are removed.  This independently proves the cut
before it is used to compose mapped-B occurrence.

The first cut partition is green at
`work/runs/20260904_c6_role_b_wr_selected_cut_s0_d0_xbar_zipcpu_axixbar_full_d1_ft0`.
For fixed source0/destination0, the new assertion proves in 22 seconds and
its antecedent is nonvacuous at radius 12; the native selector cover reaches
at radius 10.  The only promoted facts are the four route facts and output0
`a_view_wr_select_state`; all eight W-shadow assumptions are removed.  The
report SHA-256 is
`f471c6fa4e69f62b4691d5f609064156f3c39e5ad35dd29c7b1cdf4e26c5c302`.
The staged full-model checksum is 4,902 state bits, 165/166/129
assert/assume/cover directives, and 294/315/220 elaborated checkers.  Relative
to the prior B staging point, this is exactly one new assertion checker and
zero state.  The other three source/destination partitions are now running,
and s0/d0 mapped-B occurrence is being composed in parallel against this
proved cut.

All four fixed source/destination partitions of the selected-only cut are
now closed.  The s0/d0, s0/d1, s1/d0, and s1/d1 instances prove in
22/25/25/25 seconds respectively; every antecedent is nonvacuous at radius
12 and every native selector cover reaches at radius 10.  The latter three
artifacts are
`work/runs/20260904_c6_role_b_wr_selected_cut_s0_d1_runner_xbar_zipcpu_axixbar_full_d1_ft0`,
`work/runs/20260904_c6_role_b_wr_selected_cut_s1_d0_runner_xbar_zipcpu_axixbar_full_d1_ft0`,
and
`work/runs/20260904_c6_role_b_wr_selected_cut_s1_d1_runner_xbar_zipcpu_axixbar_full_d1_ft0`;
their report hashes are respectively
`fa96d77e07bbbd3d028210b3bd13684e9627b1a84d46e1230bf14fadf96cf1a0`,
`8d97d5b4a297a77e7247995d3cffbb79381f0782892397620c0c0bfdf0e6e5a2`,
and
`77616a895b73ab3ff36644a550c10df057576542e9b70f459e2d71d2e588a5ff`.
The premise DAG is identical in every partition and uses no B/W/progress or
DUT-internal fact.  The role helper ledger is provisionally **6/16** after
adding and closing this new helper; the role production ledger remains
**9/14** until endpoint-backed mapped B closes.  Protocol elaboration remains
260 assertion, 298 assumption, and 186 cover checkers because the new cut is
role-only.

The new cut is necessary and independently inductive, but it does not by
itself close the combined mapped-B occurrence target.  Artifact
`work/runs/20260904_c6_role_b_endpoint_occurrence_s0_d0_selected_cut_min_a1_xbar_zipcpu_axixbar_full_d1_ft0`
uses the prior minimal eight facts plus
`a_endpoint_shadow_output_selected`, with all eight W-shadow assumptions
removed.  The occurrence antecedent is nonvacuous at radius 14 and the
selector/stored covers reach at radii 10/14, but the assertion remains clean
and inconclusive at radius 39 after 180 seconds--exactly the old min-A1
radius.  The effective focused model has 316 assumptions, one assertion, and
two covers; all nine requested premise conversions occurred, with no proof,
compile, or engine error.  The report SHA-256 is
`1a9061311bcf9230bed469af530e4363f658bdb1292e90ae012018957310acd8`.
Do not fan out this monolithic cone.

The exact no-state Boolean split of `A -> R && (C || V)` is now:

```systemverilog
a_endpoint_shadow_mapped_b_routed: assert property (
  selected_s_b && mapped_route |-> routed);
a_endpoint_shadow_mapped_b_live_return: assert property (
  selected_s_b && mapped_route && routed &&
    !m_protocol_wr_completed |-> m_protocol_wr_rsp_visible);
```

The first helper establishes `R`.  If endpoint completion `C` is already
set, the stored branch is done; otherwise the second helper establishes the
live response `V`.  This also has the correct NBA boundary: on the output-B
handshake edge `completed` is still zero and `rsp_visible` is high, while on
the next cycle `completed` is high.  No `$past`, READY, or new ownership
state is needed.  Prove the routed half from the four route facts only, the
live half from the routed helper plus the proved selected-output helper, and
finally compose the unchanged occurrence assertion from the two halves.
The source completed-write and public response-complete premises in the
failed monolith were unused and should not be carried into these split gates.

Both split helpers are now staged exactly as above in
`xbar_write_tracker.sv`, with source SHA-256
`09fc2092f8a7c3b6da83e4735a388c77294185299aa879baee58a61e48a50d95`;
the role wrapper remains
`5d80edff8a5129f1711fd7ba0c656932eed6739b16133e8eeeaf4b1559e835f9`.
No old property or sequential state changed.  Both compile gates are clean
with zero errors/warnings and the two expected suppressed diagnostics:
`work/build/20260904_c6_role_b_occurrence_split_compile_xbar_protocol` and
`work/build/20260904_c6_role_b_occurrence_split_compile_xbar_full`.  The
exact delta is two assertion directives/checkers and zero
assumptions/covers/state.  Full elaboration is therefore 4,902 state bits,
167/166/129 directives, and 296/315/220 assertion/assumption/cover checkers;
role-disabled protocol elaboration remains 4,824 state bits and
260/298/186 checkers.  The routed half is now running across all four fixed
source/destination partitions from only the four route facts.

One compile-launch attempt used a nested `--run` shell wrapper whose quoting
dropped the explicit target arguments and began the default qverify flow.
That exact process tree was terminated before verification and produced
neither requested compile artifact; it is not evidence.  Direct interactive
`make compile ... ODIR=<absolute-path>` invocations produced the clean gates
above.  Do not reuse the nested wrapper form.

The route-only split is also exhausted and does **not** close.  All four
fixed source/destination instances of
`a_endpoint_shadow_mapped_b_routed` are clean, nonvacuous at radius 14, and
inconclusive at radius 39 after two minutes.  Selector/stored covers reach at
radii 10/14 wherever both were requested.  Every run converts exactly the
four route facts, removes exactly the eight W-shadow assumptions, and uses no
public-B, legacy-B, role-W, progress, lifecycle, or DUT-internal premise.
This proves that the remaining hard cone is specifically the relation from a
selected input B offer back to the forwarded-AW lifetime; it is not endpoint
B capture or selected-output alignment.  Do not repeat or widen this
route-only cone blindly.

The artifacts and report hashes are:

- s0/d0:
  `work/runs/20260904_c6_role_b_routed_split_s0_d0_route_only_xbar_zipcpu_axixbar_full_d1_ft0`,
  `7bfd2b98ad14515b879660b12f29fef01be83428f1efd74fed21d5553cd802dd`;
- s0/d1:
  `work/runs/20260904_c6_role_b_routed_split_s0_d1_route_only_xbar_zipcpu_axixbar_full_d1_ft0`,
  `7bd8719c1b65f2eb7708d65a878d4da00e1e83517706f9627dc3198c530f6332`;
- s1/d0:
  `work/runs/20260904_c6_role_b_endpoint_routed_s1_d0_route_only_xbar_zipcpu_axixbar_full_d1_ft0`,
  `6febe5aca76f0c48e0343b163d449741fb59c5189266d984be4842e3bd8d4703`;
- s1/d1:
  `work/runs/20260904_c6_role_b_endpoint_routed_s1_d1_route_only_xbar_zipcpu_axixbar_full_d1_ft0`,
  `9a9c0f6322eba0060981b3baea1c552a7eebca4d6d8c699020889f9ffb36fe58`.

The full model remains 4,902 state bits and 296/315/220 checkers.  Each
focused job saw 311 assumptions after the eight removals and four
promotions.  No assertion fired and no compile or engine failure occurred.

The mapped-B payload theorem is ready for a later live/stored zero-state
split, but should not be launched before occurrence closes.  The live helper
compares the current source and selected-output B bit when endpoint
completion is still low; the stored helper compares the source bit with the
captured public endpoint B snapshot after completion.  The existing stable
arbitrary `watch_payload_bit` already universally covers low BID, BRESP, and
BUSER, and both paths strip the source prefix identically.  Thus no new bit
selector, payload storage, or alignment assumption is needed.

### Live checkpoint: route-lifecycle reuse staged

The successor to the exhausted route-only implication reuses the request
stream tracker's existing selected `pending` and `completed` bits as public
role-local wires.  No register, counter, selector, or assumption was added.
The exported views are gated with `watch_write` before entering the write
checker because the same stream tracker also observes selected reads.  Three
staged helpers are:

```systemverilog
a_endpoint_shadow_route_lifecycle: assert property (
  (route_pending ^ route_completed) ==
    (role_selected && mapped_route));
a_endpoint_shadow_routed_equiv: assert property (
  routed == route_completed);
a_endpoint_shadow_route_pending_no_source_b: assert property (
  route_pending |-> !selected_s_b);
```

The first two are exact recurrence/equality checks.  The third is the sole
new role obligation: a B offer for the selected source write cannot exist
while its mapped AW is still pending at the destination.  Together they imply
`selected_s_b && mapped_route -> routed`: selected mapped state is exactly
pending xor completed, pending is excluded by the B offer, and completed is
equal to routed.  This orientation is READY-independent and handles both a
stored route and empty-queue bypass.  On a pending route-handshake edge the
sampled state is still pending/unrouted until NBA, so there must be no
`route_hsk` exemption.  W-before-AW does not change the argument and local
DECERR is excluded by `mapped_route`.

The staged source hashes are:

- `xbar_stream_tracker.sv`:
  `769f1d9c16aa10029d33c91f018c7841abe7b7ff2d9a9afee911184a561f12db`;
- `axi_xbar_role_fvip.sv`:
  `0d0ebf37e3c7efe15374e17836a3af20bf4defade8918d0c98aa93b315ef8592`;
- `xbar_write_tracker.sv`:
  `d88c06119c7605abfdeb5d9c992fb647d7f603dad9c05e3260bd58d270844f3c`.

Protocol/full compile gates are running.  Expected full delta is three
assertion checkers, no assumptions/covers/state: 299/315/220 checkers and
4,902 state bits.  If `a_endpoint_shadow_routed_equiv` closes, the later
cleanup can replace the duplicate write-local `routed` register with exported
route completion and save one additional state bit.

Both compile-only gates now pass with zero errors/warnings and the two
expected suppressed diagnostics:
`work/build/20260904_c6_role_b_route_lifecycle_compile_xbar_protocol` and
`work/build/20260904_c6_role_b_route_lifecycle_compile_xbar_full`.  Their
flists correctly select role off/on respectively.  An independent wiring
audit found no port, polarity, read/write gating, reset, bypass, or NBA bug
and confirmed the exact delta of two aliases, no sequential assignment, and
three assertions.  The compile target does not elaborate formal properties,
so 299/315/220 checkers and 4,902 state bits remain a prediction to verify in
the first focused run; directive counts are now 170/166/129.

Two proof gates are running in parallel.  The structural gate targets route
lifecycle and routed equivalence with no promoted assertion and only
`watch_write=1`.  The first hard s0/d0 gate targets only pending-route/source-B
exclusion, using the four proved route facts plus source0's public selected-
state fact, with all eight W-shadow assumptions removed.  Do not launch the
derived routed or combined occurrence properties until these roots finish.

The structural lifecycle gate is green at
`work/runs/20260904_c6_role_b_route_lifecycle_structural_arb_xbar_zipcpu_axixbar_full_d1_ft0`.
With no promoted assertion, only `watch_write=1`, and all eight W-shadow
assumptions removed, `a_endpoint_shadow_routed_equiv` proves in 22 seconds
and `a_endpoint_shadow_route_lifecycle` in 23 seconds; both are nonvacuous at
radius 2.  The formal property report confirms exactly 299/315/220 checkers
and 170/166/129 directives; the full design report remains 4,902 state bits
and has no blackbox.  The optimized two-target proof cone retained 2,509
state bits, which is a cone statistic rather than newly added storage.  The
formal report SHA-256 is
`f9ad07aadbf0bc80ff4484548db20e20c1c4070bb7615e4ee0772aac0a469769`.
This proves both the exact reuse boundary and the future one-bit `routed`
deletion opportunity.  The pending-route/source-B exclusion remains the only
unproved root in this occurrence decomposition.

The first hard s0/d0 pending-route/source-B gate did not close.  Artifact
`work/runs/20260904_c6_role_b_route_pending_no_source_b_s0_d0_min_route_select_xbar_zipcpu_axixbar_full_d1_ft0`
promotes exactly the four route facts plus source0
`a_view_wr_select_state`, removes all eight W-shadow assumptions, and targets
only the exclusion assertion plus selector/stored covers.  Its antecedent is
nonvacuous at radius 6 and both covers reach at radii 10/14, but the assertion
is clean/inconclusive at radius 39 after 180 seconds.  The report SHA-256 is
`77fa783af043549d90b06d144e1f70bd090b1f80379f71560438ca2ae4814f2d`.
There are no fires, blackboxes, compile failures, or engine failures.

This result is a useful localization: even after exact route lifecycle is
available, the proof engine still cannot induct the B-return ownership fact
from request-route bookkeeping alone.  Also, although no B assertion was
promoted, native ghost alignment assumption
`s_b_shadow_output_selection` remained enabled and appeared in the bounded
dependency report; this run is therefore not an independence gate for that
assumption.  The two controlled diagnostics reported below both remove it
explicitly: one fixes the arbitrary source/output ID while keeping unbounded
safety, and one enables the repository's declared bounded stall/response
environment.  Neither changes the closure result, so neither is fanned out.

### Prepared protocol-W decomposition (held until B source is stable)

A read-only cone audit found a no-state decomposition for all five remaining
retained-original W shapes.  Keep the production targets unchanged and prove
only their hard halves as helper lemmas; after promotion, each unchanged
production target is the complementary current-offer half.  The proposed
generic helpers are:

```systemverilog
a_tracker_aw_summary_frozen: assert property (
  (pending_aw || completed) |=>
    $stable({watched_aw_beats, watched_aw_lane_legal}));

a_tracker_wstrb_lane_hold: assert property (
  !(w_hsk && current_w_beat == watch_beat) |=>
    $stable(sampled_wstrb_lane));
```

The lane hold deliberately complements the existing capture and frozen
lemmas: it covers stalls and non-watched beats, while the existing lemmas
cover the write-enable cases.  The six subordinate/output-only helpers are:

```systemverilog
a_wstrb_live_after_aw_prefix: assert property (
  pending_aw && rank == 0 && watch_beat < current_w_beat |->
    (!sampled_wstrb_lane || watched_aw_lane_legal));
a_wstrb_live_select_aw_prefix: assert property (
  aw_valid && skew == 0 && !selected &&
    watch_beat < current_w_beat |->
      (!sampled_wstrb_lane || live_aw_lane_legal));
a_w_last_offer_after_aw_position: assert property (
  pending_aw && rank == 0 |->
    {1'b0, current_w_beat} < watched_aw_beats);
a_w_last_offer_select_aw_position: assert property (
  aw_valid && skew == 0 |-> current_w_beat <= aw_len);
a_w_last_exact_after_w_handshake: assert property (
  pending_w && aw_hsk && rank == 0 |=>
    completed && watched_w_beats == watched_aw_beats);
a_w_last_exact_after_w_stalled_live: assert property (
  pending_w && rank == 0 && aw_valid && !aw_hsk |->
    watched_w_beats == live_aw_beats);
```

The handshake/stalled split is semantically important.  Captured AW metadata
updates after the handshake edge, so the handshake lemma is nonoverlapped;
the stalled-live lemma compares the current live AW in the same cycle.
`aw_valid && !aw_hsk` is the exact stall partition because `aw_ready` is not
a pair-tracker port.  No helper uses open completed-WSTRB, packet-length,
role-W, progress, or implementation-specific premises.

Expected source delta is ten assertion directives/twenty elaborated protocol
assertion checkers, zero assumptions, zero covers, and zero state bits.  The
proof order is recurrence first; after-W handshake and stalled halves;
WSTRB prefix halves; WLAST position halves; then the unchanged production
targets.  If a prefix proof remains hard, partition by the four fixed lanes
and then the eight fixed watched beats instead of adding state.

### Live checkpoint: pending-route B diagnostics and per-ID head split

The two controlled diagnostics after the first pending-route/source-B proof
both remained clean, nonvacuous, and inconclusive.  They therefore narrow the
problem but do not close or waive it.

The unbounded fixed-ID run is
`work/runs/20260904_c6_role_b_route_pending_no_source_b_s0_d0_id0_unbounded_no_bselect_xbar_zipcpu_axixbar_full_d1_ft0`.
It fixes source 0, destination 0, the source endpoint write ID to zero, and
the output-0 endpoint write ID to zero.  It promotes only the four route facts
and source-0 public write-select state, removes all eight W-shadow assumptions
and `s_b_shadow_output_selection`, and leaves the environment unbounded.  The
focused model has 311 assumptions, one assertion, and one cover; the broad
source is 299/315/220 with 4,902 state bits.  The target is nonvacuous at
radius 6 and remains inconclusive at proof radius 41 after 180 seconds;
`c_stalled_selected_offer` covers at radius 10.  The formal report SHA-256 is
`9f5fa187dce9453053203ae5b0b153b5976ab42a01a108d2b4bdf7dd7388d664`;
the design report SHA-256 is
`9b3441bb28b396bad1bef7fe28a8f3209d70c716881a4a53d99c7dfbdd6ba8d5`.
Thus arbitrary ID choice is not the induction obstacle.

The bounded-environment comparison is
`work/runs/20260904_c6_role_b_route_pending_no_source_b_s0_d0_bounded_min_route_select_xbar_zipcpu_axixbar_full_d1_ft0`.
It uses the same five promoted facts and nine assumption removals, but sets
`ENABLE_BOUNDED_ENV=1`.  The focused model has 327 assumptions, one assertion,
and two covers; the broad source is 308/331/220 with 4,902 state bits.  The
target is again nonvacuous at radius 6 and clean but inconclusive at radius 39
after 180 seconds; the selector and stored-B covers reach radii 10 and 14.
Its formal report SHA-256 is
`073d2a52a1f0da66d7dff8265248ef61d742f454e263198a913dd7f319e9147e`.
The bounded profile adds 16 environment assumption checker instances: ten at
the two outputs for subordinate R/B response delay and AR/AW/W READY bounds,
and six at the two inputs for Manager W-data availability and B/R READY
bounds.  Only output-0 AWREADY, output-1 AWREADY, and source-0 BREADY enter
this focused cone.  It also enables nine DUT assertion checker instances
(six endpoint progress and three role progress), none of which was promoted;
the promoted source-0 `a_view_wr_select_state` was unused.  Both diagnostic
dependency reports omit `s_b_shadow_output_selection`; the native route
`s_select_handshake` selector contract remains.  Bounded fairness did not
provide a closing induction cut and is not a valid replacement for the
unbounded safety result; in particular, an AWREADY bound could hide a defect
that appears only after a longer route stall.

The next split exposes the source endpoint's existing same-ID ordering state
directly, without adding state, a timer, or an assumption:

```systemverilog
a_endpoint_shadow_route_pending_b_is_older: assert property (
  route_pending |->
    !(s_protocol_pending && s_protocol_w_complete &&
      s_protocol_rank == 0 && s_rsp.b_valid &&
      s_rsp.b.id == watch_id));
```

The `s_protocol_w_complete` premise is necessary to keep this lemma exactly
within the hard branch of the existing protocol contract.  Omitting it would
also reject an early raw B for a write whose W packet is incomplete and would
therefore need the separate input `x_b_has_completed_write` fact.  With the
public definition
`wr_rsp_visible = pending && wr_data_complete && rank == 0 && matching BVALID`,
this helper plus the proved route lifecycle implies the unchanged
`route_pending |-> !selected_s_b` assertion.  It is staged as one role helper
checker and adds zero state, assumptions, or covers.  Prove this root first,
then compose the no-source-B, mapped-route, and mapped-B occurrence DAG; do
not fan out the data half until occurrence closes.  The equivalent expression
is deliberately oriented with `route_pending` as the SVA antecedent so its
ordinary legal stalled-route behavior can be checked nonvacuously even at
outstanding depth one, where a legal older same-ID response need not exist.

Both first gates for that exact per-ID-head rewrite are clean and nonvacuous
but inconclusive, so it is not counted closed.  The independent run is
`work/runs/20260904_c6_role_b_route_pending_b_older_s0_d0_independent_xbar_zipcpu_axixbar_full_d1_ft0`.
It promotes no assertion, removes the nine shadow assumptions, has 306
focused assumptions, one assertion, and one cover, and reaches radius 39 at
the 180-second limit; the route-stall cover reaches radius 10 and assertion
vacuity passes at radius 6.  Its formal report SHA-256 is
`5f9a3f1ff70bf74c082f034007b5e7e2ef077cbc8dfba6e04e4529e749f217bc`.
The companion
`work/runs/20260904_c6_role_b_route_pending_b_older_s0_d0_protocol_cut_xbar_zipcpu_axixbar_full_d1_ft0`
promotes eleven already-proved route, lifecycle, source-view, and source
protocol facts.  It has 317 focused assumptions, the same 6/10 nonvacuity and
cover radii, and is still inconclusive at radius 39 after 180 seconds.  Its
formal report SHA-256 is
`7d1081f95bec24d04e8c1829fb51289822fe20bd5056c9cb745f29840ec38f44`.
Both dependency reports omit all nine removed assumptions; neither has a
fire, blackbox, compile failure, engine failure, or fixed ID.  This is the
same plateau as the original exclusion, so do not fan it across routes or add
the optional public visible-state equality merely to restate the same cone.

The measured exact-source formal inventory at this checkpoint is
**300/315/220** assertion/assumption/cover checkers,
**171/166/129** directives, and **4,902 state bits**.  The source hash for
that measurement is
`8128835183a13cab4dee9f67b9cdbdfef13b636b0cc9dc8ec55f085f2247b54f`.

The next controlled split is the zero-state induction shape rather than
another Boolean spelling.  Define the raw selected-source response head as
the existing pending/W-complete/rank-zero/matching-BVALID conjunction, then
check separately:

```systemverilog
a_endpoint_shadow_route_pending_b_base: assert property (
  enable && select_now && mapped_route && !route_hsk |=>
    !s_protocol_b_head);
a_endpoint_shadow_route_pending_b_hold: assert property (
  route_pending && !s_protocol_b_head && !route_hsk |=>
    !s_protocol_b_head);
```

The base covers every transition that creates `route_pending`; an empty-route
same-cycle handshake completes by bypass instead.  The hold property covers
every cycle in which pending survives; a sampled route handshake removes the
pending state on the next edge.  Together with reset, where route pending is
zero, they are an inductive proof of the unchanged present-state invariant.
They add two helper assertions and no state, assumption, cover, READY bound,
or implementation signal.  Prove base and hold independently before using
them as the only premises for the per-ID-head target.

The independent base and hold gates are both clean/nonvacuous but remain
open.  Base artifact
`work/runs/20260904_c6_role_b_route_pending_b_base_s0_d0_independent_xbar_zipcpu_axixbar_full_d1_ft0`
passes vacuity at radius 4 and reaches proof radius 41 at the two-minute
limit; its report SHA-256 is
`77fd9d4aa54769801281c9e83170233d2a08b476317cd873c08f6dd10be4dc9a`.
Hold artifact
`work/runs/20260904_c6_role_b_route_pending_b_hold_s0_d0_independent_xbar_zipcpu_axixbar_full_d1_ft0`
passes vacuity at radius 6 and reaches proof radius 39 at the same limit; its
report SHA-256 is
`9a3f2689cda1e5329abcde294f6c09f98cc65d8e96a9c891635d3edbe3d9eea2`.
Each has 306 focused assumptions, one target, no promoted assertion, the nine
shadow assumptions removed, arbitrary endpoint IDs, no fire, and no engine
or compile failure.  This says the exhaustive induction structure is sound
but each half still contains source-response admission history.

The hold step is now partitioned exactly on the full source B channel:

```systemverilog
a_endpoint_shadow_route_pending_b_hold_stalled: assert property (
  route_pending && !s_protocol_b_head && !route_hsk && s_b_stalled |=>
    !s_protocol_b_head);
a_endpoint_shadow_route_pending_b_hold_advancing: assert property (
  route_pending && !s_protocol_b_head && !route_hsk && !s_b_stalled |=>
    !s_protocol_b_head);
```

Here `s_b_stalled = s_rsp.b_valid && !s_req.b_ready`.  The branches are
disjoint and exhaustive.  The stalled branch can reuse the independently
proved full-channel B VALID/payload stability and source rank bookkeeping;
the advancing branch alone contains a newly admitted or consumed response.
The two assertions add no state or assumption.  Prove stalled first, then
advance; if advance is still hard, split only that branch into an empty
source B slot and a valid/accepted source B slot.

The first results justify that finer split but do not yet close the coarse
hold lemma.  In
`work/runs/20260904_c6_role_b_route_pending_b_hold_stalled_s0_d0_three_facts_xbar_zipcpu_axixbar_full_d1_ft0`,
the stalled branch proves in 24 seconds after promoting exactly the already
proved source-0 BVALID-stall, B-payload-stall, and
`x_b_has_completed_write` facts.  The 120-second vacuity job did not finish,
so Questa classifies the assertion as possibly vacuous; at depth one this is
plausible because a legal older B and a second route-pending AW generally
need more than one outstanding slot.  It is therefore **not counted closed**.
The run has 309 focused assumptions, one assertion, no fire, and formal report
SHA-256
`7ef8175332682830a7a83cfe2c57d0f89ea9ec437a843c75e82a28cfa918b860`.
Validate this branch nonvacuously at depth two before promoting it.

The corrected independent advancing run is
`work/runs/20260904_c6_role_b_route_pending_b_hold_advancing_s0_d0_independent_corrected_xbar_zipcpu_axixbar_full_d1_ft0`.
It promotes no assertion, removes the nine shadow assumptions, passes
vacuity at radius 6, and remains clean/inconclusive at radius 39 after 120
seconds.  Its focused model has 306 assumptions and one assertion; its formal
report SHA-256 is
`b4c9b4c2c8896bda05d27cbfd49e42ec2cb70496f22afb32100783b1139e56a5`.
An earlier directory with the same name but without `_corrected` stopped in
synthesis because an assumption-removal hierarchy was mistyped; it contains
no formal result and is not evidence.

The exact disjoint refinement now staged is:

```systemverilog
a_endpoint_shadow_route_pending_b_hold_empty: assert property (
  route_pending && !s_protocol_b_head && !route_hsk && !s_rsp.b_valid |=>
    !s_protocol_b_head);
a_endpoint_shadow_route_pending_b_hold_consumed: assert property (
  route_pending && !s_protocol_b_head && !route_hsk &&
    s_rsp.b_valid && s_req.b_ready |=>
      !s_protocol_b_head);
```

This is exhaustive because `!(b_valid && !b_ready)` is exactly
`!b_valid || (b_valid && b_ready)`.  The empty branch isolates admission of a
new response offer; the consumed branch isolates response retirement and rank
advancement.  Both use the existing role/endpoint state and add no RTL state,
assumption, cover, timer, or READY guarantee.  The two independent depth-one
s0/d0 gates are both clean but inconclusive.  The empty branch is nonvacuous
at radius 6 and reaches proof radius 39 in 120 seconds; its artifact is
`work/runs/20260904_c6_role_b_route_pending_b_hold_empty_s0_d0_independent_xbar_zipcpu_axixbar_full_d1_ft0`
and its formal report SHA-256 is
`3aa1699c7ed76e8f770281a5add25304a796f4a4c5106a21089ad49bcd1a1ac4`.
The consumed branch reaches radius 41 in the same budget but its vacuity check
does not finish, consistent with the expected lack of an older response at
outstanding depth one.  Its artifact is
`work/runs/20260904_c6_role_b_route_pending_b_hold_consumed_s0_d0_independent_xbar_zipcpu_axixbar_full_d1_ft0`
and its formal report SHA-256 is
`6b064ebbd600c2e23818748e9d4eeb31e242b4b0009d61ccbc8bcfed342983d6`.
Neither promotes an assertion; each removes the nine shadow assumptions and
has 306 focused assumptions, one assertion, no fire, no blackbox, and no
engine failure.  Do not split the empty admission edge into another Boolean
spelling.  The depth-two independent gate
`work/runs/20260904_c6_role_b_route_pending_b_hold_stalled_consumed_s0_d0_independent_xbar_zipcpu_axixbar_full_d2_ft0`
resolves the depth-one vacuity question: both stalled and consumed antecedents
are nonvacuous at radius 12.  They remain clean/inconclusive at proof radii 29
and 31 respectively after 120 seconds, with 306 assumptions, two assertions,
no promoted assertion, and the same nine shadow removals.  Its formal report
SHA-256 is
`5390005ba5223fecc2b6d13f61a8e950c57a88ac5703c7ecdd436c0c83b8b9b5`.
The D1 stalled conditional proof is therefore meaningful at a larger legal
profile, but no D2 protocol fact was assumed and neither branch is counted
closed.  The main effort now moves to the prepared protocol-W decomposition.

### Selected-packet matching architecture

The user's arbitrary-occurrence proposal is the intended architecture, with
one crucial offer-level refinement.  Formal traffic is already arbitrary, so
the FVIP does not inject a privileged request.  It observes one arbitrary
accepted request occurrence at one arbitrary DUT input/source, reuses the
endpoint's stable arbitrary ID, and filters it by one arbitrary decoded
destination.  This proves every occurrence by symbolic generalization while
avoiding a protocol/role tracker per physical source/destination combination.

For reads, the endpoint selects an arbitrary accepted AR, captures its LEN,
and initializes a same-ID predecessor rank.  Only an accepted same-ID RLAST
for an older transaction decrements that rank.  At rank zero, every matching
`RVALID` offer belongs to the selected request: the current beat index is
checked against the captured LEN, including exact RLAST, and the role layer
uses an arbitrary beat/payload bit to compare the input and routed output.
R has no WSTRB-like byte-lane legality rule; the arbitrary payload bit is for
data-integrity scaling.

Writes need a two-stage association because AXI4 has no WID and permits W to
precede AW.  The signed accepted-AW minus completed-W skew first pairs the
selected AW with its W packet in either arrival order.  The pair tracker keeps
only an opposite-side rank, the selected burst summaries, and an arbitrary
beat/WSTRB-lane sample.  The canonical arbitrary W payload-bit sample belongs
to the enclosing endpoint FVIP and is reused by the role layer.  For a DUT
input (`AXI_FVIP_MANAGER` polarity), the write-response tracker ranks completed same-ID
predecessors and can increment that rank as older selected-before-W writes
finish their data.  For a DUT output, it ranks all accepted same-ID AW
predecessors and separately asserts that any offered B has completed W data.
Only accepted matching B responses decrement a nonzero predecessor rank;
rank zero identifies the selected B response.  B has no LAST.

A sticky `matched` bit can be a useful availability/debug witness, and the
current sampled/available bits play that role for the arbitrary W beat.  It
cannot be the only correctness check.  If comparison occurs only on
`READY`/`LAST`, an owner can hold READY low forever or omit/misplace LAST and
avoid the check.  Consequently the canonical protocol path and replacement
endpoint-shadow role path check every owned `RVALID`, `WVALID`, or `BVALID`
offer immediately; handshake events update rank, beat, completion, and
optional bounded-progress state.  The retained legacy role-W assertions are
still handshake-only and must not be mistaken for the final architecture:
close the offer-level pair-shadow replacements before deleting their local
queues/ranks/samples.  The analogous legacy/new B implementations also
coexist during migration.  Safety remains unbounded wherever possible, while
bounded outstanding/skew and separately enabled stall/response deadlines
provide finite-capacity and liveness profiles without assuming that the
environment must eventually assert READY in the unbounded protocol mode.

### Live protocol pivot: W-before-AW under AW stall

The best next production target is output 1
`x_w_last_exact_after_w`.  Its old handshake form was already closeable; only
the later READY-independent `AWVALID` strengthening is new.  The current
zero-state decomposition defines
`after_w_live = pending_w && rank == 0 && aw_valid`, compares the stored W
beat count with live `AWLEN+1`, and partitions the late AW into a handshake
or a stalled offer.  The initial layer used four output-only helpers per
physical output: a handshake comparison, stalled-entry and stalled-hold
transitions, and their present-state stalled invariant.  Later layers align
the handshake with post-capture state, make all raw entry origins explicit,
and split selected-W creation by the prior AW-channel transition.  Entry plus
hold are intended to prove the invariant from reset; handshake plus that
invariant exactly cover the unchanged production antecedent.  No
implementation signal, progress bound, READY assumption, lane selector, or
new sequential state is used.

Both source-only compiles pass with zero errors/warnings and two intentionally
suppressed diagnostics at
`work/build/20260904_c6_after_w_stall_split_compile_xbar_protocol` and
`work/build/20260904_c6_after_w_stall_split_compile_xbar_full`.
The pair-tracker SHA-256 is
`37599e2ea1a5d2bc339368f73c5dd5ca1620e15ea20392db6aaf948dfce47643`.
The independent output-1 four-helper protocol gate is complete at
`work/runs/20260904_c6_protocol_m1_after_w_stall_split_independent_xbar_zipcpu_axixbar_protocol_d1_ft0`.
It uses the unbounded D1 protocol profile, promotes no assertion, and targets
only the four new helpers.  All four antecedents are formally reachable:
handshake, stalled hold, and stalled invariant at radius 12, and the original
entry spelling at radius 2.  The entry reachability result is weak because
`!after_w_stalled` includes ordinary idle/reset-adjacent cycles; the exact
entry-origin form below is the meaningful successor.  The stalled-hold helper
proves nonvacuously in 44 seconds.  Handshake, entry, and the derived stalled
invariant remain clean/inconclusive at radius 31 after 180 seconds.  Thus one
of the eight physical helper instances is closed, but neither strengthened
production property is yet reclassified.  The formal report SHA-256 is
`7f7ca1347149d25ac47f0eea8b1ca072d885d4a4201a87aabde75e2af7eb6c0b`.

Three transaction-level mutation gates validate the decomposition.  Case 24,
a completed W packet followed by a stalled late AW with the wrong length,
fires the new entry and stalled-invariant helpers plus the unchanged
`x_w_last_exact_after_w`; its report is
`work/runs/20260904_c6_after_w_stall_split_mutation24_transaction_mutations/24_bad_late_aw_completed_length/formal_verify.rpt`
with SHA-256
`84eed34cfaf33b1b0b7b3895e6f42560c30bbd65b73aa4354f3b71b0044bc08a`.
Case 18, legal W-before-AW traffic, fires no property and reaches its intended
sequence; its report is
`work/runs/20260904_c6_after_w_stall_split_mutations18_25_transaction_mutations/18_legal_w_before_aw/formal_verify.rpt`
with SHA-256
`3c2144b37da011c05185a4e7ec4476f52815211817f37d4be32ba6bd902d3968`.
Because the transaction harness instantiates the opposite pair-tracker
polarity, this is a broad legal regression rather than a direct reachability
proof for every new helper.  Case 25 keeps the late-AW length correct but
injects only an illegal saved WSTRB lane: all new length helpers and the
length production property pass, while only `x_wstrb_after_w` fires.  Its
report is
`work/runs/20260904_c6_after_w_stall_split_mutations18_25_transaction_mutations/25_bad_late_aw_completed_wstrb/formal_verify.rpt`
with SHA-256
`4675fb4f96da71a5c292bad05452dbd739571501ef0a7b0c5ef7aa31ea66857b`.
These gates demonstrate defect sensitivity and separation of packet length
from byte-lane legality; they are validation evidence, not DUT proofs.

The first same-cycle handshake composition did **not** close.  Artifact
`work/runs/20260904_c6_protocol_m1_after_w_handshake_live_composed_xbar_zipcpu_axixbar_protocol_d1_ft0`
promotes exactly output 1's independently proved `a_pair_completed_exact`
and `a_tracker_after_w_capture` helpers.  The target is nonvacuous at radius
12 but remains clean/inconclusive at radius 29 after 120 seconds, with no
fire, blackbox, or unintended assertion conversion.  Its formal report
SHA-256 is
`df490836f1e1992d817b61969dfb2b82f1b0539254bce86ad623c376ec0c0682`.
Those two facts describe the post-handshake registers, while the target asks
the engine to infer the preceding live-AW equality on the same edge.  Do not
repeat that backward-temporal cone unchanged; use an explicitly
post-capture-aligned, state-free bridge and validate its equivalence before
retrying the same-cycle partition.

The semantic audit found no reset, NBA-timing, or beat-count error.  Both
stored and live counts are one-based.  For `S = after_w_stalled`, the exact
non-reset transition from `!S` to `S` has only three RTL origins: selection of
a completed W packet before its AW; an existing `pending_w` rank of one
decremented by an AW handshake; or an existing rank-zero `pending_w` whose AW
was not valid in the preceding cycle.  A past-oriented checker must include
`$past(rstn)` so the first active sample is excluded.  The selected-W origin
is deliberately expressed as current actual entry plus `$past(select_w)`, not
as only the two legal rank-zero creation shapes.  This includes both
`skew==0 && !aw_hsk` and `skew==-1 && aw_hsk`, and also covers the raw
minimum-negative-skew truncation alias.  The latter violates the separately
checked output W-ahead bound, but omitting it here would make the partition
silently depend on promoting that bound.  With reset-reachable tracker phase
consistency and `aw_hsk = aw_valid && aw_ready`, these three categories are
exhaustive even before assuming a skew bound.

The exact-origin source compiles cleanly in protocol and full modes at
`work/build/20260904_c6_after_w_entry_origins_raw_complete_compile_xbar_protocol`
and
`work/build/20260904_c6_after_w_entry_origins_raw_complete_compile_xbar_full`.
The source hash used by its formal gate is
`c4cb2cd714ff9cf33df55807aaa34bdef42bd8375d25b116a57c79ec22bddcb9`.
A prior launch using an explicit two-shape selected-W predicate was cancelled
during formal compilation as soon as the raw truncation omission was found;
its partial `...entry_origins_independent...d2...` directory is not evidence.

The corrected independent output-1 gate is
`work/runs/20260904_c6_protocol_m1_after_w_entry_origins_raw_complete_independent_xbar_zipcpu_axixbar_protocol_d1_ft0`.
It promotes no assertion and directly measures **274/298/186** checkers and
**138/149/95** directives.  All three origin properties remain
clean/inconclusive after 180 seconds: first-AW offer and rank retirement reach
proof radius 41, while selected-W creation reaches radius 33.  The selected-W
actual-entry antecedent is nonvacuous at radius 12; the other two vacuity jobs
do not finish at D1, so they are neither called reachable nor unreachable.
Its formal report SHA-256 is
`79768a46601268a98d851e71ae82ad5a21a903a24d8683d8a5e4bd86484c119e`.
Do not repeat the same three-way independent cone unchanged.  If rank
retirement needs a reachability classification, use the legal depth-two
output-W-ahead profile; do not invent D1 traffic that violates its cap.

The corrected-source case-24 mutation at
`work/runs/20260904_c6_after_w_entry_origin_post_mutation24_transaction_mutations/24_bad_late_aw_completed_length`
fires the exact selected-W entry branch, broad entry, stalled invariant, and
unchanged production property, with every mutation score gate passing and no
inconclusive result.  Thus the meaningful selected-W antecedent both reaches
and detects its intended defect.  The formal report SHA-256 is
`8a4131af1c423499d4b44ace9b7fa9153ce5d4c1e6b2a3265b3e5cc6505185eb`.

The post-capture handshake bridge is now staged as
`after_w_live && aw_hsk |=> $past(after_w_match)`.  The enclosing FVIP's
sticky-reset-release contract makes this cycle-for-cycle equivalent to the
same-cycle handshake partition, while aligning the proof with the already
closed next-state capture facts.  It adds no FVIP state.  Current protocol and
full source compiles pass at
`work/build/20260904_c6_after_w_handshake_post_compile_xbar_protocol` and
`work/build/20260904_c6_after_w_handshake_post_compile_xbar_full`; the current
pair-tracker SHA-256 is
`d180bd79167f80c4adda67d2bc0c7dd247203d1bd6bd8c7febce66216113d252`.
In
`work/runs/20260904_c6_protocol_m1_after_w_handshake_post_composed_xbar_zipcpu_axixbar_protocol_d1_ft0`,
the bridge proves at 22 seconds and is nonvacuous at radius 12 after promoting
exactly output 1's independently proved `a_pair_completed_exact` and
`a_tracker_after_w_capture`.  It has no fire, blackbox, or unintended
conversion; total elapsed time is 25 seconds and the formal report SHA-256 is
`a74ec14add6d21f16bcb25cb21ef355fed8c19cb0b87ebfbf8ea424bc1cfbc83`.
This closes a second temporary output-1 helper.  A one-fact composition from
this proved bridge back to the immediate handshake partition did **not** help
the engine reverse time.  In
`work/runs/20260904_c6_protocol_m1_after_w_handshake_live_from_post_xbar_zipcpu_axixbar_protocol_d1_ft0`,
the immediate helper is nonvacuous at radius 12 but remains
clean/inconclusive at radius 31 after 120 seconds, with exactly the proved
post bridge converted and no other assertion premise.  Its report SHA-256 is
`674ffeb98fbdcfdaf57db7f3066f7684b190710f2d9bafcc8a13a0057a0e4cc0`.
The re-audit confirms logical equivalence under sticky reset, but this
temporal direction is solver-unhelpful.  Do not repeat it; remove the
redundant immediate helper after recording this experiment, retain the proved
post bridge as the handshake partition, and keep the immediate production
property itself unchanged until the stalled half is available for the final
composition.  Entry provenance remains the separate hard cone.

That pruning and the raw-complete origin-control theorem are now in source.
The control property proves independently and nonvacuously on both outputs in
22--24 seconds at radius 12 in
`work/runs/20260904_c6_protocol_after_w_entry_origin_control_independent_xbar_zipcpu_axixbar_protocol_d1_ft0`.
It promotes no assertion, has no fire or blackbox, and formally certifies that
the three data-origin branches exhaust every actual stalled entry.  Its
formal report SHA-256 is
`3193bd9cf64f6754041209e98e106982abd84894fd3aaf23721631cf5b4e32f5`.
The final pruned source compiles cleanly in protocol and full modes at
`work/build/20260904_c6_after_w_control_pruned_compile_xbar_protocol` and
`work/build/20260904_c6_after_w_control_pruned_compile_xbar_full` with pair
tracker SHA-256
`32378a675fb4d862804caf690a0bf3a9c5752a09c098a15b826049c63a292e82`.
The control lemma is pure tracker/selector bookkeeping; it relies on the
native selector phase contracts but on no DUT protocol assertion.  It does
not provide AWLEN/W-count provenance, so the three data branches remain open.

The symmetric output-0 post-capture bridge is also closed.  Artifact
`work/runs/20260904_c6_protocol_m0_after_w_handshake_post_composed_xbar_zipcpu_axixbar_protocol_d1_ft0`
promotes exactly output 0's independently proved `a_pair_completed_exact` and
`a_tracker_after_w_capture` facts.  The target proves in 22 seconds, is
nonvacuous at radius 12, and the whole job finishes in 25 seconds with no
fire, blackbox, engine failure, or unintended conversion.  Its formal report
SHA-256 is
`caf982fda366fc9c9ec88bf8e377f67f6d5d4fba742b9595f7912c578496e9c9`.
Together with the output-1 artifact above, the handshake half of the two
strengthened after-W production checks is now proved on both outputs.

The zero-state W-count capture
`select_w |=> watched_w_beats == $past(current_w_beats)` then proved
independently on both DUT outputs in 22 seconds, with both antecedents
nonvacuous at radius 10 and total elapsed time 23 seconds.  It promotes no
assertion and adds no sequential state.  The artifact is
`work/runs/20260904_c6_protocol_w_beats_capture_select_w_independent_xbar_zipcpu_axixbar_protocol_d1_ft0`;
its report SHA-256 is
`a28b07b6b3f0e531968b7c9907cae38cd0cf0620d7818d5c9cf40a3e248751a0`.
That run directly measured 286/298/186 checkers and 144/149/95 directives
because the then-current generic spelling also elaborated two unused
input-polarity capture instances.  The helper is now guarded by
`ifndef AXI_FVIP_MANAGER`, retaining the two proved output instances and deleting the
two irrelevant input instances.  A narrow output-only zero-skew association
leaf was added at the same time, so the current checker/directive totals stay
286/298/186 and 144/149/95 rather than growing.

The selected-W stalled-entry property is split by the prior AW-channel
history into three raw-disjoint and exhaustive cases:
`aw_valid && !aw_hsk` (stable offer), `aw_hsk` (consumed offer), and
`!aw_valid && !aw_hsk` (new offer).  Keeping `!aw_hsk` in the last predicate
preserves disjointness even before using the integrated handshake identity.
Their independent output-1 gate is
`work/runs/20260904_c6_protocol_m1_after_w_select_entry_channel_split_independent_xbar_zipcpu_axixbar_protocol_d1_ft0`.
All three are clean/inconclusive after 180 seconds with no promoted assertion,
fire, blackbox, launch failure, or unexpected termination.  Proof radii are
31 for stable, 37 for consumed, and 41 for new-AW.  Stable is nonvacuous at
radius 12; the other two vacuity jobs do not finish and therefore receive no
reachability classification.  Its report SHA-256 is
`01f97158ce0a229b423d39379438667334d3e268e5e8fecf913f218ff4e11b14`.
Do not repeat this independent split unchanged: naming the origins does not
supply the missing W-count/AWLEN correspondence.

Final-source mutations 18, 24, and 25 validate the split at
`work/runs/20260904_c6_after_w_entry_select_w_aw_offer_split_mutations18_24_25_transaction_mutations`.
All three intended sequences and READY-low states are reached, all guards
prove, and there is no inconclusive or unexpected fire.  Legal case 18 is
clean.  Wrong-length case 24 fires the new-AW branch and
`x_w_last_exact_after_w`, while the other two branches are vacuous; its report
SHA-256 is
`38dba89dea34b6066925d8b66e5c18780332476278ee2dbce4ec43bfe1a21c9a`.
WSTRB-only case 25 proves the new-AW branch and length production check and
fires only `x_wstrb_after_w`; its report SHA-256 is
`8b47211e929ddf37146fabedb8f5f9d20e5db334b916b0d9195d45a399bb6341`.
Legal case 18's
report SHA-256 is
`0f6e0028d51b5f120a4014e3f9d112260f706c757816f92aebbcf8b7f0b7c2a9`.
This confirms both defect sensitivity and separation from lane legality, but
does not turn the DUT inconclusives into proofs.

The next proof cut is
`a_w_last_exact_after_w_select_w_stalled_zero`, the irreducible port-level
association at `select_w && aw_valid && !aw_hsk && skew == 0`.  It is narrower
than the open production offer check.  If it closes, the already proved
W-count capture, output AW payload-stall stability, and output completed-W
skew bound can transport it forward into the stable-entry branch without a
new register or a READY-progress premise.  Protocol and full source-only
compiles pass with zero errors/warnings and two expected suppressed
diagnostics at
`work/build/20260904_c6_after_w_zero_leaf_compile_xbar_protocol` and
`work/build/20260904_c6_after_w_zero_leaf_compile_xbar_full`.  The current
pair-tracker SHA-256 is
`9f849b56703148e74995f82b6cbfaa65c9cc5300c21064ee555be51289d55670`.
Its independent output-1 formal gate is
`work/runs/20260904_c6_protocol_m1_after_w_select_stalled_zero_independent_xbar_zipcpu_axixbar_protocol_d1_ft0`.
The leaf is nonvacuous at radius 10 but remains clean/inconclusive at proof
radius 31 after 180 seconds, with no promoted assertion, fire, blackbox,
launch failure, or unexpected termination.  Its report SHA-256 is
`adc2c215560b64902bd29a937b4c74cf86be9b5f39dd2b416b4c202a272ff438`.
This isolates the hard part: tracker capture and transition control have
closed, while correspondence between the output W packet and live output AW
still requires a cross-port packet-provenance cut.  Do not retry the same
single-target independent cone unchanged.

This remaining work is not evidence that complete crossbar proof is
impossible.  The fixed bounded-capacity 2x2 safety model is finite-state; the
current failures are time-limited induction failures, not counterexamples.
Unconditional progress is a different claim and is intentionally impossible
when an environment may withhold READY or a response forever.  Keep safety
unbounded and READY-independent where possible, and enable the explicit
stall/response-time contract only for the separately reported bounded
progress profile.  A proof for arbitrary parameter values would additionally
need parameter induction or per-profile sign-off; the present target is the
declared finite profile, not an unbounded family of differently sized RTL
instances.

The first cross-port provenance retry deliberately reuses the role layer's
single arbitrary source, destination, beat, and payload-bit domains rather
than adding a per-port scoreboard.  The fixed source-0/destination-0 artifact
is
`work/runs/20260904_c6_role_w_pair_shadow_live_s0_d0_composed_xbar_zipcpu_axixbar_full_d1_ft0`.
It targets the scalar pair-shadow live-offer occurrence, integrity, prefix
handoff, and completion-order helpers.  Exactly eleven independently proved
facts are promoted: both input/output pair-rank facts, four route facts, both
pair-shadow state facts, and the selected-output observer cut.  All are
port/FVIP-state facts; no DUT hierarchy, progress, or READY premise is used.
The run directly confirms the current full model at 332/315/220 checkers and
190/166/129 directives with no blackbox.  Offer occurrence, offer integrity,
and completion order are nonvacuous at radius 10 but remain clean/inconclusive
at proof radii 33, 25, and 37 after 180 seconds.  Prefix handoff proves in
109 seconds, but its vacuity check establishes that this exact fixed D1
partition antecedent is unreachable, so it is not counted as a helper
closure.  The report SHA-256 is
`70085d9ccfb2739a281e84b094c630dd5c46e4515d812d2558f232fee8120778`.
Do not repeat this live group unchanged.  The stored sample/packet group is
the next diagnostic; if it also stays open, isolate the source-to-output
packet occurrence/order relation before retrying payload equality.

The stored sample/packet diagnostic has now finished, and it also does not
close.  Artifact
`work/runs/20260904_c6_role_w_pair_shadow_stored_s0_d0_composed_xbar_zipcpu_axixbar_full_d1_ft0`
targets `a_pair_shadow_w_packet_occurrence`,
`a_pair_shadow_w_packet_order`, `a_pair_shadow_w_sample_integrity`, and
`a_pair_shadow_w_sample_occurrence`.  It promotes the same eleven
independently proved port/FVIP facts as the live group.  All four targets are
nonvacuous at radius 12, clean, and inconclusive after 180 seconds; their
proof radii are respectively 31, 37, 25, and 35.  There is no fired
assertion, blackbox, compile failure, launch failure, or unintended premise.
The exact model remains 332/315/220 assertion/assumption/cover checkers and
190/166/129 directives.  The formal report SHA-256 is
`a14743ac6c7a42103e7ce012c64a7dfe4fc0c75463d0ca15186889a4521b36c0`.
Neither the live nor stored role-W cone should be repeated unchanged.  Both
now point to the same missing induction boundary: establish source-to-output
packet occurrence and ordering before asking the solver to carry beat or
payload equality.  This is the final formal run of this session; no further
proof was launched before the refactor handoff was frozen.
