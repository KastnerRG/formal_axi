# AXI Formal VIP: Feasibility and Plan

## Verdict

The project is feasible in stages. An AXI4 Valid/Ready protocol checker plus reusable end-to-end checkers for transparent FIFOs, register slices, and small crossbars is a realistic first product. A single minimal FVIP cannot, by itself, prove arbitrary DMA/memory functionality, full AXI5, unbounded forward progress, or every large crossbar without design-aware lemmas.

| Goal | Feasibility | Condition |
|---|---|---|
| AXI4 intra-channel compliance | High | Audit against AXI4 Issue H.c, then close missing rules |
| AXI4 cross-channel accounting | High | Explicit outstanding bound; normal transactions first |
| Transparent FIFO/register correctness | High | Prove no creation/loss/duplication/reordering and payload preservation |
| 2x2 crossbar | Medium-high | Address/ID mapping contract and scenario splitting |
| 6x6 crossbar | Medium | Must pass a scaling gate; generic structural invariants may be needed |
| DMA functional correctness | Low as generic VIP | Requires a DMA-specific register, memory, and transfer reference model |
| Full AXI5 | Low near-term | Separate profiles are required for credited transport, Resource Planes, atomics, chunking, tags, and other options |

Planning estimate for one experienced formal engineer: 6-10 weeks through the first FIFO proof, then 4-10 weeks for 2x2 and scaling work. DMA and full AXI5 are separate follow-on efforts.

## Fresh-session handoff

**Workspace:** `/home/a.gnaneswaran.251/scratch/formal_veri/formal_axi`

**Read first:** `docs/plan.md`, `docs/prompt.md`, `per_role_fvip/fifo/`, `axi_sva/our/axi_fvip.sv`, `qverify/flist.f`, and the C0-C5 testbenches. Preserve unrelated or untracked user files.

**Current state:**

- `axi4.txt` is the extracted AXI4 Issue H.c source. The official PDF is `papers/IHI0022H_c_amba_axi_protocol_spec.pdf`; Issue D is archived as `axi4_issue_d.txt`.
- `docs/prompt.md`, `docs/plan.md`, and `papers/` are tracked. `axi4.txt` and `axi4_issue_d.txt` are ignored by the `*.txt` rule; do not assume specification-text changes appear in `git status`.
- The QVerify file list compiles and instantiates the split FIFO role sources and cross-channel transaction checker. Historical 121-property results remain baseline-only; current C5 artifacts are the sign-off evidence.
- `per_role_fvip/fifo/` uses selected occurrences and bounded ranks without a uniqueness assumption. Its exact oracle and abstraction have matching mutation scores.

**Tool environment:**

- Questa Static Verification `2023.2_2` is installed at `/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin/qverify`.
- Source `~/bashrc-new` in an interactive Bash shell for license variables, then enter the repository `shell.nix` environment for `libXau` and `csh`. Never print license-server values.
- Reproducible eight-engine runs, parsed reports, manifests, and mutation suites are available under `work/runs/`; C0-C5 status is recorded in `docs/c0_c5_execution.md`.
- Run new experiments in new directories under `work/runs/`; `make clean`
  intentionally removes only disposable `work/build/` output.

**Default MVP configuration unless overridden:** AXI4 Full Issue H.c, Valid/Ready normal transactions, exclusives and ATOP disabled, `MAX_OUTSTANDING=4`, `MAX_AW_AHEAD=4`, `MAX_W_AHEAD=4`, maximum burst length `8`, `MAX_STALL=8`, `MAX_RESPONSE_DELAY=16`, and `MAX_WRITE_DATA_DELAY=16`. Report capacity and progress bounds explicitly; they define the selected bounded-AXI profile and are not architectural AXI limits.

**Next action:** close the remaining C6 protocol and full-role solver targets
at outstanding depths 1, 2, and 4. The implementation and scenario coverage
are complete; do not weaken the standalone endpoint/role boundary to obtain
closure. Exact current evidence is in `docs/c6_execution.md`.

## Immediate architecture refactor before C6

**Status: completed 2026-09-01.** The endpoint/role split, public PULP-typed
view, symmetric bounded-progress policies, FIFO conservation proof, and
validation suites described below are implemented. Closure evidence is under
`work/runs/20260901_arch_link_04`, `work/runs/20260901_arch_txn_mut_02`,
`work/runs/20260901_arch_fifo_mut_02`, and
`work/runs/20260901_arch_fifo_formal_05`.

