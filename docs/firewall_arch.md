# AXI Firewall Architecture and Formal Verification Plan

Status: research-backed implementation plan

Date: 2026-09-04

Scope of this phase: architecture and verification plan only; no RTL has been implemented yet.

## 1. Executive decision

Build the firewall as `NumPorts` structurally independent one-to-one lanes. The IP presents AXI Subordinate port `S[i]` to an upstream Manager and AXI Manager port `M[i]` to a downstream Subordinate. Lane `i` is the only datapath between `S[i]` and `M[i]`; there is no internal crossbar, shared data FIFO, or arbitration.

The recommended first implementation is deliberately bounded:

- AXI4 Full normal transactions, using the same protocol-feature subset as the repository's [current formal profile](axi4_mvp_profile.md). Version 1 intentionally has a tighter outstanding limit; the profile's default proof bounds are not adopted as RTL limits.
- One outstanding read and one outstanding write per lane. Read and write may proceed concurrently.
- No ATOP, exclusive, AXI5, coherent, width-conversion, or clock-domain-crossing behavior in version 1.
- An accepting/holding stage on every source channel before an untrusted endpoint can influence a protected output.
- Header admission checks, optional address permissions, counted burst enforcement, response correlation, timeouts, fail-closed quarantine, sticky evidence, interrupt, and reset-assisted recovery.
- Every firewall-driven AW, W, AR, B, or R payload is zero when its corresponding VALID is zero.
- An optional `SerializeRw` policy prevents simultaneous downstream reads and writes for targets known to have concurrency defects.

This is the smallest architecture that can make meaningful containment claims. A transparent monitor alone can report a violation only after the malformed transfer or leaked value has already crossed the boundary.

The first implementation should sustain one data beat per cycle *within an admitted burst* after pipeline fill. One-outstanding operation prevents latency hiding and can create response-latency bubbles between short bursts, so bounded multi-outstanding support is a later, separately proved optimization. Latency, area, and Fmax are acceptance measurements; this plan does not make technology-independent PPA promises.

## 2. What the research changes

