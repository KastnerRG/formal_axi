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

## Findings that change the proposed design

- `axi4.txt` is now extracted from ARM IHI 0022H.c (2021), the final combined specification containing AXI4; the previous Issue D text is preserved as `axi4_issue_d.txt`. The current AXI5 specification is Issue L (2025). Issue L permits credited transport and Resource Planes, so the present five-channel Valid/Ready architecture is not a full AXI5 checker.
- The custom FVIP currently checks only intra-channel behavior. `fifo_fvip.sv` is neither compiled nor instantiated. Historical FIFO results showing 121 proofs therefore do **not** prove transaction preservation.
- AXI4 contains three logical transaction relations, not three identical FIFOs. R responses are ordered per ID and may interleave across IDs; W bursts correspond to AW order but may arrive before AW; B responses follow completed AW+W transactions and are ordered per ID.
- Counter-free two-value ordering is not complete for repeated payloads. Use a nondeterministically selected transaction occurrence plus a bounded rank counter, and prove continuous conservation separately. This is constant-state smart tracking, not a shadow FIFO.
- No counter must count transactions since reset. Bound AR/R and completed-write/B ranks by the configured outstanding limit, AW/W matching by configured positive and negative channel skew, and burst progress by the 256-beat AXI limit.
- A response-cycle limit is a performance/fairness contract, not AXI protocol compliance. Keep it in a separately enabled bounded-progress profile.
- Questa is installed at `/tools/Siemens/2023.2/questa_static_formal/linux_x86_64/bin/qverify`. Sourcing `~/bashrc-new` interactively supplies `LM_LICENSE_FILE`, `SALT_LICENSE_SERVER`, and `MGLS_LICENSE_FILE`; `nix-shell` supplies `libXau`, and `qverify -version` succeeds. A clean proof run must still confirm feature-license checkout. Existing reports and exported VCD counterexamples are readable.

## Target architecture

1. **Link checker:** per-channel reset, handshake, stability, encoding, burst, and sideband rules. It knows nothing about DUT function.
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

- [ ] Configure the Siemens license, formal/Questa `PATH`, and Nix runtime in one checked script.
- [ ] Re-run compile, proof, waveform export, and VCD inspection in a new output directory.
- [ ] Pin tool version, DUT commit, parameters, assumptions, property statuses, time, and peak memory per run.

**Gate:** a clean FIFO baseline is reproducible; every warning is classified and no property is silently skipped.

### C1 - Freeze the supported protocol profile

- [x] Install the official AXI4 Issue H.c PDF/text and archive the previous Issue D text.
- [ ] Re-audit the rule coverage against AXI4 Issue H.c and add a separate AXI5 Issue L inventory.
- [ ] Add an `our_status` column to the coverage CSVs: implemented, missing, partial, not applicable, or policy-only.
- [ ] For MVP, select AXI4 Valid/Ready normal transactions; constrain exclusives and `AWATOP` off until their profiles exist.
- [ ] Configure and classify maximum outstanding reads/writes, maximum AW-ahead and W-ahead skew, and optional response-time bounds.
- [ ] Label every property as interface guarantee, environment assumption, configuration assumption, or bounded-progress policy.

**Gate:** every enabled signal and assertion maps to a specification revision and rule; no AXI5 claim is made for AXI4+ATOP.

### C2 - Close and validate the link checker

- [ ] Implement the missing dependency, WSTRB, beat-count/WLAST/RLAST, response, ID, exclusive, and ordering rules appropriate to the MVP.
- [ ] Move `AXI_MAX_STALL_*` out of protocol compliance and make it an opt-in policy.
- [ ] Inject deliberately bad Manager and Subordinate agents to validate assume/assert polarity.
- [ ] Add reachability covers for every assertion antecedent and for legal W-before-AW behavior.

**Gate:** no unexpected failures, no unexplained vacuous proofs, and all seeded protocol mutations are detected.

### C3 - Build the transaction oracle

- [ ] Implement a depth-2/4 bounded reference model for AR/R, AW/W association in either arrival order, and completed-write/B accounting.
- [ ] Check no phantom response, no drop, no duplicate, per-ID ordering, correct beat count, correct ID, and bounded progress when enabled.
- [ ] Exercise duplicate payloads, repeated IDs, W before AW, backpressure, different-ID R interleaving, and maximum outstanding occupancy.

**Gate:** all legal covers fire and curated drop/duplicate/corrupt/reorder/early-response/deadlock mutations fail the intended property.

### C4 - Validate the symbolic abstraction

- [ ] Implement the common smart tracker: nondeterministically select an input occurrence, capture its packet summary, and track its bounded relative rank.
- [ ] For AR/R, count only the selected ordering domain and consume transactions on `RLAST`.
- [ ] For AW/W, use a bounded signed-skew, two-sided tracker that captures whichever member arrives first; do not use an absolute nth-since-reset counter.
- [ ] Join the matched AW/W pair, then use a per-domain smart tracker for B; keep continuous outstanding counters to reject orphan or extra responses.
- [ ] Do not use `s_unique_in` on normal traffic. Prove creation, duplication, loss, ordering, payload integrity, and progress separately.
- [ ] Compare the abstract checker with the bounded oracle on the same exhaustive small models and mutations.
- [ ] Compile and instantiate `fifo_fvip.sv`; add covers proving the watched transaction can be selected and completed.

**Gate:** the abstraction matches the oracle's mutation score and has no new false failures or vacuity.

### C5 - First DUT: AXI FIFO

- [ ] Prove ZIPCPU `sfifo` at depths 2, 4, 8, and 32, including simultaneous push/pop and fall-through configurations that exist.
- [ ] Prove all five channel payloads independently, then enable the cross-channel transaction checker.
- [ ] Repeat on PULP and Taxi FIFO wrappers to demonstrate vendor reuse.

**Gate:** full proofs and required covers for at least three implementations; failures are classified as DUT, wrapper, property, or assumption bugs.

### C6 - 2x2 crossbar

- [ ] Formalize address decode, source-port prefix/removal, output ID width, default/error destination, and same-ID ordering.
- [ ] Track an arbitrary source port, ID, destination, and request occurrence; split read, write-route, and response-return scenarios.
- [ ] Cover simultaneous contention, independent destinations, decode errors, backpressure, and different-ID reordering.

**Gate:** full proof at outstanding depths 1, 2, and 4 with no design-specific internal signal references.

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