The 2026-09-01 readability follow-up consolidated the five channel modules
into the specification-ordered `axi_channel_fvip`, moved concurrent properties
out of the package, and adopted module-level default clock/reset contexts.
Regression evidence is under `work/runs/20260901_unified_channel_link_mut_02`,
`work/runs/20260901_unified_channel_txn_mut_01`,
`work/runs/20260901_unified_channel_fifo_mut_01`, and
`work/runs/20260901_unified_channel_fifo_formal_01`.

The next implementation step is a clean separation between endpoint protocol
compliance and cross-interface DUT functionality.

### 1. Freeze the standalone bounded-AXI contract

`axi_fvip` must be usable by itself at any AXI endpoint and completely prove
the selected bounded protocol profile, without knowing whether the DUT is a
FIFO, crossbar, RAM, or another role. Its assertions and assumptions are
chosen only from signal ownership:

- Assume AXI legality and bounded progress for signals driven by the formal
  environment.
- Assert AXI legality and bounded progress for signals driven by the DUT.
- Never assume that DUT-driven traffic is correct merely because the DUT is
  acting as an AXI manager or subordinate.

The standalone checker must cover link safety and transaction safety: reset
and VALID behavior, payload stability under stall, legal encodings and burst
geometry, WSTRB, exact WLAST/RLAST, IDs, AW/W association, AR-to-R and
completed-write-to-B accounting, no orphan/duplicate/early/wrong-ID response,
and same-ID ordering. It must also implement the declared bounded-progress
profile symmetrically by ownership:

- `MAX_STALL`: bound READY latency after VALID. Assume the bound when READY is
  environment-driven; assert it when READY is DUT-driven.
- `MAX_RESPONSE_DELAY`: bound subordinate response progress from an accepted
  AR to every required R beat and from a completed AW+W request to B. Assume
  it for environment-driven responses; assert it for DUT-driven responses.
  Define it per required response beat, so a first RVALID alone cannot satisfy
  completion of a burst.
- Decide and document whether bounded write completion also needs a distinct
  `MAX_WRITE_DATA_DELAY` from accepted AW to the required W beats. The existing
  `MAX_AW_AHEAD`/`MAX_W_AHEAD` parameters bound capacity/skew, not elapsed time.
- Keep outstanding, channel-skew, and burst-length limits as explicit profile
  parameters. `MAX_OUTSTANDING` bounds state; it does not itself force
  completion.

The resulting claim is "AXI4 normal-transaction safety plus the declared
bounded capacity/progress profile," not unrestricted liveness, universal AXI,
or full AXI5. The implementation now satisfies this target. In a role
aggregate, the outer-environment delay and the two role traversals are composed
explicitly for the opposite DUT-owned endpoint.

### 2. Put functionality in per-role FVIPs

Each role checker owns one standalone `axi_fvip` instance per exposed AXI
endpoint and proves relations between those independently legal endpoints.
AXI compliance alone intentionally permits a DUT to fabricate a legal
response after dropping an input request, issue an unrelated but legal output
request, return legal `SLVERR` responses, route to the wrong port, or change
data while obeying AXI signal rules. Those are role failures, not generic AXI
violations. Bounded failure to accept or respond remains an endpoint-FVIP
failure.

For a FIFO, select an arbitrary accepted input occurrence and prove that
exactly one matching transaction appears at the output in FIFO order, with the
required metadata/payload and correctly returned response. Add inverse
conservation obligations so output injection, duplication, and unrelated
transactions cannot escape a proof that checks only input-to-output
appearance.

For a crossbar, select an arbitrary input port, ID, destination, occurrence,
and payload beat/bit. Prove the request appears exactly once at the decoded
output with the specified ID transform, write ownership is retained through
WLAST, and the response returns exactly once to the originating input with the
ID restored. Also prove no wrong-output copy, phantom/duplicate transaction,
or ordering violation under contention and define unmapped-address behavior.

The selector is an unconstrained, stable proof choice. Do not use
selector-dependent assumptions as the only legality constraint: every
occurrence must remain eligible, so proving the selected occurrence is a
universal argument.

### 3. Reuse PULP AXI types and expose a public tracker view