The supplied [eXpect paper](expect.pdf) reports 135 property counterexamples in seven evaluated implementations and demonstrates seven exploits involving dropped transactions, stale information, corruption, and denial of service. The supplied [Xray paper](xray.pdf) reports 41 findings across seven evaluated interconnects, including legal concurrent traffic that triggered internal corruption. These are strong attack and mutation sources, but neither paper is an exhaustive AXI security specification. Their results are product-, version-, parameter-, and placement-dependent. See the [eXpect project and publication](https://axi-security.github.io/expect/) and [Xray project and publication](https://axi-security.github.io/xray/) for the authors' artifacts.

Several paper properties are intentionally stricter than AXI. In particular, AXI permits write data before or in the same cycle as its address, because the AW and W channels are independent. The firewall must not call W-before-AW a protocol violation. It can legally hold `WREADY` low until an address is admitted, and a compliant Manager must retain `WVALID` and its payload. The authoritative rules are in Arm's [AMBA AXI and ACE Protocol Specification, IHI 0022H.c](https://documentation-service.arm.com/static/602a9df190ee6824a1e02b98).

Likewise, AXI reset requires source VALIDs to be low but permits other signals to have any value. Idle-payload zeroing is therefore a security hardening rule, not an AXI compliance rule. It is still worth enforcing: eXpect, Xray, and Fern et al.'s [work on incompletely specified buses](https://doi.org/10.3850/9783981537079_0302) show why stale values on otherwise ignored signals can create functional leakage or covert channels.

The resulting security boundary is:

| Class | Examples | Firewall promise |
|---|---|---|
| Prevent before forwarding | Unauthorized address range, illegal burst geometry, unsupported profile feature | Do not issue the command at `M[i]`; locally reject when a well-defined completion is possible, otherwise quarantine the lane. |
| Normalize at the boundary | Stalled source payload, invalid-cycle payload, WLAST/RLAST presentation | Hold accepted payload stable, zero invalid payload, and derive protected LAST from the tracked beat count. Record disagreement with the untrusted signal. |
| Detect and contain after possible side effects | Early write beats, missing beats/responses under a configured watchdog, or a downstream protocol fault after AW/earlier W crossed | Stop new commands, preserve evidence, finish only obligations that can be finished safely, interrupt, quarantine, and coordinate reset. Do not claim rollback. Absence is a timeout-policy event, not base AXI illegality. |
| Not observable from this boundary | Correct-ID but semantically wrong read data, legal concurrency triggering an internal target bug, wrong routing inside an external fabric that still presents a plausible response | Offer stronger optional policy such as serialization or quotas, and state that topology-aware or end-to-end protection is required. |

Commercial practice supports a block/drain/reset model. AMD's current [AXI Protocol Firewall guide, PG293 v1.2](https://docs.amd.com/r/en-US/pg293-axi-firewall), freezes fault evidence, blocks selected fatal conditions, exposes interrupts and status, and documents reset-before-unblock recovery. The same guide also documents [violations that cannot be inferred from observed timing](https://docs.amd.com/r/en-US/pg293-axi-firewall/Undetectable-Protocol-Violations). It is prior art, not a completeness oracle; its guide says some payload-only violations are omitted to save area.

## 3. Scope, trust model, and claims

### 3.1 Trusted components

The security claims assume these are trusted:

- Firewall RTL and formalized parameters.
- `clk_i`, global `rst_ni`, and the reset controller handshake.
- Configuration/status transport and recovery software.
- Physical port wiring. Lane number is the security principal; attacker-controlled `AxPROT` or `AxUSER` is never the sole identity.
- Any fairness or maximum-delay assumptions explicitly enabled in a liveness proof.

The baseline is one clock and reset domain. Global `rst_ni` may assert only while every lane is idle, or while both connected peers and any intervening queues are quiesced/reset together; otherwise it could discard an outstanding VALID or obligation. Per-lane recovery requests reset a peer while retaining firewall state and are a separate mechanism. Encode both rules in the harnesses. CDC, power isolation, metastability, analog leakage, EM leakage, and physical probing are outside version 1.

### 3.2 Adversaries

Prove two complementary threat directions rather than silently assuming both endpoints are compliant:

1. An arbitrary upstream Manager can drive malformed or adversarial AW/W/AR traffic and can refuse B/R responses.
2. An arbitrary downstream Subordinate can stall requests and can drive malformed or adversarial B/R traffic.

The other side is treated as protected and, where a progress result needs it, receives an explicit bounded environment contract. If both sides are malicious, the retained guarantee is containment within that lane and structural noninterference between lanes, not useful service.

### 3.3 Placement limits

The firewall protects only transfers it observes. The requested replicated `S[i] -> M[i]` topology structurally prevents cross-lane leakage *inside this IP*. It cannot prove that a downstream crossbar routes data to the correct external port if the crossbar is outside the boundary and returns a plausible ID/data pair. Nor can independent lanes guarantee fairness in an external shared fabric.

To claim Xray-style global routing, arbitration, or bus-sharing protection, a future topology-aware wrapper must enclose all relevant ports or consume trustworthy route/provenance tags. Per-port firewalls placed before a shared interconnect can still enforce access permissions, cap admitted traffic, and remove malformed transactions, but they do not see every internal fabric decision.

## 4. Top-level architecture

```text
                         trusted control plane
                  +--------------------------------+
                  | cfg/status + IRQ + reset reqs  |
                  +---------+-----------+----------+
                            | per-lane  |

 upstream Manager           | lane i   |          downstream Subordinate
        |                    v          |                    |
        |   S[i]   +-----------------------------+   M[i]    |
        +--------->| AW/W/AR hold + admission    |---------->+
        |          | read/write obligation state |           |
        |<---------| B/R validation + completion |<----------+
                   | fault/quarantine/recovery   |
                   +-----------------------------+

        Repeat the complete lane NumPorts times; never share payload storage.
```

Recommended typed core ports are:

```systemverilog
input  axi_req_t  [NumPorts-1:0] slv_req_i;
output axi_resp_t [NumPorts-1:0] slv_resp_o;
output axi_req_t  [NumPorts-1:0] mst_req_o;
input  axi_resp_t [NumPorts-1:0] mst_resp_i;
```

Use a thin optional `AXI_BUS.Slave`/`AXI_BUS.Master` wrapper only at the integration edge. The synthesizable core should use PULP packed request/response types so lane replication, formal binding, and field overrides remain compact.

### 4.1 Version 1 parameters

| Parameter | Version 1 decision |
|---|---|
| `NumPorts` | At least 1; generated independent lanes. |
| `AxiAddrWidth`, `AxiDataWidth`, `AxiIdWidth`, `AxiUserWidth` | Explicit and checked at elaboration. Data width must be a power of two from 8 through 1024 bits; all packed-type widths must be positive. Use a tied-zero one-bit dummy USER type when USER is absent. |
| `axi_req_t`, `axi_resp_t` and channel types | Supplied PULP-compatible packed types. |
| `NumRegions` | Compile-time ACL entry count. Zero explicitly selects an allow-all-address, protocol-only build and removes ACL comparators; it does not disable protocol containment. |
| `EnableTimeout` and timeout width | Optional policy; zero threshold means disabled. |
| `SerializeRw` | Default false; enable for a target that cannot safely tolerate concurrent reads and writes. |
| Boot policy | Runtime-configured lanes reset closed until a trusted policy commit; a static-policy build can declare its reset policy valid at elaboration. There is no implicit open/bypass default. |
| Outstanding depth | Exactly one read and one write in version 1; not presented as an AXI limit. |
| ATOP/exclusive support | Disabled. `AWATOP != 0` or `AxLOCK != 0` is a profile fault and never reaches `M[i]`. Do not silently downgrade it. |

Read and write remain independent in the normal profile, so one of each can be active. This retains simple scalar ID/length/beat state while covering the most important concurrency case. A full ID CAM is deferred until the single-outstanding proof and attack suite are complete.

Elaboration assertions must cross-check `$bits` of the supplied channel types against all width parameters. Represent `AxLEN + 1` in at least nine bits, for example `{1'b0, ax.len} + 9'd1`, so `AxLEN == 8'hff` denotes 256 rather than wrapping to zero.

### 4.2 Lane blocks

Each lane contains four small responsibilities, preferably kept in one lane module and one package rather than decomposed into many wrappers:

1. **Source holding and idle scrub.** One accepting/holding element for AW, W, AR, B, and R. It prevents an untrusted source from changing a protected, stalled output. A shadow comparison detects withdrawal or payload changes while an input VALID is stalled because capacity or policy withheld READY.
2. **Admission and obligation tracking.** Capture ID, length, burst geometry, permissions, expected beat, whether the opposite side accepted the command, and which response remains owed.
3. **Pass/error mux.** Select a validated pass-through item or a locally generated response. The final assignment masks the entire corresponding payload struct to zero when VALID is zero.
4. **Lane control.** First-fault capture, cumulative fault bits/counter, watchdogs, fail-closed state, IRQ, and reset/recovery handshake.

Use one lane-level quarantine FSM with separate read/write obligation records. A fault normally closes the whole lane because both directions terminate at the same suspect endpoint. Direction-only quarantine can be evaluated later if its extra recovery state is justified.

## 5. Datapath rules

### 5.1 Invalid-cycle zeroization

Apply the following schematic invariants to firewall-owned source outputs (clock/reset wrappers omitted here):

```systemverilog
!mst_req_o[i].aw_valid |-> mst_req_o[i].aw == '0;
!mst_req_o[i].w_valid  |-> mst_req_o[i].w  == '0;
!mst_req_o[i].ar_valid |-> mst_req_o[i].ar == '0;
!slv_resp_o[i].b_valid |-> slv_resp_o[i].b == '0;
!slv_resp_o[i].r_valid |-> slv_resp_o[i].r == '0;
```

This covers data, strobes, ID, address, attributes, response, LAST, and USER fields contained in each channel payload. Do not zero a complete PULP request or response aggregate: those aggregates also carry opposite-direction READY signals, which do not have a corresponding VALID and must remain functional. External input wires cannot be forced to zero; the guarantee applies at the firewall outputs.

Also clear retired internal payload registers where this is cheap, but keep the output mask as the proved security boundary.

### 5.2 AW/AR admission

Before an AW or AR can handshake at `M[i]`, check:

- Supported protocol/profile fields.
- `AxLEN + 1`, `AxSIZE`, and bus width consistency.
- Legal FIXED/INCR/WRAP form, including legal WRAP length/alignment.
- No 4 KiB crossing.
- Overflow-safe first and final byte calculation using an extra arithmetic bit.
- The *entire* burst lies in one allowed ACL region with the required read/write permission.
- Optional restrictions on privileged/secure/instruction attributes.
- A free per-direction obligation slot.
- `SerializeRw` scheduling, if enabled.

Use half-open ACL ranges `[base, limit)` and compare the complete burst footprint. Store/compute `limit` at `AxiAddrWidth + 1` bits so the top-of-address-space value `2**AxiAddrWidth` is representable. For WRAP, compare its wrap window; for FIXED, compare the addressed beat. Port identity selects the policy. `AxPROT` can further restrict an access but must not elevate it, because it is driven by the requesting Manager.

A legal request denied only by access policy is accepted locally and completed with DECERR so a compliant requester can make progress. A malformed or unsupported command is recorded as a source/profile fault. Commands without a defined version-1 completion—especially nonzero ATOP—must not be handshaken or forwarded; the lane quarantines and requests recovery rather than inventing incorrect semantics.

### 5.3 Write path

Version 1 uses this sequence:

1. Capture and admit one AW.
2. Keep upstream `WREADY` low until that AW is admitted. This is legal even if W appears first; a compliant Manager holds WVALID and its payload.
3. Associate accepted W beats with the sole admitted AW only until the first LAST/count disagreement, and increment a nine-bit total/beat counter.
4. Validate legal WSTRB lanes for the current beat. Preserve sparse strobes inside the legal lane mask; never enable a byte that the source disabled.
5. Compare incoming WLAST with `beat == AWLEN`. The held beat can be sent downstream with LAST derived from the counter, but the mismatch changes how the upstream obligation is terminated.
6. For a correct final beat, correlate one B with the captured AWID. For a mismatch, stop accepting later upstream W beats; AXI4 has no WID, so a later beat could belong to a W-before-AW transaction and cannot safely be assigned to the faulty burst.

On **early WLAST**, the current upstream WLAST handshake is terminal. If AW or earlier W beats already crossed downstream, generate only the remaining downstream beats with `WSTRB == 0` and assert downstream WLAST on the expected counted final beat. Do not accept later upstream W as the remainder. Conservative version 1 consumes any resulting downstream B, emits no B for the malformed upstream burst, and keeps the lane quarantined for source reset.

On **missing WLAST at the expected final count**, send the held data downstream with derived WLAST if a downstream burst is already open, then stop accepting upstream W and quarantine. The firewall must not assert upstream B: no upstream WLAST handshake occurred, and a later WLAST is transaction-ambiguous. Resetting the upstream peer cancels that malformed obligation.

For an ACL-denied write, do not issue AW at `M[i]`. Absorb upstream W only while its LAST agrees with the captured length. A correct final WLAST permits one DECERR B with the captured ID and zero BUSER. Any LAST/count disagreement records a fault, emits no B for that malformed burst, and requires upstream reset.

If the source simply stops before presenting a terminal beat, no conforming subordinate can manufacture the missing *upstream handshake*. The lane must interrupt, quarantine, and reset the source. If an allowed AW or earlier W beats already handshook downstream, their side effects cannot be rolled back. Zero-strobe completion beats may close that downstream burst, but this is containment, not transaction atomicity, and must be proved against the selected profile.

A future store-and-forward option can buffer and validate the entire write burst before exposing AW/W. That is the generic way to turn late write faults into pre-commit rejection, at the cost of up to 256 data beats of storage per active burst.

### 5.4 Read path

For an admitted AR, store ARID and expected beat count before forwarding it. Each downstream R beat is inspected in a holding stage before it can handshake upstream:

- RID must equal the outstanding ARID.
- There must be an outstanding read.
- Incoming RLAST must agree with the expected final beat.
- RRESP must not be EXOKAY in the version-1 non-exclusive profile.
- The protected RLAST is derived from the firewall counter.
- RVALID and its protected payload remain stable until upstream acceptance.

An ACL-denied read never reaches `M[i]`; generate exactly `ARLEN + 1` zero-data DECERR beats with the captured RID and RLAST only on the final counted beat.

An orphan R, wrong RID, or bad RLAST does not pass unchecked. Consume or hold it only according to the quarantine policy and mark the lane faulty. An orphan with no accepted upstream AR produces no synthetic response. If a corresponding upstream read obligation does exist, synthesize its remaining zero-data SLVERR completion only after the downstream obligation is safely terminated or reset. Read data already accepted upstream before a late fault cannot be retracted. A syntactically correct beat carrying semantically wrong data is not detectable without end-to-end integrity metadata.

### 5.5 Write response path

B is eligible upstream only after the tracked AW and an upstream WLAST handshake at the expected count. BID must match the outstanding AWID, BRESP must not be EXOKAY in the version-1 non-exclusive profile, and there must be exactly one B per write transaction. An early, orphaned, duplicated, wrong-ID, or unexpected-EXOKAY B is blocked from the protected output and causes quarantine.

SLVERR and DECERR from a compliant downstream device are legal in-band responses, not protocol violations. Pass them through and optionally count them as service errors; do not label them protocol faults unless system policy explicitly says so.

### 5.6 Capacity and backpressure

Capacity exhaustion is handled by READY backpressure and is not itself a fault. Every READY assertion reserves enough state for the transfer it accepts. Internal accounting overflow is an assertion failure, not a runtime recovery mechanism.

If an untrusted source withdraws VALID or changes its payload while the firewall has deasserted READY, that source stability violation is detected from the shadowed offer and the lane is quarantined. The malformed value must never be forwarded merely to relieve pressure.

### 5.7 Watchdogs

AXI defines no universal cycle deadline. Every timeout is therefore named and reported as a **policy fault**, never as proof of base-protocol noncompliance. Provide independently configurable, zero-disables thresholds for:

- AW, W, or AR output stalled waiting for downstream READY.
- AW expected after an unaccepted W-before-AW offer has remained asserted.
- W data expected after an admitted AW.
- B expected after the write obligation is complete.
- First or next R beat expected after AR or the preceding R beat.
- Upstream BREADY/RREADY refusal that prevents response-buffer retirement.

Expiry blocks new work and raises IRQ. It does not authorize dropping an asserted output VALID: the firewall must hold the payload stable until handshake or until a trusted reset acknowledgement establishes that the peer discarded the transaction. In particular, do not return an error for a timed-out downstream command and then allow that same still-asserted command to be accepted later.

## 6. Fault policy

| Event | Classification | Immediate action | Completion/recovery |
|---|---|---|---|
| Payload nonzero while firewall VALID is zero | Internal security assertion | Mask payload to zero | This must be impossible at an output. |
| Upstream/downstream source changes or withdraws a stalled offer | Protocol fault | Do not expose changed offer; stop new commands | Drain safe obligations, quarantine, IRQ, reset offending side. |
| ACL denial | Security policy event, not malformed AXI | Never forward address | Counted local DECERR completion. Quarantine only if configured. |
| Illegal burst geometry or illegal byte-lane use | Protocol/profile fault | Never forward header or offending beat | Local completion where semantics are defined; otherwise quarantine/reset. |
| Unsupported ATOP/exclusive | Profile fault | Do not handshake or downgrade | Quarantine and reset; add compliant support only as a separately proved feature. |
| Early WLAST | Protocol fault | Stop later upstream W; use zero-strobe beats to close any downstream burst | Consume its downstream B, emit no B for the malformed upstream burst, and reset upstream. No rollback. |
| Missing WLAST at expected count | Protocol fault | Stop later upstream W; drive only the already-open downstream burst to counted completion | Do not emit upstream B; reset the upstream peer to cancel the malformed obligation. |
| RLAST, RID, BID, early/orphan/duplicate response, or EXOKAY without exclusives | Protocol/profile fault | Do not forward malformed response | Generate SLVERR only for a corresponding fully accepted upstream obligation after safe termination/reset. An orphan/duplicate with no obligation produces no response. |
| READY or response watchdog expiry | Policy fault | Hold pending output stable; stop new commands | Reset/acknowledge peer, then synthesize an error if the upstream obligation was completely accepted. |
| Downstream SLVERR/DECERR | Legal service response | Pass through | Optional counter/IRQ policy; no protocol quarantine by default. |
| Legal read/write concurrency | Not a detectable syntax fault | Normal operation by default | Enable `SerializeRw` for a target-specific mitigation. |
| Plausible but semantically wrong data/routing outside boundary | Unobservable | None | Requires end-to-end integrity or topology-aware monitoring. |

Recommended response meanings are DECERR for a local decode/access-policy rejection and SLVERR for a peer malfunction or watchdog termination. In all cases preserve the response shape required by the accepted request: a read response has the counted number of beats, and version 1 produces a write B only for a burst whose upstream WLAST occurred at the expected count. A count match without WLAST, or WLAST at the wrong count, never authorizes B.

## 7. Quarantine and recovery

Use a small lane FSM:

```text
RESET -> BOOT_LOCKED -> RUN -> DRAIN -> QUARANTINED -> RESETTING
                         ^                                  |
                         +----------- RECOVER <-------------+
                                      only when clean
```

- **BOOT_LOCKED:** Hold all lanes closed until a valid static policy is selected or trusted software atomically commits runtime policy. Reset values are deny-by-default.
- **RUN:** Admit new checked transactions.
- **DRAIN:** Stop new AW/AR, retain stable pending outputs, and complete only already accepted obligations. A timeout can make external reset mandatory.
- **QUARANTINED:** No new datapath traffic. Invalid payloads remain zero. Fault evidence and IRQ remain asserted.
- **RESETTING:** Assert the selected per-lane upstream/downstream reset request until the trusted reset controller acknowledges that the peer was reset and stale interface state is gone.
- **RECOVER:** Purge canceled local state, emit any still-legal synthetic completion, require all busy obligations to retire or their requester to be reset, then accept an explicit unblock.

The exact reset wire contract is intentionally explicit rather than pretending the firewall owns arbitrary SoC resets:

```text
up_reset_req_o[i]    down_reset_req_o[i]
up_reset_done_i[i]   down_reset_done_i[i]
```

Requests are levels, not one-cycle pulses. The reset controller owns clock-domain synchronization, reset duration, and actual module reset. A done acknowledgement means the selected peer has been quiesced/reset sufficiently that the firewall may cancel previously asserted-but-unaccepted transfers. If the integration cannot provide that guarantee, the corresponding transfer must remain pending and the lane cannot safely reopen.

Never enter the quiet QUARANTINED state by dropping an asserted VALID. Remain in DRAIN or RESETTING until the transfer handshakes or a reset acknowledgement authorizes cancellation.

Global `rst_ni` is not this recovery mechanism. It can clear the firewall's holding state immediately, so it is legal only under the whole-link idle-or-concurrent-reset contract in Section 3.1. A per-peer reset request leaves the firewall alive until `*_reset_done_i` makes cancellation safe.

Recovery software should:

1. Observe per-lane IRQ and snapshot status.
2. Stop software from submitting new work to the affected endpoint.
3. Wait for safe drain when possible.
4. Request reset of the recorded offending side, or both sides if transaction ownership is ambiguous.
5. Wait for reset acknowledgement and `busy == 0`.
6. Clear sticky evidence with write-one-to-clear, commit any policy update, and request unblock.
7. Resume traffic only after the unblock write is acknowledged.

This follows the useful parts of AMD's documented [recovery sequence](https://docs.amd.com/r/en-US/pg293-axi-firewall/Recovery) while making the external reset acknowledgement part of the proof contract.

## 8. Control and evidence

Keep the lane core independent of a bus register implementation. It consumes a compact trusted `cfg_t` and produces `status_t`. Add one optional shared AXI4-Lite adapter for CPU access; that adapter is outside all protected data lanes and must itself be trusted or placed behind separate access control.

### 8.1 Minimum per-lane status

- FSM state, read busy, write busy, and reset-needed side mask.
- Immutable first-fault code, source side, channel, and direction.
- Captured ID, AW/AR address and attributes when relevant.
- Expected and observed beat numbers/LAST.
- Whether any downstream address/data transfer had already committed.
- Cumulative fault bitmap and saturating occurrence counter.
- Optional legal SLVERR/DECERR service counters.

Freeze the first-fault record until safe clear, but retain later categories in the cumulative bitmap. Fault capture wins over a same-cycle software clear.

### 8.2 Minimum controls

- Lane-open authorization, soft pause, IRQ mask, and optional quarantine-on-ACL-denial. There is no runtime unchecked-bypass mode.
- Timeout thresholds.
- ACL base/limit/permissions and permitted attribute masks.
- `SerializeRw` if runtime control is required; otherwise make it static.
- W1C evidence clear, reset-side request, and unblock.
- Configuration lock until global reset.

Use shadow registers plus an atomic commit accepted only when `busy == 0` and the lane is boot-locked, paused, or safely quarantined. Never change an ACL or timeout halfway through an admitted burst.

Expose `irq_o[NumPorts]` plus `irq_any_o = |irq_o`. IRQ should be level-sensitive while an enabled sticky fault remains, so software cannot miss a pulse. Calling this a CPU “exception” is platform-specific; the portable IP contract is an interrupt and readable evidence.

## 9. PULP AXI reuse strategy

The checkout is a `KastnerRG/pulp_axi` fork derived from PULP AXI 0.39.9, with local VCS-support commit `70f2a315d4aa27c152cf69644ec51497d8af8a65`; it is not byte-identical to the upstream tag. The upstream project has a newer [v0.39.10 tag](https://github.com/pulp-platform/axi/tree/v0.39.10). Implement against and pin the checked-out fork first. Evaluate an upgrade independently rather than silently changing the dependency during firewall development.

Reuse:

- [`include/axi/typedef.svh`](../soc-testbed/axi/ip/pulp/axi/include/axi/typedef.svh) for channel/request/response types.
- [`include/axi/assign.svh`](../soc-testbed/axi/ip/pulp/axi/include/axi/assign.svh) for a thin interface-to-struct wrapper.
- [`axi_pkg.sv`](../soc-testbed/axi/ip/pulp/axi/src/axi_pkg.sv) response and burst constants. Do not call assumption-bearing geometry functions on attacker-controlled headers: local `wrap_boundary()` contains an immediate legality assumption, and `beat_addr()` reaches it for WRAP bursts.
- [`spill_register_flushable.sv`](../soc-testbed/axi/ip/pulp/common_cells/src/spill_register_flushable.sv), with bypass disabled, can provide a cancelable two-entry source hold. Assert flush only after normal handshake or peer reset acknowledgement authorizes cancellation. During that trusted flush, gate its internal input VALID and the externally visible READY low as its own contract requires, account for both entries, and prove neither a false handshake nor stale VALID survives. A custom one-entry cancelable hold is also acceptable if it is smaller after synthesis.
- Existing local formal burst geometry logic is a specification cross-check, especially for unaligned FIXED transfers. Put total, assumption-free, overflow-safe helpers in `axi_firewall_pkg.sv`; every input bit pattern must return a legality result without constraining it. PULP geometry helpers may be invoked only behind an independently proved legality guard. Production RTL must not depend on verification-only packages.

Do not treat these existing blocks as the complete firewall:

- [`axi_isolate.sv`](../soc-testbed/axi/ip/pulp/axi/src/axi_isolate.sv) counts and gracefully drains traffic but does not detect malicious behavior; graceful drain can wait forever for a faulty peer.
- [`axi_err_slv.sv`](../soc-testbed/axi/ip/pulp/axi/src/axi_err_slv.sv) is useful for compliant rejects, but its write sink terminates on incoming WLAST and can therefore be wedged by the very malformed stream this firewall must contain.
- [`axi_throttle.sv`](../soc-testbed/axi/ip/pulp/axi/src/axi_throttle.sv) explicitly assumes in-order or indistinguishable-ID traffic; it is not an arbitrary-ID response scoreboard.
- [`spill_register.sv`](../soc-testbed/axi/ip/pulp/common_cells/src/spill_register.sv) and [`axi_cut.sv`](../soc-testbed/axi/ip/pulp/axi/src/axi_cut.sv) tie channel flush low. They cannot purge a pending item during per-peer recovery and must not sit in a cancelable state path unless global reset covers both peers.
- `AXI_ASSIGN` copies entire channels. Use it only at wrapper boundaries, then explicitly override/generate protected fields. A blind aggregate pass-through defeats sanitization.

Retain the checked-out fork's [Solderpad Hardware License notice](../soc-testbed/axi/ip/pulp/axi/LICENSE) for any copied or modified source; the [upstream v0.39.10 license](https://github.com/pulp-platform/axi/blob/v0.39.10/LICENSE) is provided only as a provenance reference.

## 10. Formal verification architecture

The central rule is: **never constrain the malicious side with the compliance assumptions whose violations the firewall is supposed to catch.** The existing FVIP is valuable, but placing its environment contract on an attacker would remove the attack traces from the state space.

### 10.1 Harnesses

1. **Adversarial upstream.** AW/W/AR and upstream BREADY/RREADY are unconstrained apart from signal widths and the explicit whole-link global-reset contract. Assume a compliant/available downstream only for claims that require it. Assert that `M` outputs remain legal, stable, scrubbed, authorized, bounded, and correctly counted.
2. **Adversarial downstream.** B/R and downstream AWREADY/WREADY/ARREADY are unconstrained apart from that reset contract. Assume a compliant upstream only where needed. Assert that `S` outputs remain legal, stable, scrubbed, correlated, and contain malformed responses.
3. **Fault-free refinement.** With both peers compliant and policy allowing the transaction, prove conservation and observational equivalence modulo documented latency and idle-zero values: no drop, duplicate, reorder, changed payload, false error, or false IRQ.
4. **Recovery.** Constrain only the trusted control/reset handshake. Prove fault precedence, immutable evidence, no new command while blocked, no stale response after reset, correct synthetic completion, and safe reopen.
5. **Composition/noninterference.** At `NumPorts=2`, use a self-composition or taint-style miter: changing lane `j` inputs cannot change lane `i` datapath outputs or per-lane status. The only documented cross-lane effects are aggregate IRQ and the control read mux. Then rely on the generated identical structure for general `NumPorts`.

### 10.2 Assertion groups

- Reset and VALID/payload stability on all firewall-owned source channels.
- Per-channel invalid-payload zeroization.
- No unauthorized or malformed AW/AR handshake at `M`.
- Full-burst ACL containment with no address-arithmetic wraparound.
- Exact W/R beat counts and protected LAST placement.
- W belongs to the sole admitted AW; no W acceptance after a LAST/count mismatch; B requires upstream WLAST at the expected count.
- B/R ID and lifecycle correlation, and no EXOKAY when the exclusive profile is disabled.
- No spontaneous, lost, duplicated, or reordered accepted transaction in the fault-free harness.
- Local DECERR/SLVERR response ID, count, LAST, stability, and dependency correctness.
- Capacity invariants and no counter underflow/overflow.
- Total detector functions: malformed attacker inputs select a rejection result and never satisfy an RTL/package `assume`.
- After the first fault, no new command escapes and first-fault evidence cannot change.
- IRQ reduction, mask behavior, clear precedence, configuration commit/lock, and reset request/ack protocol.
- No lane-to-lane payload or control dependence beyond documented control-plane reductions.

Use the repository's [`axi_channel_fvip.sv`](../axi_sva/our/axi_channel_fvip.sv), [`axi_pair_tracker.sv`](../axi_sva/our/axi_pair_tracker.sv), [`axi_read_tracker.sv`](../axi_sva/our/axi_read_tracker.sv), and [`axi_write_tracker.sv`](../axi_sva/our/axi_write_tracker.sv) as audited property/predicate sources. Reuse selected-occurrence tracking for universal transaction claims, and use deterministic lifecycle models only for trusted environment assumptions. The production detector is synthesizable RTL; the FVIP is not substituted for detector logic.

### 10.3 Safety versus progress

Prove safety unbounded with induction wherever possible. Prove liveness only under named contracts:

- A protected destination eventually raises READY, or a configured watchdog expires and a reset acknowledgement eventually arrives.
- A protected Subordinate eventually supplies the expected response, or recovery runs.
- A protected Manager eventually accepts a response, or it is reset.

Report the bound and assumption in the property name. A timeout-enabled proof establishes the configured policy, not universal AXI progress.

### 10.4 Parameter and boundary matrix

At minimum run:

- `NumPorts=1` for deep lane proofs, `NumPorts=2` for composition, and at least one odd/more-than-two elaboration case to catch generate/index mistakes.
- Representative data widths 32 and 64, address width 32 or the integration width, and ID widths 1 and 4; separately lint elaboration limits including 8 and 1024 data bits.
- Single-beat, two-beat, maximum configured formal length, and symbolic `AxLEN` with explicit covers for 0, 1, 15, and 255 where tool capacity permits.
- FIXED, INCR, and WRAP boundary cases; unaligned starts; 4 KiB edge; address overflow.
- ACL hit, edge, gap, permission mismatch, and region-crossing bursts.
- Timeout disabled, minimum nonzero, and representative operational value.
- `SerializeRw` both off and on.

Any reduction from the architectural AXI maximum in a proof harness is a documented proof capacity bound, not silently presented as an RTL protocol limit.

### 10.5 Attack and mutation suite

Port the existing mutation scenarios under [`fvip_validation`](../fvip_validation) and add directed traces from eXpect/Xray:

- VALID withdrawal and every stalled-payload field change.
- Nonzero invalid/reset payload and stale cross-transaction values.
- W-before-AW as a **legal cover**, plus illegal source dependence exposed by a watchdog—not a false protocol assertion.
- Bad length/size/burst/4 KiB geometry and ACL-crossing bursts.
- Early, missing, and repeated WLAST/RLAST.
- EXOKAY on B/R while the exclusive profile is disabled.
- W without an admitted AW; R/B without an outstanding request; wrong/duplicated IDs.
- Downstream/address/data/response stalls and upstream refusal to accept responses.
- Read/write concurrency with `SerializeRw` both enabled and disabled.
- Fault during another outstanding direction, fault/clear collision, reset during drain, and stale response after reset.
- Two-lane attempts to influence another lane's payload/status.

For each detector/property, include a cover that reaches it and at least one mutation expected to fail when the protection is removed. Review proof cores and vacuity; “proved” with an unreachable antecedent is not acceptance.

## 11. File plan

Keep every implementation and verification artifact under `firewall/`, as required by [the prompt](firewall_prompt.md):

```text
firewall/
  rtl/
    axi_firewall_pkg.sv       # cfg/status/fault types and geometry helpers
    axi_firewall_lane.sv      # complete single-lane datapath and containment
    axi_firewall.sv           # NumPorts generate and typed-array core
    axi_firewall_intf.sv      # optional AXI_BUS wrapper
    axi_firewall_regs.sv      # optional trusted AXI4-Lite control adapter
  formal_tb/
    axi_firewall_properties.sv
    tb_firewall_upstream.sv
    tb_firewall_downstream.sv
    tb_firewall_refinement.sv
    tb_firewall_recovery.sv
    tb_firewall_noninterference.sv
    mutations/
  flist.f
  Makefile
  README.md
```

Keep the response generator inside `axi_firewall_lane.sv` unless reuse measurably reduces code and proof state. Avoid a module per rule. The optional interface wrapper and register adapter must not be prerequisites for proving the typed core.

The repository's current root formal dispatch does not yet define a firewall role/testbench. A local `firewall/Makefile` and file list satisfy the containment requirement first; a thin root target can invoke it later without moving sources. At the time of this audit, Verilator is locally available but the configured Siemens QVerify executable/license is not on `PATH`, so compile/lint can run locally while full proof execution needs the intended formal environment.

## 12. Implementation sequence

### Milestone 0 — Freeze contracts

- Assign stable fault codes and requirement/property IDs.
- Confirm CPU register address, reset acknowledgement semantics, ACL entry count, and target widths.
- Turn every claimed mitigation in the research table into a property or an explicit limitation.

### Milestone 1 — Transparent safe shell

- Add PULP typed top/lane wrappers and generated independent lanes.
- Implement source holding, reset behavior, and per-channel invalid-payload zeroing.
- Prove fault-free refinement, one-beat/cycle intra-burst post-fill data flow, documented inter-burst bubbles, and two-lane noninterference.

### Milestone 2 — Single-outstanding protocol containment

- Add one read and one write obligation record.
- Add AW/W realignment, counted LAST, response ID/lifecycle checks, and local error responses.
- Add fail-closed FSM, first-fault record, bitmap/counter, IRQ, and direct recovery sideband.
- Prove both adversarial-direction harnesses and the initial mutation suite.

### Milestone 3 — Security policy and CPU integration

- Add overflow-safe full-burst ACL checks and optional attribute restrictions.
- Add watchdogs labeled as policy.
- Add reset request/done protocol, shadow/commit/lock, and AXI4-Lite adapter.
- Prove recovery, configuration atomicity, and no bypass through the control path.

### Milestone 4 — Closure and measurement

- Run all proof configurations, induction, covers, vacuity review, and mutation testing.
- Run lint, simulation smoke tests, and synthesis.
- Record cycles of added latency, sustained bandwidth, cell/FF/BRAM area, Fmax, and parameter scaling for the actual target technology.
- Revisit buffering/cuts only with proof and PPA evidence.

### Milestone 5 — Performance extensions

- Add bounded multi-outstanding tracking, first as FIFO-ordered and then per-ID only if required.
- Re-run the complete security/refinement/mutation matrix for every supported depth.
- Do not weaken the version-1 fail-closed guarantees to gain throughput.

## 13. Definition of done for version 1

Version 1 is complete only when:

- All five firewall-owned source channels prove reset/stability and invalid-cycle zeroization.
- Global reset proves safe only under the documented idle-or-concurrent-peer-reset contract; per-peer recovery preserves live firewall state until acknowledgement.
- No disallowed or malformed address request can handshake downstream.
- All accepted legal transactions are conserved in fault-free operation with correct fields, ordering, IDs, counts, and LAST.
- No B is generated unless upstream WLAST handshakes at the expected count, and no later W beat is assigned after an early/missing-LAST mismatch.
- Every locally completed request has a protocol-shaped error response and no forbidden downstream side effect.
- Every listed detectable fault has sticky per-port evidence, IRQ behavior, a reachable cover, and a catching mutation.
- Quarantine prevents new traffic; reset acknowledgement and unblock cannot release stale traffic.
- N-lane noninterference is proved compositionally.
- Safety claims are unbounded or clearly labeled with their bounds; liveness assumptions are visible.
- No FVIP assumption constrains an attacker into compliance.
- Lint/simulation pass, formal results have no unexplained inconclusive or vacuous properties, and PPA is measured rather than estimated.
- Documentation contains the final supported profile, placement assumptions, residual risks, register/reset contract, and reproduction commands.

## 14. Prioritized future features

1. **Full-burst write store-and-forward:** prevents any write side effect until WLAST/count/strobes are validated; largest direct security gain, largest storage cost.
2. **Bounded multi-outstanding/per-ID tracking:** restores latency hiding; requires FIFO/CAM state and same-ID ordering proofs.
3. **Per-port credits, rate budgets, and burst fragmentation:** contains legal-traffic DoS in a shared fabric. [AXI-REALM](https://www.research-collection.ethz.ch/entities/publication/170d2522-6119-4f62-bba2-3cf1bb529069) is relevant primary prior art, but its published PPA is a design-point result, not a universal estimate.
4. **Topology-aware multi-port supervisor:** checks route provenance, partitions shared resources, and covers Xray cross-manager cases that independent lanes cannot observe.
5. **End-to-end data integrity:** parity/ECC/poison or cryptographic tags for semantically wrong but protocol-valid data.
6. **Policy event FIFO and tamper evidence:** retains more than first-fault metadata without bloating the fast path.
7. **ATOP and exclusive profiles:** only with correct B/R coupling, exclusivity state, and dedicated formal suites. PULP's `axi_atop_filter` can be evaluated for compliant peers, but its WLAST-terminated absorption path must be reworked or contained for an adversarial source.
8. **CDC, power-domain, and reset-domain adapters:** separate wrappers with their own formal contracts.
9. **Distributed policy generation:** compare with [AKER Access Control](https://github.com/KastnerRG/AKER-Access-Control) for scalable wrapper/policy methodology.

## 15. Explicit residual risks

- Streaming mode cannot undo write side effects that occurred before a late fault.
- A bus-only firewall cannot validate application-level data correctness.
- A one-to-one lane cannot repair hidden routing/arbitration state in an external interconnect.
- A malicious peer can deny service to its own lane; recovery availability depends on the CPU/reset controller.
- Watchdogs can classify a slow but legal device as faulty if configured too aggressively.
- AXI permissions are attributes, not authenticated identity. Security depends on trusted port binding and configuration.
- Verification covers the enumerated RTL/profile/parameter matrix, not analog leakage, physical attacks, or unreviewed configurations.

## 16. Research sources and audit notes

Primary sources used for the decisions above:

- Arm, [AMBA AXI and ACE Protocol Specification, IHI 0022H.c](https://documentation-service.arm.com/static/602a9df190ee6824a1e02b98), January 2021.
- Zonta-Roudes et al., [eXpect: On the Security Implications of Violations in AXI Implementations](https://doi.org/10.1145/3676536.3676844), ICCAD 2024; supplied local [paper](expect.pdf).
- Zonta, Hinderling, and Shinde, [Xray: Detecting and Exploiting Vulnerabilities in Arm AXI Interconnects](https://doi.org/10.23919/DATE64628.2025.10992968), DATE 2025; supplied local [paper](xray.pdf).
- AMD, [AXI Protocol Firewall Product Guide PG293 v1.2](https://docs.amd.com/r/en-US/pg293-axi-firewall), released 2025-08-29, especially Block Condition, Recovery, Timeout Faults, and Undetectable Protocol Violations.
- Fern et al., [Hardware Trojans in Incompletely Specified On-chip Bus Systems](https://doi.org/10.3850/9783981537079_0302), DATE 2016.
- PULP Platform, [AXI SystemVerilog modules v0.39.10](https://github.com/pulp-platform/axi/tree/v0.39.10), compared with the repository's pinned `KastnerRG/pulp_axi` fork derived from v0.39.9.
- Benz et al., [AXI-REALM: A Lightweight and Modular Interconnect Extension for Traffic Regulation and Monitoring of Heterogeneous Real-Time SoCs](https://www.research-collection.ethz.ch/entities/publication/170d2522-6119-4f62-bba2-3cf1bb529069), DATE 2024.
- Restuccia et al., [Is Your Bus Arbiter Really Fair?](https://doi.org/10.1145/3358183), ACM TECS 2019.
- ZipCPU's open [`axisafety` firewall](https://github.com/ZipCPU/wb2axip/blob/master/rtl/axisafety.v) was reviewed as compact prior art. It intentionally uses a more restrictive transaction model, so it is an attack/recovery reference rather than drop-in AXI behavior.

The search was stopped after the supplied papers, the normative Arm specification, current vendor recovery behavior, pinned/current PULP sources, local FVIP/mutations, and primary work on stale-signal leakage, access control, and bandwidth isolation converged on the same architecture boundaries. Remaining uncertainty is integration-specific—reset ownership, CPU register placement, desired ACL scale, timeout policy, and target PPA—not a reason to add speculative datapath features before the version-1 proofs exist.
