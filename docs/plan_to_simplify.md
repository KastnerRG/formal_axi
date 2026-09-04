# Plan to simplify the AXI FVIP

> ### ⚠ Written 2026-09-02; re-verified 2026-09-04 — read §15 first
>
> The parallel C6 closure effort has since grown the sources **3894 → 5514 lines**
> and independently implemented several items here. **§6 is inverted** (the view is
> now consumed by role code), **§13.1's state numbers are obsolete**, and
> **§13.2 is refuted on soundness**. §1, §4, §5, §7 and §12 are unaffected; §3 needs
> one adjustment (§15.4b).
> See [§15](#15-re-verification-against-the-c6-effort-2026-09-04).

**Scope:** the two checking levels — protocol-endpoint only (`axi_sva/our/`) and
protocol+role (`per_role_fvip/`). Target: same functionality, ~58% fewer lines,
20 files → 7, and 16 files deleted outright.

**Baseline:** 3894 lines / 20 files — *as of 2026-09-02*. The tree is now **5514
lines**; every absolute figure in §1, §9 and §13 needs recomputing before use (§15.6).

| Area | Now | After | Δ |
|---|---|---|---|
| `axi_sva/our/` + wrappers | 1954 (12 files) |  ~750 (4) | −62% |
| `per_role_fvip/fifo/` | 240 (3) | ~110 (1) | −54% |
| `per_role_fvip/xbar/` | 1704 (5) | ~600 (2) | −65% |
| **Total** | **3894 (20)** | **~1640 (7)** | **−58%** |

Plus, outside that count: **222 lines of dead files deletable today** with no
refactor at all ([§1](#1-files-that-can-simply-disappear)), and **~655 lines** across
the validation harness, tooling, build flow and docs ([§12](#12-second-pass-sweep-everything-outside-axi_sva--per_role_fvip)).

~~A final phase (§13) then cuts role proof state from ~2400 to ~400 bits…~~
**Struck 2026-09-04:** the C6 effort achieved a larger reduction by other means, so
§13.1's numbers no longer describe the tree and §13.2 is unsound as written. What
remains of §13 is a correctness task (align selector ownership), not a state task —
see [§15.2](#152-131s-state-budget-is-obsolete-by-roughly-two-orders-of-magnitude)
and [§15.3](#153-132-is-refuted-on-soundness--this-is-the-important-one).

Every construct below was compiled and, where semantics matter, *verified* with
Questa Static Formal 2023.2 before being proposed — see [§8](#8-tool-evidence).

---

## 1. Files that can simply disappear

### Tier 1 — dead **today**, no design change, zero risk

| File | Lines | Evidence |
|---|---|---|
| `tb/axi_include.svh` | 23 | `AXI_CMD_STRUCT` has **zero** references repo-wide; in no flist |
| `axi_sva/yosys_questa_formal_wrapper.sv` | 199 | in no flist; referenced only from commented-out blocks |
| commented-out arm/yosys/zipcpu blocks in `m_sva_wrap.sv` + `s_sva_wrap.sv` | 74 | 37 comment lines in each, all disabled |

**222 lines, 2 files — delete now.** Git preserves them if a third-party
comparison is ever revived.

*Not* recommended for deletion: the vendored `axi_sva/{arm,yosys,zipcpu}` trees
(122 files). They are third-party reference material, not dead code — but they are
in no flist, so consider relocating them under `docs/` or `third_party/` so
`axi_sva/` contains only what actually compiles.

### Tier 2 — deleted by the refactor (content folded into a generic module)

| File | Lines | Absorbed into |
|---|---|---|
| `axi_switch_fvip.svh` | 24 | gone with the `MASTER`/`SLAVE` scheme (§4) |
| `s_sva_wrap.sv` | 96 | merged wrapper (§4) |
| `fifo_tracker.sv` | 96 | `fv_smart_tracker` (§3) |
| `xbar_stream_tracker.sv` | 101 | `fv_smart_tracker` (§3) |
| `axi_read_tracker.sv` | 116 | `fv_smart_tracker` + 2 AXI asserts |
| `axi_write_tracker.sv` | 136 | `fv_smart_tracker` + 2 AXI asserts |
| `axi_pair_tracker.sv` | 203 | `fv_skew_tracker` + WSTRB asserts |
| ~~`axi_fvip_txn_view_if.sv`~~ | — | **KEEP** — now 85% *consumed* by role code (§15.4) |
| `axi_transaction_fvip.sv` | 110 | thin connector; ~30 lines into `axi_fvip.sv` |
| `axi_fifo_role_fvip.sv` | 48 | 5 instantiations → `axi_fifo_fvip.sv` |
| `axi_xbar_role_fvip.sv` | 339 | → `axi_xbar_fvip.sv` |
| `xbar_read_tracker.sv` | 393 | generic tracker instances |
| `xbar_write_tracker.sv` | 689 | generic tracker instances |

**12 more files gone** (the view interface is retained — §15.4).

### Tier 3 — `axi_fvip_env_contract.sv` (316): a judgement call

`axi_fvip_env_contract.sv` (production, 316) and
`fvip_validation/reference_models/axi_transaction_oracle.sv` (validation, 251) are
**the same exact-bounded-queue AXI model**, differing mainly in `assume` vs
`assert`. Both implement the same `join_write` AW/W join, the same oldest-matching-ID
search, the same shift/count plumbing, and the same `wstrb_valid` genvar loop:

| Idiom | env_contract | oracle |
|---|---|---|
| `join_write` | 20 | 22 |
| `r_match` / `b_match` | 19 | 12 |
| queue-shift `for` loops | 5 | (inlined) |
| `case ({…})` counters | 6 | 4 |

Property-for-property, `a_r_has_ar`/`a_rlast_exact`/`a_wlast_exact`/`a_wstrb`
mirror `x_r_has_ar`/`x_r_last_exact`/`x_w_last_exact`/`x_wstrb`.

**Recommendation:** extract the *queue mechanics* into one generic
`fv_axi_exact_model #(..., parameter bit ASSERT_NOT_ASSUME)` (~150 lines) and keep
the **property lists written out at each use site** — production inside
`axi_fvip.sv`'s generate block, validation inside the oracle harness. The file
`axi_fvip_env_contract.sv` disappears; 567 lines → ~330.

**Why not merge them completely:** the mutation suite's value rests on the oracle
being an *independent* implementation of bounded AXI. A fully shared model creates a
common-mode failure — a bug would be simultaneously assumed as an environment
constraint *and* invisible to the oracle checking it. Sharing only the shift
registers and counters preserves independence where it matters (the properties) and
removes it where it does not. The smart tracker stays fully independent of both,
so the abstraction-vs-oracle comparison the suite is built on is unaffected.

Worth noting: this file is also the one place where the production model
contradicts the stated architecture — `docs/README.md` claims the deployable
checkers "contain no array indexed by outstanding transactions", but
`axi_fvip_env_contract.sv` is 316 lines of exactly that. Either the doc or the
file should change; extracting the shared model is a good moment to reword the doc.

---

## 2. Which paper techniques we actually use

From `docs/industrial_formal.pdf` (Darbari & Singleton):

| Technique | §  | Used? | Where |
|---|---|---|---|
| **Smart Tracker — single-transaction abstraction** | 4.4 | **Yes, 7× hand-written** | every tracker |
| **Symbolic observation windows** (`anyconst` watch_id / watch_beat) | 4.2 | **Yes, ~10× hand-written** | trackers, pair, xbar |
| **Scenario splitting** | 6.1 | **Yes** | protocol/full levels; read vs write; per-destination |
| **Two-transaction abstraction** | 4.1 | **No — deliberately rejected** | `docs/plan.md`: "counter-free two-value ordering is not complete for repeated payloads" |
| Invariants beyond abstraction | 4.5 | Partly | scalar occupancy counters |

So there is **one** core technique (smart tracker + symbolic window), reimplemented
from scratch seven times. That is the single largest source of bulk. The fix is
exactly the one you proposed: make each technique a **generic module** and
*instantiate* it, passing an SV **type** as the parameter.

---

## 3. The three generic technique modules

Replace all seven hand-written trackers with three parameterized modules in one
`axi_fvip_trackers.sv`:

```systemverilog
// 1. Smart tracker: select one arbitrary occurrence, prove order + payload,
//    plus scalar occupancy for phantom/overflow.  Payload is a TYPE, not a width.
module fv_smart_tracker #(
  parameter type payload_t        = logic,   // <- ax_aw_chan_t, ax_r_chan_t, ...
  parameter int  CAPACITY         = 4,
  parameter bit  ALLOW_BYPASS     = 1'b0,
  parameter bit  ASSERT_ON_OUTPUT = 1'b1,    // 1 = assert (DUT), 0 = assume (env)
  parameter bit  ENABLE_PROGRESS  = 1'b0,
  parameter int  MAX_DELAY        = 32
) (clk, rstn, s_hsk, s_data, m_hsk, m_data,
   o_selected, o_pending, o_completed, o_rank, o_occupancy, o_watched);

// 2. Burst variant: adds the (* anyconst *) watch_beat symbolic window and
//    beat sampling.  Replaces 4 hand-written copies of
//    "sample where current_beat == watch_beat".
module fv_smart_burst_tracker #(parameter type beat_t = logic, ...);

// 3. Two-sided signed-skew tracker (AW/W association, either arrival order).
//    Replaces axi_pair_tracker + 3 copies inside xbar_write_tracker.
module fv_skew_tracker #(parameter int MAX_A_AHEAD, MAX_B_AHEAD, ...);
```

Direct replacements:

| Hand-written today | Lines | Becomes |
|---|---|---|
| `fifo_tracker.sv` | 96 | `fv_smart_tracker` instance |
| `xbar_stream_tracker.sv` | 101 | `fv_smart_tracker` instance |
| `axi_read_tracker.sv` AR→R rank | 116 | instance + 3 AXI-specific asserts |
| `axi_write_tracker.sv` AW→B rank | 136 | instance + 2 asserts |
| `axi_pair_tracker.sv` skew | 203 | `fv_skew_tracker` + WSTRB asserts |
| `xbar_read_tracker.sv` (3 ranks inside) | 393 | 3 instances (~120 lines) |
| `xbar_write_tracker.sv` (5+ ranks inside) | 689 | 5 instances (~180 lines) |

> **`fifo_tracker.sv` and `xbar_stream_tracker.sv` share one core.** (Byte-equivalent
> on 2026-09-02; the xbar copy has since gained an offer-level layer — see §15.4b.)
> Normalized diff shows only comments, default values, and block names differ; the
> xbar version is strictly more general (its `a_selected_integrity` merges the
> FIFO version's two asserts). One of the two is pure duplication today.

**Why a type parameter and not `WIDTH`:** the current `logic [WIDTH-1:0]` ports are
what force every caller to hand-flatten channels and then hand-slice them back with
magic-number widths. Passing `ax_aw_chan_t` deletes both sides of that.

---

## 4. Delete the `MASTER`/`SLAVE` textual-duplication scheme

`axi_switch_fvip.svh` defines `MODNAME_*` + `TXN_SOURCE`/`TXN_DEST`, and
`axi_fvip.sv` is `` `include ``d **twice** (once with `` `define MASTER ``) from
`m_sva_wrap.sv` / `s_sva_wrap.sv`. That compiles 886 lines of tracker source as two
textually distinct module families.

`axi_channel_fvip.sv` already shows the right idiom — `parameter bit MANAGER_IS_ENV`
plus `` `M_RULE ``/`` `S_RULE `` macros. Apply it to the trackers too:

- delete `axi_switch_fvip.svh` (24 lines) and all `MODNAME_*` macros;
- `` `ifdef MASTER `` in `axi_pair_tracker.sv:71-76` and `axi_fvip.sv:43-47`
  → `if (MANAGER_IS_ENV)` generate;
- merge `m_sva_wrap.sv` + `s_sva_wrap.sv` (96 + 96, differing only in comments and
  the `m_`/`s_` prefix) into one `axi_fvip_wrap.sv` (~70).
- drop the misleading `TXN_SOURCE`/`TXN_DEST` names — one polarity idiom repo-wide.

**Saves ~150 lines and one full compile of the tracker set.**

---

## 5. Reuse PULP `axi_pkg` much harder

| Currently hand-written | Replace with | Saves |
|---|---|---|
| `IN_AW_W = ID_W+ADDR_W+35+USER_W` and 4 siblings, copied into **4 files** | `axi_pkg::aw_width()` … `r_width()` — **verified bit-exact, see T9** | ~37 lines + all `-:` slicing |
| `pkg_axi_fvip::burst_e/resp_e/lock_e/cache_e` | `axi_pkg::BURST_*`, `RESP_*`, `len_t/size_t/burst_t/...` | ~40 lines |
| `decode()` copied in **3 files** + 5 params (`ADDR0_BASE`, `ADDR1_BASE`, `ADDR_MASK`, `DEFAULT_ENABLE`, `DEFAULT_DEST`) | `axi_pkg::xbar_rule_32_t [N-1:0] ADDR_MAP` + one N-way loop (or `addr_decode`) | ~60 lines, **and generalizes to NxM** |

Dead code found: `lock_e` and the 20-line `cache_e` enum have **zero** uses outside
the package; `burst_e`/`resp_e` are never used as *types*, only their constants —
which `axi_pkg` already provides. `pkg_axi_fvip.sv` shrinks 118 → ~55.

> **Keep `wstrb_valid()` local.** `axi_pkg::beat_upper_byte` has the documented
> unaligned-FIXED bug (`pkg_axi_fvip.sv:55-58`). Reuse `axi_pkg::aligned_addr`,
> `num_bytes`, `wrap_boundary` for the correct parts only.

---

## 6. Delete the public view interface entirely

> **⚠ WITHDRAWN 2026-09-04.** 41 of 48 selected-transaction fields are now consumed
> by role code; the C6 effort adopted this interface as the vehicle for §13.4. Keep
> the view. §6a (struct-grouping) and §6e (config struct) still apply — see §15.4.

**6a. 85% of the view is consumed by nobody.** `axi_fvip_txn_view_if.sv` exports
~40 selected-transaction fields (`rd_*`, `wr_*`, `pair_*`). A repo-wide search for
every one of them, outside the interface and its producer, returns **zero hits**.
What the roles actually read is only the live AXI bus:

| Consumer | Reads | Reads any `rd_*`/`wr_*`/`pair_*`? |
|---|---|---|
| `axi_fifo_role_fvip.sv` | `req` / `rsp` only | **no** |
| `axi_xbar_role_fvip.sv` | `live_*` only | **no** |

So the interface currently carries **two redundant copies of the same live bus**
(`req`/`rsp` structs for the FIFO, `live_*` flat vectors for the xbar) plus 40
dead fields.

**6b. Why the tracker half was never used — and can't easily be.** The intent
(`docs/plan.md` §3) was for roles to reuse endpoint tracker state instead of
rebuilding it. That does not work for a routing proof: the endpoint tracker at
input *i* and the one at output *j* each pick an occurrence with an **independent
`anyseq` selector**. Proving routing needs *the same* transaction at both ends,
which would require assuming the output selector picks the matching one — a
selector-dependent *assumption*, exactly what the repo's own soundness rule
forbids ("the environment could avoid selecting a bad occurrence"). Both roles
therefore build their own paired trackers, and the view's tracker half is dead by
construction, not by oversight. **Do not try to revive it.**

**6c. What replaces it: the `AXI_BUS.Monitor` ports the role already has.** Once
the dead fields go, what remains is just "the live AXI bus" — which the aggregate
already holds. Roles take `AXI_BUS.Monitor` directly and assemble channel records
locally in one `always_comb`, then feed the §3 generic tracker:

```systemverilog
module fv_fifo_role (input logic clk, input logic rstn,
                     AXI_BUS.Monitor s_axi, AXI_BUS.Monitor m_axi);
  `AXI_TYPEDEF_ALL_CT(f, req_t, rsp_t, addr_t, id_t, data_t, strb_t, user_t)
  f_aw_chan_t s_aw, m_aw;  /* ... one always_comb assembles all five ... */
  fv_smart_tracker #(.payload_t(f_aw_chan_t), .CAPACITY(DEPTH)) i_aw (...);
```

**Verified (T10):** compiles clean in the formal frontend, 6 asserts / 4 assumes /
4 covers elaborated. This also removes the `live_*` flat vectors, the magic-width
slicing, and the whole aliasing question in §8/T6-T7 — there is no longer a modport
hop to worry about.

**Line impact** (supersedes the earlier struct-grouping idea):

| Removed | Lines |
|---|---|
| `axi_fvip_txn_view_if.sv` deleted | 150 |
| `axi_fvip.sv`: view copy `always_comb` (170-208) | 39 |
| `axi_fvip.sv`: view sampling `always_ff` (210-268) | 59 |
| `axi_fvip.sv`: `g_no_txn` zeroing branch (269-312) | 44 |
| `axi_fvip.sv`: `live_*` assigns + `AXI_SET_TO_REQ` (54-88) | 31 |
| `axi_fvip.sv`: `rd_watch_beat` anyconst + 2 assumes | 12 |
| `axi_xbar_role_fvip.sv`: flatten + magic widths (218-283) | 54 |
| view instantiations in both aggregates + 2 wrappers | ~60 |
| **Total** | **~450** |

`axi_fvip.sv` goes 321 → ~140.

**6d. Should roles use hierarchical dot notation into endpoint internals instead?**
**No.** Two different things are being conflated:

- **Downward refs inside one module** — `axi_fvip.sv` already does
  `u_txn.i_rd_tracker.select_now`. That is fine, conventional, and should stay: it
  avoids port-plumbing a child's internals to its own parent.
- **Upward / sibling refs from a role into a different checker's guts** —
  `i_s_endpoint.u_txn.i_rd_tracker.rank`. Avoid, for four concrete reasons:
  1. §3 replaces every tracker with a generic module, so **every internal name
     changes**. A port/modport boundary is exactly what decouples that refactor
     from role code; hierarchical refs would re-couple it.
  2. Generate-block labels get baked into paths (`g_txn.u_txn…`). T8 confirmed
     labels do appear in elaborated names.
  3. For N×M (§7) the path becomes `g_slv[i].i_ep.…` — an instance-array reference,
     which is precisely the construct Questa already misbinds here (the
     `AXI_XBAR_SCALAR_ENDPOINTS` workaround in `tb_xbar.sv` exists for that).
  4. Hierarchical refs are **not type-checked**. A path that is wrong but valid
     silently yields a wrong proof. In a sign-off model that is the worst failure
     mode available.

  Passing `AXI_BUS.Monitor` gives the same dot-notation ergonomics through a
  declared, type-checked port.

**6e. Config struct.** The same ~14 profile parameters are re-declared and
re-forwarded at **19 sites**. One `axi_fvip_cfg_t` packed struct in the package
makes each site one line, and turns the xbar's four ~20-line endpoint
instantiations into a `for` loop. `axi_xbar_fvip.sv` 182 → ~60;
`axi_fifo_fvip.sv` 96 → ~45.

---

## 7. Generalize the crossbar from hard-coded 2×2 to N×M

This removes duplication **and** unblocks C7 (3×3, 6×6), which is currently blocked
by hard-coded `[2]` arrays and `logic [1:0]` destinations.

Measured duplication in `xbar_write_tracker.sv`: the `select_route0` and
`select_route1` bodies are **byte-identical** apart from the index, and the
`route_pending` branch is a **third copy** of the same body — 3 × ~36 lines that
collapse to one indexed block:

```systemverilog
wire [DEST_W-1:0] attach_dest = select_now ? s_route : selected_dest;
wire attach_now = attach_direct || attach_delayed;
if (attach_now) begin ... m_w_ahead[attach_dest] ... end   // written ONCE
```

The same 3-copy pattern is in `xbar_read_tracker.sv:282-357`. Note these files
*already* use `for (int d = 0; d < 2; d++)` loops elsewhere — only the attach paths
were copy-pasted.

With `N_SLV`/`N_MST` parameters + the rule-array decode from §5, the 2×2 role
becomes an N×M role at no extra cost: **1704 → ~600 lines**.

---

## 8. Tool evidence

All snippets are in the session scratchpad; each was run under `nix-shell` with the
Questa license environment.

| # | Construct under test | Command | Result |
|---|---|---|---|
| T1/T2 | `parameter type payload_t`; struct payload ports; `cfg_t` struct parameter; `axi_pkg::*_width()` in `localparam`; `xbar_rule_32_t` array parameter; N-way decode fn | `formal compile` | **clean** — 3 asserts / 2 assumes / 2 covers elaborated |
| T3/T4 | struct-grouped view interface; 5-name modports; `view.rd <= '0`; **array of view interfaces driven by a generate loop**; cross-element cover | `formal compile` | **clean** — 2 assert *directives* → 4 *checkers*, i.e. both array elements bound correctly |
| T5 | dest-indexed attach body (§7) generalized to `N_DEST` | `formal compile` | **clean** |
| T6 | packed struct across a modport, driven by one `always_comb` | `formal verify` | `a_id_proven` **PROVEN**; `a_addr_free`, `a_valid_free` **FIRED** → no aliasing, and test is non-vacuous |
| T7 | same, driven by many per-field continuous assigns (`` `AXI_SET_TO_REQ `` style) | `formal verify` | **same correct result** → aliasing not reproduced in either style |
| T8 | **end-to-end**: one generic type-parameterized `fv_smart_tracker` proving a real struct-payload FIFO | `formal verify` | golden: **3/3 asserts proven, 2/2 covers covered**; with a seeded drop: **fires** (`a_no_overflow`) |
| T9 | `axi_pkg::*_width()` vs `$bits(chan_t)` vs the repo's magic constants | elaboration `$error` checks | **all five channels agree exactly** — AW 72/72/72, W 38/38/38, B 7/7/7, AR 66/66/66, R 40/40/40 |
| T10 | role checker with **no view interface** — `AXI_BUS.Monitor` ports, channel structs assembled locally, fed to the generic tracker | `formal compile` | **clean** — 6 asserts / 4 assumes / 4 covers elaborated |

Two gotchas found while testing, already folded into the plan:

1. `wire int unsigned x = f();` is rejected — *"Net data types must be 4-state."*
   Use a sized `logic` vector for decode outputs.
2. Moving polarity into generate blocks **changes hierarchical property paths**
   (`i_trk.g_a_a_no_overflow.a_no_overflow`). This matches what `M_RULE`/`S_RULE`
   already does in `axi_channel_fvip.sv`, but `FORMAL_TARGETS`/`FORMAL_ASSUMES`
   patterns and `docs/c6_execution.md` reference names — keep a rename map.

---

## 9. Target file layout

```
axi_sva/our/
  axi_fvip_pkg.sv        wstrb_valid + geometry lets + cfg_t                  ~110
  axi_fvip_trackers.sv   fv_smart_tracker / _burst_ / fv_skew_tracker         ~330
  axi_exact_model.sv     shared bounded queue mechanics (env + oracle)        ~150
  axi_fvip.sv            channel rules + txn aggregate + env-contract
                         properties + endpoint top, one MANAGER_IS_ENV        ~140
axi_sva/
  axi_fvip_wrap.sv       merged m_/s_ wrapper                                  ~50
per_role_fvip/
  axi_fifo_fvip.sv       aggregate + role, AXI_BUS.Monitor ports              ~110
  axi_xbar_fvip.sv       aggregate + role + N×M read/write trackers           ~600
```

Interfaces used: `AXI_BUS.Monitor` only — no bespoke view interface anywhere.

20 files → **7**; 3894 lines → **~1640**. Separately: 2 dead files (222 lines)
gone immediately, and `fvip_validation/` loses ~150 lines by reusing
`axi_exact_model.sv`.

Files deleted outright: `axi_include.svh`, `yosys_questa_formal_wrapper.sv`,
`axi_switch_fvip.svh`, `s_sva_wrap.sv`, `fifo_tracker.sv`,
`xbar_stream_tracker.sv`, `axi_read_tracker.sv`, `axi_write_tracker.sv`,
`axi_pair_tracker.sv`, `axi_fvip_txn_view_if.sv`, `axi_transaction_fvip.sv`,
`axi_fvip_env_contract.sv`, `axi_fifo_role_fvip.sv`, `axi_xbar_role_fvip.sv`,
`xbar_read_tracker.sv`, `xbar_write_tracker.sv` — **16 files**.

---

## 10. Suggested order (each step independently provable)

0. **§1 Tier 1** delete the 2 dead files + commented-out blocks — no proof impact,
   do it first to shrink the review surface.
1. **§6a** delete the 40 unused view fields and the code that populates them
   (`axi_fvip.sv` copy block, sampling block, zeroing branch). Pure dead-code
   removal — **no role checker reads any of it**, so nothing downstream changes.
   Biggest ratio of lines-removed to risk in the whole plan; do it early.
2. **§5** `axi_pkg` reuse + trim `pkg_axi_fvip` — mechanical, T9-backed, zero risk.
3. **§4** kill `MASTER`/`SLAVE` duplication — pure refactor, no property changes.
4. **§3** introduce the three generic trackers; port `fifo_tracker` +
   `xbar_stream_tracker` first (they are already the same module), then the
   endpoint trackers.
5. **§6c** switch both roles to `AXI_BUS.Monitor` ports and delete
   `axi_fvip_txn_view_if.sv`. This also retires the `live_*` flat vectors and the
   aliasing question in one step (T10).
6. **§6e** config struct.
7. **§1 Tier 3** extract `axi_exact_model.sv`; delete `axi_fvip_env_contract.sv`.
   Re-run the transaction mutation suite **before and after** and require an
   identical score — that is the specific guard against the common-mode risk.
8. **§7** N×M crossbar — biggest win, do it last on the largest file.
9. **§13** reuse the endpoint trackers (state reduction) — **only after C6 has
   closed**. The only phase that changes proof structure; gate it on mutation
   scores, not compiles, and claim no closure benefit (§13.0).

## 11. Validation gate (non-negotiable)

The FVIP is sign-off evidence, so after each step re-run and require **identical**
results:

- `fvip_validation/tools/run_link_mutations.sh`, `run_fifo_mutations.sh`,
  `run_transaction_mutations.sh` — mutation scores must match exactly;
- `make qverify ROLE=fifo VENDOR=zipcpu LEVEL={protocol,full}`;
- `make qverify ROLE=xbar VENDOR=zipcpu IMPL=axixbar LEVEL={protocol,full}` at
  outstanding depths 1, 2, 4;
- no new inconclusive, vacuous, or uncoverable results;
- record the property rename map (gotcha 2 above) alongside `docs/c6_execution.md`.

---

## 12. Second-pass sweep: everything outside `axi_sva/` + `per_role_fvip/`

Sections 1-11 cover the checkers. This pass swept the validation harness, tooling,
build flow, docs, and repo hygiene.

### 12.1 Dead state — ✅ DONE 2026-09-04

`selected_len` in **both** `xbar_read_tracker.sv` and `xbar_write_tracker.sv` is
declared, reset, assigned on select, and **never read**:

```
xbar_write_tracker.sv:155  logic [7:0] selected_len;
xbar_write_tracker.sv:300      selected_len <= '0;
xbar_write_tracker.sv:472        selected_len <= s_req.aw.len;   <- no reader
```

At 2 sources × 2 trackers that is 4 × 8 = 32 bits of write-only state. A systematic
write-only-register sweep over every FVIP and oracle source found **only** these
two, so the rest of the code is clean at signal level.

**Expect no proof benefit.** An earlier draft called this "a proof-performance fix,
not tidiness" — that was wrong on two counts: cone-of-influence reduction almost
certainly prunes a write-only register before the solver ever sees it, and §13.0
records that far larger state reductions did not improve C6 closure. Delete it
because dead state is misleading to read, not because it will help a proof.

### 12.2 Validation testbenches: ~135 lines of manual bus assignment

| File | Issue | After |
|---|---|---|
| `tb_link_mutation.sv` (149) | two `always_comb` blocks of **47 lines each**, setting all ~40 AXI_BUS signals, differing in ~4 lines | ~55 |
| `tb_transaction_mutation.sv` (269) | 47-line copy block + 17 scalar declarations + 23-line default block, all to drive one bus | ~180 |

PULP already ships `` `AXI_SET_FROM_REQ ``/`` `AXI_SET_FROM_RESP `` (procedural,
usable inside `always_comb`). Drive a `req_t`/`rsp_t` struct, zero it with `'0`, set
only the few interesting fields, then one macro per direction. `tb_fifo_mutation.sv`
(80) is already compact — leave it.

### 12.3 Reset contract written twice

The 6-property reset contract (`rstn_at_posedge`, `rstn_released`, two `@(negedge)`
assumes, `$past` assume, `always_comb assume`) appears in **both**
`axi_fvip.sv:96-110` and `tb_transaction_mutation.sv:48-49,104-109`. One
`fv_reset_contract` module instantiated in both. ~15 lines, and it removes a place
where the two can silently disagree about what reset means.

### 12.4 Three mutation runners, one skeleton

`run_{link,fifo,transaction}_mutations.sh` (27 + 52 + 62 = 141) share ~65% of their
structure: license bootstrap, output directory, per-mutation loop, report parse, CSV
score. One `run_mutations.sh <suite>` plus a per-suite config block (names array,
expected-property array, flist, do-file, top) → ~70 lines.

### 12.5 Build flow: every knob declared three times

Each profile parameter is plumbed through **three layers** — `Makefile` (`?=` default
+ export), `tools/run_formal.sh` (`:-` default + forward), `qverify/run_formal.do`
(env → `-G`) — about 24 declaration sites for 8 knobs. Worse, `run_formal.do` has
**per-role `if` blocks** whose `-G` lines are near-identical, so adding a role means
editing the Tcl.

Since every line is mechanically `AXI_<VAR>=$::env(<VAR>)`, export one list instead:

```tcl
foreach v [split $::env(FORMAL_PARAMS) ","] {
  lappend compile_args -G "AXI_$v=$::env($v)"
}
```

`run_formal.do` 22 lines → ~5, and becomes role-agnostic.

**This has already drifted:** `Makefile:146` sets `MAX_OUTSTANDING ?= 1`, while
`docs/plan.md:40` states the default MVP configuration is `MAX_OUTSTANDING=4`.
Two sources of truth, currently disagreeing.

### 12.6 Docs: `progress.md` restates every other document

`docs/progress.md` is 903 lines and shares 55-74% of its distinctive tokens with each
of the other six docs — it inlines the architecture (README), the profile
(axi4_mvp_profile), the run recipes (formal_runs), and the C0-C5 and C6 results:

| Doc | tokens also in progress.md |
|---|---|
| `c0_c5_execution.md` | 74% |
| `axi4_mvp_profile.md` | 71% |
| `formal_runs.md` | 69% |
| `README.md` | 65% |
| `c6_execution.md` | 59% |
| `plan.md` | 55% |

It has already rotted: lines 422 and 478 describe `tb/fifo_response_env.sv` as the
current bounded FIFO environment, while line 114 records the decision to remove it —
**and the file no longer exists**.

Suggestion: reduce `progress.md` to a dated changelog plus links, and let each topic
live in exactly one document. ~450 lines. Note `docs/README.md`'s file map lists
**10 of the 16 files** this plan deletes, so it needs rewriting either way.

### 12.7 White-box coupling the refactor must update in lockstep

This qualifies §6d. A *validation* harness legitimately reaches into internals — it is
white-box by design, unlike a role checker. But that means §3/§4 break it, and the
breakage is concrete:

| Coupling | Where | Count |
|---|---|---|
| `i_txn.i_rd_tracker.*` / `i_wr_b_tracker.*` hierarchical refs | `tb_transaction_mutation.sv:249-264` | 8 |
| `m_`/`s_axi_transaction_fvip` module names from the `MASTER`/`SLAVE` scheme | `tb_transaction_mutation.sv:230-243` | 2 |
| hardcoded property names in scoring greps (`x_r_has_ar`, `x_w_last_exact`, `x_wstrb`, `i_tracker.`, `g_source\|g_response`, …) | `fvip_validation/tools/*.sh` | ~15 |

These 25 sites **are** the rename map referenced in §11. Update them in the same
commit as the module they track, and re-run the suite before and after.

### 12.8 Repo hygiene — already fine

Generated artefacts (`modelsim.ini`, `work/`, `*.log`, `*.vstf`, `.qverify/`,
`axi4*.txt`) are correctly gitignored and untracked; nothing tool-generated is
committed. `tools/` has no orphans — `inspect_vcd.py` and `run_fifo_matrix.sh` are
both referenced. No unused module parameters anywhere. Two loose untracked files in
the root (`hdlserver.vstf`, `qverify_cmds.tcl`) are worth ignoring or deleting.

### 12.9 Second-pass total

| Item | Lines |
|---|---|
| 12.2 validation testbenches | ~95 |
| 12.4 mutation runners | ~70 |
| 12.5 build flow | ~20 |
| 12.6 docs | ~450 |
| 12.1 / 12.3 dead state + reset contract | ~20 |
| **Total** | **~655** |

None of these is expected to change proof results, 12.1 included (§12.1, §13.0).
They are readability and single-source-of-truth wins.

---

## 13. Final phase — reuse the endpoint trackers (state reduction)

**Do this last, and only after C6 has closed.** It depends on §3 (generic trackers),
§6 (view deleted) and §7 (N×M crossbar), and it is the only part of the plan that
redesigns proof structure rather than moving code. Everything above preserves the
proof argument exactly; this section changes *how much state the solver carries*, so
it needs the mutation suites as a gate, not just a compile.

> ### ⚠ Correction — the closure justification for this section is withdrawn
>
> An earlier draft argued that cutting role state would help close the C6
> inconclusives. **A parallel C6 closure effort has since tested that hypothesis
> directly, and it did not hold.** See [§13.0](#130-what-the-c6-effort-already-tried).
> Do this section for **readability and architectural consistency** — which was
> always the plan's thesis — and treat any closure benefit as an open question to be
> *measured*, not a reason to do the work.

### 13.0 What the C6 effort already tried

Recorded so the same experiments are not repeated:

| Experiment | Intent | Result |
|---|---|---|
| Trimmed **79 irrelevant tracker assumptions** from the cone | remove monitor state from the property's cone | still timed out |
| `MAX_OUTSTANDING==1` specialization of the endpoint write tracker | eliminate the quantified-ID cone | induction radius **52 vs 60 — worse**; reverted |
| Output write-capacity partition | isolate a cheaper obligation | clean but unresolved, radius 43 |

Conclusion reached there: the bottleneck is **the implementation's internal
arbitration/accounting state** (the ZIPCPU `axixbar` core's own registers), which
nothing in this plan touches.

Two further reasons not to expect a closure win here:

- The blocked properties are the **arbitrary-ID read-response** obligation and an
  **output write-capacity** partition. The ~1870-bit saving in §13.2 is in
  `xbar_write_tracker`'s W-ahead queues, which are **not in those properties' cones**.
  The saving and the blockage are in different places.
- Reducing symbolic-variable count (§13.3) is a smaller version of the
  `MAX_OUTSTANDING==1` experiment that already made the radius worse.

If closure is later shown to be limited by *checker* state rather than DUT state,
this section becomes the right intervention. Today's evidence points the other way.

### 13.1 Where the state actually is

> **⚠ OBSOLETE 2026-09-04.** The queues now hold one symbolic payload bit, not a
> payload, and the depth formula changed; they are ~8 bits, not 1872. See §15.2.

Measured from the current sources (`DATA_W=32`, `USER_W=1`, `IN_ID_W=4`,
`MAX_W_AHEAD=4`; canonical widths `W_CANON=38`, `AW_CANON=72`, `AR_CANON=66`):

| State | `MAX_OUTSTANDING=1` | `MAX_OUTSTANDING=4` |
|---|---|---|
| `xbar_write_tracker` W-payload queues × 2 source ports | **1872 bits** | **2808 bits** |
| 8 route-tracker captured payloads | 552 | 552 |
| `selected_len` dead state (§12.1) | 32 | 32 |
| Endpoint `axi_pair_tracker`, *solving the same W-before-AW problem* | **~90** | **~90** |

Plus roughly **60 independent symbolic free variables** (`anyconst`/`anyseq`) in the
C6 full proof — 32 from the four endpoints, 28 from the two source roles. Folklore
says free-variable count matters more than bit count for solver cost; §13.0 is a
counterexample, so treat both columns as a map of *where the duplication is*, not as
a predictor of proof time.

So `selected_len` is noise. The target is
[`xbar_write_tracker.sv:170-181`](per_role_fvip/xbar/xbar_write_tracker.sv):

```systemverilog
logic s_w_ahead_sampled [WQ_DEPTH];
logic [W_CANON_W-1:0] s_w_ahead_data [WQ_DEPTH];
logic m_w_ahead_sampled [2][MST_WQ_DEPTH];
logic [W_CANON_W-1:0] m_w_ahead_data [2][MST_WQ_DEPTH];   // MST_WQ_DEPTH = 2*(MAX_OUTSTANDING+MAX_W_AHEAD)
```

### 13.2 Reuse the *technique* — the largest single simplification

> **⚠ REFUTED 2026-09-04.** "Rank/skew alone cannot recover an earlier payload if
> the pair choices are not aligned, so removing the queues before this selector
> ownership change would be unsound." Align selector ownership first. See §15.3.

Those queues exist for one reason: a W burst can arrive before its AW, so the
tracker buffers the sampled beat of every unmatched burst up to the skew bound.

`axi_pair_tracker.sv` already solves exactly this in **constant** state using the
two-sided selector — `select_aw` (requires `skew >= 0`) or `select_w` (requires
`skew <= 0`), then rank down the opposite side. Every (AW, W-burst) pair is
reachable by one of the two selectors, so the argument stays universal while
storing **one** burst summary instead of a queue.

Applied at the crossbar: one selector at the input, the output-side burst located by
route rank, and output-side skew handled the same way per destination.

**~1870 → ~250 bits.** It also removes the one place where production contradicts
the stated architecture (`docs/README.md`: "no array indexed by outstanding
transactions") — see §1 Tier 3, which makes the same point about
`axi_fvip_env_contract.sv`.

### 13.3 Collapse needlessly-independent symbolic variables — ✅ DONE 2026-09-04

One source port currently declares **six** independent `watch_id` anyconsts: four in
the `XBAR_ROUTE_TRACKERS` macro (2 destinations × AW/AR) plus one each in
`xbar_read_tracker` and `xbar_write_tracker`. One per direction suffices — every
property remains universally quantified over that ID, so no coverage is lost. The
same applies to `watch_beat`, which the read tracker, the write tracker and the
endpoint each declare separately.

Removes ~8 free variables across the 2×2, and scales with N in §7.

### 13.4 Reuse the endpoint tracker *instances* — ✅ DONE 2026-09-04 (input side only)

- **Input side: yes.** The input endpoint's write tracker already selects an AW,
  captures its payload, and maintains `outstanding`/`b_rank` over the same ID domain
  on the same wires. The role's `s_outstanding`, `s_b_rank`, `s_rsp_rank`,
  `s_rsp_beat` and its captured payload are exact duplicates. The destination is a
  pure function of the captured address — no new state at all.
- **Output side: no.** The output endpoint's selector is independently free. Slaving
  it to the input's selection means constraining a signal on the DUT-observed path —
  precisely the unsoundness recorded in `fvip_validation/README.md` ("the
  environment could avoid selecting a bad occurrence"). The output side must stay
  **rank-derived**, which is what `route_count`/`route_rank` already does. That is
  cheap and correct; keep it.

**The minimal sound shape:** one free selector per (source, direction), owned by the
input endpoint; everything downstream derived by small rank counters.

### 13.5 Wiring — without reintroducing a view interface

Move tracker instantiation up into the aggregate. `fv_smart_tracker` (§3) already
exposes `o_selected / o_pending / o_completed / o_rank / o_occupancy / o_watched`.
The aggregate instantiates it once per (endpoint, direction) and feeds **both** the
endpoint protocol properties and — under `if (ENABLE_ROLE)` — the role properties.
Ordinary type-checked module ports; no interface, no hierarchical references, and
`LEVEL=protocol` still elaborates the trackers with no role instance.

> **This qualifies §6.** §6 deletes the view because *today* no role reads any of its
> 40 selected-transaction fields. That stays correct. But under 13.4 the role would
> consume about **ten** of them. The conclusion is unchanged and the reason sharpens:
> delete the 40-field interface, and re-expose the ~10 live values as **tracker
> output ports** — a quarter of the surface, already present in the generic tracker's
> port list.

### 13.6 What not to do

The tempting shortcut is to let the output endpoint keep its own selector and add
`assume (output_select_now |-> it_is_the_matching_transaction)`. That is unsound for
the reason above: it is a selector-dependent assumption on DUT-observed behaviour,
so the solver can discharge the proof by never selecting a faulty occurrence. If a
future change appears to need it, the answer is a rank counter, not an assumption.

### 13.7 Expected result and caveats

**What is reliably gained:** roughly **~2400 → ~400 bits** of role state, about
**12 fewer symbolic free variables**, `xbar_write_tracker.sv` down from 689 lines,
and the removal of the one construct in production that contradicts the stated
architecture (`docs/README.md`: "no array indexed by outstanding transactions").
Those are readability and consistency wins and they hold regardless of solver
behaviour.

**What is *not* claimed:** any improvement in C6 closure. The earlier draft asserted
this would "bear directly on the depth-1/2/4 inconclusives" — that was speculation,
and §13.0 records the experiments that point the other way. State reduction and
proof closure are related but not the same axis: a smaller monitor can even
*lengthen* an induction proof, which is exactly what the `MAX_OUTSTANDING==1`
experiment showed (radius 52 vs 60). Measure it (§14); do not assume it.

**Caveat, stated plainly:** 13.2 is a redesign of the hardest file in the repo. The
two-sided skew technique is proven at the endpoint, but the **cross-endpoint
composition is not** — that has not been verified here. Treat the transaction and
xbar mutation suites as the gate, expect to iterate on the output-side skew
handling, and do not merge this phase on a compile result alone.

**Sequencing caveat:** do not start this while a C6 closure effort is in flight. It
renames property paths and moves module boundaries, which breaks
`FORMAL_TARGETS`/`FORMAL_ASSUMES` cone-partition tooling keyed on the current names
(§12.7), and it destroys the ability to attribute any change in closure behaviour to
either the refactor or the closure work. Land closure first, record its numbers as
the baseline, then refactor against it.

### 13.8 Order within this phase

1. **§12.1** delete `selected_len` — trivial, independent, do it any time.
2. **§13.3** share `watch_id`/`watch_beat` per source — no structural change, should
   leave every property outcome identical. Good canary: if mutation scores move
   here, something is wrong before the hard part starts.
3. **§13.4/13.5** wire role properties to the input endpoint's tracker outputs;
   delete the role's duplicate s-side counters and payload capture.
4. **§13.2** replace the W-ahead payload queues with the two-sided skew tracker.
   Re-run the full C6 matrix at depths 1, 2 and 4 and compare against
   `docs/c6_execution.md` before and after.

---

## 14. Note on the validation gate for §13

§11 applies to every step. **§13 additionally requires**, because it is the only
phase that alters the proof argument rather than relocating it:

- record proof depth, wall time and peak memory **before and after** each of
  13.2-13.4. Note the direction of the test: this is not confirming an expected
  speedup, it is checking that the refactor has not made closure **worse**. §13.0
  documents a state reduction that lengthened the induction radius (52 vs 60), so
  regression is the realistic risk, not disappointment;
- the transaction and xbar mutation suites must score **identically**, not merely
  pass — a state reduction that silently weakens an obligation shows up as a
  mutation that stops being detected;
- re-check reachability covers explicitly. Removing state is the change most likely
  to make a cover unreachable or a property vacuous, and neither shows up as a
  fired assertion;
- the C6 closure result recorded in `docs/c6_execution.md` is the baseline. If it
  is not yet closed, §13 has no baseline and should not start.

### 14.1 Standing note on justifying work by proof performance

§12.1 and §13 both originally argued from expected solver benefit, and both claims
were withdrawn once the C6 effort's measurements came in (§13.0). The general
lesson, worth keeping: **state count and proof closure are different axes.** Bit
counts and free-variable counts are easy to measure statically and therefore
tempting to optimise, but induction depth is driven by how hard the *invariant* is
to establish, which can get worse when a monitor is made smaller or more abstract.

Justify everything in this plan by readability, single-source-of-truth, and
architectural consistency — all of which are directly observable. If a change also
helps a proof, treat that as a measured bonus, never as the argument for doing it.

---

## 15. Re-verification against the C6 effort (2026-09-04)

This plan was written on 2026-09-02 against a 3894-line snapshot. The parallel C6
closure effort has since changed the sources substantially — **3894 → 5514 lines
(+42%)** — and has independently implemented several things this plan proposed.
Every claim below was re-checked against the current tree.

**Read this section before acting on §1-§14.** Three of its recommendations are now
wrong, and one is refuted on soundness grounds.

### 15.1 Already done by the C6 effort — do not redo

| Plan item | Status |
|---|---|
| §12.1 delete `selected_len` | **done** — zero occurrences remain in either xbar tracker |
| §13.3 share the per-source symbolic variables | **done** — `watch_id`, `watch_beat`, `watch_route`, `source` are now module **input ports**, not per-instance `anyconst` |
| §13.4 role reuses the endpoint trackers' state | **done** — `fv_xbar_write_tracker` / `fv_axi_xbar_source_role` now take `s_protocol_*`, `s_pair_*`, `m_pair_*`, `m_protocol_*` as inputs instead of rebuilding them |
| §13.2's *goal* (shrink the W-ahead queues) | **superseded by a better abstraction** — see 15.2 |

The C6 record also documents two reductions this plan never proposed: a **452-bit
payload-bit reduction** and a separate **225-bit sequential reduction** (reusing
endpoint `channel_w_beat` counters in the role; one W-data age per input instead of
per-AW; one R and one B age per output instead of per-entry; polarity-gated age
elaboration). `docs/c6_execution.md` warns explicitly: *"Do not add the two numbers
when describing one refactor."*

### 15.2 §13.1's state budget is obsolete by roughly two orders of magnitude

The plan's headline "**1872-2808 bits** of W-payload queue" is dead. Two changes
landed:

- the queue entries are no longer payloads. `s_w_ahead_data` and `m_w_ahead_data`
  are now plain `logic` — **one symbolic payload bit**, not `[W_CANON_W-1:0]`;
- the depth formula changed from `MST_W_AHEAD = 2*(MAX_OUTSTANDING + MAX_W_AHEAD)`
  to `MST_W_AHEAD = MAX_OUTPUT_W_AHEAD`, and for this ZIPCPU wrapper the measured
  tight cap is `min(MAX_OUTSTANDING, 1 core AW stage + 1 AW skid)` = **1/2/2** at
  depths 1/2/4.

Those queues are now on the order of **8 bits**, not 1872. §13.1's table, and the
"~2400 → ~400 bits" figure in the header and §13.7, should be struck rather than
re-derived — the work they were arguing for has already happened by other means.

### 15.3 §13.2 is refuted on soundness — this is the important one

§13.2 proposed replacing the W-ahead queues with the endpoint's two-sided skew
tracker, and called it "no soundness question". The C6 record contradicts that
directly (`docs/c6_execution.md`, *Selected-packet architecture clarification*):

> Rank/skew alone cannot recover an earlier payload if the pair choices are not
> aligned, so **removing the queues before this selector ownership change would be
> unsound.**

The queues are not redundant bookkeeping. They exist because the input pair tracker
and the selected-output pair tracker choose their occurrences *independently*;
rank and skew describe accepted order, not which payload was captured. Removing them
is only sound **after** the input pair, the selected-output pair, and the role are
forced to share the same arbitrary beat index and the same AW-first/W-first case —
a precondition §13.2 did not state because I had not identified it.

§13.2 should be rewritten as "align selector ownership, *then* remove the queues,"
with the alignment as the substantive step and the deletion as its consequence.

### 15.4 §6 is inverted — the view is now load-bearing

§6's entire argument was that no role checker read any of the view's
selected-transaction fields. That was true on 2026-09-02. It is now false:

**41 of 48 selected-transaction fields are consumed by role code**, including the
whole `pair_*` group, `rd_watch_id`/`wr_watch_id`, and the new
`pair_w_payload_bit` / `pair_w_payload_idx` / `pair_w_payload_available` trio.

The C6 effort implemented §13.4 — and the vehicle it used was precisely the
interface §6 proposed deleting. The view has become the stable public API it was
designed to be. **Withdraw §6's deletion recommendation.** What survives from §6 is
narrower and still worth doing:

- §6a's struct-grouping of the field list (now *more* valuable at 48 fields across
  two duplicated modport lists, and it would shorten the ~120-line input port lists
  the role modules have grown);
- §6e's config struct;
- §6d's guidance on hierarchical references, unchanged.

`live_*`, the magic widths, and the `MASTER`/`SLAVE` scheme are all still present, so
§4, §5 and §6b remain valid as written.

### 15.4b §3's "the two trackers are the same module" has partly lapsed

`fifo_tracker.sv` (96) and `xbar_stream_tracker.sv` (146) were byte-equivalent on
2026-09-02. The xbar one has since gained the READY-independent offer-level layer:
`a_no_phantom_offer`, `a_selected_integrity_class0/1`, `a_tracker_pending_rank`, and
three stalled-offer covers. They still share the same core (`select_now`,
`rank`, `occupancy`, `a_no_overflow`, `a_no_phantom`, `c_select`).

§3 survives, but the generic tracker now needs an `ENABLE_OFFER_CHECKS` parameter
rather than being a straight substitution, and the §1 Tier 2 line "one of the two is
pure duplication today" should be softened to "shared core, divergent obligations".

### 15.5 Hard constraints any future refactor must respect

The C6 log records these as settled. They bound the design space for §3 and §13:

| Constraint | Source |
|---|---|
| Occurrence selectors **must stay handshake-based** — rank and skew describe *accepted* order. Broadening `select_aw` to `AWVALID` mixes an unaccepted offer into handshake-derived state and is unsound. | *AWREADY-independent output pair checks* |
| A **selector-based assumption** on Manager inputs is unsound — it can evade an unselected bad input packet. Manager inputs keep the unconditional deterministic contract. | *Arbitrary output-packet result* |
| A helper may be promoted to an assumption **only after its own standalone proof**; an unproved protocol assumption is unsound. | *Closed output write-capacity bounds* |
| **Unconditional progress is intentionally impossible** when the environment may withhold READY or a response forever. Keep safety unbounded and READY-independent; confine deadlines to the bounded-progress profile. | closing paragraph |

Rejected designs, recorded so they are not reinvented: the per-AW W-data timer, the
Subordinate per-entry eligible timers (two entries could reach deadlines together and
force mutually incompatible READY behaviour), and the sticky selector that replaced
them. The current design is a global queue-head scheduler with one age per channel
per output.

### 15.6 Revised recommendation

The §10 ordering still holds for §1, §3, §4, §5, §7 and §12 — those are all
line-count and single-source-of-truth work, untouched by the above.

What changes:

1. **Strike §13.1's numbers and §13.2's soundness claim**; fold what remains of §13
   into "align selector ownership" as a *correctness* task, not a state-reduction one.
2. **Withdraw §6's deletion**, keep §6a/§6e.
3. **Re-baseline before starting.** The plan's targets (3894 → ~1640, 20 → 7 files)
   were computed against the old tree. At 5514 lines the *proportional* argument is
   stronger — `xbar_write_tracker.sv` is now 846 lines and
   `axi_xbar_role_fvip.sv` 769 — but every absolute number in §1, §9 and §13 needs
   recomputing against the post-closure source.
4. **Still wait for closure.** §13.0's reasoning is unaffected and is now reinforced:
   the C6 effort's own state reductions (452 + 225 bits, far larger than anything
   here) did not close the remaining eleven protocol and five role obligations. The
   blocker is induction on the crossbar response path, not checker size.

### 15.7 What the C6 record says about feasibility

Worth quoting, because it bears on whether any of this is worth doing:

> This remaining work is not evidence that complete crossbar proof is impossible.
> The fixed bounded-capacity 2x2 safety model is finite-state; the current failures
> are **time-limited induction failures, not counterexamples.**

So the refactor is not rescuing a doomed proof, and it is not needed to rescue one.
It is maintainability work on a codebase that grew 42% under closure pressure — which
is a better argument for doing it than any of the proof-performance claims this plan
started with.