All vendor wrappers already normalize their ports to PULP `AXI_BUS`, so the
common checker boundary should become `AXI_BUS.Monitor axi`; this does not
restrict verification to PULP DUTs. Use the existing macros in
`pulp/axi/include/axi/typedef.svh` to define packed AW, W, B, AR, R, request,
and response types, and use `assign.svh` helpers where they reduce wiring.
PULP `req_t`/`resp_t` describe live wires; they do not replace formal lifecycle
state.

Add an adjacent parameterized interface, tentatively
`axi_fvip_txn_view_if`, with producer/consumer modports. It is the stable
public API from each endpoint tracker to its enclosing role checker and should
carry:

- selected, pending, completed, rank, and outstanding state;
- the selected AR/AW packed channel record;
- an arbitrary selected W/R beat index and payload/strb/resp sample;
- response progress and completion observations.

Ordinary output ports or direct hierarchical dot notation are legal, but role
proofs must not depend on undocumented internal names. If hierarchy is used,
put the exposed signals under a deliberate stable `view` hierarchy.
Prefer the transaction-view interface because it keeps the boundary explicit
while retaining convenient dot notation in the role checker.

Capture complete metadata only for the one selected AR/AW transaction. Do not
store every beat of every outstanding burst: one arbitrary selected beat, and
optionally one arbitrary lane/bit, proves payload preservation universally.
Tracker/view logic not referenced in standalone mode should normally disappear
through formal cone-of-influence reduction; avoid `keep` attributes or covers
that retain it. An optional `ENABLE_ROLE_VIEW` is possible, but an always-
present stable API is simpler unless elaboration measurements show a cost.

### 4. Ordered implementation steps

1. [x] Specify exact ownership and timing semantics for `MAX_STALL`, per-beat
   `MAX_RESPONSE_DELAY`, and any `MAX_WRITE_DATA_DELAY`.
2. [x] Add the PULP-typed `axi_fvip_txn_view_if` interface.
3. [x] Refactor `axi_fvip` to accept `AXI_BUS.Monitor`, construct the PULP packed
   channel views, expose read/write selected-transaction views, and keep thin
   manager/subordinate wrappers only where useful for polarity.
4. [x] Move generic bounded endpoint behavior into `axi_fvip` and remove the
   obsolete FIFO-specific response environment.
5. [x] Create a clear `per_role_fvip` structure. The FIFO aggregate instantiates
   the input/output endpoint FVIPs and consumes their public tracker views;
   the crossbar aggregate will later do the same for endpoint arrays.
6. [x] Rewrite the FIFO proof around selected transactions plus forward and
   inverse conservation, uniqueness, order, payload, and response properties.
7. [x] Re-run the endpoint and FIFO mutation suites before beginning C6.

### 5. Refactor validation gate

- Standalone `axi_fvip` compiles/proves without role modules or DUT-internal
  references.
- Protocol/link/transaction/bounded-progress mutations fail at the appropriate
  endpoint and both manager/subordinate polarity directions are exercised.
- Role-only mutations can remain AXI-clean: a fabricated legal response,
  unrelated legal output transaction, wrong route, or legal data substitution
  must not be mislabeled as an AXI failure.
- The FIFO role suite catches drop, injection, duplication, corruption,
  reordering, and response misassociation, including cases that remain clean
  in the standalone AXI checkers.
- Required selector/progress covers are reachable, proofs close under the
  declared bounds, and there are no unexplained inconclusive or vacuous
  results.
- Exact scoreboards stay validation-only under `fvip_validation/`.

This gate is closed. C6 should reuse the same public transaction view for the
2x2 crossbar role proof.

## Findings that change the proposed design

- `axi4.txt` is now extracted from ARM IHI 0022H.c (2021), the final combined specification containing AXI4; the previous Issue D text is preserved as `axi4_issue_d.txt`. The current AXI5 specification is Issue L (2025). Issue L permits credited transport and Resource Planes, so the present five-channel Valid/Ready architecture is not a full AXI5 checker.
- The custom FVIP now includes both intra-channel rules and optional bounded cross-channel transaction accounting. Historical FIFO results showing 121 proofs still do **not** prove transaction preservation; use the current C5 artifacts.
- AXI4 contains three logical transaction relations, not three identical FIFOs. R responses are ordered per ID and may interleave across IDs; W bursts correspond to AW order but may arrive before AW; B responses follow completed AW+W transactions and are ordered per ID.
- Counter-free two-value ordering is not complete for repeated payloads. Use a nondeterministically selected transaction occurrence plus a bounded rank counter, and prove continuous conservation separately. This is constant-state smart tracking, not a shadow FIFO.
- No counter must count transactions since reset. Bound AR/R and completed-write/B ranks by the configured outstanding limit, AW/W matching by configured positive and negative channel skew, and burst progress by the 256-beat AXI limit.
- A response-cycle limit is a performance/fairness contract, not AXI protocol compliance. Keep it in a separately enabled bounded-progress profile.
- Questa is installed at `/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin/qverify`. Sourcing `~/bashrc-new` interactively supplies the license environment; `shell.nix` supplies `libXau` and `csh`. Both version and formal feature-license checks succeed, and `tools/run_formal.sh` provides the reproducible baseline.

## Target architecture

1. **Link checker:** one `axi_channel_fvip` consumes the complete AXI interface and orders reset, handshake, stability, encoding, burst, and sideband properties by specification rule. It knows nothing about DUT function.
2. **Transaction checker:** implements bounded smart trackers, joins AW with W, accounts for B, and tracks each ordering domain `(source port, ID, destination, Resource Plane when applicable)`.
3. **Role adapter:** defines the DUT function: identity for FIFO/register, route and ID transform for crossbar, width mapping for converters, memory semantics for RAM, and programmed-copy semantics for DMA.
4. **Profiles:** AXI4 normal, exclusive, AXI5-ATOP, AXI5 Valid/Ready, and later AXI5 credited transport. Disabled features are constrained explicitly and reported as not applicable.

| Logical relation | Abstraction | Counter bound |
|---|---|---|
| `AR -> R` | Select one AR occurrence; rank earlier ARs in the same ordering domain; consume on `RLAST` | Maximum outstanding reads in that domain |
| `AW <-> W` | Two-sided tracker using signed `AW count - completed-W-burst count`; capture whichever member arrives first | Maximum configured AW-ahead/W-ahead skew |
| Completed `(AW+W) -> B` | Join corresponding AW/W occurrences, then rank completed writes per response-ordering domain | Maximum outstanding completed writes in that domain |

Each tracker stores only a selected packet summary, bounded rank, and status bits. Continuous occupancy/outstanding counters prove no orphan output, overflow, or extra response. Use a depth-2/4 scoreboard as the executable oracle, then accept the abstraction only when it detects the same mutation set. Do not use lifetime transaction indices or assume unique real payloads.

Model an IP's expected output as `F(G_role(x))`: `F` is the AXI protocol envelope—association, ordering, IDs, beat counts, completion, and response timing—while `G_role` is the role-specific payload transformation. The MVP proves `F`; later FIFO, crossbar, RAM, converter, and DMA testbenches provide and verify `G_role` using the same occurrence-tracking infrastructure.

## Checkpoints

### C0 - Reproducible tool baseline

- [x] Configure the Siemens license, formal/Questa `PATH`, and Nix runtime in one checked script.
- [x] Re-run compile, proof, waveform export, and VCD inspection in a new output directory.
- [x] Pin tool version, DUT commit, parameters, assumptions, property statuses, time, and peak memory per run.

**Gate:** a clean FIFO baseline is reproducible; every warning is classified and no property is silently skipped.

### C1 - Freeze the supported protocol profile

- [x] Install the official AXI4 Issue H.c PDF/text and archive the previous Issue D text.
- [x] Re-audit the rule coverage against AXI4 Issue H.c and add a separate AXI5 Issue L inventory.
- [x] Add an `our_status` column to the coverage CSVs: implemented, missing, partial, not applicable, or policy-only.
- [x] For MVP, select AXI4 Valid/Ready normal transactions; constrain exclusives and `AWATOP` off until their profiles exist.
- [x] Configure and classify maximum outstanding reads/writes, maximum AW-ahead and W-ahead skew, and optional response-time bounds.
- [x] Label every property as interface guarantee, environment assumption, configuration assumption, or bounded-progress policy.

**Gate:** every enabled signal and assertion maps to a specification revision and rule; no AXI5 claim is made for AXI4+ATOP.

### C2 - Close and validate the link checker

- [x] Implement the missing dependency, WSTRB, beat-count/WLAST/RLAST, response, ID, exclusive, and ordering rules appropriate to the MVP.
- [x] Move `MAX_STALL` out of protocol compliance and make it an opt-in typed FVIP policy parameter.
- [x] Inject deliberately bad Manager and Subordinate agents to validate assume/assert polarity.
- [x] Audit every enabled assertion trigger: use conclusive vacuity results by
  default, add a cover only when vacuity cannot decide reachability, and retain
  explicit scenario covers such as legal W-before-AW behavior.

**Gate:** no unexpected failures, no unexplained vacuous proofs, and all seeded protocol mutations are detected.

### C3 - Build the transaction oracle

- [x] Implement a depth-2/4 bounded reference model for AR/R, AW/W association in either arrival order, and completed-write/B accounting.
- [x] Check no phantom response, no drop, no duplicate, per-ID ordering, correct beat count, correct ID, and bounded progress when enabled.
- [x] Exercise duplicate payloads, repeated IDs, W before AW, backpressure, different-ID R interleaving, and maximum outstanding occupancy.

**Gate:** all legal covers fire and curated drop/duplicate/corrupt/reorder/early-response/deadlock mutations fail the intended property.

### C4 - Validate the symbolic abstraction

- [x] Implement the common smart tracker: nondeterministically select an input occurrence, capture its packet summary, and track its bounded relative rank.
- [x] For AR/R, count only the selected ordering domain and consume transactions on `RLAST`.
- [x] For AW/W, use a bounded signed-skew, two-sided tracker that captures whichever member arrives first; do not use an absolute nth-since-reset counter.
- [x] Join the matched AW/W pair, then use a per-domain smart tracker for B; keep continuous outstanding counters to reject orphan or extra responses.
- [x] Do not use `s_unique_in` on normal traffic. Prove creation, duplication, loss, ordering, payload integrity, and progress separately.
- [x] Compare the abstract checker with the bounded oracle on the same exhaustive small models and mutations.
- [x] Compile and instantiate the FIFO role FVIP; add covers proving the watched transaction can be selected and completed.

**Gate:** the abstraction matches the oracle's mutation score and has no new false failures or vacuity.

### C5 - First DUT: AXI FIFO

- [x] Prove ZIPCPU `sfifo` at depths 2, 4, 8, and 32, including simultaneous push/pop and fall-through configurations that exist, under the declared bounded C5 environment.
- [x] Prove all five channel payloads independently, then enable the cross-channel transaction checker.
- [x] Repeat the independent-channel proof on PULP and Taxi FIFO wrappers to demonstrate vendor reuse.

**Gate:** full proofs and required covers for at least three implementations; failures are classified as DUT, wrapper, property, or assumption bugs.

**Execution status (2026-08-31):** C0-C5 are implemented and exercised. C5
closes under an explicitly bounded environment: zero consumer stall, one
outstanding transaction, and four-cycle subordinate response latency. ZIPCPU
depth 32 closes in both registered and fall-through modes, and the combined
transaction proof closes on ZIPCPU and PULP with eight-beat bursts and on Taxi
with its declared single-beat reuse profile. Separate relaxed runs reach the
required backpressure, full-queue, rank, and simultaneous-operation covers.
Unrestricted or one-cycle-stall depth-32 proof is not claimed. Exact commands,
scores, classifications, and artifact directories are in
`docs/c0_c5_execution.md`.

### C6 - 2x2 crossbar

- [x] Formalize address decode, source-port prefix/removal, output ID width, default/error destination, and same-ID ordering.
- [x] Track an arbitrary source port, ID, destination, and request occurrence; split read, write-route, and response-return scenarios.
- [x] Cover simultaneous contention, independent destinations, decode errors, backpressure, and different-ID reordering.

**Gate:** full proof at outstanding depths 1, 2, and 4 with no design-specific internal signal references.

**Execution status (2026-09-03):** the 2x2 aggregate and role proof are
implemented with no DUT-internal references. Protocol level contains all four
complete endpoint transaction FVIPs and elaborates no role instance; full
level consumes only their public views. ZIPCPU wrapper and local-error-path
bugs found during C6 were fixed directly in the wrapper/core. Depths 1, 2,
and 4 have zero fired assertions in the recorded runs, and the required
scenario covers are reachable. A separate environment-owned READY policy now
enables bounded protocol/role progress without imposing a false independent
WREADY deadline on the DUT. The role tracks one transaction on one arbitrary
input and reuses endpoint selector, rank, skew, and input/output occupancy
state rather than duplicating counters. The gate remains open because
time-limited runs retain inconclusive assertions; see `docs/c6_execution.md`
for exact counts, commands, and classifications.

### C7 - Scaling gate

- [ ] Sweep 2x2, 3x3, then 6x6 across ID widths and outstanding limits; record proof depth, time, and memory.
- [ ] If closure fails, add reusable structural lemmas: one-hot grant, route lock through WLAST, outstanding-credit conservation, and response-route consistency.
- [ ] Set CI and investigation resource budgets before claiming scalability.

**Gate:** 6x6 closes within the agreed budget. Otherwise report it as inconclusive/bounded; do not weaken assumptions merely to obtain a proof.

### C8 - Role expansion and bug handoff

- [ ] Add role adapters in increasing semantic complexity: register, demux, width converter, protocol bridge, RAM, firewall, DMA.
- [ ] For DMA, model control registers, source/destination memories, lengths, errors, and overlap policy; protocol-only proof is not a DMA functional proof.
- [ ] For each genuine failure, minimize the formal trace and reproduce it in a deterministic SV test before preparing an upstream report/PR.

**Gate:** each supported wrapper has a declared contract, full/bounded status, covers, resource record, and reproducible counterexample for every failure.

## Explicit scope contracts

- **Response time:** configure a constant maximum response delay. Classify it as a bounded-progress contract, not base AXI compliance.
- **AW/W skew:** configure constant `MAX_AW_AHEAD` and `MAX_W_AHEAD` bounds for the two-sided tracker.
- **Protocol first:** the generic FVIP proves `F`; role-specific testbenches later prove payload function `G_role` without changing the tracking core.

## Remaining feasibility risks

- **No IP-specific invariants:** this cannot be guaranteed for a 6x6 crossbar or deep proprietary design. Keep invariants generic where possible and isolate any implementation hooks in adapters.
- **Full AXI5 in the current interface:** credited channels, Resource Planes, and many optional AXI5 signals are absent. AXI5 must be a separate, feature-profiled milestone.
- **Every vendor IP:** encrypted/non-synthesizable models, unsupported language mixes, black boxes, or missing reset semantics can make formal proof impossible even when simulation works.
- **Automatic simple SV reproducer:** traces depending on X initialization, internal cut points, or formal-only fairness may not have a faithful short simulation reproducer.

## Sign-off criteria

- No unexplained fired, inconclusive, vacuous, or unsupported property.
- Every assumption has a cover or over-constraint review; feature-disabled rules are not counted as proofs.
- Every counter has a proven configuration bound; no proof depends on an absolute transaction index that can wrap.
- Mutation suite detects phantom, dropped, duplicated, corrupted, reordered, misrouted, wrong-ID, wrong-LAST, early-B, and deadlock faults.
- Full proof is distinguished from bounded proof; protocol compliance is distinguished from performance and functional correctness.
- Results are reproducible from a pinned command and include a reviewable VCD for failures.

## Primary sources

- [Arm AMBA AXI and ACE Protocol Specification, Issue H.c (AXI4 baseline)](https://documentation-service.arm.com/static/602a9df190ee6824a1e02b98)
- [Arm AMBA AXI Protocol Specification, Issue L (current AXI5)](https://documentation-service.arm.com/static/68b03beb01ae952d9559f9eb)
- [Darbari and Singleton, *Industrial Strength Formal Using Abstractions*](https://arxiv.org/abs/1606.02347)
- [Abdulla et al., data-independent queue observers](https://user.it.uu.se/~bengt/Papers/Full/tacas13.pdf)
- [PULP AXI crossbar configuration and ordering](https://github.com/pulp-platform/axi/blob/master/doc/axi_xbar.md)
- [Siemens Questa Verify Property](https://eda.sw.siemens.com/en-US/ic/questa-one/formal-verification/verify-property/)
- [ZIPCPU `wb2axip` status; public full-AXI property set is explicitly partial](https://github.com/ZipCPU/wb2axip#formal-verification)
